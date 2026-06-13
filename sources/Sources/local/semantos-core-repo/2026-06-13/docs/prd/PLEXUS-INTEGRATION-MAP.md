---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PLEXUS-INTEGRATION-MAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.686512+00:00
---

# Plexus Integration Map — Architecture Reference

**Version**: 1.0
**Date**: March 2026
**Status**: Reference document for Phases 14–18
**Companion documents**:
- `SHOMEE-TO-SEMANTOS-MAPPING.md` — conceptual domain mapping (5 domains)
- `Plexus Technical Requirements Draft v1.3` — Dusk Inc spec (20 components)
- `plexus-graph-visualiser.html` — interactive graph builder (7 node types, 7 edge types)

---

## Context

Plexus is going to be the production identity, derivation, and graph infrastructure. The loom consumes it — it does not reimplement it. Semantic-seed has 6–12 months of R&D on governance, FSM, and economic logic that Plexus does not cover. This document maps what Plexus provides, what semantic-seed contributes, where they overlap (discard the overlap), and how to graft the survivors into the loom without locking to anything dumb.

### The Thesis

The `SHOMEE-TO-SEMANTOS-MAPPING.md` said: "93 packages collapse to ~20 object types on one engine." That still holds.

What Plexus adds: the cryptographic substrate beneath those objects is no longer something we build — it is something we consume. Plexus owns identity, derivation, graph structure, capabilities, and transport. The loom owns semantic meaning, evidence chains, governance, taxonomy, flows, and reputation. The adapter is the membrane. Keep it thin. Keep it stable. Keep it ours.

The deeper consequence: if identity and governance are first-class, then anything that has identity and state — including payment channels — is just another semantic object. CashLanes channels become LINEAR objects with FSMs expressed as loom flows, governed by the same Ballot/Dispute primitives, audited by the same evidence chains. This makes the loom a universal control plane for metering any resource, not just a consumer of a payment protocol.

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

**Rule**: The loom NEVER imports `plexus-core` or `plexus-vendor-sdk` directly. It imports a `PlexusAdapter` interface. In production, this is backed by the real SDK. In dev/test, it is backed by an in-memory stub. This means:

- We can develop the entire loom without a running Plexus instance
- We can swap Plexus versions without touching loom code
- We never lock to Plexus internal types — only to our own adapter contract

---

## Plexus Components → Loom Mapping

The Plexus spec defines 20 components. Organized by tier of loom concern.

### Tier 1: Direct Dependencies (we will consume these)

| Plexus Component | What It Does | Loom Touchpoint | Adapter Methods |
|---|---|---|---|
| Core Library | Pure TS: BRC-42 derivation, BRC-52 cert issuance, graph ops, ECDH | Identity derivation, facet key paths, shared secrets | `deriveKey()`, `issueCertificate()`, `deriveSharedSecret()` |
| Contracts Library | Types, interfaces, enums, Zod schemas (no logic) | Type imports for BRC-100 headers, domain flags, tenant types | Direct import — these ARE the shared types |
| Vendor SDK | Client-side DAG management, graph DB (Postgres/SQLite), edge creation | Graph structure beneath identity objects | `createNode()`, `createEdge()`, `transferNode()`, `querySubtree()` |
| Network SDK | BRC-100 signed HTTP transport | Authenticated API calls to Plexus Control Plane | `sendAuthenticated()`, `initiateHandshake()` |

### Tier 2: Infrastructure We Interact With (via SDK, not directly)

| Plexus Component | What It Does | Loom Relationship |
|---|---|---|
| Plexus API | Go service, BRC-100 middleware, all domain coordination | Never called directly — Vendor/Network SDK wraps it |
| Verifier Sidecar | BRC-100 auth, BRC-52 cert validation, SPV checks | Transparent — sits in front of the API |
| Capability Domain | UTXO-based capability tokens (BRC-108), mint/spend | We present capabilities; it validates them. Adapter: `presentCapability()` |
| Identity Domain | BRC-52 cert lifecycle, challenge sets, OTP, key registration | We trigger registration/recovery flows. Adapter: `registerIdentity()`, `initiateRecovery()` |
| Derivation Domain | Key derivation metadata storage (recipes, not keys) | Transparent — Vendor SDK handles this internally |
| Recovery Service | Disaster recovery, attestation authority | We trigger recovery. Adapter: `requestRecoveryExport()` |

### Tier 3: Domain Logic We Don't Touch Yet

| Plexus Component | What It Does | When We Care |
|---|---|---|
| Edge Domain | ECDH peer-to-peer connections, edge recovery policies | When loom objects need encrypted channels between identities |
| Transfer Domain | Chain-of-custody, path migration in the DAG | When objects transfer ownership (sale, handoff, delegation) |
| Metering Service | MFP payment channels, 2-of-2 multisig, off-chain settlement | When CashLanes metered flow integrates with loom |
| CLI | Command-line graph management | DevOps tooling, not loom concern |

### Tier 4: Data Models (inform our types, don't import)

| Plexus Record | What It Defines | Loom Equivalent |
|---|---|---|
| Identity Record | cert_id, subject (pubkey), certifier, revocationOutpoint, challenge_set_id | `IdentityStore.rootIdentity` — modeled as semantic object, Plexus stores the crypto anchor |
| Tenant Node | cert_id, resource_id, parent_cert_id, child_index, derivation_path, anchor_txid | No direct equivalent — this IS the DAG. Queried via adapter, never stored |
| Tenant Metadata | KV attributes on nodes (display labels, device types, geo) | `LoomObject.payload` — our metadata is richer (typed, versioned, evidence-chained) |
| Edge Record | cert_id, resource_id, counterparty_cert, signing_key_index | `CardConnection` in loom — enriched with edge type + Plexus edge_id |
| Challenge Set | set_id, user, question_number, answer_hash, hint | Recovery flow in IdentityStore — we trigger the flow, Plexus manages the data |
| Authority Keys | key_id, public_key, private_key_encrypted, key_type | Never touches loom — infrastructure keys for Plexus Control Plane |
| Verification Code | OTP records for registration/recovery | Never touches loom — handled by Identity Domain |

---

## Semantic-Seed Salvage: What Plexus Replaces vs What Survives

### DISCARDED (Plexus does this better, in production)

| Semantic-Seed Module | Why Discard | Plexus Replacement |
|---|---|---|
| `src/brc42/` | Full BRC-42 ECDH implementation | Core Library — native with algorithm versioning and backward compat |
| `src/certgraph/` | Certificate graph + permission resolver | Vendor SDK + Edge Domain — production DAG with SPV verification |
| `src/identity/` | GIP identity service | Identity Domain — BRC-52 certs, challenge sets, recovery |
| `src/crypto/` | Hash functions, signing | Core Library delegates to BSV SDK |
| `src/containers/` | Bitcoin transaction containers | CashLanes handles this (separate concern) |
| `src/beef/` | BEEF/BUMP parser | CashLanes / Verifier Sidecar |
| `src/wallet/` | Wallet orchestration | Vendor SDK + MetanetWalletClient |

### SALVAGED (Plexus doesn't cover this — graft into loom)

| Semantic-Seed Module | What to Extract | Loom Core | Graft Target |
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

This is the non-locking boundary. The loom codes to this interface. The real implementation wraps the Plexus SDK. The stub fakes it for dev.

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

The loom currently uses capabilities 1–10 as abstract numbers. When Plexus goes live, these must map to the domain flag space.

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

**Migration path**: The adapter translates capability numbers to domain flags. The loom never knows about the flag encoding. When we go live, the mapping table lives in the adapter, not the loom.

---

## Plexus Node Types → Loom Archetypes

The plexus-graph-visualiser defines 7 node types. The loom has archetypes in extension configs (identity, resource, action, instrument, etc). Here is how they map — and crucially, why the loom archetypes are RICHER.

| Plexus Node Type | What It Models | Loom Archetype | Difference |
|---|---|---|---|
| PLATFORM | Root tenant (the org itself) | identity (root) | Loom adds: linearity, typeHash, evidence chain |
| ORGANIZATION | Sub-tenant, department | identity (org facet) | Loom adds: facet capabilities, selective disclosure |
| SUB_ORG | Nested organizational unit | identity (sub-facet) | Same as ORGANIZATION, deeper nesting |
| INDIVIDUAL | Person / user | identity (person facet) | Loom adds: GIP traits, glowweight |
| DEVICE | Hardware endpoint | resource | Loom adds: linearity (devices are LINEAR — one owner at a time) |
| ZONE | Logical grouping / department | — (no direct map) | Zones are a Plexus graph concept; loom uses extension configs for grouping |
| OBJECT | Data asset, certificate, token | Semantic Object | The big one. Plexus OBJECT nodes are generic containers. Loom semantic objects are typed, linear, commerce-phased, evidence-chained. |

**Key insight**: Plexus models the structural graph (who relates to whom). The loom models the semantic layer (what things mean, how they behave, who can do what to them). They are complementary, not competing.

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

## Grafting Mechanism: How Semantic-Seed Code Enters the Loom

**Principle**: Extract Types and Patterns, Not Implementations.

We are not copying semantic-seed files into the loom. We are extracting the type definitions and algorithmic patterns that Plexus does not cover, then reimplementing them against the loom's existing service architecture.

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

**Target**: `FlowRunner.ts` — add guard evaluation to `advanceFlow()`. Currently flow steps are unconditional. With guards, steps can require minimum stake value, time windows, capability checks.

**Phase**: Grafts into Phase 10 (taxonomy governance flows need guarded steps).

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

**Target**: `core.json` governance flows — enrich the existing Ballot type's flow definition with these states and guards.

**Phase**: Already partially done in Phase 9.5 (Dispute, Ballot, Stake, Resolution types exist). Graft the lifecycle FSM and voting rules into Phase 10 taxonomy governance flows.

### Graft 3: Constitution as Policy Object

**Source**: `semantic-seed/src/governance/SemanticConstitution.ts`

**What to extract**: The concept of a constitution as a RELEVANT semantic object that defines the rules governing governance itself.

```typescript
// Constitution is a RELEVANT policy object at a type path coordinate
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

**Target**: New object type in `core.json`. The reflexive governance plane (voting on rules that govern voting) is the novel contribution.

**Phase**: Phase 10 or Phase 10.5.

### Graft 4: Patch Log Audit Trail → Evidence Chain

**Source**: `semantic-seed/src/execution/PatchLogEngine.ts`

**What to extract**: The witness proof pattern — every mutation carries a cryptographic witness that can be independently verified.

**Target**: `EvidenceChain` in the inspector. Enrich each patch with a witness hash: `sha256(previousPatchHash || patchContent || facetCertId)`. Creates a hash chain that proves patch ordering and authorship.

**Phase**: Phase 15 (when real Plexus certs are available for the facetCertId).

### Graft 5: Economic Voting Weights → Ballot Flow

**Source**: `semantic-seed/src/economic/EconomicGovernanceModel.ts`

**What to extract**: Vote weight calculation based on stake, reputation, and role rather than flat one-identity-one-vote.

**Target**: Ballot flow step evaluation in FlowRunner. When counting votes, the flow checks each voter's stake (LINEAR tokens committed) and reputation (RELEVANT glowweight score) to compute weighted totals.

**Phase**: Phase 10 (reputation exists) + Phase 16 (capability tokens exist for stake).

### What We Do NOT Graft

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

1. No Plexus imports outside the adapter directory — `grep -r "@plexus" packages/loom/src/ --include="*.ts" | grep -v "/plexus/"` returns nothing
2. Adapter interface uses only primitives — no `PlexusNode`, `PlexusCert`, `BRC52Certificate` in the interface signature
3. Stub passes all gate tests — if the stub breaks, the interface is too coupled
4. Domain flag mapping is configurable — not hardcoded in loom code
5. Capability numbers are loom-native — translation happens in the adapter only
6. No Plexus error types leak — adapter catches and translates to loom errors
7. Recovery flow does not depend on Plexus availability — stub adapter handles recovery with local-only flow
8. Graph queries are adapter-mediated — loom never constructs SQL or graph queries directly
9. Algorithm versioning is adapter's concern — loom does not know about `plexus-kdf-v1` etc.
10. Edge recovery policies are adapter config — loom specifies intent ("this is a role assignment"), adapter chooses the policy

---

## What NOT to Do

1. **Do NOT import `@plexus/*` packages in any file outside `packages/loom/src/plexus/`.** The adapter directory is the containment boundary. One `grep` must prove this.
2. **Do NOT expose Plexus-specific types (`PlexusNode`, `PlexusCert`, `BRC52Certificate`) across the adapter interface.** Only primitives: string, number, boolean, `Record<string, string>`.
3. **Do NOT let Plexus error types leak.** The adapter catches and translates to loom errors.
4. **Do NOT hardcode domain flag mappings in loom code.** Translation happens in the adapter only.
5. **Do NOT remove the stub adapter after the real adapter works.** The stub is the test harness forever.
6. **Do NOT construct SQL or graph queries in loom code.** Graph queries are adapter-mediated.
7. **Do NOT copy semantic-seed files into the loom.** Extract types and patterns, reimplement against the loom service architecture.
8. **Do NOT build identity, derivation, or certificate primitives.** Plexus Core Library does this natively.
9. **Do NOT reimplement graph traversal.** Plexus Vendor SDK handles graph topology natively.
10. **Do NOT assume Plexus availability at dev time.** Every loom feature must work against the stub.

---

## Open Questions

| # | Question | Recommendation | Decision needed by |
|---|----------|---------------|-------------------|
| Q1 | Plexus Contracts Library as direct dependency? Types-only, no logic. Could be direct loom dep for type checking. | Import in adapter implementation only. Re-export loom-native types. If Plexus changes a type, only the adapter breaks. | Phase 15 |
| Q2 | SQLite vs Postgres for Vendor SDK graph store? | Default to SQLite for loom (single-user desktop app). Document Postgres path for server deployments. | Phase 15 |
| Q3 | When does the stub stop being useful? | Never. The stub is the test harness forever. Real crypto needed? Use real adapter. But stub NEVER removed. | Permanent |
| Q4 | CashLanes metering integration — whose adapter? | **RESOLVED**: No separate MeteringAdapter. Channels are semantic objects governed through the same PlexusAdapter + loom object system. CashLanes provides only the Bitcoin settlement rail (multisig, signing, broadcast). The loom IS the metering control plane. See Phase 18. | Resolved |
| Q5 | Plexus monotonic child_index constraint? | Document in IdentityStore. When Plexus is live, facet creation goes through adapter which enforces monotonicity automatically. | Phase 14 |

---

## Phase-Specific PRDs

Individual phase implementations are documented in separate PRD files. Each phase has:

| Phase | Document | Prompt | Summary |
|-------|----------|--------|---------|
| 14 | `PHASE-14-PLEXUS-ADAPTER.md` | `PHASE-14-PROMPT.md` | PlexusAdapter interface + StubAdapter + PlexusService + IdentityStore/LoomStore wiring |
| 15 | `PHASE-15-PLEXUS-REAL-SDK.md` | `PHASE-15-PROMPT.md` | Replace stub with real Plexus Vendor SDK + Network SDK |
| 16 | `PHASE-16-PLEXUS-EDGES.md` | `PHASE-16-PROMPT.md` | Wire edges + capability tokens into loom operations |
| 17 | `PHASE-17-PLEXUS-TRANSFER.md` | `PHASE-17-PROMPT.md` | Chain-of-custody transfers + disaster recovery |
| 18 | `PHASE-18-METERING-CONTROL-PLANE.md` | `PHASE-18-PROMPT.md` | Channels as governed semantic objects — universal metering control plane |

Each phase PRD contains:
- Goal and prerequisites
- Deliverables (D14.1, D14.2, etc.)
- TDD gate tests (T1–T20, etc.)
- Phase completion criteria
- File references

This architecture reference document contains ONLY shared concepts and constraints that all phases must understand. Implementation details belong in individual phase PRDs.
