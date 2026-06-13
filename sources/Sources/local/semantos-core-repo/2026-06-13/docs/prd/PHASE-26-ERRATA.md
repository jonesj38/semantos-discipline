---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.716607+00:00
---

# Phase 26 Errata — Game Engine SemanticObject SDK

## Errata Sprint Results

### 1. Orphaned Entity Check
**Status: PASS**
Every `GameEntity` returned by `createEntity()` contains a valid 1024-byte cell. The `cell` property IS the entity — there is no separate data structure. `isValidCell()` confirms magic bytes are present. There is no way to create a `GameEntity` without a backing cell.

### 2. Trade Atomicity
**Status: PASS**
`executeTrade()` uses snapshot-and-swap: both inventory Maps are cloned before mutation. If any validation fails (missing slot, RELEVANT linearity, owner mismatch), the original Maps are untouched and `{ success: false }` is returned. A crash between clone and assignment would leave originals intact since the clones are local variables.

### 3. Serialize Byte-Identity with cell-ops
**Status: PASS with caveat**
`serialize()` returns `entity.cell` which is produced by `packCell()` from `@semantos/cell-ops/typeHashRegistry`. The bytes ARE the cell-ops output. However, the magic bytes are written as raw bytes by `buildCellHeader` (not as LE u32 via DataView), so reading them back with `DataView.getUint32(offset, true)` gives different values than `MAGIC_1` etc. This is consistent within the codebase — all consumers use `isValidCell()` which compares raw bytes.

### 4. Malformed Script Handling
**Status: PASS**
`evaluatePolicy()` with malformed bytes (e.g. `[0xFF, 0xFF, 0xFF]`) returns `false` without crashing the WASM engine. The kernel's `kernel_execute()` returns a non-zero error code which maps to `false`.

### 5. WASM Loader Platform Detection
**Status: PASS for Bun/Node**
`GameCellEngine.create()` auto-detects Bun/Node and reads from `packages/cell-engine/zig-out/bin/cell-engine.wasm`. Browser requires explicit `wasmBytes` or `wasmUrl` (throws if neither provided). This is intentional — browser environments cannot access the filesystem.

### 6. Godot/Unity Scaffold Imports
**Status: PASS**
The Godot and Unity scaffolds import only from `../../types` (the game-sdk's own types). They have zero external dependencies and zero game engine imports.

### 7. Policy Template Compilation
**Status: PASS**
All five policy templates compile without errors:
- `legendary-drop.policy` → LINEAR, has-capability 7
- `quest-no-trade.policy` → RELEVANT, tradeable = 0
- `level-gate.policy` → LINEAR, level >= 10
- `durability.policy` → AFFINE, durability > 0
- `trade-restriction.policy` → LINEAR, has-capability 3

### 8. Inventory Type Mismatch Rejection
**Status: PASS**
`addToInventory()` validates that `entity.ownerId` matches `inventory.ownerId`. Mismatched owners throw `LinearityError('Entity ownerId does not match inventory ownerId')`.

### 9. Entity Creation Throughput
**Status: PASS**
1000 entities created in ~28ms (well under the 1-second target). Performance is dominated by `computeTypeHash()` (SHA256) and `buildCellHeader()` — both are pure TypeScript with no WASM overhead for creation.

## Known Limitations

1. **Host imports are stubs**: `host_checksig` always returns 1. Real ECDSA verification requires the BSV SDK, which is out of scope for Phase 26.

2. **No FUNGIBLE linearity constant**: The protocol uses `DEBUG=4` as a stand-in for FUNGIBLE. A dedicated `FUNGIBLE` linearity value should be added to `constants.json` in a future phase.

3. **State machine policies are text-based**: The `transition()` method currently passes the policy string as raw bytes to `evaluatePolicy()`, not compiled script bytes. For full policy evaluation, the caller should pre-compile via `compileGamePolicy()` and pass `scriptBytes`.

4. **Trade does not verify capabilities**: `executeTrade()` checks linearity and ownership but does not evaluate capability-gated policies. Policy evaluation requires explicit `evaluatePolicy()` calls by the game logic.

5. **Magic byte encoding**: `buildCellHeader` in `typeHashRegistry.ts` writes magic as raw bytes `[0xDE, 0xAD, ...]`, while `serializeCellHeader` in `protocol-types/cell-header.ts` writes them as LE u32 `setUint32(0, 0xDEADBEEF, true)` → `[0xEF, 0xBE, 0xAD, 0xDE]`. Both produce valid cells (their respective `isValidCell`/`deserializeCellHeader` handle the format they produce), but cross-format comparison requires awareness of this difference.
