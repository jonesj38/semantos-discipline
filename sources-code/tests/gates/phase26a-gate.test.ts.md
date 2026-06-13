---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase26a-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.583553+00:00
---

# tests/gates/phase26a-gate.test.ts

```ts
/**
 * Phase 26A Gate: IdentityAdapter Extraction
 *
 * Validates:
 * 1. IdentityAdapter interface and exports (T1–T3)
 * 2. StubIdentityAdapter behavior (T4–T7)
 * 3. Integration: subtree, recovery, backward compat (T8–T12)
 * 4. Anti-lock boundary (T13–T15)
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");

// ── Gate 1: IdentityAdapter Interface & Exports ─────────────────

describe("Phase 26A — IdentityAdapter Interface", () => {
  // T1: IdentityAdapter type exported from protocol-types
  test("T1: IdentityAdapter exported from protocol-types", () => {
    const indexSource = readFileSync(
      join(ROOT, "core/protocol-types/src/index.ts"),
      "utf-8",
    );
    expect(indexSource).toContain("IdentityAdapter");
    expect(indexSource).toContain("IdentityConfig");
    expect(indexSource).toContain("IdentityMode");
    expect(indexSource).toContain("IdentityError");
    expect(indexSource).toContain("IdentityState");
  });

  // T2: StubIdentityAdapter exported from protocol-types
  test("T2: StubIdentityAdapter exported from protocol-types", () => {
    const indexSource = readFileSync(
      join(ROOT, "core/protocol-types/src/index.ts"),
      "utf-8",
    );
    expect(indexSource).toContain("StubIdentityAdapter");
  });

  // T3: createIdentityAdapter exported from protocol-types
  test("T3: createIdentityAdapter exported from protocol-types", () => {
    const indexSource = readFileSync(
      join(ROOT, "core/protocol-types/src/index.ts"),
      "utf-8",
    );
    expect(indexSource).toContain("createIdentityAdapter");
    expect(indexSource).toContain("CreateIdentityAdapterOptions");
  });
});

// ── Gate 2: StubIdentityAdapter Behavior ────────────────────────

describe("Phase 26A — StubIdentityAdapter", () => {
  // T4: createIdentityAdapter returns StubIdentityAdapter by default
  test("T4: createIdentityAdapter returns StubIdentityAdapter", async () => {
    const { createIdentityAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/create-identity-adapter.ts"),
    );
    const { StubIdentityAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/stub-identity-adapter.ts"),
    );
    const adapter = await createIdentityAdapter();
    expect(adapter).toBeInstanceOf(StubIdentityAdapter);
  });

  // T5: StubIdentityAdapter.registerIdentity returns deterministic certId
  test("T5: deterministic certId from registerIdentity", async () => {
    const { StubIdentityAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/stub-identity-adapter.ts"),
    );
    const adapter1 = new StubIdentityAdapter({ mode: "stub" });
    const adapter2 = new StubIdentityAdapter({ mode: "stub" });

    const result1 = await adapter1.registerIdentity("alice@example.com");
    const result2 = await adapter2.registerIdentity("alice@example.com");

    expect(result1.certId).toBe(result2.certId);
    expect(result1.publicKey).toBe(result2.publicKey);
    expect(result1.certId).toMatch(/^cert:/);
    expect(result1.publicKey).toContain("-----BEGIN PUBLIC KEY-----");
  });

  // T6: Monotonic childIndex enforced
  test("T6: monotonic childIndex in deriveChild", async () => {
    const { StubIdentityAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/stub-identity-adapter.ts"),
    );
    const adapter = new StubIdentityAdapter({ mode: "stub" });
    const root = await adapter.registerIdentity("root@example.com");

    const child1 = await adapter.deriveChild(root.certId, "res1", 0x00010002);
    const child2 = await adapter.deriveChild(root.certId, "res2", 0x00010002);

    expect(child1.childIndex).toBe(0);
    expect(child2.childIndex).toBe(1);
    expect(child1.certId).not.toBe(child2.certId);
  });

  // T7: createEdge produces edgeId + sharedSecret
  test("T7: createEdge returns edgeId and sharedSecret", async () => {
    const { StubIdentityAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/stub-identity-adapter.ts"),
    );
    const adapter = new StubIdentityAdapter({ mode: "stub" });

    const alice = await adapter.registerIdentity("alice@example.com");
    const bob = await adapter.registerIdentity("bob@example.com");
    const edge = await adapter.createEdge(alice.certId, bob.certId);

    expect(edge.edgeId).toMatch(/^edge:/);
    expect(edge.sharedSecret).toHaveLength(64); // SHA-256 hex
  });
});

// ── Gate 3: Integration ─────────────────────────────────────────

describe("Phase 26A — Integration", () => {
  // T8: querySubtree returns correct tree structure at depth > 1
  test("T8: querySubtree with grandchildren", async () => {
    const { StubIdentityAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/stub-identity-adapter.ts"),
    );
    const adapter = new StubIdentityAdapter({ mode: "stub" });

    const root = await adapter.registerIdentity("root@example.com");
    const child1 = await adapter.deriveChild(root.certId, "res1", 0x00010002);
    await adapter.deriveChild(root.certId, "res2", 0x00010002);
    await adapter.deriveChild(child1.certId, "res1.1", 0x00010002);

    const tree = await adapter.querySubtree(root.certId, 2);

    expect(tree.root).toBe(root.certId);
    expect(tree.children).toHaveLength(2);
    expect(tree.children[0].grandchildren).toBeDefined();
    expect(tree.children[0].grandchildren!.length).toBe(1);
  });

  // T9: Recovery flow end-to-end
  test("T9: initiateRecovery + submitChallengeAnswers", async () => {
    const { StubIdentityAdapter } = require(
      join(ROOT, "core/protocol-types/src/adapters/stub-identity-adapter.ts"),
    );
    const adapter = new StubIdentityAdapter({ mode: "stub" });

    const recovery = await adapter.initiateRecovery("user@example.com");
    expect(recovery.sessionId).toMatch(/^session:/);
    expect(recovery.challengeCount).toBe(4);
    expect(recovery.challenges).toHaveLength(4);

    // Correct answers
    const result = await adapter.submitChallengeAnswers(recovery.sessionId, [
      { challengeId: "c1", answer: "user@example.com" },
      { challengeId: "c2", answer: "4" },
      { challengeId: "c3", answer: "true" },
      { challengeId: "c4", answer: "42" },
    ]);
    expect(result.verified).toBe(true);
    expect(result.exportPayload).toBeDefined();

    // Wrong answers
    const adapter2 = new StubIdentityAdapter({ mode: "stub" });
    const recovery2 = await adapter2.initiateRecovery("user@example.com");
    const wrong = await adapter2.submitChallengeAnswers(recovery2.sessionId, [
      { challengeId: "c1", answer: "wrong" },
    ]);
    expect(wrong.verified).toBe(false);
  });

  // T10: PlexusAdapter alias resolves from loom types.ts
  test("T10: PlexusAdapter alias in loom types.ts", () => {
    const typesSource = readFileSync(
      join(ROOT, "runtime/services/src/plexus/types.ts"),
      "utf-8",
    );
    // Should re-export IdentityAdapter as PlexusAdapter
    expect(typesSource).toContain("IdentityAdapter as PlexusAdapter");
    expect(typesSource).toContain("IdentityConfig as PlexusConfig");
    expect(typesSource).toContain("IdentityError as PlexusError");
    expect(typesSource).toContain("IdentityMode as PlexusMode");
    expect(typesSource).toContain("IdentityState as PlexusState");
  });

  // T11: StubPlexusAdapter alias works from workbench stub.ts
  test("T11: StubPlexusAdapter alias in loom", async () => {
    const { StubPlexusAdapter } = require(
      join(ROOT, "runtime/services/src/plexus/stub.ts"),
    );
    const adapter = new StubPlexusAdapter({ mode: "stub" });
    const result = await adapter.registerIdentity("compat@example.com");

    expect(result.certId).toMatch(/^cert:/);
    expect(result.publicKey).toContain("-----BEGIN PUBLIC KEY-----");
  });

  // T12: PlexusService still works with sync createAdapter
  test("T12: PlexusService works after extraction", async () => {
    const { PlexusService } = require(
      join(ROOT, "runtime/services/src/plexus/PlexusService.ts"),
    );
    const service = new PlexusService({ mode: "stub" });
    const result = await service.registerIdentity("test@example.com");

    expect(result.certId).toMatch(/^cert:/);
    expect(result.publicKey).toContain("-----BEGIN PUBLIC KEY-----");

    const snapshot = service.getSnapshot();
    expect(snapshot.identities.size).toBe(1);
    expect(snapshot.currentIdentity?.certId).toBe(result.certId);
  });
});

// ── Gate 4: Anti-Lock Boundary ──────────────────────────────────

describe("Phase 26A — Anti-Lock", () => {
  // T13: No @plexus imports in protocol-types/src/
  test("T13: no @plexus imports in protocol-types", () => {
    const filesToCheck = [
      "core/protocol-types/src/identity.ts",
      "core/protocol-types/src/adapters/stub-identity-adapter.ts",
      "core/protocol-types/src/adapters/create-identity-adapter.ts",
    ];

    for (const file of filesToCheck) {
      const content = readFileSync(join(ROOT, file), "utf-8");
      expect(content).not.toContain("@plexus");
    }
  });

  // T14: identity.ts contains only primitive types (no Plexus internals)
  test("T14: identity.ts uses only primitive types", () => {
    const content = readFileSync(
      join(ROOT, "core/protocol-types/src/identity.ts"),
      "utf-8",
    );
    const forbidden = ["PlexusNode", "PlexusCert", "BRC52", "@plexus", "VendorSDK"];
    for (const pattern of forbidden) {
      expect(content).not.toContain(pattern);
    }
  });

  // T15: loom stub.ts has no class definition (only re-export)
  test("T15: StubPlexusAdapter moved, not duplicated", () => {
    const stubSource = readFileSync(
      join(ROOT, "runtime/services/src/plexus/stub.ts"),
      "utf-8",
    );
    // Should NOT contain the full class implementation
    expect(stubSource).not.toContain("class StubPlexusAdapter implements");
    // Should contain re-export
    expect(stubSource).toContain("StubIdentityAdapter as StubPlexusAdapter");
  });
});

```
