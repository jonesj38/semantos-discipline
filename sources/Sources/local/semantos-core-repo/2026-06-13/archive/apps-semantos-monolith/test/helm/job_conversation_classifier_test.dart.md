---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/job_conversation_classifier_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.926484+00:00
---

# archive/apps-semantos-monolith/test/helm/job_conversation_classifier_test.dart

```dart
// RM-126 — tests for the on-device compression gradient.

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/helm/job_conversation_classifier.dart';

void main() {
  group('classifyJobMessage — note vs FSM-advance', () {
    test('plain note stays a note', () {
      final c = classifyJobMessage(
          'customer mentioned the back gate is usually locked', 'qualified');
      expect(c.kind, JobMessageKind.note);
      expect(c.actionKey, isNull);
    });

    test('empty / whitespace is a note', () {
      expect(classifyJobMessage('   ', 'lead').kind, JobMessageKind.note);
      expect(classifyJobMessage('', 'in_progress').kind, JobMessageKind.note);
    });

    test('advance verb from the matching state fires the one legal edge',
        () {
      final q = classifyJobMessage('go ahead and quote it', 'qualified');
      expect(q.kind, JobMessageKind.fsmAdvance);
      expect(q.actionKey, 'quote');
      expect(q.actionLabel, 'Quote');

      final done = classifyJobMessage('all done, job finished', 'in_progress');
      expect(done.kind, JobMessageKind.fsmAdvance);
      expect(done.actionKey, 'complete');

      final paid = classifyJobMessage('they paid this morning', 'invoiced');
      expect(paid.kind, JobMessageKind.fsmAdvance);
      expect(paid.actionKey, 'paid');

      final qual = classifyJobMessage('qualify this one', 'lead');
      expect(qual.actionKey, 'qualify');

      final close = classifyJobMessage('close it out', 'paid');
      expect(close.actionKey, 'close');
    });

    test('an advance verb that is not legal from this state is a note', () {
      // "paid" is only an edge from `invoiced`; from `lead` it is noise.
      expect(classifyJobMessage('they paid a deposit', 'lead').kind,
          JobMessageKind.note);
      // "start" is only legal from `scheduled`.
      expect(classifyJobMessage('we should start soon', 'qualified').kind,
          JobMessageKind.note);
    });

    test('terminal state never advances', () {
      expect(classifyJobMessage('close it', 'closed').kind,
          JobMessageKind.note);
    });

    test('word-boundary: substrings do not false-fire', () {
      // "paid" inside "unpaid"
      expect(classifyJobMessage('this is unpaid leave', 'invoiced').kind,
          JobMessageKind.note);
      // "start" inside "restarted"
      expect(classifyJobMessage('I restarted the router', 'scheduled').kind,
          JobMessageKind.note);
      // but the bare verb still fires
      expect(classifyJobMessage('start it', 'scheduled').actionKey, 'start');
    });

    test('case-insensitive', () {
      expect(classifyJobMessage('INVOICE THEM NOW', 'completed').actionKey,
          'invoice');
    });
  });
}

```
