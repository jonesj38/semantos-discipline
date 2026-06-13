---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/__tests__/bundle-transport-bridge.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.334424+00:00
---

# runtime/ws-node-adapter/__tests__/bundle-transport-bridge.test.ts

```ts
/**
 * WsBundleTransport — the Slice 5d BundleTransport over WsNodeAdapter.
 *
 * Two layers of coverage:
 *
 * 1. Unit — exercise send/receive/error paths against a minimal
 *    fake NetworkAdapter. Deterministic and fast.
 *
 * 2. Integration (G35B.bundle) — wire two real WsNodeAdapter
 *    instances over local ws, wrap each in a WsBundleTransport, and
 *    verify a real `SignedBundle` round-trips end-to-end. This is the
 *    bridge point between 5d's bundle semantics and 35B's federation
 *    wire: if this test is green on localhost, two VPSs running
 *    `semantos start` can already exchange signed intent bundles.
 */

import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { PrivateKey } from "@bsv/sdk";
import {
  BsvSdkSigner,
  BsvSdkVerifier,
  signBundle,
  verifyBundle,
  TransportError,
  type BCAProvider,
  type SignedBundle,
} from "@semantos/session-protocol";
import {
  encodeLicense,
  canonicalLicenseBodyForSigning,
  type License,
} from "@semantos/protocol-types/license";
import type {
  NetworkAdapter,
  NetworkEvent,
  NetworkQuery,
  NetworkResult,
  NodeInfo,
  PublishOptions,
  PublishResult,
  PublishableObject,
} from "@semantos/protocol-types/network";
import { StaticPeerLocator } from "@semantos/peer-locator";

import { WsNodeAdapter } from "../src/ws-node-adapter";
import {
  bundleTopicForCertId,
  createWsBundleTransport,
} from "../src/bundle-transport-bridge";

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

const ISSUER_SEED = "aa".repeat(32);
const ALICE_SEED = "bb".repeat(32);
const BOB_SEED = "cc".repeat(32);

function compressedPubkey(pk: PrivateKey): Uint8Array {
  return Uint8Array.from(pk.toPublicKey().encode(true) as number[]);
}

function derivedBca(pubkey: Uint8Array): string {
  const suffix = Array.from(pubkey.slice(-2))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `2602:f9f8::${suffix}`;
}

async function buildSigner(seedHex: string) {
  const privKey = PrivateKey.fromHex(seedHex);
  const pubkey = compressedPubkey(privKey);
  const bca = derivedBca(pubkey);
  const signer = new BsvSdkSigner(privKey, async (pk) => derivedBca(pk));
  const provider: BCAProvider = {
    identity: () => signer.identity(),
    sign: (bytes) => signer.sign(bytes),
    deriveBCA: async () => bca,
  };
  return { privKey, pubkey, bca, signer, provider };
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
// 1. Unit tests against a fake NetworkAdapter
// ---------------------------------------------------------------------------

/** Minimal in-process NetworkAdapter for unit tests — just enough to echo publish back to subscribers on the matching topic. */
function createFakeAdapter(): {
  adapter: NetworkAdapter;
  published: Array<{ object: PublishableObject; options?: PublishOptions }>;
  /** Simulate inbound wire delivery on a given topic (used to prod onReceive). */
  deliver: (topic: string, object: PublishableObject) => void;
} {
  const subs = new Map<string, Set<(ev: NetworkEvent) => void>>();
  const published: Array<{
    object: PublishableObject;
    options?: PublishOptions;
  }> = [];

  const deliver = (topic: string, object: PublishableObject) => {
    const handlers = subs.get(topic);
    if (!handlers) return;
    const event: NetworkEvent = {
      type: "object_published",
      result: {
        txid: "fake",
        vout: 0,
        cellBytes: object.cellBytes,
        semanticPath: object.semanticPath,
        contentHash: object.contentHash,
        ownerCert: object.ownerCert,
        typeHash: object.typeHash,
        multicastGroup: topic,
      } as NetworkResult,
      timestamp: Date.now(),
    };
    for (const h of handlers) h(event);
  };

  const adapter: NetworkAdapter = {
    async start() {},
    async stop() {},
    async publish(
      object: PublishableObject,
      options?: PublishOptions,
    ): Promise<PublishResult> {
      published.push({ object, options });
      return {
        txid: "fake",
        publishedAt: Date.now(),
        multicastGroup: options?.topic ?? "tm_semantos_objects",
      };
    },
    subscribe(topic: string, cb: (ev: NetworkEvent) => void): () => void {
      let set = subs.get(topic);
      if (!set) {
        set = new Set();
        subs.set(topic, set);
      }
      set.add(cb);
      return () => {
        set!.delete(cb);
        if (set!.size === 0) subs.delete(topic);
      };
    },
    async resolve(_q: NetworkQuery): Promise<NetworkResult[]> {
      return [];
    },
    async resolveBCA(_a: string): Promise<NodeInfo | null> {
      return null;
    },
    async sendToNode() {
      return { delivered: false };
    },
    isConnected() {
      return true;
    },
    getNodeBCA() {
      return null;
    },
  };

  return { adapter, published, deliver };
}

describe("WsBundleTransport — unit", () => {
  const ALICE_CERT = "cert:alice";
  const BOB_CERT = "cert:bob";

  test("T1 topic convention is bundles/<certId>", () => {
    expect(bundleTopicForCertId(BOB_CERT)).toBe("bundles/cert:bob");
  });

  test("T2 send() publishes to recipient's topic with JSON-encoded bundle", async () => {
    const { adapter, published } = createFakeAdapter();
    const transport = createWsBundleTransport({
      adapter,
      localCertId: ALICE_CERT,
    });

    const { signer } = await buildSigner(ALICE_SEED);
    const bundle = await signBundle({ hello: "world" }, signer, {
      recipient: { certId: BOB_CERT },
    });

    await transport.send(bundle);

    expect(published).toHaveLength(1);
    expect(published[0]!.options?.topic).toBe("bundles/cert:bob");

    const decoded = JSON.parse(
      new TextDecoder().decode(published[0]!.object.cellBytes),
    );
    expect(decoded.recipient.certId).toBe(BOB_CERT);
    expect(decoded.payload.hello).toBe("world");
    expect(published[0]!.object.ownerCert).toBe(ALICE_CERT);
  });

  test("T3 send() rejects unaddressed bundles", async () => {
    const { adapter } = createFakeAdapter();
    const transport = createWsBundleTransport({
      adapter,
      localCertId: ALICE_CERT,
    });

    const { signer } = await buildSigner(ALICE_SEED);
    const bundle = await signBundle({ hello: "world" }, signer);

    await expect(transport.send(bundle)).rejects.toMatchObject({
      name: "TransportError",
      code: "unaddressed_bundle",
    });
  });

  test("T4 send() rejects self-send", async () => {
    const { adapter } = createFakeAdapter();
    const transport = createWsBundleTransport({
      adapter,
      localCertId: ALICE_CERT,
    });

    const { signer } = await buildSigner(ALICE_SEED);
    const bundle = await signBundle({ hello: "world" }, signer, {
      recipient: { certId: ALICE_CERT },
    });

    await expect(transport.send(bundle)).rejects.toMatchObject({
      name: "TransportError",
      code: "self_send",
    });
  });

  test("T5 onReceive subscribes to local-certId topic and parses inbound", async () => {
    const { adapter, deliver } = createFakeAdapter();
    const transport = createWsBundleTransport({
      adapter,
      localCertId: BOB_CERT,
    });

    const received: SignedBundle<unknown>[] = [];
    const unsub = transport.onReceive<{ hello: string }>((b) => {
      received.push(b);
    });

    const { signer } = await buildSigner(ALICE_SEED);
    const bundle = await signBundle({ hello: "world" }, signer, {
      recipient: { certId: BOB_CERT },
    });

    // Simulate WsNodeAdapter delivering the inbound frame as cellBytes.
    deliver(bundleTopicForCertId(BOB_CERT), {
      cellBytes: new TextEncoder().encode(JSON.stringify(bundle)),
      semanticPath: `/bundles/${BOB_CERT}`,
      contentHash: bundle.signature,
      ownerCert: "cert:alice",
      typeHash: "signed-bundle",
    });

    // Give microtasks a chance to flush (handler is awaited but emit is sync).
    await new Promise((r) => setTimeout(r, 0));

    expect(received).toHaveLength(1);
    expect((received[0]!.payload as { hello: string }).hello).toBe("world");

    unsub();
  });

  test("T6 onReceive drops bundles whose recipient.certId doesn't match local (defence in depth)", async () => {
    const { adapter, deliver } = createFakeAdapter();
    const transport = createWsBundleTransport({
      adapter,
      localCertId: BOB_CERT,
    });

    const received: SignedBundle<unknown>[] = [];
    transport.onReceive((b) => {
      received.push(b);
    });

    const { signer } = await buildSigner(ALICE_SEED);
    // Bundle addressed to someone else but mis-delivered to bob's topic.
    const bundle = await signBundle({ hello: "world" }, signer, {
      recipient: { certId: "cert:charlie" },
    });
    deliver(bundleTopicForCertId(BOB_CERT), {
      cellBytes: new TextEncoder().encode(JSON.stringify(bundle)),
      semanticPath: `/bundles/${BOB_CERT}`,
      contentHash: bundle.signature,
      ownerCert: "cert:alice",
      typeHash: "signed-bundle",
    });

    await new Promise((r) => setTimeout(r, 0));
    expect(received).toHaveLength(0);
  });

  test("T7 onReceive unsubscribe stops delivery", async () => {
    const { adapter, deliver } = createFakeAdapter();
    const transport = createWsBundleTransport({
      adapter,
      localCertId: BOB_CERT,
    });

    const received: SignedBundle<unknown>[] = [];
    const unsub = transport.onReceive((b) => {
      received.push(b);
    });
    unsub();

    const { signer } = await buildSigner(ALICE_SEED);
    const bundle = await signBundle({ hello: "world" }, signer, {
      recipient: { certId: BOB_CERT },
    });
    deliver(bundleTopicForCertId(BOB_CERT), {
      cellBytes: new TextEncoder().encode(JSON.stringify(bundle)),
      semanticPath: `/bundles/${BOB_CERT}`,
      contentHash: bundle.signature,
      ownerCert: "cert:alice",
      typeHash: "signed-bundle",
    });

    await new Promise((r) => setTimeout(r, 0));
    expect(received).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// 2. Integration — two WsNodeAdapters exchange a real SignedBundle
// ---------------------------------------------------------------------------

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

async function startIntegrationNode(seedHex: string) {
  const identity = await buildSigner(seedHex);
  const issuer = await buildSigner(ISSUER_SEED);
  const { license } = await issueLicense(
    identity.pubkey,
    issuer.privKey,
    issuer.pubkey,
  );
  const locator = new StaticPeerLocator();
  const adapter = new WsNodeAdapter({
    identity: identity.provider,
    license,
    locator,
    verifier: new BsvSdkVerifier(),
    deriveBcaFromPubkey: async (pk) => derivedBca(pk),
    serverPort: 0,
    serverHost: "127.0.0.1",
    handshakeTimeoutMs: 2_000,
  });
  await adapter.start();
  return { identity, adapter, locator };
}

describe("G35B.bundle — two WsNodeAdapters exchange a SignedBundle", () => {
  let alice: Awaited<ReturnType<typeof startIntegrationNode>>;
  let bob: Awaited<ReturnType<typeof startIntegrationNode>>;

  beforeEach(async () => {
    alice = await startIntegrationNode(ALICE_SEED);
    bob = await startIntegrationNode(BOB_SEED);

    const alicePort = alice.adapter.listeningPort!;
    const bobPort = bob.adapter.listeningPort!;

    alice.locator.register({
      bca: bob.identity.bca,
      wssUrl: `ws://127.0.0.1:${bobPort}/session`,
    });
    bob.locator.register({
      bca: alice.identity.bca,
      wssUrl: `ws://127.0.0.1:${alicePort}/session`,
    });
  });

  afterEach(async () => {
    await alice?.adapter.stop();
    await bob?.adapter.stop();
  });

  test("alice signs → sends → bob receives + verifies", async () => {
    const ALICE_CERT = `cert:${alice.identity.bca}`;
    const BOB_CERT = `cert:${bob.identity.bca}`;

    const aliceTransport = createWsBundleTransport({
      adapter: alice.adapter,
      localCertId: ALICE_CERT,
    });
    const bobTransport = createWsBundleTransport({
      adapter: bob.adapter,
      localCertId: BOB_CERT,
    });

    const received: SignedBundle<{ intent: string }>[] = [];
    bobTransport.onReceive<{ intent: string }>((b) => {
      received.push(b);
    });

    // Dial the federation channel (same handshake 35B.1 ships).
    const conn = await alice.adapter.connect(bob.identity.bca);
    expect(conn.currentState).toBe("authenticated");
    await waitFor(
      () => bob.adapter.peers().includes(alice.identity.bca),
      1_000,
    );

    // Alice signs an addressed bundle for bob.
    const bundle = await signBundle(
      { intent: "trade/DOGE@100" },
      alice.identity.signer,
      { recipient: { certId: BOB_CERT } },
    );

    // Send via the bundle transport — goes through WsNodeAdapter's wire.
    await aliceTransport.send(bundle);

    // Wait for bob's handler to fire. No deterministic flush hook in
    // ws-node-adapter yet (35B.2 follow-up), so we poll briefly.
    await waitFor(() => received.length > 0, 1_000);

    expect(received).toHaveLength(1);
    const got = received[0]!;
    expect(got.payload.intent).toBe("trade/DOGE@100");
    expect(got.recipient?.certId).toBe(BOB_CERT);
    expect(got.signer.bca).toBe(alice.identity.bca);

    // Full crypto verification on Bob's side — the headline property.
    const verdict = await verifyBundle(got, new BsvSdkVerifier());
    expect(verdict.ok).toBe(true);
  });
});

```
