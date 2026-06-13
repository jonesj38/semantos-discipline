---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/adapter-config/default-oddjobz-config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.156192+00:00
---

# runtime/legacy-ingest/src/adapter-config/default-oddjobz-config.ts

```ts
/**
 * CC6.3a — Default adapter-config for the oddjobz pipeline.
 *
 * Captures the data that used to live as hardcoded constants inside
 * `runtime/legacy-ingest/src/extractor/email.ts`:
 *
 *   - `FALLBACK_OPERATOR_EMAILS` (was lines 71–74) → `fallback_operator_emails`
 *   - `CLEVER_PROPERTY_NAME` + Clever Property domain rule → first `billing_rules` entry
 *   - `ROBERT_JAMES_NAME` + RJR domain rule + owner variance → second entry
 *   - Bricks + Agent domain rule + LLM-trust outcome → third entry
 *   - body-text fallback substrings → `body_substrings` on the rules
 *
 * Behaviour is **byte-identical** to the pre-CC6.3a hardcode: the
 * EmailExtractor falls back to this object when no `adapterConfig` is
 * supplied via constructor options, and the rule-matching logic in
 * `normaliseBillingParty()` consults the same domains + substrings in
 * the same order it used to consult constants. The point of the move is
 * **shape**, not behaviour change.
 *
 * Future work (CC6.3b, then brain-side adapter-config cell fetch) will
 * lift this constant into either the oddjobz cartridge or a brain
 * round-trip. Until then, this file is the "seeded fallback" that keeps
 * production oddjobz ingest working with the same agency routing.
 *
 * See `docs/design/CC6-SOURCE-ADAPTER-IMPL-SPEC.md` v0.5 §5.
 */

import type { AdapterConfigMetadata } from './types';

export const DEFAULT_ODDJOBZ_ADAPTER_CONFIG: AdapterConfigMetadata = {
  fallback_operator_emails: [
    'todd.price.aus@gmail.com',
    'todd@oddjobtodd.com.au',
  ],
  billing_rules: [
    {
      agency_name: 'Clever Property',
      domain_match: { kind: 'ends_with', suffix: 'cleverproperty.com.au' },
      body_substrings: ['cleverproperty.com.au', '8 thomas st'],
      outcome: { kind: 'always_agency', agency_name: 'Clever Property' },
      // CC6.3b — Prompt pedagogy that used to be hardcoded in
      // PROMPT_TEMPLATE at email.ts:523–526.
      prompt_fragments: {
        rules_section_text:
          '(sender domain cleverproperty.com.au, header "8 Thomas St Noosaville"): ' +
          'ALWAYS bill the agency, regardless of owner. ' +
          'billing_party = { "type": "agency", "name": "Clever Property" }.',
      },
    },
    {
      agency_name: 'Robert James Realty',
      domain_match: { kind: 'regex', pattern: 'robertjamesrealty\\.' },
      body_substrings: ['robertjamesrealty', 'robert james realty'],
      outcome: { kind: 'owner_if_named_else_agency', agency_name: 'Robert James Realty' },
      // CC6.3b — Was PROMPT_TEMPLATE lines 527–532 + 374–377.
      prompt_fragments: {
        rules_section_text:
          '(sender domain robertjamesrealty.com.au or similar): VARIANCE. ' +
          'If the "issued on behalf of" line names the OWNER ' +
          '(e.g. "issued on behalf of John Smith") → ' +
          'billing_party = { "type": "owner", "name": "<owner>" }. ' +
          'If it names RJR / "Robert James" / the agency itself, OR the line ' +
          'is absent → billing_party = { "type": "agency", "name": "Robert James Realty" }.',
        heuristic_text:
          '  - Email from a property manager at a real estate agency: use\n' +
          '    "<PM name> (<agency>)" when the PM signs off\n' +
          '    (e.g. "Matthew Pohlen (Robert James Realty)"), or just the agency\n' +
          '    name when no PM is named (e.g. "Robert James Realty").',
      },
    },
    {
      agency_name: 'Bricks + Agent',
      domain_match: { kind: 'ends_with', suffix: 'bricksandagent.com' },
      outcome: { kind: 'trust_llm_or_fallback_agency', agency_name: 'Bricks + Agent' },
      // CC6.3b — Was PROMPT_TEMPLATE lines 533–535 + 370–373.
      prompt_fragments: {
        rules_section_text:
          '(sender domain bricksandagent.com): bill the routed agency / PM ' +
          '(whichever entity Bricks names). ' +
          'billing_party = { "type": "agency", "name": "<routed agency>" }.',
        heuristic_text:
          '  - Email from `noreply@bricksandagent.com` or any `*@bricksandagent.com`\n' +
          '    auto-dispatch address: use "Bricks + Agent" — append " — <PM name>"\n' +
          '    if a property manager is named in the routed order\n' +
          '    (e.g. "Bricks + Agent — Lisa Tran").',
      },
    },
  ],
};

```
