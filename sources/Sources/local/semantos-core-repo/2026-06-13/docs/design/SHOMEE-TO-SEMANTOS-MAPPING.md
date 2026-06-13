---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/SHOMEE-TO-SEMANTOS-MAPPING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.730580+00:00
---

# Shomee → Semantos: Architectural Mapping & Roadmap

> The shomee-alpha monorepo (93 packages) was R&D for a semantic operating system
> built on BSV. Much of it is vibe-coded scaffolding, but the conceptual fossils
> are sound. This document maps those concepts onto the Semantos reference
> implementation — same vision, different foundation.
>
> Semantos replaces Postgres/Redis/Kysely with the cell engine (256-byte headers,
> linearity rules, commerce phases). Shomee's services become semantic objects.
> Shomee's state machines become linearity transitions. Shomee's database
> transactions become single-spend LINEAR guarantees.

---

## How to Read This Document

Each domain section follows the same structure:

1. **Concept** — what the domain does
2. **Shomee R&D** — file paths to the original implementation (patterns and ideas)
3. **Semantos Mapping** — how it maps to the cell engine and loom
4. **Object Types** — the semantic objects this domain introduces
5. **Open Questions** — things still to resolve

All shomee paths are relative to `projects/shomee-alpha/`.

---

## Domain 1: Identity & Trust

### Concept

You are a semantic object. Your identity accumulates facets (BRC-52 certificate
stubs), each scoping a set of capabilities. Your reputation (glowweight) is a
RELEVANT object — always visible, computed from your history of stakes, tips,
disputes won/lost, and contributions. Trust is a spectrum, not a boolean.

### Shomee R&D

**Identity core:**
- `packages/civ-stack-identity/src/types/gipTypes.ts` — GIP trait fields and validation
- `packages/civ-stack-identity/src/services/IdentityService.ts` — Core identity service
- `packages/civ-stack-identity/src/services/GIPService.ts` — Global Identity Profile
- `packages/civ-stack-identity/src/services/SessionManagerService.ts` — Session lifecycle
- `packages/civ-stack-identity/src/session/sessionManager.ts` — Session state

**Certificate graph:**
- `packages/civ-stack-certgraph/src/semantic/certGraph.ts` — Linked certificate proofs
- `packages/civ-stack-certgraph/src/semantic/glowWeight.ts` — Glow weight config and entries
- `packages/civ-stack-certgraph/src/certGraph/services/certGraphLinkService.ts` — Cert linking

**Key exchange:**
- `packages/civ-stack-pike/src/services/KeyExchangeService.ts` — PIKE key exchange
- `packages/civ-stack-pike/src/services/PIKEService.ts` — Mutual authentication

**Glowweight (governance):**
- `packages/civ-stack-governance-client/src/types/glowweight.ts` — Score, adjustment, ranking types
- `packages/civ-stack-governance-client/src/interfaces/GlowweightEvaluator.ts` — Evaluator interface
- `packages/civ-stack-governance/src/services/GlowweightEvaluatorService.ts` — Implementation

### Semantos Mapping

| Shomee Concept | Semantos Equivalent |
|---|---|
| GIP identity | Identity semantic object (AFFINE, archetype: identity) |
| GIP traits | Facet capabilities — bitmask on the cell header flags field |
| Certificate graph | Evidence chain on the identity object — patches with cert references |
| Glow weight score | RELEVANT object on identity, computed from stake/tip/dispute history |
| Glow weight components | Payload fields: base, activity, reputation, disputes, contributions |
| Session manager | localStorage persistence (Phase 8.5), future: Plexus RaaS session |
| PIKE key exchange | BRC-42 ECDH via Plexus wallet — derivation path on the Facet object |

**Already implemented (Phase 8.5):**
- Identity as root object with facets and capabilities
- FacetSelector for switching active identity presentation
- Facet provenance stamped on every patch (facetId + facetCapabilities)
- ownerId encoded in cell header from active facet

**Still needed:**
- GlowweightScore as a computed RELEVANT object on the identity
- Cert graph links as typed connections between identity objects
- PIKE/BRC-42 integration when Plexus wallet is available

### Object Types

```
identity.root           — AFFINE  (accumulates facets, history)
identity.facet          — RELEVANT (frozen cert stub, capabilities)
identity.glowweight     — RELEVANT (always visible reputation score)
identity.session        — LINEAR  (consumed on logout/expiry)
```

### Open Questions

- Should glowweight be recomputed on read (materialized view) or stored as a
  patched object that updates on every relevant event?
- How does the cert graph map to object connections on the canvas? Each cert link
  could be a CardConnection, but the graph might be too dense for visual rendering.

---

## Domain 2: Publication & Visibility

### Concept

Objects have visibility states: draft (private, mutable), published (public,
frozen or append-only), revoked (hidden, evidence preserved). Publication is a
linearity transition — AFFINE → RELEVANT. Access policies scope who can see what.
Paywalls and time-locks are capability-gated conditions on the object.

### Shomee R&D

**Publication services:**
- `packages/civ-stack-chat/src/services/draftPubService.ts` — Draft state management
- `packages/civ-stack-chat/src/services/listingPubService.ts` — Publish to network
- `packages/civ-stack-chat/src/containers/ListingContainer.ts` — Listing creation flow
- `packages/civ-stack-chat/src/types/events.ts` — DraftPublished, ListingPublished events

**Modal system (publication UX):**
- `packages/civ-stack-modals/src/registry/modalRegistry.ts` — Global modal registry
- `packages/civ-stack-modals/src/definitions/ListingModal.ts` — Listing flow definition
- `packages/civ-stack-modals/src/types/ModalDefinition.ts` — Schema with access policy

### Semantos Mapping

| Shomee Concept | Semantos Equivalent |
|---|---|
| Draft state | AFFINE object at commerce phase SOURCE or PARSE |
| Published state | RELEVANT object (linearity transition triggered by "publish") |
| Revoked state | Commerce phase OUTCOME with revocation patch |
| Access policy (public/private/group/restricted) | Capability flags on cell header + facet scoping |
| Paywall condition | LINEAR payment token required to access — consumed on read |
| Time-lock condition | Commerce phase gate — object only visible after phase transition |
| DraftPubService | Conversation action: "publish this" → linearity transition |
| ListingPubService | Publish patch → type path assignment → multicast to subscribers |
| ListingContainer | ConversationPanel flow: intent classified as "create listing" |
| ModalRegistry | Extension config scripts — each script is a modal equivalent |

**Already implemented (Phase 8.5):**
- Linearity transitions defined in extension config (e.g., AFFINE → RELEVANT on "presented")
- Commerce phase pipeline in loom UI
- ConversationPanel for intent-driven interaction

**Still needed:**
- Explicit visibility field on objects (draft/published/revoked)
- Access policy as a first-class field on ObjectTypeDefinition
- Publish action that triggers linearity transition + type path assignment
- Paywall/time-lock as capability-gated conditions

### Object Types

```
listing.draft           — AFFINE  (mutable, private to author)
listing.published       — RELEVANT (frozen, visible per access policy)
listing.revoked         — RELEVANT (hidden, evidence chain preserved)
listing.access-token    — LINEAR  (consumed on access — paywall mechanic)
```

### Open Questions

- Should "revoked" be a separate linearity state or just a commerce phase
  (OUTCOME) with a revocation flag? Leaning toward commerce phase since the
  object should remain RELEVANT (immutable evidence) even when hidden.
- Access policies: per-object or per-type-path? Probably both — type path sets
  defaults, individual objects can override.

---

## Domain 3: Category & Taxonomy

### Concept

Content lives at coordinates in type space. The taxonomy is a DAG (directed
acyclic graph) of category nodes with LTREE paths. Categories have glow weights
(relevance scores). New categories are proposed via staked patches — the
community approves or rejects them through the governance system. Misclassified
content is challenged and the stake is forfeit.

### Shomee R&D

**Category services:**
- `packages/civ-stack-category/src/services/CategoryLoaderService.ts` — Taxonomy loading
- `packages/civ-stack-category/src/services/CategoryVectorizerService.ts` — Semantic vectorization
- `packages/civ-stack-category/src/services/CategorySyncService.ts` — Sync and updates

**Category types (cert graph integration):**
- `packages/civ-stack-certgraph/src/semantic/types/CategoryNode.ts` — Node type
- `packages/civ-stack-certgraph/src/semantic/flattenCategoryTree.ts` — Tree flattening

**Category classification (modal routing):**
- `packages/civ-stack-modals/src/types/category.ts` — Category type definitions
- `packages/civ-stack-modals/src/services/CategoryClassifierService.ts` — Intent-to-category

**Patch moderation (staked proposals):**
- `packages/civ-stack-governance/src/services/patchModerationService.ts` — Staked taxonomy changes

### Semantos Mapping

| Shomee Concept | Semantos Equivalent |
|---|---|
| CategoryNode | TaxonomyNode in extension config — already implemented |
| Category DAG | TaxonomyTree with dimensions (WHAT/HOW/INSTRUMENT) |
| Category glow weight | Weight field on TaxonomyNode (new) |
| CategoryVectorizer | LLM-driven classification via OpenRouter (future) |
| CategoryClassifier | Intent classifier in ConversationPanel |
| Patch moderation | Staked proposal → dispute → ballot → approve/reject |
| Category sync | Extension config hot-reload or overlay subscription |
| LTREE paths | Already using dotted paths: services.trades.carpentry |

**Already implemented (Phase 8):**
- TaxonomyBrowser sidebar with dimension navigation
- TaxonomyTree/TaxonomyNode/TaxonomyDimensionDef types
- Category field on ObjectTypeDefinition
- Filter by category in loom state

**Still needed:**
- Glow weight on taxonomy nodes (activity/relevance scoring)
- Staked category proposals as a governance action
- Challenge mechanic for misclassified objects
- Semantic vectorization for auto-classification (LLM integration)

### Object Types

```
taxonomy.node           — RELEVANT (immutable once accepted)
taxonomy.proposal       — AFFINE  (accumulates votes/stakes until resolved)
taxonomy.challenge      — AFFINE  (accumulates evidence until resolved)
```

### Open Questions

- Should taxonomy nodes be semantic objects themselves (stored in the cell engine)
  or remain JSON config? If they're objects, they get evidence chains, glow
  weights, and governance for free. If they're config, they're simpler but static.
- The CategoryVectorizer concept (embedding categories for semantic search) maps
  to the OpenRouter LLM integration — classify objects into type paths via
  conversation rather than manual selection.

---

## Domain 4: Segment Routing & Multicast

### Concept

Content published to a type path is multicast to subscribers on that path's
subnet. The network layer uses SRv6 (Segment Routing over IPv6) with contract
segments that encode access control, payment conditions, and tipping. Geo-aware
routing lets content find nearby consumers. Glow-weighted routing prioritises
high-reputation sources.

This is the furthest-future domain — it requires real network infrastructure.
But the addressing model and the contract segment concept inform how the
loom models content distribution even before the network layer exists.

### Shomee R&D

**SRv6 routing:**
- `packages/civ-stack-sr6-router/src/types/SegmentTypes.ts` — Segment and packet types
- `packages/civ-stack-sr6-router/src/router/SRv6Router.ts` — Router implementation
- `packages/civ-stack-sr6-router/src/router/SRv6RouterFactory.ts` — Router factory
- `packages/civ-stack-sr6-router/src/interfaces/SRv6Router.ts` — Router interface
- `packages/civ-stack-sr6-router/src/services/SegmentExecutorImpl.ts` — Segment execution
- `packages/civ-stack-sr6-router/src/services/PacketValidatorImpl.ts` — Packet validation

**Multicast & addressing:**
- `packages/civ-stack-stream-network/src/interfaces/MulticastAddressManager.ts` — Multicast allocation
- `packages/civ-stack-stream-network/src/interfaces/AddressAllocationService.ts` — Address pools
- `packages/civ-stack-stream-network/src/services/MulticastAddressManagerImpl.ts` — Implementation
- `packages/civ-stack-stream-network/src/services/AddressAllocationServiceImpl.ts` — Implementation

**Contract segments (payment/access):**
- `packages/civ-stack-contract-segment/src/interfaces/ContractSegmentValidator.ts` — Validator interface
- `packages/civ-stack-contract-segment/src/validators/PaymentValidator.ts` — Payment segments
- `packages/civ-stack-contract-segment/src/validators/CertValidator.ts` — Certificate segments

**Geo-aware overlay:**
- `packages/civ-stack-overlaynet/src/geo/GeoHashUtils.ts` — GeoHash encoding
- `packages/civ-stack-overlaynet/src/weight/GlowWeightUtils.ts` — Weight-based routing
- `packages/civ-stack-overlaynet/src/interfaces/AnycastManager.ts` — Anycast interface
- `packages/civ-stack-overlaynet/src/services/AnycastManagerImpl.ts` — Anycast implementation
- `packages/civ-stack-overlaynet/src/services/geo/GeoHashUtilsImpl.ts` — Geohash implementation
- `packages/civ-stack-overlaynet/src/services/weight/GlowWeightUtilsImpl.ts` — Glowweight routing

**Low-power mesh (IoT/constrained devices):**
- `packages/civ-stack-lowpan-overlay/src/adapters/BLEAdapter.ts` — Bluetooth Low Energy
- `packages/civ-stack-lowpan-overlay/src/adapters/ZigbeeAdapter.ts` — Zigbee
- `packages/civ-stack-lowpan-overlay/src/adapters/ThreadAdapter.ts` — Thread protocol
- `packages/civ-stack-lowpan-overlay/src/adapters/LowPANAdapter.ts` — 6LoWPAN
- `packages/civ-stack-lowpan-overlay/src/manager/LowPowerOverlayManager.ts` — Overlay manager

### Semantos Mapping

| Shomee Concept | Semantos Equivalent |
|---|---|
| SRv6 segment | Contract segment as a LINEAR semantic object (consumed per hop) |
| Multicast address | Type path → multicast group (1:1 mapping) |
| Address allocation | Subnet allocation per community/extension |
| Payment segment | LINEAR payment token in the contract segment chain |
| Cert segment | Facet capability check at each hop |
| GeoHash routing | Geo dimension in taxonomy (future) |
| Glow-weighted routing | Glowweight on source identity → priority in multicast |
| Anycast | Nearest-node resolution for content retrieval |
| Low-power adapters | Edge device support for IoT extensions (energy metering, etc.) |

**Not yet implemented — this is Phase 10+ territory.**

The immediate value is the addressing model: type paths as multicast groups,
contract segments as access/payment conditions. The loom can model this
as object metadata even before the network layer exists.

### Object Types

```
network.segment         — LINEAR  (consumed per hop)
network.multicast-group — RELEVANT (stable address for a type path)
network.payment-segment — LINEAR  (micropayment consumed on delivery)
network.cert-segment    — RELEVANT (capability check, reusable)
```

### Open Questions

- The SRv6 R&D is ambitious. Is the first step just modelling type paths as
  multicast addresses and leaving actual network delivery to a future phase?
- Contract segments could be validated in the cell engine directly — the Zig WASM
  engine already has CHECKSIG. Payment validation is a script evaluation.
- The low-power mesh adapters (BLE, Zigbee, Thread) point toward an IoT extension
  where sensor data flows as LINEAR objects through the mesh. Worth noting but
  not near-term.

---

## Domain 5: Chat as Semantic Shell

### Concept

Everything launches from a conversation. You talk to the system (or to an
object). The intent classifier figures out what you're doing. It routes to the
right container/flow. The action creates or modifies a semantic object. The
conversation is the universal interface — objects, governance, publication,
and navigation all happen through it.

### Shomee R&D

**Semantic shell:**
- `packages/civ-stack-chat/src/runtime/SemanticShell.ts` — OS shell for natural language
- `packages/civ-stack-chat/src/runtime/ChatRuntime.ts` — Chat execution engine

**Intent classification & routing:**
- `packages/civ-stack-chat/src/services/IntentClassifierService.ts` — Semantic intent routing
- `packages/civ-stack-chat/src/services/ContainerFactory.ts` — Container instantiation by intent
- `packages/civ-stack-chat/src/services/ChatMessageRouterService.ts` — Message routing
- `packages/civ-stack-chat/src/services/ChatContextProviderService.ts` — Context provision
- `packages/civ-stack-chat/src/services/ChatSessionService.ts` — Session lifecycle

**Semantic containers (intent handlers):**
- `packages/civ-stack-chat/src/containers/SemanticContainer.ts` — Base container
- `packages/civ-stack-chat/src/containers/ListingContainer.ts` — Listing creation
- `packages/civ-stack-chat/src/containers/PaymentContainer.ts` — Payment intent
- `packages/civ-stack-chat/src/containers/ChatContainer.ts` — Conversation

**Chat flows:**
- `packages/civ-stack-chat/src/flows/ChatFlowRegistry.ts` — Flow registry
- `packages/civ-stack-chat/src/flows/BaseChatFlow.ts` — Base class
- `packages/civ-stack-chat/src/flows/ConversationalChatFlow.ts` — Multi-turn conversation
- `packages/civ-stack-chat/src/flows/QuestionAnsweringChatFlow.ts` — QA flow
- `packages/civ-stack-chat/src/flows/TaskCompletionChatFlow.ts` — Task completion

**Chat overlay (command shell):**
- `packages/civ-stack-chat-overlay/src/interfaces/ChatOverlayService.ts` — Overlay interface
- `packages/civ-stack-chat-overlay/src/interfaces/CommandParser.ts` — Command parsing
- `packages/civ-stack-chat-overlay/src/interfaces/FlowController.ts` — Flow control
- `packages/civ-stack-chat-overlay-client/src/services/ChatOverlayServiceImpl.ts` — Implementation
- `packages/civ-stack-chat-overlay-client/src/services/CommandParserImpl.ts` — Parser implementation
- `packages/civ-stack-chat-overlay-client/src/services/FlowControllerImpl.ts` — Controller implementation

**Specialised flows:**
- `packages/civ-stack-chat-overlay-client/src/flows/CallFlow.ts` — Call intent
- `packages/civ-stack-chat-overlay-client/src/flows/PostFlow.ts` — Post/publish intent
- `packages/civ-stack-chat-overlay-client/src/flows/StakeFlow.ts` — Staking intent

### Semantos Mapping

| Shomee Concept | Semantos Equivalent |
|---|---|
| SemanticShell | CommandBar + ConversationPanel in loom |
| IntentClassifier | LLM classification via OpenRouter (future) |
| ContainerFactory | Extension config scripts — each script is a container type |
| ChatFlowRegistry | Script registry in extension config |
| ConversationalChatFlow | ConversationPanel on AFFINE objects |
| TaskCompletionChatFlow | ConversationPanel → patch sequence → state transition |
| ListingContainer | "Create listing" intent → createObjectFromType + publish flow |
| PaymentContainer | Stake/tip action → LINEAR token creation |
| ChatOverlay | CommandBar overlay for system-level commands |
| CommandParser | Intent classification from free-text input |
| PostFlow | Publish action on ConversationPanel |
| StakeFlow | Stake action on ConversationPanel |

**Already implemented (Phase 8.5):**
- ConversationPanel on action-type cards
- Messages stored as patches with facet provenance
- CommandBar in canvas for system commands

**Still needed:**
- Intent classification (LLM integration via OpenRouter)
- Flow routing from intent to container/action
- Specialised flows: publish, stake, challenge, tip
- Chat context provision (object state + identity + type path)

### Object Types

```
shell.session           — LINEAR  (one session, consumed on end)
shell.intent            — LINEAR  (classified once, routed once)
shell.flow              — AFFINE  (accumulates steps until complete)
```

### Open Questions

- The SemanticShell concept maps to either the CommandBar (system commands) or
  the ConversationPanel (object interaction). Should they merge into one
  universal input surface, or stay separate?
- Intent classification requires an LLM. The OpenRouter integration (parked for
  after Phase 8.5) becomes the enabling layer for this. Without it, conversations
  are just text patches. With it, conversations become classified intents that
  trigger actions.

---

## Governance (Cross-Cutting)

Governance isn't a domain — it's the mechanism that operates across all five.
When two identities disagree about an object's classification, that's a dispute.
When a community decides its moderation policy, that's a ballot. When content is
staked, that's a stake. When bad actors are penalised, glowweight adjusts.

### Shomee R&D

**Dispute engine:**
- `packages/civ-stack-governance-client/src/types/dispute.ts` — Dispute, evidence, resolution types
- `packages/civ-stack-governance-client/src/interfaces/DisputeEngine.ts` — Engine interface
- `packages/civ-stack-governance/src/services/DisputeEngineService.ts` — Implementation

**Stake coordinator:**
- `packages/civ-stack-governance-client/src/types/stake.ts` — Stake, distribution types
- `packages/civ-stack-governance-client/src/interfaces/StakeCoordinator.ts` — Coordinator interface
- `packages/civ-stack-governance/src/services/StakeCoordinatorService.ts` — Implementation

**Certificate ballot:**
- `packages/civ-stack-governance-client/src/types/ballot.ts` — Ballot, vote, result types
- `packages/civ-stack-governance-client/src/interfaces/CertBallotService.ts` — Service interface
- `packages/civ-stack-governance/src/services/CertBallotServiceImpl.ts` — Implementation

**Tribunal router:**
- `packages/civ-stack-governance-client/src/types/tribunal.ts` — Tribunal definition and rules
- `packages/civ-stack-governance-client/src/interfaces/TribunalRouter.ts` — Router interface
- `packages/civ-stack-governance/src/services/TribunalRouterService.ts` — Implementation

**Challenge FSM:**
- `packages/civ-stack-governance/src/governance/fsm/CertChallengeFSM.ts` — State machine

**Realm system:**
- `packages/civ-stack-governance/src/realms/` — GlobalRealm, UKOARealm, CustomRealm

### Semantos Mapping

| Shomee Concept | Semantos Equivalent |
|---|---|
| Dispute | AFFINE object (accumulates evidence → resolved) |
| Stake | LINEAR object (consumed on resolution — forfeit or return) |
| Ballot | AFFINE → RELEVANT (mutable while voting, frozen when finalized) |
| Glowweight | RELEVANT object on identity (always visible reputation) |
| Tribunal | RELEVANT policy object at a type path coordinate |
| Realm | Extension config — each extension defines its own governance rules |
| CertChallengeFSM | Commerce phase transitions on dispute objects |
| DisputeFlow states | Commerce phases: SOURCE→PARSE→TYPECHECK→ACTION→OUTCOME |

### Object Types

```
governance.dispute      — AFFINE  (accumulates evidence, resolves to RELEVANT)
governance.stake        — LINEAR  (consumed exactly once on resolution)
governance.ballot       — AFFINE  (accumulates votes → RELEVANT when finalized)
governance.tribunal     — RELEVANT (policy object, immutable once registered)
governance.resolution   — RELEVANT (frozen decision with reasoning)
```

---

## Unified UI Architecture

The five domains converge on three UI surfaces that are really one thing:

### 1. Identity Bar (top/status)
**Who you are.** Active facet selector, glowweight score, stake balance,
notification count. Switching facets changes what you can see and do everywhere
else. This already exists as FacetSelector in the StatusBar.

### 2. Type Space Navigator (left sidebar)
**What you're looking at.** Taxonomy browser, filtered by your facet's
capabilities. Governance tribunals visible at their type path coordinates.
Community subnets as top-level taxonomy dimensions. Object tree grouped by
archetype. This already exists as TaxonomyBrowser + ObjectTree + TypeList.

### 3. Conversation Canvas (centre)
**What you're doing.** Objects as cards. Every card has a conversation panel.
Conversations drive everything: creation, editing, publication, staking,
challenging, tipping. The conversation panel replaces form fields for most
interactions. Intent classification (when LLM is available) routes messages
to the right action. This already exists as Canvas + LoomCard +
ConversationPanel.

The inspector (right) shows the evidence chain, cell header, and hex view —
the audit trail of everything that happened through conversations.

### What's Missing for the Full Picture

1. **LLM integration** (OpenRouter) — enables intent classification, turns
   conversations from text patches into routed actions
2. **Governance actions** — dispute, stake, ballot, challenge as conversation
   flows on the ConversationPanel
3. **Publication flow** — visibility transitions (draft → published → revoked)
   triggered from conversation
4. **Glowweight display** — reputation score on the identity bar, visible on
   other users' objects
5. **Stake mechanics** — LINEAR token creation/consumption in the loom,
   even before on-chain settlement

---

## Suggested Phase Sequencing

| Phase | Focus | Enables |
|---|---|---|
| 8.5 (done) | Identity plane, facets, conversations, capability scoping | "Who you are" |
| 9 | Publication + governance: visibility states, disputes, stakes, ballots | "What you can do to objects" |
| 9.5 | LLM integration: intent classification, semantic shell flows | "Talk to objects instead of filling forms" |
| 10 | Taxonomy governance: staked proposals, challenges, glowweight | "Community-driven type space" |
| 11 | Network layer: multicast addressing, contract segments | "Content finds you" |
| 12 | Social extension: the full attention economy inversion | "Everything composes" |

Each phase builds on the previous. Each phase is testable with the existing
loom. Each phase adds governance depth to the same three UI surfaces.

---

## The Thesis

Shomee had 93 packages because it modelled each concept as a separate service
with its own database tables, Redis queues, and API endpoints. Semantos has
one kernel because every concept is the same thing: a semantic object with a
256-byte header, linearity rules, capability flags, and an evidence chain.

A dispute is an AFFINE object that accumulates evidence patches.
A stake is a LINEAR object consumed on resolution.
A ballot is an AFFINE object that transitions to RELEVANT when finalized.
A reputation score is a RELEVANT object on an identity.
A tribunal is a RELEVANT policy object at a type path coordinate.

93 packages collapse to ~20 object types on one engine.

That's the reference implementation.
