---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/TESSERA-LINEAR-CONSUME.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.742778+00:00
---

# TESSERA-LINEAR-CONSUME — kernel CONSUME semantics for tessera's
# successor verbs (rack / blend / bottle / assemble / transfer / confirm)

Status: **plan / review artifact (no code edited)**. Doc-only PR. Grounded
in `origin/main` post-#470 (P3d/e/f) and #471 (P3g — bottle multi-mint).
**No kernel change. No octave-API change. No CellStore vtable change.**

Reference:
- `docs/design/UNIVERSAL-CARTRIDGE-BOOT.md` §8 — the mint side (P3) that
  this plan extends.
- `core/cell-engine/src/opcodes/plexus.zig` — `opAssertLinear` (`0xC5`),
  `opCheckDomainFlag` (`0xC6`); both are read-only verifications, not
  state mutators.
- `cartridges/oddjobz/brain/src/state-machines/kernel-gate.ts` — the
  authoritative host-side K1 model (`ConsumedCellSet`,
  `cell_already_consumed`). The TS-FSM proves the shape; Zig adopts it.
- `proofs/lean/Semantos/Theorems/LinearityK1.lean` — substrate-level K1
  theorem (host-side enforcement of "LINEAR cells consumed at most once").
- `cartridges/oddjobz/brain/tools/gen-fsm-vectors.ts` —
  `consumedCellId` / `successorCellId` per transition (the
  audit-trail convention this plan adopts).

## 0. Headline

After #470 + #471 every tessera **successor-producing** verb mints its
produced cell(s). What it does **not** yet do is **consume the LINEAR
predecessor**: rack, blend, bottle, assemble-case, transfer-custody,
confirm-receipt all reference a prior LINEAR cell (a barrel, N input
barrels, a barrel→N bottles, N bottles→case, the custody chain) and
today the in-memory `tessera_store` is the only thing that prevents
double-spend. The plan: lift that prevention to a **substrate
UTXO-style spent set** keyed by cell-id, exactly the K1 model oddjobz
already simulates in TS. **Same risk profile as the merged P3a/b/c**
(generic seam + a boot-pass row + an additive vtable field).

## 1. Current state (verified, file:line)

- `OP_ASSERTLINEAR` is read-only — `core/cell-engine/src/opcodes/plexus.zig:189`:

  ```zig
  /// 0xC5 OP_ASSERTLINEAR
  /// Peek top cell. If linearity != LINEAR, script fails. No TRUE push
  /// — assertion only.
  ```

  The kernel does **not** mutate spent-state. K1 is a substrate-host
  obligation, exactly as `cartridges/oddjobz/brain/src/state-machines/
  kernel-gate.ts:1–38` documents:

  > "The 'real' K1/K2/K3/K4 enforcement happens in the cell-engine
  > kernel (`opAssertLinear`/`opCheckDomainFlag`). At the TypeScript-FSM
  > altitude we **simulate** those gates … `ConsumedCellSet` … in
  > production this is replaced by the cell-engine's UTXO-set lookup."

- The substrate UTXO-set lookup oddjobz hands off to **does not exist
  yet** in `runtime/semantos-brain/`. `cell_store` is intentionally
  minimal (`put` / `exists` / `cursor_*` / `count` —
  `runtime/semantos-brain/src/lmdb/cell_store.zig:39–71`). No `spend` /
  `consume` / `is_spent`.

- tessera's in-memory FSM (`cartridges/tessera/brain/tessera_store.zig`)
  enforces the equivalent invariants at the domain-id level (a barrel
  cannot be bottled twice; a bottle cannot be assembled twice). These
  domain-id rejections surface as `{ok:false,reason:"already_..."}` —
  see the existing tamper one-shot test
  (`cartridges/tessera/brain/tessera_walkers.zig:687`). The store is
  authoritative for FSM correctness; what it does **not** do is mint
  / consume substrate cells.

- Post-#470/#471, every successor verb that produces a cell **mints**
  via `settleMinted` / `settleMintedMany`. The mint records the
  successor's `cell_id`. No record is kept of which predecessor's
  `cell_id` it consumed.

## 2. The only gap

A successor `cell_id` exists in the CellStore; the predecessor `cell_id`
also exists; but **there is no substrate-level record of the
predecessor → successor consumption edge**. Three concrete consequences:

1. Two competing successors that reference the same predecessor (e.g.,
   two `bottle` verbs against the same barrel from concurrent operators)
   can both mint cells, even though the in-memory FSM only accepted
   one. The mint side has drifted from the FSM side.

2. A successor cell does not carry its **`consumed_cell_ids`** in
   audit — there is no on-cell trail back to the LINEAR predecessor
   that justified the mint.

3. There is no way to ask the substrate "is this LINEAR cell already
   spent?" — the question oddjobz's TS layer already answers with
   `ConsumedCellSet.has(cellId)` but is parked as a future "UTXO-set
   lookup" hand-off.

## 3. Design — the host-side UTXO-style spent set

### 3.1 Constraint: cells are immutable; spent-ness lives outside them

CellStore values are **fixed 1024-byte cells keyed by content hash**
(`runtime/semantos-brain/src/lmdb/cell_store.zig:1–11`). Re-writing a
cell to flip a "spent" bit would change the hash → different key →
different cell. Spent-ness therefore **must** live in a side index, not
in the cell bytes.

Oddjobz's `ConsumedCellSet` (`Set<string>`) is the same conclusion: a
side-channel set keyed by cell-id, **outside** the cell payload.

### 3.2 The SpentCellSet — one additive vtable field

Add to `CellStore.VTable` (the only kernel-edit-adjacent change):

```zig
/// Record cell_id as spent. Idempotent: spending an already-spent
/// cell is a no-op (matches the semantics oddjobz's ConsumedCellSet
/// expects of the production substrate). Returns true iff the cell
/// was newly spent (was not already in the set).
spend: *const fn (
    ctx: *anyopaque,
    cell_id: *const [32]u8,
) StoreError!bool,

/// O(1) is-spent query — the substrate equivalent of
/// `ConsumedCellSet.has(cellId)` (oddjobz/.../kernel-gate.ts:135).
is_spent: *const fn (
    ctx: *anyopaque,
    cell_id: *const [32]u8,
) bool,
```

LMDB backing: a second named sub-DB (`cells_spent`) in the same env,
keys = 32-byte cell_id, values = 1-byte sentinel. No new env, no new
allocator, no new lifetime. Mirrors the existing `attachments` /
`cells` co-tenancy in the LMDB module.

**Why a vtable field, not a parallel store:** keeps the
"is this LINEAR cell spent?" question with the cell-id store that
owns its lifetime, matching what oddjobz's TS layer expects (one
substrate that answers both "do you have it?" and "is it spent?").
Also lets the test-double `cell_store` mock spent-state when one is
introduced.

### 3.3 The domain-id → cell_id lookup (the missing index)

tessera walkers reference predecessors by **domain id** (`barrelId`,
`bottleId`, `lotId`), not by `cell_id`. To consume a predecessor, the
walker must resolve domain id → cell_id at consume time.

Two options. Both ride the mint pattern already in place — neither
needs new shared-boot-path machinery:

- **3.3a — Per-cartridge in-memory index** (preferred, smaller). When
  a successor is minted via `settleMinted{,Many}`, also record
  `(domain_id, cell_id)` in a per-cartridge map keyed by domain id.
  The map is rebuilt at boot by replaying CellStore for tessera's tag
  block (cursor + filter on type tags from `tessera_cell_specs.zig`).
  Lives in `cartridges/tessera/brain/tessera_store.zig` as a sibling
  field — greenfield-safe.

- **3.3b — Substrate secondary index keyed by cartridge tag**. A
  `cell_store.cellIdByDomainKey(tag, domain_id)` lookup. More general
  but pulls a cartridge concept (domain id) into the substrate. Reject
  unless 3.3a runs out of headroom.

The plan uses **3.3a**. The lookup is a cartridge concern and stays in
cartridges/.

### 3.4 The walker pattern — `settleMintedConsumes` / `settleConsumesOnly`

Three composable helpers; each tightens the existing `settleMinted{,
Many}` pattern with explicit predecessor consume:

```zig
/// Mint exactly one successor cell AND consume exactly one
/// LINEAR predecessor (rack, blend's primary input, bottle's barrel,
/// confirm-receipt's custody-token).
settleMintedConsumesOne(a, s, res, id_for_body, cell_name, predecessor_id,
                       predecessor_lookup_key, pj, obj) -> []u8

/// Mint N successor cells AND consume one LINEAR predecessor
/// (bottle: one barrel → N bottle cells).
settleMintedManyConsumesOne(a, s, res, id_for_body, cell_name, payloads,
                            predecessor_id, predecessor_lookup_key, pj, obj)
                            -> []u8

/// Mint one successor AND consume N LINEAR predecessors
/// (blend: N input barrels → one out barrel;
///  assemble-case: N bottles → one case).
settleMintedConsumesMany(a, s, res, id_for_body, cell_name,
                         predecessor_ids, predecessor_lookup_key,
                         pj, obj) -> []u8
```

All three:

1. Settle the in-memory store transition first (preserves today's FSM
   semantics; domain refusals still surface as `{ok:false,reason}`).
2. Resolve each `predecessor_id` via the 3.3a per-cartridge index →
   `cell_id`. Missing-id → `{ok:false,reason:"unknown_predecessor"}`.
3. Query `cell_store.is_spent(predecessor_cell_id)` for each. Already
   spent → `{ok:false,reason:"cell_already_consumed"}` (oddjobz's
   `KernelGateFailureKind` adopted verbatim — same audit string).
4. Mint successor(s) via the existing P3c encode path. Successor
   payload **includes the `consumed_cell_ids[]`** so the audit trail
   is on-cell, matching oddjobz's `gen-fsm-vectors.ts` convention
   (`consumedCellId` / `successorCellId`).
5. Persist successor(s) via `cell_store.put` (unchanged P3d path).
6. **Spend each predecessor via `cell_store.spend(predecessor_cell_id)`**.

Ordering: settle → resolve → check → mint → put → spend. **Spend is
last**, because if put fails we have not yet committed to the
consumption; if put succeeds we must spend, because the successor now
exists and is the proof of consumption.

CellStore-unbound mode (tests / dry-run, mirrors P3d):
`is_spent` returns false and `spend` is skipped; the walker still
returns `{ok:true,cellIds,persisted:false}`. The FSM remains
authoritative — same behaviour as today.

### 3.5 What changes per verb

| verb | helper | predecessor(s) | successor(s) |
|---|---|---|---|
| harvest | (unchanged — no predecessor) | — | `tessera.grape-lot` |
| rack | `…ConsumesOne` | grape-lot by `lotId` | `tessera.barrel` |
| blend | `…ConsumesMany` | N barrels by `inBarrelIds` | `tessera.barrel` |
| bottle | `…ManyConsumesOne` | barrel by `barrelId` | N `tessera.bottle` |
| assemble-case | `…ConsumesMany` | N bottles by `bottleIds` | `tessera.case` |
| open-container | (unchanged — opens, not consumes) | — | container cell |
| transfer-custody | `…ConsumesOne` (custody token) | prior custody by `id` | new custody (still TBD — see §6) |
| confirm-receipt | `…ConsumesOne` (custody-in-flight token) | in-flight by `id` | settled custody (TBD §6) |
| record-care-event | (unchanged — AFFINE, accumulates) | — | care-event |
| report-quality-issue | (unchanged — care-event-family) | — | care-event |
| thermo-flag | (unchanged — care-event-family) | — | care-event |
| tamper | (unchanged — terminal AFFINE on bottle) | — | tamper-event |
| consumer-scan | (unchanged — AFFINE) | — | scan-event |
| add-tasting-note | (unchanged — AFFINE) | — | tasting-note |

## 4. Greenfield, no kernel change, no octave change

- `OP_ASSERTLINEAR` / `OP_CHECKDOMAINFLAG` untouched. K1 is a
  host-side obligation per oddjobz's documented model.
- `cell_store.zig` gains two vtable fields (`spend`, `is_spent`) —
  generic. **No cartridge name added.** Greenfield gate holds.
- Octave: untouched. Spent-set entries are 32-byte keys; no payload
  escalation.
- All tessera-specific machinery (helpers, lookup, payload format)
  stays under `cartridges/tessera/brain/`. Greenfield grep
  `runtime/semantos-brain/src/` for `tessera` = 0.
- The CellStore test double can land alongside this — adding
  `spend`/`is_spent` to the vtable also unlocks the persist-path
  integration test that was deliberately deferred at P3d.

## 5. Phasing

Each phase independently reviewable; each preserves today's behaviour
under the entitlement gate + greenfield gate.

- **P4a — CellStore vtable + LMDB backing**. Add `spend`/`is_spent`
  fields and the `cells_spent` LMDB sub-DB. Default-false for any
  caller; cells_spent sub-DB created lazily so existing envs
  upgrade in place. Inline tests in `cell_store.zig` and the LMDB
  impl. Behaviour-identical for current callers (oddjobz, harvest's
  P3d path). Same risk profile as P3a.

- **P4b — tessera per-cartridge domain→cell_id index (3.3a)**.
  `tessera_store.zig` gains a `cell_id_by_domain_id`
  `std.StringHashMap([32]u8)` rebuilt by a CellStore cursor scan at
  boot (filtered to tessera's tag block via the SPEC registry from
  P3b). `settleMinted{,Many}` records the (domain_id, cell_id) pair
  on success. Tested in isolation; consume helpers don't ship yet.

- **P4c — consume helpers + per-verb retrofit**.
  `settleMintedConsumesOne`, `settleMintedManyConsumesOne`,
  `settleMintedConsumesMany` land with one shared test pattern
  (mint → re-attempt → `cell_already_consumed`). Then retrofit
  rack / blend / bottle / assemble-case to use them. The in-memory
  FSM continues to enforce domain-id invariants; the substrate
  spent-set now enforces the matching cell-id invariants.

- **P4d (optional, decide after P4c lands) — successor payload
  carries `consumed_cell_ids[]`** for on-cell audit trail (oddjobz
  `gen-fsm-vectors.ts` convention). Likely a small payload-shape
  bump; safe to ship after the spent set is proven.

P4a is **purely substrate**, doesn't touch tessera. P4b and P4c are
**purely tessera**, don't touch substrate. P4a is shippable
independently and unblocks oddjobz's TS `ConsumedCellSet → substrate
UTXO-set lookup` hand-off too — the value extends beyond tessera.

## 6. Out-of-scope here (named, not solved)

- **transfer-custody / confirm-receipt semantics** — the FSM today
  models these as pure state transitions on the same container cell,
  no successor minted. Whether they should mint a custody-token
  successor + consume the prior custody token (the cleanest LINEAR
  model) vs. stay as in-place state transitions (the current model)
  is a separate design call. P4c lists them with `(TBD §6)` and
  defers them until after rack/blend/bottle/assemble land.
- **Cross-cartridge consume** (e.g., paying for a tessera bottle by
  consuming an oddjobz invoice). Out of scope.
- **Spent-set crash recovery** — LMDB's transactional guarantees
  already give this for free at P4a. Documented for clarity.
- **Concurrency model** — the brain is a single-threaded reactor
  (CLAUDE.md `semantos_brain_single_threaded_reactor.md`). Two
  competing successors against the same predecessor are linearised
  by the dispatcher; the second sees the spent set already updated
  by the first.

## 7. Verification approach (mirrors P1/P2/P3)

- `cell_store.zig` inline tests: `put → is_spent=false → spend → is_spent=true →
  spend (idempotent) → is_spent=true`; cursor enumeration unaffected;
  fresh env upgrade-in-place.
- `tessera_store` inline test for the domain→cell_id index: rebuild
  at boot replays mints in order; mints landed after boot also
  appear in the index.
- `tessera_walkers` inline tests, one per verb retrofit: mint
  successor → re-attempt with same predecessor → reason
  `cell_already_consumed`. The existing tamper one-shot test is the
  shape this generalises.
- Greenfield gate (`grep -r tessera runtime/semantos-brain/src` = 0)
  after each phase. `bun tools/cartridge-manifest/generate.ts --check`.
- A new gate (deferred to P4c): `tests/gates/no-tessera-spent-leak.test.ts`
  asserting no tessera-shaped predicate seeps into `cell_store.zig` or
  any substrate file. Mirrors the existing greenfield gate's shape.

## 8. Why this is the right shape

- It **lifts** what oddjobz already simulated in TypeScript into Zig
  on the brain side, finishing the hand-off oddjobz documented.
- It is **additive** — every existing tessera mint test still passes;
  every walker still returns the same body shape; the FSM stays
  authoritative for domain-id invariants.
- It is **greenfield-safe** — substrate gains two vtable fields, no
  cartridge name; cartridge gains a per-cartridge index, no
  substrate name.
- It **rides P3** — same `settleMinted{,Many}` pattern, just with a
  consume pre-step. No new boot-path shape.
- It **closes the LINEARITY drift** — successor cell + spent
  predecessor cell together prove the consumption edge, exactly what
  `proofs/lean/Semantos/Theorems/LinearityK1.lean` already states.

Net: P4 is **feasible now, no kernel work, same risk profile as the
merged P3**. The "kernel consume" worry retires the same way the
"kernel spike" worry did at P3 (UNIVERSAL-CARTRIDGE-BOOT.md §3.6).
