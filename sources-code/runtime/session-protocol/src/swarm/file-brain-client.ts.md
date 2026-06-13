---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/file-brain-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.051342+00:00
---

# runtime/session-protocol/src/swarm/file-brain-client.ts

```ts
/**
 * FileBrainClient — a SwarmBrainClient backed by a shared directory.
 *
 * Stands in for the Zig brain across SEPARATE OS PROCESSES on one host (or a
 * shared mount): each infohash gets a `<dir>/<infohash>.json` file holding the
 * manifest cell hex, seeders, and settled receipts. This lets a real seeder and
 * a real leecher — two independent `bun` processes — share a tracker without a
 * running brain, so the data plane can be exercised over actual UDP sockets.
 *
 * Read-modify-write per call; fine for a small local demo, not for contention.
 * Node/Bun runtime only (uses node:fs).
 */

import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { toHex, fromHex } from '@semantos/protocol-types';
import type { SwarmBrainClient, LocateResult, SwarmReceipt, SeederInfo } from './brain-client';

interface FileEntry {
  manifestCellHex: string;
  semanticPath: string;
  seeders: Record<string, { address: string; bitfieldHex: string; lastSeen: number }>;
  receipts: SwarmReceipt[];
}

export class FileBrainClient implements SwarmBrainClient {
  private clock = 0;
  constructor(private readonly dir: string) {
    mkdirSync(dir, { recursive: true });
  }

  private path(infohashHex: string): string {
    return join(this.dir, `${infohashHex}.json`);
  }
  private read(infohashHex: string): FileEntry | null {
    const p = this.path(infohashHex);
    if (!existsSync(p)) return null;
    return JSON.parse(readFileSync(p, 'utf8')) as FileEntry;
  }
  private write(infohashHex: string, e: FileEntry): void {
    writeFileSync(this.path(infohashHex), JSON.stringify(e));
  }

  async publish(args: { infohash: Uint8Array; manifestCell: Uint8Array; semanticPath: string }): Promise<{ infohash: string }> {
    const key = toHex(args.infohash);
    if (!this.read(key)) {
      this.write(key, { manifestCellHex: toHex(args.manifestCell), semanticPath: args.semanticPath, seeders: {}, receipts: [] });
    }
    return { infohash: key };
  }

  async locate(infohash: Uint8Array): Promise<LocateResult> {
    const e = this.read(toHex(infohash));
    if (!e) return { manifestCell: null, seeders: [] };
    const seeders: SeederInfo[] = Object.values(e.seeders).map(s => ({
      address: s.address,
      bitfield: s.bitfieldHex ? fromHex(s.bitfieldHex) : undefined,
      lastSeen: s.lastSeen,
    }));
    return { manifestCell: fromHex(e.manifestCellHex), seeders };
  }

  async announce(args: { infohash: Uint8Array; address?: string; bca?: Uint8Array; bitfield: Uint8Array }): Promise<void> {
    const key = toHex(args.infohash);
    const e = this.read(key);
    if (!e) return;
    const id = args.address ?? (args.bca ? toHex(args.bca) : 'unknown');
    e.seeders[id] = { address: id, bitfieldHex: toHex(args.bitfield), lastSeen: this.clock++ };
    this.write(key, e);
  }

  async settle(args: { infohash: Uint8Array; receipts: SwarmReceipt[] }): Promise<{ recorded: number }> {
    const key = toHex(args.infohash);
    const e = this.read(key);
    if (!e) return { recorded: 0 };
    e.receipts.push(...args.receipts);
    this.write(key, e);
    return { recorded: args.receipts.length };
  }
}

```
