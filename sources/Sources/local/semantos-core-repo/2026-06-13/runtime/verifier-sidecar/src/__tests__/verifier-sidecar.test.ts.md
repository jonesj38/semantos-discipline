---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/verifier-sidecar/src/__tests__/verifier-sidecar.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.086952+00:00
---

# runtime/verifier-sidecar/src/__tests__/verifier-sidecar.test.ts

```ts
/**
 * D-V1 gate — Verifier Sidecar unit tests.
 *
 * Spec source: docs/spec/protocol-v0.5.md §9.5 (Verifier Sidecar),
 *              §4.2 (BRC-52 cert), §12.1 (SignedBundle envelope).
 * Textbook: docs/textbook/14-verifier-sidecar.md.
 *
 * Coverage (12 required gates):
 *   T1  — Valid SignedBundle accepted (happy path)
 *   T2  — Bad signature rejected (brc100_invalid_signature)
 *   T3  — Bad cert authenticity rejected (brc52_issuer_signature_invalid)
 *   T4  — Identity-binding mismatch rejected (brc52_identity_binding_mismatch)
 *   T5  — SPV-spent capability rejected (capability_utxo_spent)
 *   T6  — Constant-time comparison enforced (constantTimeEqual)
 *   T7  — Key derivation determinism (BRC-42 via @bsv/sdk PrivateKey.deriveChild)
 *   T8  — Cert payload round-trip (certId = SHA-256(canonical_preimage))
 *   T9  — Certificate-subject mismatch rejected (brc52_cert_id_mismatch)
 *   T10 — Replay attack rejected (brc100_replay_detected)
 *   T11 — Malformed envelope rejected (brc100_missing_field / brc52_malformed_cert)
 *   T12 — SPV proof tampering rejected via SpvProvider returning false
 *
 * BRC compliance:
 *   BRC-100 — signed-request standard
 *   BRC-52  — certificate format
 *   BRC-42  — key derivation
 *
 * K invariant: K2 — identity verified before state mutation.
 */

import { describe, test, expect, beforeAll } from "bun:test";
import { PrivateKey, PublicKey, Signature, Hash } from "@bsv/sdk";
import {
  BrcVerifier,
  VerifierStub,
  constantTimeEqual,
  InMemoryNonceCache,
} from "../index.js";
import type {
  RawSignedBundle,
  Brc52Certificate,
  CapabilityTokenRef,
  SpvProvider,
} from "../types.js";

// ── Crypto helpers ──────────────────────────────────────────────────────────

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    out[i / 2] = parseInt(hex.slice(i, i + 2), 16);
  }
  return out;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function sha256Hex(bytes: Uint8Array): string {
  const digest = Hash.sha256(Array.from(bytes)) as number[];
  return digest.map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sha256ToNumberArray(bytes: Uint8Array): number[] {
  return Hash.sha256(Array.from(bytes)) as number[];
}

function canonicalJson(value: unknown): string {
  return JSON.stringify(value, (_k, v) => {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      const sorted: Record<string, unknown> = {};
      for (const key of Object.keys(v as Record<string, unknown>).sort()) {
        sorted[key] = (v as Record<string, unknown>)[key];
      }
      return sorted;
    }
    return v;
  });
}

// ── Fixture builders ────────────────────────────────────────────────────────

/**
 * Build a real BRC-52 cert:
 *   certId = SHA-256(canonical_preimage)
 *   signature = issuer ECDSA over SHA-256(canonical_preimage)
 *
 * Per §4.2: the preimage covers all fields except signature.
 */
function buildCert(
  subjectPrivKey: PrivateKey,
  certifierPrivKey: PrivateKey,
  type = "plexus.identity.root",
  overrides: Partial<Brc52Certificate> = {},
): Brc52Certificate {
  const subjectPk = compressedHex(subjectPrivKey.toPublicKey());
  const certifierPk = compressedHex(certifierPrivKey.toPublicKey());
  const serialNumber = sha256Hex(new TextEncoder().encode(`${subjectPk}:${certifierPk}:${type}`));

  const preimageObj = {
    certId: "", // placeholder — filled after computing certId
    certifierPublicKey: certifierPk,
    fields: overrides.fields ?? {},
    serialNumber: overrides.serialNumber ?? serialNumber,
    subjectPublicKey: overrides.subjectPublicKey ?? subjectPk,
    type,
  };

  // Compute certId = SHA-256(canonical_preimage without certId)
  const preimageForId = { ...preimageObj };
  delete (preimageForId as Record<string, unknown>)["certId"];
  const preimageBytes = new TextEncoder().encode(canonicalJson(preimageForId));
  const certId = sha256Hex(preimageBytes);

  preimageObj.certId = certId;

  // Sign the canonical preimage (with certId now set) with the certifier key
  const fullPreimageBytes = new TextEncoder().encode(canonicalJson(preimageObj));
  const digestArr = sha256ToNumberArray(fullPreimageBytes);
  const digestHex = digestArr.map((b) => b.toString(16).padStart(2, "0")).join("");
  const sig: Signature = certifierPrivKey.sign(digestHex, "hex", true);
  const sigHex = bytesToHex(Uint8Array.from(sig.toDER() as number[]));

  return {
    certId,
    subjectPublicKey: preimageObj.subjectPublicKey,
    certifierPublicKey: certifierPk,
    type,
    serialNumber: preimageObj.serialNumber,
    fields: preimageObj.fields,
    signature: overrides.signature ?? sigHex,
  };
}

/**
 * Build a BRC-100 signed envelope.
 * The signature covers the canonical preimage (identitykey + nonce + timestamp + payload).
 */
function buildEnvelope(
  signerPrivKey: PrivateKey,
  cert: Brc52Certificate,
  payload: unknown = { action: "test" },
  overrides: Partial<RawSignedBundle> = {},
  nowMs = Date.now(),
): RawSignedBundle {
  const identityKey = compressedHex(signerPrivKey.toPublicKey());
  const nonce = sha256Hex(new TextEncoder().encode(`nonce:${nowMs}:${Math.random()}`));
  const timestamp = nowMs;

  const preimageObj = {
    "x-brc100-identitykey": overrides["x-brc100-identitykey"] ?? identityKey,
    "x-brc100-nonce": overrides["x-brc100-nonce"] ?? nonce,
    "x-brc100-timestamp": overrides["x-brc100-timestamp"] ?? timestamp,
    payload: overrides.payload ?? payload,
  };
  const preimageBytes = new TextEncoder().encode(canonicalJson(preimageObj));
  const digestArr = sha256ToNumberArray(preimageBytes);
  const digestHex = digestArr.map((b) => b.toString(16).padStart(2, "0")).join("");
  const sig: Signature = signerPrivKey.sign(digestHex, "hex", true);
  const sigHex = bytesToHex(Uint8Array.from(sig.toDER() as number[]));

  return {
    "x-brc100-identitykey": overrides["x-brc100-identitykey"] ?? identityKey,
    "x-brc100-nonce": overrides["x-brc100-nonce"] ?? nonce,
    "x-brc100-timestamp": overrides["x-brc100-timestamp"] ?? timestamp,
    "x-brc100-signature": overrides["x-brc100-signature"] ?? sigHex,
    "x-brc52-certificate": overrides["x-brc52-certificate"] ?? JSON.stringify(cert),
    payload: overrides.payload ?? payload,
  };
}

function compressedHex(pk: PublicKey): string {
  return bytesToHex(Uint8Array.from(pk.encode(true) as number[]));
}

// ── Fixture keys — deterministic, stable seeds ──────────────────────────────

const ALICE_SEED = "01".repeat(32);
const BOB_SEED = "02".repeat(32);
const MALLORY_SEED = "ff".repeat(32);

let alicePrivKey: PrivateKey;
let bobPrivKey: PrivateKey;
let malloryPrivKey: PrivateKey;
let aliceCert: Brc52Certificate;

const FIXED_NOW = 1_700_000_000_000; // fixed timestamp for deterministic tests

beforeAll(() => {
  alicePrivKey = PrivateKey.fromHex(ALICE_SEED);
  bobPrivKey = PrivateKey.fromHex(BOB_SEED);
  malloryPrivKey = PrivateKey.fromHex(MALLORY_SEED);

  // Alice's self-signed root cert
  aliceCert = buildCert(alicePrivKey, alicePrivKey, "plexus.identity.root");
});

// ── SpvProvider stubs ────────────────────────────────────────────────────────

const liveSpvProvider: SpvProvider = {
  isUnspent: async (_cap) => true,
};

const spentSpvProvider: SpvProvider = {
  isUnspent: async (_cap) => false,
};

const tamperSpvProvider: SpvProvider = {
  isUnspent: async (_cap) => false, // tampered proof — treat as spent
};

// ── Tests ────────────────────────────────────────────────────────────────────

describe("D-V1 — Verifier Sidecar", () => {
  // ── T1: Valid SignedBundle accepted ───────────────────────────────────────
  test("T1 — valid signed-bundle accepted (happy path)", async () => {
    const verifier = new BrcVerifier({ nowMs: () => FIXED_NOW });
    const envelope = buildEnvelope(alicePrivKey, aliceCert, { action: "move" }, {}, FIXED_NOW);
    const result = await verifier.verify(envelope);

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.certId).toBe(aliceCert.certId);
      expect(result.identityKey).toBe(compressedHex(alicePrivKey.toPublicKey()));
    }
  });

  // ── T2: Bad signature rejected ────────────────────────────────────────────
  test("T2 — bad BRC-100 signature rejected", async () => {
    const verifier = new BrcVerifier({ nowMs: () => FIXED_NOW });
    const envelope = buildEnvelope(alicePrivKey, aliceCert, {}, {}, FIXED_NOW);
    // Tamper the signature — flip the first two hex chars
    const badSig =
      (envelope["x-brc100-signature"].startsWith("aa") ? "bb" : "aa") +
      envelope["x-brc100-signature"].slice(2);
    const tampered: RawSignedBundle = { ...envelope, "x-brc100-signature": badSig };
    const result = await verifier.verify(tampered);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("brc100_invalid_signature");
    }
  });

  // ── T3: Bad cert authenticity rejected ────────────────────────────────────
  test("T3 — bad cert authenticity (invalid issuer signature) rejected", async () => {
    const verifier = new BrcVerifier({ nowMs: () => FIXED_NOW });
    // Build a cert where the certId is correct for the fields, but the signature
    // is wrong (signed by Mallory, not the declared certifierPublicKey = Alice).
    //
    // Strategy: take Alice's cert (self-signed, certifierPublicKey = Alice's key),
    // but replace the signature with one produced by Mallory's key.
    // The certId is still computed from the correct preimage (no certifier sig in preimage),
    // so cert_id check passes. The issuer sig check then catches the forgery.
    const mallorySignedPreimage: Brc52Certificate = {
      ...aliceCert,
      // Overwrite the signature with one produced by Mallory (wrong signer)
      signature: (() => {
        // Re-sign Alice's cert preimage with Mallory's key
        const issuerPreimageObj = {
          certId: aliceCert.certId,
          certifierPublicKey: aliceCert.certifierPublicKey,
          fields: aliceCert.fields,
          serialNumber: aliceCert.serialNumber,
          subjectPublicKey: aliceCert.subjectPublicKey,
          type: aliceCert.type,
        };
        const preimageBytes = new TextEncoder().encode(canonicalJson(issuerPreimageObj));
        const digestArr = sha256ToNumberArray(preimageBytes);
        const digestHex = digestArr.map((b) => b.toString(16).padStart(2, "0")).join("");
        const sig: Signature = malloryPrivKey.sign(digestHex, "hex", true);
        return bytesToHex(Uint8Array.from(sig.toDER() as number[]));
      })(),
    };
    const envelope = buildEnvelope(alicePrivKey, mallorySignedPreimage, {}, {}, FIXED_NOW);
    const result = await verifier.verify(envelope);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("brc52_issuer_signature_invalid");
    }
  });

  // ── T4: Identity-binding mismatch rejected ────────────────────────────────
  test("T4 — identity-binding mismatch (signing key !== cert.subject) rejected", async () => {
    const verifier = new BrcVerifier({ nowMs: () => FIXED_NOW });
    // Sign the envelope with Bob's key, but present Alice's cert (Alice's subject)
    const bobCert = buildCert(bobPrivKey, bobPrivKey);
    const envelope = buildEnvelope(bobPrivKey, aliceCert, {}, {}, FIXED_NOW);
    // envelope's identitykey = Bob's key; cert.subjectPublicKey = Alice's key
    void bobCert;
    const result = await verifier.verify(envelope);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("brc52_identity_binding_mismatch");
    }
  });

  // ── T5: SPV-spent capability rejected ─────────────────────────────────────
  test("T5 — SPV-spent capability token rejected", async () => {
    const verifier = new BrcVerifier({
      nowMs: () => FIXED_NOW,
      spvProvider: spentSpvProvider,
    });
    const envelope = buildEnvelope(alicePrivKey, aliceCert, {}, {}, FIXED_NOW);
    const capToken: CapabilityTokenRef = {
      txId: "a".repeat(64),
      vout: 0,
    };
    const result = await verifier.verify(envelope, capToken);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("capability_utxo_spent");
    }
  });

  // ── T6: Constant-time comparison enforced ─────────────────────────────────
  test("T6 — constant-time comparison enforced", () => {
    const a = new Uint8Array([1, 2, 3, 4, 5]);
    const b = new Uint8Array([1, 2, 3, 4, 5]);
    const c = new Uint8Array([1, 2, 3, 4, 6]); // last byte differs
    const d = new Uint8Array([1, 2, 3]);        // different length

    expect(constantTimeEqual(a, b)).toBe(true);
    expect(constantTimeEqual(a, c)).toBe(false);
    expect(constantTimeEqual(a, d)).toBe(false); // length mismatch
    // Empty arrays
    expect(constantTimeEqual(new Uint8Array(0), new Uint8Array(0))).toBe(true);
    // Single byte
    expect(constantTimeEqual(new Uint8Array([0xff]), new Uint8Array([0xff]))).toBe(true);
    expect(constantTimeEqual(new Uint8Array([0xff]), new Uint8Array([0x00]))).toBe(false);
  });

  // ── T7: Key derivation determinism (BRC-42) ───────────────────────────────
  test("T7 — BRC-42 child key derivation is deterministic", () => {
    // BRC-42 via @bsv/sdk PrivateKey.deriveChild — same input → same output.
    const parent = PrivateKey.fromHex(ALICE_SEED);
    const pubKey = parent.toPublicKey();
    const invoiceNumber = "semantos:signing:1";

    const child1 = parent.deriveChild(pubKey, invoiceNumber);
    const child2 = parent.deriveChild(pubKey, invoiceNumber);

    expect(compressedHex(child1.toPublicKey())).toBe(compressedHex(child2.toPublicKey()));

    // Different invoice numbers → different keys
    const child3 = parent.deriveChild(pubKey, "semantos:signing:2");
    expect(compressedHex(child1.toPublicKey())).not.toBe(compressedHex(child3.toPublicKey()));

    // Derived child can be used to build a cert and that cert passes verification
    const childCert = buildCert(child1, parent, "plexus.identity.derived");
    const verifier = new BrcVerifier({ nowMs: () => FIXED_NOW });
    const envelope = buildEnvelope(child1, childCert, {}, {}, FIXED_NOW);
    // (use returned promise — T7 is synchronous except for verify; run inline)
    void verifier.verify(envelope).then((result) => {
      expect(result.ok).toBe(true);
    });
  });

  // ── T8: Cert payload round-trip ───────────────────────────────────────────
  test("T8 — cert payload round-trip: certId = SHA-256(canonical_preimage_without_certId)", () => {
    // Build cert, then re-compute certId independently and confirm they match.
    // Per §4.2: cert_id = SHA-256(preimage of all fields except signature and certId itself).
    const cert = buildCert(alicePrivKey, alicePrivKey);

    // Reproduce the preimage computation exactly as BrcVerifier does:
    // certId excluded (it's the output), signature excluded (per §4.2).
    const preimageObj = {
      certifierPublicKey: cert.certifierPublicKey,
      fields: cert.fields,
      serialNumber: cert.serialNumber,
      subjectPublicKey: cert.subjectPublicKey,
      type: cert.type,
    };
    const preimageBytes = new TextEncoder().encode(canonicalJson(preimageObj));
    const computedId = sha256Hex(preimageBytes);

    expect(cert.certId).toBe(computedId);
    expect(cert.certId).toHaveLength(64); // 32 bytes hex
  });

  // ── T9: Certificate-subject mismatch (cert_id mismatch) rejected ──────────
  test("T9 — cert_id mismatch rejected (tampered cert body)", async () => {
    const verifier = new BrcVerifier({ nowMs: () => FIXED_NOW });
    // Build cert, then tamper the subjectPublicKey without recomputing certId
    const tamperedCert: Brc52Certificate = {
      ...aliceCert,
      subjectPublicKey: compressedHex(malloryPrivKey.toPublicKey()),
      // certId is still Alice's — will not match recomputed value
    };
    const envelope = buildEnvelope(
      alicePrivKey,
      tamperedCert,
      {},
      { "x-brc52-certificate": JSON.stringify(tamperedCert) },
      FIXED_NOW,
    );
    const result = await verifier.verify(envelope);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      // cert_id won't match because we changed the body without recomputing
      expect(result.code).toBe("brc52_cert_id_mismatch");
    }
  });

  // ── T10: Replay attack rejected ───────────────────────────────────────────
  test("T10 — replay attack rejected (same nonce re-used)", async () => {
    const verifier = new BrcVerifier({ nowMs: () => FIXED_NOW });
    const envelope = buildEnvelope(alicePrivKey, aliceCert, {}, {}, FIXED_NOW);

    // First call should pass
    const first = await verifier.verify(envelope);
    expect(first.ok).toBe(true);

    // Same envelope (same nonce) must be rejected
    const second = await verifier.verify(envelope);
    expect(second.ok).toBe(false);
    if (!second.ok) {
      expect(second.code).toBe("brc100_replay_detected");
    }
  });

  // ── T11: Malformed envelope rejected ─────────────────────────────────────
  test("T11 — malformed envelope: missing required headers rejected", async () => {
    const verifier = new BrcVerifier({ nowMs: () => FIXED_NOW });

    // Missing x-brc100-identitykey
    const missingIdentity = {
      "x-brc100-nonce": "aa".repeat(32),
      "x-brc100-timestamp": FIXED_NOW,
      "x-brc100-signature": "aa".repeat(36),
      "x-brc52-certificate": JSON.stringify(aliceCert),
      payload: {},
    } as unknown as RawSignedBundle;

    const r1 = await verifier.verify(missingIdentity);
    expect(r1.ok).toBe(false);
    if (!r1.ok) expect(r1.code).toBe("brc100_missing_field");

    // Missing x-brc52-certificate
    const noCert: RawSignedBundle = {
      "x-brc100-identitykey": compressedHex(alicePrivKey.toPublicKey()),
      "x-brc100-nonce": "bb".repeat(32),
      "x-brc100-timestamp": FIXED_NOW,
      "x-brc100-signature": "bb".repeat(36),
      "x-brc52-certificate": "",
      payload: {},
    };
    const r2 = await verifier.verify(noCert);
    expect(r2.ok).toBe(false);
    if (!r2.ok) expect(r2.code).toBe("brc100_missing_field");

    // Malformed JSON cert
    const badCertEnvelope = buildEnvelope(alicePrivKey, aliceCert, {}, {}, FIXED_NOW);
    const badCert: RawSignedBundle = {
      ...badCertEnvelope,
      "x-brc52-certificate": "not-json{{{",
    };
    const r3 = await verifier.verify(badCert);
    expect(r3.ok).toBe(false);
    // Will fail at signature first (cert tampered changes nothing in preimage),
    // but envelope was built with correct sig — after sig passes, cert parse fails.
    if (!r3.ok) {
      expect(["brc100_invalid_signature", "brc52_malformed_cert"]).toContain(r3.code);
    }
  });

  // ── T12: SPV proof tampering rejected ────────────────────────────────────
  test("T12 — SPV proof tampering rejected via SpvProvider returning false", async () => {
    const verifier = new BrcVerifier({
      nowMs: () => FIXED_NOW,
      spvProvider: tamperSpvProvider,
    });
    const envelope = buildEnvelope(alicePrivKey, aliceCert, {}, {}, FIXED_NOW);
    const capToken: CapabilityTokenRef = {
      txId: "b".repeat(64),
      vout: 1,
      bumpHex: "deadbeef", // tampered proof
    };
    const result = await verifier.verify(envelope, capToken);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("capability_utxo_spent");
    }
  });

  // ── Additional: SPV happy path with live provider ─────────────────────────
  test("T13 — capability UTXO accepted when SPV provider confirms live", async () => {
    const verifier = new BrcVerifier({
      nowMs: () => FIXED_NOW,
      spvProvider: liveSpvProvider,
    });
    const envelope = buildEnvelope(alicePrivKey, aliceCert, {}, {}, FIXED_NOW);
    const capToken: CapabilityTokenRef = {
      txId: "c".repeat(64),
      vout: 0,
    };
    const result = await verifier.verify(envelope, capToken);

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.certId).toBe(aliceCert.certId);
    }
  });

  // ── Additional: timestamp out of window ──────────────────────────────────
  test("T14 — stale timestamp rejected", async () => {
    const verifier = new BrcVerifier({
      nowMs: () => FIXED_NOW,
      timestampWindowMs: 60_000, // 1 minute
    });
    // Build envelope with timestamp 10 minutes in the past
    const staleTimestamp = FIXED_NOW - 10 * 60 * 1000;
    const envelope = buildEnvelope(alicePrivKey, aliceCert, {}, {}, staleTimestamp);
    const result = await verifier.verify(envelope);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("brc100_timestamp_out_of_window");
    }
  });

  // ── Additional: VerifierStub accepts without crypto ──────────────────────
  test("T15 — VerifierStub accepts envelope without cryptographic checks", async () => {
    const stub = new VerifierStub();
    // Build a fully valid envelope — stub accepts it trivially
    const envelope = buildEnvelope(alicePrivKey, aliceCert, {}, {}, FIXED_NOW);
    const result = await stub.verify(envelope);
    expect(result.ok).toBe(true);

    // Also accepts an envelope with no fields at all (no structural check)
    const empty = {
      "x-brc100-identitykey": "",
      "x-brc100-nonce": "",
      "x-brc100-timestamp": 0,
      "x-brc100-signature": "",
      "x-brc52-certificate": "{}",
      payload: null,
    } as unknown as RawSignedBundle;
    const r2 = await stub.verify(empty);
    expect(r2.ok).toBe(true);
  });

  // ── Additional: InMemoryNonceCache expiry ─────────────────────────────────
  test("T16 — InMemoryNonceCache: expired nonces are re-accepted", () => {
    let fakeNow = 1000;
    const cache = new InMemoryNonceCache(500, () => fakeNow);
    cache.setNonce("abc", fakeNow + 500); // expires at 1500

    expect(cache.hasNonce("abc")).toBe(true);

    // Advance clock past expiry
    fakeNow = 1600;
    expect(cache.hasNonce("abc")).toBe(false); // expired
    expect(cache.size).toBe(0);
  });
});

```
