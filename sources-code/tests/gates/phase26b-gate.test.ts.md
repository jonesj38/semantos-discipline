---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase26b-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.569797+00:00
---

# tests/gates/phase26b-gate.test.ts

```ts
/**
 * Phase 26B Gate: LocalIdentityAdapter — Offline Capability Validation
 *
 * Validates:
 * 1. LocalIdentityAdapter unit tests (T26B.1–T26B.5)
 * 2. CertChainStore unit tests (T26B.6–T26B.10)
 * 3. CapabilityTokenValidator unit tests (T26B.11–T26B.15)
 * 4. Integration tests (T26B.16–T26B.19)
 * 5. Anti-injection boundary (T26B.20)
 */

import { describe, test, expect, beforeEach } from "bun:test";
import { readFileSync, readdirSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");

// ── Shared setup ──

function createTestAdapter() {
  const { MemoryAdapter } = require(
    join(ROOT, "core/protocol-types/src/adapters/memory-adapter.ts"),
  );
  return new MemoryAdapter();
}

function createLocalIdentityAdapter(storage?: any) {
  const { LocalIdentityAdapter } = require(
    join(ROOT, "core/protocol-types/src/identity-adapters/LocalIdentityAdapter.ts"),
  );
  const s = storage ?? createTestAdapter();
  return { adapter: new LocalIdentityAdapter(s), storage: s };
}

function createCertChainStore(storage?: any) {
  const { CertChainStore } = require(
    join(ROOT, "core/protocol-types/src/identity-adapters/CertChainStore.ts"),
  );
  const s = storage ?? createTestAdapter();
  return { store: new CertChainStore(s), storage: s };
}

function createCapabilityTokenValidator(store: any) {
  const { CapabilityTokenValidator } = require(
    join(ROOT, "core/protocol-types/src/identity-adapters/CapabilityTokenValidator.ts"),
  );
  return new CapabilityTokenValidator(store);
}

function createKeyDerivationService() {
  const { KeyDerivationService } = require(
    join(ROOT, "core/protocol-types/src/identity-adapters/KeyDerivationService.ts"),
  );
  return new KeyDerivationService();
}

// ── Gate 1: LocalIdentityAdapter (T26B.1–T26B.5) ──

describe("Phase 26B — LocalIdentityAdapter", () => {
  test("T26B.1: registerIdentity generates deterministic certId", async () => {
    const { adapter } = createLocalIdentityAdapter();

    const first = await adapter.registerIdentity("alice@example.com");
    expect(first.certId).toMatch(/^cert:/);
    expect(first.publicKey).toContain("BEGIN PUBLIC KEY");

    // Same email → same certId
    const second = await adapter.registerIdentity("alice@example.com");
    expect(second.certId).toBe(first.certId);
    expect(second.publicKey).toBe(first.publicKey);

    // Different email → different certId
    const bob = await adapter.registerIdentity("bob@example.com");
    expect(bob.certId).not.toBe(first.certId);
  });

  test("T26B.2: resolveIdentity retrieves stored cert", async () => {
    const { adapter } = createLocalIdentityAdapter();

    const { certId } = await adapter.registerIdentity("bob@example.com");
    const resolved = await adapter.resolveIdentity(certId);

    expect(resolved.certId).toBe(certId);
    expect(resolved.email).toBe("bob@example.com");
    expect(resolved.publicKey).toContain("BEGIN PUBLIC KEY");
    expect(resolved.created).toBeGreaterThan(0);
  });

  test("T26B.3: deriveChild enforces monotonic childIndex", async () => {
    const { adapter } = createLocalIdentityAdapter();

    const { certId: parent } = await adapter.registerIdentity("alice@example.com");

    const child0 = await adapter.deriveChild(parent, "resource1", 0x00010002);
    expect(child0.childIndex).toBe(0);

    const child1 = await adapter.deriveChild(parent, "resource2", 0x00010002);
    expect(child1.childIndex).toBe(1);

    const child2 = await adapter.deriveChild(parent, "resource3", 0x00010002);
    expect(child2.childIndex).toBe(2);

    // Indices are strictly increasing
    expect(child1.childIndex).toBeGreaterThan(child0.childIndex);
    expect(child2.childIndex).toBeGreaterThan(child1.childIndex);
  });

  test("T26B.4: deriveChild is deterministic (same inputs, same adapter state)", async () => {
    // Two fresh adapters with same email produce same root certId
    const { adapter: a1 } = createLocalIdentityAdapter();
    const { adapter: a2 } = createLocalIdentityAdapter();

    const root1 = await a1.registerIdentity("alice@example.com");
    const root2 = await a2.registerIdentity("alice@example.com");
    expect(root1.certId).toBe(root2.certId);

    // First child of each (same parentCertId, same resourceId, same domainFlag, same index=0)
    const child1 = await a1.deriveChild(root1.certId, "resource1", 0x00010002);
    const child2 = await a2.deriveChild(root2.certId, "resource1", 0x00010002);
    expect(child1.certId).toBe(child2.certId);
    expect(child1.publicKey).toBe(child2.publicKey);
  });

  test("T26B.5: revokeChild reserves index, next child gets N+1", async () => {
    const storage = createTestAdapter();
    const { adapter } = createLocalIdentityAdapter(storage);
    const { CertChainStore } = require(
      join(ROOT, "core/protocol-types/src/identity-adapters/CertChainStore.ts"),
    );
    const certStore = new CertChainStore(storage);

    const { certId: parent } = await adapter.registerIdentity("alice@example.com");

    const child0 = await adapter.deriveChild(parent, "resource1", 0x00010002);
    expect(child0.childIndex).toBe(0);

    // Revoke child0
    await certStore.revokeChild(child0.certId);

    // Verify child0 is revoked
    const revoked = await certStore.get(child0.certId);
    expect(revoked!.revoked).toBe(true);

    // Next child should get index 1, not 0
    const child1 = await adapter.deriveChild(parent, "resource2", 0x00010002);
    expect(child1.childIndex).toBe(1);
  });
});

// ── Gate 2: CertChainStore (T26B.6–T26B.10) ──

describe("Phase 26B — CertChainStore", () => {
  test("T26B.6: put/get round-trip", async () => {
    const { store } = createCertChainStore();

    const cert = {
      certId: "cert:test123",
      email: "test@example.com",
      publicKey: "-----BEGIN PUBLIC KEY-----\ntest\n-----END PUBLIC KEY-----",
      domainFlags: [0x00010001, 0x00010002],
      created: Date.now(),
      revoked: false,
    };

    await store.put(cert.certId, cert);
    const retrieved = await store.get(cert.certId);

    expect(retrieved).not.toBeNull();
    expect(retrieved!.certId).toBe(cert.certId);
    expect(retrieved!.email).toBe(cert.email);
    expect(retrieved!.domainFlags).toEqual(cert.domainFlags);
    expect(retrieved!.revoked).toBe(false);
  });

  test("T26B.7: getChildren sorted by childIndex", async () => {
    const { store } = createCertChainStore();
    const parentId = "cert:parent";

    // Store parent
    await store.put(parentId, {
      certId: parentId,
      publicKey: "test",
      domainFlags: [],
      created: Date.now(),
      revoked: false,
    });

    // Store children out of order
    for (const idx of [2, 0, 1]) {
      await store.put(`cert:child${idx}`, {
        certId: `cert:child${idx}`,
        publicKey: `key${idx}`,
        parentCertId: parentId,
        childIndex: idx,
        resourceId: `res${idx}`,
        domainFlags: [0x00010002],
        created: Date.now(),
        revoked: false,
      });
    }

    const children = await store.getChildren(parentId);
    expect(children).toHaveLength(3);
    expect(children[0].childIndex).toBe(0);
    expect(children[1].childIndex).toBe(1);
    expect(children[2].childIndex).toBe(2);
  });

  test("T26B.8: getNextChildIndex is monotonic", async () => {
    const { store } = createCertChainStore();
    const parentId = "cert:parent";

    await store.put(parentId, {
      certId: parentId,
      publicKey: "test",
      domainFlags: [],
      created: Date.now(),
      revoked: false,
    });

    // No children yet → 0
    const first = await store.getNextChildIndex(parentId);
    expect(first).toBe(0);

    // Add a child at index 0
    await store.put("cert:child0", {
      certId: "cert:child0",
      publicKey: "test",
      parentCertId: parentId,
      childIndex: 0,
      domainFlags: [],
      created: Date.now(),
      revoked: false,
    });

    // Next should be 1
    const second = await store.getNextChildIndex(parentId);
    expect(second).toBe(1);

    // claimNextChildIndex advances atomically
    const claimed = await store.claimNextChildIndex(parentId);
    expect(claimed).toBe(1);
    const after = await store.getNextChildIndex(parentId);
    expect(after).toBe(2);
  });

  test("T26B.9: walk respects maxDepth", async () => {
    const { store } = createCertChainStore();

    // Build 3-level tree: root → child → grandchild
    await store.put("cert:root", {
      certId: "cert:root",
      publicKey: "test",
      domainFlags: [],
      created: Date.now(),
      revoked: false,
    });
    await store.put("cert:child", {
      certId: "cert:child",
      publicKey: "test",
      parentCertId: "cert:root",
      childIndex: 0,
      domainFlags: [],
      created: Date.now(),
      revoked: false,
    });
    await store.put("cert:grandchild", {
      certId: "cert:grandchild",
      publicKey: "test",
      parentCertId: "cert:child",
      childIndex: 0,
      domainFlags: [],
      created: Date.now(),
      revoked: false,
    });

    // Walk depth=1 should only visit root + child
    const visited1: string[] = [];
    await store.walk("cert:root", async (cert) => {
      visited1.push(cert.certId);
    }, 1);
    expect(visited1).toEqual(["cert:root", "cert:child"]);

    // Walk depth=2 visits all three
    const visited2: string[] = [];
    await store.walk("cert:root", async (cert) => {
      visited2.push(cert.certId);
    }, 2);
    expect(visited2).toEqual(["cert:root", "cert:child", "cert:grandchild"]);
  });

  test("T26B.10: verifyAncestry", async () => {
    const { store } = createCertChainStore();

    await store.put("cert:parent", {
      certId: "cert:parent",
      publicKey: "test",
      domainFlags: [],
      created: Date.now(),
      revoked: false,
    });
    await store.put("cert:child", {
      certId: "cert:child",
      publicKey: "test",
      parentCertId: "cert:parent",
      childIndex: 0,
      domainFlags: [],
      created: Date.now(),
      revoked: false,
    });

    const valid = await store.verifyAncestry("cert:child", "cert:parent");
    expect(valid).toBe(true);

    const invalid = await store.verifyAncestry("cert:child", "cert:nonexistent");
    expect(invalid).toBe(false);

    const wrongParent = await store.verifyAncestry("cert:parent", "cert:child");
    expect(wrongParent).toBe(false);
  });
});

// ── Gate 3: CapabilityTokenValidator (T26B.11–T26B.15) ──

describe("Phase 26B — CapabilityTokenValidator", () => {
  test("T26B.11: parseToken parses valid token", () => {
    const { store } = createCertChainStore();
    const validator = createCapabilityTokenValidator(store);
    const kds = createKeyDerivationService();

    const key = kds.generateRootKey("test@example.com");
    const token = validator.createToken(
      "cert:issuer", "cert:holder", [0x00010001, 0x00010002],
      Date.now() + 60000, key,
    );

    const parsed = validator.parseToken(token);
    expect(parsed.issuerCertId).toBe("cert:issuer");
    expect(parsed.holderCertId).toBe("cert:holder");
    expect(parsed.domainFlags).toEqual([0x00010001, 0x00010002]);
    expect(parsed.signature).toBeTruthy();
  });

  test("T26B.12: rejects expired token", async () => {
    const { store } = createCertChainStore();
    const validator = createCapabilityTokenValidator(store);
    const kds = createKeyDerivationService();

    const key = kds.generateRootKey("test@example.com");
    // Create token that expired 1 second ago
    const token = validator.createToken(
      "cert:issuer", "cert:holder", [0x00010001],
      Date.now() - 1000, key,
    );

    const result = await validator.validateToken(token);
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("expired");
  });

  test("T26B.13: rejects invalid signature", async () => {
    const { store } = createCertChainStore();
    const validator = createCapabilityTokenValidator(store);
    const kds = createKeyDerivationService();

    // Store issuer cert
    const key = kds.generateRootKey("issuer@example.com");
    const certId = kds.generateCertId(key);
    await store.put(certId, {
      certId,
      publicKey: kds.generatePublicKey(key),
      domainFlags: [0x00010001],
      created: Date.now(),
      revoked: false,
    });

    // Create token with a different key (wrong signature)
    const wrongKey = kds.generateRootKey("wrong@example.com");
    const token = validator.createToken(
      certId, "cert:holder", [0x00010001],
      Date.now() + 60000, wrongKey,
    );

    const result = await validator.validateToken(token);
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("signature");
  });

  test("T26B.14: validates cert chain from holder to issuer", async () => {
    const { store } = createCertChainStore();
    const validator = createCapabilityTokenValidator(store);
    const kds = createKeyDerivationService();

    const rootKey = kds.generateRootKey("root@example.com");
    const rootCertId = kds.generateCertId(rootKey);
    const rootPubKey = kds.generatePublicKey(rootKey);

    // Store root (issuer)
    await store.put(rootCertId, {
      certId: rootCertId,
      publicKey: rootPubKey,
      domainFlags: [0x00010001, 0x00010002],
      created: Date.now(),
      revoked: false,
    });

    // Store child (holder) with parent reference
    const childKey = kds.deriveChildKey(rootKey, 0, 0x00010002);
    const childCertId = kds.generateCertId(childKey);
    await store.put(childCertId, {
      certId: childCertId,
      publicKey: kds.generatePublicKey(childKey),
      parentCertId: rootCertId,
      childIndex: 0,
      domainFlags: [0x00010002],
      created: Date.now(),
      revoked: false,
    });

    // Create token: root issues to child
    // Sign with key derived from root's public key (matches validator's keyFromPublicKey)
    const { createHash } = require("crypto");
    const sigKey = new Uint8Array(
      createHash("sha256").update(rootPubKey).digest().buffer,
    );
    const token = validator.createToken(
      rootCertId, childCertId, [0x00010002],
      Date.now() + 60000, sigKey,
    );

    const result = await validator.validateToken(token);
    expect(result.valid).toBe(true);
  });

  test("T26B.15: extractDomainFlags", () => {
    const { store } = createCertChainStore();
    const validator = createCapabilityTokenValidator(store);
    const kds = createKeyDerivationService();

    const key = kds.generateRootKey("test@example.com");
    const flags = [0x00010001, 0x00010003, 0x00010005];
    const token = validator.createToken(
      "cert:issuer", "cert:holder", flags,
      Date.now() + 60000, key,
    );

    const extracted = validator.extractDomainFlags(token);
    expect(extracted).toEqual(flags);
  });
});

// ── Gate 4: Integration Tests (T26B.16–T26B.19) ──

describe("Phase 26B — Integration", () => {
  test("T26B.16: create 3-level hierarchy", async () => {
    const { adapter, storage } = createLocalIdentityAdapter();

    // Root
    const root = await adapter.registerIdentity("pm@company.com");
    expect(root.certId).toMatch(/^cert:/);

    // Level 1: facet
    const facet = await adapter.deriveChild(root.certId, "property-mgmt", 0x00010002);
    expect(facet.childIndex).toBe(0);

    // Level 2: sub-facet
    const subfacet = await adapter.deriveChild(facet.certId, "lease-mgmt", 0x00010003);
    expect(subfacet.childIndex).toBe(0);

    // Verify all exist in storage
    const resolved = await adapter.resolveIdentity(root.certId);
    expect(resolved.children).toHaveLength(1);
    expect(resolved.children![0].certId).toBe(facet.certId);

    const facetResolved = await adapter.resolveIdentity(facet.certId);
    expect(facetResolved.children).toHaveLength(1);
    expect(facetResolved.children![0].certId).toBe(subfacet.certId);

    // querySubtree depth=2 should get all levels
    const subtree = await adapter.querySubtree(root.certId, 2);
    expect(subtree.root).toBe(root.certId);
    expect(subtree.children).toHaveLength(1);
    expect(subtree.children[0].grandchildren).toHaveLength(1);
  });

  test("T26B.17: offline capability validation completes in <10ms", async () => {
    const { adapter } = createLocalIdentityAdapter();

    const { certId } = await adapter.registerIdentity("tradie@vps.local");
    await adapter.deriveChild(certId, "jobs", 0x00010002);

    // Measure presentCapability round-trip
    const start = performance.now();
    const result = await adapter.presentCapability(certId, "0x00010002");
    const elapsed = performance.now() - start;

    expect(result.valid).toBe(true);
    expect(elapsed).toBeLessThan(10);
  });

  test("T26B.18: revocation propagates — revoked cert cannot present capabilities", async () => {
    const storage = createTestAdapter();
    const { adapter } = createLocalIdentityAdapter(storage);
    const { CertChainStore } = require(
      join(ROOT, "core/protocol-types/src/identity-adapters/CertChainStore.ts"),
    );
    const certStore = new CertChainStore(storage);

    const root = await adapter.registerIdentity("alice@example.com");
    const child = await adapter.deriveChild(root.certId, "resource1", 0x00010002);

    // Capability valid before revocation
    const before = await adapter.presentCapability(child.certId, "0x00010002");
    expect(before.valid).toBe(true);

    // Revoke child
    await certStore.revokeChild(child.certId);

    // Capability invalid after revocation
    const after = await adapter.presentCapability(child.certId, "0x00010002");
    expect(after.valid).toBe(false);
    expect(after.reason).toContain("revoked");
  });

  test("T26B.19: recovery shares end-to-end", () => {
    const { RecoveryShareManager } = require(
      join(ROOT, "core/protocol-types/src/identity-adapters/RecoveryShareManager.ts"),
    );
    const storage = createTestAdapter();
    const recovery = new RecoveryShareManager(storage);
    const kds = createKeyDerivationService();

    const masterKey = kds.generateRootKey("recovery@example.com");
    // Encryption key derived from recovery challenges (separate from master key)
    const encKey = kds.generateRootKey("challenge-answers-hash");

    // Generate 5 shares with threshold 3, encrypted with encKey
    const shares = recovery.generateRecoveryShares(masterKey, 3, 5, encKey);
    expect(shares).toHaveLength(5);

    // Each share is encrypted (not plaintext)
    for (const share of shares) {
      expect(share.encryptedData).toBeInstanceOf(Uint8Array);
      expect(share.iv).toBeInstanceOf(Uint8Array);
      expect(share.authTag).toBeInstanceOf(Uint8Array);
      expect(share.integrity).toBeTruthy();
    }

    // Verify integrity using encKey
    for (const share of shares) {
      expect(recovery.verifyShareIntegrity(share, encKey)).toBe(true);
    }

    // Reconstruct from shares [0, 2, 4] (any 3 of 5)
    const subset = [shares[0], shares[2], shares[4]];
    const reconstructed = recovery.reconstructMasterKey(subset, encKey);
    expect(reconstructed).toEqual(masterKey);

    // Reconstruct from different subset [1, 3, 4]
    const subset2 = [shares[1], shares[3], shares[4]];
    const reconstructed2 = recovery.reconstructMasterKey(subset2, encKey);
    expect(reconstructed2).toEqual(masterKey);
  });
});

// ── Gate 5: Anti-Injection Boundary (T26B.20) ──

describe("Phase 26B — Anti-injection", () => {
  test("T26B.20: no @plexus imports in identity-adapters/", () => {
    const dir = join(ROOT, "core/protocol-types/src/identity-adapters");
    const files = scanTsFiles(dir);
    const violations: string[] = [];

    for (const file of files) {
      const content = readFileSync(file, "utf-8");
      if (content.includes("@plexus/") || content.includes("@plexus\\")) {
        violations.push(file.replace(dir + "/", ""));
      }
    }

    expect(violations).toEqual([]);
  });
});

// ── Helpers ──

function scanTsFiles(dir: string): string[] {
  const files: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory() && entry.name !== "node_modules") {
      files.push(...scanTsFiles(fullPath));
    } else if (entry.isFile() && (entry.name.endsWith(".ts") || entry.name.endsWith(".tsx"))) {
      files.push(fullPath);
    }
  }
  return files;
}

```
