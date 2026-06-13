---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/host-exec/extractor/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.396011+00:00
---

# runtime/shell/src/host-exec/extractor/index.ts

```ts
/**
 * NL → ShellCommand extractor — unified entry point.
 *
 * Tries LLM extraction first (if ctx.llm is provided), falls back
 * to deterministic regex rules for CI / offline use.
 *
 * Phase 38F.
 */

export type { ExtractResult, ExtractedCommand, ExtractError, ExtractorContext, LlmClient } from './types';

import type { ExtractResult, ExtractorContext } from './types';
import { extractViaLlm } from './llm';
import { extractViaFallback } from './fallback';

/**
 * Extract a structured ShellCommand from a natural-language utterance.
 *
 * Pure function of (utterance, context). No side effects, no store writes.
 */
export async function extractShellCommand(
  utterance: string,
  ctx: ExtractorContext,
): Promise<ExtractResult> {
  const trimmed = utterance.trim();
  if (!trimmed) {
    return { ok: false, code: 'UNPARSEABLE', message: 'Empty utterance' };
  }

  // LLM path: try first if a client is provided
  if (ctx.llm) {
    try {
      return await extractViaLlm(trimmed, ctx);
    } catch {
      // LLM call failed — fall through to deterministic fallback
    }
  }

  // Deterministic fallback: regex rules, confidence ≤ 0.5
  return extractViaFallback(trimmed, ctx);
}

```
