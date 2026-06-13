---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/recipe_store_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.127138+00:00
---

# apps/semantos/test/wallet/recipe_store_test.dart

```dart
// C11 PR-C11-4c — Unit tests for `recipe_store.dart`.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/identity/child_cert_store.dart';
import 'package:semantos/src/wallet/derivation_domain.dart';
import 'package:semantos/src/wallet/recipe_store.dart';

/// Fixed 32-byte cell type_hash for the anchor-scope tests.
final Uint8List _typeHash =
    Uint8List.fromList(List<int>.generate(32, (i) => i));
const String _typeHashHex =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';

void main() {
  group('RecipeStore', () {
    late SecureStore store;
    late RecipeStore recipes;

    setUp(() {
      store = InMemorySecureStore();
      recipes = RecipeStore(store);
    });

    test('starts empty', () async {
      expect(await recipes.readAll(), isEmpty);
    });

    test('registerRule is idempotent', () async {
      final a = await recipes.registerRule(DerivationDomain.tier0);
      final b = await recipes.registerRule(DerivationDomain.tier0);
      expect(a.id, b.id);
      expect(a.createdAtMs, b.createdAtMs);
      expect(a.highWater, -1);
      final all = await recipes.readAll();
      expect(all.length, 1);
    });

    test('allocateNextIndex starts at 0 and increments', () async {
      final domain = DerivationDomain.spend('oddjobz/payout');
      final first = await recipes.allocateNextIndex(domain);
      final second = await recipes.allocateNextIndex(domain);
      final third = await recipes.allocateNextIndex(domain);
      expect(first.index, 0);
      expect(second.index, 1);
      expect(third.index, 2);
      expect(third.rule.highWater, 2);
    });

    test('independent domains track their own highWater', () async {
      final payout = DerivationDomain.spend('oddjobz/payout');
      final release = DerivationDomain.spend('betterment/release');
      await recipes.allocateNextIndex(payout);
      await recipes.allocateNextIndex(payout);
      final r = await recipes.allocateNextIndex(release);
      expect(r.index, 0);
      final payoutThird = await recipes.allocateNextIndex(payout);
      expect(payoutThird.index, 2);
    });

    test('persists across instance recreation', () async {
      final spend = DerivationDomain.spend('oddjobz/payout');
      await recipes.allocateNextIndex(spend);
      await recipes.allocateNextIndex(spend);
      final reborn = RecipeStore(store);
      final next = await reborn.allocateNextIndex(spend);
      expect(next.index, 2);
    });

    test('rule rows carry context label / typeHash + kdfVersion', () async {
      final spend = DerivationDomain.spend('oddjobz/payout');
      final anchor = DerivationDomain.anchor(_typeHash);
      await recipes.registerRule(spend);
      await recipes.registerRule(anchor);
      final all = await recipes.readAll();
      final spendRow = all.firstWhere((r) => r.id == spend.label);
      final anchorRow = all.firstWhere((r) => r.id == anchor.label);
      expect(spendRow.contextLabel, 'oddjobz/payout');
      expect(spendRow.scope, DerivationScope.context);
      // L11 P6: anchor scope is keyed by the cell type_hash hex.
      expect(anchorRow.typeHash, _typeHashHex);
      expect(anchorRow.scope, DerivationScope.anchor);
      // L11.5: all unilateral domains are domain-separated kdf-v3.
      expect(spendRow.kdfVersion, kKdfVersionV3);
      expect(anchorRow.kdfVersion, kKdfVersionV3);
    });

    test('scope → KDF: counterparty=v1, all unilateral=v3', () {
      expect(kdfVersionForScope(DerivationScope.counterparty), kKdfVersionV1);
      // L11.5: every unilateral domain folds its flag → domain-separated kdf-v3.
      expect(kdfVersionForScope(DerivationScope.change), kKdfVersionV3);
      expect(kdfVersionForScope(DerivationScope.anchor), kKdfVersionV3);
      // P6: tier0/spend now use WALLET_TIER0 / WALLET_SPEND flags → v3.
      expect(kdfVersionForScope(DerivationScope.context), kKdfVersionV3);
      expect(kdfVersionForScope(DerivationScope.tier0), kKdfVersionV3);
    });

    test('concurrent allocateNextIndex serialises and never collides',
        () async {
      final spend = DerivationDomain.spend('concurrent/test');
      // Fire 32 in parallel; each must get a unique index in [0..31].
      final futures = List.generate(32, (_) => recipes.allocateNextIndex(spend));
      final results = await Future.wait(futures);
      final indices = results.map((r) => r.index).toList()..sort();
      expect(indices, List<int>.generate(32, (i) => i));
    });

    test('clear empties the log', () async {
      await recipes.allocateNextIndex(DerivationDomain.change);
      await recipes.clear();
      expect(await recipes.readAll(), isEmpty);
    });

    test('round-trips through JSON', () async {
      final spend = DerivationDomain.spend('oddjobz/payout');
      final anchor = DerivationDomain.anchor(_typeHash);
      await recipes.allocateNextIndex(spend);
      await recipes.allocateNextIndex(spend);
      await recipes.registerRule(anchor);
      final all = await recipes.readAll();
      final json = all.map((r) => r.toJson()).toList();
      final restored =
          json.map((m) => DerivationRule.fromJson(m)).toList();
      expect(restored.length, all.length);
      for (var i = 0; i < restored.length; i++) {
        expect(restored[i].id, all[i].id);
        expect(restored[i].scope, all[i].scope);
        expect(restored[i].highWater, all[i].highWater);
        expect(restored[i].contextLabel, all[i].contextLabel);
        expect(restored[i].typeHash, all[i].typeHash);
        expect(restored[i].kdfVersion, all[i].kdfVersion);
      }
    });

    test('legacy rows without kdfVersion default by scope', () {
      // A row with no kdfVersion key must parse and route to the scope's
      // current canonical KDF rather than crashing. Post-L11.5 the change
      // scope's canonical KDF is v3 — which is what the PWA actually derives
      // (the flag is folded unconditionally), so the advisory metadata matches
      // real derivation. (Pre-L11.5 throwaway keys are not recovered.)
      final legacy = DerivationRule.fromJson({
        'id': 'vault/0/change',
        'scope': 'change',
        'label': 'vault/0/change',
        'highWater': 3,
        'createdAtMs': 1717000000000,
      });
      expect(legacy.kdfVersion, kKdfVersionV3);
    });
  });
}

```
