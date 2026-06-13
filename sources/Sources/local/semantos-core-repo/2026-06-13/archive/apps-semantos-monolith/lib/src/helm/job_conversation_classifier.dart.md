---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/job_conversation_classifier.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.885568+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/job_conversation_classifier.dart

```dart
// RM-126 — ② conversation box → intent / FSM (edge-classify path).
//
// Operator's mental model (verbatim): "the compression gradient should
// understand if its just a note about the job, which is applied as a
// patch, or it requires flipping the state of the FSM. Either way
// stored as a log of conversation patches."
//
// The full triage/conversation-patch model already exists server-side
// in runtime/intent (handleMessage → conversation patch → triage
// NO_INTENT|PROPOSES|RATIFIES). But the brain's /api/v1/voice-extract
// shellout is still a Phase-1 placeholder that never persists a patch
// or moves the FSM, and wiring the real server path would require the
// forked bun child to call back into the brain job store — the exact
// self-call shape that caused the 2026-05-18 deadlock outage.
//
// So per the operator's chosen architecture (edge-classify + live
// repl): this is the "compression gradient" — a pure, deterministic,
// no-AI classifier that runs on-device and decides whether a typed
// message is a plain note (→ patch only) or a request to advance THIS
// job's FSM (→ the already-live transition the §O4 table allows from
// the current state, the same proven path the action buttons use).
// Intelligence stays at the edge (no LLM in the substrate).
//
// Every message is logged as a conversation patch either way; the
// caller appends the turn (and, on an advance, an outcome turn) to the
// job-linked ConversationCell.

/// What the gradient decided a message is.
enum JobMessageKind {
  /// Just a note about the job. Patch only — no FSM change.
  note,

  /// A request to advance the job's FSM. The single transition the
  /// canonical §O4 table allows from the current state runs through
  /// the already-live JobsRepository verb.
  fsmAdvance,
}

class JobMessageClassification {
  final JobMessageKind kind;

  /// Operator-readable action label for [JobMessageKind.fsmAdvance]
  /// (matches the action-button labels: 'Qualify', 'Quote',
  /// 'Schedule', 'Start', 'Complete', 'Invoice', 'Mark Paid', 'Close',
  /// 'Set visit', 'Visited'). Null for a note.
  final String? actionLabel;

  /// Stable key the screen maps to a JobsRepository call. Null for a
  /// note.
  final String? actionKey;

  const JobMessageClassification.note()
      : kind = JobMessageKind.note,
        actionLabel = null,
        actionKey = null;

  const JobMessageClassification.advance(this.actionLabel, this.actionKey)
      : kind = JobMessageKind.fsmAdvance;
}

/// One advance edge per state — mirrors job_detail_screen's
/// `_actionsForState` (itself realigned to the shipped 13-state Job
/// FSM in RM-123). Keeping the trigger set state-keyed means the
/// gradient can only ever propose the *one* transition the FSM
/// actually allows from here, so a recognised verb can never fire an
/// illegal edge ("not in FSM table"). Anything else is a note.
class _Edge {
  final String actionKey;
  final String actionLabel;
  final List<String> triggers;
  const _Edge(this.actionKey, this.actionLabel, this.triggers);
}

const Map<String, _Edge> _edgeForState = {
  'lead': _Edge('qualify', 'Qualify', [
    'qualify', 'qualified', 'real lead', 'legit', 'genuine', 'is real',
    'worth quoting', 'good lead',
  ]),
  'qualified': _Edge('quote', 'Quote', [
    'quote', 'quoted', 'send a quote', 'needs a quote', 'price it',
    'price up', 'put a price', 'get a quote out', 'quote it',
  ]),
  'visited': _Edge('quote', 'Quote', [
    'quote', 'quoted', 'send a quote', 'needs a quote', 'price it',
    'price up', 'put a price', 'get a quote out', 'quote it',
  ]),
  'quoted': _Edge('schedule', 'Schedule', [
    'schedule', 'scheduled', 'book it', 'book in', 'book them in',
    'schedule it', 'lock it in', 'put it in the diary',
  ]),
  'authorized': _Edge('schedule', 'Schedule', [
    'schedule', 'scheduled', 'book it', 'book in', 'book them in',
    'schedule it', 'lock it in', 'put it in the diary',
  ]),
  'visit_pending': _Edge('setVisit', 'Set visit', [
    'set visit', 'schedule the visit', 'visit scheduled', 'book the visit',
    'book a visit', 'arrange the visit',
  ]),
  'visit_scheduled': _Edge('visited', 'Visited', [
    'visited', 'did the visit', 'attended', 'been out', 'went out',
    'site visit done', 'visit done', 'had a look',
  ]),
  'scheduled': _Edge('start', 'Start', [
    'start', 'started', 'starting', 'on site', 'begin', 'began',
    'kick off', 'kicked off', 'commenced', 'underway',
  ]),
  'in_progress': _Edge('complete', 'Complete', [
    'done', 'complete', 'completed', 'finished', 'wrapped up',
    'all done', 'job done', 'work done', 'finished up',
  ]),
  'completed': _Edge('invoice', 'Invoice', [
    'invoice', 'invoiced', 'bill them', 'send invoice', 'send the invoice',
    'raise an invoice', 'bill it',
  ]),
  'invoiced': _Edge('paid', 'Mark Paid', [
    'paid', 'payment received', 'they paid', 'mark paid', 'money in',
    'got paid', 'has paid', 'settled', 'payment in',
  ]),
  'paid': _Edge('close', 'Close', [
    'close', 'closed', 'close it out', 'close it off', 'wrap up the file',
    'all finished', 'finalise', 'finalize',
  ]),
  // 'closed' — terminal; nothing to advance. Always a note.
};

/// The on-device compression gradient.
///
/// Returns [JobMessageKind.fsmAdvance] only when the trimmed message
/// expresses the single FSM advance available from [fromState];
/// everything else is a plain [JobMessageKind.note]. Deterministic and
/// side-effect free so it unit-tests cleanly and never surprises the
/// operator — a misread at worst yields a patch-only note (a
/// recognised verb can never fire an illegal edge because the trigger
/// set is state-keyed to the one legal transition).
JobMessageClassification classifyJobMessage(String text, String fromState) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return const JobMessageClassification.note();

  final edge = _edgeForState[fromState];
  if (edge == null) return const JobMessageClassification.note();

  for (final trigger in edge.triggers) {
    if (_containsPhrase(t, trigger)) {
      return JobMessageClassification.advance(
        edge.actionLabel,
        edge.actionKey,
      );
    }
  }
  return const JobMessageClassification.note();
}

/// Word-boundary-ish phrase match: the phrase must appear delimited by
/// start/end or a non-letter so "started" doesn't fire on "restarted
/// the router" and "paid" doesn't fire inside "unpaid leave". Multi-
/// word triggers ("send a quote") match as a contiguous substring with
/// the same boundary rule on each end.
bool _containsPhrase(String haystack, String phrase) {
  var from = 0;
  while (true) {
    final i = haystack.indexOf(phrase, from);
    if (i < 0) return false;
    final beforeOk = i == 0 || !_isLetter(haystack.codeUnitAt(i - 1));
    final endIdx = i + phrase.length;
    final afterOk = endIdx == haystack.length ||
        !_isLetter(haystack.codeUnitAt(endIdx));
    if (beforeOk && afterOk) return true;
    from = i + 1;
  }
}

bool _isLetter(int c) =>
    (c >= 0x61 && c <= 0x7a) || (c >= 0x41 && c <= 0x5a);

```
