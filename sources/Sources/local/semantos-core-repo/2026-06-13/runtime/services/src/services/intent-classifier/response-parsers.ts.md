---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/response-parsers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.105742+00:00
---

# runtime/services/src/services/intent-classifier/response-parsers.ts

```ts
/**
 * Pure response parsers — same JSON shapes the pre-split monolith
 * accepted from the LLM.
 */

import type { IntentClassification } from '../intent-types';
import { UNKNOWN_INTENT } from '../intent-types';

export interface FastPathParsed {
  intent: string;
  confidence: number;
  flowId?: string;
  extractedFields?: Record<string, unknown>;
}

export function parseFastPathResponse(raw: string): FastPathParsed | null {
  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed.intent !== 'string' || typeof parsed.confidence !== 'number') return null;
    return {
      intent: parsed.intent,
      confidence: Math.max(0, Math.min(1, parsed.confidence)),
      flowId: typeof parsed.flowId === 'string' ? parsed.flowId : undefined,
      extractedFields:
        typeof parsed.extractedFields === 'object' && parsed.extractedFields !== null
          ? parsed.extractedFields
          : undefined,
    };
  } catch {
    return null;
  }
}

export function parseLevelResponse(raw: string): { selected: string; confidence: number } | null {
  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed.selected !== 'string' || typeof parsed.confidence !== 'number') return null;
    return {
      selected: parsed.selected,
      confidence: Math.max(0, Math.min(1, parsed.confidence)),
    };
  } catch {
    return null;
  }
}

export function parseFlatClassification(raw: string): IntentClassification {
  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed.intent !== 'string' || typeof parsed.confidence !== 'number') {
      return {
        ...UNKNOWN_INTENT,
        extractedFields: { parseError: 'Missing intent or confidence', raw },
      };
    }
    return {
      intent: parsed.intent,
      confidence: Math.max(0, Math.min(1, parsed.confidence)),
      objectType: typeof parsed.objectType === 'string' ? parsed.objectType : undefined,
      typePath: typeof parsed.typePath === 'string' ? parsed.typePath : undefined,
      flowId: typeof parsed.flowId === 'string' ? parsed.flowId : undefined,
      extractedFields:
        typeof parsed.extractedFields === 'object' && parsed.extractedFields !== null
          ? parsed.extractedFields
          : undefined,
    };
  } catch {
    return { ...UNKNOWN_INTENT, extractedFields: { parseError: 'Invalid JSON', raw } };
  }
}

```
