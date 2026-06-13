---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/quotes-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.065226+00:00
---

# apps/loom-svelte/tests/quotes-store.test.ts

```ts
// D-O5.followup-4 — quotes-store.ts unit tests.
//
// Mirrors visits-store.test.ts.  Asserts quotesTick increments on
// quote.created AND quote.transitioned, ignores unrelated event types,
// and wireQuotesTick disposer stops further increments.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { get } from "svelte/store";

import {
  HelmEventStream,
  type HelmSocket,
} from "../src/lib/helm-event-stream";
import { quotesTick, wireQuotesTick } from "../src/lib/quotes-store";

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
    topics: ["quotes"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
  });
  stream.connect();
  socket!.open();
  return { stream, socket: socket! };
}

test("quotesTick increments on quote.created event", () => {
  const { stream, socket } = makeStream();
  const before = get(quotesTick);
  const unsub = wireQuotesTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "quote.created", data: { id: "q-001" } },
    }),
  );
  assert.equal(get(quotesTick), before + 1);
  unsub();
  stream.disconnect();
});

test("quotesTick increments on quote.transitioned event", () => {
  const { stream, socket } = makeStream();
  const before = get(quotesTick);
  const unsub = wireQuotesTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: {
        type: "quote.transitioned",
        data: { id: "q-001", from: "draft", to: "presented" },
      },
    }),
  );
  assert.equal(get(quotesTick), before + 1);
  unsub();
  stream.disconnect();
});

test("quotesTick stays put on unrelated event type", () => {
  const { stream, socket } = makeStream();
  const before = get(quotesTick);
  const unsub = wireQuotesTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "invoice.created", data: { id: "i-001" } },
    }),
  );
  assert.equal(get(quotesTick), before);
  unsub();
  stream.disconnect();
});

test("wireQuotesTick disposer stops further increments", () => {
  const { stream, socket } = makeStream();
  const unsub = wireQuotesTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "quote.created", data: { id: "q-1" } },
    }),
  );
  const after = get(quotesTick);
  unsub();
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "quote.created", data: { id: "q-2" } },
    }),
  );
  assert.equal(get(quotesTick), after);
  stream.disconnect();
});

```
