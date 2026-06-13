---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/wallet_bridge_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.126285+00:00
---

# apps/semantos/test/wallet/wallet_bridge_test.dart

```dart
// C11 PR-C11-4e/f — Unit tests for `wallet_bridge.dart` (refactored
// to consume `WalletKeyService`).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos_core/semantos_core.dart' show IdentityStore;

import 'package:semantos/src/plexus/challenge_bundle_store.dart';
import 'package:semantos/src/plexus/envelope.dart';
import 'package:semantos/src/wallet/brc42_derive.dart';
import 'package:semantos/src/wallet/derivation_domain.dart';
import 'package:semantos/src/wallet/wallet_bridge.dart';
import 'package:semantos/src/wallet/wallet_key_service.dart';

/// In-memory `IdentityStore` for tests.
class _InMemoryIdentityStore implements IdentityStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  bool get isHardwareBacked => false;
}

String _hexEncode(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List _fakeCertBody(int seed) {
  return Uint8List.fromList(
      List<int>.generate(32, (i) => ((i + seed) * 37 + 1) & 0xff));
}

Future<({IdentityStore store, WalletKeyService svc, WalletBridge bridge})>
    _setup({Uint8List? certBody, ChallengeBundle? bundle}) async {
  final store = _InMemoryIdentityStore();
  if (certBody != null) {
    await store.write(kActiveCertBodySlot, _hexEncode(certBody));
  }
  if (bundle != null) {
    await ChallengeBundleStore(store)
        .write(bundle, createdAt: '2026-05-30T00:00:00Z');
  }
  final svc = WalletKeyService(identityStore: store);
  await svc.loadIdentity();
  final bridge = WalletBridge(service: svc, identityStore: store);
  return (store: store, svc: svc, bridge: bridge);
}

String _encodeReady() =>
    jsonEncode({'id': 't-ready', 'kind': 'ready', 'payload': {}});

String _encodeAddressRequest(String ctx) => jsonEncode({
      'id': 't-addr',
      'kind': 'address.request',
      'payload': {'contextLabel': ctx},
    });

String _encodeTxRequest() => jsonEncode({
      'id': 't-tx',
      'kind': 'tx.request',
      'payload': {
        'recipientAddrOrPub': '0xabc',
        'amountSats': 100,
        'contextLabel': 'oddjobz/payout',
        'memo': '',
      },
    });

void main() {
  group('WalletBridge handle(ready)', () {
    test('with no cert_body, returns identity.set with empty fields', () async {
      final ctx = await _setup();
      final out = await ctx.bridge.handle(_encodeReady());
      expect(out, hasLength(1));
      expect(out[0].kind, 'identity.set');
      expect(out[0].payload['certIdHex'], '');
      expect(out[0].payload['tier0Pub'], '');
      expect(out[0].payload['recoverable'], isFalse);
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });

    test('with cert_body present, returns identity.set + utxos.list',
        () async {
      final ctx = await _setup(certBody: _fakeCertBody(1));
      final out = await ctx.bridge.handle(_encodeReady());
      expect(out, hasLength(2));
      expect(out[0].kind, 'identity.set');
      expect(out[1].kind, 'utxos.list');
      expect(out[0].payload['certIdHex'], hasLength(32));
      expect(out[0].payload['tier0Pub'], hasLength(66)); // 33 bytes hex
      expect(out[0].payload['recoverable'], isFalse);
      // Fresh setup: no addresses allocated yet, so utxos.list is
      // empty.
      expect(out[1].payload['rows'], isEmpty);
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });

    test('recoverable flips true when a challenge bundle is stored',
        () async {
      final bundle = ChallengeBundle(
        questions: const ['Q1?', 'Q2?', 'Q3?'],
        saltHex: 'a' * 64,
        answerHashes: List<String>.filled(3, 'b' * 64),
        kdfIterations: kPbkdf2Iterations,
      );
      final ctx = await _setup(
        certBody: _fakeCertBody(2),
        bundle: bundle,
      );
      final out = await ctx.bridge.handle(_encodeReady());
      expect(out[0].payload['recoverable'], isTrue);
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });

    test('reloads identity on subsequent ready (covers dev-cert insert)',
        () async {
      final ctx = await _setup(); // no cert
      final first = await ctx.bridge.handle(_encodeReady());
      expect(first[0].payload['certIdHex'], '');

      // Insert a cert_body between ready calls — mimics what the
      // Me sheet's "Generate dev cert" button does mid-session.
      await ctx.store.write(
          kActiveCertBodySlot, _hexEncode(_fakeCertBody(99)));

      final second = await ctx.bridge.handle(_encodeReady());
      expect(second[0].payload['certIdHex'], hasLength(32));
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });
  });

  group('WalletBridge handle(address.request)', () {
    test('without identity, returns error.show', () async {
      final ctx = await _setup();
      final out = await ctx.bridge
          .handle(_encodeAddressRequest('oddjobz/payout'));
      expect(out, hasLength(1));
      expect(out[0].kind, 'error.show');
      expect(out[0].payload['message'], contains('No identity bound'));
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });

    test('with identity, returns address.reply at monotonic indices',
        () async {
      final ctx = await _setup(certBody: _fakeCertBody(3));
      await ctx.bridge.handle(_encodeReady());
      final out1 =
          await ctx.bridge.handle(_encodeAddressRequest('oddjobz/payout'));
      final out2 =
          await ctx.bridge.handle(_encodeAddressRequest('oddjobz/payout'));
      // address.reply followed by a utxos.list refresh.
      expect(out1, hasLength(2));
      expect(out1[0].kind, 'address.reply');
      expect(out1[1].kind, 'utxos.list');
      expect(out2[0].kind, 'address.reply');
      expect(out2[1].kind, 'utxos.list');
      expect(out1[0].payload['index'], 0);
      expect(out2[0].payload['index'], 1);
      expect(out1[0].payload['recipeId'], 'vault/0/spend/oddjobz/payout');
      expect(out1[0].payload['contextLabel'], 'oddjobz/payout');
      // PR-C11-7a: address is a real BSV P2PKH (base58check, ~34
      // chars on mainnet, starts with '1'). pubHex is kept for
      // diagnostics.
      expect(out1[0].payload['address'], startsWith('1'));
      expect(out1[0].payload['pubHex'], hasLength(66));
      expect(out1[0].payload['address'],
          isNot(equals(out2[0].payload['address'])));
      // The utxos.list snapshot should now contain two watching rows.
      final rows = out2[1].payload['rows'] as List;
      expect(rows, hasLength(2));
      expect(rows.first['status'], 'watching');
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });

    test('rejects empty contextLabel', () async {
      final ctx = await _setup(certBody: _fakeCertBody(4));
      await ctx.bridge.handle(_encodeReady());
      final out = await ctx.bridge.handle(_encodeAddressRequest(''));
      expect(out[0].kind, 'error.show');
      expect(out[0].payload['message'], contains('contextLabel'));
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });
  });

  group('WalletBridge handle(tx.request)', () {
    test('returns error.show pointing at PR-C11-7', () async {
      final ctx = await _setup(certBody: _fakeCertBody(5));
      await ctx.bridge.handle(_encodeReady());
      final out = await ctx.bridge.handle(_encodeTxRequest());
      expect(out, hasLength(1));
      expect(out[0].kind, 'error.show');
      expect(out[0].payload['message'], contains('PR-C11-7'));
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });
  });

  group('WalletBridge handle(tx.confirm/cancel)', () {
    test('returns no envelopes in 4e (no bridge preview state yet)',
        () async {
      final ctx = await _setup();
      final confirm = await ctx.bridge.handle(jsonEncode({
        'id': 't',
        'kind': 'tx.confirm',
        'payload': {'previewId': 'p1'},
      }));
      final cancel = await ctx.bridge.handle(jsonEncode({
        'id': 't',
        'kind': 'tx.cancel',
        'payload': {'previewId': 'p1'},
      }));
      expect(confirm, isEmpty);
      expect(cancel, isEmpty);
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });
  });

  group('WalletBridge handle(derivation.request)', () {
    test('returns derivation.reply with requested pubs', () async {
      final ctx = await _setup(certBody: _fakeCertBody(6));
      await ctx.bridge.handle(_encodeReady());
      await ctx.bridge.handle(_encodeAddressRequest('oddjobz/payout'));
      await ctx.bridge.handle(_encodeAddressRequest('oddjobz/payout'));
      final out = await ctx.bridge.handle(jsonEncode({
        'id': 't-der',
        'kind': 'derivation.request',
        'payload': {
          'recipeId': 'vault/0/spend/oddjobz/payout',
          'fromIndex': 0,
          'count': 2,
        },
      }));
      expect(out, hasLength(1));
      expect(out[0].kind, 'derivation.reply');
      final pubs = out[0].payload['pubs'] as List;
      expect(pubs, hasLength(2));
      expect(pubs[0]['index'], 0);
      expect(pubs[1]['index'], 1);
      expect((pubs[0]['pub'] as String), hasLength(66));
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });

    test('rejects unknown recipeId', () async {
      final ctx = await _setup(certBody: _fakeCertBody(7));
      await ctx.bridge.handle(_encodeReady());
      final out = await ctx.bridge.handle(jsonEncode({
        'id': 't-der',
        'kind': 'derivation.request',
        'payload': {
          'recipeId': 'vault/0/spend/nope',
          'fromIndex': 0,
          'count': 1,
        },
      }));
      expect(out[0].kind, 'error.show');
      expect(out[0].payload['message'], contains('unknown recipeId'));
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });
  });

  group('WalletBridge malformed input', () {
    test('returns error.show on non-JSON', () async {
      final ctx = await _setup();
      final out = await ctx.bridge.handle('this is not json');
      expect(out, hasLength(1));
      expect(out[0].kind, 'error.show');
      expect(out[0].payload['message'], contains('Malformed'));
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });

    test('returns error.show on unknown kind', () async {
      final ctx = await _setup();
      final out = await ctx.bridge.handle(jsonEncode({
        'id': 't',
        'kind': 'totally.bogus',
        'payload': {},
      }));
      expect(out[0].kind, 'error.show');
      expect(out[0].payload['message'], contains('Unknown'));
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });
  });

  group('WalletBridge envelope decoding', () {
    test('round-trips JSON via WalletEnvelope.tryDecode/toJson', () {
      final src = WalletEnvelope(
        id: 'abc',
        kind: 'identity.set',
        payload: {'certIdHex': 'deadbeef'},
      );
      final dec = WalletEnvelope.tryDecode(jsonEncode(src.toJson()));
      expect(dec, isNotNull);
      expect(dec!.kind, 'identity.set');
      expect(dec.payload['certIdHex'], 'deadbeef');
    });

    test('tier-0 pub from identity.set matches direct derivation',
        () async {
      final body = _fakeCertBody(11);
      final ctx = await _setup(certBody: body);
      final out = await ctx.bridge.handle(_encodeReady());
      final tier0Sk = deriveSelfChild(
        parentSk: body,
        protocolHash: DerivationDomain.tier0.protocolHash,
        index: 0,
        domainFlag: DerivationDomain.tier0.domainFlag, // L11.5 kdf-v3
      );
      final tier0Pub = publicKeyFromPrivate(tier0Sk);
      expect(out[0].payload['tier0Pub'], _hexEncode(tier0Pub));
      ctx.bridge.dispose();
      ctx.svc.dispose();
    });
  });

  group('Headless / shared-state contract', () {
    test(
        'bridge and direct WalletKeyService caller share the same recipe '
        'state — bridge allocates index 0, direct call gets index 1',
        () async {
      // This is the test that proves the "drawer of postage stamps"
      // architecture from the contract: any Dart consumer can derive
      // the next receive index without crossing the bridge, and the
      // index counter is honoured globally.
      final ctx = await _setup(certBody: _fakeCertBody(42));

      // 1) Renderer path: bridge ready + address.request → index 0.
      await ctx.bridge.handle(_encodeReady());
      final bridgeReply = await ctx.bridge
          .handle(_encodeAddressRequest('talk/p2p-payment'));
      expect(bridgeReply[0].payload['index'], 0);

      // 2) Direct headless path: same service, no bridge involved.
      //    Imagine this call coming from a REPL verb, conversation-
      //    engine intent handler, or cell-anchoring scheduler.
      final headless = await ctx.svc.deriveReceive('talk/p2p-payment');
      expect(headless.index, 1);
      expect(headless.recipeId, 'vault/0/spend/talk/p2p-payment');

      // 3) Addresses differ — proves each index is a fresh derivation
      //    + a fresh address, not a cached or replayed one.
      expect(bridgeReply[0].payload['address'],
          isNot(equals(headless.address)));

      // 4) Both consumers' allocations end up in the SAME UTXO store
      //    — the postage-stamp drawer is shared.
      final utxoRows = await ctx.svc.utxos.readAll();
      expect(utxoRows, hasLength(2));
      expect(utxoRows.map((r) => r.index).toSet(), {0, 1});

      ctx.bridge.dispose();
      ctx.svc.dispose();
    });
  });
}

```
