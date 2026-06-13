---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/prompt-injection.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.363287+00:00
---

# runtime/shell/src/prompt-injection.ts

```ts
/**
 * Prompt script injection — builds system prompts from loaded extensions.
 *
 * Called during kernel shell initialization after all extensions are loaded.
 * Reads .md files from each extension's prompts/ directory and concatenates
 * them into the system prompt sent to the LLM.
 *
 * Cross-references:
 *   extension-loader.ts   → ExtensionLoader populates ExtensionConfig.flows
 *   extensionConfig.ts    → ExtensionConfig, ConversationFlow
 *   storage.ts           → StorageAdapter (read, list)
 */

import type { ExtensionConfig, StorageAdapter } from '@semantos/protocol-types';

/**
 * Build a system prompt by injecting extension flow context into a base prompt.
 *
 * Order matters: base system prompt first, then extension-specific flow
 * context in the order extensions were activated. This order determines
 * LLM behavior priority.
 *
 * @param baseSystemPrompt — the kernel's base system prompt
 * @param extensionConfigs — loaded ExtensionConfigs, in activation order
 * @returns concatenated system prompt string
 */
export function buildSystemPromptFromExtensions(
  baseSystemPrompt: string,
  extensionConfigs: ExtensionConfig[],
): string {
  let prompt = baseSystemPrompt;

  for (const cfg of extensionConfigs) {
    if (!cfg.flows || cfg.flows.length === 0) continue;

    prompt += `\n\n# Extension: ${cfg.name}`;

    for (const flow of cfg.flows) {
      prompt += `\n\n## Flow: ${flow.name}\nID: ${flow.id}`;
      if (flow.triggerIntents && flow.triggerIntents.length > 0) {
        prompt += `\nTrigger intents: ${flow.triggerIntents.join(', ')}`;
      }
    }
  }

  return prompt;
}

/**
 * Load all .md prompt scripts from an extension's prompts/ directory.
 *
 * Reads all files ending in .md, concatenates them with markdown separators.
 * Individual file failures are logged as warnings and skipped.
 *
 * @param extensionPath — storage key prefix for the extension directory
 * @param storage — StorageAdapter for filesystem access
 * @returns concatenated markdown string, or empty string if no prompts found
 */
export async function loadExtensionPrompts(
  extensionPath: string,
  storage: StorageAdapter,
): Promise<string> {
  const promptsDir = `${extensionPath}/prompts`;
  const prompts: string[] = [];

  try {
    const relativeKeys = await storage.list(promptsDir);
    for (const relKey of relativeKeys) {
      if (!relKey.endsWith('.md')) continue;
      try {
        const fullKey = `${promptsDir}/${relKey}`;
        const data = await storage.read(fullKey);
        if (data) {
          prompts.push(new TextDecoder().decode(data));
        }
      } catch (err) {
        console.warn(`Failed to load prompt ${relKey}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }
  } catch (err) {
    console.warn(`Could not list prompts directory ${promptsDir}: ${err instanceof Error ? err.message : String(err)}`);
  }

  return prompts.join('\n\n---\n\n');
}

```
