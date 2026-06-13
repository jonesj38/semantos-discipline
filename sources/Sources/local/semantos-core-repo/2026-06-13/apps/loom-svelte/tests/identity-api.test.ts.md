---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/tests/identity-api.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.063019+00:00
---

# apps/loom-svelte/tests/identity-api.test.ts

```ts
// identity-api.fetchBrainInfo — tolerant /api/v1/info parse for the "me" panel.

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { fetchBrainInfo } from "../src/lib/identity-api";

function withFetch(
  impl: (url: string, init?: RequestInit) => Promise<Response>,
  run: () => Promise<void>,
): Promise<void> {
  const orig = globalThis.fetch;
  (globalThis as { fetch: unknown }).fetch = impl as unknown;
  return run().finally(() => {
    (globalThis as { fetch: unknown }).fetch = orig;
  });
}

function jsonResponse(body: unknown, ok = true): Response {
  return {
    ok,
    status: ok ? 200 : 500,
    json: async () => body,
  } as unknown as Response;
}

test("fetchBrainInfo: maps brain_pin_* / server_version / cartridges[]", async () => {
  await withFetch(
    async () =>
      jsonResponse({
        brain_pin_pubkey: "02" + "ab".repeat(32),
        brain_pin_cert_id: "cd".repeat(16),
        server_version: "brain 0.1.0",
        cartridges: [{ id: "oddjobz" }, { name: "wallet-headers" }, {}],
      }),
    async () => {
      const info = await fetchBrainInfo("https://brain.test", "f".repeat(64));
      assert.notEqual(info, null);
      assert.equal(info!.pinPubkey, "02" + "ab".repeat(32));
      assert.equal(info!.pinCertId, "cd".repeat(16));
      assert.equal(info!.serverVersion, "brain 0.1.0");
      // empty entries dropped; id preferred over name.
      assert.deepEqual(info!.cartridges, ["oddjobz", "wallet-headers"]);
    },
  );
});

test("fetchBrainInfo: tolerates missing keys (thin brain build)", async () => {
  await withFetch(
    async () => jsonResponse({}),
    async () => {
      const info = await fetchBrainInfo("https://brain.test", "f".repeat(64));
      assert.notEqual(info, null);
      assert.equal(info!.pinPubkey, "");
      assert.deepEqual(info!.cartridges, []);
    },
  );
});

test("fetchBrainInfo: returns null on non-ok / network error", async () => {
  await withFetch(
    async () => jsonResponse({}, false),
    async () => {
      assert.equal(await fetchBrainInfo("https://brain.test", "f".repeat(64)), null);
    },
  );
  await withFetch(
    async () => { throw new Error("network down"); },
    async () => {
      assert.equal(await fetchBrainInfo("https://brain.test", "f".repeat(64)), null);
    },
  );
});

```
