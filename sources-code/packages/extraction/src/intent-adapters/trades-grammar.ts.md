---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/intent-adapters/trades-grammar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.455996+00:00
---

# packages/extraction/src/intent-adapters/trades-grammar.ts

```ts
/**
 * OddJobTodd trades grammar — the first concrete extension grammar for
 * the LLM classifier.
 *
 * This mirrors the vertical chat.ts was originally built around:
 * property-maintenance conversations between a tenant, a property
 * manager, an REA, a landlord, and tradespeople. The grammar captures
 * the actions the classifier can propose and the taxonomy coordinates
 * that resulting intents will carry.
 *
 * Keep this file verbatim-stable across calls — it forms the bulk of
 * the cached system prompt. Changes here invalidate the prompt cache
 * for every subsequent classification.
 *
 * Slice 4: the grammar is parameterised on a Lexicon from
 * @semantos/semantos-sir. This grammar binds to the jural lexicon;
 * other extension grammars (SCADA-style ControlSystems, CDM,
 * BillsOfLading, etc.) pass their own Lexicon.
 */

import { JuralLexicon, type Lexicon, type TrustClass, type ProofRequirement } from '@semantos/semantos-sir';

export interface ActionDefinition {
  /** Verb as it appears on Intent.action. */
  name: string;
  /**
   * Category within the grammar's lexicon. Must be a member of
   * `grammar.lexicon.categories` — the classifier tool schema's
   * `category` enum is generated from those at construction time,
   * so mis-paired categories surface as classifier-output
   * rejections.
   *
   * Typed as `string` at the grammar layer so grammars can be
   * written against any lexicon. The TaggedCategory produced on
   * Intent by the classifier stamps `grammar.lexicon.name` as the
   * discriminant, giving strict per-lexicon narrowing at the Intent
   * consumer level.
   */
  category: string;
  /** Which hat roles can propose this action (used for trust-tier hints). */
  authoredBy: ReadonlyArray<string>;
  /** Short description the classifier sees. */
  description: string;
}

export interface ExtensionGrammarSpec {
  extensionId: string;
  domainFlag: number;
  /**
   * The lexicon this grammar's actions are categorised under.
   * Drives (a) the classifier tool-schema's `category` enum,
   * (b) the `Intent.lexicon` discriminant on PROPOSES outcomes,
   * (c) the prompt text the classifier sees.
   *
   * See `@semantos/semantos-sir`'s `lexicons.ts` for the available
   * lexicons (jural, control-systems, cdm, bills-of-lading,
   * project-management, property-management, risk-assessment,
   * circuit-commands). Custom extension-contributed lexicons can
   * also be passed — the Lexicon typeclass is polymorphic.
   */
  lexicon: Lexicon;
  /** Default taxonomy `what` coordinate when the model doesn't resolve a specific type. */
  defaultTaxonomyWhat: string;
  actions: ReadonlyArray<ActionDefinition>;
  /** Named object types the grammar recognises (taxonomy `what` coordinates). */
  objectTypes: ReadonlyArray<{ name: string; description: string }>;
  /**
   * Maximum trust class this grammar's intents can carry. The astronomy pass
   * caps `GovernanceContext.trustClass` at this value. Defaults to 'cosmetic'
   * when absent — callers must explicitly declare 'interpretive' or
   * 'authoritative' for higher-stakes domains.
   */
  trustClass?: TrustClass;
  /**
   * Proof requirement for authoritative intents under this grammar.
   * The astronomy pass enforces: if trustClass='authoritative' then
   * proofRequirement must be 'formal'. Defaults to 'none'.
   */
  proofRequirement?: ProofRequirement;
}

/**
 * Trades grammar — actions grouped by the party that originates them.
 * Kept narrow deliberately; expand only when real conversation corpora
 * demand new verbs.
 */
export const TRADES_GRAMMAR: ExtensionGrammarSpec = {
  extensionId: 'odd-job-todd',
  domainFlag: 7,
  lexicon: JuralLexicon,
  defaultTaxonomyWhat: 'maintenance.job',

  objectTypes: [
    { name: 'maintenance.job', description: 'A property maintenance work order.' },
    { name: 'maintenance.quote', description: 'A priced estimate for a job.' },
    { name: 'maintenance.visit', description: 'A scheduled site visit.' },
    { name: 'maintenance.invoice', description: 'An invoice for completed work.' },
  ],

  actions: [
    {
      name: 'report_issue',
      category: 'declaration',
      authoredBy: ['tenant'],
      description:
        'The tenant reports a maintenance issue (e.g. dripping tap, broken heater).',
    },
    {
      name: 'request_photos',
      category: 'obligation',
      authoredBy: ['pm', 'rea'],
      description: 'PM/REA asks the tenant for photos to diagnose the issue.',
    },
    {
      name: 'attach_photos',
      category: 'declaration',
      authoredBy: ['tenant'],
      description: 'The tenant attaches photos of the reported issue.',
    },
    {
      name: 'request_quote',
      category: 'declaration',
      authoredBy: ['pm', 'rea'],
      description: 'Solicit a quote from a tradesperson for the job.',
    },
    {
      name: 'submit_quote',
      category: 'declaration',
      authoredBy: ['tradesperson'],
      description: 'A tradesperson submits a priced quote for the job.',
    },
    {
      name: 'approve_quote',
      category: 'power',
      authoredBy: ['landlord', 'rea'],
      description:
        'Authorise a quote. Landlord approval is authoritative-tier when ' +
        'the amount exceeds the REA discretionary threshold.',
    },
    {
      name: 'schedule_visit',
      category: 'condition',
      authoredBy: ['pm', 'tradesperson'],
      description: 'Schedule a site visit on the calendar.',
    },
    {
      name: 'mark_work_complete',
      category: 'declaration',
      authoredBy: ['tradesperson'],
      description: 'Tradesperson marks the job work complete.',
    },
    {
      name: 'issue_invoice',
      category: 'transfer',
      authoredBy: ['tradesperson'],
      description: 'Tradesperson issues an invoice for the completed work.',
    },
    {
      name: 'pay_invoice',
      category: 'transfer',
      authoredBy: ['pm', 'landlord'],
      description: 'Pay the tradesperson invoice.',
    },
  ],
};

```
