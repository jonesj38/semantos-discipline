---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.687113+00:00
---

# @semantos/demo-wasm-threejs

Substructural linearity, animated. A Three.js scene driven by Semantos cells — each cube is a cell with a linearity class, and the kernel's K1 enforcement gate decides what you can do with it.

Built as a hook for browser/XR developers (A-Frame, Three.js, OffscreenCanvas, custom WebGL): the cell engine is **one file plus a WASM blob** — no npm packages, no Node crypto, no BSV SDK.

## Run

```bash
# From the repo root
bun install
cd core/cell-engine && zig build && cd ../..   # one-time: produce the WASM artifact
cd apps/demo-wasm-threejs
bun run dev                                     # vite at http://localhost:5174
```

Click any cube. Its backing cell executes a script that attempts an operation (DUP or DROP) on itself. The kernel either allows it or rejects it, based on the cell's linearity class.

## What you're looking at

Three colours, three substructural rules, the full 3×2 decision table:

|                        | DUP              | DROP             |
| ---                    | ---              | ---              |
| **LINEAR**   (blue)    | shatter (K1a)    | shatter (K1b)    |
| **AFFINE**   (grey)    | shatter          | fade             |
| **RELEVANT** (green)   | mitosis          | shatter          |

- **LINEAR** — must be consumed exactly once. No DUP, no DROP.
- **AFFINE** — consumed at most once. No DUP. Silent discard is fine.
- **RELEVANT** — must be consumed at least once. DUP is fine. No DROP.

Plus a **conductor cube** that uses `OP_CALLHOST` (0xD0) to push two cells and call a host-side `merge` function — the cells glide together and coalesce. That's the same opcode boundary [Phase 38's `host.exec` verb](../../docs/prd/PHASE-38B-PROMPT.md) uses to reach out of the kernel.

The "shatter" animation is not decoration — it's what the kernel's K1 gate returning `cannot_duplicate_linear` (error code 22) *looks like*. Toggle enforcement off with the control in the bottom-left and watch the same scripts succeed where they shouldn't.

## What's actually running

The browser loads `cell-engine.wasm` via `WebAssembly.instantiateStreaming()`. Each cube's click builds a script of the shape:

```
OP_PUSHDATA2 <packed 1024-byte cell>  OP_DUP | OP_DROP
```

where the packed cell has the linearity class baked into its header at byte 16. On click, the demo calls `engine.executeScript(script)`, reads `errorCode`, maps it to a `LinearityError` via a small lookup table, and picks an animation. No server, no backend.

The K1 theorem in [LinearityK1.lean](../../proofs/lean/Semantos/Theorems/LinearityK1.lean) proves that the kernel rejects these violations. You're watching that theorem execute.

## Drop into your own scene

The whole runtime is one file: [src/cell-engine.ts](src/cell-engine.ts) (~220 lines, zero deps beyond `fetch` + `WebAssembly`). Copy it plus `cell-engine.wasm` into your project and you have a working 2-PDA executor with linearity enforcement:

```ts
import { loadCellEngine, pushCellScript, concatScript, OP_DUP } from './cell-engine';

const engine = await loadCellEngine('/cell-engine.wasm');
engine.setEnforcement(true);

// Craft a LINEAR cell, try to duplicate it — kernel rejects with
// linearityError: 'cannot_duplicate_linear'.
const cell = engine.packCell('linear');
const script = concatScript(pushCellScript(cell), new Uint8Array([OP_DUP]));
const result = engine.executeScript(script);

console.log(result.linearityError); // 'cannot_duplicate_linear'
```

## Why a minimal loader?

The full binding at [core/cell-engine/bindings/browser/loader.ts](../../core/cell-engine/bindings/browser/loader.ts) gives you the whole feature surface (cell pack/unpack, SPV, BCA, type-hash registry, anchor scheduling). It's the right choice for a real app.

For a demo, an XR sketch, or "I just want to see the kernel run", that surface drags in `@semantos/protocol-types` → `@semantos/cell-ops` → Node `crypto.createHash` (which doesn't exist in browsers without polyfills). The minimal `src/cell-engine.ts` here exposes only what a renderer actually needs — `executeScript`, `stackDepth`, `stackPeek`, `packCell`, `setEnforcement` — and runs in any browser without polyfills.

If you outgrow it, swap the import for the full binding. The signatures are nearly identical.

## Where this could go next

This demo is narrow on purpose — teach substructural typing in 30 seconds, no more. For the bigger idea (collaborative 3D canvas, every edit is a patch, linearity as collaboration semantics, kernel-backed audit chain), see [NEXT_IDEAS.md](NEXT_IDEAS.md).

## What this demo is — and isn't

**Is**: a visual argument for substructural typing, and a sanity check that the cell engine runs in a browser without ceremony. Use it as a starting scaffold for visual/XR work that uses cells as state.

**Isn't**: a semantic-engine API. The kernel is a 2-PDA *script executor*. If you want higher-level constructs (conversation theory primitives, jural categories, identity), those compile *down to* cell scripts via the IR pipeline (see [docs/PIPELINE.md](../../docs/PIPELINE.md)). Don't expect a `kernel_speak()` or `kernel_listen()` — there isn't one and there shouldn't be.

## Files

```
apps/demo-wasm-threejs/
├── index.html             entry HTML — canvas, HUD, legend, controls
├── NEXT_IDEAS.md          sketch: collaborative canvas + patch chain (Path 2)
├── src/
│   ├── main.ts            three.js scene + click handler + animation loop
│   ├── cell-engine.ts     minimal WASM loader (zero deps; copy this anywhere)
│   ├── cells.ts           declarative cube recipes (class + operation)
│   └── style.css          dark-mode HUD styling
├── vite.config.ts         dev server + auto-copies WASM into public/
├── tsconfig.json
└── package.json           the only dep is `three`
```

## Dependencies

- [`three`](https://github.com/mrdoob/three.js) — render loop and 3D primitives

That's it. No `@semantos/*` workspace deps.
