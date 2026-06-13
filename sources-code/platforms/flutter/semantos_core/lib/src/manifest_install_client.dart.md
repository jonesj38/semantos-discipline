---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/manifest_install_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.016983+00:00
---

# platforms/flutter/semantos_core/lib/src/manifest_install_client.dart

```dart
import 'dart:convert';

import 'extension_manifest.dart';
import 'manifest_provisioner.dart';

/// Client for the brain's `manifest.install` / `manifest.list` /
/// `manifest.uninstall` JSON-RPC methods.
///
/// Lets a field shell (PWA or native) push a verified manifest to the
/// brain so other paired shells discover it. The brain stores the
/// manifest in an in-memory registry (LMDB persistence is the next
/// iteration); calling `list()` at boot lets a fresh shell hydrate its
/// own [GrammarRegistry] from the brain's view of installed extensions.
///
/// Transport-agnostic: callers provide the JSON-RPC sender. Same shape
/// as [VerbDispatchClient] and [CellQueryClient].
abstract class ManifestInstallClient {
  /// Push a verified manifest to the brain.
  Future<ManifestInstallResult> install(ProvisionedExtension provisioned);

  /// Fetch every manifest the brain knows about.
  Future<List<InstalledManifest>> list();

  /// Remove a previously-installed manifest from the brain.
  Future<void> uninstall(String extensionId);
}

/// Result of [ManifestInstallClient.install].
class ManifestInstallResult {
  final bool installed;
  final String extensionId;
  const ManifestInstallResult({
    required this.installed,
    required this.extensionId,
  });
}

/// One installed-manifest record returned by [ManifestInstallClient.list].
/// Mirrors the brain-side `renderEntry` JSON shape in manifest_registry.zig.
class InstalledManifest {
  final String extensionId;
  final String version;
  final String source;
  final int installedAt;
  final String? signerPubkey;
  final ExtensionManifest manifest;

  const InstalledManifest({
    required this.extensionId,
    required this.version,
    required this.source,
    required this.installedAt,
    required this.manifest,
    this.signerPubkey,
  });

  factory InstalledManifest.fromJson(Map<String, dynamic> json) {
    final m = json['manifest'];
    if (m is! Map<String, dynamic>) {
      throw const FormatException('InstalledManifest: missing manifest object');
    }
    return InstalledManifest(
      extensionId: (json['extensionId'] as String?) ?? '',
      version: (json['version'] as String?) ?? '',
      source: (json['source'] as String?) ?? '',
      installedAt: (json['installedAt'] as int?) ?? 0,
      signerPubkey: json['signerPubkey'] as String?,
      manifest: ExtensionManifest.fromJson(m),
    );
  }
}

/// JSON-RPC envelope helpers — `install` / `list` / `uninstall` param
/// builders and response decoders. Implementations consume these to
/// drive their transport.
class ManifestInstallRpc {
  /// Build params for `manifest.install` from a provisioned extension.
  /// The brain stores the manifest verbatim alongside source + signer
  /// metadata; the verifier evidence stays client-side.
  static Map<String, dynamic> installParams(ProvisionedExtension p) {
    return {
      'extensionId': p.manifest.id,
      'version': p.manifest.version,
      'source': p.source,
      if (p.bundle.signature?.signerPubkey != null)
        'signerPubkey': p.bundle.signature!.signerPubkey,
      // The brain stores the manifest as a JSON object — we pass it via
      // the manifest's canonical JSON re-encoding. Reusing the bundle's
      // canonical body would include extra envelope fields, so we
      // serialise the manifest slice directly.
      'manifest': _manifestToJsonMap(p.manifest),
    };
  }

  /// Build params for `manifest.uninstall`.
  static Map<String, dynamic> uninstallParams(String extensionId) {
    return {'extensionId': extensionId};
  }

  /// Decode the result of `manifest.install`.
  static ManifestInstallResult decodeInstallResult(String body) {
    final result = _resultOrThrow(body);
    return ManifestInstallResult(
      installed: (result['installed'] as bool?) ?? false,
      extensionId: (result['extensionId'] as String?) ?? '',
    );
  }

  /// Decode the result of `manifest.list`.
  static List<InstalledManifest> decodeListResult(String body) {
    final result = _resultOrThrow(body);
    final manifests = result['manifests'];
    if (manifests is! List) {
      return const [];
    }
    return manifests
        .whereType<Map<String, dynamic>>()
        .map(InstalledManifest.fromJson)
        .toList(growable: false);
  }

  static Map<String, dynamic> _resultOrThrow(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('manifest.* response not a JSON object');
    }
    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      throw FormatException(
        'manifest.* error ${error['code']}: ${error['message']}',
      );
    }
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) {
      throw const FormatException('manifest.* result missing or not an object');
    }
    return result;
  }

  /// Re-encode a [ExtensionManifest] back into the JSON shape the brain
  /// expects. Mirrors [ExtensionBundle._canonicalManifest] in
  /// `extension_bundle.dart` — kept here so transports that build the
  /// install request envelope don't need to pull in the bundle module.
  static Map<String, dynamic> _manifestToJsonMap(ExtensionManifest m) {
    return <String, dynamic>{
      'id': m.id,
      'name': m.name,
      'version': m.version,
      'domainFlag': m.domainFlag,
      if (m.requiredCapabilities.isNotEmpty)
        'requiredCapabilities': m.requiredCapabilities,
      if (m.hatRoles.isNotEmpty) 'hatRoles': m.hatRoles,
      if (m.metadata.isNotEmpty) 'metadata': m.metadata,
      'grammar': {
        'extensionId': m.grammar.extensionId,
        'lexicon': {
          'name': m.grammar.lexicon.name,
          'categories': m.grammar.lexicon.categories,
        },
        'defaultTaxonomyWhat': m.grammar.defaultTaxonomyWhat,
        'objectTypes': m.grammar.objectTypes
            .map((o) => {'name': o.name, 'description': o.description})
            .toList(),
        'actions': m.grammar.actions
            .map((a) => {
                  'name': a.name,
                  'category': a.category,
                  'authoredBy': a.authoredBy,
                  'description': a.description,
                })
            .toList(),
        'trustClass': m.grammar.trustClass,
        'proofRequirement': m.grammar.proofRequirement,
      },
    };
  }
}

```
