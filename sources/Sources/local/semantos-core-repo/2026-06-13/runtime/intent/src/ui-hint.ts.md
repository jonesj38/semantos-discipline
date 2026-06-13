---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/ui-hint.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.342494+00:00
---

# runtime/intent/src/ui-hint.ts

```ts
/**
 * deriveUIHint — tell the input mode how to present the IntentResult.
 *
 * Pure mapping from (intent, kernel result, rejection?) → UIHint. The
 * pipeline doesn't render UI; it gives every caller enough structured
 * info to render correctly.
 *
 * See docs/INTENT-PIPELINE.md §"Output modes".
 */

import type { Intent, UIHint, IntentRejection, ScriptResult } from './types';

export interface DeriveUIHintInput {
  intent: Intent;
  kernelResult: ScriptResult;
  rejection?: IntentRejection;
}

export function deriveUIHint(input: DeriveUIHintInput): UIHint {
  const { intent, kernelResult, rejection } = input;

  // Rejection path — always surface to the user with a toast, plus
  // a clarify follow-up for SIR rejections that the producer can
  // retry (per doc Decision #3).
  if (rejection) {
    const retryable = rejection.stage === 'sir';
    return {
      presentation: 'toast',
      invalidate: [],
      followUp: retryable
        ? { kind: 'clarify', prompt: rejection.message }
        : undefined,
    };
  }

  // Kernel failed — surface as a toast, no retry (kernel errors are
  // state-level, not intent-level).
  if (!kernelResult.ok) {
    return {
      presentation: 'toast',
      invalidate: [],
    };
  }

  // Success path — invalidate the target object (if any) so UI
  // re-renders with the new evidence.
  const invalidate: string[] = [];
  if (intent.target?.objectId) invalidate.push(intent.target.objectId);

  // Presentation rule. Jural categories get specialised rendering;
  // other lexicons fall through to `inline` — sensible default that
  // keeps UI alive without over-promoting. Per-lexicon presentation
  // rules can plug in here as extensions register preferences.
  const presentation: UIHint['presentation'] = (() => {
    if (intent.category.lexicon !== 'jural') return 'inline';
    switch (intent.category.category) {
      case 'transfer':
      case 'power':
        return 'inspector';
      case 'obligation':
      case 'permission':
      case 'prohibition':
        return 'inline';
      case 'declaration':
      case 'condition':
        return 'silent';
    }
  })();

  return { presentation, invalidate };
}

```
