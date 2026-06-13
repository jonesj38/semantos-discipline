---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/TIER-2P-PHASE-D2-BRIEF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.663184+00:00
---

# Phase D.2 — Mobile `AttentionService` (agent brief)

**Pre-scoped 2026-05-06**, fires after D.1 lands.
**Tier**: 2P — see `docs/prd/TIER-2P-PASK-ATTENTION-MOBILE.md`
**Depends on**: D.1 (`OddjobzAttentionClient`).
**Subagent type**: `bsv-blockchain-wallet-toolbox-expert`

---

## Brief (paste directly to agent)

Working in `/Users/toddprice/projects/semantos-core/apps/oddjobz-mobile`.

# Task: Phase D.2 — AttentionService (Tier 2P)

D.1 just shipped `OddjobzAttentionClient` with three RPC wrappers (`listMessages`, `listDispatchDecisions`, `pollAttentionSignals`). Build the Dart service layer that consumes them and exposes a live, observable surface to the UI.

# Architecture

`AttentionService` is a singleton-per-paired-session class (constructed in `_AuthRouterState`, alongside `OutboxService` from Phase A). It owns:

1. A `OddjobzAttentionClient` instance.
2. A `HelmEventStream` reference for incremental invalidation subscriptions.
3. Cached state: `List<OddjobzAttentionSignal>` (most recent poll), `List<OddjobzMessagePatch>` (recent messages buffer), `List<OddjobzDispatchDecision>` (recent dispatch buffer), `Map<String, List<String>> jobToPatchIds` (job-cellId → patchIds for thread view).
4. A periodic `Timer.periodic(Duration(seconds: 30))` poll loop.
5. App-lifecycle hooks: pause poll on background, resume + refresh on foreground.
6. `helm.subscribe` topic listeners for: `job.transitioned`, `ratification.created`, `oddjobz.message.appended`, `oddjobz.dispatch.appended` (latter two are NEW topics — see "brain-side topic emission" below).

Exposes:
- `Stream<List<OddjobzAttentionSignal>> get signals` — broadcast stream, replays the latest snapshot to new listeners.
- `Stream<List<OddjobzMessagePatch>> messagesForJob(String jobCellId)` — derived stream filtered by primaryTarget. Implementation: cache jobCellId → list of dispatch decisions → list of patchIds → list of message patches; refreshes when underlying buffer refreshes.
- `Stream<List<OddjobzDispatchDecision>> get pendingRatifications` — filtered stream of decisions where `requiresRatification == true` AND not yet ratified (we don't track "ratified" yet — for v1, just emit all `requiresRatification: true` decisions; deduping with ratified state comes in F or later).
- `Future<void> refresh()` — manual refresh trigger (pull-to-refresh on the feed).
- `Future<void> dispose()` — cancels timer, closes stream controllers, drops listeners.

# What to ship

## File: `apps/oddjobz-mobile/lib/src/attention/attention_service.dart`

The service. ~250-400 lines. Use `StreamController.broadcast()` for the public streams. Use private state vars + a single `_recompute()` method that re-derives the streams from the cached buffers; call `_recompute()` after every poll completion + after every topic-driven invalidation.

Match the `JobsRepository` pattern for cache-then-fetch initialization:
1. Construct service → starts cold.
2. `start()` is called by AuthRouter once auth + WSS subscribed → fires initial poll, sets up topic subs, starts timer.
3. `dispose()` tears down.

## File: `apps/oddjobz-mobile/lib/src/attention/attention_models.dart`

Re-export D.1's models. Add **derived** local models if needed (e.g. a `JobAttentionSummary` that combines a Job row with its attention score + last-message snippet — convenience for E.1's JobListRow). Don't bake business logic here; this is just typed glue.

## File: `apps/oddjobz-mobile/lib/src/app.dart` — modification

In `_AuthRouterState`:
- Construct `AttentionService` alongside `OutboxService` (use the same `_ensureAttention()` pattern as `_ensureOutbox()`).
- Call `attentionService.start()` once WSS state hits `subscribed`.
- Pass to `HomeScreen(attention: _attentionService)` so screens downstream can consume it. (HomeScreen doesn't render attention itself; it just propagates.)
- Dispose on logout/unpair.

## File: `apps/oddjobz-mobile/lib/src/helm/home_screen.dart` — modification

Add `final AttentionService? attention;` to constructor. No UI changes here — D.3 builds the AttentionFeedScreen, E.1 reads it from JobListRow, E.4 uses it for the ratify-pending tray. HomeScreen just holds the reference and passes it down to whichever child needs it.

## Tests: `apps/oddjobz-mobile/test/attention/attention_service_test.dart`

Mock `OddjobzAttentionClient` and `HelmEventStream`. Cover:
1. `start()` triggers initial poll, signals stream emits the result.
2. Periodic timer fires → second poll → signals stream emits updated result.
3. Topic event `oddjobz.message.appended` triggers refresh → buffers update → derived `messagesForJob(...)` stream emits.
4. `requiresRatification` filtering: 5 dispatch decisions, 2 with the flag → `pendingRatifications` stream emits 2.
5. `messagesForJob(jobCellId)` correctly cross-references dispatch decisions → patchIds → messages, sorted desc by timestamp.
6. `dispose()` cancels timer and closes streams (no late emissions).
7. App-lifecycle: backgrounding → no poll fires; foregrounding → triggers a poll.

# brain-side topic emission (small Zig change — keep scope tight)

Phase B's RPC verbs READ data. For real-time mobile updates, the Semantos Brain side must **emit topics** when new messages/dispatches land. Locate `runtime/semantos-brain/src/wss_dispatcher.zig` (or wherever `helm.subscribe` topic dispatch lives — search for `helm.publish` or topic-emission helper). Wire two new topics:

- `oddjobz.message.appended` — emitted when a new line lands in `messages.jsonl` (file watcher on the data dir, or appended-by-handler if/when brain starts owning the writes).
- `oddjobz.dispatch.appended` — same for `dispatch-decisions.jsonl`.

For v1, since legacy-ingest writes the JSONL out-of-process, add a **file-watcher** approach: poll mtime of the two files every 5s in a background fiber/thread; when mtime changes, emit the topic. This is a simple seam — Phase F or a dedicated optimisation pass can replace it with kqueue/inotify later.

If you can't find a cheap place to wire this, **drop the topic emission from this phase** and rely solely on the 30s mobile polling timer. Note that fact in the PR description so we know to wire it later. The mobile-side service must work either way.

# Constraints

- Do NOT add Riverpod / Provider / Bloc.
- Do NOT touch `OddjobzQueryClient` or `JobsRepository` — they're orthogonal.
- The streams must be `broadcast` so multiple UI screens (Feed, ratify tray, JobList) can subscribe simultaneously.
- App-lifecycle handling must use `WidgetsBindingObserver` (look for existing usage in `home_screen.dart`).
- Don't try to dedupe across providers — if Meta ingestion + Gmail ingestion both produce a patch for the same conversation, both show. Reconciliation is a Tier 5 problem.

# Verification

- `flutter analyze` clean
- `flutter test test/attention/` passes
- `flutter test` (full suite) — your additions don't break A's outbox tests or anything else
- `git diff --stat HEAD` ~5-7 files (service + models + app.dart + home_screen.dart + test + maybe brain topic plumbing)

# PR

Branch `feat/tier2p-D2-mobile-attention-service` from current origin/main. Commit message starts "Tier 2P Phase D.2 — mobile AttentionService". PR body: list streams exposed, describe topic-emission decision (wired or deferred), test coverage, note this unblocks D.3 + E.1 + E.2 + E.4.

Report back the PR URL + 6-line summary including (a) which streams are exposed, (b) whether topic-emission was wired or deferred, (c) any architectural decisions where you took a non-obvious path.
