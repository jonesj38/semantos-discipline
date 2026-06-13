---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/cc6-3a-adapter-config-extension.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.147810+00:00
---

# runtime/legacy-ingest/src/__tests__/cc6-3a-adapter-config-extension.test.ts

```ts
/**
 * CC6.3a — Acceptance fixture: a NEW operator / NEW agency / NEW source
 * yields a valid canonical billing-party with **zero edits** to
 * `runtime/legacy-ingest/src/extractor/email.ts`.
 *
 * Per `docs/design/CC6-SOURCE-ADAPTER-IMPL-SPEC.md` v0.5 §6 row CC6.3:
 *
 *   > Retire `FALLBACK_OPERATOR_EMAILS` + per-agency prompt rules →
 *   > adapter-config + `entityMappings[].condition`; transport
 *   > untouched.
 *
 *   > Acceptance: a fixture "new operator, new agency, Meta source"
 *   > yields valid canonical cells with ZERO `extractor/` code edits;
 *   > existing oddjobz ingest unchanged.
 *
 * CC6.3a delivers the substrate of this acceptance — the runtime
 * constants + per-agency normalisation rules now live in
 * `AdapterConfigMetadata` (a structured `BillingRule[]` + an explicit
 * `fallback_operator_emails` list). The default
 * (`DEFAULT_ODDJOBZ_ADAPTER_CONFIG`) preserves existing oddjobz
 * behaviour exactly (the existing 38-test email-extractor suite still
 * passes unmodified). This test exercises the OTHER half: passing a
 * fresh config with a new agency entry → the extractor routes it
 * correctly with no code path changes.
 *
 * CC6.3b will move the agency-name strings in PROMPT_TEMPLATE (LLM
 * pedagogy) into the same config — this file demonstrates only the
 * runtime-rule retirement.
 */

import { describe, expect, test } from 'bun:test';
import { EmailExtractor } from '../extractor/email';
import type { ExtractionOutcome, LLMAdapter } from '../extractor/types';
import type { RawItem } from '../types';
import type { AdapterConfigMetadata } from '../adapter-config/types';

function stubLLM(payload: unknown, confidence: number): LLMAdapter {
  return {
    async extract<T>() {
      return { payload: payload as T, confidence, raw: JSON.stringify(payload) };
    },
  };
}

function emailItem(content: string): RawItem {
  return {
    providerId: 'meta',
    providerItemId: 'msg-cc6-3a-1',
    fetchedAt: 1000,
    contentType: 'email/rfc822',
    bytes: new TextEncoder().encode(content),
    metadata: {},
  };
}

async function singleOutcome(
  extractor: EmailExtractor,
  item: RawItem,
  llm: LLMAdapter,
): Promise<ExtractionOutcome> {
  const outcomes = await extractor.extract(item, llm);
  expect(outcomes.length).toBe(1);
  return outcomes[0];
}

/**
 * A fresh AdapterConfigMetadata for the acceptance scenario. NONE of
 * the agency names appear in the EmailExtractor source — they are
 * data, passed in by the caller. A real CC6.3-and-beyond deployment
 * would source this from a brain-side adapter-config cell.
 */
const NEW_OPERATOR_CONFIG: AdapterConfigMetadata = {
  fallback_operator_emails: ['ops@metaproperty.example.com'],
  billing_rules: [
    // New agency: MetaProperty — always-agency rule (analogous to Clever Property).
    {
      agency_name: 'MetaProperty',
      domain_match: { kind: 'ends_with', suffix: 'metaproperty.example.com' },
      body_substrings: ['metaproperty.example.com'],
      outcome: { kind: 'always_agency', agency_name: 'MetaProperty' },
    },
    // New agency: NeoRealty — owner-variance rule (analogous to RJR).
    {
      agency_name: 'NeoRealty',
      domain_match: { kind: 'regex', pattern: 'neorealty[a-z0-9-]*\\.example\\.com' },
      outcome: { kind: 'owner_if_named_else_agency', agency_name: 'NeoRealty' },
    },
  ],
};

const META_EMAIL_FROM_NEW_AGENCY = `From: leads@metaproperty.example.com
To: ops@metaproperty.example.com
Subject: Quote: 12 Test Lane, Springfield
Message-ID: <new-agency-1@example.com>

Hi, please quote a fence repair at 12 Test Lane, Springfield.
`;

const NEORALTY_EMAIL_WITH_OWNER = `From: dispatch@neorealty-prod.example.com
To: ops@metaproperty.example.com
Subject: Quote: 5 Owner St, Springfield
Message-ID: <new-agency-2@example.com>

Issued on behalf of owner Sam Doe.
`;

const NEORALTY_EMAIL_NO_OWNER = `From: dispatch@neorealty-prod.example.com
To: ops@metaproperty.example.com
Subject: Quote: 7 Vacant Way, Springfield
Message-ID: <new-agency-3@example.com>

No owner name available.
`;

describe('CC6.3a — new operator/agency/source routes via adapter-config with zero email.ts edits', () => {
  test('a brand-new agency (always_agency) is routed by adapter-config alone', async () => {
    const extractor = new EmailExtractor({ adapterConfig: NEW_OPERATOR_CONFIG });
    const llm = stubLLM({
      job_type: 'quote_request',
      summary: 'Quote for fence at MetaProperty-routed lead.',
      customer: { name: 'MetaProperty', email: 'leads@metaproperty.example.com' },
      job: { description: 'fence repair', location: 'Springfield' },
      // The LLM happens to guess an "owner" billing — the adapter-config
      // domain match for MetaProperty overrides to agency.
      billing_party: { type: 'owner', name: 'Owner Person' },
    }, 0.9);

    const outcome = await singleOutcome(extractor, emailItem(META_EMAIL_FROM_NEW_AGENCY), llm);
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind !== 'extracted') return;
    expect(outcome.proposal.billingParty).toEqual({
      type: 'agency',
      name: 'MetaProperty',
    });
  });

  test('a brand-new agency (owner_if_named_else_agency) bills owner when LLM extracted an owner_name', async () => {
    const extractor = new EmailExtractor({ adapterConfig: NEW_OPERATOR_CONFIG });
    const llm = stubLLM({
      job_type: 'work_order',
      summary: 'Work order from NeoRealty for Sam Doe.',
      customer: { name: 'Sam Doe', email: '' },
      job: { description: 'general maintenance', location: 'Springfield' },
      owner_name: 'Sam Doe',
      billing_party: { type: 'agency', name: 'NeoRealty' }, // LLM says agency; rule overrides to owner
    }, 0.9);

    const outcome = await singleOutcome(extractor, emailItem(NEORALTY_EMAIL_WITH_OWNER), llm);
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind !== 'extracted') return;
    expect(outcome.proposal.billingParty).toEqual({
      type: 'owner',
      name: 'Sam Doe',
    });
  });

  test('a brand-new agency (owner_if_named_else_agency) bills the agency when no owner_name was extracted', async () => {
    const extractor = new EmailExtractor({ adapterConfig: NEW_OPERATOR_CONFIG });
    const llm = stubLLM({
      job_type: 'work_order',
      summary: 'Work order from NeoRealty, no owner identified.',
      customer: { name: '', email: '' },
      job: { description: 'general maintenance', location: 'Springfield' },
      // owner_name omitted
    }, 0.9);

    const outcome = await singleOutcome(extractor, emailItem(NEORALTY_EMAIL_NO_OWNER), llm);
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind !== 'extracted') return;
    expect(outcome.proposal.billingParty).toEqual({
      type: 'agency',
      name: 'NeoRealty',
    });
  });

  test('an email from a domain NOT in the new config falls through to the LLM-trust path', async () => {
    // The new config has only MetaProperty + NeoRealty. An email from
    // a wholly different domain matches no rule → Phase 3 (LLM trust)
    // returns whatever the LLM emitted.
    const extractor = new EmailExtractor({ adapterConfig: NEW_OPERATOR_CONFIG });
    const llm = stubLLM({
      job_type: 'quote_request',
      summary: 'Quote from a random sender unknown to the config.',
      customer: { name: 'Random Sender', email: '' },
      job: { description: 'plumbing', location: 'Springfield' },
      billing_party: { type: 'agency', name: 'Random Agency' },
    }, 0.9);

    const unknownEmail = `From: someone@unknown-agency.example.com
To: ops@metaproperty.example.com
Subject: Random quote
Message-ID: <random-1@example.com>

Body.
`;

    const outcome = await singleOutcome(extractor, emailItem(unknownEmail), llm);
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind !== 'extracted') return;
    expect(outcome.proposal.billingParty).toEqual({
      type: 'agency',
      name: 'Random Agency',
    });
  });

  test('default config (no override) preserves existing Clever Property routing — backward compatibility', async () => {
    // No `adapterConfig` arg → DEFAULT_ODDJOBZ_ADAPTER_CONFIG, which
    // contains Clever Property. This is the regression guard the
    // existing 38-test email-extractor suite covers in full; we add
    // a one-line spot-check here to make the backward-compat
    // contract explicit in this acceptance file.
    const extractor = new EmailExtractor();
    const llm = stubLLM({
      job_type: 'quote_request',
      summary: 'Clever Property quote.',
      customer: { name: 'Tenant', email: '' },
      job: { description: 'paint', location: 'Tewantin' },
      // LLM emits owner — domain rule overrides to agency.
      billing_party: { type: 'owner', name: 'Owner Name' },
    }, 0.9);

    const cleverEmail = `From: pm@cleverproperty.com.au
To: todd@oddjobtodd.com.au
Subject: CP quote
Message-ID: <cp-default-1@example.com>

Body.
`;

    const outcome = await singleOutcome(extractor, emailItem(cleverEmail), llm);
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind !== 'extracted') return;
    expect(outcome.proposal.billingParty).toEqual({
      type: 'agency',
      name: 'Clever Property',
    });
  });
});

```
