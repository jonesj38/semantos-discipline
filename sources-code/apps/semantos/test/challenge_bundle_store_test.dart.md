---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/challenge_bundle_store_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.094158+00:00
---

# apps/semantos/test/challenge_bundle_store_test.dart

```dart
// C11 PR-C11-3 — ChallengeBundleStore round-trip + malformed-record
// tests. Uses an in-memory IdentityStore fake so the suite stays under
// pure `flutter test` with no platform deps.

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/plexus/challenge_bundle_store.dart';
import 'package:semantos/src/plexus/envelope.dart';
import 'package:semantos_core/semantos_core.dart';

class _MemoryIdentityStore implements IdentityStore {
  final Map<String, String> _kv = {};

  @override
  Future<String?> read(String key) async => _kv[key];

  @override
  Future<void> write(String key, String value) async {
    _kv[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _kv.remove(key);
  }

  @override
  bool get isHardwareBacked => false;
}

void main() {
  group('ChallengeBundleStore', () {
    late _MemoryIdentityStore identity;
    late ChallengeBundleStore store;

    setUp(() {
      identity = _MemoryIdentityStore();
      store = ChallengeBundleStore(identity);
    });

    test('isSet returns false on empty store', () async {
      expect(await store.isSet(), isFalse);
      expect(await store.read(), isNull);
    });

    test('write + read round-trip preserves the bundle', () async {
      const bundle = ChallengeBundle(
        questions: ['Q1', 'Q2', 'Q3'],
        saltHex:
            'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899',
        answerHashes: [
          '1111111111111111111111111111111111111111111111111111111111111111',
          '2222222222222222222222222222222222222222222222222222222222222222',
          '3333333333333333333333333333333333333333333333333333333333333333',
        ],
        kdfIterations: 100000,
      );
      const createdAt = '2026-05-30T00:00:00Z';
      await store.write(bundle, createdAt: createdAt);

      expect(await store.isSet(), isTrue);
      final got = await store.read();
      expect(got, isNotNull);
      expect(got!.createdAt, createdAt);
      expect(got.bundle.questions, bundle.questions);
      expect(got.bundle.saltHex, bundle.saltHex);
      expect(got.bundle.answerHashes, bundle.answerHashes);
      expect(got.bundle.kdfIterations, 100000);
    });

    test('write overwrites previous bundle', () async {
      final oldBundle = ChallengeBundle(
        questions: const ['Old'],
        saltHex: 'a' * 64,
        answerHashes: ['b' * 64],
      );
      final newBundle = ChallengeBundle(
        questions: const ['New1', 'New2'],
        saltHex: 'c' * 64,
        answerHashes: ['d' * 64, 'e' * 64],
      );
      await store.write(oldBundle, createdAt: '2026-01-01T00:00:00Z');
      await store.write(newBundle, createdAt: '2026-06-01T00:00:00Z');
      final got = await store.read();
      expect(got!.bundle.questions, ['New1', 'New2']);
      expect(got.createdAt, '2026-06-01T00:00:00Z');
    });

    test('clear removes the bundle', () async {
      final bundle = ChallengeBundle(
        questions: const ['Q'],
        saltHex: 'a' * 64,
        answerHashes: ['b' * 64],
      );
      await store.write(bundle, createdAt: '2026-05-30T00:00:00Z');
      expect(await store.isSet(), isTrue);
      await store.clear();
      expect(await store.isSet(), isFalse);
      expect(await store.read(), isNull);
    });

    test('malformed record returns null (does not throw)', () async {
      await identity.write(kChallengeBundleStoreKey, 'not-json-at-all');
      expect(await store.read(), isNull);
    });

    test('record with mismatched counts returns null', () async {
      await identity.write(kChallengeBundleStoreKey, '''
{
  "questions": ["Q1", "Q2"],
  "salt": "${'a' * 64}",
  "answerHashes": ["${'b' * 64}"],
  "kdfIterations": 100000,
  "createdAt": "2026-05-30T00:00:00Z"
}
''');
      expect(await store.read(), isNull);
    });

    test('record with bad salt length returns null', () async {
      await identity.write(kChallengeBundleStoreKey, '''
{
  "questions": ["Q"],
  "salt": "abc",
  "answerHashes": ["${'a' * 64}"],
  "kdfIterations": 100000,
  "createdAt": "2026-05-30T00:00:00Z"
}
''');
      expect(await store.read(), isNull);
    });
  });
}

```
