---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cell-relay/src/jsonl.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.441123+00:00
---

# packages/cell-relay/src/jsonl.ts

```ts
/**
 * JSONL helpers — read/write the relay's per-room append-only log.
 *
 * The Elixir cell-relay (runtime/world-beam/apps/cell_relay/) and the Bun dev variant
 * (apps/demo-collab-versioning/) both treat the JSONL file as
 * authoritative — they replay it on startup, persist every commit, and
 * trust nothing else for state recovery. So a process appending here
 * is durable even with no relay running.
 *
 * Path convention: <relayDataDir>/<room>.jsonl
 *   e.g. apps/demo-collab-versioning/data/release.kernel.pask.jsonl
 */

import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
} from 'node:fs';
import path from 'node:path';

import type { SerializedCell } from './types';

export function jsonlPathFor(relayDataDir: string, room: string): string {
  return path.join(relayDataDir, `${room}.jsonl`);
}

export function loadAllCells(jsonlPath: string): SerializedCell[] {
  if (!existsSync(jsonlPath)) return [];
  const out: SerializedCell[] = [];
  for (const line of readFileSync(jsonlPath, 'utf8').split('\n')) {
    if (!line) continue;
    try {
      out.push(JSON.parse(line) as SerializedCell);
    } catch {
      // Skip malformed lines — matches the relay's tolerant replay.
    }
  }
  return out;
}

/** Last cell in the log whose patch.op matches. */
export function lastCellOfOp(cells: SerializedCell[], op: string): SerializedCell | null {
  for (let i = cells.length - 1; i >= 0; i--) {
    if (cells[i]!.patch.op === op) return cells[i]!;
  }
  return null;
}

export function appendCell(jsonlPath: string, cell: SerializedCell): void {
  const dir = path.dirname(jsonlPath);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  appendFileSync(jsonlPath, JSON.stringify(cell) + '\n');
}

/**
 * Walk parent links from `headHash` back to a root. Throws on broken
 * chain or cycle. Returns root → head ordering.
 */
export function walkChain(
  byHash: Map<string, SerializedCell>,
  headHash: string,
): SerializedCell[] {
  const chain: SerializedCell[] = [];
  const seen = new Set<string>();
  let cursor: string | null = headHash;
  while (cursor) {
    if (seen.has(cursor)) throw new Error(`cycle detected at ${cursor}`);
    seen.add(cursor);
    const cell = byHash.get(cursor);
    if (!cell) throw new Error(`chain broken: cell ${cursor} not present`);
    chain.push(cell);
    cursor = cell.parentHashes[0] ?? null;
  }
  return chain.reverse();
}

/** Build an in-memory index by stateHashHex. */
export function indexByHash(cells: SerializedCell[]): Map<string, SerializedCell> {
  return new Map(cells.map((c) => [c.stateHashHex, c]));
}

```
