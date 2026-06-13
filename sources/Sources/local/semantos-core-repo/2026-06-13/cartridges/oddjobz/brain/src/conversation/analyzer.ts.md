---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/analyzer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.524427+00:00
---

# cartridges/oddjobz/brain/src/conversation/analyzer.ts

```ts
/**
 * D-O7 — periodic conversation analyzer.
 *
 * Origin: `oddjobtodd/src/app/api/cron/analyze-conversations/route.ts`.
 *
 * Provenance note: the OJT cron route was a 47-line reverse-proxy to
 * `/api/analyze-conversations`, which **did not exist** in the OJT
 * repo (verified via `find oddjobtodd/src -iname '*analyze*'` — only
 * the cron stub matched). So there is no real OJT logic to port; this
 * module is a placeholder shape that makes the periodic-analysis seam
 * explicit in semantos-core, with a documented trigger model.
 *
 * Trigger model (per D-O7 brief §(c)):
 *   brain has no built-in cron. The analyzer is exposed as a pure
 *   function (`analyzeConversations`) that the operator triggers
 *   manually:
 *
 *     - via the REPL/CLI (`semantos analyze-conversations` once D-O10
 *       lands the CLI),
 *     - via the dispatcher's resource interface (planned: the Semantos Brain-
 *       side will register `oddjobz.analyzer.analyze` as a resource
 *       alongside `oddjobz.lead_extract.extract`), or
 *     - via an external cron + curl call against the dispatcher's
 *       HTTP surface (the current production trigger path).
 *
 * The module body is intentionally thin: the analyzer's input is the
 * set of recent chat sessions + their accumulated states; the output
 * is a per-session decision (drop | keep-warm | escalate-to-helm).
 * Real-world tuning lives in the application layer that consumes this
 * module's output — D-O7's responsibility is to provide the typed
 * shape and the deterministic decision function, not to bake in
 * specific business rules.
 */

import type { AccumulatedJobState } from './accumulated-job-state.js';

/* ══════════════════════════════════════════════════════════════════════
 * Per-session shape
 * ══════════════════════════════════════════════════════════════════════ */

/** A single conversation session + its accumulated state, as the
 *  analyzer sees it. The session-id is the chatSessionId from D-O6b's
 *  chat-persistence; the timestamps are wall-clock. */
export interface ConversationSnapshot {
  readonly chatSessionId: string;
  readonly state: AccumulatedJobState;
  readonly lastTurnAt: string;
  readonly nowIso: string;
}

/** Per-session decision the analyzer emits. */
export type AnalyzerDecision =
  | { readonly kind: 'drop'; readonly reason: string }
  | { readonly kind: 'keep_warm'; readonly reason: string }
  | { readonly kind: 'escalate_to_helm'; readonly reason: string };

/** Output of `analyzeConversations`. */
export interface AnalyzerResult {
  readonly perSession: ReadonlyArray<{
    readonly chatSessionId: string;
    readonly decision: AnalyzerDecision;
  }>;
  /** Total sessions inspected. */
  readonly totalCount: number;
  /** Counts grouped by decision kind. */
  readonly summary: {
    readonly dropped: number;
    readonly keptWarm: number;
    readonly escalated: number;
  };
}

/* ══════════════════════════════════════════════════════════════════════
 * Decision function (deterministic)
 * ══════════════════════════════════════════════════════════════════════ */

/** Default config. */
export const DEFAULT_ANALYZER_CONFIG = Object.freeze({
  /** Decision-readiness above which a session escalates to helm. */
  escalateAtDecisionReadiness: 50,
  /** Minutes since last turn after which a "stuck" session is dropped. */
  dropStaleAfterMinutes: 60 * 24 * 7, // one week
  /** Minimum scope clarity for keep-warm; below this we treat as dead. */
  keepWarmMinScopeClarity: 20,
});

export type AnalyzerConfig = typeof DEFAULT_ANALYZER_CONFIG;

/**
 * Decide a single session's fate. Pure function.
 *
 * Decision tree:
 *   1. If conversationPhase === 'confirmed' OR
 *      decisionReadiness >= config.escalateAtDecisionReadiness:
 *      → escalate_to_helm (operator should look)
 *   2. If conversationPhase === 'disengaged' OR
 *      now - lastTurn > config.dropStaleAfterMinutes:
 *      → drop (no further work)
 *   3. If scopeClarity < config.keepWarmMinScopeClarity AND
 *      no contact info captured:
 *      → drop (dead before it started)
 *   4. Otherwise → keep_warm (let the next visitor turn run)
 */
export function decideForSession(
  snap: ConversationSnapshot,
  config: AnalyzerConfig = DEFAULT_ANALYZER_CONFIG,
): AnalyzerDecision {
  const { state } = snap;

  // Step 1: escalate.
  if (state.conversationPhase === 'confirmed') {
    return {
      kind: 'escalate_to_helm',
      reason: 'conversation_phase_confirmed',
    };
  }
  if (state.decisionReadiness >= config.escalateAtDecisionReadiness) {
    return {
      kind: 'escalate_to_helm',
      reason: `decision_readiness>=${config.escalateAtDecisionReadiness}`,
    };
  }

  // Step 2: drop stale or disengaged.
  if (state.conversationPhase === 'disengaged') {
    return { kind: 'drop', reason: 'conversation_phase_disengaged' };
  }
  const ageMin = ageMinutes(snap.lastTurnAt, snap.nowIso);
  if (ageMin > config.dropStaleAfterMinutes) {
    return { kind: 'drop', reason: `stale_after_${ageMin}_min` };
  }

  // Step 3: dead-on-arrival.
  const hasContact =
    state.customerName !== null ||
    state.customerPhone !== null ||
    state.customerEmail !== null;
  if (state.scopeClarity < config.keepWarmMinScopeClarity && !hasContact) {
    return {
      kind: 'drop',
      reason: `low_scope_no_contact (scopeClarity=${state.scopeClarity})`,
    };
  }

  // Step 4: keep warm.
  return { kind: 'keep_warm', reason: 'still_active' };
}

/**
 * Analyse a batch of conversation snapshots. Pure function.
 * Returns per-session decisions + a summary count by kind.
 */
export function analyzeConversations(
  snaps: readonly ConversationSnapshot[],
  config: AnalyzerConfig = DEFAULT_ANALYZER_CONFIG,
): AnalyzerResult {
  const perSession: Array<{
    chatSessionId: string;
    decision: AnalyzerDecision;
  }> = [];
  let dropped = 0;
  let keptWarm = 0;
  let escalated = 0;

  for (const snap of snaps) {
    const decision = decideForSession(snap, config);
    perSession.push({ chatSessionId: snap.chatSessionId, decision });
    if (decision.kind === 'drop') dropped++;
    else if (decision.kind === 'keep_warm') keptWarm++;
    else if (decision.kind === 'escalate_to_helm') escalated++;
  }

  return {
    perSession: Object.freeze(perSession),
    totalCount: snaps.length,
    summary: { dropped, keptWarm, escalated },
  };
}

/** Compute age in minutes between two ISO-8601 timestamps. */
function ageMinutes(lastTurnIso: string, nowIso: string): number {
  const last = Date.parse(lastTurnIso);
  const now = Date.parse(nowIso);
  if (!Number.isFinite(last) || !Number.isFinite(now)) return 0;
  return Math.max(0, Math.floor((now - last) / 60000));
}

```
