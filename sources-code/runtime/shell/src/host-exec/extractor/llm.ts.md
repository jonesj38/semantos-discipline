---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/host-exec/extractor/llm.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.396865+00:00
---

# runtime/shell/src/host-exec/extractor/llm.ts

```ts
/**
 * LLM-based extractor — calls an LLM to parse NL into a ShellCommand draft.
 *
 * The system prompt includes the full handler manifest list (grounded output).
 * The LLM output is JSON-parsed, validated against the registry, and arg-coerced.
 *
 * Phase 38F.
 */

import type { HandlerManifest } from '../types';
import type { ExtractResult, ExtractorContext } from './types';

/** Build the system prompt with the current handler manifest list. */
function buildSystemPrompt(handlers: HandlerManifest[]): string {
  const handlerList = handlers.map(h => {
    const argsDesc = Object.entries(h.argsSchema)
      .map(([k, v]) => `${k}: ${v.type}${v.required ? ' (required)' : ''}`)
      .join(', ');
    return `  - ${h.id} — ${h.description}. Args: {${argsDesc}}`;
  }).join('\n');

  return `You turn a user utterance into a structured shell command.
Allowed handlers (pick exactly one id from this list, or refuse):
${handlerList}

Return JSON only, no markdown fences:
{"handler": "<id>", "args": {...}, "confidence": 0..1, "rationale": "<1 sentence>"}

If no handler matches, return:
{"handler": null, "args": {}, "confidence": 0, "rationale": "<why>"}`;
}

/** Strip markdown code fences and trim whitespace for tolerant JSON parsing. */
function stripFences(raw: string): string {
  let cleaned = raw.trim();
  // Remove ```json ... ``` or ``` ... ```
  cleaned = cleaned.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '');
  return cleaned.trim();
}

/** Coerce args to the types declared in the manifest's argsSchema. */
function coerceArgs(
  args: Record<string, unknown>,
  manifest: HandlerManifest,
): { ok: true; coerced: Record<string, unknown> } | { ok: false; field: string; reason: string } {
  const coerced: Record<string, unknown> = { ...args };

  for (const [key, schema] of Object.entries(manifest.argsSchema)) {
    const val = coerced[key];
    if (val === undefined) {
      if (schema.required) {
        return { ok: false, field: key, reason: `missing required field '${key}'` };
      }
      continue;
    }

    if (schema.type === 'number' || schema.type === 'integer') {
      const n = Number(val);
      if (Number.isNaN(n)) {
        return { ok: false, field: key, reason: `'${key}' cannot be coerced to number: ${val}` };
      }
      coerced[key] = n;
    } else if (schema.type === 'string') {
      coerced[key] = String(val);
    } else if (schema.type === 'boolean') {
      if (typeof val === 'string') {
        coerced[key] = val === 'true' || val === '1';
      }
    }
  }

  return { ok: true, coerced };
}

export async function extractViaLlm(
  utterance: string,
  ctx: ExtractorContext,
): Promise<ExtractResult> {
  if (!ctx.llm) {
    return { ok: false, code: 'LLM_UNAVAILABLE', message: 'No LLM client provided' };
  }

  const systemPrompt = buildSystemPrompt(ctx.handlers);
  const raw = await ctx.llm.complete(systemPrompt, utterance);

  if (!raw) {
    return { ok: false, code: 'LLM_UNAVAILABLE', message: 'LLM returned null response' };
  }

  // Parse JSON tolerantly
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(stripFences(raw));
  } catch {
    return { ok: false, code: 'UNPARSEABLE', message: 'LLM output is not valid JSON', raw };
  }

  const handler = parsed.handler as string | null;
  const args = (parsed.args ?? {}) as Record<string, unknown>;
  const confidence = Number(parsed.confidence ?? 0);
  const rationale = parsed.rationale as string | undefined;

  // Null handler means the LLM couldn't match
  if (!handler) {
    return {
      ok: false,
      code: 'UNPARSEABLE',
      message: rationale ?? 'LLM could not identify a matching handler',
      raw,
    };
  }

  // Ground: handler must be in the registry
  const manifest = ctx.handlers.find(h => h.id === handler);
  if (!manifest) {
    // Suggest closest handlers
    const suggestions = ctx.handlers
      .map(h => h.id)
      .sort((a, b) => levenshtein(a, handler) - levenshtein(b, handler))
      .slice(0, 3);

    return {
      ok: false,
      code: 'UNKNOWN_HANDLER',
      message: `Handler '${handler}' is not in the registry`,
      suggestions,
      raw,
    };
  }

  // Coerce args to manifest types
  const coercion = coerceArgs(args, manifest);
  if (!coercion.ok) {
    return {
      ok: false,
      code: 'INVALID_ARGS',
      message: coercion.reason,
      raw,
    };
  }

  return {
    ok: true,
    verb: 'host.exec',
    handler,
    args: coercion.coerced,
    confidence: Math.max(0, Math.min(1, confidence)),
    rationale,
  };
}

/** Simple Levenshtein distance for handler suggestions. */
function levenshtein(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  const dp: number[][] = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] === b[j - 1]
        ? dp[i - 1][j - 1]
        : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
    }
  }
  return dp[m][n];
}

```
