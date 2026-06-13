---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/llm-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.462286+00:00
---

# packages/extraction/src/inference/llm-client.ts

```ts
/**
 * Thin LLM client for taxonomy inference via OpenRouter.
 *
 * Follows the IntentClassifier pattern (POST to OpenRouter) but is
 * a standalone function for the inference pipeline. Used ONLY by
 * TaxonomyMapper — no other inference module calls LLM.
 */

import type { LLMSettings } from './types';

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

/**
 * Call LLM via OpenRouter for taxonomy coordinate suggestion.
 *
 * Returns the raw content string or null on failure/timeout.
 * Never throws — returns null on any error.
 */
export async function callTaxonomyLLM(
  systemPrompt: string,
  userMessage: string,
  settings: LLMSettings,
  timeoutMs: number = 5000,
): Promise<string | null> {
  if (!settings.openRouterApiKey) {
    return null;
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(OPENROUTER_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${settings.openRouterApiKey}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://semantos.dev',
        'X-Title': 'Semantos Inference Agent',
      },
      body: JSON.stringify({
        model: settings.modelId,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage },
        ],
        temperature: settings.temperature,
        response_format: { type: 'json_object' },
      }),
      signal: controller.signal,
    });

    if (!response.ok) return null;

    const data = await response.json() as {
      choices?: { message?: { content?: string } }[];
    };
    return data.choices?.[0]?.message?.content ?? null;
  } catch {
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
}

```
