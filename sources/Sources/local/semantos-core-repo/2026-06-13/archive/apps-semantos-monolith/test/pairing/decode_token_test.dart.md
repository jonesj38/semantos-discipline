---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/pairing/decode_token_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.905839+00:00
---

# archive/apps-semantos-monolith/test/pairing/decode_token_test.dart

```dart
// D-O5m — decode_token.dart conformance test.
//
// Loads the canonical fixture at
// `test/fixtures/device-pair-v2-fixture.json` (mirror of
// `extensions/oddjobz/tests/vectors/device-pair/v2-fixture.json`) and
// asserts that decoding the `tokenBase64Url` field produces a
// PairPayload whose every field matches the fixture's `payload` block
// + the operator's root pub/cert id.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:semantos/src/pairing/decode_token.dart';
import 'package:semantos/src/pairing/pair_payload.dart';

void main() {
  group('decodePairingToken — v2 fixture', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final raw =
          File('test/fixtures/device-pair-v2-fixture.json').readAsStringSync();
      fixture = json.decode(raw) as Map<String, dynamic>;
    });

    test('decodes the v2 token with all fields equal to the fixture', () {
      final token = fixture['tokenBase64Url'] as String;
      final decoded = decodePairingToken(token);

      final expectedPayload = fixture['payload'] as Map<String, dynamic>;
      final expectedOperator = fixture['operator'] as Map<String, dynamic>;

      expect(decoded.v, equals(2));
      expect(decoded.domain, equals('brain-device-pair-v2'));
      expect(decoded.operatorRootCertId,
          equals(expectedOperator['certIdHex']));
      expect(decoded.operatorRootPub, equals(expectedOperator['pubHex']));
      expect(decoded.contextTag, equals(expectedPayload['contextTag']));
      expect(decoded.label, equals(expectedPayload['label']));
      expect(
          decoded.capabilities,
          equals(
              (expectedPayload['capabilities'] as List).cast<String>()));
      expect(decoded.expiresAt, equals(expectedPayload['expiresAt']));
      expect(decoded.nonce, equals(expectedPayload['nonceHex']));
      expect(decoded.brainPairEndpoint,
          equals(expectedPayload['brainPairEndpoint']));
      expect(decoded.brainWssEndpoint,
          equals(expectedPayload['brainWssEndpoint']));
      // brain_pin_cert_id + brain_pin_pubkey are pinned to operator
      // root in the fixture (D-O5p ships them as same-as-operator;
      // future delegated-brain forks revise this).
      expect(decoded.brainPinCertId, equals(expectedOperator['certIdHex']));
      expect(decoded.brainPinPubkey, equals(expectedOperator['pubHex']));
      expect(decoded.signature, isA<String>());
      expect(decoded.signature.length, greaterThan(64));
    });

    test('strips the ?token= URL prefix', () {
      final token = fixture['tokenBase64Url'] as String;
      final wrapped =
          'https://oddjobtodd.info/pair?token=$token';
      final decoded = decodePairingToken(wrapped);
      expect(decoded.v, equals(2));
      expect(decoded.domain, equals('brain-device-pair-v2'));
    });

    test('rejects non-base64url input', () {
      expect(
        () => decodePairingToken('not a valid token!!! @@@'),
        throwsA(isA<PairPayloadFormatException>()),
      );
    });

    test('rejects unknown wire version', () {
      // Hand-craft a v3 payload (otherwise valid).
      final bogus = {
        'v': 3,
        'domain': 'brain-device-pair-v2',
        'operator_root_cert_id': '00' * 16,
        'operator_root_pub': '02${'00' * 32}',
        'context_tag': 16,
        'label': 'x',
        'capabilities': <String>[],
        'expires_at': 0,
        'nonce': '00' * 16,
        'brain_pair_endpoint': 'https://x/y',
        'brain_wss_endpoint': 'wss://x/y',
        'brain_pin_cert_id': '00' * 16,
        'brain_pin_pubkey': '02${'00' * 32}',
        'signature': '00' * 32,
      };
      final raw = json.encode(bogus);
      final b64 = base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
      expect(
        () => decodePairingToken(b64),
        throwsA(isA<PairPayloadFormatException>()),
      );
    });

    test('rejects unknown wire domain', () {
      final bogus = {
        'v': 2,
        'domain': 'brain-device-pair-v1',
        'operator_root_cert_id': '00' * 16,
        'operator_root_pub': '02${'00' * 32}',
        'context_tag': 16,
        'label': 'x',
        'capabilities': <String>[],
        'expires_at': 0,
        'nonce': '00' * 16,
        'brain_pair_endpoint': 'https://x/y',
        'brain_wss_endpoint': 'wss://x/y',
        'brain_pin_cert_id': '00' * 16,
        'brain_pin_pubkey': '02${'00' * 32}',
        'signature': '00' * 32,
      };
      final raw = json.encode(bogus);
      final b64 = base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
      expect(
        () => decodePairingToken(b64),
        throwsA(isA<PairPayloadFormatException>()),
      );
    });

    test('rejects context_tag outside u8', () {
      final bogus = {
        'v': 2,
        'domain': 'brain-device-pair-v2',
        'operator_root_cert_id': '00' * 16,
        'operator_root_pub': '02${'00' * 32}',
        'context_tag': 999,
        'label': 'x',
        'capabilities': <String>[],
        'expires_at': 0,
        'nonce': '00' * 16,
        'brain_pair_endpoint': 'https://x/y',
        'brain_wss_endpoint': 'wss://x/y',
        'brain_pin_cert_id': '00' * 16,
        'brain_pin_pubkey': '02${'00' * 32}',
        'signature': '00' * 32,
      };
      final raw = json.encode(bogus);
      final b64 = base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
      expect(
        () => decodePairingToken(b64),
        throwsA(isA<PairPayloadFormatException>()),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────
  // Smoke-test pass #1, fix #16 — accept either bare token OR full
  // `semantos-pair://...?token=<base64url>` URL form.
  //
  // Pre-fix the URL form failed because the substring search for
  // `?token=` happened to miss in some shapes the user pasted, and
  // the bare URL got fed into base64 decode → "invalid character at
  // index 6" (the `:` of `semantos-pair://`).
  // ───────────────────────────────────────────────────────────────────
  group('smoke-fix #16 — URL-form acceptance', () {
    late String bareToken;

    setUpAll(() {
      final raw =
          File('test/fixtures/device-pair-v2-fixture.json').readAsStringSync();
      bareToken = (json.decode(raw) as Map<String, dynamic>)['tokenBase64Url']
          as String;
    });

    test('bare token decodes (regression — previously the only happy path)',
        () {
      final decoded = decodePairingToken(bareToken);
      expect(decoded.v, equals(2));
    });

    test('semantos-pair:// URL form decodes', () {
      final url = 'semantos-pair://localhost/pair?token=$bareToken';
      final decoded = decodePairingToken(url);
      expect(decoded.v, equals(2));
    });

    test('URL form with leading + trailing whitespace decodes', () {
      final url = '  semantos-pair://brain.example/pair?token=$bareToken  \n';
      final decoded = decodePairingToken(url);
      expect(decoded.v, equals(2));
    });

    test('https URL with token query parameter decodes', () {
      // Some QR encoders use the https-shaped variant; both must work.
      final url = 'https://oddjobtodd.info/pair?token=$bareToken';
      final decoded = decodePairingToken(url);
      expect(decoded.v, equals(2));
    });

    test('URL with extra query parameters strips correctly', () {
      // Operators sometimes paste a URL with a `&utm_source=` tag.
      final url =
          'semantos-pair://localhost/pair?token=$bareToken&utm_source=test';
      final decoded = decodePairingToken(url);
      expect(decoded.v, equals(2));
    });
  });
}

```
