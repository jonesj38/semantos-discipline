---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/__tests__/outbound-queue.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.071113+00:00
---

# runtime/session-protocol/src/adapters/multicast/__tests__/outbound-queue.test.ts

```ts
/**
 * outbound-queue unit tests — FIFO drain + retry policy.
 */

import { describe, expect, test } from "bun:test";
import { createOutboundQueue } from "../outbound-queue";

describe("outbound-queue", () => {
  test("drains items in FIFO order through `send`", async () => {
    const seen: string[] = [];
    const q = createOutboundQueue({
      send: async (_packet, _port, address) => {
        seen.push(address);
      },
    });
    await Promise.all([
      q.enqueue({ packet: new Uint8Array([1]), port: 1, address: "a" }),
      q.enqueue({ packet: new Uint8Array([2]), port: 1, address: "b" }),
      q.enqueue({ packet: new Uint8Array([3]), port: 1, address: "c" }),
    ]);
    expect(seen).toEqual(["a", "b", "c"]);
  });

  test("retries up to maxAttempts on transient transport failures", async () => {
    let calls = 0;
    const q = createOutboundQueue({
      retryPolicy: { maxAttempts: 3, backoffMs: [0, 0] },
      send: async () => {
        calls += 1;
        if (calls < 3) throw new Error("transient");
      },
    });
    await q.enqueue({ packet: new Uint8Array([1]), port: 1, address: "a" });
    expect(calls).toBe(3);
  });

  test("invokes onDrop after exhausting retries", async () => {
    const dropped: string[] = [];
    const q = createOutboundQueue({
      retryPolicy: { maxAttempts: 2, backoffMs: [0] },
      send: async () => {
        throw new Error("permanent");
      },
      onDrop: (item) => dropped.push(item.address),
    });
    await q.enqueue({ packet: new Uint8Array([1]), port: 1, address: "a" });
    expect(dropped).toEqual(["a"]);
  });

  test("bestEffort packets are not retried", async () => {
    let calls = 0;
    const q = createOutboundQueue({
      retryPolicy: { maxAttempts: 5, backoffMs: [0] },
      send: async () => {
        calls += 1;
        throw new Error("transient");
      },
    });
    await q.enqueue({
      packet: new Uint8Array([1]),
      port: 1,
      address: "hb",
      bestEffort: true,
    });
    expect(calls).toBe(1);
  });
});

```
