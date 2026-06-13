---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-15-PLEXUS-REAL-SDK.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.672118+00:00
---

# Phase 15 — Production Plexus SDK Integration

**Version**: 1.0
**Date**: March 2026
**Status**: Pending Phase 14 gate
**Duration**: 2 weeks (3-day buffer)
**Prerequisites**: Phase 14 merged, `@plexus/vendor-sdk` and `@plexus/contracts` available as npm packages
**Master document**: `PLEXUS-INTEGRATION-MAP.md`
**Branch**: `phase-15-plexus-real`

## Context

Phase 14 established the adapter boundary with a stub implementation. This phase replaces the stub's backing implementation with the real Plexus SDK. The adapter interface does NOT change. The loom does NOT change. Only the implementation file changes.

The stub was deterministic but offline. The real adapter uses BRC-42 key derivation, BRC-52 certificate issuance, DAG persistence via SQLite/Postgres, and authenticated transport via BRC-100. All of this is hidden behind the same interface.

## Source Files Reference

| Alias | Path | Purpose |
|-------|------|---------|
| MAP:PLEXUS | `docs/prd/PLEXUS-INTEGRATION-MAP.md` | Architecture and component mapping |
| ADAPTER:TYPES | `packages/loom/src/plexus/types.ts` | PlexusAdapter interface (Phase 14) |
| ADAPTER:STUB | `packages/loom/src/plexus/stub.ts` | StubPlexusAdapter (Phase 14) |
| ADAPTER:SERVICE | `packages/loom/src/plexus/PlexusService.ts` | Renderer-agnostic wrapper (Phase 14) |
| SVC:IDENTITY | `packages/loom/src/services/IdentityStore.ts` | Identity service (delegates to PlexusService) |
| SVC:STORE | `packages/loom/src/services/LoomStore.ts` | Object creation (stamps certId as ownerId) |

## Deliverables

### D15.1: RealPlexusAdapter Wrapping Vendor SDK

**File**: `packages/loom/src/plexus/real.ts`

Implement `RealPlexusAdapter` class that wraps `@plexus/vendor-sdk`. This adapter:

- Instantiates the Vendor SDK with config (endpoint, database backend, debug flags)
- Delegates every `PlexusAdapter` method to corresponding Vendor SDK methods
- Translates between loom types and Plexus contract types at the boundary
- Does NOT re-export any `@plexus/contracts` types — uses only primitives in return values
- Handles Vendor SDK errors and wraps them as `PlexusError` (recoverable, message, code)

Methods mapped:

- `registerIdentity(email)` → calls Vendor SDK Identity Domain, returns `{ certId, publicKey }`
- `resolveIdentity(certId)` → queries Vendor SDK graph, returns node state
- `deriveChild(params)` → calls Vendor SDK `deriveChild()`, returns `{ certId, derivationPath, childIndex }`
- `createEdge(params)` → calls Vendor SDK `createEdge()`, returns `{ edgeId, sharedSecret }`
- `querySubtree(certId, depth)` → traverses Vendor SDK graph, returns flat node array
- `presentCapability(certId, flag)` → queries Vendor SDK capability store, returns `{ valid, ttl }`
- `mintCapability(targetCertId, flag, ttl)` → mints UTXO token, returns `{ utxoRef, expiry }`
- `initiateRecovery(email)` → triggers Recovery Service, returns `{ sessionId, challengeCount }`
- `submitChallengeAnswers(sessionId, answers)` → validates, returns `{ verified, exportPayload }`
- `sendAuthenticated(endpoint, payload)` → uses Network SDK BRC-100 transport, returns response
- `deriveSharedSecret(local, remote, context)` → uses Vendor SDK ECDH, returns hex string
- `deriveDomainKey(certId, domainFlag, rotationIndex)` → derives domain key, returns key material

Database backend selection (SQLite for dev, Postgres for production) is configured via `PlexusConfig.endpoint`.

### D15.2: @plexus/contracts Types Isolated to real.ts

Import `@plexus/contracts` ONLY in `packages/loom/src/plexus/real.ts`. Never import in:
- `types.ts` (PlexusAdapter interface must remain pure)
- `stub.ts` (stub uses no Plexus types)
- `PlexusService.ts` (wrapper should not know about Plexus internals)
- Any loom service outside `packages/loom/src/plexus/`

The adapter interface translates `@plexus/contracts` types to primitives before returning:

```typescript
// Inside real.ts only:
import { PlexusCert, BRC52Certificate } from '@plexus/contracts'

// Translate before returning from PlexusAdapter method:
export async resolveIdentity(certId: string): Promise<{
  certId: string          // primitive
  publicKey: string       // hex string
  isRevoked: boolean      // primitive
  childIndex: number      // primitive
}> {
  const cert: BRC52Certificate = await this.vendor.resolveCert(certId)
  return {
    certId: cert.id,
    publicKey: cert.pubkey.toString('hex'),
    isRevoked: cert.revoked_at !== null,
    childIndex: cert.child_index
  }
}
```

### D15.3: Environment Switching Config

**File**: `packages/loom/src/plexus/config.ts`

Create a config module that switches between stub/local/cloud implementations without code changes:

```typescript
export type PlexusMode = 'stub' | 'local' | 'cloud'

export interface PlexusEnvironmentConfig {
  mode: PlexusMode
  endpoint?: string              // local: sqlite:///path, cloud: https://plexus.example.com
  debugLogging?: boolean
  contractAddress?: string       // for cloud mode
  recoveryServiceEndpoint?: string
}

export function createAdapter(config: PlexusEnvironmentConfig): PlexusAdapter {
  if (config.mode === 'stub') {
    return new StubPlexusAdapter(config)
  }
  if (config.mode === 'local' || config.mode === 'cloud') {
    return new RealPlexusAdapter(config)
  }
  throw new Error(`Unknown Plexus mode: ${config.mode}`)
}

// Load from environment variables:
export function loadPlexusConfig(): PlexusEnvironmentConfig {
  const mode = (process.env.PLEXUS_MODE || 'stub') as PlexusMode
  return {
    mode,
    endpoint: process.env.PLEXUS_ENDPOINT,
    debugLogging: process.env.PLEXUS_DEBUG === 'true',
    contractAddress: process.env.PLEXUS_CONTRACT,
    recoveryServiceEndpoint: process.env.PLEXUS_RECOVERY_URL
  }
}
```

**No code changes required to switch**: `PLEXUS_MODE=stub npm run dev` uses the stub. `PLEXUS_MODE=real npm run dev` uses the real SDK.

### D15.4: BRC-100 Transport via @plexus/network-sdk

Wire authenticated transport through `sendAuthenticated()`:

```typescript
// In RealPlexusAdapter:
async sendAuthenticated(endpoint: string, payload: Record<string, string>): Promise<Record<string, string>> {
  const networkSdk = new NetworkSDK(this.config)
  const response = await networkSdk.sendBRC100(endpoint, payload, {
    certId: this.rootCertId,
    signer: this.cryptoUtils.sign
  })
  return response
}
```

The Network SDK handles:
- Serialization of BRC-100 headers (cert_id, challenge, signature)
- HMAC-SHA256 signing of the payload
- Retry logic on network errors
- SPV verification of responses (optional, behind flag)

### D15.5: Graph Persistence via Vendor SDK Store

Delegate graph operations to Vendor SDK's SQLite/Postgres backend:

- All nodes created via `deriveChild()` are persisted in the Vendor SDK's graph store
- Edges created via `createEdge()` are stored with ECDH metadata
- `querySubtree()` loads from persistent storage, not in-memory
- Graph state survives service restart

The Vendor SDK handles:
- Database initialization (schema creation, migrations)
- Transactional consistency for multi-node operations
- Query optimization (indexed lookups, depth-limited traversal)
- Conflict resolution (last-write-wins for concurrent derives)

### D15.6: Full Identity Registration Flow

Implement the complete identity registration flow in `registerIdentity()`:

```
Email → OTP Verification → Challenge Set Creation → BRC-52 Cert Issuance
```

Steps:

1. **Email validation**: Call `@plexus/vendor-sdk` Identity Domain with email
2. **OTP delivery**: Plexus sends OTP via email, adapter waits for user submission
3. **OTP verification**: Loom collects OTP, adapter calls Identity Domain to verify
4. **Challenge set**: Upon OTP success, adapter initiates challenge set (3 questions, hashed answers stored)
5. **Cert issuance**: Upon challenge verification, Plexus issues BRC-52 cert with root key material
6. **Return**: Adapter returns `{ certId, publicKey }` to PlexusService

**Adapter responsibility**: Call Plexus APIs in order, handle timeouts, wrap errors. Do NOT implement OTP generation or storage — Plexus owns that.

### D15.7: Facet Derivation with Domain Flags in Plexus DAG

Implement deterministic key derivation using BRC-42:

```typescript
async deriveChild(params: {
  parentCertId: string
  resourceId: string
  domainFlag: number
}): Promise<{
  certId: string
  derivationPath: string
  childIndex: number
}> {
  const vendorResult = await this.vendor.deriveChild({
    parent_cert_id: params.parentCertId,
    resource_id: params.resourceId,
    domain_flag: params.domainFlag
  })

  return {
    certId: vendorResult.cert_id,
    derivationPath: vendorResult.path,  // "m/0'/0'/1'" format
    childIndex: vendorResult.child_index
  }
}
```

**Properties**:

- Same inputs → same certId (deterministic across runs)
- Monotonic childIndex: once a child is created, its index slot is never reused
- Domain flags map to facet types (0x00010002 for CREATE, 0x00010003 for EDIT, etc.)
- Derivation path is proof of hierarchy: parent → child relationship is auditable

## Gate Tests

### T1–T8: Real Adapter Passes Same Tests as Stub

Real adapter must pass the exact same unit tests as the stub (PHASE-14-GATE.test.ts T1–T8):

- T1: `registerIdentity()` returns deterministic certId + publicKey
- T2: `deriveChild()` produces correct derivation path at 3 levels deep
- T3: `deriveChild()` enforces monotonic childIndex
- T4: `createEdge()` returns edgeId + sharedSecret
- T5: `querySubtree()` returns correct tree structure
- T6: `presentCapability()` returns valid flag
- T7: `initiateRecovery()` returns sessionId + challengeCount
- T8: `submitChallengeAnswers()` with correct answers returns verified=true

**Critical**: No changes to PlexusAdapter interface. Same test suite, same expectations.

### T9: Identity Registration Produces Real BRC-52 Cert

```typescript
it("Real adapter identity registration produces BRC-52 cert_id", async () => {
  const adapter = new RealPlexusAdapter(realConfig)
  const result = await adapter.registerIdentity("test@example.com")

  expect(result.certId).toMatch(/^[a-f0-9]{64}$/)  // 32-byte hex
  expect(result.publicKey).toMatch(/^[a-f0-9]{66}$/)  // 33-byte compressed pubkey
  // Verify certId is valid on the chain (if testnet available)
})
```

### T10: Derived Keys Deterministic

```typescript
it("Derived keys are deterministic: same inputs → same cert_id", async () => {
  const adapter1 = new RealPlexusAdapter(realConfig)
  const adapter2 = new RealPlexusAdapter(realConfig)

  const root1 = await adapter1.registerIdentity("test@example.com")
  const root2 = await adapter2.registerIdentity("test@example.com")
  expect(root1.certId).toBe(root2.certId)

  const child1 = await adapter1.deriveChild({
    parentCertId: root1.certId,
    resourceId: "trades.job",
    domainFlag: 0x00010002
  })
  const child2 = await adapter2.deriveChild({
    parentCertId: root2.certId,
    resourceId: "trades.job",
    domainFlag: 0x00010002
  })
  expect(child1.certId).toBe(child2.certId)
})
```

### T11: Environment Switching with No Code Changes

```typescript
it("PLEXUS_MODE=stub vs PLEXUS_MODE=real", async () => {
  // Stub mode
  process.env.PLEXUS_MODE = 'stub'
  const stubAdapter = createAdapter(loadPlexusConfig())
  const stubResult = await stubAdapter.registerIdentity("test@example.com")

  // Real mode (if credentials available)
  process.env.PLEXUS_MODE = 'real'
  const realAdapter = createAdapter(loadPlexusConfig())
  const realResult = await realAdapter.registerIdentity("test@example.com")

  // Same interface, same contract, different backends
  expect(typeof stubResult.certId).toBe('string')
  expect(typeof realResult.certId).toBe('string')
})
```

### T12: @plexus/contracts Import Appears Only in real.ts

```typescript
it("@plexus/contracts import isolated to real.ts", () => {
  const files = globSync('packages/loom/src/**/*.ts', {
    exclude: ['packages/loom/src/plexus/real.ts']
  })

  for (const file of files) {
    const content = fs.readFileSync(file, 'utf8')
    expect(content).not.toMatch(/@plexus\/contracts/)
    expect(content).not.toMatch(/@plexus\/vendor-sdk/)
  }
})
```

## Completion Criteria

- [ ] `packages/loom/src/plexus/real.ts` exists with full `RealPlexusAdapter` implementation
- [ ] `packages/loom/src/plexus/config.ts` exists with mode-switching logic
- [ ] `@plexus/contracts` imports appear ONLY in `real.ts`
- [ ] `RealPlexusAdapter` passes T1–T8 (same as stub)
- [ ] Identity registration produces real BRC-52 certs (T9)
- [ ] Derived keys are deterministic (T10)
- [ ] Environment switching works with no code changes (T11)
- [ ] Type isolation test passes (T12)
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All PlexusService tests still pass (Phase 14 integration unbroken)
- [ ] Errata sprint complete with `docs/prd/PHASE-15-ERRATA.md`
- [ ] All commits follow `phase-15/D15.N:` naming convention
- [ ] Branch is `phase-15-plexus-real`

## What NOT to Do

1. **Do NOT change the PlexusAdapter interface.** Phase 15 is implementation-only. The interface is frozen by Phase 14.
2. **Do NOT let @plexus types leak into loom code.** The isolation test will catch this. Real adapter translates at the boundary.
3. **Do NOT break stub tests.** The stub is permanent test infrastructure. Both adapters must pass the same test suite.
4. **Do NOT hardcode Plexus-specific logic in PlexusService.** PlexusService must not know whether it's running against real or stub.

## Next Phase

Phase 16 wires Plexus edges and capability tokens into loom operations. Object connections become real ECDH-secured edges. Capability checks hit real UTXO-based tokens.
