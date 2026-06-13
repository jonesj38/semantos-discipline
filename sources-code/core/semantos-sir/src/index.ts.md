---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.812732+00:00
---

# core/semantos-sir/src/index.ts

```ts
export type {
  JuralCategory,
  TaxonomyCoordinates,
  TrustClass,
  ProofRequirement,
  ExecutionAuthority,
  GovernanceContext,
  SIRIdentity,
  SIRConstraint,
  SIRTarget,
  SIRGate,
  SIRFulfillment,
  SIRProvenance,
  SIRNode,
  SIRProgram,
  LoweringResult,
  DomainType,
  DomainBinding,
  DelegationChain,
  IdentityRef,
  ComparisonOp,
  LinearityMode,
} from './types';

export { lowerSIR, lowerSIRWithAuthority } from './lower-sir';
export type { LowerSIROptions } from './lower-sir';
export { compileToSIR } from './compile-to-sir';

// Lexicon authority — D-A6 (matrix cell A7×A). Extensions that mint
// capabilities or define lexicons must declare a BRC-52-anchored
// authority cert + grammar signature; the lowering pass refuses
// programs whose authority fails verification.
export {
  StubAuthorityVerifier,
  RejectAuthorityVerifier,
} from './authority';
export type {
  Brc52CertRef,
  LexiconAuthority,
  AuthorityVerifier,
  AuthorityVerificationResult,
  AuthorityErrorCode,
} from './authority';

// Lexicons — Lean-verified discriminated-union category vocabularies.
// The `Lexicon<Cat>` typeclass parameterises category dimensions
// across jural / control-systems / cdm / bills-of-lading /
// project-management / property-management / risk-assessment /
// circuit-commands. `TaggedCategory` is the discriminated union
// every Intent + SIRNode carries as `category`.
export {
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
  BRAP_VERBS,
  isBRAPCategory,
  isBRAPVerb,
  TesseraLexicon,
  BettermentLexicon,
  ALL_LEXICONS,
  verifyLexiconInjective,
  isCategoryOf,
} from './lexicons';
export type {
  Lexicon,
  TaggedCategory,
  AnyLexicon,
  ControlSystemsCategory,
  CircuitCommandsCategory,
  CDMCategory,
  BillsOfLadingCategory,
  ProjectManagementCategory,
  PropertyManagementCategory,
  RiskAssessmentCategory,
  CalendarCategory,
  TradesCategory,
  BRAPCategory,
  BRAPVerb,
  TesseraCategory,
  BettermentCategory,
} from './lexicons';

// SCG conversation-graph relations — Phase 1 bolt-on (RM-010).
// Lives in `@semantos/scg-relations`; re-exported here for ergonomic
// access alongside the other registered lexicons.
export { relationLexicon } from '@semantos/scg-relations';
export type { RelationKind } from '@semantos/scg-relations';

```
