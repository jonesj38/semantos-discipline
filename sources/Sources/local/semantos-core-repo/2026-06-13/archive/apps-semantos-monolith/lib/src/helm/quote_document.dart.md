---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/quote_document.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.897222+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/quote_document.dart

```dart
// Quote document — local line-item store.
//
// QuoteDocument is a structured document stored locally in
// HatEntityRepository (entity_tag: 'quote_doc.v1').  It sits alongside
// the Semantos Brain Quote (which holds the FSM state and cost range); the
// QuoteDocument holds the operator's actual line items, payment terms,
// and free-form notes — the data that makes up a real quote sheet.
//
// Relationship:
//   brain Quote (FSM)  ←→  QuoteDocument (local)
//   linked via quoteId (set after `add quote` succeeds)
//   both linked to jobId
//
// QuoteDocRepository uses HatEntityRepository as the backing store,
// keying documents with id 'quotedoc-<jobId>' so there is at most one
// draft per job.  The id scheme is intentionally simple — if a job goes
// through multiple quote cycles the document is overwritten in place.

import 'dart:convert';

import '../repl/hat_context.dart';
import '../repl/hat_entity_repository.dart';

// ── QuoteLineItem ─────────────────────────────────────────────────────────

class QuoteLineItem {
  final String description;
  final double quantity;
  final int unitCents;

  const QuoteLineItem({
    required this.description,
    required this.quantity,
    required this.unitCents,
  });

  int get totalCents => (quantity * unitCents).round();

  QuoteLineItem copyWith({
    String? description,
    double? quantity,
    int? unitCents,
  }) =>
      QuoteLineItem(
        description: description ?? this.description,
        quantity: quantity ?? this.quantity,
        unitCents: unitCents ?? this.unitCents,
      );

  factory QuoteLineItem.fromJson(Map<String, dynamic> j) => QuoteLineItem(
        description: (j['description'] ?? '').toString(),
        quantity:    (j['quantity'] as num?)?.toDouble() ?? 1.0,
        unitCents:   (j['unit_cents'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'description': description,
        'quantity':    quantity,
        'unit_cents':  unitCents,
      };
}

// ── QuoteDocument ─────────────────────────────────────────────────────────

class QuoteDocument {
  final String id;
  final String jobId;
  final String? quoteId;
  final List<QuoteLineItem> lineItems;
  final String paymentTerms;
  final String notes;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const QuoteDocument({
    required this.id,
    required this.jobId,
    this.quoteId,
    required this.lineItems,
    required this.paymentTerms,
    required this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  int get totalCents =>
      lineItems.fold(0, (sum, item) => sum + item.totalCents);

  QuoteDocument copyWith({
    String? quoteId,
    List<QuoteLineItem>? lineItems,
    String? paymentTerms,
    String? notes,
    String? status,
    DateTime? updatedAt,
  }) =>
      QuoteDocument(
        id:           id,
        jobId:        jobId,
        quoteId:      quoteId ?? this.quoteId,
        lineItems:    lineItems    ?? this.lineItems,
        paymentTerms: paymentTerms ?? this.paymentTerms,
        notes:        notes        ?? this.notes,
        status:       status       ?? this.status,
        createdAt:    createdAt,
        updatedAt:    updatedAt    ?? this.updatedAt,
      );

  factory QuoteDocument.newForJob(String jobId) {
    final now = DateTime.now();
    return QuoteDocument(
      id:           'quotedoc-$jobId',
      jobId:        jobId,
      lineItems:    const [],
      paymentTerms: 'Payment due within 14 days of invoice.',
      notes:        '',
      status:       'draft',
      createdAt:    now,
      updatedAt:    now,
    );
  }

  // ── Serialisation ────────────────────────────────────────────────────

  String toEntityJson() => json.encode({
        'entity_tag':    'quote_doc.v1',
        'id':            id,
        'job_id':        jobId,
        if (quoteId != null) 'quote_id': quoteId,
        'line_items':    lineItems.map((i) => i.toJson()).toList(),
        'payment_terms': paymentTerms,
        'notes':         notes,
        'status':        status,
        'created_at':    createdAt.toIso8601String(),
        'updated_at':    updatedAt.toIso8601String(),
      });

  factory QuoteDocument.fromEntityJson(String entityJson) {
    final j = json.decode(entityJson) as Map<String, dynamic>;
    return QuoteDocument(
      id:           (j['id']     ?? '').toString(),
      jobId:        (j['job_id'] ?? '').toString(),
      quoteId:      (j['quote_id'] as String?)?.isNotEmpty == true
          ? j['quote_id'] as String
          : null,
      lineItems: (j['line_items'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(QuoteLineItem.fromJson)
              .toList() ??
          const [],
      paymentTerms: (j['payment_terms'] ?? '').toString(),
      notes:        (j['notes'] ?? '').toString(),
      status:       (j['status'] ?? 'draft').toString(),
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

// ── QuoteDocRepository ────────────────────────────────────────────────────

class QuoteDocRepository {
  final HatEntityRepository _repo;
  final HatContext _hat;

  QuoteDocRepository({
    required HatEntityRepository repo,
    required HatContext hat,
  })  : _repo = repo,
        _hat = hat;

  Future<QuoteDocument?> findForJob(String jobId) async {
    final id = 'quotedoc-$jobId';
    final all = await _repo.queryAll(domainFlag: _hat.domainFlag);
    final matching = all.where((e) =>
        e.id == id &&
        e.entityJson.contains('"entity_tag":"quote_doc.v1"'));
    if (matching.isEmpty) return null;
    try {
      return QuoteDocument.fromEntityJson(matching.first.entityJson);
    } catch (_) {
      return null;
    }
  }

  Future<QuoteDocument> save(QuoteDocument doc) async {
    final updated = doc.copyWith(updatedAt: DateTime.now());
    await _repo.upsert(HatEntity(
      id:          updated.id,
      domainFlag:  _hat.domainFlag,
      state:       updated.status,
      scheduledAt: '',
      entityJson:  updated.toEntityJson(),
      updatedAt:   updated.updatedAt.toUtc().toIso8601String(),
    ));
    return updated;
  }
}

```
