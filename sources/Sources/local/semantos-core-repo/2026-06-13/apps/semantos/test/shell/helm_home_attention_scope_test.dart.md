---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/shell/helm_home_attention_scope_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.132539+00:00
---

# apps/semantos/test/shell/helm_home_attention_scope_test.dart

```dart
import 'dart:typed_data';

import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/shell/cartridge_hat_state.dart';
import 'package:semantos/shell/conversation_engine.dart';
import 'package:semantos/shell/helm_home_screen.dart';
import 'package:semantos/shell/semantos_platform.dart';
import 'package:semantos/shell/semantos_router.dart';
import 'package:semantos/src/dispatch/cell_minter.dart';
import 'package:semantos/src/dispatch/intent_dispatcher.dart';
import 'package:semantos/src/rpc/brain_rpc_client.dart';
import 'package:semantos/src/wallet/wallet_key_service.dart';
import 'package:semantos_core/semantos_core.dart';

void main() {
  testWidgets(
    'null active cartridge shows blank helm without OddJobz attention',
    (tester) async {
      final state = CartridgeHatState();
      final rpc = _FakeRpcCaller(replOutput: _oddjobzAttentionJson);

      await tester.pumpWidget(_Harness(state: state, rpc: rpc));
      await tester.pumpAndSettle();

      expect(find.text('Melissa Collins'), findsNothing);
      expect(find.text('Blank helm'), findsOneWidget);
      expect(
        find.text('Pick a cartridge to show its field surface.'),
        findsOneWidget,
      );
      expect(rpc.replEvalCalls, isEmpty);
    },
  );

  testWidgets('active Betterment scope hides OddJobz attention cards', (
    tester,
  ) async {
    final state = CartridgeHatState(initialCartridge: 'betterment');
    final rpc = _FakeRpcCaller(replOutput: _oddjobzAttentionJson);

    await tester.pumpWidget(_Harness(state: state, rpc: rpc));
    await tester.pumpAndSettle();

    expect(find.text('Melissa Collins'), findsNothing);
    expect(find.text('Cartridge surface unavailable here.'), findsOneWidget);
    expect(rpc.replEvalCalls, isEmpty);
  });

  testWidgets(
    'router does not mount OddJobz operator shell for active Betterment',
    (tester) async {
      final state = CartridgeHatState(initialCartridge: 'betterment');
      final rpc = _FakeRpcCaller(replOutput: _oddjobzAttentionJson);

      await tester.pumpWidget(_RouterHarness(state: state, rpc: rpc));
      await tester.pumpAndSettle();

      expect(find.text('Melissa Collins'), findsNothing);
      expect(find.text('Cartridge surface unavailable here.'), findsOneWidget);
      expect(rpc.replEvalCalls, isEmpty);
    },
  );

  testWidgets('active Betterment helm chrome uses cartridge title', (
    tester,
  ) async {
    addTearDown(CartridgeRegistry.instance.resetForTest);
    _registerBettermentForChromeTest();
    final state = CartridgeHatState(initialCartridge: 'betterment');
    final rpc = _FakeRpcCaller(replOutput: _oddjobzAttentionJson);

    await tester.pumpWidget(_Harness(state: state, rpc: rpc));
    await tester.pumpAndSettle();

    expect(find.text('Betterment'), findsOneWidget);
    expect(find.text('Semantos'), findsNothing);
    expect(find.byTooltip('Switch cartridge'), findsNothing);
  });

  testWidgets('direct active OddJobz helm stays shell-neutral', (tester) async {
    final state = CartridgeHatState(initialCartridge: 'oddjobz');
    final rpc = _FakeRpcCaller(replOutput: _oddjobzAttentionJson);

    await tester.pumpWidget(_Harness(state: state, rpc: rpc));
    await tester.pumpAndSettle();

    expect(find.text('Melissa Collins'), findsNothing);
    expect(find.text('Cartridge surface unavailable here.'), findsOneWidget);
    expect(rpc.replEvalCalls, isEmpty);
  });
}

class _RouterHarness extends StatelessWidget {
  const _RouterHarness({required this.state, required this.rpc});

  final CartridgeHatState state;
  final RpcCaller rpc;

  @override
  Widget build(BuildContext context) {
    final identity = _FakeIdentityStore();
    return SemantosPlatform(
      walletService: const _FakeWalletService(),
      conversationEngine: ConversationEngine(),
      grammarRegistry: GrammarRegistry.empty(),
      hatRegistry: HatRegistry.empty(),
      identityStore: identity,
      walletKeyService: WalletKeyService(identityStore: identity),
      rpcClient: rpc,
      child: CartridgeHatScope(
        notifier: state,
        child: SemantosRouter(
          dispatcher: IntentDispatcher(brain: const _FakeCellMinter()),
          isConnected: true,
          rpcStatus: 'RPC ✓ test',
        ),
      ),
    );
  }
}

class _Harness extends StatelessWidget {
  const _Harness({required this.state, required this.rpc});

  final CartridgeHatState state;
  final RpcCaller rpc;

  @override
  Widget build(BuildContext context) {
    final identity = _FakeIdentityStore();
    return MaterialApp(
      home: SemantosPlatform(
        walletService: const _FakeWalletService(),
        conversationEngine: ConversationEngine(),
        grammarRegistry: GrammarRegistry.empty(),
        hatRegistry: HatRegistry.empty(),
        identityStore: identity,
        walletKeyService: WalletKeyService(identityStore: identity),
        rpcClient: rpc,
        child: CartridgeHatScope(
          notifier: state,
          child: HelmHomeScreen(
            dispatcher: IntentDispatcher(brain: const _FakeCellMinter()),
          ),
        ),
      ),
    );
  }
}

class _FakeRpcCaller implements RpcCaller {
  _FakeRpcCaller({required this.replOutput});

  final String replOutput;
  final List<String> replEvalCalls = [];

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? params,
  ]) async => <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> cellQuery(
    String typeHash, {
    Map<String, dynamic>? filter,
  }) async => <String, dynamic>{};

  @override
  Future<String> replEval(String cmd) async {
    replEvalCalls.add(cmd);
    return replOutput;
  }
}

class _FakeCellMinter implements CellMinter {
  const _FakeCellMinter();

  @override
  Future<MintCellResult> mintCell({
    required String typeHashHex,
    required Map<String, dynamic> payload,
  }) async => const MintCellResult(
    cellId: 'cell',
    cartridgeId: 'betterment',
    cellType: 'betterment.practice.release',
    persistedAt: 1,
  );

  @override
  Future<MintCellResult> mintCellSigned({
    required String typeHashHex,
    required Map<String, dynamic> payload,
    required String signatureHex,
    required String signerCertIdHex,
  }) async => mintCell(typeHashHex: typeHashHex, payload: payload);
}

class _FakeIdentityStore implements IdentityStore {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  bool get isHardwareBacked => false;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

class _FakeWalletService implements WalletService {
  const _FakeWalletService();

  @override
  Future<AnchorResult> anchorTransition(
    Uint8List typeHash,
    int anchorIndex,
    Uint8List newStateHash, {
    String? description,
  }) async => const AnchorResult(txid: 'anchor');

  @override
  Future<PayResult> createAction(
    List<TxInput> inputs,
    List<Output> outputs, {
    String? description,
  }) async => const PayResult(txid: 'action');

  @override
  Future<String> identityPubkeyHex() async => '00';

  @override
  Future<PayResult> pay(List<Output> outputs, {String? description}) async =>
      const PayResult(txid: 'pay');
}

void _registerBettermentForChromeTest() {
  CartridgeRegistry.instance.register(
    CartridgeEntry(
      descriptor: const CartridgeDescriptor(
        id: 'betterment',
        role: 'experience',
        title: 'Betterment',
        routePath: '/betterment',
      ),
      buildScreen: (_) => const SizedBox.shrink(),
    ),
  );
}

const _oddjobzAttentionJson = '''
{
  "total": 1,
  "pending_quote": [
    {
      "id": "job-1",
      "customer_name": "Melissa Collins",
      "state": "new",
      "propertyAddress": "12 Dollarbird Drive",
      "description": "Property manager Melissa Collins requests amendment to invoice",
      "services": "invoice amendment"
    }
  ]
}
''';

```
