---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/__tests__/license-policy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.305073+00:00
---

# runtime/node/__tests__/license-policy.test.ts

```ts
/**
 * license-policy tests — boot-time license enforcement.
 */

import { describe, test, expect } from "bun:test";
import { writeFile, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PrivateKey } from "@bsv/sdk";
import { BsvSdkSigner } from "@semantos/session-protocol";
import {
  encodeLicense,
  canonicalLicenseBodyForSigning,
  type License,
} from "@semantos/protocol-types/license";

import {
  deriveDevIssuer,
  isDevIssuedLicense,
  loadLicenseFromDisk,
  validateLicenseForBoot,
} from "../src/license-policy";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function compressedPubkey(pk: PrivateKey): Uint8Array {
  return Uint8Array.from(pk.toPublicKey().encode(true) as number[]);
}

async function mintLicense(opts: {
  issuerPrivKey: PrivateKey;
  issuerPubkey: Uint8Array;
  holderPubkey: Uint8Array;
  expiry?: number;
}): Promise<{ license: License; bytes: Uint8Array }> {
  const license: License = {
    pubkey: opts.holderPubkey,
    issuer: opts.issuerPubkey,
    services: ["session"],
    expiry: opts.expiry,
    issuerSig: new Uint8Array(0),
  };
  const body = canonicalLicenseBodyForSigning(license);
  const signer = new BsvSdkSigner(opts.issuerPrivKey, async () => "issuer-bca");
  const issuerSig = await signer.sign(body);
  const signed: License = { ...license, issuerSig };
  return { license: signed, bytes: encodeLicense(signed) };
}

// ---------------------------------------------------------------------------
// deriveDevIssuer / isDevIssuedLicense
// ---------------------------------------------------------------------------

describe("deriveDevIssuer", () => {
  test("is deterministic — same keypair every call", () => {
    const a = deriveDevIssuer();
    const b = deriveDevIssuer();
    expect(a.privKeyHex).toBe(b.privKeyHex);
    expect(a.pubkey).toEqual(b.pubkey);
  });

  test("derives a 33-byte compressed pubkey", () => {
    const dev = deriveDevIssuer();
    expect(dev.pubkey.length).toBe(33);
  });

  test("privKeyHex is 64 hex chars", () => {
    const dev = deriveDevIssuer();
    expect(dev.privKeyHex).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("isDevIssuedLicense", () => {
  test("true for dev-issuer-signed license", async () => {
    const dev = deriveDevIssuer();
    const holder = PrivateKey.fromHex("11".repeat(32));
    const { license } = await mintLicense({
      issuerPrivKey: dev.privKey,
      issuerPubkey: dev.pubkey,
      holderPubkey: compressedPubkey(holder),
    });
    expect(isDevIssuedLicense(license)).toBe(true);
  });

  test("false for a different issuer", async () => {
    const otherIssuer = PrivateKey.fromHex("22".repeat(32));
    const holder = PrivateKey.fromHex("11".repeat(32));
    const { license } = await mintLicense({
      issuerPrivKey: otherIssuer,
      issuerPubkey: compressedPubkey(otherIssuer),
      holderPubkey: compressedPubkey(holder),
    });
    expect(isDevIssuedLicense(license)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// loadLicenseFromDisk
// ---------------------------------------------------------------------------

describe("loadLicenseFromDisk", () => {
  test("reads + decodes a license written to disk", async () => {
    const dev = deriveDevIssuer();
    const holder = PrivateKey.fromHex("33".repeat(32));
    const { bytes } = await mintLicense({
      issuerPrivKey: dev.privKey,
      issuerPubkey: dev.pubkey,
      holderPubkey: compressedPubkey(holder),
    });

    const dir = await mkdtemp(join(tmpdir(), "license-"));
    const path = join(dir, "node.license");
    await writeFile(path, bytes);

    const { license, bytes: back } = await loadLicenseFromDisk(path);
    expect(license.pubkey).toEqual(compressedPubkey(holder));
    expect(back).toEqual(bytes);
  });

  test("throws a descriptive error on missing file", async () => {
    await expect(
      loadLicenseFromDisk("/definitely/not/a/real/path.license"),
    ).rejects.toThrow(/cannot read file/);
  });

  test("throws on malformed bytes", async () => {
    const dir = await mkdtemp(join(tmpdir(), "license-"));
    const path = join(dir, "garbage");
    await writeFile(path, new Uint8Array([0xff, 0xff, 0xff]));
    await expect(loadLicenseFromDisk(path)).rejects.toThrow(/malformed/);
  });
});

// ---------------------------------------------------------------------------
// validateLicenseForBoot
// ---------------------------------------------------------------------------

describe("validateLicenseForBoot", () => {
  test("valid non-dev license passes regardless of dev mode", async () => {
    const issuer = PrivateKey.fromHex("aa".repeat(32));
    const holder = PrivateKey.fromHex("bb".repeat(32));
    const { license } = await mintLicense({
      issuerPrivKey: issuer,
      issuerPubkey: compressedPubkey(issuer),
      holderPubkey: compressedPubkey(holder),
    });

    const v1 = await validateLicenseForBoot(license, { devMode: false });
    const v2 = await validateLicenseForBoot(license, { devMode: true });
    expect(v1.ok).toBe(true);
    expect(v2.ok).toBe(true);
    if (v1.ok) expect(v1.devIssued).toBe(false);
  });

  test("dev-issued license in non-dev mode → dev-issuer-rejected", async () => {
    const dev = deriveDevIssuer();
    const holder = PrivateKey.fromHex("cc".repeat(32));
    const { license } = await mintLicense({
      issuerPrivKey: dev.privKey,
      issuerPubkey: dev.pubkey,
      holderPubkey: compressedPubkey(holder),
    });

    const v = await validateLicenseForBoot(license, { devMode: false });
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.reason).toBe("dev-issuer-rejected");
  });

  test("dev-issued license in dev mode → ok with devIssued:true", async () => {
    const dev = deriveDevIssuer();
    const holder = PrivateKey.fromHex("dd".repeat(32));
    const { license } = await mintLicense({
      issuerPrivKey: dev.privKey,
      issuerPubkey: dev.pubkey,
      holderPubkey: compressedPubkey(holder),
    });

    const v = await validateLicenseForBoot(license, { devMode: true });
    expect(v.ok).toBe(true);
    if (v.ok) expect(v.devIssued).toBe(true);
  });

  test("expired license → expired regardless of dev mode", async () => {
    const dev = deriveDevIssuer();
    const holder = PrivateKey.fromHex("ee".repeat(32));
    const past = Math.floor(Date.now() / 1000) - 3600;
    const { license } = await mintLicense({
      issuerPrivKey: dev.privKey,
      issuerPubkey: dev.pubkey,
      holderPubkey: compressedPubkey(holder),
      expiry: past,
    });

    const v = await validateLicenseForBoot(license, { devMode: true });
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.reason).toBe("expired");
  });

  test("explicit devMode:false overrides SEMANTOS_DEV_MODE=1 env", async () => {
    const dev = deriveDevIssuer();
    const holder = PrivateKey.fromHex("f1".repeat(32));
    const { license } = await mintLicense({
      issuerPrivKey: dev.privKey,
      issuerPubkey: dev.pubkey,
      holderPubkey: compressedPubkey(holder),
    });

    const v = await validateLicenseForBoot(license, {
      devMode: false,
      env: { SEMANTOS_DEV_MODE: "1" },
    });
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.reason).toBe("dev-issuer-rejected");
  });

  test("SEMANTOS_DEV_MODE=1 env unlocks dev licenses when devMode undefined", async () => {
    const dev = deriveDevIssuer();
    const holder = PrivateKey.fromHex("f2".repeat(32));
    const { license } = await mintLicense({
      issuerPrivKey: dev.privKey,
      issuerPubkey: dev.pubkey,
      holderPubkey: compressedPubkey(holder),
    });

    const v = await validateLicenseForBoot(license, {
      env: { SEMANTOS_DEV_MODE: "1" },
    });
    expect(v.ok).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// NL-1 — node cap-UTXO authorization layer (SELLABLE-NODE-LICENSE.md N3
// "Layer"). Verbatim reuse of the proven BRC-108 K15 path; additive &
// non-breaking over the signed-License identity layer above.
// ---------------------------------------------------------------------------

import {
  CapabilityTokenValidator,
  MonotoneSpendOracle,
  PERMISSION_GRANT_DERIVATION,
} from "@semantos/protocol-types";
import type { CertChainStore, CertData } from "@semantos/protocol-types";
import { verifyNodeCapAuthorization } from "../src/license-policy";

const NODE_PUBKEY = "-----BEGIN PUBLIC KEY-----\nNODE-OWNER\n-----END PUBLIC KEY-----";
const PAGE = 0x00010101; // ODDJOBZ page base | 0x01 — a registered capability page
const NL_TXID = "f".repeat(64);
const NL_SIGNING_KEY = new Uint8Array(32).fill(9);

const nlHolder: CertData = {
  certId: "node-owner-1",
  publicKey: NODE_PUBKEY,
  domainFlags: [],
  created: 0,
  revoked: false,
};
function nlStore(): CertChainStore {
  return { get: async (id: string) => (id === "node-owner-1" ? nlHolder : null) } as unknown as CertChainStore;
}
const nlAlive = { verifyBeef: async () => true, verifyBump: async () => true };
function nlToken(v: CapabilityTokenValidator, vout = 0): Uint8Array {
  return v.createBrc108Token(
    {
      outpoint: { txid: NL_TXID, vout },
      issuerCertId: "issuer-1",
      holderCertId: "node-owner-1",
      domainFlag: PAGE,
      issuerDerivationDomain: PERMISSION_GRANT_DERIVATION,
      expiry: Date.now() + 60_000,
    },
    NL_SIGNING_KEY,
  );
}

describe("NL-1 node cap-UTXO authorization (layered over signed-License)", () => {
  test("not configured ⇒ no-op pass (configured:false; non-breaking Phase-35B)", async () => {
    const v = new CapabilityTokenValidator(nlStore());
    const r = await verifyNodeCapAuthorization({
      validator: v,
      nodePubKey: NODE_PUBKEY,
      nodeParticipationDomainFlag: PAGE,
      // capLicenseOutpointRef omitted
    });
    expect(r.authorized).toBe(true);
    if (r.authorized) expect(r.configured).toBe(false);
  });

  test("configured + unspent + holder-bound + page-scoped ⇒ authorized", async () => {
    const v = new CapabilityTokenValidator(nlStore());
    const r = await verifyNodeCapAuthorization({
      validator: v,
      licenseToken: nlToken(v),
      nodePubKey: NODE_PUBKEY,
      nodeParticipationDomainFlag: PAGE,
      spv: new MonotoneSpendOracle().spvContext(nlAlive, "beef"),
      capLicenseOutpointRef: `${NL_TXID}:0`,
    });
    expect(r.authorized).toBe(true);
    if (r.authorized) expect(r.configured).toBe(true);
  });

  test("K15b: spent node-license UTXO ⇒ unauthorized (kill switch)", async () => {
    const v = new CapabilityTokenValidator(nlStore());
    const oracle = new MonotoneSpendOracle();
    oracle.markSpent({ txid: NL_TXID, vout: 0 });
    const r = await verifyNodeCapAuthorization({
      validator: v,
      licenseToken: nlToken(v),
      nodePubKey: NODE_PUBKEY,
      nodeParticipationDomainFlag: PAGE,
      spv: oracle.spvContext(nlAlive, "beef"),
      capLicenseOutpointRef: `${NL_TXID}:0`,
    });
    expect(r.authorized).toBe(false);
    if (!r.authorized) expect(r.reason).toContain("K15");
  });

  test("binding: token outpoint ≠ configured ref ⇒ unauthorized", async () => {
    const v = new CapabilityTokenValidator(nlStore());
    const r = await verifyNodeCapAuthorization({
      validator: v,
      licenseToken: nlToken(v, 0),
      nodePubKey: NODE_PUBKEY,
      nodeParticipationDomainFlag: PAGE,
      spv: new MonotoneSpendOracle().spvContext(nlAlive, "beef"),
      capLicenseOutpointRef: `${NL_TXID}:9`,
    });
    expect(r.authorized).toBe(false);
  });

  test("configured but no token ⇒ unauthorized", async () => {
    const v = new CapabilityTokenValidator(nlStore());
    const r = await verifyNodeCapAuthorization({
      validator: v,
      nodePubKey: NODE_PUBKEY,
      nodeParticipationDomainFlag: PAGE,
      capLicenseOutpointRef: `${NL_TXID}:0`,
    });
    expect(r.authorized).toBe(false);
  });

  test("K15d: wrong node pubkey (≠ holder subject) ⇒ unauthorized", async () => {
    const v = new CapabilityTokenValidator(nlStore());
    const r = await verifyNodeCapAuthorization({
      validator: v,
      licenseToken: nlToken(v),
      nodePubKey: "-----BEGIN PUBLIC KEY-----\nWRONG\n-----END PUBLIC KEY-----",
      nodeParticipationDomainFlag: PAGE,
      spv: new MonotoneSpendOracle().spvContext(nlAlive, "beef"),
      capLicenseOutpointRef: `${NL_TXID}:0`,
    });
    expect(r.authorized).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// NL-1 boot helper — evaluateNodeCapAuthorizationFromConfig.
// Todd decision: holder == config.nodeCert, resolved via
// new CertChainStore(config.storage). K15d binds the kill-switch to the
// genuine owner cert.
// ---------------------------------------------------------------------------

import { MemoryAdapter, CertChainStore as CCS } from "@semantos/protocol-types";
import { evaluateNodeCapAuthorizationFromConfig } from "../src/license-policy";

const OWNER_CERT_ID = "node-owner-cert-1";

async function seededAdapter(): Promise<MemoryAdapter> {
  const adapter = new MemoryAdapter();
  const store = new CCS(adapter);
  await store.put(OWNER_CERT_ID, {
    certId: OWNER_CERT_ID,
    publicKey: NODE_PUBKEY,
    domainFlags: [],
    created: 0,
    revoked: false,
  } as any);
  return adapter;
}
function ownerToken(v: CapabilityTokenValidator, vout = 0): Uint8Array {
  return v.createBrc108Token(
    {
      outpoint: { txid: NL_TXID, vout },
      issuerCertId: "issuer-1",
      holderCertId: OWNER_CERT_ID, // == config.nodeCert (K15d binds owner)
      domainFlag: PAGE,
      issuerDerivationDomain: PERMISSION_GRANT_DERIVATION,
      expiry: Date.now() + 60_000,
    },
    NL_SIGNING_KEY,
  );
}

describe("NL-1 evaluateNodeCapAuthorizationFromConfig (owner-cert binding)", () => {
  test("not configured ⇒ no-op pass (Phase-35B preserved)", async () => {
    const r = await evaluateNodeCapAuthorizationFromConfig({
      nodeCert: OWNER_CERT_ID,
      storage: await seededAdapter(),
      license: {},
    });
    expect(r.authorized).toBe(true);
    if (r.authorized) expect(r.configured).toBe(false);
  });

  test("owner cert missing ⇒ unauthorized (K15d holder unbindable)", async () => {
    const r = await evaluateNodeCapAuthorizationFromConfig({
      nodeCert: "no-such-owner",
      storage: new MemoryAdapter(),
      license: { capLicenseOutpointRef: `${NL_TXID}:0`, nodeParticipationDomainFlag: PAGE },
    });
    expect(r.authorized).toBe(false);
    if (!r.authorized) expect(r.reason).toContain("owner cert");
  });

  test("configured + owner-held unspent cap-UTXO ⇒ authorized (federation enabled)", async () => {
    const adapter = await seededAdapter();
    const v = new CapabilityTokenValidator(new CCS(adapter));
    // token bytes provided via a tmp file (capLicenseTokenPath)
    const dir = await mkdtemp(join(tmpdir(), "nl1-"));
    const tokPath = join(dir, "node-license.tok");
    await writeFile(tokPath, ownerToken(v));
    const r = await evaluateNodeCapAuthorizationFromConfig(
      {
        nodeCert: OWNER_CERT_ID,
        storage: adapter,
        license: {
          capLicenseOutpointRef: `${NL_TXID}:0`,
          capLicenseTokenPath: tokPath,
          nodeParticipationDomainFlag: PAGE,
        },
      },
      { spv: new MonotoneSpendOracle().spvContext(nlAlive, "beef") },
    );
    expect(r.authorized).toBe(true);
    if (r.authorized) expect(r.configured).toBe(true);
  });

  test("K15b: spent ⇒ unauthorized (kill switch; node still boots locally)", async () => {
    const adapter = await seededAdapter();
    const v = new CapabilityTokenValidator(new CCS(adapter));
    const dir = await mkdtemp(join(tmpdir(), "nl1-"));
    const tokPath = join(dir, "node-license.tok");
    await writeFile(tokPath, ownerToken(v));
    const oracle = new MonotoneSpendOracle();
    oracle.markSpent({ txid: NL_TXID, vout: 0 });
    const r = await evaluateNodeCapAuthorizationFromConfig(
      {
        nodeCert: OWNER_CERT_ID,
        storage: adapter,
        license: {
          capLicenseOutpointRef: `${NL_TXID}:0`,
          capLicenseTokenPath: tokPath,
          nodeParticipationDomainFlag: PAGE,
        },
      },
      { spv: oracle.spvContext(nlAlive, "beef") },
    );
    expect(r.authorized).toBe(false);
    if (!r.authorized) expect(r.reason).toContain("K15");
  });
});

```
