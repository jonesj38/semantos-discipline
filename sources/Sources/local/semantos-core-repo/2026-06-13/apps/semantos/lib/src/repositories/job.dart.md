---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/repositories/job.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.118426+00:00
---

# apps/semantos/lib/src/repositories/job.dart

```dart
/// job.dart — operator Job model for the rebuilt oddjobz surface.
///
/// Mirrors the fields the brain's `oddjobz.job.v2` cell decoder emits in the
/// `cell.query` collection envelope (`{"jobs":[…]}`): customer_name, state,
/// cellId, propertyAddress, services, workOrderNumber, scheduled_at. Owned by
/// apps/semantos (the rebuild subsumes cartridges/oddjobz/experience). A fully
/// manifest-driven generic renderer may later consume raw maps instead, but the
/// typed model keeps the FSM grouping/repository logic readable + testable.
library;

/// Canonical job FSM states (brain `oddjobz.job.v2`), grouped by operator
/// action-significance — mirrors the monolith HomeNode sections.
enum JobBucket { needsAttention, active, recent, unknown }

class Job {
  final String id;
  final String customerName;
  final String state;
  final String? cellId; // hex-64; present for v2+ rows
  final String? propertyAddress;
  final String? services;
  final String? workOrderNumber;
  final String? scheduledAt;

  const Job({
    required this.id,
    required this.customerName,
    required this.state,
    this.cellId,
    this.propertyAddress,
    this.services,
    this.workOrderNumber,
    this.scheduledAt,
  });

  factory Job.fromJson(Map<String, dynamic> j) => Job(
        id: j['id'] as String? ?? j['_id'] as String? ?? '',
        customerName: j['customer_name'] as String? ?? '',
        state: j['state'] as String? ?? '',
        cellId: j['cellId'] as String?,
        propertyAddress: j['propertyAddress'] as String?,
        services: j['services'] as String?,
        workOrderNumber: j['workOrderNumber'] as String?,
        scheduledAt: j['scheduled_at'] as String?,
      );

  // Section membership mirrors the monolith HomeNode grouping.
  static const _needsAttention = {
    'lead', 'qualified', 'authorized', 'visit_pending', 'visited', 'quoted', 'completed',
  };
  static const _active = {'visit_scheduled', 'scheduled', 'in_progress'};
  static const _recent = {'invoiced', 'paid', 'closed'};

  JobBucket get bucket {
    if (_needsAttention.contains(state)) return JobBucket.needsAttention;
    if (_active.contains(state)) return JobBucket.active;
    if (_recent.contains(state)) return JobBucket.recent;
    return JobBucket.unknown;
  }

  bool get isDone => state == 'paid' || state == 'closed' || state == 'completed';
}

```
