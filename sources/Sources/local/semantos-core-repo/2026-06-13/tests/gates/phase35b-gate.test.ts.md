---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase35b-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.562948+00:00
---

# tests/gates/phase35b-gate.test.ts

```ts
/**
 * Phase 35B.1 — sovereign-license federation MVP gate.
 *
 * Consolidated gate tests from the Phase 35B.1 MVP plan.
 *
 * Gate matrix:
 *   G35B.1    Two WsNodeAdapter instances federate over local ws:
 *             A.publish → B.subscribe callback fires
 *   G35B.7    DnsPeerLocator resolves a BCA to an endpoint via an
 *             injected TXT resolver (DNS-only reachability)
 *   G35B.8    License handshake BCA binding: claimedBca mismatch → rejected
 *   G35B.8b   Expired license rejected at handshake
 *   G35B.8c   Dev-issuer license rejected when production policy says so
 *   G35B.8d   Per-envelope sig enforcement: envelope with invalid signature
 *             is dropped; subscriber never fires (35B.1 loose-end close)
 *   G35B.12   Phase 35A invariants: the 35A gate suite still passes;
 *             session-protocol's @bsv/sdk choke-point remains in place
 *             (verified here by confirming the expected exports resolve
 *             and the choke-point audit still holds for this repo tree)
 *
 * Plus a small "picked up" set from the plan: LoopbackAdapter roundtrip,
 * license cell encode/decode, mint-license round-trip.
 */

import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { writeFile, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { PrivateKey } from "@bsv/sdk";

import {
  BsvSdkSigner,
  BsvSdkVerifier,
  type BCAProvider,
} from "../../runtime/session-protocol/src/index.js";
import {
  encodeLicense,
  decodeLicense,
  canonicalLicenseBodyForSigning,
  licenseCertId,
  type License,
} from "../../core/protocol-types/src/license.js";
import {
  LoopbackAdapter,
  LoopbackNetwork,
} from "../../runtime/session-protocol/src/adapters/loopback-adapter.js";
import {
  DeterministicBCAProvider,
} from "../../runtime/session-protocol/src/adapters/bca-provider.js";
import {
  DnsPeerLocator,
  StaticPeerLocator,
  type TxtResolver,
} from "../../runtime/peer-locator/src/index.js";
import {
  buildHandshakeFrame,
  verifyHandshakeFrame,
  WsNodeAdapter,
} from "../../runtime/ws-node-adapter/src/index.js";
import {
  deriveDevIssuer,
  validateLicenseForBoot,
  loadLicenseFromDisk,
} from "../../runtime/node/src/license-policy.js";
import { licenseCommand } from "../../runtime/node/src/commands/license.js";

// ---------------------------------------------------------------------------
// Shared fixture helpers
// ---------------------------------------------------------------------------

function compressedPubkey(pk: PrivateKey): Uint8Array {
  return Uint8Array.from(pk.toPublicKey().encode(true) as number[]);
}

function derivedBca(pubkey: Uint8Array): string {
  const suffix = Array.from(pubkey.slice(-2))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `2602:f9f8::${suffix}`;
}

function makeSigner(seedHex: string) {
  const privKey = PrivateKey.fromHex(seedHex);
  const pubkey = compressedPubkey(privKey);
  const signer = new BsvSdkSigner(privKey, async (pk) => derivedBca(pk));
  const provider: BCAProvider = {
    identity: () => signer.identity(),
    sign: (bytes) => signer.sign(bytes),
    deriveBCA: async () => derivedBca(pubkey),
  };
  return { privKey, pubkey, signer, provider, bca: derivedBca(pubkey) };
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
  const signer = new BsvSdkSigner(opts.issuerPrivKey, async () => "issuer");
  const issuerSig = await signer.sign(body);
  const signed: License = { ...license, issuerSig };
  return { license: signed, bytes: encodeLicense(signed) };
}

function waitFor(predicate: () => boolean, timeoutMs: number): Promise<void> {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const tick = () => {
      if (predicate()) return resolve();
      if (Date.now() - start > timeoutMs) {
        return reject(new Error(`waitFor timeout after ${timeoutMs}ms`));
      }
      setTimeout(tick, 5);
    };
    tick();
  });
}

// ---------------------------------------------------------------------------
// G35B.1 — Two WsNodeAdapter instances federate over local ws
// ---------------------------------------------------------------------------

describe("G35B.1 — federation over local ws", () => {
  const ISSUER_SEED = "aa".repeat(32);
  let alice: WsNodeAdapter;
  let bob: WsNodeAdapter;
  let aliceLocator: StaticPeerLocator;
  let bobLocator: StaticPeerLocator;
  let aliceBca: string;
  let bobBca: string;

  beforeEach(async () => {
    const issuer = makeSigner(ISSUER_SEED);
    const a = makeSigner("b0".repeat(32));
    const b = makeSigner("b1".repeat(32));
    aliceBca = a.bca;
    bobBca = b.bca;

    const aliceLicense = await mintLicense({
      issuerPrivKey: issuer.privKey,
      issuerPubkey: issuer.pubkey,
      holderPubkey: a.pubkey,
    });
    const bobLicense = await mintLicense({
      issuerPrivKey: issuer.privKey,
      issuerPubkey: issuer.pubkey,
      holderPubkey: b.pubkey,
    });

    aliceLocator = new StaticPeerLocator();
    bobLocator = new StaticPeerLocator();

    alice = new WsNodeAdapter({
      identity: a.provider,
      license: aliceLicense.license,
      locator: aliceLocator,
      verifier: new BsvSdkVerifier(),
      deriveBcaFromPubkey: async (pk) => derivedBca(pk),
      serverPort: 0,
      serverHost: "127.0.0.1",
      handshakeTimeoutMs: 2_000,
    });
    bob = new WsNodeAdapter({
      identity: b.provider,
      license: bobLicense.license,
      locator: bobLocator,
      verifier: new BsvSdkVerifier(),
      deriveBcaFromPubkey: async (pk) => derivedBca(pk),
      serverPort: 0,
      serverHost: "127.0.0.1",
      handshakeTimeoutMs: 2_000,
    });
    await alice.start();
    await bob.start();

    aliceLocator.register({
      bca: bobBca,
      wssUrl: `ws://127.0.0.1:${bob.listeningPort}/session`,
    });
    bobLocator.register({
      bca: aliceBca,
      wssUrl: `ws://127.0.0.1:${alice.listeningPort}/session`,
    });
  });

  afterEach(async () => {
    await alice?.stop();
    await bob?.stop();
  });

  test("publish on A → subscribe callback on B fires", async () => {
    const received: Uint8Array[] = [];
    bob.subscribe("tm_semantos_objects", (ev) => {
      received.push(ev.result.cellBytes);
    });

    await alice.connect(bobBca);
    await waitFor(() => bob.peers().includes(aliceBca), 1_000);

    const payload = new Uint8Array(256).fill(0x5a);
    await alice.publish({
      cellBytes: payload,
      semanticPath: "gate-test/obj",
      contentHash: "a".repeat(64),
      ownerCert: "alice",
      typeHash: "b".repeat(64),
    });

    await waitFor(() => received.length === 1, 1_000);
    expect(received[0]).toEqual(payload);
  });

  test("/.well-known/semantos-node advertises bca + licenseCertId", async () => {
    const res = await fetch(
      `http://127.0.0.1:${alice.listeningPort}/.well-known/semantos-node`,
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, string>;
    expect(body.bca).toBe(aliceBca);
    expect(body.licenseCertId).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(body.pubkeyHex).toMatch(/^[0-9a-f]{66}$/);
  });
});

// ---------------------------------------------------------------------------
// G35B.8d — per-envelope signature enforcement (35B.1 loose-end close)
//
// Before this gate, SessionEnvelopeFrame.sig was an empty Uint8Array on the
// wire: the license handshake provided transport auth, but individual
// envelopes carried no cryptographic proof of sender authorship. A man-in-
// the-middle (or a buggy peer) could mint fake envelopes after the handshake
// and they'd be accepted.
//
// After this gate, every envelope carries a Signer-produced sig over its
// canonical bytes. The receive path re-computes the canonical bytes and
// verifies against the peer's handshake-bound pubkey; mismatches are
// silently dropped with a log. G35B.1's existing "alice → bob publish →
// subscriber fires" test is the positive case — the real signer + verifier
// pair succeeds end-to-end. This gate is the negative case.
// ---------------------------------------------------------------------------

describe("G35B.8d — per-envelope sig enforcement", () => {
  const ISSUER_SEED = "aa".repeat(32);
  let alice: WsNodeAdapter;
  let bob: WsNodeAdapter;
  let aliceLocator: StaticPeerLocator;
  let bobLocator: StaticPeerLocator;
  let aliceBca: string;
  let bobBca: string;

  beforeEach(async () => {
    const issuer = makeSigner(ISSUER_SEED);
    const a = makeSigner("b2".repeat(32));
    const b = makeSigner("b3".repeat(32));
    aliceBca = a.bca;
    bobBca = b.bca;

    const aliceLicense = await mintLicense({
      issuerPrivKey: issuer.privKey,
      issuerPubkey: issuer.pubkey,
      holderPubkey: a.pubkey,
    });
    const bobLicense = await mintLicense({
      issuerPrivKey: issuer.privKey,
      issuerPubkey: issuer.pubkey,
      holderPubkey: b.pubkey,
    });

    // Alice's signer lies on every sign() call AFTER the first one.
    // The first call is consumed by the license handshake (valid sig);
    // every subsequent call is an envelope sign — we return a fixed
    // 64-byte buffer that is not a valid DER-ECDSA signature over the
    // envelope's canonical bytes. Bob's verifier must reject these.
    let callCount = 0;
    const aliceLyingProvider: BCAProvider = {
      identity: () => a.provider.identity(),
      async sign(bytes: Uint8Array): Promise<Uint8Array> {
        callCount++;
        if (callCount === 1) return a.signer.sign(bytes);
        // Return a 64-byte all-zero buffer — wrong length + wrong bits;
        // BsvSdkVerifier.verify() must return false.
        return new Uint8Array(64);
      },
      deriveBCA: () => a.provider.deriveBCA(),
    };

    aliceLocator = new StaticPeerLocator();
    bobLocator = new StaticPeerLocator();

    alice = new WsNodeAdapter({
      identity: aliceLyingProvider,
      license: aliceLicense.license,
      locator: aliceLocator,
      verifier: new BsvSdkVerifier(),
      deriveBcaFromPubkey: async (pk) => derivedBca(pk),
      serverPort: 0,
      serverHost: "127.0.0.1",
      handshakeTimeoutMs: 2_000,
    });
    bob = new WsNodeAdapter({
      identity: b.provider,
      license: bobLicense.license,
      locator: bobLocator,
      verifier: new BsvSdkVerifier(),
      deriveBcaFromPubkey: async (pk) => derivedBca(pk),
      serverPort: 0,
      serverHost: "127.0.0.1",
      handshakeTimeoutMs: 2_000,
    });
    await alice.start();
    await bob.start();

    aliceLocator.register({
      bca: bobBca,
      wssUrl: `ws://127.0.0.1:${bob.listeningPort}/session`,
    });
    bobLocator.register({
      bca: aliceBca,
      wssUrl: `ws://127.0.0.1:${alice.listeningPort}/session`,
    });
  });

  afterEach(async () => {
    await alice?.stop();
    await bob?.stop();
  });

  test("envelope with invalid sig is dropped; bob's subscriber never fires", async () => {
    const received: Uint8Array[] = [];
    bob.subscribe("tm_semantos_objects", (ev) => {
      received.push(ev.result.cellBytes);
    });

    await alice.connect(bobBca);
    await waitFor(() => bob.peers().includes(aliceBca), 1_000);

    // Handshake already consumed alice's first sign(); the next publish will
    // get a bogus sig from the lying provider. Bob must reject silently.
    await alice.publish({
      cellBytes: new Uint8Array(32).fill(0x7e),
      semanticPath: "tamper-test/obj",
      contentHash: "a".repeat(64),
      ownerCert: "alice",
      typeHash: "b".repeat(64),
    });

    // Give the wire generous time — if the envelope is going to arrive +
    // be delivered, it will happen in well under 200ms. If it never
    // arrives, we want to assert that conclusively.
    await new Promise((r) => setTimeout(r, 300));
    expect(received.length).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// G35B.7 — DNS-only reachability
// ---------------------------------------------------------------------------

describe("G35B.7 — DnsPeerLocator with fake resolver", () => {
  test("resolves BCA to NodeEndpoint via injected TXT resolver", async () => {
    const fakeResolver: TxtResolver = {
      async resolveTxt(hostname: string): Promise<string[]> {
        if (hostname === "_semantos-node.bob.example.com") {
          return [
            "bca=2602:f9f8::b0b;wss=wss://bob.example.com:443/session",
          ];
        }
        return [];
      },
    };
    const loc = new DnsPeerLocator({
      txtResolver: fakeResolver,
      hostnames: ["bob.example.com"],
    });

    const ep = await loc.resolve("2602:f9f8::b0b");
    expect(ep).not.toBeNull();
    expect(ep!.wssUrl).toBe("wss://bob.example.com:443/session");
  });

  test("returns null when no advertised hostname carries the BCA", async () => {
    const loc = new DnsPeerLocator({
      txtResolver: { async resolveTxt() { return []; } },
      hostnames: ["nothing.example.com"],
    });
    expect(await loc.resolve("2602:f9f8::b0b")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// G35B.8 — License handshake: BCA binding + expiry + issuer policy
// ---------------------------------------------------------------------------

describe("G35B.8 — license handshake enforcement", () => {
  const ISSUER_SEED = "aa".repeat(32);
  const HOLDER_SEED = "bb".repeat(32);

  async function setup() {
    const issuer = makeSigner(ISSUER_SEED);
    const holder = makeSigner(HOLDER_SEED);
    const license = await mintLicense({
      issuerPrivKey: issuer.privKey,
      issuerPubkey: issuer.pubkey,
      holderPubkey: holder.pubkey,
    });
    return { issuer, holder, license };
  }

  test("G35B.8 — claimedBca mismatch → bca-mismatch", async () => {
    const { holder, license } = await setup();
    const frame = await buildHandshakeFrame({
      signer: holder.signer,
      licenseBytes: license.bytes,
      claimedBca: "2602:f9f8::imposter", // lie
    });
    const verdict = await verifyHandshakeFrame(frame, {
      verifier: new BsvSdkVerifier(),
      deriveBcaFromPubkey: async (pk) => derivedBca(pk),
    });
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("bca-mismatch");
  });

  test("G35B.8b — expired license → license-expired", async () => {
    const issuer = makeSigner(ISSUER_SEED);
    const holder = makeSigner(HOLDER_SEED);
    const expired = await mintLicense({
      issuerPrivKey: issuer.privKey,
      issuerPubkey: issuer.pubkey,
      holderPubkey: holder.pubkey,
      expiry: Math.floor(Date.now() / 1000) - 3600,
    });
    const frame = await buildHandshakeFrame({
      signer: holder.signer,
      licenseBytes: expired.bytes,
      claimedBca: holder.bca,
    });
    const verdict = await verifyHandshakeFrame(frame, {
      verifier: new BsvSdkVerifier(),
      deriveBcaFromPubkey: async (pk) => derivedBca(pk),
    });
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("license-expired");
  });

  test("G35B.8c — dev issuer rejected by production policy → issuer-rejected", async () => {
    const dev = deriveDevIssuer();
    const holder = makeSigner("cc".repeat(32));
    const devLicense = await mintLicense({
      issuerPrivKey: dev.privKey,
      issuerPubkey: dev.pubkey,
      holderPubkey: holder.pubkey,
    });

    const frame = await buildHandshakeFrame({
      signer: holder.signer,
      licenseBytes: devLicense.bytes,
      claimedBca: holder.bca,
    });
    const verdict = await verifyHandshakeFrame(frame, {
      verifier: new BsvSdkVerifier(),
      deriveBcaFromPubkey: async (pk) => derivedBca(pk),
      // Production policy: reject the dev issuer specifically.
      isAcceptableIssuer: (issuerPubkey) => {
        for (let i = 0; i < issuerPubkey.length; i++) {
          if (issuerPubkey[i] !== dev.pubkey[i]) return true;
        }
        return false;
      },
    });
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.reason).toBe("issuer-rejected");
  });
});

// ---------------------------------------------------------------------------
// Consolidated picked-up coverage (per plan)
// ---------------------------------------------------------------------------

describe("picked-up coverage: loopback + license + mint-license", () => {
  test("LoopbackAdapter in-memory roundtrip: A publishes, B receives", async () => {
    const net = new LoopbackNetwork();
    const a = new LoopbackAdapter({
      identity: new DeterministicBCAProvider(
        new BsvSdkSigner(
          PrivateKey.fromHex("aa".repeat(32)),
          async (pk) => derivedBca(pk),
        ),
      ),
      network: net,
    });
    const b = new LoopbackAdapter({
      identity: new DeterministicBCAProvider(
        new BsvSdkSigner(
          PrivateKey.fromHex("bb".repeat(32)),
          async (pk) => derivedBca(pk),
        ),
      ),
      network: net,
    });
    await a.start();
    await b.start();

    const received: number[] = [];
    b.subscribe("topic-x", () => received.push(1));
    await a.publish(
      {
        cellBytes: new Uint8Array(8),
        semanticPath: "x",
        contentHash: "a".repeat(64),
        ownerCert: "a",
        typeHash: "b".repeat(64),
      },
      { topic: "topic-x" },
    );

    expect(received.length).toBe(1);
  });

  test("license cell encode/decode roundtrip preserves all fields", async () => {
    const issuer = makeSigner("12".repeat(32));
    const holder = makeSigner("34".repeat(32));
    const { license } = await mintLicense({
      issuerPrivKey: issuer.privKey,
      issuerPubkey: issuer.pubkey,
      holderPubkey: holder.pubkey,
      expiry: 2_000_000_000,
    });

    const back = decodeLicense(encodeLicense(license));
    expect(back.pubkey).toEqual(license.pubkey);
    expect(back.issuer).toEqual(license.issuer);
    expect(back.issuerSig).toEqual(license.issuerSig);
    expect(back.services).toEqual(license.services);
    expect(back.expiry).toBe(2_000_000_000);
  });

  test("licenseCertId format is 'sha256:' + 64 hex chars", async () => {
    const issuer = makeSigner("12".repeat(32));
    const holder = makeSigner("34".repeat(32));
    const { license } = await mintLicense({
      issuerPrivKey: issuer.privKey,
      issuerPubkey: issuer.pubkey,
      holderPubkey: holder.pubkey,
    });
    expect(licenseCertId(license)).toMatch(/^sha256:[0-9a-f]{64}$/);
  });

  test("mint-license CLI roundtrip: written license loads and validates in dev mode", async () => {
    const holder = makeSigner("56".repeat(32));
    const dir = await mkdtemp(join(tmpdir(), "35b-gate-"));
    const path = join(dir, "test.license");
    const holderHex = Array.from(holder.pubkey)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // Capture stdout so we can silence CLI noise.
    const origLog = console.log;
    console.log = () => {};
    try {
      await licenseCommand([
        "mint",
        "--holder-pubkey",
        holderHex,
        "--out",
        path,
      ]);
    } finally {
      console.log = origLog;
    }

    const { license } = await loadLicenseFromDisk(path);
    const v = await validateLicenseForBoot(license, { devMode: true });
    expect(v.ok).toBe(true);

    // And rejected without dev mode.
    const v2 = await validateLicenseForBoot(license, { devMode: false });
    expect(v2.ok).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// G35B.12 — Phase 35A invariants still hold
// ---------------------------------------------------------------------------

describe("G35B.12 — Phase 35A regression", () => {
  // The full 35A gate (27 tests in tests/gates/phase35a-gate.test.ts) runs
  // separately as part of the usual CI sweep. Here we perform the minimal
  // structural invariants — the session-protocol @bsv/sdk choke-point, the
  // key exported surface — as a fast cross-check that 35B additions didn't
  // silently break 35A's architecture.

  const SESSION_PROTOCOL_SRC = join(
    import.meta.dir,
    "..",
    "..",
    "runtime",
    "session-protocol",
    "src",
  );

  function walk(dir: string, out: string[] = []): string[] {
    for (const entry of readdirSync(dir)) {
      const p = join(dir, entry);
      const st = statSync(p);
      if (st.isDirectory()) walk(p, out);
      else if (/\.(ts|tsx)$/.test(entry)) out.push(p);
    }
    return out;
  }

  test("G35A.12 still holds — only signer.ts + bsv-* adapters import @bsv/sdk in session-protocol", () => {
    // See phase35a-gate.test.ts for the full rationale: signer.ts
    // is the identity/signing choke-point; files whose basename
    // starts with `bsv-` are explicit BSV-specific adapters (the
    // overlay bundle client + codec, the wallet signer).
    const bsvSdkImport = /from\s+['"]@bsv\/sdk(?:\/[^'"]*)?['"]/;
    const isAllowed = (rel: string): boolean => {
      if (rel === "signer.ts") return true;
      const basename = rel.split("/").pop() ?? rel;
      return basename.startsWith("bsv-");
    };
    const offenders: string[] = [];
    for (const file of walk(SESSION_PROTOCOL_SRC)) {
      const rel = relative(SESSION_PROTOCOL_SRC, file);
      if (isAllowed(rel)) continue;
      const src = readFileSync(file, "utf8");
      if (bsvSdkImport.test(src)) offenders.push(rel);
    }
    expect(offenders).toEqual([]);
  });

  test("35A's exported surface still resolves (LoopbackAdapter lives there too now)", async () => {
    // Dynamic import — any resolution / type error would fail here.
    const mod = (await import(
      "../../runtime/session-protocol/src/index.js"
    )) as Record<string, unknown>;
    expect(typeof mod.BsvSdkSigner).toBe("function");
    expect(typeof mod.BsvSdkVerifier).toBe("function");
    expect(typeof mod.MulticastAdapter).toBe("function");
    expect(typeof mod.LoopbackAdapter).toBe("function");
    expect(typeof mod.DeterministicBCAProvider).toBe("function");
  });
});

```
