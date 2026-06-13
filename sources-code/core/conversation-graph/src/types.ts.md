---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.007133+00:00
---

# core/conversation-graph/src/types.ts

```ts
/**
 * Conversation-graph types — substrate-level abstractions over which
 * extensions build domain-specific pipelines (RM-031).
 *
 * A `Turn` is the substrate's minimal view of a single contribution to
 * a conversation: who said it, when, what was said, and (optionally)
 * what prior turn it quotes. Extensions (Oddjobz, future Reddit-style
 * threads, etc.) carry richer per-domain state in their own per-turn
 * types and convert down to this minimal shape when calling
 * `autoEmitReplyRelation`.
 *
 * The interesting cross-cutting move: when a new turn carries a
 * `quotedTurnId`, the substrate emits a `REPLIES_TO` relation
 * (`@semantos/scg-relations`) without the domain pipeline having to
 * know about SCG. This is the SCG Phase-1 wiring that makes "any
 * future app can consume the graph" work — extensions just have to
 * report quotes; SCG fills in the typed-relation layer.
 */

/**
 * Minimal substrate-level view of a conversation contribution. Domain
 * extensions construct one of these per turn and pass it to
 * `autoEmitReplyRelation` when the turn is about to be persisted.
 */
export interface Turn {
  /** The conversation aggregate this turn belongs to. */
  readonly conversationId: string;
  /** The `sem_objects.id` of THIS turn (after persistence). */
  readonly turnId: string;
  /** Optional — the `sem_objects.id` of a prior turn this turn quotes.
   *  When set, `autoEmitReplyRelation` emits a `REPLIES_TO` relation. */
  readonly quotedTurnId?: string;
  /** Identity that authored the turn (cert id). */
  readonly authorCertId?: string;
}

/** Configuration for an auto-relation emission. */
export interface AutoEmitOptions {
  /**
   * Optional capability-check thunk forwarded to `createRelation`.
   * RM-022 wires this to `capabilityPort.check(RELATION_MINT, …)` for
   * production callers. Tests and demos can leave it undefined.
   */
  capabilityCheck?: () => Promise<void> | void;
}

```
