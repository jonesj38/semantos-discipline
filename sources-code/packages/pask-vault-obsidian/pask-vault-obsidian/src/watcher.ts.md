---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-vault-obsidian/pask-vault-obsidian/src/watcher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.490008+00:00
---

# packages/pask-vault-obsidian/pask-vault-obsidian/src/watcher.ts

```ts
/**
 * ObsidianWatcher — DB3 of the Dimensional Second Brain workstream.
 *
 * Observes a local Obsidian vault (Node/Bun) via fs.watch and emits Pask
 * interactions for every meaningful file event. On cold-start it seeds
 * the link topology from the existing vault without overwhelming recency.
 *
 * Cell-ID namespace:
 *   obs:note:<vault-id>/<rel-path-without-ext>
 *   obs:tag:#<tag>
 *   obs:folder:<vault-id>/<parent-dir>
 *
 * Interactions are fire-and-forget; errors are swallowed (non-fatal).
 */

import { promises as fs } from 'node:fs';
import { watch } from 'node:fs';
import path from 'node:path';
import type { PaskGraph } from '@semantos/runtime-services';

// ── Parsing ────────────────────────────────────────────────────────────────

const WIKILINK_RE = /\[\[([^\]|#\n]+?)(?:[|#][^\]]*?)?\]\]/g;
const TAG_RE = /(?:^|\s)#([\w/]+)/gm;

export function parseWikilinks(content: string): string[] {
  const links: string[] = [];
  let m: RegExpExecArray | null;
  WIKILINK_RE.lastIndex = 0;
  while ((m = WIKILINK_RE.exec(content)) !== null) {
    links.push(m[1]!.trim());
  }
  return links;
}

export function parseTags(content: string): string[] {
  const tags: string[] = [];
  let m: RegExpExecArray | null;
  TAG_RE.lastIndex = 0;
  while ((m = TAG_RE.exec(content)) !== null) {
    tags.push(m[1]!.trim());
  }
  return tags;
}

// ── Cell-ID helpers ────────────────────────────────────────────────────────

/** Convert a Windows or POSIX rel-path to the POSIX form used in cell IDs. */
function normPath(p: string): string {
  return p.replace(/\\/g, '/');
}

function noteCell(vaultId: string, relPath: string): string {
  const withoutExt = relPath.replace(/\.md$/i, '');
  return `obs:note:${vaultId}/${normPath(withoutExt)}`;
}

function tagCell(tag: string): string {
  return `obs:tag:#${tag}`;
}

function folderCell(vaultId: string, relPath: string): string {
  const dir = normPath(path.dirname(relPath));
  return dir === '.' ? `obs:folder:${vaultId}` : `obs:folder:${vaultId}/${dir}`;
}

function wikilinkCell(vaultId: string, link: string): string {
  // Strip .md suffix if present, normalise separator
  return `obs:note:${vaultId}/${normPath(link.replace(/\.md$/i, ''))}`;
}

function vaultIdFromPath(vaultPath: string): string {
  return path
    .basename(vaultPath)
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9-]/g, '');
}

// ── Glob matching ──────────────────────────────────────────────────────────

function globToRe(pattern: string): RegExp {
  const escaped = pattern
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    // **/ → optional any-path-prefix (handles root-level files for patterns like **/*.md)
    .replace(/\*\*\//g, '\x00')
    // remaining ** (e.g. suffix pattern like foo/**) → match anything
    .replace(/\*\*/g, '\x01')
    // single * → non-separator wildcard
    .replace(/\*/g, '[^/]*')
    .replace(/\x00/g, '(.*/)?')
    .replace(/\x01/g, '.*');
  return new RegExp(`^${escaped}$`);
}

function matchesAny(relPath: string, patterns: string[]): boolean {
  const p = normPath(relPath);
  return patterns.some((g) => globToRe(g).test(p));
}

// ── Options & class ────────────────────────────────────────────────────────

export interface ObsidianWatcherOptions {
  /** Absolute path to the vault root directory. */
  vaultPath: string;
  /** Stable short ID used as cell namespace. Defaults to a slug of the vault dirname. */
  vaultId?: string;
  /** PaskGraph instance to feed interactions into. */
  paskGraph: PaskGraph;
  /** Glob patterns to watch. Default: ["**\/*.md"] */
  include?: string[];
  /** Glob patterns to exclude. Default: [".obsidian/**", ".trash/**"] */
  exclude?: string[];
  /**
   * When true, after reaching a stable graph state write a Map-of-Content
   * note back into the vault. Fires after every finalize tick (~60s).
   */
  writeMoc?: boolean;
  mocPath?: string;
  /**
   * During cold-start seed, interactions are backdated uniformly over this
   * many milliseconds of history. Default: 30 days.
   */
  coldStartWindowMs?: number;
}

export class ObsidianWatcher {
  private readonly vaultId: string;
  private readonly include: string[];
  private readonly exclude: string[];
  private readonly graph: PaskGraph;
  private fsWatcher: ReturnType<typeof watch> | null = null;
  private stopped = false;

  readonly vaultPath: string;
  readonly writeMoc: boolean;
  readonly mocPath: string;
  readonly coldStartWindowMs: number;

  constructor(private readonly opts: ObsidianWatcherOptions) {
    this.vaultPath = opts.vaultPath;
    this.vaultId = opts.vaultId ?? vaultIdFromPath(opts.vaultPath);
    this.include = opts.include ?? ['**/*.md'];
    this.exclude = opts.exclude ?? ['.obsidian/**', '.trash/**'];
    this.graph = opts.paskGraph;
    this.writeMoc = opts.writeMoc ?? false;
    this.mocPath = opts.mocPath ?? 'Stable Threads.md';
    this.coldStartWindowMs = opts.coldStartWindowMs ?? 30 * 24 * 60 * 60 * 1000;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  async start(): Promise<void> {
    this.stopped = false;
    await this.coldStart();
    this.startWatcher();
  }

  stop(): void {
    this.stopped = true;
    this.fsWatcher?.close();
    this.fsWatcher = null;
  }

  // ── Cold-start ────────────────────────────────────────────────────────────

  private async coldStart(): Promise<void> {
    const files = await this.walk(this.vaultPath);
    const now = Date.now();
    const window = this.coldStartWindowMs;

    // Distribute seed interactions uniformly over the backdate window.
    const step = files.length > 1 ? window / files.length : 0;

    for (let i = 0; i < files.length; i++) {
      if (this.stopped) return;
      const relPath = files[i]!;
      const content = await this.read(relPath).catch(() => null);
      if (!content) continue;
      const backdate = now - window + i * step;
      this.emitSeed(relPath, content, backdate);
    }
  }

  private emitSeed(relPath: string, content: string, nowMs: number): void {
    const cell = noteCell(this.vaultId, relPath);
    const related = this.relatedCells(relPath, content);
    this.graph.interact({ cellId: cell, kind: 'seed', strength: 0.1, relatedCells: related, nowMs });
  }

  // ── Live watcher ──────────────────────────────────────────────────────────

  private startWatcher(): void {
    try {
      this.fsWatcher = watch(
        this.vaultPath,
        { recursive: true, persistent: false },
        (eventType, filename) => {
          if (!filename || this.stopped) return;
          // `filename` on macOS/Linux is relative to the watched dir; on older
          // Node it may be just the basename. Normalise to a relative path.
          const relPath = normPath(filename);
          if (!this.shouldWatch(relPath)) return;
          this.handleChange(relPath, eventType).catch(() => {});
        },
      );
    } catch {
      // fs.watch not available in this environment (e.g., Bun WASM runtime)
    }
  }

  private async handleChange(relPath: string, eventType: string): Promise<void> {
    const now = Date.now();
    const cell = noteCell(this.vaultId, relPath);

    if (eventType === 'rename') {
      // Could be create or delete — probe the file
      const content = await this.read(relPath).catch(() => null);
      if (content === null) {
        // File was deleted
        this.graph.interact({ cellId: cell, kind: 'dismissed', strength: -1.0, nowMs: now });
      } else {
        // File was created
        const related = this.relatedCells(relPath, content);
        this.graph.interact({ cellId: cell, kind: 'edit', strength: 0.8, relatedCells: related, nowMs: now });
        if (this.writeMoc) this.maybeWriteMoc().catch(() => {});
      }
      return;
    }

    // 'change' event — file was modified
    const content = await this.read(relPath).catch(() => null);
    if (!content) return;
    const related = this.relatedCells(relPath, content);
    this.graph.interact({ cellId: cell, kind: 'edit', strength: 0.8, relatedCells: related, nowMs: now });
    if (this.writeMoc) this.maybeWriteMoc().catch(() => {});
  }

  // ── Plugin-protocol events (called by companion plugin via IPC) ───────────

  /**
   * Called when the Obsidian companion plugin emits a file-open event.
   * relPath is relative to the vault root.
   */
  onFileOpen(relPath: string, nowMs = Date.now()): void {
    if (!this.shouldWatch(normPath(relPath))) return;
    const cell = noteCell(this.vaultId, relPath);
    const related = [folderCell(this.vaultId, relPath)];
    this.graph.interact({ cellId: cell, kind: 'open', strength: 0.5, relatedCells: related, nowMs });
  }

  /**
   * Called when the user clicks a [[wikilink]] — traversal from source to target.
   * Both directions get an interaction so the edge is bidirectional.
   */
  onLinkTraverse(sourceRelPath: string, targetRelPath: string, nowMs = Date.now()): void {
    if (!this.shouldWatch(normPath(sourceRelPath))) return;
    const sourceCell = noteCell(this.vaultId, sourceRelPath);
    const targetCell = noteCell(this.vaultId, targetRelPath);
    this.graph.interact({ cellId: sourceCell, kind: 'link-traverse', strength: 1.0, relatedCells: [targetCell], nowMs });
    this.graph.interact({ cellId: targetCell, kind: 'link-traverse', strength: 1.0, relatedCells: [sourceCell], nowMs });
  }

  /**
   * Called when the user clicks a backlink in Obsidian's Backlinks panel.
   */
  onBacklinkClick(sourceRelPath: string, targetRelPath: string, nowMs = Date.now()): void {
    if (!this.shouldWatch(normPath(sourceRelPath))) return;
    const sourceCell = noteCell(this.vaultId, sourceRelPath);
    const targetCell = noteCell(this.vaultId, targetRelPath);
    this.graph.interact({ cellId: sourceCell, kind: 'link-traverse', strength: 0.8, relatedCells: [targetCell], nowMs });
  }

  /**
   * Called when the user clicks a search result in Obsidian's search panel.
   * queryHash is the first 8 hex chars of a djb2 hash of the query string.
   */
  onSearchResultClick(relPath: string, queryHash: string, nowMs = Date.now()): void {
    if (!this.shouldWatch(normPath(relPath))) return;
    const cell = noteCell(this.vaultId, relPath);
    const qCell = `q:${queryHash}`;
    this.graph.interact({ cellId: cell, kind: 'tapped', strength: 0.6, relatedCells: [qCell], nowMs });
  }

  // ── MOC write-back ────────────────────────────────────────────────────────

  private mocWriteTimer: ReturnType<typeof setTimeout> | null = null;

  private maybeWriteMoc(): Promise<void> {
    // Debounce — write at most once per 60s
    if (this.mocWriteTimer) return Promise.resolve();
    return new Promise((resolve) => {
      this.mocWriteTimer = setTimeout(async () => {
        this.mocWriteTimer = null;
        await this.writeMocFile().catch(() => {});
        resolve();
      }, 60_000);
    });
  }

  private async writeMocFile(): Promise<void> {
    const threads = this.graph.stableThreads({ limit: 20 });
    const now = new Date().toISOString().slice(0, 16).replace('T', ' ');
    const lines: string[] = [
      '# Stable Threads — generated by semantos pask, do not edit',
      `_Last updated: ${now}_`,
      '',
      '## Top 20 by traffic',
      '',
    ];
    for (const t of threads) {
      const label = t.cellId.startsWith(`obs:note:${this.vaultId}/`)
        ? `[[${t.cellId.slice(`obs:note:${this.vaultId}/`.length)}]]`
        : `\`${t.cellId}\``;
      lines.push(`- ${label} — ${t.trafficCount} interactions, h=${t.hState.toFixed(3)}`);
    }
    const mocAbs = path.join(this.vaultPath, this.mocPath);
    await fs.writeFile(mocAbs, lines.join('\n') + '\n', 'utf8');
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  private shouldWatch(relPath: string): boolean {
    return matchesAny(relPath, this.include) && !matchesAny(relPath, this.exclude);
  }

  private relatedCells(relPath: string, content: string): string[] {
    const cells: string[] = [];
    // Parent folder
    cells.push(folderCell(this.vaultId, relPath));
    // Wikilink targets
    for (const link of parseWikilinks(content)) {
      cells.push(wikilinkCell(this.vaultId, link));
    }
    // Tags
    for (const tag of parseTags(content)) {
      cells.push(tagCell(tag));
    }
    return cells;
  }

  private async read(relPath: string): Promise<string> {
    return fs.readFile(path.join(this.vaultPath, relPath), 'utf8');
  }

  private async walk(dir: string): Promise<string[]> {
    const results: string[] = [];
    const entries = await fs.readdir(dir, { withFileTypes: true, recursive: true }).catch(() => []);
    for (const entry of entries) {
      if (entry.isFile()) {
        // entry.path is the directory containing the file on Node 20+;
        // fall back to parentPath for older Node versions.
        const parentDir: string = (entry as { path?: string; parentPath?: string }).path
          ?? (entry as { path?: string; parentPath?: string }).parentPath
          ?? dir;
        const abs = path.join(parentDir, entry.name);
        const relPath = normPath(path.relative(dir, abs));
        if (this.shouldWatch(relPath)) results.push(relPath);
      }
    }
    return results;
  }
}

```
