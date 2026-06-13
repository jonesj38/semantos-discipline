---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/semantos_platform.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.101094+00:00
---

# apps/semantos/lib/shell/semantos_platform.dart

```dart
import 'package:flutter/material.dart';
import 'package:semantos_core/semantos_core.dart';

import '../src/rpc/brain_rpc_client.dart' show RpcCaller;
import '../src/wallet/wallet_key_service.dart';
import 'conversation_engine.dart';

/// The root widget that provides platform services to all descendant
/// widgets. Experience packages (oddjobz_experience, jam_experience)
/// access the wallet, conversation engine, grammar registry, and hat
/// registry via [SemantosPlatform.of(context)].
class SemantosPlatform extends InheritedWidget {
  final WalletService walletService;
  final ConversationEngine conversationEngine;

  /// All extensions the shell loaded at boot — surfaced so
  /// experiences can inspect what other experiences are active (e.g.
  /// for cross-extension links in the home screen).
  final GrammarRegistry grammarRegistry;

  /// Composed hat list across all active extensions. The shell's
  /// active-hat selector reads from here.
  final HatRegistry hatRegistry;

  /// C11 PR-C11-3: the operator's identity custody seam (Keychain /
  /// Keystore on native, IndexedDB on web). The Me sheet's secret-
  /// question + recovery-envelope flows persist their state here. Also
  /// holds the brain url / bearer the dispatcher built from at boot —
  /// post-C11 work can read those back without reconstructing the
  /// adapter.
  final IdentityStore identityStore;

  /// C11 PR-C11-4f: shell-singleton wallet key service. Owns cert
  /// custody, tier-0 derivation, and the recipe store for the active
  /// operator identity. Lives across wallet-sheet opens so any Dart
  /// consumer (renderer bridge, REPL verbs, intent dispatch, cell
  /// anchoring) operates on the same key state. See
  /// `lib/src/wallet/wallet_key_service.dart` and
  /// `docs/design/WALLET-RENDERER-CONTRACT.md` §5.
  final WalletKeyService walletKeyService;

  /// M1.6 — the unified-channel RPC client, connected at boot from the
  /// saved brain connection. Null when unpaired or the connect failed.
  /// Repositories (M1.8 generic renderer) read through this via
  /// `SemantosPlatform.of(context).rpcClient`; the dispatcher's mints move
  /// onto it in M1.7b. Typed as the [RpcCaller] interface so consumers +
  /// tests depend on the abstraction, not the concrete socket client.
  final RpcCaller? rpcClient;

  const SemantosPlatform({
    super.key,
    required this.walletService,
    required this.conversationEngine,
    required this.grammarRegistry,
    required this.hatRegistry,
    required this.identityStore,
    required this.walletKeyService,
    this.rpcClient,
    required super.child,
  });

  static SemantosPlatform of(BuildContext context) {
    final platform =
        context.dependOnInheritedWidgetOfExactType<SemantosPlatform>();
    assert(
      platform != null,
      'SemantosPlatform.of() called outside a SemantosPlatform widget.',
    );
    return platform!;
  }

  @override
  bool updateShouldNotify(SemantosPlatform oldWidget) =>
      walletService != oldWidget.walletService ||
      conversationEngine != oldWidget.conversationEngine ||
      grammarRegistry != oldWidget.grammarRegistry ||
      hatRegistry != oldWidget.hatRegistry ||
      identityStore != oldWidget.identityStore ||
      walletKeyService != oldWidget.walletKeyService ||
      rpcClient != oldWidget.rpcClient;
}

```
