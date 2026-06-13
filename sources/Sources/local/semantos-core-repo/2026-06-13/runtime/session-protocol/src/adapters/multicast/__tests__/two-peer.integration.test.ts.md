---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/__tests__/two-peer.integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.070216+00:00
---

# runtime/session-protocol/src/adapters/multicast/__tests__/two-peer.integration.test.ts

```ts
/**
 * Two-peer integration test — proves the codec / peer / subscription /
 * outbound layers compose without a real UDP socket.
 *
 * Per the prompt-38 test plan: "Two peers over in-memory transport
 * exchange envelopes; subscription fan-out delivers each envelope to
 * every subscriber exactly once."
 */

import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import {
  LoopbackUdpTransport,
} from "@semantos/protocol-types/adapters/udp-transport";
import type {
  NetworkEvent,
  PublishableObject,
} from "@semantos/protocol-types/network";

import { DeterministicBCAProvider } from "../../bca-provider";
import { MulticastAdapter } from "../multicast-adapter";
import { createJsonCodec } from "../ports/codec-port";

let counter = 0;
const txidProvider = {
  mint: async () => `tx${(++counter).toString().padStart(64, "0")}`,
};

function makePublishable(
  overrides: Partial<PublishableObject> = {},
): PublishableObject {
  return {
    cellBytes: new Uint8Array([1, 2, 3, 4]),
    semanticPath: "/x/y",
    contentHash: "c".repeat(64),
    ownerCert: "owner-a",
    typeHash: "T".repeat(64),
    parentPath: undefined,
    ...overrides,
  };
}

function makeAdapter(index: number, port: number): {
  adapter: MulticastAdapter;
  transport: LoopbackUdpTransport;
} {
  return makeAdapterWith(index, port, {});
}

function makeAdapterWith(
  index: number,
  port: number,
  overrides: { heartbeatIntervalMs?: number; staleTimeoutMs?: number },
): { adapter: MulticastAdapter; transport: LoopbackUdpTransport } {
  const transport = new LoopbackUdpTransport(`fe80::${index}`);
  const adapter = new MulticastAdapter({
    identity: new DeterministicBCAProvider(index),
    transport,
    txidProvider,
    codec: createJsonCodec(),
    port,
    primaryGroup: "ff02::1",
    heartbeatIntervalMs: overrides.heartbeatIntervalMs ?? 60_000,
    staleTimeoutMs: overrides.staleTimeoutMs ?? 60_000,
  });
  return { adapter, transport };
}

beforeEach(() => {
  LoopbackUdpTransport.resetAll();
  counter = 0;
});

afterEach(async () => {
  LoopbackUdpTransport.resetAll();
});

describe("MulticastAdapter — two-peer integration", () => {
  test("peer B receives a cell published by peer A", async () => {
    const a = makeAdapter(1, 5683);
    const b = makeAdapter(2, 5683);
    await a.adapter.start();
    await b.adapter.start();

    const received: NetworkEvent[] = [];
    b.adapter.subscribe("tm_semantos_objects", (e) => received.push(e));

    await a.adapter.publish(makePublishable());

    // LoopbackUdpTransport delivers via queueMicrotask — give it a tick.
    await new Promise<void>((r) => queueMicrotask(r));
    await new Promise<void>((r) => queueMicrotask(r));

    expect(received.length).toBe(1);
    expect(received[0]?.result.semanticPath).toBe("/x/y");
    expect(received[0]?.result.ownerCert).toBe("owner-a");

    await a.adapter.stop();
    await b.adapter.stop();
  });

  test("subscription fan-out delivers each envelope exactly once per subscriber", async () => {
    const a = makeAdapter(3, 5684);
    const b = makeAdapter(4, 5684);
    await a.adapter.start();
    await b.adapter.start();

    const fan1: NetworkEvent[] = [];
    const fan2: NetworkEvent[] = [];
    b.adapter.subscribe("tm_semantos_objects", (e) => fan1.push(e));
    b.adapter.subscribe("tm_semantos_objects", (e) => fan2.push(e));

    const N = 20;
    for (let i = 0; i < N; i++) {
      await a.adapter.publish(
        makePublishable({ semanticPath: `/p${i}`, ownerCert: `o${i}` }),
      );
    }

    // Drain the queueMicrotask deliveries.
    await new Promise<void>((r) => setTimeout(r, 10));

    expect(fan1.length).toBe(N);
    expect(fan2.length).toBe(N);
    const paths1 = fan1.map((e) => e.result.semanticPath).sort();
    const paths2 = fan2.map((e) => e.result.semanticPath).sort();
    expect(paths1).toEqual(paths2);

    await a.adapter.stop();
    await b.adapter.stop();
  });

  test("heartbeats register peer B on adapter A and vice versa", async () => {
    // Use shorter heartbeat so both peers re-emit during the wait window.
    const a = makeAdapterWith(5, 5685, { heartbeatIntervalMs: 30 });
    const b = makeAdapterWith(6, 5685, { heartbeatIntervalMs: 30 });
    await a.adapter.start();
    await b.adapter.start();

    await new Promise<void>((r) => setTimeout(r, 200));

    const peersOfA = a.adapter.discoverPeers().map((p) => p.bca);
    const peersOfB = b.adapter.discoverPeers().map((p) => p.bca);
    expect(peersOfA).toContain("2602:f9f8::0006");
    expect(peersOfB).toContain("2602:f9f8::0005");

    await a.adapter.stop();
    await b.adapter.stop();
  });

  test("isConnected + getNodeBCA flip with start/stop", async () => {
    const a = makeAdapter(7, 5686);
    expect(a.adapter.isConnected()).toBe(false);
    expect(a.adapter.getNodeBCA()).toBeNull();
    await a.adapter.start();
    expect(a.adapter.isConnected()).toBe(true);
    expect(a.adapter.getNodeBCA()).toBe("2602:f9f8::0007");
    await a.adapter.stop();
    expect(a.adapter.isConnected()).toBe(false);
  });

  test("publish populates the local object-store for resolve()", async () => {
    const a = makeAdapter(8, 5687);
    await a.adapter.start();
    await a.adapter.publish(
      makePublishable({ semanticPath: "/look-me-up" }),
    );
    const found = await a.adapter.resolve({ path: "/look-me-up" });
    expect(found.length).toBe(1);
    expect(found[0]?.semanticPath).toBe("/look-me-up");
    await a.adapter.stop();
  });
});

```
