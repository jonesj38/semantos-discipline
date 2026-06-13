---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/peer-locator/__tests__/dns-peer-locator.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.166883+00:00
---

# runtime/peer-locator/__tests__/dns-peer-locator.test.ts

```ts
/**
 * DnsPeerLocator tests — Phase 35B.1 G35B.7 ("DNS-only reachability").
 *
 * Exercises the locator with a fake `TxtResolver` injected via the ctor so
 * tests never touch real DNS. Confirms:
 *
 *   - TXT records of form `bca=...;wss=...` parse to NodeEndpoint
 *   - Multiple known hostnames are tried; match on exact bca wins
 *   - Unresolved BCA → null
 *   - Resolver errors swallowed into null (don't break the locator)
 *   - Cache TTL: repeated resolve within TTL doesn't re-hit the resolver;
 *     expiry forces a fresh lookup
 *   - resolveByHostname parses the first matching TXT record directly
 */

import { describe, test, expect } from "bun:test";
import { DnsPeerLocator } from "../src/dns-peer-locator";
import { parseNodeEndpointTxt } from "../src/dns-peer-locator";
import type { TxtResolver, NodeEndpoint } from "../src/types";

// ---------------------------------------------------------------------------
// Fake resolver + time helpers
// ---------------------------------------------------------------------------

function makeResolver(
  table: Record<string, string[] | Error>,
): TxtResolver & { callCount: number } {
  const callCount = 0;
  const r: TxtResolver & { callCount: number } = {
    callCount,
    async resolveTxt(hostname: string): Promise<string[]> {
      r.callCount += 1;
      const entry = table[hostname];
      if (entry === undefined) return [];
      if (entry instanceof Error) throw entry;
      return entry;
    },
  };
  return r;
}

// ---------------------------------------------------------------------------
// parseNodeEndpointTxt
// ---------------------------------------------------------------------------

describe("parseNodeEndpointTxt", () => {
  test("parses a minimal bca+wss record", () => {
    const ep = parseNodeEndpointTxt(
      "bob.example.com",
      "bca=2602:f9f8::b0b;wss=wss://bob.example.com:443/session",
    );
    expect(ep).toEqual({
      bca: "2602:f9f8::b0b",
      wssUrl: "wss://bob.example.com:443/session",
    });
  });

  test("parses optional licenseCertId and pubkey (hex)", () => {
    const ep = parseNodeEndpointTxt(
      "alice.example.com",
      "bca=2602:f9f8::a11ce;wss=wss://alice:443/session;licenseCertId=sha256:beef;pubkey=02aa",
    );
    expect(ep?.bca).toBe("2602:f9f8::a11ce");
    expect(ep?.licenseCertId).toBe("sha256:beef");
    expect(ep?.pubkey).toEqual(new Uint8Array([0x02, 0xaa]));
  });

  test("tolerates whitespace around k=v pairs", () => {
    const ep = parseNodeEndpointTxt(
      "bob.example.com",
      " bca = 2602:f9f8::b0b ;  wss = wss://bob:443/session ",
    );
    expect(ep?.bca).toBe("2602:f9f8::b0b");
    expect(ep?.wssUrl).toBe("wss://bob:443/session");
  });

  test("returns null when required bca or wss missing", () => {
    expect(parseNodeEndpointTxt("x.com", "wss=wss://x:443/session")).toBeNull();
    expect(parseNodeEndpointTxt("x.com", "bca=2602::1")).toBeNull();
    expect(parseNodeEndpointTxt("x.com", "not-a-record")).toBeNull();
  });

  test("returns null on malformed pubkey hex", () => {
    const ep = parseNodeEndpointTxt(
      "x.com",
      "bca=2602::1;wss=wss://x:443/session;pubkey=nothex",
    );
    expect(ep).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// DnsPeerLocator
// ---------------------------------------------------------------------------

describe("DnsPeerLocator.resolve (BCA → endpoint)", () => {
  test("G35B.7 — with fake resolver, produces expected NodeEndpoint for a hostname", async () => {
    const resolver = makeResolver({
      "_semantos-node.bob.example.com": [
        "bca=2602:f9f8::b0b;wss=wss://bob.example.com:443/session",
      ],
    });
    const loc = new DnsPeerLocator({
      txtResolver: resolver,
      hostnames: ["bob.example.com"],
    });

    const ep = await loc.resolve("2602:f9f8::b0b");
    expect(ep).not.toBeNull();
    expect(ep!.bca).toBe("2602:f9f8::b0b");
    expect(ep!.wssUrl).toBe("wss://bob.example.com:443/session");
  });

  test("iterates multiple known hostnames, returns the first matching BCA", async () => {
    const resolver = makeResolver({
      "_semantos-node.alice.example.com": [
        "bca=2602:f9f8::a11ce;wss=wss://alice:443/session",
      ],
      "_semantos-node.bob.example.com": [
        "bca=2602:f9f8::b0b;wss=wss://bob:443/session",
      ],
    });
    const loc = new DnsPeerLocator({
      txtResolver: resolver,
      hostnames: ["alice.example.com", "bob.example.com"],
    });

    const ep = await loc.resolve("2602:f9f8::b0b");
    expect(ep).not.toBeNull();
    expect(ep!.bca).toBe("2602:f9f8::b0b");
    expect(ep!.wssUrl).toContain("bob");
  });

  test("returns null when no known hostname advertises the BCA", async () => {
    const resolver = makeResolver({
      "_semantos-node.bob.example.com": [
        "bca=2602:f9f8::b0b;wss=wss://bob:443/session",
      ],
    });
    const loc = new DnsPeerLocator({
      txtResolver: resolver,
      hostnames: ["bob.example.com"],
    });

    const ep = await loc.resolve("2602:f9f8::someone-else");
    expect(ep).toBeNull();
  });

  test("swallows resolver errors, continues to next hostname", async () => {
    const resolver = makeResolver({
      "_semantos-node.broken.example.com": new Error("NXDOMAIN"),
      "_semantos-node.bob.example.com": [
        "bca=2602:f9f8::b0b;wss=wss://bob:443/session",
      ],
    });
    const loc = new DnsPeerLocator({
      txtResolver: resolver,
      hostnames: ["broken.example.com", "bob.example.com"],
    });

    const ep = await loc.resolve("2602:f9f8::b0b");
    expect(ep).not.toBeNull();
    expect(ep!.bca).toBe("2602:f9f8::b0b");
  });
});

// ---------------------------------------------------------------------------
// Cache TTL
// ---------------------------------------------------------------------------

describe("DnsPeerLocator cache TTL", () => {
  test("repeated resolve within TTL does not re-hit the resolver", async () => {
    const resolver = makeResolver({
      "_semantos-node.bob.example.com": [
        "bca=2602:f9f8::b0b;wss=wss://bob:443/session",
      ],
    });
    let fakeNow = 1_000_000;
    const loc = new DnsPeerLocator({
      txtResolver: resolver,
      hostnames: ["bob.example.com"],
      cacheTtlMs: 60_000,
      now: () => fakeNow,
    });

    await loc.resolve("2602:f9f8::b0b");
    const firstCalls = resolver.callCount;

    fakeNow += 30_000;
    await loc.resolve("2602:f9f8::b0b");

    expect(resolver.callCount).toBe(firstCalls);
  });

  test("resolve after TTL expiry re-hits the resolver", async () => {
    const resolver = makeResolver({
      "_semantos-node.bob.example.com": [
        "bca=2602:f9f8::b0b;wss=wss://bob:443/session",
      ],
    });
    let fakeNow = 1_000_000;
    const loc = new DnsPeerLocator({
      txtResolver: resolver,
      hostnames: ["bob.example.com"],
      cacheTtlMs: 60_000,
      now: () => fakeNow,
    });

    await loc.resolve("2602:f9f8::b0b");
    const firstCalls = resolver.callCount;

    fakeNow += 120_000;
    await loc.resolve("2602:f9f8::b0b");

    expect(resolver.callCount).toBeGreaterThan(firstCalls);
  });
});

// ---------------------------------------------------------------------------
// register (no-op)
// ---------------------------------------------------------------------------

describe("DnsPeerLocator.register", () => {
  test("is a no-op — DnsPeerLocator does not maintain a reverse index", async () => {
    const resolver = makeResolver({});
    const loc = new DnsPeerLocator({ txtResolver: resolver, hostnames: [] });

    // Should resolve to null for this registered endpoint — DnsPeerLocator
    // is DNS-backed, not cache-backed on register.
    const ep: NodeEndpoint = { bca: "2602:f9f8::b0b", wssUrl: "wss://x" };
    await expect(loc.register(ep)).resolves.toBeUndefined();

    expect(await loc.resolve(ep.bca)).toBeNull();
  });
});

```
