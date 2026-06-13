---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/HELM-ATTENTION-SURFACE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.732790+00:00
---

# Helm — Attention Surface (Phase 39B+) — AS1–AS5

**Version**: 0.1 DRAFT
**Status**: Plan
**Authors**: Todd
**Related**: Phase 39A (`Merge phase-39-helm: Helm attention surface + calendar events`, commit `044e88f`); `runtime/services/src/services/AttentionEngine.ts` (existing); `runtime/services/src/types/loom.ts` (AttentionItem / AttentionReason); `apps/loom-react/src/helm/AttentionSurface.tsx` (renderer); `docs/design/WALLET-LEGACY-INGEST.md` (signal source); `docs/design/WALLET-VOICE-SHELL-GRAMMAR.md` (interaction telemetry source)

---

## 0. Headline

> The attention surface is the right-panel feed where the operator's working day actually lives — not an audit log, an *inferred ranked list of what to look at next*. Phase 39A shipped the deterministic skeleton: an AttentionEngine that scores LoomObjects by recency / deadline / active-work / pending-action with hard-coded weights and renders them via `AttentionSurface.tsx`. The 39A code marks the next move explicitly: `// Phase 39B (future): Paskian-learned weights`. AS1–AS5 close that gap. The operator interacts with surfaced items; the engine watches; weights drift toward what actually earns the operator's attention; new signal sources (weather, Surfline, legacy-ingest events, capability state changes) plug in without touching the core scorer.

### On layering

The AttentionEngine and the new AttentionTelemetry / AttentionWeightLearner / AttentionSignals modules live **inside the Loom service layer** at `runtime/services/src/services/` — not inside Helm. Helm renders engine output via `apps/loom-react/src/helm/AttentionSurface.tsx` and dispatches operator interactions back through the Loom action bus. When this doc says "the right-panel attention feed," the rendering is in Helm; the inference, telemetry, and learning are in Loom. See chapter 17b of the textbook for the substrate position of Loom as U11.

---

## 1. Where We Are

Phase 39A is merged and live. The pieces in tree as of writing:

| File | Role | What it does |
|---|---|---|
| `runtime/services/src/services/AttentionEngine.ts` | Scoring engine | Five factors (recency 30 %, deadline 25 %, active-work 20 %, goal-alignment 15 %, pending-action 10 %); deterministic heuristic; recomputes within 16 ms for up to 500 objects |
| `runtime/services/src/types/loom.ts` | Type contract | `AttentionItem` (object + relevance + reason + urgency + scoredAt), `AttentionReason` (active_work / deadline_approaching / goal_misalignment / pending_action / new_update / streak_continuation / scheduled / extension_signal) |
| `apps/loom-react/src/services/AttentionEngine.ts` | Re-export shim | Loom-internal alias to the runtime-services impl |
| `apps/loom-react/src/helm/AttentionSurface.tsx` | Renderer | Pretty card list with linearity badges, urgency accents, `formatTimeSince`, `reasonText` |
| `apps/loom-react/src/hooks/useAttention.ts` | React hook | `useSyncExternalStore` over `engine.stableSubscribe` / `engine.getSnapshot` |
| `apps/loom-react/src/helm/Helm.tsx` | Helm root | Mounts `AttentionEngine`, subscribes via `useAttention`, renders `<AttentionSurface>` in the centre column above the dock |

Two explicit gaps in the 39A code itself:
- `private scoreObject()` declares `const goalAlignment = 0; // Phase 39B: EmbeddingService integration` — the goal-alignment factor is a placeholder waiting for embedding-based similarity against the operator's stated objectives.
- All five weights are constants (`WEIGHT_RECENCY = 0.30`, etc.). There is no per-operator tuning, no learning, no decay-from-ignore, no boost-from-engage.

What is also missing — beyond 39A's scope — is the signal-source breadth. The current factors operate over `LoomObject` properties only. The operator's life surfaces other inputs: weather changing, surf forecast worth a half-day off, a legacy-ingest proposal needing ratification, a capability-token expiring, a customer who hasn't replied to a quote in 4 days. Each of these is *information already in the substrate* (or arriving via the LI pipeline) but Phase 39A's engine doesn't know to score it.

AS1–AS5 closes both gaps: the learning loop (AS1+AS2) and the signal-source breadth (AS3+AS4), plus a thin AS5 for delivering attention beyond the right panel when the operator isn't looking at it.

---

## 2. The Loop, in Pictures

```
   ┌─────────────────────────────────────────────────────┐
   │ Substrate cells, calendar events, legacy proposals,  │
   │ capability state, weather feed, Surfline feed, etc.  │
   └────────────────────────────┬────────────────────────┘
                                 │ signal sources
                                 ▼
                    ┌──────────────────────────┐
                    │ AttentionEngine          │
                    │  - recency               │
                    │  - deadline              │
                    │  - active-work           │
                    │  - goal-alignment        │ ◄─── per-operator weights
                    │  - pending-action        │       (learned, not constant)
                    │  - external-signal       │
                    └────────────┬─────────────┘
                                 │ ranked items
                                 ▼
                    ┌──────────────────────────┐
                    │ AttentionSurface         │
                    │ (right panel, mobile     │
                    │  push, voice "what's     │
                    │  next" surface)          │
                    └────────────┬─────────────┘
                                 │
                                 │ operator interacts
                                 ▼
                    ┌──────────────────────────┐
                    │ Interaction telemetry    │
                    │  - tapped / opened       │
                    │  - dismissed             │
                    │  - acted on (do | …)     │
                    │  - ignored for N hours   │
                    │  - pinned / suppressed   │
                    └────────────┬─────────────┘
                                 │
                                 ▼
                    ┌──────────────────────────┐
                    │ Weight learner           │
                    │  - per-factor weight     │
                    │    drift                 │
                    │  - per-class boost /     │
                    │    suppress              │
                    │  - per-context profile   │
                    │    (in field / at desk)  │
                    └────────────┬─────────────┘
                                 │ weight updates
                                 │ (signed cells, audit-trailed)
                                 ▼
                    [back to AttentionEngine]
```

The learner is bounded — it adjusts weights, it does not invent new factors. New factor *kinds* require new code (a new scoring branch in AS3 or a new external-signal adapter in AS4). The operator's behaviour can re-weight existing factors and can boost or suppress specific item *classes* ("trades.job.*" surfaces +20%; "newsletter.*" suppresses entirely), but cannot magically infer that the operator cares about, say, lunar phase unless a lunar-phase signal source has been wired.

This boundary is the same one VS draws between voice and shell: the LLM-as-aide assists within the schema; new behaviours require code. The architectural property is *legible learning*: the operator can inspect the current weight map, see why item X is ranked above Y, and roll back any drift via REPL.

---

## 3. Phases

### AS1 — Interaction telemetry (~ 1.5 days)

**Goal**: every operator interaction with the attention surface is captured as a
typed event, signed by the operator's hat, and persisted as a substrate cell. This
is the input the learner consumes. Without telemetry there is nothing to learn from.

**Deliverables**:

1. New file `runtime/services/src/services/AttentionTelemetry.ts` exporting:
   ```typescript
   export type AttentionInteraction =
     | { kind: 'tapped'; itemId: string; rank: number; relevance: number; primaryReason: AttentionReason['type'] }
     | { kind: 'opened'; itemId: string; secondsViewed: number }
     | { kind: 'dismissed'; itemId: string; explicit: boolean }
     | { kind: 'acted-on'; itemId: string; verb: 'do' | 'find' | 'talk'; targetVerb: string }
     | { kind: 'ignored'; itemId: string; surfaceForMs: number }
     | { kind: 'pinned'; itemId: string }
     | { kind: 'suppressed'; itemId: string; pattern: string }
     | { kind: 'unsuppressed'; itemId: string };

   export interface AttentionTelemetry {
     record(interaction: AttentionInteraction): Promise<void>;
     stream(opts?: { since?: number }): AsyncIterable<AttentionInteractionRecord>;
   }
   ```

2. **Hooks into the existing `AttentionSurface.tsx` renderer**:
   - `onItemTap` already exists in the prop type; instrument it to call
     `telemetry.record({ kind: 'tapped', ... })` before invoking the
     consumer's tap handler.
   - Add `IntersectionObserver` per card to fire `opened` when a card is
     visible for ≥ 500 ms and `ignored` after a card scrolls past without
     an interaction (configurable threshold).
   - Add `onDismiss` (swipe / tap-X) producing `dismissed` events.

3. **Pinned / suppressed surface**. Add UI affordances on each card:
   - Long-press / right-click → context menu with `Pin`, `Suppress class`,
     `Suppress until tomorrow`, `Always show`.
   - Pinned items render at the top of the surface with a pin icon, score
     uncapped.
   - Suppressed patterns persist in `~/.semantos/attention-rules.toml` and
     are signed cells (audit-trail of "operator suppressed `newsletter.*`
     at $ts").

4. **Acted-on linkage**. When the operator's voice or REPL command targets
   an attention item (the parser carries an `acted-on-attention-item-id`
   in the dispatch context), telemetry records `acted-on` with the verb +
   the target.

5. **Per-context awareness**. The telemetry record carries an optional
   `context` field — `field` (mobile, GPS active), `desk` (desktop or
   stationary mobile), `night` (out-of-hours). Source: a small inferrer
   reading device flags. The learner uses this in AS2 to maintain
   per-context weight profiles.

6. **Storage**. Telemetry events are signed cells (LINEARITY = RELEVANT),
   batched into the lmdb cell store. Retention is operator-configurable
   (default: 90 days raw, lifetime aggregated).

**Success criterion**: every operator interaction with the attention surface
produces a typed signed cell; the telemetry stream is queryable; pinned and
suppressed UX affordances work end-to-end; per-context tagging is correct.

### AS2 — Per-operator weight learning (~ 2 days)

**Goal**: the AttentionEngine's five weights stop being constants. They become
per-operator (and per-context-profile) values that drift toward the operator's
demonstrated preferences.

**Deliverables**:

1. New file `runtime/services/src/services/AttentionWeightLearner.ts`. Reads
   the telemetry stream, maintains a weight cell per operator + context.
   The weight cell is a substrate cell (signed, hash-chained), not a
   localStorage value — so weight history is auditable and the operator
   can roll back.

2. **Update rule**. Per-factor weights drift per the following schema:
   - When an item is `tapped` / `opened` / `acted-on`: the factor that
     contributed most to its score gets a small positive nudge (+0.5%
     per interaction, capped at +20% of base).
   - When an item is `dismissed` / `ignored`: the dominant factor gets a
     small negative nudge (-0.5% per ignore, capped at -20% of base).
   - Weights re-normalise after every batch so they sum to 1.0; no factor
     can fall below 0.05 (avoids dead weights).
   - Updates batched daily; the operator sees "weights updated" in the
     `attention status` REPL output.

3. **Per-class boost / suppress**. Beyond the five base factors, the
   learner tracks per-`type-path` (e.g. `trades.job.fencing`,
   `extension.calendar.event`) multipliers. A class is auto-boosted if
   the operator's interaction-rate on items of that class is significantly
   above mean; auto-suppressed if significantly below. Operator-pinned
   patterns from AS1 §3 take precedence and lock the multiplier.

4. **Per-context profiles**. Three default profiles — `field`, `desk`,
   `night` — each with their own weight + multiplier set. Field profile
   typically up-weights `deadline` and `active-work` (the operator wants
   "what's at the customer's house I'm at"); night profile usually
   down-weights everything except critical alerts. Profiles are
   automatically selected from telemetry context at scoring time.

5. **`attention status` REPL command**:
   ```
   > attention status
   Active profile: field
   Weights:
     recency:        0.34  (up from 0.30 baseline, learning trend +)
     deadline:       0.31  (up from 0.25, +)
     active-work:    0.18  (-)
     goal-alignment: 0.10  (-)
     pending-action: 0.07  (-)
   Class multipliers:
     trades.job.*:        x1.18  (auto-boosted, 47 interactions over 30 days)
     calendar.event:      x1.05  (auto-boosted, 22 interactions)
     legacy-ingest.*:     x0.92  (slight auto-suppress, mostly dismissed)
     newsletter.*:        x0.00  (operator-suppressed, since 2026-04-05)
   Last 30 days: 312 surface impressions, 89 interactions (28.5%)
   ```

6. **Roll-back**. `attention rollback --to <iso-date>` reverts to the
   weight cell as of that date. Useful for "the new weights feel worse
   since I tried that thing." The roll-back is itself a substrate event;
   nothing is destroyed.

7. **Cold start**. New operators (no telemetry history) use the Phase 39A
   constants. The first 100 interactions accumulate before any drift is
   applied. This avoids overfitting on early noise.

**Success criterion**: an operator's weights demonstrably drift after a week
of usage; class auto-boost / auto-suppress correctly identifies operator
preferences (verified against held-out interactions); roll-back works; cold-start
uses defaults; profiles switch correctly between field / desk / night.

### AS3 — Override surface: pins, suppressions, must-show rules (~ 1 day)

**Goal**: the operator's explicit knobs. Most of the system should be inferred,
but some things the operator wants to *declare* — "always show me overdue
quotes," "never show me low-priority Meta lead-ad replies," "pin this
specific job until I close it."

**Deliverables**:

1. New file `~/.semantos/attention-rules.toml` (example):
   ```toml
   [pins]
   # always-show, regardless of score, while these conditions hold
   "trades.job.fencing.henderson" = { reason = "active critical job", until = "2026-05-15" }

   [must-show]
   # surface even when score is below the 0.05 floor
   "*.overdue" = { boost = 0.30 }
   "calendar.event.today" = { boost = 0.20 }

   [suppress]
   # remove from surface entirely
   "newsletter.*" = { since = "2026-04-05" }
   "legacy-ingest.gmail.from:no-reply@*" = { since = "2026-04-12" }

   [class-boost]
   # multiplier on the learned per-class weight
   "trades.dispatch.*" = 1.50            # cross-vertical dispatches always matter
   ```

2. **REPL surface**:
   ```
   attention pin <object-id> [--until <date>]
   attention unpin <object-id>
   attention suppress <pattern> [--until <date>]
   attention unsuppress <pattern>
   attention must-show <pattern> [--boost <0..1>]
   attention rules                        # show current rules
   attention rules edit                   # opens $EDITOR on the rules file
   ```

3. **Helm UI surface**. Right-click / long-press on a card surfaces these
   verbs. The same context menu from AS1 §3, expanded with "Always show"
   and "Boost class."

4. **Pattern matching**. Patterns support glob (`trades.job.*.henderson`)
   and structured filters (`from:<email>`, `to:<phone>`, `region:<area>`).
   Compiled to a small predicate evaluator that runs at scoring time.

5. **Conflict resolution**. When pins and suppressions overlap (operator
   pins one item whose class is suppressed), pin wins for that item;
   class suppression continues to apply to siblings.

6. **Audit trail**. Every rule change is a signed cell. `attention
   rules history` shows the timeline. The operator can revert any rule
   change.

**Success criterion**: pin / suppress / must-show all work via REPL and Helm;
patterns evaluate correctly; conflict resolution is documented and tested;
rules history is complete and accurate.

### AS4 — External signal sources (~ 2 days)

**Goal**: the AttentionEngine needs to know about things outside the LoomObject
graph — weather changing for a scheduled outdoor job, Surfline rating for the
operator's blocked-out window, a legacy-ingest proposal needing ratification, a
capability token approaching expiry, a federated peer dispatch envelope arriving.

**Deliverables**:

1. New file `runtime/services/src/services/AttentionSignals.ts` defining the
   pluggable adapter interface:
   ```typescript
   export interface AttentionSignalSource {
     readonly id: string;                     // "weather", "surfline", "legacy-ingest", "capability", "federation"
     readonly displayName: string;

     // Periodic poll OR push subscription; engine handles both
     poll?(now: number): Promise<AttentionSignal[]>;
     subscribe?(emit: (signal: AttentionSignal) => void): () => void;
   }

   export interface AttentionSignal {
     readonly sourceId: string;
     readonly attachToObjectId?: string;       // if signal is about an existing LoomObject
     readonly synthesizesObject?: LoomObject;  // if signal creates a transient surface item
     readonly factor: AttentionReason;
     readonly score: number;                   // contribution to the synthetic factor
     readonly expiresAt?: number;
   }
   ```

2. **Weather adapter** (`runtime/services/src/services/signals/weather.ts`):
   - Periodic poll against a weather API (BoM for AU operators, OpenWeatherMap fallback)
   - For every calendar event in the next 7 days that is geo-tagged
     and outdoor-flagged, computes a "weather risk" score
   - Emits `extension_signal` reasons with `signal: "rain forecast 18mm
     Friday afternoon during scheduled visit"`

3. **Surfline adapter** (`runtime/services/src/services/signals/surfline.ts`):
   - Periodic poll against Surfline's per-spot forecast endpoint
   - For windows in the operator's calendar marked `flexible` or `personal`,
     computes a surf opportunity score
   - Emits `extension_signal` reasons with `signal: "Sunshine Beach 4★
     6-9am Saturday during your free morning"`
   - Off by default; opt-in via `attention enable surfline`. (Most
     operators won't want this; it's the OJT-tradie-on-the-Sunshine-Coast
     case.)

4. **Legacy-ingest adapter**: a thin connector that turns
   `legacy-ingest.proposal.created` events (cf. LEGACY-INGEST §3 LI3)
   into AttentionSignals with `extension_signal` reasons. The score is
   the proposal's confidence times a per-provider multiplier (Gmail
   proposals about active customers rank higher than archive cleanup).

5. **Capability adapter**: emits signals when capability tokens are
   approaching expiry, when capability state changes (a rotation, a
   revocation), or when a capability-required action is queued.

6. **Federation adapter** (forward-pointer for WF workstream): emits
   signals for incoming dispatch envelopes from federated peers. Out of
   scope for AS4-day-one but the interface is in place.

7. **Combined scoring**. The engine extends `scoreObject` with a sixth
   factor: `external_signal` (weight 0.10 by default, learnable in AS2).
   For *synthesized* items (signals that produce new surface entries
   rather than augmenting existing objects), a synthetic LoomObject is
   constructed with the signal's expiry as a TTL — the item disappears
   when the signal expires.

8. **Configuration**. Each source is opt-in and operator-configurable in
   `~/.semantos/attention-signals.toml`:
   ```toml
   [sources.weather]
   enabled = true
   provider = "bom"
   location = { lat = -26.43, lon = 153.09 }       # Sunshine Coast
   poll_interval = "30m"

   [sources.surfline]
   enabled = false                                  # opt-in
   spots = ["sunshine-beach", "tea-tree-bay"]

   [sources.legacy-ingest]
   enabled = true
   providers = ["gmail", "meta-pages", "whatsapp-cloud"]
   ```

**Success criterion**: weather adapter correctly surfaces rain-risk on
geo-tagged outdoor calendar events; Surfline adapter (when enabled) surfaces
opportunities in flexible windows; legacy-ingest proposals show up in the
right panel as signals; capability expiry warnings surface before they bite;
the engine respects per-source enable/disable and rate-limits each source.

### AS5 — Cross-surface delivery: mobile push + voice "what's next" (~ 1 day)

**Goal**: when the operator isn't looking at Helm — phone in pocket, mid-job, or
otherwise — the high-urgency items reach him through a different channel.

**Deliverables**:

1. **Mobile push** via the operator's wallet origin. WSITE3-issued sessions
   include the device's optional push subscription. When an attention item
   crosses an `urgency = immediate` threshold and the operator has not
   interacted with Helm in the last N minutes (configurable), a push
   notification is dispatched. Payload includes the item summary, the
   primary reason, and a deep-link URL that opens Helm scrolled to that
   item.

2. **Voice "what's next" surface**. From the voice grammar's `find`
   modal — `find | self | next` (or just `find | next`) — surfaces the
   top-3 attention items as a spoken summary. The operator can press the
   mic in the field, ask "what's next," hear "you've got Mrs Henderson's
   fence quote 4 days unanswered, rain Friday afternoon at the Tewantin
   roof job, and a Surfline 4★ Saturday morning."

3. **SMS fallback** (operator opt-in, `attention sms = true`): when the
   web push channel is silent (browser closed, push unsupported), the
   same urgency threshold triggers a Twilio SMS to the operator's number.
   Body: "Henderson fence quote 4d no reply — tap to open: <short-URL>".
   The short URL is hosted on the operator's WSITE node (cf. WSITE2
   short-URL handler).

4. **Quiet hours**. `attention quiet 22:00-07:00` suppresses push +
   SMS in the configured window unless the urgency is `immediate-critical`
   (a tiny set: capability about to revoke a live session, a wallet
   security event, an explicit pinned-must-alert item).

5. **Per-channel telemetry**. Push delivered / opened / dismissed
   reaches AS1's telemetry as additional `AttentionInteraction`
   variants — same learning loop, different channel. The system learns
   that operator dismisses surf-related pushes during work hours and
   stops sending them in that window.

**Success criterion**: a push notification fires within 30 s of an immediate
attention item being scored, on both iOS and Android; voice "what's next"
returns a coherent spoken summary; SMS fallback works when push fails;
quiet hours suppress correctly except for immediate-critical class; telemetry
captures per-channel outcomes.

---

## 4. Dependency Graph

```
   Phase 39A (existing) ──┐
                           │
                           ▼
   AS1 (interaction telemetry) ──► AS2 (weight learning)
                           │
                           ├──────► AS3 (override rules)
                           │
                           └──────► AS4 (external signals)
                                       │
                                       ▼
                                  AS5 (cross-surface delivery)
```

AS1 is foundational. AS2/AS3/AS4 can land in any order after AS1; AS5 depends on
AS4 to have signal sources to deliver from.

---

## 5. Sizing

| Phase | Effort | Risk |
|---|---|---|
| AS1 — Interaction telemetry | 1.5 days | Low — instrumentation + cell-write |
| AS2 — Weight learning | 2 days | Medium — update rule needs tuning; profile selection logic |
| AS3 — Override rules | 1 day | Low — pattern matcher + REPL surface |
| AS4 — External signals | 2 days | Medium — three adapters + plug-in interface |
| AS5 — Cross-surface delivery | 1 day | Low — push + SMS + quiet hours |

**Total**: ~7.5 days for one engineer.

---

## 6. Commit Boundary Plan

1. `feat(services): AS1 — attention interaction telemetry + pinned/suppressed UX`
2. `feat(services): AS2 — per-operator attention weight learning + profile selection`
3. `feat(services): AS3 — attention override rules (pin/suppress/must-show)`
4. `feat(services): AS4 — external attention signal sources (weather + surfline + legacy + capability)`
5. `feat(services): AS5 — cross-surface attention delivery (push + voice + SMS)`

---

## 7. Acceptance Criteria

AS is done when:

1. Every interaction with the attention surface produces a signed
   telemetry cell; the operator can `attention telemetry --since
   "1 week ago"` and read what they did.
2. Weights demonstrably drift per operator over a week of usage;
   `attention status` is informative; `attention rollback` works.
3. Pin / suppress / must-show via both REPL and Helm context menu;
   conflict resolution documented; rule history complete.
4. Weather + Surfline + legacy-ingest + capability signals are
   plumbed and visible in the right panel with correct
   `extension_signal` reasons.
5. Mobile push fires within 30 s of urgency = immediate; voice
   "what's next" returns coherent summary; SMS fallback works;
   quiet hours respected.
6. End-to-end on OJT: operator runs the system for a week; the
   engine has correctly learned that he taps trades-job items 2x
   more than calendar events, that he ignores legacy-ingest
   newsletters, and that surf-condition pushes during work hours
   are dismissed within 5 s. The weight map shows it.

---

## 8. What AS Does Not Cover

- **Embeddings-based goal alignment**. The Phase 39A code stubs the
  goal-alignment factor at zero with a `// Phase 39B: EmbeddingService
  integration` comment. Wiring real embeddings is a separate workstream
  (the EmbeddingService already exists in `services/EmbeddingService.ts`)
  that lands as `AS2.5` or as a Phase 39C effort. AS2's weight learner
  treats the goal-alignment factor as one of the five even when its
  underlying signal is zero — that's fine; the learner will down-weight
  it organically until the embedding integration lands and gives it
  signal.
- **Federation-driven attention** — incoming dispatch envelopes from
  peer operators rank as attention signals, but the federation
  workstream itself (WF) is out of scope here.
- **Attention as a service to other operators** — sharing "what Todd is
  paying attention to today" with another operator (e.g. an apprentice
  who needs to know what's hot) — is a future cross-operator workstream,
  not a v1.0 concern.
- **Attention-driven automation** — using the attention signal to
  *trigger* actions ("if Henderson quote unanswered for 7 days, auto-
  re-send") — is the natural successor workstream but explicitly not
  AS's concern. AS surfaces; humans decide. Automation is an explicit
  policy declaration the operator authors, not an inferred behaviour.
- **Cross-operator weight sharing** — a tradie cooperative's operators
  could benefit from shared weight priors, but is opt-in cross-substrate
  knowledge transfer, deferred.

---

## 9. Cross-references

- **Phase 39A**: commit `044e88f` — `runtime/services/src/services/AttentionEngine.ts`,
  `apps/loom-react/src/helm/AttentionSurface.tsx`, types in
  `runtime/services/src/types/loom.ts`
- `docs/design/WALLET-SHELL-VPS-SUBSTRATE.md` — BRAIN provides the lmdb
  storage AS1 telemetry persists into and the REPL AS2/AS3 expose verbs
  on
- `docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md` — WSITE serves the
  Helm portal that hosts the attention surface; AS5's mobile push uses
  WSITE3 sessions
- `docs/design/WALLET-LEGACY-INGEST.md` — produces the legacy-ingest
  signals AS4 consumes; ratification queue surfaces here
- `docs/design/WALLET-VOICE-SHELL-GRAMMAR.md` — `find | next` is voice
  affordance for AS5's voice "what's next" surface; the voice
  parser's "acted-on" hook produces AS1 telemetry
- `docs/design/WALLET-MOBILE-AUTH-FLOW.md` — push notifications fire
  through the operator's session established via this flow
- `runtime/services/src/services/EmbeddingService.ts` — exists; the
  embedding-based goal-alignment factor's source (Phase 39B side-track)
- `apps/loom-react/src/helm/Helm.tsx` — mounts the engine + renderer
- `apps/loom-react/src/helm/CommandApprovalCard.tsx` — Phase 38G
  approval UX; voice-extracted commands targeting attention items
  flow through this
- BoM / OpenWeatherMap APIs — AS4 weather sources
- Surfline forecast API — AS4 surf source
- Web Push API (RFC 8030) + APNs / FCM — AS5 mobile push
