---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-9.5-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.674406+00:00
---

# Phase 9.5 Execution Prompt — Publication + Visibility + Governance Types

> Paste this prompt into a fresh session to execute Phase 9.5.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and React loom for Bitcoin-native semantic objects (npm: `@semantos/core`). The kernel (cell engine, 2-PDA) is Zig/WASM in `packages/cell-engine/`; this repo also holds the type system, compiler, WASM bindings, and loom UI. Phase 9 extracted React-coupled state into plain TypeScript services (LoomStore, IdentityStore, ConfigStore), added LLM intent classification via OpenRouter, and built a flow registry/runner. Identity now has GIP trait structure (disclosed/hashed selective disclosure). All services are renderer-agnostic.

Your task is Phase 9.5: add visibility states (draft/published/revoked) to objects, implement publish/revoke conversation flows, and register governance object types (Dispute, Ballot, Stake, Resolution) with their conversation flows.

## CRITICAL: READ THESE FILES FIRST

**Read first** (the PRD):
- `docs/prd/SHOMEE-EXTRACTION-AUDIT-AND-ROADMAP.md` — Phase 9.5 spec with deliverables D9.5.1-D9.5.4

**Read second** (Phase 9 implementations you are building on — these MUST exist before you start):
- `packages/loom/src/services/LoomStore.ts` — renderer-agnostic state store
- `packages/loom/src/services/IdentityStore.ts` — renderer-agnostic identity
- `packages/loom/src/services/ConfigStore.ts` — renderer-agnostic config loading
- `packages/loom/src/services/IntentClassifier.ts` — LLM intent classification
- `packages/loom/src/services/FlowRegistry.ts` — flow lookup from extension config
- `packages/loom/src/services/FlowRunner.ts` — multi-turn flow execution

If any of these files don't exist or are stubs, STOP. Phase 9 is not complete. Do not proceed.

**Read third** (existing loom code):
- `packages/loom/src/types/workbench.ts` — LoomObject, ObjectPatch, Identity, Facet
- `packages/loom/src/config/extensionConfig.ts` — ExtensionConfig schema (you will extend this)
- `packages/loom/src/state/workbenchReducer.ts` — 16 action types
- `packages/loom/src/state/objectFactory.ts` — createObject() with typeHash
- `packages/loom/src/canvas/ConversationPanel.tsx` — conversation with intent integration

**Read fourth** (extension configs):
- `configs/extensions/trades-services.json` — you will add visibility + flows
- `configs/extensions/blockchain-risk.json` — you will add visibility + governance types
- `configs/extensions/core.json` — you will add governance types here (shared across extensions)

**Read fifth** (kernel types):
- `src/cell-engine/typeHashRegistry.ts` — computeTypeHash(), Linearity constants
- `src/types/semantic-objects.ts` — semantic object types

**Read sixth**:
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-9.5-publication-governance`.

---

## ANTI-BULLSHIT RULES

Same rules as Phase 9. Read them. Follow them. Additionally:

### 6. GOVERNANCE IS NOT A SERVICE

Governance objects (Dispute, Ballot, Stake, Resolution, Tribunal) are ordinary semantic objects
with ordinary linearity transitions driven by ordinary conversation flows. If you find yourself
creating a `GovernanceEngine`, `DisputeService`, `BallotCoordinator`, or any class with
"governance" in its name that isn't a type definition or a flow definition, STOP. You are
recreating Shomee's 93-package mistake.

The cell engine enforces linearity. The flow runner drives conversations. The extension config
defines the types. That is the entire governance implementation.

### 7. VISIBILITY IS A FIELD, NOT A SYSTEM

Visibility (draft/published/revoked) is a field on ObjectTypeDefinition and a value on
LoomObject. It is not a PublicationService, a VisibilityManager, or a DraftPubService.
If you create any of those, you are recreating Shomee's 93-package mistake.

---

## Step 1: Visibility Field on ObjectTypeDefinition (D9.5.1)

1. Extend `ObjectTypeDefinition` in `extensionConfig.ts`:
   ```typescript
   visibility?: {
     states: ('draft' | 'published' | 'revoked')[];
     defaultState: 'draft' | 'published';
     publishTransition?: {
       fromLinearity: 'AFFINE';
       toLinearity: 'RELEVANT';
       requiredCapabilities?: number[];
     };
     revokePreservesEvidence: boolean;
   };
   accessPolicy?: {
     default: 'public' | 'private' | 'facet-scoped';
     overridable: boolean;
   };
   ```

2. Extend `LoomObject` in `workbench.ts`:
   ```typescript
   visibility: 'draft' | 'published' | 'revoked';
   ```

3. Update `objectFactory.ts`: set initial visibility from `typeDef.visibility?.defaultState ?? 'draft'`.

4. Update extension configs: add visibility to object types where it makes sense:
   - Job: `{ states: ["draft", "published", "revoked"], defaultState: "draft", publishTransition: { fromLinearity: "AFFINE", toLinearity: "RELEVANT" }, revokePreservesEvidence: true }`
   - Quote/ROM: same pattern
   - Customer: no visibility (always private by default)

5. Add `TRANSITION_VISIBILITY` action to loomReducer:
   ```typescript
   | { type: 'TRANSITION_VISIBILITY'; objectId: string; newVisibility: 'draft' | 'published' | 'revoked' }
   ```

6. LoomStore: expose `transitionVisibility(objectId, newVisibility)` method that validates the transition (draft→published requires AFFINE linearity and the configured capabilities, revoked preserves RELEVANT linearity).

**Gate test**:
- Create a Job from trades-services config → visibility is "draft"
- Publish it → visibility becomes "published", linearity transitions AFFINE→RELEVANT
- Revoke it → visibility becomes "revoked", linearity stays RELEVANT
- Attempt to publish without required capabilities → rejected
- Attempt to publish a LINEAR object → rejected (only AFFINE can be published)

---

## Step 2: Publish and Revoke Flows (D9.5.2)

Add to trades-services.json flows:

```json
{
  "id": "publish",
  "triggerIntents": ["publish", "make.public", "share"],
  "requiredCapabilities": [2],
  "steps": [
    {"prompt": "Confirm you want to publish this object?", "extractionSchema": {"confirmed": "boolean"}}
  ],
  "onComplete": {"type": "transition", "linearityTransition": "AFFINE_TO_RELEVANT"}
},
{
  "id": "revoke",
  "triggerIntents": ["revoke", "retract", "hide", "unpublish"],
  "requiredCapabilities": [2],
  "steps": [
    {"prompt": "Are you sure you want to revoke? Evidence chain will be preserved.", "extractionSchema": {"confirmed": "boolean"}}
  ],
  "onComplete": {"type": "patch", "patchFields": ["visibility"]}
}
```

Extend FlowRunner to handle `transition` and `patch` action types (Phase 9 only had `create` and `navigate`).

**Gate test**:
- User says "publish this" on a draft Job → intent classified → publish flow activates → confirmation → AFFINE→RELEVANT
- User says "revoke this listing" → revoke flow → confirmation → visibility changes, linearity preserved
- Flow rejects if object is already published (can't publish twice)
- Flow rejects if object is LINEAR (wrong linearity for publication)

---

## Step 3: Governance Object Types (D9.5.3)

Add governance types to `configs/extensions/core.json` (so they're available in all extensions):

```json
{
  "typeHash": "",
  "name": "Dispute",
  "icon": "alert-triangle",
  "linearity": "AFFINE",
  "archetype": "action",
  "conversationEnabled": true,
  "visibility": {"states": ["draft", "published"], "defaultState": "draft", "publishTransition": {"fromLinearity": "AFFINE", "toLinearity": "RELEVANT"}, "revokePreservesEvidence": true},
  "linearityTransitions": [{"from": "AFFINE", "to": "RELEVANT", "trigger": "resolved"}],
  "defaultCapabilities": [5, 1],
  "fields": [
    {"name": "subjectObjectId", "type": "string"},
    {"name": "claimantFacetId", "type": "string"},
    {"name": "respondentFacetId", "type": "string"},
    {"name": "status", "type": "enum", "values": ["open", "evidence", "review", "resolved"]},
    {"name": "resolution", "type": "enum", "values": ["pending", "upheld", "dismissed", "split"]}
  ],
  "category": "governance.dispute"
},
{
  "typeHash": "",
  "name": "Ballot",
  "icon": "vote",
  "linearity": "AFFINE",
  "archetype": "action",
  "conversationEnabled": true,
  "linearityTransitions": [{"from": "AFFINE", "to": "RELEVANT", "trigger": "finalized"}],
  "defaultCapabilities": [5],
  "fields": [
    {"name": "motion", "type": "string"},
    {"name": "quorum", "type": "number", "min": 1},
    {"name": "votesFor", "type": "number", "min": 0},
    {"name": "votesAgainst", "type": "number", "min": 0},
    {"name": "status", "type": "enum", "values": ["open", "quorum_reached", "finalized"]}
  ],
  "category": "governance.ballot"
},
{
  "typeHash": "",
  "name": "Stake",
  "icon": "lock",
  "linearity": "LINEAR",
  "archetype": "instrument",
  "defaultCapabilities": [10],
  "fields": [
    {"name": "amount", "type": "number", "min": 0},
    {"name": "subjectObjectId", "type": "string"},
    {"name": "stakerFacetId", "type": "string"},
    {"name": "status", "type": "enum", "values": ["active", "forfeited", "returned"]}
  ],
  "category": "governance.stake"
},
{
  "typeHash": "",
  "name": "Resolution",
  "icon": "check-circle",
  "linearity": "RELEVANT",
  "archetype": "instrument",
  "defaultCapabilities": [5, 2],
  "fields": [
    {"name": "disputeObjectId", "type": "string"},
    {"name": "outcome", "type": "enum", "values": ["upheld", "dismissed", "split"]},
    {"name": "reasoning", "type": "string"}
  ],
  "category": "governance.resolution"
}
```

Compute typeHash for all new types. Validate all configs pass `validateExtensionConfig()`.

**Gate test**:
- core.json loads and validates with governance types
- Dispute created → AFFINE, phase SOURCE
- Dispute accumulates evidence patches → patches stored with facet provenance
- Dispute resolved → AFFINE→RELEVANT transition, status "resolved"
- Stake created → LINEAR, can be consumed exactly once (forfeited or returned)

---

## Step 4: Governance Conversation Flows (D9.5.4)

Add governance flows to core.json:

```json
"flows": [
  {
    "id": "file-dispute",
    "triggerIntents": ["dispute", "challenge", "flag", "report"],
    "requiredCapabilities": [5],
    "steps": [
      {"prompt": "Which object are you disputing?", "extractionSchema": {"subjectObjectId": "string"}},
      {"prompt": "What is the basis of your dispute?", "extractionSchema": {"reasoning": "string"}}
    ],
    "onComplete": {"type": "create", "objectType": "Dispute"}
  },
  {
    "id": "cast-vote",
    "triggerIntents": ["vote", "approve", "reject", "support", "oppose"],
    "requiredCapabilities": [5],
    "steps": [
      {"prompt": "Vote for or against?", "extractionSchema": {"vote": "enum"}}
    ],
    "onComplete": {"type": "patch", "patchFields": ["votesFor", "votesAgainst"]}
  },
  {
    "id": "stake",
    "triggerIntents": ["stake", "back", "wager"],
    "requiredCapabilities": [10],
    "steps": [
      {"prompt": "How much do you want to stake?", "extractionSchema": {"amount": "number"}},
      {"prompt": "What are you staking on?", "extractionSchema": {"subjectObjectId": "string"}}
    ],
    "onComplete": {"type": "create", "objectType": "Stake"}
  }
]
```

**Gate test**:
- "I want to challenge this listing" → file-dispute flow → Dispute object created
- "Vote yes" on a Ballot → vote patch applied, votesFor incremented
- Governance flows work across trades-services AND blockchain-risk extensions (core types are shared)

---

## Phase 9.5 Gate Test File

Create `packages/__tests__/phase9.5-gate.test.ts`:

```typescript
describe("Phase 9.5 Gate: Publication + Visibility + Governance", () => {
  // Gate 1: Visibility
  test("new objects have correct default visibility from config", () => {});
  test("publish transitions AFFINE→RELEVANT and sets visibility=published", () => {});
  test("revoke preserves RELEVANT linearity and sets visibility=revoked", () => {});
  test("publish rejects if capabilities insufficient", () => {});
  test("publish rejects if linearity is not AFFINE", () => {});

  // Gate 2: Publish/revoke flows
  test("publish flow triggers on 'publish this' intent", () => {});
  test("revoke flow triggers on 'retract' intent", () => {});
  test("FlowRunner handles 'transition' action type", () => {});

  // Gate 3: Governance types
  test("core.json loads with governance types", () => {});
  test("Dispute is AFFINE, transitions to RELEVANT on resolved", () => {});
  test("Stake is LINEAR, consumed exactly once", () => {});
  test("Ballot accumulates vote patches", () => {});

  // Gate 4: Governance flows
  test("file-dispute flow creates Dispute with correct fields", () => {});
  test("cast-vote flow patches Ballot with incremented votes", () => {});
  test("governance flows available in trades-services extension (via core)", () => {});

  // Gate 5: Anti-regression
  test("no GovernanceEngine or DisputeService in source", () => {});
  test("no PublicationService or VisibilityManager in source", () => {});
  test("Phase 9 gate still passes (cumulative)", () => {});
});
```

---

## Completion Criteria

1. AFFINE objects can be published (→RELEVANT) via "publish this" conversation
2. Published objects can be revoked, evidence preserved
3. Dispute, Ballot, Stake, Resolution types registered in core.json and creatable
4. Dispute flow: file → gather evidence → resolve → linearity transition
5. All governance is driven by conversation flows and extension config, not by dedicated services
6. `bun test packages/__tests__/phase9.5-gate.test.ts` passes
7. `bun run check` passes (zero TypeScript errors)
8. No stubs, no governance engines, no publication services

---

## Post-Phase: Errata Sprint

After merging to main, follow the errata scan protocol in `docs/BRANCHING-AND-CI-POLICY.md`.
Open a FRESH session, paste the errata scan prompt, and review all delivered code adversarially.
Fix any issues on an `errata/phase-9.5` branch before starting Phase 10.
