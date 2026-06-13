---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/brain_info_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.092771+00:00
---

# apps/semantos/test/brain_info_test.dart

```dart
// C11 PR-C11-1 — BrainHttpClient.getInfo() parser test.
//
// Mirrors the real /api/v1/info response from oddjobtodd.info (probed
// during PR #726's brain-redeploy run). Locks the wire shape the
// "me" sheet Identity row depends on.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/brain/brain_http_client.dart';

class _FixedJsonAdapter implements HttpClientAdapter {
  final String body;
  final int status;
  _FixedJsonAdapter(this.body, {this.status = 200});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('BrainHttpClient.getInfo', () {
    const realResponse = '''
{
  "shard_proxy_endpoint": null,
  "shard_group_id": "",
  "brain_pin_cert_id": "af90d1d61ae742839897e24cc59ce873",
  "brain_pin_pubkey": "029cf8e43942bd9a3f1c58b3a843049d9b95ecbb0532f20021ac465bb62a08dfec",
  "server_version": "brain 0.1.0-brain1",
  "theme": {"primary_hex": "#4F46E5"},
  "hat": {
    "id": "71fb3ba4737e577fa2439599fa45a7f4",
    "name": "canon-c3-emulator-test",
    "cert_id": ""
  },
  "cartridges": [
    {"id": "betterment", "role": "domain", "experiencePackage": ""}
  ]
}
''';

    test('parses the real oddjobtodd.info response (post-betterment-deploy)',
        () async {
      final brain = BrainHttpClient(
        baseUrl: 'https://example.brain',
        bearerToken: 't',
        dio: Dio()..httpClientAdapter = _FixedJsonAdapter(realResponse),
      );

      final info = await brain.getInfo();
      expect(info.serverVersion, 'brain 0.1.0-brain1');
      expect(info.pinCertId, 'af90d1d61ae742839897e24cc59ce873');
      expect(info.pinPubkey, startsWith('029cf8e4'));
      expect(info.hat.id, '71fb3ba4737e577fa2439599fa45a7f4');
      expect(info.hat.name, 'canon-c3-emulator-test');
      expect(info.hat.isEmpty, isFalse);
      expect(info.cartridges, hasLength(1));
      expect(info.cartridges.map((c) => c.id), containsAll(['betterment']));
    });

    test('missing hat block → HatInfo.isEmpty', () async {
      final brain = BrainHttpClient(
        baseUrl: 'https://example.brain',
        bearerToken: 't',
        dio: Dio()
          ..httpClientAdapter = _FixedJsonAdapter(
            '{"server_version":"brain 0.1.0","brain_pin_cert_id":"abc","brain_pin_pubkey":"def","cartridges":[]}',
          ),
      );
      final info = await brain.getInfo();
      expect(info.hat.isEmpty, isTrue);
      expect(info.cartridges, isEmpty);
    });

    test('non-2xx throws BrainHttpError', () async {
      final brain = BrainHttpClient(
        baseUrl: 'https://example.brain',
        bearerToken: 't',
        dio: Dio()
          ..httpClientAdapter =
              _FixedJsonAdapter('{"error":"unauthorized"}', status: 401),
      );
      await expectLater(
        brain.getInfo(),
        throwsA(isA<BrainHttpError>()),
      );
    });
  });
}

```
