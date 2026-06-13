---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/operator_jobs_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.464094+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/operator_jobs_repository.dart

```dart
/// operator_jobs_repository.dart — the oddjobz operator's job reads over the
/// unified channel. Backs the Home (significance sections) + Find tabs.
///
/// Reads go through the shell-native **`query <noun>`** primitive (→ cell.query
/// substrate), which returns the RAW canonical cell payload — the cell IS the
/// wire shape, no view-store translation layer. Because the raw job payload
/// carries only refs (`site_ref`, `customer_refs[].cell_id`), this repository
/// fetches jobs + sites + customers and **resolves the cell graph locally**
/// (job → its site's address, job → its point-of-contact's name) — i.e. the
/// PWA holds the cells and navigates them, mirroring the resolution the brain's
/// view-store used to do (RM-121).
library;

import 'dart:convert';

import 'oddjobz_rpc.dart';

/// A job row, resolved from its raw canonical cell + the site/customer cells
/// it references.
class OperatorJob {
  final String id; // = the job cell's content hash (cellHash)
  final String customerName;
  final String state;
  final String propertyAddress;
  final String description;
  final String? services;
  final String? workOrderNumber;
  final String scheduledAt;
  final String dueDate;
  final bool hasPhotos;
  final int photoCount;

  const OperatorJob({
    required this.id,
    required this.customerName,
    required this.state,
    required this.propertyAddress,
    required this.description,
    this.services,
    this.workOrderNumber,
    this.scheduledAt = '',
    this.dueDate = '',
    this.hasPhotos = false,
    this.photoCount = 0,
  });

  /// Build from a raw canonical job cell payload, resolving `site_ref` →
  /// address and `customer_refs[]` → point-of-contact name against the
  /// (cellHash → cell) indexes of all sites + customers.
  factory OperatorJob.fromRawCell(
    Map<String, dynamic> j,
    Map<String, Map<String, dynamic>> sites,
    Map<String, Map<String, dynamic>> customers,
  ) {
    // site_ref → the site cell's address.
    var propertyAddress = '';
    final siteRef = j['site_ref'];
    if (siteRef is String) {
      final site = sites[siteRef];
      if (site != null) {
        propertyAddress =
            (site['normalized_address'] ?? site['raw_address'] ?? '')
                .toString();
      }
    }

    // services array → joined display string.
    String? services;
    final sv = j['services'];
    if (sv is List && sv.isNotEmpty) {
      services = sv.map((e) => e.toString()).join(', ');
    }

    final pictureCount = (j['picture_count'] is num)
        ? (j['picture_count'] as num).toInt()
        : 0;

    return OperatorJob(
      id: (j['cellHash'] ?? '').toString(),
      customerName: _resolveContactName(j, customers),
      state: (j['state'] ?? 'lead').toString(),
      propertyAddress: propertyAddress,
      description: (j['summary'] ?? '').toString(),
      services: services,
      workOrderNumber: j['work_order_number']?.toString(),
      dueDate: (j['due_date'] ?? '').toString(),
      hasPhotos: j['has_pictures'] == true || pictureCount > 0,
      photoCount: pictureCount,
    );
  }

  /// Pick the operator's point-of-contact from `customer_refs` and resolve its
  /// name from the referenced customer cell. Rule (RM-121): the `primary:true`
  /// tenant, else the first tenant, else the first agent/property_manager, else
  /// the first ref. Falls back to the job's `display_name` (minus a trailing
  /// " (role)") when no name resolves.
  static String _resolveContactName(
    Map<String, dynamic> j,
    Map<String, Map<String, dynamic>> customers,
  ) {
    final refs = j['customer_refs'];
    final fallback = _stripRole((j['display_name'] ?? '').toString());
    if (refs is! List || refs.isEmpty) return fallback;

    final typed = refs.whereType<Map>().map((r) => r.cast<String, dynamic>());
    Map<String, dynamic>? pick;
    for (final r in typed) {
      if (r['primary'] == true && _roleOf(r, customers) == 'tenant') {
        pick = r;
        break;
      }
    }
    pick ??= _firstWhere(typed, (r) => _roleOf(r, customers) == 'tenant');
    pick ??= _firstWhere(typed, (r) => _isAgentish(_roleOf(r, customers)));
    pick ??= typed.isNotEmpty ? typed.first : null;

    final cellId = pick?['cell_id'];
    if (cellId is String) {
      final name = (customers[cellId]?['name'] ?? '').toString();
      if (name.isNotEmpty) return name;
    }
    return fallback;
  }

  /// Role of a customer_ref: prefer the referenced customer cell's `role`,
  /// else the ref's own `role`.
  static String _roleOf(
    Map<String, dynamic> ref,
    Map<String, Map<String, dynamic>> customers,
  ) {
    final cellId = ref['cell_id'];
    if (cellId is String) {
      final r = customers[cellId]?['role'];
      if (r is String && r.isNotEmpty) return r;
    }
    return (ref['role'] ?? '').toString();
  }

  static bool _isAgentish(String role) =>
      role == 'agent' || role == 'property_manager' || role == 'pm';

  static Map<String, dynamic>? _firstWhere(
    Iterable<Map<String, dynamic>> it,
    bool Function(Map<String, dynamic>) test,
  ) {
    for (final r in it) {
      if (test(r)) return r;
    }
    return null;
  }

  /// Strip a trailing " (role)" annotation from a display name.
  static String _stripRole(String s) {
    final i = s.lastIndexOf(' (');
    return (i > 0) ? s.substring(0, i) : s;
  }
}

/// Home's three significance buckets — covers all 13 FSM states so nothing
/// falls through unseen (mirrors the monolith home_node grouping).
class JobSignificance {
  final List<OperatorJob> needsAttention; // lead..quoted, completed
  final List<OperatorJob> active; // visit_scheduled, scheduled, in_progress
  final List<OperatorJob> recent; // invoiced, paid, closed
  const JobSignificance(this.needsAttention, this.active, this.recent);

  static const _active = {'visit_scheduled', 'scheduled', 'in_progress'};
  static const _recent = {'invoiced', 'paid', 'closed'};

  factory JobSignificance.from(List<OperatorJob> jobs) {
    final n = <OperatorJob>[], a = <OperatorJob>[], r = <OperatorJob>[];
    for (final j in jobs) {
      if (_active.contains(j.state)) {
        a.add(j);
      } else if (_recent.contains(j.state)) {
        r.add(j);
      } else {
        n.add(j);
      }
    }
    return JobSignificance(n, a, r);
  }
}

class OperatorJobsRepository {
  final OddjobzRpc _rpc;
  const OperatorJobsRepository(this._rpc);

  /// All jobs for Home — fetched as raw canonical cells and resolved against
  /// the site + customer cells they reference (one `query` per type, joined
  /// locally). The PWA holds the cell graph; the brain does no resolution.
  Future<List<OperatorJob>> findJobs() async {
    final fetched = await Future.wait([
      findEntities('jobs'),
      findEntities('sites'),
      findEntities('customers'),
    ]);
    final siteIndex = _indexByCellHash(fetched[1]);
    final custIndex = _indexByCellHash(fetched[2]);
    return fetched[0]
        .map((j) => OperatorJob.fromRawCell(j, siteIndex, custIndex))
        .toList(growable: false);
  }

  /// Generic substrate read: `query <noun>` → the raw canonical cells of that
  /// type as maps. Cartridge-agnostic — any registered cell type is queryable.
  Future<List<Map<String, dynamic>>> findEntities(String noun) async {
    final raw = await _rpc.replEval('query $noun');
    return _decodeList(raw)
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList(growable: false);
  }

  /// Index raw cell rows by their `cellHash` (the content-addressed identity
  /// other cells' refs point at).
  static Map<String, Map<String, dynamic>> _indexByCellHash(
    List<Map<String, dynamic>> rows,
  ) {
    final m = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final h = r['cellHash'];
      if (h is String) m[h] = r;
    }
    return m;
  }

  static List<dynamic> _decodeList(String raw) {
    final s = raw.indexOf('[');
    final e = raw.lastIndexOf(']');
    if (s < 0 || e <= s) return const [];
    final d = jsonDecode(raw.substring(s, e + 1));
    return d is List ? d : const [];
  }
}

```
