---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/customers-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.062742+00:00
---

# apps/loom-svelte/tests/customers-store.test.ts

```ts
// D-O5.followup-4 — customers-store.ts unit tests.
//
// Mirrors the shape of `tests/helm-event-stream.test.ts`'s FakeSocket
// drive-the-stream pattern.  Asserts:
//   • customersTick increments on a `customer.created` event;
//   • customersTick stays put on unrelated event types;
//   • the wireCustomersTick disposer cleanly unregisters the listener
//     (no further increments after dispose).

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { get } from "svelte/store";

import {
  HelmEventStream,
  type HelmSocket,
} from "../src/lib/helm-event-stream";
import { customersTick, wireCustomersTick } from "../src/lib/customers-store";

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
    topics: ["customers"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
  });
  stream.connect();
  socket!.open();
  return { stream, socket: socket! };
}

test("customersTick increments on customer.created event", () => {
  const { stream, socket } = makeStream();
  const before = get(customersTick);
  const unsub = wireCustomersTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "customer.created", data: { id: "cust-001" } },
    }),
  );
  assert.equal(get(customersTick), before + 1);
  unsub();
  stream.disconnect();
});

test("customersTick increments on customer.upserted (the brain's actual event)", () => {
  const { stream, socket } = makeStream();
  const before = get(customersTick);
  const unsub = wireCustomersTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "customer.upserted", data: { id: "cust-002" } },
    }),
  );
  assert.equal(get(customersTick), before + 1);
  unsub();
  stream.disconnect();
});

test("customersTick increments on cell.created (new cell minted)", () => {
  const { stream, socket } = makeStream();
  const before = get(customersTick);
  const unsub = wireCustomersTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "cell.created", data: {} },
    }),
  );
  assert.equal(get(customersTick), before + 1);
  unsub();
  stream.disconnect();
});

test("customersTick stays put on unrelated event type", () => {
  const { stream, socket } = makeStream();
  const before = get(customersTick);
  const unsub = wireCustomersTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "job.transitioned", data: { id: "job-001" } },
    }),
  );
  assert.equal(get(customersTick), before);
  unsub();
  stream.disconnect();
});

test("wireCustomersTick disposer stops further increments", () => {
  const { stream, socket } = makeStream();
  const unsub = wireCustomersTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "customer.created", data: { id: "c-1" } },
    }),
  );
  const after = get(customersTick);
  unsub();
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "customer.created", data: { id: "c-2" } },
    }),
  );
  assert.equal(get(customersTick), after);
  stream.disconnect();
});

```
