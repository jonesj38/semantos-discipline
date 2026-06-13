---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/__tests__/bsv-bundle-subscriber.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.073355+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/__tests__/bsv-bundle-subscriber.test.ts

```ts
/**
 * Unit tests for the per-cycle subscriber loop.
 *
 * Drives `runSubscriberCycle` directly with a fake `BundleLookupPoller`
 * + an in-memory dedupe — no timers, no real network.
 */

import { describe, test, expect } from "bun:test";

import type { SignedBundle } from "../../bundle-envelope.js";
import { createBundleDedupe } from "../bsv-bundle-dedupe.js";
import { runSubscriberCycle } from "../bsv-bundle-subscriber.js";
import type {
  BundleLookupPoller,
  PolledBundleResult,
} from "../bsv-bundle-ports.js";

const fakeBundle = (id: string): SignedBundle<{ id: string }> => ({
  version: 1,
  payload: { id },
  signedAt: "2026-01-01T00:00:00.000Z",
  signer: { bca: "::1", pubkeyHex: "00".repeat(33) },
  recipient: { certId: "alice" },
  signature: "00".repeat(70),
});

const recordingPoller = (
  scripted: PolledBundleResult<unknown>[][],
): BundleLookupPoller & { calls: number } => {
  let calls = 0;
  return {
    get calls() {
      return calls;
    },
    async pollForRecipient() {
      const result = scripted[calls] ?? [];
      calls += 1;
      return result;
    },
  } as BundleLookupPoller & { calls: number };
};

describe("runSubscriberCycle", () => {
  test("delivers each unique outpoint exactly once", async () => {
    const delivered: string[] = [];
    const poller = recordingPoller([
      [
        { outpoint: "tx1.0", bundle: fakeBundle("a") },
        { outpoint: "tx2.0", bundle: fakeBundle("b") },
      ],
    ]);
    const dedupe = createBundleDedupe();

    await runSubscriberCycle({
      poller,
      dedupe,
      handler: (b) => {
        delivered.push((b.payload as { id: string }).id);
      },
      recipientCertId: "alice",
      isCancelled: () => false,
      logger: () => {},
    });

    expect(delivered).toEqual(["a", "b"]);
    expect(dedupe.size).toBe(2);
  });

  test("dedupes outpoints across cycles", async () => {
    const delivered: string[] = [];
    const dup = { outpoint: "tx1.0", bundle: fakeBundle("a") };
    const poller = recordingPoller([
      [dup],
      [dup, { outpoint: "tx2.0", bundle: fakeBundle("b") }],
    ]);
    const dedupe = createBundleDedupe();

    const cycleArgs = {
      poller,
      dedupe,
      handler: (b: SignedBundle<{ id: string }>) => {
        delivered.push(b.payload.id);
      },
      recipientCertId: "alice",
      isCancelled: () => false,
      logger: () => {},
    };

    await runSubscriberCycle(cycleArgs);
    await runSubscriberCycle(cycleArgs);

    expect(delivered).toEqual(["a", "b"]);
  });

  test("swallows poller errors and routes to logger", async () => {
    const logs: string[] = [];
    const poller: BundleLookupPoller = {
      async pollForRecipient() {
        throw new Error("upstream down");
      },
    };
    const dedupe = createBundleDedupe();

    await runSubscriberCycle({
      poller,
      dedupe,
      handler: () => {
        throw new Error("should not be called");
      },
      recipientCertId: "alice",
      isCancelled: () => false,
      logger: (m) => logs.push(m),
    });

    expect(logs.length).toBe(1);
    expect(logs[0]).toMatch(/poll failed/);
  });

  test("handler throws are logged but next bundle still delivered", async () => {
    const logs: string[] = [];
    const delivered: string[] = [];
    const poller = recordingPoller([
      [
        { outpoint: "tx1.0", bundle: fakeBundle("a") },
        { outpoint: "tx2.0", bundle: fakeBundle("b") },
      ],
    ]);

    await runSubscriberCycle({
      poller,
      dedupe: createBundleDedupe(),
      handler: (b) => {
        const id = (b.payload as { id: string }).id;
        if (id === "a") throw new Error("handler boom");
        delivered.push(id);
      },
      recipientCertId: "alice",
      isCancelled: () => false,
      logger: (m) => logs.push(m),
    });

    expect(delivered).toEqual(["b"]);
    expect(logs.some((l) => /handler threw/.test(l))).toBe(true);
  });

  test("isCancelled mid-loop short-circuits remaining bundles", async () => {
    const delivered: string[] = [];
    let cancelled = false;
    const poller = recordingPoller([
      [
        { outpoint: "tx1.0", bundle: fakeBundle("a") },
        { outpoint: "tx2.0", bundle: fakeBundle("b") },
        { outpoint: "tx3.0", bundle: fakeBundle("c") },
      ],
    ]);

    await runSubscriberCycle({
      poller,
      dedupe: createBundleDedupe(),
      handler: (b) => {
        const id = (b.payload as { id: string }).id;
        delivered.push(id);
        if (id === "a") cancelled = true;
      },
      recipientCertId: "alice",
      isCancelled: () => cancelled,
      logger: () => {},
    });

    expect(delivered).toEqual(["a"]);
  });

  test("returns immediately when already cancelled", async () => {
    const poller = recordingPoller([
      [{ outpoint: "tx1.0", bundle: fakeBundle("a") }],
    ]);
    let calls = 0;
    await runSubscriberCycle({
      poller,
      dedupe: createBundleDedupe(),
      handler: () => {
        calls++;
      },
      recipientCertId: "alice",
      isCancelled: () => true,
      logger: () => {},
    });
    expect(calls).toBe(0);
    expect(poller.calls).toBe(0);
  });
});

```
