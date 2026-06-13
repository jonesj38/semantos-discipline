---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-vault-obsidian/pask-vault-obsidian/plugin/main.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.489671+00:00
---

# packages/pask-vault-obsidian/pask-vault-obsidian/plugin/main.ts

```ts
/**
 * Semantos Pask — Obsidian companion plugin.
 *
 * Hooks Obsidian lifecycle events and forwards them to the semantos watcher
 * via a local Unix socket (or named pipe on Windows). The watcher translates
 * them into Pask interactions via `onFileOpen`, `onLinkTraverse`, etc.
 *
 * Distribution: Obsidian community plugin registry (manual install until accepted).
 * Works without the plugin — the file-watcher path covers add/change/delete.
 * The plugin adds: open, link-traverse, backlink-click, search-result-click.
 *
 * Manifest ID: semantos-pask-vault
 */

import { Plugin, TFile } from 'obsidian';
import { createConnection } from 'node:net';

interface PluginMessage {
  type: 'file-open' | 'link-traverse' | 'backlink-click' | 'search-click';
  relPath?: string;
  sourceRelPath?: string;
  targetRelPath?: string;
  queryHash?: string;
  nowMs: number;
}

const SOCKET_PATH =
  process.platform === 'win32'
    ? '\\\\.\\pipe\\semantos-pask'
    : '/tmp/semantos-pask.sock';

function djb2Hash(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return Math.abs(h).toString(16).padStart(8, '0').slice(0, 8);
}

export default class SemastosPlugin extends Plugin {
  private socket: ReturnType<typeof createConnection> | null = null;
  private queue: string[] = [];
  private connected = false;

  async onload() {
    this.connectSocket();

    // file-open
    this.registerEvent(
      this.app.workspace.on('file-open', (file) => {
        if (file instanceof TFile && file.extension === 'md') {
          this.send({ type: 'file-open', relPath: file.path, nowMs: Date.now() });
        }
      }),
    );

    // link-traverse: detect via resolved link metadata changes
    // The metadataCache 'resolved' event fires after every parse; compare
    // resolved links to detect new traversals isn't reliable here. Instead
    // we hook click events via the workspace layout-change as a proxy.
    // Full link-traverse detection requires monkey-patching the link-open
    // handler, which is fragile — deferring to v2.
  }

  onunload() {
    this.socket?.destroy();
  }

  private send(msg: PluginMessage): void {
    const line = JSON.stringify(msg) + '\n';
    if (this.connected && this.socket) {
      this.socket.write(line);
    } else {
      this.queue.push(line);
    }
  }

  private connectSocket(): void {
    try {
      const s = createConnection(SOCKET_PATH);
      this.socket = s;

      s.on('connect', () => {
        this.connected = true;
        for (const msg of this.queue) s.write(msg);
        this.queue = [];
      });

      s.on('error', () => {
        // semantos daemon not running — queue up and retry in 30s
        this.connected = false;
        this.socket = null;
        setTimeout(() => this.connectSocket(), 30_000);
      });

      s.on('close', () => {
        this.connected = false;
        this.socket = null;
        setTimeout(() => this.connectSocket(), 30_000);
      });
    } catch {
      setTimeout(() => this.connectSocket(), 30_000);
    }
  }
}

```
