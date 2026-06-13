---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/TIER-2P-PHASE-E-AND-F-BRIEFS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.708913+00:00
---

# Tier 2P — Phase D.3 + E + F (full agent briefs)

**Pre-scoped 2026-05-06.** D.3 / E.1 / E.2 / E.4 fire in parallel after D.2 lands. F fires after the wave-3 PRs all merge.

Each section below is a self-contained agent prompt. Read this file's "Wave-3 architectural decisions" section first for context before firing.

---

## Wave-3 architectural decisions

After reviewing the current mobile code:

1. **HomeNode is the operator's dashboard** at `apps/oddjobz-mobile/lib/src/helm/home_node.dart`. Currently shows 3 stage-grouped sections: "Needs attention" (lead/quoted/completed), "Active" (scheduled/in_progress), "Recent" (invoiced/paid/closed). The new Pask-attention feed integrates here as a NEW top section called "Surface", pushing the existing stage groups down. This avoids touching the dock (Home/Do/Talk/Find — Pask 4-node model preserved).

2. **`attention_screen.dart` already exists** for the older `jobs.find_attention` bucketing (D-O5 era — pending_quote / pending_schedule / pending_invoice). Don't replace it. The new D.3 feed is additive, lives in HomeNode, and surfaces dispatch+message+job signals from the unified Pask pipeline. The two attention surfaces will eventually be merged in a polish phase.

3. **`job_detail_screen.dart` is 738 lines, no tabs.** Adding a TabBar would be a big refactor. E.2 instead ships a separate `JobThreadScreen` pushed from a button in the existing detail screen — no regression risk.

4. **`E.4 ratify tray` is reachable from a badge on the AppBar** (count of pending ratifications) — pushes a dedicated `RatifyTrayScreen`. The badge on AppBar is universal across all 4 dock nodes via the parent `_HomeScreenState`.

5. **"Pre-existing F.2 site_screen_test.dart failure"** (referenced in todos and the handoff doc) is unrelated to wave-3 work — agents can ignore it as long as they don't introduce new failures.

---

## Phase D.3 — `AttentionFeedSection` (HomeNode top section)

**Subagent**: `bsv-blockchain-wallet-toolbox-expert`
**Depends on**: D.2 (AttentionService).
**Branch**: `feat/tier2p-D3-mobile-attention-feed-section`

### Brief (paste-ready)

Working in `/Users/toddprice/projects/semantos-core/apps/oddjobz-mobile`.

# Task: Tier 2P Phase D.3 — AttentionFeedSection in HomeNode

D.2 just merged. `AttentionService` exposes:
- `Stream<List<OddjobzAttentionSignal>> get signals` (broadcast)
- `Stream<List<OddjobzDispatchDecision>> get pendingRatifications` (broadcast)
- `Future<void> refresh()`

Build a new section that renders the top-N attention signals at the **top of HomeNode**. Read `docs/prd/TIER-2P-PHASE-E-AND-F-BRIEFS.md` Wave-3 architectural decisions section first for context.

# What to ship

## File: `apps/oddjobz-mobile/lib/src/helm/attention_feed_section.dart` (new)

A `StatefulWidget` that:
- Takes `AttentionService attention` + `JobsRepository jobs` (for navigation to job detail) as constructor params
- Subscribes to `attention.signals` stream
- Renders top-10 signals as cards, sorted by score desc
- Each card matches the signal's `kind`:
  - **dispatch**: lane chip (Direct/Squad/Broadcast/Agent/Self with color), confidence-bar bottom edge, "tap to ratify" affordance if `requiresRatification`, primary-target summary
  - **message**: customer name (resolved via OddjobzQueryClient cache OR signal.summary), channel icon (gmail/meta/voice), relative timestamp ("3m", "2h", "yesterday"), first 80 chars of text
  - **job**: site address (from signal.summary or raw), customer name, due date, urgency color (red ≤ today, amber ≤ tomorrow, gray ≤ 7d)
- Tap a card → navigates to JobDetailScreen for the underlying job
- Pull-to-refresh on the section → calls `attention.refresh()`
- "See all (N)" link at bottom → for now, no-op or "Coming soon" (full feed screen is a follow-up)
- Empty state: hide the section entirely (don't show "you're caught up" — let HomeNode's existing empty-state handle that)

Section header: "Surface" with a small attention dot indicator.

## File: `apps/oddjobz-mobile/lib/src/helm/home_node.dart` (modify)

- Add `AttentionService? attention` to `HomeNode` constructor
- In `build()`, prepend an `AttentionFeedSection(attention: attention!, jobs: widget.jobs)` to the existing scroll IF `attention != null`
- Maintain existing stage-grouped sections below

## File: `apps/oddjobz-mobile/lib/src/helm/home_screen.dart` (modify)

- The AuthRouter wires `AttentionService` (via D.2) and passes it via `HomeScreen(attention: ...)` already
- `HomeScreen` propagates to `HomeNode(attention: widget.attention, ...)` in the IndexedStack at line ~394

## Tests

In `apps/oddjobz-mobile/test/helm/`, add `attention_feed_section_test.dart`:

1. Empty stream → section renders nothing (returns SizedBox.shrink or similar)
2. 5 mixed signals → 5 cards rendered, sorted by score desc, each with kind-appropriate visuals
3. Dispatch signal with `requiresRatification: true` → "Pending ratification" tag visible
4. Tap a job-kind card → navigation pushed (use NavigatorObserver mock)
5. Pull-to-refresh triggers `attention.refresh()`

Use a fake AttentionService that exposes a manually-pushable StreamController so the test controls signal emission.

# Constraints

- Keep section visually compact — operator's screen is not infinite. Top-10 signals max, each card ~80dp tall.
- Match Material 3 theming used elsewhere in the app.
- No new packages.
- Don't rebuild the existing 3-section stage layout — that lives below this new section unchanged.
- Don't introduce a 5th dock destination.

# Verification

```
cd /Users/toddprice/projects/semantos-core/apps/oddjobz-mobile
flutter analyze
flutter test test/helm/attention_feed_section_test.dart
flutter test
git diff --stat HEAD
```

Pre-existing `site_screen_test.dart` failure is NOT yours.

# PR

Branch `feat/tier2p-D3-mobile-attention-feed-section` from `origin/main` (NOT from D.2's branch — verify with `git fetch origin && git checkout -b feat/tier2p-D3-mobile-attention-feed-section origin/main`).

Title: "Tier 2P Phase D.3 — AttentionFeedSection in HomeNode"
Body: 1-2 sentences on what shipped, mention the kind-aware card layout, test coverage.

Report back the PR URL + a 5-line summary.

---

## Phase E.1 — JobListRow attention richness

**Subagent**: `bsv-blockchain-wallet-toolbox-expert`
**Depends on**: D.2.
**Branch**: `feat/tier2p-E1-joblist-attention-row`

### Brief (paste-ready)

Working in `/Users/toddprice/projects/semantos-core/apps/oddjobz-mobile`.

# Task: Tier 2P Phase E.1 — JobListRow attention richness

D.2 just merged. Augment the existing JobListRow (used in `find_node.dart` Jobs tab + HomeNode + DoNode) so each row surfaces attention info inline.

# Background

`JobListRow` is at `lib/src/helm/job_list_row.dart`. Currently has:
- `onTap` (row body, F.1)
- `onPhotosTap` (F.4 photos icon)
- `onCustomerTap` (F.3 customer-name link)

Already richly composed. You're adding visual augments — NOT new tap handlers.

# What to ship

## File: `apps/oddjobz-mobile/lib/src/helm/job_list_row.dart` (modify)

Add 3 new optional constructor params:
- `OddjobzAttentionSignal? attentionSignal` — score badge + dot
- `OddjobzMessagePatch? lastMessagePatch` — message snippet line
- `OddjobzDispatchDecision? primaryDispatch` — lane chip

New visual elements:
1. **Lane chip** (top-trailing area, near photos icon): small Material `Chip` with the lane label (`direct`/`squad`/`broadcast`/`agent`/`self`) and color:
   - direct → blue (Colors.blue.shade100 bg, blue.shade900 text)
   - squad → orange
   - broadcast → red
   - agent → green
   - self → gray
   Hidden if `primaryDispatch == null`.

2. **Score dot** (next to job title): 8dp circle dot colored by score:
   - red ≥ 0.8
   - amber ≥ 0.6
   - gray < 0.6
   Hidden if `attentionSignal == null`.

3. **Last-message snippet** (compact line below site/customer line, before the optional photo strip): "💬 [first 60 chars of text]…  [relative time]" in `Theme.of(context).textTheme.bodySmall`. Hidden if `lastMessagePatch == null`.

Total added vertical space: ~16-20dp when all 3 are present. Operator's screen is small — keep it tight.

## File: `apps/oddjobz-mobile/lib/src/helm/job_list_screen.dart` (modify)

- Add optional `AttentionService? attention` to `JobListScreen` constructor
- Subscribe to `attention.signals` stream; index by `signal.ref` (job cellId)
- Subscribe ONCE to `attention.client.listMessages(limit: 200)` on init (don't poll each row separately) — index latest message per session-id, then map session to job via dispatch decisions
- For each visible row, look up:
  - `attentionSignal` from the indexed signals map (filter to `kind: job` matching this jobCellId)
  - `lastMessagePatch` from session→latest-message map keyed off the job's primary dispatch's sourcePatchId
  - `primaryDispatch` from dispatch decisions where `primaryTargetType: job` and `primaryTargetRef == job.cellId`
- Pass to `JobListRow(...)`

If `attention == null`, JobListRow renders unchanged — tests must verify this.

## File: `apps/oddjobz-mobile/lib/src/helm/find_node.dart` (modify)

- Add `AttentionService? attention` to FindNode constructor
- Pass through to `JobListScreen(attention: attention)` for the Jobs tab

(Same propagation pattern as `oddjobzQuery` — copy that.)

## File: `apps/oddjobz-mobile/lib/src/helm/home_screen.dart` (modify)

- HomeScreen → FindNode wiring already passes oddjobzQuery; add the same for attention

## Tests

`apps/oddjobz-mobile/test/helm/job_list_row_attention_test.dart` (new):

1. Row with all 3 (signal+msg+dispatch) → all 3 visuals render
2. Row with no attention info → original rendering unchanged
3. Lane chip color matches lane enum
4. Score dot color: 0.85 → red, 0.65 → amber, 0.4 → gray
5. Snippet truncates at 60 chars + "…"

Don't break existing JobListRow tests.

# Constraints

- Backward-compat: rows without attention info MUST render exactly as before
- Don't increase row height by more than 24dp total when fully populated
- The legacy `onAddressTap` referenced in pre-existing site_screen_test.dart is NOT a real param — leave unchanged

# Verification

```
flutter analyze
flutter test test/helm/job_list_row_attention_test.dart
flutter test test/helm/job_list_row_test.dart
flutter test
```

# PR

Branch `feat/tier2p-E1-joblist-attention-row` from origin/main.
Title: "Tier 2P Phase E.1 — JobListRow attention richness"
Body: list the 3 new visuals + backward-compat note + test count.

Report back PR URL + 5-line summary.

---

## Phase E.2 — `JobThreadScreen` (push from JobDetailScreen)

**Subagent**: `bsv-blockchain-wallet-toolbox-expert`
**Depends on**: D.2.
**Branch**: `feat/tier2p-E2-job-thread-screen`

### Brief (paste-ready)

Working in `/Users/toddprice/projects/semantos-core/apps/oddjobz-mobile`.

# Task: Tier 2P Phase E.2 — JobThreadScreen

For a given job, surface the full chronological merge of every message patch + dispatch decision touching that job. Push from a button in JobDetailScreen.

# Why a separate screen, not a tab

JobDetailScreen is 738 lines, no TabBar. Adding tabs is a meaningful refactor with regression risk. A separate pushable screen is cleaner and lower-risk.

# What to ship

## File: `apps/oddjobz-mobile/lib/src/helm/job_thread_screen.dart` (new)

A `StatefulWidget` accepting `String jobCellId, AttentionService attention`. On init:

1. Subscribe to `attention.messagesForJob(jobCellId)` for the message patches
2. Call `attention.client.listDispatchDecisions(primaryTargetType: OddjobzDispatchTargetType.job, primaryTargetRef: jobCellId)` once (and again on pull-to-refresh)
3. Merge messages + dispatches into a single chronological list, sorted by timestamp ascending (oldest at top, like a chat)

Render:
- **Message patches** (`OddjobzMessagePatch`):
  - Customer role (`role == 'customer'`): left-aligned bubble, light-blue bg, customer name + channel icon (gmail/meta) + timestamp at top, full text below
  - Operator role (`role == 'operator'`): right-aligned bubble, light-green bg, "you" + channel + timestamp, full text
  - Assistant role (`role == 'assistant'`): center-aligned narrow bubble, gray bg, italic
- **Dispatch decisions** (`OddjobzDispatchDecision`): inline system message bar — small, italic, distinct color. Format: "Routed to [lane] · [target.type] · score [target.score · 2dp]". If `requiresRatification: true`, prepend "⚠ Pending ratification:" and add a "Ratify" outlined button.
- Empty state: "No conversation history yet."
- Pull-to-refresh: refetches the dispatch list (messages stream auto-updates).
- AppBar: "Thread — [job title]" with back arrow.

Ratify button → for v1, navigate to existing ratification flow if reachable, OR show a SnackBar "Ratify flow coming soon." Don't reinvent the wallet-side ratify path; it's a separate phase.

## File: `apps/oddjobz-mobile/lib/src/helm/job_detail_screen.dart` (modify)

- Add `AttentionService? attention` to JobDetailScreen constructor
- In the existing AppBar actions, add an IconButton(`Icons.chat_bubble_outline`) labeled "Thread" — pushes `JobThreadScreen(jobCellId: widget.job.cellId, attention: widget.attention!)` when tapped
- Hide the button if `attention == null`

Propagate from FindNode → JobListScreen → JobDetailScreen the same way `attention` flows through. Mirror the existing `oddjobzQuery` propagation chain.

## Tests

`apps/oddjobz-mobile/test/helm/job_thread_screen_test.dart` (new):

1. Empty thread → empty-state shown
2. 3 messages + 2 dispatches → 5 items in correct chronological order
3. Customer role left, operator role right
4. Pending-ratification dispatch shows the warning tag + Ratify button
5. Tap Ratify button (no real navigation — just verify callback invoked or SnackBar shown)

# Constraints

- Don't touch the existing 738-line JobDetailScreen body — only its AppBar actions
- Don't introduce TabBar
- The `Ratify` button is intentionally minimal in v1 — full ratify flow is post-Tier-2P

# Verification

```
flutter analyze
flutter test test/helm/job_thread_screen_test.dart
flutter test
```

# PR

Branch `feat/tier2p-E2-job-thread-screen` from origin/main.
Title: "Tier 2P Phase E.2 — JobThreadScreen"
Body: 2-line description, note Ratify button is v1-stub, test count.

Report back PR URL + 5-line summary.

---

## Phase E.4 — `RatifyTrayScreen`

**Subagent**: `bsv-blockchain-wallet-toolbox-expert`
**Depends on**: D.2.
**Branch**: `feat/tier2p-E4-ratify-tray-screen`

### Brief (paste-ready)

Working in `/Users/toddprice/projects/semantos-core/apps/oddjobz-mobile`.

# Task: Tier 2P Phase E.4 — RatifyTrayScreen

A dedicated screen surfacing all dispatch decisions where `requiresRatification: true`, so the operator can see and clear pending broadcast/squad approvals in one place.

# What to ship

## File: `apps/oddjobz-mobile/lib/src/helm/ratify_tray_screen.dart` (new)

A `StatefulWidget` accepting `AttentionService attention`. Subscribes to `attention.pendingRatifications` stream.

For each pending dispatch, render a card:
- Lane chip (matching E.1's color map)
- PrimaryTarget summary: "[type] · [ref-shortened]" (truncate ref to first 8 hex chars + "…")
- Confidence bar (linear progress 0-1 with color: red < 0.5, amber 0.5-0.7, green ≥ 0.7)
- Source message snippet (look up via `dispatch.sourcePatchId` from the messages buffer in attention service — if not present in cache, show "(message not loaded)")
- "Ratify" + "Decline" buttons:
  - **Ratify**: for v1, show a SnackBar "Ratify flow coming soon" (real wallet-side ratify is a separate phase).
  - **Decline**: same v1 placeholder.

AppBar: "Ratify Tray — [N] pending"
Empty state: "Nothing waiting — surface is clean."
Pull-to-refresh: `attention.refresh()`.

## File: `apps/oddjobz-mobile/lib/src/helm/home_screen.dart` (modify)

In the existing AppBar `actions:` (alongside `OutboxStatusIndicator` and `_LiveIndicator`):
- Add a `_RatifyBadge` widget that subscribes to `attention.pendingRatifications`, shows a `Badge.count()` with the count when > 0, hidden when 0
- Tap → pushes `RatifyTrayScreen(attention: widget.attention!)`

If `widget.attention == null`, don't render the badge.

## Tests

`apps/oddjobz-mobile/test/helm/ratify_tray_screen_test.dart` (new):

1. Empty stream → empty-state visible
2. 3 pending dispatches → 3 cards in score-desc order
3. Confidence bar color: 0.4 red, 0.6 amber, 0.8 green
4. Ratify button tap → SnackBar shown
5. Pull-to-refresh calls service.refresh()

`apps/oddjobz-mobile/test/helm/home_screen_test.dart` (modify or new):
- Badge count matches stream value
- Badge hidden when `attention == null`

# Constraints

- v1 Ratify/Decline are stubs — real flow is post-Tier-2P (probably its own phase since wallet-side ratify is involved)
- No new packages
- Badge must not crowd the existing AppBar actions

# Verification

```
flutter analyze
flutter test test/helm/ratify_tray_screen_test.dart
flutter test
```

# PR

Branch `feat/tier2p-E4-ratify-tray-screen` from origin/main.
Title: "Tier 2P Phase E.4 — RatifyTrayScreen + AppBar badge"
Body: describe the screen + badge integration + v1 stub note.

Report back PR URL + 5-line summary.

---

## Phase F — Voice path fidelity end-to-end

**Subagent**: `bsv-blockchain-wallet-toolbox-expert`
**Depends on**: D.2 + D.3 + E.1 + E.2 + E.4 (all merged) + Phase A (already merged).
**Branch**: `feat/tier2p-F-voice-path-smoke`

### Brief (paste-ready, expand at fire-time)

Working in /Users/toddprice/projects/semantos-core.

# Task: Tier 2P Phase F — voice path fidelity end-to-end

All wave-1/2/3 PRs have merged. Time to verify the full voice loop:

1. Operator taps mic
2. Whisper transcribes locally
3. Llama on-device produces SIR candidate
4. OutboxService enqueues the recording (Phase A wired this)
5. Outbox flushes to brain via REPL/HTTP upload
6. Brain receives + ratifies → message patch + dispatch decision written
7. AttentionService poll picks up the new signal
8. AttentionFeedSection shows the new card on phone (D.3 surfaces it)

# What to ship

## A. Smoke harness: `scripts/oddjobz-voice-path-smoke.ts`

Mirror Codex's `oddjobz-ingestion-attention-smoke.ts` shape. Synthesize:
- 3 voice memo recordings (mock audio bytes + transcript + SIR candidate)
- Push them through the brain as if from outbox
- Verify each produces: 1 message patch + 1 dispatch decision (lane: `self`)
- Verify attention projector picks up the new signals
- Real Pask kernel mode (not RecordingPask) — match the existing smoke's --mock-pask escape hatch

Pass criteria: 3 messages, 3 dispatches, 3 self-lane signals, max cell-id ≤ 63 bytes, Pask kernel snapshot grows.

## B. Flutter integration test: `apps/oddjobz-mobile/integration_test/voice_to_attention_test.dart`

Use `flutter_test` + `integration_test`:
1. Mock the WSS so we can inject test responses
2. Trigger a fake voice memo through OutboxService
3. Verify outbox flush → REPL upload (mocked) succeeds
4. Verify the AttentionFeedSection rebuilds with the new signal
5. Verify card content matches the synthesized voice memo

If integration_test isn't already wired, document that as a follow-up rather than wiring it from scratch this session.

## C. Bug-fix budget

≤ 3 small follow-up fixes if anything found broken. Bigger discoveries spawn their own phase.

# Constraints

- Must pass on iOS Simulator (Bridget's pairing test compatibility)
- Must NOT depend on real Meta backfill (Phase C blocked)
- Use voice as the single trigger

# Verification

```
bun scripts/oddjobz-voice-path-smoke.ts
cd apps/oddjobz-mobile && flutter test integration_test/voice_to_attention_test.dart
```

# PR

Branch `feat/tier2p-F-voice-path-smoke` from origin/main.
Title: "Tier 2P Phase F — voice path fidelity smoke"
Body: list both harness + integration test, pass/fail report, any small fixes shipped, any deferred follow-ups.

Report back PR URL + 6-line summary including any bugs found and how they were addressed.
