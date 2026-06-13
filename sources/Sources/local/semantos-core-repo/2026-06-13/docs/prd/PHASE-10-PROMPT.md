---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-10-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.660616+00:00
---

# Phase 10 Execution Prompt — Three-Axis Taxonomy Governance + Reputation

> Paste this prompt into a fresh session to execute Phase 10.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and React loom for Bitcoin-native semantic objects (npm: `@semantos/core`). The kernel (cell engine, 2-PDA) is Zig/WASM in `packages/cell-engine/`; this repo also holds the type system, compiler, WASM bindings, and loom UI. Phase 9 extracted services from React, added LLM intent classification and flow routing. Phase 9.5 added visibility states, publication/revoke flows, and governance types (Dispute, Ballot, Stake, Resolution). Identity has GIP trait structure with selective disclosure (disclosed/hashed split).

Your task is Phase 10: implement the three-axis taxonomy (WHAT/HOW/WHY), seed it from a civilisational production ontology, add reputation as a computed materialized view over identity evidence chains, and build taxonomy governance flows (propose, challenge, vote).

The coordinate system is documented in `docs/TAXONOMY-SEED-DESIGN.md` — read this carefully. It defines six axes (three required semantic, three optional context), the seed LTREEs, the GIP integration, and the zero-cell-engine-changes constraint.

## CRITICAL: READ THESE FILES FIRST

**Read first** (the PRD):
- `docs/prd/SHOMEE-EXTRACTION-AUDIT-AND-ROADMAP.md` — Phase 10 spec with deliverables D10.1-D10.4

**Read second** (Phase 9 + 9.5 implementations you are building on — ALL must exist):
- `packages/loom/src/services/LoomStore.ts` — renderer-agnostic state
- `packages/loom/src/services/IdentityStore.ts` — renderer-agnostic identity
- `packages/loom/src/services/ConfigStore.ts` — renderer-agnostic config
- `packages/loom/src/services/IntentClassifier.ts` — LLM intent classification
- `packages/loom/src/services/FlowRegistry.ts` — flow lookup
- `packages/loom/src/services/FlowRunner.ts` — multi-turn flow execution

If any service file is missing or stubbed, STOP. Previous phases are incomplete.

**Read third** (existing loom code with 9.5 extensions):
- `packages/loom/src/types/workbench.ts` — LoomObject (now has visibility field)
- `packages/loom/src/config/extensionConfig.ts` — ExtensionConfig (now has visibility and flows)
- `packages/loom/src/state/workbenchReducer.ts` — now includes TRANSITION_VISIBILITY
- `packages/loom/src/sidebar/TaxonomyBrowser.tsx` — existing tree view (you will extend to three axes)
- `packages/loom/src/shell/StatusBar.tsx` — you will add reputation display here
- `packages/loom/src/identity/IdentityProvider.tsx` — identity context

**Read fourth** (extension configs with governance types):
- `configs/extensions/core.json` — now has Dispute, Ballot, Stake, Resolution types + governance flows
- `configs/extensions/trades-services.json` — 7 object types + taxonomy + publish/revoke flows

**Read fifth**:
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-10-taxonomy-governance`.

---

## ANTI-BULLSHIT RULES

Same rules as Phase 9 and 9.5. Plus:

### 8. REPUTATION IS NOT A SERVICE

Reputation is a materialized view — a computation over an identity's evidence chain. It's a function: `computeReputation(patches: ObjectPatch[]): ReputationScore`. Not a ReputationEvaluatorService, not a ReputationEngine, not a ScoreManager. A function. It returns a family of views (global, contextual, scoped), not one monolithic number.

### 9. TAXONOMY PROPOSALS ARE BALLOTS

A taxonomy proposal is a Ballot object with category `governance.taxonomy-proposal`. When the ballot resolves, a TaxonomyNode is appended to the extension config overlay. If you create a TaxonomyProposalService or a CategoryGovernanceEngine, you are wrong.

### 10. TAXONOMY IS THREE AXES, NOT ONE TREE

Type space is a coordinate system: WHAT (what the thing is), HOW (how it operates), WHY (what function it serves). Object types bind coordinates across all three. If you build a single flat LTREE for everything, you are wrong. Three separate governed LTREEs: `taxonomy.what.*`, `taxonomy.how.*`, `taxonomy.why.*`.

### 11. TAXONOMY NODES ARE SEMANTIC OBJECTS

Taxonomy nodes are not just config entries. They are objects of type `taxonomy.node` with patches, evidence chains, and governance. Schema, policies, flows, and view hints accumulate around taxonomy coordinates as children. Each branch is a semantic jurisdiction.

### 12. EMBEDDINGS ARE ASSISTIVE, NOT AUTHORITATIVE

If you use embeddings/vectors, they assist lookup, synonym discovery, and candidate classification. The authoritative ontology is symbolic — object relations and patches, not vector proximity. Never let an embedding DB be the source of truth for type space.

---

## Step 1: Reputation on Identities (D10.1)

1. Define `ReputationScore` in `packages/loom/src/types/workbench.ts`:
   ```typescript
   interface ReputationScore {
     base: number;
     activity: number;
     disputeOutcomes: number;
     contributions: number;
     total: number;
     context?: string;  // optional context scope (global if omitted)
   }
   ```

2. Create `packages/loom/src/services/ReputationComputer.ts`:
   ```typescript
   // Pure function. No state. No side effects.
   function computeReputation(
     identityPatches: ObjectPatch[],
     allObjects: Map<string, LoomObject>,
     weights?: ReputationWeights,
     context?: string  // scope to a type path or domain
   ): ReputationScore
   ```
   - base: 50
   - activity: count of patches in last 30 days, capped at 30 points
   - disputeOutcomes: stakes won minus forfeited, scaled
   - contributions: bonus for Ballots where identity was proposer and ballot approved
   - total: weighted sum (default: base 0.2, activity 0.3, disputeOutcomes 0.3, contributions 0.2)
   - If `context` provided, filter patches to those touching objects at that type coordinate

3. Display on StatusBar. Display on LoomCards for other identities. Add ReputationWeights to extension config policies.

**Gate test**: Pure function tests — deterministic, no React, correct scoring for activity/disputes/contributions. Context-scoped reputation differs from global.

---

## Step 2: Three-Axis Taxonomy (D10.2)

1. Extend TaxonomyNode with `axis: "what" | "how" | "why"` and `weight?: { activity, relevance, lastUpdated }`.

2. Define `TypeCoordinate` in `packages/loom/src/types/workbench.ts`:
   ```typescript
   interface TypeCoordinate {
     what: string;      // e.g. "what.service.fabrication.carpentry"
     how: string[];     // e.g. ["how.physical.manual", "how.technical.joinery"]
     why: string[];     // e.g. ["why.production", "why.maintenance"]
   }
   ```

3. Seed the three root LTREEs in `configs/taxonomy/seed.json`:
   - WHAT roots: person, group, institution, object, resource, place, event, process, service, claim, rule, record, asset, tool, system
   - HOW roots: biological, physical, cognitive, social, economic, legal, technical, communicative, computational, logistical, educational, governance
   - WHY roots: survival, safety, maintenance, production, reproduction, coordination, exchange, knowledge, healing, mobility, security, play, meaning

   Each node carries: function_type, primary_outputs, required_inputs, enables, depends_on, positive_externalities, negative_externalities, time_horizon, beneficiary_scope.

   The seed is compressed through a civilisational production lens — not a neutral encyclopedia but a production ontology grounded in contribution, utility, coordination, and externalities. Reproductive/generative functions (parenting, care, education) are first-class economic realities.

4. Create `packages/loom/src/services/TaxonomyWeightComputer.ts` — pure function, counts objects at each coordinate across all three axes.

5. Update TaxonomyBrowser to support three-axis navigation (tabbed or stacked dimensions) and sort by weight. Dim low-activity nodes.

**Gate test**: Seed loads all three axes, object counts drive weights, sorting changes per axis, TypeCoordinate binds across axes, recomputes on object addition.

---

## Step 3: Taxonomy Proposal Flow (D10.3)

1. Add `propose-category` flow to core.json — flow specifies which axis (what/how/why) and parent path.
2. Creates a Ballot with motion and proposed node details including axis, parent, and production metadata.
3. On ballot resolution, append TaxonomyNode to a `ConfigOverlay`.
4. Config overlays persist alongside extension configs.
5. The appended node is a semantic object of type `taxonomy.node` — it can itself receive patches, governance, schema children.

**Gate test**: Flow creates ballot, approval appends node to correct axis, node appears in browser under correct dimension, overlay persists.

---

## Step 4: Misclassification Challenge (D10.4)

1. Add `challenge-classification` flow to core.json.
2. Creates a Dispute with subject and proposed correct coordinate(s) across any axis.
3. On upheld resolution, subject object's TypeCoordinate is patched.
4. Evidence chain records the reclassification with full provenance.

**Gate test**: Challenge creates dispute, upheld reclassifies coordinate, dismissed leaves unchanged.

---

## Completion Criteria

1. Reputation on StatusBar, computed from evidence chain
2. Reputation as badge on other identities' objects
3. Context-scoped reputation returns different scores than global
4. Three-axis TaxonomyBrowser (WHAT/HOW/WHY) with tabbed or stacked navigation
5. Seed taxonomy loads with ~40 root+second-level nodes across three axes
6. TypeCoordinate binds objects across all three axes
7. TaxonomyBrowser sorts by activity/relevance per axis
8. Taxonomy proposal: propose → ballot → approve → node appears in correct axis
9. Misclassification: challenge → dispute → resolve → reclassify coordinate
10. All computations are pure functions
11. Taxonomy nodes are semantic objects with patches
12. `bun test` passes all gate files
13. No ReputationService, TaxonomyGovernanceEngine, or ScoreManager

---

## Post-Phase: Errata Sprint

After merging to main, follow the errata scan protocol in `docs/BRANCHING-AND-CI-POLICY.md`.
Open a FRESH session, paste the errata scan prompt, and review all delivered code adversarially.
Fix any issues on an `errata/phase-10` branch before starting Phase 11.
