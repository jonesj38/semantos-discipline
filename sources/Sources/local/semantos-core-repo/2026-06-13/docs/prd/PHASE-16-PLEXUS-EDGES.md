---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-16-PLEXUS-EDGES.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.687089+00:00
---

# Phase 16 — Edge + Capability Integration

**Version**: 1.0
**Date**: March 2026
**Status**: Pending Phase 15 gate
**Duration**: 2 weeks (3-day buffer)
**Prerequisites**: Phase 15 merged, `@plexus/vendor-sdk` and `@plexus/contracts` available
**Master document**: `PLEXUS-INTEGRATION-MAP.md`
**Branch**: `phase-16-plexus-edges`

## Context

Phase 15 delivered real Plexus SDK integration with BRC-42 key derivation, BRC-52 certificates, and DAG persistence. This phase wires Plexus edges and capability tokens into loom operations.

Object connections on the canvas become real ECDH-secured edges in the Plexus DAG. Capability checks hit real UTXO-based tokens. Admin facets mint capability tokens. Loom capabilities (1–10) are translated to Plexus domain flags (uint32) and back.

## Source Files Reference

| Alias | Path | Purpose |
|-------|------|---------|
| ADAPTER:SERVICE | `packages/loom/src/plexus/PlexusService.ts` | Service wrapper (Phase 14/15) |
| ADAPTER:REAL | `packages/loom/src/plexus/real.ts` | Real adapter impl (Phase 15) |
| ADAPTER:CONFIG | `packages/loom/src/plexus/config.ts` | Mode switching (Phase 15) |
| SVC:IDENTITY | `packages/loom/src/services/IdentityStore.ts` | Identity service |
| CANVAS:CONNECTION | `packages/loom/src/canvas/CardConnection.tsx` | Object connection UI |
| MODEL:CARDCONNECTION | `packages/loom/src/types/workbench.ts` | CardConnection interface |

## Deliverables

### D16.1: CardConnection Enriched with Plexus Edge Metadata

**Modify**: `packages/loom/src/types/workbench.ts`

Extend `CardConnection` interface to store Plexus edge metadata:

```typescript
export interface CardConnection {
  // Existing fields
  id: string
  sourceCardId: string
  targetCardId: string
  connectionType: 'hard' | 'soft' | 'reference'

  // New: Plexus edge metadata (added by Phase 16)
  edgeId?: string              // Hex string, Plexus DAG edge ID
  edgeType?: string            // "ECDH", "MESSAGING", "DELEGATION", etc.
  recoveryPolicy?: {            // Edge recovery strategy
    backupRecipes: string[]     // Serialized recovery recipes
    recoveryParty?: string      // Cert ID of recovery authority (optional)
  }
  sharedSecret?: string        // Hex-encoded ECDH shared secret (for encrypted channels)
  createdAt?: number           // Timestamp
  status?: 'active' | 'revoked' | 'suspended'
}
```

These fields are populated when the edge is created via `PlexusAdapter.createEdge()`. Existing connections work as before; new connections include edge metadata.

### D16.2: Edge Creation Flow

**Modify**: Canvas connection logic (location TBD based on codebase structure)

When a user draws a connection on the canvas between two identity-owned objects:

1. **Precondition**: Both source and target objects have `ownerId` (Plexus cert ID) from Phase 14/15
2. **Call adapter**: `adapter.createEdge({ source: sourceCertId, target: targetCertId, edgeType: 'ECDH' })`
3. **Receive**: `{ edgeId, sharedSecret, recoveryPolicy }`
4. **Stamp CardConnection**: Store edgeId, edgeType, sharedSecret, recoveryPolicy on the connection object
5. **Persist**: CardConnection is written to LoomStore with full metadata

Example flow:

```typescript
async function handleCanvasConnection(sourceCard: LoomObject, targetCard: LoomObject) {
  const sourceCertId = sourceCard.header.ownerId
  const targetCertId = targetCard.header.ownerId

  if (!sourceCertId || !targetCertId) {
    throw new Error("Objects must have Plexus cert IDs to create edge")
  }

  const edgeResult = await plexusService.createEdge({
    source: sourceCertId,
    target: targetCertId,
    edgeType: 'ECDH'
  })

  const connection: CardConnection = {
    id: generateId(),
    sourceCardId: sourceCard.id,
    targetCardId: targetCard.id,
    connectionType: 'hard',
    edgeId: edgeResult.edgeId,
    edgeType: edgeResult.edgeType,
    sharedSecret: edgeResult.sharedSecret,
    recoveryPolicy: edgeResult.recoveryPolicy,
    createdAt: Date.now(),
    status: 'active'
  }

  await loomStore.createConnection(connection)
}
```

### D16.3: Capability Validation

**Modify**: Any code that gates operations on capabilities.

Every capability-gated operation (create, edit, delete, govern, transfer, admin) must call `adapter.presentCapability()` before proceeding:

```typescript
// Before user can edit an object:
async function canEditObject(objectId: string, userCertId: string): Promise<boolean> {
  const EDIT_CAPABILITY = 3  // Loom capability number
  const result = await plexusService.presentCapability(userCertId, EDIT_CAPABILITY)
  return result.valid && (result.ttl === null || result.ttl > Date.now())
}

// Before flow step executes:
async function executeFlowStep(step: FlowStep, actorCertId: string): Promise<void> {
  if (step.requiredCapability) {
    const valid = await plexusService.presentCapability(actorCertId, step.requiredCapability)
    if (!valid.valid) {
      throw new Error(`Capability ${step.requiredCapability} required but not present`)
    }
  }
  // Execute step
}
```

Capability validation happens at these points:

- **Create**: Require capability 2 (Create)
- **Edit/Patch**: Require capability 3 (Edit)
- **Query/Inspect**: No capability required
- **Consume**: Require capability 4 (Consume)
- **Govern (Vote)**: Require capability 6 (Vote)
- **Govern (Propose)**: Require capability 7 (Propose)
- **Govern (Stake)**: Require capability 8 (Stake)
- **Transfer**: Require capability 9 (Transfer)
- **Admin**: Require capability 10 (Admin)

If capability check fails, operation is blocked with `PlexusError { code: 'CAPABILITY_DENIED', recoverable: true }`.

### D16.4: Capability Minting

**Create**: `packages/loom/src/plexus/CapabilityMinter.ts`

Implement capability minting for Admin facets:

```typescript
export class CapabilityMinter {
  constructor(private adapter: PlexusAdapter) {}

  async mintCapability(
    adminCertId: string,
    targetCertId: string,
    capabilityNumber: number,
    ttlSeconds: number
  ): Promise<{ utxoRef: string; expiryTimestamp: number }> {
    // Verify admin has Admin capability (10)
    const adminCheck = await this.adapter.presentCapability(adminCertId, 10)
    if (!adminCheck.valid) {
      throw new Error("Only Admin (capability 10) can mint capabilities")
    }

    // Mint the capability
    const result = await this.adapter.mintCapability(targetCertId, capabilityNumber, ttlSeconds)
    return result
  }
}
```

Minting creates a UTXO-backed token that the Plexus capability domain recognizes. Once minted, calls to `presentCapability()` will validate the UTXO:

```typescript
// After minting capability 3 (Edit) for user:
const canEdit = await adapter.presentCapability(userCertId, 3)
// canEdit.valid === true (assuming UTXO not spent)
```

Minting is typically an admin flow step:

```json
{
  "flowId": "admin.mint-capability",
  "steps": [
    {
      "type": "action",
      "action": "mintCapability",
      "params": {
        "targetCertId": "{{ selectedUser }}",
        "capability": "{{ selectedCapability }}",
        "ttlSeconds": 86400
      }
    }
  ]
}
```

### D16.5: Domain Flag Mapping Table

**Create**: `packages/loom/src/plexus/domainFlags.ts`

Define bidirectional mapping between loom capabilities (1–10) and Plexus domain flags (uint32):

```typescript
export const CAPABILITY_TO_DOMAIN_FLAG: Record<number, number> = {
  1: 0x00010001,  // Admin — can do anything
  2: 0x00010002,  // Create — can create new objects
  3: 0x00010003,  // Edit — can patch existing objects
  4: 0x00010004,  // Consume — can consume/use objects
  5: 0x00010005,  // Inspect — can read metadata (not enforced; read is always allowed)
  6: 0x00010006,  // Vote — can vote in governance
  7: 0x00010007,  // Propose — can submit proposals
  8: 0x00010008,  // Stake — can stake resources
  9: 0x00010009,  // Transfer — can transfer ownership
  10: 0x0001000A  // Admin — can mint capabilities
}

export const DOMAIN_FLAG_TO_CAPABILITY: Record<number, number> = Object.entries(CAPABILITY_TO_DOMAIN_FLAG)
  .reduce((acc, [cap, flag]) => {
    acc[flag] = parseInt(cap)
    return acc
  }, {} as Record<number, number>)

export function capabilityToDomainFlag(cap: number): number {
  const flag = CAPABILITY_TO_DOMAIN_FLAG[cap]
  if (!flag) {
    throw new Error(`Unknown capability: ${cap}`)
  }
  return flag
}

export function domainFlagToCapability(flag: number): number {
  const cap = DOMAIN_FLAG_TO_CAPABILITY[flag]
  if (!cap) {
    throw new Error(`Unknown domain flag: ${flag.toString(16)}`)
  }
  return cap
}
```

**Properties**:

- Mapping is bidirectional and lossless (every capability maps to exactly one flag, every flag maps to exactly one capability)
- Loom code ONLY uses capability numbers (1–10), never domain flags directly
- When calling Plexus APIs, the real adapter translates: `adapter.deriveChild({ domainFlag: capabilityToDomainFlag(3) })`
- When receiving from Plexus, the real adapter translates back: `domainFlagToCapability(result.domainFlag)`

Test the mapping:

```typescript
for (let cap = 1; cap <= 10; cap++) {
  const flag = capabilityToDomainFlag(cap)
  const cap2 = domainFlagToCapability(flag)
  assert(cap === cap2, `Round-trip failed for capability ${cap}`)
}
```

## Gate Tests

### T1: Canvas Connection Creates Plexus Edge

```typescript
it("Canvas connection between identity-owned objects creates Plexus edge", async () => {
  const source = await loomStore.createObject({ typePath: "trades.job" })
  const target = await loomStore.createObject({ typePath: "trades.worker" })

  const connection = await canvasService.createConnection(source.id, target.id)

  expect(connection.edgeId).toBeDefined()
  expect(connection.edgeId).toMatch(/^[a-f0-9]{64}$/)  // 32-byte hex
  expect(connection.edgeType).toBe('ECDH')
})
```

### T2: Edge Creation Returns edgeId + sharedSecret

```typescript
it("Edge creation returns edgeId + sharedSecret", async () => {
  const root1 = await identityStore.createIdentity("alice@example.com")
  const root2 = await identityStore.createIdentity("bob@example.com")

  const result = await plexusService.createEdge({
    source: root1.certId,
    target: root2.certId,
    edgeType: 'ECDH'
  })

  expect(result.edgeId).toMatch(/^[a-f0-9]{64}$/)
  expect(result.sharedSecret).toMatch(/^[a-f0-9]{64}$/)
  expect(result.recoveryPolicy).toBeDefined()
})
```

### T3: CardConnection Stores Edge Metadata

```typescript
it("CardConnection stores edge_id, edge_type, recovery_policy", async () => {
  const source = await loomStore.createObject({ typePath: "trades.job" })
  const target = await loomStore.createObject({ typePath: "trades.worker" })

  const connection = await canvasService.createConnection(source.id, target.id)
  const stored = await loomStore.getConnection(connection.id)

  expect(stored.edgeId).toBeDefined()
  expect(stored.edgeType).toBe('ECDH')
  expect(stored.recoveryPolicy).toBeDefined()
  expect(stored.status).toBe('active')
})
```

### T4: Capability Check Passes for Valid UTXO

```typescript
it("Capability check passes for valid UTXO", async () => {
  const admin = await identityStore.createIdentity("admin@example.com")
  const user = await identityStore.createIdentity("user@example.com")

  // Admin mints Edit capability for user
  const minted = await capabilityMinter.mintCapability(admin.certId, user.certId, 3, 86400)

  // User's Edit capability check passes
  const result = await plexusService.presentCapability(user.certId, 3)
  expect(result.valid).toBe(true)
})
```

### T5: Capability Check Fails When UTXO Spent/Expired

```typescript
it("Capability check fails gracefully when UTXO spent or expired", async () => {
  const user = await identityStore.createIdentity("user@example.com")

  // Mint a capability with 1-second TTL
  await capabilityMinter.mintCapability(root.certId, user.certId, 3, 1)

  // Wait for expiry
  await new Promise(r => setTimeout(r, 1100))

  // Check fails
  const result = await plexusService.presentCapability(user.certId, 3)
  expect(result.valid).toBe(false)
})
```

### T6: Capability Minting Requires Admin Capability

```typescript
it("Capability minting requires Admin capability (10)", async () => {
  const user1 = await identityStore.createIdentity("user1@example.com")
  const user2 = await identityStore.createIdentity("user2@example.com")

  // User1 (no Admin capability) tries to mint for User2
  expect(async () => {
    await capabilityMinter.mintCapability(user1.certId, user2.certId, 3, 86400)
  }).rejects.toThrow("Only Admin")
})
```

### T7: Domain Flag Translation Bidirectional and Lossless

```typescript
it("Domain flag translation is bidirectional and lossless", async () => {
  for (let cap = 1; cap <= 10; cap++) {
    const flag = capabilityToDomainFlag(cap)
    const cap2 = domainFlagToCapability(flag)
    expect(cap2).toBe(cap)
  }
})
```

### T8: Loom Code Never References Domain Flags Directly

```typescript
it("Loom code never references domain flags directly", () => {
  const files = globSync('packages/loom/src/**/*.ts', {
    exclude: ['packages/loom/src/plexus/**', '**/node_modules/**']
  })

  for (const file of files) {
    const content = fs.readFileSync(file, 'utf8')
    // Check for hardcoded flag patterns like 0x0001000A, 0x00010001, etc.
    expect(content).not.toMatch(/0x0001[0-9a-fA-F]{4}/g)
  }

  // Capability numbers (1-10) are ok
  expect(content).toMatch(/capability\s*[=:]\s*\d/)
})
```

## Completion Criteria

- [ ] `CardConnection` interface extended with edgeId, edgeType, recoveryPolicy, status
- [ ] Canvas connection UI calls `plexusService.createEdge()` and stores metadata
- [ ] All capability-gated operations call `presentCapability()` before proceeding
- [ ] `CapabilityMinter.ts` created with `mintCapability()` method
- [ ] `domainFlags.ts` created with bidirectional mapping
- [ ] Tests T1–T8 all pass
- [ ] No loom code references domain flags directly
- [ ] No new `@plexus/*` imports outside `packages/loom/src/plexus/`
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] Errata sprint complete with `docs/prd/PHASE-16-ERRATA.md`
- [ ] All commits follow `phase-16/D16.N:` naming convention
- [ ] Branch is `phase-16-plexus-edges`

## What NOT to Do

1. **Do NOT change the PlexusAdapter interface.** Edges and capabilities are already part of the interface (Phase 14). You are only wiring them into loom operations.
2. **Do NOT hardcode capability requirements.** Capability gates are configurable (flow definitions, object type definitions). Extract them from config.
3. **Do NOT call domain flag values directly.** Use `capabilityToDomainFlag()` and `domainFlagToCapability()`.
4. **Do NOT break Phase 15 tests.** All tests from Phase 15 must still pass.

## Next Phase

Phase 17 implements transfer + recovery: chain-of-custody transfers and disaster recovery through Plexus. Objects can change ownership. Identities can be recovered from backups.
