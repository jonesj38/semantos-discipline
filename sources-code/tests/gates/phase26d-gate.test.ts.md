---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase26d-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.564112+00:00
---

# tests/gates/phase26d-gate.test.ts

```ts
/**
 * Phase 26D Gate: NetworkAdapter Interface & Overlay Composition
 *
 * Validates:
 * 1. StubNetworkAdapter unit tests (T1–T6)
 * 2. NetworkAdapter composition / integration (T7–T12)
 * 3. Storage and Network decoupling (T13–T15)
 */

import { describe, test, expect, beforeEach } from "bun:test";
import { readFileSync, readdirSync, existsSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");

// ── Helpers ──────────────────────────────────────────────────────────

function makePublishable(overrides: Partial<{
  semanticPath: string;
  contentHash: string;
  ownerCert: string;
  typeHash: string;
  parentPath: string;
}> = {}) {
  return {
    cellBytes: new Uint8Array(1024),
    semanticPath: overrides.semanticPath ?? 'objects/test/item-1',
    contentHash: overrides.contentHash ?? 'a'.repeat(64),
    ownerCert: overrides.ownerCert ?? 'cert-owner-1',
    typeHash: overrides.typeHash ?? 'type-hash-1',
    parentPath: overrides.parentPath,
  };
}

// ── Gate 1: StubNetworkAdapter Unit Tests ────────────────────────────

describe("Phase 26D — StubNetworkAdapter", () => {
  let StubNetworkAdapter: any;

  beforeEach(async () => {
    const mod = await import(
      join(ROOT, "core/protocol-types/src/adapters/stub-network-adapter.ts")
    );
    StubNetworkAdapter = mod.StubNetworkAdapter;
  });

  // T1: publish stores object, returns txid with "stub" prefix + publishedAt
  test("T1: publish stores object and returns deterministic txid", async () => {
    const adapter = new StubNetworkAdapter();
    const obj = makePublishable();

    const result = await adapter.publish(obj);

    expect(result.txid).toStartWith("stub");
    expect(result.txid).toHaveLength(64);
    expect(result.publishedAt).toBeGreaterThan(0);
    expect(typeof result.publishedAt).toBe("number");

    // Verify stored — resolve should find it
    const resolved = await adapter.resolve({ path: obj.semanticPath });
    expect(resolved).toHaveLength(1);
    expect(resolved[0].txid).toBe(result.txid);
    expect(resolved[0].semanticPath).toBe(obj.semanticPath);
    expect(resolved[0].contentHash).toBe(obj.contentHash);
  });

  // T2: subscribe fires callback on publish
  test("T2: subscribe fires callback with correct event on publish", async () => {
    const adapter = new StubNetworkAdapter();
    const events: any[] = [];

    adapter.subscribe("tm_semantos_objects", (event: any) => {
      events.push(event);
    });

    const obj = makePublishable();
    await adapter.publish(obj);

    expect(events).toHaveLength(1);
    expect(events[0].type).toBe("object_published");
    expect(events[0].result.semanticPath).toBe(obj.semanticPath);
    expect(events[0].result.contentHash).toBe(obj.contentHash);
    expect(events[0].result.ownerCert).toBe(obj.ownerCert);
    expect(events[0].result.typeHash).toBe(obj.typeHash);
    expect(events[0].timestamp).toBeGreaterThan(0);
  });

  // T3: resolve by path returns matching objects
  test("T3: resolve by path returns exact match", async () => {
    const adapter = new StubNetworkAdapter();

    await adapter.publish(makePublishable({ semanticPath: "objects/a" }));
    await adapter.publish(makePublishable({ semanticPath: "objects/b" }));
    await adapter.publish(makePublishable({ semanticPath: "objects/c" }));

    const results = await adapter.resolve({ path: "objects/b" });
    expect(results).toHaveLength(1);
    expect(results[0].semanticPath).toBe("objects/b");
  });

  // T4: resolve by contentHash returns exact match
  test("T4: resolve by contentHash returns exact match", async () => {
    const adapter = new StubNetworkAdapter();
    const hash1 = "b".repeat(64);
    const hash2 = "c".repeat(64);

    await adapter.publish(makePublishable({ semanticPath: "objects/x", contentHash: hash1 }));
    await adapter.publish(makePublishable({ semanticPath: "objects/y", contentHash: hash2 }));

    const results = await adapter.resolve({ contentHash: hash2 });
    expect(results).toHaveLength(1);
    expect(results[0].contentHash).toBe(hash2);
    expect(results[0].semanticPath).toBe("objects/y");
  });

  // T5: resolve by ownerCert returns matching objects
  test("T5: resolve by ownerCert returns matching objects", async () => {
    const adapter = new StubNetworkAdapter();

    await adapter.publish(makePublishable({ semanticPath: "objects/1", ownerCert: "alice" }));
    await adapter.publish(makePublishable({ semanticPath: "objects/2", ownerCert: "bob" }));
    await adapter.publish(makePublishable({ semanticPath: "objects/3", ownerCert: "alice" }));

    const results = await adapter.resolve({ ownerCert: "alice" });
    expect(results).toHaveLength(2);
    expect(results.every((r: any) => r.ownerCert === "alice")).toBe(true);
  });

  // T6: resolve by typeHash + respects limit
  test("T6: resolve by typeHash respects limit parameter", async () => {
    const adapter = new StubNetworkAdapter();

    for (let i = 0; i < 5; i++) {
      await adapter.publish(
        makePublishable({
          semanticPath: `objects/item-${i}`,
          typeHash: "same-type",
          contentHash: `${i}`.padStart(64, '0'),
        }),
      );
    }

    const unlimited = await adapter.resolve({ typeHash: "same-type" });
    expect(unlimited).toHaveLength(5);

    const limited = await adapter.resolve({ typeHash: "same-type", limit: 2 });
    expect(limited).toHaveLength(2);
  });

  // Additional: unsubscribe works
  test("T2b: unsubscribe removes callback", async () => {
    const adapter = new StubNetworkAdapter();
    const events: any[] = [];

    const unsub = adapter.subscribe("tm_semantos_objects", (event: any) => {
      events.push(event);
    });

    await adapter.publish(makePublishable({ semanticPath: "objects/a" }));
    expect(events).toHaveLength(1);

    unsub();

    await adapter.publish(makePublishable({ semanticPath: "objects/b" }));
    expect(events).toHaveLength(1); // no new event
  });

  // Additional: deterministic txid ordering
  test("T1b: txids are deterministic and sequential", async () => {
    const adapter = new StubNetworkAdapter();

    const r1 = await adapter.publish(makePublishable({ semanticPath: "objects/a" }));
    const r2 = await adapter.publish(makePublishable({ semanticPath: "objects/b" }));

    expect(r1.txid).toBe("stub" + "1".padStart(60, "0"));
    expect(r2.txid).toBe("stub" + "2".padStart(60, "0"));
  });

  // Additional: isConnected, getNodeBCA, sendToNode, resolveBCA
  test("T1c: utility methods return expected values", async () => {
    const adapter = new StubNetworkAdapter({ nodeBCA: "2602:f9f8::1" });

    expect(adapter.isConnected()).toBe(true);
    expect(adapter.getNodeBCA()).toBe("2602:f9f8::1");

    const delivery = await adapter.sendToNode("2602:f9f8::2", new Uint8Array([1, 2, 3]));
    expect(delivery.delivered).toBe(true);

    const bca = await adapter.resolveBCA("2602:f9f8::2");
    expect(bca).toBeNull();
  });

  test("T1d: getNodeBCA returns null when not configured", () => {
    const adapter = new StubNetworkAdapter();
    expect(adapter.getNodeBCA()).toBeNull();
  });
});

// ── Gate 2: NetworkAdapter Composition / Integration ─────────────────

describe("Phase 26D — NetworkAdapter composition", () => {
  // T7: BsvOverlayNetworkAdapter exists and exports correctly
  test("T7: BsvOverlayNetworkAdapter is exported from protocol-types", () => {
    const indexSource = readFileSync(
      join(ROOT, "core/protocol-types/src/index.ts"),
      "utf-8",
    );
    expect(indexSource).toContain("BsvOverlayNetworkAdapter");
    expect(indexSource).toContain("BsvOverlayNetworkAdapterConfig");
  });

  // T8: BsvOverlayNetworkAdapter file exists with correct class
  test("T8: BsvOverlayNetworkAdapter implements NetworkAdapter", () => {
    const source = readFileSync(
      join(ROOT, "core/protocol-types/src/adapters/bsv-overlay-network-adapter.ts"),
      "utf-8",
    );
    expect(source).toContain("implements NetworkAdapter");
    expect(source).toContain("async publish(");
    expect(source).toContain("subscribe(");
    expect(source).toContain("async resolve(");
    expect(source).toContain("async resolveBCA(");
    expect(source).toContain("async sendToNode(");
    expect(source).toContain("isConnected(");
    expect(source).toContain("getNodeBCA(");
  });

  // T9–T12: Use StubNetworkAdapter for round-trip tests
  // (BsvOverlayNetworkAdapter requires real overlay network, so we test the
  //  interface contract via the stub which implements the same interface)

  // T9: publish + subscribe round-trip
  test("T9: publish + subscribe round-trip delivers event to subscriber", async () => {
    const { StubNetworkAdapter } = await import(
      join(ROOT, "core/protocol-types/src/adapters/stub-network-adapter.ts")
    );
    const adapter = new StubNetworkAdapter();
    const received: any[] = [];

    adapter.subscribe("tm_semantos_objects", (event: any) => {
      received.push(event);
    });

    const obj = makePublishable({ semanticPath: "trades/job/plumbing-42" });
    const result = await adapter.publish(obj);

    expect(received).toHaveLength(1);
    expect(received[0].result.txid).toBe(result.txid);
    expect(received[0].result.semanticPath).toBe("trades/job/plumbing-42");
  });

  // T10: resolve after publish finds by path
  test("T10: resolve after publish finds object by path", async () => {
    const { StubNetworkAdapter } = await import(
      join(ROOT, "core/protocol-types/src/adapters/stub-network-adapter.ts")
    );
    const adapter = new StubNetworkAdapter();

    const obj = makePublishable({ semanticPath: "objects/create/job/plumbing/job-1774" });
    await adapter.publish(obj);

    const results = await adapter.resolve({ path: "objects/create/job/plumbing/job-1774" });
    expect(results).toHaveLength(1);
    expect(results[0].contentHash).toBe(obj.contentHash);
    expect(results[0].ownerCert).toBe(obj.ownerCert);
  });

  // T11: resolve by ownerCert
  test("T11: resolve by ownerCert returns matching objects", async () => {
    const { StubNetworkAdapter } = await import(
      join(ROOT, "core/protocol-types/src/adapters/stub-network-adapter.ts")
    );
    const adapter = new StubNetworkAdapter();

    await adapter.publish(makePublishable({
      semanticPath: "objects/a",
      ownerCert: "cert-tradie-todd",
    }));
    await adapter.publish(makePublishable({
      semanticPath: "objects/b",
      ownerCert: "cert-pm-agency",
    }));

    const results = await adapter.resolve({ ownerCert: "cert-tradie-todd" });
    expect(results).toHaveLength(1);
    expect(results[0].ownerCert).toBe("cert-tradie-todd");
  });

  // T12: resolve by typeHash
  test("T12: resolve by typeHash returns matching objects", async () => {
    const { StubNetworkAdapter } = await import(
      join(ROOT, "core/protocol-types/src/adapters/stub-network-adapter.ts")
    );
    const adapter = new StubNetworkAdapter();

    await adapter.publish(makePublishable({
      semanticPath: "objects/job-1",
      typeHash: "sha256-trades-job",
    }));
    await adapter.publish(makePublishable({
      semanticPath: "objects/quote-1",
      typeHash: "sha256-trades-quote",
    }));

    const results = await adapter.resolve({ typeHash: "sha256-trades-job" });
    expect(results).toHaveLength(1);
    expect(results[0].typeHash).toBe("sha256-trades-job");
    expect(results[0].semanticPath).toBe("objects/job-1");
  });
});

// ── Gate 3: Storage and Network Decoupling ───────────────────────────

describe("Phase 26D — Storage and Network Decoupling", () => {
  // T13: StorageAdapter and NetworkAdapter are independent contracts
  test("T13: StorageAdapter and NetworkAdapter coexist independently", async () => {
    const { MemoryAdapter } = await import(
      join(ROOT, "core/protocol-types/src/adapters/memory-adapter.ts")
    );
    const { StubNetworkAdapter } = await import(
      join(ROOT, "core/protocol-types/src/adapters/stub-network-adapter.ts")
    );

    // Instantiate both — no conflicts
    const storage = new MemoryAdapter();
    const network = new StubNetworkAdapter();

    // Use storage
    const data = new Uint8Array([1, 2, 3, 4]);
    await storage.write("test/key", data);
    const read = await storage.read("test/key");
    expect(read).toEqual(data);

    // Use network (independent)
    const obj = makePublishable({ semanticPath: "objects/test" });
    const publishResult = await network.publish(obj);
    expect(publishResult.txid).toStartWith("stub");

    const resolved = await network.resolve({ path: "objects/test" });
    expect(resolved).toHaveLength(1);

    // Verify they don't interfere
    expect(await storage.exists("objects/test")).toBe(false);
    expect(network.isConnected()).toBe(true);
  });

  // T14: No TopicManagerClient/LookupServiceClient/ShardProxyClient imports outside adapters/ and overlay/
  test("T14: network clients not imported outside adapters/ and overlay/", () => {
    const srcDir = join(ROOT, "core/protocol-types/src");
    const files = getAllTsFiles(srcDir);

    const violations: string[] = [];
    const clientPattern = /import\s+.*(?:TopicManagerClient|LookupServiceClient|ShardProxyClient)/;

    for (const file of files) {
      const relPath = file.replace(srcDir + "/", "");

      // Skip files inside adapters/ and overlay/ — they're allowed
      if (relPath.startsWith("adapters/") || relPath.startsWith("overlay/")) continue;

      const content = readFileSync(file, "utf-8");
      if (clientPattern.test(content)) {
        violations.push(relPath);
      }
    }

    expect(violations).toEqual([]);
  });

  // T15: NetworkAdapter interface contains only primitives — no @bsv/sdk types
  test("T15: network.ts contains no @bsv/sdk overlay-tools types", () => {
    const networkSource = readFileSync(
      join(ROOT, "core/protocol-types/src/network.ts"),
      "utf-8",
    );

    // Strip comments (JSDoc may mention "Transaction ID" etc.)
    const stripped = networkSource
      .replace(/\/\*\*[\s\S]*?\*\//g, '')  // block comments
      .replace(/\/\/.*/g, '');              // line comments

    // These @bsv/sdk types must NOT appear in non-comment code
    const forbiddenTypes = [
      "STEAK",
      "TaggedBEEF",
      "LookupAnswer",
      "LookupQuestion",
      "ShardFrame",
    ];

    for (const forbidden of forbiddenTypes) {
      expect(stripped).not.toContain(forbidden);
    }

    // Verify no imports at all (network.ts should be pure types)
    expect(networkSource).not.toMatch(/^import\s/m);

    // Verify no @bsv/sdk reference anywhere
    expect(networkSource).not.toContain("@bsv/sdk");
  });
});

// ── Utilities ────────────────────────────────────────────────────────

function getAllTsFiles(dir: string): string[] {
  const results: string[] = [];
  const entries = readdirSync(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory() && entry.name !== "node_modules") {
      results.push(...getAllTsFiles(fullPath));
    } else if (entry.isFile() && entry.name.endsWith(".ts") && !entry.name.endsWith(".test.ts")) {
      results.push(fullPath);
    }
  }

  return results;
}

```
