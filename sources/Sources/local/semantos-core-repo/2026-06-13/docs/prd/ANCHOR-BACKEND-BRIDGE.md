---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/ANCHOR-BACKEND-BRIDGE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.685152+00:00
---

# Anchor backend bridge — brain → wallet-headers cartridge

**Version**: 0.1 (design)
**Date**: 2026-05-25
**Status**: DESIGN — gates §11.10 order 3a step 3 (task #16) — real anchor backend
**Master document**: [`UNIFICATION-ROADMAP.md` §11.10 v0.12](UNIFICATION-ROADMAP.md)
**Sister docs**:
- [`POLICY-RUNTIME-EXECUTOR-ADAPTER.md`](POLICY-RUNTIME-EXECUTOR-ADAPTER.md) — predicate-execution seam (PR-2a/2b)
- [`D-LIFT-BSV-ANCHOR.md`](D-LIFT-BSV-ANCHOR.md) — BSV cartridge carve
- [`CELL-SIGNER-SEAM`] — cell-signing brain primitive (PR-4a)

---

## Headline (TL;DR)

The brain's [`anchor_emitter.zig`](../../runtime/semantos-brain/src/anchor_emitter.zig) seam exists with two backends: `.stub` (synthesised txid; what `cell_handler.zig` + `intent_cells_handler.zig` call today) and `.bsv` (returns `bsv_backend_not_wired`). This doc designs the `.bsv` backend as an event-bus async bridge to `cartridges/wallet-headers`, completing Todd 2026-05-25's "every cell write triggers an anchor" directive and closing Bridget Doran's L3-unwired review item.

**Transport recommendation (matches §11.10 order 3a row)**: brain emits `cell.created` event on the existing `helm_event_broker` after every successful cell write. Wallet-headers cartridge subscribes; mints the AnchorAttestation cell, broadcasts the BSV tx via ARC, persists the attestation back through `cell.create`. Anchoring is eventually-consistent — cell writes don't block on tx confirmation.

**Three-PR sequence (in order of dependency)**:

| PR | Scope | Effort |
|---|---|---|
| **PR-3a-bridge-1** | Define event-bus contract + brain-side `emitBsv` publishes `cell.created` | ~half day |
| **PR-3a-bridge-2** | Wallet-headers subscriber: mint AnchorAttestation + broadcast tx | ~2 days |
| **PR-3a-bridge-3** | Confirmation feedback: `anchor.confirmed` event → brain audit-log update | ~1 day |

---

## §0 Why this work matters (Wright frame + Runar frame)

Two adjacent theoretical anchors:

**Craig Wright, *Scripted Supply* (PR-2 frame)**: state transitions are proofs, not RPC calls. A cell write becomes an *admissible* state transition the moment the predicate (PolicyRuntime) accepts it. PR-2b made the brain enforce that predicate in a deterministic 2-PDA. But predicates are off-chain proofs until they're anchored — without §3 ("state transitions are proofs"), the predicate is just internal accounting. This PR closes that loop: every accepted cell becomes an on-chain commitment.

**Runar (runar.build)**: per the [Runar overview](https://runar.build/docs/getting-started/overview/), Runar is a *smart-contract compiler* — mainstream-language source (TS / Go / Rust / Python / Zig / Ruby / Solidity / Move) compiles to Bitcoin Script for BSV deployment. Its `StatefulSmartContract` model uses the OP_PUSH_TX pattern to thread state across UTXOs. This is *structurally the same architecture* the anchor backend needs:

- An AnchorAttestation cell's BSV tx is a `StatefulSmartContract`-shaped UTXO whose lock script commits to `cell_hash` + `type_hash` + `domain_flag`.
- Spending that UTXO (e.g., to demote a LINEAR cell) is the on-chain act of consuming the cell. `cell-anchor.ts` in `cartridges/wallet-headers/brain/src/` already implements this — `deriveCellAnchorSk` derives the spending key from the type_hash via BRC-42.
- The deterministic-compilation property Runar guarantees ("same source → byte-identical script") is what makes cross-language conformance work — same property our cross-language fixtures (e.g. `intent_cell_envelope_fixture.json`) depend on for parity between Dart mobile + Zig brain.

**Runar as future integration point (NOT in scope for this PR)**:

1. **Anchor lock script compilation**: today `cartridges/wallet-headers/brain/src/cell-anchor.ts` hand-writes the anchor lock script as a sequence of opcode bytes. A future cartridge could author the same script as Runar source (Zig or TypeScript) and let Runar emit the bytes — gaining cross-language conformance.
2. **Cartridge precondition policies**: today cartridges hand-emit opcode bytes for the PolicyRuntime to evaluate. A cartridge author could write the precondition as Runar source. The brain's `evaluateReal` (PR-2b) accepts opaque opcode bytes — it doesn't care whether they came from Runar, hand-written, or another compiler.
3. **Conformance pattern parallel**: Runar runs the same source through 6 language frontends + checks byte-identical output. Our cross-language fixtures (Dart + Zig agreeing on envelope decode) are the same shape at smaller scale. As more languages join the brain's cartridge surface, Runar's conformance discipline is the model to emulate.

Neither is on the critical path for #16 — flagged for the unification roadmap once the bridge works end-to-end. Tracking note added to §11.10.

---

## §1 Current state

**Already shipped (orders 14 + 15)**:

- `runtime/semantos-brain/src/anchor_emitter.zig` — the seam with `.stub` + `.bsv` modes
- `cell_handler.zig:201` — calls `anchor_emitter.AnchorEmitter.init(self.allocator, .stub)` after every successful generic `cell.create`
- `resources/intent_cells_handler.zig:446` — same pattern after every intent_cells.submit
- `intent_cell_lmdb_store.zig` — store layer references the layout AnchorEmitter expects
- Recursion break wired: `ANCHOR_ATTESTATION_ENTITY_TAG = 0x20` short-circuits with `status=.skipped`
- Inline tests covering stub determinism + recursion break

**Already shipped on the cartridge side**:

- `cartridges/wallet-headers/brain/src/cell-anchor.ts` — `anchorProtocolHash`, `domainFlagFromTypeHash`, `buildSchemaMapping`, `deriveCellAnchorSk`, `buildCellAnchorLock` — the wallet-side primitives for anchor-UTXO derivation + lock-script construction
- `cartridges/wallet-headers/brain/src/dispatcher.ts` — BRC-100 method dispatcher with `createAction` (select UTXOs, sign, broadcast to ARC)
- `cartridges/wallet-headers/brain/src/arc-broadcast.ts` — ARC broadcast adapter
- `core/anchor-attestation/src/operations.ts` — `AnchorAttestation` cell schema (`buildAnchorAttestation`, etc.)
- `cartridges/bsv-anchor-bundle/brain/zig/` — header sync / store / payment ledger (Zig side of the wallet bundle)
- Memory `mnca_anchor_onchain_mainnet` proves the recipe end-to-end on mainnet: BRC-42 edge keys → buildAnchorTx PushDrop (cell OP_DROP leafPk OP_CHECKSIG) → BEEF v1 → ARC `/v1/tx` → txid. Reuse verbatim.

**What's missing (this PR's scope)**:

- `emitBsv` in `anchor_emitter.zig` doesn't publish to `helm_event_broker` — returns `bsv_backend_not_wired`
- Wallet-headers has no subscriber wired to `cell.created` events
- No confirmation-feedback path from broadcast success back to the brain's audit log

---

## §2 Transport — event-bus async (recommended)

Three alternatives were considered in `UNIFICATION-ROADMAP.md §11.10` order 3a row:

1. **Event-bus async** — `helm_event_broker` publish; wallet subscribes. ✓ RECOMMENDED.
2. **Synchronous HTTP** — brain blocks until wallet returns txid. Slow + bad for write throughput; couples brain liveness to wallet liveness.
3. **In-process Zig FFI** — brain links lifted Zig wallet code directly. Tight coupling against the cartridge boundary we just established (§11.10 order 3).

Event-bus async wins because:

- **Cartridge boundary stays clean** — the brain emits a typed event; the wallet decides what to do. Same shape as `job.transitioned` / `lead.created` events already on the broker.
- **Eventual consistency is correct** — a cell-write succeeding is a brain-local invariant; on-chain confirmation lands later. Cell writes don't fail because the wallet is busy or BSV mempool is congested.
- **Wallet-headers can already do the work** — `dispatcher.ts createAction` exists; we're wiring an event to invoke it.
- **Failure surface is observable** — broker subscribers that fail emit their own audit events; the brain's caller never sees a half-broadcast tx.

**Wire shape (event payload)**:

```json
{
  "cell_hash": "<64-hex SHA-256 of the 1024-byte cell>",
  "entity_tag": <u32 — the cell's type discriminator>,
  "type_hash": "<64-hex — the canonical typeHash for anchor key derivation>",
  "cartridge_id": "<short string — 'oddjobz', 'jambox', etc. — routing hint>",
  "correlation_id": "<uuid — trace threading>",
  "created_at": "<ISO-8601 — when the brain accepted the cell>"
}
```

Event type token: `"cell.created"` (broker constant). `requires_operator_attention` stays `false` — operator doesn't get a push notification for routine anchoring.

`type_hash` is added vs. today's `AnchorContext` because the wallet needs it to derive the anchor protocolHash (`cell-anchor.ts anchorProtocolHash`). The brain has `entity_tag` already; `type_hash` comes from the canonical cell header (PR-2b decommissioned `entity_cell`; `substrate_entity.zig` carries the spec).

---

## §3 emitBsv implementation (PR-3a-bridge-1)

Replace `anchor_emitter.zig emitBsv` placeholder with a real publish:

```zig
fn emitBsv(self: *AnchorEmitter, context: AnchorContext) AnchorResult {
    // The broker is wired into AnchorEmitter at construction; .bsv mode
    // requires it. The seam's init signature grows a broker pointer for
    // .bsv backers — .stub callers can keep passing null.
    const broker = self.broker orelse return .{
        .enqueued = false,
        .status = .failed,
        .error_kind = "broker_not_configured",
    };

    // Format the event payload — same buffer pattern as job.transitioned
    // emit sites (helm_event_broker.zig §92 example).
    var payload_buf: [512]u8 = undefined;
    const payload_json = std.fmt.bufPrint(&payload_buf,
        \\{{"cell_hash":"{s}","entity_tag":{},"type_hash":"{s}","cartridge_id":"{s}","correlation_id":"{s}"}}
    , .{
        std.fmt.fmtSliceHexLower(&context.cell_hash),
        context.entity_tag,
        std.fmt.fmtSliceHexLower(&context.type_hash),
        context.cartridge_id orelse "",
        context.correlation_id orelse "",
    }) catch return .{
        .enqueued = false,
        .status = .failed,
        .error_kind = "payload_overflow",
    };

    broker.publish(.{
        .type = "cell.created",
        .payload_json = payload_json,
    }) catch return .{
        .enqueued = false,
        .status = .failed,
        .error_kind = "broker_publish_failed",
    };

    return .{
        .enqueued = true,
        .status = .pending,
        // No txid yet — wallet emits "anchor.confirmed" with the txid
        // once broadcast completes (PR-3a-bridge-3).
    };
}
```

**AnchorEmitter struct changes**:
- New `broker: ?*helm_event_broker.Broker` field; only required in `.bsv` mode
- `init(allocator, mode)` stays; new `initWithBroker(allocator, mode, broker)` for `.bsv` callers
- `.stub` mode unchanged (broker stays null; tests don't need broker boot)

**AnchorContext additions**:
- `type_hash: [32]u8` — added so the wallet doesn't need to look it up from cell storage

**Call-site changes**:
- `cell_handler.zig:201` and `intent_cells_handler.zig:446` keep `.stub` for tests; production paths (cli/serve.zig boot) construct with `.bsv` + the brain's broker handle

---

## §4 Wallet-headers subscriber (PR-3a-bridge-2)

The wallet-headers cartridge already has the primitives — what's missing is the bridge from the broker to those primitives.

Today the cartridge is a TS package consumed by external tooling (the BRC-100 wallet popup, the chess-brain-proxy chain). It doesn't currently run inside the brain process. Two integration shapes:

**Option A: In-brain TS runner** — the brain spawns a `bun` child that subscribes to the broker (via the existing detached-grandchild pattern per memory `semantos_brain_single_threaded_reactor`) and runs the wallet-headers cartridge in-process. The child calls `createAction` for each `cell.created` event.

**Option B: HTTP poll** — an external wallet daemon polls a new `/api/v1/anchor-queue` endpoint on the brain. Tighter cartridge isolation, but reintroduces the synchronous-HTTP problem #2 said we wanted to avoid.

**Recommendation: Option A** — matches the existing pattern (voice notes, oddjobz cmds, etc. all use detached-bun-children). Concretely:

```typescript
// cartridges/wallet-headers/brain/src/anchor-subscriber.ts (NEW)
import { dispatchAction } from './dispatcher';
import { buildCellAnchorLock, deriveCellAnchorSk } from './cell-anchor';
import { buildAnchorAttestation } from '@semantos/anchor-attestation';

export async function handleCellCreated(event: CellCreatedEvent): Promise<void> {
  // 1. Derive anchor key from event.type_hash (BRC-42 via deriveCellAnchorSk).
  const sk = deriveCellAnchorSk(event.type_hash);

  // 2. Build the anchor lock script (commits to cell_hash + type_hash).
  const lock = buildCellAnchorLock(sk.publicKey, event.cell_hash, event.type_hash);

  // 3. Build the BSV tx via dispatcher.createAction.
  const tx = await dispatchAction({
    method: 'createAction',
    params: {
      description: `anchor:${event.entity_tag}:${event.cartridge_id}`,
      outputs: [{ satoshis: 1, lockingScript: lock }],
    },
  });

  // 4. Mint the AnchorAttestation cell via the brain's cell.create dispatch.
  const attestation = buildAnchorAttestation({
    targetCellId: event.cell_hash,
    txid: tx.txid,
    broadcastAt: new Date().toISOString(),
  });
  await postBrainCellCreate(attestation);

  // 5. Emit "anchor.confirmed" back through the broker (PR-3a-bridge-3).
  await postBrainEvent({
    type: 'anchor.confirmed',
    payload: { cell_hash: event.cell_hash, txid: tx.txid },
  });
}
```

**Brain-side subscriber binding**: in `cli/serve.zig` after broker construction, register a subscriber whose callback forwards `cell.created` events to the bun child over its stdin (or a fifo). Same pattern as the voice-note submitter (per memory `semantos_brain_single_threaded_reactor`).

**Recursion break (cartridge side)**: subscriber MUST filter `event.entity_tag != ANCHOR_ATTESTATION_ENTITY_TAG` before invoking step 4. Two guards (brain-side in `emit()`, cartridge-side in handler) is belt + suspenders against schema drift.

---

## §5 Confirmation feedback (PR-3a-bridge-3)

Currently `AnchorResult.status` returns `.pending` immediately. The wallet eventually broadcasts; the txid comes back via `anchor.confirmed` event. The brain needs to:

1. Subscribe to `anchor.confirmed` on its own broker (handler in `runtime/semantos-brain/src/anchor_confirmer.zig` NEW)
2. Persist (`cell_hash` → `txid`) mapping in the cell store metadata
3. Update audit log with the confirm transition

**Audit log entry**:
```json
{
  "type": "anchor.confirmed",
  "cell_hash": "<hex>",
  "txid": "<hex>",
  "broadcast_at": "<iso>",
  "confirmed_at": "<iso>"
}
```

**Failure path**: if the cartridge's broadcast fails (ARC reject, network timeout), it emits `anchor.failed` with `error_kind`. Brain logs but doesn't roll back the cell write (anchoring is eventually-consistent; a re-anchor sweep job can pick up failed cells later).

**Reconciliation pass (future, not PR-3a-bridge-3 scope)**: a periodic worker scans cells with no `txid` and `created_at > now - 24h` and re-enqueues them. Out of scope here.

---

## §6 Recursion break (already done) + double-anchor protection

**Recursion break** is wired in `anchor_emitter.zig`: an AnchorAttestation cell carries `entity_tag = 0x20`; `emit()` short-circuits with `.skipped`. Belt+suspenders cartridge-side filter recommended in §4.

**Double-anchor protection** — what stops the wallet from broadcasting twice for the same cell?

- **Cartridge idempotency key** = `cell_hash`. The cartridge's queue keys on this. A duplicate `cell.created` event for an already-anchored cell short-circuits.
- **BRC-42 derivation determinism** = `deriveCellAnchorSk(type_hash)` is deterministic. If two threads race to broadcast for the same cell, they produce identical lock scripts; the second broadcast is a UTXO conflict at ARC level (idempotent: second submission returns the same txid or "already-broadcast" sentinel).
- **At-most-once guarantee** is therefore: broker + cartridge queue + ARC-side dedup. None of those alone is sufficient; combined they reduce dup-anchor probability to "extremely rare" without a distributed commit protocol.

---

## §7 Test strategy

**PR-3a-bridge-1 (Zig brain side)**:
- `emitBsv` with broker but recursion-break entity_tag → `.skipped`, no publish
- `emitBsv` with broker + non-anchor entity_tag → publish observed; `.pending` returned with no txid
- `emitBsv` without broker (`.bsv` mode + null broker) → `.failed / broker_not_configured`
- `emitBsv` with overflow-sized event payload → `.failed / payload_overflow`
- Broker publish failure (forced via test-only broker mock) → `.failed / broker_publish_failed`

**PR-3a-bridge-2 (cartridge side)**:
- TS unit tests for `handleCellCreated`: well-formed event → `dispatchAction` invoked with correct lock script + output value
- Filter test: `entity_tag = ANCHOR_ATTESTATION_ENTITY_TAG` → no action taken
- Cross-cartridge: oddjobz cell + jambox cell → both anchored under their own `type_hash`-derived keys (proves cell-anchor.ts derivation is cartridge-specific not brain-shared)

**PR-3a-bridge-3 (round-trip)**:
- End-to-end smoke: cell.create → broker publish → cartridge child broadcasts (mocked ARC) → anchor.confirmed event → brain audit log carries txid
- Failure smoke: ARC reject → anchor.failed → brain audit log carries error_kind
- Idempotency: duplicate cell.create with same cell_hash → second emit is `.pending` but cartridge queue dedups; only one broadcast

**On-chain integration** (out of scope this PR, future smoke):
- Per memory `mnca_anchor_onchain_mainnet`, the recipe is proven end-to-end on mainnet. Final integration smoke uses the same path: real wallet, real ARC, single 1024-byte cell.

---

## §8 What needs Todd's input

1. **Option A (in-brain bun child) vs Option B (HTTP poll) for the cartridge runner** — Option A matches existing patterns + memory `semantos_brain_single_threaded_reactor`'s detached-grandchild discipline. Confirm or override.

2. **`type_hash` in AnchorContext** — adding requires touching the existing `cell_handler.zig:201` + `intent_cells_handler.zig:446` call sites to populate it. Audit confirms both call sites have type_hash in scope (post-PR-20/22 canonical-256B header). Just procedural; flagging for visibility.

3. **Per-cartridge brokers vs shared broker** — today there's one process-scoped `helm_event_broker.Broker` (per its module doc-comment). Multiple cartridges subscribing to `cell.created` is fine on the shared broker. If you'd later want per-cartridge isolation (e.g., wallet-headers shouldn't see jambox events), that's a broker-fan-out enhancement, not this PR.

4. **`anchor.failed` → operator notification?** — should a failed broadcast set `requires_operator_attention = true` so the device wakes the operator? Recommendation: NO for v0.1 (transient ARC errors are noisy; reconciliation sweep handles them silently). Confirm.

5. **Runar integration timing** — the §0 Runar adjacency note flags two possible touchpoints (compile anchor lock scripts via Runar; cartridge precondition policies via Runar). Neither blocks #16. Should I add a §11.10 order 4b reserving the slot, or keep it informal for now?

---

## §9 PR sequencing recap

```
#657 (PR-2b real executor) → MERGE
#660 (PR-4a CellSigner)    → MERGE
                             ↓
PR-3a-bridge-1 (emitBsv + event payload)
    requires: AnchorContext.type_hash added; broker handle plumbed
                             ↓
PR-3a-bridge-2 (wallet-headers anchor-subscriber)
    requires: bun-child runner skeleton in cli/serve.zig
                             ↓
PR-3a-bridge-3 (anchor.confirmed feedback loop)
    requires: anchor_confirmer.zig + audit-log entry shape
                             ↓
Task #16 closed; Bridget's L3-unwired gap fully addressed.
```

PR-3a-bridge-1 can land immediately after #657 + #660 merge — it's pure Zig brain-side work with mocked broker for tests. PR-3a-bridge-2 has TS dependencies + needs a runner pattern; longest of the three. PR-3a-bridge-3 is small once the prior two land.

---

## §10 Out of scope (named so it doesn't scope-creep)

- **Cartridge isolation per hat** — today one operator hat; multi-hat anchor routing is post-§11.10 order 4a's hat-resolution registry
- **Header-store sync from wallet → brain** — the brain doesn't need confirmed headers for the anchor flow; the wallet runs its own header pipeline (`bsv-anchor-bundle headers_sync.zig`)
- **Spending the anchor UTXO** — that's the LINEAR-cell consume path (`cell-anchor.ts deriveCellAnchorSk` already supports it). Out of scope here; lands when a cartridge needs to demote a LINEAR cell on-chain.
- **Runar integration** — flagged in §0; future work
- **AnchorAttestation cell schema reconciliation** — `core/anchor-attestation` already exists; this PR consumes it without modifying. Schema evolution is its own thread.

---

## §11 Change log

- **v0.1** (2026-05-25) — Initial design. Drafted while PR #657 (PR-2b real executor) + #660 (PR-4a CellSigner) await merge. Integrates Runar overview as theoretical adjacency frame (cited specifically: deterministic compilation, StatefulSmartContract, UTXO model, cross-impl conformance).
