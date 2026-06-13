---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/mesh/shard_proxy_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.902808+00:00
---

# archive/apps-semantos-monolith/lib/src/mesh/shard_proxy_client.dart

```dart
// D-O5m.followup-6 Phase 2 — Pure-Dart shard-proxy HTTP client.
//
// Reference: core/protocol-types/src/overlay/shard-proxy-client.ts
//   (the UDP-based desktop client).  Mobile can't open raw UDP sockets
//   on iOS without entitlement gymnastics, so we ship an HTTP relay
//   shape: POST /publish to push a signed bundle, GET /subscribe
//   long-polled to pull bundles addressed to this device's cert id.
//
// Responsibilities:
//   • Encode a SignedBundle to its canonical wire bytes (the codec
//     ships post-#329; we just call .encode()).
//   • POST those bytes to <shardProxyEndpoint>/publish?shard=<group>.
//   • Open a long-polled GET to <shardProxyEndpoint>/subscribe?shard=
//     <group>&recipient=<cert-id> and stream decoded bundles back to
//     the caller.
//
// The relay's wire shape is a substrate concern (each operator picks
// a relay implementation — bitcoin-shard-proxy w/ an HTTP front, or a
// tenant-owned Semantos Brain serving as a relay).  This client speaks the
// minimal contract: bundles in, bundles out, addressed by recipient
// cert id.
//
// Phase 2 ships the seam.  Phase 3 (federated relay) and beyond can
// swap the long-poll for a WebSocket without changing the seam.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'signed_bundle.dart';

/// Parsed shard-proxy endpoint.  Carries the base URL + the operator's
/// configured shard group id (derived from tenant manifest [mesh]).
class ShardProxyConfig {
  final String baseUrl;
  final String shardGroupId;

  /// Long-poll timeout in seconds.  The shard-proxy holds the GET open
  /// for this long before flushing whatever bundles it has buffered.
  /// 25s is the typical browser-tolerated cap (Cloudflare: 100s, Heroku:
  /// 30s, conservative default 25s).
  final int longPollTimeoutSeconds;

  /// Backoff base for exponential retry on network errors, in
  /// milliseconds.  Real wait = base * 2^attempt up to maxBackoffMs.
  final int retryBackoffBaseMs;
  final int retryMaxBackoffMs;

  const ShardProxyConfig({
    required this.baseUrl,
    required this.shardGroupId,
    this.longPollTimeoutSeconds = 25,
    this.retryBackoffBaseMs = 500,
    this.retryMaxBackoffMs = 30 * 1000,
  });
}

/// Pure-Dart shard-proxy client.  Handles publish + subscribe over
/// HTTP; tests inject a mocked Dio.
class ShardProxyClient {
  final ShardProxyConfig _config;
  final Dio _http;

  /// Whether a subscription stream is currently active.  Setting
  /// `close()` flips this so any in-flight long-poll loop unwinds at
  /// the next iteration.
  bool _closed = false;

  ShardProxyClient({
    required ShardProxyConfig config,
    required Dio http,
  })  : _config = config,
        _http = http;

  /// POST a SignedBundle to <baseUrl>/publish?shard=<group>.  Returns
  /// when the relay accepts the bundle (typically immediate); throws
  /// [ShardProxyError] on a non-2xx response.
  ///
  /// The bundle bytes are the canonical wire form (`bundle.encode()`).
  Future<void> publish({
    required SignedBundle bundle,
    String? overrideShardGroupId,
  }) async {
    if (_closed) {
      throw const ShardProxyError(
          reason: 'closed', message: 'shard-proxy client is closed');
    }
    final shard = overrideShardGroupId ?? _config.shardGroupId;
    final url = '${_config.baseUrl}/publish?shard=$shard';
    final body = bundle.encode();
    try {
      final resp = await _http.post<dynamic>(
        url,
        data: body,
        options: Options(
          contentType: 'application/json',
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
      final status = resp.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw ShardProxyError(
          reason: 'http_$status',
          message: 'shard-proxy publish failed (status=$status)',
          statusCode: status,
        );
      }
    } on DioException catch (e) {
      throw ShardProxyError(
        reason: 'network_error',
        message: e.message ?? e.type.toString(),
      );
    }
  }

  /// Long-polled GET <baseUrl>/subscribe?shard=<group>&recipient=
  /// <cert-id>.  Yields decoded SignedBundles addressed to
  /// `myCertId`; bundles addressed to other recipients are filtered
  /// out.  Reconnects with exponential backoff on transient errors.
  ///
  /// The stream is single-subscription (per the long-poll loop).
  /// Callers that need a broadcast should wrap with
  /// `.asBroadcastStream()`.
  Stream<SignedBundle> subscribe({
    required String myCertId,
  }) {
    final controller = StreamController<SignedBundle>(sync: false);
    () async {
      var attempt = 0;
      while (!_closed && !controller.isClosed) {
        try {
          final url = '${_config.baseUrl}/subscribe'
              '?shard=${_config.shardGroupId}'
              '&recipient=$myCertId'
              '&timeout=${_config.longPollTimeoutSeconds}';
          final resp = await _http.get<dynamic>(
            url,
            options: Options(
              responseType: ResponseType.json,
              validateStatus: (_) => true,
              receiveTimeout:
                  Duration(seconds: _config.longPollTimeoutSeconds + 5),
            ),
          );
          final status = resp.statusCode ?? 0;
          if (status == 204) {
            // No bundles available; loop and re-poll immediately (the
            // server held the request open until its long-poll window
            // expired, so we don't spam reconnects).
            attempt = 0;
            continue;
          }
          if (status < 200 || status >= 300) {
            // Non-204 non-2xx — treat as a retry-with-backoff error.
            await _backoff(attempt);
            attempt += 1;
            continue;
          }
          attempt = 0;
          // The relay emits an array of SignedBundle JSON envelopes.
          final data = resp.data;
          if (data is! List) {
            await _backoff(attempt);
            attempt += 1;
            continue;
          }
          for (final raw in data) {
            try {
              if (raw is! Map<String, dynamic>) continue;
              // Round-trip via the codec.  We re-encode the map to
              // wire bytes then decode — that ensures any malformed
              // entry surfaces here as a FormatException and is
              // dropped, while well-formed entries decode through the
              // proven codec path.
              final wireBytes = Uint8List.fromList(utf8.encode(jsonEncode(raw)));
              final bundle = SignedBundle.decode(wireBytes);
              if (bundle.recipientCertId != myCertId) {
                // Filter out bundles for other recipients.  The relay
                // SHOULD do this server-side but we re-verify defensively.
                continue;
              }
              if (controller.isClosed) return;
              controller.add(bundle);
            } catch (_) {
              // Drop malformed envelopes; the next loop iteration will
              // pick up the next batch.
            }
          }
        } on DioException catch (_) {
          await _backoff(attempt);
          attempt += 1;
        } catch (_) {
          await _backoff(attempt);
          attempt += 1;
        }
      }
      if (!controller.isClosed) {
        await controller.close();
      }
    }();

    controller.onCancel = () async {
      _closed = true;
    };

    return controller.stream;
  }

  /// Quick reachability check.  Returns true if the shard-proxy
  /// answers a HEAD or GET to its base URL within a short timeout.
  Future<bool> healthCheck() async {
    try {
      final resp = await _http.get<dynamic>(
        '${_config.baseUrl}/health',
        options: Options(
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      );
      final status = resp.statusCode ?? 0;
      return status >= 200 && status < 500;
    } catch (_) {
      return false;
    }
  }

  /// Close the client.  In-flight subscribe streams unwind on the next
  /// loop iteration.
  void close() {
    _closed = true;
  }

  Future<void> _backoff(int attempt) async {
    final ms =
        (_config.retryBackoffBaseMs * (1 << attempt)).clamp(0, _config.retryMaxBackoffMs);
    await Future<void>.delayed(Duration(milliseconds: ms));
  }
}

/// Typed error surface.  The mesh-transport seam wraps these into
/// MeshSendFailed / MeshTransportUnavailable.
class ShardProxyError implements Exception {
  final String reason;
  final String message;
  final int? statusCode;

  const ShardProxyError({
    required this.reason,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'ShardProxyError($reason): $message';
}

```
