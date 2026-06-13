---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/chain-broadcast/chain-broadcast/src/__tests__/chain-tip-manager.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.521457+00:00
---

# packages/chain-broadcast/chain-broadcast/src/__tests__/chain-tip-manager.test.ts

```ts
/**
 * ChainTipManager tests — adapted from
 * todriguez/hackathon-submission:test/direct-broadcast-chaintip.test.ts@496ee8f
 *
 * The hackathon version reached into `(engine as any).utxoPools` via
 * white-box casts because the engine kept pools private. Our decomposition
 * exposes pools behind a clean public API (`ingest`, `pick`, `returnUtxo`,
 * `drain`, `persist`, `restore`), so these tests hit the surface directly.
 *
 * Covers:
 *   - Pool partitioning per stream
 *   - Dust-floor filtering in `pick()`
 *   - Idempotent `returnUtxo` / `drain`
 *   - Persist / restore round-trip preserves every field
 *   - Restore rejects stream-count mismatch
 *   - No-op when no `chainTipPath` configured
 */

import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync, existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PrivateKey, Transaction, P2PKH } from "@bsv/sdk";
import {
  ChainTipManager,
  type FundingUtxo,
} from "../chain-tip-manager.js";

function buildDummyTx(
  privKey: PrivateKey,
  outputs: { satoshis: number }[],
): Transaction {
  const tx = new Transaction();
  const p2pkh = new P2PKH();
  const lock = p2pkh.lock(privKey.toPublicKey().toAddress());
  for (const o of outputs) {
    tx.addOutput({ lockingScript: lock, satoshis: o.satoshis });
  }
  return tx;
}

function makeUtxo(
  sourceTx: Transaction,
  txid: string,
  vout: number,
  satoshis: number,
): FundingUtxo {
  return { txid, vout, satoshis, sourceTx };
}

describe("ChainTipManager", () => {
  let tmpDir: string;
  const privKey = PrivateKey.fromRandom();

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), "chaintip-test-"));
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it("ingestMany partitions round-robin across streams", () => {
    const mgr = new ChainTipManager({
      streams: 3,
      minFee: 100,
      cellSatoshis: 1,
    });
    const tx = buildDummyTx(
      privKey,
      Array.from({ length: 9 }, () => ({ satoshis: 500 })),
    );
    const utxos: FundingUtxo[] = Array.from({ length: 9 }, (_, i) =>
      makeUtxo(tx, "a".repeat(64), i, 500),
    );
    mgr.ingestMany(utxos);
    expect(mgr.balance().map((b) => b.utxoCount)).toEqual([3, 3, 3]);
    expect(mgr.totalPoolSize()).toBe(9);
  });

  it("pick returns non-dust UTXOs and throws when exhausted", () => {
    const mgr = new ChainTipManager({
      streams: 1,
      minFee: 100,
      cellSatoshis: 1,
    });
    const tx = buildDummyTx(privKey, [{ satoshis: 500 }, { satoshis: 200 }]);
    mgr.ingest(0, makeUtxo(tx, "b".repeat(64), 0, 500));
    mgr.ingest(0, makeUtxo(tx, "b".repeat(64), 1, 200)); // at threshold 101 — still useful
    const u = mgr.pick(0, "test");
    expect(u.satoshis).toBe(500);
    const u2 = mgr.pick(0, "test");
    expect(u2.satoshis).toBe(200);
    expect(() => mgr.pick(0, "test")).toThrow();
  });

  it("pick silently discards dust UTXOs below minFee + cellSatoshis", () => {
    const mgr = new ChainTipManager({
      streams: 1,
      minFee: 500,
      cellSatoshis: 1,
    });
    const tx = buildDummyTx(privKey, [{ satoshis: 100 }, { satoshis: 700 }]);
    // 100 is dust (< 501), 700 is useful
    mgr.ingest(0, makeUtxo(tx, "c".repeat(64), 0, 100));
    mgr.ingest(0, makeUtxo(tx, "c".repeat(64), 1, 700));
    const u = mgr.pick(0, "op");
    expect(u.satoshis).toBe(700);
    expect(mgr.poolSize(0)).toBe(0);
  });

  it("returnUtxo recycles change back into the pool", () => {
    const mgr = new ChainTipManager({
      streams: 1,
      minFee: 100,
      cellSatoshis: 1,
    });
    const tx = buildDummyTx(privKey, [{ satoshis: 1_000 }]);
    mgr.ingest(0, makeUtxo(tx, "d".repeat(64), 0, 1_000));
    const u = mgr.pick(0, "op");
    expect(mgr.poolSize(0)).toBe(0);
    mgr.returnUtxo(0, { ...u, satoshis: 800, vout: 1 });
    expect(mgr.poolSize(0)).toBe(1);
    const u2 = mgr.pick(0, "op");
    expect(u2.satoshis).toBe(800);
  });

  it("drain returns and empties a stream's pool", () => {
    const mgr = new ChainTipManager({
      streams: 2,
      minFee: 100,
      cellSatoshis: 1,
    });
    const tx = buildDummyTx(privKey, [
      { satoshis: 500 },
      { satoshis: 500 },
      { satoshis: 500 },
    ]);
    mgr.ingest(0, makeUtxo(tx, "e".repeat(64), 0, 500));
    mgr.ingest(0, makeUtxo(tx, "e".repeat(64), 1, 500));
    mgr.ingest(1, makeUtxo(tx, "e".repeat(64), 2, 500));
    expect(mgr.poolSize(0)).toBe(2);
    const drained = mgr.drain(0);
    expect(drained).toHaveLength(2);
    expect(mgr.poolSize(0)).toBe(0);
    expect(mgr.poolSize(1)).toBe(1);
  });

  it("invalid streamId raises", () => {
    const mgr = new ChainTipManager({
      streams: 2,
      minFee: 100,
      cellSatoshis: 1,
    });
    const tx = buildDummyTx(privKey, [{ satoshis: 500 }]);
    expect(() => mgr.ingest(5, makeUtxo(tx, "f".repeat(64), 0, 500))).toThrow();
    expect(() => mgr.pick(-1, "op")).toThrow();
  });

  it("persist + restore round-trip preserves all fields", () => {
    const chainTipPath = join(tmpDir, "chaintip.json");
    const mgrA = new ChainTipManager({
      streams: 2,
      minFee: 100,
      cellSatoshis: 1,
      chainTipPath,
      chainTipFlushMs: 60_000,
    });
    const tx = buildDummyTx(privKey, [
      { satoshis: 1_000 },
      { satoshis: 2_000 },
    ]);
    mgrA.ingest(0, makeUtxo(tx, "aa".repeat(32), 0, 1_000));
    mgrA.ingest(1, makeUtxo(tx, "bb".repeat(32), 1, 2_000));
    mgrA.persist();
    mgrA.shutdown();

    expect(existsSync(chainTipPath)).toBe(true);
    const raw = readFileSync(chainTipPath, "utf8");
    const parsed = JSON.parse(raw);
    expect(parsed).toHaveLength(2);
    expect(parsed[0]).toHaveLength(1);

    const mgrB = new ChainTipManager({
      streams: 2,
      minFee: 100,
      cellSatoshis: 1,
      chainTipPath,
      chainTipFlushMs: 60_000,
    });
    const { restored } = mgrB.restore((hex) => Transaction.fromHex(hex));
    expect(restored).toBe(2);
    expect(mgrB.poolSize(0)).toBe(1);
    expect(mgrB.poolSize(1)).toBe(1);

    const u = mgrB.pick(0, "restored");
    expect(u.txid).toBe("aa".repeat(32));
    expect(u.satoshis).toBe(1_000);
    expect(u.sourceTx).toBeDefined();

    mgrB.shutdown();
  });

  it("restore rejects stream-count mismatch", () => {
    const chainTipPath = join(tmpDir, "mismatch.json");
    const mgrA = new ChainTipManager({
      streams: 2,
      minFee: 100,
      cellSatoshis: 1,
      chainTipPath,
      chainTipFlushMs: 60_000,
    });
    const tx = buildDummyTx(privKey, [{ satoshis: 500 }]);
    mgrA.ingest(0, makeUtxo(tx, "cc".repeat(32), 0, 500));
    mgrA.persist();
    mgrA.shutdown();

    // Restore with a DIFFERENT stream count — should return 0 and leave pools empty.
    const mgrB = new ChainTipManager({
      streams: 4,
      minFee: 100,
      cellSatoshis: 1,
      chainTipPath,
      chainTipFlushMs: 60_000,
    });
    const { restored } = mgrB.restore((hex) => Transaction.fromHex(hex));
    expect(restored).toBe(0);
    expect(mgrB.totalPoolSize()).toBe(0);
    mgrB.shutdown();
  });

  it("no-ops when chainTipPath is not configured", () => {
    const mgr = new ChainTipManager({
      streams: 1,
      minFee: 100,
      cellSatoshis: 1,
    });
    mgr.persist(); // no throw
    const { restored } = mgr.restore((hex) => Transaction.fromHex(hex));
    expect(restored).toBe(0);
    mgr.shutdown();
  });
});

```
