---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/main.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.091763+00:00
---

# apps/semantos/lib/main.dart

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:oddjobz_experience/oddjobz_experience.dart';
import 'package:betterment_experience/betterment_experience.dart';
import 'package:semantos_core/semantos_core.dart';

import 'platform/wallet_resolver.dart';
import 'shell/brain_connect_screen.dart';
import 'shell/cartridge_hat_state.dart';
import 'shell/conversation_engine.dart';
import 'shell/semantos_platform.dart';
import 'shell/semantos_router.dart';
import 'src/dispatch/intent_dispatcher.dart';
import 'src/dispatch/signed_mint.dart';
import 'src/wallet/wallet_key_service.dart';
import 'src/dispatch/intent_dispatcher_factory.dart';
import 'src/rpc/brain_rpc_client.dart';
import 'src/ocr/image_extract_uploader.dart';
import 'src/voice/audio_extract_uploader.dart';
import 'shell/shell_cartridge_host.dart';
import 'platform/identity_store_stub.dart'
    if (dart.library.html) 'platform/identity_store_web.dart' as identity_adapter;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BootstrapApp());
}

/// Root widget that owns the async boot sequence. Renders a loading
/// indicator while [bootResolvedNode] is in flight, a pairing screen
/// when no wallet is configured, and the full shell once booted.
class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late Future<Widget> _bootFuture;

  @override
  void initState() {
    super.initState();
    _bootFuture = _boot();
  }

  void _retry() => setState(() {
        _bootFuture = _boot();
      });

  Future<Widget> _boot() async {
    try {
      final node = await bootResolvedNode();
      return _buildShell(node);
    } on StateError {
      return BrainConnectScreen(onConnected: _retry);
    }
  }

  Widget _buildShell(ResolvedNode node) {
    final provisioner = ManifestProvisioner(
      verifier: const DevModeBundleVerifier(),
    );

    return _AsyncShell(
      node: node,
      provisioner: provisioner,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Semantos',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: FutureBuilder<Widget>(
        future: _bootFuture,
        builder: (context, snap) {
          if (snap.hasData) return snap.data!;
          if (snap.hasError) {
            return _ErrorScreen(
              error: snap.error.toString(),
              onRetry: _retry,
            );
          }
          return const _SplashScreen();
        },
      ),
    );
  }
}

/// Completes the async parts of boot (manifest provisioning, registry
/// construction) after the node is resolved, then hands off to the
/// full shell tree.
class _AsyncShell extends StatefulWidget {
  const _AsyncShell({required this.node, required this.provisioner});

  final ResolvedNode node;
  final ManifestProvisioner provisioner;

  @override
  State<_AsyncShell> createState() => _AsyncShellState();
}

class _AsyncShellState extends State<_AsyncShell> {
  late Future<_ShellData> _future;

  @override
  void initState() {
    super.initState();
    _future = _prepare();
  }

  /// Re-run boot prepare — re-reads the saved brain connection and
  /// reconnects the RPC client. Invoked after the operator enters a new
  /// connection via [BrainConnectScreen] (M1.6 native connect entry-point).
  void _reload() => setState(() => _future = _prepare());

  Future<_ShellData> _prepare() async {
    // Canonical cartridges: oddjobz + betterment. jam_experience + tessera_experience
    // archived per C8. Other cartridges with dedicated UIs would slot in here
    // alongside oddjobz/betterment per their ui.surfacingMode (canonicalization-glossary.md).
    // RENAME (2026-05-29): self_experience → betterment_experience.
    final provisioned = await Future.wait([
      OddjobzManifestLoader.provisionFromAsset(widget.provisioner),
      BettermentManifestLoader.provisionFromAsset(widget.provisioner),
    ]);

    final grammarRegistry = GrammarRegistry.fromProvisioned(provisioned);
    final hatRegistry = HatRegistry.fromGrammarRegistry(grammarRegistry);

    registerOddjobzCartridge();
    registerBettermentCartridge();

    final conversationEngine = ConversationEngine(
      grammars: [
        OddjobzIntentGrammar(),
        BettermentIntentGrammar(),
      ],
    );

    // Build the IntentDispatcher with brain creds from IdentityStore
    // (per Q4 decision). This is the seam between forklifted primitives
    // and the live brain — when dispatcher is non-null the canonical
    // helm becomes the home route (SemantosRouter handles fallback).
    final identity = identity_adapter.buildIdentityStore();

    // C11 PR-C11-4f / C7-B 2b — shell-singleton wallet key service.
    // Constructed BEFORE the dispatcher so the dispatcher can route mints
    // through the sovereign signed path (operator signs the payload; brain
    // #828 verifies before persisting). loadIdentity eagerly populates the
    // tier-0 cache (and the wallet sheet's first `ready` envelope); it's a
    // no-op when no cert_body is stored yet — the signer then yields null,
    // so the mint falls back to the unsigned path.
    final walletKeyService = WalletKeyService(identityStore: identity);
    await walletKeyService.loadIdentity();

    // M1.6 / M1.7b — construct the unified-channel BrainRpcClient from the
    // saved connection (brainUrl + brainToken in the IdentityStore) and
    // connect it BEFORE building the dispatcher, so the dispatcher's mints
    // (`cells.mint`) ride this SAME socket the reads use. connect() awaits the
    // WSS upgrade, so a 401 / bad URL surfaces here, not on first mint. The
    // client is also handed to repositories (M1.8) via SemantosPlatform.
    BrainRpcClient? rpcClient;
    String? rpcStatus;
    final brainUrl = await identity.read(NodeResolver.brainUrlKey);
    final brainToken = await identity.read(NodeResolver.brainTokenKey);
    if (brainUrl != null &&
        brainUrl.isNotEmpty &&
        brainToken != null &&
        brainToken.isNotEmpty) {
      final client = BrainRpcClient(baseUrl: brainUrl, bearer: brainToken);
      try {
        await client.connect();
        rpcClient = client;
        rpcStatus = 'RPC ✓ ${Uri.parse(brainUrl).host}';
      } catch (e) {
        rpcStatus = 'RPC ✗ ${Uri.parse(brainUrl).host}: $e';
      }
    }

    // M1.7b — the dispatcher mints over `cells.mint` on the connected RPC
    // client (a [CellMinter]). A null minter (unpaired / connect failed) ⇒ no
    // dispatcher; SemantosRouter then renders the connect prompt.
    final resolved = await buildIntentDispatcher(
      minter: rpcClient,
      signer: walletMintSigner(walletKeyService),
    );

    // C9 PR-C9-7d: cartridge dispatch bindings registered FROM THE
    // MANIFEST. Each verb in `ui.verbs[]` that carries a `dispatch`
    // block (cellType + triple + defaultPayload) gets wrapped into
    // an IntentDispatcher binding. Manifest = single source of
    // truth; cartridge packages no longer hand-maintain a parallel
    // IntentSpec constant. Verbs without `dispatch` stay declared
    // (visible in the modal verb shelf) but render `(unwired)`.
    final dispatcher = resolved.dispatcher;
    if (dispatcher != null) {
      for (final manifest in grammarRegistry.manifests) {
        for (final verb in manifest.uiVerbs) {
          final dispatch = verb.dispatch;
          if (dispatch == null) continue;
          dispatcher.registerSpec(
            intentTypeName: verb.intentType,
            cartridgeId: manifest.id,
            cellType: dispatch.cellType,
            s1: dispatch.s1,
            s2: dispatch.s2,
            s3: dispatch.s3,
            s4: dispatch.s4,
            defaultPayload: dispatch.defaultPayload,
          );
        }
      }
    }

    // Neutral capability host for cartridge-owned screens (e.g. betterment's
    // ReleaseCaptureScreen): mint over the same RPC client + OCR over the brain
    // image-extract endpoint. Installed via CartridgeHostScope in build().
    final ocrUploader = (brainUrl != null &&
            brainUrl.isNotEmpty &&
            brainToken != null &&
            brainToken.isNotEmpty)
        ? DioImageExtractUploader(
            http: Dio(),
            baseUrl: brainUrl,
            bearer: () => brainToken,
          )
        : null;
    // Voice-release transcription bounces to the brain (server-side whisper) —
    // the betterment cartridge runs on the Flutter PWA, which can't run
    // on-device inference. Available only when a brain connection exists; the
    // ShellCartridgeHost segments the returned transcript into turns.
    VoiceTranscriber? transcriber;
    if (brainUrl != null &&
        brainUrl.isNotEmpty &&
        brainToken != null &&
        brainToken.isNotEmpty) {
      final audioUploader = DioAudioExtractUploader(
        http: Dio(),
        baseUrl: brainUrl,
        bearer: () => brainToken,
      );
      transcriber = (bytes) async {
        final res = await audioUploader.upload(audioBytes: bytes);
        return switch (res) {
          AudioExtractSuccess(:final rawText) => rawText,
          AudioExtractFailed(:final reason, :final statusCode) =>
            throw Exception('audio-extract failed: $reason ($statusCode)'),
          AudioExtractNetworkError(:final message) =>
            throw Exception('audio-extract network error: $message'),
        };
      };
    }

    final cartridgeHost = ShellCartridgeHost(
      minter: rpcClient,
      ocr: ocrUploader,
      identity: identity,
      transcriber: transcriber,
    );

    return _ShellData(
      grammarRegistry: grammarRegistry,
      hatRegistry: hatRegistry,
      conversationEngine: conversationEngine,
      intentDispatcher: dispatcher,
      identityStore: identity,
      walletKeyService: walletKeyService,
      hasIdentity: walletKeyService.hasIdentity,
      rpcClient: rpcClient,
      rpcStatus: rpcStatus,
      cartridgeHost: cartridgeHost,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ShellData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) return const _SplashScreen();
        final data = snap.data!;
        // C9 PR-C9-1: cartridge-scoped hat state. Initial active
        // cartridge = first extension id in the registry (matches
        // pre-refactor default-hat behaviour: first-provisioned wins).
        // PR-C9-3 (tab strip) will let the operator change it.
        final extensionIds =
            data.hatRegistry.extensionIds.toList(growable: false);
        final initialCartridge =
            extensionIds.isNotEmpty ? extensionIds.first : null;
        final cartridgeHatState = CartridgeHatState(
          initialCartridge: initialCartridge,
        );
        return CartridgeHatScope(
          notifier: cartridgeHatState,
          child: CartridgeHostScope(
            host: data.cartridgeHost,
            child: SemantosPlatform(
            walletService: widget.node.wallet,
            conversationEngine: data.conversationEngine,
            grammarRegistry: data.grammarRegistry,
            hatRegistry: data.hatRegistry,
            identityStore: data.identityStore,
            walletKeyService: data.walletKeyService,
            rpcClient: data.rpcClient,
            child: SemantosRouter(
              dispatcher: data.intentDispatcher,
              hasIdentity: data.hasIdentity,
              rpcStatus: data.rpcStatus,
              isConnected: data.rpcClient != null,
              onReconnect: _reload,
            ),
            ),
          ),
        );
      },
    );
  }
}

class _ShellData {
  const _ShellData({
    required this.grammarRegistry,
    required this.hatRegistry,
    required this.conversationEngine,
    required this.identityStore,
    required this.walletKeyService,
    required this.hasIdentity,
    this.intentDispatcher,
    this.rpcClient,
    this.rpcStatus,
    required this.cartridgeHost,
  });

  final GrammarRegistry grammarRegistry;
  final HatRegistry hatRegistry;
  final ConversationEngine conversationEngine;
  final IdentityStore identityStore;
  final WalletKeyService walletKeyService;
  final IntentDispatcher? intentDispatcher;

  /// Snapshot of WalletKeyService.hasIdentity at boot. False means
  /// no cert_body was loaded — SemantosRouter shows a persistent
  /// banner across every screen until provisioning lands. See the
  /// SemantosRouter doc-comment for the detect-only rationale.
  final bool hasIdentity;

  /// M1.6 — the unified-channel RPC client, connected at boot when a
  /// brain connection is saved. Null when unpaired or the connect failed.
  /// Repositories (M1.8) read through this; the dispatcher's mints move
  /// onto it in M1.7b.
  final BrainRpcClient? rpcClient;

  /// Human-readable boot-time RPC connection status (✓/✗ + probe result),
  /// shown as a banner by SemantosRouter so the channel state is visible.
  final String? rpcStatus;

  /// Neutral capability host handed to cartridge-owned custom screens via
  /// CartridgeHostScope (mint + OCR without a cartridge→shell import).
  final ShellCartridgeHost cartridgeHost;
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

```
