---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/outbox/mesh_outbox_builder.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.862947+00:00
---

# archive/apps-semantos-monolith/lib/src/outbox/mesh_outbox_builder.dart

```dart
// D-O5m.followup-6 Phase 2 — OutboxEntry → SignedBundle builder.
//
// Reference: this brief.  When the outbox flushes via the mesh
// transport (instead of the legacy per-kind uploader path), each
// entry is wrapped as a SignedBundle and pushed through
// MeshTransport.send.  This file owns the entry → bundle conversion;
// the mesh_transport seam itself stays kind-agnostic.
//
// Three entry kinds → three payload_types:
//   • attachment_upload (cell_type = oddjobz.attachment.v1)
//       → payload_type = oddjobz.attachment.create; payload =
//         entry.payloadJson (the metadata JSON the brain dispatches
//         against; the blob continues to flow through the legacy
//         multipart endpoint until Phase 3).
//   • voice_extract (cell_type = oddjobz.voice_extract.v1)
//       → payload_type = oddjobz.voice-extract; payload =
//         entry.payloadJson (the {transcript, metadata} envelope).
//   • signed_cell (any other cell_type)
//       → payload_type = oddjobz.cell.create; payload =
//         entry.payloadJson (the cell-write JSON).
//
// The bundle's sender_cert_chain + signature are produced by the
// existing identity / cell-signer infrastructure (post-#316).  This
// module exposes a thin builder that takes the device's identity
// state + a single OutboxEntry and returns a signed SignedBundle ready
// to publish.

import 'dart:math';
import 'dart:typed_data';

import '../mesh/cert_ref.dart';
import '../mesh/mesh_transport.dart' show payloadTypeCellCreate;
import '../mesh/signature_metadata.dart';
import '../mesh/signed_bundle.dart';
import 'outbox_db.dart';

/// Identity state the bundle builder needs.  Threaded in from the
/// outbox layer so this module stays Flutter-SDK-free for tests.
class MeshIdentityContext {
  /// The device's leaf cert chain (leaf-first, root last).  The
  /// chain matches what the brain's cert store recognises.
  final List<CertRef> senderCertChain;

  /// 32-hex-char brain root cert id — the recipient address.  Bundles
  /// addressed to anything else are rejected on the brain side.
  final String brainRootCertId;

  /// 32-byte secp256k1 private key for the leaf cert.  The signer
  /// produces the SignedBundle's `signature` field by signing the
  /// canonical preimage.
  final Uint8List leafPrivateKey;

  const MeshIdentityContext({
    required this.senderCertChain,
    required this.brainRootCertId,
    required this.leafPrivateKey,
  });
}

/// Map an OutboxEntry to the wire payload_type.
///
/// W1.2 — the old `cell_type` TEXT column is gone.  All entries now
/// carry the full cell envelope in the `payload` BLOB.  The payload
/// type is always `payloadTypeCellCreate`; specialised routing
/// (attachment, voice-extract) is handled by the brain's dispatch layer
/// once it unpacks the envelope.
String payloadTypeForOutboxEntry(OutboxEntry entry) {
  return payloadTypeCellCreate;
}

/// Build a signed SignedBundle from an OutboxEntry.  The bundle's
/// `payload` is the entry's JSON — the brain decodes that into the
/// inner cell-write / attachment metadata / voice envelope per the
/// payload_type.
///
/// `nonceProvider` defaults to a 32-byte random hex; tests pin it for
/// deterministic round-trips.
SignedBundle buildBundleFromOutboxEntry({
  required OutboxEntry entry,
  required MeshIdentityContext identity,
  String Function()? nonceProvider,
  int Function()? clockProvider,
}) {
  final nonce = (nonceProvider ?? _defaultNonce)();
  final ts = (clockProvider ?? _defaultClock)();
  final unsigned = SignedBundle(
    senderCertChain: identity.senderCertChain,
    recipientCertId: identity.brainRootCertId,
    payloadType: payloadTypeForOutboxEntry(entry),
    // W1.2 — payload is now the raw cell-envelope BLOB stored in the DB.
    payload: entry.payload ?? Uint8List(0),
    signature: Uint8List(signedBundleSigLen),
    signatureMetadata: SignatureMetadata(
      nonceHex: nonce,
      timestampUnix: ts,
    ),
  );
  return signBundle(
    unsigned: unsigned,
    signingPriv: identity.leafPrivateKey,
  );
}

String _defaultNonce() {
  // 32 bytes of fresh CSPRNG output, hex-encoded.  The codec only
  // requires the field be 64 hex chars; the brain's NonceLru uses the
  // hex string verbatim as its key.
  final r = Random.secure();
  final sb = StringBuffer();
  for (var i = 0; i < 32; i++) {
    sb.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

int _defaultClock() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

```
