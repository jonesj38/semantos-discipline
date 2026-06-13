---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/attention_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.461411+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/attention_repository.dart

```dart
/// attention_repository.dart — the operator's Attention feed over the unified
/// WSS RPC channel. Drives the helm Home: the items needing action, in the
/// same three operator-action buckets the monolith surfaced.
///
/// Reads via `repl.eval("find attention")` (the oddjobz cartridge verb, now
/// reachable over /api/v1/rpc — see fix(brain): attach cartridge REPL verb
/// registry). The verb returns buckets of jobs/leads keyed by the next
/// operator step. We parse the raw JSON the verb prints.
library;

import 'dart:convert';

import 'oddjobz_rpc.dart';

/// One actionable item in the attention feed (a lead/job awaiting a step).
class AttentionItem {
  final String id;
  final String customerName;
  final String state;
  final String propertyAddress;
  final String description;
  final String? services;
  final String? workOrderNumber;
  final String scheduledAt;

  const AttentionItem({
    required this.id,
    required this.customerName,
    required this.state,
    required this.propertyAddress,
    required this.description,
    this.services,
    this.workOrderNumber,
    this.scheduledAt = '',
  });

  factory AttentionItem.fromJson(Map<String, dynamic> j) => AttentionItem(
    id: (j['id'] ?? '').toString(),
    customerName: (j['customer_name'] ?? '').toString(),
    state: (j['state'] ?? '').toString(),
    propertyAddress: (j['propertyAddress'] ?? '').toString(),
    description: (j['description'] ?? '').toString(),
    services: j['services']?.toString(),
    workOrderNumber: j['workOrderNumber']?.toString(),
    scheduledAt: (j['scheduled_at'] ?? '').toString(),
  );
}

/// One bucket of the attention feed — the operator-action lane + its items.
class AttentionBucket {
  /// Stable key (`pending_quote` / `pending_schedule` / `pending_invoice`).
  final String key;

  /// Human label ("Pending quote", …).
  final String label;
  final List<AttentionItem> items;

  const AttentionBucket({
    required this.key,
    required this.label,
    required this.items,
  });
}

/// The full attention feed: ordered buckets + the brain's reported total.
class AttentionFeed {
  final List<AttentionBucket> buckets;
  final int total;

  const AttentionFeed({required this.buckets, required this.total});

  bool get isEmpty => buckets.every((b) => b.items.isEmpty);
}

class AttentionRepository {
  final OddjobzRpc _rpc;
  const AttentionRepository(this._rpc);

  /// Ordered (key → label) for the operator-action buckets the brain returns.
  static const _bucketOrder = <MapEntry<String, String>>[
    MapEntry('pending_quote', 'Pending quote'),
    MapEntry('pending_schedule', 'Pending schedule'),
    MapEntry('pending_invoice', 'Pending invoice'),
  ];

  /// Load the attention feed via `find attention`. Returns buckets in a fixed
  /// operator order; unknown extra buckets are appended after.
  Future<AttentionFeed> load() async {
    final raw = await _rpc.replEval('find attention');
    final obj = _decodeObject(raw);

    int total = (obj['total'] as num?)?.toInt() ?? 0;
    final seen = <String>{};
    final buckets = <AttentionBucket>[];

    for (final entry in _bucketOrder) {
      final list = obj[entry.key];
      seen.add(entry.key);
      buckets.add(
        AttentionBucket(
          key: entry.key,
          label: entry.value,
          items: _items(list),
        ),
      );
    }
    // Any other list-valued keys the brain adds later (forward-compatible).
    for (final e in obj.entries) {
      if (seen.contains(e.key) || e.value is! List) continue;
      buckets.add(
        AttentionBucket(
          key: e.key,
          label: _humanize(e.key),
          items: _items(e.value),
        ),
      );
    }
    if (total == 0) {
      total = buckets.fold(0, (n, b) => n + b.items.length);
    }
    return AttentionFeed(buckets: buckets, total: total);
  }

  static List<AttentionItem> _items(dynamic list) {
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => AttentionItem.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// The verb prints raw JSON (possibly with a trailing newline or stray
  /// prefix); extract the object span defensively.
  static Map<String, dynamic> _decodeObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw FormatException('find attention: no JSON object in output: $raw');
    }
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('find attention: output is not an object');
    }
    return decoded;
  }

  static String _humanize(String key) => key
      .replaceAll('_', ' ')
      .replaceFirstMapped(RegExp(r'^\w'), (m) => m.group(0)!.toUpperCase());
}

```
