---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-15-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.684867+00:00
---

# Phase 15 Execution Prompt — Production Plexus SDK Integration

> Paste this prompt into a fresh session to execute Phase 15.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and React loom for Bitcoin-native semantic objects (npm: `@semantos/core`). Phase 14 established the adapter boundary with a stub implementation that enabled development without a running Plexus instance. Phase 15 replaces that stub with the real Plexus SDK: real BRC-42 key derivation, BRC-52 certificate issuance, DAG persistence via SQLite/Postgres, and authenticated BRC-100 transport.

Your task is to implement `RealPlexusAdapter`, wire it through environment config, and ensure it passes the same test suite as the stub. The adapter interface does NOT change. The loom does NOT change. Only the implementation changes.

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are building on top of. If you haven't read them, you will produce stubs, mocks, or code that doesn't integrate. That is not acceptable.

**Read first** (the PRD — your requirements):
- `docs/prd/PHASE-15-PLEXUS-REAL-SDK.md` — Full spec with deliverables D15.1–D15.7, gate tests T1–T12, isolation requirements

**Read second** (the adapter files from Phase 14 — understand them completely):
- `packages/loom/src/plexus/types.ts` — PlexusAdapter interface (non-locking, primitive-only)
- `packages/loom/src/plexus/stub.ts` — StubPlexusAdapter (deterministic in-memory implementation)
- `packages/loom/src/plexus/PlexusService.ts` — Renderer-agnostic wrapper with useSyncExternalStore
- `packages/loom/src/plexus/index.ts` — Barrel export

**Read third** (the Plexus specification):
- `docs/prd/PLEXUS-INTEGRATION-MAP.md` — Architecture, Plexus components, what the Vendor SDK provides

**Read fourth** (the integration points):
- `packages/loom/src/services/IdentityStore.ts` — Identity service (delegates cert ops to PlexusService)
- `packages/loom/src/services/LoomStore.ts` — Object creation (stamps certId as ownerId)

**Read fifth** (the test infrastructure from Phase 14):
- `packages/__tests__/phase14-gate.test.ts` — Full test suite T1–T20. Phase 15 must pass T1–T8, add T9–T12.

**Read sixth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-15-plexus-real`. Commits as `phase-15/D15.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phase 14. Plus:

### 1. NO STUBS IN PRODUCTION

Every method in RealPlexusAdapter must call real Plexus SDK methods. If a function body throws `new Error("not implemented")`, you have failed. If you call the stub fallback "just in case," you have failed.

### 2. NO PLEXUS IMPORTS OUTSIDE real.ts

`@plexus/*` imports may ONLY appear in `packages/loom/src/plexus/real.ts`. Gate test T12 scans for this. Zero tolerance.

### 3. NO PLEXUS TYPES IN ADAPTER INTERFACE

The PlexusAdapter interface in types.ts uses ONLY primitives: `string`, `number`, `boolean`, `Record<string, string>`. Translation from `@plexus/contracts` types to primitives happens inside `real.ts`, never in the interface or PlexusService.

### 4. REAL ADAPTER MUST PASS SAME TESTS AS STUB

The test suite T1–T8 runs against both adapters. Same input, same output, same contract. Different backends. If the real adapter produces a different certId for the same email, you are broken.

### 5. ENVIRONMENT SWITCHING IS NOT OPTIONAL

After Phase 15, these two commands must work:

```bash
PLEXUS_MODE=stub npm run dev
PLEXUS_MODE=real npm run dev
```

No code changes between them. The `config.ts` module handles the switch.

### 6. VENDOR SDK ISOLATION

You are wrapping the Vendor SDK, not rewriting it. If the Vendor SDK throws an error, catch it, wrap it as `PlexusError`, and return it. Do not filter, modify, or hide errors from the loom.

### 7. DETERMINISM

Same email → same certId, every run, across service restarts. If you use random data, timestamps, or nonces in key derivation, you have broken determinism. BRC-42 is deterministic. Use it.

### 8. NO MOCKS IN PRODUCTION

Test files may mock HTTP calls. Source files may not contain hardcoded responses, test data, or fallback stubs. Every code path hits the real Vendor SDK (or stub, if mode is stub).

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

### 0.3 Verify Phase 14 is complete

```bash
# Adapter files exist and are not stubbed
ls packages/loom/src/plexus/types.ts
ls packages/loom/src/plexus/stub.ts
ls packages/loom/src/plexus/PlexusService.ts
ls packages/loom/src/plexus/index.ts

# Phase 14 tests pass
bun test packages/__tests__/phase14-gate.test.ts

# No TypeScript errors
bun run check
```

All files must exist and tests must pass. If anything is missing or broken, STOP.

### 0.4 Create Phase 15 branch

```bash
git checkout -b phase-15-plexus-real
```

---

## Step 1: RealPlexusAdapter (D15.1)

Create `packages/loom/src/plexus/real.ts`.

This wraps `@plexus/vendor-sdk`. Every method maps directly to Vendor SDK methods. Translate Plexus types to primitives before returning.

Implementation requirements:

- Constructor takes `PlexusConfig`
- Instantiates Vendor SDK client with endpoint (SQLite for local, Postgres endpoint for cloud)
- Implements all 12 methods from PlexusAdapter interface
- Every method returns only primitives (string, number, boolean, Record)
- Errors from Vendor SDK are wrapped as PlexusError with code, message, recoverable flag
- No `@plexus/contracts` types in public method signatures

Sketch:

```typescript
import { PlexusAdapter, PlexusConfig } from './types'
import { VendorSDK } from '@plexus/vendor-sdk'
import { PlexusCert } from '@plexus/contracts'  // ONLY in this file

export class RealPlexusAdapter implements PlexusAdapter {
  private vendor: VendorSDK
  private rootCertId: string | null = null

  constructor(config: PlexusConfig) {
    this.vendor = new VendorSDK({
      endpoint: config.endpoint || 'sqlite:///plexus.db',
      debug: config.debugLogging || false
    })
  }

  async registerIdentity(email: string): Promise<{ certId: string; publicKey: string }> {
    try {
      const cert: PlexusCert = await this.vendor.registerIdentity(email)
      this.rootCertId = cert.id
      return {
        certId: cert.id,
        publicKey: cert.pubkey.toString('hex')
      }
    } catch (err) {
      throw this.wrapError(err)
    }
  }

  // ... rest of methods
}
```

Commit: `phase-15/D15.1: RealPlexusAdapter wrapping @plexus/vendor-sdk`

---

## Step 2: Type Isolation at Boundary (D15.2)

Verify D15.2 requirements:

- `types.ts` has ZERO `@plexus/*` imports
- `stub.ts` has ZERO `@plexus/*` imports
- `PlexusService.ts` has ZERO `@plexus/*` imports
- Only `real.ts` imports from `@plexus/contracts` and `@plexus/vendor-sdk`

Translation happens at the boundary of `real.ts`:

```typescript
// Inside real.ts:
const cert: PlexusCert = await this.vendor.resolveCert(certId)

// Before returning to caller:
return {
  certId: cert.id,              // primitive string
  publicKey: cert.pubkey.hex(), // primitive string
  isRevoked: cert.revoked_at !== null  // primitive boolean
}
```

Commit: `phase-15/D15.2: @plexus/contracts types isolated to real.ts only`

---

## Step 3: Environment Config (D15.3)

Create `packages/loom/src/plexus/config.ts`.

```typescript
export type PlexusMode = 'stub' | 'local' | 'cloud'

export interface PlexusEnvironmentConfig {
  mode: PlexusMode
  endpoint?: string           // sqlite:///path or https://plexus.example.com
  debugLogging?: boolean
  contractAddress?: string
  recoveryServiceEndpoint?: string
}

export function createAdapter(config: PlexusEnvironmentConfig): PlexusAdapter {
  if (config.mode === 'stub') {
    return new StubPlexusAdapter(config)
  }
  if (config.mode === 'local' || config.mode === 'cloud') {
    return new RealPlexusAdapter(config)
  }
  throw new Error(`Unknown mode: ${config.mode}`)
}

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

Test:

```bash
PLEXUS_MODE=stub node -e "console.log(createAdapter(loadPlexusConfig()).constructor.name)"
# Output: StubPlexusAdapter

PLEXUS_MODE=real PLEXUS_ENDPOINT=sqlite:///test.db node -e "console.log(createAdapter(loadPlexusConfig()).constructor.name)"
# Output: RealPlexusAdapter
```

Commit: `phase-15/D15.3: environment switching config with loadPlexusConfig()`

---

## Step 4: BRC-100 Transport (D15.4)

In RealPlexusAdapter, implement `sendAuthenticated()`:

```typescript
async sendAuthenticated(endpoint: string, payload: Record<string, string>): Promise<Record<string, string>> {
  const networkSdk = this.vendor.getNetworkSDK()
  const response = await networkSdk.sendBRC100(endpoint, payload, {
    certId: this.rootCertId,
    signer: (data) => this.vendor.sign(data)
  })
  return response
}
```

The Network SDK handles:
- BRC-100 header serialization (cert_id, challenge, signature)
- HMAC-SHA256 signing
- Retry logic

If the Vendor SDK doesn't expose Network SDK directly, instantiate it:

```typescript
import { NetworkSDK } from '@plexus/network-sdk'

const networkSdk = new NetworkSDK(this.vendor.getConfig())
```

Test: Send a mock BRC-100 request and verify headers are present.

Commit: `phase-15/D15.4: BRC-100 transport via @plexus/network-sdk in sendAuthenticated()`

---

## Step 5: Graph Persistence (D15.5)

Verify Vendor SDK persistence by testing `querySubtree()`:

```typescript
async querySubtree(certId: string, depth: number): Promise<Array<{ certId: string; childIndex: number }>> {
  const nodes = await this.vendor.querySubtree(certId, { maxDepth: depth })
  return nodes.map(n => ({
    certId: n.id,
    childIndex: n.child_index
  }))
}
```

The Vendor SDK manages SQLite/Postgres internally. Your job is to translate return types.

Test: Create identity, derive 2 children, restart the RealPlexusAdapter, query subtree again. Same results.

Commit: `phase-15/D15.5: querySubtree delegates to Vendor SDK persistent store`

---

## Step 6: Identity Registration Flow (D15.6)

Implement `registerIdentity()` as a full flow:

1. Call Vendor SDK Identity Domain with email
2. Plexus sends OTP to email
3. Adapter returns immediately with `{ sessionId }` (or blocks for OTP, based on Vendor SDK API)
4. Caller (PlexusService → IdentityStore → UI) collects OTP from user
5. Call `submitChallengeAnswers()` with OTP
6. Upon success, Identity Domain issues BRC-52 cert

If the Vendor SDK handles OTP internally (non-blocking), let it. If it expects async callback, wire it through PlexusService.

The adapter is responsible for calling the right APIs in order. The UI flow is PlexusService's concern.

Commit: `phase-15/D15.6: full identity registration flow via Identity Domain`

---

## Step 7: Facet Derivation with Domain Flags (D15.7)

Implement `deriveChild()` using real BRC-42:

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
  const result = await this.vendor.deriveChild({
    parent_cert_id: params.parentCertId,
    resource_id: params.resourceId,
    domain_flag: params.domainFlag
  })

  return {
    certId: result.cert_id,
    derivationPath: result.derivation_path,  // "m/0'/0'/1'" format
    childIndex: result.child_index
  }
}
```

**Critical property**: `deriveChild()` with same inputs must always return the same certId. BRC-42 guarantees this. Verify it.

Test: Derive same child twice, verify certId matches.

Commit: `phase-15/D15.7: facet derivation with real BRC-42 key material`

---

## Step 8: Gate Tests

Add tests T9–T12 to `packages/__tests__/phase14-gate.test.ts`.

Existing tests T1–T8 must pass against BOTH adapters. Run:

```bash
bun test packages/__tests__/phase14-gate.test.ts
```

All tests should pass without modification. If not, fix the real adapter, not the tests.

New tests:

- **T9**: Real adapter identity registration produces valid BRC-52 cert_id (32-byte hex)
- **T10**: Derived keys deterministic (same email → same certId, same parent + resource → same child)
- **T11**: Environment mode switching works (PLEXUS_MODE env var controls adapter type)
- **T12**: @plexus imports scan (no @plexus imports outside plexus/ directory)

Commit: `phase-15/T9-T12: gate tests for real adapter and isolation`

---

## Step 9: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review of every line in `real.ts`
2. Check error handling: does every catch block wrap as PlexusError?
3. Check determinism: same email twice → same certId?
4. Check type boundaries: are PlexusCert, PlexusNode ever returned from public methods?
5. Check Vendor SDK version compatibility: does the adapter work with the installed SDK version?
6. Check recovery: can the adapter recover from network errors gracefully?
7. Verify all 12 methods are implemented (no stubs, no fallbacks)
8. Write errata doc as `docs/prd/PHASE-15-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/loom/src/plexus/real.ts` exists with full `RealPlexusAdapter` (12 methods implemented)
- [ ] `packages/loom/src/plexus/config.ts` exists with `createAdapter()` and `loadPlexusConfig()`
- [ ] `@plexus/*` imports appear ONLY in `real.ts`
- [ ] Tests T1–T8 pass against both stub and real adapters
- [ ] Tests T9–T12 pass (real adapter, determinism, env switching, isolation)
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All PlexusService and IdentityStore tests still pass (Phase 14 integration unbroken)
- [ ] Errata sprint complete with `docs/prd/PHASE-15-ERRATA.md`
- [ ] All commits follow `phase-15/D15.N:` naming convention
- [ ] Branch is `phase-15-plexus-real`

---

## Next Phase

Phase 16 wires Plexus edges and capability tokens into loom operations. Object connections become real ECDH-secured edges. Capability checks hit real UTXO-based tokens.
