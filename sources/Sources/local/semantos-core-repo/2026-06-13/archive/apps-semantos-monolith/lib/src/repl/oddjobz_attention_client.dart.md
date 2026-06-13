---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/oddjobz_attention_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.880012+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/oddjobz_attention_client.dart

```dart
// Tier 2P Phase D.1 — mobile OddjobzAttentionClient.
//
// Reference: docs/prd/TIER-2P-PASK-ATTENTION-MOBILE.md §Wave-2;
//            runtime/semantos-brain/src/oddjobz_attention_handler.zig — server side
//              (Phase B, PR #396);
//            runtime/legacy-ingest/src/conversation/turn-patch-store.ts
//              (OddjobzMessagePatch schema);
//            runtime/legacy-ingest/src/dispatch-router.ts
//              (ConversationDispatchDecision schema).
//
// Wraps the three Phase B attention verbs added to the Semantos Brain in PR #396:
//   `oddjobz.list_messages`          → [listMessages]
//   `oddjobz.list_dispatch_decisions` → [listDispatchDecisions]
//   `oddjobz.poll_attention_signals`  → [pollAttentionSignals]
//
// Wire shape note: unlike the `oddjobz.list_*` query verbs
// (which return `{"sites":[...]}` etc.), the Phase B attention
// verbs return a **bare JSON array** as the JSON-RPC `result`.
// This client dispatches via HelmEventStream.callOddjobzQueryList
// (added in the same PR as this client) which handles array-typed
// results.
//
// Scope for D.1: typed wrapper only.  D.2 builds the consumer
// service + Pask projection on top.

import 'dart:async';

import 'helm_event_stream.dart';

// Re-export so callers can catch [OddjobzQueryError] without importing
// helm_event_stream directly.
export 'helm_event_stream.dart' show OddjobzQueryError;

// ── Source object ────────────────────────────────────────────────────

/// Platform-level metadata attached to an [OddjobzMessagePatch].
/// All fields are optional — the source object may be absent (e.g.
/// for operator-generated messages) or partially populated on older
/// ingest paths.
class OddjobzMessageSource {
  /// 'messenger' | 'instagram' | …
  final String? platform;

  /// Platform-specific participant id (PSID / IGSID / …).
  final String? participantId;

  /// Sender id within the platform thread.
  final String? senderId;

  /// Platform-level message id for deduplication.
  final String? messageId;

  /// Thread / conversation container id.
  final String? threadId;

  /// Conversation session id (platform-level, not the Semantos Brain sessionId).
  final String? conversationId;

  const OddjobzMessageSource({
    required this.platform,
    required this.participantId,
    required this.senderId,
    required this.messageId,
    required this.threadId,
    required this.conversationId,
  });

  /// Returns null when [r] is null or an empty map — callers treat a
  /// missing source as no platform metadata rather than an error.
  static OddjobzMessageSource? fromJson(dynamic r) {
    if (r is! Map) return null;
    String? optStr(dynamic v) =>
        (v is String && v.isNotEmpty) ? v : null;
    final hasAny = r['platform'] != null ||
        r['participantId'] != null ||
        r['senderId'] != null ||
        r['messageId'] != null ||
        r['threadId'] != null ||
        r['conversationId'] != null;
    if (!hasAny) return null;
    return OddjobzMessageSource(
      platform: optStr(r['platform']),
      participantId: optStr(r['participantId']),
      senderId: optStr(r['senderId']),
      messageId: optStr(r['messageId']),
      threadId: optStr(r['threadId']),
      conversationId: optStr(r['conversationId']),
    );
  }
}

// ── Message patch ────────────────────────────────────────────────────

/// One row of the `oddjobz.list_messages` response.
///
/// Mirrors the `oddjobz.message.v1` schema written by the Codex
/// pipeline into `<data_dir>/oddjobz/messages.jsonl` and served
/// verbatim by the Semantos Brain attention handler.
class OddjobzMessagePatch {
  /// Stable dedupe key — the brain writes this once per ingest.
  final String patchId;

  /// Originating provider: 'meta' | 'gmail' | 'widget' | 'voice' | …
  final String providerId;

  /// Session identifier, e.g. 'meta:messenger:PAGE:PARTICIPANT'.
  final String sessionId;

  /// Channel: 'meta_messenger' | 'meta_instagram' | 'gmail' | …
  final String channel;

  /// Asset id of the receiving entity (page id, ig account, …).
  final String recipientId;

  /// Message author role: 'customer' | 'assistant' | 'operator'.
  final String role;

  /// Plain-text body of the message.
  final String text;

  /// Wall-clock send time as Unix milliseconds.
  final int timestamp;

  /// Optional platform-level metadata; null for operator-generated
  /// or voice-only messages.
  final OddjobzMessageSource? source;

  const OddjobzMessagePatch({
    required this.patchId,
    required this.providerId,
    required this.sessionId,
    required this.channel,
    required this.recipientId,
    required this.role,
    required this.text,
    required this.timestamp,
    required this.source,
  });

  /// Parse one message patch row from the wire shape.  Tolerates
  /// missing / null fields by substituting safe defaults — a missing
  /// required string becomes '' and timestamp 0 rather than throwing
  /// so a single malformed row doesn't crash the list.
  factory OddjobzMessagePatch.fromJson(Map<String, dynamic> r) =>
      OddjobzMessagePatch(
        patchId: (r['patchId'] ?? '').toString(),
        providerId: (r['providerId'] ?? '').toString(),
        sessionId: (r['sessionId'] ?? '').toString(),
        channel: (r['channel'] ?? '').toString(),
        recipientId: (r['recipientId'] ?? '').toString(),
        role: (r['role'] ?? '').toString(),
        text: (r['text'] ?? '').toString(),
        timestamp: r['timestamp'] is int
            ? r['timestamp'] as int
            : (r['timestamp'] is num
                ? (r['timestamp'] as num).toInt()
                : 0),
        source: OddjobzMessageSource.fromJson(r['source']),
      );
}

// ── Dispatch decision enums + models ─────────────────────────────────

/// Routing lane for a dispatch decision.
enum OddjobzDispatchLane { self, direct, squad, agent, broadcast }

/// Transport mechanism selected by the router.
enum OddjobzDispatchTransport { none, direct, multicast, agent, broadcast }

/// Category of the primary routing target.
enum OddjobzDispatchTargetType {
  job,
  customer,
  site,
  squad,
  agent,
  broadcastChannel,
  conversationSession,
}

OddjobzDispatchLane _parseLane(dynamic v) {
  if (v is! String) return OddjobzDispatchLane.self;
  switch (v) {
    case 'direct':
      return OddjobzDispatchLane.direct;
    case 'squad':
      return OddjobzDispatchLane.squad;
    case 'agent':
      return OddjobzDispatchLane.agent;
    case 'broadcast':
      return OddjobzDispatchLane.broadcast;
    default:
      return OddjobzDispatchLane.self;
  }
}

OddjobzDispatchTransport _parseTransport(dynamic v) {
  if (v is! String) return OddjobzDispatchTransport.none;
  switch (v) {
    case 'direct':
      return OddjobzDispatchTransport.direct;
    case 'multicast':
      return OddjobzDispatchTransport.multicast;
    case 'agent':
      return OddjobzDispatchTransport.agent;
    case 'broadcast':
      return OddjobzDispatchTransport.broadcast;
    default:
      return OddjobzDispatchTransport.none;
  }
}

OddjobzDispatchTargetType _parseTargetType(dynamic v) {
  if (v is! String) return OddjobzDispatchTargetType.job;
  switch (v) {
    case 'customer':
      return OddjobzDispatchTargetType.customer;
    case 'site':
      return OddjobzDispatchTargetType.site;
    case 'squad':
      return OddjobzDispatchTargetType.squad;
    case 'agent':
      return OddjobzDispatchTargetType.agent;
    case 'broadcast-channel':
      return OddjobzDispatchTargetType.broadcastChannel;
    case 'conversation-session':
      return OddjobzDispatchTargetType.conversationSession;
    default:
      return OddjobzDispatchTargetType.job;
  }
}

/// The primary target of a dispatch decision — the entity the router
/// chose to route towards.
class OddjobzDispatchTarget {
  /// Target category.
  final OddjobzDispatchTargetType type;

  /// Cell id / entity ref of the target (e.g. a job cellId).
  final String ref;

  /// Pask graph proximity score, 0.0–1.0.
  final double score;

  const OddjobzDispatchTarget({
    required this.type,
    required this.ref,
    required this.score,
  });

  factory OddjobzDispatchTarget.fromJson(Map<String, dynamic> r) =>
      OddjobzDispatchTarget(
        type: _parseTargetType(r['type']),
        ref: (r['ref'] ?? '').toString(),
        score: r['score'] is num ? (r['score'] as num).toDouble() : 0.0,
      );
}

/// One row of the `oddjobz.list_dispatch_decisions` response.
///
/// Mirrors `ConversationDispatchDecision` from
/// `runtime/legacy-ingest/src/dispatch-router.ts`.
class OddjobzDispatchDecision {
  /// References [OddjobzMessagePatch.patchId] of the triggering patch.
  final String sourcePatchId;

  /// Routing lane chosen by the dispatch router.
  final OddjobzDispatchLane lane;

  /// Slot string, typically 'talk.LANE'.
  final String slot;

  /// Transport mechanism selected for this decision.
  final OddjobzDispatchTransport transport;

  /// Router confidence, 0.0–1.0.
  final double confidence;

  /// True when this decision requires operator ratification before
  /// any action is taken.
  final bool requiresRatification;

  /// Primary routing target.
  final OddjobzDispatchTarget primaryTarget;

  /// Wall-clock decision time as Unix milliseconds (uses `writtenAt`
  /// if present, else `timestamp`, else 0 — mirrors server fallback).
  final int timestamp;

  const OddjobzDispatchDecision({
    required this.sourcePatchId,
    required this.lane,
    required this.slot,
    required this.transport,
    required this.confidence,
    required this.requiresRatification,
    required this.primaryTarget,
    required this.timestamp,
  });

  factory OddjobzDispatchDecision.fromJson(Map<String, dynamic> r) {
    final ptRaw = r['primaryTarget'];
    final pt = (ptRaw is Map<String, dynamic>)
        ? OddjobzDispatchTarget.fromJson(ptRaw)
        : (ptRaw is Map
            ? OddjobzDispatchTarget.fromJson(
                Map<String, dynamic>.from(ptRaw))
            : OddjobzDispatchTarget(
                type: OddjobzDispatchTargetType.job,
                ref: '',
                score: 0.0,
              ));
    final ts = r['writtenAt'] is int
        ? r['writtenAt'] as int
        : (r['writtenAt'] is num
            ? (r['writtenAt'] as num).toInt()
            : (r['timestamp'] is int
                ? r['timestamp'] as int
                : (r['timestamp'] is num
                    ? (r['timestamp'] as num).toInt()
                    : 0)));
    return OddjobzDispatchDecision(
      sourcePatchId: (r['sourcePatchId'] ?? '').toString(),
      lane: _parseLane(r['lane']),
      slot: (r['slot'] ?? '').toString(),
      transport: _parseTransport(r['transport']),
      confidence:
          r['confidence'] is num ? (r['confidence'] as num).toDouble() : 0.0,
      requiresRatification: r['requiresRatification'] == true,
      primaryTarget: pt,
      timestamp: ts,
    );
  }
}

// ── Attention signal ─────────────────────────────────────────────────

/// Kind of an [OddjobzAttentionSignal].
enum OddjobzAttentionKind { dispatch, message, job }

OddjobzAttentionKind _parseKind(dynamic v) {
  if (v is! String) return OddjobzAttentionKind.message;
  switch (v) {
    case 'dispatch':
      return OddjobzAttentionKind.dispatch;
    case 'job':
      return OddjobzAttentionKind.job;
    default:
      return OddjobzAttentionKind.message;
  }
}

/// One item from the `oddjobz.poll_attention_signals` response.
///
/// Aggregates dispatch decisions, customer messages, and open jobs
/// into a ranked surface for the mobile attention UI.
class OddjobzAttentionSignal {
  /// Source type of this signal.
  final OddjobzAttentionKind kind;

  /// Attention priority score, 0.0–1.0.
  final double score;

  /// Stable reference id of the underlying record (patchId for
  /// messages, sourcePatchId for dispatch, job id for jobs).
  final String ref;

  /// Short human-readable description suitable for a surface banner.
  final String summary;

  /// Optional expiry time as Unix milliseconds.  Null when the signal
  /// has no defined lifetime.
  final int? expiresAt;

  /// Original record verbatim.  Typed consumers can cast to
  /// [OddjobzMessagePatch] / [OddjobzDispatchDecision] as needed.
  final Map<String, dynamic> raw;

  const OddjobzAttentionSignal({
    required this.kind,
    required this.score,
    required this.ref,
    required this.summary,
    required this.expiresAt,
    required this.raw,
  });

  factory OddjobzAttentionSignal.fromJson(Map<String, dynamic> r) {
    final rawVal = r['raw'];
    final rawMap = rawVal is Map<String, dynamic>
        ? rawVal
        : (rawVal is Map
            ? Map<String, dynamic>.from(rawVal)
            : const <String, dynamic>{});
    final expiresAtRaw = r['expiresAt'];
    final expiresAt = expiresAtRaw is int
        ? expiresAtRaw
        : (expiresAtRaw is num ? expiresAtRaw.toInt() : null);
    return OddjobzAttentionSignal(
      kind: _parseKind(r['kind']),
      score: r['score'] is num ? (r['score'] as num).toDouble() : 0.0,
      ref: (r['ref'] ?? '').toString(),
      summary: (r['summary'] ?? '').toString(),
      expiresAt: expiresAt,
      raw: rawMap,
    );
  }
}

// ── Client ───────────────────────────────────────────────────────────

/// Typed client over the three Phase B attention verbs.  Stateless
/// apart from the [HelmEventStream] it dispatches through; the WSS
/// lifecycle is owned by HelmEventStream itself.
///
/// All methods throw:
///   - [StateError] — when the underlying WSS isn't open.
///   - [OddjobzQueryError] — on a JSON-RPC error reply.
///   - [TimeoutException] — when the brain doesn't reply within the
///     supplied timeout (defaults to 10s).
class OddjobzAttentionClient {
  final HelmEventStream _stream;

  /// Default timeout for any single RPC.
  final Duration timeout;

  OddjobzAttentionClient(
    this._stream, {
    // 2026-05-07: bumped default from 10s → 30s.  At operator-
    // realistic data volumes (822 messages + 822 dispatch decisions
    // post-overnight gmail ingest) the 10s budget repeatedly tripped
    // — Bridget flagged this on her ngrok demo, then the operator's
    // first connect to brain.oddjobtodd.info showed the same
    // TimeoutException loop in AttentionService init.  30s is
    // generous enough for the full list-query transfer over a
    // typical Caddy → brain reactor path on residential bandwidth;
    // most calls return in <500ms anyway.
    this.timeout = const Duration(seconds: 30),
  });

  /// `oddjobz.list_messages(...)` — recent message patches in
  /// descending-timestamp order.  All filter params are optional;
  /// omitting them returns all stored patches up to the server default
  /// limit (100).
  Future<List<OddjobzMessagePatch>> listMessages({
    int? sinceMs,
    int? limit,
    String? providerId,
    String? sessionId,
  }) async {
    final params = <String, dynamic>{};
    if (sinceMs != null) params['since'] = sinceMs;
    if (limit != null) params['limit'] = limit;
    if (providerId != null) params['providerId'] = providerId;
    if (sessionId != null) params['sessionId'] = sessionId;

    final raw = await _stream.callOddjobzQueryList(
      'oddjobz.list_messages',
      params,
      timeout: timeout,
    );
    return raw
        .whereType<Map<String, dynamic>>()
        .map(OddjobzMessagePatch.fromJson)
        .toList();
  }

  /// `oddjobz.list_dispatch_decisions(...)` — recent dispatch
  /// decisions in descending-timestamp order.  All filter params are
  /// optional.
  ///
  /// [lane] is serialised as the wire string ('self' | 'direct' |
  /// 'squad' | 'agent' | 'broadcast').
  Future<List<OddjobzDispatchDecision>> listDispatchDecisions({
    int? sinceMs,
    int? limit,
    OddjobzDispatchLane? lane,
    bool? requiresRatification,
    OddjobzDispatchTargetType? primaryTargetType,
    String? primaryTargetRef,
  }) async {
    final params = <String, dynamic>{};
    if (sinceMs != null) params['since'] = sinceMs;
    if (limit != null) params['limit'] = limit;
    if (lane != null) params['lane'] = _laneToWire(lane);
    if (requiresRatification != null) {
      params['requiresRatification'] = requiresRatification;
    }
    if (primaryTargetType != null) {
      params['primaryTargetType'] = _targetTypeToWire(primaryTargetType);
    }
    if (primaryTargetRef != null) {
      params['primaryTargetRef'] = primaryTargetRef;
    }

    final raw = await _stream.callOddjobzQueryList(
      'oddjobz.list_dispatch_decisions',
      params,
      timeout: timeout,
    );
    return raw
        .whereType<Map<String, dynamic>>()
        .map(OddjobzDispatchDecision.fromJson)
        .toList();
  }

  /// `oddjobz.poll_attention_signals(limit:)` — aggregated ranked
  /// attention surface drawn from dispatch decisions, customer
  /// messages, and open jobs with near due dates.
  Future<List<OddjobzAttentionSignal>> pollAttentionSignals({
    int limit = 50,
  }) async {
    final raw = await _stream.callOddjobzQueryList(
      'oddjobz.poll_attention_signals',
      {'limit': limit},
      timeout: timeout,
    );
    return raw
        .whereType<Map<String, dynamic>>()
        .map(OddjobzAttentionSignal.fromJson)
        .toList();
  }
}

// ── Wire-string serialisers ──────────────────────────────────────────

String _laneToWire(OddjobzDispatchLane lane) {
  switch (lane) {
    case OddjobzDispatchLane.self:
      return 'self';
    case OddjobzDispatchLane.direct:
      return 'direct';
    case OddjobzDispatchLane.squad:
      return 'squad';
    case OddjobzDispatchLane.agent:
      return 'agent';
    case OddjobzDispatchLane.broadcast:
      return 'broadcast';
  }
}

String _targetTypeToWire(OddjobzDispatchTargetType t) {
  switch (t) {
    case OddjobzDispatchTargetType.job:
      return 'job';
    case OddjobzDispatchTargetType.customer:
      return 'customer';
    case OddjobzDispatchTargetType.site:
      return 'site';
    case OddjobzDispatchTargetType.squad:
      return 'squad';
    case OddjobzDispatchTargetType.agent:
      return 'agent';
    case OddjobzDispatchTargetType.broadcastChannel:
      return 'broadcast-channel';
    case OddjobzDispatchTargetType.conversationSession:
      return 'conversation-session';
  }
}

```
