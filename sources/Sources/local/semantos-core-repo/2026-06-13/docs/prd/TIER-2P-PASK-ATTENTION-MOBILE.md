---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/TIER-2P-PASK-ATTENTION-MOBILE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.684097+00:00
---

# Tier 2P — Pask Attention on Mobile + Meta Full Ingest

**Status**: started 2026-05-06 (post-handoff #393)
**Owner**: Claude session (this), with operator action for Phase C
**Origin**: operator request after Codex's `0e18eb3` ("unify meta ingestion dispatch and attention") shipped to main. Mobile app is missing the new attention/Pask surface; the same Codex commit also exposed a Meta Business Suite Inbox backfill script that needs to be run.

The "P" in Tier 2P is for **P**ask — this is the parallel mobile/data track that runs alongside the Tier 2 backlog kanban (`TIER-2-BACKLOG-KANBAN.md`).

---

## §1 — Problem statement

Three concrete pains:

1. **"Outbox not ready — please try again"** — operator's phone has Whisper + Llama on-device but every voice/message send blocks at this snackbar. Bug.
2. **Meta jobs not in the graph** — Meta Business Suite Inbox (Messenger, Instagram DMs, eventually WhatsApp/comments) carries a substantial chunk of operator's job traffic. Codex's `oddjobz-backfill-meta-conversations.ts` is shipped but never run.
3. **Attention surface is helm-only** — the new Pask-projected attention/StableThreads surface from `0e18eb3` exists in `apps/loom-react/src/helm/{Helm,StableThreads}.tsx` but has no mobile equivalent. Operator's primary-use device is the phone; helm is brain-side.

---

## §2 — Goal

Operator's phone surfaces the same Paskian attention richness the helm has. Outbox flushes voice/message recordings into the unified graph. Meta Business Suite traffic is fully ingested (historical + webhook-tail) into signed cells with the same dispatch routing.

End state: operator looks at phone, sees ranked feed of hot jobs / pending dispatches / recent customer messages. Voice memo enters the outbox, gets uploaded, becomes a signed message patch, gets routed by dispatch lane, lights up the attention surface.

---

## §3 — Architecture decision: where does projection happen?

**Codex's `attention-projector.ts`** is TypeScript and runs in the legacy-ingest process or in the helm SPA. Mobile can't execute TS.

**Decision**: brain exposes **raw data** (messages, dispatch decisions, optionally pre-projected signals). Mobile does Dart-side projection + ranking. Helm continues to read JSONL directly via its existing TS path.

This means:
- Phase B exposes `oddjobz.list_messages`, `oddjobz.list_dispatch_decisions`, optionally `oddjobz.poll_attention_signals` (projected) over WSS
- Phase D builds Dart equivalents of the projector signals + AttentionEngine ranking
- Phase E renders the surface

Future: if the projection becomes nontrivial enough, port to Zig in brain. Not now.

---

## §4 — Phase matrix

| Phase | Title | File scope | Depends | Size | Status |
|---|---|---|---|---|---|
| **A** | Outbox unblock — wire `OutboxDb` + `OutboxService` into `AuthRouter`, flush timer | `apps/oddjobz-mobile/lib/src/{app.dart, helm/home_screen.dart, outbox/outbox_service.dart}` | — | XS | started 2026-05-06 |
| **B** | brain attention RPC verbs (`list_messages`, `list_dispatch_decisions`, `poll_attention_signals`) | `runtime/semantos-brain/src/oddjobz_query_handler.zig`, new `oddjobz_attention_handler.zig`, JSONL readers | — | M | started 2026-05-06 |
| **C** | Meta backfill — operator runs `oddjobz-backfill-meta-conversations.ts` with `META_ACCESS_TOKEN`; verify resolver mints signed cells; reconcile against existing gmail-ingested jobs | operator action + verification harness | — | S | pending operator |
| **D.1** | Mobile `OddjobzAttentionClient` (parallel to OddjobzQueryClient) | `apps/oddjobz-mobile/lib/src/repl/oddjobz_attention_client.dart` | B | S | pending |
| **D.2** | Mobile `AttentionService` (Dart projection equiv. of `attention-projector.ts`) | `apps/oddjobz-mobile/lib/src/attention/` | D.1 | M | pending |
| **D.3** | Mobile `AttentionFeedScreen` (top-N ranked feed, dispatch + job + message signals) | `apps/oddjobz-mobile/lib/src/helm/attention_feed_screen.dart` | D.2 | M | pending |
| **E.1** | JobListRow: dispatch lane chip + attention score indicator + last-msg snippet | `apps/oddjobz-mobile/lib/src/helm/job_list_row.dart` | D.2 | S | pending |
| **E.2** | JobDetail: thread view of all message patches + dispatch decision history | `apps/oddjobz-mobile/lib/src/helm/job_detail_screen.dart` | D.1 | M | pending |
| **E.3** | StableThreads view (mobile) | new screen + Pask graph mobile client (or brain-side stable_thread RPC) | D.2 | M | pending |
| **E.4** | Ratify-pending tray (broadcast dispatches with `requiresRatification: true`) | new screen | D.2 | S | pending |
| **F** | Voice path fidelity end-to-end (verify after A ships) | smoke test + small fixes | A | S | pending |

**Parallelism map** (file-disjoint phases that can fire simultaneously):
- Wave 1 (now): **A + B** — mobile bug fix in lib/src + Zig RPC in runtime/semantos-brain
- Wave 2 (after B lands): **D.1** alone (need it for D.2)
- Wave 3 (after D.1): **D.2 + E.1 + E.2** — D.2 builds projection lib; E.1 wires into existing JobListRow; E.2 wires into JobDetailScreen (file-disjoint from E.1)
- Wave 4 (after D.2): **D.3 + E.3 + E.4 + F** — all consumers of AttentionService

C is operator action — independent of all waves.

---

## §5 — Open architecture questions

To resolve before Wave 2:

1. **Stable threads transport** — Codex's helm reads stable threads via `paskGraph.stableThreads()` (a JS-side Pask client). Mobile equivalent? Options:
   - (a) brain runs Pask in Zig and exposes `oddjobz.stable_threads` RPC. Heavier port; gives consistent state.
   - (b) Mobile gets raw graph and runs Dart-side Pask. Probably won't perform well at scale.
   - (c) Skip stable threads on mobile for v1 (E.3 deferred).
   
   **Tentative**: (c) — defer E.3 until we see if (a) is needed for the helm UX too.

2. **Voice → SIR → ratify on mobile** — voice path produces SIR candidate via on-device llama, then enqueues to outbox. After outbox flush, brain receives + ratifies. Does the brain re-run SIR extraction or trust mobile's? Already-decided: brain skips L0→L1 when `sir_candidate` present (per ingest path). No change needed; just verify in F.

3. **Webhook tail for Meta** — Codex's commit shipped backfill but not webhook receiver. Webhook deferred to next session — backfill alone unblocks the Tier 2P value prop.

4. **Reconciliation with gmail jobs** — same lead may arrive via Gmail (already ingested) AND Meta DM. Dedupe is `meta:<platform>:<asset>:<participant>` for the conversation but not for the job. Codex's resolver should already handle this (same customer cell from address + name). Verify in C.

---

## §6 — Acceptance criteria

For Tier 2P "shipped":

- ✅ Operator's phone successfully sends voice memo → reaches brain → becomes signed message patch (Phase A + F)
- ✅ All historical Meta Messenger + Instagram DM conversations on-disk as `oddjobz.message.v1` patches (Phase C)
- ✅ Each patch routed via dispatch decision (Phase C — Codex pipeline already does this once data exists)
- ✅ Resolved leads/jobs visible on phone JobList with dispatch lane chip + last-msg snippet (Phase E.1)
- ✅ Phone has dedicated AttentionFeed screen showing top-N ranked signals (Phase D.3)
- ✅ Tap a job on phone → see full thread of all message patches + dispatch history (Phase E.2)
- ✅ Pending broadcast dispatches surface a ratify tray on phone (Phase E.4)

Not in this tier:
- Webhook tail (next session)
- WhatsApp / comments adapters (next session)
- Stable threads on mobile (deferred — see §5.1)
- Bricks weekly summary (Tier 5, separate)

---

## §7 — Cross-references

- `docs/prd/SESSION-HANDOFF-2026-05-06.md` — overall session handoff
- `docs/prd/CODEX-INTEGRATION-MAP.md` — what Codex shipped (incl. `0e18eb3` and `node-protocol` triage)
- `docs/prd/TIER-2-BACKLOG-KANBAN.md` — sibling Tier 2 track (kanban view)
- `docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md` — pattern this PRD follows
- Codex commit `0e18eb3` — origin of attention/dispatch pipeline
- `runtime/legacy-ingest/src/attention-projector.ts` — TS-side projector to port to Dart in D.2
- `runtime/legacy-ingest/src/conversation/turn-patch-store.ts` — wire format reference
- `scripts/oddjobz-backfill-meta-conversations.ts` — Phase C script
