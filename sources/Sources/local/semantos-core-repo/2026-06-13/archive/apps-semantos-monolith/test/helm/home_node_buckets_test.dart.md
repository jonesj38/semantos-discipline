---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/helm/home_node_buckets_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.927893+00:00
---

# archive/apps-semantos-monolith/test/helm/home_node_buckets_test.dart

```dart
// Regression guard for the §O4/JobFSM drift class (2026-05-18).
//
// HomeNode groups jobs into 3 Home sections by hardcoded state sets.
// Before this fix those sets were the pre-remodel §O4-linear states,
// so post-remodel jobs (qualified / authorized / visit_*) matched NO
// section and silently vanished from the operator's Home while still
// appearing in `find` — the exact field-reported symptom (1 visible
// of 6). This test asserts EVERY canonical 13-state Job-FSM state maps
// to a real Home section, so a shipped state can never again fall
// through, plus the operator-approved placement.

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/helm/home_node.dart';

void main() {
  group('HomeNode bucket coverage — 13-state remodel faithfulness', () {
    test('every canonical Job-FSM state maps to a non-null HomeSection', () {
      for (final state in kCanonicalJobFsmStates) {
        expect(
          homeSectionForState(state),
          isNotNull,
          reason:
              '"$state" is a shipped Job-FSM state but maps to NO Home '
              'section — it would silently vanish from the operator Home '
              '(the §O4-drift bug). Add it to a bucket in home_node.dart.',
        );
      }
      // Sanity: exactly the 13 canonical states (catches a state added
      // to the FSM but not mirrored here — re-drift in the other
      // direction).
      expect(kCanonicalJobFsmStates.length, 13);
    });

    test('operator-approved placement (SD2/JobFSM-faithful)', () {
      // Needs attention — every state awaiting an operator step.
      for (final s in [
        'lead',
        'qualified',
        'authorized',
        'visit_pending',
        'visited',
        'quoted',
        'completed',
      ]) {
        expect(homeSectionForState(s), HomeSection.attention, reason: s);
      }
      // Active — work / visit in flight.
      for (final s in ['visit_scheduled', 'scheduled', 'in_progress']) {
        expect(homeSectionForState(s), HomeSection.active, reason: s);
      }
      // Recent — closed-out lifecycle tail.
      for (final s in ['invoiced', 'paid', 'closed']) {
        expect(homeSectionForState(s), HomeSection.recent, reason: s);
      }
    });

    test('the field-reported invisible states are now visible', () {
      // Derek/Marcus/Jenny were `qualified`; INCR2 was `authorized` —
      // all rendered nowhere pre-fix.
      expect(homeSectionForState('qualified'), HomeSection.attention);
      expect(homeSectionForState('authorized'), HomeSection.attention);
      // An unknown/garbage state still yields null (no false bucket).
      expect(homeSectionForState('not_a_state'), isNull);
    });
  });
}

```
