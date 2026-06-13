---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/attachments-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.061333+00:00
---

# apps/loom-svelte/tests/attachments-store.test.ts

```ts
// D-O5.followup-4 — attachments-store.ts unit tests.
//
// Mirrors customers-store.test.ts (attachments has no transition;
// the cell is affine write-once).  Asserts attachmentsTick increments
// on attachment.created, ignores unrelated event types, and the
// wireAttachmentsTick disposer stops further increments.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { get } from "svelte/store";

import {
  HelmEventStream,
  type HelmSocket,
} from "../src/lib/helm-event-stream";
import {
  attachmentsTick,
  wireAttachmentsTick,
} from "../src/lib/attachments-store";

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
    topics: ["attachments"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
  });
  stream.connect();
  socket!.open();
  return { stream, socket: socket! };
}

test("attachmentsTick increments on attachment.created event", () => {
  const { stream, socket } = makeStream();
  const before = get(attachmentsTick);
  const unsub = wireAttachmentsTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: {
        type: "attachment.created",
        data: { id: "att-001", visit_id: "v-001" },
      },
    }),
  );
  assert.equal(get(attachmentsTick), before + 1);
  unsub();
  stream.disconnect();
});

test("attachmentsTick stays put on unrelated event type", () => {
  const { stream, socket } = makeStream();
  const before = get(attachmentsTick);
  const unsub = wireAttachmentsTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type: "visit.created", data: { id: "v-001" } },
    }),
  );
  assert.equal(get(attachmentsTick), before);
  unsub();
  stream.disconnect();
});

test("wireAttachmentsTick disposer stops further increments", () => {
  const { stream, socket } = makeStream();
  const unsub = wireAttachmentsTick(stream);
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: {
        type: "attachment.created",
        data: { visit_id: "v-001" },
      },
    }),
  );
  const after = get(attachmentsTick);
  unsub();
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: {
        type: "attachment.created",
        data: { visit_id: "v-002" },
      },
    }),
  );
  assert.equal(get(attachmentsTick), after);
  stream.disconnect();
});

```
