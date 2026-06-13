---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/me/wallet_launch.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.119834+00:00
---

# apps/semantos/lib/shell/me/wallet_launch.dart

```dart
// C11 PR-C11-4 — Wallet row + native webview of the stripped renderer.
//
// References:
//   - docs/design/HELM-ME-SURFACE.md §3 row 2 (Wallet) + D2 (native
//     webview vs external tab)
//   - docs/design/PLEXUS-ALIGNMENT.md §10.C (cert custody via
//     SecureStore adapter)
//   - docs/design/WALLET-RENDERER-CONTRACT.md (the authority — Dart
//     owns all keys; the in-webview JS is a renderer only)
//
// Architecture:
//
//   The renderer bundle (wallet.html + wallet-page.js) lives under
//   `apps/semantos/assets/wallet/`. As of PR-C11-4d, both files are
//   hand-written, dependency-free, and ship NO wasm — every byte of
//   cryptographic material lives in Dart (PR-C11-4c landed cert
//   custody, tier-0, recipe store).
//
//   The assets are served to `webview_flutter` by a per-sheet
//   loopback HTTP server bound to `127.0.0.1` on a kernel-chosen
//   port (see `wallet_asset_server.dart` for the full rationale,
//   including why `loadFlutterAsset()` does not work).
//
// Bridge status (re-tally 2026-05-31):
//   The `SemantosWallet` JavaScriptChannel IS wired (see `addJavaScriptChannel`
//   below). Renderer posts → `_handleInbound` → `WalletBridge.handle()`;
//   replies dispatch back via `runJavaScript("window.SemantosWallet_dispatch")`.
//   Live verbs: `ready`, `address.request`, `derivation.request`. `tx.request`
//   is explicitly deferred to PR-C11-7 (UTXO store + tx builder) — see
//   wallet_bridge.dart:114–121 for the inline rejection message the bridge
//   returns to the renderer in the meantime.
//
//   Cert body / tier-0 / recipe-store ↔ renderer flows are bound through
//   `WalletKeyService` (DI'd into `WalletBridge`), which reads from the
//   stores landed in PR-C11-4c.
//
// Bundle workflow (until CI consolidates):
//   1. Edit `apps/semantos/assets/wallet/wallet.html` and
//      `wallet-page.js` directly (hand-written stub renderer; no
//      build step).
//   2. `flutter pub get`
//   3. `flutter build apk` (or hot-restart via `flutter run --debug`).
// The legacy `cd cartridges/wallet-headers && bun run build` step is
// gone — wallet-headers is no longer the source of truth for the
// in-app wallet payload. It remains a reference for the panel
// layouts the renderer will eventually replicate (contract §8).

import 'dart:async' show unawaited;
import 'dart:convert' show jsonEncode;

import 'package:flutter/material.dart';
import 'package:semantos_core/semantos_core.dart' show IdentityStore;
import 'package:webview_flutter/webview_flutter.dart';

import '../../src/wallet/wallet_bridge.dart';
import '../../src/wallet/wallet_key_service.dart';
import '../semantos_platform.dart';
import 'wallet_asset_server.dart';

/// Bundled wallet entry file (relative to the asset-server root).
const String kWalletEntry = 'wallet.html';

/// Wallet-webview probe logger.
///
/// Routed through `debugPrint` (not `dart:developer.log`) so the lines
/// reach `flutter run` stdout and `adb logcat` instead of disappearing
/// into the DevTools Logging tab. `debugPrint` is gated off in release
/// via the framework's no-op override, so production builds stay quiet.
void _logWallet(String message, {String name = 'wallet', int level = 800}) {
  final tag = level >= 1000 ? 'ERROR' : (level >= 900 ? 'WARN' : 'INFO');
  debugPrint('[$name] [$tag] $message');
}

/// Show the wallet in a full-screen sheet. Returns when the operator
/// dismisses the sheet. State (identity cache, IndexedDB stores) is
/// scoped to the webview's origin — see the file header for the
/// persistence caveat.
///
/// Reads the shell's `IdentityStore` and `WalletKeyService` from
/// `SemantosPlatform.of(context)` so the bridge can drive the
/// renderer with the active operator identity. See
/// `lib/src/wallet/wallet_bridge.dart` and
/// `lib/src/wallet/wallet_key_service.dart`.
Future<void> showWalletSheet(BuildContext context) {
  final platform = SemantosPlatform.of(context);
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => _WalletSheet(
        identityStore: platform.identityStore,
        walletKeyService: platform.walletKeyService,
      ),
    ),
  );
}

class _WalletSheet extends StatefulWidget {
  const _WalletSheet({
    required this.identityStore,
    required this.walletKeyService,
  });

  final IdentityStore identityStore;
  final WalletKeyService walletKeyService;

  @override
  State<_WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends State<_WalletSheet> {
  final WalletAssetServer _assetServer = WalletAssetServer();
  late final WalletBridge _bridge = WalletBridge(
    service: widget.walletKeyService,
    identityStore: widget.identityStore,
  );
  WebViewController? _controller;
  int _loadingPercent = 0;
  String? _loadError;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    _bringUp();
  }

  Future<void> _bringUp() async {
    try {
      final base = await _assetServer.start();
      final entry = base.resolve(kWalletEntry);
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0F1115))
        // Forward webview console.{log,warn,error} into dart logs so
        // wallet-page.js failures surface in `flutter logs` / logcat.
        ..setOnConsoleMessage((JavaScriptConsoleMessage msg) {
          _logWallet(
            '[wallet-webview] ${msg.message}',
            level: switch (msg.level) {
              JavaScriptLogLevel.error => 1000,
              JavaScriptLogLevel.warning => 900,
              _ => 800,
            },
          );
        })
        // `SemantosWallet` bridge channel (live). JS posts here via
        // `window.SemantosWallet.postMessage(JSON.stringify(env))`;
        // the Dart side decodes the envelope, routes it through
        // `WalletBridge`, and dispatches any reply envelopes back via
        // `runJavaScript("window.SemantosWallet_dispatch(...)")`. See
        // `lib/src/wallet/wallet_bridge.dart::handle` for the live verb
        // table.
        ..addJavaScriptChannel(
          'SemantosWallet',
          onMessageReceived: (JavaScriptMessage msg) {
            unawaited(_handleInbound(msg.message));
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (p) {
              if (!mounted) return;
              setState(() => _loadingPercent = p);
            },
            onPageStarted: (url) {
              _logWallet('[wallet-nav] onPageStarted url=$url');
              if (!mounted) return;
              setState(() {
                _loadingPercent = 0;
                _loadError = null;
              });
            },
            onPageFinished: (url) {
              _logWallet('[wallet-nav] onPageFinished url=$url');
              if (!mounted) return;
              setState(() => _loadingPercent = 100);
            },
            onWebResourceError: (err) {
              // Always log; only flip the UI into error state on
              // main-frame failures (subresource errors are common
              // during boot, e.g. external SPV probes timing out).
              _logWallet(
                '[wallet-nav] onWebResourceError mainFrame=${err.isForMainFrame} '
                'code=${err.errorCode} type=${err.errorType} '
                'url=${err.url} desc=${err.description}',
                level: 1000,
              );
              if (!mounted) return;
              if (err.isForMainFrame ?? false) {
                setState(() => _loadError = err.description);
              }
            },
          ),
        )
        ..loadRequest(entry);
      _logWallet('[wallet-nav] loadRequest($entry) issued');
      if (!mounted) {
        // The sheet was dismissed before bring-up completed; drop the
        // server we just started.
        await _assetServer.stop();
        return;
      }
      setState(() => _controller = controller);
    } catch (e, s) {
      _logWallet('[wallet-boot] bring-up failed: $e\n$s', level: 1000);
      if (!mounted) return;
      setState(() => _bootError = '$e');
    }
  }

  /// Route a `SemantosWallet` envelope from the renderer through the
  /// bridge, then dispatch any reply envelopes back into the page.
  Future<void> _handleInbound(String raw) async {
    _logWallet('[wallet-bridge] in: $raw');
    try {
      final replies = await _bridge.handle(raw);
      for (final env in replies) {
        await _dispatchToJs(env);
      }
    } catch (e, s) {
      _logWallet('[wallet-bridge] handler crashed: $e\n$s', level: 1000);
    }
  }

  /// Push a Dart-built envelope into the renderer via the
  /// `window.SemantosWallet_dispatch(...)` entrypoint defined by
  /// `wallet-page.js`. The argument is the envelope as a JSON value
  /// (object literal), not a stringified JSON — the renderer's
  /// handler expects `env.kind`, not `JSON.parse(env).kind`.
  Future<void> _dispatchToJs(WalletEnvelope env) async {
    final controller = _controller;
    if (controller == null) return;
    final payloadLiteral = jsonEncode(env.toJson());
    final script = 'window.SemantosWallet_dispatch($payloadLiteral);';
    _logWallet('[wallet-bridge] out: ${env.kind}');
    try {
      await controller.runJavaScript(script);
    } catch (e) {
      _logWallet('[wallet-bridge] runJavaScript failed: $e', level: 1000);
    }
  }

  @override
  void dispose() {
    _bridge.dispose();
    // Fire-and-forget — close the listening socket. We don't await
    // because dispose must not block the framework.
    unawaited(_assetServer.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D24),
        foregroundColor: const Color(0xFFE8EAED),
        title: const Text('Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _controller == null ? null : () => _controller!.reload(),
          ),
        ],
        bottom: _loadingPercent > 0 && _loadingPercent < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _loadingPercent / 100.0,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_bootError != null) {
      return _WalletErrorBody(
        error: 'Loopback asset server failed to start:\n${_bootError!}',
        onRetry: () {
          setState(() => _bootError = null);
          _bringUp();
        },
        theme: theme,
      );
    }
    if (_loadError != null) {
      return _WalletErrorBody(
        error: _loadError!,
        onRetry: () {
          setState(() => _loadError = null);
          _controller?.reload();
        },
        theme: theme,
      );
    }
    final controller = _controller;
    if (controller == null) {
      // Server is starting; show a spinner so the operator sees
      // motion instead of a black sheet.
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE8EAED)),
        ),
      );
    }
    return WebViewWidget(controller: controller);
  }
}

class _WalletErrorBody extends StatelessWidget {
  const _WalletErrorBody({
    required this.error,
    required this.onRetry,
    required this.theme,
  });

  final String error;
  final VoidCallback onRetry;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Color(0xFFE8EAED),
              size: 40,
            ),
            const SizedBox(height: 16),
            const Text(
              'Wallet failed to load.',
              style: TextStyle(color: Color(0xFFE8EAED)),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                color: Color(0xFF6F78A0),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}


```
