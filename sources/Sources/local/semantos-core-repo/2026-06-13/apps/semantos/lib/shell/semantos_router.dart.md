---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/semantos_router.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.100795+00:00
---

# apps/semantos/lib/shell/semantos_router.dart

```dart
import 'package:flutter/material.dart';
import 'package:oddjobz_experience/oddjobz_experience.dart';

import '../src/dispatch/intent_dispatcher.dart';
import 'brain_connect_screen.dart';
import 'cartridge_hat_state.dart';
import 'helm_home_screen.dart';
import 'me/me_sheet.dart';
import 'semantos_platform.dart';

/// The top-level router.
///
/// Routes the canonical home to [HelmHomeScreen]. When a dispatcher
/// hasn't been wired (boot failure / unpaired brain / tests), the home
/// falls back to a tiny shell-neutral boot-incomplete view rather than
/// the legacy cartridge-index page.
///
/// PR-C9-7a (2026-05-29): the legacy `/cartridges` index route +
/// `_CartridgeIndexScreen` widget were removed. They were a pre-helm
/// surface that crossed wires with the canonical home — tapping a
/// cartridge from the index opened a stale full-screen view that the
/// modal verb shelf was supposed to supersede. Cartridge picking now
/// lives in the AppBar apps-icon → [CartridgePicker] bottom sheet,
/// and the modal verb shelf is the only verb-dispatch surface.
class SemantosRouter extends StatefulWidget {
  /// IntentDispatcher built at boot by _BootstrapApp via buildIntentDispatcher.
  /// When non-null the canonical helm becomes the home route.
  final IntentDispatcher? dispatcher;

  /// True when the wallet key service successfully loaded a cert_body
  /// at boot (i.e. WalletKeyService.hasIdentity). When false, a
  /// persistent banner appears at the top of every screen telling
  /// the operator that identity provisioning hasn't run yet — some
  /// surfaces (the wallet sheet, signing, BRC-100 actions) will not
  /// behave normally until a cert is in place.
  ///
  /// Detect-only by design: the banner does not link to a provisioning
  /// flow because cert provisioning (BRC-52 cert + capability +
  /// Plexus challenge) is parked in the phase-1b cluster — see the
  /// `semantos_parked_identity_phase1b` memory note. Until that lands,
  /// this gate's job is honesty, not remediation.
  final bool hasIdentity;

  /// M1.6 — boot-time RPC connection status (e.g. "RPC ✓ host" or
  /// "RPC ✗ host: error"). Null when unpaired. Rendered as a thin banner so
  /// the unified-channel connection state is visible.
  final String? rpcStatus;

  /// M1.6 — whether the [BrainRpcClient] connected at boot. When false, the
  /// banner offers a Connect affordance (native has no wallet-gated pairing
  /// screen, so this is the operator's entry-point to point at a brain).
  final bool isConnected;

  /// Invoked after a new connection is saved via [BrainConnectScreen] — the
  /// shell re-runs boot prepare so the RPC client reconnects.
  final VoidCallback? onReconnect;

  const SemantosRouter({
    super.key,
    this.dispatcher,
    this.hasIdentity = true,
    this.rpcStatus,
    this.isConnected = false,
    this.onReconnect,
  });

  @override
  State<SemantosRouter> createState() => _SemantosRouterState();
}

class _SemantosRouterState extends State<SemantosRouter> {
  // Stable across rebuilds so pushing the connect screen doesn't reset the
  // navigator. The banner lives in MaterialApp.builder (above the Navigator),
  // so it pushes through this key rather than an inherited Navigator.
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  void _openConnect() {
    _navKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => BrainConnectScreen(
          onConnected: () {
            _navKey.currentState?.pop();
            widget.onReconnect?.call();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The OddJobz operator app is a cartridge-owned field surface, not shell
    // chrome. Only mount it while OddJobz is the active cartridge; otherwise the
    // home route stays on the cartridge-neutral helm so Betterment/null scopes
    // cannot invoke OddJobz repositories or REPL verbs through Home/Do/Talk/Find.
    final homeBuilder = widget.dispatcher != null
        ? (BuildContext ctx) {
            final rpc = SemantosPlatform.of(ctx).rpcClient;
            final activeCartridge = CartridgeHatScope.of(ctx).activeCartridge;
            if (rpc != null && activeCartridge == 'oddjobz') {
              return OperatorShell(
                rpc: _OddjobzRpcAdapter(rpc),
                onMePressed: () => showMeSheet(ctx),
              );
            }
            return HelmHomeScreen(dispatcher: widget.dispatcher!);
          }
        : (BuildContext _) => const _BootIncompleteScreen();

    final needsNoCert = !widget.hasIdentity;
    // Show the RPC region whenever there's a status to report OR we're not
    // connected (so the operator always has a way to connect).
    final needsRpc = widget.rpcStatus != null || !widget.isConnected;

    return MaterialApp(
      title: 'Semantos',
      navigatorKey: _navKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      builder: (needsNoCert || needsRpc)
          ? (context, child) => _TopBanners(
              showNoCert: needsNoCert,
              isConnected: widget.isConnected,
              rpcStatus: widget.rpcStatus,
              onConnect: _openConnect,
              child: child,
            )
          : null,
      initialRoute: '/',
      routes: <String, WidgetBuilder>{'/': homeBuilder},
    );
  }
}

class _OddjobzRpcAdapter implements OddjobzRpc {
  const _OddjobzRpcAdapter(this._inner);

  final dynamic _inner;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? params,
  ]) => _inner.call(method, params);

  @override
  Future<Map<String, dynamic>> cellQuery(
    String typeHash, {
    Map<String, dynamic>? filter,
  }) => _inner.cellQuery(typeHash, filter: filter);

  @override
  Future<String> replEval(String cmd) => _inner.replEval(cmd);
}

/// Stacks the optional boot banners (no-cert + RPC connection state) above
/// the navigator. When disconnected, the RPC banner carries a Connect button
/// that opens [BrainConnectScreen]; when connected it's a confirmation chip.
class _TopBanners extends StatelessWidget {
  const _TopBanners({
    required this.showNoCert,
    required this.isConnected,
    required this.rpcStatus,
    required this.onConnect,
    required this.child,
  });

  final bool showNoCert;
  final bool isConnected;
  final String? rpcStatus;
  final VoidCallback onConnect;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (showNoCert)
              _Banner(
                key: const Key('no-cert-banner'),
                bg: theme.colorScheme.errorContainer,
                fg: theme.colorScheme.onErrorContainer,
                icon: Icons.warning_amber_rounded,
                text:
                    'No identity cert — wallet sign + BRC-100 surfaces '
                    'unavailable until provisioning lands.',
              ),
            if (isConnected && rpcStatus != null)
              _Banner(
                key: const Key('rpc-status-banner'),
                bg: theme.colorScheme.primaryContainer,
                fg: theme.colorScheme.onPrimaryContainer,
                icon: Icons.cloud_done_outlined,
                text: rpcStatus!,
              ),
            if (!isConnected)
              _Banner(
                key: const Key('rpc-connect-banner'),
                bg: theme.colorScheme.errorContainer,
                fg: theme.colorScheme.onErrorContainer,
                icon: Icons.cloud_off_outlined,
                text: rpcStatus ?? 'Not connected to a brain.',
                action: TextButton(
                  onPressed: onConnect,
                  child: const Text('Connect'),
                ),
              ),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

/// One full-width banner row.
class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.bg,
    required this.fg,
    required this.icon,
    required this.text,
    this.action,
  });

  final Color bg;
  final Color fg;
  final IconData icon;
  final String text;

  /// Optional trailing widget (e.g. a Connect button).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: fg, fontSize: 13)),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Fallback rendered when boot hasn't produced an IntentDispatcher.
/// Communicates the state explicitly instead of silently dropping the
/// user into a stale surface.
class _BootIncompleteScreen extends StatelessWidget {
  const _BootIncompleteScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Semantos')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.hourglass_empty,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text('Boot incomplete.', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Pair this device to a brain to enable the helm.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

```
