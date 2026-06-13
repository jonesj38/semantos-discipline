---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/invoice_document.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.898438+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/invoice_document.dart

```dart
// Invoice document — local line-item store for invoices.
//
// InvoiceDocument is structurally parallel to QuoteDocument but purpose-built
// for the invoicing workflow.  The key differences:
//
//   • InvoiceLineItem has a `source` field ('quote' | 'manual' | 'receipt')
//     so the invoice UI can show source chips and the operator can tell
//     which items were carried from the approved quote vs added at invoice time.
//
//   • Stored with entity_tag 'invoice_doc.v1'; keyed as 'invoicedoc-<jobId>'.
//
//   • No approval state machine — invoices are operator-authored and drive
//     straight to the brain FSM transition via do_node._doInvoice().
//
// P3a of OJT-UNIFIED-QUOTE-INVOICE-PLAN.

import 'dart:convert';

import '../repl/hat_context.dart';
import '../repl/hat_entity_repository.dart';
import 'quote_document.dart' show QuoteDocument, QuoteLineItem;

// ── InvoiceLineItem ───────────────────────────────────────────────────────

/// Source of a line item on the invoice.
enum InvoiceLineSource {
  /// Carried from the approved QuoteDocument.
  quote,

  /// Added manually by the operator at invoice time.
  manual,

  /// Scanned from a receipt photo via ReceiptOcrService.
  receipt,
}

class InvoiceLineItem {
  final String description;
  final double quantity;
  final int unitCents;
  final InvoiceLineSource source;

  const InvoiceLineItem({
    required this.description,
    required this.quantity,
    required this.unitCents,
    this.source = InvoiceLineSource.manual,
  });

  int get totalCents => (quantity * unitCents).round();

  InvoiceLineItem copyWith({
    String? description,
    double? quantity,
    int? unitCents,
    InvoiceLineSource? source,
  }) =>
      InvoiceLineItem(
        description: description ?? this.description,
        quantity: quantity ?? this.quantity,
        unitCents: unitCents ?? this.unitCents,
        source: source ?? this.source,
      );

  /// Convert to a plain QuoteLineItem (loses source info; used when passing
  /// totalCents to the brain FSM).
  QuoteLineItem toQuoteLineItem() => QuoteLineItem(
        description: description,
        quantity: quantity,
        unitCents: unitCents,
      );

  factory InvoiceLineItem.fromJson(Map<String, dynamic> j) {
    final src = switch ((j['source'] as String?) ?? 'manual') {
      'quote' => InvoiceLineSource.quote,
      'receipt' => InvoiceLineSource.receipt,
      _ => InvoiceLineSource.manual,
    };
    return InvoiceLineItem(
      description: (j['description'] ?? '').toString(),
      quantity: (j['quantity'] as num?)?.toDouble() ?? 1.0,
      unitCents: (j['unit_cents'] as num?)?.toInt() ?? 0,
      source: src,
    );
  }

  Map<String, dynamic> toJson() => {
        'description': description,
        'quantity': quantity,
        'unit_cents': unitCents,
        'source': source.name,
      };
}

// ── InvoiceDocument ───────────────────────────────────────────────────────

class InvoiceDocument {
  final String id;
  final String jobId;
  final List<InvoiceLineItem> lineItems;
  final String paymentTerms;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InvoiceDocument({
    required this.id,
    required this.jobId,
    required this.lineItems,
    required this.paymentTerms,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  int get totalCents =>
      lineItems.fold(0, (sum, item) => sum + item.totalCents);

  InvoiceDocument copyWith({
    List<InvoiceLineItem>? lineItems,
    String? paymentTerms,
    String? notes,
    DateTime? updatedAt,
  }) =>
      InvoiceDocument(
        id: id,
        jobId: jobId,
        lineItems: lineItems ?? this.lineItems,
        paymentTerms: paymentTerms ?? this.paymentTerms,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Create a new blank invoice for a job.
  factory InvoiceDocument.newForJob(String jobId) {
    final now = DateTime.now();
    return InvoiceDocument(
      id: 'invoicedoc-$jobId',
      jobId: jobId,
      lineItems: const [],
      paymentTerms: 'Payment due within 14 days.',
      notes: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create an invoice pre-populated from an approved QuoteDocument.
  /// All items are tagged with source='quote'.
  factory InvoiceDocument.fromQuote(QuoteDocument quote) {
    final now = DateTime.now();
    return InvoiceDocument(
      id: 'invoicedoc-${quote.jobId}',
      jobId: quote.jobId,
      lineItems: quote.lineItems
          .map((q) => InvoiceLineItem(
                description: q.description,
                quantity: q.quantity,
                unitCents: q.unitCents,
                source: InvoiceLineSource.quote,
              ))
          .toList(),
      paymentTerms: quote.paymentTerms,
      notes: quote.notes,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ── Serialisation ────────────────────────────────────────────────────

  String toEntityJson() => json.encode({
        'entity_tag': 'invoice_doc.v1',
        'id': id,
        'job_id': jobId,
        'line_items': lineItems.map((i) => i.toJson()).toList(),
        'payment_terms': paymentTerms,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      });

  factory InvoiceDocument.fromEntityJson(String entityJson) {
    final j = json.decode(entityJson) as Map<String, dynamic>;
    return InvoiceDocument(
      id: (j['id'] ?? '').toString(),
      jobId: (j['job_id'] ?? '').toString(),
      lineItems: (j['line_items'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(InvoiceLineItem.fromJson)
              .toList() ??
          const [],
      paymentTerms: (j['payment_terms'] ?? '').toString(),
      notes: (j['notes'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((j['created_at'] ?? '').toString()) ??
              DateTime.now(),
      updatedAt:
          DateTime.tryParse((j['updated_at'] ?? '').toString()) ??
              DateTime.now(),
    );
  }
}

// ── InvoiceDocRepository ─────────────────────────────────────────────────

class InvoiceDocRepository {
  final HatEntityRepository _repo;
  final HatContext _hat;

  InvoiceDocRepository({
    required HatEntityRepository repo,
    required HatContext hat,
  })  : _repo = repo,
        _hat = hat;

  Future<InvoiceDocument?> findForJob(String jobId) async {
    final id = 'invoicedoc-$jobId';
    final all = await _repo.queryAll(domainFlag: _hat.domainFlag);
    final matching = all.where((e) =>
        e.id == id &&
        e.entityJson.contains('"entity_tag":"invoice_doc.v1"'));
    if (matching.isEmpty) return null;
    try {
      return InvoiceDocument.fromEntityJson(matching.first.entityJson);
    } catch (_) {
      return null;
    }
  }

  Future<InvoiceDocument> save(InvoiceDocument doc) async {
    final updated = doc.copyWith(updatedAt: DateTime.now());
    await _repo.upsert(HatEntity(
      id: updated.id,
      domainFlag: _hat.domainFlag,
      state: 'draft',
      scheduledAt: '',
      entityJson: updated.toEntityJson(),
      updatedAt: updated.updatedAt.toUtc().toIso8601String(),
    ));
    return updated;
  }
}

```
