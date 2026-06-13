---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/src/manifest_loader.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.813541+00:00
---

# archive/packages-jam_experience/lib/src/manifest_loader.dart

```dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:semantos_core/semantos_core.dart';

/// Loads the bundled jambox extension manifest from the package's
/// asset bundle.
///
/// Mirrors [OddjobzManifestLoader] in `oddjobz_experience`. Two entry
/// points:
///   - [load]              — returns the raw [ExtensionManifest].
///   - [provisionFromAsset] — runs through the shell's
///                            [ManifestProvisioner] for uniform
///                            verification policy.
class JamManifestLoader {
  static const String _manifestAssetPath =
      'packages/jam_experience/assets/manifest.json';

  static const String _bundleAssetPath =
      'packages/jam_experience/assets/bundle.json';

  /// Asset key for the signed bundle envelope.
  static String get bundleAssetPath => _bundleAssetPath;

  /// Read the raw manifest asset and parse it.
  static Future<ExtensionManifest> load() async {
    final raw = await rootBundle.loadString(_manifestAssetPath);
    return ExtensionManifest.fromJsonString(raw);
  }

  /// Read the bundle envelope and run it through [provisioner].
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
