---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/node_resolver.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.016100+00:00
---

# platforms/flutter/semantos_core/lib/src/node_resolver.dart

```dart
import 'brain_verb_dispatch_client.dart';
import 'brain_wallet_service.dart';
import 'identity_store.dart';
import 'node_target.dart';
import 'stt_provider.dart';
import 'verb_dispatch_client.dart';
import 'wallet_service.dart';

/// Boot-time resolved adapter set for the active [NodeTarget].
///
/// The shell receives one [ResolvedNode] from [NodeResolver.resolve] and
/// uses it for every wallet, identity, and STT operation thereafter. No
/// code below this layer needs to know whether it's running native or PWA.
class ResolvedNode {
  final NodeTarget target;
  final WalletService wallet;
  final IdentityStore identity;
  final SttProvider stt;

  /// Optional kernel handle (FFI on native, WASM on PWA, or null when
  /// running in pure remote-thin-client mode). The shell treats kernel
  /// access as best-effort: if null, all cell ops go through the brain.
  final Object? kernel;

  /// Optional verb.dispatch client. Built when a paired brain is
  /// configured (the same `(brainUrl, bearerToken)` that gave us the
  /// [BrainWalletService]). Null in the no-brain fallback path —
  /// experience packages that need it should guard accordingly.
  final VerbDispatchClient? verbDispatch;

  const ResolvedNode({
    required this.target,
    required this.wallet,
    required this.identity,
    required this.stt,
    this.kernel,
    this.verbDispatch,
  });
}

/// Configurable factory for building a [ResolvedNode].
///
/// The shell registers concrete adapter factories per target (typically
/// from the platform's entrypoint — e.g. semantos_ffi for native,
/// semantos_web for PWA), then calls [resolve] to pick the right tuple.
///
/// This is the platform's only target-aware seam. Everything else in the
/// shell consumes [ResolvedNode] and is target-agnostic.
class NodeResolver {
  final NodeTarget target;
  final Future<IdentityStore> Function() identityFactory;
  final Future<SttProvider> Function() sttFactory;
  final Future<Object?> Function()? kernelFactory;

  /// Brain connection lookup keys (read from [identity] after it loads).
  static const String brainUrlKey = 'semantos.brain.url';
  static const String brainTokenKey = 'semantos.brain.token';
  static const String operatorWifKey = 'semantos.operator.wif';

  /// Factory the resolver uses when the operator has a paired brain
  /// (any target). The [NodeResolver] reads the URL + bearer token from
  /// the [IdentityStore] and hands them to this factory.
  final WalletService Function({
    required String baseUrl,
    required String bearerToken,
  }) brainWalletFactory;

  /// Optional factory for the local FFI wallet (native-only path).
  /// PWA registrations leave this null — there's no local wallet on web.
  /// When null and no paired brain is found, [resolve] throws.
  final WalletService Function({required String wif})? ffiWalletFactory;

  NodeResolver({
    required this.target,
    required this.identityFactory,
    required this.sttFactory,
    required this.brainWalletFactory,
    this.kernelFactory,
    this.ffiWalletFactory,
  });

  /// Default-construct a [NodeResolver] wired with the built-in
  /// [BrainWalletService] for the brain path. Callers supply identity
  /// + STT factories per target.
  factory NodeResolver.withDefaults({
    required NodeTarget target,
    required Future<IdentityStore> Function() identityFactory,
    required Future<SttProvider> Function() sttFactory,
    Future<Object?> Function()? kernelFactory,
    WalletService Function({required String wif})? ffiWalletFactory,
  }) {
    return NodeResolver(
      target: target,
      identityFactory: identityFactory,
      sttFactory: sttFactory,
      kernelFactory: kernelFactory,
      ffiWalletFactory: ffiWalletFactory,
      brainWalletFactory: ({required String baseUrl, required String bearerToken}) {
        return BrainWalletService(baseUrl: baseUrl, bearerToken: bearerToken);
      },
    );
  }

  Future<ResolvedNode> resolve() async {
    final identity = await identityFactory();
    final stt = await sttFactory();
    final kernel = kernelFactory != null ? await kernelFactory!() : null;

    final brainUrl = await identity.read(brainUrlKey);
    final brainToken = await identity.read(brainTokenKey);

    final WalletService wallet;
    VerbDispatchClient? verbDispatch;
    if (brainUrl != null &&
        brainUrl.isNotEmpty &&
        brainToken != null &&
        brainToken.isNotEmpty) {
      wallet = brainWalletFactory(baseUrl: brainUrl, bearerToken: brainToken);
      // verb.dispatch rides the same (baseUrl, bearerToken) — opening
      // the WSS upgrade on /api/v1/wallet uses the same bearer the
      // wallet HTTP path uses.
      verbDispatch = BrainVerbDispatchClient(
        baseUrl: brainUrl,
        bearerToken: brainToken,
      );
    } else if (ffiWalletFactory != null) {
      final wif = await identity.read(operatorWifKey);
      if (wif == null || wif.isEmpty) {
        throw StateError(
          'No wallet configuration found. '
          'Pair with a brain (Settings → Pair) or provision an operator key.',
        );
      }
      wallet = ffiWalletFactory!(wif: wif);
      // No brain paired — substrate writes go through FFI; verb.dispatch
      // is brain-only, so verbDispatch stays null.
    } else {
      throw StateError(
        'PWA target requires a paired brain. '
        'No FFI wallet fallback available in this build.',
      );
    }

    return ResolvedNode(
      target: target,
      wallet: wallet,
      identity: identity,
      stt: stt,
      kernel: kernel,
      verbDispatch: verbDispatch,
    );
  }
}

```
