---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/conversation_turns_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.883318+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/conversation_turns_repository.dart

```dart
// ConversationTurnsRepository — bearer-gated Dio client for the
// canonical conversation turns endpoint on the Semantos Brain.
//
// Endpoints:
//   GET  /api/v1/conversation/turns?entityRef=<cellHash>&limit=<n>
//   POST /api/v1/conversation/turn/:id/approve
//
// Mirrors the ConversationSendApi pattern exactly (same Dio + baseUrl
// + bearer-closure construction) so it slots into the same HomeScreen
// late-init chain without new wiring boilerplate.

import 'package:dio/dio.dart';

import 'conversation_turn.dart';

export 'conversation_turn.dart';

/// Thrown when the brain returns a non-200 on a turns request.
class ConversationTurnsError implements Exception {
  /// Brain's `{"error":"<wire>"}` string.
  final String wire;

  /// HTTP status from the brain.
  final int httpStatus;

  const ConversationTurnsError({
    required this.wire,
    required this.httpStatus,
  });

  bool get isUnauthorised => httpStatus == 401;

  @override
  String toString() =>
      'ConversationTurnsError(http=$httpStatus, wire="$wire")';
}

class ConversationTurnsRepository {
  final Dio _http;
  final String _baseUrl;
  final String Function() _bearer;

  ConversationTurnsRepository({
    required Dio http,
    required String baseUrl,
    required String Function() bearer,
  })  : _http = http,
        _baseUrl = _stripTrailingSlash(baseUrl),
        _bearer = bearer;

  // ── Fetch ────────────────────────────────────────────────────────────

  /// Fetch up to [limit] conversation turns for the job cell identified
  /// by [entityRef] (the 64-hex cellId from the job row).  Returns the
  /// list in oldest-first order (ascending timestamp).
  ///
  /// Throws [ConversationTurnsError] for non-200 responses.
  Future<List<ConversationTurn>> fetchTurns({
    required String entityRef,
    int limit = 100,
  }) async {
    final resp = await _http.get<Map<String, dynamic>>(
      '$_baseUrl/api/v1/conversation/turns',
      queryParameters: <String, dynamic>{
        'entityRef': entityRef,
        'limit': limit,
      },
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${_bearer()}',
        },
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );

    final status = resp.statusCode ?? 0;
    final data = resp.data ?? const <String, dynamic>{};

    if (status != 200) {
      final wire =
          (data['error'] is String) ? data['error'] as String : '';
      throw ConversationTurnsError(wire: wire, httpStatus: status);
    }

    final list = data['turns'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ConversationTurn.fromJson)
        .toList();
  }

  // ── Voice note ───────────────────────────────────────────────────────

  /// Submit a voice note transcript anchored to a job/site/customer entity.
  ///
  /// [entityId] is the 64-hex cellId of the job/site/customer.
  /// [entityKind] must be `'job'`, `'site'`, or `'customer'`.
  /// [capturedAt] is an ISO-8601 timestamp (e.g. DateTime.now().toUtc().toIso8601String()).
  ///
  /// Returns the created [turnId] from the brain.
  /// Throws [ConversationTurnsError] for non-2xx responses.
  Future<String> submitVoiceNote({
    required String transcript,
    required String entityId,
    required String entityKind,
    required String capturedAt,
    double? durationSeconds,
    String? recordingId,
  }) async {
    final body = <String, dynamic>{
      'transcript': transcript,
      'entity_id': entityId,
      'entity_kind': entityKind,
      'captured_at': capturedAt,
      'duration_seconds': ?durationSeconds,
      'recording_id': ?recordingId,
    };

    // voice-note-intake.ts has no LLM step — it shells out a bun child
    // that writes one ConversationTurn to Postgres.  Even a cold-start
    // Postgres connection finishes well inside 15s on a healthy brain;
    // anything longer is failure-mode behaviour (Postgres unreachable,
    // bun child stuck, reactor backpressure) where blocking the
    // operator for a full minute is the wrong choice — fail fast and
    // let the caller surface the failed state inline.  Callers should
    // not `await` this in front of UI; see job_thread_screen.dart's
    // local-first composer for the canonical pattern.
    final resp = await _http.post<Map<String, dynamic>>(
      '$_baseUrl/api/v1/voice-note',
      data: body,
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${_bearer()}',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.json,
        validateStatus: (_) => true,
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

    final status = resp.statusCode ?? 0;
    final data = resp.data ?? const <String, dynamic>{};

    if (status != 201) {
      final wire =
          (data['error'] is String) ? data['error'] as String : '';
      throw ConversationTurnsError(wire: wire, httpStatus: status);
    }

    return (data['turn_id'] is String) ? data['turn_id'] as String : '';
  }

  // ── Approve ──────────────────────────────────────────────────────────

  /// Approve a proposed outbound turn, causing the brain to dispatch it.
  ///
  /// Throws [ConversationTurnsError] for non-200 responses.
  Future<void> approveTurn(String turnId) async {
    final resp = await _http.post<Map<String, dynamic>>(
      '$_baseUrl/api/v1/conversation/turn/$turnId/approve',
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${_bearer()}',
        },
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );

    final status = resp.statusCode ?? 0;
    if (status != 200) {
      final data = resp.data ?? const <String, dynamic>{};
      final wire =
          (data['error'] is String) ? data['error'] as String : '';
      throw ConversationTurnsError(wire: wire, httpStatus: status);
    }
  }

  static String _stripTrailingSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}

```
