---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.006847+00:00
---

# core/conversation-graph/src/index.ts

```ts
/**
 * @semantos/conversation-graph — RM-031.
 *
 * Substrate-level conversation primitives. Provides:
 *   - `Turn` shape (cross-cutting minimal contribution view)
 *   - `autoEmitReplyRelation` — when a turn quotes a prior turn,
 *     emit a `REPLIES_TO` SCG relation transparently
 *
 * Extensions (Oddjobz today; Reddit-style / Discourse-style apps in
 * Wave 5) keep their domain-specific conversation pipelines and call
 * `autoEmitReplyRelation` at turn-persistence time. They don't need
 * to import `@semantos/scg-relations` directly.
 *
 * Future work (RM-031b): the rest of oddjobz's pipeline (runConversationTurn,
 * turn-handler, turn-extractor, reply-generator) genericises and lifts
 * here. RM-031a (this commit) ships the minimum interface + the
 * auto-relation hook so the SCG Phase 1 acceptance bar (`turn quoting
 * a previous turn auto-emits REPLIES_TO`) is met.
 */
export * from './types.js';
export * from './auto-emit.js';
export * from './pipeline.js';
export * from './retrieve-context.js';
export * from './rendering.js';

```
