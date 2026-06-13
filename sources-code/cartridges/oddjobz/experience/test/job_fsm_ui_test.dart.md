---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/job_fsm_ui_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.458079+00:00
---

# cartridges/oddjobz/experience/test/job_fsm_ui_test.dart

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oddjobz_experience/src/operator/field_job_detail_repository.dart';

void main() {
  test('JobFsm exposes the canonical 13-state OddJobz pipeline', () {
    expect(JobFsm.stages, const [
      'lead',
      'qualified',
      'visit_pending',
      'visit_scheduled',
      'visited',
      'quoted',
      'authorized',
      'scheduled',
      'in_progress',
      'completed',
      'invoiced',
      'paid',
      'closed',
    ]);
  });

  test('qualified state exposes visit, quote, and authorize branches', () {
    final actions = JobFsm.actionsFrom('qualified');

    expect(actions.map((a) => a.toState), [
      'visit_pending',
      'quoted',
      'authorized',
    ]);
    expect(actions[0].sheet, JobActionSheetKind.visitScheduler);
    expect(actions[1].sheet, JobActionSheetKind.quoteTemplate);
    expect(actions[2].sheet, JobActionSheetKind.none);
  });

  test(
    'template sheets are attached to visit, quote, and invoice transitions',
    () {
      expect(
        JobFsm.actionsFrom('visit_pending').single.sheet,
        JobActionSheetKind.visitScheduler,
      );
      expect(
        JobFsm.actionsFrom('visited').single.sheet,
        JobActionSheetKind.quoteTemplate,
      );
      expect(
        JobFsm.actionsFrom('completed').single.sheet,
        JobActionSheetKind.invoiceTemplate,
      );
    },
  );

  test('actions emit canonical generic transition job commands', () {
    final quote = JobFsm.actionsFrom('visited').single;
    expect(
      quote.commandFor('job-1'),
      'transition job job-1 quoted --principal operator --cap cap.oddjobz.quote',
    );

    final start = JobFsm.actionsFrom('scheduled').single;
    expect(
      start.commandFor('job-1'),
      'transition job job-1 in_progress --principal service',
    );

    final close = JobFsm.actionsFrom('paid').single;
    expect(
      close.commandFor('job-1'),
      'transition job job-1 closed --principal operator --cap cap.oddjobz.close',
    );
  });
}

```
