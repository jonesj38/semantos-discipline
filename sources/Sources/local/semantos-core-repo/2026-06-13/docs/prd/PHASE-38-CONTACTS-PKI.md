---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-38-CONTACTS-PKI.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.657880+00:00
---

# Phase 38: Contacts Book + Full PKI Flow

**Status**: Design + Implementation  
**Depends on**: Phase 26A (IdentityAdapter), Phase 26B (LocalIdentityAdapter, CertChainStore, CapabilityTokenValidator, KeyDerivationService)

---

## Overview

Two things that belong together: a **contacts book** that maps human-readable identities to cryptographic cert IDs, and a coherent **three-layer PKI** that makes those identities trustworthy.

The contacts book without PKI is just a local address list. PKI without a contacts book is crypto with no UI. Together they form the identity surface for the full Semantos network: "I know Alice (cert: `abc123`), her cert was issued by a root I trust, and I have a shared secret with her that I can use to encrypt messages."

---

## Part 1: Full PKI Flow Design

### The three layers

```
Layer 1 — Cert Issuance (BRC-52 signing)
  Who: Parent cert holder signs child cert with CHILD_CREATION (0x06) domain key
  What: A valid Brc52Cert with a real ECDSA DER signature in cert.signature
  Why: Establishes the identity DAG — every cert traces back to a self-signed root

Layer 2 — Attestation (SPV proofs)
  Who: RaaS Attestation Authority (holds the ATTESTATION (0x05) domain key)
  What: A signed statement that a cert was active at a point in time
  Why: Lets third parties verify identity without trusting the local cert store alone

Layer 3 — Capability Tokens (BRC-108)
  Who: Any cert holder that wants to delegate a permission to another cert
  What: A signed token binding {issuerCertId, holderCertId, domainFlags, expiry}
  Why: Fine-grained, offline-verifiable authorization
```

---

### Layer 1: Cert Issuance

**What we have (Phase 26B):**
- `KeyDerivationService.generateRootKey(email)` — HMAC-SHA-512 from email, not real secp256k1
- `KeyDerivationService.deriveChildKey(parentKey, index, domainFlag)` — HMAC-SHA-512, not BRC-42
- `KeyDerivationService.generatePublicKey(privateKey)` — PEM-format SHA-256 hash, not secp256k1 pubkey
- `identity-registrar.ts` — registers root certs and derives children, produces `CertData` (internal format)
- **NOT produced**: a valid `Brc52Cert.signature` (ECDSA DER hex over the canonical preimage)

**The gap — real BRC-52 issuance:**

A valid BRC-52 cert requires the issuer to produce an ECDSA secp256k1 signature over
`canonicalCertPreimage(childCert)` using their CHILD_CREATION (0x06) domain key:

```
certPreimage  = canonicalCertPreimage(childCert)  // from protocol-types/src/identity.ts
issuerKey     = BRC-42 derivation of parent's root key at domain 0x06
cert.signature = ECDSA_secp256k1_sign(SHA-256(certPreimage), issuerKey) → DER hex
```

**Upgrade path:**
1. Replace `KeyDerivationService.generateRootKey` with `@bsv/sdk PrivateKey.fromRandom()` for new certs, PBKDF2+BRC-42 for recovered certs.
2. Replace `generatePublicKey` with `privateKey.toPublicKey().toString()` (compressed hex).
3. Add `CertIssuer.signChildCert(parentPrivKey, childCert)` → populates `Brc52Cert.signature`.
4. Store the root private key encrypted (AES-256-GCM, passphrase from recovery challenges) in the StorageAdapter under `identity/keys/{certId}.enc`.

**New module**: `core/contact-book/src/cert-issuer.ts`

```ts
interface CertIssuer {
  /**
   * Sign a child BRC-52 cert using the parent's CHILD_CREATION domain key.
   * Returns the cert with cert.signature populated.
   *
   * @param parentCertId — must be registered in the local cert store
   * @param childCert    — all fields except signature (certId already computed)
   */
  issueChildCert(
    parentCertId: string,
    childCert: Omit<Brc52Cert, 'signature'>,
  ): Promise<Brc52Cert>;

  /**
   * Self-sign a root cert. The certifier = subject (self-signed root).
   */
  issueRootCert(
    privateKey: Uint8Array,
    email: string,
  ): Promise<Brc52Cert>;
}
```

**Verification (already partially exists):**
`computeCertId(cert)` in `protocol-types/src/identity.ts` computes the expected cert_id.
Verifying `cert.signature` needs `@bsv/sdk PublicKey.verify(certPreimage, sig)`.

---

### Layer 2: Attestation

**What we have:**
- `AttestationPort` interface in `identity-ports/src/types.ts` — three methods: `proveContinuity`, `proveEdgePresence`, `proveAppPresence`
- Both bindings (stub + vendor-sdk) return `verified: 'stub'` — no real signatures

**What a real attestation looks like:**

The Attestation Authority holds a well-known ATTESTATION (0x05) domain key (`attestorPublicKey`).  
It signs `{certId, kind, generatedAt}` with that key → `SPVAttestation.signature`.  
Any third party can verify by:
1. Resolving the authority's public key (distributed out-of-band or from the RaaS registry)
2. Verifying `ECDSA_verify(SHA-256({certId, kind, generatedAt}), signature, attestorPublicKey)`

**What we need to build:**

**AttestationAuthority** (server-side / authority-controlled):
```ts
class AttestationAuthority {
  constructor(private authorityPrivKey: Uint8Array) {}

  async proveContinuity(certId: string): Promise<SPVAttestation>;
  async proveEdgePresence(certId: string, edgeType: string): Promise<SPVAttestation>;
  async proveAppPresence(certId: string, resourceId: string): Promise<SPVAttestation>;

  // Canonical preimage for a given attestation
  static preimage(certId: string, kind: string, generatedAt: number): Uint8Array;
}
```

**AttestationVerifier** (client-side):
```ts
class AttestationVerifier {
  constructor(private knownAuthorityKeys: string[]) {}

  verify(attestation: SPVAttestation): boolean;
}
```

For Phase 38, we implement `AttestationAuthority` using `@bsv/sdk` ECDSA and wire it into the stub binding's `attestation` port so it returns `verified: 'spv'` when the authority key is present.

**New files:**
- `core/contact-book/src/attestation-authority.ts`
- `core/contact-book/src/attestation-verifier.ts`

---

### Layer 3: Capability Tokens

**What we have (Phase 26B):**
- `CapabilityTokenValidator` in `identity-adapters/` — JSON token with HMAC-SHA-256 signature
- Token format: `{issuerCertId, holderCertId, domainFlags, expiry, signature}`
- Validation: checks expiry, verifies HMAC against issuer's public key hash, walks cert chain

**What the current implementation does right:**
- Offline validation — no network calls
- Cert chain walking (up to depth 10)
- Revocation check
- Constant-time signature comparison

**What needs upgrading:**
- The HMAC key is derived from SHA-256(PEM) — once real secp256k1 pubkeys land, this should be SHA-256(compressed_pubkey_bytes) (still HMAC-SHA-256, just different key material)
- No on-chain anchoring — Phase 38 keeps offline-only; BSV UTXO binding is deferred to Phase 40
- Domain flag semantics — `domainFlags: number[]` needs to align with the domain flag constants in `@semantos/core` (`CHILD_CREATION`, `SIGNING`, `ENCRYPTION`, etc.)

**Action for Phase 38:** Update `CapabilityTokenValidator.validateToken()` to use domain flag constants from `@semantos/core` for semantic validation (e.g., only certs with `SIGNING` flag can issue attestations).

---

### PKI flow: putting it together

```
1. Alice registers:
   → generateRootKey(email) [PBKDF2 + BRC-42 in prod, HMAC stub in dev]
   → issueRootCert(rootPrivKey, email) → Brc52Cert (self-signed)
   → storeEncryptedKey(certId, rootPrivKey) → StorageAdapter

2. Alice derives a child (e.g., her "messaging" hat):
   → deriveChildKey(rootPrivKey, childIndex=0, domainFlag=MESSAGING)
   → issueChildCert(aliceRootCertId, childCert) → Brc52Cert (parent-signed)
   → storeEncryptedKey(childCertId, childPrivKey)

3. Attestation Authority certifies Alice:
   → proveContinuity(aliceRootCertId) → SPVAttestation (authority-signed)
   → Alice includes this in her ContactDiscoveryResult

4. Bob discovers Alice:
   → contactBook.discoverByEmail("alice@example.com")
   → identityPort.resolveIdentity(certId) → IdentityResolution
   → attestationVerifier.verify(alice.attestation) → true
   → contactBook.addContact(alice.certId, "Alice")

5. Bob connects to Alice:
   → contactBook.connectTo(bobCertId, aliceCertId)
   → identityPort.createEdge(bobCertId, aliceCertId) → {edgeId, sharedSecretHash}
   → contact record updated with edgeId + sharedSecretHash

6. Bob sends Alice a message (future):
   → derive session key from sharedSecretHash
   → encrypt payload with session key
   → SignedBundle wraps encrypted payload with BRC-100 headers
```

---

## Part 2: Contacts Book — core/contact-book

### Package design

```
core/contact-book/
├── src/
│   ├── types.ts              — Contact, ContactRecord, EdgeRecord, ContactDiscoveryResult
│   ├── ports.ts              — contactBookPort singleton (Port<ContactBook>)
│   ├── contact-store.ts      — StorageAdapter-backed ContactStore
│   ├── stub-binding.ts       — in-memory stub for tests/demos
│   ├── cert-issuer.ts        — BRC-52 cert signing (Layer 1)
│   ├── attestation-authority.ts — AttestationAuthority (Layer 2)
│   ├── attestation-verifier.ts  — AttestationVerifier (Layer 2)
│   ├── __tests__/
│   │   ├── contact-store.test.ts
│   │   └── attestation.test.ts
│   └── index.ts
├── package.json
└── tsconfig.json
```

### ContactBook interface

```ts
interface ContactBook {
  // ── Local CRUD ──────────────────────────────────────────────────────────
  addContact(certId: string, displayName: string, opts?: AddContactOptions): Promise<Contact>;
  getContact(certId: string): Contact | null;
  listContacts(): Contact[];
  updateContact(certId: string, patch: ContactPatch): Contact;
  removeContact(certId: string): void;
  search(query: string): Contact[];

  // ── DAG discovery ───────────────────────────────────────────────────────
  resolveContact(certId: string): Promise<Contact>;           // fetch from DAG + save locally
  discoverByEmail(email: string): Promise<Contact | null>;    // lookup root cert by email

  // ── Edge establishment ──────────────────────────────────────────────────
  connectTo(myCertId: string, theirCertId: string): Promise<EdgeRecord>;
  isConnected(theirCertId: string): boolean;
  getEdge(theirCertId: string): EdgeRecord | null;
}
```

### Storage layout

All contact data lives under a `contacts/` prefix in the StorageAdapter:

```
contacts/records/{certId}    — serialised ContactRecord (JSON → Uint8Array)
contacts/index/email/{email} — certId (fast email lookup)
contacts/index/name/{name}   — certId[] (name may not be unique)
contacts/edges/{theirCertId} — serialised EdgeRecord
```

### Discovery flow

`discoverByEmail(email)` works by asking `identityPort.resolveIdentity()` after first mapping email → certId via the RaaS registry (when available) or a local index. Phase 38 implements the local-index path; RaaS registry integration is deferred to Phase 39.

---

## Gate criteria

- [ ] `ContactStore` implements full `ContactBook` interface
- [ ] Stub binding implements full `ContactBook` interface
- [ ] `contactBookPort` singleton wired into the port pattern
- [ ] PKI design doc committed to `docs/prd/`
- [ ] `CertIssuer` interface defined in types (implementation: Phase 38B)
- [ ] `AttestationAuthority` interface defined in types (implementation: Phase 38B)
- [ ] Tests: CRUD, search, discovery, edge, stub round-trip
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] No circular imports between `contact-book` and `identity-ports`

---

## Next phases

**Phase 38B** — Wire real secp256k1 (replace HMAC stubs with @bsv/sdk)  
**Phase 39** — RaaS registry discovery (resolve certId by email via network)  
**Phase 40** — BRC-108 on-chain capability UTXO binding  
**Phase 41** — Encrypted messaging using edge shared secret
