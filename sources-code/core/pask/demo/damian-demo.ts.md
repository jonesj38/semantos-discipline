---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/demo/damian-demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.932842+00:00
---

# core/pask/demo/damian-demo.ts

```ts
#!/usr/bin/env bun
/**
 * damian-demo.ts — kernel + pask running side-by-side in one host.
 *
 *   bun run core/pask/demo/damian-demo.ts
 *
 * What it does, in order:
 *   1. Instantiate cell-engine-embedded.wasm with a stub host.
 *   2. Instantiate pask.wasm via the bindings.
 *   3. Push a one-byte "TRUE" script through the cell-engine, prove it executes.
 *   4. Feed 200 PGN games through pask, finalize, print the top opening
 *      moves by traffic — the chess result, in TS.
 */

import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { loadPask, PaskAdapter } from '../bindings/ts/src';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const REPO = path.resolve(HERE, '../../..');

const CELL_WASM = path.join(REPO, 'core/cell-engine/zig-out/bin/cell-engine-embedded.wasm');
const PASK_WASM = path.join(REPO, 'core/pask/zig-out/bin/pask.wasm');
const COMBINED_WASM = path.join(REPO, 'core/pask-and-cell/zig-out/bin/pask-and-cell.wasm');
const PGN_PATH = path.resolve(
  REPO, '..', 'friend-semantos/scripts/chess-paskian-rig/data/twic1500.pgn',
);

// ── Cell-engine: minimal host imports ──────────────────────────────────
// Just enough to instantiate. Real hosts wire mbedTLS or web crypto;
// for this demo the script doesn't reach a crypto opcode so noops work.

function noopHost() {
  // Match the actual import set of the freshly-built embedded wasm.
  // Run `strings cell-engine-embedded.wasm | grep host_` to verify.
  return {
    host_sha256: () => {},
    host_sha1: () => {},
    host_hash160: () => {},
    host_hash256: () => {},
    host_ripemd160: () => {},
    host_checksig: () => 0,
    host_sign: () => 0,
    host_call_by_name: () => 0xffffffff,
    host_fetch_cell: () => 0,
  };
}

async function loadCellEngine(bytes: Buffer) {
  const module = await WebAssembly.compile(bytes);
  const instance = await WebAssembly.instantiate(module, { host: noopHost() });
  const exp = instance.exports as any;
  exp.kernel_init();
  return exp;
}

// ── Tiny PGN parser (matches the Zig chess test) ───────────────────────

function* extractMoves(body: string): Generator<string> {
  let i = 0;
  while (i < body.length) {
    const c = body[i]!;
    if (c === '{') { while (i < body.length && body[i] !== '}') i++; if (i < body.length) i++; continue; }
    if (/\s/.test(c)) { i++; continue; }
    if (c === '$') { while (i < body.length && !/\s/.test(body[i]!)) i++; continue; }
    const start = i;
    while (i < body.length && !/\s/.test(body[i]!) && body[i] !== '{') i++;
    const tok = body.slice(start, i);
    if (!tok) continue;
    if (/^[\d.]+$/.test(tok)) continue;
    if (tok === '1-0' || tok === '0-1' || tok === '1/2-1/2' || tok === '*') continue;
    yield tok;
  }
}

function* readGames(text: string): Generator<string[]> {
  let pos = 0;
  while (pos < text.length) {
    while (pos < text.length && /[\s\n]/.test(text[pos]!)) pos++;
    if (pos >= text.length) break;
    while (pos < text.length && text[pos] === '[') {
      while (pos < text.length && text[pos] !== '\n') pos++;
      if (pos < text.length) pos++;
    }
    while (pos < text.length && /[\n\r]/.test(text[pos]!)) pos++;
    const start = pos;
    while (pos < text.length) {
      if (pos + 1 < text.length && text[pos] === '\n' && text[pos + 1] === '[') break;
      if (pos + 1 < text.length && text[pos] === '\n' && /[\n\r]/.test(text[pos + 1]!)) break;
      pos++;
    }
    const body = text.slice(start, pos);
    if (body.length === 0) continue;
    yield Array.from(extractMoves(body));
  }
}

// ── Demo ──────────────────────────────────────────────────────────────

async function main() {
  const mode = process.argv.includes('--combined') ? 'combined' : 'sibling';
  console.log(`=== kernel + pask demo (mode: ${mode}) ===\n`);

  // ── Pick a wiring ──
  // sibling:  load cell-engine.wasm and pask.wasm separately. Two
  //           Memory instances. Cross-kernel data has to be copied
  //           through JS-owned buffers.
  // combined: load pask-and-cell.wasm — one WebAssembly.Memory shared
  //           by both kernels. Anything one writes, the other reads
  //           directly without copying. This is what Damian asked for.

  let cell: any;
  let pask: Awaited<ReturnType<typeof loadPask>>;

  if (mode === 'combined') {
    if (!existsSync(COMBINED_WASM)) {
      console.log(`[!] missing ${COMBINED_WASM}`);
      console.log('    rebuild: cd core/pask-and-cell && zig build');
      process.exit(1);
    }
    const bytes = readFileSync(COMBINED_WASM);
    const module = await WebAssembly.compile(bytes);
    const instance = await WebAssembly.instantiate(module, { host: noopHost() });
    cell = instance.exports;
    cell.kernel_init();
    // The combined module exposes pask_* via the same instance.
    pask = { exports: cell, module, instance };
    cell.pask_init();
  } else {
    if (!existsSync(CELL_WASM) || !existsSync(PASK_WASM)) {
      console.log(`[!] missing ${CELL_WASM} or ${PASK_WASM}`);
      process.exit(1);
    }
    cell = await loadCellEngine(readFileSync(CELL_WASM));
    pask = await loadPask(readFileSync(PASK_WASM));
  }

  // Tiny script: push 1, end. cell_engine should leave 1 on the stack.
  const script = new Uint8Array([0x51]); // OP_1
  const memBuf = (cell.memory as WebAssembly.Memory).buffer;
  // Pick a write address well past static state for whichever wiring we
  // chose. Combined-mode pask static state is ~24 MB so we go past that.
  const scriptPtr = mode === 'combined' ? 26 * 1024 * 1024 : 4 * 1024 * 1024;
  if (scriptPtr + script.length > memBuf.byteLength) {
    throw new Error(`memory too small: ${memBuf.byteLength} bytes, need ${scriptPtr + script.length}`);
  }
  new Uint8Array(memBuf).set(script, scriptPtr);
  cell.kernel_load_script(scriptPtr, script.length);
  const rc = cell.kernel_execute();
  console.log(`[cell-engine] OP_1 → rc=${rc}, stack_depth=${cell.kernel_stack_depth()}`);

  const adapter = new PaskAdapter(pask, {
    stabilityCheckEvery: 0,
    pruneEvery: 0,
    minInteractions: 10,
  });

  if (!existsSync(PGN_PATH)) {
    console.log(`\n[!] no PGN corpus at ${PGN_PATH} — skipping chess result`);
    console.log('    grab one from chess-paskian-rig/data or use --pgn');
    return;
  }

  const pgn = readFileSync(PGN_PATH, 'utf8');
  let games = 0;
  let clock = 0;
  const MAX_GAMES = 200; // bigger N → more dramatic stable threads
  const MAX_PLY = 10;

  console.log(`\n[pask] feeding ${MAX_GAMES} PGN games...`);
  const t0 = performance.now();
  for (const moves of readGames(pgn)) {
    if (games >= MAX_GAMES) break;
    if (moves.length === 0) continue;
    let prev = 'p:';
    let prefix = '';
    for (const mv of moves.slice(0, MAX_PLY)) {
      prefix = prefix ? `${prefix} ${mv}` : mv;
      const cellId = `p:${prefix}`;
      clock++;
      await adapter.interact({
        cellId: prev, kind: 'chess', strength: 1.0,
        relatedCells: [cellId], nowMs: clock,
      });
      prev = cellId;
    }
    games++;
  }
  adapter.finalize(clock + 1);
  const elapsed = performance.now() - t0;

  // Top edges out of the root.
  const snap = adapter.snapshot();
  const fromRoot = snap.edges.filter(e => e.fromCell === 'p:');
  fromRoot.sort((a, b) => b.interactionCount - a.interactionCount);

  console.log(`[pask] ${games} games in ${elapsed.toFixed(0)} ms`);
  console.log(`[pask] graph: ${snap.nodes.length} nodes, ${snap.edges.length} edges`);
  console.log('[pask] top first-ply moves by traffic:');
  for (const e of fromRoot.slice(0, 8)) {
    const move = e.toCell.slice(2); // strip "p:"
    console.log(`         n=${String(e.interactionCount).padStart(4)}  ${move}`);
  }

  // Demonstrate the new zero-copy range slice — same data, no per-element call.
  console.log('\n[pask] zero-copy nodesView (first 3 nodes raw bytes):');
  const view = adapter.nodesView();
  console.log(`         count=${view.count} stride=${view.stride}`);
  for (let i = 0; i < Math.min(3, view.count); i++) {
    const cellIdLen = new DataView(
      view.bytes.buffer, view.bytes.byteOffset + i * view.stride + 64, 4,
    ).getUint32(0, true);
    const cellId = new TextDecoder().decode(
      view.bytes.subarray(i * view.stride, i * view.stride + cellIdLen),
    );
    console.log(`         [${i}] ${cellId}`);
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

```
