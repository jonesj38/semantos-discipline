---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-31A-PLEXUS-WAB.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.717682+00:00
---

# Phase 31A — Plexus WAB Service (Wallet Application Backend)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week (with 2-day buffer)
**Prerequisites**: Phase 26B complete (LocalIdentityAdapter, offline BRC-108 validation)
**Master document**: `PHASE-31-MOBILE-CLIENT-MASTER.md`
**Branch**: `phase-31a-plexus-wab`

---

## Context

The BSV Browser connects to a WAB (Wallet Application Backend) for identity management. The default WAB at `https://wab.babbage.systems` uses BIP-39 mnemonics — users write down 12 words for backup. This is a non-starter for non-technical users (tradies, property managers, researchers).

Phase 31A builds a Plexus-native WAB service that replaces the Babbage default. Identity setup uses recovery questions instead of seed phrases. Key derivation uses the Plexus cert hierarchy. Recovery uses Shamir slice reassembly via Plexus infrastructure. The BSV Browser connects to this WAB by setting `selectedWabUrl` to the Plexus WAB endpoint.

The WAB must implement the same HTTP protocol the BSV Browser expects — the browser doesn't know or care that the backend is Plexus rather than Babbage. It just calls the WAB endpoints and gets keys, certs, and signatures back.

---

## Source Files / References

| Alias | Path | What to read |
|-------|------|--------------|
| `PLEXUS:TYPES` | `packages/loom/src/plexus/types.ts` | PlexusAdapter interface — registerIdentity, deriveChild, initiateRecovery, submitChallengeAnswers |
| `PLEXUS:STUB` | `packages/loom/src/plexus/stub.ts` | StubPlexusAdapter — reference for deterministic identity creation |
| `IDENTITY:LOCAL` | `packages/protocol-types/src/adapters/local-identity-adapter.ts` | LocalIdentityAdapter — offline BRC-108 validation, CertChainStore |
| `SHELL:CAPS` | `packages/shell/src/capabilities.ts` | CAPABILITY_MAP — domain flag → shell verb mapping |
| `BSV:WALLET` | `bsv-browser/context/WalletContext.tsx` | WalletContext — selectedWabUrl, setPasswordRetriever, setRecoveryKeySaver |
| `BSV:CONFIG` | `bsv-browser/context/config.tsx` | DEFAULT_WAB_URL = 'https://wab.babbage.systems' |
| `POLICY:BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Deliverables

### D31A.1 — WAB HTTP Service Scaffold

**New package**: `packages/plexus-wab/`

HTTP service (Bun or Express) implementing the WAB protocol endpoints:

```typescript
// WAB Protocol Endpoints (matches what BSV Browser expects)
POST /api/v1/identity/create     — Create new Plexus identity from recovery questions
POST /api/v1/identity/restore    — Restore identity from recovery question answers
POST /api/v1/identity/derive     — Derive child key for resource/device
POST /api/v1/keys/public         — Return public key for identity
POST /api/v1/keys/sign           — Sign message with identity key
POST /api/v1/certs/acquire       — Acquire/present capability certificate
POST /api/v1/certs/verify        — Verify certificate validity
POST /api/v1/encrypt             — Encrypt data with recipient's public key
POST /api/v1/decrypt             — Decrypt data with own private key
GET  /api/v1/status              — WAB health check + identity status
```

### D31A.2 — Recovery Question Auth Flow

Replace the BIP-39 mnemonic flow:

```typescript
interface RecoverySetup {
  /** User's email (identity anchor) */
  email: string;
  /** Recovery questions chosen by user */
  questions: Array<{
    id: string;
    question: string;    // "What was your first pet's name?"
    answerHash: string;  // SHA-256(normalize(answer)) — answer never stored plaintext
  }>;
  /** Shamir threshold config */
  shamir: {
    totalSlices: number;     // e.g. 5
    requiredSlices: number;  // e.g. 3
    sliceDistribution: Array<{
      sliceIndex: number;
      storageNode: string;   // Plexus infrastructure node URL
    }>;
  };
}

interface RecoveryChallenge {
  sessionId: string;
  challengeCount: number;
  challenges: Array<{
    id: string;
    prompt: string;     // "What was your first pet's name?"
  }>;
}
```

Setup flow:
1. User provides email + answers to N recovery questions
2. Answers are normalised (lowercase, trim, strip punctuation) and hashed
3. Answer hashes + email derive the root key material via HKDF
4. Root key is used to create Plexus identity (`registerIdentity`)
5. Key material is Shamir-split into slices
6. Slices are distributed to Plexus infrastructure nodes
7. Root key is returned to the BSV Browser for `expo-secure-store` storage

Recovery flow:
1. User provides email → `initiateRecovery(email)` → get challenges
2. User answers challenges → `submitChallengeAnswers(sessionId, answers)`
3. If verified, Plexus reassembles Shamir slices → returns key material
4. Key material stored in `expo-secure-store` on new device

### D31A.3 — Plexus Cert ↔ BSV Key Bridge

Maps between Plexus cert operations and BSV key operations that the browser expects:

```typescript
/**
 * Bridge between Plexus cert hierarchy and BSV key operations.
 *
 * The BSV Browser expects HD-style key derivation.
 * Plexus uses cert-based derivation via deriveChild().
 * This bridge translates between the two models.
 */
interface PlexusBsvBridge {
  /** Derive a BSV-compatible key pair from a Plexus cert */
  deriveKeyForCert(certId: string): { publicKey: string; privateKeyRef: string };

  /** Sign a message using the key associated with a Plexus cert */
  signWithCert(certId: string, message: Uint8Array): Uint8Array;

  /** Present a capability and return it in BSV certificate format (BRC-68) */
  presentAsBrc68(certId: string, capabilityId: string): BRC68Certificate;

  /** Verify a BRC-68 certificate against the Plexus cert chain */
  verifyBrc68(certificate: BRC68Certificate): { valid: boolean; certId: string };
}
```

### D31A.4 — Shamir Slice Distribution Service

Manages distribution and reassembly of key recovery slices:

```typescript
interface SliceDistributor {
  /** Split key material into Shamir slices and distribute to storage nodes */
  distribute(
    keyMaterial: Uint8Array,
    config: ShamirConfig,
  ): Promise<{ distributed: boolean; sliceIds: string[] }>;

  /** Reassemble key material from threshold slices */
  reassemble(
    email: string,
    verifiedAnswers: VerifiedAnswerSet,
  ): Promise<{ keyMaterial: Uint8Array }>;
}
```

### D31A.5 — WAB Integration Tests

```typescript
describe("Plexus WAB Service", () => {
  // T1: Create identity from recovery questions → returns certId + publicKey
  // T2: Restore identity with correct answers → returns same certId
  // T3: Restore identity with wrong answers → rejected
  // T4: Derive child key for resource → returns child certId
  // T5: Sign message → signature verifiable with public key
  // T6: Acquire capability certificate → returns BRC-68 cert
  // T7: Shamir slice distribution → slices stored on N nodes
  // T8: Shamir reassembly with threshold slices → original key recovered
  // T9: Shamir reassembly below threshold → rejected
  // T10: BSV Browser WalletContext can connect with selectedWabUrl pointing to Plexus WAB
});
```

---

## Completion Criteria

- [ ] `packages/plexus-wab/` created with WAB HTTP service
- [ ] All WAB protocol endpoints implemented
- [ ] Recovery question setup flow working
- [ ] Recovery question restore flow working
- [ ] Plexus cert ↔ BSV key bridge working
- [ ] Shamir slice distribution and reassembly working
- [ ] Tests T1–T10 pass
- [ ] BSV Browser can connect to Plexus WAB via `selectedWabUrl`
- [ ] All commits follow `phase-31a/D31A.N:` naming convention
- [ ] Branch is `phase-31a-plexus-wab`

---

## Next Phase

Phase 31B builds the Semantos shell web application that runs in the BSV Browser's WebView, using the Plexus WAB for authentication and CWI for wallet operations.
