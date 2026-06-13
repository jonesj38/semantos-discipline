---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/contacts/contacts_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.884583+00:00
---

# archive/apps-semantos-monolith/lib/src/contacts/contacts_repository.dart

```dart
// ContactsRepository — hat-scoped contact book backed by SQLite.
//
// Storage key schema (identical to the TypeScript contact-store so
// records written by the brain are readable here without any
// transformation):
//
//   contacts/{hatCertId}/records/{certId}             → JSON ContactRecord
//   contacts/{hatCertId}/index/edges/{certId}:{type}  → JSON ContactEdgeRecord
//
// Contacts are scoped to the active hat's certId.  The hat certId is
// derived from the operator's root cert via BRC-42
// (identityPort.deriveChild(rootCertId, extensionId, domainFlag)).
// Switching hats switches the prefix; records are never shared.
//
// SqfliteStorageAdapter.list() returns full paths, so _recordsPrefix
// is used as both the list filter and the read key directly.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:semantos_ffi/semantos_ffi.dart' show SqfliteStorageAdapter;

import 'contact_record.dart';

class ContactsRepository {
  final SqfliteStorageAdapter _storage;

  /// BRC-42 certId of the active hat — scopes all storage keys.
  final String hatCertId;

  ContactsRepository({
    required SqfliteStorageAdapter storage,
    required this.hatCertId,
  }) : _storage = storage;

  // ── Key helpers ───────────────────────────────────────────────────────────

  String get _prefix => 'contacts/$hatCertId/';

  String _recordKey(String certId) => '${_prefix}records/$certId';

  String _edgeKey(String certId, String edgeType) =>
      '${_prefix}index/edges/$certId:$edgeType';

  // ── Contact reads ─────────────────────────────────────────────────────────

  Future<List<ContactRecord>> listContacts() async {
    final paths = await _storage.list('${_prefix}records/');
    final results = <ContactRecord>[];
    for (final path in paths) {
      final data = await _storage.read(path);
      if (data == null) continue;
      try {
        final j = json.decode(utf8.decode(data)) as Map<String, dynamic>;
        results.add(ContactRecord.fromJson(j));
      } catch (e) {
        debugPrint('[Contacts] parse error at $path: $e');
      }
    }
    results.sort((a, b) => a.displayName
        .toLowerCase()
        .compareTo(b.displayName.toLowerCase()));
    return results;
  }

  Future<ContactRecord?> getContact(String certId) async {
    final data = await _storage.read(_recordKey(certId));
    if (data == null) return null;
    try {
      return ContactRecord.fromJson(
          json.decode(utf8.decode(data)) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[Contacts] getContact parse error for $certId: $e');
      return null;
    }
  }

  /// All contacts that have at least one active MESSAGING edge.
  Future<List<ContactRecord>> listConnectedContacts() async {
    final all = await listContacts();
    final connected = <ContactRecord>[];
    for (final c in all) {
      final edge = await getEdge(c.certId);
      if (edge != null && edge.isActive) connected.add(c);
    }
    return connected;
  }

  Future<List<ContactRecord>> search(String query) async {
    final q = query.toLowerCase();
    final all = await listContacts();
    return all
        .where((c) =>
            c.displayName.toLowerCase().contains(q) ||
            (c.email?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  // ── Edge reads ────────────────────────────────────────────────────────────

  /// Get the edge of [edgeType] (default MESSAGING) to [certId].
  /// Returns null if no edge exists.  Includes revoked edges — check
  /// [ContactEdgeRecord.isActive] if you only want live ones.
  Future<ContactEdgeRecord?> getEdge(
    String certId, {
    String edgeType = 'MESSAGING',
  }) async {
    final data = await _storage.read(_edgeKey(certId, edgeType));
    if (data == null) return null;
    try {
      return ContactEdgeRecord.fromJson(
          json.decode(utf8.decode(data)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// All edges to [certId] across every edge type.
  Future<List<ContactEdgeRecord>> listEdgesTo(String certId) async {
    final paths = await _storage.list('${_prefix}index/edges/$certId:');
    final results = <ContactEdgeRecord>[];
    for (final path in paths) {
      final data = await _storage.read(path);
      if (data == null) continue;
      try {
        results.add(ContactEdgeRecord.fromJson(
            json.decode(utf8.decode(data)) as Map<String, dynamic>));
      } catch (_) {}
    }
    return results;
  }

  bool isConnectedSync(String certId, Map<String, ContactEdgeRecord> edgeCache) {
    final edge = edgeCache['$certId:MESSAGING'];
    return edge != null && edge.isActive;
  }

  // ── Contact writes ────────────────────────────────────────────────────────

  Future<void> putContact(ContactRecord contact) async {
    await _storage.write(
      _recordKey(contact.certId),
      Uint8List.fromList(utf8.encode(json.encode(contact.toJson()))),
    );
  }

  Future<ContactRecord> addContact({
    required String certId,
    required String publicKey,
    required String displayName,
    String? email,
    String? nodeType,
    String source = 'manual',
  }) async {
    final existing = await getContact(certId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final contact = ContactRecord(
      certId:      certId,
      publicKey:   publicKey,
      displayName: displayName,
      email:       email ?? existing?.email,
      nodeType:    nodeType ?? existing?.nodeType,
      edgeId:      existing?.edgeId,
      source:      source,
      addedAt:     existing?.addedAt ?? now,
      updatedAt:   now,
    );
    await putContact(contact);
    return contact;
  }

  Future<bool> removeContact(String certId) async {
    return _storage.delete(_recordKey(certId));
  }

  // ── Edge writes ───────────────────────────────────────────────────────────

  Future<void> putEdge(ContactEdgeRecord edge) async {
    await _storage.write(
      _edgeKey(edge.responderCertId, edge.edgeType),
      Uint8List.fromList(utf8.encode(json.encode(edge.toJson()))),
    );
    // Update primary edgeId on the contact if this is a MESSAGING edge.
    if (edge.edgeType == 'MESSAGING' && edge.isActive) {
      final contact = await getContact(edge.responderCertId);
      if (contact != null) {
        await putContact(contact.copyWith(
          edgeId:    edge.edgeId,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    }
  }

  /// Soft-delete an edge per Plexus §1.1.8 — sets revokedAt, never
  /// hard-deletes.  Returns false if the edge doesn't exist or is
  /// already revoked.
  Future<bool> revokeEdge(
    String certId, {
    String edgeType = 'MESSAGING',
  }) async {
    final edge = await getEdge(certId, edgeType: edgeType);
    if (edge == null || !edge.isActive) return false;
    await putEdge(ContactEdgeRecord(
      edgeId:          edge.edgeId,
      initiatorCertId: edge.initiatorCertId,
      responderCertId: edge.responderCertId,
      edgeType:        edge.edgeType,
      signingKeyIndex: edge.signingKeyIndex,
      recoveryPolicy:  edge.recoveryPolicy,
      backupRecipe:    edge.backupRecipe,
      appId:           edge.appId,
      createdAt:       edge.createdAt,
      revokedAt:       DateTime.now().millisecondsSinceEpoch,
    ));
    // Clear the primary edgeId from the contact if this was MESSAGING.
    if (edgeType == 'MESSAGING') {
      final contact = await getContact(certId);
      if (contact != null && contact.edgeId == edge.edgeId) {
        await putContact(contact.copyWith(
          edgeId:    '',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    }
    return true;
  }
}

```
