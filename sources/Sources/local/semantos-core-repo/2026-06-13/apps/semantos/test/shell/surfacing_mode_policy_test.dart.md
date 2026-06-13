---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/shell/surfacing_mode_policy_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.132258+00:00
---

# apps/semantos/test/shell/surfacing_mode_policy_test.dart

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
  setUp(() {
    CartridgeRegistry.instance.resetForTest();
  });

  test(
    'surfacing policy aggregates field verbs from default cartridges only',
    () {
      final registry = GrammarRegistry.fromJsonStrings([
        _manifestJson(
          id: 'default-cart',
          name: 'Default Cart',
          surfacingMode: 'default',
          domainFlag: 0x010001,
          verbs: const [
            _Verb('do', 'Default Do', 'default.do'),
            _Verb('talk', 'Default Talk', 'default.talk'),
            _Verb('find', 'Default Find', 'default.find'),
          ],
        ),
        _manifestJson(
          id: 'dedicated-cart',
          name: 'Dedicated Cart',
          surfacingMode: 'dedicated',
          domainFlag: 0x010002,
          verbs: const [_Verb('do', 'Dedicated Do', 'dedicated.do')],
        ),
        _manifestJson(
          id: 'passive-cart',
          name: 'Passive Cart',
          surfacingMode: 'passive',
          domainFlag: 0x010003,
          verbs: const [_Verb('do', 'Passive Do', 'passive.do')],
        ),
      ]);

      expect(
        registry.verbsForModal(HelmVerbModal.do_).map((b) => b.verb.label),
        ['Default Do'],
        reason:
            'DO/TALK/FIND are field verbs; dedicated/passive cartridges do not contribute',
      );
      expect(
        registry.verbsForModal(HelmVerbModal.talk).map((b) => b.verb.label),
        ['Default Talk'],
      );
      expect(
        registry.verbsForModal(HelmVerbModal.find).map((b) => b.verb.label),
        ['Default Find'],
      );

      expect(
        registry.verbsForModalAndExtension(HelmVerbModal.do_, 'dedicated-cart'),
        isEmpty,
        reason:
            'dedicated cartridges own their own surface instead of field verbs',
      );
      expect(
        registry.verbsForModalAndExtension(HelmVerbModal.do_, 'passive-cart'),
        isEmpty,
        reason: 'passive cartridges are silent in the helm',
      );
    },
  );

  testWidgets(
    'picker shows default and dedicated cartridges but hides passive',
    (tester) async {
      final state = CartridgeHatState();
      final registry = GrammarRegistry.fromJsonStrings([
        _manifestJson(
          id: 'default-cart',
          name: 'Default Cart',
          surfacingMode: 'default',
          domainFlag: 0x010001,
        ),
        _manifestJson(
          id: 'dedicated-cart',
          name: 'Dedicated Cart',
          surfacingMode: 'dedicated',
          domainFlag: 0x010002,
        ),
        _manifestJson(
          id: 'passive-cart',
          name: 'Passive Cart',
          surfacingMode: 'passive',
          domainFlag: 0x010003,
        ),
      ]);

      for (final id in ['default-cart', 'dedicated-cart', 'passive-cart']) {
        CartridgeRegistry.instance.register(
          CartridgeEntry(
            descriptor: CartridgeDescriptor(
              id: id,
              role: 'experience',
              routePath: '/$id',
              title: 'Title $id',
            ),
            buildScreen: (_) => Scaffold(body: Text('screen for $id')),
          ),
        );
      }

      await tester.pumpWidget(
        _Harness(
          state: state,
          registry: registry,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCartridgePicker(context),
              child: const Text('Open picker'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open picker'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('2 active'), findsOneWidget);
      expect(find.text('Title default-cart'), findsOneWidget);
      expect(find.text('Title dedicated-cart'), findsOneWidget);
      expect(find.text('Title passive-cart'), findsNothing);
      expect(find.text('passive-cart'), findsNothing);

      await tester.tap(find.text('Title dedicated-cart'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(state.activeCartridge, 'dedicated-cart');
      expect(find.text('screen for dedicated-cart'), findsOneWidget);
    },
  );
}

class _Verb {
  final String modal;
  final String label;
  final String intentType;
  const _Verb(this.modal, this.label, this.intentType);
}

String _manifestJson({
  required String id,
  required String name,
  required String surfacingMode,
  required int domainFlag,
  List<_Verb> verbs = const [],
}) {
  final verbJson = verbs
      .map(
        (v) =>
            '''{
          "modal": "${v.modal}",
          "label": "${v.label}",
          "intentType": "${v.intentType}"
        }''',
      )
      .join(',');
  return '''
{
  "id": "$id",
  "name": "$name",
  "version": "0.1.0",
  "domainFlag": $domainFlag,
  "grammar": {
    "extensionId": "$id",
    "lexicon": { "name": "$id", "categories": [] },
    "defaultTaxonomyWhat": "$id.item",
    "objectTypes": [],
    "actions": []
  },
  "ui": {
    "surfacingMode": "$surfacingMode",
    "verbs": [$verbJson]
  }
}
''';
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.state,
    required this.registry,
    required this.child,
  });

  final CartridgeHatState state;
  final GrammarRegistry registry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final identity = _FakeIdentityStore();
    return MaterialApp(
      home: SemantosPlatform(
        walletService: const _FakeWalletService(),
        conversationEngine: ConversationEngine(),
        grammarRegistry: registry,
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
