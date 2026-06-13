---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-apps/jam-room-mobile/lib/src/identity/platform_secure_signing_key_adapter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.832968+00:00
---

# archive/apps-world-apps/jam-room-mobile/lib/src/identity/platform_secure_signing_key_adapter.dart

```dart
// D-O5m.followup-2 — MethodChannel-backed SecureSigningKey adapter.
//
// Wraps the iOS Swift / Android Kotlin native implementations behind
// the SecureSigningKeyAdapter contract.  Lives in its own file so
// the import surface of `secure_signing_key.dart` stays free of
// `package:flutter/services.dart` — keeps the unit-test suite
// runnable under plain `dart test` without a Flutter SDK gate.
//
// The Flutter app wires this adapter into the helm at app boot in
// `main.dart` via:
//
//   final adapter = PlatformSecureSigningKeyAdapter();
//   final pairingService = PairingService(
//     ...,
//     secureSigningKeyAdapter: adapter,
//   );
//
// On builds that don't ship the native handler (e.g. early-stage
// Android emulator without the security-crypto / bouncycastle
// libraries linked), the channel returns `MissingPluginException`
// or `UNSUPPORTED`; both surface as `SecureSigningKeyUnsupported`
// so the caller can fall through to the legacy raw-priv path.

import 'package:flutter/services.dart';

import 'secure_signing_key.dart';

/// MethodChannel name shared with the iOS `FlutterMethodChannel` in
/// `SecureSigningKey.swift` and the Android `MethodChannel` in
/// `SecureSigningKey.kt`.  Keep these three in lock-step.
const String kSecureSigningKeyChannelName =
    'semantos.oddjobz/secure_signing_key';

/// Production adapter — dispatches to native iOS Keychain or
/// Android EncryptedSharedPreferences.
class PlatformSecureSigningKeyAdapter implements SecureSigningKeyAdapter {
  final MethodChannel _channel;

  PlatformSecureSigningKeyAdapter([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel(kSecureSigningKeyChannelName);

  @override
  Future<SecureKeyMaterial> generateNew({required String label}) async {
    try {
      final r = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'generate',
        {'label': label},
      );
      if (r == null) {
        throw const SecureSigningKeyError(
            'GENERATE_FAILED', 'native generate returned null');
      }
      final handle = r['keyHandle'] as String?;
      final pub = r['publicKey'] as Uint8List?;
      if (handle == null || pub == null) {
        throw const SecureSigningKeyError('GENERATE_FAILED',
            'native generate response missing keyHandle/publicKey');
      }
      return SecureKeyMaterial(
        keyHandle: handle,
        publicKey: pub,
        generatedAt: DateTime.now(),
      );
    } on PlatformException catch (e) {
      throw _mapNativeError(e);
    } on MissingPluginException catch (e) {
      throw SecureSigningKeyUnsupported(
          'secure-signing-key channel not registered: ${e.message ?? "<no message>"}');
    }
  }

  @override
  Future<Uint8List> sign({
    required String keyHandle,
    required Uint8List message,
  }) async {
    try {
      final r = await _channel.invokeMethod<Uint8List>(
        'sign',
        {'keyHandle': keyHandle, 'message': message},
      );
      if (r == null) {
        throw const SecureSigningKeyError(
            'SIGN_FAILED', 'native sign returned null');
      }
      return r;
    } on PlatformException catch (e) {
      throw _mapNativeError(e);
    } on MissingPluginException catch (e) {
      throw SecureSigningKeyUnsupported(
          'secure-signing-key channel not registered: ${e.message ?? "<no message>"}');
    }
  }

  @override
  Future<void> delete({required String keyHandle}) async {
    try {
      await _channel.invokeMethod<void>('delete', {'keyHandle': keyHandle});
    } on PlatformException catch (e) {
      // KEY_NOT_FOUND is treated as success at the adapter level —
      // the postcondition (no entry exists at this handle) holds.
      if (e.code == 'KEY_NOT_FOUND') return;
      throw _mapNativeError(e);
    } on MissingPluginException catch (e) {
      throw SecureSigningKeyUnsupported(
          'secure-signing-key channel not registered: ${e.message ?? "<no message>"}');
    }
  }

  @override
  Future<bool> exists({required String keyHandle}) async {
    try {
      final r = await _channel.invokeMethod<bool>('exists',
          {'keyHandle': keyHandle});
      return r ?? false;
    } on PlatformException catch (e) {
      throw _mapNativeError(e);
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Translate a native-channel `PlatformException` into a typed
  /// adapter exception so the helm UI can pattern-match.
  SecureSigningKeyException _mapNativeError(PlatformException e) {
    switch (e.code) {
      case 'KEY_NOT_FOUND':
        return SecureSigningKeyNotFound(e.message ?? 'key not found');
      case 'UNSUPPORTED':
        return SecureSigningKeyUnsupported(
            e.message ?? 'native secure-signing-key not supported on this build');
      case 'GENERATE_FAILED':
      case 'SIGN_FAILED':
      case 'DELETE_FAILED':
      case 'BAD_ARGS':
        return SecureSigningKeyError(e.code, e.message ?? e.code);
      default:
        return SecureSigningKeyError(
            e.code, e.message ?? 'unknown native error');
    }
  }
}

```
