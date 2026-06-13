---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/utxo_store_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.124569+00:00
---

# apps/semantos/test/wallet/utxo_store_test.dart

```dart
// C11 PR-C11-7a — Unit tests for `utxo_store.dart`.

import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/identity/child_cert_store.dart';
import 'package:semantos/src/wallet/utxo_store.dart';

void main() {
  group('UtxoStore', () {
    late SecureStore secure;
    late UtxoStore utxos;

    setUp(() {
      secure = InMemorySecureStore();
      utxos = UtxoStore(secure);
    });

    test('starts empty', () async {
      expect(await utxos.readAll(), isEmpty);
    });

    test('addWatching persists a row with status=watching', () async {
      final row = await utxos.addWatching(
        address: '1AAAA',
        recipeId: 'vault/0/spend/oddjobz/payout',
        index: 0,
      );
      expect(row.status, UtxoStatus.watching);
      expect(row.value, 0);
      expect(row.txid, isEmpty);
      expect(row.vout, -1);
      final all = await utxos.readAll();
      expect(all, hasLength(1));
      expect(all.first.address, '1AAAA');
    });

    test('addWatching is idempotent on (recipeId, index)', () async {
      await utxos.addWatching(
        address: '1AAAA',
        recipeId: 'vault/0/spend/oddjobz/payout',
        index: 0,
      );
      await utxos.addWatching(
        address: '1AAAA',
        recipeId: 'vault/0/spend/oddjobz/payout',
        index: 0,
      );
      expect(await utxos.readAll(), hasLength(1));
    });

    test('different indices keep independent rows', () async {
      await utxos.addWatching(
        address: '1AAAA',
        recipeId: 'vault/0/spend/oddjobz/payout',
        index: 0,
      );
      await utxos.addWatching(
        address: '1BBBB',
        recipeId: 'vault/0/spend/oddjobz/payout',
        index: 1,
      );
      expect(await utxos.readAll(), hasLength(2));
    });

    test('recordConfirmed flips status and fills outpoint', () async {
      await utxos.addWatching(
        address: '1AAAA',
        recipeId: 'vault/0/spend/oddjobz/payout',
        index: 0,
      );
      final updated = await utxos.recordConfirmed(
        recipeId: 'vault/0/spend/oddjobz/payout',
        index: 0,
        txid: 'deadbeef' * 8,
        vout: 1,
        value: 50000,
        scriptHex: '76a9' * 5,
      );
      expect(updated, isNotNull);
      expect(updated!.status, UtxoStatus.confirmed);
      expect(updated.value, 50000);
      expect(updated.txid.length, 64);
      expect(updated.vout, 1);
      final all = await utxos.readAll();
      expect(all, hasLength(1));
      expect(all.first.status, UtxoStatus.confirmed);
    });

    test('recordConfirmed returns null for unknown rows', () async {
      final out = await utxos.recordConfirmed(
        recipeId: 'vault/0/spend/missing',
        index: 0,
        txid: 'a' * 64,
        vout: 0,
        value: 1,
        scriptHex: '',
      );
      expect(out, isNull);
    });

    test('markSpent flips status by (txid, vout)', () async {
      await utxos.addWatching(
        address: '1AAAA',
        recipeId: 'vault/0/spend/oddjobz/payout',
        index: 0,
      );
      await utxos.recordConfirmed(
        recipeId: 'vault/0/spend/oddjobz/payout',
        index: 0,
        txid: 'cafe' * 16,
        vout: 0,
        value: 100,
        scriptHex: '',
      );
      final spent = await utxos.markSpent(txid: 'cafe' * 16, vout: 0);
      expect(spent, isNotNull);
      expect(spent!.status, UtxoStatus.spent);
    });

    test('rowsWhere filters', () async {
      await utxos.addWatching(
        address: '1AAAA',
        recipeId: 'vault/0/spend/a',
        index: 0,
      );
      await utxos.addWatching(
        address: '1BBBB',
        recipeId: 'vault/0/spend/b',
        index: 0,
      );
      final watching = await utxos
          .rowsWhere((r) => r.status == UtxoStatus.watching);
      expect(watching, hasLength(2));
    });

    test('persists across instance recreation', () async {
      await utxos.addWatching(
        address: '1AAAA',
        recipeId: 'vault/0/spend/oddjobz/payout',
        index: 0,
      );
      final reborn = UtxoStore(secure);
      final all = await reborn.readAll();
      expect(all, hasLength(1));
      expect(all.first.address, '1AAAA');
    });

    test('clear empties the log', () async {
      await utxos.addWatching(
        address: '1AAAA',
        recipeId: 'vault/0/spend/x',
        index: 0,
      );
      await utxos.clear();
      expect(await utxos.readAll(), isEmpty);
    });

    test('UtxoRow.sameOutputAs matches by txid+vout when populated',
        () async {
      final txid = 'beef' * 16;
      final a = UtxoRow(
        address: 'x',
        recipeId: 'r',
        index: 0,
        status: UtxoStatus.confirmed,
        addedAtMs: 1,
        updatedAtMs: 1,
        txid: txid,
        vout: 2,
      );
      final b = a.copyWith(value: 999);
      expect(a.sameOutputAs(b), isTrue);
      final c = a.copyWith();
      // Different recipe row, same outpoint: still same output.
      final d = UtxoRow(
        address: 'y',
        recipeId: 'other',
        index: 9,
        status: UtxoStatus.confirmed,
        addedAtMs: 1,
        updatedAtMs: 1,
        txid: txid,
        vout: 2,
      );
      expect(c.sameOutputAs(d), isTrue);
    });
  });
}

```
