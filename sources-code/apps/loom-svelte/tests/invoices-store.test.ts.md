---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/invoices-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.057587+00:00
---

# apps/loom-svelte/tests/invoices-store.test.ts

```ts
// D-O5.followup-4 — invoices-store.ts unit tests.
//
// Mirrors quotes-store.test.ts.  Asserts invoicesTick increments on
// invoice.created AND invoice.transitioned, ignores unrelated event
// types, and wireInvoicesTick disposer stops further increments.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { get } from "svelte/store";

import {
  HelmEventStream,
  type HelmSocket,
} from "../src/lib/helm-event-stream";
import { invoicesTick, wireInvoicesTick } from "../src/lib/invoices-store";

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
    topics: ["invoices"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
  });
  stream.connect();
  socket!.open();
  return { stream, socket: socket! };
}

test("invoicesTick increments on invoice.created event", () => {
  const { stream, socket } = makeStream();
  const before = get(invoicesTick);
  const unsub = wireInvoicesTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "invoice.created", data: { id: "i-001" } },
    }),
  );
  assert.equal(get(invoicesTick), before + 1);
  unsub();
  stream.disconnect();
});

test("invoicesTick increments on invoice.transitioned event", () => {
  const { stream, socket } = makeStream();
  const before = get(invoicesTick);
  const unsub = wireInvoicesTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: {
        type: "invoice.transitioned",
        data: { id: "i-001", from: "sent", to: "paid" },
      },
    }),
  );
  assert.equal(get(invoicesTick), before + 1);
  unsub();
  stream.disconnect();
});

test("invoicesTick stays put on unrelated event type", () => {
  const { stream, socket } = makeStream();
  const before = get(invoicesTick);
  const unsub = wireInvoicesTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "customer.created", data: { id: "cust-001" } },
    }),
  );
  assert.equal(get(invoicesTick), before);
  unsub();
  stream.disconnect();
});

test("wireInvoicesTick disposer stops further increments", () => {
  const { stream, socket } = makeStream();
  const unsub = wireInvoicesTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "invoice.created", data: { id: "i-1" } },
    }),
  );
  const after = get(invoicesTick);
  unsub();
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "invoice.created", data: { id: "i-2" } },
    }),
  );
  assert.equal(get(invoicesTick), after);
  stream.disconnect();
});

```
