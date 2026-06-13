---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/helm-event-stream.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.066865+00:00
---

# apps/loom-svelte/tests/helm-event-stream.test.ts

```ts
// D-O5.followup-4 — HelmEventStream client test (loom-svelte side).
//
// Mirrors the Dart-side test posture
// (`apps/oddjobz-mobile/test/repl/helm_event_stream_test.dart`):
// drives a hand-rolled in-memory HelmSocket through the full lifecycle
// — connect → subscribe → ack → event parse → reconnect → disconnect.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import {
  HelmEventStream,
  type HelmEvent,
  type HelmEventStreamState,
  type HelmSocket,
} from "../src/lib/helm-event-stream";

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

  // Test helpers — drive the FakeSocket as if the server emitted
  // these frames.
  open(): void {
    this.dispatch("open", {});
  }
  message(data: string): void {
    this.dispatch("message", { data });
  }
  hangup(): void {
    this.dispatch("close", { code: 1006, reason: "transport hangup" });
  }

  private dispatch(event: string, ev: unknown): void {
    const ls = this.listeners[event] ?? [];
    for (const l of ls) l(ev);
  }
}

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

test("HelmEventStream connect sends helm.subscribe with topics", async () => {
  let socket: FakeSocket | null = null;
  const stream = new HelmEventStream({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "a".repeat(64),
    topics: ["jobs", "customers"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
  });
  stream.connect();
  socket!.open();
  // helm.subscribe is sent immediately on `open`.
  assert.equal(socket!.sent.length, 1);
  const body = JSON.parse(socket!.sent[0]) as Record<string, unknown>;
  assert.equal(body["method"], "helm.subscribe");
  assert.deepEqual((body["params"] as Record<string, unknown>)["topics"], [
    "jobs",
    "customers",
  ]);
  stream.disconnect();
});

test("HelmEventStream subscribe ack flips state to subscribed", async () => {
  const states: HelmEventStreamState[] = [];
  let socket: FakeSocket | null = null;
  const stream = new HelmEventStream({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "a".repeat(64),
    topics: ["jobs"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
    onState: (s) => states.push(s),
  });
  stream.connect();
  socket!.open();
  socket!.message(
    JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      result: { subscribed: true, topics: ["jobs"] },
    }),
  );
  assert.equal(stream.currentState, "subscribed");
  assert.ok(states.includes("subscribed"));
  stream.disconnect();
});

test("HelmEventStream parses helm.event into HelmEvent", async () => {
  const events: HelmEvent[] = [];
  let socket: FakeSocket | null = null;
  const stream = new HelmEventStream({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "a".repeat(64),
    topics: ["jobs"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
    onEvent: (e) => events.push(e),
  });
  stream.connect();
  socket!.open();
  socket!.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: {
        type: "job.transitioned",
        data: {
          id: "job-001",
          from: "lead",
          to: "quoted",
          transitioned_at: "2026-05-02T14:30:00Z",
        },
      },
    }),
  );
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "job.transitioned");
  assert.equal(events[0].data["id"], "job-001");
  assert.equal(events[0].data["from"], "lead");
  assert.equal(events[0].data["to"], "quoted");
  stream.disconnect();
});

test("HelmEventStream multiple events arrive in order", async () => {
  const events: HelmEvent[] = [];
  let socket: FakeSocket | null = null;
  const stream = new HelmEventStream({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "a".repeat(64),
    topics: ["jobs"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
    onEvent: (e) => events.push(e),
  });
  stream.connect();
  socket!.open();
  for (let i = 0; i < 3; i++) {
    socket!.message(
      JSON.stringify({
        jsonrpc: "2.0",
        method: "helm.event",
        params: { type: "job.transitioned", data: { id: `job-${i}` } },
      }),
    );
  }
  assert.equal(events.length, 3);
  assert.equal(events[0].data["id"], "job-0");
  assert.equal(events[2].data["id"], "job-2");
  stream.disconnect();
});

test("HelmEventStream non-event server frames ignored", async () => {
  const events: HelmEvent[] = [];
  let socket: FakeSocket | null = null;
  const stream = new HelmEventStream({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "a".repeat(64),
    topics: ["jobs"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
    onEvent: (e) => events.push(e),
  });
  stream.connect();
  socket!.open();
  // Reply to some other RPC — must not parse as an event.
  socket!.message(
    JSON.stringify({ jsonrpc: "2.0", id: 99, result: { foo: "bar" } }),
  );
  assert.equal(events.length, 0);
  stream.disconnect();
});

test("HelmEventStream malformed frames are dropped", async () => {
  const events: HelmEvent[] = [];
  let socket: FakeSocket | null = null;
  const stream = new HelmEventStream({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "a".repeat(64),
    topics: ["jobs"],
    socketFactory: () => {
      socket = new FakeSocket();
      return socket;
    },
    onEvent: (e) => events.push(e),
  });
  stream.connect();
  socket!.open();
  socket!.message("not-json");
  socket!.message(JSON.stringify({ foo: "bar" }));
  socket!.message(
    JSON.stringify({
      jsonrpc: "2.0",
      method: "helm.event",
      params: { data: {} }, // missing type
    }),
  );
  assert.equal(events.length, 0);
  stream.disconnect();
});

test("HelmEventStream reconnects on transport hangup", async () => {
  let socketCount = 0;
  let lastSocket: FakeSocket | null = null;
  const states: HelmEventStreamState[] = [];
  const stream = new HelmEventStream({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "a".repeat(64),
    topics: ["jobs"],
    socketFactory: () => {
      socketCount += 1;
      lastSocket = new FakeSocket();
      return lastSocket;
    },
    reconnectBackoff: [1, 1, 1],
    onState: (s) => states.push(s),
  });
  stream.connect();
  lastSocket!.open();
  assert.equal(socketCount, 1);
  // Server hangs up.
  lastSocket!.hangup();
  await wait(20);
  assert.ok(states.includes("reconnecting"));
  assert.ok(socketCount >= 2);
  stream.disconnect();
});

test("HelmEventStream disconnect prevents further reconnect attempts", async () => {
  let socketCount = 0;
  let lastSocket: FakeSocket | null = null;
  const stream = new HelmEventStream({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "a".repeat(64),
    topics: ["jobs"],
    socketFactory: () => {
      socketCount += 1;
      lastSocket = new FakeSocket();
      return lastSocket;
    },
    reconnectBackoff: [1, 1, 1],
  });
  stream.connect();
  lastSocket!.open();
  assert.equal(socketCount, 1);
  stream.disconnect();
  // Hang-up after disconnect should NOT cause a reconnect.
  lastSocket!.hangup();
  await wait(20);
  assert.equal(socketCount, 1);
  assert.equal(stream.currentState, "disconnected");
});

test("HelmEventStream appends ?bearer= to the WSS URL", async () => {
  let capturedUrl: string | null = null;
  const stream = new HelmEventStream({
    wssUrl: "ws://example.test/api/v1/wallet",
    bearer: "cafef00d".repeat(8),
    topics: ["jobs"],
    socketFactory: (url) => {
      capturedUrl = url;
      return new FakeSocket();
    },
  });
  stream.connect();
  assert.ok(capturedUrl !== null);
  assert.ok(
    capturedUrl!.includes(`bearer=${"cafef00d".repeat(8)}`),
    `expected ?bearer= in ${capturedUrl}`,
  );
  stream.disconnect();
});

```
