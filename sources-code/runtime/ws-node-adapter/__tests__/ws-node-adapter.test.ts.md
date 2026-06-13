---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/__tests__/ws-node-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.333847+00:00
---

# runtime/ws-node-adapter/__tests__/ws-node-adapter.test.ts

```ts
/**
 * WsNodeAdapter integration — G35B.1.
 *
 * Spins up two WsNodeAdapter instances on local free ports, wires each
 * into the other's StaticPeerLocator, and exercises the end-to-end
 * flow: dial → handshake → authenticated → publish → subscriber
 * callback fires on the peer.
 *
 * Uses plain ws (not wss) for test simplicity — TLS is a transport-
 * layer concern that Bun owns. What this test proves is the protocol:
 * envelope codec, handshake auth, cross-adapter publish delivery.
 */

import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { PrivateKey } from "@bsv/sdk";
import {
  BsvSdkSigner,
  BsvSdkVerifier,
  type BCAProvider,
} from "@semantos/session-protocol";
import {
  encodeLicense,
  canonicalLicenseBodyForSigning,
  type License,
} from "@semantos/protocol-types/license";
import { StaticPeerLocator } from "@semantos/peer-locator";

import { WsNodeAdapter } from "../src/ws-node-adapter";

// ---------------------------------------------------------------------------
// Fixture: derive a dev-issuer, issue licenses for two holders.
// ---------------------------------------------------------------------------

const ISSUER_SEED = "aa".repeat(32);
const ALICE_SEED = "bb".repeat(32);
const BOB_SEED = "cc".repeat(32);

function compressedPubkey(pk: PrivateKey): Uint8Array {
  return Uint8Array.from(pk.toPublicKey().encode(true) as number[]);
}

/** Stub BCA-from-pubkey derivation matching the StubSigner convention. */
function derivedBca(pubkey: Uint8Array): string {
  const suffix = Array.from(pubkey.slice(-2))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `2602:f9f8::${suffix}`;
}

async function buildIdentity(seedHex: string): Promise<{
  provider: BCAProvider;
  privKey: PrivateKey;
  pubkey: Uint8Array;
  bca: string;
}> {
  const privKey = PrivateKey.fromHex(seedHex);
  const pubkey = compressedPubkey(privKey);
  const bca = derivedBca(pubkey);
  const deriver = async (pk: Uint8Array): Promise<string> => derivedBca(pk);
  const signer = new BsvSdkSigner(privKey, deriver);
  const provider: BCAProvider = {
    identity: () => signer.identity(),
    sign: (bytes) => signer.sign(bytes),
    deriveBCA: async () => bca,
  };
  return { provider, privKey, pubkey, bca };
}

async function issueLicense(
  holderPubkey: Uint8Array,
  issuerPrivKey: PrivateKey,
  issuerPubkey: Uint8Array,
): Promise<{ license: License; bytes: Uint8Array }> {
  const license: License = {
    pubkey: holderPubkey,
    issuer: issuerPubkey,
    services: ["session"],
    issuerSig: new Uint8Array(0),
  };
  const body = canonicalLicenseBodyForSigning(license);
  const issuer = new BsvSdkSigner(issuerPrivKey, async () => "issuer-bca");
  const issuerSig = await issuer.sign(body);
  const signed: License = { ...license, issuerSig };
  return { license: signed, bytes: encodeLicense(signed) };
}

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

interface TestNode {
  adapter: WsNodeAdapter;
  locator: StaticPeerLocator;
  bca: string;
}

async function buildNode(seedHex: string): Promise<{
  identity: Awaited<ReturnType<typeof buildIdentity>>;
  license: Awaited<ReturnType<typeof issueLicense>>;
}> {
  const identity = await buildIdentity(seedHex);
  const issuer = await buildIdentity(ISSUER_SEED);
  const license = await issueLicense(
    identity.pubkey,
    issuer.privKey,
    issuer.pubkey,
  );
  return { identity, license };
}

async function startNode(
  seedHex: string,
): Promise<TestNode> {
  const { identity, license } = await buildNode(seedHex);
  const locator = new StaticPeerLocator();
  const adapter = new WsNodeAdapter({
    identity: identity.provider,
    license: license.license,
    locator,
    verifier: new BsvSdkVerifier(),
    deriveBcaFromPubkey: async (pk) => derivedBca(pk),
    serverPort: 0,
    serverHost: "127.0.0.1",
    handshakeTimeoutMs: 2_000,
  });
  await adapter.start();
  return { adapter, locator, bca: identity.bca };
}

function waitFor(
  predicate: () => boolean,
  timeoutMs: number,
): Promise<void> {
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
// G35B.1
// ---------------------------------------------------------------------------

describe("G35B.1 — two WsNodeAdapters federate over local ws", () => {
  let alice: TestNode;
  let bob: TestNode;

  beforeEach(async () => {
    alice = await startNode(ALICE_SEED);
    bob = await startNode(BOB_SEED);

    const alicePort = alice.adapter.listeningPort!;
    const bobPort = bob.adapter.listeningPort!;

    // Cross-register endpoints so each side can dial the other.
    alice.locator.register({
      bca: bob.bca,
      wssUrl: `ws://127.0.0.1:${bobPort}/session`,
    });
    bob.locator.register({
      bca: alice.bca,
      wssUrl: `ws://127.0.0.1:${alicePort}/session`,
    });
  });

  afterEach(async () => {
    await alice?.adapter.stop();
    await bob?.adapter.stop();
  });

  test("alice connects to bob, publishes, bob's subscriber fires", async () => {
    const bobReceived: Array<{
      topic: string;
      bytes: Uint8Array;
    }> = [];
    bob.adapter.subscribe("topic-x", (ev) => {
      bobReceived.push({
        topic: ev.result.multicastGroup ?? "",
        bytes: ev.result.cellBytes,
      });
    });

    const conn = await alice.adapter.connect(bob.bca);
    expect(conn.currentState).toBe("authenticated");
    expect(conn.peerBca).toBe(bob.bca);

    // Wait for bob to also mark alice authenticated (listener side races
    // the dialer-side onAuthenticated callback).
    await waitFor(() => bob.adapter.peers().includes(alice.bca), 1_000);

    const payload = new Uint8Array(1024).fill(0x42);
    await alice.adapter.publish(
      {
        cellBytes: payload,
        semanticPath: "trades/job/plumbing-1774",
        contentHash: "a".repeat(64),
        ownerCert: "cert-alice",
        typeHash: "b".repeat(64),
      },
      { topic: "topic-x" },
    );

    await waitFor(() => bobReceived.length === 1, 1_000);
    expect(bobReceived[0]!.topic).toBe("topic-x");
    expect(bobReceived[0]!.bytes).toEqual(payload);
  });

  test("round-trip from publish() to subscriber callback is well under 1s", async () => {
    const timings: number[] = [];
    bob.adapter.subscribe("topic-fast", (ev) => {
      timings.push(Date.now() - (ev.result.publishedAt ?? Date.now()));
    });

    await alice.adapter.connect(bob.bca);
    await waitFor(() => bob.adapter.peers().includes(alice.bca), 1_000);

    const t0 = Date.now();
    await alice.adapter.publish(
      {
        cellBytes: new Uint8Array(32).fill(0x01),
        semanticPath: "p",
        contentHash: "c".repeat(64),
        ownerCert: "o",
        typeHash: "t".repeat(64),
      },
      { topic: "topic-fast" },
    );
    await waitFor(() => timings.length === 1, 1_000);
    const elapsed = Date.now() - t0;

    // Plan's target is <50ms; in CI we allow a much looser bound to avoid
    // flakes. The important thing is it's real-time, not minutes.
    expect(elapsed).toBeLessThan(500);
  });

  test("publish also delivers to the publisher's own subscribers (loopback semantics)", async () => {
    const aliceReceived: unknown[] = [];
    alice.adapter.subscribe("topic-self", () => aliceReceived.push(1));

    await alice.adapter.publish(
      {
        cellBytes: new Uint8Array(8),
        semanticPath: "p",
        contentHash: "c".repeat(64),
        ownerCert: "o",
        typeHash: "t".repeat(64),
      },
      { topic: "topic-self" },
    );

    expect(aliceReceived.length).toBe(1);
  });

  test("peers() list reflects current authenticated connections", async () => {
    expect(alice.adapter.peers()).toEqual([]);
    await alice.adapter.connect(bob.bca);
    expect(alice.adapter.peers()).toEqual([bob.bca]);
    await alice.adapter.disconnect(bob.bca);
    expect(alice.adapter.peers()).toEqual([]);
  });

  test("connect with no locator entry throws", async () => {
    // Start a fresh adapter with a bare locator so no endpoint is known.
    const { identity, license } = await buildNode("dd".repeat(32));
    const empty = new WsNodeAdapter({
      identity: identity.provider,
      license: license.license,
      locator: new StaticPeerLocator(),
      verifier: new BsvSdkVerifier(),
      deriveBcaFromPubkey: async (pk) => derivedBca(pk),
      serverPort: 0,
      serverHost: "127.0.0.1",
    });
    await empty.start();
    try {
      await expect(empty.connect("2602:f9f8::unknown")).rejects.toThrow(
        /no endpoint/,
      );
    } finally {
      await empty.stop();
    }
  });

  test("sendToNode reports delivered:true for authenticated peers, false otherwise", async () => {
    await alice.adapter.connect(bob.bca);
    await waitFor(() => bob.adapter.peers().includes(alice.bca), 1_000);

    const ok = await alice.adapter.sendToNode(bob.bca, new Uint8Array([1]));
    const bad = await alice.adapter.sendToNode("2602:f9f8::nope", new Uint8Array());
    expect(ok.delivered).toBe(true);
    expect(bad.delivered).toBe(false);
  });

  test("getNodeBCA / isConnected lifecycle", async () => {
    expect(alice.adapter.getNodeBCA()).toBe(alice.bca);
    expect(alice.adapter.isConnected()).toBe(true);
  });

  // ── /.well-known/semantos-node ──────────────────────────────

  test("/.well-known/semantos-node returns bca + pubkeyHex + licenseCertId", async () => {
    const port = alice.adapter.listeningPort!;
    const res = await fetch(`http://127.0.0.1:${port}/.well-known/semantos-node`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("application/json");

    const body = (await res.json()) as Record<string, unknown>;
    expect(body.bca).toBe(alice.bca);
    expect(body.pubkeyHex).toMatch(/^[0-9a-f]{66}$/);
    expect(body.licenseCertId).toMatch(/^sha256:[0-9a-f]{64}$/);
  });

  test("/.well-known/semantos-node merges wellKnownExtras callback output", async () => {
    const { identity, license } = await buildNode("1f".repeat(32));
    const node = new WsNodeAdapter({
      identity: identity.provider,
      license: license.license,
      locator: new StaticPeerLocator(),
      verifier: new BsvSdkVerifier(),
      deriveBcaFromPubkey: async (pk) => derivedBca(pk),
      serverPort: 0,
      serverHost: "127.0.0.1",
      wellKnownExtras: () => ({
        version: "0.1.0",
        adapters: { network: "ws-node" },
        advertised: { wssUrl: "wss://node.example.com:443/session" },
      }),
    });
    await node.start();
    try {
      const body = await node.buildWellKnownResponse();
      expect(body.bca).toBe(identity.bca);
      expect(body.version).toBe("0.1.0");
      expect(body.adapters).toEqual({ network: "ws-node" });
      expect((body.advertised as any).wssUrl).toBe("wss://node.example.com:443/session");
    } finally {
      await node.stop();
    }
  });

  test("/.well-known/semantos-node without extras still serves the core fields", async () => {
    const port = alice.adapter.listeningPort!;
    const res = await fetch(`http://127.0.0.1:${port}/.well-known/semantos-node`);
    const body = (await res.json()) as Record<string, unknown>;
    expect(Object.keys(body).sort()).toEqual([
      "bca",
      "licenseCertId",
      "pubkeyHex",
    ]);
  });

  test("unknown HTTP path still 404s", async () => {
    const port = alice.adapter.listeningPort!;
    const res = await fetch(`http://127.0.0.1:${port}/not-a-thing`);
    expect(res.status).toBe(404);
  });
});

```
