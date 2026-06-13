---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/checksig-real.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.986157+00:00
---

# core/cell-engine/tests-bun/checksig-real.test.ts

```ts
/**
 * D7.5.4: Real CHECKSIG integration test.
 *
 * Verifies end-to-end P2PKH signature verification through the CellEngine
 * WASM pipeline using a programmatically-signed test vector.
 *
 * Uses the embedded profile so CHECKSIG goes through:
 *   sighash.zig (BIP-143 preimage) → host_hash256 → host_checksig → @bsv/sdk ECDSA
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { loadCellEngine } from '../bindings/bun/loader';
import type { CellEngine } from '../bindings/bun/cell-engine';

interface ChecksigVector {
  lockingScript: string;
  unlockingScript: string;
  rawSpendingTx: string;
  prevoutValue: number;
  sequence: number;
  locktime: number;
  txVersion: number;
  sighash: string;
  signature: string;
  hashtypeByte: number;
  publicKey: string;
  expectedResult: boolean;
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

const vectorPath = join(import.meta.dir, '..', 'test-vectors', 'checksig-p2pkh.json');
const vector: ChecksigVector = JSON.parse(readFileSync(vectorPath, 'utf-8'));

describe('D7.5.4: Real P2PKH CHECKSIG through CellEngine', () => {
  let engine: CellEngine;

  beforeAll(async () => {
    // Use embedded profile: crypto delegated to host_checksig → @bsv/sdk
    engine = await loadCellEngine({ profile: 'embedded' });
  });

  test('CHECKSIG verifies a real P2PKH signature end-to-end', () => {
    engine.kernelReset();

    // Load the raw spending transaction as tx context
    const rawTx = hexToBytes(vector.rawSpendingTx);
    engine.loadTxContext(rawTx, 0, BigInt(vector.prevoutValue));

    // Load unlock and lock scripts via low-level API
    // (executeScript() calls kernel_reset which clears tx context)
    const wasm = (engine as any).wasm;
    const writeBytes = (engine as any).writeBytes.bind(engine);
    const IO_SCRIPT = 0x300000 + 0x1000;
    const IO_UNLOCK = 0x300000 + 0x11000;

    const lockScript = hexToBytes(vector.lockingScript);
    const unlockScript = hexToBytes(vector.unlockingScript);

    writeBytes(IO_UNLOCK, unlockScript);
    wasm.kernel_load_unlock(IO_UNLOCK, unlockScript.length);
    writeBytes(IO_SCRIPT, lockScript);
    wasm.kernel_load_script(IO_SCRIPT, lockScript.length);

    const rc = wasm.kernel_execute();

    // This is the real test: a valid ECDSA signature through the full pipeline
    expect(rc).toBe(0); // SUCCESS
  });

  test('CHECKSIG rejects a flipped signature byte (negative test)', () => {
    engine.kernelReset();

    const rawTx = hexToBytes(vector.rawSpendingTx);
    engine.loadTxContext(rawTx, 0, BigInt(vector.prevoutValue));

    const wasm = (engine as any).wasm;
    const writeBytes = (engine as any).writeBytes.bind(engine);
    const IO_SCRIPT = 0x300000 + 0x1000;
    const IO_UNLOCK = 0x300000 + 0x11000;

    const lockScript = hexToBytes(vector.lockingScript);
    const unlockScript = hexToBytes(vector.unlockingScript);

    // Flip one byte in the DER signature (byte 5 — inside r value)
    const badUnlock = new Uint8Array(unlockScript);
    badUnlock[5] ^= 0xFF;

    writeBytes(IO_UNLOCK, badUnlock);
    wasm.kernel_load_unlock(IO_UNLOCK, badUnlock.length);
    writeBytes(IO_SCRIPT, lockScript);
    wasm.kernel_load_script(IO_SCRIPT, lockScript.length);

    const rc = wasm.kernel_execute();

    // Should fail: signature is invalid
    expect(rc).toBe(6); // VERIFY_FAILED
  });
});

```
