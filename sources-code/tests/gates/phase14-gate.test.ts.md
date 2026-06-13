---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase14-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.574313+00:00
---

# tests/gates/phase14-gate.test.ts

```ts
/**
 * Phase 14 Gate: PlexusAdapter + StubAdapter + PlexusService
 *
 * Tests T1–T20 covering unit, integration, and anti-lock behavior.
 * StubPlexusAdapter and PlexusService are tested via direct import
 * (no @semantos/protocol-types dependency). Integration tests for
 * IdentityStore/LoomStore use source scanning (Bun import constraint).
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync, existsSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");
const WORKBENCH_SRC = join(ROOT, "runtime/services/src");
const PLEXUS_DIR = join(WORKBENCH_SRC, "plexus");

// Direct imports — plexus modules have zero @semantos/protocol-types dependency
const { StubPlexusAdapter } = require("../../runtime/services/src/plexus/stub");
const { PlexusService } = require("../../runtime/services/src/plexus/PlexusService");

// ── Unit Tests T1–T8: StubPlexusAdapter ──────────────────────────

describe("T1–T8: StubPlexusAdapter", () => {
  test("T1: registerIdentity returns deterministic certId + publicKey", async () => {
    const adapter = new StubPlexusAdapter({ mode: "stub" });
    const result1 = await adapter.registerIdentity("alice@example.com");
    const result2 = await adapter.registerIdentity("alice@example.com");

    // certId has "cert:" prefix
    expect(result1.certId).toMatch(/^cert:[0-9a-f]{32}$/);
    // publicKey is PEM-formatted
    expect(result1.publicKey).toContain("-----BEGIN PUBLIC KEY-----");
    expect(result1.publicKey).toContain("-----END PUBLIC KEY-----");
    // Deterministic: same email → same certId
    expect(result1.certId).toBe(result2.certId);

    // Different email → different certId
    const bob = await adapter.registerIdentity("bob@example.com");
    expect(bob.certId).not.toBe(result1.certId);
  });

  test("T2: deriveChild produces correct derivation at 3 levels deep", async () => {
    const adapter = new StubPlexusAdapter({ mode: "stub" });
    const root = await adapter.registerIdentity("root@test.com");

    // Level 1: root → child
    const child = await adapter.deriveChild(root.certId, "facet-a", 0x00010002);
    expect(child.certId).toMatch(/^cert:[0-9a-f]{32}$/);
    expect(child.childIndex).toBe(0);
    expect(child.certId).not.toBe(root.certId);

    // Level 2: child → grandchild
    const grandchild = await adapter.deriveChild(child.certId, "subfacet", 0x00010001);
    expect(grandchild.certId).toMatch(/^cert:[0-9a-f]{32}$/);
    expect(grandchild.childIndex).toBe(0);
    expect(grandchild.certId).not.toBe(child.certId);
    expect(grandchild.certId).not.toBe(root.certId);

    // Level 3: grandchild → great-grandchild
    const ggchild = await adapter.deriveChild(grandchild.certId, "deep", 0x00010003);
    expect(ggchild.certId).toMatch(/^cert:[0-9a-f]{32}$/);
    expect(ggchild.childIndex).toBe(0);

    // All certIds are distinct
    const ids = new Set([root.certId, child.certId, grandchild.certId, ggchild.certId]);
    expect(ids.size).toBe(4);
  });

  test("T3: deriveChild enforces monotonic childIndex", async () => {
    const adapter = new StubPlexusAdapter({ mode: "stub" });
    const root = await adapter.registerIdentity("mono@test.com");

    const c0 = await adapter.deriveChild(root.certId, "a", 1);
    const c1 = await adapter.deriveChild(root.certId, "b", 1);
    const c2 = await adapter.deriveChild(root.certId, "c", 1);

    expect(c0.childIndex).toBe(0);
    expect(c1.childIndex).toBe(1);
    expect(c2.childIndex).toBe(2);

    // Even after "conceptual deletion" — derive another child, index must be 3
    const c3 = await adapter.deriveChild(root.certId, "d", 1);
    expect(c3.childIndex).toBe(3);

    // Derive under c0 — its index space starts at 0
    const sub = await adapter.deriveChild(c0.certId, "sub", 1);
    expect(sub.childIndex).toBe(0);
  });

  test("T4: createEdge returns edgeId + sharedSecret hash", async () => {
    const adapter = new StubPlexusAdapter({ mode: "stub" });
    const alice = await adapter.registerIdentity("alice@edge.com");
    const bob = await adapter.registerIdentity("bob@edge.com");

    const edge = await adapter.createEdge(alice.certId, bob.certId);
    expect(edge.edgeId).toMatch(/^edge:[0-9a-f]{32}$/);
    expect(edge.sharedSecret).toMatch(/^[0-9a-f]{64}$/);

    // Deterministic: same inputs → same result
    const edge2 = await adapter.createEdge(alice.certId, bob.certId);
    expect(edge2.edgeId).toBe(edge.edgeId);
    expect(edge2.sharedSecret).toBe(edge.sharedSecret);

    // Direction matters
    const reverse = await adapter.createEdge(bob.certId, alice.certId);
    expect(reverse.edgeId).not.toBe(edge.edgeId);
  });

  test("T5: querySubtree returns correct tree at depth 1, 2, 3", async () => {
    const adapter = new StubPlexusAdapter({ mode: "stub" });
    const root = await adapter.registerIdentity("tree@test.com");
    const c0 = await adapter.deriveChild(root.certId, "child-0", 1);
    const c1 = await adapter.deriveChild(root.certId, "child-1", 1);
    const gc0 = await adapter.deriveChild(c0.certId, "grandchild-0", 1);

    // Depth 1: only direct children
    const d1 = await adapter.querySubtree(root.certId, 1);
    expect(d1.root).toBe(root.certId);
    expect(d1.children).toHaveLength(2);
    expect(d1.children[0].certId).toBe(c0.certId);
    expect(d1.children[0].resourceId).toBe("child-0");
    expect(d1.children[1].certId).toBe(c1.certId);

    // Depth 2: children + grandchildren
    const d2 = await adapter.querySubtree(root.certId, 2);
    expect(d2.children).toHaveLength(2);
    expect(d2.children[0].grandchildren).toHaveLength(1);
    expect(d2.children[0].grandchildren![0].certId).toBe(gc0.certId);
    expect(d2.children[0].grandchildren![0].resourceId).toBe("grandchild-0");
    expect(d2.children[1].grandchildren).toHaveLength(0);

    // Depth 3: no great-grandchildren exist, but traversal works
    const d3 = await adapter.querySubtree(root.certId, 3);
    expect(d3.children).toHaveLength(2);
    expect(d3.children[0].grandchildren).toHaveLength(1);
  });

  test("T6: presentCapability returns { valid: true } for all", async () => {
    const adapter = new StubPlexusAdapter({ mode: "stub" });
    const id = await adapter.registerIdentity("cap@test.com");

    const result = await adapter.presentCapability(id.certId, "any-capability");
    expect(result.valid).toBe(true);
    expect(result.reason).toBeUndefined();

    // Works for any capability string
    const result2 = await adapter.presentCapability(id.certId, "0x00010002");
    expect(result2.valid).toBe(true);
  });

  test("T7: initiateRecovery returns sessionId + challengeCount", async () => {
    const adapter = new StubPlexusAdapter({ mode: "stub" });

    const recovery = await adapter.initiateRecovery("recover@test.com");
    expect(recovery.sessionId).toMatch(/^session:[0-9a-f]{32}$/);
    expect(recovery.challengeCount).toBe(4);
    expect(recovery.challenges).toHaveLength(4);
    expect(recovery.challenges![0].id).toBe("c1");
    expect(recovery.challenges![0].prompt).toBeTruthy();

    // Deterministic session ID
    const recovery2 = await adapter.initiateRecovery("recover@test.com");
    expect(recovery2.sessionId).toBe(recovery.sessionId);
  });

  test("T8: submitChallengeAnswers with correct answers returns verified + exportPayload", async () => {
    const adapter = new StubPlexusAdapter({ mode: "stub" });
    const recovery = await adapter.initiateRecovery("verified@test.com");

    // Correct answers
    const result = await adapter.submitChallengeAnswers(recovery.sessionId, [
      { challengeId: "c1", answer: "verified@test.com" },
      { challengeId: "c2", answer: "4" },
      { challengeId: "c3", answer: "true" },
      { challengeId: "c4", answer: "42" },
    ]);
    expect(result.verified).toBe(true);
    expect(result.exportPayload).toBeTruthy();
    // exportPayload is base64-encoded JSON
    const decoded = JSON.parse(Buffer.from(result.exportPayload!, "base64").toString());
    expect(decoded.sessionId).toBe(recovery.sessionId);
    expect(decoded.email).toBe("verified@test.com");

    // Wrong answers
    const adapter2 = new StubPlexusAdapter({ mode: "stub" });
    const r2 = await adapter2.initiateRecovery("wrong@test.com");
    const bad = await adapter2.submitChallengeAnswers(r2.sessionId, [
      { challengeId: "c1", answer: "wrong" },
    ]);
    expect(bad.verified).toBe(false);
    expect(bad.exportPayload).toBeUndefined();
  });
});

// ── Unit Tests T9–T10: PlexusService ──────────────────────────

describe("T9–T10: PlexusService", () => {
  test("T9: PlexusService constructor with mode 'stub' creates working service", async () => {
    const service = new PlexusService({ mode: "stub" });
    const snapshot = service.getSnapshot();
    expect(snapshot.identities).toBeDefined();
    expect(snapshot.edges).toBeDefined();

    // Can register identity through the service
    const result = await service.registerIdentity("service@test.com");
    expect(result.certId).toMatch(/^cert:/);
    expect(result.publicKey).toContain("PUBLIC KEY");

    // State updated
    const after = service.getSnapshot();
    expect(after.identities.size).toBe(1);
    expect(after.currentIdentity?.certId).toBe(result.certId);
    expect(after.lastOperation?.method).toBe("registerIdentity");
    expect(after.lastOperation?.success).toBe(true);
  });

  test("T10: PlexusService.subscribe notifies after state-changing operations", async () => {
    const service = new PlexusService({ mode: "stub" });
    let notifyCount = 0;
    const unsub = service.subscribe(() => { notifyCount++; });

    // registerIdentity should notify
    await service.registerIdentity("notify@test.com");
    expect(notifyCount).toBe(1);

    // deriveChild should notify
    const snap = service.getSnapshot();
    await service.deriveChild(snap.currentIdentity!.certId, "child", 1);
    expect(notifyCount).toBe(2);

    // createEdge should notify (need two identities)
    const other = await service.registerIdentity("other@test.com");
    expect(notifyCount).toBe(3);
    await service.createEdge(snap.currentIdentity!.certId, other.certId);
    expect(notifyCount).toBe(4);

    // Unsubscribe works
    unsub();
    await service.registerIdentity("ignored@test.com");
    expect(notifyCount).toBe(4); // no increment
  });
});

// ── Integration Tests T11–T15 ──────────────────────────

describe("T11–T15: PlexusService integration", () => {
  test("T11: IdentityStore source delegates to PlexusService", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "services/IdentityStore.ts"), "utf-8");
    expect(source).toContain("getPlexusService");
    expect(source).toContain("plexus/PlexusService");
    expect(source).toContain("registerIdentity");
    expect(source).toContain("deriveChild");
  });

  test("T12: IdentityStore.createIdentity stamps certId on identity", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "services/IdentityStore.ts"), "utf-8");
    // createIdentity method stores certId from plexus result
    expect(source).toContain("certId");
    expect(source).toContain("publicKey");
    // The Identity type has certId field
    const typesSource = readFileSync(join(WORKBENCH_SRC, "types/loom.ts"), "utf-8");
    expect(typesSource).toContain("certId?: string");
  });

  test("T13: LoomProvider uses certId for ownerIdBytes", () => {
    const source = readFileSync(join(WORKBENCH_SRC, "state/LoomProvider.tsx"), "utf-8");
    expect(source).toContain("activeFacet?.certId");
    expect(source).toContain("hexToBytes16");
    expect(source).toContain("replace(/^cert:/");
  });

  test("T14: 3 facets under one identity → 3 distinct certIds with sequential childIndex", async () => {
    const adapter = new StubPlexusAdapter({ mode: "stub" });
    const root = await adapter.registerIdentity("multi@test.com");

    const f0 = await adapter.deriveChild(root.certId, "Developer", 0x00010002);
    const f1 = await adapter.deriveChild(root.certId, "Contractor", 0x00010002);
    const f2 = await adapter.deriveChild(root.certId, "Admin", 0x00010002);

    // Sequential childIndex
    expect(f0.childIndex).toBe(0);
    expect(f1.childIndex).toBe(1);
    expect(f2.childIndex).toBe(2);

    // All distinct certIds
    const ids = new Set([f0.certId, f1.certId, f2.certId]);
    expect(ids.size).toBe(3);

    // All have valid public keys
    for (const f of [f0, f1, f2]) {
      expect(f.publicKey).toContain("PUBLIC KEY");
    }
  });

  test("T15: querySubtree on root returns all derived facets", async () => {
    const adapter = new StubPlexusAdapter({ mode: "stub" });
    const root = await adapter.registerIdentity("subtree@test.com");

    await adapter.deriveChild(root.certId, "Developer", 0x00010002);
    await adapter.deriveChild(root.certId, "Contractor", 0x00010002);
    await adapter.deriveChild(root.certId, "Admin", 0x00010002);

    const tree = await adapter.querySubtree(root.certId, 1);
    expect(tree.root).toBe(root.certId);
    expect(tree.children).toHaveLength(3);
    expect(tree.children[0].resourceId).toBe("Developer");
    expect(tree.children[1].resourceId).toBe("Contractor");
    expect(tree.children[2].resourceId).toBe("Admin");
    expect(tree.children[0].childIndex).toBe(0);
    expect(tree.children[1].childIndex).toBe(1);
    expect(tree.children[2].childIndex).toBe(2);
  });
});

// ── Anti-Lock Tests T16–T20 ──────────────────────────

describe("T16–T20: Anti-lock boundary", () => {
  test("T16: No @plexus imports outside packages/loom/src/plexus/", () => {
    // Recursively scan all .ts and .tsx files in workbench src
    const scanDir = (dir: string): string[] => {
      const files: string[] = [];
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const fullPath = join(dir, entry.name);
        if (entry.isDirectory() && entry.name !== "node_modules" && entry.name !== "plexus") {
          files.push(...scanDir(fullPath));
        } else if (entry.isFile() && (entry.name.endsWith(".ts") || entry.name.endsWith(".tsx"))) {
          files.push(fullPath);
        }
      }
      return files;
    };

    const files = scanDir(WORKBENCH_SRC);
    const violations: string[] = [];
    for (const file of files) {
      // Skip files inside the plexus/ directory
      if (file.includes("/plexus/")) continue;
      const content = readFileSync(file, "utf-8");
      if (content.includes("@plexus/") || content.includes("@plexus\\")) {
        violations.push(file.replace(WORKBENCH_SRC + "/", ""));
      }
    }
    expect(violations).toEqual([]);
  });

  test("T17: PlexusAdapter interface contains only primitive types", () => {
    const source = readFileSync(join(PLEXUS_DIR, "types.ts"), "utf-8");

    // Must NOT contain any Plexus-specific type names
    expect(source).not.toContain("PlexusNode");
    expect(source).not.toContain("PlexusCert");
    expect(source).not.toContain("BRC52Certificate");
    expect(source).not.toContain("BRC52");
    // Check for @plexus/ as an actual import, not in comments
    const importLines = source.split("\n").filter((l: string) => l.match(/^\s*import\s/));
    const plexusImports = importLines.filter((l: string) => l.includes("@plexus/"));
    expect(plexusImports).toEqual([]);

    // Must export PlexusAdapter (either as interface or re-export alias)
    expect(source).toContain("PlexusAdapter");

    // After Phase 26A extraction, verify the canonical interface lives in protocol-types
    const identitySource = readFileSync(
      join(PLEXUS_DIR, "../../../protocol-types/src/identity.ts"),
      "utf-8",
    );
    expect(identitySource).toContain("export interface IdentityAdapter");
  });

  test("T18: Adapter swap — two StubPlexusAdapter instances produce identical results", async () => {
    const adapter1 = new StubPlexusAdapter({ mode: "stub" });
    const adapter2 = new StubPlexusAdapter({ mode: "stub" });

    // Same email → same certId on both instances
    const r1 = await adapter1.registerIdentity("swap@test.com");
    const r2 = await adapter2.registerIdentity("swap@test.com");
    expect(r1.certId).toBe(r2.certId);
    expect(r1.publicKey).toBe(r2.publicKey);

    // Same derivation → same certId
    const d1 = await adapter1.deriveChild(r1.certId, "facet", 1);
    const d2 = await adapter2.deriveChild(r2.certId, "facet", 1);
    expect(d1.certId).toBe(d2.certId);
    expect(d1.childIndex).toBe(d2.childIndex);

    // Same edge → same result
    const other1 = await adapter1.registerIdentity("other@swap.com");
    const other2 = await adapter2.registerIdentity("other@swap.com");
    const e1 = await adapter1.createEdge(r1.certId, other1.certId);
    const e2 = await adapter2.createEdge(r2.certId, other2.certId);
    expect(e1.edgeId).toBe(e2.edgeId);
    expect(e1.sharedSecret).toBe(e2.sharedSecret);
  });

  test("T19: Unknown parentCertId throws PlexusError with recoverable: true", async () => {
    const adapter = new StubPlexusAdapter({ mode: "stub" });

    try {
      await adapter.deriveChild("cert:nonexistent", "resource", 1);
      // Should not reach here
      expect(true).toBe(false);
    } catch (err: any) {
      expect(err.code).toBe("CERT_NOT_FOUND");
      expect(err.message).toContain("not found");
      expect(err.recoverable).toBe(true);
    }

    // Also test resolveIdentity
    try {
      await adapter.resolveIdentity("cert:unknown");
      expect(true).toBe(false);
    } catch (err: any) {
      expect(err.code).toBe("CERT_NOT_FOUND");
      expect(err.recoverable).toBe(true);
    }

    // Also test submitChallengeAnswers with bad session
    try {
      await adapter.submitChallengeAnswers("session:fake", []);
      expect(true).toBe(false);
    } catch (err: any) {
      expect(err.code).toBe("SESSION_NOT_FOUND");
      expect(err.recoverable).toBe(true);
    }
  });

  test("T20: No Plexus-specific error types outside packages/loom/src/plexus/", () => {
    const scanDir = (dir: string): string[] => {
      const files: string[] = [];
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const fullPath = join(dir, entry.name);
        if (entry.isDirectory() && entry.name !== "node_modules" && entry.name !== "plexus") {
          files.push(...scanDir(fullPath));
        } else if (entry.isFile() && (entry.name.endsWith(".ts") || entry.name.endsWith(".tsx"))) {
          files.push(fullPath);
        }
      }
      return files;
    };

    const files = scanDir(WORKBENCH_SRC);
    const leakedTypes = ["PlexusCert", "PlexusNode", "BRC52Certificate"];
    const violations: string[] = [];
    for (const file of files) {
      if (file.includes("/plexus/")) continue;
      const content = readFileSync(file, "utf-8");
      for (const typeName of leakedTypes) {
        if (content.includes(typeName)) {
          violations.push(`${file.replace(WORKBENCH_SRC + "/", "")}: ${typeName}`);
        }
      }
    }
    expect(violations).toEqual([]);
  });
});

```
