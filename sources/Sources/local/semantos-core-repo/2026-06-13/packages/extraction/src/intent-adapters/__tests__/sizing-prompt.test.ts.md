---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/intent-adapters/__tests__/sizing-prompt.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.465251+00:00
---

# packages/extraction/src/intent-adapters/__tests__/sizing-prompt.test.ts

```ts
/**
 * sizing-prompt — canonical-copy conformance.
 *
 * Guards the cherry-picked packages/extraction/src/intent-adapters/
 * sizing-prompt.ts (ported from runtime/shell/src/chat/
 * prompt-builders.ts). Asserts the sizing-questions block renders
 * required/optional/prompts/effortMap per category, skips `_`-keys
 * except `_default`, carries the no-Job-until-sized guardrail, and
 * that the field-rules addendum pins the ROM-computable enums.
 */

import { describe, expect, test } from 'bun:test';
import {
  buildSizingQuestionsPrompt,
  ODDJOBZ_EXTRACTION_FIELD_RULES,
} from '../sizing-prompt';

describe('buildSizingQuestionsPrompt', () => {
  const sizing = {
    'services.trades.plumbing': {
      required: ['fixtureCount', 'stories'],
      optional: ['accessNotes'],
      prompts: { fixtureCount: 'How many fixtures need work?' },
      effortMap: { '1 fixture': 'short', '5+ fixtures': 'half_day' },
    },
    _default: {
      required: ['scope'],
      prompts: { scope: 'Roughly how big is the job?' },
    },
    _ignored: { required: ['nope'] },
  };

  test('renders a category block with required/optional/prompts/effortMap', () => {
    const out = buildSizingQuestionsPrompt(sizing);
    expect(out).toContain('services.trades.plumbing:');
    expect(out).toContain('Required: fixtureCount, stories');
    expect(out).toContain('Optional: accessNotes');
    expect(out).toContain('fixtureCount: "How many fixtures need work?"');
    expect(out).toContain('Effort mapping:');
    expect(out).toContain('1 fixture → short');
    expect(out).toContain('5+ fixtures → half_day');
  });

  test('renders _default as the fallback block but skips other _-keys', () => {
    const out = buildSizingQuestionsPrompt(sizing);
    expect(out).toContain('For any other category:');
    expect(out).toContain('Required: scope');
    expect(out).not.toContain('_ignored');
    expect(out).not.toContain('nope');
  });

  test('carries the no-Job-until-sized guardrail', () => {
    const out = buildSizingQuestionsPrompt(sizing);
    expect(out).toContain(
      'IMPORTANT: Do NOT create a Job until you have answers to the REQUIRED sizing questions',
    );
  });

  test('empty map → header lines only, no category blocks', () => {
    const out = buildSizingQuestionsPrompt({});
    expect(out).toContain('SIZING QUESTIONS');
    expect(out).not.toContain('Required:');
  });
});

describe('ODDJOBZ_EXTRACTION_FIELD_RULES', () => {
  test('pins the ROM-computable enums (effortBand/urgency/estimateType)', () => {
    expect(ODDJOBZ_EXTRACTION_FIELD_RULES).toContain(
      'effortBand MUST be one of: quick, short, quarter_day, half_day, full_day, multi_day',
    );
    expect(ODDJOBZ_EXTRACTION_FIELD_RULES).toContain('categoryPath MUST map to the taxonomy');
    expect(ODDJOBZ_EXTRACTION_FIELD_RULES).toContain(
      'estimateType MUST be one of: auto_rom, operator_rom, formal_quote',
    );
  });
});

```
