---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/trades-grammar-spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.515038+00:00
---

# cartridges/oddjobz/brain/src/conversation/trades-grammar-spec.ts

```ts
/**
 * TRADES_GRAMMAR_SPEC — GrammarSpec-shaped binding for the trades vertical.
 *
 * This bridges the full ExtensionGrammarSpec (from extensions/extraction)
 * to the minimal GrammarSpec interface that runtime/intent's reducer uses.
 * Declared here (in oddjobz) rather than in extraction so the dependency
 * direction stays unidirectional: oddjobz → intent, not intent → extraction.
 */

import type { GrammarSpec } from '@semantos/intent/reducer/types';

export const TRADES_GRAMMAR_SPEC: GrammarSpec = {
  extensionId: 'odd-job-todd',
  domainFlag: 7,
  lexicon: {
    name: 'jural',
    categories: ['declaration', 'obligation', 'power', 'condition', 'transfer'],
  },
  defaultTaxonomyWhat: 'maintenance.job',
  objectTypes: [
    { name: 'maintenance.job',     description: 'A property maintenance work order.' },
    { name: 'maintenance.quote',   description: 'A priced estimate for a job.' },
    { name: 'maintenance.visit',   description: 'A scheduled site visit.' },
    { name: 'maintenance.invoice', description: 'An invoice for completed work.' },
  ],
  actions: [
    { name: 'report_issue',       category: 'declaration', authoredBy: ['tenant'],              description: 'Tenant reports a maintenance issue.' },
    { name: 'request_photos',     category: 'obligation',  authoredBy: ['pm', 'rea'],           description: 'PM/REA asks for photos.' },
    { name: 'attach_photos',      category: 'declaration', authoredBy: ['tenant'],              description: 'Tenant attaches photos.' },
    { name: 'request_quote',      category: 'declaration', authoredBy: ['pm', 'rea'],           description: 'Solicit a quote.' },
    { name: 'submit_quote',       category: 'declaration', authoredBy: ['tradesperson'],        description: 'Tradesperson submits a quote.' },
    { name: 'approve_quote',      category: 'power',       authoredBy: ['landlord', 'rea'],     description: 'Authorise a quote.' },
    { name: 'schedule_visit',     category: 'condition',   authoredBy: ['pm', 'tradesperson'],  description: 'Schedule a site visit.' },
    { name: 'mark_work_complete', category: 'declaration', authoredBy: ['tradesperson'],        description: 'Mark job work complete.' },
    { name: 'issue_invoice',      category: 'transfer',    authoredBy: ['tradesperson'],        description: 'Issue an invoice.' },
    { name: 'pay_invoice',        category: 'transfer',    authoredBy: ['pm', 'landlord'],      description: 'Pay the invoice.' },
  ],
  trustClass: 'interpretive',
  proofRequirement: 'attestation',
};

```
