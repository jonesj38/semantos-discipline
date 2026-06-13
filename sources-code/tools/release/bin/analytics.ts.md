---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/bin/analytics.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.559161+00:00
---

# tools/release/bin/analytics.ts

```ts
#!/usr/bin/env bun
/**
 * release-analytics — feed every release cell across every room into
 * a fresh pask kernel and dump the structural patterns:
 *
 *   bun run tools/release/bin/analytics.ts
 *     [--blobs <path>]      default: apps/demo-collab-versioning/data/blobs
 *     [--data <path>]       default: apps/demo-collab-versioning/data
 *     [--pask <wasm path>]  default: core/pask/zig-out/bin/pask.wasm
 *
 * What it surfaces:
 *   - per-package rollup: total / stable / pruned releases
 *   - top dependency edges (most-trafficked cross-package pins)
 *   - stable threads (releases settled into the dep graph)
 *   - top inbound traffic (most-pinned releases — the canonical pins)
 *
 * Pask analyses release cells without knowing they're release cells.
 * Add more rooms (release.lib.x, release.app.y) and they show up
 * automatically — no kernel changes, no script changes.
 */

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

import { loadAllCells, type SerializedCell } from '../lib';

const argv = process.argv.slice(2);
function arg(flag: string, dflt: string): string {
  const i = argv.indexOf(flag);
  if (i >= 0 && argv[i + 1]) return argv[i + 1]!;
  return dflt;
}

const REPO_ROOT = path.resolve(import.meta.dir, '../../..');
const DEFAULT_RELAY_DATA = path.join(REPO_ROOT, 'apps/demo-collab-versioning/data');

const relayData = arg('--data', DEFAULT_RELAY_DATA);
const paskWasm = arg('--pask', path.join(REPO_ROOT, 'core/pask/zig-out/bin/pask.wasm'));

if (!existsSync(paskWasm)) {
  console.error(`pask.wasm not found at ${paskWasm}`);
  console.error('build it first: cd core/pask && zig build');
  process.exit(1);
}

// Lazy-import the pask bindings so this CLI doesn't pay the cost when
// pask isn't built.
const { loadPask } = await import(path.join(REPO_ROOT, 'core/pask/bindings/ts/src/loader'));
const { PaskAdapter } = await import(path.join(REPO_ROOT, 'core/pask/bindings/ts/src/adapter'));

interface ReleasePayload {
  name: string;
  version: string;
  dependencies?: Array<{ name: string; release: string }>;
  build?: { builtAt?: string };
}

interface LoadedCell {
  cell: SerializedCell;
  payload: ReleasePayload;
  builtAtMs: number;
  room: string;
  label: string;
}

function loadAllReleases(): LoadedCell[] {
  if (!existsSync(relayData)) return [];
  const out: LoadedCell[] = [];
  for (const f of readdirSync(relayData)) {
    if (!f.startsWith('release.') || !f.endsWith('.jsonl')) continue;
    const room = f.slice(0, -'.jsonl'.length);
    for (const cell of loadAllCells(path.join(relayData, f))) {
      if (cell.patch?.op !== 'release.kernel.publish') continue;
      const payload = cell.patch.payload as unknown as ReleasePayload;
      const builtAtMs = payload.build?.builtAt ? new Date(payload.build.builtAt).getTime() : 0;
      out.push({
        cell, payload, builtAtMs, room,
        label: `${payload.name}@${payload.version}`,
      });
    }
  }
  return out;
}

const releases = loadAllReleases();
if (releases.length === 0) {
  console.log(`no release cells under ${relayData}`);
  process.exit(0);
}

releases.sort((a, b) => a.builtAtMs - b.builtAtMs);

const labelByHash = new Map<string, string>();
const roomByHash = new Map<string, string>();
for (const r of releases) {
  labelByHash.set(r.cell.stateHashHex, r.label);
  roomByHash.set(r.cell.stateHashHex, r.room);
}

console.log(`loaded ${releases.length} release cells across ${new Set(releases.map((r) => r.room)).size} rooms`);
console.log(`  earliest: ${new Date(releases[0]!.builtAtMs).toISOString()}`);
console.log(`  latest:   ${new Date(releases[releases.length - 1]!.builtAtMs).toISOString()}\n`);

const pask = await loadPask(readFileSync(paskWasm));
const adapter = new PaskAdapter(pask, {
  stabilityWindowMs: 30 * 24 * 60 * 60 * 1000,
  minInteractions: 1,
  stabilityCheckEvery: 0,
  pruneEvery: 0,
  propagationDepth: 2,
  stabilityEpsilon: 0.05,
});

for (const r of releases) {
  const related: string[] = [];
  if (r.cell.parentHashes[0]) related.push(r.cell.parentHashes[0]);
  for (const d of r.payload.dependencies ?? []) {
    if (d.release) related.push(d.release);
  }
  await adapter.interact({
    cellId: r.cell.stateHashHex,
    kind: r.room,
    strength: 1.0,
    relatedCells: related,
    nowMs: r.builtAtMs,
  });
}
adapter.finalize(releases[releases.length - 1]!.builtAtMs + 1);

const snap = adapter.snapshot();
console.log(`graph: ${snap.nodes.length} nodes, ${snap.edges.length} edges, ${snap.nodes.filter((n) => n.isStable).length} stable, ${snap.nodes.filter((n) => n.isPruned).length} pruned\n`);

// Per-package rollup.
const byRoom = new Map<string, { stable: number; pruned: number; total: number }>();
for (const n of snap.nodes) {
  const room = roomByHash.get(n.cellId) ?? n.typePath;
  const r = byRoom.get(room) ?? { stable: 0, pruned: 0, total: 0 };
  r.total += 1;
  if (n.isStable) r.stable += 1;
  if (n.isPruned) r.pruned += 1;
  byRoom.set(room, r);
}
console.log('per-package rollup:');
console.log('  ' + 'package'.padEnd(36) + 'total  stable  pruned');
for (const [room, r] of byRoom) {
  console.log(`  ${room.padEnd(36)}${String(r.total).padStart(5)}  ${String(r.stable).padStart(6)}  ${String(r.pruned).padStart(6)}`);
}
console.log('');

// Top edges.
const topEdges = [...snap.edges].sort((a, b) => b.interactionCount - a.interactionCount).slice(0, 10);
console.log('top dependency edges (by traffic):');
for (const e of topEdges) {
  const from = labelByHash.get(e.fromCell) ?? e.fromCell.slice(0, 12);
  const to = labelByHash.get(e.toCell) ?? e.toCell.slice(0, 12);
  console.log(`  n=${String(e.interactionCount).padStart(3)}  w=${e.constraintWeight.toFixed(3).padStart(7)}  ${from}  →  ${to}`);
}
console.log('');

// Stable threads.
const stable = adapter.stableThreads(50);
if (stable.length === 0) {
  console.log('stable threads: (none — try widening window or epsilon)');
} else {
  console.log(`stable threads (${stable.length}):`);
  for (const s of stable.slice(0, 10)) {
    const label = labelByHash.get(s.cellId) ?? s.cellId.slice(0, 16);
    console.log(`  h=${s.hState.toFixed(3).padStart(7)}  inbound=${s.totalConstraintStrength.toFixed(3).padStart(6)}  ${label}`);
  }
}
console.log('');

// Top inbound.
const inbound = new Map<string, number>();
for (const e of snap.edges) inbound.set(e.toCell, (inbound.get(e.toCell) ?? 0) + e.interactionCount);
const topInbound = [...inbound.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10);
console.log('top inbound traffic (most-pinned cells):');
for (const [hash, n] of topInbound) {
  const label = labelByHash.get(hash) ?? hash.slice(0, 16);
  console.log(`  in=${String(n).padStart(3)}  ${label}`);
}

```
