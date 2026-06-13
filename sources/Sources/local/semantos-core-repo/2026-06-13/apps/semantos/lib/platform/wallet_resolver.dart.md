---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/platform/wallet_resolver.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.099339+00:00
---

# apps/semantos/lib/platform/wallet_resolver.dart

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:semantos_core/semantos_core.dart';

// Conditional import: native targets get the real FFI factory; web gets
// a stub that returns null. This keeps `dart:ffi` out of the web build's
// import graph entirely (Flutter web rejects any transitive dart:ffi).
import 'ffi_wallet_factory_stub.dart'
    if (dart.library.io) 'ffi_wallet_factory_native.dart';

// Conditional import: native targets get flutter_secure_storage-backed
// IdentityStore (Keychain / Keystore); web targets get an
// IndexedDB-backed adapter via idb_shim that is wasm-clean. The stub
// file imports flutter_secure_storage and is selected on native; the
// web file imports idb_shim and is selected on web.
import 'identity_store_stub.dart'
    if (dart.library.html) 'identity_store_web.dart' as identity_adapter;

/// Placeholder STT provider that signals "transcribe via the brain"
/// for any target. The shell currently uploads audio to
/// /api/v1/voice-extract; on-device STT (whisper.cpp native, Web Speech
/// for PWA) plugs in by replacing this in the [NodeResolver] STT factory.
class BrainBackedSttProvider implements SttProvider {
  const BrainBackedSttProvider();

  @override
  bool get isOnDevice => false;

  @override
  Future<SttResult> transcribe(SttRequest request) {
    throw UnimplementedError(
      'BrainBackedSttProvider.transcribe — audio upload is handled by '
      'the shell\'s VoiceExtractUploader today. Replace this provider '
      'with a target-specific implementation (Whisper for native, '
      'Web Speech for PWA) to bring STT in-process.',
    );
  }
}

/// Resolves the active [WalletService] implementation at boot.
///
/// Thin wrapper around [NodeResolver] that preserves the existing API
/// surface for callers that only need wallet resolution. New code should
/// prefer [bootResolvedNode] which returns the full adapter tuple.
class WalletResolver {
  static Future<WalletService> resolve() async {
    final node = await bootResolvedNode();
    return node.wallet;
  }

  /// Persist a brain connection after a successful pairing handshake.
  /// Routes through the target's [IdentityStore] so PWA writes hit
  /// IndexedDB and native writes hit Keychain/Keystore — no
  /// flutter_secure_storage direct use.
  static Future<void> saveBrainConnection({
    required String baseUrl,
    required String bearerToken,
  }) async {
    final identity = identity_adapter.buildIdentityStore();
    await Future.wait([
      identity.write(NodeResolver.brainUrlKey, baseUrl),
      identity.write(NodeResolver.brainTokenKey, bearerToken),
    ]);
  }

  /// Clear the stored brain connection (e.g. on sign-out).
  static Future<void> clearBrainConnection() async {
    final identity = identity_adapter.buildIdentityStore();
    await Future.wait([
      identity.delete(NodeResolver.brainUrlKey),
      identity.delete(NodeResolver.brainTokenKey),
    ]);
  }
}

/// Boot-time entrypoint for the shell — returns the full [ResolvedNode]
/// for the current target. Native gets the FFI wallet fallback; PWA
/// requires a paired brain (no local wallet on web).
Future<ResolvedNode> bootResolvedNode() {
  final target = kIsWeb ? NodeTarget.pwa : NodeTarget.native;

  final resolver = NodeResolver.withDefaults(
    target: target,
    identityFactory: () async => identity_adapter.buildIdentityStore(),
    sttFactory: () async => const BrainBackedSttProvider(),
    // Conditional import: native gets the FFI factory, web gets null.
    ffiWalletFactory: buildFfiWalletFactory(),
    // Kernel handle is optional and target-specific. The shell currently
    // routes kernel ops through the brain; an FFI / WASM handle would
    // plug in here.
    kernelFactory: null,
  );

  return resolver.resolve();
}

```
