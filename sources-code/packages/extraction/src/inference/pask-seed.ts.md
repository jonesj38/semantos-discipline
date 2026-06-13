---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/pask-seed.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.464880+00:00
---

# packages/extraction/src/inference/pask-seed.ts

```ts
/**
 * G-1 — Pask store seed.
 *
 * Pre-loads known grammar field→taxonomy associations from the existing
 * grammar corpus (PropertyMe, trades, SCADA, CDM, etc.) into a PaskAdapter
 * so that the TaxonomyMapper (G-2) starts with a rich prior.
 *
 * Each confirmed (fieldPath, taxonomyPath) association is encoded as a Pask
 * interaction. The store learns: fields that co-activate with the same
 * taxonomy paths as these seeds belong to the same semantic type region.
 *
 * Config: propagationDepth=3, learningRate=0.05 (slower than real-time Pask
 * — stability > speed for offline corpus inference).
 *
 * See docs/textbook/33-automated-grammar-synthesis.md §Stage 2
 */

import { PaskAdapter, type PaskConfig } from '../../../../core/pask/bindings/ts/src';

export const GRAMMAR_INFERENCE_PASK_CONFIG: Partial<PaskConfig> = {
  propagationDepth: 3,
  learningRate: 0.05,
  pruneThreshold: -0.1,
  stabilityEpsilon: 0.005,
  minInteractions: 2,
};

// ---------------------------------------------------------------------------
// Known corpus: confirmed field → taxonomy associations
// Each entry is { field, what, how, why, source } where field is the
// canonical source field name from the grammar it came from.
// ---------------------------------------------------------------------------

export interface CorpusEntry {
  field: string;
  what: string;
  how: string;
  why: string;
  source: string; // grammar ID / vertical name
}

export const GRAMMAR_CORPUS: CorpusEntry[] = [
  // ── Trades / Property Maintenance ──────────────────────────────
  { field: 'job_id',           what: 'what.record.job',          how: 'how.technical.api.rest', why: 'why.integration.property-management', source: 'trades' },
  { field: 'job_type',         what: 'what.record.job',          how: 'how.technical.api.rest', why: 'why.integration.property-management', source: 'trades' },
  { field: 'scope_description',what: 'what.record.job',          how: 'how.technical.api.rest', why: 'why.maintenance.repair',              source: 'trades' },
  { field: 'urgency',          what: 'what.record.job',          how: 'how.technical.api.rest', why: 'why.maintenance.repair',              source: 'trades' },
  { field: 'property_id',      what: 'what.object.property',     how: 'how.technical.api.rest', why: 'why.integration.property-management', source: 'propertyme' },
  { field: 'street_address',   what: 'what.object.property',     how: 'how.technical.api.rest', why: 'why.integration.property-management', source: 'propertyme' },
  { field: 'suburb',           what: 'what.object.property',     how: 'how.technical.api.rest', why: 'why.integration.property-management', source: 'propertyme' },
  { field: 'bedrooms',         what: 'what.object.property',     how: 'how.technical.api.rest', why: 'why.integration.property-management', source: 'propertyme' },
  { field: 'quote_amount',     what: 'what.record.quote',        how: 'how.commercial.transfer', why: 'why.finance.billing',               source: 'trades' },
  { field: 'invoice_number',   what: 'what.record.invoice',      how: 'how.commercial.transfer', why: 'why.finance.billing',               source: 'trades' },
  { field: 'invoice_amount',   what: 'what.record.invoice',      how: 'how.commercial.transfer', why: 'why.finance.billing',               source: 'trades' },
  { field: 'visit_date',       what: 'what.event.visit',         how: 'how.technical.api.rest', why: 'why.maintenance.inspection',         source: 'trades' },
  { field: 'tradesperson_id',  what: 'what.person.tradesperson', how: 'how.technical.api.rest', why: 'why.integration.property-management', source: 'trades' },
  { field: 'landlord_id',      what: 'what.person.owner',        how: 'how.technical.api.rest', why: 'why.integration.property-management', source: 'propertyme' },
  { field: 'tenant_id',        what: 'what.person.tenant',       how: 'how.technical.api.rest', why: 'why.integration.property-management', source: 'propertyme' },

  // ── SCADA / Process Automation ────────────────────────────────
  { field: 'tag',              what: 'what.object.equipment',    how: 'how.technical.api.rest', why: 'why.operations.monitoring',           source: 'scada' },
  { field: 'equipment_id',     what: 'what.object.equipment',    how: 'how.technical.api.rest', why: 'why.operations.monitoring',           source: 'scada' },
  { field: 'measurement_value',what: 'what.resource.measurement',how: 'how.technical.database', why: 'why.operations.monitoring',           source: 'scada' },
  { field: 'setpoint',         what: 'what.resource.control',    how: 'how.technical.database', why: 'why.operations.control',             source: 'scada' },
  { field: 'alarm_id',         what: 'what.event.alarm',         how: 'how.technical.database', why: 'why.safety.alert',                   source: 'scada' },
  { field: 'alarm_state',      what: 'what.event.alarm',         how: 'how.technical.database', why: 'why.safety.alert',                   source: 'scada' },
  { field: 'interlock_id',     what: 'what.process.interlock',   how: 'how.technical.database', why: 'why.safety.interlock',               source: 'scada' },
  { field: 'interlock_active', what: 'what.process.interlock',   how: 'how.technical.database', why: 'why.safety.interlock',               source: 'scada' },

  // ── CDM (Common Data Model) ───────────────────────────────────
  { field: 'account_id',       what: 'what.record.account',      how: 'how.technical.api.rest', why: 'why.finance.accounting',             source: 'cdm' },
  { field: 'contact_id',       what: 'what.person.contact',      how: 'how.technical.api.rest', why: 'why.operations.management',          source: 'cdm' },
  { field: 'opportunity_id',   what: 'what.record.opportunity',  how: 'how.technical.api.rest', why: 'why.operations.management',          source: 'cdm' },
  { field: 'contract_id',      what: 'what.record.contract',     how: 'how.technical.api.rest', why: 'why.compliance.audit',               source: 'cdm' },
  { field: 'amount',           what: 'what.record.transaction',  how: 'how.commercial.transfer', why: 'why.finance.billing',               source: 'cdm' },
  { field: 'currency',         what: 'what.record.transaction',  how: 'how.commercial.transfer', why: 'why.finance.accounting',            source: 'cdm' },

  // ── Project Management ────────────────────────────────────────
  { field: 'project_id',       what: 'what.process.project',     how: 'how.technical.api.rest', why: 'why.operations.management',          source: 'project-management' },
  { field: 'task_id',          what: 'what.process.task',        how: 'how.technical.api.rest', why: 'why.operations.management',          source: 'project-management' },
  { field: 'assignee_id',      what: 'what.person.employee',     how: 'how.technical.api.rest', why: 'why.operations.management',          source: 'project-management' },
  { field: 'due_date',         what: 'what.process.task',        how: 'how.technical.api.rest', why: 'why.operations.management',          source: 'project-management' },
  { field: 'status',           what: 'what.process.workflow',    how: 'how.technical.api.rest', why: 'why.operations.management',          source: 'project-management' },
  { field: 'priority',         what: 'what.process.workflow',    how: 'how.technical.api.rest', why: 'why.operations.management',          source: 'project-management' },
];

// ---------------------------------------------------------------------------
// Cell ID encoding
// ---------------------------------------------------------------------------

/** Stable cell ID for a (field, axis, path) triple. */
export function fieldTaxonomyCell(field: string, axis: 'what' | 'how' | 'why', path: string): string {
  return `corpus:${axis}:${field}:${path}`;
}

/** Stable cell ID for a taxonomy path node (shared across fields). */
export function taxonomyPathCell(axis: 'what' | 'how' | 'why', path: string): string {
  return `taxonomy:${axis}:${path}`;
}

// ---------------------------------------------------------------------------
// Seed function
// ---------------------------------------------------------------------------

/**
 * Seed a PaskAdapter with the known corpus. After seeding, call
 * `adapter.finalize()` before running TaxonomyMapper queries.
 *
 * @param adapter - A freshly constructed PaskAdapter (empty store).
 */
export async function seedPaskStore(adapter: PaskAdapter): Promise<void> {
  const nowMs = Date.now();

  for (const entry of GRAMMAR_CORPUS) {
    for (const axis of ['what', 'how', 'why'] as const) {
      const fieldCell = fieldTaxonomyCell(entry.field, axis, entry[axis]);
      const taxCell = taxonomyPathCell(axis, entry[axis]);

      // Interact: field cell co-activates with the taxonomy path cell.
      // strength=1.0 — confirmed corpus association.
      await adapter.interact({
        cellId: fieldCell,
        kind: `taxonomy:${axis}`,
        strength: 1.0,
        relatedCells: [taxCell],
        nowMs,
      });
    }
  }

  adapter.finalize(nowMs);
}

```
