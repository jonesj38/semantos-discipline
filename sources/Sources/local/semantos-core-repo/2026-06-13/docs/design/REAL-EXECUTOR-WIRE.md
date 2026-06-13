---
slug: real-executor-wire
track: C10 — Real Kernel Executor (PR-2b consumer rollout)
status: LANDED — A/B/C code-side flips merged 2026-05-28; D/E (deploy) pending operator action
date: 2026-05-28 (revised 2026-05-31 — status flipped post-merge)
supersedes: nothing (new doc for the canonicalization track)
master_design: docs/prd/POLICY-RUNTIME-EXECUTOR-ADAPTER.md (the adapter itself)
roadmap: docs/prd/UNIFICATION-ROADMAP.md §11.10 order 2e PR-2c+PR-2d
matrix: docs/canon/canonicalization-matrix.yml C10
brief: docs/prd/CANONICALIZATION-BRIEF.md §8.2 cross-brain substrate coordination
---

# C10 — Real-executor wire: the consumer-rollout doc

## TL;DR

The PolicyRuntime → cell-engine 2-PDA executor adapter is **already implemented**
(`evaluateReal` in `runtime/semantos-brain/src/policy_runtime.zig` shipped via
PR-2a + PR-2b; six inline tests green). The seam is no longer the blocker.

C10 is **consumer rollout** — flipping the brain handlers that today either
default to `.syntactic_shim` or skip PolicyRuntime entirely so that cells are
gated by *actual* deterministic 2-PDA execution before they reach LMDB.

There are exactly **two flips** plus **one new wire-in** plus **one canary
deploy step**:

| Step | What | File | Status |
|------|------|------|--------|
| **A** | Flip `cell_handler` → `.real_executor` | `runtime/semantos-brain/src/cell_handler.zig:192` | ✓ landed 2026-05-28 (PR-2c, commit `2ee55ca`) |
| **B** | Wire `cells_mint_handler` through PolicyRuntime | `runtime/semantos-brain/src/cells_mint_handler.zig` | ✓ landed 2026-05-28 (PR-2d, commit `d7c61c4`) |
| **C** | Make `.real_executor` the `init()` default | `runtime/semantos-brain/src/policy_runtime.zig:196` | ✓ landed 2026-05-28 (PR-2e, commit `2c94428`) |
| **D** | Canary deploy on Todd's brain (oddjobtodd.info) | systemd drop-in | TODO (operator-side) |
| **E** | Bridget-brain coordination (utxoengineer.com) | shared substrate; same binary | TODO (operator-side) |

A/B/C landed in three commits on 2026-05-28 (see canon-matrix
`D-CANON-C10-A/B/C`). "Cells are legitimate" is now the binary's
default behaviour — any caller of `PolicyRuntime.init()` gets the
real-executor backend; the syntactic shim is fallback-only via
`initWithMode(allocator, .syntactic_shim)`.

D/E are deployment activities (systemd canary on rbs + Bridget
federation coordination), not code-side work — tracked separately
in the operator runbook. V2 anchor can resume per the C10 → V2
sequence in `docs/canon/canonicalization-matrix.yml`.

---

## 1. What already shipped (so the doc doesn't claim new substrate work)

Surveyed 2026-05-28 in this worktree (`canon/c0-foundation`). Two
items in this section have been overtaken by the A/B/C landings —
inline annotations note where.

- `runtime/semantos-brain/src/policy_runtime.zig`
  - `PolicyRuntimeMode { syntactic_shim, real_executor }` enum live (line 84).
  - `init(allocator)` defaults to `.syntactic_shim` (line 196, backward-compat).
    **— C10-C: this defaulted-to-shim line was flipped to `.real_executor` on
    2026-05-28 (commit `2c94428`); shim stays callable via `initWithMode`.**
  - `initWithMode(allocator, mode)` lets consumers opt in (line 200).
  - `evaluateReal` fully implemented (lines 280–345) — per-call heap-allocated
    `pda_mod.PDA` via `initInPlace(MAX_OPS_PER_EVAL=500_000)`, 64 KB
    `allocator_mod.ScriptArena`, all-lock `loadScript`, `executor.execute(&ctx)`,
    `@errorName(err)` → `rejection_code` token mapping, `pda.opcount` → `gas`.
  - Phase 1 limits per adapter §2 D3: `tx_context = null`, `context.fields`
    ignored — handlers thread `PolicyContext` through unchanged for Phase 2.
  - Six inline tests cover: accept / verify_failed / invalid_pushdata wire-compat
    / script_too_large / backend isolation / Rúnar-compiled `Always` predicate
    (lines 437–620). All green per `zig build test -j1 --summary all`.

- `runtime/semantos-brain/src/resources/intent_cells_handler.zig:375` — already
  on `.real_executor` (the first-consumer flip from adapter §6 #4 landed).

- `runtime/semantos-brain/src/cell_handler.zig:192` — **C10-A landed
  2026-05-28 (commit `2ee55ca`)**. Now reads
  `PolicyRuntime.initWithMode(allocator, .real_executor)`. The
  opcode_bytes_b64 precondition gate executes through the cell-engine
  2-PDA executor; behaviour-equivalent fallback to `.syntactic_shim`
  preserved via initWithMode for tests that need it.

- `runtime/semantos-brain/src/cells_mint_handler.zig` — **C10-B landed
  2026-05-28 (commit `d7c61c4`)**. Now imports `policy_runtime` and
  evaluates `opcode_bytes_b64` from the mint envelope through
  `.real_executor` (lines ~187-225). Default-permit when absent so
  existing PWA clients (BrainHttpClient.mintCell) keep working
  unchanged; cartridges that want precondition enforcement supply
  opcode bytes via the mint envelope.

- `core/cell-engine/src/opcodes/plexus.zig` — the precondition opcode family
  is fully implemented in the executor:
  - `0xC0 OP_CHECKLINEARTYPE` — linearity (one-use cells)
  - `0xC1 OP_CHECKAFFINETYPE` — affine (drop-or-use)
  - `0xC2 OP_CHECKRELEVANTTYPE` — must-use
  - `0xC3 OP_CHECKCAPABILITY` — capability bit match
  - `0xC4 OP_CHECKIDENTITY` — cert-id match
  - `0xC6 OP_CHECKDOMAINFLAG` — domain-axis discriminator
  - `0xC7 OP_CHECKTYPEHASH` — typeHash equality
  - `0xCC OP_READPAYLOAD` — read payload region (Phase 2 host-context)
  - `0xC5 OP_ASSERTLINEAR` — assert linearity in flight

  Consumers can author preconditions today; Phase 2 is the payload-context
  wiring (out of scope for C10).

**What this means for the canon track**: C10 stops being "PR-2b implementation"
(done) and becomes "make `.real_executor` the brain's default execution mode
for cell writes." That's a smaller, more reviewable change set.

---

## 2. The two flips + one wire-in (PR sequencing)

### PR-2c — Flip `cell_handler.zig` to `.real_executor`

**Scope**: 1-line change + 1 test update.

```diff
- var rt = policy_runtime.PolicyRuntime.init(allocator);
+ var rt = policy_runtime.PolicyRuntime.initWithMode(allocator, .real_executor);
```

**Tests affected**:
- `cell_handler.zig:513` — `test "writeRejection: emits {ok:false, error, hint}
  for policy_runtime path"` already asserts the rejection envelope, not the
  backend. Should pass under `.real_executor` if the fixture script lands in
  `verify_failed`. **Triage per-failure per audit §5 R3 policy** (per adapter
  §4): if the test stops failing-as-expected because the real executor accepts
  a script the shim rejected, the FIXTURE is wrong, not the swap.
- Add 1 positive smoke: `cell.create` with `opcode_bytes_b64` of `0x51` (OP_1)
  → ok=true cell persisted.

**Risk**: Today's `cell.create` consumers don't supply `opcode_bytes_b64` (it's
optional). The flip changes behavior **only** for callers that opt in. Low
blast radius.

**Matrix cell delta**: `C10-A executor seam → real` flips from `⚠` (PR-2a
landed) to `✓` for cell_handler. (Already `✓` for intent_cells_handler.)

### PR-2d — Wire `cells_mint_handler.zig` through PolicyRuntime

**Scope**: new field on `RequestEnvelope`, ~30 LOC handler change, 3 tests.

`cells_mint_http.zig` parses requests with `ignore_unknown_fields: true`, so
adding `opcode_bytes_b64: ?[]const u8 = null` to `RequestEnvelope` is
non-breaking — existing PWA clients sending `{typeHashHex, payload}` keep
working with no precondition (default-permit on this endpoint).

The wire-in in `cells_mint_handler.zig` mirrors `cell_handler.zig:187–212`:

```zig
if (envelope.opcode_bytes_b64) |b64| {
    const decoded = decodeBase64(allocator, b64) catch
        return writeRejection(allocator, "invalid_args", ...);
    defer allocator.free(decoded);

    var rt = policy_runtime.PolicyRuntime.initWithMode(allocator, .real_executor);
    const policy_ctx = policy_runtime.PolicyContext{
        .actor = .{ .cert_id = cert_id_from_bearer, .capabilities = caps },
        .co_actor = null,
    };
    const r = rt.evaluate(decoded, policy_ctx) catch
        return writeRejection(allocator, "kernel_local_exec_failed", ...);
    if (!r.ok) return writeRejection(allocator, "kernel_rejected_locally", r.rejection_code);
}
// existing mint path (validate → encode → put → emit anchor event) unchanged
```

**Why this matters for canon**: the PWA's `BrainHttpClient.mintCell` hits
`POST /api/v1/cells` (per `apps/semantos/lib/src/brain/brain_http_client.dart`).
That's the canonical mint path for self / oddjobz releases. Without C10-B,
the V1 slice we just shipped mints cells the kernel never inspects. With
C10-B, cartridges can declare per-verb opcode preconditions in their
manifests and the brain enforces them at write time — the actual point of
"cells are legitimate."

**Cartridge manifest contract** (separate doc, but flagged here):
`cartridges/<id>/cartridge.json` already has per-verb metadata. Adding
`precondition_opcodes_b64: "..."` per verb is the canonical authorship
surface. PR-2d does NOT load preconditions from the manifest — that's the
cartridge-loader's job. PR-2d just makes the seam exist so manifests can
opt in.

**Matrix cell delta**: NEW row needed. Add `C10-B mint seam → policy_runtime`
to `docs/canon/canonicalization-matrix.yml` (axis: "kernel enforcement"; cell:
B). Starts ✗, lands ⚠ on PR-2d, ✓ after first cartridge-manifest-driven
precondition reject in production.

### PR-2e — Switch `init()` default to `.real_executor`

**Scope**: 1-line change + delete the backward-compat seam.

```diff
 pub fn init(allocator: std.mem.Allocator) PolicyRuntime {
-    return .{ .allocator = allocator, .mode = .syntactic_shim };
+    return .{ .allocator = allocator, .mode = .real_executor };
 }
```

**Why last**: PR-2c and PR-2d migrate the two known call sites explicitly.
PR-2e catches any *unknown* consumers (REPL smokes, future cartridge handlers,
test helpers) and makes "if you call `init`, you get real semantics." The
syntactic shim stays callable via `.initWithMode(allocator, .syntactic_shim)`
for one release as the fallback per adapter §7.

**Acceptance**: full `zig build test -j1 --summary all` passes with no
`@errorName` token drift in tests that previously relied on shim-only error
strings.

---

## 3. Acceptance — the testable wow-moments

Per CANONICALIZATION-BRIEF.md §8.2, C10 has two named wow-moments. Translating
each into a concrete fixture:

### Wow-1: Bridget's FundRelease purpose-mismatch rejected

The bridge cell-handler scenario: a "FundRelease" cell must carry a
`capability_bit = FUND_RELEASE_AUTHORITY (0x04)` in the actor's cert. A cell
carrying purpose=`FUND_RELEASE` with actor capabilities `[0x01, 0x02]`
(missing 0x04) gets rejected by `OP_CHECKCAPABILITY` (0xC3) before LMDB
persistence.

**Fixture path**: `tests/canonicalization/c10/fund_release_purpose_mismatch.fixture.json`
- input: `{cell_payload: <FundRelease bytes>, opcode_bytes_b64: <pushdata 0x04 OP_CHECKCAPABILITY>, actor_caps: [0x01, 0x02]}`
- expected: `{ok: false, error: "kernel_rejected_locally", hint: "verify_failed"}`

**Note**: Phase 1 of `evaluateReal` ignores `context.fields` (adapter §2 D3),
so this fixture exercises a SHIM-level pre-execution check, not the real
OP_CHECKCAPABILITY runtime. The fixture STAYS GREEN as Phase 2 lands payload-
context wiring (the wire shape doesn't change; the enforcement layer
deepens). Document this as a Phase 1 limitation in the fixture's `_meta`.

### Wow-2: Todd's anchor-of-anchor loop rejected

The anchor cell carries `linearity = LINEAR (one-use)`. An attempt to anchor
an already-anchored cell (i.e., the source cell's `OP_CHECKLINEARTYPE` (0xC0)
fails because it's been consumed once) gets rejected at the brain mint
boundary.

**Fixture path**: `tests/canonicalization/c10/anchor_of_anchor_loop.fixture.json`
- step 1: mint cell A with linearity=LINEAR, opcode_bytes_b64=`<0xC0 LINEAR>`
  → ok=true, cellId_A returned.
- step 2: mint anchor cell B carrying cellId_A in payload, same precondition
  → ok=true, cellId_B returned, source A marked consumed.
- step 3: mint anchor cell C ALSO carrying cellId_A
  → ok=false, error="kernel_rejected_locally", hint="verify_failed"
  (OP_CHECKLINEARTYPE sees A already consumed).

**Same Phase 1 caveat**: payload-context wiring needed for the full check.
Phase 1 fixture asserts the precondition stream EXECUTES; Phase 2 fixture
will assert it REJECTS for the right semantic reason.

---

## 4. Cross-brain coordination (Bridget's brain + Todd's brain)

Per CANONICALIZATION-BRIEF.md §8.2 and the memory `bridget_federation_ready`:
Bridget runs the **same** `semantos-brain` binary at brain.utxoengineer.com.
There are NOT two codebases. The "cross-brain" framing means **both production
brains absorb the same upgrade** when PR-2c / PR-2d / PR-2e land on main.

**Deploy order** (low-risk):

1. **Land PR-2c / PR-2d / PR-2e on `main`.** All tests green locally + CI.
2. **Build `brain` binary** (per `cli/build.zig`).
3. **Canary on Todd's brain** (`oddjobtodd.info`): `scp` binary to `/opt/semantos/brain`
   via `ssh rbs`; restart `semantos-brain.service`; mint a self.practice.release
   cell with `opcode_bytes_b64 = <0x51>` (OP_1, trivially-true precondition)
   from the canonical PWA → cell persists. Soak for 24 h.
4. **Roll to Bridget** (`brain.utxoengineer.com`): same binary, same deploy
   path (Bridget runs identical systemd layout per the federation-ready
   memory). Coordinate on the brain-to-brain test window already in the
   memory (`Pick a time-zone window when both online`).
5. **Mint first cross-brain-witnessed kernel-rejected cell**: Bridget mints a
   FundRelease with intentionally-wrong actor capabilities; both brains' logs
   show `kernel_rejected_locally` on the federation gossip. **This is the
   canon proof point** — same wire, same rejection, both brains.

**Risk**: if either brain blocks (e.g., a real cartridge in production was
relying on shim-only error strings), `.initWithMode(allocator, .syntactic_shim)`
is the per-call escape hatch (adapter §7 explicit fallback). PR-2e doesn't
remove the shim; it just flips the default.

---

## 5. Matrix deltas (apply to `docs/canon/canonicalization-matrix.yml` C10)

| Axis | Cell before | Cell after PR-2c | After PR-2d | After PR-2e + canary |
|------|-------------|------------------|-------------|----------------------|
| C10-A executor seam | ⚠ (PR-2b landed) | ✓ (cell_handler on real) | ✓ | ✓ |
| C10-B mint enforcement | ✗ (not wired) | ✗ | ⚠ (seam present, no manifest preconditions) | ⚠ |
| C10-C default mode | ✗ (shim default) | ✗ | ✗ | ✓ |
| C10-D Todd canary | ✗ | ✗ | ✗ | ✓ |
| C10-E Bridget rollout | ✗ | ✗ | ✗ | ⚠ (deploy done, awaiting cross-brain reject proof) |

Final ✓ on C10-E comes from the cross-brain witnessed reject in §4 step 5.

---

## 6. Out of scope (named so it doesn't scope-creep)

- **Phase 2 payload-context wiring** — `OP_READPAYLOAD` host-context + `tx_context`
  for `OP_CHECKSIG` (adapter §2 D3 Phase 2). Lands when V2 anchor needs sighash
  semantics, not before.
- **Cartridge-manifest precondition loader** — `cartridges/<id>/cartridge.json`
  per-verb `precondition_opcodes_b64`. Separate PR; out of C10.
- **HostCallRecord audit trail** — `OP_CALLHOST` capture per adapter §7.
- **Per-PolicyRuntime PDA pool** — hot-path optimization; defer until a hot
  path emerges.
- **Retiring `kernel_zig.zig`** — explicit fallback per adapter §7; stays
  callable via `.initWithMode(allocator, .syntactic_shim)`.

---

## 7. Why this gates V2 anchor (per Todd 2026-05-28)

> "We shouldn't focus on anchoring until the cells are legitimate, then return
> to v2 slice."

The V2 anchor pipeline (sync path: `buildAnchorTx` + `headless-wallet.sendPushdrop`
per `docs/canon/canonicalization-v2-anchor-survey.md` revised) commits a cell
to BSV mainnet at ~$0.0001 per anchor. Today, that cell was admitted by the
brain through a *frame validator* (the syntactic shim's job: well-formed
pushdata, balanced control flow). It was NOT admitted by an *enforcer* (the
real 2-PDA executing the cell's declared preconditions).

Anchoring a frame-valid-but-semantically-broken cell makes the chain a
permanent record of brain failure. C10 closes that gap: when V2 resumes,
every anchored cell will have passed the same deterministic 2-PDA that
Wright's *Scripted Supply* frames as the precondition layer (adapter §0 #2).

C10 ✓ → V2 unblock criterion met.

---

## 8. The /loop-able tick list

Each is small enough for one /loop tick:

1. ✓ PR-2c: flip cell_handler line 192, add 1 smoke test, run `zig build test`
   — landed 2026-05-28 (commit `2ee55ca`).
2. ✓ PR-2d: extend `cells_mint_handler.RequestEnvelope`, mirror cell_handler's
   gate block, 3 tests (well-formed accept / opcode missing-permit / explicit
   reject) — landed 2026-05-28 (commit `d7c61c4`).
3. ✓ PR-2e: flip `init()` default, run full test suite, triage drift —
   landed 2026-05-28 (commit `2c94428`).
4. Fixture C10-Wow-1 (FundRelease purpose-mismatch) — JSON + Zig harness (~1 h).
5. Fixture C10-Wow-2 (anchor-of-anchor loop) — JSON + Zig harness (~2 h).
6. Build binary, scp to `ssh rbs`, restart service, smoke from PWA (~30 min).
7. Schedule Bridget cross-brain reject witnessing (async, coordinate via memory
   `bridget_federation_ready`).

Items 1–3 (the code-side flips) landed in three commits on 2026-05-28.
Items 4–7 are still open: 4–5 are conformance fixtures (good to have
but not blocking); 6 is the canary-deploy item D from the TL;DR table;
7 is the federation item E.

---

**Doc owner**: this worktree (`canon/c0-foundation`).
**Status (2026-05-31)**: A/B/C code-side flips merged. Remaining work
is operator-side (canary deploy + Bridget federation coordination) +
the two optional conformance fixtures (C10-Wow-1, C10-Wow-2).
