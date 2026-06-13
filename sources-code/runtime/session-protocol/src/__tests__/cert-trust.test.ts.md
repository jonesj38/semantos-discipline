---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/__tests__/cert-trust.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.046432+00:00
---

# runtime/session-protocol/src/__tests__/cert-trust.test.ts

```ts
/**
 * Slice 5b gate — KnownCertStore + verifyBundleWithTrust.
 *
 * Builds on Slice 5a's sign/verify primitives. Each test exercises
 * the receiver-side trust layer: given a signed bundle whose signer
 * advertises a `certId`, the receiver consults its KnownCertStore
 * allowlist before committing to the import.
 *
 * Gates:
 *   G1  Known-signer happy path: cert in store, signature valid,
 *       import proceeds and cert record returned in result
 *   G2  Unknown-signer rejection: bundle signed by a real ECDSA key
 *       whose certId is not in the receiver's allowlist
 *   G3  Revoked-cert rejection: cert was in the store, receiver
 *       marked it revoked, subsequent bundles rejected
 *   G4  Pubkey-cert mismatch: bundle claims a certId that's in the
 *       store, but advertises a different pubkey than the cert
 *       records. Catches a signer pretending to own someone else's
 *       cert.
 *   G5  Missing certId rejection (requireCertId: true default):
 *       bundles without certId can't be trust-validated
 *   G6  Missing certId passthrough (requireCertId: false): transitional
 *       flow for pre-cert bundles; signature still verified, no cert
 *       record in the result's `cert.certId` field (empty string)
 *   G7  Allowlist add/revoke round-trip: initially-revoked cert can
 *       be re-added fresh (add overwrites, resetting revoked: false)
 *   G8  list() returns all stored certs including revoked ones
 *   G9  Tampered bundle still fails signature-verify after the trust
 *       checks pass (trust gate doesn't skip signature check)
 */

import { describe, test, expect, beforeAll } from "bun:test";
import { signBundle, type SignedBundle } from "../bundle-envelope.js";
import { StubSigner, BsvSdkVerifier } from "../signer.js";
import {
  createInMemoryKnownCertStore,
  verifyBundleWithTrust,
  type CertRecord,
} from "../cert-trust.js";

// ── Fixtures ────────────────────────────────────────────────────

const ojtSigner = new StubSigner("01".repeat(32));
const reaSigner = new StubSigner("02".repeat(32));
const attackerSigner = new StubSigner("ff".repeat(32));
const verifier = new BsvSdkVerifier();

let ojtPubkeyHex: string;
let reaPubkeyHex: string;
let attackerPubkeyHex: string;

const OJT_CERT_ID = "ojt-cert-aaa111bbb222";
const REA_CERT_ID = "rea-cert-ccc333ddd444";
const ATTACKER_CERT_ID = "attacker-cert-zzz999";

beforeAll(async () => {
  const pk = (id: Awaited<ReturnType<typeof ojtSigner.identity>>) =>
    Array.from(id.pubkey)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
  ojtPubkeyHex = pk(await ojtSigner.identity());
  reaPubkeyHex = pk(await reaSigner.identity());
  attackerPubkeyHex = pk(await attackerSigner.identity());
});

const samplePayload = { documentId: "job-1", patches: [{ id: "p1", body: "hi" }] };

// Signs a bundle + stamps the given certId onto its signer.certId
// field — StubSigner.identity() doesn't set certId by default, so
// we attach it post-sign. In production BsvSdkSigner(cert, ...) wires
// certId into identity() directly.
async function signWithCertId<T>(
  payload: T,
  signer: StubSigner,
  certId: string,
): Promise<SignedBundle<T>> {
  const signed = await signBundle(payload, signer);
  return {
    ...signed,
    signer: { ...signed.signer, certId },
  };
}

// ── Tests ───────────────────────────────────────────────────────

describe("verifyBundleWithTrust — known-signer happy path", () => {
  test("G1 — cert in store + valid signature → ok + resolved cert returned", async () => {
    const store = createInMemoryKnownCertStore([
      {
        certId: OJT_CERT_ID,
        publicKeyHex: ojtPubkeyHex,
        resourceId: "odd-job-todd",
      },
    ]);

    const signed = await signWithCertId(samplePayload, ojtSigner, OJT_CERT_ID);
    const result = await verifyBundleWithTrust(signed, verifier, store);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.payload).toEqual(samplePayload);
    expect(result.cert.certId).toBe(OJT_CERT_ID);
    expect(result.cert.publicKeyHex).toBe(ojtPubkeyHex);
    expect(result.cert.resourceId).toBe("odd-job-todd");
  });
});

describe("verifyBundleWithTrust — attack rejection", () => {
  test("G2 — unknown certId (signer has real ECDSA key but not in allowlist)", async () => {
    const store = createInMemoryKnownCertStore([
      {
        certId: OJT_CERT_ID,
        publicKeyHex: ojtPubkeyHex,
      },
    ]);
    // Attacker has a valid secp256k1 keypair + produces a valid
    // signature — but their certId isn't known to the receiver.
    const signed = await signWithCertId(
      samplePayload,
      attackerSigner,
      ATTACKER_CERT_ID,
    );

    const result = await verifyBundleWithTrust(signed, verifier, store);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("unknown_signer");
      expect(result.message).toContain(ATTACKER_CERT_ID);
    }
  });

  test("G3 — revoked cert rejected even with valid signature", async () => {
    const store = createInMemoryKnownCertStore([
      { certId: OJT_CERT_ID, publicKeyHex: ojtPubkeyHex },
    ]);
    const signed = await signWithCertId(samplePayload, ojtSigner, OJT_CERT_ID);

    // Before revocation — allowed
    const before = await verifyBundleWithTrust(signed, verifier, store);
    expect(before.ok).toBe(true);

    // After revocation — rejected
    await store.revoke(OJT_CERT_ID);
    const after = await verifyBundleWithTrust(signed, verifier, store);
    expect(after.ok).toBe(false);
    if (!after.ok) {
      expect(after.code).toBe("revoked_cert");
      expect(after.message).toContain(OJT_CERT_ID);
    }
  });

  test("G4 — pubkey-cert mismatch: signer claims a cert they don't own", async () => {
    // Receiver has OJT's cert on file (pubkey = ojtPubkeyHex). An
    // attacker signs a bundle with their OWN key but tags it with
    // OJT's certId, trying to look like OJT. Pubkey-cert mismatch
    // catches this before signature verification runs.
    const store = createInMemoryKnownCertStore([
      { certId: OJT_CERT_ID, publicKeyHex: ojtPubkeyHex },
    ]);
    const signedAsAttacker = await signBundle(samplePayload, attackerSigner);
    const impostorBundle: SignedBundle<typeof samplePayload> = {
      ...signedAsAttacker,
      signer: {
        ...signedAsAttacker.signer,
        certId: OJT_CERT_ID,
        // .pubkeyHex is still attackerPubkeyHex — this is the mismatch.
      },
    };

    const result = await verifyBundleWithTrust(impostorBundle, verifier, store);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("pubkey_cert_mismatch");
    }
  });

  test("G5 — missing certId rejected (requireCertId defaults to true)", async () => {
    const store = createInMemoryKnownCertStore([
      { certId: OJT_CERT_ID, publicKeyHex: ojtPubkeyHex },
    ]);
    // signBundle without post-tagging leaves signer.certId undefined.
    const signed = await signBundle(samplePayload, ojtSigner);
    expect(signed.signer.certId).toBeUndefined();

    const result = await verifyBundleWithTrust(signed, verifier, store);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("missing_cert_id");
  });
});

describe("verifyBundleWithTrust — configuration variants", () => {
  test("G6 — requireCertId:false allows bundles without a certId", async () => {
    const store = createInMemoryKnownCertStore([]);
    const signed = await signBundle(samplePayload, ojtSigner);

    const result = await verifyBundleWithTrust(signed, verifier, store, {
      requireCertId: false,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      // Passthrough cert record — certId is empty string
      expect(result.cert.certId).toBe("");
      expect(result.cert.publicKeyHex).toBe(signed.signer.pubkeyHex);
    }
  });

  test("G7 — add after revoke resets the revoked flag", async () => {
    const store = createInMemoryKnownCertStore([
      { certId: OJT_CERT_ID, publicKeyHex: ojtPubkeyHex },
    ]);
    await store.revoke(OJT_CERT_ID);
    const revokedCheck = await store.get(OJT_CERT_ID);
    expect(revokedCheck?.revoked).toBe(true);

    // Re-add with fresh metadata — overwrites, clears revoked
    await store.add({
      certId: OJT_CERT_ID,
      publicKeyHex: ojtPubkeyHex,
      resourceId: "odd-job-todd-v2",
    });
    const fresh = await store.get(OJT_CERT_ID);
    expect(fresh?.revoked).toBeUndefined();
    expect(fresh?.resourceId).toBe("odd-job-todd-v2");

    const signed = await signWithCertId(samplePayload, ojtSigner, OJT_CERT_ID);
    const result = await verifyBundleWithTrust(signed, verifier, store);
    expect(result.ok).toBe(true);
  });

  test("G8 — list() returns all stored certs including revoked ones", async () => {
    const store = createInMemoryKnownCertStore([
      { certId: OJT_CERT_ID, publicKeyHex: ojtPubkeyHex },
      { certId: REA_CERT_ID, publicKeyHex: reaPubkeyHex },
    ]);
    await store.revoke(OJT_CERT_ID);

    const all = await store.list();
    expect(all).toHaveLength(2);
    const byId = Object.fromEntries(all.map((c) => [c.certId, c]));
    expect(byId[OJT_CERT_ID]?.revoked).toBe(true);
    expect(byId[REA_CERT_ID]?.revoked).toBeUndefined();
  });
});

describe("verifyBundleWithTrust — trust + crypto layered correctly", () => {
  test("G9 — trust check passes but tampered signature still fails at verify", async () => {
    const store = createInMemoryKnownCertStore([
      { certId: OJT_CERT_ID, publicKeyHex: ojtPubkeyHex },
    ]);
    const signed = await signWithCertId(samplePayload, ojtSigner, OJT_CERT_ID);

    // Flip last byte of the signature — trust store still has the
    // right cert, but crypto verification must still fail.
    const body = signed.signature.slice(0, -2);
    const last = parseInt(signed.signature.slice(-2), 16);
    const corrupted = body + (last ^ 0x01).toString(16).padStart(2, "0");
    const tampered: SignedBundle<typeof samplePayload> = {
      ...signed,
      signature: corrupted,
    };

    const result = await verifyBundleWithTrust(tampered, verifier, store);
    expect(result.ok).toBe(false);
    // Slice 5a's code, surfaced through the trust layer.
    if (!result.ok) expect(result.code).toBe("invalid_signature");
  });
});

```
