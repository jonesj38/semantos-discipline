---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/contacts_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.108112+00:00
---

# apps/semantos/lib/src/wallet/contacts_service.dart

```dart
// PWA contacts-PKI — shell service tying the operator identity to the
// invite → bilateral edge → BRC-69 backup flow.
//
// This is the headless seam the contacts UI drives. It owns:
//   - reading the operator's identity key (cert_body) on demand,
//     deriving the identity pubkey + cert id, and zeroing the key
//     immediately after use (get-use-zero, same discipline as
//     WalletKeyService);
//   - generating an outgoing invite for my identity;
//   - accepting an incoming invite to mint + persist a
//     LocalEdgeEnvelope (edgeId + BRC-69 backup recipe), via the
//     bilateral BRC-42 edge crypto in `edge_invite.dart`;
//   - listing the edges/contacts the wallet holds.
//
// The cert_body slot + cert-id convention match WalletKeyService
// (`me.cert_body.v1`, certId = SHA-256(certPub)[0:16] hex), so an edge
// minted here is bound to the same operator identity the rest of the
// wallet uses — and (per the cross-language KAT) interoperates with a
// brain-created edge.

import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:semantos_core/semantos_core.dart' show IdentityStore;

import 'brc42_derive.dart' show publicKeyFromPrivate;
import 'edge_invite.dart';
import 'edge_store.dart';
import 'identity_store_adapter.dart';
import 'wallet_key_service.dart' show kActiveCertBodySlot;

/// Result of generating an outgoing invite — both the structured invite
/// and the shareable URL, so the UI can render either (URL today, QR
/// once a QR widget lands).
class GeneratedInvite {
  const GeneratedInvite({required this.invite, required this.url});

  final PeerInvite invite;
  final String url;
}

/// Headless contacts/edge service. Construct once per session against
/// the shell's [IdentityStore].
class ContactsService {
  ContactsService({required IdentityStore identityStore})
      : _identityStore = identityStore,
        _edges = EdgeStore(IdentityStoreSecureStoreAdapter(identityStore));

  final IdentityStore _identityStore;
  final EdgeStore _edges;

  /// Direct accessor to the edge store (UI list, recovery scanner).
  EdgeStore get edges => _edges;

  /// True when an operator identity (cert_body) is bound — invites and
  /// edge acceptance require it.
  Future<bool> hasIdentity() async {
    final body = await _readCertBody();
    if (body == null) return false;
    body.fillRange(0, body.length, 0);
    return true;
  }

  /// Generate an outgoing invite for my identity. Returns null when no
  /// identity is bound (caller prompts the user to set one up).
  Future<GeneratedInvite?> generateMyInvite({String? baseUrl}) async {
    final body = await _readCertBody();
    if (body == null) return null;
    try {
      final certPub = publicKeyFromPrivate(body);
      final certId = _certIdOf(certPub);
      final invite = generateInvite(myCertId: certId, myPk: certPub);
      return GeneratedInvite(
        invite: invite,
        url: buildInviteUrl(invite, baseUrl: baseUrl),
      );
    } finally {
      body.fillRange(0, body.length, 0);
    }
  }

  /// Accept an incoming invite (URL or bare token) and persist the new
  /// edge. A fresh edge starts at signing-key index 0; subsequent
  /// rotated payments call [EdgeStore.advanceIndex].
  ///
  /// Returns the stored [LocalEdgeEnvelope]. Throws [StateError] when no
  /// identity is bound or the invite is malformed/expired, and rethrows
  /// derivation [ArgumentError]s — the UI surfaces the cause.
  Future<LocalEdgeEnvelope> acceptInvite(String urlOrToken) async {
    final invite = _parse(urlOrToken);
    if (invite == null) {
      throw StateError('invite is malformed or expired');
    }
    final body = await _readCertBody();
    if (body == null) {
      throw StateError('no operator identity bound');
    }
    try {
      final certId = _certIdOf(publicKeyFromPrivate(body));
      final envelope = createEdgeEnvelope(
        invite: invite,
        myCertId: certId,
        mySk: body,
        signingKeyIndex: 0,
      );
      await _edges.save(envelope);
      return envelope;
    } finally {
      body.fillRange(0, body.length, 0);
    }
  }

  /// List all edges/contacts, most-recent first.
  Future<List<LocalEdgeEnvelope>> listEdges() async {
    final all = await _edges.loadAll();
    final sorted = all.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  // ─────────────── helpers ───────────────

  /// Accept either a full invite URL or a bare base64url token.
  PeerInvite? _parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains('invite=') || trimmed.contains('://')) {
      final fromUrl = parseInviteUrl(trimmed);
      if (fromUrl != null) return fromUrl;
    }
    return decodeInviteToken(trimmed);
  }

  /// certId = SHA-256(certPub)[0:16] hex — matches WalletKeyService.
  String _certIdOf(Uint8List certPub) =>
      _hex(SHA256Digest().process(certPub).sublist(0, 16));

  /// Read + hex-decode the active cert_body. Returns null when absent or
  /// malformed. Caller MUST zero the returned bytes.
  Future<Uint8List?> _readCertBody() async {
    final raw = await _identityStore.read(kActiveCertBodySlot);
    if (raw == null || raw.length != 64) return null;
    if (raw.length.isOdd) return null;
    final out = Uint8List(raw.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final b = int.tryParse(raw.substring(i * 2, i * 2 + 2), radix: 16);
      if (b == null) return null;
      out[i] = b;
    }
    return out;
  }

  String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

```
