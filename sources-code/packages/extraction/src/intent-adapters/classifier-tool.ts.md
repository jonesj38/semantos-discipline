---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/intent-adapters/classifier-tool.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.455698+00:00
---

# packages/extraction/src/intent-adapters/classifier-tool.ts

```ts
/**
 * classify_message — the strict-schema tool Claude calls with its
 * classification decision.
 *
 * We force structured output via `tool_choice: {type: 'tool', name:
 * 'classify_message'}` and `strict: true` so the model cannot return
 * malformed JSON (per docs/INTENT-PIPELINE.md Decision #1).
 *
 * The tool input is a discriminated union on `outcome` matching the
 * three triage outcomes. We extract the relevant fields in
 * `parseClassifierToolInput` below and build a `TriageOutcome` that
 * `handleMessage` consumes directly.
 */

import type {
  Intent,
  IntentId,
  PatchId,
  Signature,
  TriageOutcome,
  IntentSource,
} from '@semantos/intent';

export interface ClassifierToolInput {
  outcome: 'no_intent' | 'proposes' | 'ratifies';
  /** When outcome=no_intent. One sentence explaining why. */
  reason?: string;
  /** When outcome=proposes. Draft Intent for the pipeline to process. */
  intent?: {
    summary: string;
    category: Intent['category'];
    action: string;
    taxonomy: {
      what: string;
      how: string;
      why: string;
    };
    /** Numeric confidence the classifier self-reported. We override this with inferred scoring. */
    claimedConfidence?: number;
    target?: {
      objectId?: string;
      typePath?: string;
    };
    /** Basic capability constraints the classifier identified. */
    capabilityNames?: ReadonlyArray<string>;
  };
  /** When outcome=ratifies. The id of the pending proposal being accepted. */
  pendingPatchId?: string;
}

import type { Lexicon } from '@semantos/semantos-sir';
import { JuralLexicon } from '@semantos/semantos-sir';

/**
 * Build the `classify_message` tool schema for a specific lexicon.
 *
 * Slice 4: the `category` enum is generated from
 * `lexicon.categories` at classifier-construction time, so the same
 * classifier machinery works against any lexicon (jural,
 * control-systems, cdm, bills-of-lading, project-management,
 * property-management, risk-assessment, circuit-commands). The
 * model's tool-use output is constrained to categories that are
 * actually members of the grammar's lexicon.
 */
export function buildClassifierToolSchema(lexicon: Lexicon) {
  return {
    name: 'classify_message',
    description:
      'Classify a conversation message into one of three outcomes and ' +
      'return structured arguments describing the decision.',
    input_schema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        outcome: {
          type: 'string',
          enum: ['no_intent', 'proposes', 'ratifies'],
          description:
            'no_intent → message is chat only. ' +
            'proposes → message proposes a new action to take; include `intent`. ' +
            'ratifies → message accepts an earlier pending proposal; include `pendingPatchId`.',
        },
        reason: {
          type: 'string',
          description: 'One-sentence explanation when outcome is no_intent.',
        },
        intent: {
          type: 'object',
          additionalProperties: false,
          properties: {
            summary: { type: 'string' },
            category: {
              type: 'string',
              enum: [...lexicon.categories],
              description: `Category within the ${lexicon.name} lexicon.`,
            },
            action: { type: 'string' },
            taxonomy: {
              type: 'object',
              additionalProperties: false,
              properties: {
                what: { type: 'string' },
                how: { type: 'string' },
                why: { type: 'string' },
              },
              required: ['what', 'how', 'why'],
            },
            claimedConfidence: {
              type: 'number',
              description: '0..1 self-reported. System will override with inferred score.',
            },
            target: {
              type: 'object',
              additionalProperties: false,
              properties: {
                objectId: { type: 'string' },
                typePath: { type: 'string' },
              },
            },
            capabilityNames: {
              type: 'array',
              items: { type: 'string' },
            },
          },
          required: ['summary', 'category', 'action', 'taxonomy'],
        },
        pendingPatchId: {
          type: 'string',
          description: 'Patch id of the pending proposal being ratified (when outcome=ratifies).',
        },
      },
      required: ['outcome'],
    },
  } as const;
}

/**
 * Backward-compat alias — jural-lexicon tool schema, matching the
 * pre-Slice-4 hardcoded shape. Existing call sites that import this
 * constant keep working; new call sites should use
 * `buildClassifierToolSchema(grammar.lexicon)` instead.
 */
export const CLASSIFIER_TOOL_SCHEMA = buildClassifierToolSchema(JuralLexicon);

export interface ParseClassifierInputContext {
  generateIntentId: () => string;
  source: IntentSource;
  /** Signer used when outcome=ratifies. Produces the attestation. */
  sign: (preimage: Uint8Array) => Signature;
  /** Authoring hat id — threaded into the ratification preimage. */
  hatId: string;
  /**
   * Lexicon name stamped onto the Intent for PROPOSES outcomes. The
   * classifier already ran with that lexicon's category enum in the
   * tool schema; we record it on the Intent as the discriminant so
   * downstream (buildSIR / lowerSIR / ui-hint) can route
   * lexicon-aware logic. Defaults to 'jural' to preserve behaviour
   * for callers that predate Slice 4.
   */
  lexiconName?: string;
}

/**
 * Translate the raw tool input into a {@link TriageOutcome} ready for
 * `handleMessage` to consume. Throws on shape violations that
 * `strict: true` should have prevented — treat those as 'retry once,
 * then surface' per doc Decision #3.
 */
export function parseClassifierToolInput(
  input: ClassifierToolInput,
  ctx: ParseClassifierInputContext,
): TriageOutcome {
  switch (input.outcome) {
    case 'no_intent':
      return {
        kind: 'no_intent',
        reason: input.reason ?? 'classifier reported no actionable intent',
      };

    case 'proposes': {
      if (!input.intent) {
        throw new Error(
          'classify_message: outcome=proposes but no intent object supplied',
        );
      }
      // Stamp the grammar's lexicon + model-selected category onto
      // the Intent as a TaggedCategory. The classifier tool schema's
      // `category` enum was generated from `ctx.lexiconName`'s
      // categories, so `input.intent.category` is known to be a
      // valid member — TypeScript's `any`-cast through the
      // discriminated union is safe here by construction.
      const lexiconName = ctx.lexiconName ?? 'jural';
      const intent: Intent = {
        id: ctx.generateIntentId() as IntentId,
        summary: input.intent.summary,
        category: {
          lexicon: lexiconName,
          category: input.intent.category,
          // Cast to satisfy TaggedCategory's discriminated union —
          // validated at classifier-construction time via the
          // lexicon's category enum.
        } as Intent['category'],
        taxonomy: input.intent.taxonomy,
        action: input.intent.action,
        constraints: (input.intent.capabilityNames ?? []).map((name, i) => ({
          kind: 'capability',
          // Capability id resolution is extension-specific; use the index
          // as a placeholder. Real extensions will resolve names via the
          // governanceConfig's capability table.
          required: i + 1,
          name,
        })),
        target: input.intent.target,
        // Confidence is filled in at a later stage by
        // runtime/intent/confidence.ts scoring; start with what the model
        // reported (or a conservative default) so handleMessage can
        // override without losing the claim.
        confidence: input.intent.claimedConfidence ?? 0.7,
        source: ctx.source,
      };
      return { kind: 'proposes', intent };
    }

    case 'ratifies': {
      if (!input.pendingPatchId) {
        throw new Error(
          'classify_message: outcome=ratifies but no pendingPatchId supplied',
        );
      }
      const preimage = new TextEncoder().encode(
        `ratify\x1f${ctx.hatId}\x1f${input.pendingPatchId}`,
      );
      return {
        kind: 'ratifies',
        pendingPatchId: input.pendingPatchId as PatchId,
        attestation: ctx.sign(preimage),
      };
    }
  }
}

```
