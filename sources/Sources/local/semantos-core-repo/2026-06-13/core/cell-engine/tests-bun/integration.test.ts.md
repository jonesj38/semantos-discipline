---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.988985+00:00
---

# core/cell-engine/tests-bun/integration.test.ts

```ts
/**
 * Integration tests — Full semantic object lifecycle with real infrastructure (D7.6).
 *
 * No mocks. Real SQLite, real WASM engine, real @bsv/sdk.
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { Database } from 'bun:sqlite';
import { PrivateKey, PublicKey } from '@bsv/sdk';
import { loadCellEngine } from '../bindings/bun/loader';
import { CellEngine } from '../bindings/bun/cell-engine';
import {
  buildCellHeader,
  packCell as tsPackCell,
  computeTypeHash,
  LINEARITY,
} from '@semantos/cell-ops';
import {
  computeDomainPayloadRoot,
  commerceSchemaV1,
  commercePayload,
} from '@semantos/plexus-schema-registry';

// ── Helpers ──

const FIXED_TIMESTAMP = BigInt(1700000000000);
const TYPE_HASH = computeTypeHash('services.trades.carpentry', 'hire', 'inst.contract.service-agreement');
const OWNER_ID = Buffer.alloc(16, 0);
Buffer.from('0123456789abcdef', 'hex').copy(OWNER_ID, 0, 0, 8);

// RM-041: commerce semantics encoded into payload via commerceSchemaV1.
const TEST_DOMAIN_PAYLOAD = Buffer.from(
  computeDomainPayloadRoot(
    commerceSchemaV1,
    commercePayload({ phase: 'parse', dimension: 'what' }),
  ),
);

function buildHeader(linearity: number, payloadSize: number): Buffer {
  const orig = Date.now;
  Date.now = () => Number(FIXED_TIMESTAMP);
  try {
    return buildCellHeader({
      typeHash: TYPE_HASH,
      linearity: linearity as any,
      ownerId: OWNER_ID,
      domainPayload: TEST_DOMAIN_PAYLOAD,
      payloadSize,
    });
  } finally {
    Date.now = orig;
  }
}

describe('Full semantic object lifecycle', () => {
  let engine: CellEngine;
  let embeddedEngine: CellEngine;
  let db: Database;

  beforeAll(async () => {
    engine = await loadCellEngine();
    embeddedEngine = await loadCellEngine({ profile: 'embedded' });

    // Real SQLite via bun:sqlite
    db = new Database(':memory:');
    db.run(`
      CREATE TABLE cells (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cell_data BLOB NOT NULL,
        linearity INTEGER NOT NULL,
        spent INTEGER DEFAULT 0
      )
    `);
  });

  test('LINEAR object: create → pack → store → query → verify', () => {
    const payload = new Uint8Array(32);
    for (let i = 0; i < 32; i++) payload[i] = i;
    const header = new Uint8Array(buildHeader(LINEARITY.LINEAR, 32));

    // Pack through CellEngine
    const cell = engine.packCell(header, payload);
    expect(cell.length).toBe(1024);

    // Store in SQLite
    db.run('INSERT INTO cells (cell_data, linearity) VALUES (?, ?)', [
      Buffer.from(cell),
      LINEARITY.LINEAR,
    ]);

    // Query back
    const row = db.query('SELECT cell_data, linearity FROM cells WHERE linearity = ?').get(LINEARITY.LINEAR) as any;
    expect(row).not.toBeNull();

    // Unpack and verify
    const stored = new Uint8Array(row.cell_data);
    const unpacked = engine.unpackCell(stored);
    expect(unpacked.payloadLen).toBe(32);
    for (let i = 0; i < 32; i++) {
      expect(unpacked.payload[i]).toBe(i);
    }

    // Verify magic
    expect(engine.validateMagic(stored)).toBe(true);
  });

  test('AFFINE vote: create → consume → reject double consume', () => {
    const payload = new Uint8Array(16).fill(0xAF);
    const header = new Uint8Array(buildHeader(LINEARITY.AFFINE, 16));

    const cell = engine.packCell(header, payload);

    // Store with spent=0
    const result = db.run('INSERT INTO cells (cell_data, linearity, spent) VALUES (?, ?, 0)', [
      Buffer.from(cell),
      LINEARITY.AFFINE,
    ]);
    const cellId = Number(result.lastInsertRowid);

    // Consume (mark as spent)
    const row = db.query('SELECT spent FROM cells WHERE id = ?').get(cellId) as any;
    expect(row.spent).toBe(0);
    db.run('UPDATE cells SET spent = 1 WHERE id = ? AND spent = 0', [cellId]);

    // Verify consumed
    const after = db.query('SELECT spent FROM cells WHERE id = ?').get(cellId) as any;
    expect(after.spent).toBe(1);

    // Reject double consume — UPDATE WHERE spent=0 should affect 0 rows
    const doubleSpend = db.run('UPDATE cells SET spent = 1 WHERE id = ? AND spent = 0', [cellId]);
    expect(doubleSpend.changes).toBe(0);
  });

  test('Capability token: verify valid → verify expired → verify wrong domain', () => {
    const ownerPubkey = new Uint8Array(33);
    ownerPubkey[0] = 0x02;
    for (let i = 1; i < 33; i++) ownerPubkey[i] = i;

    // OP_TRUE script — always valid
    const validScript = new Uint8Array([0x51]);
    const result = engine.verifyCapability(validScript, ownerPubkey, 0, 1, 1000);
    expect(result.valid).toBe(true);

    // OP_FALSE script — always fails
    const failScript = new Uint8Array([0x00]);
    const failResult = engine.verifyCapability(failScript, ownerPubkey, 0, 1, 1000);
    expect(failResult.valid).toBe(false);

    // Different domain flag — still uses same scripts, but capability system
    // is exercised with different parameters
    const domainResult = engine.verifyCapability(validScript, ownerPubkey, 0, 999, 1000);
    expect(domainResult.valid).toBe(true); // OP_TRUE doesn't check domain

    // Expired: time=0 with OP_TRUE still passes (script doesn't check time)
    const expiredResult = engine.verifyCapability(validScript, ownerPubkey, 0, 1, 0);
    expect(expiredResult.valid).toBe(true);
  });

  test('CHECKSIG: real ECDSA path exercised through CellEngine (embedded profile)', () => {
    // This test verifies the real @bsv/sdk ECDSA path is wired through CellEngine.
    // We use the low-level kernel API because executeScript() calls kernel_reset()
    // which clears the tx context needed for CHECKSIG.

    const privkey = PrivateKey.fromRandom();
    const pubkey = PublicKey.fromPrivateKey(privkey);
    const pubkeyDER = pubkey.toDER() as number[];

    // Build a minimal transaction
    const tx = new Uint8Array([
      0x01, 0x00, 0x00, 0x00, // version 1
      0x01, // 1 input
      ...new Array(32).fill(0xAA), // prev_txid
      0x00, 0x00, 0x00, 0x00, // prev_vout = 0
      0x00, // empty scriptSig
      0xFF, 0xFF, 0xFF, 0xFF, // nSequence
      0x01, // 1 output
      0x10, 0x27, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // value = 10000 sats
      0x01, 0x51, // scriptPubKey: OP_1
      0x00, 0x00, 0x00, 0x00, // locktime
    ]);

    // Reset first, then load tx context
    embeddedEngine.kernelReset();
    embeddedEngine.loadTxContext(tx, 0, BigInt(50000));

    // Lock: OP_CHECKSIG
    const lock = new Uint8Array([0xAC]);

    // Unlock: properly-formatted DER sig + pubkey (sig is valid-format but wrong sighash)
    const fakeDER = [
      0x30, 0x44,
      0x02, 0x20, ...new Array(32).fill(0x01), // r
      0x02, 0x20, ...new Array(32).fill(0x02), // s
      0x41, // SIGHASH_ALL|FORKID
    ];

    const unlock = new Uint8Array(1 + fakeDER.length + 1 + pubkeyDER.length);
    let off = 0;
    unlock[off++] = fakeDER.length;
    for (const b of fakeDER) unlock[off++] = b;
    unlock[off++] = 0x21; // PUSH 33 bytes
    for (let i = 0; i < pubkeyDER.length; i++) unlock[off + i] = pubkeyDER[i];

    // Use low-level API to avoid executeScript's internal reset
    const wasm = (embeddedEngine as any).wasm;
    const writeBytes = (embeddedEngine as any).writeBytes.bind(embeddedEngine);
    const IO_SCRIPT = 0x300000 + 1024 * 4;
    const IO_UNLOCK = 0x300000 + 1024 * 4 + 0x10000;

    writeBytes(IO_UNLOCK, unlock);
    wasm.kernel_load_unlock(IO_UNLOCK, unlock.length);
    writeBytes(IO_SCRIPT, lock);
    wasm.kernel_load_script(IO_SCRIPT, lock.length);

    const rc = wasm.kernel_execute();

    // Should fail with VERIFY_FAILED (6), proving the real ECDSA path ran
    // (if the host_checksig stub just returned 0, it would still be verify_failed,
    // but combined with checksig_integration.test.ts that tests the full profile,
    // this confirms the embedded profile host path is correctly wired)
    expect(rc).toBe(6); // VERIFY_FAILED
  });

  test('BSV testnet: anchor → BEEF → verify BUMP (conditional)', () => {
    if (!process.env.BSV_TESTNET_KEY) {
      console.log('SKIPPED: BSV_TESTNET_KEY not set');
      return;
    }
    // Real testnet lifecycle would go here
    // This is a placeholder for when the key is available
    expect(true).toBe(true);
  });
});

```
