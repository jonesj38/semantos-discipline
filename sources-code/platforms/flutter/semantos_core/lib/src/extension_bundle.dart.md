---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/extension_bundle.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.017839+00:00
---

# platforms/flutter/semantos_core/lib/src/extension_bundle.dart

```dart
import 'dart:convert';

import 'extension_manifest.dart';

/// Portable bundle format for distributing extension grammars.
///
/// An [ExtensionBundle] is the on-wire artifact an extension author
/// publishes. The substrate-portability promise depends on this format
/// being:
///
///   1. **Self-describing** — schemaVersion + canonical structure so
///      bundles from any author parse in any shell without prior setup
///   2. **Signed** — signature metadata that an operator's shell can
///      verify against the author's BRC-42 identity
///   3. **Address-agnostic** — fetchable from any URL, file, or asset;
///      no Semantos marketplace dependency
///
/// Today the bundle envelope wraps a single [ExtensionManifest] (which
/// itself embeds the grammar spec). Future iterations will inline cell
/// type definitions, intake prompts, FSMs, and ratification patterns
/// as base64-encoded payloads alongside the manifest — keeping the
/// envelope as one fetchable JSON file.
///
/// Wire shape:
/// ```json
/// {
///   "schemaVersion": 1,
///   "manifest": { ...ExtensionManifest... },
///   "signature": {
///     "scheme": "brc42-ecdsa-sha256",
///     "signerPubkey": "<66-hex>",
///     "signatureBytes": "<hex>",
///     "signedAt": 1234567890
///   },
///   "issuedBy": "https://author.example/odd-job-todd",
///   "publishedAt": 1234567890
/// }
/// ```
class ExtensionBundle {
  /// Bundle schema version. Bumped when the envelope shape changes.
  /// Verifiers MUST reject bundles with a schemaVersion they don't
  /// understand — defensive default against future format drift.
  final int schemaVersion;

  /// The extension manifest the bundle delivers.
  final ExtensionManifest manifest;

  /// Signature envelope. Null permitted for development bundles; the
  /// shell's [BundleVerifier] decides whether to accept unsigned bundles
  /// (typically only in dev/test mode).
  final BundleSignature? signature;

  /// Identifier of the issuing party. URL preferred, plain string
  /// accepted. Surfaced to the operator in install confirmations.
  final String? issuedBy;

  /// Unix-second timestamp the bundle was published. Distinct from
  /// `signature.signedAt` — a bundle may be re-published with the same
  /// signature when no content changed.
  final int? publishedAt;

  const ExtensionBundle({
    required this.schemaVersion,
    required this.manifest,
    this.signature,
    this.issuedBy,
    this.publishedAt,
  });

  /// Parse a [Map] (typically from `jsonDecode`) into a bundle.
  /// Throws [FormatException] when the envelope shape is invalid; lets
  /// nested [ExtensionManifest.fromJson] throw on manifest errors.
  factory ExtensionBundle.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version is! int) {
      throw const FormatException(
        'ExtensionBundle: missing or non-int "schemaVersion"',
      );
    }
    if (version != 1) {
      throw FormatException(
        'ExtensionBundle: unsupported schemaVersion $version '
        '(this client supports schemaVersion 1)',
      );
    }
    final manifestJson = json['manifest'];
    if (manifestJson is! Map<String, dynamic>) {
      throw const FormatException(
        'ExtensionBundle: missing or non-object "manifest"',
      );
    }
    final manifest = ExtensionManifest.fromJson(manifestJson);

    BundleSignature? signature;
    final sigJson = json['signature'];
    if (sigJson is Map<String, dynamic>) {
      signature = BundleSignature.fromJson(sigJson);
    }

    return ExtensionBundle(
      schemaVersion: version,
      manifest: manifest,
      signature: signature,
      issuedBy: json['issuedBy'] as String?,
      publishedAt: json['publishedAt'] as int?,
    );
  }

  /// Parse a JSON string. Convenience over [fromJson] for callers that
  /// just fetched bytes from a URL.
  factory ExtensionBundle.fromJsonString(String s) {
    final decoded = jsonDecode(s);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ExtensionBundle: JSON root must be an object');
    }
    return ExtensionBundle.fromJson(decoded);
  }

  /// Re-serialise the bundle to a canonical JSON string for hashing.
  /// Field order is fixed (schemaVersion → manifest → signature →
  /// issuedBy → publishedAt) and the manifest is re-encoded via its
  /// own canonical form. The signature itself is NOT part of the
  /// canonical body — verifiers hash the body without the signature
  /// envelope and check the signature against that digest.
  String canonicalBody() {
    final body = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'manifest': _canonicalManifest(manifest),
      if (issuedBy != null) 'issuedBy': issuedBy,
      if (publishedAt != null) 'publishedAt': publishedAt,
    };
    return jsonEncode(body);
  }

  /// Minimal canonical re-encoding of the manifest. Mirrors the field
  /// order in [ExtensionManifest.fromJson] for stable serialisation.
  static Map<String, dynamic> _canonicalManifest(ExtensionManifest m) {
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

/// Signature envelope for an [ExtensionBundle].
///
/// Production scheme: `brc42-ecdsa-sha256` — ECDSA over SHA-256 of the
/// bundle's [ExtensionBundle.canonicalBody] using the author's BRC-42
/// identity public key. Other schemes can land later (e.g. multisig).
class BundleSignature {
  /// Signature scheme identifier. Verifiers route on this string.
  /// Initial: `"brc42-ecdsa-sha256"`. Dev/test bundles may use
  /// `"none"` to mark explicitly unsigned content.
  final String scheme;

  /// Author's compressed pubkey (66 lowercase hex chars for secp256k1).
  /// Required for the brc42-ecdsa-sha256 scheme; ignored for `"none"`.
  final String? signerPubkey;

  /// DER-encoded ECDSA signature, hex. Required for the brc42 scheme.
  final String? signatureBytes;

  /// Unix-second timestamp the bundle was signed.
  final int? signedAt;

  const BundleSignature({
    required this.scheme,
    this.signerPubkey,
    this.signatureBytes,
    this.signedAt,
  });

  factory BundleSignature.fromJson(Map<String, dynamic> json) {
    final scheme = json['scheme'];
    if (scheme is! String || scheme.isEmpty) {
      throw const FormatException(
        'BundleSignature: missing or invalid "scheme"',
      );
    }
    return BundleSignature(
      scheme: scheme,
      signerPubkey: json['signerPubkey'] as String?,
      signatureBytes: json['signatureBytes'] as String?,
      signedAt: json['signedAt'] as int?,
    );
  }

  /// True when the signature is the explicit "none" sentinel — the
  /// bundle is published without signature metadata, and the verifier
  /// must decide whether to accept that (typically only in dev mode).
  bool get isExplicitlyUnsigned => scheme == 'none';
}

```
