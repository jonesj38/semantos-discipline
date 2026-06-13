---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-apps/jam-room-mobile/lib/src/pairing/claim_request.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.830929+00:00
---

# archive/apps-world-apps/jam-room-mobile/lib/src/pairing/claim_request.dart

```dart
// D-O5m — Build the JSON request body the device POSTs to the brain
// at `/api/v1/device-pair`.
//
// Port of `buildAcceptRequestBody` in
// `extensions/oddjobz/src/device-pair-client.ts`. The brain-side
// acceptor (runtime/semantos-brain/src/site_server.zig + device_pair.zig) parses
// this body, re-derives the child pub via the symmetric BRC-42 path
// (operator_root_priv * device_pub), and asserts equality. On match
// the brain registers the child cert in the identity DAG with the
// payload's capability allowlist (spec v0.5 §4.4 isolation).

import 'dart:convert';

import 'brc42_derive.dart';

/// JSON body the device POSTs to `<brain_pair_endpoint>`.
class ClaimRequest {
  /// Original base64url token (with the `?token=` URL prefix stripped
  /// if present) — the brain re-decodes + re-verifies the operator
  /// signature on receipt.
  final String token;

  /// 66 hex chars (compressed SEC1) — the BRC-42 child pub the brain
  /// will recompute via its symmetric path and assert equality
  /// against.
  final String derivationPubkey;

  /// 66 hex chars (compressed SEC1) — the device's identity pub. The
  /// brain stores this as the cert's audit-surface identifier.
  final String derivationProof;

  const ClaimRequest({
    required this.token,
    required this.derivationPubkey,
    required this.derivationProof,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'derivation_pubkey': derivationPubkey,
        'derivation_proof': derivationProof,
      };

  String toJsonString() => json.encode(toJson());
}

/// Strip a URL wrapper if present, returning the bare base64url token.
/// Smoke-test pass #1, fix #16 — see decode_token.dart for the matching
/// upgrade.  Same logic, kept here as a sibling to avoid a cross-file
/// dependency on the private helper.
String _stripPairUrlScheme(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  try {
    final uri = Uri.parse(s);
    if (uri.queryParameters.containsKey('token')) {
      return uri.queryParameters['token']!;
    }
  } catch (_) {}
  const marker = '?token=';
  final idx = s.indexOf(marker);
  if (idx >= 0) {
    var tail = s.substring(idx + marker.length);
    final amp = tail.indexOf('&');
    if (amp >= 0) tail = tail.substring(0, amp);
    return tail;
  }
  return s;
}

/// Build the claim_child request body from the original token + the
/// derived child key material.
ClaimRequest buildClaimRequest({
  required String tokenBase64Url,
  required DerivedChild derived,
}) {
  return ClaimRequest(
    token: _stripPairUrlScheme(tokenBase64Url),
    derivationPubkey: derived.childPubKeyHex,
    derivationProof: derived.devicePubKeyHex,
  );
}

```
