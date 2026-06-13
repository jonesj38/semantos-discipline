---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/conversation_send_api.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.879133+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/conversation_send_api.dart

```dart
// Dio-backed client for POST /api/v1/conversation/<id>/send.
//
// W5 of CUSTOMER-CONV-LOOP-PLAN. The endpoint is implemented by the
// brain in runtime/semantos-brain/src/conversation_send_http.zig
// (W2.1-W2.5).  When Twilio is configured (/var/lib/semantos/
// twilio.json present), this dispatches a real SMS to the contact.
//
// `conversationId` in the brain's model is the customer.v2 id —
// "one conversation per contact" per Todd's REA + 3 tenants pattern.
//
// Error model: brain returns {"error":"<wire>"} for non-200 paths.
// We surface the wire name + http status so callers can show actionable
// messages (e.g. "twilio_not_configured" → "Operator hasn't set up
// Twilio yet"; "invalid_recipient" → "Phone number is invalid").

import 'package:dio/dio.dart';

class ConversationSendResult {
  /// Twilio message SID — primary record of truth in the SMS provider.
  final String sid;

  /// Twilio status (queued / sent / delivered / failed at provider).
  final String status;

  const ConversationSendResult({required this.sid, required this.status});
}

/// Recoverable error from the brain's POST /api/v1/conversation/<id>/send.
/// Distinguishes wire-name (typed semantics, mappable to user-facing
/// language) from raw http status (for diagnostics).
class ConversationSendError implements Exception {
  /// Brain's `{"error":"<wire>"}` field. Known values:
  ///   unauthorised, conversation_not_found, twilio_not_configured,
  ///   malformed_body, invalid_recipient, rate_limited, upstream_error.
  /// Empty if the response wasn't well-formed JSON.
  final String wire;

  /// HTTP status code from the brain.
  final int httpStatus;

  const ConversationSendError({required this.wire, required this.httpStatus});

  @override
  String toString() => 'ConversationSendError(http=$httpStatus, wire="$wire")';

  /// Translate to a user-facing message — keep these short, the UI
  /// shows them as a snackbar.
  String get userMessage {
    switch (wire) {
      case 'unauthorised':
        return 'Not authorised — please re-pair this device.';
      case 'conversation_not_found':
        return 'Contact not found on this brain.';
      case 'twilio_not_configured':
        return 'SMS not yet configured on the operator brain.';
      case 'malformed_body':
        return 'Message body was rejected by the brain.';
      case 'invalid_recipient':
        return 'Phone number is invalid for SMS.';
      case 'rate_limited':
        return 'SMS rate-limited — try again in a moment.';
      case 'upstream_error':
        return 'SMS provider returned an error.';
      default:
        return 'Send failed ($httpStatus).';
    }
  }
}

class ConversationSendApi {
  final Dio _http;
  final String _baseUrl;
  final String Function() _bearer;

  ConversationSendApi({
    required Dio http,
    required String baseUrl,
    required String Function() bearer,
  })  : _http = http,
        _baseUrl = _stripTrailingSlash(baseUrl),
        _bearer = bearer;

  /// POST /api/v1/conversation/<id>/send with body `{"body": <text>}`.
  /// Throws [ConversationSendError] for any non-200 response.
  Future<ConversationSendResult> send({
    required String conversationId,
    required String body,
  }) async {
    final resp = await _http.post<Map<String, dynamic>>(
      '$_baseUrl/api/v1/conversation/$conversationId/send',
      data: <String, dynamic>{'body': body},
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${_bearer()}',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );

    final status = resp.statusCode ?? 0;
    final data = resp.data ?? const <String, dynamic>{};

    if (status == 200 && (data['sent'] == true)) {
      return ConversationSendResult(
        sid: (data['sid'] ?? '').toString(),
        status: (data['status'] ?? '').toString(),
      );
    }

    final wire = (data['error'] is String) ? data['error'] as String : '';
    throw ConversationSendError(wire: wire, httpStatus: status);
  }

  static String _stripTrailingSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}

```
