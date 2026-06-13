---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/repositories/jobs_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.118707+00:00
---

# apps/semantos/lib/src/repositories/jobs_repository.dart

```dart
/// jobs_repository.dart — job reads + FSM transitions over the unified WSS RPC
/// channel. Reads go through `cell.query("oddjobz.job.v2")` (the immune path —
/// the runtime-registry dispatch that sidesteps the legacy wss_wallet codegen
/// drop). FSM verbs go through `repl.eval` with the canonical command strings
/// the monolith used (jobs_repository.dart §FSM table).
library;

import '../rpc/brain_rpc_client.dart';
import 'job.dart';

class JobsRepository {
  final RpcCaller _rpc;

  /// The friendly typeHash alias the brain registers for job cells.
  static const String jobType = 'oddjobz.job.v2';

  JobsRepository(this._rpc);

  // ── Reads (cell.query) ───────────────────────────────────────────────────

  /// All jobs (optionally filtered by state). Returns [] when none.
  Future<List<Job>> findJobs({String? state}) async {
    final result = await _rpc.cellQuery(
      jobType,
      filter: state == null ? null : {'state': state},
    );
    final list = result['jobs'] as List<dynamic>? ?? const [];
    return list
        .map((e) => Job.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Single job by id. M1: filters client-side from the full set (owner-scoped
  /// server-side queries are a later phase). Returns null when absent.
  Future<Job?> findJob(String id) async {
    final jobs = await findJobs();
    for (final j in jobs) {
      if (j.id == id || j.cellId == id) return j;
    }
    return null;
  }

  /// Jobs grouped into the three operator sections (Home view).
  Future<Map<JobBucket, List<Job>>> findGrouped() async {
    final jobs = await findJobs();
    final grouped = <JobBucket, List<Job>>{
      JobBucket.needsAttention: [],
      JobBucket.active: [],
      JobBucket.recent: [],
      JobBucket.unknown: [],
    };
    for (final j in jobs) {
      grouped[j.bucket]!.add(j);
    }
    return grouped;
  }

  // ── FSM transitions (repl.eval) ──────────────────────────────────────────
  // Canonical command strings (monolith parity). Each returns the raw REPL
  // output; callers refresh the relevant view afterwards.

  Future<String> quoteJob(String id) => _rpc.replEval('quote job $id');

  Future<String> scheduleJob(String id, {DateTime? at}) {
    final suffix = at == null ? '' : ' --at ${at.toUtc().toIso8601String()}';
    return _rpc.replEval('schedule job $id$suffix');
  }

  Future<String> startJob(String id) => _rpc.replEval('start job $id');

  Future<String> completeJob(String id) => _rpc.replEval('complete job $id');

  Future<String> invoiceJob(String id, {int? totalCents}) {
    final suffix = totalCents == null ? '' : ' total_cents $totalCents';
    return _rpc.replEval('invoice job $id$suffix');
  }

  Future<String> markJobPaid(String id) => _rpc.replEval('mark job paid $id');

  Future<String> closeJob(String id) => _rpc.replEval('close job $id');
}

```
