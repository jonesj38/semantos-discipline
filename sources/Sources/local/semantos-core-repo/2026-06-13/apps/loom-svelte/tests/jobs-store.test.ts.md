---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/jobs-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.056511+00:00
---

# apps/loom-svelte/tests/jobs-store.test.ts

```ts
// jobs-store.ts unit tests.
//
// Mirrors tests/customers-store.test.ts.  Asserts:
//   • jobsTick increments on `job.transitioned` (existing FSM move);
//   • jobsTick increments on `cell.created` (a NEW lead/job cell minted —
//     the live-refresh fix so freshly-ingested leads appear without reload);
//   • jobsTick stays put on unrelated event types;
//   • the wireJobsTick disposer cleanly unregisters the listener.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { get } from "svelte/store";

import {
  HelmEventStream,
  type HelmSocket,
} from "../src/lib/helm-event-stream";
import { jobsTick, wireJobsTick } from "../src/lib/jobs-store";

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
    topics: ["jobs"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
  });
  stream.connect();
  socket!.open();
  return { stream, socket: socket! };
}

function emit(socket: FakeSocket, type: string): void {
  socket.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { type, data: {} },
    }),
  );
}

test("jobsTick increments on job.transitioned event", () => {
  const { stream, socket } = makeStream();
  const before = get(jobsTick);
  const unsub = wireJobsTick(stream);
  emit(socket, "job.transitioned");
  assert.equal(get(jobsTick), before + 1);
  unsub();
  stream.disconnect();
});

test("jobsTick increments on cell.created (new lead/job minted)", () => {
  const { stream, socket } = makeStream();
  const before = get(jobsTick);
  const unsub = wireJobsTick(stream);
  emit(socket, "cell.created");
  assert.equal(get(jobsTick), before + 1);
  unsub();
  stream.disconnect();
});

test("jobsTick stays put on unrelated event type", () => {
  const { stream, socket } = makeStream();
  const before = get(jobsTick);
  const unsub = wireJobsTick(stream);
  emit(socket, "invoice.sent");
  assert.equal(get(jobsTick), before);
  unsub();
  stream.disconnect();
});

test("wireJobsTick disposer stops further increments", () => {
  const { stream, socket } = makeStream();
  const unsub = wireJobsTick(stream);
  emit(socket, "cell.created");
  const after = get(jobsTick);
  unsub();
  emit(socket, "cell.created");
  assert.equal(get(jobsTick), after);
  stream.disconnect();
});

```
