---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/job_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.455690+00:00
---

# cartridges/oddjobz/experience/test/job_test.dart

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oddjobz_experience/src/operator/job.dart';

void main() {
  test('Job parses attachmentRefs from v2 job rows', () {
    final job = Job.fromJson({
      'id': 'job-1',
      'customer_name': 'Customer',
      'state': 'lead',
      'cellId': 'cell-abc',
      'attachmentRefs': ['att-1', 'att-2'],
    });

    expect(job.attachmentRefs, ['att-1', 'att-2']);
  });

  test('Job parses snake_case attachment_refs fallback', () {
    final job = Job.fromJson({
      'id': 'job-1',
      'attachment_refs': ['att-snake'],
    });

    expect(job.attachmentRefs, ['att-snake']);
  });
}

```
