---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.671846+00:00
---

# Phase 26: Kernel Isolation & Sovereign Node — Master PRD

**Duration**: 6 weeks (with 20% buffer: ~7.5 weeks)
**Prerequisites**: Phase 25A–D complete (StorageAdapter, CellStore, SemanticFS, BsvOverlayAdapter)
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md`
**Branch prefix**: `phase-26-kernel-isolation`

---

## Context

The Semantos kernel currently runs as a monolithic loom application. Storage adapters are clean (Phase 25A–D), but identity, anchoring, and networking are entangled with the loom package. This prevents deploying the kernel as a standalone node — on a VPS, in a Colo facility, or via an infrastructure partner.

Phase 26 isolates the kernel behind four clean adapter interfaces, packages it as a deployable node, and enables the node-as-semantic-object model where a running Semantos instance describes itself as a RELEVANT object manageable via the conversational shell.

The commercial motivation is threefold:

1. **Tradie nodes** — $10/month VPS running kernel + trades vertical, administered via phone app
2. **Enterprise sovereignty nodes** — Colo deployment with provable data residency via BCA addressing + BSV anchoring
3. **Infrastructure partner nodes** — Equinix Metal / inference.ai deployments where the partner provides hardware, Semantos provides the software stack

All three require the kernel to be deployable without the full React loom, configurable via filesystem-loaded vertical grammars, and administrable remotely via the conversational shell.

### Commercial Product Context

The kernel isolation work directly enables the three-product platform described in `PLATFORM-ARCHITECTURE.md`:

1. **OddJobTodd** (trades vertical) — the existing product, currently monolithic, becomes the first vertical grammar loaded by the isolated kernel
2. **Property Management Suite** (property vertical) — standalone PM product with Properties, Leases, Tenants, Inspections, Compliance — becomes a second vertical grammar
3. **Dispatch Envelope / Marketplace** — the cross-vertical sync layer where a PM's MaintenanceRequest becomes a tradie's Job lead via a single semantic object with faceted visibility

The dispatch envelope model — where RELEVANT patches are shared across verticals and AFFINE patches stay private — depends on the kernel having clean adapter interfaces. Without Phase 26, cross-vertical dispatch requires point-to-point integrations. With Phase 26, any vertical can publish objects that any other vertical can subscribe to, with capability tokens controlling who sees what.

The V1→V2→V3 progression in PLATFORM-ARCHITECTURE.md maps directly to adapter swaps:
- **V1** (shared Postgres): `NodeFsAdapter` or Postgres-backed `StorageAdapter`
- **V2** (Supabase Realtime): `NetworkAdapter` with Supabase subscription implementation
- **V3** (overlay network): `BsvOverlayNetworkAdapter` — fully decentralised, no central marketplace

See `docs/prd/PLATFORM-ARCHITECTURE.md` for full product-level architecture.

---

## Architecture: The Four Adapter Interfaces

A Semantos node is defined entirely by four adapter choices plus configuration:

```
┌──────────────────────────────────────────────────────┐
│                 CONVERSATIONAL SHELL                  │
│    (intent classifier, flow runner, chat, BYOK LLM)  │
│              ships WITH kernel, not IN kernel         │
└──────────────────┬───────────────────────────────────┘
                   │
┌──────────────────┴───────────────────────────────────┐
│                    KERNEL CORE                        │
│  cell engine (Zig/WASM) · linearity · capability     │
│  validation · evidence chains · typeHash computation  │
│              THE PROOF BOUNDARY                       │
└──────┬──────────┬──────────┬──────────┬──────────────┘
       │          │          │          │
  StorageAdapter  IdentityAdapter  AnchorAdapter  NetworkAdapter
  (where bytes    (who you are,    (proving things  (how objects
   live)           what you can do)  existed)         move)
```

### Three Boundaries (Do Not Conflate)

| Boundary | What's inside | Changed by |
|----------|---------------|------------|
| **Proof boundary** | Cell engine, linearity, capability tokens, evidence chains | Never (Lean 4 proved) |
| **Package boundary** | Proof boundary + shell + generic taxonomy + adapter interfaces | Kernel releases only |
| **Configuration boundary** | Vertical grammars, prompt scripts, domain flows, object types | Vertical config files |

---

## Sub-Phase Overview

| Phase | Title | Deliverable | Adapter | Effort | Prerequisites |
|-------|-------|-------------|---------|--------|--------------|
| 26A | Identity Extraction | IdentityAdapter in protocol-types | IdentityAdapter | 2–3 days | Phase 25D |
| 26B | Local Identity | Offline capability validation | IdentityAdapter | 1 week | 26A |
| 26C | Anchor Adapter | AnchorAdapter + BsvAnchorAdapter | AnchorAdapter | 1 week | 26A |
| 26D | Network Adapter | NetworkAdapter + overlay composition | NetworkAdapter | 1 week | 26A |
| 26E | Node Bootstrap | NodeConfig + node self-object | All four | 3–4 days | 26B, 26C, 26D |
| 26F | Extension Loading | Filesystem-based extension config | Configuration | 2–3 days | 26E |
| 26H | Extension Rename | Vertical → Extension terminology alignment | Terminology | 1–2 days | 26F |
| 26G | Node Packaging | Docker + install script + admin | Deployment | 1 week | 26H |

```
26A ──→ 26B ──→ 26E ──→ 26F ──→ 26H ──→ 26G
  │              ↑
  ├──→ 26C ──────┤
  │              │
  └──→ 26D ──────┘
```

26B, 26C, 26D can run in parallel after 26A completes. 26H (rename) must complete before 26G (packaging) so the public API uses "extension" from day one.

---

## Adapter Interface Summary

### StorageAdapter (COMPLETE — Phase 25A–D)

```typescript
// protocol-types/src/storage.ts — DONE, reference pattern
interface StorageAdapter {
  read(key: string): Promise<Uint8Array | null>
  write(key: string, data: Uint8Array): Promise<void>
  exists(key: string): Promise<boolean>
  list(prefix: string): Promise<string[]>
  delete(key: string): Promise<boolean>
  stat(key: string): Promise<StorageStat | null>
  watch?(prefix: string, cb: (event: StorageEvent) => void): () => void
}
```

Six implementations: Memory, NodeFs, OPFS, IndexedDB, Overlay, BSV.

### IdentityAdapter (Phase 26A — extraction; 26B — local implementation)

```typescript
// protocol-types/src/identity.ts — TO CREATE
interface IdentityAdapter {
  registerIdentity(email: string): Promise<{ certId: string; publicKey: string }>
  deriveChild(parentCertId: string, resourceId: string, domainFlag: number): Promise<{ certId: string; publicKey: string; childIndex: number }>
  resolveIdentity(certId: string): Promise<IdentityInfo>
  presentCapability(certId: string, domainFlag: number): Promise<{ valid: boolean; reason?: string; token?: Uint8Array }>
  createEdge(initiatorCertId: string, responderCertId: string): Promise<{ edgeId: string; sharedSecret: string }>
  querySubtree(rootCertId: string, depth: number): Promise<CertTree>
  initiateRecovery(email: string): Promise<{ sessionId: string; challengeCount: number }>
  submitChallengeAnswers(sessionId: string, answers: ChallengeAnswer[]): Promise<{ verified: boolean; exportPayload?: string }>
  sendAuthenticated(senderCertId: string, receiverCertId: string, payload: Record<string, string>): Promise<{ messageId: string }>
}
```

Currently exists as PlexusAdapter in loom/src/plexus/types.ts — needs extraction to protocol-types.

### AnchorAdapter (Phase 26C — new interface)

```typescript
// protocol-types/src/anchor.ts — TO CREATE
interface AnchorAdapter {
  anchor(stateHash: string, metadata?: AnchorMetadata): Promise<AnchorProof>
  batchAnchor(items: AnchorItem[]): Promise<AnchorProof[]>
  verify(proof: AnchorProof): Promise<{ valid: boolean; timestamp: number; blockHeight: number }>
  getLatestAnchor(stateHash: string): Promise<AnchorProof | null>
  getAnchorHistory(objectPath: string): Promise<AnchorProof[]>
  getAnchorInterval(): number
  setAnchorInterval(ms: number): void
}
```

Does not exist. BSV anchoring is currently entangled with BsvOverlayAdapter storage.

### NetworkAdapter (Phase 26D — unification)

```typescript
// protocol-types/src/network.ts — TO CREATE
interface NetworkAdapter {
  publish(object: PublishableObject, options?: PublishOptions): Promise<PublishResult>
  subscribe(topic: string, callback: (event: NetworkEvent) => void): () => void
  resolve(query: NetworkQuery): Promise<NetworkResult[]>
  resolveBCA(address: string): Promise<NodeInfo | null>
  sendToNode(targetBCA: string, message: Uint8Array): Promise<{ delivered: boolean }>
  isConnected(): boolean
  getNodeBCA(): string | null
}
```

Partially exists across TopicManagerClient, LookupServiceClient, ShardProxyClient. Needs unified interface.

---

## Node Deployment Profiles

### Development Laptop
```
storage:   MemoryAdapter | NodeFsAdapter('~/.semantos/dev')
identity:  StubIdentityAdapter
anchor:    StubAnchorAdapter
network:   StubNetworkAdapter
verticals: [trades]
```

### Tradie VPS ($10/month)
```
storage:   NodeFsAdapter('/var/semantos/data')
identity:  CloudIdentityAdapter (Plexus RaaS $20/yr)
anchor:    BsvAnchorAdapter (every 10 min)
network:   BsvOverlayNetworkAdapter
verticals: [trades]
```

### Enterprise Sovereignty Node (Colo)
```
storage:   NodeFsAdapter('/mnt/nvme0/semantos')
identity:  LocalIdentityAdapter (on-prem cert chain)
anchor:    BsvAnchorAdapter (every 1 min)
network:   DirectNetworkAdapter (campus LAN)
verticals: [sovereignty, cdm, scada]
bcaAddress: 2602:f9f8:0060:0001::a3f8:b2c1
```

### Infra Partner Node (Equinix Metal)
```
storage:   NodeFsAdapter('/data/semantos')
identity:  CloudIdentityAdapter (Plexus RaaS)
anchor:    BsvAnchorAdapter (every 5 min)
network:   BsvOverlayNetworkAdapter + DirectNetworkAdapter
verticals: [sovereignty]
bcaAddress: registered by partner
```

---

## The Node Object

On startup, the kernel creates a `sovereignty.node.{cert_id}` RELEVANT semantic object describing itself:

```typescript
{
  linearity:   Linearity.RELEVANT,
  typeHash:    sha256('sovereignty.node'),
  ownerCert:   nodeCert,
  payload: {
    bcaAddress:   '2602:f9f8:0060:0001::...',
    verticals:    ['trades', 'sovereignty'],
    capabilities: [/* active capability tokens */],
    version:      '1.0.0',
    uptime:       Date.now() - startTime,
    lastAnchor:   latestAnchorProof,
    adapters: {
      storage:  'NodeFsAdapter',
      identity: 'LocalIdentityAdapter',
      anchor:   'BsvAnchorAdapter',
      network:  'DirectNetworkAdapter'
    }
  }
}
```

The admin phone app is the conversational shell scoped to this object. "Add the CDM vertical" → intent classifies to `govern.node.install-vertical` → flow runner guides through capability token purchase → node activates vertical.

---

## OddJobTodd Permission Migration

The existing trades bot permission model maps mechanically to BRC-108 capability tokens:

| OJT Role | Current Check | BRC-108 Capability Token |
|----------|---------------|-------------------------|
| creator | roleRule.contributionRights.scope = "approve" | branch.property.maintenance token; domainFlag: 0x00010002 (Create) |
| approver | override hierarchy: canOverride all | LINEAR approval token; consumed on state transition; gates completion |
| executor | requiresApproval: ["approver"] | executor.job.{scope} token; domainFlag: 0x00010003 + 0x00010005 |
| contributor | allowedEvidenceKinds: message, image | temporary cert via SMS invite; scoped domainFlags |
| observer | scope: read_only | cert with 0x00010001 (View) only |

Approval gates become LINEAR tokens — minted once, consumed once, cannot be duplicated.

---

## Cumulative Phase Completion

Phase 26 is complete when:

1. All four adapter interfaces exist in protocol-types/src/ with matching factory functions
2. Each adapter has stub + at least one production implementation
3. A Semantos node can be started from a NodeConfig with four adapter choices
4. The node creates a sovereignty.node RELEVANT object about itself on startup
5. Vertical grammars load from filesystem paths at startup
6. The conversational shell works when scoped to the node self-object
7. The admin can manage the node remotely via the shell
8. All 25A–D gate tests still pass (no regressions)
9. Phase 26 gate tests pass for all seven sub-phases
10. `npm run build` succeeds with zero errors
11. Docker image builds and runs the node
12. The node is deployable on a fresh VPS with a single install command

---

## Next Phase

Phase 27 deploys the first production tradie node and the first enterprise demo node. Phase 28 integrates the Flutter mobile shell as the tradie daily driver.
