---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/canonicalization-v2-anchor-survey.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.629966+00:00
---

# V2 anchor — brain survey findings

**Status**: REVISED 2026-05-28. Initial survey missed the synchronous anchor path proven on mainnet via the MNCA + IXP demos. V2 is FEASIBLE without landing the half-built brain async pipeline.

## TL;DR (revised)

There are TWO anchor pipelines in the codebase:

1. **Sync / on-demand** — `buildAnchorTx` (wallet-headers/brain/mesh-bsv-sink.ts) + `headless-wallet.sendPushdrop` (shared/anchor). Mainnet-proven via MNCA cell anchor 2026-05-22 + IXP bridge demos (~100ms latency). **This is what V2 should use.**
2. **Async / event-driven** — anchor-subscriber.ts subscribing to `cell.created` broker events via PR-3a-bridge-2c bun-child runner. **NOT yet landed.** Don't gate V2 on it.

V2 wires the sync path: extend `cells_mint_handler` with `anchor: true`; when set, inline-call `buildAnchorTx` + headless-wallet broadcast; return `anchorTxid` synchronously. The brain at oddjobtodd.info already has a funded wallet path per the MNCA mainnet anchor commit (see `[[mnca-anchor-onchain-mainnet]]` memory).

(Original survey kept below for the record — it correctly identified the async path's incompleteness but wrongly concluded V2 was blocked overall.)

---

## ORIGINAL SURVEY (initial reading — corrected by revision above)

## Survey answers

### Q-V2-1 — Does cells_mint_handler accept `anchor` param?
**No.** `runtime/semantos-brain/src/cells_mint_http.zig` RequestEnvelope:
```zig
const RequestEnvelope = struct {
    typeHashHex: []const u8,
    payload: std.json.Value,
    capabilityProof: ?std.json.Value = null,
};
```
Parser uses `ignore_unknown_fields: true` so sending `anchor: true` would be silently dropped. Adding the field requires Zig code change + a follow-up envelope versioning question (BRC-100 compatibility?).

### Q-V2-2 — Anchor pipeline shape?
**Event-driven, NOT synchronous.** Per `cartridges/wallet-headers/brain/src/anchor-subscriber.ts` header:

```
brain.AnchorEmitter.emitBsv(...)
  → broker.publish("cell.created", {cell_hash, type_hash, ...})
    → [bun-child runner pipes the event to this subscriber]
      → handleCellCreated(event, identity, createAction)
        → derive anchor SK via BRC-42
        → build cell-anchor lock script
        → createAction (wallet builds + signs + broadcasts)
        → return {status: 'broadcast', txid}
```

**Implication for V2 fixture**: mint returns cellId synchronously; anchorTxid attaches asynchronously. V2 fixture's expected response with `anchorTxid` inline is the WRONG model — needs two-phase (mint immediate, anchor later via polling/subscription).

### Q-V2-3 — anchorTxid storage?
**Half-defined.** Found:
- `contact_book_lmdb.zig` has `cells_by_anchor_txid = noopCellsByAnchorTxid` — index slot reserved, noop impl
- `test-mnca-anchor.ts` carries `anchorTxid` per anchor attestation
- No production persistence path observed for `cells.<id>.anchorTxid` metadata

Likely needs:
- A new field on the cell-store or a sibling anchor-log
- Or an AnchorAttestation cell with `ANCHOR_ATTESTATION_ENTITY_TAG = 0x20` linking back to source cell

### Q-V2-4 — Is anchor pipeline live on rbs today?
**No.** Live audit log shows `intent_cell.created` events but **no `cell.created` events** (cells_mint_handler doesn't emit them). No `bun-child` anchor-runner process. Brain serve flags include `--enable-intent-action-router` but no `--enable-anchor-bridge` equivalent.

Per anchor-subscriber.ts: *"PR-3a-bridge-2c lands the bun-child runner"* — that PR has not landed.

### Q-V2-5 — anchor:optional default-local-only policy intact?
**Yes** — cartridges/self/cartridge.json doesn't declare `anchor: required` on any verb. Q5 decision holds.

## The block

V2 requires ONE of:

### Option A — Land PR-3a-bridge-2c (the bun-child anchor-runner)
Multi-step infrastructure work:
1. Implement the bun-child runner per docs/prd/ANCHOR-BACKEND-BRIDGE.md §4 "Option A — in-brain bun-child runner"
2. Wire `cells_mint_handler` to publish `cell.created` events (not just `intent_cell.created`)
3. Decide + implement anchorTxid storage (cell-store metadata vs sibling AnchorAttestation cell)
4. Add `--enable-anchor-bridge` brain serve flag + systemd drop-in
5. Establish ARC funding model (Q-V2-4 answered: brain wallet needs a funded BSV address)
6. Verify on rbs: mint a cell, observe broker event, observe runner subscribing, observe ARC broadcast, observe anchorTxid persisted

Estimated scope: 3-5 days of focused brain work.

### Option B — Synchronous anchor (architectural deviation)
Add `anchor: true` to RequestEnvelope; cells_mint_handler does the anchor inline before returning. Returns cellId + anchorTxid in one call.

Pros: no async-state plumbing, simpler PWA UI.
Cons: blocks request on ARC roundtrip (~10s for confirmation); violates the event-driven design that anchor-subscriber was built for; harder to retry on ARC failures.

### Option C — Defer V2; pivot to other slice work
Push V2 anchoring out (track it as a stalled track in the matrix). Pick a different next slice that doesn't depend on brain anchor pipeline:
- **V2 alt (multi-turn capture)**: extend Release sheet to capture all 3 steps of cartridges/self/cartridge.json's daily-release flow (source/prompt-choice/write) — pure PWA work, no brain changes.
- **V2 alt (cards persist across sessions)**: replace in-memory recent-mints with brain query (`/api/v1/cell/since/`) so closing/reopening app preserves history.
- **V2 alt (voice mic)**: wire `voice_extract_uploader` to brain `/api/v1/voice-extract` so operator can speak the release.
- **Oddjobz slice (per user priority)**: register Quote/Job intents; build oddjobz Release-sheet equivalent.

## Recommended user move

Pick a path:

1. **Option A** if anchoring is the V2 acceptance you want and you're OK with the brain-side work
2. **Option B** if you want anchored cells fast and accept the architectural cost
3. **Option C** + pick which alternative V2 slice
4. Or move to **oddjobz** per your stated priority — the canonical PWA's wiring is cartridge-agnostic, oddjobz "just needs" intent bindings + UI (but UI is real work)

The /loop can't autonomously pick this — it's a scope decision.
