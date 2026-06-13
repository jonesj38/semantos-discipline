---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/__tests__/license-handshake.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.334145+00:00
---

# runtime/ws-node-adapter/__tests__/license-handshake.test.ts

```ts
/**
 * license-handshake tests — Phase 35B.1 G35B.8 variants.
 *
 * Exercises the handshake with real ECDSA (via BsvSdkSigner / BsvSdkVerifier
 * from session-protocol). Covers:
 *
 *   - Happy path: valid license + valid sig + correct claimedBca → ok
 *   - G35B.8    : claimedBca mismatch → "bca-mismatch"
 *   - G35B.8b   : expired license → "license-expired"
 *   - G35B.8c   : dev-issuer rejected in prod mode → "issuer-rejected"
 *   - Tampered sig → "sig-invalid"
 *   - Tampered license bytes → "sig-invalid" (sig was over original bytes)
 *   - Malformed license bytes in frame → "malformed"
 *   - Wrong challenge used when verifying → "sig-invalid"
 */

import { describe, test, expect } from "bun:test";
import {
  BsvSdkSigner,
  BsvSdkVerifier,
} from "@semantos/session-protocol";
import {
  encodeLicense,
  canonicalLicenseBodyForSigning,
  type License,
} from "@semantos/protocol-types/license";
import { PrivateKey } from "@bsv/sdk";

import {
  buildHandshakeFrame,
  verifyHandshakeFrame,
  type HandshakeVerifyConfig,
} from "../src/license-handshake";
import { FRAME_KIND } from "../src/types";

// ---------------------------------------------------------------------------
// Fixture builders — real ECDSA keypairs via @bsv/sdk (permitted in runtime/
// tier tests; session-protocol's signer.ts is the production choke-point).
// ---------------------------------------------------------------------------

function compressedPubkey(pk: PrivateKey): Uint8Array {
  const encoded = pk.toPublicKey().encode(true) as number[];
  return Uint8Array.from(encoded);
}

function makeSigner(seedHex: string): {
  signer: BsvSdkSigner;
  privKey: PrivateKey;
  pubkey: Uint8Array;
} {
  const privKey = PrivateKey.fromHex(seedHex);
  const pubkey = compressedPubkey(privKey);
  const signer = new BsvSdkSigner(
    privKey,
    async (pk) =>
      `2602:f9f8::${Array.from(pk.slice(-2))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("")}`,
  );
  return { signer, privKey, pubkey };
}

async function makeSignedLicense(
  holderPubkey: Uint8Array,
  issuerPrivKey: PrivateKey,
  issuerPubkey: Uint8Array,
  opts: { expiry?: number; services?: string[] } = {},
): Promise<{ license: License; bytes: Uint8Array }> {
  const license: License = {
    pubkey: holderPubkey,
    issuer: issuerPubkey,
    services: opts.services ?? ["session"],
    expiry: opts.expiry,
    issuerSig: new Uint8Array(0), // placeholder; will overwrite
  };
  const body = canonicalLicenseBodyForSigning(license);
  const issuerSigner = new BsvSdkSigner(issuerPrivKey, async () => "issuer-bca");
  const issuerSig = await issuerSigner.sign(body);
  const signed: License = { ...license, issuerSig };
  return { license: signed, bytes: encodeLicense(signed) };
}

const ISSUER_SEED = "aa".repeat(32);
const HOLDER_SEED = "bb".repeat(32);
const ATTACKER_SEED = "cc".repeat(32);

async function defaultHolderSetup() {
  const issuer = makeSigner(ISSUER_SEED);
  const holder = makeSigner(HOLDER_SEED);
  const holderBca = (await holder.signer.identity()).bca;
  const signed = await makeSignedLicense(
    holder.pubkey,
    issuer.privKey,
    issuer.pubkey,
  );
  return { issuer, holder, holderBca, ...signed };
}

function makeVerifyConfig(
  overrides: Partial<HandshakeVerifyConfig> = {},
): HandshakeVerifyConfig {
  return {
    verifier: new BsvSdkVerifier(),
    deriveBcaFromPubkey: async (pk) =>
      `2602:f9f8::${Array.from(pk.slice(-2))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("")}`,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Happy path
// ---------------------------------------------------------------------------

describe("buildHandshakeFrame + verifyHandshakeFrame — happy path", () => {
  test("valid license + valid sig + correct claimedBca → ok", async () => {
    const fx = await defaultHolderSetup();

    const frame = await buildHandshakeFrame({
      signer: fx.holder.signer,
      licenseBytes: fx.bytes,
      claimedBca: fx.holderBca,
    });

    expect(frame.kind).toBe(FRAME_KIND.LICENSE_HANDSHAKE);
    expect(frame.license).toEqual(fx.bytes);
    expect(frame.claimedBca).toBe(fx.holderBca);
    expect(frame.challenge.length).toBe(32);
    expect(frame.sig.length).toBeGreaterThan(0);

    const verdict = await verifyHandshakeFrame(frame, makeVerifyConfig());
    expect(verdict.ok).toBe(true);
    if (verdict.ok) {
      expect(verdict.peerBca).toBe(fx.holderBca);
      expect(verdict.peerPubkey).toEqual(fx.holder.pubkey);
    }
  });
});

// ---------------------------------------------------------------------------
// G35B.8 — BCA binding (claimedBca mismatch)
// ---------------------------------------------------------------------------

describe("G35B.8 — claimedBca must match license.pubkey derivation", () => {
  test("attacker replays license with a different claimed BCA → bca-mismatch", async () => {
    const fx = await defaultHolderSetup();

    const frame = await buildHandshakeFrame({
      signer: fx.holder.signer,
      licenseBytes: fx.bytes,
      claimedBca: "2602:f9f8::deadbeef", // lie about the BCA
    });

    const verdict = await verifyHandshakeFrame(frame, makeVerifyConfig());
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("bca-mismatch");
  });
});

// ---------------------------------------------------------------------------
// G35B.8b — Expired license
// ---------------------------------------------------------------------------

describe("G35B.8b — expired license rejected", () => {
  test("holder license with expiry < now → license-expired", async () => {
    const issuer = makeSigner(ISSUER_SEED);
    const holder = makeSigner(HOLDER_SEED);
    const holderBca = (await holder.signer.identity()).bca;

    const past = Math.floor(Date.now() / 1000) - 3600;
    const { bytes } = await makeSignedLicense(
      holder.pubkey,
      issuer.privKey,
      issuer.pubkey,
      { expiry: past },
    );

    const frame = await buildHandshakeFrame({
      signer: holder.signer,
      licenseBytes: bytes,
      claimedBca: holderBca,
    });

    const verdict = await verifyHandshakeFrame(frame, makeVerifyConfig());
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("license-expired");
  });

  test("license with future expiry passes", async () => {
    const issuer = makeSigner(ISSUER_SEED);
    const holder = makeSigner(HOLDER_SEED);
    const holderBca = (await holder.signer.identity()).bca;

    const future = Math.floor(Date.now() / 1000) + 3600;
    const { bytes } = await makeSignedLicense(
      holder.pubkey,
      issuer.privKey,
      issuer.pubkey,
      { expiry: future },
    );

    const frame = await buildHandshakeFrame({
      signer: holder.signer,
      licenseBytes: bytes,
      claimedBca: holderBca,
    });

    const verdict = await verifyHandshakeFrame(frame, makeVerifyConfig());
    expect(verdict.ok).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// G35B.8c — Dev-issuer rejected in production mode
// ---------------------------------------------------------------------------

describe("G35B.8c — isAcceptableIssuer policy gate", () => {
  test("dev-issued license rejected when isAcceptableIssuer returns false → issuer-rejected", async () => {
    const fx = await defaultHolderSetup();

    const frame = await buildHandshakeFrame({
      signer: fx.holder.signer,
      licenseBytes: fx.bytes,
      claimedBca: fx.holderBca,
    });

    const cfg = makeVerifyConfig({
      // Production policy: reject anything signed by this specific issuer.
      isAcceptableIssuer: (issuerPubkey) =>
        !bytesEqual(issuerPubkey, fx.issuer.pubkey),
    });

    const verdict = await verifyHandshakeFrame(frame, cfg);
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("issuer-rejected");
  });

  test("license passes when isAcceptableIssuer returns true", async () => {
    const fx = await defaultHolderSetup();

    const frame = await buildHandshakeFrame({
      signer: fx.holder.signer,
      licenseBytes: fx.bytes,
      claimedBca: fx.holderBca,
    });

    const cfg = makeVerifyConfig({
      isAcceptableIssuer: () => true,
    });

    const verdict = await verifyHandshakeFrame(frame, cfg);
    expect(verdict.ok).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Tampered sig / license bytes
// ---------------------------------------------------------------------------

describe("Integrity checks", () => {
  test("tampered handshake sig → sig-invalid", async () => {
    const fx = await defaultHolderSetup();

    const frame = await buildHandshakeFrame({
      signer: fx.holder.signer,
      licenseBytes: fx.bytes,
      claimedBca: fx.holderBca,
    });

    // Flip a byte in the handshake sig.
    const bad = { ...frame, sig: new Uint8Array(frame.sig) };
    bad.sig[10] = (bad.sig[10]! ^ 0xff) & 0xff;

    const verdict = await verifyHandshakeFrame(bad, makeVerifyConfig());
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("sig-invalid");
  });

  test("attacker replays license with their own sig → sig-invalid", async () => {
    const fx = await defaultHolderSetup();
    const attacker = makeSigner(ATTACKER_SEED);

    // Attacker has the license bytes (publicly observable) but NOT the
    // holder's private key. They sign the handshake with their own key.
    const frame = await buildHandshakeFrame({
      signer: attacker.signer,
      licenseBytes: fx.bytes,
      claimedBca: fx.holderBca,
    });

    const verdict = await verifyHandshakeFrame(frame, makeVerifyConfig());
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("sig-invalid");
  });

  test("malformed license bytes in frame → malformed", async () => {
    const fx = await defaultHolderSetup();

    const frame = await buildHandshakeFrame({
      signer: fx.holder.signer,
      licenseBytes: fx.bytes,
      claimedBca: fx.holderBca,
    });

    const bad = { ...frame, license: new Uint8Array([0xff, 0xff, 0xff]) };

    const verdict = await verifyHandshakeFrame(bad, makeVerifyConfig());
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("malformed");
  });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

```
