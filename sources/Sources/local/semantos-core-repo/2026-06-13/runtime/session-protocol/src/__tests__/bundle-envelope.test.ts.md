---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/__tests__/bundle-envelope.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.046724+00:00
---

# runtime/session-protocol/src/__tests__/bundle-envelope.test.ts

```ts
/**
 * Slice 5a gate — SignedBundle<T> envelope.
 *
 * Exercises the sign/verify roundtrip against the real StubSigner +
 * BsvSdkVerifier pair (both are backed by `@bsv/sdk`'s PrivateKey /
 * PublicKey — this is production-grade secp256k1 ECDSA, not a test
 * double).
 *
 * Gates:
 *   G1  Happy path: sign → verify returns ok:true with payload intact
 *   G2  Canonical JSON is deterministic (sorted-keys independent of
 *       property construction order)
 *   G3  Tampered payload fails with invalid_signature
 *   G4  Tampered signature fails with invalid_signature
 *   G5  Wrong verifier pubkey fails with invalid_signature
 *   G6  Wrong version (v2 wire format) rejected with
 *       unsupported_version
 *   G7  Bad hex in signer.pubkeyHex rejected with
 *       bad_signature_encoding
 *   G8  Wrong pubkey length rejected with pubkey_mismatch
 *   G9  expectedSignerPubkeyHex gate rejects unexpected signer before
 *       the signature-verify call runs
 *   G10 expectedSignerBca gate does the same via BCA
 *   G11 Works for complex payload shapes — nested objects, arrays,
 *       Unicode, boolean flags
 */

import { describe, test, expect } from "bun:test";
import {
  signBundle,
  verifyBundle,
  canonicalJson,
  SIGNED_BUNDLE_VERSION,
  type SignedBundle,
} from "../bundle-envelope.js";
import { StubSigner, BsvSdkVerifier } from "../signer.js";

// Shared signer + verifier — deterministic seed for reproducibility.
const signer = new StubSigner();
const verifier = new BsvSdkVerifier();

// Fixture payload — nested shape that exercises the canonical
// serialisation correctness.
const samplePayload = {
  documentId: "job-42",
  patches: [
    { id: "p1", lexicon: "jural", delta: { body: "tap dripping" } },
    { id: "p2", lexicon: "project-management", delta: { body: "scheduled" } },
  ],
  payload: { type: "maintenance.job", title: "Kitchen tap" },
};

describe("SignedBundle — roundtrip", () => {
  test("G1 — sign then verify → ok:true with payload intact", async () => {
    const signed = await signBundle(samplePayload, signer);
    expect(signed.version).toBe(SIGNED_BUNDLE_VERSION);
    expect(signed.payload).toEqual(samplePayload);
    expect(signed.signer.pubkeyHex.length).toBe(66); // 33 bytes * 2 hex chars
    expect(signed.signature.length).toBeGreaterThan(0);

    const result = await verifyBundle(signed, verifier);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.payload).toEqual(samplePayload);
      expect(result.signer.bca).toBe(signed.signer.bca);
      expect(result.signedAt).toBe(signed.signedAt);
    }
  });

  test("G11 — complex payload (nested, arrays, unicode, booleans) signs + verifies", async () => {
    const payload = {
      zName: "bundle",
      nested: { a: 1, z: { inner: [3, 2, 1] }, b: null },
      unicode: "δ semantos ✓ — ⚙ 日本語",
      bool: true,
      count: 42,
    };
    const signed = await signBundle(payload, signer);
    const result = await verifyBundle(signed, verifier);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.payload).toEqual(payload);
  });
});

describe("canonicalJson — determinism", () => {
  test("G2 — same logical value → identical bytes regardless of key order", () => {
    const a = { z: 1, a: { c: 3, b: 2 }, m: [1, 2, 3] };
    const b = { a: { b: 2, c: 3 }, m: [1, 2, 3], z: 1 };
    expect(canonicalJson(a)).toBe(canonicalJson(b));
  });

  test("G2b — array order preserved (not sorted)", () => {
    expect(canonicalJson([3, 1, 2])).toBe("[3,1,2]");
    expect(canonicalJson([3, 1, 2])).not.toBe(canonicalJson([1, 2, 3]));
  });
});

describe("SignedBundle — tamper detection", () => {
  test("G3 — tampered payload → invalid_signature", async () => {
    const signed = await signBundle(samplePayload, signer);
    const tampered: SignedBundle<typeof samplePayload> = {
      ...signed,
      payload: {
        ...signed.payload,
        // Same shape, different content — changes canonical bytes.
        patches: [
          ...signed.payload.patches,
          { id: "p3-injected", lexicon: "jural", delta: { body: "evil" } },
        ],
      },
    };
    const result = await verifyBundle(tampered, verifier);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("invalid_signature");
  });

  test("G4 — tampered signature → invalid_signature", async () => {
    const signed = await signBundle(samplePayload, signer);
    const corrupted = flipLastByte(signed.signature);
    const tampered: SignedBundle<typeof samplePayload> = {
      ...signed,
      signature: corrupted,
    };
    const result = await verifyBundle(tampered, verifier);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("invalid_signature");
  });

  test("G5 — attacker swaps in their own pubkey → invalid_signature", async () => {
    const signed = await signBundle(samplePayload, signer);
    // Attacker's key. Re-stamp the bundle with their pubkey but the
    // original signature — signature is over a preimage that
    // embedded the ORIGINAL pubkey, so a pubkey swap breaks verify.
    const attackerSigner = new StubSigner("02".repeat(32));
    const attackerIdentity = await attackerSigner.identity();
    const attackerPubkeyHex = Array.from(attackerIdentity.pubkey)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    const tampered: SignedBundle<typeof samplePayload> = {
      ...signed,
      signer: {
        ...signed.signer,
        pubkeyHex: attackerPubkeyHex,
        bca: attackerIdentity.bca,
      },
    };
    const result = await verifyBundle(tampered, verifier);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("invalid_signature");
  });
});

describe("SignedBundle — malformed envelopes", () => {
  test("G6 — unsupported version rejected", async () => {
    const signed = await signBundle(samplePayload, signer);
    const bumped = {
      ...signed,
      version: 2 as unknown as typeof SIGNED_BUNDLE_VERSION,
    };
    const result = await verifyBundle(bumped, verifier);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("unsupported_version");
  });

  test("G7 — non-hex pubkeyHex rejected with bad_signature_encoding", async () => {
    const signed = await signBundle(samplePayload, signer);
    const broken: SignedBundle<typeof samplePayload> = {
      ...signed,
      signer: { ...signed.signer, pubkeyHex: "zzz" },
    };
    const result = await verifyBundle(broken, verifier);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("bad_signature_encoding");
  });

  test("G8 — wrong pubkey length rejected", async () => {
    const signed = await signBundle(samplePayload, signer);
    const broken: SignedBundle<typeof samplePayload> = {
      ...signed,
      signer: { ...signed.signer, pubkeyHex: "abcd" }, // 2 bytes not 33
    };
    const result = await verifyBundle(broken, verifier);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("pubkey_mismatch");
  });
});

describe("SignedBundle — expected-signer gating", () => {
  test("G9 — expectedSignerPubkeyHex mismatch rejected pre-verify", async () => {
    const signed = await signBundle(samplePayload, signer);
    const result = await verifyBundle(signed, verifier, {
      expectedSignerPubkeyHex: "00".repeat(33),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("expected_signer_mismatch");
  });

  test("G9b — expectedSignerPubkeyHex match allows verification through", async () => {
    const signed = await signBundle(samplePayload, signer);
    const result = await verifyBundle(signed, verifier, {
      expectedSignerPubkeyHex: signed.signer.pubkeyHex,
    });
    expect(result.ok).toBe(true);
  });

  test("G10 — expectedSignerBca mismatch rejected", async () => {
    const signed = await signBundle(samplePayload, signer);
    const result = await verifyBundle(signed, verifier, {
      expectedSignerBca: "2602:f9f8::ffff",
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("expected_signer_mismatch");
  });

  test("G10b — expectedSignerBca match allows verification through", async () => {
    const signed = await signBundle(samplePayload, signer);
    const result = await verifyBundle(signed, verifier, {
      expectedSignerBca: signed.signer.bca,
    });
    expect(result.ok).toBe(true);
  });
});

// ── Addressed bundles (Slice 5c) ────────────────────────────────

describe("SignedBundle — addressed bundles (recipient)", () => {
  const RECIPIENT = {
    certId: "rea-cert-ccc333",
    bca: "2602:f9f8::0002",
    pubkeyHex: "02".repeat(33),
  };

  test("G12 — addressed bundle: recipient stamped + surfaced on verify result", async () => {
    const signed = await signBundle(samplePayload, signer, {
      recipient: RECIPIENT,
    });
    expect(signed.recipient).toEqual(RECIPIENT);

    const result = await verifyBundle(signed, verifier);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.recipient).toEqual(RECIPIENT);
  });

  test("G13 — receiver enforces expectedRecipientCertId against addressed bundle", async () => {
    const signed = await signBundle(samplePayload, signer, {
      recipient: RECIPIENT,
    });

    // Expected match → ok
    const match = await verifyBundle(signed, verifier, {
      expectedRecipientCertId: RECIPIENT.certId,
    });
    expect(match.ok).toBe(true);

    // Mismatch → expected_recipient_mismatch
    const miss = await verifyBundle(signed, verifier, {
      expectedRecipientCertId: "different-cert-id",
    });
    expect(miss.ok).toBe(false);
    if (!miss.ok) expect(miss.code).toBe("expected_recipient_mismatch");
  });

  test("G14 — expectedRecipientBca and expectedRecipientPubkeyHex gate the same way", async () => {
    const signed = await signBundle(samplePayload, signer, {
      recipient: RECIPIENT,
    });

    const bcaMatch = await verifyBundle(signed, verifier, {
      expectedRecipientBca: RECIPIENT.bca,
    });
    expect(bcaMatch.ok).toBe(true);

    const pubkeyMiss = await verifyBundle(signed, verifier, {
      expectedRecipientPubkeyHex: "00".repeat(33),
    });
    expect(pubkeyMiss.ok).toBe(false);
    if (!pubkeyMiss.ok)
      expect(pubkeyMiss.code).toBe("expected_recipient_mismatch");
  });

  test("G15 — unaddressed bundle + any expectedRecipient* → unaddressed_bundle", async () => {
    const signed = await signBundle(samplePayload, signer); // no recipient
    const result = await verifyBundle(signed, verifier, {
      expectedRecipientCertId: "someone",
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("unaddressed_bundle");
  });

  test("G16 — requireRecipient:true rejects unaddressed bundles explicitly", async () => {
    const signed = await signBundle(samplePayload, signer);
    const result = await verifyBundle(signed, verifier, {
      requireRecipient: true,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("unaddressed_bundle");
  });

  test("G17 — recipient is part of signed preimage: forger can't bolt one on", async () => {
    // Sender ships a broadcast bundle (no recipient).
    const signed = await signBundle(samplePayload, signer);

    // Attacker-in-the-middle injects a recipient field, hoping the
    // receiver imports it as "addressed to me." This changes the
    // preimage on verify, so the signature should fail.
    const forged = {
      ...signed,
      recipient: {
        certId: "attacker-cert",
        bca: "2602:f9f8::dead",
      },
    };

    const result = await verifyBundle(forged, verifier);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("invalid_signature");
  });

  test("G18 — recipient tamper on addressed bundle → invalid_signature", async () => {
    const signed = await signBundle(samplePayload, signer, {
      recipient: RECIPIENT,
    });

    // Attacker swaps recipient.bca. Original preimage embedded the
    // original recipient, so verification breaks.
    const tampered = {
      ...signed,
      recipient: {
        ...signed.recipient!,
        bca: "2602:f9f8::beef",
      },
    };

    const result = await verifyBundle(tampered, verifier);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("invalid_signature");
  });
});

// ── Helpers ─────────────────────────────────────────────────────

function flipLastByte(hex: string): string {
  const body = hex.slice(0, -2);
  const last = parseInt(hex.slice(-2), 16);
  const flipped = (last ^ 0x01).toString(16).padStart(2, "0");
  return body + flipped;
}

```
