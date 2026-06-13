---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/PLEXUS-SEMANTOS-INTEGRATION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.724633+00:00
---

# Plexus SDK + Semantic-Seed Salvage: Integration Map & Grafting Plan

> Plexus is going to be the production identity, derivation, and graph
> infrastructure. The loom consumes it — it does not reimplement it.
> Semantic-seed has 6-12 months of R&D on governance, FSM, and economic
> logic that Plexus doesn't cover. This document maps what Plexus provides,
> what semantic-seed contributes, where they overlap (discard the overlap),
> and how to graft the survivors into the loom without locking to
> anything dumb.
>
> **Companion documents:**
> - `SHOMEE-TO-SEMANTOS-MAPPING.md` — conceptual domain mapping (5 domains)
> - `Plexus Technical Requirements Draft v1.3` — Dusk Inc spec (20 components)
> - `plexus-graph-visualiser.html` — interactive graph builder (7 node types, 7 edge types)

---

## Architecture: What Owns What

Three layers. The boundary is non-negotiable.

```
+------------------------------------------------------------------+
|  WORKBENCH (semantos-core)                                       |
|  - Semantic objects, extension configs, flows, governance          |
|  - UI: canvas, conversation, taxonomy, reputation                |
|  - Consumes Plexus via adapter interface                         |
+------------------------------------------------------------------+
        |  PlexusAdapter (interface)          |
        |  - deriveKey()                     |
        |  - createEdge()                    |
        |  - resolveIdentity()               |
        |  - issueCapability()               |
        v                                    v
+----------------------------+  +----------------------------+
|  PLEXUS SDK (production)   |  |  STUB ADAPTER (dev/test)   |
|  - Vendor SDK (graph DAG)  |  |  - In-memory graph         |
|  - Core Library (crypto)   |  |  - Deterministic keys      |
|  - Network SDK (transport) |  |  - No wallet required      |
|  - Contracts (types)       |  |                            |
+----------------------------+  +----------------------------+
```

**Rule: The loom NEVER imports plexus-core or plexus-vendor-sdk directly.**
It imports a `PlexusAdapter` interface. In production, this is backed by the real
SDK. In dev/test, it's backed by an in-memory stub. This means:

- We can develop the entire loom without a running Plexus instance
- We can swap Plexus versions without touching loom code
- We never lock to Plexus internal types — only to our own adapter contract

---

## Plexus Components → Loom Mapping

The Plexus spec defines 20 components. Here's what each one means for us.

### Tier 1: Direct Dependencies (we will consume these)

| Plexus Component | What It Does | Loom Touchpoint | Adapter Method |
|---|---|---|---|
| **Core Library** | Pure TS functions: BRC-42 derivation, BRC-52 cert issuance, graph ops, ECDH | Identity derivation, facet key paths, shared secrets | `deriveKey()`, `issueCertificate()`, `deriveSharedSecret()` |
| **Contracts Library** | Types, interfaces, enums, Zod schemas (no logic) | Type imports for BRC-100 headers, domain flags, tenant types | Direct import — these ARE the shared types |
| **Vendor SDK** | Client-side DAG management, graph DB (Postgres/SQLite), edge creation | Graph structure beneath identity objects | `createNode()`, `createEdge()`, `transferNode()`, `querySubtree()` |
| **Network SDK** | BRC-100 signed HTTP transport | Authenticated API calls to Plexus Control Plane | `sendAuthenticated()`, `initiateHandshake()` |

### Tier 2: Infrastructure We Interact With (via SDK, not directly)

| Plexus Component | What It Does | Loom Relationship |
|---|---|---|
| **Plexus API** | Go service, BRC-100 middleware, all domain coordination | We never call this directly — Vendor/Network SDK wraps it |
| **Verifier Sidecar** | BRC-100 auth, BRC-52 cert validation, SPV checks | Transparent to us — sits in front of the API |
| **Capability Domain** | UTXO-based capability tokens (BRC-108), mint/spend | We present capabilities; it validates them. Adapter: `presentCapability()` |
| **Identity Domain** | BRC-52 cert lifecycle, challenge sets, OTP, key registration | We trigger registration/recovery flows. Adapter: `registerIdentity()`, `initiateRecovery()` |
| **Derivation Domain** | Key derivation metadata storage (recipes, not keys) | Transparent — Vendor SDK handles this internally |
| **Recovery Service** | Disaster recovery, attestation authority | We trigger recovery. Adapter: `requestRecoveryExport()` |

### Tier 3: Domain Logic We Don't Touch Yet

| Plexus Component | What It Does | When We Care |
|---|---|---|
| **Edge Domain** | ECDH peer-to-peer connections, edge recovery policies | When loom objects need encrypted channels between identities |
| **Transfer Domain** | Chain-of-custody, path migration in the DAG | When objects transfer ownership (sale, handoff, delegation) |
| **Metering Service** | MFP payment channels, 2-of-2 multisig, off-chain settlement | When CashLanes metered flow integrates with loom |
| **CLI** | Command-line graph management | DevOps tooling, not loom concern |

### Tier 4: Data Models (inform our types, don't import)

| Plexus Record | What It Defines | Loom Equivalent |
|---|---|---|
| **Identity Record** | cert_id, subject (pubkey), certifier, revocationOutpoint, challenge_set_id | `IdentityStore.rootIdentity` — we model this as a semantic object, Plexus stores the crypto anchor |
| **Tenant Node** | cert_id, resource_id, parent_cert_id, child_index, derivation_path, anchor_txid | No direct equivalent — this IS the DAG. We query it via adapter, never store it |
| **Tenant Metadata** | KV attributes on nodes (display labels, device types, geo) | `LoomObject.payload` — our metadata is richer (typed, versioned, evidence-chained) |
| **Edge Record** | cert_id, resource_id, counterparty_cert, signing_key_index | `CardConnection` in loom — we'll need to enrich this with edge type + Plexus edge_id |
| **Challenge Set** | set_id, user, question_number, answer_hash, hint | Recovery flow in IdentityStore — we trigger the flow, Plexus manages the data |
| **Authority Keys** | key_id, public_key, private_key_encrypted, key_type | Never touches loom — infrastructure keys for Plexus Control Plane |
| **Verification Code** | OTP records for registration/recovery | Never touches loom — handled by Identity Domain |

---

## Semantic-Seed Salvage: What Plexus Replaces vs What Survives

### DISCARDED (Plexus does this better, in production)

| Semantic-Seed Module | Why Discard | Plexus Replacement |
|---|---|---|
| `src/brc42/` | Full BRC-42 ECDH implementation | Plexus Core Library does this natively with algorithm versioning and backward compat |
| `src/certgraph/` | Certificate graph + permission resolver | Plexus Vendor SDK + Edge Domain — production DAG with SPV verification |
| `src/identity/` | GIP identity service | Plexus Identity Domain — BRC-52 certs, challenge sets, recovery |
| `src/crypto/` | Hash functions, signing | Plexus Core Library delegates to BSV SDK |
| `src/containers/` | Bitcoin transaction containers | CashLanes handles this (separate concern from loom) |
| `src/beef/` | BEEF/BUMP parser | CashLanes / Plexus Verifier Sidecar |
| `src/wallet/` | Wallet orchestration | Plexus Vendor SDK + MetanetWalletClient |

### SALVAGED (Plexus doesn't cover this — graft into loom)

| Semantic-Seed Module | What to Extract | Maps to Loom Core | Graft Target |
|---|---|---|---|
| `src/governance/GovernanceModel.ts` | Proposal lifecycle (draft→voting→approved→implemented), constitutional law enforcement | Governance (core 3) | Reference for Phase 9.5 governance types (already partially done) |
| `src/governance/VotingSystem.ts` | Certificate-weighted voting, quorum rules | Governance (core 3) | Ballot flow execution logic |
| `src/governance/SemanticConstitution.ts` | Constitutional laws, reflexive governance | Governance (core 3) | Novel — constitution as a RELEVANT policy object |
| `src/fsm/FSMEvaluationEngine.ts` | Certificate-gated transitions, constraint guards (time/value/spatial/relationship/contextual) | Intent/Flow (core 5) | Enrich FlowRunner step guards beyond simple boolean |
| `src/fsm/FSMTypes.ts` | Constraint type definitions | Intent/Flow (core 5) | Type definitions for flow step guards |
| `src/factories/UniversalSemanticFactory.ts` | Async create() with certificate validation, dependency graph | Semantic Objects (core 1) | Pattern for objectFactory.ts — add cert validation to creation |
| `src/execution/PatchLogEngine.ts` | Mutation audit trail with witness proofs | Semantic Objects (core 1) | Enrich EvidenceChain in inspector |
| `src/economic/EconomicGovernanceModel.ts` | Stake-weighted voting, creator economy | Governance (core 3) | Economic dimension of Ballot/Stake types |
| `src/realms/` | Multi-realm governance with different constitutions | Extension Configs (core 4) | Each extension IS a realm — governance rules per extension |
| `src/hypervisor/` | System introspection, resource quotas, audit | Loom meta | DevTools inspector, not user-facing |

### STUDY ONLY (good patterns, don't copy code)

| Module | Pattern Worth Noting |
|---|---|
| `src/metatype/` | Rust-like trait system for composable capabilities — interesting but orthogonal |
| `src/language/` | AST semantic function analysis — incomplete NLP, superseded by OpenRouter LLM integration |
| `src/topology/` | Graph algorithms — Plexus Vendor SDK handles graph topology natively |
| `src/temporal/` | Time vector synchronization — premature until real multi-node deployment |

---

## The PlexusAdapter Interface

This is the non-locking boundary. The loom codes to this interface.
The real implementation wraps the Plexus SDK. The stub fakes it for dev.

```typescript
/**
 * PlexusAdapter — the loom's only touchpoint to the identity/graph layer.
 *
 * Rule: NO Plexus-internal types cross this boundary.
 * Everything is expressed in loom-native types (string keys,
 * hex hashes, capability numbers). The adapter translates.
 */
interface PlexusAdapter {
  // === Identity ===

  /** Register a new root identity. Returns cert_id (32-byte hex). */
  registerIdentity(email: string): Promise<{ certId: string; publicKey: string }>;

  /** Derive a child node under a parent context. Returns derived public key + cert_id. */
  deriveChild(parentCertId: string, resourceId: string, domainFlag: number): Promise<{
    certId: string;
    publicKey: string;
    childIndex: number;
    derivationPath: string;
  }>;

  /** Resolve a cert_id to its current state (active, revoked, etc). */
  resolveIdentity(certId: string): Promise<{
    certId: string;
    publicKey: string;
    isRevoked: boolean;
    parentCertId: string | null;
    metadata: Record<string, string>;
  }>;

  // === Graph (DAG) ===

  /** Create a structural edge between two nodes. */
  createEdge(params: {
    sourceCertId: string;
    targetCertId: string;
    edgeType: string;         // ROLE_ASSIGNMENT | AUTHORITY | DATA_ACCESS | MESSAGING | TRANSFER | ATTESTATION | CUSTOM
    recoveryPolicy: string;   // NONE | BACKUP_ON_CREATE | BACKUP_ON_CONFIRM | PARENT_MANAGED
    metadata?: Record<string, string>;
  }): Promise<{ edgeId: string; sharedSecret?: string }>;

  /** Query the subtree beneath a node. */
  querySubtree(certId: string, depth?: number): Promise<Array<{
    certId: string;
    resourceId: string;
    parentCertId: string;
    childIndex: number;
    nodeType: string;
    metadata: Record<string, string>;
  }>>;

  // === Capabilities ===

  /** Present a capability UTXO for verification. */
  presentCapability(certId: string, capabilityFlag: number): Promise<{
    valid: boolean;
    expiresAt?: string;
  }>;

  /** Request a new capability token be minted (requires authority). */
  mintCapability(targetCertId: string, capabilityFlag: number, ttlSeconds?: number): Promise<{
    utxoRef: string;
  }>;

  // === Key Derivation (BRC-42) ===

  /** Derive a shared secret between two identities via ECDH. */
  deriveSharedSecret(localCertId: string, remoteCertId: string, context: string): Promise<{
    sharedSecretHash: string;  // We never see the actual secret — only its hash
  }>;

  /** Derive a key for a specific functional domain. */
  deriveDomainKey(certId: string, domainFlag: number, rotationIndex: number): Promise<{
    publicKey: string;
    derivationPath: string;
  }>;

  // === Recovery ===

  /** Initiate disaster recovery flow. */
  initiateRecovery(email: string): Promise<{ sessionId: string; challengeCount: number }>;

  /** Submit challenge answers for recovery. */
  submitChallengeAnswers(sessionId: string, answers: Array<{ questionNumber: number; answer: string }>): Promise<{
    verified: boolean;
    exportPayload?: string;  // Signed JSON metadata for client-side key reconstruction
  }>;

  // === Transport (BRC-100) ===

  /** Send an authenticated request to the Plexus Control Plane. */
  sendAuthenticated(endpoint: string, payload: unknown): Promise<unknown>;
}
```

### Stub Adapter for Dev/Test

```typescript
class StubPlexusAdapter implements PlexusAdapter {
  private nodes = new Map<string, StubNode>();
  private edges = new Map<string, StubEdge>();
  private counter = 0;

  async registerIdentity(email: string) {
    const certId = sha256(`stub:${email}:${Date.now()}`);
    const publicKey = sha256(`pubkey:${certId}`);
    this.nodes.set(certId, { certId, publicKey, email, children: [], parentCertId: null });
    return { certId, publicKey };
  }

  async deriveChild(parentCertId: string, resourceId: string, domainFlag: number) {
    const parent = this.nodes.get(parentCertId);
    if (!parent) throw new Error(`Unknown parent: ${parentCertId}`);
    const childIndex = parent.children.length;
    const derivationPath = `m/${domainFlag}'/${childIndex}'`;
    const certId = sha256(`${parentCertId}:${resourceId}:${domainFlag}:${childIndex}`);
    const publicKey = sha256(`pubkey:${certId}`);
    parent.children.push(certId);
    this.nodes.set(certId, { certId, publicKey, resourceId, parentCertId, children: [] });
    return { certId, publicKey, childIndex, derivationPath };
  }

  // ... remainder follows same pattern: deterministic, in-memory, no wallet
}
```

---

## Plexus Domain Flags → Loom Capabilities

Plexus reserves functional domain flag namespaces. We must respect this.

```
0x00000001 – 0x0000FFFF    Plexus standard/extended flags
0x00010000 – 0xFFFFFFFF    Client-defined (us)
```

### Plexus Standard Flags (from spec)

| Flag | Domain | Plexus Usage |
|---|---|---|
| 0x01 | EDGE_CREATION | Derive keys for ECDH shared secrets |
| 0x05 | ATTESTATION | Sign continuity/ancestry proofs |
| 0x0A | METERING | Payment channel funding/settlement |

### Loom Capability Mapping

The loom currently uses capabilities 1-10 as abstract numbers.
When Plexus goes live, these must map to the domain flag space.

| Loom Capability | Current Number | Plexus Domain Flag | Notes |
|---|---|---|---|
| View/Read | 1 | 0x00010001 | Client-defined — basic read access |
| Create | 2 | 0x00010002 | Client-defined — create objects |
| Edit/Patch | 3 | 0x00010003 | Client-defined — apply patches |
| Delete/Revoke | 4 | 0x00010004 | Client-defined — revoke/discard |
| Publish | 5 | 0x00010005 | Client-defined — visibility transition |
| Govern (Vote) | 6 | 0x00010006 | Client-defined — cast ballots |
| Govern (Propose) | 7 | 0x00010007 | Client-defined — create proposals |
| Stake | 8 | 0x00010008 | Client-defined — lock value |
| Transfer | 9 | 0x00010009 | Maps to Plexus Transfer Domain |
| Admin | 10 | 0x0001000A | Client-defined — full authority |

**Migration path**: The adapter translates capability numbers to domain flags.
The loom never knows about the flag encoding. When we go live, the
mapping table lives in the adapter, not the loom.

---

## Plexus Node Types → Loom Archetypes

The plexus-graph-visualiser defines 7 node types. The loom has archetypes
in extension configs (identity, resource, action, instrument, etc). Here's how
they map — and crucially, why the loom archetypes are RICHER.

| Plexus Node Type | What It Models | Loom Archetype | Difference |
|---|---|---|---|
| PLATFORM | Root tenant (the org itself) | identity (root) | Loom adds: linearity, typeHash, evidence chain |
| ORGANIZATION | Sub-tenant, department | identity (org facet) | Loom adds: facet capabilities, selective disclosure |
| SUB_ORG | Nested organizational unit | identity (sub-facet) | Same as ORGANIZATION, deeper nesting |
| INDIVIDUAL | Person / user | identity (person facet) | Loom adds: GIP traits, glowweight |
| DEVICE | Hardware endpoint | resource | Loom adds: linearity (devices are LINEAR — one owner at a time) |
| ZONE | Logical grouping / department | — (no direct map) | Zones are a Plexus graph concept; loom uses extension configs for grouping |
| OBJECT | Data asset, certificate, token | Semantic Object | **This is the big one.** Plexus OBJECT nodes are generic containers. Loom semantic objects are typed, linear, commerce-phased, evidence-chained. |

**Key insight**: Plexus models the *structural graph* (who relates to whom).
The loom models the *semantic layer* (what things mean, how they behave,
who can do what to them). They are complementary, not competing.

When both are live:
- Plexus stores the cryptographic identity graph (cert_id, derivation paths, edges)
- The loom stores the semantic object graph (typed objects, evidence chains, flows)
- The PlexusAdapter bridges them: `certId ↔ ownerId` on the cell header

---

## Plexus Edge Types → Loom Connections

| Plexus Edge Type | Semantics | Loom Connection Type | Recovery Policy |
|---|---|---|---|
| ROLE_ASSIGNMENT | Parent grants role to child | `connection.authority` — org assigns capability to person | PARENT_MANAGED |
| AUTHORITY | Hierarchical authority chain | `connection.delegation` — capability delegation | BACKUP_ON_CREATE |
| DATA_ACCESS | Permissioned data sharing | `connection.access` — read/write grant between identities | BACKUP_ON_CONFIRM |
| MESSAGING | Encrypted communication channel | `connection.channel` — ECDH-secured message channel | BACKUP_ON_CREATE |
| TRANSFER | Ownership transfer of an object | `connection.transfer` — chain-of-custody record | BACKUP_ON_CREATE |
| ATTESTATION | Third-party proof/verification | `connection.attestation` — signed proof of fact | NONE (ephemeral) |
| CUSTOM | Client-defined relationship | `connection.custom` — extension-specific relationship | Configurable |

---

## PRD Sequencing: Where Plexus Enters the Phase Plan

The existing phase plan (through Phase 12) was designed without Plexus as a
hard dependency. Plexus integration should be a *parallel track* that grafts
onto the existing phases, not a rewrite.

### Current Phase State

| Phase | Status | What It Delivered |
|---|---|---|
| 8/8.5 | Done | Loom shell, identity plane, facets, conversations |
| 9 | Done | Service extraction, LLM intent classification, flow routing |
| 9.5 | Done | Visibility states, publish/revoke, governance types |
| 10 | Prompt ready | Three-axis taxonomy, reputation, taxonomy governance |
| 11 | Prompt ready | Formal verification, TLA+ protocol spec |
| 12 | Prompt ready | Implementation bridge (cell engine ↔ loom) |

### New Phases: Plexus Integration Track

These phases run AFTER Phase 10 (or in parallel where noted). They assume
the Plexus Vendor SDK and Contracts Library are available as npm packages.

---

### Phase 13: PlexusAdapter + Stub — The Non-Locking Boundary

**Goal**: Define the adapter interface. Implement the stub. Wire it into the
loom service layer. Every identity operation goes through the adapter.

**Deliverables**:

- **D13.1**: `PlexusAdapter` interface (as defined above) in `packages/loom/src/plexus/types.ts`
- **D13.2**: `StubPlexusAdapter` in `packages/loom/src/plexus/stub.ts` — in-memory DAG, deterministic keys, no wallet
- **D13.3**: `PlexusService` (renderer-agnostic service, follows Phase 9 pattern) wrapping the adapter with `useSyncExternalStore`-compatible state
- **D13.4**: Wire `IdentityStore` to delegate cert operations to `PlexusService` — register identity, derive facet keys, resolve certs
- **D13.5**: Wire `LoomStore.createObject()` to stamp `certId` from `PlexusService.deriveChild()` onto the cell header `ownerId` field

**Gate tests**:
- Stub adapter passes: identity registration, child derivation (3 levels deep), edge creation, subtree query
- `IdentityStore` creates real facets via adapter (not hardcoded IDs)
- Object creation stamps a deterministic certId as ownerId
- Switching from stub to a mock "real" adapter requires zero loom code changes

**Anti-lock rules**:
- No `@plexus/*` imports in any file outside `packages/loom/src/plexus/`
- PlexusAdapter interface uses only primitive types (string, number, boolean, Record)
- No Plexus-specific error types cross the adapter boundary

---

### Phase 14: Production Plexus SDK Integration

**Goal**: Replace the stub with the real Plexus Vendor SDK + Network SDK.
Real BRC-42 derivation. Real BRC-52 certificates. Real DAG persistence.

**Prerequisites**: Plexus Vendor SDK available as `@plexus/vendor-sdk`, Plexus
Contracts Library available as `@plexus/contracts`.

**Deliverables**:

- **D14.1**: `RealPlexusAdapter` in `packages/loom/src/plexus/real.ts` wrapping `@plexus/vendor-sdk`
- **D14.2**: `@plexus/contracts` types imported ONLY in the adapter implementation — never in loom core
- **D14.3**: Configuration: `plexus.config.ts` with environment switching (stub/local/cloud)
- **D14.4**: BRC-100 transport wired through `@plexus/network-sdk` — all adapter calls authenticated
- **D14.5**: Graph persistence: adapter delegates to Vendor SDK's SQLite/Postgres graph store
- **D14.6**: Identity registration flow: email → OTP → challenge set → cert issuance (full Plexus Identity Domain flow via adapter)
- **D14.7**: Facet derivation: each facet creation derives a child node in the Plexus DAG with the appropriate domain flag

**Gate tests**:
- Real adapter passes same gate tests as stub (interface compliance)
- Identity registration produces a real BRC-52 cert_id
- Derived keys are deterministic: same inputs → same cert_id across runs
- Graph queries return correct subtree structure
- Switching `PLEXUS_MODE=stub` vs `PLEXUS_MODE=real` in env works with no code changes

---

### Phase 15: Edge + Capability Integration

**Goal**: Wire Plexus edges and capability tokens into loom operations.
Object connections become real ECDH-secured edges. Capability checks hit
real UTXO-based tokens.

**Deliverables**:

- **D15.1**: `CardConnection` enriched with Plexus edge metadata (edge_id, edge_type, recovery_policy)
- **D15.2**: Edge creation flow: when two objects are connected on the canvas, adapter creates a Plexus edge with ECDH shared secret
- **D15.3**: Capability validation: every capability-gated operation (publish, govern, stake) calls `adapter.presentCapability()` before execution
- **D15.4**: Capability minting: Admin facets can mint capability tokens for other identities via `adapter.mintCapability()`
- **D15.5**: Domain flag mapping table in adapter config — translates loom capability numbers (1-10) to Plexus uint32 domain flags

**Gate tests**:
- Canvas connection between two identity-owned objects creates a Plexus edge
- Capability check fails gracefully when UTXO is spent/expired
- Capability minting requires Admin capability (10) on the minting facet
- Domain flag translation is bidirectional and lossless

---

### Phase 16: Transfer + Recovery

**Goal**: Chain-of-custody transfers and disaster recovery through Plexus.

**Deliverables**:

- **D16.1**: Transfer flow: object ownership change triggers Plexus Transfer Domain (path migration in DAG)
- **D16.2**: Recovery flow: full 4-phase Plexus recovery (OTP → challenge → export → reconstruct) accessible from loom identity settings
- **D16.3**: Attestation: identity continuity proofs generated via Plexus Recovery Service's attestation authority
- **D16.4**: Edge recovery: revoked edges preserved with `revoked_at` timestamp, backup recipes retained

---

### Phase 17: Metering Bridge (CashLanes ↔ Plexus ↔ Loom)

**Goal**: Connect the CashLanes metered flow protocol to loom objects
via Plexus metering domain keys.

**Deliverables**:

- **D17.1**: Metering domain key derivation (Flag 0x0A) via adapter
- **D17.2**: Payment channel status surfaced in loom object inspector
- **D17.3**: Metered access capability tokens for paywall/time-lock gating
- **D17.4**: Settlement events reflected as evidence chain patches on metered objects

---

## Grafting Mechanism: How Semantic-Seed Code Enters the Loom

### Principle: Extract Types and Patterns, Not Implementations

We are not copying semantic-seed files into the loom. We are extracting
the *type definitions* and *algorithmic patterns* that Plexus doesn't cover,
then reimplementing them against the loom's existing service architecture.

### Graft 1: FSM Constraint Guards → FlowRunner

**Source**: `semantic-seed/src/fsm/FSMTypes.ts`, `FSMEvaluationEngine.ts`

**What to extract**: The constraint type system.

```typescript
// From semantic-seed — the constraint model is richer than simple booleans
interface FlowStepGuard {
  type: 'value' | 'time' | 'count' | 'capability' | 'relationship' | 'spatial' | 'contextual';
  operator: 'lt' | 'lte' | 'gt' | 'gte' | 'eq' | 'ne' | 'in' | 'between';
  field: string;       // path into the flow's collected data or object state
  value: unknown;      // comparison value
  certGated?: boolean; // requires a valid certificate to evaluate
}
```

**Target**: `FlowRunner.ts` — add guard evaluation to `advanceFlow()`.
Currently flow steps are unconditional. With guards, steps can require:
- Minimum stake value (`type: 'value', field: 'stake.amount', operator: 'gte', value: 1000`)
- Time window (`type: 'time', field: 'ballot.closesAt', operator: 'gt', value: 'now'`)
- Capability check (`type: 'capability', field: 'facet.capabilities', operator: 'in', value: [6, 7]`)

**Phase**: This grafts into Phase 10 (taxonomy governance flows need guarded steps).

### Graft 2: Governance Lifecycle → Extension Config Flows

**Source**: `semantic-seed/src/governance/GovernanceModel.ts`, `VotingSystem.ts`

**What to extract**: The proposal state machine and voting rules.

```
PROPOSAL LIFECYCLE:
  draft → open_for_voting → quorum_reached → approved | rejected → implemented | archived

VOTING RULES:
  - Certificate-weighted (one cert = one vote, or weighted by stake)
  - Quorum threshold (percentage of eligible voters)
  - Time-bounded (voting window opens/closes)
  - Constitutional veto (certain proposals require supermajority)
```

**Target**: `core.json` governance flows — enrich the existing Ballot type's
flow definition with these states and guards.

**Phase**: Already partially done in Phase 9.5 (Dispute, Ballot, Stake, Resolution
types exist). Graft the lifecycle FSM and voting rules into Phase 10's
taxonomy governance flows.

### Graft 3: Constitution as Policy Object

**Source**: `semantic-seed/src/governance/SemanticConstitution.ts`

**What to extract**: The concept of a constitution as a RELEVANT semantic object
that defines the rules governing governance itself.

```typescript
// Constitution is a RELEVANT policy object at a type path coordinate
// It defines: who can propose, voting thresholds, amendment process
interface ConstitutionDef {
  typePath: string;           // e.g., "governance.constitution"
  linearity: 'RELEVANT';     // immutable once ratified
  visibility: 'published';   // always visible
  rules: {
    proposalThreshold: number;   // min stake to propose
    votingQuorum: number;        // percentage needed
    amendmentQuorum: number;     // supermajority for self-modification
    vetoCapabilities: number[];  // capabilities that can veto
  };
}
```

**Target**: New object type in `core.json`. The reflexive governance plane
(voting on rules that govern voting) is the novel contribution.

**Phase**: Phase 10 or Phase 10.5.

### Graft 4: Patch Log Audit Trail → Evidence Chain

**Source**: `semantic-seed/src/execution/PatchLogEngine.ts`

**What to extract**: The witness proof pattern — every mutation carries a
cryptographic witness that can be independently verified.

**Target**: `EvidenceChain` in the inspector already displays patches.
Enrich each patch with a witness hash: `sha256(previousPatchHash || patchContent || facetCertId)`.
This creates a hash chain that proves patch ordering and authorship.

**Phase**: Phase 14 (when real Plexus certs are available for the facetCertId).

### Graft 5: Economic Voting Weights → Ballot Flow

**Source**: `semantic-seed/src/economic/EconomicGovernanceModel.ts`

**What to extract**: Vote weight calculation based on stake, reputation, and
role rather than flat one-identity-one-vote.

**Target**: Ballot flow step evaluation in FlowRunner. When counting votes,
the flow checks each voter's stake (LINEAR tokens committed) and reputation
(RELEVANT glowweight score) to compute weighted totals.

**Phase**: Phase 10 (reputation exists) + Phase 15 (capability tokens exist for stake).

---

## What We Do NOT Graft

| Semantic-Seed Thing | Why Not |
|---|---|
| BRC-42 implementation | Plexus Core Library does this, with algorithm versioning |
| Certificate graph traversal | Plexus Vendor SDK does this, with real persistence |
| BEEF/BUMP parsing | CashLanes concern, not loom |
| Wallet orchestration | Plexus Vendor SDK + MetanetWalletClient |
| SPV verification | Plexus Verifier Sidecar handles this |
| Heraldic identity fields | Cool but cosmetic — add later as metadata on cert objects |
| Trait/metatype system | Orthogonal to the 5 cores, adds complexity without enabling anything |
| Zone-scoped key policies | Plexus DAG with domain flags achieves this natively |
| Hypervisor introspection | DevTools feature, not user-facing — build if needed |

---

## Anti-Lock Checklist

Before any Plexus integration code is merged, verify:

1. **No Plexus imports outside the adapter directory** — `grep -r "@plexus" packages/loom/src/ --include="*.ts" | grep -v "/plexus/"` returns nothing
2. **Adapter interface uses only primitives** — no `PlexusNode`, `PlexusCert`, `BRC52Certificate` in the interface signature
3. **Stub passes all gate tests** — if the stub breaks, the interface is too coupled
4. **Domain flag mapping is configurable** — not hardcoded in loom code
5. **Capability numbers are loom-native** — translation happens in the adapter only
6. **No Plexus error types leak** — adapter catches and translates to loom errors
7. **Recovery flow doesn't depend on Plexus availability** — stub adapter handles recovery with local-only flow
8. **Graph queries are adapter-mediated** — loom never constructs SQL or graph queries directly
9. **Algorithm versioning is adapter's concern** — loom doesn't know about `plexus-kdf-v1` etc.
10. **Edge recovery policies are adapter config** — loom specifies intent ("this is a role assignment"), adapter chooses the policy

---

## Open Questions

1. **Plexus Contracts Library as direct dependency?**
   The Contracts Library is "strictly structural" — types, interfaces, enums, Zod schemas.
   No logic. It could be a direct loom dependency for type checking without
   creating lock-in. But it means our types need to stay compatible with theirs.
   **Recommendation**: Import in the adapter implementation only. Re-export loom-native
   types from the adapter. If Plexus changes a type, only the adapter breaks.

2. **SQLite vs Postgres for Vendor SDK graph store?**
   Plexus supports both. For the loom (single-user desktop app), SQLite is
   simpler. For multi-user deployments, Postgres. The adapter doesn't care — that's
   Vendor SDK configuration.
   **Recommendation**: Default to SQLite for loom. Document Postgres path for
   server deployments.

3. **When does the stub stop being useful?**
   The stub is useful as long as we're developing loom features that don't
   require real crypto. Once we need real BRC-52 certs or real UTXO capabilities,
   we need the real adapter. But the stub should NEVER be removed — it's the
   test harness forever.

4. **CashLanes metering integration (Phase 17) — whose adapter?**
   CashLanes has its own wallet architecture (CLAUDE.md in the cashlanes repo).
   The metering bridge might need a *second* adapter for CashLanes, or the
   PlexusAdapter might grow a metering section.
   **Recommendation**: Separate `MeteringAdapter` interface. Same pattern. Same rules.
   CashLanes and Plexus are independent systems that happen to share BSV.

5. **Plexus's monotonic child_index constraint**
   Plexus enforces that child_index only ever increments (even if a child is deleted,
   its index is never reused). The loom's facet numbering must respect this.
   If a facet is revoked, its capability slot is permanently consumed.
   **Recommendation**: Document this constraint in IdentityStore. When Plexus is live,
   facet creation goes through the adapter which enforces monotonicity automatically.

---

## Summary: The Thesis, Updated

The SHOMEE-TO-SEMANTOS-MAPPING.md said: "93 packages collapse to ~20 object
types on one engine." That's still true.

What Plexus adds: **the cryptographic substrate beneath those objects is no
longer something we build — it's something we consume.**

Plexus owns:
- Identity (BRC-52 certs, challenge recovery, attestation)
- Derivation (key recipes, domain flags, algorithm versioning)
- Graph structure (DAG, edges, ECDH, transfers)
- Capabilities (UTXO tokens, SPV verification)
- Transport (BRC-100 auth, nonce handshakes)

The loom owns:
- Semantic meaning (typed objects, linearity, commerce phases)
- Evidence chains (patches, witness proofs, audit trail)
- Governance (disputes, ballots, stakes, constitutions)
- Taxonomy (three-axis classification, weighted nodes)
- Flows (intent classification, multi-turn execution, guarded steps)
- Reputation (materialized view over identity history)

The adapter is the membrane. Keep it thin. Keep it stable. Keep it ours.
