---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/messagebox_api.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.884244+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/messagebox_api.dart

```dart
// D-network-messagebox-first-class — MessageboxApi: HTTP client for the
// brain's /api/v1/messages/* endpoints.
//
// Auth model (matches the brain):
//   POST /send   — no bearer (open deposit; envelope self-authenticates)
//   GET  /list   — bearer required (recipient-only)
//   POST /ack    — bearer required (recipient-only)
//
// V1 payload encoding: UTF-8 text → base64.  The brain stores the bytes
// opaquely; the receiving client base64-decodes and renders as text.
// BRC-77 signed / BRC-78 encrypted envelopes will replace this in a
// follow-on wave.
//
// Usage:
//   final api = MessageboxApi(
//     http: dio,
//     localBrainBaseUrl: 'https://brain.oddjobtodd.info',
//     bearer: record.bearer,
//   );
//   // Send to Bridget's brain:
//   await api.send(
//     remoteBrainUrl: 'https://brain.utxoengineer.com',
//     recipientHex: '02abc...',
//     senderHex: '029cf8...',
//     text: 'hello from Todd',
//   );
//   // Read own inbox:
//   final msgs = await api.list(myPubkeyHex);

import 'dart:convert';

import 'package:dio/dio.dart';

// ── MessageboxMessage ─────────────────────────────────────────────────────

class MessageboxMessage {
  final String id;
  final String senderHex;
  final String kind;
  final String payloadB64;
  final int tsMs;

  const MessageboxMessage({
    required this.id,
    required this.senderHex,
    required this.kind,
    required this.payloadB64,
    required this.tsMs,
  });

  static MessageboxMessage? fromJson(Map<String, dynamic> m) {
    final id = m['id'];
    final sender = m['sender'];
    final kind = m['kind'];
    final payload = m['payload'];
    final ts = m['ts'];
    if (id is! String || sender is! String || kind is! String ||
        payload is! String) {
      return null;
    }
    final tsMs = ts is int ? ts : (ts is num ? ts.toInt() : 0);
    return MessageboxMessage(
      id: id,
      senderHex: sender,
      kind: kind,
      payloadB64: payload,
      tsMs: tsMs,
    );
  }

  /// Try to decode [payloadB64] as UTF-8 text.
  /// Returns null if the bytes are not valid UTF-8 (i.e. a real
  /// BRC-77/78 binary envelope — not a V1 plaintext message).
  String? get text {
    try {
      return utf8.decode(base64Decode(payloadB64));
    } catch (_) {
      return null;
    }
  }

  /// Abbreviated sender for display: first 8 + last 4 hex chars.
  String get senderShort {
    if (senderHex.length < 12) return senderHex;
    return '${senderHex.substring(0, 8)}…${senderHex.substring(senderHex.length - 4)}';
  }
}

// ── MessageboxApi ─────────────────────────────────────────────────────────

class MessageboxApi {
  final Dio http;

  /// Base URL of the local brain (e.g. "https://brain.oddjobtodd.info").
  /// Used for list and ack (recipient-only, bearer-gated).
  final String localBrainBaseUrl;

  /// Bearer token valid on the local brain.
  final String bearer;

  const MessageboxApi({
    required this.http,
    required this.localBrainBaseUrl,
    required this.bearer,
  });

  // ── Send ────────────────────────────────────────────────────────────

  /// Send [text] to [recipientHex] by depositing a message on
  /// [remoteBrainUrl] (the recipient's brain).
  ///
  /// No bearer is required — the remote brain's /send endpoint is open.
  ///
  /// Returns the 32-char hex message ID assigned by the remote brain.
  /// Throws [DioException] on network or server error.
  Future<String> send({
    required String remoteBrainUrl,
    required String recipientHex,
    required String senderHex,
    required String text,
  }) async {
    final payloadB64 = base64Encode(utf8.encode(text));
    final resp = await http.post<Map<String, dynamic>>(
      '$remoteBrainUrl/api/v1/messages/send',
      data: {
        'recipient': recipientHex,
        'kind': 'signed',
        'payload': payloadB64,
        'sender': senderHex,
      },
      options: Options(
        contentType: 'application/json',
        responseType: ResponseType.json,
      ),
    );
    final data = resp.data;
    if (data == null) throw StateError('empty response from /messages/send');
    return data['id'] as String;
  }

  // ── List ────────────────────────────────────────────────────────────

  /// Fetch pending messages from the local brain addressed to
  /// [recipientHex].  Requires a valid bearer token.
  ///
  /// Returns an empty list when there are no pending messages or on a
  /// non-fatal parse error; rethrows [DioException] for network failures.
  Future<List<MessageboxMessage>> list(String recipientHex) async {
    final resp = await http.get<Map<String, dynamic>>(
      '$localBrainBaseUrl/api/v1/messages/list',
      queryParameters: {'recipient': recipientHex},
      options: Options(
        headers: {'Authorization': 'Bearer $bearer'},
        responseType: ResponseType.json,
      ),
    );
    final data = resp.data;
    if (data == null) return [];
    final msgs = data['messages'];
    if (msgs is! List) return [];
    return msgs
        .whereType<Map<String, dynamic>>()
        .map(MessageboxMessage.fromJson)
        .whereType<MessageboxMessage>()
        .toList();
  }

  // ── Ack ─────────────────────────────────────────────────────────────

  /// Acknowledge (remove) message [id] from the local brain's store.
  /// Requires a valid bearer token.
  ///
  /// Throws [DioException] on network error; the brain returns 404 for
  /// an unknown id.
  Future<void> ack(String id) async {
    await http.post<void>(
      '$localBrainBaseUrl/api/v1/messages/ack',
      data: {'id': id},
      options: Options(
        contentType: 'application/json',
        headers: {'Authorization': 'Bearer $bearer'},
      ),
    );
  }
}

```
