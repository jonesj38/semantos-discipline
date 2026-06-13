---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-16-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.676829+00:00
---

# Phase 16 Execution Prompt — Edge + Capability Integration

> Paste this prompt into a fresh session to execute Phase 16.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and React loom for Bitcoin-native semantic objects (npm: `@semantos/core`). Phase 15 delivered real Plexus SDK integration with production key derivation and certificate issuance. Phase 16 wires Plexus edges and capability tokens into loom operations.

Object connections on the canvas become real ECDH-secured edges in the Plexus DAG. Capability checks hit real UTXO-based tokens. Admin facets mint capability tokens. Loom capabilities (1–10) are translated to Plexus domain flags (uint32) and back.

Your task is to enrich CardConnection with edge metadata, wire capability validation into all operations, implement capability minting, and create a domain flag mapping table.

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are building on top of. If you haven't read them, you will produce stubs, mocks, or code that doesn't integrate. That is not acceptable.

**Read first** (the PRD — your requirements):
- `docs/prd/PHASE-16-PLEXUS-EDGES.md` — Full spec with deliverables D16.1–D16.5, gate tests T1–T8

**Read second** (the adapter from Phase 15 — the interface you are calling):
- `packages/loom/src/plexus/types.ts` — PlexusAdapter interface
- `packages/loom/src/plexus/real.ts` — Real adapter implementation
- `packages/loom/src/plexus/PlexusService.ts` — Service wrapper

**Read third** (the loom data model):
- `packages/loom/src/types/workbench.ts` — CardConnection, LoomObject interfaces
- `packages/loom/src/services/LoomStore.ts` — Object and connection persistence

**Read fourth** (the integration points):
- `packages/loom/src/services/IdentityStore.ts` — Identity service
- Canvas connection logic (find where user connections are created and stored)

**Read fifth** (the test infrastructure):
- `packages/__tests__/phase14-gate.test.ts` — Phase 14/15 tests (Phase 16 must not break these)

**Read sixth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-16-plexus-edges`. Commits as `phase-16/D16.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phase 15. Plus:

### 1. CAPABILITY CHECKS ARE NOT OPTIONAL

Every operation that requires a capability (create, edit, transfer, govern, admin) must call `presentCapability()` before proceeding. You cannot skip this. You cannot mock it. Gate test T8 will scan your code for it.

### 2. EDGES ARE CREATED LAZILY

When the user draws a connection on the canvas, that is when you call `adapter.createEdge()`. Not during object creation. Not in a background task. At the moment of connection.

### 3. DOMAIN FLAGS ARE INTERNAL TO PLEXUS

Loom code NEVER references domain flag values (0x0001000A, etc.). Only the mapping module does. All loom code uses capability numbers (1–10). Gate test T8 enforces this with a regex scan.

### 4. NO CHANGES TO PLEXUS ADAPTER INTERFACE

Edges and capabilities are already part of the interface (Phase 14). You are only wiring them. Do not add new methods to PlexusAdapter.

### 5. CAPABILITY MINTING REQUIRES ADMIN

Only identities with capability 10 (Admin) can mint new capabilities. The `CapabilityMinter.ts` class must verify this on every mint call.

### 6. RECOVERY POLICY IS OPTIONAL

Not every edge needs a recovery policy. If `createEdge()` returns null, store null. Do not create empty objects.

### 7. BIDIRECTIONAL MAPPING

The domain flag mapping must work both ways. A test will round-trip every capability: capability → flag → capability. It must match.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify Phase 15 is complete

```bash
# Adapter files exist and are not stubbed
ls packages/loom/src/plexus/types.ts
ls packages/loom/src/plexus/stub.ts
ls packages/loom/src/plexus/real.ts
ls packages/loom/src/plexus/config.ts
ls packages/loom/src/plexus/PlexusService.ts

# Phase 14/15 tests pass
bun test packages/__tests__/phase14-gate.test.ts
bun test packages/__tests__/phase15-gate.test.ts  # If exists

# No TypeScript errors
bun run check
```

All files must exist and tests must pass. If anything is missing or broken, STOP.

### 0.4 Create Phase 16 branch

```bash
git checkout -b phase-16-plexus-edges
```

---

## Step 1: CardConnection Extension (D16.1)

Modify `packages/loom/src/types/workbench.ts`.

Add fields to `CardConnection` interface:

```typescript
export interface CardConnection {
  // Existing fields
  id: string
  sourceCardId: string
  targetCardId: string
  connectionType: 'hard' | 'soft' | 'reference'

  // New: Plexus edge metadata (Phase 16)
  edgeId?: string
  edgeType?: string
  recoveryPolicy?: {
    backupRecipes: string[]
    recoveryParty?: string
  }
  sharedSecret?: string
  createdAt?: number
  status?: 'active' | 'revoked' | 'suspended'
}
```

These fields are optional to maintain backward compatibility with existing connections. New connections will have all fields populated.

Commit: `phase-16/D16.1: CardConnection enriched with edgeId, edgeType, recoveryPolicy, sharedSecret`

---

## Step 2: Edge Creation Flow (D16.2)

Find the canvas connection creation logic. This is likely in a component or service that handles user interaction on the canvas.

When a connection is created (user draws a line between two objects):

1. Check that both objects have `ownerId` (Plexus cert ID)
2. Call `plexusService.createEdge({ source: sourceCertId, target: targetCertId, edgeType: 'ECDH' })`
3. Store the returned edgeId, sharedSecret, recoveryPolicy on the CardConnection
4. Persist the connection via `loomStore.createConnection(connection)`

Example:

```typescript
async function createConnectionBetweenObjects(sourceId: string, targetId: string) {
  const source = await loomStore.getObject(sourceId)
  const target = await loomStore.getObject(targetId)

  if (!source.header.ownerId || !target.header.ownerId) {
    throw new Error("Both objects must have Plexus cert IDs")
  }

  const edge = await plexusService.createEdge({
    source: source.header.ownerId,
    target: target.header.ownerId,
    edgeType: 'ECDH'
  })

  const connection: CardConnection = {
    id: generateUUID(),
    sourceCardId: sourceId,
    targetCardId: targetId,
    connectionType: 'hard',
    edgeId: edge.edgeId,
    edgeType: edge.edgeType,
    sharedSecret: edge.sharedSecret,
    recoveryPolicy: edge.recoveryPolicy,
    createdAt: Date.now(),
    status: 'active'
  }

  await loomStore.createConnection(connection)
  return connection
}
```

Update UI components to display edge status (green for active, red for revoked).

Commit: `phase-16/D16.2: canvas connection → adapter.createEdge() → CardConnection metadata`

---

## Step 3: Capability Validation (D16.3)

This is the most important part. Every capability-gated operation must call `presentCapability()`.

Find all locations where operations are gated:

- **Create object**: Require capability 2
- **Edit object**: Require capability 3
- **Delete object**: Require capability 4 (consume)
- **Govern (vote)**: Require capability 6
- **Govern (propose)**: Require capability 7
- **Transfer object**: Require capability 9
- **Admin operations**: Require capability 10

Create a helper:

```typescript
// packages/loom/src/plexus/capabilityGuard.ts

export const CAPABILITY_REQUIREMENTS: Record<string, number> = {
  'create': 2,
  'edit': 3,
  'consume': 4,
  'inspect': 5,      // No check needed, always allowed
  'vote': 6,
  'propose': 7,
  'stake': 8,
  'transfer': 9,
  'admin': 10
}

export async function checkCapability(
  plexusService: PlexusService,
  userCertId: string,
  operation: string
): Promise<boolean> {
  const required = CAPABILITY_REQUIREMENTS[operation]
  if (!required) {
    return true  // Unknown operation, allow it
  }

  const result = await plexusService.presentCapability(userCertId, required)
  return result.valid && (result.ttl === null || result.ttl > Date.now())
}

// Usage in LoomStore.updateObject():
async updateObject(id: string, patch: ObjectPatch, userCertId: string) {
  if (!await checkCapability(this.plexus, userCertId, 'edit')) {
    throw new PlexusError('CAPABILITY_DENIED', 'Edit capability required')
  }
  // Proceed with update
}
```

Wire this into:
- `LoomStore.createObject()` (requires capability 2)
- `LoomStore.updateObject()` (requires capability 3)
- `LoomStore.deleteObject()` (requires capability 4)
- `FlowRunner` step execution (check step.requiredCapability)
- Any governance flow (vote, propose, stake require 6, 7, 8)

Commit: `phase-16/D16.3: capability validation wired into all operations`

---

## Step 4: Capability Minting (D16.4)

Create `packages/loom/src/plexus/CapabilityMinter.ts`:

```typescript
import { PlexusService } from './PlexusService'
import { PlexusError } from './types'

export class CapabilityMinter {
  constructor(private plexus: PlexusService) {}

  async mintCapability(
    adminCertId: string,
    targetCertId: string,
    capabilityNumber: number,
    ttlSeconds: number
  ): Promise<{ utxoRef: string; expiryTimestamp: number }> {
    // Verify admin has Admin capability (10)
    const adminCheck = await this.plexus.presentCapability(adminCertId, 10)
    if (!adminCheck.valid) {
      throw new PlexusError('CAPABILITY_DENIED', 'Only Admin (capability 10) can mint', true)
    }

    // Verify capability number is valid (1-10)
    if (capabilityNumber < 1 || capabilityNumber > 10) {
      throw new Error(`Invalid capability number: ${capabilityNumber}`)
    }

    // Mint
    const result = await this.plexus.mintCapability(targetCertId, capabilityNumber, ttlSeconds)
    return {
      utxoRef: result.utxoRef,
      expiryTimestamp: result.expiry
    }
  }
}
```

This is typically called from a flow step:

```json
{
  "flowId": "governance.mint-capability",
  "steps": [
    {
      "id": "select-user",
      "type": "input",
      "prompt": "Who should receive this capability?",
      "inputType": "identity-picker"
    },
    {
      "id": "select-capability",
      "type": "input",
      "prompt": "Which capability?",
      "inputType": "select",
      "options": [
        { "label": "Create", "value": 2 },
        { "label": "Edit", "value": 3 },
        { "label": "Consume", "value": 4 }
      ]
    },
    {
      "id": "mint",
      "type": "action",
      "action": "mintCapability",
      "params": {
        "targetCertId": "{{ select-user.result }}",
        "capabilityNumber": "{{ select-capability.result }}",
        "ttlSeconds": 86400
      },
      "requiredCapability": 10
    }
  ]
}
```

Commit: `phase-16/D16.4: CapabilityMinter enforces Admin-only minting`

---

## Step 5: Domain Flag Mapping (D16.5)

Create `packages/loom/src/plexus/domainFlags.ts`:

```typescript
/**
 * Bidirectional mapping between loom capabilities (1-10)
 * and Plexus domain flags (uint32).
 *
 * Loom code ONLY uses capability numbers.
 * Domain flag values are internal to Plexus translation.
 */

export const CAPABILITY_TO_DOMAIN_FLAG: Record<number, number> = {
  1: 0x00010001,  // Admin
  2: 0x00010002,  // Create
  3: 0x00010003,  // Edit
  4: 0x00010004,  // Consume
  5: 0x00010005,  // Inspect (not enforced)
  6: 0x00010006,  // Vote
  7: 0x00010007,  // Propose
  8: 0x00010008,  // Stake
  9: 0x00010009,  // Transfer
  10: 0x0001000A  // Admin (same as 1? check Plexus spec)
}

export const DOMAIN_FLAG_TO_CAPABILITY: Record<number, number> = {}

// Build reverse map
for (const [capStr, flag] of Object.entries(CAPABILITY_TO_DOMAIN_FLAG)) {
  const cap = parseInt(capStr)
  DOMAIN_FLAG_TO_CAPABILITY[flag] = cap
}

export function capabilityToDomainFlag(capability: number): number {
  const flag = CAPABILITY_TO_DOMAIN_FLAG[capability]
  if (flag === undefined) {
    throw new Error(`Unknown capability: ${capability}`)
  }
  return flag
}

export function domainFlagToCapability(flag: number): number {
  const cap = DOMAIN_FLAG_TO_CAPABILITY[flag]
  if (cap === undefined) {
    throw new Error(`Unknown domain flag: ${flag.toString(16)}`)
  }
  return cap
}

/**
 * Validate that mapping is bidirectional and lossless.
 * Call this in tests.
 */
export function validateMapping(): void {
  for (let cap = 1; cap <= 10; cap++) {
    const flag = capabilityToDomainFlag(cap)
    const cap2 = domainFlagToCapability(flag)
    if (cap !== cap2) {
      throw new Error(`Mapping not lossless: ${cap} -> ${flag} -> ${cap2}`)
    }
  }
}
```

Use this in `real.ts` when calling Plexus APIs:

```typescript
// In RealPlexusAdapter.deriveChild():
const result = await this.vendor.deriveChild({
  parent_cert_id: params.parentCertId,
  resource_id: params.resourceId,
  domain_flag: capabilityToDomainFlag(params.domainFlag)  // Convert to Plexus flag
})

// In RealPlexusAdapter.presentCapability():
const result = await this.vendor.presentCapability(
  certId,
  capabilityToDomainFlag(capability)
)
return {
  valid: result.valid,
  ttl: result.ttl
}
```

**Critical**: Loom services never import `domainFlags.ts` directly. Only `real.ts` uses it.

Commit: `phase-16/D16.5: bidirectional capability ↔ domain flag mapping`

---

## Step 6: Gate Tests

Create `packages/__tests__/phase16-gate.test.ts`.

Tests T1–T8 from the PRD:

```typescript
describe("Phase 16: Edge + Capability Integration", () => {
  let loom: LoomStore
  let plexus: PlexusService
  let identity: IdentityStore
  let minter: CapabilityMinter

  beforeEach(async () => {
    // Initialize with stub adapter
    plexus = new PlexusService({ mode: 'stub' })
    identity = new IdentityStore(plexus)
    loom = new LoomStore(plexus, identity)
    minter = new CapabilityMinter(plexus)
  })

  // T1: Canvas connection creates Plexus edge
  it("T1: Canvas connection between identity-owned objects creates Plexus edge", async () => {
    const source = await loom.createObject({ typePath: "trades.job" })
    const target = await loom.createObject({ typePath: "trades.worker" })
    const connection = await canvasService.createConnection(source.id, target.id)

    expect(connection.edgeId).toBeDefined()
    expect(connection.edgeId).toMatch(/^[a-f0-9]{64}$/)
    expect(connection.status).toBe('active')
  })

  // T2: Edge returns edgeId + sharedSecret
  it("T2: Edge creation returns edgeId + sharedSecret", async () => {
    const alice = await identity.createIdentity("alice@example.com")
    const bob = await identity.createIdentity("bob@example.com")

    const result = await plexus.createEdge({
      source: alice.certId,
      target: bob.certId,
      edgeType: 'ECDH'
    })

    expect(result.edgeId).toBeDefined()
    expect(result.sharedSecret).toBeDefined()
  })

  // T3: CardConnection stores edge metadata
  it("T3: CardConnection stores edge_id, edge_type, recovery_policy", async () => {
    // ... create connection, verify stored metadata
  })

  // T4: Capability check passes for valid UTXO
  it("T4: Capability check passes for valid UTXO", async () => {
    const admin = await identity.createIdentity("admin@example.com")
    const user = await identity.createIdentity("user@example.com")

    // Admin mints Edit capability
    await minter.mintCapability(admin.certId, user.certId, 3, 86400)

    // User's Edit check passes
    const result = await plexus.presentCapability(user.certId, 3)
    expect(result.valid).toBe(true)
  })

  // T5: Capability fails when UTXO expired
  it("T5: Capability check fails when UTXO spent/expired", async () => {
    // ... mint with 1-second TTL, wait, check fails
  })

  // T6: Minting requires Admin
  it("T6: Capability minting requires Admin capability (10)", async () => {
    const user = await identity.createIdentity("user@example.com")
    const other = await identity.createIdentity("other@example.com")

    expect(async () => {
      await minter.mintCapability(user.certId, other.certId, 3, 86400)
    }).rejects.toThrow("Admin")
  })

  // T7: Domain flag mapping bidirectional
  it("T7: Domain flag translation is bidirectional and lossless", async () => {
    for (let cap = 1; cap <= 10; cap++) {
      const flag = capabilityToDomainFlag(cap)
      const cap2 = domainFlagToCapability(flag)
      expect(cap2).toBe(cap)
    }
  })

  // T8: Loom never references domain flags directly
  it("T8: Loom code never references domain flags directly", () => {
    const files = globSync('packages/loom/src/**/*.ts', {
      exclude: ['packages/loom/src/plexus/**', '**/node_modules/**']
    })

    for (const file of files) {
      const content = fs.readFileSync(file, 'utf8')
      // Regex to detect hex patterns like 0x0001000A
      expect(content).not.toMatch(/0x0001[0-9a-fA-F]{4}/g)
    }
  })
})
```

Run tests:

```bash
bun test packages/__tests__/phase16-gate.test.ts
```

Commit: `phase-16/T1-T8: full gate test suite for edges and capabilities`

---

## Step 7: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review: every capability check, every edge creation
2. Check error paths: what happens if `createEdge()` fails?
3. Check backward compatibility: do old connections (without edge metadata) still work?
4. Check capability isolation: can a user with Create (2) also transfer (9)? Only if they have capability 9.
5. Check domain flag mapping: are all 10 capabilities mapped? Do any overlap?
6. Check Phase 15 integration: do real adapter tests still pass?
7. Write errata doc as `docs/prd/PHASE-16-ERRATA.md`

---

## Completion Criteria

- [ ] `CardConnection` interface extended with edgeId, edgeType, recoveryPolicy, status
- [ ] Canvas connection flow calls `plexusService.createEdge()` and stores metadata
- [ ] All capability-gated operations call `presentCapability()` before proceeding
- [ ] `CapabilityMinter.ts` created with `mintCapability()` enforcing Admin requirement
- [ ] `domainFlags.ts` created with bidirectional mapping
- [ ] `capabilityGuard.ts` (or equivalent) helper for operation guards
- [ ] Tests T1–T8 all pass
- [ ] Phase 14/15 tests still pass (no regressions)
- [ ] No loom code references domain flags directly (T8 enforced by scan)
- [ ] No new `@plexus/*` imports outside `packages/loom/src/plexus/`
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] Errata sprint complete with `docs/prd/PHASE-16-ERRATA.md`
- [ ] All commits follow `phase-16/D16.N:` naming convention
- [ ] Branch is `phase-16-plexus-edges`

---

## Next Phase

Phase 17 implements chain-of-custody transfers and disaster recovery. Objects transfer ownership. Identities recover from backups.
