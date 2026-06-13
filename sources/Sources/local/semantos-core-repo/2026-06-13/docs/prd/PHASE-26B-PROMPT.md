---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26B-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.705555+00:00
---

# Phase 26B Execution Prompt — Local Identity Adapter (Offline Token Validation)

> Paste this prompt into a fresh session to execute Phase 26B.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and React loom for Bitcoin-native semantic objects (npm: `@semantos/core`). The kernel is Zig/WASM in the sibling `semantos` repo. Phase 26A extracted the `IdentityAdapter` interface to `protocol-types/src/identity.ts`. Now Phase 26B implements `LocalIdentityAdapter` — the offline capability validation system for standalone Semantos nodes.

Your task is to build `LocalIdentityAdapter` and supporting classes that enable a node to validate BRC-108 capability tokens **without calling any remote service**. The node reads a certificate chain from StorageAdapter, walks it locally, and validates tokens offline. This is essential for tradie VPS nodes, enterprise sovereignty nodes, and disaster recovery scenarios.

### What Already Exists (Phase 26A Output)

- `packages/protocol-types/src/identity.ts` — `IdentityAdapter` interface (8 methods, all primitive types)
- `packages/protocol-types/src/storage.ts` — `StorageAdapter` interface (complete, Phase 25A)
- `packages/protocol-types/src/cell-store.ts` — `CellStore` interface (complete, Phase 25B)
- `packages/shell/src/capabilities.ts` — capability domain flag mappings (0x00010001–0x0001000A)
- Test patterns from Phase 14 (`packages/__tests__/phase14-gate.test.ts`)

---

## CRITICAL: READ THESE FILES FIRST

Before starting, read the product context document:

- `/Users/toddprice/projects/semantos-core/docs/prd/PLATFORM-ARCHITECTURE.md` — **Product context.** The dispatch envelope model requires offline capability validation. When a PM dispatches a job to a tradie, the tradie's node must validate the PM's capability token without calling the PM's identity service. LocalIdentityAdapter makes cross-vertical dispatch work without a central identity authority.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 9–14. Plus:

### 1. NO REMOTE SERVICE CALLS

All certificate chain walks and token validation must use **only** the StorageAdapter. If any method calls a Plexus RaaS endpoint or makes a network request, you have failed. `presentCapability()` must return in <10ms (local storage only).

### 2. NO PLEXUS IMPORTS IN identity-adapters/

`@plexus/*` imports may ONLY appear in `packages/loom/src/plexus/`. The `identity-adapters` directory lives in `protocol-types/src/` — it must be Plexus-agnostic. Gate test T26B.20 enforces this.

### 3. MONOTONIC CHILD INDEX IS IMMUTABLE

Child indices are assigned strictly in order: 0, 1, 2, 3... per parent. Once index N is used, it is **never reused**, even if the child is deleted or revoked. The next child gets index N+1. This is a core security invariant.

### 4. ALL VALIDATION IS OFFLINE

Capability token validation does **not** fetch remote certs, check remote revocation lists, or contact external services. Everything comes from the local cert store. If a cert is not in local storage, throw `PlexusError` with `code: 'CERT_NOT_FOUND'` and `recoverable: true`.

### 5. RECOVERY SHARES ARE ENCRYPTED

Recovery shares stored in StorageAdapter are **AES-256-GCM encrypted**. The encryption key is derived from user recovery challenges. No share is stored in plaintext.

### 6. NO STUBS

Every function must do real work. If a function body is `throw new Error("not implemented")` or `return undefined`, you have failed. `LocalIdentityAdapter` is a complete production implementation.

### 7. STORAGE KEY PATTERNS

All identity data lives under `identity/` prefix in storage:

```
identity/certs/{certId}                 → serialized cert
identity/certs/{certId}/children        → list of child certIds
identity/recovery/session/{sessionId}   → recovery session
identity/recovery/share/{shareId}       → encrypted recovery share
identity/keystore/{certId}/private      → encrypted private key
```

These patterns must be consistent across all adapters.

### 8. TESTS MUST USE REAL STORAGE

Tests must create a real `MemoryAdapter` or `NodeFsAdapter` and pass it to `LocalIdentityAdapter`. Do not mock StorageAdapter. Do not hardcode cert data.

### 9. ERROR HANDLING IS SPECIFIC

Never throw generic `Error`. Always throw `PlexusError` with specific `code` values:

- `CERT_NOT_FOUND` — cert doesn't exist in storage
- `INVALID_TOKEN` — token parsing failed
- `TOKEN_EXPIRED` — token TTL exceeded
- `INVALID_SIGNATURE` — signature verification failed
- `CERT_REVOKED` — cert is marked revoked
- `INVALID_CHAIN` — cert chain is broken or incomplete
- `SHARE_RECONSTRUCTION_FAILED` — not enough shares or corrupted shares

### 10. DETERMINISM MATTERS

Key derivation must be deterministic. Given the same parent certId, resourceId, and domainFlag, `deriveChild()` must always produce the same child certId and public key. This enables recovery without storing all keys.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify prerequisites are complete

```bash
# IdentityAdapter interface exists
ls packages/protocol-types/src/identity.ts

# StorageAdapter interface exists
ls packages/protocol-types/src/storage.ts

# Capability mappings exist
ls packages/shell/src/capabilities.ts

# Test infrastructure exists
ls packages/__tests__/phase14-gate.test.ts
```

All files must exist. If anything is missing, STOP.

### 0.4 Create Phase 26B branch

```bash
git checkout -b phase-26b-local-identity
```

---

## Step 1: LocalIdentityAdapter (D26B.1)

File: `packages/protocol-types/src/identity-adapters/LocalIdentityAdapter.ts`

Create the main adapter class implementing `IdentityAdapter`:

```typescript
import type { IdentityAdapter, /* other types */ } from '../identity';
import type { StorageAdapter } from '../storage';
import { CertChainStore } from './CertChainStore';
import { CapabilityTokenValidator } from './CapabilityTokenValidator';
import { KeyDerivationService } from './KeyDerivationService';
import { RecoveryShareManager } from './RecoveryShareManager';

export interface LocalIdentityConfig {
  debugLogging?: boolean;
  keyDerivationAlgorithm?: 'brc42'; // extensible for future algorithms
}

export class LocalIdentityAdapter implements IdentityAdapter {
  private certStore: CertChainStore;
  private validator: CapabilityTokenValidator;
  private keyDerivation: KeyDerivationService;
  private recovery: RecoveryShareManager;
  private debugLogging: boolean;

  constructor(storageAdapter: StorageAdapter, config?: LocalIdentityConfig) {
    this.debugLogging = config?.debugLogging ?? false;
    this.certStore = new CertChainStore(storageAdapter);
    this.validator = new CapabilityTokenValidator(this.certStore);
    this.keyDerivation = new KeyDerivationService();
    this.recovery = new RecoveryShareManager(storageAdapter);
  }

  async registerIdentity(email: string): Promise<{
    certId: string;
    publicKey: string;
  }> {
    // 1. Generate root cert (hash-based, deterministic from email)
    // 2. Generate root private key (BRC-42)
    // 3. Store cert in certStore under identity/certs/{certId}
    // 4. Return certId + publicKey
  }

  async deriveChild(parentCertId: string, resourceId: string, domainFlag: number): Promise<{
    certId: string;
    publicKey: string;
    childIndex: number;
  }> {
    // 1. Resolve parent cert from certStore
    // 2. Get next childIndex from certStore (monotonic)
    // 3. Derive child key using BRC-42 (deterministic)
    // 4. Create child cert with parentCertId reference
    // 5. Store child cert in certStore
    // 6. Return certId + publicKey + childIndex
  }

  async resolveIdentity(certId: string): Promise<{
    certId: string;
    publicKey: string;
    email?: string;
    created: number;
    updated: number;
    children?: Array<{ certId: string; childIndex: number; resourceId: string }>;
  }> {
    // 1. Retrieve cert from certStore
    // 2. Return cert metadata
    // 3. Throw PlexusError(CERT_NOT_FOUND) if not found
  }

  async presentCapability(certId: string, domainFlag: number): Promise<{
    valid: boolean;
    reason?: string;
    token?: Uint8Array;
  }> {
    // 1. Check if cert is revoked
    // 2. Check if cert holds domainFlag in its capability token
    // 3. Return { valid: true } or { valid: false, reason: "..." }
    // Must be offline — no remote calls
  }

  async createEdge(initiatorCertId: string, responderCertId: string): Promise<{
    edgeId: string;
    sharedSecret: string;
  }> {
    // 1. Resolve both certs from certStore
    // 2. Derive shared secret using ECDH (or hash-based for offline)
    // 3. Generate edgeId = hash(initiatorCertId + responderCertId)
    // 4. Store edge in certStore
    // 5. Return edgeId + sharedSecret
  }

  async querySubtree(rootCertId: string, depth: number): Promise<{
    root: string;
    children: Array<{
      certId: string;
      childIndex: number;
      resourceId: string;
      grandchildren?: Array<{
        certId: string;
        childIndex: number;
        resourceId: string;
      }>;
    }>;
  }> {
    // 1. Walk cert tree from rootCertId using certStore.walk()
    // 2. Limit traversal to specified depth
    // 3. Return tree structure
  }

  async initiateRecovery(email: string): Promise<{
    sessionId: string;
    challengeCount: number;
    challenges?: Array<{ id: string; prompt: string }>;
  }> {
    // 1. Create recovery session in storage
    // 2. Generate recovery challenges (stored hashes, not plain text)
    // 3. Return sessionId + challengeCount
  }

  async submitChallengeAnswers(
    sessionId: string,
    answers: Array<{ challengeId: string; answer: string }>,
  ): Promise<{
    verified: boolean;
    exportPayload?: string;
  }> {
    // 1. Retrieve session from storage
    // 2. Verify each answer against stored hash
    // 3. If M of N verified, reconstruct master key using RecoveryShareManager
    // 4. Return { verified: true, exportPayload: encrypted_master_key }
  }

  async sendAuthenticated(
    senderCertId: string,
    receiverCertId: string,
    payload: Record<string, string>,
  ): Promise<{ messageId: string }> {
    // 1. Resolve both certs
    // 2. Generate messageId = hash(senderCertId + receiverCertId + timestamp)
    // 3. Log if debugLogging enabled
    // 4. Return messageId
    // Note: Phase 26D will implement actual network transport
  }
}
```

Include JSDoc comments for every method. Include error handling that throws `PlexusError`.

Commit: `phase-26b/D26B.1: LocalIdentityAdapter — offline capability validation from local cert chain`

---

## Step 2: CertChainStore (D26B.2)

File: `packages/protocol-types/src/identity-adapters/CertChainStore.ts`

Manages the local certificate DAG:

```typescript
import type { StorageAdapter } from '../storage';

interface CertData {
  certId: string;
  email?: string;
  publicKey: string;
  parentCertId?: string;
  childIndex?: number;
  resourceId?: string;
  domainFlags: number[];
  created: number;
  revoked: boolean;
}

export class CertChainStore {
  private storage: StorageAdapter;
  private nextChildIndices = new Map<string, number>();

  constructor(storageAdapter: StorageAdapter) {
    this.storage = storageAdapter;
  }

  async put(certId: string, cert: CertData): Promise<void> {
    // 1. Serialize cert to JSON
    // 2. Write to storage at `identity/certs/{certId}`
    // 3. Update nextChildIndices[parentCertId] if this is a child
  }

  async get(certId: string): Promise<CertData | null> {
    // 1. Read from storage at `identity/certs/{certId}`
    // 2. Parse JSON
    // 3. Return cert or null if not found
  }

  async getChildren(parentCertId: string): Promise<CertData[]> {
    // 1. Iterate storage keys under `identity/certs/`
    // 2. Filter for certs with parentCertId === parentCertId
    // 3. Sort by childIndex (ascending)
    // 4. Return array
  }

  async getNextChildIndex(parentCertId: string): Promise<number> {
    // 1. Check in-memory cache
    // 2. If not cached, scan storage for max childIndex under this parent
    // 3. Return max + 1 (or 0 if no children yet)
    // 4. Cache result and increment for next call
  }

  async revokeChild(certId: string): Promise<void> {
    // 1. Retrieve cert
    // 2. Mark revoked: true
    // 3. Write back to storage
    // Note: Index is reserved, never reused
  }

  async walk(
    parentCertId: string,
    visitor: (cert: CertData, depth: number) => Promise<void>,
    maxDepth: number = 3,
  ): Promise<void> {
    // 1. Retrieve parent cert
    // 2. Call visitor(parent, 0)
    // 3. Get children, sort by childIndex
    // 4. Recursively visit each child with depth+1
    // 5. Stop at maxDepth
  }

  async verifyAncestry(certId: string, claimedParentCertId: string): Promise<boolean> {
    // 1. Retrieve cert
    // 2. Check cert.parentCertId === claimedParentCertId
    // 3. Retrieve parent cert
    // 4. Verify signatures (hash-based)
    // 5. Return true if chain is valid, false otherwise
  }
}
```

Commit: `phase-26b/D26B.2: CertChainStore — DAG management with monotonic child indices`

---

## Step 3: CapabilityTokenValidator (D26B.3)

File: `packages/protocol-types/src/identity-adapters/CapabilityTokenValidator.ts`

Parses and validates BRC-108 capability tokens:

```typescript
export interface CapabilityToken {
  issuerCertId: string;
  holderCertId: string;
  domainFlags: number[];
  scope?: string;
  expiry: number; // epoch ms
  conditions?: Record<string, string>;
  signature: Uint8Array;
}

export class CapabilityTokenValidator {
  private certStore: CertChainStore;

  constructor(certStore: CertChainStore) {
    this.certStore = certStore;
  }

  async parseToken(token: Uint8Array): Promise<CapabilityToken> {
    // 1. Deserialize token (JSON or binary)
    // 2. Validate structure
    // 3. Return parsed CapabilityToken
    // 4. Throw PlexusError(INVALID_TOKEN) if malformed
  }

  async validateToken(token: Uint8Array): Promise<{
    valid: boolean;
    reason?: string;
  }> {
    // 1. Parse token
    // 2. Check expiry
    // 3. Verify issuer signature
    // 4. Walk cert chain from issuer to holder
    // 5. Verify chain is complete and unbroken
    // 6. Return { valid: true } or { valid: false, reason: "..." }
  }

  async extractDomainFlags(token: Uint8Array): Promise<number[]> {
    // 1. Parse token
    // 2. Return domainFlags array
  }

  async checkExpiry(token: Uint8Array): Promise<boolean> {
    // 1. Parse token
    // 2. Return token.expiry > Date.now()
  }

  private async validateChainSignature(
    issuerCert: CertData,
    holderCert: CertData,
    signature: Uint8Array,
  ): Promise<boolean> {
    // 1. Hash issuerCert + holderCert
    // 2. Verify signature against issuer's publicKey
    // 3. Return true/false
  }
}
```

Commit: `phase-26b/D26B.3: CapabilityTokenValidator — offline token parsing and validation`

---

## Step 4: KeyDerivationService (D26B.4)

File: `packages/protocol-types/src/identity-adapters/KeyDerivationService.ts`

BRC-42 key derivation:

```typescript
export class KeyDerivationService {
  /**
   * Derive a child key deterministically from parent + index + domainFlag.
   * Uses BRC-42 (BIP-32 style) but hash-based for simplicity.
   * Same inputs always produce the same output.
   */
  async deriveChildKey(
    parentKey: Uint8Array,
    index: number,
    domainFlag: number,
  ): Promise<Uint8Array> {
    // 1. Create HMAC-SHA-512 of (parentKey + index + domainFlag)
    // 2. Return left 32 bytes as child key
    // 3. Must be deterministic
  }

  async derivePath(parentCertId: string, indices: number[], domainFlag: number): Promise<string> {
    // 1. Build path string: "m/" + domainFlag + "'/" + indices.join("/") + "'"
    // 2. Return path
  }

  async deriveSharedSecret(
    localCertId: string,
    remoteCertId: string,
    context: string,
  ): Promise<string> {
    // 1. Hash(localCertId + remoteCertId + context)
    // 2. Return hex digest
  }

  async rotateDomainKey(
    certId: string,
    domainFlag: number,
    rotationIndex: number,
  ): Promise<Uint8Array> {
    // 1. Hash(certId + domainFlag + rotationIndex)
    // 2. Return key
  }
}
```

Commit: `phase-26b/D26B.4: KeyDerivationService — BRC-42 deterministic key derivation`

---

## Step 5: RecoveryShareManager (D26B.5)

File: `packages/protocol-types/src/identity-adapters/RecoveryShareManager.ts`

Shamir secret sharing:

```typescript
export interface RecoveryShare {
  shareId: string;
  shareIndex: number;
  encryptedData: Uint8Array;
  integrity: string; // HMAC for tampering detection
}

export class RecoveryShareManager {
  private storage: StorageAdapter;

  constructor(storageAdapter: StorageAdapter) {
    this.storage = storageAdapter;
  }

  async generateRecoveryShares(
    masterKey: Uint8Array,
    threshold: number,
    totalShares: number,
  ): Promise<RecoveryShare[]> {
    // 1. Split masterKey into totalShares using Shamir secret sharing
    // (Use a library like `secrets.js` if available, or implement basic version)
    // 2. For each share:
    //    - Generate shareId = hash(masterKey + shareIndex)
    //    - Encrypt share using AES-256-GCM
    //    - Add HMAC for integrity
    // 3. Return array of shares (not yet stored)
  }

  async storeRecoveryShare(share: RecoveryShare): Promise<void> {
    // 1. Write encrypted share to storage at `identity/recovery/share/{shareId}`
    // 2. Include integrity HMAC
  }

  async reconstructMasterKey(shares: RecoveryShare[]): Promise<Uint8Array> {
    // 1. Verify integrity of each share (check HMAC)
    // 2. Decrypt each share
    // 3. Combine using Shamir reconstruction
    // 4. Return master key
    // 5. Throw PlexusError(SHARE_RECONSTRUCTION_FAILED) if not enough shares or corruption
  }

  async verifyShareIntegrity(share: RecoveryShare): Promise<boolean> {
    // 1. Recompute HMAC
    // 2. Compare to stored HMAC
    // 3. Return true if match, false otherwise
  }

  async rotateRecoveryShares(
    masterKey: Uint8Array,
    threshold: number,
    totalShares: number,
  ): Promise<RecoveryShare[]> {
    // 1. Generate new shares
    // 2. Delete old shares from storage
    // 3. Store new shares
    // 4. Return new shares
  }
}
```

Commit: `phase-26b/D26B.5: RecoveryShareManager — Shamir secret sharing for key backup`

---

## Step 6: Barrel Export

File: `packages/protocol-types/src/identity-adapters/index.ts`

```typescript
export { LocalIdentityAdapter, type LocalIdentityConfig } from './LocalIdentityAdapter';
export { CertChainStore } from './CertChainStore';
export { CapabilityTokenValidator } from './CapabilityTokenValidator';
export { KeyDerivationService } from './KeyDerivationService';
export { RecoveryShareManager } from './RecoveryShareManager';
```

Update `packages/protocol-types/src/index.ts` to export from `identity-adapters/index.ts`.

Commit: `phase-26b/D26B.6: Barrel exports for identity-adapters package`

---

## Step 7: Gate Tests

Create `packages/__tests__/phase26b-gate.test.ts`.

### Unit Tests: LocalIdentityAdapter (T26B.1–T26B.5)

```typescript
describe('LocalIdentityAdapter', () => {
  let adapter: LocalIdentityAdapter;
  let storage: MemoryAdapter; // or NodeFsAdapter for integration

  beforeEach(() => {
    storage = new MemoryAdapter();
    adapter = new LocalIdentityAdapter(storage);
  });

  it('T26B.1: registerIdentity generates deterministic certId', async () => {
    const { certId, publicKey } = await adapter.registerIdentity('alice@example.com');
    expect(certId).toMatch(/^cert:/);
    expect(publicKey).toContain('BEGIN PUBLIC KEY');

    // Same email should produce same certId
    const again = await adapter.registerIdentity('alice@example.com');
    expect(again.certId).toBe(certId);
  });

  it('T26B.2: resolveIdentity retrieves stored cert', async () => {
    const { certId } = await adapter.registerIdentity('bob@example.com');
    const resolved = await adapter.resolveIdentity(certId);
    expect(resolved.certId).toBe(certId);
    expect(resolved.email).toBe('bob@example.com');
  });

  it('T26B.3: deriveChild enforces monotonic childIndex', async () => {
    const { certId: parent } = await adapter.registerIdentity('alice@example.com');

    const child1 = await adapter.deriveChild(parent, 'resource1', 0x00010002);
    expect(child1.childIndex).toBe(0);

    const child2 = await adapter.deriveChild(parent, 'resource2', 0x00010002);
    expect(child2.childIndex).toBe(1);

    const child3 = await adapter.deriveChild(parent, 'resource3', 0x00010002);
    expect(child3.childIndex).toBe(2);
  });

  it('T26B.4: deriveChild is deterministic', async () => {
    const { certId: parent } = await adapter.registerIdentity('alice@example.com');

    const child1 = await adapter.deriveChild(parent, 'resource1', 0x00010002);
    const child2 = await adapter.deriveChild(parent, 'resource1', 0x00010002);
    expect(child1.certId).toBe(child2.certId);
    expect(child1.publicKey).toBe(child2.publicKey);
  });

  it('T26B.5: revokeChild reserves index', async () => {
    const { certId: parent } = await adapter.registerIdentity('alice@example.com');
    const child1 = await adapter.deriveChild(parent, 'resource1', 0x00010002);

    // Revoke child1
    // (add revoke method to adapter if needed)

    // Next child should get index 1, not 0
    const child2 = await adapter.deriveChild(parent, 'resource2', 0x00010002);
    expect(child2.childIndex).toBe(1);
  });
});
```

### Unit Tests: CertChainStore (T26B.6–T26B.10)

```typescript
describe('CertChainStore', () => {
  // Similar pattern, test put/get, walk, getNextChildIndex, etc.
});
```

### Unit Tests: CapabilityTokenValidator (T26B.11–T26B.15)

```typescript
describe('CapabilityTokenValidator', () => {
  // Test parseToken, validateToken, checkExpiry, etc.
});
```

### Integration Tests (T26B.16–T26B.19)

```typescript
describe('Phase 26B Integration', () => {
  it('T26B.16: Create 3-level hierarchy', async () => {
    // Create root → facet → object cert chain
    // Verify all certs exist in storage
  });

  it('T26B.17: Offline capability validation', async () => {
    // Create cert hierarchy with capability token
    // Validate token without remote service call
    // Measure round-trip time (should be <10ms)
  });

  it('T26B.18: Revocation propagates', async () => {
    // Revoke mid-level cert
    // Verify children cannot present capabilities
  });

  it('T26B.19: Recovery shares end-to-end', async () => {
    // Generate 5 shares, threshold 3
    // Reconstruct from any 3 shares
    // Verify integrity
  });
});
```

### Anti-Injection Test (T26B.20)

```typescript
describe('Anti-injection boundary', () => {
  it('T26B.20: No @plexus imports in identity-adapters', () => {
    const plexusImportsCount = scanForPlexusImports('packages/protocol-types/src/identity-adapters');
    expect(plexusImportsCount).toBe(0);
  });
});
```

Commit: `phase-26b/T26B.1-T26B.20: full gate test suite — unit, integration, anti-injection`

---

## Step 8: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review of every new file
2. Verify monotonic child index survives service restart
3. Verify tokens cannot be replayed
4. Verify revoked certs are properly marked and cannot present capabilities
5. Verify recovery shares are encrypted and cannot be read unencrypted
6. Verify storage key patterns are consistent
7. Verify no hardcoded values or test data in production code
8. Write errata doc as `docs/prd/PHASE-26B-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/protocol-types/src/identity-adapters/LocalIdentityAdapter.ts` complete with all 8 methods
- [ ] `packages/protocol-types/src/identity-adapters/CertChainStore.ts` complete with DAG operations
- [ ] `packages/protocol-types/src/identity-adapters/CapabilityTokenValidator.ts` complete with offline validation
- [ ] `packages/protocol-types/src/identity-adapters/KeyDerivationService.ts` complete with BRC-42 derivation
- [ ] `packages/protocol-types/src/identity-adapters/RecoveryShareManager.ts` complete with Shamir shares
- [ ] `packages/protocol-types/src/identity-adapters/index.ts` barrel export exists
- [ ] Tests T26B.1–T26B.20 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No `@plexus` imports in `identity-adapters/` directory
- [ ] No remote service calls in `presentCapability()`
- [ ] Monotonic child index enforcement verified
- [ ] All commits follow `phase-26b/D26B.N:` naming convention
- [ ] Branch is `phase-26b-local-identity`
- [ ] Errata sprint complete with `docs/prd/PHASE-26B-ERRATA.md`

---

## Next Phases

**Phase 26C**: AnchorAdapter — anchor proofs to BSV blockchain
**Phase 26D**: NetworkAdapter — overlay network composition
**Phase 26E**: Node Bootstrap — assemble all four adapters
