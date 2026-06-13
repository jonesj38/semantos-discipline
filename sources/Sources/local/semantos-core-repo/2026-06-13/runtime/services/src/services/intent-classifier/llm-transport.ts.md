---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/llm-transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.106025+00:00
---

# runtime/services/src/services/intent-classifier/llm-transport.ts

```ts
/**
 * Default LLM transport — talks to OpenRouter via fetch. Tests bind a
 * stub through `llmClientPort` instead of patching fetch.
 */

import {
  getLlmClient,
  llmClientPort,
  type ClassifierSettings,
  type LlmClient,
} from './ports';

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

export const defaultOpenRouterClient: LlmClient = {
  async call(systemPrompt, userMessage, settings) {
    if (!settings.openRouterApiKey) return null;
    try {
      const response = await fetch(OPENROUTER_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${settings.openRouterApiKey}`,
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://semantos.dev',
          'X-Title': 'Semantos Workbench',
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
      });

      if (!response.ok) return null;
      const data = await response.json();
      const content = data.choices?.[0]?.message?.content;
      return typeof content === 'string' ? content : null;
    } catch {
      return null;
    }
  },
};

/** Bind the OpenRouter client to the LLM port. Idempotent. */
export function bindDefaultOpenRouterClient(): void {
  if (!llmClientPort.isBound()) llmClientPort.bind(defaultOpenRouterClient);
}

/**
 * Invoke the bound LLM client. When no port is bound, fall back to
 * the default OpenRouter transport — preserves the pre-split contract
 * where the classifier just used `fetch` directly.
 */
export async function callBoundLlm(
  systemPrompt: string,
  userMessage: string,
  settings: ClassifierSettings,
): Promise<string | null> {
  const client = getLlmClient() ?? defaultOpenRouterClient;
  return client.call(systemPrompt, userMessage, settings);
}

```
