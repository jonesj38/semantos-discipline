---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/lexicons.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.813002+00:00
---

# core/semantos-sir/src/lexicons.ts

```ts
/**
 * Lexicon abstraction — parameterises the category dimension of SIRNode.
 *
 * The existing `JuralCategory` type (in ./types.ts) is one specific
 * lexicon — the Hohfeldian vocabulary for legal/contractual discourse.
 * Additional lexicons (ControlSystems, TradeLifecycle, Clinical, audio-
 * production, film-editing, …) plug in here to provide alternative
 * semantic-intent vocabularies on the same patch substrate.
 *
 * Formal correspondence (Lean 4 proofs):
 *   proofs/lean/Semantos/Substrate/Lexicon.lean
 *     — defines the `Lexicon` typeclass with the injectivity obligation
 *   proofs/lean/Semantos/Lexicons/Jural.lean
 *     — JuralLexicon instance + juralHeader_injective theorem
 *   proofs/lean/Semantos/Lexicons/ControlSystems.lean
 *     — ControlSystemsLexicon instance + controlSystemsHeader_injective
 *
 * Substrate invariants (M1-M4 merge, D1-D3 diff, renderCard_*) are proved
 * once at `Patch α` and apply to every lexicon by specialisation — see
 * proofs/lean/Semantos/Substrate/Merge.lean and Diff.lean.
 */

import type { JuralCategory } from './types';
import {
  type Lexicon,
  verifyLexiconInjective,
  isCategoryOf,
} from '@semantos/lexicon-core';
import { relationLexicon, type RelationKind } from '@semantos/scg-relations';

// ── Lexicon interface ──────────────────────────────────────────────────

/**
 * Re-export the `Lexicon` interface + helpers from `@semantos/lexicon-core`
 * so existing consumers (`import { Lexicon, verifyLexiconInjective } from
 * '@semantos/semantos-sir'`) keep working. The interface lives in
 * `lexicon-core` so domain packages (`@semantos/scg-relations`, future
 * lexicon authors) can depend on it without dragging in the SIR stack —
 * see core/lexicon-core/src/index.ts for rationale.
 */
export { type Lexicon, verifyLexiconInjective, isCategoryOf };

// ── Jural Lexicon ──────────────────────────────────────────────────────

/** Legal / Hohfeldian discourse. The seven categories classify jural
    relations between parties: declaration, obligation, permission,
    prohibition, power, condition, transfer.
    Formal proof: `juralHeader_injective` in Lexicons/Jural.lean. */
export const JuralLexicon: Lexicon<JuralCategory> = {
  name: 'jural',
  categories: [
    'declaration',
    'obligation',
    'permission',
    'prohibition',
    'power',
    'condition',
    'transfer',
  ] as const,
  header: (c) => c.toUpperCase(),
};

// ── Control Systems Lexicon ────────────────────────────────────────────

/** Semantic-intent vocabulary for SCADA, process automation, and
    safety-instrumented systems. Orthogonal to the jural vocabulary —
    a plant operator isn't making declarations and transfers; they're
    issuing setpoints, acknowledging alarms, and enforcing interlocks. */
export type ControlSystemsCategory =
  | 'measurement'
  | 'setpoint'
  | 'actuation'
  | 'interlock'
  | 'alarm'
  | 'acknowledgement'
  | 'calibration';

/** Formal proof: `controlSystemsHeader_injective` in
    Lexicons/ControlSystems.lean. Note the non-identity mapping on
    'acknowledgement' → 'ACK' demonstrates that the header function can
    be non-trivial while still provably injective. */
export const ControlSystemsLexicon: Lexicon<ControlSystemsCategory> = {
  name: 'control-systems',
  categories: [
    'measurement',
    'setpoint',
    'actuation',
    'interlock',
    'alarm',
    'acknowledgement',
    'calibration',
  ] as const,
  header: (c) => (c === 'acknowledgement' ? 'ACK' : c.toUpperCase()),
};

// ── Circuit Commands Lexicon ───────────────────────────────────────────

/** Fine-grained verb-level vocabulary for electrical / circuit operations.
    Each category has distinct operational consequences warranting
    category-level status (charge vs discharge is a real-world injury
    if confused). Formal proof: `circuitHeader_injective` in
    Lexicons/CircuitCommands.lean. */
export type CircuitCommandsCategory =
  | 'charge'
  | 'discharge'
  | 'connect'
  | 'disconnect'
  | 'bias'
  | 'clamp'
  | 'trip';

export const CircuitCommandsLexicon: Lexicon<CircuitCommandsCategory> = {
  name: 'circuit-commands',
  categories: [
    'charge',
    'discharge',
    'connect',
    'disconnect',
    'bias',
    'clamp',
    'trip',
  ] as const,
  header: (c) => c.toUpperCase(),
};

// ── CDM (Common Domain Model) Lexicon ──────────────────────────────────

/** ISDA Common Domain Model lifecycle events for financial derivatives.
    Formal proof: `cdmHeader_injective` in Lexicons/CDM.lean. */
export type CDMCategory =
  | 'confirmation'
  | 'amendment'
  | 'allocation'
  | 'exercise'
  | 'termination'
  | 'novation'
  | 'settlement';

export const CDMLexicon: Lexicon<CDMCategory> = {
  name: 'cdm',
  categories: [
    'confirmation',
    'amendment',
    'allocation',
    'exercise',
    'termination',
    'novation',
    'settlement',
  ] as const,
  header: (c) => c.toUpperCase(),
};

// ── Bills of Lading Lexicon ────────────────────────────────────────────

/** Maritime / multimodal Bill of Lading lifecycle events.
    Formal proof: `billsOfLadingHeader_injective`. */
export type BillsOfLadingCategory =
  | 'issuance'
  | 'endorsement'
  | 'surrender'
  | 'transshipment'
  | 'amendment'
  | 'release'
  | 'claim';

export const BillsOfLadingLexicon: Lexicon<BillsOfLadingCategory> = {
  name: 'bills-of-lading',
  categories: [
    'issuance',
    'endorsement',
    'surrender',
    'transshipment',
    'amendment',
    'release',
    'claim',
  ] as const,
  header: (c) => c.toUpperCase(),
};

// ── Project Management Lexicon ─────────────────────────────────────────

/** PMBOK / PRINCE2-style work-breakdown and execution lifecycle.
    Formal proof: `projectManagementHeader_injective`. */
export type ProjectManagementCategory =
  | 'scope'
  | 'plan'
  | 'commitment'
  | 'execution'
  | 'change'
  | 'review'
  | 'closure';

export const ProjectManagementLexicon: Lexicon<ProjectManagementCategory> = {
  name: 'project-management',
  categories: [
    'scope',
    'plan',
    'commitment',
    'execution',
    'change',
    'review',
    'closure',
  ] as const,
  header: (c) => c.toUpperCase(),
};

// ── Property Management Lexicon ────────────────────────────────────────

/** Rental-operations lifecycle (distinct from sale-prep in the
    estate-to-auction demo). Formal proof:
    `propertyManagementHeader_injective`. */
export type PropertyManagementCategory =
  | 'lease'
  | 'maintenance'
  | 'inspection'
  | 'rent'
  | 'violation'
  | 'renewal'
  | 'termination';

export const PropertyManagementLexicon: Lexicon<PropertyManagementCategory> = {
  name: 'property-management',
  categories: [
    'lease',
    'maintenance',
    'inspection',
    'rent',
    'violation',
    'renewal',
    'termination',
  ] as const,
  header: (c) => c.toUpperCase(),
};

// ── Risk Assessment Lexicon ────────────────────────────────────────────

/** BREM / ISO 31000 / COSO ERM risk lifecycle. The `acceptance` category
    is the Mutation Authority ratification point in BREM terms. Formal
    proof: `riskAssessmentHeader_injective`. */
export type RiskAssessmentCategory =
  | 'identification'
  | 'analysis'
  | 'evaluation'
  | 'treatment'
  | 'monitoring'
  | 'acceptance'
  | 'communication';

export const RiskAssessmentLexicon: Lexicon<RiskAssessmentCategory> = {
  name: 'risk-assessment',
  categories: [
    'identification',
    'analysis',
    'evaluation',
    'treatment',
    'monitoring',
    'acceptance',
    'communication',
  ] as const,
  header: (c) => c.toUpperCase(),
};

// ── Calendar Lexicon ───────────────────────────────────────────────────

/** Inter-hat scheduling primitive. Consumed by `@semantos/calendar-ext`.
    Categories track the four concepts the calendar model works in: a
    half-open time slot, a multi-slot search window, a conflict between
    overlapping commitments, and the identity hat that owns the slot.
    The calendar extension's API verbs (hold, book, release, cancel,
    reschedule) all reduce to these four category objects. */
export type CalendarCategory = 'slot' | 'window' | 'conflict' | 'hat';

export const CalendarLexicon: Lexicon<CalendarCategory> = {
  name: 'calendar',
  categories: ['slot', 'window', 'conflict', 'hat'] as const,
  header: (c) => `CAL_${c.toUpperCase()}`,
};

// ── Trades Lexicon ─────────────────────────────────────────────────────

/** Trades / services discourse vocabulary for the oddjobz extension.
    Each category names a distinct discourse move that produces or
    transitions a typed cell in the trades vertical (Job/Quote/Visit/
    Invoice/Customer/Site/Estimate/Message per ODDJOBZ-EXTENSION-PLAN
    §O2). The categories track the speech acts, not the cells themselves
    — same pattern as project-management, where `commitment` is the act
    not the artefact.

    The eight categories mirror the §O4 state-machine transitions:

      lead      — origin of work (∅ → lead): visitor enquiry via public
                  chat or operator-entered customer record
      estimate  — operator drafts a pre-quote proposal (AFFINE; can be
                  discarded without becoming a quote)
      quote     — operator sends a firm priced offer (lead → quoted)
      dispatch  — operator commits a worker to a visit slot
                  (quoted → scheduled)
      visit     — worker on site / work performed
                  (scheduled → in_progress → completed)
      invoice   — billing record issued (completed → invoiced)
      settle    — payment received and engagement closed
                  (invoiced → paid → closed)
      message   — vertical-context communication act, including public
                  chat, customer chat, and internal patches against
                  Customer / Job

    Granularity rationale: estimate vs quote, dispatch vs visit, and
    invoice vs settle are pairs that look adjacent but carry different
    curator obligations and different capability tokens (cap.oddjobz.
    {quote, dispatch, invoice, close} per §O3). Confusing them is a
    canonical source of trades-vertical disputes — so they earn
    category-level status.

    Formal proof: `tradesHeader_injective` in Lexicons/Trades.lean. */
export type TradesCategory =
  | 'lead'
  | 'estimate'
  | 'quote'
  | 'dispatch'
  | 'visit'
  | 'invoice'
  | 'settle'
  | 'message';

export const TradesLexicon: Lexicon<TradesCategory> = {
  name: 'trades',
  categories: [
    'lead',
    'estimate',
    'quote',
    'dispatch',
    'visit',
    'invoice',
    'settle',
    'message',
  ] as const,
  header: (c) => c.toUpperCase(),
};

// ── BRAP Lexicon ───────────────────────────────────────────────────────

/** Blockchain Risk Assessment Platform (BRAP) — the 9-cell BREM matrix.
    Categories are the cell keys of the scoring grid:

      Network domain:     na (Architecture), nc (Consensus), ns (Settlement)
      System-state:       se (Expertise), sm (Mutation authority), sf (Functional readiness)
      Law domain:         ls (Standards), lr (Regulatory), lp (Policy)

    BRAP's agent emits patches per-cell (one patch per cell-score update).
    Every patch carries `lexicon: 'brap'` so the receiver can route to this
    lexicon's validator — rejecting any verb or category outside the set
    protects the cell-score chain from schema drift. */
export type BRAPCategory =
  | 'na'
  | 'nc'
  | 'ns'
  | 'se'
  | 'sm'
  | 'sf'
  | 'ls'
  | 'lr'
  | 'lp';

/** BRAP's cell-level actions. Not part of the core `Lexicon<Cat>` interface
    (that's category-only); exported alongside for validators that want to
    enforce verb discipline. */
export const BRAP_VERBS = [
  'score',
  'refine',
  'probe',
  'mitigate',
  'escalate',
  'classify',
  'accept',
  'reject',
] as const;
export type BRAPVerb = (typeof BRAP_VERBS)[number];

export const BRAPLexicon: Lexicon<BRAPCategory> = {
  name: 'brap',
  categories: ['na', 'nc', 'ns', 'se', 'sm', 'sf', 'ls', 'lr', 'lp'] as const,
  header: (c) => `BRAP_${c.toUpperCase()}`,
};

/** Validator: true iff `category` is a known BRAP cell key. */
export function isBRAPCategory(category: string): category is BRAPCategory {
  return (BRAPLexicon.categories as ReadonlyArray<string>).includes(category);
}

/** Validator: true iff `verb` is a known BRAP action. */
export function isBRAPVerb(verb: string): verb is BRAPVerb {
  return (BRAP_VERBS as ReadonlyArray<string>).includes(verb);
}

// ── Tessera Lexicon ────────────────────────────────────────────────────

/** Care-chain provenance discourse vocabulary for the tessera cartridge.

    Each category names a discourse move that produces or transitions a
    typed cell in the care-chain vertical — wine, premium coffee, cold-
    chain pharma, art transit, and any future vertical where the value
    of a delivered object depends on its handling history. Same speech-
    act framing as trades / project-management: the act, not the
    artefact.

    The thirteen categories trace a physical object's journey:

      harvest         — origin: produces an AFFINE grape-lot
                        (or analogue) cell
      ferment         — primary fermentation event
      rack            — racking / cellar transfer between barrels
      blend           — blend transition consuming N barrels into one
                        (K15 conservation: Σinput.amount = Σoutput.amount)
      addition        — record an oenological / processing addition
      bottle          — produce N LINEAR bottle cells from one barrel
      label           — labelling / packaging act
      custody-transfer — case / pallet / shipment custody handoff
      care-event      — environmental reading (temp logger, humidity,
                        shock) accumulating against a shipment
      excursion       — out-of-spec event (temperature / humidity /
                        elapsed time threshold breach)
      tamper-event    — single LINEAR transition `intact → broken`
                        on a bottle's tamper-loop seal
      scan            — consumer NFC scan; RELEVANT (must exist for
                        Care Score view to render)
      tasting-note    — DEBUG class; read-only opaque-to-FSM annotation

    Granularity rationale: harvest / ferment / rack / blend / addition /
    bottle / label are pairs that look adjacent but carry different
    capabilities (cap.tessera.{harvest, rack, blend-declare, bottle,
    care-record}) and different linearity classes. Confusing them
    breaks the Lean theorems V5.2–V5.6 (tamper_one_shot,
    care_score_monotonic, blend_conservation, custody_linear,
    scan_evidence_present). So they earn category-level status.

    Formal proof: `tesseraHeader_injective` in Lexicons/Tessera.lean
    (V5.7 — initially pending, moves to proven when the ritual
    obligation lands). */
export type TesseraCategory =
  | 'harvest'
  | 'ferment'
  | 'rack'
  | 'blend'
  | 'addition'
  | 'bottle'
  | 'label'
  | 'custody-transfer'
  | 'care-event'
  | 'excursion'
  | 'tamper-event'
  | 'scan'
  | 'tasting-note';

export const TesseraLexicon: Lexicon<TesseraCategory> = {
  name: 'tessera',
  categories: [
    'harvest',
    'ferment',
    'rack',
    'blend',
    'addition',
    'bottle',
    'label',
    'custody-transfer',
    'care-event',
    'excursion',
    'tamper-event',
    'scan',
    'tasting-note',
  ] as const,
  header: (c) => `TESSERA_${c.toUpperCase().replace(/-/g, '_')}`,
};

// ── Self Lexicon ───────────────────────────────────────────────────────

/** Self practice + Paskian narrative discourse vocabulary for the
 *  `self` cartridge (T6 / T7).  Each category names a discourse move
 *  that produces or transitions a typed cell in the self vertical:
 *
 *    release   — Stream-of-consciousness release writing/photo capture
 *    intention — Setting an intention with dimension targeting
 *    session   — Starting/closing a practice session
 *    insight   — Capturing a retained insight
 *    pattern   — Noticing/marking a recurring pattern
 *    connect   — Connecting to receive intelligence
 *    vacuum    — QSE vacuum-cleaner release+integrate cycle
 *    seal      — Gold-seal completion ritual
 *    morning   — Morning intention setting (accountability cadence)
 *    review    — Evening review (accountability cadence)
 *    pulse     — Per-dimension daily pulse
 *    inquire   — Resistance / discernment inquiry
 *
 *  Sourced from `configs/extensions/consciousness.json` (legacy) +
 *  cherry-picked into `cartridges/betterment/cartridge.json` flows[] per
 *  the tick-20 cleanup.  Categories track speech acts, not cells —
 *  same pattern as trades/project-management/calendar.
 *
 *  Status: planned (Lean obligation `bettermentHeader_injective` deferred
 *  until betterment practice cells ship in production usage). */
export type BettermentCategory =
  | 'release'
  | 'intention'
  | 'session'
  | 'insight'
  | 'pattern'
  | 'connect'
  | 'vacuum'
  | 'seal'
  | 'morning'
  | 'review'
  | 'pulse'
  | 'inquire';

export const BettermentLexicon: Lexicon<BettermentCategory> = {
  name: 'betterment',
  categories: [
    'release',
    'intention',
    'session',
    'insight',
    'pattern',
    'connect',
    'vacuum',
    'seal',
    'morning',
    'review',
    'pulse',
    'inquire',
  ] as const,
  header: (c) => `BETTERMENT_${c.toUpperCase()}`,
};

// ── Union types for multi-lexicon SIRNodes ─────────────────────────────

/** A category tagged with its originating lexicon. For SIRNodes that
    participate in workflows crossing lexicons (e.g. a jural obligation
    whose fulfilment is measured by a control-systems sensor, or a
    project-management change request that triggers a risk-assessment
    treatment). */
export type TaggedCategory =
  | { lexicon: 'jural'; category: JuralCategory }
  | { lexicon: 'control-systems'; category: ControlSystemsCategory }
  | { lexicon: 'circuit-commands'; category: CircuitCommandsCategory }
  | { lexicon: 'cdm'; category: CDMCategory }
  | { lexicon: 'bills-of-lading'; category: BillsOfLadingCategory }
  | { lexicon: 'project-management'; category: ProjectManagementCategory }
  | { lexicon: 'property-management'; category: PropertyManagementCategory }
  | { lexicon: 'risk-assessment'; category: RiskAssessmentCategory }
  | { lexicon: 'calendar'; category: CalendarCategory }
  | { lexicon: 'trades'; category: TradesCategory }
  | { lexicon: 'brap'; category: BRAPCategory }
  | { lexicon: 'tessera'; category: TesseraCategory }
  | { lexicon: 'betterment'; category: BettermentCategory }
  | { lexicon: 'scg-relation'; category: RelationKind };

/** Union of all registered lexicons. Adding a new lexicon extends this. */
export type AnyLexicon =
  | typeof JuralLexicon
  | typeof ControlSystemsLexicon
  | typeof CircuitCommandsLexicon
  | typeof CDMLexicon
  | typeof BillsOfLadingLexicon
  | typeof ProjectManagementLexicon
  | typeof PropertyManagementLexicon
  | typeof RiskAssessmentLexicon
  | typeof CalendarLexicon
  | typeof TradesLexicon
  | typeof BRAPLexicon
  | typeof TesseraLexicon
  | typeof BettermentLexicon
  | typeof relationLexicon;

/** Registry of all verified lexicons. Convenient for iterating over the
    full set (tests, documentation, UI pickers). */
export const ALL_LEXICONS: ReadonlyArray<Lexicon> = [
  JuralLexicon,
  ControlSystemsLexicon,
  CircuitCommandsLexicon,
  CDMLexicon,
  BillsOfLadingLexicon,
  ProjectManagementLexicon,
  PropertyManagementLexicon,
  RiskAssessmentLexicon,
  CalendarLexicon,
  TradesLexicon,
  BRAPLexicon,
  TesseraLexicon,
  BettermentLexicon,
  relationLexicon,
] as const;

// ── Runtime injectivity verification ───────────────────────────────────
// (Moved to @semantos/lexicon-core. Re-exported above for back-compat.)

```
