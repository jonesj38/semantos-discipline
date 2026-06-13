---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/cc6-3b-prompt-template-parameterization.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.150356+00:00
---

# runtime/legacy-ingest/src/__tests__/cc6-3b-prompt-template-parameterization.test.ts

```ts
/**
 * CC6.3b — Acceptance fixture: PROMPT_TEMPLATE is composed from
 * `AdapterConfigMetadata` — agency-name literals in the imperative
 * zones (billing-rules section + POC heuristics + dispatcher example
 * lists + maintenance-order routing mentions) come from
 * `config.billing_rules[].agency_name` + per-rule
 * `prompt_fragments`. A fresh config that does not declare Clever
 * Property / Robert James Realty / Bricks + Agent produces a prompt
 * with NONE of those names in the imperative zones.
 *
 * Per `docs/design/CC6-SOURCE-ADAPTER-IMPL-SPEC.md` v0.6 §6 row CC6.3b:
 *
 *   > a fresh adapter-config produces a prompt that names ONLY its
 *   > declared agencies; existing OJT prompt hash regenerates
 *   > deterministically; existing extraction confidence preserved on
 *   > the CP_07487 + RJR fixtures.
 *
 * Residual coupling (intentional, documented in the PR):
 *
 *   The DEEP-STRUCTURED-FIELDS worked-example block (canonical Clever
 *   Property PDF + its expected JSON output) remains in the static
 *   prompt skeleton in `prompt-builder.ts`. It is OJT-specific TRAINING
 *   DATA showing the LLM the STRUCTURE of a property-management PDF —
 *   it does not make claims about the LLM's recognition set. A future
 *   CC6.3c (or follow-up) could add `worked_examples?` to
 *   `AdapterConfigMetadata` if/when an operator wants to override.
 *   This test does NOT assert "the prompt is free of every literal
 *   string 'Clever Property'" — it asserts the IMPERATIVE zones are
 *   config-driven.
 */

import { describe, expect, test } from 'bun:test';
import { EmailExtractor, parseRfc822 } from '../extractor/email';
import {
  buildPromptTemplate,
  buildBillingRulesSection,
  buildPocHeuristics,
  buildAgencyListInline,
  formatAgencyList,
} from '../extractor/prompt-builder';
import type { ExtractionOutcome, LLMAdapter } from '../extractor/types';
import type { RawItem } from '../types';
import type { AdapterConfigMetadata } from '../adapter-config/types';
import { DEFAULT_ODDJOBZ_ADAPTER_CONFIG } from '../adapter-config/default-oddjobz-config';

const FRESH_CONFIG_NO_OJT_AGENCIES: AdapterConfigMetadata = {
  fallback_operator_emails: ['ops@example.com'],
  billing_rules: [
    {
      agency_name: 'MetaProperty',
      domain_match: { kind: 'ends_with', suffix: 'metaproperty.example.com' },
      outcome: { kind: 'always_agency', agency_name: 'MetaProperty' },
      prompt_fragments: {
        rules_section_text:
          '(sender domain metaproperty.example.com): ALWAYS bill the agency. ' +
          'billing_party = { "type": "agency", "name": "MetaProperty" }.',
      },
    },
    {
      agency_name: 'NeoRealty',
      domain_match: { kind: 'regex', pattern: 'neorealty\\.example\\.com' },
      outcome: { kind: 'owner_if_named_else_agency', agency_name: 'NeoRealty' },
      prompt_fragments: {
        rules_section_text:
          '(sender domain neorealty.example.com): VARIANCE. ' +
          'If the PDF names an owner → bill owner; else bill ' +
          'billing_party = { "type": "agency", "name": "NeoRealty" }.',
        heuristic_text:
          '  - Email from a NeoRealty PM: use "<PM name> (NeoRealty)" when the PM signs off.',
      },
    },
  ],
};

const MINIMAL_CONFIG_NO_RULES: AdapterConfigMetadata = {
  fallback_operator_emails: [],
  billing_rules: [],
};

function stubLLM(payload: unknown, confidence: number): LLMAdapter {
  return {
    async extract<T>() {
      return { payload: payload as T, confidence, raw: JSON.stringify(payload) };
    },
  };
}

describe('CC6.3b — formatAgencyList: English inline list formatting', () => {
  test('[] → ""', () => {
    expect(formatAgencyList([])).toBe('');
  });
  test('["X"] → "X"', () => {
    expect(formatAgencyList(['X'])).toBe('X');
  });
  test('["X", "Y"] → "X or Y"', () => {
    expect(formatAgencyList(['X', 'Y'])).toBe('X or Y');
  });
  test('["X", "Y", "Z"] → "X, Y, or Z"', () => {
    expect(formatAgencyList(['X', 'Y', 'Z'])).toBe('X, Y, or Z');
  });
  test('four-or-more comma-separated, Oxford comma before final or', () => {
    expect(formatAgencyList(['A', 'B', 'C', 'D'])).toBe('A, B, C, or D');
  });
});

describe('CC6.3b — buildBillingRulesSection: rules block reflects config exactly', () => {
  test('default config: rules section enumerates Clever Property, RJR, Bricks + Agent', () => {
    const section = buildBillingRulesSection(DEFAULT_ODDJOBZ_ADAPTER_CONFIG);
    expect(section).toContain('BILLING party rules — apply per source:');
    expect(section).toContain('  - Clever Property');
    expect(section).toContain('  - Robert James Realty');
    expect(section).toContain('  - Bricks + Agent');
    expect(section).toContain('  - Ambiguous / unknown sources: billing_party = null.');
  });

  test('fresh config: rules section enumerates MetaProperty + NeoRealty ONLY (no OJT agencies)', () => {
    const section = buildBillingRulesSection(FRESH_CONFIG_NO_OJT_AGENCIES);
    expect(section).toContain('  - MetaProperty');
    expect(section).toContain('  - NeoRealty');
    expect(section).not.toContain('Clever Property');
    expect(section).not.toContain('Robert James Realty');
    expect(section).not.toContain('Bricks + Agent');
    expect(section).toContain('  - Ambiguous / unknown sources: billing_party = null.');
  });

  test('empty config: rules section degrades to the catch-all line', () => {
    const section = buildBillingRulesSection(MINIMAL_CONFIG_NO_RULES);
    expect(section).toContain('BILLING party rules — apply per source:');
    expect(section).toContain('billing_party = null');
    // The per-rule bullets are absent (only the catch-all).
    expect(section).not.toMatch(/^\s*- (?!All sources|Ambiguous)/m);
  });

  test('rule without prompt_fragments: builder synthesises a minimal entry', () => {
    const synthesised: AdapterConfigMetadata = {
      fallback_operator_emails: [],
      billing_rules: [
        {
          agency_name: 'GenericCo',
          domain_match: { kind: 'ends_with', suffix: 'generic.example.com' },
          outcome: { kind: 'always_agency', agency_name: 'GenericCo' },
          // no prompt_fragments
        },
      ],
    };
    const section = buildBillingRulesSection(synthesised);
    expect(section).toContain('  - GenericCo (sender domain *.generic.example.com): ');
    expect(section).toContain('ALWAYS bill the agency.');
    expect(section).toContain('"name": "GenericCo"');
  });
});

describe('CC6.3b — buildPocHeuristics: heuristic block reflects per-rule fragments', () => {
  test('default config: RJR + Bricks heuristics are present, Clever Property has no heuristic entry', () => {
    const block = buildPocHeuristics(DEFAULT_ODDJOBZ_ADAPTER_CONFIG);
    // RJR heuristic text contains "<PM name> (<agency>)" template.
    expect(block).toContain('<PM name> (<agency>)');
    // Bricks + Agent heuristic text contains the bricksandagent.com pattern.
    expect(block).toContain('bricksandagent.com');
    // Clever Property has no heuristic_text → its content not present in heuristic block.
    expect(block).not.toContain('cleverproperty.com.au, header "8 Thomas St');
  });

  test('fresh config: only the NeoRealty heuristic appears', () => {
    const block = buildPocHeuristics(FRESH_CONFIG_NO_OJT_AGENCIES);
    expect(block).toContain('NeoRealty');
    expect(block).not.toContain('Bricks + Agent');
    expect(block).not.toContain('Robert James Realty');
  });

  test('empty config: heuristic block is empty', () => {
    expect(buildPocHeuristics(MINIMAL_CONFIG_NO_RULES)).toBe('');
  });
});

describe('CC6.3b — buildPromptTemplate: imperative zones name ONLY declared agencies', () => {
  test('fresh config: prompt billing-rules section excludes Clever Property / RJR / Bricks + Agent', () => {
    const prompt = buildPromptTemplate(FRESH_CONFIG_NO_OJT_AGENCIES);
    // Find the BILLING rules section and verify NO OJT agency names appear within it.
    const rulesStart = prompt.indexOf('BILLING party rules');
    expect(rulesStart).toBeGreaterThan(-1);
    // The rules section runs until the next double-newline-then-uppercase-word.
    const rulesSection = prompt.slice(rulesStart, prompt.indexOf('\n\nDATE format'));
    expect(rulesSection).toContain('MetaProperty');
    expect(rulesSection).toContain('NeoRealty');
    expect(rulesSection).not.toContain('Clever Property');
    expect(rulesSection).not.toContain('Robert James Realty');
    expect(rulesSection).not.toContain('Bricks + Agent');
  });

  test('fresh config: agency mentions in classification + POC zones reflect new agencies', () => {
    const prompt = buildPromptTemplate(FRESH_CONFIG_NO_OJT_AGENCIES);
    // The maintenance_order classification interpolation includes the inline agency list.
    expect(prompt).toMatch(/maintenance \/ repair request from a[\s\n]*property manager or tenant \(often routed via MetaProperty or NeoRealty\)/);
    // The dispatcher example list interpolation likewise.
    expect(prompt).toContain('(e.g. MetaProperty or NeoRealty)');
    // POC heuristics block contains only the NeoRealty heuristic.
    expect(prompt).toContain('NeoRealty');
    expect(prompt).not.toContain('bricksandagent.com');
  });

  test('default config: imperative zones still contain all OJT agencies (backward-compat)', () => {
    const prompt = buildPromptTemplate(DEFAULT_ODDJOBZ_ADAPTER_CONFIG);
    // The maintenance_order routing mention names all three OJT agencies.
    expect(prompt).toContain('Clever Property');
    expect(prompt).toContain('Robert James Realty');
    expect(prompt).toContain('Bricks + Agent');
    // The Phase-1 false-positive regression markers still present.
    expect(prompt).toContain('weekly digest summaries');
    expect(prompt).toContain('Google');
    expect(prompt).toContain('Facebook');
  });

  test('empty config: prompt is well-formed and does not name any agency in imperative zones', () => {
    const prompt = buildPromptTemplate(MINIMAL_CONFIG_NO_RULES);
    // Sanity: imperative zones simplify gracefully.
    expect(prompt).not.toContain('(often routed via )');
    expect(prompt).not.toContain('(e.g. )');
    // The worked-example block stays (OJT-style training data; the
    // spec acknowledges this residual coupling).
    expect(prompt).toContain('canonical Clever Property quote request');
  });
});

describe('CC6.3b — promptHash determinism + config sensitivity', () => {
  function emailItem(content: string): RawItem {
    return {
      providerId: 'gmail',
      providerItemId: `msg-${Math.random()}`,
      fetchedAt: 1000,
      contentType: 'email/rfc822',
      bytes: new TextEncoder().encode(content),
      metadata: {},
    };
  }

  const SIMPLE_EMAIL = `From: jane@example.com
To: ops@example.com
Subject: Quote
Message-ID: <1@example.com>

Body.
`;

  async function singleOutcome(
    extractor: EmailExtractor,
    item: RawItem,
    llm: LLMAdapter,
  ): Promise<ExtractionOutcome> {
    const outcomes = await extractor.extract(item, llm);
    expect(outcomes.length).toBe(1);
    return outcomes[0];
  }

  function llmStub(): LLMAdapter {
    return stubLLM({
      job_type: 'quote_request',
      summary: 's',
      customer: { name: 'x', email: '' },
      job: { description: 'x', location: 'x' },
    }, 0.9);
  }

  test('default config: prompt hash is stable across two EmailExtractor instances', async () => {
    const a = new EmailExtractor();
    const b = new EmailExtractor();
    const ra = await singleOutcome(a, emailItem(SIMPLE_EMAIL), llmStub());
    const rb = await singleOutcome(b, emailItem(SIMPLE_EMAIL), llmStub());
    if (ra.kind !== 'extracted' || rb.kind !== 'extracted') {
      throw new Error('expected both outcomes to be extracted');
    }
    expect(ra.proposal.provenance.promptHash).toBe(rb.proposal.provenance.promptHash);
  });

  test('fresh config (different rules) produces a DIFFERENT prompt hash than the default', async () => {
    const def = new EmailExtractor();
    const fresh = new EmailExtractor({ adapterConfig: FRESH_CONFIG_NO_OJT_AGENCIES });
    const rd = await singleOutcome(def, emailItem(SIMPLE_EMAIL), llmStub());
    const rf = await singleOutcome(fresh, emailItem(SIMPLE_EMAIL), llmStub());
    if (rd.kind !== 'extracted' || rf.kind !== 'extracted') {
      throw new Error('expected both outcomes to be extracted');
    }
    expect(rd.proposal.provenance.promptHash).not.toBe(rf.proposal.provenance.promptHash);
  });

  test('two extractors with the SAME fresh config produce the SAME prompt hash', async () => {
    const a = new EmailExtractor({ adapterConfig: FRESH_CONFIG_NO_OJT_AGENCIES });
    const b = new EmailExtractor({ adapterConfig: FRESH_CONFIG_NO_OJT_AGENCIES });
    const ra = await singleOutcome(a, emailItem(SIMPLE_EMAIL), llmStub());
    const rb = await singleOutcome(b, emailItem(SIMPLE_EMAIL), llmStub());
    if (ra.kind !== 'extracted' || rb.kind !== 'extracted') {
      throw new Error('expected both outcomes to be extracted');
    }
    expect(ra.proposal.provenance.promptHash).toBe(rb.proposal.provenance.promptHash);
  });
});

describe('CC6.3b — extractor runs end-to-end under the fresh config (no broken substitutions)', () => {
  test('fresh-config extractor classifies a quote_request as before', async () => {
    const extractor = new EmailExtractor({ adapterConfig: FRESH_CONFIG_NO_OJT_AGENCIES });
    const llm = stubLLM({
      job_type: 'quote_request',
      summary: 'Quote for fence at MetaProperty.',
      customer: { name: 'MetaProperty', email: 'leads@metaproperty.example.com' },
      job: { description: 'fence', location: 'Springfield' },
    }, 0.9);
    const item: RawItem = {
      providerId: 'meta',
      providerItemId: 'cc6-3b-end-to-end-1',
      fetchedAt: 1000,
      contentType: 'email/rfc822',
      bytes: new TextEncoder().encode(`From: leads@metaproperty.example.com
To: ops@metaproperty.example.com
Subject: Quote
Message-ID: <e2e-1@example.com>

Body.
`),
      metadata: {},
    };
    const outcomes = await extractor.extract(item, llm);
    expect(outcomes.length).toBe(1);
    expect(outcomes[0].kind).toBe('extracted');
  });
});

```
