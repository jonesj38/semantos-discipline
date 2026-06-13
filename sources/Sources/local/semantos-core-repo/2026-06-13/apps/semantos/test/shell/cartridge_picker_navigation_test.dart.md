---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/shell/cartridge_picker_navigation_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.131431+00:00
---

# apps/semantos/test/shell/cartridge_picker_navigation_test.dart

```dart
import 'dart:typed_data';

import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/shell/cartridge_hat_state.dart';
import 'package:semantos/shell/cartridge_picker.dart';
import 'package:semantos/shell/conversation_engine.dart';
import 'package:semantos/shell/semantos_platform.dart';
import 'package:semantos/src/wallet/wallet_key_service.dart';
import 'package:semantos_core/semantos_core.dart';

void main() {
  testWidgets('picker opens the registered cartridge screen', (tester) async {
    CartridgeRegistry.instance.resetForTest();
    final state = CartridgeHatState();

    CartridgeRegistry.instance.register(
      CartridgeEntry(
        descriptor: const CartridgeDescriptor(
          id: 'fake',
          role: 'experience',
          routePath: '/fake',
          title: 'Fake Cartridge',
        ),
        icon: Icons.extension,
        buildScreen: (_) =>
            const Scaffold(body: Center(child: Text('Fake cartridge screen'))),
      ),
    );

    await tester.pumpWidget(
      _Harness(
        state: state,
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showCartridgePicker(context),
            child: const Text('Open picker'),
          ),
        ),
      ),
    );

    expect(find.text('Open picker'), findsOneWidget);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Cartridges'), findsOneWidget);
    expect(find.text('Fake Cartridge'), findsOneWidget);

    await tester.tap(find.text('Fake Cartridge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.activeCartridge, 'fake');
    expect(find.text('Fake cartridge screen'), findsOneWidget);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.state, required this.child});

  final CartridgeHatState state;
  final Widget child;

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
        child: CartridgeHatScope(
          notifier: state,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }
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

```
