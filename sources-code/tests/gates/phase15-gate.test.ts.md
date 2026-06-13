---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase15-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.574633+00:00
---

# tests/gates/phase15-gate.test.ts

```ts
/**
 * Phase 15 Gate: RealPlexusAdapter + Environment Switching + Import Isolation
 *
 * Tests T21–T36 covering real BRC-42 adapter, determinism, config factory,
 * and type isolation constraints.
 *
 * Phase 14 tests (T1–T20) remain in phase14-gate.test.ts and must pass unchanged.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");
const WORKBENCH_SRC = join(ROOT, "runtime/services/src");

// Direct imports — real adapter uses bun:sqlite + @bsv/sdk
const { RealPlexusAdapter } = require("../../runtime/services/src/plexus/real");
const { createAdapter, resolveMode } = require("../../runtime/services/src/plexus/config");
const { PlexusService } = require("../../runtime/services/src/plexus/PlexusService");

// Helper: 64-char lowercase hex
const HEX64 = /^[0-9a-f]{64}$/;
// Helper: 66-char compressed pubkey (02 or 03 prefix)
const COMPRESSED_PUBKEY = /^0[23][0-9a-f]{64}$/;

// ── Unit Tests T21–T28: RealPlexusAdapter ──────────────────────────

describe("T21–T28: RealPlexusAdapter", () => {
  test("T21: registerIdentity returns deterministic certId + compressed pubkey", async () => {
    const adapter = new RealPlexusAdapter({ mode: "local" });
    const result1 = await adapter.registerIdentity("alice@example.com");
    const result2 = await adapter.registerIdentity("alice@example.com");

    // certId is 64-char hex (SHA-256 of canonical preimage)
    expect(result1.certId).toMatch(HEX64);
    // publicKey is 66-char compressed secp256k1
    expect(result1.publicKey).toMatch(COMPRESSED_PUBKEY);
    // Deterministic: same email → same certId
    expect(result1.certId).toBe(result2.certId);
    expect(result1.publicKey).toBe(result2.publicKey);

    // Different email → different certId
    const bob = await adapter.registerIdentity("bob@example.com");
    expect(bob.certId).not.toBe(result1.certId);
  });

  test("T22: deriveChild produces correct derivation at 3 levels deep", async () => {
    const adapter = new RealPlexusAdapter({ mode: "local" });
    const root = await adapter.registerIdentity("root@test.com");

    // Level 1
    const child = await adapter.deriveChild(root.certId, "facet-a", 0x00010002);
    expect(child.certId).toMatch(HEX64);
    expect(child.publicKey).toMatch(COMPRESSED_PUBKEY);
    expect(child.childIndex).toBe(0);
    expect(child.certId).not.toBe(root.certId);

    // Level 2
    const grandchild = await adapter.deriveChild(child.certId, "subfacet", 0x00010001);
    expect(grandchild.certId).toMatch(HEX64);
    expect(grandchild.childIndex).toBe(0);
    expect(grandchild.certId).not.toBe(child.certId);

    // Level 3
    const ggchild = await adapter.deriveChild(grandchild.certId, "deep", 0x00010003);
    expect(ggchild.certId).toMatch(HEX64);
    expect(ggchild.childIndex).toBe(0);

    // All certIds are distinct
    const ids = new Set([root.certId, child.certId, grandchild.certId, ggchild.certId]);
    expect(ids.size).toBe(4);
  });

  test("T23: deriveChild enforces monotonic childIndex", async () => {
    const adapter = new RealPlexusAdapter({ mode: "local" });
    const root = await adapter.registerIdentity("mono@test.com");

    const c0 = await adapter.deriveChild(root.certId, "a", 1);
    const c1 = await adapter.deriveChild(root.certId, "b", 1);
    const c2 = await adapter.deriveChild(root.certId, "c", 1);

    expect(c0.childIndex).toBe(0);
    expect(c1.childIndex).toBe(1);
    expect(c2.childIndex).toBe(2);

    // Next child gets index 3 (never rewinds)
    const c3 = await adapter.deriveChild(root.certId, "d", 1);
    expect(c3.childIndex).toBe(3);

    // Derive under c0 — its index space starts at 0
    const sub = await adapter.deriveChild(c0.certId, "sub", 1);
    expect(sub.childIndex).toBe(0);
  });

  test("T24: createEdge returns edgeId + sharedSecret, direction matters", async () => {
    const adapter = new RealPlexusAdapter({ mode: "local" });
    const alice = await adapter.registerIdentity("alice@edge.com");
    const bob = await adapter.registerIdentity("bob@edge.com");

    const edge = await adapter.createEdge(alice.certId, bob.certId);
    expect(edge.edgeId).toMatch(HEX64);
    expect(edge.sharedSecret).toMatch(HEX64);

    // Deterministic: same inputs → same result
    const edge2 = await adapter.createEdge(alice.certId, bob.certId);
    expect(edge2.edgeId).toBe(edge.edgeId);

    // Direction matters
    const reverse = await adapter.createEdge(bob.certId, alice.certId);
    expect(reverse.edgeId).not.toBe(edge.edgeId);
  });

  test("T25: querySubtree returns correct tree structure", async () => {
    const adapter = new RealPlexusAdapter({ mode: "local" });
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
    expect(d2.children[1].grandchildren).toHaveLength(0);
  });

  test("T26: presentCapability returns { valid: true }", async () => {
    const adapter = new RealPlexusAdapter({ mode: "local" });
    const id = await adapter.registerIdentity("cap@test.com");

    const result = await adapter.presentCapability(id.certId, "any-capability");
    expect(result.valid).toBe(true);
  });

  test("T27: initiateRecovery returns sessionId + challengeCount", async () => {
    const adapter = new RealPlexusAdapter({ mode: "local" });

    const recovery = await adapter.initiateRecovery("recover@test.com");
    expect(recovery.sessionId).toMatch(HEX64);
    expect(recovery.challengeCount).toBe(4);
    expect(recovery.challenges).toHaveLength(4);
    expect(recovery.challenges![0].id).toBe("c1");
    expect(recovery.challenges![0].prompt).toBeTruthy();

    // Deterministic session ID
    const recovery2 = await adapter.initiateRecovery("recover@test.com");
    expect(recovery2.sessionId).toBe(recovery.sessionId);
  });

  test("T28: submitChallengeAnswers with correct answers returns verified + exportPayload", async () => {
    const adapter = new RealPlexusAdapter({ mode: "local" });
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
    const adapter2 = new RealPlexusAdapter({ mode: "local" });
    const r2 = await adapter2.initiateRecovery("wrong@test.com");
    const bad = await adapter2.submitChallengeAnswers(r2.sessionId, [
      { challengeId: "c1", answer: "wrong" },
    ]);
    expect(bad.verified).toBe(false);
    expect(bad.exportPayload).toBeUndefined();
  });
});

// ── Cross-adapter and config tests T29–T31 ──────────────────────────

describe("T29–T31: Config and cross-adapter", () => {
  test("T29: Cross-instance determinism — two RealPlexusAdapters produce identical results", async () => {
    const adapter1 = new RealPlexusAdapter({ mode: "local" });
    const adapter2 = new RealPlexusAdapter({ mode: "local" });

    const r1 = await adapter1.registerIdentity("swap@test.com");
    const r2 = await adapter2.registerIdentity("swap@test.com");
    expect(r1.certId).toBe(r2.certId);
    expect(r1.publicKey).toBe(r2.publicKey);

    // Same derivation → same certId
    const d1 = await adapter1.deriveChild(r1.certId, "facet", 1);
    const d2 = await adapter2.deriveChild(r2.certId, "facet", 1);
    expect(d1.certId).toBe(d2.certId);
    expect(d1.childIndex).toBe(d2.childIndex);
  });

  test("T30: createAdapter returns correct adapter type per mode", () => {
    const stubAdapter = createAdapter({ mode: "stub" });
    // After Phase 26A, StubPlexusAdapter is a re-export of StubIdentityAdapter
    expect(["StubPlexusAdapter", "StubIdentityAdapter"]).toContain(stubAdapter.constructor.name);

    const realAdapter = createAdapter({ mode: "local" });
    expect(realAdapter.constructor.name).toBe("RealPlexusAdapter");
  });

  test("T31: PlexusService with mode 'local' works", async () => {
    const service = new PlexusService({ mode: "local" });
    const result = await service.registerIdentity("service-real@test.com");

    expect(result.certId).toMatch(HEX64);
    expect(result.publicKey).toMatch(COMPRESSED_PUBKEY);

    const snapshot = service.getSnapshot();
    expect(snapshot.identities.size).toBe(1);
    expect(snapshot.currentIdentity?.certId).toBe(result.certId);
  });
});

// ── Import isolation tests T32–T33 ──────────────────────────

describe("T32–T33: Import isolation", () => {
  test("T32: No @plexus imports outside plexus/ dir and plexus-* packages", () => {
    const scanDir = (dir: string): string[] => {
      const files: string[] = [];
      try {
        for (const entry of readdirSync(dir, { withFileTypes: true })) {
          const fullPath = join(dir, entry.name);
          if (entry.isDirectory() && entry.name !== "node_modules" && entry.name !== "plexus") {
            files.push(...scanDir(fullPath));
          } else if (entry.isFile() && (entry.name.endsWith(".ts") || entry.name.endsWith(".tsx"))) {
            files.push(fullPath);
          }
        }
      } catch {
        // Ignore permission errors
      }
      return files;
    };

    const files = scanDir(WORKBENCH_SRC);
    const violations: string[] = [];
    for (const file of files) {
      if (file.includes("/plexus/")) continue;
      const content = readFileSync(file, "utf-8");
      if (content.includes("@plexus/") || content.includes("@plexus\\")) {
        violations.push(file.replace(WORKBENCH_SRC + "/", ""));
      }
    }
    expect(violations).toEqual([]);
  });

  test("T33: real.ts is the only workbench file importing from @plexus/", () => {
    const scanDir = (dir: string): string[] => {
      const files: string[] = [];
      try {
        for (const entry of readdirSync(dir, { withFileTypes: true })) {
          const fullPath = join(dir, entry.name);
          if (entry.isDirectory() && entry.name !== "node_modules") {
            files.push(...scanDir(fullPath));
          } else if (entry.isFile() && (entry.name.endsWith(".ts") || entry.name.endsWith(".tsx"))) {
            files.push(fullPath);
          }
        }
      } catch {
        // Ignore permission errors
      }
      return files;
    };

    const plexusDir = join(WORKBENCH_SRC, "plexus");
    const files = scanDir(plexusDir);
    const importingFiles: string[] = [];

    for (const file of files) {
      const content = readFileSync(file, "utf-8");
      // Check for actual import statements (not comments)
      const importLines = content.split("\n").filter((l: string) => l.match(/^\s*import\s/) && l.includes("@plexus/"));
      if (importLines.length > 0) {
        importingFiles.push(file.replace(plexusDir + "/", ""));
      }
    }

    // Only real.ts should import from @plexus/
    expect(importingFiles).toEqual(["real.ts"]);
  });
});

// ── BRC-42 determinism and format tests T34–T36 ──────────────────────────

describe("T34–T36: BRC-42 properties", () => {
  test("T34: BRC-42 determinism — same parent + resource + domainFlag → same certId", async () => {
    const adapter1 = new RealPlexusAdapter({ mode: "local" });
    const adapter2 = new RealPlexusAdapter({ mode: "local" });

    const root1 = await adapter1.registerIdentity("determ@test.com");
    const root2 = await adapter2.registerIdentity("determ@test.com");

    const child1 = await adapter1.deriveChild(root1.certId, "trades.job", 0x00010002);
    const child2 = await adapter2.deriveChild(root2.certId, "trades.job", 0x00010002);

    expect(child1.certId).toBe(child2.certId);
    expect(child1.publicKey).toBe(child2.publicKey);
  });

  test("T35: Real pubkey is valid 33-byte compressed secp256k1", async () => {
    const adapter = new RealPlexusAdapter({ mode: "local" });
    const result = await adapter.registerIdentity("pubkey@test.com");

    // 66 hex chars = 33 bytes
    expect(result.publicKey).toHaveLength(66);
    // Must start with 02 or 03
    expect(result.publicKey.slice(0, 2)).toMatch(/^0[23]$/);
    // All lowercase hex
    expect(result.publicKey).toMatch(/^[0-9a-f]+$/);
  });

  test("T36: Unknown parentCertId throws PlexusError with code CERT_NOT_FOUND", async () => {
    const adapter = new RealPlexusAdapter({ mode: "local" });

    try {
      await adapter.deriveChild("0".repeat(64), "resource", 1);
      expect(true).toBe(false);
    } catch (err: any) {
      expect(err.code).toBe("CERT_NOT_FOUND");
      expect(err.message).toContain("not found");
      expect(err.recoverable).toBe(true);
    }

    // Also test resolveIdentity
    try {
      await adapter.resolveIdentity("0".repeat(64));
      expect(true).toBe(false);
    } catch (err: any) {
      expect(err.code).toBe("CERT_NOT_FOUND");
      expect(err.recoverable).toBe(true);
    }

    // Also test submitChallengeAnswers with bad session
    try {
      await adapter.submitChallengeAnswers("0".repeat(64), []);
      expect(true).toBe(false);
    } catch (err: any) {
      expect(err.code).toBe("SESSION_NOT_FOUND");
      expect(err.recoverable).toBe(true);
    }
  });
});

```
