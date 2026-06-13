---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/intent_dispatcher_factory_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.093887+00:00
---

# apps/semantos/test/intent_dispatcher_factory_test.dart

```dart
// Tests for buildIntentDispatcher. M1.7b: the factory no longer reads creds —
// the shell constructs + connects the BrainRpcClient at boot and passes it as
// the [CellMinter]. The factory's only job is the pairing gate: null minter ⇒
// no dispatcher; a supplied minter ⇒ a BARE dispatcher (cartridges register
// their own bindings in main.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/dispatch/cell_minter.dart';
import 'package:semantos/src/dispatch/intent_dispatcher_factory.dart';

/// Minimal in-memory [CellMinter] — stands in for the connected BrainRpcClient.
class _FakeMinter implements CellMinter {
  @override
  Future<MintCellResult> mintCell({
    required String typeHashHex,
    required Map<String, dynamic> payload,
  }) async =>
      const MintCellResult(
          cellId: 'x', cartridgeId: 'c', cellType: 't', persistedAt: 0);

  @override
  Future<MintCellResult> mintCellSigned({
    required String typeHashHex,
    required Map<String, dynamic> payload,
    required String signatureHex,
    required String signerCertIdHex,
  }) async =>
      const MintCellResult(
          cellId: 'x', cartridgeId: 'c', cellType: 't', persistedAt: 0);
}

void main() {
  group('buildIntentDispatcher', () {
    test('returns needsPairing when minter is null (unpaired / not connected)',
        () async {
      final result = await buildIntentDispatcher(minter: null);
      expect(result.dispatcher, isNull);
      expect(result.needsPairing, isTrue);
    });

    test('returns a dispatcher when a connected minter is supplied', () async {
      final result = await buildIntentDispatcher(minter: _FakeMinter());
      expect(result.dispatcher, isNotNull);
      expect(result.needsPairing, isFalse);
    });

    test(
        'dispatcher returned by factory is BARE — no intent bindings registered',
        () async {
      final result = await buildIntentDispatcher(minter: _FakeMinter());
      // Cartridges register their own specs via main.dart after the
      // factory returns. Factory itself is cartridge-agnostic.
      expect(result.dispatcher!.registeredIntentTypes, isEmpty);
      expect(result.dispatcher!.registeredIntentTypeNames, isEmpty);
    });
  });
}

```
