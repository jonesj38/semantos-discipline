---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/repl_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.880618+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/repl_client.dart

```dart
// D-O5m — bearer-gated REPL HTTP client (mobile-helm side).
//
// Port of `apps/loom-svelte/src/lib/repl-client.ts`. Wire shape
// (request):
//
//     POST <brainPairEndpoint-host>/api/v1/repl
//     Authorization: Bearer <hex64>
//     Content-Type: application/json
//     {"cmd": "<repl-line>"}
//
// Wire shape (response) — see `runtime/semantos-brain/src/repl_http.zig`:
//
//     200 → {"result": "<captured stdout>", "exit": "continue" | "quit"}
//     401 → {"error": "..."}     → ReplUnauthorisedError
//     400 → {"error": "..."}     → ReplValidationError
//     503 → {"error": "..."}     → ReplBackendUnavailable
//
// IMPORTANT — D-O5m-MVP scope: mirrors the desktop SPA's best-effort
// text-parsing posture (D-O5.followup-1). The first time we hit a
// view that needs structured output we'll add a typed dispatcher
// resource (e.g. `find_jobs`) and surface it through this client as
// a typed method. Tracked as D-O5m.followup-4 in deliverables.yml.

import 'package:dio/dio.dart';

import 'repl_errors.dart';

/// Successful REPL response.
class ReplOk {
  /// Captured stdout from the REPL handler.
  final String result;

  /// "continue" or "quit" — the helm shell uses this to decide
  /// whether to stay in the same session or transition state.
  final String exit;

  const ReplOk({required this.result, required this.exit});
}

/// Bearer-gated REPL client. The bearer token is sourced from a
/// closure so token-rotation handlers don't need to plumb the new
/// value through every call site.
class ReplClient {
  final Dio _http;
  final String _baseUrl;
  final String? Function() _bearerSource;

  ReplClient({
    required Dio http,
    required String baseUrl,
    required String? Function() bearerSource,
  })  : _http = http,
        _baseUrl = _stripTrailingSlash(baseUrl),
        _bearerSource = bearerSource;

  /// Build a ReplClient from a static bearer string. Convenience for
  /// tests + the helm screens (which pull the bearer from
  /// ChildCertStore at construction time).
  factory ReplClient.withBearer({
    required Dio http,
    required String baseUrl,
    required String bearer,
  }) =>
      ReplClient(
        http: http,
        baseUrl: baseUrl,
        bearerSource: () => bearer,
      );

  /// Send a single REPL line. Throws a typed exception on non-2xx;
  /// otherwise returns a [ReplOk]. The 401 path clears nothing
  /// here — the caller (typically `JobsRepository.findJobs` or the
  /// helm screen's catch handler) decides whether to call
  /// [clearAuth].
  ///
  /// [receiveTimeout] overrides the Dio default for this call only.
  /// LLM-backed commands (llm complete, llm vision) can take 15–45s —
  /// pass Duration(seconds: 90) for those paths.
  Future<ReplOk> send(String cmd, {Duration? receiveTimeout}) async {
    final bearer = _bearerSource();
    final headers = <String, String>{
      'content-type': 'application/json',
    };
    if (bearer != null) {
      headers['authorization'] = 'Bearer $bearer';
    }

    Response<dynamic> resp;
    try {
      resp = await _http.postUri<dynamic>(
        Uri.parse('$_baseUrl/api/v1/repl'),
        data: {'cmd': cmd},
        options: Options(
          headers: headers,
          // Don't throw on non-2xx; we surface typed exceptions.
          validateStatus: (_) => true,
          responseType: ResponseType.json,
          receiveTimeout: receiveTimeout,
        ),
      );
    } on DioException catch (e) {
      throw ReplError('network error: ${e.message ?? e.type.name}');
    }

    final status = resp.statusCode ?? 0;
    final body = resp.data;

    if (status == 401) {
      throw ReplUnauthorisedError(_extractError(body) ??
          'REPL bearer token rejected by brain');
    }
    if (status == 400) {
      throw ReplValidationError(
        _extractError(body) ?? 'REPL validation failed',
        body: body is Map ? Map<String, Object?>.from(body) : null,
      );
    }
    if (status == 503) {
      throw ReplBackendUnavailable(_extractError(body) ??
          'REPL backend not enabled in this serve mode');
    }
    if (status < 200 || status >= 300) {
      throw ReplError(
          'REPL returned HTTP $status: ${_extractError(body) ?? body ?? ""}');
    }
    if (body is! Map) {
      throw const ReplError('REPL response was not a JSON object');
    }
    final result = body['result'];
    final exit = body['exit'];
    if (result is! String || exit is! String) {
      // 200 response with `error` field — brain REPL surfaces this via
      // the same body shape on certain paths.
      final err = body['error'];
      if (err is String) {
        throw ReplValidationError(
          err,
          body: Map<String, Object?>.from(body),
        );
      }
      throw const ReplError('REPL response missing result/exit fields');
    }
    return ReplOk(result: result, exit: exit);
  }
}

String? _extractError(dynamic body) {
  if (body is Map && body['error'] is String) return body['error'] as String;
  return null;
}

String _stripTrailingSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;

```
