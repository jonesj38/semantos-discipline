---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase35a-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.577779+00:00
---

# tests/gates/phase35a-gate.test.ts

```ts
/**
 * Phase 35A — session-protocol promotion gate.
 *
 * Test matrix from docs/prd/PHASE-35A-SESSION-PROTOCOL-PROMOTION.md §D35A.7.
 * Tests land incrementally as the TDD sequencing in the sprint plan unfolds.
 * Currently-exercised gates: G35A.11, G35A.12.
 */

import { describe, it, expect } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import {
  BsvSdkSigner,
  BsvSdkVerifier,
  StubSigner,
} from "../../runtime/session-protocol/src/signer.js";
import {
  LoopbackUdpTransport,
  NodeUdpTransport,
} from "../../core/protocol-types/src/adapters/udp-transport.js";
import {
  MulticastAdapter,
  PayloadTooLargeError,
} from "../../runtime/session-protocol/src/adapters/multicast-adapter.js";
import { DeterministicBCAProvider } from "../../runtime/session-protocol/src/adapters/bca-provider.js";
import type {
  MeteringHook,
  MeteringTick,
  StateMachine,
  TopicToGroup,
  TxidProvider,
} from "../../runtime/session-protocol/src/types.js";
import type { DuplicatePathEvent } from "../../runtime/session-protocol/src/adapters/multicast-adapter.js";
import type {
  NetworkEvent,
  PublishableObject,
} from "../../core/protocol-types/src/network.js";
import { SessionRuntime } from "../../runtime/session-protocol/src/runtime.js";
import {
  PlexusCertBCAProvider,
  DeterministicBCAProvider as DetBCAProviderForG35A5,
} from "../../runtime/session-protocol/src/adapters/bca-provider.js";
import {
  deriveBCABytes,
  bcaBytesToIPv6,
  StubSigner as StubSignerForG35A5,
} from "../../runtime/session-protocol/src/signer.js";
import { readFileSync as readFileSyncG35A5 } from "node:fs";
import { join as joinG35A5 } from "node:path";

// ---------------------------------------------------------------------------
// G35A.11 — Signer composability round-trip
// ---------------------------------------------------------------------------

describe("Phase 35A gate — G35A.11 signer round-trip", () => {
  it("BsvSdkSigner + BsvSdkVerifier round-trip on a 1KB payload", async () => {
    const { PrivateKey } = await import("@bsv/sdk");
    const priv = PrivateKey.fromRandom();
    const bcaDeriver = async () => "2602:f9f8::abcd";
    const signer = new BsvSdkSigner(priv, bcaDeriver);
    const verifier = new BsvSdkVerifier();

    const payload = new Uint8Array(1024);
    for (let i = 0; i < payload.length; i++) payload[i] = (i * 7) & 0xff;

    const identity = await signer.identity();
    const sig = await signer.sign(payload);
    const ok = await verifier.verify(identity.pubkey, payload, sig);
    expect(ok).toBe(true);

    // Flip one byte — verification must fail.
    const tampered = new Uint8Array(payload);
    tampered[500] ^= 0xff;
    const bad = await verifier.verify(identity.pubkey, tampered, sig);
    expect(bad).toBe(false);
  });

  it("StubSigner passes the same Signer contract", async () => {
    const verifier = new BsvSdkVerifier();
    const stub = new StubSigner();
    const identity = await stub.identity();

    expect(identity.pubkey).toBeInstanceOf(Uint8Array);
    expect(identity.pubkey.length).toBe(33);
    expect(identity.bca).toMatch(/^2602:f9f8::[0-9a-f]{4}$/);

    const payload = new TextEncoder().encode("golden-vector test payload");
    const sig = await stub.sign(payload);
    const ok = await verifier.verify(identity.pubkey, payload, sig);
    expect(ok).toBe(true);
  });

  it("StubSigner with fixed seed is deterministic across constructions", async () => {
    const seed = "42".repeat(32);
    const a = new StubSigner(seed);
    const b = new StubSigner(seed);
    const idA = await a.identity();
    const idB = await b.identity();
    expect(idA.bca).toBe(idB.bca);
    expect(Array.from(idA.pubkey)).toEqual(Array.from(idB.pubkey));
  });
});

// ---------------------------------------------------------------------------
// G35A.8 — UdpTransport multi-group membership API
// ---------------------------------------------------------------------------

describe("Phase 35A gate — G35A.8 UdpTransport membership", () => {
  it("addMembership / dropMembership update memberships() set", async () => {
    LoopbackUdpTransport.resetAll();
    const t = new LoopbackUdpTransport("2602:f9f8::1");
    await t.bind(8080);
    expect(t.memberships().size).toBe(0);

    await t.addMembership("ff02::1");
    expect(t.memberships()).toEqual(new Set(["ff02::1"]));

    await t.addMembership("ff02::2");
    expect(t.memberships()).toEqual(new Set(["ff02::1", "ff02::2"]));

    // Idempotent add
    await t.addMembership("ff02::1");
    expect(t.memberships().size).toBe(2);

    await t.dropMembership("ff02::1");
    expect(t.memberships()).toEqual(new Set(["ff02::2"]));

    // Idempotent drop
    await t.dropMembership("ff02::1");
    expect(t.memberships()).toEqual(new Set(["ff02::2"]));

    await t.close();
  });

  it("bind with initial multicastGroup joins it", async () => {
    LoopbackUdpTransport.resetAll();
    const t = new LoopbackUdpTransport("2602:f9f8::2");
    await t.bind(8081, "ff02::1");
    expect(t.memberships()).toEqual(new Set(["ff02::1"]));
    await t.close();
  });

  it("messages reach only peers that joined the group", async () => {
    LoopbackUdpTransport.resetAll();
    const sender = new LoopbackUdpTransport("2602:f9f8::100");
    const inGroup = new LoopbackUdpTransport("2602:f9f8::101");
    const notInGroup = new LoopbackUdpTransport("2602:f9f8::102");
    await sender.bind(9000, "ff02::abc");
    await inGroup.bind(9000, "ff02::abc");
    await notInGroup.bind(9000); // bound on same port but not in group

    const received: string[] = [];
    inGroup.onMessage((msg) => {
      received.push(`in:${new TextDecoder().decode(msg)}`);
    });
    notInGroup.onMessage((msg) => {
      received.push(`out:${new TextDecoder().decode(msg)}`);
    });

    await sender.send(new TextEncoder().encode("hello"), 9000, "ff02::abc");
    // Wait for microtask delivery
    await new Promise((resolve) => setTimeout(resolve, 10));

    expect(received).toEqual(["in:hello"]);

    await sender.close();
    await inGroup.close();
    await notInGroup.close();
  });

  it("dropMembership stops delivery", async () => {
    LoopbackUdpTransport.resetAll();
    const sender = new LoopbackUdpTransport("2602:f9f8::200");
    const receiver = new LoopbackUdpTransport("2602:f9f8::201");
    await sender.bind(9100, "ff02::xyz");
    await receiver.bind(9100, "ff02::xyz");

    const received: string[] = [];
    receiver.onMessage((msg) => {
      received.push(new TextDecoder().decode(msg));
    });

    await sender.send(new TextEncoder().encode("first"), 9100, "ff02::xyz");
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(received).toEqual(["first"]);

    await receiver.dropMembership("ff02::xyz");
    expect(receiver.memberships().size).toBe(0);

    await sender.send(new TextEncoder().encode("second"), 9100, "ff02::xyz");
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(received).toEqual(["first"]); // 'second' dropped

    await sender.close();
    await receiver.close();
  });

  it("NodeUdpTransport is exported with matching shape", () => {
    // Only verify the class exists and exposes the new membership API —
    // don't bind a real socket in the gate test (Docker-only concern).
    expect(typeof NodeUdpTransport).toBe("function");
    const instance = new NodeUdpTransport("::1");
    expect(typeof instance.addMembership).toBe("function");
    expect(typeof instance.dropMembership).toBe("function");
    expect(typeof instance.memberships).toBe("function");
    expect(instance.memberships().size).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// G35A.2 / G35A.3 / G35A.6 / G35A.7 — MulticastAdapter gates
// ---------------------------------------------------------------------------

/** Build a counter-based TxidProvider so we can assert mint was called. */
function counterTxidProvider(): TxidProvider & { count: number } {
  const self = {
    count: 0,
    async mint(_cellBytes: Uint8Array): Promise<string> {
      self.count++;
      return "tx" + self.count.toString(16).padStart(62, "0");
    },
  };
  return self;
}

function samplePublishable(
  path: string,
  owner: string,
  content: string,
): PublishableObject {
  return {
    cellBytes: new TextEncoder().encode(content),
    semanticPath: path,
    contentHash: `content-${content}`,
    ownerCert: owner,
    typeHash: "type-generic",
  };
}

async function buildAdapter(options: {
  bcaIndex: number;
  topicToGroup?: TopicToGroup;
  txidProvider?: TxidProvider;
  maxPayload?: number;
  primaryGroup?: string;
  port?: number;
  transport?: LoopbackUdpTransport;
}) {
  const identity = new DeterministicBCAProvider(options.bcaIndex);
  const bca = await identity.deriveBCA();
  const transport = options.transport ?? new LoopbackUdpTransport(bca);
  const txidProvider = options.txidProvider ?? counterTxidProvider();
  const adapter = new MulticastAdapter({
    identity,
    transport,
    txidProvider,
    topicToGroup: options.topicToGroup,
    primaryGroup: options.primaryGroup,
    maxPayload: options.maxPayload,
    port: options.port ?? 5683,
    heartbeatIntervalMs: 60_000, // quiet during tests
    staleTimeoutMs: 60_000,
  });
  await adapter.start();
  return { adapter, transport, txidProvider };
}

describe("Phase 35A gate — G35A.2 publish with default topicToGroup", () => {
  it("all subscribers receive published cells on the primary group", async () => {
    LoopbackUdpTransport.resetAll();
    const a = await buildAdapter({ bcaIndex: 1, port: 5700 });
    const b = await buildAdapter({ bcaIndex: 2, port: 5700 });
    const c = await buildAdapter({ bcaIndex: 3, port: 5700 });

    const received: Record<string, NetworkEvent[]> = { b: [], c: [] };
    b.adapter.subscribe("tm_widgets", (ev) => received.b.push(ev));
    c.adapter.subscribe("tm_widgets", (ev) => received.c.push(ev));

    await a.adapter.publish(samplePublishable("/widgets/a", "owner-a", "one"), {
      topic: "tm_widgets",
    });
    await new Promise((r) => setTimeout(r, 20));

    expect(received.b.length).toBe(1);
    expect(received.c.length).toBe(1);
    expect(received.b[0]!.type).toBe("object_published");

    await a.adapter.stop();
    await b.adapter.stop();
    await c.adapter.stop();
  });
});

describe("Phase 35A gate — G35A.3 Phase-34-style topicToGroup filtering", () => {
  it("non-subscribing nodes don't observe messages outside their joined group", async () => {
    LoopbackUdpTransport.resetAll();

    // Each topic maps to its own group; transport-level membership gates delivery.
    const topicToGroup: TopicToGroup = (topic) => `ff02::${topic.slice(-2)}`;

    const a = await buildAdapter({
      bcaIndex: 10,
      port: 5710,
      topicToGroup,
      primaryGroup: "ff02::10",
    });
    const b = await buildAdapter({
      bcaIndex: 11,
      port: 5710,
      topicToGroup,
      primaryGroup: "ff02::11",
    });
    const c = await buildAdapter({
      bcaIndex: 12,
      port: 5710,
      topicToGroup,
      primaryGroup: "ff02::12",
    });

    const bReceived: NetworkEvent[] = [];
    const cReceived: NetworkEvent[] = [];
    b.adapter.subscribe("tm_alpha_aa", (ev) => bReceived.push(ev));
    c.adapter.subscribe("tm_beta_bb", (ev) => cReceived.push(ev));

    // Give the transport a moment to register new memberships.
    await new Promise((r) => setTimeout(r, 10));

    await a.adapter.publish(
      samplePublishable("/alpha/a", "owner-a", "A"),
      { topic: "tm_alpha_aa" },
    );
    await new Promise((r) => setTimeout(r, 20));

    // Only b joined group ff02::aa; c joined ff02::bb, so c must NOT receive.
    expect(bReceived.length).toBe(1);
    expect(cReceived.length).toBe(0);

    await a.adapter.stop();
    await b.adapter.stop();
    await c.adapter.stop();
  });
});

describe("Phase 35A gate — G35A.6 TxidProvider injection", () => {
  it("adapter mints every publish txid through the injected provider", async () => {
    LoopbackUdpTransport.resetAll();
    const txidProvider = counterTxidProvider();
    const { adapter } = await buildAdapter({
      bcaIndex: 20,
      port: 5720,
      txidProvider,
    });

    expect(txidProvider.count).toBe(0);
    await adapter.publish(samplePublishable("/x/1", "owner-x", "v1"));
    await adapter.publish(samplePublishable("/x/2", "owner-x", "v2"));
    await adapter.publish(samplePublishable("/x/3", "owner-x", "v3"));
    expect(txidProvider.count).toBe(3);

    await adapter.stop();
  });

  it("rejects oversize publishes with PayloadTooLargeError", async () => {
    LoopbackUdpTransport.resetAll();
    const { adapter } = await buildAdapter({
      bcaIndex: 21,
      port: 5721,
      maxPayload: 64,
    });

    const big = samplePublishable("/big", "owner-big", "x".repeat(1024));
    let error: unknown;
    try {
      await adapter.publish(big);
    } catch (e) {
      error = e;
    }
    expect(error).toBeInstanceOf(PayloadTooLargeError);

    await adapter.stop();
  });
});

describe("Phase 35A gate — G35A.7 duplicate-path detection", () => {
  it("fires duplicate_path observer when two owners publish to the same path", async () => {
    LoopbackUdpTransport.resetAll();
    const a = await buildAdapter({ bcaIndex: 30, port: 5730 });
    const b = await buildAdapter({ bcaIndex: 31, port: 5730 });

    const events: DuplicatePathEvent[] = [];
    b.adapter.onDuplicatePath((ev) => events.push(ev));
    // b also needs to observe the cells to record them, so subscribe
    b.adapter.subscribe("tm_contest", () => {});

    await a.adapter.publish(
      samplePublishable("/contested", "owner-a", "first"),
      { topic: "tm_contest" },
    );
    await new Promise((r) => setTimeout(r, 20));

    // Now b publishes to the same path with its own ownerCert.
    await b.adapter.publish(
      samplePublishable("/contested", "owner-b", "second"),
      { topic: "tm_contest" },
    );
    await new Promise((r) => setTimeout(r, 20));

    expect(events.length).toBeGreaterThanOrEqual(1);
    const ev = events[0]!;
    expect(ev.semanticPath).toBe("/contested");
    expect(
      [ev.existingOwner, ev.newOwner].sort(),
    ).toEqual(["owner-a", "owner-b"]);

    await a.adapter.stop();
    await b.adapter.stop();
  });

  it("does NOT fire duplicate_path when the same owner re-publishes", async () => {
    LoopbackUdpTransport.resetAll();
    const { adapter } = await buildAdapter({ bcaIndex: 40, port: 5740 });
    const events: DuplicatePathEvent[] = [];
    adapter.onDuplicatePath((ev) => events.push(ev));

    await adapter.publish(samplePublishable("/p", "owner-self", "v1"));
    await adapter.publish(samplePublishable("/p", "owner-self", "v2"));
    expect(events.length).toBe(0);

    await adapter.stop();
  });
});

// ---------------------------------------------------------------------------
// G35A.1 / G35A.9 / G35A.10 — SessionRuntime end-to-end
// ---------------------------------------------------------------------------

/**
 * A trivial state machine: transitions `idle → ponging → done` driven by a
 * `ping` event followed by a `pong` event. Used for G35A.1 and G35A.9.
 */
type PingPongEvent = { type: "ping" } | { type: "pong" };
type PingPongState = "idle" | "ponging" | "done";

function pingPongStateMachine(opts?: {
  meterOnPong?: boolean;
}): StateMachine<PingPongEvent, PingPongState> {
  return {
    initialState: "idle",
    terminalStates: new Set<PingPongState>(["done"]),
    validate: () => true,
    transition(current, event) {
      if (current === "idle" && event.type === "ping") {
        return {
          next: "ponging",
          emit: [{ type: "pong" }],
        };
      }
      if (current === "ponging" && event.type === "pong") {
        const result: {
          next: PingPongState;
          meterTick?: MeteringTick;
        } = { next: "done" };
        if (opts?.meterOnPong) {
          result.meterTick = {
            channelId: "ch-pingpong",
            seq: 1,
            sats: 1,
            eventHash: new Uint8Array(32),
          };
        }
        return result;
      }
      return { next: current };
    },
  };
}

async function buildSessionPair(opts?: {
  meterOnPong?: boolean;
  hookA?: MeteringHook;
  hookB?: MeteringHook;
  port?: number;
}) {
  LoopbackUdpTransport.resetAll();
  const a = await buildAdapter({
    bcaIndex: 50,
    port: opts?.port ?? 5750,
  });
  const b = await buildAdapter({
    bcaIndex: 51,
    port: opts?.port ?? 5750,
  });

  const descriptor = {
    id: "s1",
    minParty: 2,
    maxParty: 2,
    topic: "tm_ping_pong",
  };
  const runtimeA = new SessionRuntime<PingPongEvent, PingPongState>({
    descriptor,
    stateMachine: pingPongStateMachine({
      meterOnPong: opts?.meterOnPong,
    }),
    adapter: a.adapter,
    meteringHook: opts?.hookA,
  });
  const runtimeB = new SessionRuntime<PingPongEvent, PingPongState>({
    descriptor,
    stateMachine: pingPongStateMachine({
      meterOnPong: opts?.meterOnPong,
    }),
    adapter: b.adapter,
    meteringHook: opts?.hookB,
  });

  await runtimeA.start();
  await runtimeB.start();
  return { a, b, runtimeA, runtimeB };
}

describe("Phase 35A gate — G35A.1 session-runtime forms a session", () => {
  it("two SessionRuntimes on loopback reach the same terminal state", async () => {
    const { a, b, runtimeA, runtimeB } = await buildSessionPair();

    // A sends ping → both observe the full ping/pong sequence via the adapter.
    await runtimeA.submit({ type: "ping" });
    await new Promise((r) => setTimeout(r, 40));

    // A's local transition: idle → ponging (emits pong) → done.
    expect(runtimeA.state).toBe("done");
    // B receives the ping from the wire: idle → ponging, then receives the
    // pong emit that A produced locally AND that A published: B lands in done.
    expect(runtimeB.state).toBe("done");

    await runtimeA.stop();
    await runtimeB.stop();
    await a.adapter.stop();
    await b.adapter.stop();
  });
});

describe("Phase 35A gate — G35A.9 state-machine polymorphism", () => {
  it("a MinimalStateMachine drives the runtime end-to-end", async () => {
    const { a, b, runtimeA, runtimeB } = await buildSessionPair({
      port: 5760,
    });

    const seenA: PingPongState[] = [runtimeA.state];
    const seenB: PingPongState[] = [runtimeB.state];
    runtimeA.onTransition((next) => seenA.push(next));
    runtimeB.onTransition((next) => seenB.push(next));

    await runtimeA.submit({ type: "ping" });
    await new Promise((r) => setTimeout(r, 40));

    // The plug-in contract pushes idle → ponging → done through both runtimes.
    expect(seenA[seenA.length - 1]).toBe("done");
    expect(seenB[seenB.length - 1]).toBe("done");
    expect(seenA).toContain("ponging");
    expect(seenB).toContain("ponging");

    await runtimeA.stop();
    await runtimeB.stop();
    await a.adapter.stop();
    await b.adapter.stop();
  });
});

describe("Phase 35A gate — G35A.10 metering hook is optional + wired", () => {
  it("runtime instantiates without a MeteringHook", async () => {
    const { a, b, runtimeA, runtimeB } = await buildSessionPair({
      port: 5770,
    });
    await runtimeA.submit({ type: "ping" });
    await new Promise((r) => setTimeout(r, 40));
    expect(runtimeA.state).toBe("done");
    await runtimeA.stop();
    await runtimeB.stop();
    await a.adapter.stop();
    await b.adapter.stop();
  });

  it("fires onTick when the state machine emits a meterTick", async () => {
    const ticksA: MeteringTick[] = [];
    const ticksB: MeteringTick[] = [];
    const hookA: MeteringHook = {
      async onTick(tick) {
        ticksA.push(tick);
      },
      async onSettle() {
        /* noop */
      },
    };
    const hookB: MeteringHook = {
      async onTick(tick) {
        ticksB.push(tick);
      },
      async onSettle() {
        /* noop */
      },
    };

    const { a, b, runtimeA, runtimeB } = await buildSessionPair({
      meterOnPong: true,
      hookA,
      hookB,
      port: 5780,
    });

    await runtimeA.submit({ type: "ping" });
    await new Promise((r) => setTimeout(r, 50));

    // Both runtimes process the pong → both see the meter tick.
    expect(ticksA.length).toBe(1);
    expect(ticksB.length).toBe(1);
    expect(ticksA[0]!.channelId).toBe("ch-pingpong");
    expect(ticksA[0]!.sats).toBe(1);

    await runtimeA.stop();
    await runtimeB.stop();
    await a.adapter.stop();
    await b.adapter.stop();
  });
});

// ---------------------------------------------------------------------------
// G35A.5 — PlexusCertBCAProvider matches bca_conformance.zig vectors
// ---------------------------------------------------------------------------

interface BcaBasicVector {
  pubkey: string;
  subnetPrefix: string;
  modifier: string;
  sec: number;
  expectedAddress: string;
  expectedCollisionCount: number;
  description: string;
}

function fromHex(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    out[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return out;
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

describe("Phase 35A gate — G35A.5 BCA derivation vs golden vectors", () => {
  const vectorsPath = joinG35A5(
    import.meta.dir,
    "..",
    "..",
    "core",
    "cell-engine",
    "tests",
    "vectors",
    "bca_basic.json",
  );
  const vectors = JSON.parse(
    readFileSyncG35A5(vectorsPath, "utf8"),
  ) as BcaBasicVector[];

  it("loaded at least 4 golden vectors from bca_basic.json", () => {
    expect(vectors.length).toBeGreaterThanOrEqual(4);
  });

  it("deriveBCABytes matches every bca_basic.json vector byte-for-byte", () => {
    for (const v of vectors) {
      const got = deriveBCABytes(
        fromHex(v.pubkey),
        fromHex(v.subnetPrefix),
        fromHex(v.modifier),
        v.sec,
      );
      expect(toHex(got)).toBe(v.expectedAddress);
    }
  });

  it("bcaBytesToIPv6 round-trips 16-byte addresses to RFC-5952 strings", () => {
    // PUBKEY_1 vector → 20010db800000001186b2b5b8336ab60 → 2001:db8:0:1:186b:2b5b:8336:ab60
    const formatted = bcaBytesToIPv6(
      fromHex("20010db800000001186b2b5b8336ab60"),
    );
    expect(formatted).toBe("2001:db8:0:1:186b:2b5b:8336:ab60");

    // All-zero tail compresses properly.
    expect(bcaBytesToIPv6(fromHex("2602f9f800000000000000000000abcd"))).toBe(
      "2602:f9f8::abcd",
    );
    // All-zero address → ::
    expect(bcaBytesToIPv6(new Uint8Array(16))).toBe("::");
  });

  it("PlexusCertBCAProvider.deriveBCA() matches vector #1 end-to-end", async () => {
    const v = vectors[0]!;
    // Drive a StubSigner whose pubkey equals the vector's pubkey — we use
    // a config with a custom deriver that ignores the signer's pubkey and
    // uses the vector's pubkey directly, so we can exercise the provider
    // without reverse-engineering a seed.
    const stubSigner = new StubSignerForG35A5();
    const vectorPubkey = fromHex(v.pubkey);
    const provider = new PlexusCertBCAProvider({
      signer: stubSigner,
      subnetPrefix: fromHex(v.subnetPrefix),
      modifier: fromHex(v.modifier),
      sec: v.sec,
      deriver: (_pubkey, prefix, modifier, sec) =>
        deriveBCABytes(vectorPubkey, prefix, modifier, sec),
    });
    const bca = await provider.deriveBCA();
    expect(bca).toBe(bcaBytesToIPv6(fromHex(v.expectedAddress)));
  });

  it("PlexusCertBCAProvider delegates signing to the underlying Signer", async () => {
    const stub = new StubSignerForG35A5();
    const provider = new PlexusCertBCAProvider({ signer: stub });
    const msg = new TextEncoder().encode("hello");
    const a = await stub.sign(msg);
    const b = await provider.sign(msg);
    expect(Array.from(a)).toEqual(Array.from(b));
  });

  it("DeterministicBCAProvider coexists for legacy swarm tests", async () => {
    const p = new DetBCAProviderForG35A5(0x2a);
    expect(await p.deriveBCA()).toBe("2602:f9f8::002a");
  });
});

// ---------------------------------------------------------------------------
// G35A.4 — Poker-agent behaviour-parity (skeleton-consumer regression)
// ---------------------------------------------------------------------------
//
// Scope note: the production-grade poker agent lives in the standalone
// todriguez/hackathon-submission repo. `apps/poker-agent/` in semantos-core
// is the skeleton consumer that demonstrates session-protocol +
// chain-broadcast integration. Behaviour parity here means:
//   1. the workspace package still compiles (covered by repo-wide
//      `bun run check`);
//   2. TableFormationService accepts a `MulticastAdapter` from
//      `@semantos/session-protocol` — proving the old
//      `DockerMulticastAdapter`-typed API was migrated cleanly;
//   3. no allowlist entry was needed in the import-boundary gate
//      (covered separately by tests/gates/import-boundaries.test.ts).

describe("Phase 35A gate — G35A.4 poker-agent skeleton consumer", () => {
  it("TableFormationService accepts a MulticastAdapter without DockerMulticastAdapter coupling", async () => {
    // Import lazily so this gate runs even if one of poker-agent's deeper
    // files fails to load — we only care about the formation surface here.
    const { TableFormationService } = await import(
      "../../apps/poker-agent/src/table-formation.js"
    );
    const { MulticastAdapter } = await import(
      "../../runtime/session-protocol/src/adapters/multicast-adapter.js"
    );
    const { DeterministicBCAProvider } = await import(
      "../../runtime/session-protocol/src/adapters/bca-provider.js"
    );
    const { LoopbackUdpTransport } = await import(
      "../../core/protocol-types/src/adapters/udp-transport.js"
    );

    LoopbackUdpTransport.resetAll();
    const identity = new DeterministicBCAProvider(99);
    const bca = await identity.deriveBCA();
    const adapter = new MulticastAdapter({
      identity,
      transport: new LoopbackUdpTransport(bca),
      txidProvider: {
        async mint() {
          return "deadbeef".padEnd(64, "0");
        },
      },
      heartbeatIntervalMs: 60_000,
      staleTimeoutMs: 60_000,
    });
    await adapter.start();

    // The key compile-level invariant: this ctor signature accepts the new
    // MulticastAdapter. Before step 5 it required DockerMulticastAdapter.
    const service = new TableFormationService({
      adapter,
      profile: {
        botIndex: 99,
        bca,
        persona: "observer",
        minStake: 1,
        maxStake: 10,
      },
      minPlayers: 2,
      maxPlayers: 6,
      discoveryIntervalMs: 60_000,
    });

    expect(service).toBeDefined();
    expect(typeof (service as { start?: unknown }).start).toBe("function");

    await adapter.stop();
  });

  it("poker-agent's barrel declares the expected exports (source-level check)", () => {
    // Static check — reading the barrel source rather than importing it at
    // runtime. Importing pulls in transitive deps (packages/games,
    // runtime/shell, …) which carry their own pre-existing broken relative
    // imports from the tier restructure. Those are out of scope for 35A;
    // the real regression we care about is "did the barrel lose an export
    // under the session-protocol migration?" — a source grep catches that.
    const barrelPath = joinG35A5(
      import.meta.dir,
      "..",
      "..",
      "apps",
      "poker-agent",
      "src",
      "index.ts",
    );
    const src = readFileSyncG35A5(barrelPath, "utf8");
    const expected = [
      "GameStateDB",
      "AgentRuntime",
      "PERSONALITIES",
      "GameLoop",
      "PokerStateMachine",
      "DirectPokerStateMachine",
      "PokerMessageTransport",
      "P2PAgentRunner",
      "AgentDiscoveryService",
      "PaymentChannelManager",
      "DirectBroadcastEngine",
    ];
    for (const name of expected) {
      // Accept the name either as a value export `{ Name }` or a type export
      // `type { Name }`. The grep is loose on purpose — refactors that
      // re-group exports are fine; dropping one is not.
      expect(src).toContain(name);
    }
  });
});

// ---------------------------------------------------------------------------
// G35A.12 — Static choke-point: @bsv/sdk imported only by signer.ts
// ---------------------------------------------------------------------------

describe("Phase 35A gate — G35A.12 single @bsv/sdk choke point", () => {
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

  it("only signer.ts and bsv-* adapters import @bsv/sdk", () => {
    // Match any import specifier starting with @bsv/sdk (the bare
    // package, @bsv/sdk/overlay-tools/*, any subpath).
    const bsvSdkImport = /from\s+['"]@bsv\/sdk(?:\/[^'"]*)?['"]/;
    const offenders: string[] = [];

    // Allowed: `signer.ts` is the historical identity/signing
    // choke-point. Files whose BASENAME starts with `bsv-` are
    // explicit BSV-specific adapters (e.g. `bsv-overlay-bundle-*`,
    // `adapters/bsv-wallet-signer.ts`) — they embody the SDK-vs-
    // Plexus swap boundary rather than hide it. Any other file
    // reaching for @bsv/sdk is a leak.
    const isAllowed = (rel: string): boolean => {
      if (rel === "signer.ts") return true;
      const basename = rel.split("/").pop() ?? rel;
      return basename.startsWith("bsv-");
    };

    for (const file of walk(SESSION_PROTOCOL_SRC)) {
      const rel = relative(SESSION_PROTOCOL_SRC, file);
      if (isAllowed(rel)) continue;
      const src = readFileSync(file, "utf8");
      if (bsvSdkImport.test(src)) offenders.push(rel);
    }

    expect(offenders).toEqual([]);
  });
});

```
