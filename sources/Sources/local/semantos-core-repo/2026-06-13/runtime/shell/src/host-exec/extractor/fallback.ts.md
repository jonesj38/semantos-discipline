---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/host-exec/extractor/fallback.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.396585+00:00
---

# runtime/shell/src/host-exec/extractor/fallback.ts

```ts
/**
 * Deterministic rule-based extractor — regex fallback for CI.
 *
 * Covers a small fixture set of utterances so tests run without an LLM.
 * Fallback results always have confidence ≤ 0.5.
 *
 * Phase 38F.
 */

import type { ExtractResult, ExtractorContext } from './types';

interface FallbackRule {
  pattern: RegExp;
  handler: string;
  extract: (match: RegExpMatchArray) => Record<string, unknown>;
  confidence: number;
}

const RULES: FallbackRule[] = [
  {
    // "kill the process on port 9000", "kill port 9000", "stop process on port 8080"
    pattern: /(?:kill|stop|terminate)\s+(?:the\s+)?(?:process\s+)?(?:on\s+)?port\s+(\d+)/i,
    handler: 'process.killByPort',
    extract: (m) => ({ port: Number(m[1]) }),
    confidence: 0.5,
  },
  {
    // "force kill port 9000", "forcefully kill port 8080"
    pattern: /force(?:fully)?\s+kill\s+(?:the\s+)?(?:process\s+)?(?:on\s+)?port\s+(\d+)/i,
    handler: 'process.killByPort',
    extract: (m) => ({ port: Number(m[1]), signal: 'SIGKILL' }),
    confidence: 0.4,
  },
];

export function extractViaFallback(
  utterance: string,
  ctx: ExtractorContext,
): ExtractResult {
  for (const rule of RULES) {
    const match = utterance.match(rule.pattern);
    if (match) {
      // Verify handler exists in the registry allowlist
      const handlerExists = ctx.handlers.some(h => h.id === rule.handler);
      if (!handlerExists) continue;

      return {
        ok: true,
        verb: 'host.exec',
        handler: rule.handler,
        args: rule.extract(match),
        confidence: rule.confidence,
        rationale: 'deterministic fallback match',
      };
    }
  }

  return {
    ok: false,
    code: 'UNPARSEABLE',
    message: 'No fallback rule matched the utterance',
  };
}

```
