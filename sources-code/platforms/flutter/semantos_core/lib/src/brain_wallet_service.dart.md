---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/brain_wallet_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.014668+00:00
---

# platforms/flutter/semantos_core/lib/src/brain_wallet_service.dart

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'wallet_service.dart';

/// [WalletService] implementation that calls POST /api/v1/wallet-op on a
/// running `brain` instance. Used when the mobile app is online and the
/// operator has a brain process reachable at [baseUrl].
///
/// The [bearerToken] is a 64-hex-char token issued by `brain bearer issue`.
/// All requests are sent to `$baseUrl/api/v1/wallet-op`.
///
/// Error handling: throws [BrainWalletException] on API errors (4xx/5xx)
/// and rethrows [http.ClientException] for network failures.
class BrainWalletService implements WalletService {
  final String baseUrl;
  final String bearerToken;
  final http.Client _client;

  BrainWalletService({
    required this.baseUrl,
    required this.bearerToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<PayResult> pay(List<Output> outputs, {String? description}) async {
    final body = {
      'action': 'pay',
      'outputs': outputs.map((o) => o.toJson()).toList(),
      if (description != null) 'description': description,
    };
    final txid = await _dispatch(body);
    return PayResult(txid: txid);
  }

  @override
  Future<AnchorResult> anchorTransition(
    Uint8List typeHash,
    int anchorIndex,
    Uint8List newStateHash, {
    String? description,
  }) async {
    final body = {
      'action': 'anchorTransition',
      'typeHash': _hex(typeHash),
      'anchorIndex': anchorIndex,
      'newStateHash': _hex(newStateHash),
      if (description != null) 'description': description,
    };
    final txid = await _dispatch(body);
    return AnchorResult(txid: txid);
  }

  @override
  Future<PayResult> createAction(
    List<TxInput> inputs,
    List<Output> outputs, {
    String? description,
  }) async {
    final body = {
      'action': 'createAction',
      'inputs': inputs.map((i) => i.toJson()).toList(),
      'outputs': outputs.map((o) => o.toJson()).toList(),
      if (description != null) 'description': description,
    };
    final txid = await _dispatch(body);
    return PayResult(txid: txid);
  }

  @override
  Future<String> identityPubkeyHex() async {
    final body = {'action': 'identityPubkey'};
    final resp = await _post(body);
    final json = _parseJson(resp);
    final pubkey = json['pubkey'];
    if (pubkey is! String) {
      throw BrainWalletException('identityPubkey: unexpected response shape');
    }
    return pubkey;
  }

  Future<String> _dispatch(Map<String, dynamic> body) async {
    final resp = await _post(body);
    final json = _parseJson(resp);
    final txid = json['txid'];
    if (txid is! String) {
      throw BrainWalletException(
          'wallet-op ${body['action']}: unexpected response shape');
    }
    return txid;
  }

  Future<http.Response> _post(Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl/api/v1/wallet-op');
    final resp = await _client.post(
      uri,
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $bearerToken',
      },
      body: jsonEncode(body),
    );
    if (resp.statusCode >= 400) {
      Map<String, dynamic> errorBody = {};
      try {
        errorBody = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {}
      final msg = errorBody['error']?.toString() ??
          'HTTP ${resp.statusCode}';
      throw BrainWalletException(msg, statusCode: resp.statusCode);
    }
    return resp;
  }

  Map<String, dynamic> _parseJson(http.Response resp) {
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw BrainWalletException('wallet-op: invalid JSON response body');
    }
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  void dispose() => _client.close();
}

/// Thrown when the brain returns an error response or the response cannot
/// be parsed.
class BrainWalletException implements Exception {
  final String message;
  final int? statusCode;
  const BrainWalletException(this.message, {this.statusCode});

  @override
  String toString() => statusCode != null
      ? 'BrainWalletException($statusCode): $message'
      : 'BrainWalletException: $message';
}

```
