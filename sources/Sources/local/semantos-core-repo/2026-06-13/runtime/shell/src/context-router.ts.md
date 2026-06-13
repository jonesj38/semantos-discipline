---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/context-router.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.365462+00:00
---

# runtime/shell/src/context-router.ts

```ts
/**
 * Context Router — Pure function module for conversation context configuration.
 *
 * Phase 2: Each ConversationType gets a distinct configuration that governs
 * system prompt, extraction behavior, encryption requirements, and settlement.
 *
 * @module @semantos/shell/context-router
 */

import { ConversationType, ContextWeight } from '@semantos/protocol-types';
import type { ContextConfig } from '@semantos/protocol-types';

/** System prompt prefixes per conversation context. */
const CONTEXT_PROMPTS: Record<ConversationType, string> = {
  [ConversationType.SELF]:
    `This is a private self-reflection context. The user is journaling or introspecting.
Focus on extracting insights about their inner state across the seven life dimensions
(Mental, Physical, Spiritual, Social, Vocational, Financial, Familial).
Surface patterns, emotions, and growth areas. All content is private and encrypted at rest.`,

  [ConversationType.INDIVIDUAL]:
    `This is an end-to-end encrypted 1:1 conversation between two people.
Messages are encrypted via BRC-85/86 ECDH. Extract relevant structured data
while maintaining conversational flow. Be aware of the relationship dynamic
between participants.`,

  [ConversationType.GROUP]:
    `This is a group conversation within a ZONE. Messages are encrypted with a shared ZONE key.
Multiple participants may contribute. Track which participant said what.
Extract collective decisions, action items, and shared themes.`,

  [ConversationType.AI_AGENT]:
    `You are acting as an AI agent persona. Stay in character and provide
expertise relevant to your domain. No settlement cost — this is a first-party
LLM interaction. Focus on coaching, analysis, or guidance.`,
};

/**
 * Get the configuration for a conversation context type.
 *
 * Pure function — no state, no side effects.
 */
export function getContextConfig(contextType: ConversationType): ContextConfig {
  return {
    systemPromptPrefix: CONTEXT_PROMPTS[contextType],
    extractionEnabled: contextType !== ConversationType.AI_AGENT,
    contextWeight: ContextWeight[contextType],
    encryptionRequired: contextType === ConversationType.INDIVIDUAL || contextType === ConversationType.GROUP,
    governanceLevel: contextType === ConversationType.SELF ? 'L0' : 'L1',
    settlementSats: contextType === ConversationType.AI_AGENT ? 0 : 25,
  };
}

/**
 * Check whether a context type requires Plexus edge validation before sending.
 */
export function requiresEdgeValidation(contextType: ConversationType): boolean {
  return contextType === ConversationType.INDIVIDUAL || contextType === ConversationType.GROUP;
}

/**
 * Get the display icon for a context type.
 */
export function contextIcon(contextType: ConversationType): string {
  switch (contextType) {
    case ConversationType.SELF: return '🔮';
    case ConversationType.INDIVIDUAL: return '🔒';
    case ConversationType.GROUP: return '🛡';
    case ConversationType.AI_AGENT: return '🤖';
    default: return '💬';
  }
}

```
