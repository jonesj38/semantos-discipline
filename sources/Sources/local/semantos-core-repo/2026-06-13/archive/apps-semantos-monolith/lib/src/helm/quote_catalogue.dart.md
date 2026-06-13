---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/quote_catalogue.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.885269+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/quote_catalogue.dart

```dart
// Quote catalogue — operator's standard line items with default prices.
//
// CatalogueItem is a reusable line-item template.  The operator's personal
// catalogue is stored as a single entity in HatEntityRepository (tag
// `quote_catalogue.v1`, id `catalogue`) so it travels with the hat and
// needs no extra storage permissions.  It falls back to _kDefaultItems if
// no saved catalogue exists yet.
//
// The catalogue is used two ways:
//   1. Passed as pricing context to QuoteExtractorService so Claude can
//      match and price work against standard rates.
//   2. Surfaced in the QuoteEditorSheet as a quick-picker for manual adds.

import 'dart:convert';

import '../repl/hat_context.dart';
import '../repl/hat_entity_repository.dart';

// ── CatalogueItem ─────────────────────────────────────────────────────────

class CatalogueItem {
  final String id;
  final String description;
  final double defaultQty;
  final int unitCents; // price per unit in cents
  final String unit; // 'hr', 'each', 'job', 'visit', etc.
  final String category; // 'labour', 'travel', 'materials', 'job'

  const CatalogueItem({
    required this.id,
    required this.description,
    required this.defaultQty,
    required this.unitCents,
    required this.unit,
    required this.category,
  });

  String get formattedPrice =>
      unitCents == 0 ? 'varies' : '\$${(unitCents / 100).toStringAsFixed(0)}';
  String get priceLabel => '$formattedPrice/$unit';

  CatalogueItem copyWith({
    String? description,
    double? defaultQty,
    int? unitCents,
    String? unit,
    String? category,
  }) =>
      CatalogueItem(
        id: id,
        description: description ?? this.description,
        defaultQty: defaultQty ?? this.defaultQty,
        unitCents: unitCents ?? this.unitCents,
        unit: unit ?? this.unit,
        category: category ?? this.category,
      );

  factory CatalogueItem.fromJson(Map<String, dynamic> j) => CatalogueItem(
        id: (j['id'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        defaultQty: (j['default_qty'] as num?)?.toDouble() ?? 1.0,
        unitCents: (j['unit_cents'] as num?)?.toInt() ?? 0,
        unit: (j['unit'] ?? 'each').toString(),
        category: (j['category'] ?? 'labour').toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'default_qty': defaultQty,
        'unit_cents': unitCents,
        'unit': unit,
        'category': category,
      };

  /// One-line summary for inclusion in AI prompts.
  String toPromptLine() =>
      '- $description: \$${(unitCents / 100).toStringAsFixed(2)} per $unit';
}

// ── Default seed ─────────────────────────────────────────────────────────
//
// Queensland sole-trader handyman / maintenance trade rates (2025).

const _kDefaultItems = <CatalogueItem>[
  // Labour
  CatalogueItem(
    id: 'labour_hr',
    description: 'Labour (per hour)',
    defaultQty: 1.0,
    unitCents: 9500,
    unit: 'hr',
    category: 'labour',
  ),
  CatalogueItem(
    id: 'labour_half_hr',
    description: 'Labour (per half hour)',
    defaultQty: 1.0,
    unitCents: 5500,
    unit: '0.5hr',
    category: 'labour',
  ),
  // Travel / callout
  CatalogueItem(
    id: 'callout',
    description: 'Callout / site visit fee',
    defaultQty: 1.0,
    unitCents: 9000,
    unit: 'visit',
    category: 'travel',
  ),
  CatalogueItem(
    id: 'travel_15min',
    description: 'Travel (per 15 min)',
    defaultQty: 1.0,
    unitCents: 2500,
    unit: '15min',
    category: 'travel',
  ),
  // Plumbing
  CatalogueItem(
    id: 'tap_washer',
    description: 'Tap washer replacement (supply + fit)',
    defaultQty: 1.0,
    unitCents: 4500,
    unit: 'each',
    category: 'job',
  ),
  CatalogueItem(
    id: 'toilet_seat',
    description: 'Toilet seat supply and fit',
    defaultQty: 1.0,
    unitCents: 12000,
    unit: 'each',
    category: 'job',
  ),
  CatalogueItem(
    id: 'silicone_tube',
    description: 'Silicone sealant (tube, supply + apply)',
    defaultQty: 1.0,
    unitCents: 2500,
    unit: 'tube',
    category: 'materials',
  ),
  // Gutters
  CatalogueItem(
    id: 'gutter_single',
    description: 'Gutter cleaning — single storey',
    defaultQty: 1.0,
    unitCents: 18000,
    unit: 'job',
    category: 'job',
  ),
  CatalogueItem(
    id: 'gutter_double',
    description: 'Gutter cleaning — double storey',
    defaultQty: 1.0,
    unitCents: 28000,
    unit: 'job',
    category: 'job',
  ),
  // General maintenance
  CatalogueItem(
    id: 'wash_line_replace',
    description: 'Clothes line / wash line replacement',
    defaultQty: 1.0,
    unitCents: 15000,
    unit: 'job',
    category: 'job',
  ),
  CatalogueItem(
    id: 'handrail_install',
    description: 'Handrail installation / replacement',
    defaultQty: 1.0,
    unitCents: 32000,
    unit: 'job',
    category: 'job',
  ),
  CatalogueItem(
    id: 'glass_door_repair',
    description: 'Glass / sliding door repair',
    defaultQty: 1.0,
    unitCents: 30000,
    unit: 'job',
    category: 'job',
  ),
  CatalogueItem(
    id: 'fence_repair_hr',
    description: 'Fence / privacy screening repair',
    defaultQty: 1.0,
    unitCents: 9500,
    unit: 'hr',
    category: 'labour',
  ),
  CatalogueItem(
    id: 'roof_inspection',
    description: 'Roof inspection and report',
    defaultQty: 1.0,
    unitCents: 15000,
    unit: 'job',
    category: 'job',
  ),
  CatalogueItem(
    id: 'materials_supply',
    description: 'Materials supply (cost price)',
    defaultQty: 1.0,
    unitCents: 0, // set per-job
    unit: 'lot',
    category: 'materials',
  ),
];

// ── QuoteCatalogueService ─────────────────────────────────────────────────

class QuoteCatalogueService {
  final HatEntityRepository? _repo;
  final HatContext? _hat;

  List<CatalogueItem> _items = List.of(_kDefaultItems);
  bool _loaded = false;

  static const _kEntityId = 'catalogue';
  static const _kEntityTag = 'quote_catalogue.v1';

  /// [repo] and [hat] may be null — in that case, the catalogue uses
  /// built-in defaults and changes are not persisted.
  QuoteCatalogueService({HatEntityRepository? repo, HatContext? hat})
      : _repo = repo,
        _hat = hat;

  List<CatalogueItem> get items => List.unmodifiable(_items);

  /// Load catalogue from the entity store (falls back to defaults).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final repo = _repo;
    final hat = _hat;
    if (repo == null || hat == null) return;
    try {
      final all = await repo.queryAll(domainFlag: hat.domainFlag);
      final match = all.where((e) =>
          e.id == _kEntityId &&
          e.entityJson.contains('"$_kEntityTag"'));
      if (match.isEmpty) return;
      final j = jsonDecode(match.first.entityJson) as Map<String, dynamic>;
      final list = (j['items'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map(CatalogueItem.fromJson)
          .toList();
      if (list != null && list.isNotEmpty) _items = list;
    } catch (_) {
      // keep defaults on any error
    }
  }

  Future<void> _save() async {
    final repo = _repo;
    final hat = _hat;
    if (repo == null || hat == null) return;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await repo.upsert(HatEntity(
        id: _kEntityId,
        domainFlag: hat.domainFlag,
        state: 'active',
        scheduledAt: '',
        entityJson: jsonEncode({
          'entity_tag': _kEntityTag,
          'id': _kEntityId,
          'items': _items.map((i) => i.toJson()).toList(),
          'updated_at': now,
        }),
        updatedAt: now,
      ));
    } catch (_) {}
  }

  Future<void> updateItem(CatalogueItem updated) async {
    final idx = _items.indexWhere((i) => i.id == updated.id);
    if (idx >= 0) {
      _items[idx] = updated;
    } else {
      _items.add(updated);
    }
    await _save();
  }

  Future<void> removeItem(String id) async {
    _items.removeWhere((i) => i.id == id);
    await _save();
  }

  Future<void> resetToDefaults() async {
    _items = List.of(_kDefaultItems);
    await _save();
  }

  /// Compact text block for AI prompt context.
  String toPromptContext() {
    if (_items.isEmpty) return '(no standard catalogue items configured)';
    final lines = _items
        .where((i) => i.unitCents > 0)
        .map((i) => i.toPromptLine())
        .join('\n');
    return 'Standard catalogue (use for pricing):\n$lines';
  }
}

```
