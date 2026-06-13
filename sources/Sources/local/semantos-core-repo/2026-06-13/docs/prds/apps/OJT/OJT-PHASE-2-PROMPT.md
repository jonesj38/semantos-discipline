---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/OJT/OJT-PHASE-2-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.791197+00:00
---

# OJT Phase 2 Execution Prompt — Phone-Number Identity Adapter

> Paste this prompt into a fresh session to execute Phase 2 of the OJT
> migration. Repo: `oddjobtodd`. Branch: `feat/phone-cert-adapter`.
> Prerequisite: Phase 1 merged.

## Context

You are working in the `oddjobtodd` repo. The real Plexus SDK from Dusk
has not shipped yet, but semantos-core has a complete identity story
behind the `CertRecord` interface (`runtime/session-protocol/src/...`).
The Slice 5b `KnownCertStore` accepts any value that assigns
structurally to `CertRecord` — it doesn't care whether the cert came
from the real SDK or a stub.

Phase 2 builds OJT's identity adapter on this stub-cert path:

- A **hardcoded admin cert** for Todd, loaded from environment variables,
  used as the OJT signer for outbound bundles and as the trusted root
  for inbound traffic.
- A **phone-number → CertRecord** function that deterministically derives
  a `certId` and `pubkeyHex` from a tenant's or REA's phone number.
- A **`bootKnownCertStore()`** initializer that pre-loads the admin cert
  plus any pre-registered REA peer certs.

The whole adapter is one module so that when the real Plexus SDK ships,
it can be replaced by deleting one file and re-implementing the same
exported surface.

**Why this matters**: every outbound bundle in P4 is signed by the admin
cert; every inbound bundle is checked against the trust store seeded by
this adapter; every conversation patch in P5 carries a `facet_id` derived
from the user's phone. Without P2, P4 has no signer and P5 has no facet.

---

## CRITICAL: READ THESE FILES FIRST

**Semantos-core side (the interfaces you must satisfy):**
- `/sessions/nifty-bold-sagan/mnt/semantos-core/runtime/session-protocol/src/bundle-envelope.ts`
  — `SignerIdentity`, `RecipientIdentity`, `Signer` interface
  (`identity()` + `sign()`), `BsvSdkSigner`, `StubSigner` (the test
  signer that ships with semantos and produces real ECDSA).
- `/sessions/nifty-bold-sagan/mnt/semantos-core/runtime/session-protocol/src/known-cert-store.ts`
  — `KnownCertStore`, `CertRecord` (the structural shape your phone-cert
  records must assign to), `createInMemoryKnownCertStore`.
- `/sessions/nifty-bold-sagan/mnt/semantos-core/core/plexus-vendor-sdk/src/index.ts`
  — `VendorSDK`, `deriveRootKey`, `computeCertId` (the local mock that
  has the real BRC-42 derivation logic; copy the certId computation
  pattern).
- `/sessions/nifty-bold-sagan/mnt/semantos-core/core/protocol-types/src/adapters/stub-identity-adapter.ts`
  — the canonical stub-adapter pattern; mirror its shape.

**OJT side:**
- `oddjobtodd/.env.local.example` — current env conventions; you will
  add `OJT_ADMIN_CERT_ID`, `OJT_ADMIN_PUBKEY_HEX`, `OJT_ADMIN_PRIVKEY_HEX`,
  `OJT_REA_PEERS_JSON`.
- `oddjobtodd/src/lib/db/index.ts` (or wherever the db client lives) —
  for the future hookup, but DO NOT modify in this phase.
- `oddjobtodd/plexus-core/` — exists on disk but unused. Do NOT import
  from it; the adapter is independent of plexus-core for now.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. THE EXPORTED SURFACE IS THE CONTRACT

These exports must exist with exactly these signatures. The real Plexus
SDK adapter (future) must be a drop-in replacement with the same exports:

```ts
export interface OjtIdentity {
  certId: string;
  pubkeyHex: string;
  privkeyHex: string;          // present only for self (admin / device-keyed users)
  bca: string;
  facetId: string;             // human-readable: 'admin', `tenant:${phone}`, `rea:${phone}`
}

export function loadAdminIdentity(): OjtIdentity;
export function phoneToIdentity(phone: string, role: 'tenant' | 'rea'): OjtIdentity;
export function identityToCertRecord(id: OjtIdentity): CertRecord;
export function createOjtSigner(id: OjtIdentity): Signer;
export function bootKnownCertStore(opts: {
  adminId: OjtIdentity;
  reaPeers?: OjtIdentity[];
}): KnownCertStore;
```

If you find yourself wanting to add an export, stop. The contract is
fixed for SDK-swap compatibility.

### 2. PHONE NORMALISATION IS E.164

All phone strings are normalised to E.164 (`+61412345678`) **before**
hashing. Provide a `normalizePhone(raw: string, defaultCountry = 'AU')`
helper using `libphonenumber-js`. Different normalisations of the same
phone must produce the same `certId`.

### 3. DERIVATION IS DETERMINISTIC

`phoneToIdentity(phone)` must be a pure function: same phone → same
identity, every time, across processes. The `certId` is
`sha256(`ojt:${role}:${normalizedPhone}`)` (hex). The `pubkeyHex` is
derived via secp256k1 key derivation seeded by
`hmac_sha256(masterSeed, `ojt:${role}:${normalizedPhone}`)` where
`masterSeed` comes from env var `OJT_DERIVATION_SEED`.

### 4. PRIVATE KEYS NEVER LEAVE THE SIGNER

`OjtIdentity.privkeyHex` is filled only for the admin. For phone-derived
tenant/REA identities, `privkeyHex` is empty — those parties hold their
own keys (in production), and OJT only knows their pubkeys. Do not
fabricate private keys for users.

### 5. STORE NEVER MUTATED FROM REQUEST HANDLERS

`bootKnownCertStore()` is called once at boot (Phase 4). Request
handlers may call `store.has(certId)` and `store.get(certId)` but never
`store.add()` from inside a request. If a new REA peer needs to be
trusted, that's an admin-only operation done out-of-band (env reload).

### 6. NO PLEXUS-CORE IMPORTS

`oddjobtodd/plexus-core/` is dormant. Do not import from it. This
adapter is a pure stub on top of `@semantos/session-protocol` types.

---

## PART 0: GIT HYGIENE

```bash
cd /sessions/nifty-bold-sagan/mnt/oddjobtodd
git status -u
git log --oneline -5
git checkout main && git pull
git checkout -b feat/phone-cert-adapter
```

Verify Phase 1 is on main:

```bash
ls drizzle/0008_*.sql drizzle/0009_*.sql    # Phase 1 migrations must exist
```

---

## Step 1: Add libphonenumber-js + secp256k1 dependencies (D2.1)

```bash
bun add libphonenumber-js
bun add @noble/secp256k1 @noble/hashes
```

(`@noble/secp256k1` is what semantos-core's `BsvSdkSigner` already uses
internally; check its peer-dep version and match.)

Commit: `feat(ojt-p2/D2.1): add phone normalization + secp256k1 deps`

---

## Step 2: `normalizePhone` + `certIdFromPhone` (D2.2)

File: `src/lib/identity/phone.ts`

```ts
import { parsePhoneNumberWithError, type CountryCode } from 'libphonenumber-js';
import { sha256 } from '@noble/hashes/sha256';
import { bytesToHex } from '@noble/hashes/utils';

export function normalizePhone(raw: string, defaultCountry: CountryCode = 'AU'): string {
  const parsed = parsePhoneNumberWithError(raw, defaultCountry);
  if (!parsed.isValid()) throw new Error(`invalid phone: ${raw}`);
  return parsed.format('E.164');           // '+61412345678'
}

export function certIdFromPhone(phone: string, role: 'tenant' | 'rea'): string {
  const normalized = normalizePhone(phone);
  return bytesToHex(sha256(`ojt:${role}:${normalized}`));
}
```

Test: `tests/identity/phone.test.ts` — three normalisations of the same
number all produce the same certId; invalid numbers throw.

Commit: `feat(ojt-p2/D2.2): phone normalization + deterministic certId`

---

## Step 3: Key derivation from phone (D2.3)

File: `src/lib/identity/derive.ts`

```ts
import { hmac } from '@noble/hashes/hmac';
import { sha256 } from '@noble/hashes/sha256';
import { getPublicKey } from '@noble/secp256k1';
import { bytesToHex } from '@noble/hashes/utils';

export function derivePubkeyHexFromPhone(
  normalizedPhone: string,
  role: 'tenant' | 'rea',
  masterSeed: Uint8Array,
): string {
  // HMAC-SHA256(masterSeed, "ojt:role:phone") → privkey scalar (32 bytes)
  const privkey = hmac(sha256, masterSeed, `ojt:${role}:${normalizedPhone}`);
  const pubkey = getPublicKey(privkey, true); // 33-byte compressed
  return bytesToHex(pubkey);
}
```

The derivation is deterministic given a fixed `masterSeed`. The
`masterSeed` lives in env var `OJT_DERIVATION_SEED` (32 bytes hex). In
production, rotate by issuing a fresh seed and re-deriving for new
users only — old users keep their existing certs.

Test: same phone + same seed → same pubkey, every run.

Commit: `feat(ojt-p2/D2.3): deterministic pubkey derivation from phone + master seed`

---

## Step 4: `OjtIdentity` constructors (D2.4)

File: `src/lib/identity/identity.ts`

```ts
export interface OjtIdentity {
  certId: string;
  pubkeyHex: string;
  privkeyHex: string;          // empty string for non-admin identities
  bca: string;
  facetId: string;
}

export function loadAdminIdentity(): OjtIdentity {
  const certId = required('OJT_ADMIN_CERT_ID');
  const pubkeyHex = required('OJT_ADMIN_PUBKEY_HEX');
  const privkeyHex = required('OJT_ADMIN_PRIVKEY_HEX');
  const bca = process.env.OJT_ADMIN_BCA ?? `::ffff:ojt-admin`;
  return { certId, pubkeyHex, privkeyHex, bca, facetId: 'admin' };
}

export function phoneToIdentity(phone: string, role: 'tenant' | 'rea'): OjtIdentity {
  const normalized = normalizePhone(phone);
  const certId = certIdFromPhone(normalized, role);
  const masterSeed = hexToBytes(required('OJT_DERIVATION_SEED'));
  const pubkeyHex = derivePubkeyHexFromPhone(normalized, role, masterSeed);
  return {
    certId, pubkeyHex,
    privkeyHex: '',                                  // OJT never holds user privkeys
    bca: `::ffff:${role}-${certId.slice(0, 8)}`,
    facetId: `${role}:${normalized}`,
  };
}

function required(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`missing env: ${key}`);
  return v;
}
```

Test: `loadAdminIdentity()` reads the env vars; `phoneToIdentity()`
returns a fully-populated record with empty `privkeyHex`.

Commit: `feat(ojt-p2/D2.4): OjtIdentity constructors for admin + phone-derived users`

---

## Step 5: Bridge to semantos `CertRecord` + `Signer` (D2.5)

File: `src/lib/identity/bridge.ts`

```ts
import type { CertRecord } from '@semantos/session-protocol';
import { StubSigner, type Signer } from '@semantos/session-protocol';

export function identityToCertRecord(id: OjtIdentity): CertRecord {
  return {
    certId: id.certId,
    pubkeyHex: id.pubkeyHex,
    bca: id.bca,
    issuedAt: 0,                                  // pre-Plexus: no real issuance time
    revokedAt: undefined,
    metadata: { facetId: id.facetId },
  };
}

export function createOjtSigner(id: OjtIdentity): Signer {
  if (!id.privkeyHex) {
    throw new Error(`identity ${id.facetId} has no privkey — cannot sign`);
  }
  return new StubSigner(id.privkeyHex);            // real secp256k1 ECDSA via @noble
}
```

The structural assignment to `CertRecord` is the entire point. If
TypeScript complains, the field names or types are wrong — fix them
to match the semantos definition exactly.

Commit: `feat(ojt-p2/D2.5): bridge OjtIdentity → CertRecord + Signer`

---

## Step 6: `bootKnownCertStore()` (D2.6)

File: `src/lib/identity/store.ts`

```ts
import { createInMemoryKnownCertStore, type KnownCertStore } from '@semantos/session-protocol';

export function bootKnownCertStore(opts: {
  adminId: OjtIdentity;
  reaPeers?: OjtIdentity[];
}): KnownCertStore {
  const store = createInMemoryKnownCertStore();
  store.add(identityToCertRecord(opts.adminId));
  for (const peer of opts.reaPeers ?? []) {
    store.add(identityToCertRecord(peer));
  }
  return store;
}

export function loadReaPeersFromEnv(): OjtIdentity[] {
  const json = process.env.OJT_REA_PEERS_JSON;
  if (!json) return [];
  // Format: [{"phone": "+61412345678"}]
  const peers = JSON.parse(json) as Array<{ phone: string }>;
  return peers.map((p) => phoneToIdentity(p.phone, 'rea'));
}
```

Test: boot a store with an admin + two REA peers, assert
`store.has(adminCertId) === true` and `store.has(rea1CertId) === true`.

Commit: `feat(ojt-p2/D2.6): bootKnownCertStore + REA peer loading`

---

## Step 7: Index + `.env.local.example` updates (D2.7)

File: `src/lib/identity/index.ts`

```ts
export * from './phone';
export * from './derive';
export * from './identity';
export * from './bridge';
export * from './store';
```

File: `.env.local.example` — append:

```bash
# OJT identity adapter (Phase 2)
OJT_ADMIN_CERT_ID=         # hex sha256 of your admin handle, 64 chars
OJT_ADMIN_PUBKEY_HEX=      # 33-byte compressed secp256k1 pubkey, 66 chars hex
OJT_ADMIN_PRIVKEY_HEX=     # 32-byte privkey, 64 chars hex — keep secret, never commit
OJT_ADMIN_BCA=             # optional IPv6/BCA for admin
OJT_DERIVATION_SEED=       # 32 bytes hex, master seed for phone-derived keys
OJT_REA_PEERS_JSON=[]      # JSON array of {"phone": "..."} for trusted REA peers
```

Commit: `feat(ojt-p2/D2.7): export surface + env documentation`

---

## Step 8: Drop-in-replaceability test (D2.8)

File: `tests/identity/drop-in-replaceable.test.ts`

The point of this phase is that the real Plexus SDK (when it ships)
must be a drop-in replacement for this adapter. Prove it by writing a
"fake real SDK" mock that exports the same surface and verifying every
test still passes when the import is swapped.

```ts
// tests/identity/drop-in-replaceable.test.ts
// Define a parallel module with the same exported names but a different
// implementation (e.g., always returns deterministic fixtures), and assert
// that the same downstream code (createOjtSigner, identityToCertRecord)
// works against either.
```

This is a structural test, not a runtime test — the goal is to surface
any signature drift early.

Commit: `feat(ojt-p2/D2.8): drop-in-replaceability gate for SDK swap`

---

## Step 9: Full test sweep + PR

```bash
bun test tests/identity/
git push -u origin feat/phone-cert-adapter
gh pr create --title "OJT P2: phone-number identity adapter + admin cert" \
  --body "Hardcoded admin OjtIdentity loaded from env + deterministic phone→CertRecord derivation. Bridges to @semantos/session-protocol StubSigner + KnownCertStore. Drop-in replaceable by real Plexus SDK. 8 gate tests."
```

---

## Gate tests (must pass before PR)

- **G1**: `normalizePhone('0412345678', 'AU')` and
  `normalizePhone('+61412345678')` both return `'+61412345678'`.
- **G2**: `certIdFromPhone(p, 'tenant')` is deterministic across runs.
- **G3**: `derivePubkeyHexFromPhone(p, role, seed)` is deterministic; same
  inputs → same 66-char hex output.
- **G4**: `loadAdminIdentity()` throws if any of the three env vars is
  missing.
- **G5**: `phoneToIdentity()` returns `privkeyHex === ''` (OJT never
  fabricates user privkeys).
- **G6**: `identityToCertRecord(id)` assigns to `CertRecord` (TypeScript
  compile-time check via a `const _: CertRecord = identityToCertRecord(id)`
  pattern).
- **G7**: `bootKnownCertStore({ adminId, reaPeers })` produces a store
  where `store.has()` returns true for every supplied identity.
- **G8**: A `SignedBundle` produced by `createOjtSigner(adminId)` is
  accepted by `verifyBundleWithTrust(bundle, verifier, store)` from
  semantos-core. (This is the round-trip proof.)

## Completion criteria

- All exports listed in rule 1 exist with the exact signatures.
- All 8 gate tests pass.
- `.env.local.example` documents every new env var.
- No imports from `oddjobtodd/plexus-core/`.
- PR open with the body above.

When merged, P3 is the next critical-path phase, but P3 is on
semantos-core (not OJT). P3 may already be running in parallel — check
`feat/http-bundle-transport` on semantos-core.
