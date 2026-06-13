---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/TIER-2P-PHASE-D1-BRIEF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.658626+00:00
---

# Phase D.1 — Mobile `OddjobzAttentionClient` (agent brief)

**Pre-scoped 2026-05-06**, ready to fire the moment Phase B's PR lands.
**Tier**: 2P — see `docs/prd/TIER-2P-PASK-ATTENTION-MOBILE.md`
**Depends on**: Phase B (brain attention RPC verbs) — must be merged to main first.
**Subagent type**: `bsv-blockchain-wallet-toolbox-expert`

---

## Brief (paste directly to agent)

Working in `/Users/toddprice/projects/semantos-core/apps/oddjobz-mobile`.

# Task: Phase D.1 — Mobile OddjobzAttentionClient (Tier 2P)

Phase B has just shipped three new brain RPC verbs:
- `oddjobz.list_messages`
- `oddjobz.list_dispatch_decisions`
- `oddjobz.poll_attention_signals`

(See the merged PR — branch was `feat/tier2p-B-brain-attention-rpc`. Its PR description has the exact wire shape; also `runtime/legacy-ingest/src/conversation/turn-patch-store.ts` is the canonical TS-side type for messages, and `runtime/legacy-ingest/src/dispatch-router.ts` for dispatch decisions.)

You're building the **Dart client** parallel to the existing `OddjobzQueryClient`. Same channel (`HelmEventStream.callOddjobzQuery`), same timeout/error conventions, same model+factory pattern.

# What to ship

## File: `apps/oddjobz-mobile/lib/src/repl/oddjobz_attention_client.dart`

Mirror the structure of `oddjobz_query_client.dart` exactly. Read that file first to absorb the conventions:

- Top-of-file doc block referencing the matrix doc (`docs/prd/TIER-2P-PASK-ATTENTION-MOBILE.md`) and Phase B's PR.
- `export 'helm_event_stream.dart' show OddjobzQueryError;` so callers can catch errors without importing helm_event_stream.
- One `class` per record type with `final` fields, named `required` ctor, and a `factory fromJson(Map<String, dynamic>)`. Tolerate missing/null optional fields with the same defensive idiom (`r['x'] is String && (r['x'] as String).isNotEmpty ? ... : null`).
- One `OddjobzAttentionClient` class with constructor `(HelmEventStream stream, {Duration timeout = const Duration(seconds: 10)})` — mirror exactly.

## Models to define

### `OddjobzMessagePatch`

Mirrors the `oddjobz.message.v1` schema from `runtime/legacy-ingest/src/conversation/turn-patch-store.ts`:

```dart
class OddjobzMessagePatch {
  final String patchId;       // stable dedupe key
  final String providerId;    // 'meta' | 'gmail' | 'widget' | 'voice' | ...
  final String sessionId;     // e.g. 'meta:messenger:<asset>:<participant>'
  final String channel;       // 'meta_messenger' | 'meta_instagram' | 'gmail' | ...
  final String recipientId;   // asset id (page/ig account)
  final String role;          // 'customer' | 'assistant' | 'operator'
  final String text;
  final int timestamp;        // ms-epoch
  final OddjobzMessageSource? source;
  // ...
}

class OddjobzMessageSource {
  final String? platform;        // 'messenger' | 'instagram'
  final String? participantId;   // PSID / IGSID
  final String? senderId;
  final String? messageId;
  final String? threadId;
  final String? conversationId;
  // ...
}
```

Defensive `fromJson` for both. `OddjobzMessageSource.fromJson` returns null when the source map is null/empty.

### `OddjobzDispatchDecision`

Mirrors `runtime/legacy-ingest/src/dispatch-router.ts`:

```dart
enum OddjobzDispatchLane { self, direct, squad, agent, broadcast }
enum OddjobzDispatchTransport { none, direct, multicast, agent, broadcast }
enum OddjobzDispatchTargetType {
  job, customer, site, squad, agent, broadcastChannel, conversationSession
}

class OddjobzDispatchDecision {
  final String sourcePatchId;          // → OddjobzMessagePatch.patchId
  final OddjobzDispatchLane lane;
  final String slot;                   // 'talk.<lane>'
  final OddjobzDispatchTransport transport;
  final double confidence;             // 0.0–1.0
  final bool requiresRatification;
  final OddjobzDispatchTarget primaryTarget;
  final int timestamp;                 // ms-epoch
  // ...
}

class OddjobzDispatchTarget {
  final OddjobzDispatchTargetType type;
  final String ref;                    // e.g. job cellId
  final double score;                  // Pask graph proximity, 0.0–1.0
  // ...
}
```

Use `_parseLane`, `_parseTransport`, `_parseTargetType` helper functions (private) that map wire strings to enum values; default to a sensible fallback for unknown values rather than throwing (forward compatibility).

### `OddjobzAttentionSignal`

Mirrors Phase B's `poll_attention_signals` response shape:

```dart
enum OddjobzAttentionKind { dispatch, message, job }

class OddjobzAttentionSignal {
  final OddjobzAttentionKind kind;
  final double score;                       // 0.0–1.0
  final String ref;                         // id of underlying record
  final String summary;                     // short string for surface
  final int? expiresAt;                     // ms-epoch, optional
  final Map<String, dynamic> raw;           // original record — typed clients
                                            // can cast to MessagePatch /
                                            // DispatchDecision / Job as needed
  // ...
}
```

## Client methods

```dart
class OddjobzAttentionClient {
  final HelmEventStream _stream;
  final Duration timeout;

  OddjobzAttentionClient(this._stream,
      {this.timeout = const Duration(seconds: 10)});

  /// `oddjobz.list_messages(...)` — recent message patches in
  /// descending-timestamp order. All filter params are optional.
  Future<List<OddjobzMessagePatch>> listMessages({
    int? sinceMs,
    int? limit,
    String? providerId,
    String? sessionId,
  });

  /// `oddjobz.list_dispatch_decisions(...)` — recent dispatch
  /// decisions. All filter params optional.
  Future<List<OddjobzDispatchDecision>> listDispatchDecisions({
    int? sinceMs,
    int? limit,
    OddjobzDispatchLane? lane,
    bool? requiresRatification,
    OddjobzDispatchTargetType? primaryTargetType,
    String? primaryTargetRef,
  });

  /// `oddjobz.poll_attention_signals(limit:)` — aggregated ranked
  /// surface (dispatch + message + job signals).
  Future<List<OddjobzAttentionSignal>> pollAttentionSignals({
    int limit = 50,
  });
}
```

Each method:
- Builds the params map omitting nulls.
- Calls `_stream.callOddjobzQuery(verb, params, timeout: timeout)`.
- Pulls the array key (`messages`, `decisions`, or `signals` — whatever Phase B chose; check the merged PR's response shape).
- Maps via `whereType<Map<String, dynamic>>().map(Model.fromJson).toList()`.
- Returns `const []` if the array key is missing — match `oddjobz_query_client.dart`'s defensive style.

## Tests

Add `apps/oddjobz-mobile/test/repl/oddjobz_attention_client_test.dart` matching the existing query-client test layout (look for `oddjobz_query_client_test.dart` if it exists, otherwise check `test/` for the closest pattern).

Cover:
1. `listMessages()` with no filters — calls correct verb with empty params, parses 2-3 sample rows.
2. `listMessages(sinceMs: ..., providerId: 'meta')` — params map has only the non-null keys.
3. `listDispatchDecisions(lane: OddjobzDispatchLane.broadcast, requiresRatification: true)` — enum→string serialisation correct.
4. `pollAttentionSignals(limit: 25)` — parses signals with each `kind`; round-trips `raw` map intact.
5. Error path: server returns `OddjobzQueryError` — re-thrown unchanged.
6. Defensive parse: malformed rows skipped silently (`whereType`); unknown enum values default to a chosen fallback.

Use a mock `HelmEventStream` (the existing query-client test should show how — copy the mock pattern; do NOT introduce a new mocking framework).

# Constraints

- Do NOT touch `helm_event_stream.dart` unless Phase B's PR added a new helper there. If the existing `callOddjobzQuery` method serves these new verbs (it should — same dispatcher, same socket), use it as-is.
- Do NOT add new Flutter packages.
- Do NOT add Riverpod / Provider / Bloc — pure pure-Dart class, no widget tree integration. D.2 will build the consumer service on top.
- Match the existing file's tone in the doc comments — terse, references the matrix doc and Phase B's PR.
- Don't over-engineer — this is a typed wrapper over JSON-RPC, nothing more. D.2/D.3 will do the projection + UI.

# Verification

Before declaring done:
- `cd /Users/toddprice/projects/semantos-core/apps/oddjobz-mobile && flutter analyze` clean
- `flutter test test/repl/oddjobz_attention_client_test.dart` passes
- `flutter test` (full suite) passes — your additions don't break anything else
- `git diff --stat HEAD` should show ~2 files (the client + its test)

# PR

Branch `feat/tier2p-D1-mobile-attention-client` from current origin/main. Commit message starts "Tier 2P Phase D.1 — mobile OddjobzAttentionClient". PR body summarises: 3 record types defined, 3 client methods exposed, test coverage, ties-in to TIER-2P matrix's Wave-2.

Report back the PR URL + a 5-line summary including which Phase B verb each method calls.

---

## Notes for me (Claude) before firing

When Phase B lands:
1. Read its PR body to confirm the exact response keys (`messages` vs `rows` etc.) and the exact `raw` shape inside `pollAttentionSignals` items — update this brief if the agent's choices differ from my assumptions above.
2. Confirm `helm_event_stream.dart` didn't need changes (Phase B's agent might have added a helper).
3. Fire this brief as-is.

Ready to fire — operator approved pre-scoping.
