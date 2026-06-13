---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase26c-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.572099+00:00
---

# tests/gates/phase26c-gate.test.ts

```ts
/**
 * Phase 26C Gate: AnchorAdapter — Decoupling Proof from Storage
 *
 * Validates:
 * 1. StubAnchorAdapter behavior (T1–T8)
 * 2. BsvAnchorAdapter structure (T9–T12)
 * 3. Jurisdiction proof (T13–T15)
 * 4. AnchorScheduler integration
 * 5. Boundary enforcement (no @bsv/* imports outside adapters/)
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { createHash } from "crypto";

const ROOT = join(import.meta.dir, "../..");

function sha256hex(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}

/**
 * Verify a Merkle proof path reconstructs to the expected root.
 */
function verifyMerkleProof(
  leafHash: string,
  proofJson: string,
  expectedRoot: string,
): boolean {
  const path: Array<{ hash: string; side: "left" | "right" }> =
    JSON.parse(proofJson);
  let current = leafHash;

  for (const step of path) {
    if (step.side === "left") {
      current = sha256hex(step.hash + current);
    } else {
      current = sha256hex(current + step.hash);
    }
  }

  return current === expectedRoot;
}

// ── Gate 1: StubAnchorAdapter Unit Tests (T1–T8) ─────────────────

describe("Phase 26C — StubAnchorAdapter", () => {
  // Dynamically import to avoid bundling @bsv/sdk in test context
  async function makeStub(interval = 600_000) {
    const { StubAnchorAdapter } = await import(
      "../../core/protocol-types/src/adapters/stub-anchor-adapter"
    );
    return new StubAnchorAdapter(interval);
  }

  test("T1: anchor() returns proof with txid, blockHeight, timestamp, merkleProof", async () => {
    const stub = await makeStub();
    const hash = sha256hex("test-state-1");
    const proof = await stub.anchor(hash);

    expect(proof.stateHash).toBe(hash);
    expect(proof.txid).toHaveLength(64); // SHA-256 hex
    expect(proof.vout).toBe(0);
    expect(proof.blockHeight).toBeGreaterThan(1_000_000);
    expect(proof.blockHash).toHaveLength(64);
    expect(proof.timestamp).toBeGreaterThan(0);
    expect(proof.merkleProof).toHaveLength(64);
    expect(proof.interval).toBe(600_000);

    // Verify txid is deterministic from stateHash
    expect(proof.txid).toBe(sha256hex("stub:" + hash));
  });

  test("T2: anchor() same stateHash produces deterministic txid", async () => {
    const stub = await makeStub();
    const hash = sha256hex("determinism-check");
    const proof1 = await stub.anchor(hash);
    const proof2 = await stub.anchor(hash);

    // txid must be identical for same input
    expect(proof1.txid).toBe(proof2.txid);
    expect(proof1.txid).toBe(sha256hex("stub:" + hash));
  });

  test("T3: batchAnchor() produces N proofs with shared blockHash, sequential vout", async () => {
    const stub = await makeStub();
    const hashes = [
      sha256hex("batch-1"),
      sha256hex("batch-2"),
      sha256hex("batch-3"),
    ];
    const items = hashes.map((h) => ({ stateHash: h }));
    const proofs = await stub.batchAnchor(items);

    expect(proofs).toHaveLength(3);

    // All share same blockHash and txid
    const blockHash = proofs[0].blockHash;
    const txid = proofs[0].txid;
    for (const p of proofs) {
      expect(p.blockHash).toBe(blockHash);
      expect(p.txid).toBe(txid);
    }

    // Sequential vout
    expect(proofs[0].vout).toBe(0);
    expect(proofs[1].vout).toBe(1);
    expect(proofs[2].vout).toBe(2);

    // Each proof has its own stateHash
    expect(proofs[0].stateHash).toBe(hashes[0]);
    expect(proofs[1].stateHash).toBe(hashes[1]);
    expect(proofs[2].stateHash).toBe(hashes[2]);
  });

  test("T4: batchAnchor() merkle paths validate correctly", async () => {
    const stub = await makeStub();
    const hashes = [
      sha256hex("merkle-a"),
      sha256hex("merkle-b"),
      sha256hex("merkle-c"),
      sha256hex("merkle-d"),
    ];
    const items = hashes.map((h) => ({ stateHash: h }));
    const proofs = await stub.batchAnchor(items);

    // Compute expected Merkle root
    const left = sha256hex(hashes[0] + hashes[1]);
    const right = sha256hex(hashes[2] + hashes[3]);
    const expectedRoot = sha256hex(left + right);

    // Each proof's merkle path should reconstruct to the same root
    for (let i = 0; i < proofs.length; i++) {
      const valid = verifyMerkleProof(
        hashes[i],
        proofs[i].merkleProof,
        expectedRoot,
      );
      expect(valid).toBe(true);
    }
  });

  test("T5: verify() always returns { valid: true }", async () => {
    const stub = await makeStub();
    const proof = await stub.anchor(sha256hex("verify-test"));
    const result = await stub.verify(proof);

    expect(result.valid).toBe(true);
    expect(result.timestamp).toBe(proof.timestamp);
    expect(result.blockHeight).toBe(proof.blockHeight);
  });

  test("T6: getLatestAnchor() returns most recent proof for a stateHash", async () => {
    const stub = await makeStub();
    const hash = sha256hex("latest-test");

    const proof1 = await stub.anchor(hash);
    const proof2 = await stub.anchor(hash);

    const latest = await stub.getLatestAnchor(hash);
    expect(latest).not.toBeNull();
    expect(latest!.timestamp).toBe(proof2.timestamp);

    // Non-existent hash returns null
    const missing = await stub.getLatestAnchor(sha256hex("nonexistent"));
    expect(missing).toBeNull();
  });

  test("T7: getAnchorHistory() returns proofs in chronological order", async () => {
    const stub = await makeStub();
    const hash = sha256hex("history-test");
    const typeHint = "test.type";

    await stub.anchor(hash, { typeHint });
    await stub.anchor(hash, { typeHint });
    await stub.anchor(hash, { typeHint });

    const objectPath = `objects/${typeHint}/${hash}`;
    const history = await stub.getAnchorHistory(objectPath);

    expect(history.length).toBe(3);
    // Chronological order (oldest first)
    for (let i = 1; i < history.length; i++) {
      expect(history[i].timestamp).toBeGreaterThanOrEqual(
        history[i - 1].timestamp,
      );
    }
  });

  test("T8: setAnchorInterval() changes interval; getAnchorInterval() reflects new value", async () => {
    const stub = await makeStub(600_000);
    expect(stub.getAnchorInterval()).toBe(600_000);

    stub.setAnchorInterval(60_000);
    expect(stub.getAnchorInterval()).toBe(60_000);

    stub.setAnchorInterval(1_000);
    expect(stub.getAnchorInterval()).toBe(1_000);
  });
});

// ── Gate 2: BsvAnchorAdapter Structure (T9–T12) ─────────────────

describe("Phase 26C — BsvAnchorAdapter", () => {
  const adapterPath = join(
    ROOT,
    "core/protocol-types/src/adapters/bsv-anchor-adapter.ts",
  );

  test("T9: bsv-anchor-adapter.ts exists with anchor() method", () => {
    expect(existsSync(adapterPath)).toBe(true);
    const source = readFileSync(adapterPath, "utf-8");

    // Verify OP_RETURN transaction creation pattern
    expect(source).toContain("OP.OP_RETURN");
    expect(source).toContain("OP.OP_FALSE");
    expect(source).toContain("async anchor(");
    expect(source).toContain("stateHash");
  });

  test("T10: batchAnchor() creates single OP_RETURN with Merkle root", () => {
    const source = readFileSync(adapterPath, "utf-8");

    expect(source).toContain("async batchAnchor(");
    expect(source).toContain("buildMerkleTree");
    expect(source).toContain("merkleProofPath");
    // Single transaction with root
    expect(source).toContain("rootBytes");
  });

  test("T11: verify() validates merkle proof", () => {
    const source = readFileSync(adapterPath, "utf-8");

    expect(source).toContain("async verify(");
    // Verifies merkle path reconstruction
    expect(source).toContain("JSON.parse(proof.merkleProof)");
    expect(source).toContain("step.side");
  });

  test("T12: block header caching implemented", () => {
    const source = readFileSync(adapterPath, "utf-8");

    expect(source).toContain("blockHeaderCache");
    expect(source).toContain("fetchBlockHeader");
    expect(source).toContain("BLOCK_HEADER_CACHE_MAX");
    // LRU eviction
    expect(source).toContain("blockHeaderCache.size >= BLOCK_HEADER_CACHE_MAX");
  });
});

// ── Gate 3: Jurisdiction Proof (T13–T15) ─────────────────────────

describe("Phase 26C — Jurisdiction proof", () => {
  async function makeStub() {
    const { StubAnchorAdapter } = await import(
      "../../core/protocol-types/src/adapters/stub-anchor-adapter"
    );
    return new StubAnchorAdapter();
  }

  test("T13: StubAnchorAdapter includes bcaAddress in proof when provided", async () => {
    const stub = await makeStub();
    const hash = sha256hex("jurisdiction-test");
    const bcaAddress = "2602:f9f8:0060:0001::a3f8:b2c1";

    const proof = await stub.anchor(hash, { bcaAddress });
    expect(proof.bcaAddress).toBe(bcaAddress);

    // Without bcaAddress, field should be undefined
    const proofNoBca = await stub.anchor(hash);
    expect(proofNoBca.bcaAddress).toBeUndefined();
  });

  test("T14: BsvAnchorAdapter includes bcaAddress in source", () => {
    const adapterPath = join(
      ROOT,
      "core/protocol-types/src/adapters/bsv-anchor-adapter.ts",
    );
    const source = readFileSync(adapterPath, "utf-8");

    // Verify bcaAddress is included when provided
    expect(source).toContain("metadata?.bcaAddress");
    expect(source).toContain("proof.bcaAddress = metadata.bcaAddress");
  });

  test("T15: Proof verification works with or without bcaAddress", async () => {
    const stub = await makeStub();
    const hash = sha256hex("verify-bca-test");

    const proofWithBca = await stub.anchor(hash, {
      bcaAddress: "2602::1",
    });
    const proofWithoutBca = await stub.anchor(hash);

    const resultWith = await stub.verify(proofWithBca);
    const resultWithout = await stub.verify(proofWithoutBca);

    expect(resultWith.valid).toBe(true);
    expect(resultWithout.valid).toBe(true);
  });
});

// ── Gate 4: AnchorScheduler Integration ──────────────────────────

describe("Phase 26C — AnchorScheduler", () => {
  async function makeScheduler() {
    const { StubAnchorAdapter } = await import(
      "../../core/protocol-types/src/adapters/stub-anchor-adapter"
    );
    const { MemoryAdapter } = await import(
      "../../core/protocol-types/src/adapters/memory-adapter"
    );
    const { AnchorScheduler } = await import(
      "../../core/protocol-types/src/anchor-scheduler"
    );

    const adapter = new StubAnchorAdapter(600_000);
    const storage = new MemoryAdapter();
    const scheduler = new AnchorScheduler(adapter, storage);
    return { scheduler, adapter, storage };
  }

  test("Scheduler batch-anchors pending hashes on trigger", async () => {
    const { scheduler, storage } = await makeScheduler();
    const hash1 = sha256hex("pending-1");
    const hash2 = sha256hex("pending-2");

    scheduler.addPending(hash1);
    scheduler.addPending(hash2);
    expect(scheduler.getPendingCount()).toBe(2);

    await scheduler.anchor();
    expect(scheduler.getPendingCount()).toBe(0);
  });

  test("Scheduler stores proof references in storage", async () => {
    const { scheduler, storage } = await makeScheduler();
    const hash = sha256hex("storage-proof-test");

    scheduler.addPending(hash);
    await scheduler.anchor();

    // Verify proof was stored at proofs/{stateHash}/{timestamp}.proof
    const keys = await storage.list("proofs/");
    expect(keys.length).toBeGreaterThan(0);

    // Read the stored proof and verify it's valid JSON
    const proofKey = "proofs/" + keys[0];
    const data = await storage.read(proofKey);
    expect(data).not.toBeNull();

    const proof = JSON.parse(new TextDecoder().decode(data!));
    expect(proof.stateHash).toBe(hash);
    expect(proof.txid).toHaveLength(64);
  });

  test("Scheduler getState() returns correct snapshot", async () => {
    const { scheduler } = await makeScheduler();
    const hash1 = sha256hex("state-1");
    const hash2 = sha256hex("state-2");

    scheduler.addPending(hash1);
    scheduler.addPending(hash2);

    const state = await scheduler.getState();
    expect(state.interval).toBe(600_000);
    expect(state.pendingStateHashes).toHaveLength(2);
    expect(state.pendingStateHashes).toContain(hash1);
    expect(state.pendingStateHashes).toContain(hash2);
  });

  test("Scheduler anchor() is no-op with empty pending set", async () => {
    const { scheduler, storage } = await makeScheduler();
    await scheduler.anchor();
    const keys = await storage.list("proofs/");
    expect(keys.length).toBe(0);
  });
});

// ── Gate 5: Boundary Enforcement ─────────────────────────────────

describe("Phase 26C — Boundary enforcement", () => {
  test("No @bsv/* imports outside adapters/ directory", () => {
    const anchorPath = join(
      ROOT,
      "core/protocol-types/src/anchor.ts",
    );
    const schedulerPath = join(
      ROOT,
      "core/protocol-types/src/anchor-scheduler.ts",
    );

    const anchorSource = readFileSync(anchorPath, "utf-8");
    const schedulerSource = readFileSync(schedulerPath, "utf-8");

    // Check for actual import statements, not JSDoc references
    const importPattern = /from\s+['"]@bsv\//;
    expect(importPattern.test(anchorSource)).toBe(false);
    expect(importPattern.test(schedulerSource)).toBe(false);
  });

  test("AnchorAdapter interface uses only primitive types", () => {
    const anchorPath = join(
      ROOT,
      "core/protocol-types/src/anchor.ts",
    );
    const source = readFileSync(anchorPath, "utf-8");

    // No BSV SDK type names in the interface
    expect(source).not.toContain("Transaction");
    expect(source).not.toContain("PrivateKey");
    expect(source).not.toContain("PublicKey");
    expect(source).not.toContain("LockingScript");
  });

  test("anchor.ts, stub-anchor-adapter.ts, bsv-anchor-adapter.ts, anchor-scheduler.ts all exist", () => {
    const files = [
      "core/protocol-types/src/anchor.ts",
      "core/protocol-types/src/adapters/stub-anchor-adapter.ts",
      "core/protocol-types/src/adapters/bsv-anchor-adapter.ts",
      "core/protocol-types/src/anchor-scheduler.ts",
    ];
    for (const f of files) {
      expect(existsSync(join(ROOT, f))).toBe(true);
    }
  });

  test("Barrel exports include all anchor types", () => {
    const indexSource = readFileSync(
      join(ROOT, "core/protocol-types/src/index.ts"),
      "utf-8",
    );
    expect(indexSource).toContain("AnchorAdapter");
    expect(indexSource).toContain("AnchorProof");
    expect(indexSource).toContain("AnchorConfig");
    expect(indexSource).toContain("AnchorState");
    expect(indexSource).toContain("StubAnchorAdapter");
    expect(indexSource).toContain("BsvAnchorAdapter");
    expect(indexSource).toContain("AnchorScheduler");
    expect(indexSource).toContain("createAnchorAdapter");
  });
});

// ── Gate 6: Merkle Tree Correctness ──────────────────────────────

describe("Phase 26C — Merkle tree correctness", () => {
  async function makeStub() {
    const { StubAnchorAdapter } = await import(
      "../../core/protocol-types/src/adapters/stub-anchor-adapter"
    );
    return new StubAnchorAdapter();
  }

  test("Single-item batch produces valid proof", async () => {
    const stub = await makeStub();
    const hash = sha256hex("single-batch");
    const proofs = await stub.batchAnchor([{ stateHash: hash }]);

    expect(proofs).toHaveLength(1);
    expect(proofs[0].stateHash).toBe(hash);
    expect(proofs[0].vout).toBe(0);
  });

  test("Odd-count batch handles duplication correctly", async () => {
    const stub = await makeStub();
    const hashes = [
      sha256hex("odd-1"),
      sha256hex("odd-2"),
      sha256hex("odd-3"),
    ];
    const items = hashes.map((h) => ({ stateHash: h }));
    const proofs = await stub.batchAnchor(items);

    expect(proofs).toHaveLength(3);

    // Compute expected Merkle root with 3 leaves (last duplicated)
    const left = sha256hex(hashes[0] + hashes[1]);
    const right = sha256hex(hashes[2] + hashes[2]); // duplicated
    const expectedRoot = sha256hex(left + right);

    // All proofs should validate to same root
    for (let i = 0; i < proofs.length; i++) {
      const valid = verifyMerkleProof(
        hashes[i],
        proofs[i].merkleProof,
        expectedRoot,
      );
      expect(valid).toBe(true);
    }
  });

  test("Large batch (10 items) produces correct proofs", async () => {
    const stub = await makeStub();
    const hashes = Array.from({ length: 10 }, (_, i) =>
      sha256hex(`large-batch-${i}`),
    );
    const items = hashes.map((h) => ({ stateHash: h }));
    const proofs = await stub.batchAnchor(items);

    expect(proofs).toHaveLength(10);

    // All proofs should share the same txid and blockHash
    const txid = proofs[0].txid;
    const blockHash = proofs[0].blockHash;
    for (const p of proofs) {
      expect(p.txid).toBe(txid);
      expect(p.blockHash).toBe(blockHash);
    }

    // Each proof should have a unique vout
    const vouts = new Set(proofs.map((p) => p.vout));
    expect(vouts.size).toBe(10);

    // Verify all merkle proofs lead to the same root
    // Manually compute the merkle root
    function computeRoot(leaves: string[]): string {
      if (leaves.length === 1) return leaves[0];
      const next: string[] = [];
      for (let i = 0; i < leaves.length; i += 2) {
        const l = leaves[i];
        const r = leaves[i + 1] ?? leaves[i];
        next.push(sha256hex(l + r));
      }
      return computeRoot(next);
    }

    const expectedRoot = computeRoot(hashes);
    for (let i = 0; i < proofs.length; i++) {
      const valid = verifyMerkleProof(
        hashes[i],
        proofs[i].merkleProof,
        expectedRoot,
      );
      expect(valid).toBe(true);
    }
  });

  test("Batch anchor with bcaAddress propagates to all proofs", async () => {
    const stub = await makeStub();
    const bcaAddress = "2602:f9f8:0060:0001::a3f8:b2c1";
    const items = [
      { stateHash: sha256hex("bca-batch-1"), metadata: { bcaAddress } },
      { stateHash: sha256hex("bca-batch-2"), metadata: { bcaAddress } },
      { stateHash: sha256hex("bca-batch-3") }, // no bcaAddress
    ];
    const proofs = await stub.batchAnchor(items);

    expect(proofs[0].bcaAddress).toBe(bcaAddress);
    expect(proofs[1].bcaAddress).toBe(bcaAddress);
    expect(proofs[2].bcaAddress).toBeUndefined();
  });
});

```
