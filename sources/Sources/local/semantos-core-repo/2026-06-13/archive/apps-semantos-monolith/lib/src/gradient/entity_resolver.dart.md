---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/gradient/entity_resolver.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.876972+00:00
---

# archive/apps-semantos-monolith/lib/src/gradient/entity_resolver.dart

```dart
// Wave 9 PWA — entity resolver. Producer-side glue between a free-text
// transcript (or extractor-emitted summary/taxonomy.where) and the
// operator's local list of active jobs/customers.
//
// Why this exists: the cell that landed on rbs had
// `intent_taxonomy_json.where = "Yellow Wood Court"` lifted verbatim
// from the transcript — but the brain side never bound it to the
// actual job at "16 Yellowood Cl, Tewantin". The producer has the
// active-jobs cache locally (JobsRepository.loadCached), so the
// resolver matches transcript fragments to that list BEFORE the
// cell is minted. The result populates `intent.target.jobId` /
// `target.customerId` so downstream consumers don't have to re-derive
// entity identity from free text.
//
// Heuristic (light + deterministic, no LLM):
//   1. Tokenize transcript + summary + taxonomy.where, lowercase,
//      drop tokens shorter than 4 bytes (mirrors the brain router's
//      `findSingleMatchingJob` heuristic for parity).
//   2. For each active Job, score it as the count of distinct
//      tokens that appear in (customerName ∪ propertyAddress)
//      lowercase. Bonus for exact address-fragment matches.
//   3. Pick the single highest-scoring job iff its score > 0 AND it
//      beats the runner-up by at least 1 (no near-ties — ambiguous
//      transcripts stay unresolved). Below threshold → unresolved.
//   4. Customer id is taken from the matched job's primary customer
//      ref when available.
//
// The resolver returns a typed [ResolutionResult] so the trace can
// render `target_resolved` / `target_unresolved` events explicitly —
// the user sees WHICH job (or why no match) without leaving the PWA.

import '../repl/jobs_repository.dart' show Job;

/// Result of a single resolution pass over the active jobs list.
sealed class ResolutionResult {
  const ResolutionResult();
}

/// A unique high-confidence match was found.
class ResolutionMatched extends ResolutionResult {
  final String jobId;
  final String? customerId;
  /// Score of the winning candidate.
  final int score;
  /// Score of the second-best candidate (0 if no runner-up). Used to
  /// surface near-tie warnings in the trace even though the match
  /// is accepted.
  final int runnerUpScore;
  /// Short human-readable explanation: "matched job &lt;id&gt; on
  /// tokens [wattle, street]". Goes into the inspector detail line.
  final String reason;
  const ResolutionMatched({
    required this.jobId,
    required this.customerId,
    required this.score,
    required this.runnerUpScore,
    required this.reason,
  });
}

/// No active job could be matched OR the match was ambiguous.
class ResolutionUnresolved extends ResolutionResult {
  /// One of: 'no_active_jobs', 'no_match', 'ambiguous_match',
  /// 'no_tokens'.
  final String code;
  final String reason;
  const ResolutionUnresolved({required this.code, required this.reason});
}

class EntityResolver {
  EntityResolver({this.minTokenLength = 4, this.minWinningMargin = 1});

  /// Tokens shorter than this are dropped from both transcript and
  /// candidate fields. Matches the brain router's heuristic so a
  /// match here implies a match there (assuming the same jobs list).
  final int minTokenLength;

  /// The winning candidate's score must exceed the runner-up's by at
  /// least this much. 1 = strict — near-ties fail rather than risk
  /// a wrong-job mutation.
  final int minWinningMargin;

  ResolutionResult resolve({
    required Iterable<Job> activeJobs,
    String? transcript,
    String? summary,
    String? taxonomyWhere,
  }) {
    final jobs = activeJobs.toList(growable: false);
    if (jobs.isEmpty) {
      return const ResolutionUnresolved(
        code: 'no_active_jobs',
        reason: 'producer has no cached jobs to match against',
      );
    }

    final tokens = _extractTokens([transcript, summary, taxonomyWhere]);
    if (tokens.isEmpty) {
      return const ResolutionUnresolved(
        code: 'no_tokens',
        reason: 'no resolvable tokens in transcript/summary/where',
      );
    }

    // Score every job.
    final scored = <_Scored>[];
    for (final job in jobs) {
      final corpus = _normalise([
        job.customerName,
        job.propertyAddress,
      ]);
      if (corpus.isEmpty) continue;
      final matched = <String>{};
      for (final t in tokens) {
        if (corpus.contains(t)) matched.add(t);
      }
      if (matched.isNotEmpty) {
        scored.add(_Scored(job: job, score: matched.length, matched: matched));
      }
    }

    if (scored.isEmpty) {
      return const ResolutionUnresolved(
        code: 'no_match',
        reason: 'no job\'s customer name or address shared any tokens',
      );
    }

    scored.sort((a, b) => b.score - a.score);
    final winner = scored.first;
    final runnerUp = scored.length > 1 ? scored[1].score : 0;
    if (winner.score - runnerUp < minWinningMargin) {
      return ResolutionUnresolved(
        code: 'ambiguous_match',
        reason:
            'top two jobs tied (score=${winner.score} vs $runnerUp) — '
            'refusing to guess. Tokens: ${winner.matched.join(", ")}',
      );
    }

    final primaryCustomerId = _primaryCustomerId(winner.job);
    return ResolutionMatched(
      jobId: winner.job.id,
      customerId: primaryCustomerId,
      score: winner.score,
      runnerUpScore: runnerUp,
      reason:
          'matched job ${winner.job.id} on '
          'tokens [${winner.matched.join(", ")}]',
    );
  }

  /// Returns the customer id for the job's primary customer ref (the
  /// one with `primary: true`), or the first ref's id when the
  /// primary flag isn't set on any. Returns null when no refs exist
  /// (v1 jobs).
  String? _primaryCustomerId(Job job) {
    final refs = job.customerRefs;
    if (refs == null || refs.isEmpty) return null;
    for (final ref in refs) {
      if (ref.primary) return ref.cellId;
    }
    return refs.first.cellId;
  }

  /// Tokenize the input strings into a deduplicated set of lowercase
  /// tokens at least `minTokenLength` chars long.
  Set<String> _extractTokens(Iterable<String?> inputs) {
    final out = <String>{};
    for (final s in inputs) {
      if (s == null || s.isEmpty) continue;
      final pieces = s.toLowerCase().split(RegExp(r'[^a-z0-9]+'));
      for (final p in pieces) {
        if (p.length >= minTokenLength) out.add(p);
      }
    }
    return out;
  }

  /// Returns a lowercase concatenated bag of unique tokens from the
  /// supplied strings (whitespace + punctuation split). Used for
  /// substring containment scoring.
  Set<String> _normalise(Iterable<String?> inputs) {
    final out = <String>{};
    for (final s in inputs) {
      if (s == null || s.isEmpty) continue;
      final pieces = s.toLowerCase().split(RegExp(r'[^a-z0-9]+'));
      for (final p in pieces) {
        if (p.length >= minTokenLength) out.add(p);
      }
    }
    return out;
  }
}

class _Scored {
  final Job job;
  final int score;
  final Set<String> matched;
  _Scored({required this.job, required this.score, required this.matched});
}

```
