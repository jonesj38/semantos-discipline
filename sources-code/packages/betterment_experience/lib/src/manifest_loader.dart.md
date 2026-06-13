---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/betterment_experience/lib/src/manifest_loader.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.448060+00:00
---

# packages/betterment_experience/lib/src/manifest_loader.dart

```dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:semantos_core/semantos_core.dart';

/// Loads the bundled betterment extension manifest from the package's
/// asset bundle. Mirrors [OddjobzManifestLoader].
///
/// Two entry points:
///   - [load]              — returns the raw [ExtensionManifest].
///   - [provisionFromAsset] — returns a [ProvisionedExtension] via the
///                            [ManifestProvisioner] pathway, so the
///                            install flow stays uniform whether the
///                            bundle came from a compile-time asset or
///                            a remote URL.
///
/// RENAME (2026-05-29): class previously named SelfManifestLoader and
/// asset paths under packages/self_experience/. Renamed and moved as
/// part of the self_experience → betterment_experience rename.
class BettermentManifestLoader {
  static const String _manifestAssetPath =
      'packages/betterment_experience/assets/manifest.json';

  static const String _bundleAssetPath =
      'packages/betterment_experience/assets/bundle.json';

  /// Asset key for the signed bundle envelope.
  static String get bundleAssetPath => _bundleAssetPath;

  /// Read the raw manifest asset and parse it.
  static Future<ExtensionManifest> load() async {
    final raw = await rootBundle.loadString(_manifestAssetPath);
    return ExtensionManifest.fromJsonString(raw);
  }

  /// Read the bundle envelope, run it through [provisioner], return the
  /// verified [ProvisionedExtension].
  static Future<ProvisionedExtension> provisionFromAsset(
    ManifestProvisioner provisioner,
  ) async {
    final raw = await rootBundle.loadString(_bundleAssetPath);
    return provisioner.loadFromJsonString(
      raw,
      source: 'asset:$_bundleAssetPath',
    );
  }
}

```
