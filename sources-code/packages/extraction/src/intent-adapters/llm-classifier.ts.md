---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/intent-adapters/llm-classifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.456861+00:00
---

# packages/extraction/src/intent-adapters/llm-classifier.ts

```ts
/**
 * createAnthropicClassifier — LLM-backed Classifier implementation.
 *
 * Wraps the Anthropic Messages API with tool_use to guarantee
 * structured output. The classifier:
 *
 *   1. Formats the conversation message + pending-proposals context
 *      as a user message.
 *   2. Calls the Messages API forcing `classify_message` as the tool.
 *   3. Parses the tool input into a TriageOutcome.
 *   4. On malformed output, retries once with the validation error
 *      appended (per docs/INTENT-PIPELINE.md Decision #3). Second
 *      failure surfaces as an Error.
 *
 * The system prompt is cached via `cache_control: {type:'ephemeral'}`
 * — the extension grammar is stable across calls so classification
 * pays the full prompt cost once per 5-minute window.
 *
 * Model default: `claude-haiku-4-5`. Cheap and fast enough for 3-way
 * classification. Override via `options.model` if the vertical needs
 * nuance the Haiku tier misses.
 */

import Anthropic from '@anthropic-ai/sdk';
import type {
  Classifier,
  ClassifierInput,
  Signature,
  TriageOutcome,
} from '@semantos/intent';
import {
  buildClassifierToolSchema,
  parseClassifierToolInput,
  type ClassifierToolInput,
} from './classifier-tool';
import { buildClassifierSystemPrompt } from './system-prompt';
import type { ExtensionGrammarSpec } from './trades-grammar';

export interface AnthropicClassifierOptions {
  /** Defaults to process.env.ANTHROPIC_API_KEY. */
  apiKey?: string;
  /** Defaults to claude-haiku-4-5. */
  model?: string;
  /** The extension grammar to parameterise the system prompt with. */
  grammar: ExtensionGrammarSpec;
  /** Signer for ratification attestations. */
  sign: (preimage: Uint8Array) => Signature;
  /** Intent-id generator. */
  generateIntentId: () => string;
  /** Pre-constructed Anthropic client — override for dependency injection in tests. */
  client?: Anthropic;
}

const DEFAULT_MODEL = 'claude-haiku-4-5';
const MAX_TOKENS = 1024;

export function createAnthropicClassifier(
  options: AnthropicClassifierOptions,
): Classifier {
  const client =
    options.client ??
    new Anthropic({ apiKey: options.apiKey ?? process.env.ANTHROPIC_API_KEY });
  const model = options.model ?? DEFAULT_MODEL;
  const systemPrompt = buildClassifierSystemPrompt(options.grammar);
  // Tool schema's `category` enum generated from the grammar's
  // lexicon.categories — ensures the model's output is constrained
  // to valid categories for THIS grammar, not a hardcoded set.
  const toolSchema = buildClassifierToolSchema(options.grammar.lexicon);
  const lexiconName = options.grammar.lexicon.name;

  async function classifyOnce(
    userPrompt: string,
    retryHint?: string,
  ): Promise<TriageOutcome> {
    const messages: Anthropic.MessageParam[] = [
      {
        role: 'user',
        content: retryHint
          ? `${userPrompt}\n\n(Previous attempt failed: ${retryHint}. Retry with a valid classify_message call.)`
          : userPrompt,
      },
    ];

    const response = await client.messages.create({
      model,
      max_tokens: MAX_TOKENS,
      // Cached — the grammar is stable for the session; only the user
      // prompt varies. Single breakpoint on the system block.
      system: [
        {
          type: 'text',
          text: systemPrompt,
          cache_control: { type: 'ephemeral' },
        },
      ],
      tools: [toolSchema as unknown as Anthropic.Tool],
      tool_choice: { type: 'tool', name: toolSchema.name },
      messages,
    });

    const toolUse = response.content.find(
      (b): b is Anthropic.ToolUseBlock => b.type === 'tool_use',
    );
    if (!toolUse) {
      throw new Error(
        `classify_message: model returned no tool_use block (stop_reason=${response.stop_reason})`,
      );
    }
    if (toolUse.name !== toolSchema.name) {
      throw new Error(
        `classify_message: unexpected tool name '${toolUse.name}'`,
      );
    }

    // Per the Claude API skill: always JSON.parse tool_use.input is
    // already-parsed JSON from the SDK; keep the narrow cast but
    // validate shape in parseClassifierToolInput.
    const input = toolUse.input as ClassifierToolInput;
    return parseClassifierToolInput(input, {
      generateIntentId: options.generateIntentId,
      source: 'nl',
      sign: options.sign,
      hatId: 'classifier-runtime', // overridden in real call via Classifier wrapper below
      lexiconName,
    });
  }

  return {
    async classify(input: ClassifierInput): Promise<TriageOutcome> {
      const userPrompt = formatClassifierPrompt(input);

      try {
        const outcome = await classifyOnce(userPrompt);
        return rewriteRatifyHat(outcome, input.hat.hatId, options.sign);
      } catch (err) {
        // One retry with the error in context. Second failure surfaces.
        const reason = err instanceof Error ? err.message : String(err);
        const outcome = await classifyOnce(userPrompt, reason);
        return rewriteRatifyHat(outcome, input.hat.hatId, options.sign);
      }
    },
  };
}

/**
 * If the classifier returned a ratifies outcome, re-sign the
 * attestation with the real authoring hat. classifyOnce() doesn't
 * have hat context in scope, so it uses a placeholder id in the
 * preimage — we overwrite with the real one here.
 */
function rewriteRatifyHat(
  outcome: TriageOutcome,
  hatId: string,
  sign: (preimage: Uint8Array) => Signature,
): TriageOutcome {
  if (outcome.kind !== 'ratifies') return outcome;
  const preimage = new TextEncoder().encode(
    `ratify\x1f${hatId}\x1f${outcome.pendingPatchId}`,
  );
  return { ...outcome, attestation: sign(preimage) };
}

// ── User-prompt formatter ────────────────────────────────────

function formatClassifierPrompt(input: ClassifierInput): string {
  const bodyText =
    typeof input.body === 'string'
      ? input.body
      : `[non-text content: ${JSON.stringify(input.body).slice(0, 200)}]`;

  const pendingBlock =
    input.pendingProposals.length === 0
      ? '(no pending proposals)'
      : input.pendingProposals
          .map((p) => `  - ${p.patchId}: ${p.summary}`)
          .join('\n');

  return `Conversation context:
- Object: ${input.objectId}
- Authoring hat: ${input.hat.hatId} (extension=${input.hat.extensionId}, domain=${input.hat.domainFlag})
- Source: ${input.source}
- Conversation patch just written: ${input.conversationPatchId}

Pending proposals on this object:
${pendingBlock}

Message:
${bodyText}

Classify this message by calling the classify_message tool.`;
}

```
