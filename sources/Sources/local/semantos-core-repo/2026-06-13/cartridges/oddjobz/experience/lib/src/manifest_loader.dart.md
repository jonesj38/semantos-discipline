---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/manifest_loader.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.459896+00:00
---

# cartridges/oddjobz/experience/lib/src/manifest_loader.dart

```dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:semantos_core/semantos_core.dart';

/// Loads the bundled oddjobz extension manifest from the package's
/// asset bundle.
///
/// Two entry points:
///   - [load]              — returns the raw [ExtensionManifest]. Kept
///                           for back-compat with consumers wired before
///                           the bundle format landed.
///   - [provisionFromAsset] — returns a [ProvisionedExtension] (manifest
///                           plus verification evidence) via the
///                           [ManifestProvisioner] pathway, so the
///                           install flow can stay uniform whether the
///                           bundle came from a compile-time asset or a
///                           remote URL.
///
/// Until brain-fetched dynamic install lands, [provisionFromAsset] is
/// how compile-bundled extensions surface their config to the shell's
/// [GrammarRegistry].
class OddjobzManifestLoader {
  static const String _manifestAssetPath =
      'packages/oddjobz_experience/assets/manifest.json';

  static const String _bundleAssetPath =
      'packages/oddjobz_experience/assets/bundle.json';

  /// Asset key for the signed bundle envelope. Exposed for shells that
  /// want to feed the path into their own provisioner pipeline.
  static String get bundleAssetPath => _bundleAssetPath;

  /// Read the raw manifest asset and parse it.
  static Future<ExtensionManifest> load() async {
    final raw = await rootBundle.loadString(_manifestAssetPath);
    return ExtensionManifest.fromJsonString(raw);
  }

  /// Read the bundle envelope, run it through [provisioner], return the
  /// verified [ProvisionedExtension]. The shell threads its boot-time
  /// verifier into the provisioner so dev / production policies apply
  /// uniformly across URL installs and compile-bundled extensions.
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
