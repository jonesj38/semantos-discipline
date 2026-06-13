---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PRE-FLIGHT-EXECUTOR-WIRING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.703317+00:00
---

# Pre-flight audit — real `executor.zig` wiring into the brain (§11.10 order 2e)

**Version**: 0.1 (audit)
**Date**: 2026-05-25
**Status**: AUDIT — pre-commitment scoping per Todd 2026-05-25: *"make sure all the pieces are there for committing to"* the big-bet executor pull-in
**Master document**: [`UNIFICATION-ROADMAP.md` §11.10 v0.12](UNIFICATION-ROADMAP.md) order 2e
**Origin context**: [`kernel_zig.zig:17-24`](../../runtime/semantos-brain/src/kernel_zig.zig#L17-L24) — the long-standing TODO comment that frames order 2e as "a substantial build-graph refactor that doesn't fit the Phase 3 scope here," naming 14 transitive cell-engine modules as the dep chain.

---

## Headline (TL;DR)

**The 14-module dep refactor named in `kernel_zig.zig` is materially smaller than the comment suggested**, for two reasons surfaced during this audit:

1. **`core/cell-engine/build.zig` already exposes `pub fn createModules`** — designed exactly for cross-binary consumption, returning the entire executor-relevant module graph (executor, pda, linearity, standard, macro, plexus, hostcall, allocator, sighash, host, constants, errors, octave, pointer, plus build_options, beef, bsvz, ripemd160, multicell, …). One call replaces 14+ individual `b.createModule(...)` lines.
2. **A working precedent already exists in `src/ffi/build.zig`** which inlines the embedded-profile slice of `createModules` so the FFI surface (`semantos_execute_script`) calls the real 2-PDA executor in place of its previous syntactic-only validator. The brain's wiring is the same problem shape with different parameters (embedded=false to keep bsvz, since brain already links bsvz).

**Revised effort estimate:** days, not weeks. Probably one scaffold PR (createModules call + module wiring) + one swap PR (`policy_runtime.evaluate` backend dispatches to `executor.execute` instead of `kernel_zig.executeOpcodeBytes`) + per-test-fix follow-up PRs.

The pattern is the same as Phase 29.5 / D-LIFT-* / D-O5p reconciliations: PRD framing was conservative; ground-truth says the substrate is more advanced than the PRD knew.

---

## §1 Module inventory

Cross-reference of `kernel_zig.zig:17`'s 14 names against actual paths in `core/cell-engine/`:

| # | Name (kernel_zig.zig:17) | Path | Notes |
|---|---|---|---|
| 1 | `constants` | `core/cell-engine/src/constants.zig` | Plain types/values. No transitive surprises. |
| 2 | `errors` | `core/cell-engine/src/errors.zig` | Same — error enum + helpers. |
| 3 | `linearity` | `core/cell-engine/src/linearity.zig` | K1 enforcement. Pulled into `executor` directly. |
| 4 | `allocator` | `core/cell-engine/src/allocator.zig` | Cell-engine's arena. Imported by `executor` as `allocator_mod`. |
| 5 | `pda` | `core/cell-engine/src/pda.zig` | 2-PDA stack. `pda.zig` consumes `build_options.embedded` to carve stack depth. |
| 6 | `sighash` | `core/cell-engine/src/sighash.zig` | Likewise consumes `build_options.embedded` for `MAX_INPUTS` sizing. |
| 7 | `host` | `core/cell-engine/src/host.zig` | Host-function shim. **Sees `embedded`** (full discussion in §2). |
| 8 | `build_options` | *(auto-generated)* | `b.addOptions()` + `options.addOption(bool, "embedded", …)`. Not a source file — created in `build.zig`. |
| 9 | `standard` | `core/cell-engine/src/opcodes/standard.zig` | Lives under `opcodes/`, not src root (PRD path implication was slightly off). |
| 10 | `macro` | `core/cell-engine/src/opcodes/macro.zig` | Same — under `opcodes/`. |
| 11 | `plexus` | `core/cell-engine/src/opcodes/plexus.zig` | Same — under `opcodes/`. |
| 12 | `hostcall` | `core/cell-engine/src/opcodes/hostcall.zig` | Same — under `opcodes/`. Phase 25.5 OP_CALLHOST dispatch. |
| 13 | `pointer` | `core/cell-engine/src/pointer.zig` | Phase 6 module. |
| 14 | `octave` | `core/cell-engine/src/octave.zig` | Phase 6 module. |

**Executor itself**: `core/cell-engine/src/executor.zig` — 370 lines. Its top-level imports (one level deep): `constants`, `errors`, `pda`, `standard`, `macro`, `plexus`, `hostcall`, `allocator`, `sighash`, `std`. 9 of the 14 directly.

**Additional modules pulled in via createModules** that aren't on the 14-name list but the brain might or might not need: `commerce`, `cell`, `multicell`, `bca`, `beef` (optional), `bsvz` (optional), `escalation_descriptor`, `cell_merkle`, `path_merkle`, `derivation_state`, `output_store`, `slot_store`, `headers`, `header_store`, `local_chain_tracker`, `ripemd160`. Most are downstream of WH (headers) or Phase 6 (octave) work — brain may already have them via other paths (bsvz wiring already touches many).

**No modules missing. No paths broken.** The 14-name list resolves cleanly once you know `opcodes/` is a subdirectory.

---

## §2 `host.zig`'s `embedded` build-option plumbing

Read of [`core/cell-engine/src/host.zig`](../../core/cell-engine/src/host.zig) lines 1-15:

```zig
// The `embedded` build option controls dispatch:
//   embedded=false (default): BSVZ native crypto for all targets
//   embedded=true: Phase 3/4 behavior — host externs for WASM, std lib / stubs for native
const build_options = @import("build_options");
const embedded = build_options.embedded;
const bsvz = if (!embedded) @import("bsvz") else struct {};
```

**Two profiles, runtime-decided at build time:**

- **`embedded=false`** (default, what we want for the brain) — `host.zig` imports `bsvz` and dispatches to BSVZ native crypto (sha256, ECDSA, etc.). This is the same profile cell-engine uses for its own native tests.
- **`embedded=true`** — `host.zig` declares WASM externs (resolved at link time for WASM builds) OR falls back to `std.crypto` stubs for native. This is what `src/ffi/build.zig` uses because the FFI library brings its own crypto wiring.

**Brain decision is easy: `embedded=false`.**
- bsvz is already wired in runtime/semantos-brain/build.zig (151 references — bkds, identity_certs inline test setup, others).
- We want real native crypto for the brain's signing + verification paths.
- No need to inline a slice of createModules; just call it with `embedded=false`.

**Nothing to change in `host.zig` itself.** The plumbing is already done.

---

## §3 bsvz integration status

`grep -c "bsvz" runtime/semantos-brain/build.zig` → **151 mentions**.

bsvz is brought in via `b.dependency("bsvz", .{...}).module("bsvz")` in multiple module-setup blocks. The pattern is already idiomatic: every Zig module that needs bsvz adds `.{ .name = "bsvz", .module = bsvz_dep.module("bsvz") }` to its `imports` list.

For `createModules(...embedded=false)`, the cell-engine build.zig itself does `b.dependency("bsvz", .{...}).module("bsvz")` internally (lines 81-86) and wires it into `host_mod` + `beef_mod`. **The brain doesn't need to pass bsvz in — createModules resolves it from `build.zig.zon` dependencies.**

Check needed: does `runtime/semantos-brain/build.zig.zon` already declare a path-dependency on `core/cell-engine`? If yes, createModules just works. If no, add `.dependencies = .{ .cell_engine = .{ .path = "../../core/cell-engine" } }`.

---

## §4 Build-graph impact estimate

**Source LOC delta (estimate):**
- `runtime/semantos-brain/build.zig`: +30-50 lines for the createModules call + import threading.
- Affected: 1-3 modules that need the `executor` import (`policy_runtime_mod` becomes a real consumer; possibly `kernel_zig_mod` is retired or made a thin wrapper). Each adds 1-2 lines.
- `runtime/semantos-brain/build.zig.zon`: 0-3 lines if cell-engine dep needs declaring.

**Total: ~30-60 LOC delta.** Not the thousands-of-LOC reshape `kernel_zig.zig:17`'s tone implied.

**Build-time impact (qualitative):**
- Cell-engine modules already compile during ffi build + cell-engine's own tests. Adding them to the brain's compilation unit shares some artifacts (the Zig build cache is content-addressed).
- Likely small bump in brain `zig build` cold time; warm/incremental builds unaffected because cell-engine sources rarely change relative to brain sources.
- Test suite: cell-engine's own tests don't run via brain `zig build test`. No new tests inherited; the brain stays at its current ~2200 test count (modulo any tests we add for the swap).

---

## §5 Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| **R1.** Cell-engine module names collide with existing brain modules (`constants`, `errors`, `host`, `allocator` are common identifiers) | Medium | The brain creates its modules via `b.createModule({.imports = ...})`; module names are import-scoped, not global. Collisions are per-consumer. If a brain module has its own `allocator` import name, rename one. Surveyable in one grep pass. |
| **R2.** `host.zig`'s bsvz import pulls in a transitive native lib (libsecp256k1?) the brain's binary hasn't linked | Low | bsvz is already linked across 151 brain build sites; transitive deps are already pulled. If a NEW transitive lib appears (e.g., a cell-engine-only addition since the audit grep), surfaces as a linker error — easy to debug. |
| **R3.** Executor's runtime semantics reject cells that the current syntactic shim accepts (test failures across conformance suites) | High | EXPECTED — the whole point of order 2e is real enforcement. Existing oddjobz intent_cells_handler conformance tests have phone-side `kernelResult.ok=true` claims that the syntactic shim agrees with; the real executor may disagree because it actually evaluates linearity / domain flags / type hashes. Per-failure triage: each rejection either reveals a real bug in the test fixture (the cell actually IS malformed) OR a real bug in the executor (regression to triage upstream in cell-engine). Don't paper over either case. |
| **R4.** PolicyContext shape mismatch — TS-mirrored `PolicyContext.fields: StringHashMapUnmanaged` doesn't map cleanly to what the real executor's OP_LOADFIELD expects | Medium | PolicyContext is currently ignored by the syntactic shim. When the real executor lands, the field-loading semantics need to translate from PolicyContext to the executor's PDA stack layout. This is the same work CDM/SCADA already solved on the TS side; mirror their approach (or accept it as a known follow-up if executor accepts an empty fields map and the test fixtures don't exercise OP_LOADFIELD). |
| **R5.** `_ = context;` discards in `policy_runtime.evaluate` become real consumption — context fields not previously wired must now thread through to the executor | Low | Mechanical edit; the function signature already takes `context`. |

---

## §6 Recommended sequencing

**PR sequence (estimate):**

1. **PR-1 (scaffold, ~half day):**
   - Add `cell_engine` dependency to `runtime/semantos-brain/build.zig.zon` if missing.
   - Call `cell_engine_build.createModules(b, target, optimize, false)` in `runtime/semantos-brain/build.zig`.
   - `_ = ce_modules;` discards initially.
   - Verify `zig build test` is green (no consumer yet, so no behavioral change).

2. **PR-2 (real backend swap, ~1-2 days):**
   - In `policy_runtime.zig`, add a third backend option: `.executor` (alongside existing `.shim`).
   - Backend dispatches to `executor.execute(policy_bytes, ...)` instead of `kernel_zig.executeOpcodeBytes`.
   - Wire the brain to construct PolicyRuntime with `.executor` mode for at least one cartridge handler (likely cell_handler.zig as the safest first consumer — fewest existing fixtures).
   - Triage test failures (expect some per R3).

3. **PR-3+ (per-cartridge migration, ~days each):**
   - Switch `intent_cells_handler` to `.executor` mode. Triage failures.
   - Switch any other consumers (none today, but order 1's Dispatcher Phase 1 work may add some).
   - Update §11.10's matrix delta when order 2e flips to ✓.

4. **PR-N (retire `kernel_zig.zig` or keep as fallback):**
   - Decision: do we keep `.shim` mode for embedded targets / FFI parity, or fully retire `kernel_zig.executeOpcodeBytes`?
   - If retire: delete `kernel_zig.zig` + its inline tests + remove imports.
   - If keep: document `.shim` as the embedded-profile backend (matches `src/ffi/build.zig`'s embedded slice).

---

## §7 What needs Todd's input before committing

Per loop rules — surfacing the decisions that warrant Todd's call before launching PR-1:

1. **Keep or retire `kernel_zig.executeOpcodeBytes` after the swap?**
   - Keep: useful for embedded profiles (matches FFI's choice) + as a fallback if executor proves slow/buggy.
   - Retire: cleaner; one backend; fewer code paths.
   - Recommendation: **keep** (mirror FFI's pattern), retire only if it becomes maintenance burden.

2. **PolicyContext.fields wiring under the real executor:**
   - The TS PolicyRuntime serializes fields to byte slices that the executor's OP_LOADFIELD reads. The Zig PolicyContext mirrors the TS shape (`Record<string, unknown>` → `StringHashMapUnmanaged([]const u8)`) but the executor's actual field-loading API needs to be reviewed.
   - This is a per-PR concern (resolves during PR-2 implementation), but if it turns out to be load-bearing for first-cartridge wiring, surface for design discussion before PR-2.

3. **First-consumer choice for PR-2:**
   - **cell_handler.zig** (recommended): the `opcode_bytes_b64` opt-in path already exists from §11.10 order 2d (PR #641). No current callers use it, so behavior change = zero. Lowest blast radius.
   - **intent_cells_handler.zig**: actually used in production-flavor tests; bigger blast radius if executor disagrees with shim.

4. **Test triage policy** (per R3):
   - When an existing conformance test fails because the real executor rejects a cell the shim accepted, do we (a) treat the test fixture as buggy and fix the fixture, or (b) treat the executor as buggy and surface upstream?
   - Recommendation: **case-by-case**, but bias toward (a) — most existing test fixtures predate the real executor; they're validated against the shim, not against semantic 2-PDA enforcement. The whole point of order 2e is to surface real semantic gaps.

5. **Tick scoping after the swap:**
   - PR-2 may not get to "all cartridges through real executor" in one tick. Plan for 2-4 PRs in PR-3+ category. Worth committing now, or wait until PR-2 surfaces actual gaps?

---

## Appendix — references

- `src/ffi/build.zig` — working precedent for cross-binary cell-engine consumption (embedded-profile slice; ~280 lines of inline createModules replication).
- `core/cell-engine/build.zig:createModules` — the public API that makes the brain's wiring a single call (lines 14-90 of cell-engine/build.zig).
- `core/cell-engine/src/executor.zig` — 370-line file; entry point is `pub fn execute(...)`.
- `runtime/semantos-brain/src/kernel_zig.zig` — current syntactic shim; comment lines 17-24 frame the long-standing TODO this audit resolves.
- `runtime/semantos-brain/src/policy_runtime.zig` — the seam where the backend swap lands (the `evaluate` method's backend dispatch).
