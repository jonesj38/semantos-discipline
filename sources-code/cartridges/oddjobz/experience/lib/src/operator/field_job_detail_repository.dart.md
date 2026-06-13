---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/field_job_detail_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.462021+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/field_job_detail_repository.dart

```dart
/// job_detail_repository.dart — a single job's detail over the unified WSS RPC
/// channel: metadata + FSM transitions + the per-job conversation thread.
///
/// All three ride `repl.eval` (the oddjobz cartridge verbs, reachable over the
/// channel since fix(brain): attach cartridge REPL verb registry):
///   - `find job <id>`            → job metadata
///   - `<verb> job <id>`          → FSM transition (quote/schedule/…)
///   - `find turns job <id>`      → conversation turns (Postgres via bun)
library;

import 'dart:convert';

import 'oddjobz_rpc.dart';

/// A job's current detail (the cartridge-store projection `find job` returns).
class JobDetail {
  final String id;
  final String customerName;
  final String state;
  final String propertyAddress;
  final String description;
  final String? services;
  final String? workOrderNumber;
  final String scheduledAt;

  const JobDetail({
    required this.id,
    required this.customerName,
    required this.state,
    required this.propertyAddress,
    required this.description,
    this.services,
    this.workOrderNumber,
    this.scheduledAt = '',
  });

  factory JobDetail.fromJson(Map<String, dynamic> j) => JobDetail(
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

/// One conversation turn (the per-job message thread).
class ConvTurn {
  final String surface; // widget | email | voice | sms | …
  final String role; // operator | ai | external | …
  final String direction; // inbound | outbound
  final String body;
  final String outboundState; // proposed | approved | sent | …
  final String createdAt;

  const ConvTurn({
    required this.surface,
    required this.role,
    required this.direction,
    required this.body,
    required this.outboundState,
    required this.createdAt,
  });

  factory ConvTurn.fromJson(Map<String, dynamic> j) => ConvTurn(
    surface: (j['surface'] ?? '').toString(),
    role: (j['participantRole'] ?? j['role'] ?? '').toString(),
    direction: (j['direction'] ?? '').toString(),
    body: (j['bodyText'] ?? j['body'] ?? '').toString(),
    outboundState: (j['outboundState'] ?? '').toString(),
    createdAt: (j['createdAt'] ?? j['created_at'] ?? '').toString(),
  );
}

/// Result of fetching the conversation thread: either turns, or a reason the
/// thread is unavailable (e.g. the job predates entity-anchoring → no cellId).
class TurnsResult {
  final List<ConvTurn> turns;
  final String? unavailableReason;
  const TurnsResult(this.turns, {this.unavailableReason});
  bool get available => unavailableReason == null;
}

class JobDetailRepository {
  final OddjobzRpc _rpc;
  const JobDetailRepository(this._rpc);

  /// `find job <id>` → the job's current metadata.
  Future<JobDetail> load(String jobId) async {
    final raw = await _rpc.replEval('find job $jobId');
    return JobDetail.fromJson(_decodeObject(raw));
  }

  /// `find turns job <id>` → conversation turns. The verb prints a plain-text
  /// hint (not JSON) when the job has no cellId to anchor turns; surface that
  /// as `unavailableReason` rather than throwing.
  Future<TurnsResult> turns(String jobId) async {
    final raw = (await _rpc.replEval('find turns job $jobId')).trim();
    final start = raw.indexOf('[');
    if (start < 0) {
      // Not a JSON array → the verb's hint (e.g. "has no cellId").
      return TurnsResult(const [], unavailableReason: _firstLine(raw));
    }
    final end = raw.lastIndexOf(']');
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! List) return const TurnsResult([]);
    final turns = decoded
        .whereType<Map>()
        .map((m) => ConvTurn.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
    return TurnsResult(turns);
  }

  /// Dispatch an FSM transition verb (`quote`/`schedule`/`start`/`complete`/
  /// `invoice`/`mark-paid`/`close`) against the job. Returns the verb's raw
  /// output line for surfacing to the operator.
  Future<String> transition(String verb, String jobId) async =>
      transitionCommand('$verb job $jobId');

  Future<String> transitionCommand(String command) async {
    final out = await _rpc.replEval(command);
    return _firstLine(out.trim());
  }

  static Map<String, dynamic> _decodeObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw FormatException('find job: no JSON object in output: $raw');
    }
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('find job: output is not an object');
    }
    return decoded;
  }

  static String _firstLine(String s) {
    final i = s.indexOf('\n');
    return i < 0 ? s : s.substring(0, i);
  }
}

/// The canonical oddjobz job FSM — ordered pipeline + operator-facing actions.
/// Mirrors cartridges/oddjobz/brain/src/state-machines/job-fsm.ts.
class JobFsm {
  static const stages = <String>[
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
  ];

  static const labels = <String, String>{
    'lead': 'lead',
    'qualified': 'qualified',
    'visit_pending': 'visit needed',
    'visit_scheduled': 'visit booked',
    'visited': 'visited',
    'quoted': 'quoted',
    'authorized': 'authorized',
    'scheduled': 'scheduled',
    'in_progress': 'on-site',
    'completed': 'done',
    'invoiced': 'invoiced',
    'paid': 'paid',
    'closed': 'closed',
  };

  static const actionsByState = <String, List<JobFsmAction>>{
    'lead': [
      JobFsmAction(
        label: 'Qualify ROM',
        verb: 'qualify',
        toState: 'qualified',
        sheet: JobActionSheetKind.none,
      ),
      JobFsmAction(
        label: 'Authorize WO',
        verb: 'authorize',
        toState: 'authorized',
        sheet: JobActionSheetKind.none,
      ),
    ],
    'qualified': [
      JobFsmAction(
        label: 'Book site visit',
        verb: 'visit',
        toState: 'visit_pending',
        sheet: JobActionSheetKind.visitScheduler,
      ),
      JobFsmAction(
        label: 'Quote from ROM',
        verb: 'quote',
        toState: 'quoted',
        sheet: JobActionSheetKind.quoteTemplate,
        cap: 'cap.oddjobz.quote',
      ),
      JobFsmAction(
        label: 'Authorize WO',
        verb: 'authorize',
        toState: 'authorized',
        sheet: JobActionSheetKind.none,
      ),
    ],
    'visit_pending': [
      JobFsmAction(
        label: 'Lock visit time',
        verb: 'schedule-visit',
        toState: 'visit_scheduled',
        sheet: JobActionSheetKind.visitScheduler,
      ),
    ],
    'visit_scheduled': [
      JobFsmAction(
        label: 'Mark visited',
        verb: 'complete-visit',
        toState: 'visited',
        sheet: JobActionSheetKind.none,
      ),
    ],
    'visited': [
      JobFsmAction(
        label: 'Build quote',
        verb: 'quote',
        toState: 'quoted',
        sheet: JobActionSheetKind.quoteTemplate,
        cap: 'cap.oddjobz.quote',
      ),
    ],
    'quoted': [
      JobFsmAction(
        label: 'Schedule work',
        verb: 'schedule',
        toState: 'scheduled',
        sheet: JobActionSheetKind.visitScheduler,
        cap: 'cap.oddjobz.dispatch',
      ),
    ],
    'authorized': [
      JobFsmAction(
        label: 'Schedule work',
        verb: 'schedule',
        toState: 'scheduled',
        sheet: JobActionSheetKind.visitScheduler,
        cap: 'cap.oddjobz.dispatch',
      ),
    ],
    'scheduled': [
      JobFsmAction(
        label: 'Start visit',
        verb: 'start',
        toState: 'in_progress',
        sheet: JobActionSheetKind.none,
        principal: 'service',
      ),
    ],
    'in_progress': [
      JobFsmAction(
        label: 'Mark done',
        verb: 'complete',
        toState: 'completed',
        sheet: JobActionSheetKind.none,
      ),
    ],
    'completed': [
      JobFsmAction(
        label: 'Create invoice',
        verb: 'invoice',
        toState: 'invoiced',
        sheet: JobActionSheetKind.invoiceTemplate,
        cap: 'cap.oddjobz.invoice',
      ),
    ],
    'invoiced': [
      JobFsmAction(
        label: 'Mark paid',
        verb: 'mark-paid',
        toState: 'paid',
        sheet: JobActionSheetKind.none,
        principal: 'service',
      ),
    ],
    'paid': [
      JobFsmAction(
        label: 'Close job',
        verb: 'close',
        toState: 'closed',
        sheet: JobActionSheetKind.none,
        cap: 'cap.oddjobz.close',
      ),
    ],
  };

  static List<JobFsmAction> actionsFrom(String state) =>
      actionsByState[state] ?? const [];

  static int indexOf(String state) => stages.indexOf(state);

  static String labelFor(String state) =>
      labels[state] ?? state.replaceAll('_', ' ');
}

enum JobActionSheetKind { none, visitScheduler, quoteTemplate, invoiceTemplate }

class JobFsmAction {
  final String label;
  final String verb;
  final String toState;
  final JobActionSheetKind sheet;
  final String principal;
  final String? cap;

  const JobFsmAction({
    required this.label,
    required this.verb,
    required this.toState,
    required this.sheet,
    this.principal = 'operator',
    this.cap,
  });

  /// Canonical generic REPL transition command registered by
  /// `oddjobz_repl_verbs.zig`. Prefer this over legacy sugar aliases so the
  /// PWA can reach every 13-state edge, including visit_* and authorized.
  String commandFor(String jobId) {
    final capArg = cap == null ? '' : ' --cap $cap';
    return 'transition job $jobId $toState --principal $principal$capArg';
  }
}

```
