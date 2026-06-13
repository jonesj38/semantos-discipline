---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/dispatch/signed_mint.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.117811+00:00
---

# apps/semantos/lib/src/dispatch/signed_mint.dart

```dart
// C7-B Option A — operator-signed mint helper (PWA side).
//
// Ties the canonicaliser (payload_canonical.dart) to the ECDSA signer
// (identity/cell_signer.dart) so a mint payload can be cryptographically
// authorised by the operator's hat key. The brain (#828) re-derives the
// same canonical bytes and verifies the signature against the signer cert
// before persisting — so the operator, not the brain, authorises the cell.
//
// Contract (must match runtime/semantos-brain attachments_upload_http.zig
// verifyPayloadSignature): sign `sha256(canonicaliseCellPayload(payload))`,
// 64-byte (r‖s) compact, no domain prefix.

import 'dart:typed_data';

import '../identity/cell_signer.dart' show signCellPayload;
import '../wallet/wallet_key_service.dart' show WalletKeyService;
import 'intent_dispatcher.dart' show MintSigner;
import 'payload_canonical.dart';

/// Sign [payload] with the operator's [operatorPriv] (32-byte secp256k1).
/// Returns the 64-byte (r‖s) signature as 128 lowercase hex chars, computed
/// over `sha256(canonicaliseCellPayload(payload))`. Pair with the operator
/// cert id when POSTing via `BrainHttpClient.mintCellSigned`.
String signMintPayloadHex(Object? payload, Uint8List operatorPriv) {
  final canonical = canonicaliseCellPayload(payload);
  final sig = signCellPayload(canonical, operatorPriv);
  return bytesToHex(sig);
}

/// Lowercase hex of [bytes].
String bytesToHex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// Build an [IntentDispatcher] [MintSigner] backed by [wks]'s operator
/// (tier-0) key. The returned signer canonicalises the payload, signs it
/// with the operator key, and pairs the signature with the operator cert
/// id — or yields null (⇒ unsigned mint) when no identity is loaded. Wire
/// this into `buildIntentDispatcher(signer: walletMintSigner(wks))` so the
/// helm's DO→Release routes through the sovereign signed path (#828).
MintSigner walletMintSigner(WalletKeyService wks) {
  return (payload) {
    final certId = wks.certIdHex;
    if (certId == null) return null;
    final sig = wks.signWithOperatorKey(canonicaliseCellPayload(payload));
    if (sig == null) return null;
    return (signatureHex: bytesToHex(sig), signerCertIdHex: certId);
  };
}

```
