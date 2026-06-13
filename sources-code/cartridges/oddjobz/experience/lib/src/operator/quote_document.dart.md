---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/quote_document.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.465966+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/quote_document.dart

```dart
/// Client-side editable quote draft for the Oddjobz operator UI.
///
/// The current canonical `oddjobz.quote.v1` cell stores summary/range
/// fields rather than detailed invoice-style line items.  This document is
/// therefore the operator draft/preview shape; [toQuoteRequestJson] folds it
/// down to the canonical fields the brain can persist today.
library;

class QuoteLineItem {
  const QuoteLineItem({
    required this.description,
    required this.quantity,
    required this.unitCents,
    this.unit,
    this.category,
    this.sourceCatalogItemId,
    this.provenanceRefs = const [],
  });

  final String description;
  final double quantity;
  final int unitCents;
  final String? unit;
  final String? category;
  final String? sourceCatalogItemId;

  /// Stable refs explaining where this line came from, e.g.
  /// `turn:<conversation-turn-id>` and/or `catalog:<catalog-item-id>`.
  final List<String> provenanceRefs;

  int get totalCents => (quantity * unitCents).round();

  QuoteLineItem copyWith({
    String? description,
    double? quantity,
    int? unitCents,
    String? unit,
    String? category,
    String? sourceCatalogItemId,
    List<String>? provenanceRefs,
  }) {
    return QuoteLineItem(
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unitCents: unitCents ?? this.unitCents,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      sourceCatalogItemId: sourceCatalogItemId ?? this.sourceCatalogItemId,
      provenanceRefs: provenanceRefs ?? this.provenanceRefs,
    );
  }

  factory QuoteLineItem.fromJson(Map<String, dynamic> json) {
    return QuoteLineItem(
      description: json['description'] as String? ?? '',
      quantity: (json['quantity'] as num? ?? 1).toDouble(),
      unitCents: (json['unitCents'] as num? ?? 0).toInt(),
      unit: json['unit'] as String?,
      category: json['category'] as String?,
      sourceCatalogItemId: json['sourceCatalogItemId'] as String?,
      provenanceRefs: [
        for (final ref
            in (json['provenanceRefs'] as List<dynamic>? ?? const []))
          ref.toString(),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'description': description,
    'quantity': quantity,
    'unitCents': unitCents,
    if (unit != null) 'unit': unit,
    if (category != null) 'category': category,
    if (sourceCatalogItemId != null) 'sourceCatalogItemId': sourceCatalogItemId,
    if (provenanceRefs.isNotEmpty) 'provenanceRefs': provenanceRefs,
  };
}

class QuoteDocument {
  const QuoteDocument({
    required this.id,
    required this.jobId,
    required this.status,
    required this.lineItems,
    required this.paymentTerms,
    required this.notes,
    required this.customerSummary,
    required this.createdAt,
    required this.updatedAt,
    this.quoteId,
    this.markdown = '',
  });

  final String id;
  final String jobId;
  final String? quoteId;
  final String status;
  final List<QuoteLineItem> lineItems;
  final String paymentTerms;
  final String notes;
  final String customerSummary;
  final String markdown;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get totalCents =>
      lineItems.fold<int>(0, (sum, item) => sum + item.totalCents);

  factory QuoteDocument.newForJob(String jobId, {DateTime? now}) {
    final timestamp = now ?? DateTime.now().toUtc();
    return QuoteDocument(
      id: 'draft-${timestamp.microsecondsSinceEpoch}',
      jobId: jobId,
      status: 'draft',
      lineItems: const [],
      paymentTerms: 'Due on completion.',
      notes: '',
      customerSummary: '',
      markdown: '',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  QuoteDocument copyWith({
    String? id,
    String? jobId,
    String? quoteId,
    String? status,
    List<QuoteLineItem>? lineItems,
    String? paymentTerms,
    String? notes,
    String? customerSummary,
    String? markdown,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return QuoteDocument(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      quoteId: quoteId ?? this.quoteId,
      status: status ?? this.status,
      lineItems: lineItems ?? this.lineItems,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      notes: notes ?? this.notes,
      customerSummary: customerSummary ?? this.customerSummary,
      markdown: markdown ?? this.markdown,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory QuoteDocument.fromJson(Map<String, dynamic> json) {
    return QuoteDocument(
      id: json['id'] as String? ?? '',
      jobId: json['jobId'] as String? ?? '',
      quoteId: json['quoteId'] as String?,
      status: json['status'] as String? ?? 'draft',
      lineItems: [
        for (final item in (json['lineItems'] as List<dynamic>? ?? const []))
          QuoteLineItem.fromJson(item as Map<String, dynamic>),
      ],
      paymentTerms: json['paymentTerms'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      customerSummary: json['customerSummary'] as String? ?? '',
      markdown: json['markdown'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'jobId': jobId,
    if (quoteId != null) 'quoteId': quoteId,
    'status': status,
    'lineItems': lineItems.map((item) => item.toJson()).toList(),
    'paymentTerms': paymentTerms,
    'notes': notes,
    'customerSummary': customerSummary,
    if (markdown.trim().isNotEmpty) 'markdown': markdown,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toQuoteRequestJson() => {
    'jobId': jobId,
    'costMin': totalCents,
    'costMax': totalCents,
    'customerSummary': customerSummary.isEmpty
        ? _defaultCustomerSummary()
        : customerSummary,
    'assumptionNotes': [
      if (notes.trim().isNotEmpty) notes.trim(),
      if (paymentTerms.trim().isNotEmpty)
        'Payment terms: ${paymentTerms.trim()}',
    ].join('\n'),
    'lineItems': lineItems.map((item) => item.toJson()).toList(),
    if (markdown.trim().isNotEmpty) 'markdown': markdown,
  };

  String _defaultCustomerSummary() {
    if (lineItems.isEmpty) return 'Quote for job $jobId.';
    return lineItems.map((item) => item.description).join(', ');
  }
}

```
