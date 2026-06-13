---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/bundle_verifier.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.014375+00:00
---

# platforms/flutter/semantos_core/lib/src/bundle_verifier.dart

```dart
import 'extension_bundle.dart';

/// Result of verifying an [ExtensionBundle].
class VerificationResult {
  /// True when the bundle's signature is structurally + cryptographically
  /// valid AND the verifier trusts the signer.
  final bool valid;

  /// Human-readable explanation. Surfaced to the operator in install
  /// confirmations on success ("signed by Author <pubkey-prefix>") and
  /// in install errors on failure.
  final String reason;

  /// True when the bundle had no signature envelope at all (vs.
  /// `signature.scheme == "none"` which is explicit). Useful for the
  /// operator-facing distinction "no signature provided" vs "signed
  /// claim of no signature".
  final bool wasUnsigned;

  const VerificationResult({
    required this.valid,
    required this.reason,
    this.wasUnsigned = false,
  });

  const VerificationResult.ok(String reason)
      : valid = true,
        reason = reason,
        wasUnsigned = false;

  const VerificationResult.rejected(String reason)
      : valid = false,
        reason = reason,
        wasUnsigned = false;

  const VerificationResult.unsigned(String reason)
      : valid = false,
        reason = reason,
        wasUnsigned = true;
}

/// Verifies the integrity + authorship of an [ExtensionBundle].
///
/// Implementations:
///   - [DevModeBundleVerifier] — accepts everything; for local dev only.
///   - [RequireSignatureBundleVerifier] — rejects unsigned bundles but
///     accepts any well-formed brc42 signature without checking it
///     cryptographically. A stepping stone before the full BRC-42
///     verifier lands; useful for testing the install flow without
///     needing real keys.
///   - Brc42BundleVerifier (planned) — full BRC-42 signature verification
///     against an operator-managed trust list of signer pubkeys.
///
/// The shell picks a verifier at boot via [NodeResolver] (or equivalent
/// app wiring) and threads it into the [ManifestProvisioner]. Different
/// targets can use different verifiers (dev native vs production PWA).
abstract class BundleVerifier {
  Future<VerificationResult> verify(ExtensionBundle bundle);
}

/// Accept-everything verifier. **Never use in production.**
///
/// Useful for the field shell's first-boot bring-up where the operator
/// is loading compile-bundled assets they trust by virtue of trusting
/// the app binary itself. Marked clearly so production-config audits
/// flag any use of it.
class DevModeBundleVerifier implements BundleVerifier {
  const DevModeBundleVerifier();

  @override
  Future<VerificationResult> verify(ExtensionBundle bundle) async {
    if (bundle.signature == null) {
      return const VerificationResult.ok(
        'dev-mode: accepting unsigned bundle (PRODUCTION USE FORBIDDEN)',
      );
    }
    if (bundle.signature!.isExplicitlyUnsigned) {
      return const VerificationResult.ok(
        'dev-mode: accepting bundle with scheme="none" (PRODUCTION USE FORBIDDEN)',
      );
    }
    return VerificationResult.ok(
      'dev-mode: accepting bundle signed under scheme="${bundle.signature!.scheme}" '
      'without cryptographic verification (PRODUCTION USE FORBIDDEN)',
    );
  }
}

/// Structure-check verifier — rejects unsigned bundles and bundles with
/// missing signature fields, but does NOT cryptographically verify the
/// signature. Useful as an interim while the BRC-42 verifier is being
/// implemented; lets the install flow exercise its error paths without
/// requiring real keys.
///
/// Production replacement: [Brc42BundleVerifier] (planned).
class RequireSignatureBundleVerifier implements BundleVerifier {
  const RequireSignatureBundleVerifier();

  @override
  Future<VerificationResult> verify(ExtensionBundle bundle) async {
    final sig = bundle.signature;
    if (sig == null) {
      return const VerificationResult.unsigned(
        'bundle is unsigned (no signature envelope)',
      );
    }
    if (sig.isExplicitlyUnsigned) {
      return const VerificationResult.unsigned(
        'bundle declares scheme="none" (explicitly unsigned)',
      );
    }
    if (sig.scheme != 'brc42-ecdsa-sha256') {
      return VerificationResult.rejected(
        'unsupported signature scheme "${sig.scheme}" '
        '(this client supports "brc42-ecdsa-sha256")',
      );
    }
    if (sig.signerPubkey == null || sig.signerPubkey!.length != 66) {
      return const VerificationResult.rejected(
        'signature missing or invalid signerPubkey (need 66-hex compressed pubkey)',
      );
    }
    if (sig.signatureBytes == null || sig.signatureBytes!.isEmpty) {
      return const VerificationResult.rejected(
        'signature missing signatureBytes',
      );
    }
    return VerificationResult.ok(
      'signature structurally valid '
      '(scheme=${sig.scheme}, signer=${sig.signerPubkey!.substring(0, 12)}…) '
      '— CRYPTOGRAPHIC VERIFICATION NOT YET IMPLEMENTED',
    );
  }
}

```
