---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/job.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.463795+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/job.dart

```dart
// Job — minimal Dart model for the REPL `find jobs` / `find job <id>`
// response.  Mirrors the subset of the mobile JobsRepository.Job that
// the operator PWA needs.

class Job {
  final String id;
  final String customerName;
  final String state;
  final String? cellId; // hex-64; present for v2+ rows
  final String? propertyAddress;
  final String? services;
  final String? workOrderNumber;
  final String? scheduledAt;
  final List<String> attachmentRefs;

  const Job({
    required this.id,
    required this.customerName,
    required this.state,
    this.cellId,
    this.propertyAddress,
    this.services,
    this.workOrderNumber,
    this.scheduledAt,
    this.attachmentRefs = const [],
  });

  factory Job.fromJson(Map<String, dynamic> j) {
    return Job(
      id: j['id'] as String? ?? j['_id'] as String? ?? '',
      customerName: j['customer_name'] as String? ?? '',
      state: j['state'] as String? ?? '',
      cellId: j['cellId'] as String?,
      propertyAddress: j['propertyAddress'] as String?,
      services: j['services'] as String?,
      workOrderNumber: j['workOrderNumber'] as String?,
      scheduledAt: j['scheduled_at'] as String?,
      attachmentRefs: _stringList(j['attachmentRefs'] ?? j['attachment_refs']),
    );
  }

  String get stateLabel {
    const labels = {
      'lead': 'lead',
      'qualified': 'qualified',
      'quoted': 'quoted',
      'scheduled': 'sched',
      'in_progress': 'on-site',
      'visited': 'visited',
      'completed': 'done',
      'invoiced': 'invoiced',
      'paid': 'paid',
      'closed': 'closed',
    };
    return labels[state] ?? state;
  }

  bool get isDone =>
      state == 'paid' || state == 'closed' || state == 'completed';
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item != null && item.toString().isNotEmpty) item.toString(),
  ];
}

```
