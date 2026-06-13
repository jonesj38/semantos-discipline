---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/prompts/prompts.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.490238+00:00
---

# cartridges/oddjobz/brain/tests/prompts/prompts.test.ts

```ts
/**
 * D-O7 — prompt tests.
 *
 * Acceptance:
 *  - System prompt is hat-keyed (carpenter vs musician produces different
 *    operator-name strings).
 *  - System prompt preserves the operator-tuned tone-rules block verbatim.
 *  - Extraction prompt embeds the JSON schema literally + the EXTRACTION
 *    RULES block + the jobPivot HARD RULES.
 *  - PDF extraction prompt embeds the trades job-type list verbatim.
 *  - Frozen string snapshots: same inputs → identical prompts.
 */

import { describe, expect, test } from 'bun:test';
import {
  buildSystemPrompt,
  CARPENTER_PERSONA,
  MUSICIAN_PERSONA,
  PERSONAS,
} from '../../src/prompts/system-prompt.js';
import {
  buildExtractionPrompt,
  buildTradesTaggedFactsSection,
  JOB_TYPE_VALUES,
} from '../../src/prompts/extraction-prompt.js';
import {
  buildPdfExtractionPrompt,
  PDF_EXTRACTION_PROMPT,
} from '../../src/prompts/pdf-extraction-prompt.js';

describe('D-O7 — system prompt — hat selection', () => {
  test('carpenter persona renders Todd + Sunshine Coast', () => {
    const out = buildSystemPrompt({ hatId: 'carpenter' });
    expect(out).toContain("You are Todd's job intake assistant");
    expect(out).toContain('Sunshine Coast');
    expect(out).toContain('handyman business');
  });

  test('musician persona renders the musician trade label', () => {
    const out = buildSystemPrompt({ hatId: 'musician' });
    expect(out).toContain('session-musician booking');
  });

  test('unknown hatId falls back to carpenter', () => {
    const out = buildSystemPrompt({ hatId: 'no-such-hat' });
    expect(out).toContain('handyman business');
  });

  test('personaOverride bypasses the registry', () => {
    const out = buildSystemPrompt({
      hatId: 'carpenter',
      personaOverride: {
        hatId: 'custom',
        operatorName: 'Sam',
        serviceArea: 'Test Area',
        tradeName: 'test trade',
      },
    });
    expect(out).toContain("You are Sam's job intake assistant");
    expect(out).toContain('Test Area');
    expect(out).toContain('test trade');
  });

  test('PERSONAS contains both built-in personas', () => {
    expect(PERSONAS.carpenter).toBe(CARPENTER_PERSONA);
    expect(PERSONAS.musician).toBe(MUSICIAN_PERSONA);
  });
});

describe('D-O7 — system prompt — operator-tuned content preserved', () => {
  test('contains the ROM-not-quote core-job paragraph', () => {
    const out = buildSystemPrompt({ hatId: 'carpenter' });
    // The "ROM" framing is the load-bearing operator-tuned mechanic.
    expect(out).toContain('ROUGH ORDER OF MAGNITUDE');
    expect(out).toContain('free on-site visit');
    expect(out).toContain('self-qualify');
  });

  test('contains the tone rules block verbatim', () => {
    const out = buildSystemPrompt({ hatId: 'carpenter' });
    expect(out).toContain('TONE RULES:');
    expect(out).toContain('Practical, slightly blunt, not corporate');
    expect(out).toContain('Sound like a tradie');
  });

  test('contains the NEVER block verbatim', () => {
    const out = buildSystemPrompt({ hatId: 'carpenter' });
    expect(out).toContain('NEVER:');
    expect(out).toContain('Quote an exact price');
    expect(out).toContain("Call the bot's output a \"quote\"");
  });

  test('contains the pricing-discipline block', () => {
    const out = buildSystemPrompt({ hatId: 'carpenter' });
    expect(out).toContain('PRICING DISCIPLINE:');
    expect(out).toContain('NEVER name a specific dollar figure');
  });

  test('contains the pushback handling block', () => {
    const out = buildSystemPrompt({ hatId: 'carpenter' });
    expect(out).toContain('HANDLING ESTIMATE PUSHBACK:');
    expect(out).toContain("That's cheap");
    expect(out).toContain("That's expensive");
  });

  test('historyBlock is prepended when supplied', () => {
    const out = buildSystemPrompt({
      hatId: 'carpenter',
      historyBlock: 'Prior turn — visitor asked about deck.',
    });
    expect(out.startsWith('Prior turn — visitor asked about deck.')).toBe(true);
  });

  test('historyBlock omitted when empty', () => {
    const out = buildSystemPrompt({
      hatId: 'carpenter',
      historyBlock: '',
    });
    expect(out.startsWith('You are Todd')).toBe(true);
  });

  test('PDF import context renders the import section', () => {
    const out = buildSystemPrompt({
      hatId: 'carpenter',
      pdfImportContext: {
        address: '123 Beach Rd, Noosa',
        tasks: ['Replace front door', 'Paint hallway'],
        agentName: 'Ray White Noosa',
        gaps: ['photos of door'],
      },
    });
    expect(out).toContain('PDF IMPORT CONTEXT');
    expect(out).toContain('123 Beach Rd, Noosa');
    expect(out).toContain('- Replace front door');
    expect(out).toContain('Ray White Noosa');
  });

  test('channel context renders hidden topics', () => {
    const out = buildSystemPrompt({
      hatId: 'carpenter',
      channelContext: {
        participantRole: 'tenant',
        hiddenTopics: ['estimates', 'pricing'],
      },
    });
    expect(out).toContain('CHANNEL CONTEXT:');
    expect(out).toContain('participant whose role is: tenant');
    expect(out).toContain('DO NOT discuss');
    expect(out).toContain('estimates, pricing');
  });

  test('frozen-string snapshot — same inputs yield identical output', () => {
    const a = buildSystemPrompt({ hatId: 'carpenter' });
    const b = buildSystemPrompt({ hatId: 'carpenter' });
    expect(a).toBe(b);
  });
});

describe('D-O7 — extraction prompt', () => {
  const STATE = {
    customerName: null,
    suburb: 'Noosa Heads',
    jobType: null,
    scopeDescription: null,
    estimatePresented: false,
    conversationPhase: 'greeting',
  };

  test('contains EXTRACTION RULES block + tuned thresholds', () => {
    const out = buildExtractionPrompt({
      currentState: STATE,
      latestMessage: 'Hi I need a deck repair',
      conversationSummary: '(no prior turns)',
    });
    expect(out).toContain('EXTRACTION RULES:');
    expect(out).toContain('1. JOB TYPE');
    expect(out).toContain('2. URGENCY');
    expect(out).toContain('3. ESTIMATE REACTION');
    expect(out).toContain('4. CUSTOMER TONE');
    expect(out).toContain('5. CHEAPEST MINDSET');
    expect(out).toContain('6. CONVERSATION PHASE');
    expect(out).toContain('9. JOB PIVOT');
  });

  test('jobPivot HARD RULES are preserved verbatim', () => {
    const out = buildExtractionPrompt({
      currentState: STATE,
      latestMessage: 'hi',
      conversationSummary: '',
    });
    expect(out).toContain('HARD RULES — these override anything else:');
    expect(out).toContain('seems cheap');
    expect(out).toContain('Pushback on the estimate');
    expect(out).toContain('NEVER different_job');
  });

  test('JSON schema embeds the full enum unions', () => {
    const out = buildExtractionPrompt({
      currentState: STATE,
      latestMessage: 'hi',
      conversationSummary: '',
    });
    // Each job-type value must appear in the rendered union.
    for (const v of JOB_TYPE_VALUES) {
      expect(out).toContain(`"${v}"`);
    }
    // The conversation-phase enum is rendered literally.
    expect(out).toContain(
      '"greeting" | "describing_job" | "providing_details"',
    );
  });

  test('CURRENT KNOWN STATE block is JSON-stringified state', () => {
    const out = buildExtractionPrompt({
      currentState: STATE,
      latestMessage: 'test',
      conversationSummary: 'one earlier message',
    });
    expect(out).toContain('CURRENT KNOWN STATE:');
    // The JSON output of STATE.
    expect(out).toContain('"suburb": "Noosa Heads"');
    expect(out).toContain('LATEST CUSTOMER MESSAGE:\n"test"');
  });

  test('default tagged-facts section is the trades-job-types one', () => {
    const out = buildExtractionPrompt({
      currentState: STATE,
      latestMessage: 'hi',
      conversationSummary: '',
    });
    expect(out).toContain('TAGGED FACTS:');
    expect(out).toContain('trades-job-types');
    expect(out).toContain('carpentry');
    expect(out).toContain('plumbing');
  });

  test('tagged-facts override drops the default section', () => {
    const out = buildExtractionPrompt({
      currentState: STATE,
      latestMessage: 'hi',
      conversationSummary: '',
      taggedFactsSection: '\n[CUSTOM TAGGED FACTS]\n',
    });
    expect(out).toContain('[CUSTOM TAGGED FACTS]');
    expect(out).not.toContain('trades-job-types');
  });

  test('frozen-string snapshot for trades section', () => {
    const a = buildTradesTaggedFactsSection();
    const b = buildTradesTaggedFactsSection();
    expect(a).toBe(b);
  });
});

describe('D-O7 — PDF extraction prompt', () => {
  test('embeds the trades job-type list', () => {
    const out = buildPdfExtractionPrompt();
    for (const v of JOB_TYPE_VALUES) {
      expect(out).toContain(`"${v}"`);
    }
  });

  test('contains the EXTRACTION RULES block verbatim', () => {
    const out = buildPdfExtractionPrompt();
    expect(out).toContain('EXTRACTION RULES:');
    expect(out).toContain(
      'For Australian addresses, infer state as "QLD"',
    );
    expect(out).toContain('Tenant is the customer');
    expect(out).toContain('Agent is the referrer');
  });

  test('PDF_EXTRACTION_PROMPT is the frozen build output', () => {
    expect(PDF_EXTRACTION_PROMPT).toBe(buildPdfExtractionPrompt());
  });
});

```
