---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/contacts/contact_record.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.884881+00:00
---

# archive/apps-semantos-monolith/lib/src/contacts/contact_record.dart

```dart
// Dart mirror of the TypeScript Contact + EdgeRecord types from
// @semantos/contact-book.
//
// JSON field names are identical so records written by the brain
// (TypeScript contact-store over NodeFsAdapter) and records written
// here (via ContactsRepository over SqfliteStorageAdapter) share the
// same wire format.  Brain-written contacts can be replicated into
// local SQLite and read without any transformation.

import 'dart:convert';

// ── ContactRecord ─────────────────────────────────────────────────────────────

class ContactRecord {
  /// BRC-52 cert_id — the stable primary key.
  final String certId;

  /// 33-byte compressed secp256k1 public key, hex-encoded.
  final String publicKey;

  /// Display name the local user gives this contact.
  final String displayName;

  /// Email address, if known.
  final String? email;

  /// Plexus DAG node type (PLATFORM, ORGANIZATION, INDIVIDUAL, DEVICE, …).
  final String? nodeType;

  /// Primary MESSAGING edge id, set after connectTo().
  final String? edgeId;

  /// How this contact was added: 'manual' | 'discovered' | 'imported'.
  final String source;

  final int addedAt;
  final int updatedAt;

  const ContactRecord({
    required this.certId,
    required this.publicKey,
    required this.displayName,
    this.email,
    this.nodeType,
    this.edgeId,
    required this.source,
    required this.addedAt,
    required this.updatedAt,
  });

  factory ContactRecord.fromJson(Map<String, dynamic> j) => ContactRecord(
        certId:      (j['certId']      as String?) ?? '',
        publicKey:   (j['publicKey']   as String?) ?? '',
        displayName: (j['displayName'] as String?) ?? '',
        email:       j['email']        as String?,
        nodeType:    j['nodeType']     as String?,
        edgeId:      j['edgeId']       as String?,
        source:      (j['source']      as String?) ?? 'manual',
        addedAt:     (j['addedAt']     as int?)    ?? 0,
        updatedAt:   (j['updatedAt']   as int?)    ?? 0,
      );

  factory ContactRecord.fromJsonString(String s) =>
      ContactRecord.fromJson(json.decode(s) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'certId':      certId,
        'publicKey':   publicKey,
        'displayName': displayName,
        if (email    != null) 'email':    email,
        if (nodeType != null) 'nodeType': nodeType,
        if (edgeId   != null) 'edgeId':   edgeId,
        'source':    source,
        'addedAt':   addedAt,
        'updatedAt': updatedAt,
      };

  String toJsonString() => json.encode(toJson());

  /// Initials for avatar display (e.g. "Alice Chen" → "AC").
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  ContactRecord copyWith({String? edgeId, int? updatedAt}) => ContactRecord(
        certId:      certId,
        publicKey:   publicKey,
        displayName: displayName,
        email:       email,
        nodeType:    nodeType,
        edgeId:      edgeId ?? this.edgeId,
        source:      source,
        addedAt:     addedAt,
        updatedAt:   updatedAt ?? this.updatedAt,
      );
}

// ── EdgeRecord ────────────────────────────────────────────────────────────────

class ContactEdgeRecord {
  final String edgeId;
  final String initiatorCertId;
  final String responderCertId;

  /// 'MESSAGING' | 'DATA_ACCESS' | 'ROLE_ASSIGNMENT' | 'AUTHORITY' |
  /// 'TRANSFER' | 'ATTESTATION' | 'CUSTOM'
  final String edgeType;

  /// BKDS signing key index (invoiceNumber). Never the shared secret
  /// itself — per Plexus §2.5.5 the secret is re-derived locally.
  final int signingKeyIndex;

  /// 'NONE' | 'BACKUP_ON_CREATE' | 'BACKUP_ON_CONFIRM' | 'PARENT_MANAGED'
  final String recoveryPolicy;

  /// BRC-69 key linkage recipe (present when recoveryPolicy ≠ NONE).
  final String? backupRecipe;

  /// Application context for the uniqueness tuple (§1.1.7).
  final String? appId;

  final int createdAt;

  /// Soft-delete timestamp per §1.1.8 — null means active.
  final int? revokedAt;

  const ContactEdgeRecord({
    required this.edgeId,
    required this.initiatorCertId,
    required this.responderCertId,
    required this.edgeType,
    required this.signingKeyIndex,
    required this.recoveryPolicy,
    this.backupRecipe,
    this.appId,
    required this.createdAt,
    this.revokedAt,
  });

  bool get isActive => revokedAt == null;

  factory ContactEdgeRecord.fromJson(Map<String, dynamic> j) =>
      ContactEdgeRecord(
        edgeId:           (j['edgeId']           as String?) ?? '',
        initiatorCertId:  (j['initiatorCertId']  as String?) ?? '',
        responderCertId:  (j['responderCertId']  as String?) ?? '',
        edgeType:         (j['edgeType']         as String?) ?? 'MESSAGING',
        signingKeyIndex:  (j['signingKeyIndex']  as int?)    ?? 0,
        recoveryPolicy:   (j['recoveryPolicy']   as String?) ?? 'NONE',
        backupRecipe:     j['backupRecipe'] as String?,
        appId:            j['appId']        as String?,
        createdAt:        (j['createdAt']   as int?) ?? 0,
        revokedAt:        j['revokedAt']    as int?,
      );

  factory ContactEdgeRecord.fromJsonString(String s) =>
      ContactEdgeRecord.fromJson(json.decode(s) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'edgeId':           edgeId,
        'initiatorCertId':  initiatorCertId,
        'responderCertId':  responderCertId,
        'edgeType':         edgeType,
        'signingKeyIndex':  signingKeyIndex,
        'recoveryPolicy':   recoveryPolicy,
        if (backupRecipe != null) 'backupRecipe': backupRecipe,
        if (appId        != null) 'appId':        appId,
        'createdAt': createdAt,
        if (revokedAt != null) 'revokedAt': revokedAt,
      };

  String toJsonString() => json.encode(toJson());
}

```
