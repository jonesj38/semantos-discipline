---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/template-version.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.523307+00:00
---

# cartridges/oddjobz/brain/src/conversation/template-version.ts

```ts
/**
 * Versioned template registry — prompt + decision-tree provenance.
 *
 * The intake bot must not be a black box. Every conversation turn
 * (see conversation-turn-patch.ts) records WHICH prompt template and
 * WHICH decision-tree version produced it, as a versioned data
 * structure, so bot behaviour is auditable/diffable against its
 * prompts AND its decision logic — not just an opaque LLM context
 * window.
 *
 * Two independently-versioned things:
 *   • PROMPT — the assembled system/reply prompt the LLM actually
 *     saw this turn. `promptHash` is the SHA-256 of the exact
 *     assembled string (catches any drift, even un-bumped);
 *     `promptVersion` is the operator-managed semver (bump on an
 *     intentional prompt change).
 *   • DECISION TREE — the operator-tuned state-manager cascade
 *     (`THRESHOLDS` + `evaluateConversationState`). `decisionTreeHash`
 *     is content-addressed over THRESHOLDS so a threshold change is
 *     caught even if the version tag isn't bumped; `decisionTreeVersion`
 *     tracks state-manager's "Last tuned" provenance.
 *
 * Pure. No I/O. Deterministic. The single source the patch layer
 * draws version provenance from.
 */

import { createHash } from 'node:crypto';
import { THRESHOLDS } from './state-manager.js';

// ── Version identifiers (operator-managed) ───────────────────

export const PROMPT_TEMPLATE_ID = 'oddjobz.intake.prompt' as const;
/** Semver. Bump on any intentional change to the assembled intake
 *  prompt (BASE_SYSTEM / system-injection / extraction prompt). */
export const PROMPT_TEMPLATE_VERSION = '1.0.0' as const;

export const DECISION_TREE_ID = 'oddjobz.intake.decision-tree' as const;
/** Tracks state-manager.ts "Last tuned" provenance (the operator-
 *  tuned cascade + THRESHOLDS). Bump when the cascade logic or a
 *  threshold is intentionally retuned. */
export const DECISION_TREE_VERSION = '2026-04' as const;

// ── Hashing ──────────────────────────────────────────────────

export function sha256hex(s: string): string {
  return createHash('sha256').update(s, 'utf8').digest('hex');
}

/** Stable JSON (sorted keys) so the hash is order-independent. */
function stableStringify(v: unknown): string {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return `[${v.map(stableStringify).join(',')}]`;
  const o = v as Record<string, unknown>;
  return `{${Object.keys(o)
    .sort()
    .map((k) => `${JSON.stringify(k)}:${stableStringify(o[k])}`)
    .join(',')}}`;
}

/** Content hash of the assembled prompt the LLM saw this turn. */
export function promptHash(assembledPrompt: string): string {
  return sha256hex(assembledPrompt);
}

/** Content hash of the decision tree (THRESHOLDS). Changes if any
 *  threshold changes — independent of the version tag, so drift is
 *  always visible in the audit log. */
export function decisionTreeHash(): string {
  return sha256hex(stableStringify(THRESHOLDS));
}

// ── The versioned descriptor carried on every turn patch ─────

export interface TemplateVersionDescriptor {
  readonly prompt: {
    readonly id: typeof PROMPT_TEMPLATE_ID;
    readonly version: typeof PROMPT_TEMPLATE_VERSION;
    /** SHA-256 of the exact assembled prompt for THIS turn. */
    readonly hash: string;
  };
  readonly decisionTree: {
    readonly id: typeof DECISION_TREE_ID;
    readonly version: typeof DECISION_TREE_VERSION;
    /** SHA-256 of THRESHOLDS (content-addressed; drift-catching). */
    readonly hash: string;
  };
}

/**
 * Build the per-turn version descriptor. `assembledPrompt` is the
 * exact prompt string the LLM was given this turn (BASE_SYSTEM +
 * system-injection + any ROM line, concatenated). Recorded into the
 * conversation patch so each turn maps to its prompt + decision-tree
 * version as a versioned data structure.
 */
export function intakeTemplateDescriptor(
  assembledPrompt: string,
): TemplateVersionDescriptor {
  return {
    prompt: {
      id: PROMPT_TEMPLATE_ID,
      version: PROMPT_TEMPLATE_VERSION,
      hash: promptHash(assembledPrompt),
    },
    decisionTree: {
      id: DECISION_TREE_ID,
      version: DECISION_TREE_VERSION,
      hash: decisionTreeHash(),
    },
  };
}

// ── Content-addressed prompt schema link (D-OJ-conv-prompt-versioning) ──
//
// The descriptor above hashes the EXACT assembled prompt seen this
// turn (drift-catching). `prompt-store.ts` is the registry of the
// canonical prompt SCHEMAS and their version history. The two relate
// via this re-export so the reply-audit-log can pin a turn to BOTH
// the live per-turn hash AND the registered schema version that
// produced it.

export {
  PROMPT_IDS,
  type PromptId,
  type ResolvedPrompt,
  type PromptVersionRef,
  resolvePrompt,
  promptVersion,
  promptVersionRef,
  promptContentHash,
  listPromptIds,
  listPromptVersions,
  UnknownPromptError,
  UnknownPromptVersionError,
} from './prompt-store.js';

```
