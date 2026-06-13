---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-tessera_experience/test/tessera_client_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.827557+00:00
---

# archive/packages-tessera_experience/test/tessera_client_test.dart

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos_core/semantos_core.dart';
import 'package:tessera_experience/tessera_experience.dart';

/// In-memory [VerbDispatchClient] that records every dispatch call and
/// returns a canned response per verb. The pattern mirrors the brain's
/// real walker contract: success → `{ok:true, id, cellId, persisted}`
/// (or `cellIds` for multi-mint), refusal → `{ok:false, reason}`.
class FakeVerbDispatchClient implements VerbDispatchClient {
  final List<DispatchCall> calls = [];
  final Map<String, Map<String, dynamic>> responsesByVerb = {};
  // 64-char hex literal — `String * int` is not const-evaluable in Dart,
  // so we spell the cellId out rather than build it with multiplication.
  static const String _zeroCellId =
      '0000000000000000000000000000000000000000000000000000000000000000';
  Map<String, dynamic> defaultResponse = const {
    'ok': true,
    'id': 'X',
    'cellId': _zeroCellId,
    'persisted': false,
  };

  @override
  Future<Map<String, dynamic>> dispatch({
    required String extensionId,
    required String verb,
    Map<String, dynamic>? params,
  }) async {
    calls.add(DispatchCall(extensionId: extensionId, verb: verb, params: params));
    return responsesByVerb[verb] ?? defaultResponse;
  }
}

class DispatchCall {
  final String extensionId;
  final String verb;
  final Map<String, dynamic>? params;
  const DispatchCall({
    required this.extensionId,
    required this.verb,
    required this.params,
  });
}

void main() {
  group('TesseraClient: wire shape mirrors the brain walker contracts', () {
    test('harvest sends tessera.harvest with lotId/grower/volumeMl', () async {
      final fake = FakeVerbDispatchClient();
      final client = TesseraClient(fake);
      final result = await client.harvest(
        lotId: 'L1',
        grower: 'alice',
        volumeMl: 1000,
      );
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.extensionId, 'tessera');
      expect(fake.calls.single.verb, 'tessera.harvest');
      expect(fake.calls.single.params, {
        'lotId': 'L1',
        'grower': 'alice',
        'volumeMl': 1000,
      });
      expect(result, isA<MintAck>());
    });

    test('ownerIdHex is forwarded when provided (P3e)', () async {
      final fake = FakeVerbDispatchClient();
      final client = TesseraClient(fake);
      await client.harvest(
        lotId: 'L1',
        grower: 'g',
        volumeMl: 1,
        ownerIdHex: '0123456789abcdef0123456789abcdef',
      );
      expect(
        fake.calls.single.params!['ownerIdHex'],
        '0123456789abcdef0123456789abcdef',
      );
    });

    test('rack forwards [lotId, barrelId, volumeMl]', () async {
      final fake = FakeVerbDispatchClient();
      await TesseraClient(fake).rack(
        lotId: 'L1',
        barrelId: 'B1',
        volumeMl: 500,
      );
      expect(fake.calls.single.verb, 'tessera.rack');
      expect(fake.calls.single.params, {
        'lotId': 'L1',
        'barrelId': 'B1',
        'volumeMl': 500,
      });
    });

    test('blend forwards [outBarrelId, inBarrelIds[], declaredOutMl]', () async {
      final fake = FakeVerbDispatchClient();
      await TesseraClient(fake).blend(
        outBarrelId: 'Bo',
        inBarrelIds: ['B1', 'B2'],
        declaredOutMl: 1000,
      );
      expect(fake.calls.single.verb, 'tessera.blend');
      expect(fake.calls.single.params, {
        'outBarrelId': 'Bo',
        'inBarrelIds': ['B1', 'B2'],
        'declaredOutMl': 1000,
      });
    });

    test('bottle returns MultiMintAck with N cell ids', () async {
      final fake = FakeVerbDispatchClient();
      fake.responsesByVerb['tessera.bottle'] = {
        'ok': true,
        'id': 'B1',
        'cellIds': ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'],
        'persisted': true,
      };
      final result = await TesseraClient(fake).bottle(
        barrelId: 'B1',
        bottleIds: ['x', 'y', 'z'],
      );
      expect(result, isA<MultiMintAck>());
      final ack = result as MultiMintAck;
      expect(ack.id, 'B1');
      expect(ack.cellIds, hasLength(3));
      expect(ack.persisted, isTrue);
    });

    test('transferCustody forwards [id, from, to]', () async {
      final fake = FakeVerbDispatchClient();
      await TesseraClient(fake).transferCustody(
        id: 'S1',
        from: 'alice',
        to: 'bob',
      );
      expect(fake.calls.single.verb, 'tessera.transfer-custody');
      expect(fake.calls.single.params, {'id': 'S1', 'from': 'alice', 'to': 'bob'});
    });

    test('every kebab-case verb name lands on the wire verbatim', () async {
      final fake = FakeVerbDispatchClient();
      final client = TesseraClient(fake);
      await client.harvest(lotId: 'L', grower: 'g', volumeMl: 1);
      await client.rack(lotId: 'L', barrelId: 'B', volumeMl: 1);
      await client.blend(outBarrelId: 'O', inBarrelIds: ['B'], declaredOutMl: 1);
      await client.bottle(barrelId: 'B', bottleIds: ['x']);
      await client.assembleCase(caseId: 'C', holder: 'h', bottleIds: ['x']);
      await client.openContainer(id: 'P', kind: 'pallet', holder: 'h');
      await client.transferCustody(id: 'C', from: 'a', to: 'b');
      await client.confirmReceipt(id: 'C', who: 'b');
      await client.recordCareEvent(containerId: 'C');
      await client.reportQualityIssue(containerId: 'C');
      await client.thermoFlag(containerId: 'C');
      await client.tamper(bottleId: 'x');
      await client.consumerScan(bottleId: 'x');
      await client.addTastingNote(bottleId: 'x');
      expect(fake.calls.map((c) => c.verb).toList(), [
        'tessera.harvest',
        'tessera.rack',
        'tessera.blend',
        'tessera.bottle',
        'tessera.assemble-case',
        'tessera.open-container',
        'tessera.transfer-custody',
        'tessera.confirm-receipt',
        'tessera.record-care-event',
        'tessera.report-quality-issue',
        'tessera.thermo-flag',
        'tessera.tamper',
        'tessera.consumer-scan',
        'tessera.add-tasting-note',
      ]);
      // 14 walkers; every call targets extensionId="tessera".
      expect(fake.calls.every((c) => c.extensionId == 'tessera'), isTrue);
    });
  });

  group('MintResult: success vs refusal discrimination', () {
    test('ok:true → MintAck with id/cellId/persisted', () {
      final r = MintResult.fromJson({
        'ok': true,
        'id': 'L1',
        'cellId': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'persisted': true,
      });
      expect(r, isA<MintAck>());
      final ack = r as MintAck;
      expect(ack.id, 'L1');
      expect(ack.cellId.length, 64);
      expect(ack.persisted, isTrue);
    });

    test('ok:false → MintRefusal with reason (FSM rejection)', () {
      final r = MintResult.fromJson({'ok': false, 'reason': 'lot_not_found'});
      expect(r, isA<MintRefusal>());
      expect((r as MintRefusal).reason, 'lot_not_found');
    });

    test('P4c reasons surface verbatim (unknown_predecessor, cell_already_consumed)',
        () {
      for (final reason in const [
        'unknown_predecessor',
        'cell_already_consumed',
        'already_tampered',
        'not_the_recipient',
        'blend_not_conserved',
      ]) {
        final r = MintResult.fromJson({'ok': false, 'reason': reason});
        expect(r, isA<MintRefusal>());
        expect((r as MintRefusal).reason, reason);
      }
    });

    test('persisted defaults to false when missing', () {
      final r = MintResult.fromJson({
        'ok': true,
        'id': 'L1',
        'cellId': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        // persisted omitted — dry-run shape (no CellStore bound)
      });
      expect((r as MintAck).persisted, isFalse);
    });
  });

  group('MultiMintResult', () {
    test('ok:true → MultiMintAck with cellIds[]', () {
      final r = MultiMintResult.fromJson({
        'ok': true,
        'id': 'B1',
        'cellIds': ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'],
        'persisted': false,
      });
      expect(r, isA<MultiMintAck>());
      expect((r as MultiMintAck).cellIds, hasLength(2));
    });

    test('ok:false → MultiMintRefusal', () {
      final r = MultiMintResult.fromJson({
        'ok': false,
        'reason': 'unknown_predecessor',
      });
      expect(r, isA<MultiMintRefusal>());
      expect((r as MultiMintRefusal).reason, 'unknown_predecessor');
    });
  });

  group('TesseraIntentGrammar.withClient: dispatches matching intents', () {
    test('no client → recognised intents acknowledged, no dispatch (scaffold)',
        () async {
      const g = TesseraIntentGrammar();
      // No client wired — onIntent returns true on recognised shapes
      // but cannot dispatch. The signature requires an IntentContext
      // (wallet stub) we don't actually need for tessera; use a
      // minimal one.
      final ctx = _NoopContext();
      expect(await g.onIntent(const ConsumerScan(bottleId: 'x'), ctx), isTrue);
      expect(await g.onIntent(const MarkTamper(bottleId: 'x'), ctx), isTrue);
    });

    test('with client → ConsumerScan dispatches tessera.consumer-scan', () async {
      final fake = FakeVerbDispatchClient();
      final g = TesseraIntentGrammar.withClient(TesseraClient(fake));
      final ok = await g.onIntent(const ConsumerScan(bottleId: 'b1'), _NoopContext());
      expect(ok, isTrue);
      expect(fake.calls.single.verb, 'tessera.consumer-scan');
      expect(fake.calls.single.params, {'bottleId': 'b1'});
    });

    test('with client → MarkTamper dispatches tessera.tamper', () async {
      final fake = FakeVerbDispatchClient();
      final g = TesseraIntentGrammar.withClient(TesseraClient(fake));
      await g.onIntent(const MarkTamper(bottleId: 'b1'), _NoopContext());
      expect(fake.calls.single.verb, 'tessera.tamper');
    });

    test('with client → Bottle generates sequential bottle ids', () async {
      final fake = FakeVerbDispatchClient();
      fake.responsesByVerb['tessera.bottle'] = {
        'ok': true,
        'id': 'B1',
        'cellIds': ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'],
        'persisted': false,
      };
      final g = TesseraIntentGrammar.withClient(TesseraClient(fake));
      await g.onIntent(const Bottle(barrelId: 'B1', count: 3), _NoopContext());
      expect(fake.calls.single.verb, 'tessera.bottle');
      expect(fake.calls.single.params, {
        'barrelId': 'B1',
        'bottleIds': ['B1-bottle-1', 'B1-bottle-2', 'B1-bottle-3'],
      });
    });
  });
}

/// Minimal IntentContext for tests — tessera doesn't actually need
/// `ctx.wallet`, but the IntentGrammar contract requires the param.
class _NoopContext implements IntentContext {
  @override
  WalletService get wallet =>
      throw UnimplementedError('tessera intents never call ctx.wallet');
}

```
