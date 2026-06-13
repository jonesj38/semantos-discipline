---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/conversation/dispatch-router.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.161949+00:00
---

# runtime/legacy-ingest/src/conversation/dispatch-router.ts

```ts
/**
 * Oddjobz conversation dispatch router.
 *
 * This is the thin "butler" layer between the unified message trail and the
 * existing intent/capture machinery. It is deliberately pure: it does not send
 * Twilio messages, multicast squad traffic, or mutate job cells. It decides
 * which talk lane a turn belongs to and which graph targets should receive the
 * next step. A host can then feed self/job mutations into @semantos/intent
 * handleMessage, or hand direct/squad/broadcast decisions to transport ports.
 */

import type { OddjobzMessagePatch } from './turn-patch-store';

export type ConversationDispatchLane =
  | 'self'
  | 'direct'
  | 'squad'
  | 'agent'
  | 'broadcast';

export type ConversationDispatchSlot = `talk.${ConversationDispatchLane}`;

export type ConversationDispatchTransport =
  | 'none'
  | 'direct'
  | 'multicast'
  | 'agent'
  | 'broadcast';

export type ConversationDispatchTargetType =
  | 'conversation-session'
  | 'participant'
  | 'customer'
  | 'job'
  | 'site'
  | 'squad'
  | 'agent'
  | 'broadcast-channel';

export interface ConversationDispatchTarget {
  readonly type: ConversationDispatchTargetType;
  readonly ref: string;
  readonly label?: string;
  /** Optional Pask/attention cell id for graph-distance scoring. */
  readonly paskCellId?: string;
  /** Relevance in [0, 1]. Pask candidates normally carry this. */
  readonly score: number;
  readonly source: 'message' | 'heuristic' | 'graph' | 'pask' | 'explicit';
}

export interface ConversationDispatchCandidate {
  readonly lane?: ConversationDispatchLane;
  readonly target: ConversationDispatchTarget;
  readonly reason?: string;
}

export interface ConversationDispatchResolverInput {
  readonly patch: OddjobzMessagePatch;
  readonly lane: ConversationDispatchLane;
  readonly slot: ConversationDispatchSlot;
  readonly text: string;
}

export type ConversationDispatchResolver = (
  input: ConversationDispatchResolverInput,
) =>
  | ReadonlyArray<ConversationDispatchCandidate>
  | Promise<ReadonlyArray<ConversationDispatchCandidate>>;

export interface ConversationDispatchRouterOpts {
  /**
   * Optional Pask/context resolver. Production wiring should resolve likely
   * job/site/customer/squad nodes from the message/session topology. Tests can
   * inject a tiny resolver without loading the Pask WASM.
   */
  readonly resolveCandidates?: ConversationDispatchResolver;
  /** Confidence below this asks the operator/agent to ratify before action. */
  readonly ratificationThreshold?: number;
  /** Default target refs when no resolver candidate exists for a lane. */
  readonly defaults?: Partial<Record<ConversationDispatchLane, string>>;
}

export interface RouteConversationDispatchOpts {
  /** Explicit UI mode wins over text heuristics. */
  readonly lane?: ConversationDispatchLane;
}

export interface ConversationDispatchDecision {
  readonly sourcePatchId: string;
  readonly providerId: string;
  readonly sessionId: string;
  readonly lane: ConversationDispatchLane;
  readonly slot: ConversationDispatchSlot;
  readonly transport: ConversationDispatchTransport;
  readonly text: string;
  readonly confidence: number;
  readonly requiresRatification: boolean;
  readonly reason: string;
  readonly primaryTarget: ConversationDispatchTarget;
  readonly targets: ReadonlyArray<ConversationDispatchTarget>;
  readonly candidateReasons: ReadonlyArray<string>;
  /** Direct messages can be fanned out independently by the host. */
  readonly parallelizable: boolean;
}

const DEFAULTS: Record<ConversationDispatchLane, string> = {
  self: 'operator:self',
  direct: 'conversation:active',
  squad: 'squad:default',
  agent: 'agent:oddjobz',
  broadcast: 'broadcast:oddjobtodd-info',
};

export class ConversationDispatchRouter {
  private readonly resolveCandidates: ConversationDispatchResolver | null;
  private readonly ratificationThreshold: number;
  private readonly defaults: Record<ConversationDispatchLane, string>;

  constructor(opts: ConversationDispatchRouterOpts = {}) {
    this.resolveCandidates = opts.resolveCandidates ?? null;
    this.ratificationThreshold = opts.ratificationThreshold ?? 0.65;
    this.defaults = { ...DEFAULTS, ...(opts.defaults ?? {}) };
  }

  async route(
    patch: OddjobzMessagePatch,
    opts: RouteConversationDispatchOpts = {},
  ): Promise<ConversationDispatchDecision> {
    const text = patch.text.trim();
    const laneGuess = opts.lane
      ? { lane: opts.lane, confidence: 0.95, reason: 'explicit UI lane' }
      : inferLane(patch);
    const slot = `talk.${laneGuess.lane}` as ConversationDispatchSlot;
    const candidates = this.resolveCandidates
      ? await this.resolveCandidates({
          patch,
          lane: laneGuess.lane,
          slot,
          text,
        })
      : [];

    const targets = dedupeTargets([
      ...messageTargets(patch, laneGuess.lane),
      ...fallbackTargets(laneGuess.lane, this.defaults),
      ...candidates
        .filter((c) => !c.lane || c.lane === laneGuess.lane)
        .map((c) => c.target),
    ]).sort((a, b) => b.score - a.score);

    const primaryTarget =
      selectPrimaryTarget(laneGuess.lane, targets)
      ?? fallbackTargets(laneGuess.lane, this.defaults)[0]!;
    const targetConfidence = Math.max(primaryTarget.score, ...targets.map((t) => t.score));
    const confidence = clamp01(laneGuess.confidence * 0.72 + targetConfidence * 0.28);
    const requiresRatification =
      laneGuess.lane === 'broadcast' || confidence < this.ratificationThreshold;

    return {
      sourcePatchId: patch.patchId,
      providerId: patch.providerId,
      sessionId: patch.sessionId,
      lane: laneGuess.lane,
      slot,
      transport: transportForLane(laneGuess.lane),
      text,
      confidence,
      requiresRatification,
      reason: laneGuess.reason,
      primaryTarget,
      targets,
      candidateReasons: candidates
        .filter((c) => c.reason)
        .map((c) => c.reason!),
      parallelizable: laneGuess.lane === 'direct' && targets.length > 1,
    };
  }
}

export function routeConversationDispatch(
  patch: OddjobzMessagePatch,
  opts: ConversationDispatchRouterOpts & RouteConversationDispatchOpts = {},
): Promise<ConversationDispatchDecision> {
  const { lane, ...routerOpts } = opts;
  return new ConversationDispatchRouter(routerOpts).route(patch, { lane });
}

function inferLane(patch: OddjobzMessagePatch): {
  lane: ConversationDispatchLane;
  confidence: number;
  reason: string;
} {
  const text = patch.text.trim().toLowerCase();

  if (patch.role === 'customer') {
    return {
      lane: 'direct',
      confidence: 0.82,
      reason: 'customer turn stays in the direct conversation lane',
    };
  }

  if (patch.role === 'assistant') {
    return {
      lane: 'agent',
      confidence: 0.72,
      reason: 'assistant turn belongs to the agent lane',
    };
  }

  if (/^(broadcast|publish|post)\b|^send (this )?(to )?(the )?(page|website|public)/.test(text)) {
    return {
      lane: 'broadcast',
      confidence: 0.82,
      reason: 'operator requested a broadcast/publish action',
    };
  }

  if (/^(squad|crew|team|everyone|all hands)\b|\b(to|tell|message) (the )?(squad|crew|team)\b/.test(text)) {
    return {
      lane: 'squad',
      confidence: 0.84,
      reason: 'operator addressed a squad/group',
    };
  }

  if (/^(agent|assistant|brain|butler)\b|\bask (the )?(agent|assistant|brain|butler)\b/.test(text)) {
    return {
      lane: 'agent',
      confidence: 0.78,
      reason: 'operator addressed the assistant/agent',
    };
  }

  if (/^(tell|text|message|reply|send)\b/.test(text)) {
    return {
      lane: 'direct',
      confidence: 0.76,
      reason: 'operator requested a direct message',
    };
  }

  if (/\b(note to self|remind me|remember|journal|log this|for myself)\b/.test(text)) {
    return {
      lane: 'self',
      confidence: 0.8,
      reason: 'operator wrote a self-directed note',
    };
  }

  return {
    lane: 'self',
    confidence: patch.role === 'operator' ? 0.62 : 0.5,
    reason: 'defaulted to self lane for unresolved operator/internal turn',
  };
}

function messageTargets(
  patch: OddjobzMessagePatch,
  lane: ConversationDispatchLane,
): ConversationDispatchTarget[] {
  const session: ConversationDispatchTarget = {
    type: 'conversation-session',
    ref: patch.sessionId,
    score: 0.55,
    source: 'message',
  };

  if (lane === 'direct') {
    return [
      {
        type: 'participant',
        ref: patch.recipientId,
        score: 0.78,
        source: 'message',
      },
      session,
    ];
  }

  if (lane === 'self') return [session];
  return [];
}

function fallbackTargets(
  lane: ConversationDispatchLane,
  defaults: Record<ConversationDispatchLane, string>,
): ConversationDispatchTarget[] {
  const type: Record<ConversationDispatchLane, ConversationDispatchTargetType> = {
    self: 'customer',
    direct: 'participant',
    squad: 'squad',
    agent: 'agent',
    broadcast: 'broadcast-channel',
  };
  return [{
    type: type[lane],
    ref: defaults[lane],
    score: 0.2,
    source: 'heuristic',
  }];
}

function dedupeTargets(
  targets: ReadonlyArray<ConversationDispatchTarget>,
): ConversationDispatchTarget[] {
  const byKey = new Map<string, ConversationDispatchTarget>();
  for (const target of targets) {
    const key = `${target.type}:${target.ref}`;
    const prior = byKey.get(key);
    if (!prior || target.score > prior.score) byKey.set(key, target);
  }
  return [...byKey.values()];
}

function transportForLane(lane: ConversationDispatchLane): ConversationDispatchTransport {
  switch (lane) {
    case 'self': return 'none';
    case 'direct': return 'direct';
    case 'squad': return 'multicast';
    case 'agent': return 'agent';
    case 'broadcast': return 'broadcast';
  }
}

function selectPrimaryTarget(
  lane: ConversationDispatchLane,
  targets: ReadonlyArray<ConversationDispatchTarget>,
): ConversationDispatchTarget | null {
  const priority: Record<ConversationDispatchLane, ConversationDispatchTargetType[]> = {
    self: ['job', 'customer', 'site', 'conversation-session'],
    direct: ['participant', 'customer', 'job', 'conversation-session'],
    squad: ['squad', 'job', 'site'],
    agent: ['agent', 'job', 'customer', 'conversation-session'],
    broadcast: ['broadcast-channel', 'job', 'site'],
  };
  for (const type of priority[lane]) {
    const match = targets.find((target) => target.type === type);
    if (match) return match;
  }
  return targets[0] ?? null;
}

function clamp01(n: number): number {
  return Math.max(0, Math.min(1, n));
}

```
