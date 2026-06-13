---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-tessera_experience/lib/src/manifest_loader.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.829065+00:00
---

# archive/packages-tessera_experience/lib/src/manifest_loader.dart

```dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:semantos_core/semantos_core.dart';

/// Loads the bundled tessera extension manifest from the package's
/// asset bundle.
///
/// Mirrors `OddjobzManifestLoader`. Two entry points:
///   - [load]               — returns the raw [ExtensionManifest].
///   - [provisionFromAsset] — returns a [ProvisionedExtension]
///                            (manifest + verification evidence) via
///                            the [ManifestProvisioner] pathway, so
///                            the install flow stays uniform whether
///                            the bundle came from a compile-time
///                            asset or a remote URL.
///
/// Note: this is the Flutter-shell manifest format (id / name /
/// version / domainFlag / grammar / hatRoles), distinct from the
/// brain-side Phase 36A manifest at `extensions/tessera/manifest.json`.
/// The two formats are unreconciled (D-Manifest-canonical, pending);
/// the shell asset uses domainFlag 0x000105 to avoid a runtime
/// collision with jambox's shell domainFlag 0x000104, while the
/// brain-side authoritative tessera page is 0x00010400 per V0.1.
class TesseraManifestLoader {
  static const String _manifestAssetPath =
      'packages/tessera_experience/assets/manifest.json';

  static const String _bundleAssetPath =
      'packages/tessera_experience/assets/bundle.json';

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
