---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/attention-verb.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.097057+00:00
---

# runtime/services/src/services/attention-verb.ts

```ts
/**
 * `attention` REPL verb — surfaces the AS workstream's introspection +
 * mutation surface (status / pin / unpin / suppress / unsuppress /
 * must-show / rules / rollback / telemetry / enable / disable).
 *
 * Implements the verbs called out in AS2 §5, AS3 §2, AS4 §8.
 *
 * Wired via `registerVerb('attention', routeAttention)` in the runtime
 * services index — that gives both the BRAIN REPL and the shell router
 * a single source of truth.
 */
import { attentionTelemetry } from './AttentionTelemetry';
import { attentionWeightLearner, BASELINE_WEIGHTS } from './AttentionWeightLearner';
import { attentionRules } from './AttentionRules';
import { attentionSignals } from './AttentionSignals';

interface AttentionShellCommand {
  flags?: Record<string, unknown>;
  args?: string[];
  positional?: string[];
}

export async function routeAttention(cmdRaw: unknown, _ctx: unknown): Promise<unknown> {
  const cmd = (cmdRaw ?? {}) as AttentionShellCommand;
  const args = cmd.positional ?? cmd.args ?? [];
  const sub = args[0];
  const flags = cmd.flags ?? {};

  switch (sub) {
    case undefined:
    case 'status':
      return statusReport();
    case 'pin':
      return doPin(args[1], flags);
    case 'unpin':
      return doUnpin(args[1]);
    case 'suppress':
      return doSuppress(args[1], flags);
    case 'unsuppress':
      return doUnsuppress(args[1]);
    case 'must-show':
      return doMustShow(args[1], flags);
    case 'rules':
      if (args[1] === 'history') return rulesHistory();
      return rulesSnapshot();
    case 'rollback':
      return doRollback(flags);
    case 'telemetry':
      return doTelemetry(flags);
    case 'enable':
      return doSetEnabled(args[1], true);
    case 'disable':
      return doSetEnabled(args[1], false);
    case 'help':
    default:
      return helpText();
  }
}

function statusReport(): unknown {
  const ctx = inferContextTag();
  const profile = attentionWeightLearner.selectProfile(ctx);
  const weights = attentionWeightLearner.getWeights(profile);
  const multipliers = attentionWeightLearner.getClassMultipliers(profile);
  const stats = attentionWeightLearner.getImpressionStats();

  const trend = (factor: keyof typeof weights) => {
    const w = weights[factor];
    const base = BASELINE_WEIGHTS[factor];
    if (Math.abs(w - base) < 0.005) return '\u2014'; // em-dash, neutral
    return w > base ? '+' : '-';
  };

  return {
    activeProfile: profile,
    weights: {
      recency:        { value: weights.recency,        baseline: BASELINE_WEIGHTS.recency,        trend: trend('recency') },
      deadline:       { value: weights.deadline,       baseline: BASELINE_WEIGHTS.deadline,       trend: trend('deadline') },
      activeWork:     { value: weights.active_work,    baseline: BASELINE_WEIGHTS.active_work,    trend: trend('active_work') },
      goalAlignment:  { value: weights.goal_alignment, baseline: BASELINE_WEIGHTS.goal_alignment, trend: trend('goal_alignment') },
      pendingAction:  { value: weights.pending_action, baseline: BASELINE_WEIGHTS.pending_action, trend: trend('pending_action') },
      externalSignal: { value: weights.external_signal, baseline: BASELINE_WEIGHTS.external_signal, trend: trend('external_signal') },
    },
    classMultipliers: multipliers,
    impressionStats: stats,
    rules: attentionRules.snapshot(),
    enabledSignalSources: ['weather', 'surfline', 'legacy-ingest', 'capability']
      .map(id => ({ id, enabled: attentionSignals.isEnabled(id) })),
  };
}

async function doPin(target: string | undefined, flags: Record<string, unknown>): Promise<unknown> {
  if (!target) return { error: 'Usage: attention pin <object-id|pattern> [--until <iso-date>]' };
  await attentionRules.pin(target, {
    reason: typeof flags.reason === 'string' ? flags.reason : undefined,
    until: typeof flags.until === 'string' ? flags.until : undefined,
  });
  return { ok: true, pinned: target };
}

async function doUnpin(target: string | undefined): Promise<unknown> {
  if (!target) return { error: 'Usage: attention unpin <object-id|pattern>' };
  await attentionRules.unpin(target);
  return { ok: true, unpinned: target };
}

async function doSuppress(pattern: string | undefined, flags: Record<string, unknown>): Promise<unknown> {
  if (!pattern) return { error: 'Usage: attention suppress <pattern> [--until <iso-date>]' };
  await attentionRules.suppress(pattern, {
    until: typeof flags.until === 'string' ? flags.until : undefined,
  });
  return { ok: true, suppressed: pattern };
}

async function doUnsuppress(pattern: string | undefined): Promise<unknown> {
  if (!pattern) return { error: 'Usage: attention unsuppress <pattern>' };
  await attentionRules.unsuppress(pattern);
  return { ok: true, unsuppressed: pattern };
}

async function doMustShow(pattern: string | undefined, flags: Record<string, unknown>): Promise<unknown> {
  if (!pattern) return { error: 'Usage: attention must-show <pattern> [--boost <0..1>]' };
  const boost = typeof flags.boost === 'number' ? flags.boost
    : typeof flags.boost === 'string' ? Number(flags.boost)
    : 0.20;
  await attentionRules.mustShow(pattern, boost);
  return { ok: true, mustShow: pattern, boost };
}

function rulesSnapshot(): unknown {
  return attentionRules.snapshot();
}

function rulesHistory(): unknown {
  return attentionRules.getHistory();
}

function doRollback(flags: Record<string, unknown>): unknown {
  const to = typeof flags.to === 'string' ? flags.to : undefined;
  if (!to) return { error: 'Usage: attention rollback --to <iso-date>' };
  const ok = attentionWeightLearner.rollbackTo(to);
  return { ok, to };
}

function doTelemetry(flags: Record<string, unknown>): unknown {
  const since = typeof flags.since === 'string' ? Date.parse(flags.since) : undefined;
  const limit = typeof flags.limit === 'number' ? flags.limit : 100;
  const records = attentionTelemetry.query({ since, limit });
  return { records, total: attentionTelemetry.size() };
}

function doSetEnabled(sourceId: string | undefined, enabled: boolean): unknown {
  if (!sourceId) {
    return { error: `Usage: attention ${enabled ? 'enable' : 'disable'} <source-id>` };
  }
  attentionSignals.setEnabled(sourceId, enabled);
  return { ok: true, sourceId, enabled };
}

function helpText(): unknown {
  return {
    verbs: [
      'attention status',
      'attention pin <id|pattern> [--until <iso>]',
      'attention unpin <id|pattern>',
      'attention suppress <pattern> [--until <iso>]',
      'attention unsuppress <pattern>',
      'attention must-show <pattern> [--boost <0..1>]',
      'attention rules',
      'attention rules history',
      'attention rollback --to <iso-date>',
      'attention telemetry [--since <iso>] [--limit <n>]',
      'attention enable <source-id>',
      'attention disable <source-id>',
    ],
  };
}

function inferContextTag(): 'field' | 'desk' | 'night' | null {
  if (typeof navigator === 'undefined') return null;
  const isMobile = /Mobi|Android/i.test(navigator.userAgent);
  const hour = new Date().getHours();
  if (hour < 7 || hour >= 22) return 'night';
  return isMobile ? 'field' : 'desk';
}

```
