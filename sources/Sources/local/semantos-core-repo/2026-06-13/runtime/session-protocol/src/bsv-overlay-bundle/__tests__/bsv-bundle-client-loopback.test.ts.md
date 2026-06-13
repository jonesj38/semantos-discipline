---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/__tests__/bsv-bundle-client-loopback.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.073027+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/__tests__/bsv-bundle-client-loopback.test.ts

```ts
/**
 * In-memory loopback test for the full bsv-overlay-bundle client.
 *
 * Wires `createBsvOverlayBundleClient` against an in-memory
 * publish/poll transport that simulates the BRC-22 broadcast +
 * BRC-24 lookup loop without any wallet, network, or `@bsv/sdk`
 * tx machinery. Covers the publish → subscribe → dedupe path
 * through the real facade (publisher + poller + subscriber +
 * dedupe + ports composed together).
 */

import { describe, test, expect } from "bun:test";
import { PublicKey, PrivateKey } from "@bsv/sdk";

import type { SignedBundle } from "../../bundle-envelope.js";
import { createBsvOverlayBundleClient } from "../bsv-bundle-client-facade.js";
import type {
  BundleLookupPoller,
  BundleTxSender,
  PolledBundleResult,
} from "../bsv-bundle-ports.js";

interface InMemoryOverlay {
  sender: BundleTxSender;
  poller: BundleLookupPoller;
  /** Inject a duplicate outpoint to test dedupe across polls. */
  republishLast(): void;
}

const makeInMemoryOverlay = (): InMemoryOverlay => {
  // Map of recipient → outpoint → bundle. Senders push, pollers
  // drain — but pollers always see the *full* set (matches the
  // real BRC-24 SLAP behaviour: no cursor, dedupe is the client's
  // job).
  const bundlesByRecipient = new Map<
    string,
    Map<string, SignedBundle<unknown>>
  >();
  let txCount = 0;
  let lastEntry: { recipient: string; outpoint: string } | null = null;

  const sender: BundleTxSender = {
    async sendBundleTx({ recipientCertId }) {
      txCount += 1;
      const txid = `mem-tx-${txCount}`;
      // We don't have the bundle here — the real client would
      // encode it into the locking script. For this loopback we
      // accept the txid + record the publication via a
      // `publishBundleDirectly` helper invoked by the test.
      lastEntry = { recipient: recipientCertId, outpoint: `${txid}.0` };
      return { txid };
    },
  };

  const poller: BundleLookupPoller = {
    async pollForRecipient(recipientCertId: string) {
      const m = bundlesByRecipient.get(recipientCertId);
      if (!m) return [];
      const results: PolledBundleResult<unknown>[] = [];
      for (const [outpoint, bundle] of m) {
        results.push({ outpoint, bundle });
      }
      return results;
    },
  };

  return {
    sender: {
      async sendBundleTx(args) {
        // For tests we compose: hand off to sender, then "publish"
        // the bundle into the in-memory map keyed by its sender-
        // assigned outpoint. Real production goes via the
        // PushDrop+wallet stack.
        const result = await sender.sendBundleTx(args);
        // The bundle being published is owned by the test —
        // record-on-publish happens via `publishBundleAndReturnOutpoint`.
        return result;
      },
    },
    poller,
    republishLast() {
      if (!lastEntry) return;
    },
    // ── test helpers ──
    // Placed below TS won't type-check on InMemoryOverlay, so we
    // attach them on the returned object via Object.assign.
    ...({
      _publish: (recipient: string, bundle: SignedBundle<unknown>) => {
        let m = bundlesByRecipient.get(recipient);
        if (!m) {
          m = new Map();
          bundlesByRecipient.set(recipient, m);
        }
        const outpoint = `mem-tx-${++txCount}.0`;
        m.set(outpoint, bundle);
        lastEntry = { recipient, outpoint };
        return outpoint;
      },
    } as Record<string, unknown>),
  } as InMemoryOverlay & {
    _publish(recipient: string, bundle: SignedBundle<unknown>): string;
  };
};

const fakeBundle = (
  recipient: string,
  payloadId: string,
): SignedBundle<{ id: string }> => ({
  version: 1,
  payload: { id: payloadId },
  signedAt: "2026-01-01T00:00:00.000Z",
  signer: { bca: "::1", pubkeyHex: "00".repeat(33) },
  recipient: { certId: recipient },
  signature: "00".repeat(70),
});

const wait = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));

describe("bsv-overlay-bundle loopback (publisher + subscriber + dedupe)", () => {
  test("subscribe receives bundles published to the same recipient, deduped across polls", async () => {
    const overlay = makeInMemoryOverlay() as ReturnType<
      typeof makeInMemoryOverlay
    > & { _publish(r: string, b: SignedBundle<unknown>): string };
    const senderKey = PublicKey.fromPrivateKey(PrivateKey.fromRandom());

    const client = createBsvOverlayBundleClient({
      sender: overlay.sender,
      poller: overlay.poller,
      senderPubKey: senderKey,
      pollIntervalMs: 10, // fast for the test
      now: () => 1234,
      logger: () => {},
    });

    const delivered: string[] = [];
    const unsubscribe = client.subscribeBundlesForRecipient<{ id: string }>(
      "alice",
      (b) => {
        delivered.push(b.payload.id);
      },
    );

    // Loop the in-memory overlay's "publish into the recipient map".
    // We bypass the encoded PushDrop path because this test owns the
    // wire — it's exercising the publish→subscribe→dedupe seam, not
    // the PushDrop codec (which has its own gate test).
    overlay._publish("alice", fakeBundle("alice", "first"));
    overlay._publish("alice", fakeBundle("alice", "second"));

    // Wait for the first immediate poll + at least one interval poll.
    await wait(40);

    // Re-poll: same outpoints already in the recipient map. Dedupe
    // should drop them.
    await wait(30);

    unsubscribe();

    // Each id delivered once, in publish order.
    expect(delivered).toEqual(["first", "second"]);
  });

  test("unsubscribe stops further deliveries", async () => {
    const overlay = makeInMemoryOverlay() as ReturnType<
      typeof makeInMemoryOverlay
    > & { _publish(r: string, b: SignedBundle<unknown>): string };
    const senderKey = PublicKey.fromPrivateKey(PrivateKey.fromRandom());

    const client = createBsvOverlayBundleClient({
      sender: overlay.sender,
      poller: overlay.poller,
      senderPubKey: senderKey,
      pollIntervalMs: 10,
      now: () => 0,
      logger: () => {},
    });

    const delivered: string[] = [];
    const unsubscribe = client.subscribeBundlesForRecipient<{ id: string }>(
      "alice",
      (b) => {
        delivered.push(b.payload.id);
      },
    );

    overlay._publish("alice", fakeBundle("alice", "before"));
    await wait(40);
    unsubscribe();

    // After unsubscribe, new publishes must not be delivered.
    overlay._publish("alice", fakeBundle("alice", "after"));
    await wait(40);

    expect(delivered).toEqual(["before"]);
  });

  test("publishBundle returns a `bsv-overlay`-tagged receipt", async () => {
    const overlay = makeInMemoryOverlay();
    const senderKey = PublicKey.fromPrivateKey(PrivateKey.fromRandom());
    const client = createBsvOverlayBundleClient({
      sender: overlay.sender,
      poller: overlay.poller,
      senderPubKey: senderKey,
      pollIntervalMs: 10_000,
      now: () => 7777,
      logger: () => {},
    });

    const receipt = await client.publishBundle(fakeBundle("bob", "x"));
    expect(receipt.backend).toBe("bsv-overlay");
    expect(receipt.publishedAt).toBe(7777);
    expect(receipt.id).toMatch(/^mem-tx-\d+$/);
  });

  test("rejects publishBundle for unaddressed bundles", async () => {
    const overlay = makeInMemoryOverlay();
    const senderKey = PublicKey.fromPrivateKey(PrivateKey.fromRandom());
    const client = createBsvOverlayBundleClient({
      sender: overlay.sender,
      poller: overlay.poller,
      senderPubKey: senderKey,
      pollIntervalMs: 10_000,
      now: () => 0,
      logger: () => {},
    });

    const unaddressed: SignedBundle<{ id: string }> = {
      version: 1,
      payload: { id: "x" },
      signedAt: "2026-01-01T00:00:00.000Z",
      signer: { bca: "::1", pubkeyHex: "00".repeat(33) },
      signature: "00".repeat(70),
    };

    await expect(client.publishBundle(unaddressed)).rejects.toThrow(
      /requires an addressed bundle/,
    );
  });
});

```
