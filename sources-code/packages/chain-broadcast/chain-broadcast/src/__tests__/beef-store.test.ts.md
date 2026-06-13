---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/chain-broadcast/chain-broadcast/src/__tests__/beef-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.521151+00:00
---

# packages/chain-broadcast/chain-broadcast/src/__tests__/beef-store.test.ts

```ts
/**
 * BeefStore tests — ported from
 * todriguez/hackathon-submission:test/beef-store.test.ts@496ee8f
 *
 * Verifies BEEF envelope persistence: merge, persist, restore, extract
 * UTXOs, atomic-BEEF export, structural validity. No network.
 */

import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync, existsSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PrivateKey, Transaction, P2PKH } from "@bsv/sdk";
import { BeefStore } from "../beef-store.js";

function buildFundingTx(
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

async function buildChildTx(
  privKey: PrivateKey,
  parentTx: Transaction,
  vout: number,
): Promise<Transaction> {
  const p2pkh = new P2PKH();
  const tx = new Transaction();
  tx.addInput({
    sourceTXID: parentTx.id("hex") as string,
    sourceOutputIndex: vout,
    sourceTransaction: parentTx,
    unlockingScriptTemplate: p2pkh.unlock(privKey),
  });
  const satoshis = Number(parentTx.outputs[vout]!.satoshis);
  const fee = 50;
  if (satoshis > fee) {
    tx.addOutput({
      lockingScript: p2pkh.lock(privKey.toPublicKey().toAddress()),
      satoshis: satoshis - fee,
    });
  }
  await tx.sign();
  return tx;
}

describe("BeefStore", () => {
  let tmpDir: string;
  const privKey = PrivateKey.fromRandom();
  const nolog = () => {};

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), "beefstore-test-"));
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it("merges transactions and persists to disk", async () => {
    const beefPath = join(tmpDir, "chain.beef");
    const store = new BeefStore({
      filePath: beefPath,
      flushIntervalMs: 60_000,
      log: nolog,
    });

    const parent = buildFundingTx(privKey, [{ satoshis: 10_000 }]);
    store.mergeTransaction(parent);
    store.persist();

    expect(existsSync(beefPath)).toBe(true);
    expect(statSync(beefPath).size).toBeGreaterThan(10);

    store.shutdown();
  });

  it("restores from disk and validates structure", async () => {
    const beefPath = join(tmpDir, "chain.beef");

    const storeA = new BeefStore({
      filePath: beefPath,
      flushIntervalMs: 60_000,
      log: nolog,
    });
    const parent = buildFundingTx(privKey, [{ satoshis: 10_000 }]);
    const child = await buildChildTx(privKey, parent, 0);
    storeA.mergeTransaction(parent);
    storeA.mergeTransaction(child);
    storeA.persist();
    storeA.shutdown();

    const storeB = new BeefStore({
      filePath: beefPath,
      flushIntervalMs: 60_000,
      log: nolog,
    });
    expect(storeB.restore()).toBe(true);
    expect(storeB.isStructurallyValid()).toBe(true);

    const childTxid = child.id("hex") as string;
    expect(storeB.hasTxid(childTxid)).toBe(true);

    storeB.shutdown();
  });

  it("extractUtxos returns correct outputs", async () => {
    const beefPath = join(tmpDir, "chain.beef");
    const store = new BeefStore({
      filePath: beefPath,
      flushIntervalMs: 60_000,
      log: nolog,
    });

    const parent = buildFundingTx(privKey, [
      { satoshis: 3_000 },
      { satoshis: 4_000 },
      { satoshis: 5_000 },
    ]);
    store.mergeTransaction(parent);

    const parentTxid = parent.id("hex") as string;
    const utxos = store.extractUtxos(parentTxid);

    expect(utxos).toHaveLength(3);
    expect(utxos[0]!.satoshis).toBe(3_000);
    expect(utxos[1]!.satoshis).toBe(4_000);
    expect(utxos[2]!.satoshis).toBe(5_000);
    expect(utxos[0]!.txid).toBe(parentTxid);
    expect(utxos[0]!.vout).toBe(0);
    expect(utxos[0]!.sourceTx).toBeDefined();

    store.shutdown();
  });

  it("extracted UTXOs are spendable (sourceTx is populated)", async () => {
    const beefPath = join(tmpDir, "chain.beef");
    const store = new BeefStore({
      filePath: beefPath,
      flushIntervalMs: 60_000,
      log: nolog,
    });

    const parent = buildFundingTx(privKey, [{ satoshis: 10_000 }]);
    store.mergeTransaction(parent);
    store.persist();
    store.shutdown();

    const store2 = new BeefStore({
      filePath: beefPath,
      flushIntervalMs: 60_000,
      log: nolog,
    });
    store2.restore();

    const parentTxid = parent.id("hex") as string;
    const utxos = store2.extractUtxos(parentTxid);
    expect(utxos).toHaveLength(1);

    const child = await buildChildTx(privKey, utxos[0]!.sourceTx, 0);
    const childTxid = child.id("hex") as string;
    expect(childTxid).toHaveLength(64);

    store2.shutdown();
  });

  it("restore returns false for missing file", () => {
    const store = new BeefStore({
      filePath: join(tmpDir, "nonexistent.beef"),
      flushIntervalMs: 60_000,
      log: nolog,
    });
    expect(store.restore()).toBe(false);
    store.shutdown();
  });

  it("restore returns false for corrupt file", () => {
    const beefPath = join(tmpDir, "corrupt.beef");
    writeFileSync(beefPath, Buffer.from([0xde, 0xad, 0xbe, 0xef]));

    const store = new BeefStore({
      filePath: beefPath,
      flushIntervalMs: 60_000,
      log: nolog,
    });
    expect(store.restore()).toBe(false);
    store.shutdown();
  });

  it("BEEF file for 200-UTXO chain is under 100KB", async () => {
    const beefPath = join(tmpDir, "big-chain.beef");
    const store = new BeefStore({
      filePath: beefPath,
      flushIntervalMs: 60_000,
      log: nolog,
    });

    const parent = buildFundingTx(
      privKey,
      Array.from({ length: 200 }, () => ({ satoshis: 500 })),
    );
    store.mergeTransaction(parent);

    for (let i = 0; i < 200; i++) {
      const child = await buildChildTx(privKey, parent, i);
      store.mergeTransaction(child);
    }
    store.persist();

    expect(statSync(beefPath).size).toBeLessThan(100 * 1024);
    store.shutdown();
  });

  it("getStats returns correct counts", async () => {
    const beefPath = join(tmpDir, "stats.beef");
    const store = new BeefStore({
      filePath: beefPath,
      flushIntervalMs: 60_000,
      log: nolog,
    });

    const parent = buildFundingTx(privKey, [{ satoshis: 5_000 }]);
    const child = await buildChildTx(privKey, parent, 0);
    store.mergeTransaction(parent);
    store.mergeTransaction(child);

    const stats = store.getStats();
    expect(stats.txCount).toBe(2);
    expect(stats.valid).toBe(true);

    store.persist();
    const after = store.getStats();
    expect(after.fileSize).toBeGreaterThan(0);

    store.shutdown();
  });

  it("getAtomicBEEF produces valid atomic envelope for a txid", async () => {
    const beefPath = join(tmpDir, "atomic.beef");
    const store = new BeefStore({
      filePath: beefPath,
      flushIntervalMs: 60_000,
      log: nolog,
    });

    const parent = buildFundingTx(privKey, [
      { satoshis: 10_000 },
      { satoshis: 10_000 },
    ]);
    const child1 = await buildChildTx(privKey, parent, 0);
    const child2 = await buildChildTx(privKey, parent, 1);

    store.mergeTransaction(parent);
    store.mergeTransaction(child1);
    store.mergeTransaction(child2);

    const child1Txid = child1.id("hex") as string;
    const atomic = store.getAtomicBEEF(child1Txid);

    // AtomicBEEF magic: 0x01010101 little-endian at offset 0
    const prefix =
      ((atomic[0]! |
        (atomic[1]! << 8) |
        (atomic[2]! << 16) |
        (atomic[3]! << 24)) >>>
        0);
    expect(prefix).toBe(0x01010101);
    expect(atomic.length).toBeGreaterThan(10);

    store.shutdown();
  });
});

```
