---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/__tests__/loopback-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.038871+00:00
---

# runtime/session-protocol/__tests__/loopback-adapter.test.ts

```ts
/**
 * Phase 35B.1 — LoopbackAdapter tests.
 *
 * In-memory full `NetworkAdapter` fixture. Two adapters bound to the same
 * `LoopbackNetwork` see each other's publishes, resolve each other's BCAs,
 * and `sendToNode` delivers synchronously — with zero transport setup.
 *
 * Replaces the old `LoopbackUdpTransport + MulticastAdapter` fixture for
 * tests that just need a NetworkAdapter and don't care about wire format.
 */

import { describe, test, expect, beforeEach } from "bun:test";
import type {
  NetworkEvent,
  PublishableObject,
} from "@semantos/protocol-types/network";
import {
  LoopbackAdapter,
  LoopbackNetwork,
} from "../src/adapters/loopback-adapter";
import { DeterministicBCAProvider } from "../src/adapters/bca-provider";
import { StubSigner } from "../src/signer";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

function makeIdentity(seedByte: number) {
  const seed = seedByte.toString(16).padStart(2, "0").repeat(32);
  return new DeterministicBCAProvider(new StubSigner(seed));
}

function makePublishable(
  overrides: Partial<PublishableObject> = {},
): PublishableObject {
  return {
    cellBytes: new Uint8Array(1024).fill(0x42),
    semanticPath: "trades/job/plumbing-1774",
    contentHash: "a".repeat(64),
    ownerCert: "cert-alice",
    typeHash: "b".repeat(64),
    parentPath: undefined,
    ...overrides,
  };
}

let net: LoopbackNetwork;

beforeEach(() => {
  net = new LoopbackNetwork();
});

// ---------------------------------------------------------------------------
// Happy path: two adapters see each other
// ---------------------------------------------------------------------------

describe("LoopbackAdapter — roundtrip via shared LoopbackNetwork", () => {
  test("A publishes, B receives with full NetworkEvent shape", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });
    const b = new LoopbackAdapter({ identity: makeIdentity(0x02), network: net });
    await a.start();
    await b.start();

    const received: NetworkEvent[] = [];
    b.subscribe("tm_semantos_objects", (e) => received.push(e));

    const obj = makePublishable();
    const pub = await a.publish(obj);

    expect(received.length).toBe(1);
    const ev = received[0]!;
    expect(ev.type).toBe("object_published");
    expect(ev.result.cellBytes).toEqual(obj.cellBytes);
    expect(ev.result.semanticPath).toBe("trades/job/plumbing-1774");
    expect(ev.result.contentHash).toBe("a".repeat(64));
    expect(ev.result.ownerCert).toBe("cert-alice");
    expect(ev.result.txid).toBe(pub.txid);
  });

  test("publish also delivers to the publisher's own subscribers", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });
    await a.start();

    const received: NetworkEvent[] = [];
    a.subscribe("tm_semantos_objects", (e) => received.push(e));

    await a.publish(makePublishable());

    expect(received.length).toBe(1);
  });

  test("subscribers only receive events for their topic", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });
    const b = new LoopbackAdapter({ identity: makeIdentity(0x02), network: net });
    await a.start();
    await b.start();

    const onTopicX: NetworkEvent[] = [];
    const onTopicY: NetworkEvent[] = [];
    b.subscribe("topic-x", (e) => onTopicX.push(e));
    b.subscribe("topic-y", (e) => onTopicY.push(e));

    await a.publish(makePublishable(), { topic: "topic-x" });

    expect(onTopicX.length).toBe(1);
    expect(onTopicY.length).toBe(0);
  });

  test("unsubscribe stops delivery", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });
    const b = new LoopbackAdapter({ identity: makeIdentity(0x02), network: net });
    await a.start();
    await b.start();

    const received: NetworkEvent[] = [];
    const unsub = b.subscribe("tm_semantos_objects", (e) => received.push(e));

    await a.publish(makePublishable());
    expect(received.length).toBe(1);

    unsub();
    await a.publish(makePublishable());
    expect(received.length).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// resolve / resolveBCA / sendToNode / getNodeBCA / isConnected
// ---------------------------------------------------------------------------

describe("LoopbackAdapter — NetworkAdapter method coverage", () => {
  test("resolve returns locally published objects matching the query", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });
    await a.start();

    await a.publish(makePublishable({ semanticPath: "path/one" }));
    await a.publish(makePublishable({ semanticPath: "path/two" }));

    const results = await a.resolve({ path: "path/one" });
    expect(results.length).toBe(1);
    expect(results[0]!.semanticPath).toBe("path/one");
  });

  test("resolveBCA returns NodeInfo for peers on the same network", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });
    const b = new LoopbackAdapter({ identity: makeIdentity(0x02), network: net });
    await a.start();
    await b.start();

    const bBca = b.getNodeBCA()!;
    const info = await a.resolveBCA(bBca);

    expect(info).not.toBeNull();
    expect(info!.bca).toBe(bBca);
  });

  test("resolveBCA returns null for unknown BCA", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });
    await a.start();

    const info = await a.resolveBCA("2602:f9f8::ffff");
    expect(info).toBeNull();
  });

  test("sendToNode reports delivered:true when peer exists, false otherwise", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });
    const b = new LoopbackAdapter({ identity: makeIdentity(0x02), network: net });
    await a.start();
    await b.start();

    const bBca = b.getNodeBCA()!;
    const ok = await a.sendToNode(bBca, new Uint8Array([1, 2, 3]));
    const bad = await a.sendToNode("2602:f9f8::ffff", new Uint8Array([1]));

    expect(ok.delivered).toBe(true);
    expect(bad.delivered).toBe(false);
  });

  test("isConnected flips with start/stop", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });

    expect(a.isConnected()).toBe(false);
    await a.start();
    expect(a.isConnected()).toBe(true);
    await a.stop();
    expect(a.isConnected()).toBe(false);
  });

  test("getNodeBCA returns null before start, a BCA after start", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });

    expect(a.getNodeBCA()).toBeNull();
    await a.start();
    expect(a.getNodeBCA()).toMatch(/:/); // looks IPv6-ish
  });

  test("stop unregisters: later publishes from peers are not received", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });
    const b = new LoopbackAdapter({ identity: makeIdentity(0x02), network: net });
    await a.start();
    await b.start();

    const received: NetworkEvent[] = [];
    b.subscribe("tm_semantos_objects", (e) => received.push(e));

    await b.stop();
    await a.publish(makePublishable());

    expect(received.length).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Default network singleton
// ---------------------------------------------------------------------------

describe("LoopbackAdapter — default network singleton", () => {
  test("two adapters without explicit network share the default one", async () => {
    // NOTE: this test uses the default network, so it can pollute/be polluted
    // by sibling tests using the default. Reset before starting.
    const { DEFAULT_LOOPBACK_NETWORK } = await import("../src/adapters/loopback-adapter");
    DEFAULT_LOOPBACK_NETWORK.reset();

    const a = new LoopbackAdapter({ identity: makeIdentity(0x03) });
    const b = new LoopbackAdapter({ identity: makeIdentity(0x04) });
    await a.start();
    await b.start();

    const received: NetworkEvent[] = [];
    b.subscribe("tm_semantos_objects", (e) => received.push(e));

    await a.publish(makePublishable());

    expect(received.length).toBe(1);

    await a.stop();
    await b.stop();
    DEFAULT_LOOPBACK_NETWORK.reset();
  });
});

// ---------------------------------------------------------------------------
// LoopbackNetwork.reset
// ---------------------------------------------------------------------------

describe("LoopbackNetwork.reset", () => {
  test("clears peers, subscribers, and objects", async () => {
    const a = new LoopbackAdapter({ identity: makeIdentity(0x01), network: net });
    const b = new LoopbackAdapter({ identity: makeIdentity(0x02), network: net });
    await a.start();
    await b.start();

    const received: NetworkEvent[] = [];
    b.subscribe("tm_semantos_objects", (e) => received.push(e));
    await a.publish(makePublishable());
    expect(received.length).toBe(1);

    net.reset();

    // After reset the network forgets everything. Publishing through a still-
    // running adapter falls into a fresh empty network — no peer sees the event.
    await a.publish(makePublishable());
    expect(received.length).toBe(1);
  });
});

```
