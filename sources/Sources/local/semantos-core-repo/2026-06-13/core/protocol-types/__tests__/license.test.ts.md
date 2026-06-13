---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/license.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.862216+00:00
---

# core/protocol-types/__tests__/license.test.ts

```ts
/**
 * Phase 35B.1 — License primitive tests.
 *
 * Covers:
 *  - encode/decode roundtrip (all fields + optional-field absence)
 *  - decodeLicense rejects malformed bytes
 *  - canonicalLicenseBodyForSigning excludes issuerSig and is deterministic
 *  - licenseCertId format + stability + sensitivity to sig changes
 *  - verifyLicense: signature verifier wiring, expiry, opts.now override
 *  - DEV_ISSUER_PRIVKEY_SEED constant
 *
 * The tests are self-contained — no @bsv/sdk, no runtime/session-protocol.
 * Signature verification is exercised with a mock Verifier that captures
 * inputs, so we assert the license module *calls* the seam correctly.
 * Real ECDSA end-to-end coverage lives in session-protocol gate tests.
 */

import { describe, test, expect } from "bun:test";
import {
  encodeLicense,
  decodeLicense,
  canonicalLicenseBodyForSigning,
  verifyLicense,
  licenseCertId,
  DEV_ISSUER_PRIVKEY_SEED,
  type License,
  type LicenseVerifier,
} from "../src/license";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// Not real keys — the license module never runs ECDSA; it only encodes +
// hands bytes to an injected Verifier. Fixed byte patterns make diffs easy.
const FAKE_HOLDER = new Uint8Array(33).fill(0xab);
const FAKE_ISSUER = new Uint8Array(33).fill(0xcd);
const FAKE_SIG = new Uint8Array(70).fill(0x30);

function makeLicense(overrides: Partial<License> = {}): License {
  return {
    pubkey: FAKE_HOLDER,
    issuer: FAKE_ISSUER,
    issuerSig: FAKE_SIG,
    services: ["session"],
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// encode / decode
// ---------------------------------------------------------------------------

describe("License encode/decode", () => {
  test("roundtrip preserves all fields (full license)", () => {
    const l = makeLicense({
      expiry: 1_800_000_000,
      services: ["session", "media"],
      meta: { tier: "dev", issuedBy: "plexus" },
    });

    const bytes = encodeLicense(l);
    const back = decodeLicense(bytes);

    expect(back.pubkey).toEqual(l.pubkey);
    expect(back.issuer).toEqual(l.issuer);
    expect(back.issuerSig).toEqual(l.issuerSig);
    expect(back.services).toEqual(["session", "media"]);
    expect(back.expiry).toBe(1_800_000_000);
    expect(back.meta).toEqual({ tier: "dev", issuedBy: "plexus" });
  });

  test("roundtrip with optional fields absent", () => {
    const l = makeLicense();
    const back = decodeLicense(encodeLicense(l));

    expect(back.expiry).toBeUndefined();
    expect(back.meta).toBeUndefined();
    expect(back.services).toEqual(["session"]);
  });

  test("decoded pubkey and sig are Uint8Array (not Buffer subclass surprises)", () => {
    const l = makeLicense();
    const back = decodeLicense(encodeLicense(l));

    expect(back.pubkey).toBeInstanceOf(Uint8Array);
    expect(back.issuer).toBeInstanceOf(Uint8Array);
    expect(back.issuerSig).toBeInstanceOf(Uint8Array);
  });

  test("decodeLicense on malformed bytes throws", () => {
    expect(() => decodeLicense(new Uint8Array([0xff, 0xff, 0xff]))).toThrow();
  });

  test("decodeLicense on wrong-arity tuple throws", () => {
    // A 3-element CBOR array is valid CBOR but not a valid License tuple.
    // We encode via the same Encoder to get a well-formed but wrong-shape payload.
    const { Encoder } = require("cbor-x");
    const bogus = new Uint8Array(new Encoder({ useRecords: false }).encode([1, 2, 3]));
    expect(() => decodeLicense(bogus)).toThrow(/malformed/);
  });
});

// ---------------------------------------------------------------------------
// canonicalLicenseBodyForSigning
// ---------------------------------------------------------------------------

describe("canonicalLicenseBodyForSigning", () => {
  test("body bytes identical across different sig values", () => {
    const a = makeLicense({ issuerSig: new Uint8Array([1, 2, 3]) });
    const b = makeLicense({ issuerSig: new Uint8Array([9, 9, 9, 9]) });

    expect(canonicalLicenseBodyForSigning(a)).toEqual(canonicalLicenseBodyForSigning(b));
  });

  test("body bytes differ when services differ", () => {
    const a = makeLicense({ services: ["session"] });
    const b = makeLicense({ services: ["media"] });

    expect(canonicalLicenseBodyForSigning(a)).not.toEqual(canonicalLicenseBodyForSigning(b));
  });

  test("body bytes differ when expiry added vs absent", () => {
    const a = makeLicense();
    const b = makeLicense({ expiry: 1_800_000_000 });

    expect(canonicalLicenseBodyForSigning(a)).not.toEqual(canonicalLicenseBodyForSigning(b));
  });

  test("body bytes deterministic across repeated calls", () => {
    const l = makeLicense({ expiry: 2_000_000_000, meta: { x: 1 } });
    const a = canonicalLicenseBodyForSigning(l);
    const b = canonicalLicenseBodyForSigning(l);
    expect(a).toEqual(b);
  });
});

// ---------------------------------------------------------------------------
// licenseCertId
// ---------------------------------------------------------------------------

describe("licenseCertId", () => {
  test("format is sha256:<64-hex-chars>", () => {
    const id = licenseCertId(makeLicense());
    expect(id).toMatch(/^sha256:[0-9a-f]{64}$/);
  });

  test("stable across calls for same license", () => {
    const l = makeLicense({ expiry: 1_800_000_000 });
    expect(licenseCertId(l)).toBe(licenseCertId(l));
  });

  test("changes when issuerSig changes", () => {
    const a = makeLicense({ issuerSig: new Uint8Array([1]) });
    const b = makeLicense({ issuerSig: new Uint8Array([2]) });
    expect(licenseCertId(a)).not.toBe(licenseCertId(b));
  });

  test("changes when body changes (e.g. services)", () => {
    const a = makeLicense({ services: ["session"] });
    const b = makeLicense({ services: ["media"] });
    expect(licenseCertId(a)).not.toBe(licenseCertId(b));
  });
});

// ---------------------------------------------------------------------------
// verifyLicense
// ---------------------------------------------------------------------------

describe("verifyLicense", () => {
  const okVerifier: LicenseVerifier = {
    async verify() {
      return true;
    },
  };
  const failVerifier: LicenseVerifier = {
    async verify() {
      return false;
    },
  };

  test("calls verifier with (issuer pubkey, body bytes, issuerSig)", async () => {
    let captured: {
      pubkey: Uint8Array;
      bytes: Uint8Array;
      sig: Uint8Array;
    } | null = null;

    const capturingVerifier: LicenseVerifier = {
      async verify(pubkey, bytes, sig) {
        captured = { pubkey, bytes, sig };
        return true;
      },
    };

    const l = makeLicense();
    await verifyLicense(l, capturingVerifier);

    expect(captured).not.toBeNull();
    expect(captured!.pubkey).toEqual(l.issuer);
    expect(captured!.bytes).toEqual(canonicalLicenseBodyForSigning(l));
    expect(captured!.sig).toEqual(l.issuerSig);
  });

  test("ok:true for valid unexpired license", async () => {
    const v = await verifyLicense(makeLicense(), okVerifier);
    expect(v.ok).toBe(true);
  });

  test("ok:false invalid-signature when verifier returns false", async () => {
    const v = await verifyLicense(makeLicense(), failVerifier);
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.reason).toBe("invalid-signature");
  });

  test("ok:false expired when expiry is past", async () => {
    const past = Math.floor(Date.now() / 1000) - 10;
    const v = await verifyLicense(makeLicense({ expiry: past }), okVerifier);
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.reason).toBe("expired");
  });

  test("ok:true when expiry is future", async () => {
    const future = Math.floor(Date.now() / 1000) + 3600;
    const v = await verifyLicense(makeLicense({ expiry: future }), okVerifier);
    expect(v.ok).toBe(true);
  });

  test("opts.now overrides current time for expiry check", async () => {
    const l = makeLicense({ expiry: 999 });
    const v = await verifyLicense(l, okVerifier, { now: 1_000 });
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.reason).toBe("expired");
  });

  test("expired licenses short-circuit before calling verifier", async () => {
    let called = false;
    const tattle: LicenseVerifier = {
      async verify() {
        called = true;
        return true;
      },
    };

    const past = Math.floor(Date.now() / 1000) - 10;
    await verifyLicense(makeLicense({ expiry: past }), tattle);

    expect(called).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Dev-issuer constants
// ---------------------------------------------------------------------------

describe("dev issuer constants", () => {
  test("DEV_ISSUER_PRIVKEY_SEED is the spec literal", () => {
    expect(DEV_ISSUER_PRIVKEY_SEED).toBe("semantos-dev-issuer");
  });
});

```
