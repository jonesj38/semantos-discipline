---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/quote_catalog.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.467786+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/quote_catalog.dart

```dart
import 'quote_document.dart';

class QuoteCatalogItem {
  const QuoteCatalogItem({
    required this.id,
    required this.description,
    required this.defaultQty,
    required this.unitCents,
    required this.unit,
    required this.category,
  });

  final String id;
  final String description;
  final double defaultQty;
  final int unitCents;
  final String unit;
  final String category;

  String get formattedPrice => formatCents(unitCents);
  String get priceLabel => '$formattedPrice / $unit';

  QuoteLineItem toLineItem() => QuoteLineItem(
    description: description,
    quantity: defaultQty,
    unitCents: unitCents,
    unit: unit,
    category: category,
    sourceCatalogItemId: id,
    provenanceRefs: ['catalog:$id'],
  );

  factory QuoteCatalogItem.fromJson(Map<String, dynamic> json) {
    return QuoteCatalogItem(
      id: json['id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      defaultQty: (json['defaultQty'] as num? ?? 1).toDouble(),
      unitCents: (json['unitCents'] as num? ?? 0).toInt(),
      unit: json['unit'] as String? ?? 'ea',
      category: json['category'] as String? ?? 'general',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'defaultQty': defaultQty,
    'unitCents': unitCents,
    'unit': unit,
    'category': category,
  };
}

/// Service-business catalog items are operator-owned.
///
/// OddJobz is not a handyman app; it is a visit-based service-business
/// cartridge. A fresh operator should configure their own policy/catalog.
/// These entries are only an optional example seed a host may offer during
/// onboarding or tests.
const oddjobzExampleServiceCatalogItems = <QuoteCatalogItem>[
  QuoteCatalogItem(
    id: 'labour_hr',
    description: 'Labour',
    defaultQty: 1,
    unitCents: 9500,
    unit: 'hr',
    category: 'labour',
  ),
  QuoteCatalogItem(
    id: 'callout',
    description: 'Callout / site visit',
    defaultQty: 1,
    unitCents: 8500,
    unit: 'ea',
    category: 'labour',
  ),
  QuoteCatalogItem(
    id: 'travel',
    description: 'Travel',
    defaultQty: 1,
    unitCents: 4500,
    unit: 'ea',
    category: 'labour',
  ),
  QuoteCatalogItem(
    id: 'tap_washer',
    description: 'Replace tap washer',
    defaultQty: 1,
    unitCents: 3500,
    unit: 'ea',
    category: 'plumbing',
  ),
  QuoteCatalogItem(
    id: 'toilet_seat',
    description: 'Replace toilet seat',
    defaultQty: 1,
    unitCents: 6500,
    unit: 'ea',
    category: 'bathroom',
  ),
  QuoteCatalogItem(
    id: 'silicone',
    description: 'Remove and replace silicone',
    defaultQty: 1,
    unitCents: 12000,
    unit: 'area',
    category: 'bathroom',
  ),
  QuoteCatalogItem(
    id: 'gutter_clean',
    description: 'Clean gutters',
    defaultQty: 1,
    unitCents: 18000,
    unit: 'job',
    category: 'roofing',
  ),
  QuoteCatalogItem(
    id: 'roof_inspection',
    description: 'Roof inspection',
    defaultQty: 1,
    unitCents: 16500,
    unit: 'ea',
    category: 'roofing',
  ),
  QuoteCatalogItem(
    id: 'materials_supply',
    description: 'Materials supply',
    defaultQty: 1,
    unitCents: 10000,
    unit: 'allowance',
    category: 'materials',
  ),
];

String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final dollars = abs ~/ 100;
  final remainder = (abs % 100).toString().padLeft(2, '0');
  return '$sign\$$dollars.$remainder';
}

List<QuoteCatalogItem> parseQuoteCatalogItems(dynamic json) {
  if (json is! List) return const [];
  return [
    for (final item in json)
      if (item is Map<String, dynamic>) QuoteCatalogItem.fromJson(item),
  ];
}

List<Map<String, dynamic>> encodeQuoteCatalogItems(
  List<QuoteCatalogItem> items,
) => items.map((item) => item.toJson()).toList();

```
