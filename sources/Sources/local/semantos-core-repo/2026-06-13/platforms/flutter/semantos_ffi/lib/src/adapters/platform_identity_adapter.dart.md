---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/lib/src/adapters/platform_identity_adapter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.008992+00:00
---

# platforms/flutter/semantos_ffi/lib/src/adapters/platform_identity_adapter.dart

```dart
// PlatformIdentityAdapter — Secure key and certificate storage for Flutter.
//
// Uses flutter_secure_storage which maps to:
// - iOS: Keychain Services (with Secure Enclave if available)
// - Android: Keystore (with StrongBox if available)
// - macOS: Keychain Services
//
// Certificates are stored as JSON strings, keys by certificate ID.

import 'dart:convert' show json, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure identity adapter backed by platform keystore.
class PlatformIdentityAdapter {
  final FlutterSecureStorage _storage;

  /// Key prefix to namespace identity data in the keystore.
  static const String _prefix = 'semantos_identity_';

  PlatformIdentityAdapter({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  /// Resolve a certificate by its ID. Returns the certificate JSON bytes
  /// or null if not found.
  Future<Uint8List?> resolve(String certId) async {
    final value = await _storage.read(key: '$_prefix$certId');
    if (value == null) return null;
    return Uint8List.fromList(utf8.encode(value));
  }

  /// Store a certificate by its ID.
  Future<void> store(String certId, Uint8List certJson) async {
    final value = utf8.decode(certJson);
    await _storage.write(key: '$_prefix$certId', value: value);
  }

  /// Derive a new certificate from a parent certificate for a resource.
  /// This is a client-side derivation — the actual cryptographic derivation
  /// happens in the kernel via the callback. This method stores the result.
  Future<Uint8List> derive(
    Uint8List parentCertJson,
    String resourceId,
    int domainFlag,
  ) async {
    // Parse parent cert to extract ID for storage key generation.
    final parentJson = json.decode(utf8.decode(parentCertJson));
    final parentId = parentJson['id'] as String? ?? 'unknown';
    final derivedId = '${parentId}_${resourceId}_$domainFlag';

    // Create derived certificate JSON.
    final derived = {
      'id': derivedId,
      'parent_id': parentId,
      'resource_id': resourceId,
      'domain_flag': domainFlag,
      'derived_at': DateTime.now().toIso8601String(),
    };
    final derivedBytes = Uint8List.fromList(utf8.encode(json.encode(derived)));

    // Persist in secure storage.
    await store(derivedId, derivedBytes);

    return derivedBytes;
  }

  /// Delete a certificate from the keystore.
  Future<void> delete(String certId) async {
    await _storage.delete(key: '$_prefix$certId');
  }

  /// List all stored certificate IDs.
  Future<List<String>> listCertificates() async {
    final all = await _storage.readAll();
    return all.keys
        .where((k) => k.startsWith(_prefix))
        .map((k) => k.substring(_prefix.length))
        .toList();
  }
}

```
