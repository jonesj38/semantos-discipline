---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/visits-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.060516+00:00
---

# apps/loom-svelte/tests/visits-store.test.ts

```ts
// D-O5.followup-4 — visits-store.ts unit tests.
//
// Mirrors customers-store.test.ts.  Asserts visitsTick increments on
// both visit.created AND visit.transitioned, ignores unrelated event
// types, and the wireVisitsTick disposer stops further increments.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { get } from "svelte/store";

import {
  HelmEventStream,
  type HelmSocket,
} from "../src/lib/helm-event-stream";
import { visitsTick, wireVisitsTick } from "../src/lib/visits-store";

class FakeSocket implements HelmSocket {
  sent: string[] = [];
  closed = false;
  private listeners: Record<string, ((ev: any) => void)[]> = {};
  send(data: string): void {
    this.sent.push(data);
  }
  close(): void {
    this.closed = true;
    this.dispatch("close", { code: 1000, reason: "" });
  }
  addEventListener(event: string, handler: (ev: any) => void): void {
    (this.listeners[event] ??= []).push(handler);
  }
  open(): void {
    this.dispatch("open", {});
  }
  message(data: string): void {
    this.dispatch("message", { data });
  }
  private dispatch(event: string, ev: unknown): void {
    const ls = this.listeners[event] ?? [];
    for (const l of ls) l(ev);
  }
}

function makeStream(): { stream: HelmEventStream; socket: FakeSocket } {
  let socket: FakeSocket | null = null;
  const stream = new HelmEventStream({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "a".repeat(64),
    topics: ["visits"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
  });
  stream.connect();
  socket!.open();
  return { stream, socket: socket! };
}

test("visitsTick increments on visit.created event", () => {
  const { stream, socket } = makeStream();
  const before = get(visitsTick);
  const unsub = wireVisitsTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "visit.created", data: { id: "v-001" } },
    }),
  );
  assert.equal(get(visitsTick), before + 1);
  unsub();
  stream.disconnect();
});

test("visitsTick increments on visit.transitioned event", () => {
  const { stream, socket } = makeStream();
  const before = get(visitsTick);
  const unsub = wireVisitsTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: {
        type: "visit.transitioned",
        data: { id: "v-001", from: "scheduled", to: "in_progress" },
      },
    }),
  );
  assert.equal(get(visitsTick), before + 1);
  unsub();
  stream.disconnect();
});

test("visitsTick stays put on unrelated event type", () => {
  const { stream, socket } = makeStream();
  const before = get(visitsTick);
  const unsub = wireVisitsTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "job.transitioned", data: { id: "job-001" } },
    }),
  );
  assert.equal(get(visitsTick), before);
  unsub();
  stream.disconnect();
});

test("wireVisitsTick disposer stops further increments", () => {
  const { stream, socket } = makeStream();
  const unsub = wireVisitsTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "visit.created", data: { id: "v-1" } },
    }),
  );
  const after = get(visitsTick);
  unsub();
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "visit.created", data: { id: "v-2" } },
    }),
  );
  assert.equal(get(visitsTick), after);
  stream.disconnect();
});

```
