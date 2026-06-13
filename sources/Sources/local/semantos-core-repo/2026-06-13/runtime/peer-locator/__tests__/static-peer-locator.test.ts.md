---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/peer-locator/__tests__/static-peer-locator.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.167178+00:00
---

# runtime/peer-locator/__tests__/static-peer-locator.test.ts

```ts
/**
 * StaticPeerLocator tests — map-backed, for bootstrapping and tests.
 */

import { describe, test, expect } from "bun:test";
import { StaticPeerLocator } from "../src/static-peer-locator";
import type { NodeEndpoint } from "../src/types";

const bobEndpoint: NodeEndpoint = {
  bca: "2602:f9f8::b0b",
  wssUrl: "wss://bob.example.com:443/session",
};
const aliceEndpoint: NodeEndpoint = {
  bca: "2602:f9f8::a11ce",
  wssUrl: "wss://alice.example.com:443/session",
  licenseCertId: "sha256:deadbeef",
};

describe("StaticPeerLocator", () => {
  test("resolve returns null when empty", async () => {
    const loc = new StaticPeerLocator();
    expect(await loc.resolve("2602:f9f8::anyone")).toBeNull();
  });

  test("construct with initial endpoints, resolve finds them", async () => {
    const loc = new StaticPeerLocator({ endpoints: [bobEndpoint, aliceEndpoint] });

    expect(await loc.resolve(bobEndpoint.bca)).toEqual(bobEndpoint);
    expect(await loc.resolve(aliceEndpoint.bca)).toEqual(aliceEndpoint);
  });

  test("resolve returns null for unknown BCA", async () => {
    const loc = new StaticPeerLocator({ endpoints: [bobEndpoint] });
    expect(await loc.resolve("2602:f9f8::deadbeef")).toBeNull();
  });

  test("register adds to the map", async () => {
    const loc = new StaticPeerLocator();
    await loc.register(bobEndpoint);

    expect(await loc.resolve(bobEndpoint.bca)).toEqual(bobEndpoint);
  });

  test("register overwrites an existing entry for the same BCA", async () => {
    const loc = new StaticPeerLocator({ endpoints: [bobEndpoint] });
    const updated: NodeEndpoint = {
      bca: bobEndpoint.bca,
      wssUrl: "wss://bob-moved.example.com:9443/session",
    };
    await loc.register(updated);

    expect(await loc.resolve(bobEndpoint.bca)).toEqual(updated);
  });
});

```
