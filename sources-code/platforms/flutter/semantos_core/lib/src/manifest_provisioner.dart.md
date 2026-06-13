---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/manifest_provisioner.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.013512+00:00
---

# platforms/flutter/semantos_core/lib/src/manifest_provisioner.dart

```dart
import 'dart:async';

import 'package:http/http.dart' as http;

import 'bundle_verifier.dart';
import 'extension_bundle.dart';
import 'extension_manifest.dart';

/// Provisioned extension — a verified manifest plus the verification
/// evidence the shell shows to the operator.
class ProvisionedExtension {
  final ExtensionManifest manifest;
  final ExtensionBundle bundle;
  final VerificationResult verification;

  /// Where the bundle was loaded from (URL, file path, or asset key).
  /// Persisted alongside the manifest so the operator can audit + the
  /// shell can re-fetch on update.
  final String source;

  const ProvisionedExtension({
    required this.manifest,
    required this.bundle,
    required this.verification,
    required this.source,
  });
}

/// Raised when provisioning fails. The shell surfaces the message to
/// the operator's install confirmation screen.
class ProvisioningException implements Exception {
  final String message;
  final String source;
  final Object? cause;

  const ProvisioningException(this.message, this.source, {this.cause});

  @override
  String toString() => 'ProvisioningException($source): $message';
}

/// Fetches extension bundles from URL, file, or asset and produces
/// verified [ExtensionManifest] instances.
///
/// The provisioner is the substrate-portability seam: the operator
/// installs a grammar from any URL (or any file or asset) and the
/// shell wires it into the [GrammarRegistry] without any Semantos-
/// marketplace dependency.
///
/// Today's wire shape: bundles are JSON envelopes (see
/// [ExtensionBundle]). Tomorrow they may be ZIP archives with embedded
/// cell-type definitions and FSMs; the [load*] entry points remain
/// stable across that evolution.
class ManifestProvisioner {
  final BundleVerifier verifier;
  final http.Client _httpClient;

  ManifestProvisioner({
    required this.verifier,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Fetch a bundle from [url], verify it, return the provisioned
  /// extension. The HTTP request follows redirects and accepts both
  /// `application/json` and `application/x-semantos-bundle+json`
  /// (latter reserved for future formats).
  Future<ProvisionedExtension> loadFromUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw ProvisioningException('invalid URL: $url', url);
    }
    final http.Response response;
    try {
      response = await _httpClient.get(uri, headers: {
        'Accept': 'application/json, application/x-semantos-bundle+json',
      });
    } catch (e) {
      throw ProvisioningException(
        'HTTP fetch failed: $e',
        url,
        cause: e,
      );
    }
    if (response.statusCode != 200) {
      throw ProvisioningException(
        'HTTP ${response.statusCode}: ${response.reasonPhrase ?? "no body"}',
        url,
      );
    }
    return _verifyAndPackage(response.body, url);
  }

  /// Parse a bundle from a JSON string already in hand (asset bundles
  /// loaded via `rootBundle.loadString`, file reads, paste-from-clipboard,
  /// etc.). Verification proceeds as for [loadFromUrl].
  Future<ProvisionedExtension> loadFromJsonString(
    String jsonStr, {
    required String source,
  }) async {
    return _verifyAndPackage(jsonStr, source);
  }

  /// Convenience: load + verify many bundles concurrently, returning
  /// only the ones that passed verification. Failures are reported
  /// via [onFailure] (defaults to throwing on the first error).
  Future<List<ProvisionedExtension>> loadAll(
    Iterable<Future<ProvisionedExtension> Function()> loaders, {
    void Function(Object error)? onFailure,
  }) async {
    final results = <ProvisionedExtension>[];
    for (final load in loaders) {
      try {
        results.add(await load());
      } catch (e) {
        if (onFailure != null) {
          onFailure(e);
        } else {
          rethrow;
        }
      }
    }
    return results;
  }

  Future<ProvisionedExtension> _verifyAndPackage(
    String body,
    String source,
  ) async {
    final ExtensionBundle bundle;
    try {
      bundle = ExtensionBundle.fromJsonString(body);
    } on FormatException catch (e) {
      throw ProvisioningException(
        'bundle parse failed: ${e.message}',
        source,
        cause: e,
      );
    } catch (e) {
      throw ProvisioningException(
        'bundle parse failed: $e',
        source,
        cause: e,
      );
    }

    final verification = await verifier.verify(bundle);
    if (!verification.valid) {
      throw ProvisioningException(
        'bundle verification rejected: ${verification.reason}',
        source,
      );
    }

    return ProvisionedExtension(
      manifest: bundle.manifest,
      bundle: bundle,
      verification: verification,
      source: source,
    );
  }

  /// Close underlying HTTP resources. Call when the shell shuts down.
  void close() {
    _httpClient.close();
  }
}

/// Helper that wraps a raw [ExtensionManifest] (loaded directly, no
/// bundle envelope) into a [ProvisionedExtension] with a synthetic
/// verification result. Useful for compile-bundled assets that ship
/// inside the app binary — the operator trusts the binary itself, so
/// the manifest doesn't need a separate signature.
///
/// Marks the result with `wasUnsigned: true` so the shell can surface
/// the distinction in audit logs (e.g. "installed via compile-time
/// bundling" vs "installed via signed URL").
ProvisionedExtension provisionFromCompileBundle({
  required ExtensionManifest manifest,
  required String source,
}) {
  return ProvisionedExtension(
    manifest: manifest,
    bundle: ExtensionBundle(
      schemaVersion: 1,
      manifest: manifest,
      signature: null,
      issuedBy: 'compile-time',
      publishedAt: null,
    ),
    verification: const VerificationResult.unsigned(
      'compile-time-bundled (trusted via app binary)',
    ),
    source: source,
  );
}


```
