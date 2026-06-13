---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/SHOMEE-EXTRACTION-AUDIT-AND-ROADMAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.700340+00:00
---

# Shomee Extraction: Audit, Roadmap & Master PRD

**Date**: 2026-03-28
**Status**: Draft
**Prerequisite**: Phase 8.5 (Identity) complete
**Scope**: Extract valuable Shomee concepts into the Semantos loom without bloating the kernel

> **Implementation note (audited 2026-03-28 against semantos-core@492fc28):**
> Phase 8/8.5 is committed in `semantos-core` (separate repo from the `semantos`
> Zig/WASM repo). The loom is 46 source files across packages/loom/ with
> a real Bun server, 4 extension configs, and full identity plane. See conformance
> audit below for what's built, what conforms, and what's missing.

---

## Phase 8/8.5 Conformance Audit

Audited against the Phase 8 PRD (PHASE-8-SEMANTIC-WORKBENCH.md) and the Shomee
mapping assumptions. Source: `semantos-core/packages/loom/` (46 .ts/.tsx files).

### What's Built and Conforms

**Shell Framework (D8.1) — COMPLETE**
- `App.tsx` — three-panel layout (Sidebar, MainCanvas, Inspector)
- `shell/Sidebar.tsx`, `shell/MainCanvas.tsx`, `shell/Inspector.tsx`, `shell/StatusBar.tsx`
- `shell/ResizeHandle.tsx` — resizable panels
- `engine/useEngine.ts` — React hook loading CellEngine WASM (full/embedded profiles)
- `engine/EngineProvider.tsx` — React context wrapping WASM lifecycle
- `config/extensionConfig.ts` — ExtensionConfig schema with validation
- `config/ExtensionProvider.tsx` — extension config context + hot-reload
- `vite.config.ts`, `tailwind.config.ts` — Vite + React 19 + Tailwind build

**Semantic Object Panel / Sidebar (D8.2) — COMPLETE**
- `sidebar/ObjectTree.tsx` — object list grouped by archetype
- `sidebar/CapabilityToggles.tsx` — toggle domain flags per object
- `sidebar/TypeList.tsx` — type definitions from extension config
- `sidebar/TaxonomyBrowser.tsx` — dimension-aware tree navigation with category filter
- `sidebar/PolicyViewer.tsx` — policy display from extension config
- `sidebar/LinearityBadge.tsx` — visual linearity indicator
- `sidebar/CommercePhaseChip.tsx` — phase badge

**Canvas (D8.3) — COMPLETE**
- `canvas/Canvas.tsx` — card workspace with pan/zoom
- `canvas/LoomCard.tsx` — object cards with collapse/expand/maximize
- `canvas/ConnectionLine.tsx` — SVG connections between cards
- `canvas/CommandBar.tsx` — command shell with history, parser, executor
- `canvas/CommercePipeline.tsx` — commerce phase progression visualization
- `canvas/ConversationPanel.tsx` — messages as patches with facet provenance

**Inspector (D8.4) — COMPLETE**
- `inspector/ObjectInspector.tsx` — full cell header display, linearity transitions, flag decode
- `inspector/ScriptInspector.tsx` — script view
- `inspector/StackDebugView.tsx` — stack visualization
- `inspector/HexView.tsx` — raw 256-byte header hex display
- `inspector/EvidenceChain.tsx` — patch history (evidence chain)
- `inspector/AccumulatedStateView.tsx` — scoring/accumulated state view

**State Management — COMPLETE**
- `state/WorkbenchProvider.tsx` — React context + reducer
- `state/workbenchReducer.ts` — 16 action types (ADD_OBJECT, ADD_PATCH, TRANSITION_LINEARITY, SET_CAPABILITY, FILTER_BY_CATEGORY, etc.)
- `state/objectFactory.ts` — creates LoomObject from ObjectTypeDefinition, uses protocol-types `serializeCellHeader`, `MAGIC_*`, `Linearity`, `CommercePhase` constants

**Identity Plane (Phase 8.5) — COMPLETE**
- `identity/IdentityProvider.tsx` — Identity context with localStorage persistence
- `identity/FacetSelector.tsx` — facet switcher in StatusBar
- `identity/FacetManager.tsx` — add/remove facets with capabilities
- `identity/IdentitySetup.tsx` — first-run identity creation
- `identity/PolicyCreator.tsx` — create policies from conversation decisions
- Identity as AFFINE LoomObject, Facets as RELEVANT, Policies as RELEVANT
- Facet provenance stamped on every patch (`facetId` + `facetCapabilities`)
- ownerId on cell header from active facet

**Command System — COMPLETE**
- `commands/parser.ts` — typed command parser (create, list, inspect, execute, set, show, switch, step/continue/reset, help)
- `commands/executor.ts` — command executor with full loom context

**Bun Server (D8.6) — COMPLETE**
- `server/index.ts` — HTTP + WebSocket, extension config loading, workspace persistence
- `server/config-loader.ts` — loads extension JSON files, watches for changes
- `server/state.ts` — workspace state persistence

**Extension Configs — 4 CONFIGS**
- `configs/extensions/core.json` — base types (Thing/Action/Instrument), all 10 capabilities, all 8 commerce phases
- `configs/extensions/trades-services.json` — OddJobTodd: 7 object types, 7 capabilities, 3-dimension taxonomy, scoring policy
- `configs/extensions/blockchain-risk.json` — BREM extension
- `configs/extensions/development.json` — full debug config

**Core Kernel (semantos-core/src/) — PRODUCTION**
- `kernel/typeHashRegistry.ts` — SHA256 type hashes from WHAT/HOW/INSTRUMENT triples, buildCellHeader, packCell, unpackCell, isValidCell
- `kernel/cellPacker.ts` — production cell packing
- `kernel/merkleEnvelope.ts` — merkle envelope
- `kernel/opcodes.ts` — opcode definitions
- `kernel/wasm-interface.ts` — WASM export contract
- `types/semantic-objects.ts` — semantic object type definitions
- `types/capability.ts`, `types/domain-flags.ts` — capability and flag types

### What Conforms to the Shomee Mapping Assumptions

| Shomee Mapping Claim | Actual State | Verdict |
|---|---|---|
| ConversationPanel on action-type cards | Yes — messages stored as patches with facet provenance, channelId-scoped | CONFIRMED |
| CommandBar in canvas for system commands | Yes — typed parser + executor, 11 command types | CONFIRMED |
| FacetSelector for switching active identity | Yes — select dropdown in StatusBar, switches active facet | CONFIRMED |
| Facet provenance stamped on every patch | Yes — `facetId` + `facetCapabilities` on ObjectPatch | CONFIRMED |
| ownerId encoded in cell header from active facet | Yes — passed to `createObject()`, set on CellHeader | CONFIRMED |
| TaxonomyBrowser sidebar with dimension navigation | Yes — tree view with dimension groups, category filter | CONFIRMED |
| Linearity transitions defined in extension config | Yes — `linearityTransitions` on ObjectTypeDefinition | CONFIRMED |
| Commerce phase pipeline in loom UI | Yes — CommercePipeline component | CONFIRMED |
| Category field on ObjectTypeDefinition | Yes — `category` field with LTREE paths | CONFIRMED |
| objectFactory uses type registry constants | Yes — imports from @semantos/protocol-types, uses MAGIC_*, Linearity, CommercePhase | CONFIRMED |

### What's Missing or Incomplete

1. **typeHash fields are empty strings** in all extension config object types. The typeHashRegistry.ts has `computeTypeHash()` but extension configs don't pre-compute hashes. This means objects are created with zeroed typeHash bytes. **Fix: compute typeHash from WHAT/HOW/INSTRUMENT triple at config load time or object creation.**

2. **ConversationPanel is text-only** — no intent classification, no flow routing, no LLM integration. Messages are plain text patches. This is correct for Phase 8.5 but is the primary gap for Phase 9.

3. **CommandBar uses regex parsing, not LLM** — the command parser is a manual token parser. This works for developer commands but won't handle natural language. Phase 9 replaces this with LLM intent classification.

4. **No visibility field** on ObjectTypeDefinition (draft/published/revoked). Phase 9.5 adds this.

5. **No governance object types** registered in any extension config. Phase 9.5 adds these.

6. **No reputation scoring** on identities. Phase 10 adds this.

7. **`conversationEnabled` flag** exists on ObjectTypeDefinition but is only checked at the UI level — good, but there's no enforcement preventing conversations on types that have it false.

8. **Script execution is stubbed** — the `execute` command returns "not yet implemented." This is expected since the cell engine WASM exports are stubs in the Zig repo.

### Verdict

Phase 8/8.5 implementation is **solid and conforms** to both the PRD and the Shomee mapping assumptions. The loom is a real, functional application with extension configs driving rendering, identity plane with facet provenance, and conversation-as-patches. The gaps (intent classification, governance types, visibility, reputation) are all correctly scoped to Phase 9+.

The one structural issue is **empty typeHash values** — objects are identifiable by name but not by their cryptographic type hash. This should be addressed before Phase 9, either by pre-computing hashes in the config loader or at object creation time.

---

## Part 1: Audit of SHOMEE-TO-SEMANTOS-MAPPING.md

### Methodology

Every concept in the mapping document was evaluated against three questions:

1. **Does it already exist?** — Is the concept already covered by the cell engine, type registry, extension config, or loom shell?
2. **Does it belong in the kernel or the loom?** — Kernel additions must be universal. Domain-specific behaviour belongs in extension configs and conversation flows.
3. **Is it premature?** — Concepts that require infrastructure that doesn't exist yet (real network layer, production wallet, on-chain settlement) are parked, not planned.

### Verdict by Domain

#### Domain 1: Identity & Trust — KEEP (mostly done)

**Already built (Phase 8.5):**
- Identity as root AFFINE object with facets
- FacetSelector in StatusBar
- Facet provenance stamped on every patch
- ownerId encoded in cell header from active facet

**Worth extracting:**
- ReputationScore as a computed RELEVANT object — this is a loom extension, not a kernel change. The cell engine already supports RELEVANT linearity; reputation is a *type* registered in the extension config with computed payload fields. Reputation is a family of derived or attestable views (global, contextual, task-specific, portable ZK proofs over thresholds) rather than one monolithic score.
- Cert graph links as typed connections — these are CardConnections on the canvas. The loom already has ConnectionLine. The missing piece is a *connection type* in the extension config that carries cert reference metadata.

**Bloat risk:** The PIKE/BRC-42 integration is correctly deferred to when Plexus wallet exists. Don't stub it. Don't model it. Just note it as a future enabler.

**Audit verdict:** Clean. Identity is well-mapped. Reputation and cert links are extension config + conversation flow additions, not kernel changes.

#### Domain 2: Publication & Visibility — KEEP (needs loom flow, not kernel)

**Already built:**
- Linearity transitions in extension config (AFFINE → RELEVANT on "presented")
- Commerce phase pipeline in loom UI

**Worth extracting:**
- Visibility states (draft/published/revoked) as a first-class field on ObjectTypeDefinition. This is a *schema addition* to the extension config, not a kernel change. The cell header already has flags — visibility can be encoded there.
- Publish action as a conversation flow: user says "publish this" → intent classified → linearity transition triggered → type path assigned. This is the canonical loom pattern.

**Bloat risk:** Paywalls and time-locks are described as "capability-gated conditions." This is correct but premature. The access gate is optional — expressed as a 402-style challenge condition, not a consumed read-token. The object may expose a `402 Payment Required` challenge, and the access path can decide whether payment, entitlement, preview, or some other proof satisfies it. Model the *access policy field* now. Wire the *payment mechanic* later.

**Audit verdict:** Clean. Publication is a conversation flow on top of existing linearity transitions. Add visibility field to ObjectTypeDefinition. Don't build payment gating yet — but when you do, it's an optional access challenge, not literal per-read token consumption.

#### Domain 3: Category & Taxonomy — KEEP (mostly done)

**Already built:**
- TaxonomyBrowser sidebar with dimension navigation
- TaxonomyTree/TaxonomyNode/TaxonomyDimensionDef types
- Category field on ObjectTypeDefinition
- Filter by category in loom state
- LTREE dotted paths: services.trades.carpentry

**Worth extracting:**
- Reputation weight on taxonomy nodes — same pattern as identity reputation. Add a weight field to TaxonomyNode. Compute from activity/relevance. This is a schema change, not a kernel change.
- LLM-driven classification: user creates an object, the conversation classifies it into a type path. This is the core loom pattern — intent classification via OpenRouter. Not a separate "CategoryVectorizer" service.

**Bloat risk:** Staked category proposals and challenge mechanics are governance concepts that depend on stakes being real (on-chain LINEAR tokens). Model the *governance object types* now. Don't build the *staking mechanic* until payment channels exist.

**Audit verdict:** Clean. Taxonomy is well-mapped. Weight field and LLM classification are the two additions worth making.

#### Domain 4: Segment Routing & Multicast — PARK (premature)

**What it is:** SRv6 routing, multicast addressing, contract segments, geo-aware delivery, low-power mesh (BLE, Zigbee, Thread).

**Why it's premature:** Every concept in this domain requires a real network layer — overlay nodes, packet routing, multicast group management, payment segments consumed per hop. None of this infrastructure exists. The loom runs on localhost.

**What to scavenge:**
- The *addressing model* (type path = multicast group) is a useful mental model but doesn't need code. It's already implicit in how the taxonomy works.
- Contract segments as LINEAR objects consumed per hop — this maps to CashLanes payment channel patterns. When MFP channels exist, this concept applies. Until then, it's architecture fiction.

**Bloat risk:** HIGH. This domain is 100+ lines of mapping for infrastructure that is Phase 11+ at the earliest. The mapping document correctly identifies this as "not yet implemented — Phase 10+ territory."

**Audit verdict:** Park entirely. Don't allocate object types. Don't model network segments. Don't add addressing concepts to the loom. Revisit when CashLanes payment channels and Plexus node are real.

#### Domain 5: Chat as Semantic Shell — KEEP (highest value)

**Already built:**
- ConversationPanel on action-type cards
- Messages stored as patches with facet provenance
- CommandBar in canvas for system commands

**Worth extracting — this is the crown jewel:**
- Intent classification from free-text → routed action. User says "I need a plumber in Northcote" → classified as job.intake → creates AFFINE object at services.trades.plumbing → enters commerce pipeline. This is the entire UX thesis.
- Flow routing: classified intent → container/action. The Shomee ContainerFactory and ChatFlowRegistry concepts map directly to extension config scripts. Each script is a "flow" — a sequence of conversation turns that results in an object being created or transitioned.
- Specialised flows (publish, stake, challenge, tip) as conversation actions, not button clicks. The ConversationPanel becomes the universal input surface.

**The key Shomee insight to preserve:** Shomee had SemanticShell (OS-level), ChatRuntime (execution engine), IntentClassifier (routing), ContainerFactory (instantiation), and 5+ flow types (conversational, QA, task completion, post, stake, call). All of these collapse into: **ConversationPanel + LLM intent classification + extension config scripts**.

**Bloat risk:** LOW. The implementation is thin: LLM classifies intent → script selected from extension config → conversation drives patches on an object → linearity transition when flow completes. No new kernel concepts needed.

**Audit verdict:** This is the most valuable domain. It defines the loom UX. Prioritise intent classification and flow routing above everything else.

#### Governance (Cross-Cutting) — KEEP (object types only, not mechanics)

**Worth extracting:**
- Dispute, Stake, Ballot, Tribunal, Resolution as registered object types in extension configs. These are AFFINE/LINEAR/RELEVANT objects like any other — the cell engine doesn't need to know they're "governance."
- Commerce phase mapping for governance flows: SOURCE (filed) → PARSE (evidence gathered) → TYPECHECK (quorum checked) → ACTION (vote) → OUTCOME (resolved).

**Bloat risk:** The dispute engine, stake coordinator, cert ballot service, and tribunal router from Shomee are each 200-500 lines of TypeScript. In Semantos, they're conversation flows on governance object types. Don't build engines. Define types and let conversations drive them.

**Audit verdict:** Register the governance object types. Map their commerce phases. The "engine" is the conversation + linearity transitions. No separate governance service needed.

---

### Audit Summary Table

| Domain | Verdict | Kernel Changes | Loom Changes | Deferred |
|--------|---------|---------------|-------------------|----------|
| Identity & Trust | KEEP | None | Reputation type, cert connection type | PIKE/BRC-42 |
| Publication | KEEP | None | Visibility field on ObjectTypeDef, publish flow | Paywall mechanics |
| Category & Taxonomy | KEEP | None | Weight field on TaxonomyNode | Staked proposals |
| Segment Routing | PARK | None | None | Everything |
| Chat as Shell | KEEP | None | Intent classification, flow routing, script registry | None |
| Governance | KEEP | None | Governance object types, commerce phase mappings | Stake settlement |

**Key finding: Zero kernel changes needed.** Every valuable Shomee concept maps to either a extension config schema addition, a new object type registration, or a conversation flow in the loom. The cell engine, type registry, and linearity system are already sufficient.

---

## Part 2: README Update Guidance

The current README describes:
- Phase 1-3 as Forth-based (Phase 1 complete, Phase 2 crypto in progress, Phase 3 LISP compiler planned)
- A directory structure that references phase1-foundation/, phase2-crypto/, v4-improvements/, archive/

This is the old Forth reference implementation era. The project has since:
1. Moved to Zig/WASM cell engine (Phases 0-7.5 in docs/prd/)
2. Built Phase 8 Semantic Object Loom (React + Bun)
3. Completed Phase 8.5 Identity (facets, provenance, capabilities)
4. Branched away from Phase 7's CI/CD and the original Phase 8's embedded target

The README should reflect the actual state: a Zig/WASM cell engine kernel with a React loom shell, extension configs driving domain-specific behaviour, and conversation-driven interaction through LLM intent classification as the primary UX.

*(A separate README update task is recommended — this PRD focuses on the Shomee extraction roadmap.)*

---

## Part 3: Master PRD — Shomee Extraction into the Semantic Loom

### Design Principle

Every Shomee concept enters through the same door: **a conversation in the loom captures user intent, the LLM classifies it, and the system creates or transitions a semantic object**. There are no new services, no new databases, no new APIs. There are only:

1. **Object types** registered in extension configs
2. **Conversation flows** (scripts) that guide multi-turn interactions
3. **Linearity transitions** triggered by flow completion
4. **Commerce phase progressions** driven by conversation actions

The loom is the shell. The conversation is the interface. The cell engine is the kernel. Everything else is a extension config.

### Phase Overview

```
Phase 8.5 (done) ── Identity, facets, conversations, capability scoping
     │
Phase 9 ────────── LLM Intent Classification + Flow Routing
     │               (enables everything else)
     │
Phase 9.5 ──────── Publication + Visibility + Governance Types
     │               (object lifecycle through conversation)
     │
Phase 10 ───────── Taxonomy Governance + Reputation
     │               (community-driven type space)
     │
Phase 11 ───────── Network + Settlement Integration
     │               (when CashLanes/Plexus exist)
     │
Phase 12 ───────── Social Extension: Full Composition
                    (everything composes)
```

---

### Architectural Constraint: Renderer Agnosticism

**Applies to**: Phase 9 and all subsequent phases.

The Phase 8/8.5 loom is React. But the consumer surface may be a game engine
(Babylon.js, PlayCanvas), a CLI, a mobile app, a voice interface, or a VR headset.
The cell engine already got this right — it's WASM, renderer-agnostic by construction.
The loom application layer must follow the same pattern.

**Rule: All new services in Phase 9+ must be plain TypeScript, not React hooks.**

- `IntentClassifier` — takes a message + extension config, returns `IntentClassification`. Pure function.
- `FlowRegistry` — takes an intent, returns a `ConversationFlow`. Pure lookup.
- `FlowRunner` — tracks multi-turn flow state, emits patches. Event emitter or observable.
- `IdentityStore` — holds identity/facet state, emits changes. Currently in React context; extract to plain TS.
- `LoomStore` — holds object/card state, dispatches actions. Currently in React context; extract to plain TS.

React wraps these in contexts and hooks. A game engine subscribes directly. A CLI
reads over the Bun WebSocket (already on port 3001). The server doesn't know what's
rendering.

**What this means in practice:**

- New logic goes in `src/services/` (plain TS), not `src/canvas/` or `src/identity/` (React).
- React components import from services and call methods. They don't contain business logic.
- The Bun server WebSocket becomes the universal state sync channel — any client connects.
- Extension config gains optional `rendering` hints (spatial position, mesh, material) that
  a 3D renderer can consume and a 2D renderer ignores.

This is not a game engine phase. It's a separation-of-concerns constraint that keeps the
architecture open to any rendering target — including the "Semantos Second Life" extension
where semantic objects are entities in a 3D scene, type paths are spatial coordinates,
capabilities gate access to zones, reputation is rendered visually, and facet switching
changes what you can perceive.

The loom is the level editor. Any renderer is the game. The cell engine is
the simulation. Extension config is the content. Clean separation all the way down.

---

### Phase 9: LLM Intent Classification + Flow Routing

**Duration**: 3 weeks
**Prerequisites**: Phase 8.5 complete. ConversationPanel functional. CommandBar operational.
**Thesis**: The conversation becomes the universal interface. Without intent classification, conversations are just text patches. With it, every message is a classified action that creates or transitions objects.

#### What This Enables

Every subsequent phase depends on this. Publication, governance, taxonomy proposals, staking — all of these are conversation flows that begin with an intent being classified and routed to the right script.

#### Deliverables

**D9.1 — OpenRouter LLM Bridge**

A thin service that sends conversation context + extension config metadata to an OpenRouter-compatible endpoint and receives a classified intent.

```typescript
interface IntentClassification {
  intent: string;              // "create.job", "publish", "stake", "challenge", "navigate"
  confidence: number;          // 0-1
  objectType?: string;         // typeHash of the target object type
  typePath?: string;           // taxonomy path for auto-classification
  flowId?: string;             // script/flow to activate
  extractedFields?: Record<string, unknown>;  // fields parsed from natural language
}
```

The LLM receives:
- Current extension config (object types, capabilities, taxonomy)
- Active facet and capabilities
- Current object context (if conversation is on a card)
- The user's message

The LLM returns: an IntentClassification.

**Key constraint**: The user provides their own OpenRouter API key (BYOK model from commercial context). The loom never holds API keys — they're stored in localStorage or a local config file.

**D9.2 — Flow Registry**

Scripts in extension config become executable conversation flows. Each flow defines:

```typescript
interface ConversationFlow {
  id: string;                          // "create-job", "publish-listing", "file-dispute"
  triggerIntents: string[];            // intents that activate this flow
  requiredCapabilities: number[];      // facet must have these
  steps: FlowStep[];                   // conversation turn sequence
  onComplete: FlowAction;             // what happens when the flow finishes
}

interface FlowStep {
  prompt: string;                      // what the system asks
  extractionSchema: Record<string, FieldType>;  // what to extract from the response
  validation?: string;                 // validation expression
  optional?: boolean;
}

interface FlowAction {
  type: 'create' | 'transition' | 'patch' | 'navigate';
  objectType?: string;                 // for 'create'
  linearityTransition?: string;        // for 'transition'
  patchFields?: string[];              // for 'patch'
}
```

Flows live in the extension config JSON. The loom loads them alongside object types and taxonomy.

**D9.3 — ConversationPanel Intent Integration**

The existing ConversationPanel gains:
- Intent classification on every user message (async, non-blocking)
- Intent indicator badge on the message (shows what was classified)
- Flow activation when a message triggers a registered flow
- Multi-turn flow state: the ConversationPanel tracks which step of a flow is active and prompts accordingly
- Flow completion triggers the FlowAction (create object, transition linearity, apply patch)

**D9.4 — CommandBar Intent Bridge**

The CommandBar (system-level commands) gains:
- Intent classification for navigation and system actions
- "Go to plumbing jobs" → navigate to taxonomy path services.trades.plumbing
- "Show my disputes" → filter by governance.dispute type
- "Switch to business facet" → FacetSelector activation

#### Shomee Concepts Absorbed

| Shomee Component | Absorbed By |
|---|---|
| SemanticShell | CommandBar + ConversationPanel |
| ChatRuntime | ConversationPanel with flow state |
| IntentClassifierService | D9.1 OpenRouter bridge |
| ContainerFactory | D9.2 Flow registry (extension config scripts) |
| ChatFlowRegistry | D9.2 Flow registry |
| ConversationalChatFlow | Multi-turn flow on ConversationPanel |
| TaskCompletionChatFlow | Flow with onComplete: create/transition |
| ListingContainer | "create-listing" flow in extension config |
| PaymentContainer | "stake" flow in extension config |
| ChatOverlayService | CommandBar intent integration |
| CommandParser | LLM intent classification (replaces regex parsing) |
| PostFlow | "publish" flow in extension config |
| StakeFlow | "stake" flow in extension config |
| CallFlow | "contact" flow in extension config |

#### Object Types Registered

```
shell.session           — LINEAR  (one session, consumed on end)
shell.flow-state        — LINEAR  (tracks active flow, consumed on completion)
```

#### Completion Criteria

1. User types "I need a plumber in Northcote" in ConversationPanel → intent classified as create.job with typePath services.trades.plumbing
2. Flow activates, asks for details across 2-3 turns, creates AFFINE job object on completion
3. CommandBar accepts "show plumbing jobs" → navigates to taxonomy filter
4. Intent classification works with both OddJobTodd and BREM extensions (different flows, same mechanism)
5. BYOK: OpenRouter API key configurable in loom settings, not hardcoded

#### What NOT To Do

- Do not build a custom NLP pipeline. Use the LLM.
- Do not hard-code intent patterns. Everything comes from extension config.
- Do not make the LLM bridge synchronous/blocking. Classify in background, show results when ready.
- Do not store API keys on the server. localStorage or local config file only.

---

### Phase 9.5: Publication + Visibility + Governance Types

**Duration**: 2 weeks
**Prerequisites**: Phase 9 complete. Intent classification and flow routing operational.
**Thesis**: Objects have lifecycles — draft, published, revoked. Governance is just another set of object types with conversation flows. Both are enabled by intent classification.

#### Deliverables

**D9.5.1 — Visibility Field on ObjectTypeDefinition**

Add to extension config schema:

```typescript
interface ObjectTypeDefinition {
  // ... existing fields ...
  visibility?: {
    states: ('draft' | 'published' | 'revoked')[];
    defaultState: 'draft' | 'published';
    publishTransition?: {
      fromLinearity: 'AFFINE';
      toLinearity: 'RELEVANT';
      requiredCapabilities?: number[];
    };
    revokePreservesEvidence: boolean;  // always true — revoked objects stay RELEVANT
  };
  accessPolicy?: {
    default: 'public' | 'private' | 'facet-scoped';
    overridable: boolean;
  };
}
```

**D9.5.2 — Publish Flow**

A conversation flow registered in extension configs:
- Trigger intent: "publish"
- Steps: confirm object ready → set visibility → trigger linearity transition (AFFINE → RELEVANT) → assign type path if not set
- On complete: object becomes RELEVANT, visibility set to "published"

Revoke flow:
- Trigger intent: "revoke" / "retract" / "hide"
- Steps: confirm revocation → apply revocation patch → set visibility to "revoked"
- On complete: object remains RELEVANT (evidence preserved), visibility flag changes

**D9.5.3 — Governance Object Types**

Register in extension config (available across extensions):

```json
{
  "objectTypes": [
    {
      "name": "Dispute",
      "linearity": "AFFINE",
      "category": "governance.dispute",
      "fields": [
        { "name": "subject", "type": "reference" },
        { "name": "claimant", "type": "identity-ref" },
        { "name": "respondent", "type": "identity-ref" },
        { "name": "status", "type": "enum", "values": ["open", "evidence", "review", "resolved"] }
      ],
      "commercePhases": ["SOURCE", "PARSE", "TYPECHECK", "ACTION", "OUTCOME"],
      "linearityTransitions": [
        { "from": "AFFINE", "to": "RELEVANT", "trigger": "resolved" }
      ]
    },
    {
      "name": "Ballot",
      "linearity": "AFFINE",
      "category": "governance.ballot",
      "fields": [
        { "name": "motion", "type": "text" },
        { "name": "quorum", "type": "number" },
        { "name": "votes", "type": "patch-accumulator" }
      ],
      "linearityTransitions": [
        { "from": "AFFINE", "to": "RELEVANT", "trigger": "finalized" }
      ]
    },
    {
      "name": "Stake",
      "linearity": "LINEAR",
      "category": "governance.stake",
      "fields": [
        { "name": "amount", "type": "number" },
        { "name": "subject", "type": "reference" },
        { "name": "staker", "type": "identity-ref" }
      ]
    },
    {
      "name": "Resolution",
      "linearity": "RELEVANT",
      "category": "governance.resolution",
      "fields": [
        { "name": "dispute", "type": "reference" },
        { "name": "outcome", "type": "enum", "values": ["upheld", "dismissed", "split"] },
        { "name": "reasoning", "type": "text" }
      ]
    }
  ]
}
```

**D9.5.4 — Governance Conversation Flows**

File dispute flow: "I want to challenge this listing" → creates dispute object → links to subject → enters evidence-gathering conversation.

Vote flow: "Vote yes on the category proposal" → finds active ballot → applies vote patch → checks quorum.

These are conversation flows, not engines. The LLM classifies the intent, the flow guides the turns, the patches accumulate on the object, and the linearity transition fires when the flow completes.

#### Shomee Concepts Absorbed

| Shomee Component | Absorbed By |
|---|---|
| DraftPubService | Publish conversation flow |
| ListingPubService | Publish flow + type path assignment |
| ModalRegistry | Extension config scripts (each flow = one modal) |
| DisputeEngine | Dispute object type + dispute conversation flow |
| StakeCoordinator | Stake object type (LINEAR, consumed on resolution) |
| CertBallotService | Ballot object type + vote conversation flow |
| TribunalRouter | Tribunal as RELEVANT policy object at type path coordinate |
| CertChallengeFSM | Commerce phase transitions on dispute object |
| Realm system | Extension configs (each extension = one realm) |

#### Completion Criteria

1. An AFFINE object can be published (→ RELEVANT) via conversation: "publish this"
2. A published object can be revoked via conversation, evidence preserved
3. Dispute, Ballot, Stake, Resolution object types registered and creatable
4. Dispute conversation flow: file → gather evidence → resolve → linearity transition
5. Governance types work across OddJobTodd and BREM extensions

---

### Phase 10: Taxonomy Governance + Reputation

**Duration**: 2 weeks
**Prerequisites**: Phase 9.5 complete. Governance object types registered. Publication flow working.
**Thesis**: The type space itself is governed through three-axis taxonomy (WHAT/HOW/WHY). Taxonomy nodes are semantic objects. Reputation is a family of derived views over identity evidence chains. New categories are proposed through conversations, approved through ballots.

#### Architectural Decision: Three-Axis Taxonomy

Type space is not a single flat tree. It is a coordinate space across three orthogonal LTREE dimensions:

- **WHAT** — what the thing is (taxonomy.what.*)
- **HOW** — how it operates / is performed / is realised (taxonomy.how.*)
- **WHY** — what function / purpose / end it serves (taxonomy.why.*)

Object types are compositions across axes, not descendants of one hierarchy:

```typescript
interface TypeCoordinate {
  what: string;      // e.g. "what.service.fabrication.carpentry"
  how: string[];     // e.g. ["how.physical.manual", "how.technical.joinery"]
  why: string[];     // e.g. ["why.production", "why.maintenance"]
}
```

Taxonomy nodes are themselves semantic objects (taxonomy.node type). Patches can be applied to taxonomy objects. Child branches inherit or specialise parent meaning. Schema, policies, flows, and view hints accumulate around taxonomy coordinates as children — making each branch a **semantic jurisdiction** where meaning, structure, governance, and affordances converge.

The authoritative ontology is symbolic/object-native. Embeddings are an assistive index for synonym discovery, candidate classification, and merge suggestions — explicitly non-authoritative.

#### Seeding Strategy

Seed from wiki-scale ontology (Wikidata/Wikipedia), but compress through a civilisational production lens: contribution, utility, coordination, and externalities. Not a neutral encyclopedia — a production ontology grounded in what things do, what they cost, what they enable, and how they affect other agents across time. This includes reproductive/generative functions (parenting, care work, education) as first-class economic realities.

Each taxonomy node carries fields: function_type, primary_outputs, required_inputs, enables, depends_on, positive_externalities, negative_externalities, time_horizon, beneficiary_scope, substitutability.

Embeddings DB assists lookup and synonym resolution but is never the source of truth. Seed first, govern later, assist with embeddings, preserve symbolic authority.

#### Deliverables

**D10.1 — Reputation on Identities**

Add ReputationScore as a computed RELEVANT object type:

```typescript
interface ReputationScore {
  base: number;              // initial score
  activity: number;          // from recent actions
  disputeOutcomes: number;   // from dispute wins/losses
  contributions: number;     // from accepted taxonomy proposals
  total: number;             // computed weighted sum
  context?: string;          // optional context scope (global if omitted)
}
```

Reputation is a family of views: global, contextual (scoped to a type path or domain), task-specific, and portable (ZK proofs over thresholds without revealing the underlying evidence graph). Recomputed on read (materialized view pattern), not stored as a separate patch stream. Pulls from identity's evidence chain: stakes won/lost, disputes resolved, contributions accepted.

Display in StatusBar alongside FacetSelector. Display on other users' objects as a trust indicator.

**D10.2 — Three-Axis Taxonomy Node Weights**

Add weight field to TaxonomyNode, now across all three axes:

```typescript
interface TaxonomyNode {
  // ... existing fields ...
  axis: "what" | "how" | "why";   // which dimension this node belongs to
  weight?: {
    activity: number;              // objects placed at this coordinate recently
    relevance: number;             // reputation-weighted activity
    lastUpdated: string;           // ISO timestamp
  };
}
```

Weights influence sort order in TaxonomyBrowser. High-activity coordinates surface first. Low-activity coordinates fade (but never disappear — taxonomy is append-only).

**D10.3 — Taxonomy Proposal Flow**

A conversation flow for proposing new coordinates in any axis:

"I think we need a category for solar panel installation under what.service.trades"
→ Intent: taxonomy.propose
→ Flow: describe proposed node → specify axis and parent path → create Ballot object → community votes
→ On quorum reached: TaxonomyNode added to extension config overlay

Taxonomy proposals are Ballot objects at a well-known type path (governance.taxonomy-proposal). The ballot accumulates votes as patches. When quorum is reached, the TaxonomyNode is appended to the appropriate axis.

**D10.4 — Challenge Flow for Misclassified Objects**

"This listing is filed under plumbing but it's clearly electrical work"
→ Intent: governance.challenge
→ Flow: identify object → identify correct coordinate(s) → create Dispute → gather evidence → resolve
→ On resolution: object reclassified or challenge dismissed

Misclassification challenges are Dispute objects with a reclassification action on resolution.

#### Shomee Concepts Absorbed

| Shomee Component | Absorbed By |
|---|---|
| GlowweightEvaluatorService | ReputationScore materialized view over identity evidence chain |
| CategoryLoaderService | Already done — TaxonomyBrowser |
| CategoryVectorizerService | LLM classification in Phase 9 |
| CategorySyncService | Extension config hot-reload |
| CategoryClassifierService | LLM intent classification |
| PatchModerationService | Taxonomy proposal ballot flow |
| GlowWeightUtils (routing) | TaxonomyNode weight field across three axes |

#### Completion Criteria

1. Reputation displayed on StatusBar for active identity
2. Reputation visible on other users' objects as trust indicator
3. TaxonomyBrowser supports three-axis navigation (WHAT/HOW/WHY)
4. TaxonomyBrowser sorts by node weight (activity/relevance)
5. Taxonomy proposal flow: propose → ballot → approve → node appears
6. Misclassification challenge flow: challenge → dispute → resolve → reclassify or dismiss
7. Taxonomy nodes are semantic objects with patches, not just config entries

---

### Phase 11: Network + Settlement Integration (Future — When Infrastructure Exists)

**Duration**: TBD
**Prerequisites**: CashLanes payment channels operational. Plexus node exists. Real BSV wallet integration.
**Thesis**: Objects flow through the network. Payment channels meter access. Contract segments enforce conditions.

This phase is deliberately underspecified because it depends on infrastructure that doesn't exist yet. The key concepts to preserve from Shomee:

**Type paths as multicast addresses.** When a Plexus node subscribes to services.trades.plumbing, it receives objects published to that type path. The addressing model is already implicit in the taxonomy.

**Contract segments as LINEAR objects.** A payment segment is consumed per hop. A cert segment checks capabilities. These map directly to cell engine linearity enforcement once CashLanes channels can fund them.

**Geo-aware routing.** A geo dimension in the taxonomy (already supported as a taxonomy dimension). Objects at services.trades.plumbing.au.vic.3070 are discoverable by geographic proximity.

**Stake mechanics become real.** The Stake object type registered in Phase 9.5 currently tracks amounts as numbers. In Phase 11, stakes are backed by LINEAR BSV payment tokens created through CashLanes channels. Forfeit means the token is consumed. Return means the token is released.

**IoT edge.** The low-power mesh concepts (BLE, Zigbee, Thread) from Shomee point toward an IoT extension where sensor data flows as LINEAR objects. The cell engine already targets embedded (Phase 8 embedded target). Worth revisiting when the first IoT extension is defined.

No deliverables specified. This phase activates when the enabling infrastructure arrives.

---

### Phase 12: Social Extension — Full Composition

**Duration**: TBD
**Prerequisites**: Phase 11 complete. Network delivery operational. Stake mechanics real.
**Thesis**: Everything composes. The attention economy inverts — reputation flows to quality, payment flows to value, garbage is challenged and penalised.

This is the Shomee thesis realised on the Semantos kernel:
- Identity with reputation (Phase 10)
- Publication with visibility (Phase 9.5)
- Governance with disputes, stakes, ballots (Phase 9.5)
- Taxonomy with community governance (Phase 10)
- Network delivery with contract segments (Phase 11)
- Conversation as the universal interface (Phase 9)

A new extension config: social.json. Object types include Post, Comment, Tip, Follow, Block. All governed by the same mechanisms as OddJobTodd jobs or BREM risk assessments. The conversation panel drives all interactions. Reputation determines visibility. Stakes back quality claims. Disputes resolve disagreements.

93 Shomee packages → 1 extension config + ~15 object types + conversation flows.

No deliverables specified. This is the endgame extension that proves the architecture.

---

## Part 4: What the Mapping Document Got Right

The mapping document's thesis is correct: **93 packages collapse to ~20 object types on one engine.** The audit confirms this. Not a single Shomee concept requires a kernel change. Every concept maps to:

1. An **object type** registered in a extension config
2. A **conversation flow** that creates or transitions that object
3. A **linearity rule** already enforced by the cell engine
4. A **commerce phase** already modelled in the loom

The type registry is the index. The cell engine is the kernel. The loom is the shell. The conversation is the interface.

## Part 5: What the Mapping Document Got Wrong (or Inflated)

1. **Domain 4 (Segment Routing) is premature.** 100+ lines of mapping for infrastructure that doesn't exist. The addressing concepts are already implicit in the taxonomy. Park it.

2. **Object type proliferation.** The mapping defines 20+ object types across 5 domains + governance. Many of these (shell.session, shell.intent, shell.flow, network.segment, network.multicast-group, network.payment-segment, network.cert-segment) are either unnecessary or premature. The actual count of *near-term* types is closer to 12:
   - identity.root, identity.facet, identity.reputation, identity.session
   - listing.draft → listing.published → listing.revoked (one type with visibility states, not three)
   - taxonomy.proposal
   - governance.dispute, governance.stake, governance.ballot, governance.resolution, governance.tribunal

3. **"Still needed" lists are too long.** Each domain's "still needed" section reads like a separate project. The audit shows that most items are conversation flows on existing object types, not new infrastructure.

4. **Governance as "cross-cutting" is misleading.** Governance is just object types with linearity transitions. It's no more cross-cutting than any other object type. Calling it cross-cutting implies a separate governance engine, which is exactly what Shomee built (and what Semantos should not).

---

## Part 6: Updated Phase Summary

| Phase | Focus | Duration | Enables |
|---|---|---|---|
| 8.5 (done) | Identity, facets, conversations, capability scoping | — | "Who you are" |
| 9 | LLM intent classification + flow routing | 3 weeks | "Talk to objects instead of filling forms" |
| 9.5 | Publication + visibility + governance types | 2 weeks | "Object lifecycles through conversation" |
| 10 | Taxonomy governance + reputation | 2 weeks | "Community-driven type space" |
| 11 | Network + settlement (when infra exists) | TBD | "Content finds you, payment flows" |
| 12 | Social extension: full composition | TBD | "Everything composes" |

**Phases 9-10 total: 7 weeks.** These are the actionable phases that extract all near-term value from Shomee into the loom.

**Phases 11-12 are parked.** They activate when CashLanes payment channels and Plexus node infrastructure exist.

---

## Appendix A: Object Type Registry (Near-Term)

All types below are registered in extension configs, not hard-coded in the kernel.

| Type Path | Linearity | Commerce Phases | Notes |
|---|---|---|---|
| identity.root | AFFINE | — | Accumulates facets, history |
| identity.facet | RELEVANT | — | Frozen cert stub with capabilities |
| identity.reputation | RELEVANT | — | Computed reputation score (family of views: global, contextual, ZK-provable) |
| identity.session | LINEAR | — | Consumed on logout/expiry |
| listing (with visibility) | AFFINE → RELEVANT | SOURCE → OUTCOME | Visibility states: draft/published/revoked |
| governance.dispute | AFFINE → RELEVANT | SOURCE → OUTCOME | Accumulates evidence, resolves |
| governance.stake | LINEAR | — | Consumed exactly once on resolution |
| governance.ballot | AFFINE → RELEVANT | SOURCE → OUTCOME | Accumulates votes, freezes when finalized |
| governance.tribunal | RELEVANT | — | Policy object at type path coordinate |
| governance.resolution | RELEVANT | — | Frozen decision with reasoning |
| taxonomy.proposal | AFFINE | SOURCE → OUTCOME | Ballot for new taxonomy node |
| shell.flow-state | LINEAR | — | Tracks active conversation flow |

## Appendix B: Conversation Flow Registry (Near-Term)

| Flow ID | Trigger Intents | Creates/Transitions | Phase |
|---|---|---|---|
| create-object | "create", "new", "I need" | Creates typed object | 9 |
| navigate | "show", "go to", "find" | Filters taxonomy/objects | 9 |
| publish | "publish", "make public" | AFFINE → RELEVANT transition | 9.5 |
| revoke | "revoke", "retract", "hide" | Visibility flag change | 9.5 |
| file-dispute | "challenge", "dispute", "flag" | Creates dispute object | 9.5 |
| vote | "vote", "approve", "reject" | Patch on ballot object | 9.5 |
| propose-category | "propose category", "new category" | Creates taxonomy.proposal ballot | 10 |
| challenge-classification | "misclassified", "wrong category" | Creates dispute with reclassification | 10 |

## Appendix C: Shomee Package → Semantos Mapping (Complete)

For reference, how every significant Shomee package maps:

| Shomee Package | Semantos Equivalent | Phase |
|---|---|---|
| civ-stack-identity | identity.root + identity.facet types (done in 8.5) | 8.5 |
| civ-stack-certgraph | CardConnections with cert reference metadata | 9.5 |
| civ-stack-pike | Deferred to Plexus wallet availability | 11 |
| civ-stack-governance | governance.* object types + conversation flows | 9.5 |
| civ-stack-governance-client | Loom UI components for governance | 9.5 |
| civ-stack-chat | ConversationPanel + intent classification | 9 |
| civ-stack-chat-overlay | CommandBar intent integration | 9 |
| civ-stack-chat-overlay-client | Flow implementations in extension config | 9 |
| civ-stack-category | TaxonomyBrowser (done in 8) + weight field | 10 |
| civ-stack-modals | Extension config scripts (each flow = one modal) | 9 |
| civ-stack-sr6-router | Parked — Phase 11+ | 11 |
| civ-stack-stream-network | Parked — Phase 11+ | 11 |
| civ-stack-contract-segment | Parked — Phase 11+ | 11 |
| civ-stack-overlaynet | Parked — Phase 11+ | 11 |
| civ-stack-lowpan-overlay | Parked — Phase 11+ | 11 |
