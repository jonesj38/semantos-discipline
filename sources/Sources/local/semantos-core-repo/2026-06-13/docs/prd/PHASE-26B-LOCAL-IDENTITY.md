---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-26B-LOCAL-IDENTITY.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.704886+00:00
---

# Phase 26B: Local Identity Adapter — Offline Capability Validation

**Duration**: 1 week

**Prerequisites**: Phase 26A complete (IdentityAdapter extracted to protocol-types)

**Branch**: `phase-26b-local-identity`

**Master document**: `SEMANTOS_ZIG_WASM_PRD.md`

---

## Context

Phase 26A extracted the `IdentityAdapter` interface to `protocol-types/src/identity.ts`. Now Phase 26B implements `LocalIdentityAdapter` — the critical piece for standalone node operation.

A standalone Semantos node must validate capability tokens **offline** from a local certificate chain, without calling a remote Plexus service. This is essential for:

- **VPS tradie nodes** ($10/month) with intermittent internet
- **Enterprise sovereignty nodes** in restricted networks
- **Disaster recovery** — node operates even if Plexus service is unavailable
- **Audit trail** — every token validation is logged locally

The LocalIdentityAdapter:
1. Stores a certificate chain in StorageAdapter under `identity/` prefix
2. Validates BRC-108 capability tokens by walking the local cert chain
3. Performs all validation offline — no network round-trips
4. Implements BRC-42 key derivation for deterministic child cert generation
5. Manages Shamir recovery shares for key backup

---

## Deliverables

### D26B.1: LocalIdentityAdapter Implementation

File: `packages/protocol-types/src/identity-adapters/LocalIdentityAdapter.ts`

Implements `IdentityAdapter` interface with:

- Constructor: `LocalIdentityAdapter(storageAdapter: StorageAdapter, config?: LocalIdentityConfig)`
- `registerIdentity(email: string)` — generate root cert, store in storage
- `deriveChild(parentCertId, resourceId, domainFlag)` — BRC-42 key derivation with monotonic indices
- `resolveIdentity(certId)` — retrieve cert from storage, return cert metadata
- `presentCapability(certId, domainFlag)` — validate capability token offline
- `createEdge(initiatorCertId, responderCertId)` — create authenticated edge with shared secret
- `querySubtree(rootCertId, depth)` — walk cert DAG in storage
- `initiateRecovery(email)` — start recovery flow with stored challenges
- `submitChallengeAnswers(sessionId, answers)` — verify against stored hashes
- `sendAuthenticated(senderCertId, receiverCertId, payload)` — log authenticated message
- Error handling: throw `PlexusError` with `recoverable: true/false` as appropriate

**Key constraint**: All cert chain walks and token validation must use only the local StorageAdapter. No network calls. No Plexus RaaS dependencies.

### D26B.2: CertChainStore

File: `packages/protocol-types/src/identity-adapters/CertChainStore.ts`

Manages the local certificate DAG:

- `put(certId, cert)` — store cert in storage under `identity/certs/{certId}`
- `get(certId)` — retrieve cert from storage, parse, cache in memory
- `walk(parentCertId, visitor)` — depth-first traversal of children
- `getChildren(parentCertId)` — list all direct children with monotonic indices
- `getNextChildIndex(parentCertId)` — return next available index (always increments)
- `verifyAncestry(certId, parentCertId)` — verify cert chain via Merkle hashes
- `revokeChild(certId)` — mark cert as revoked (reserves index, doesn't delete)

**Key constraint**: Child indices are **monotonic per parent**. Once index N is assigned, it is never reused, even if the child is deleted or revoked.

### D26B.3: CapabilityTokenValidator

File: `packages/protocol-types/src/identity-adapters/CapabilityTokenValidator.ts`

Parses and validates BRC-108 capability tokens:

- `parseToken(token: Uint8Array)` — deserialize to `{issuerCert, holderCert, domainFlags, scope, expiry, conditions}`
- `validateToken(token, localCertStore)` — check:
  - Issuer signature is valid
  - Cert chain from issuer to holder is complete and unbroken
  - Token is not expired
  - Domain flags match the requested capability
  - Conditions (if any) are satisfied
- `extractDomainFlags(token)` — return the set of domain flags in the token
- `checkExpiry(token)` — true if token is not expired
- `validateChainSignature(issuerCert, holderCert, signature)` — verify signature chain

**Key constraint**: Offline-first. All validation from local cert store. No remote certificate lookup.

### D26B.4: KeyDerivationService

File: `packages/protocol-types/src/identity-adapters/KeyDerivationService.ts`

BRC-42 key derivation for deterministic child key generation:

- `deriveChildKey(parentKey, index, domainFlag)` — deterministic ED25519 key from parent + index
- `derivePath(parentCertId, indices)` — path derivation: `"m/" + domainFlag + "'/" + index + "'"`
- `deriveSharedSecret(localCertId, remoteCertId, context)` — ECDH for edge creation
- `rotateDomainKey(certId, domainFlag, rotationIndex)` — derive key for key rotation

All derivation is **deterministic**: same inputs always produce the same keys. Hardware key storage is optional (future).

### D26B.5: Recovery Share Management

File: `packages/protocol-types/src/identity-adapters/RecoveryShareManager.ts`

Shamir secret sharing for key backup:

- `generateRecoveryShares(masterKey, threshold, shares)` — split master key into N shares (M-of-N scheme)
- `storeRecoveryShare(shareId, encryptedShare, storageAdapter)` — store share in `identity/recovery/{shareId}`
- `reconstructMasterKey(shares)` — reconstruct master key from M shares
- `verifyShareIntegrity(share)` — check share hasn't been tampered with
- `rotateRecoveryShares(masterKey)` — generate new shares if old ones are compromised

Shares are AES-256-GCM encrypted before storage. The share encryption key is derived from the user's recovery challenges.

---

## TDD Gate: 20+ Tests

All tests in `packages/__tests__/phase26b-gate.test.ts`.

### Unit Tests: LocalIdentityAdapter (T26B.1–T26B.5)

```typescript
// T26B.1: registerIdentity generates root cert, stores in storage/identity/certs/{certId}
// T26B.2: resolveIdentity retrieves cert from storage, returns full metadata
// T26B.3: deriveChild enforces monotonic childIndex (0, 1, 2, ... never reuses)
// T26B.4: deriveChild with same parent+resourceId+domainFlag produces same certId (determinism)
// T26B.5: revokeChild marks cert as revoked, reserves index, next child gets next index
```

### Unit Tests: CertChainStore (T26B.6–T26B.10)

```typescript
// T26B.6: put/get round-trip cert in storage
// T26B.7: walk returns children in order of childIndex
// T26B.8: getNextChildIndex returns monotonically increasing value
// T26B.9: revokeChild marks revoked but doesn't allow reuse of index
// T26B.10: verifyAncestry validates Merkle chain from child to parent
```

### Unit Tests: CapabilityTokenValidator (T26B.11–T26B.15)

```typescript
// T26B.11: parseToken deserializes BRC-108 token
// T26B.12: validateToken checks issuer signature
// T26B.13: validateToken rejects expired tokens
// T26B.14: validateToken rejects tokens with domain flags not held by holder
// T26B.15: validateToken accepts valid token with matching cert chain
```

### Integration Tests (T26B.16–T26B.19)

```typescript
// T26B.16: Create 3-level cert hierarchy (root → facet → object), validate all certs exist
// T26B.17: Validate capability token at depth 2 without remote service call
// T26B.18: Revoke a mid-level cert, verify revocation propagates to children
// T26B.19: Recovery shares: generate, store, reconstruct master key from M of N shares
```

### Anti-Injection Tests (T26B.20)

```typescript
// T26B.20: No Plexus RaaS imports outside identity-adapters directory
//   → Scan all .ts files for @plexus imports (should be zero in this phase)
```

---

## What NOT to Do

- **Don't call any remote service from `presentCapability()`**. All validation must be offline.
- **Don't store private keys unencrypted**. Use AES-256-GCM for key storage.
- **Don't skip cert chain validation**. Every token must have a complete verified chain.
- **Don't allow reuse of child indices**. Monotonic enforcement is non-negotiable.
- **Don't allow capability tokens without valid issuer signatures**. Signature verification is mandatory.
- **Don't hardcode recovery challenges**. Challenges come from configuration or user input.

---

## File Structure

```
packages/protocol-types/src/identity-adapters/
├── LocalIdentityAdapter.ts         (D26B.1)
├── CertChainStore.ts               (D26B.2)
├── CapabilityTokenValidator.ts     (D26B.3)
├── KeyDerivationService.ts         (D26B.4)
├── RecoveryShareManager.ts         (D26B.5)
└── index.ts                        (barrel export)
```

Also update:
- `packages/protocol-types/src/identity.ts` — extend IdentityAdapter with recovery-related methods if needed
- `packages/protocol-types/src/index.ts` — export all adapters

---

## Gate Criteria (All Must Pass)

- [ ] `LocalIdentityAdapter` implements full `IdentityAdapter` interface
- [ ] All cert operations use StorageAdapter exclusively (no Plexus RaaS)
- [ ] Child index enforcement: monotonic per parent, never reused
- [ ] Capability token validation works offline with local cert chain
- [ ] Recovery shares: generate, store, reconstruct from M of N
- [ ] Tests T26B.1–T26B.20 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] No `@plexus` imports in identity-adapters (Phase 26A IdentityAdapter is in protocol-types)
- [ ] All commits follow `phase-26b/D26B.N:` naming convention
- [ ] Branch is `phase-26b-local-identity`

---

## Completion Checklist

- [ ] `LocalIdentityAdapter` complete with all 8 methods
- [ ] `CertChainStore` complete with DAG operations
- [ ] `CapabilityTokenValidator` complete with offline parsing/validation
- [ ] `KeyDerivationService` complete with BRC-42 derivation
- [ ] `RecoveryShareManager` complete with Shamir secret sharing
- [ ] Barrel export `identity-adapters/index.ts` created
- [ ] Tests T26B.1–T26B.20 all passing
- [ ] StorageAdapter integration verified (no hardcoded storage keys)
- [ ] Monotonic child index enforcement verified
- [ ] Recovery flow end-to-end tested

---

## Next Phases

**Phase 26C**: AnchorAdapter — anchor proofs to BSV blockchain
**Phase 26D**: NetworkAdapter — overlay network composition
**Phase 26E**: Node Bootstrap — assemble all four adapters into a deployable node
