---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/transition-validator.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.563262+00:00
---

# tests/gates/transition-validator.test.ts

```ts
/**
 * TransitionValidator tests — 2PDA ↔ CellToken bridge.
 *
 * Validates that the TransitionValidator correctly gates state transitions
 * through the linearity enforcement engine before on-chain operations.
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { loadCellEngine } from '../../core/cell-engine/bindings/bun/loader';
import type { CellEngine } from '../../core/cell-engine/bindings/bun/cell-engine';
import { TransitionValidator } from '../../core/protocol-types/src/transition-validator';
import { CellStore } from '../../core/protocol-types/src/cell-store';
import { MemoryAdapter } from '../../core/protocol-types/src/adapters/memory-adapter';
import { deserializeCellHeader, serializeCellHeader } from '../../core/protocol-types/src/cell-header';
import { Linearity, CELL_SIZE, HEADER_SIZE } from '../../core/protocol-types/src/constants';
import { createHash } from 'crypto';

// We need a PublicKey for the CellToken scripts. Use a deterministic one.
let PublicKey: any;
let ownerPubKey: any;

function sha256Bytes(data: Uint8Array): Uint8Array {
  return new Uint8Array(createHash('sha256').update(data).digest());
}

describe('TransitionValidator — 2PDA linearity gate', () => {
  let engine: CellEngine;
  let validator: TransitionValidator;

  // Shared cell data
  let v1Cell: Uint8Array;
  let v2Cell: Uint8Array;
  let v1ContentHash: Uint8Array;
  let v2ContentHash: Uint8Array;
  const semanticPath = 'objects/create/job/test-1';

  beforeAll(async () => {
    // Load CellEngine WASM
    engine = await loadCellEngine({ profile: 'full' });
    validator = new TransitionValidator(engine, { debug: false });

    // Import PublicKey from @bsv/sdk
    const sdk = await import('@bsv/sdk');
    PublicKey = sdk.PublicKey;

    // Use a fixed public key for deterministic tests
    // (compressed, 33 bytes — standard secp256k1 point)
    const { PrivateKey } = sdk;
    const privKey = PrivateKey.fromRandom();
    ownerPubKey = privKey.toPublicKey();

    // Build v1 cell (status: open)
    const storage1 = new MemoryAdapter();
    const store1 = new CellStore(storage1);
    const v1Data = new TextEncoder().encode(JSON.stringify({
      type: 'job', title: 'Test job', status: 'open',
    }));
    const v1Ref = await store1.put(semanticPath, v1Data, { linearity: Linearity.LINEAR });
    v1Cell = (await storage1.read(semanticPath))!;
    v1ContentHash = hexToBytes(v1Ref.contentHash);

    // Build v2 cell (status: in_progress)
    const storage2 = new MemoryAdapter();
    const store2 = new CellStore(storage2);
    const v2Data = new TextEncoder().encode(JSON.stringify({
      type: 'job', title: 'Test job', status: 'in_progress',
    }));
    const v2Ref = await store2.put(semanticPath, v2Data, { linearity: Linearity.LINEAR });
    v2Cell = (await storage2.read(semanticPath))!;
    v2ContentHash = hexToBytes(v2Ref.contentHash);

    // CellStore always writes version=1. For a valid transition, v2 must
    // have a strictly higher version. Patch the header in-place.
    const v2Dv = new DataView(v2Cell.buffer, v2Cell.byteOffset, v2Cell.byteLength);
    v2Dv.setUint32(20, 2, true);  // offset 20 = version, set to 2

    // v2 must bind to v1 via commercePrevState = sha256(v1Cell). Since both
    // cells were built against separate MemoryAdapters, CellStore wrote zeros
    // into the prev-state slot. Patch it here so the hash-chain continuity
    // check in TransitionValidator.validate() passes for the happy path.
    const prevHash = sha256Bytes(v1Cell);
    v2Cell.set(prevHash, 128);  // offset 128 = commercePrevState, 32 bytes
  });

  // ── Happy path ──

  test('valid LINEAR transition passes all checks', () => {
    const result = validator.validate({
      v1CellBytes: v1Cell,
      v2CellBytes: v2Cell,
      semanticPath,
      v1ContentHash,
      v2ContentHash,
      ownerPubKey,
    });

    expect(result.valid).toBe(true);
    expect(result.v1Linearity).toBe(Linearity.LINEAR);
    expect(result.typeHashContinuity).toBe(true);
    expect(result.scriptValid).toBe(true);
    expect(result.opcodeCount).toBeGreaterThan(0);
  });

  // ── Cell size validation ──

  test('rejects v1 cell with wrong size', () => {
    const badCell = new Uint8Array(512);
    const result = validator.validate({
      v1CellBytes: badCell,
      v2CellBytes: v2Cell,
      semanticPath,
      v1ContentHash,
      v2ContentHash,
      ownerPubKey,
    });

    expect(result.valid).toBe(false);
    expect(result.reason).toContain('512 bytes');
  });

  test('rejects v2 cell with wrong size', () => {
    const badCell = new Uint8Array(2048);
    const result = validator.validate({
      v1CellBytes: v1Cell,
      v2CellBytes: badCell,
      semanticPath,
      v1ContentHash,
      v2ContentHash,
      ownerPubKey,
    });

    expect(result.valid).toBe(false);
    expect(result.reason).toContain('2048 bytes');
  });

  // ── Magic byte validation ──

  test('rejects cell with invalid magic bytes', () => {
    const badCell = new Uint8Array(CELL_SIZE);
    badCell.set(v1Cell);
    // Corrupt first magic word (LE u32 at offset 0)
    const dv = new DataView(badCell.buffer);
    dv.setUint32(0, 0x00000000, true);

    const result = validator.validate({
      v1CellBytes: badCell,
      v2CellBytes: v2Cell,
      semanticPath,
      v1ContentHash,
      v2ContentHash,
      ownerPubKey,
    });

    expect(result.valid).toBe(false);
    expect(result.reason).toContain('magic');
  });

  // ── Linearity preservation ──

  test('rejects transition that changes linearity type', () => {
    // Modify v2 to have AFFINE linearity instead of LINEAR
    const modifiedV2 = new Uint8Array(CELL_SIZE);
    modifiedV2.set(v2Cell);

    const dv = new DataView(modifiedV2.buffer);
    dv.setUint32(16, Linearity.AFFINE, true); // offset 16 = linearity

    const result = validator.validate({
      v1CellBytes: v1Cell,
      v2CellBytes: modifiedV2,
      semanticPath,
      v1ContentHash,
      v2ContentHash,
      ownerPubKey,
    });

    expect(result.valid).toBe(false);
    expect(result.reason).toContain('Linearity mismatch');
    expect(result.reason).toContain('LINEAR');
    expect(result.reason).toContain('AFFINE');
  });

  // ── Type-hash continuity ──

  test('rejects transition that changes type hash', () => {
    // Modify v2 type hash to be different
    const modifiedV2 = new Uint8Array(CELL_SIZE);
    modifiedV2.set(v2Cell);

    // Type hash is at offset 30, 32 bytes
    for (let i = 0; i < 32; i++) {
      modifiedV2[30 + i] = 0xFF;
    }

    const result = validator.validate({
      v1CellBytes: v1Cell,
      v2CellBytes: modifiedV2,
      semanticPath,
      v1ContentHash,
      v2ContentHash,
      ownerPubKey,
    });

    expect(result.valid).toBe(false);
    expect(result.reason).toContain('Type-hash mismatch');
  });

  // ── Owner-ID continuity ──

  test('rejects transition that changes owner ID', () => {
    const modifiedV2 = new Uint8Array(CELL_SIZE);
    modifiedV2.set(v2Cell);

    // Owner ID is at offset 62, 16 bytes
    for (let i = 0; i < 16; i++) {
      modifiedV2[62 + i] = 0xAA;
    }

    const result = validator.validate({
      v1CellBytes: v1Cell,
      v2CellBytes: modifiedV2,
      semanticPath,
      v1ContentHash,
      v2ContentHash,
      ownerPubKey,
    });

    expect(result.valid).toBe(false);
    expect(result.reason).toContain('Owner-ID mismatch');
  });

  // ── Version monotonicity ──

  test('rejects transition with non-monotonic version', () => {
    // Build v2 with same version as v1 (should be strictly greater)
    const v1Header = deserializeCellHeader(v1Cell);
    const modifiedV2 = new Uint8Array(CELL_SIZE);
    modifiedV2.set(v2Cell);

    const dv = new DataView(modifiedV2.buffer);
    dv.setUint32(20, v1Header.version, true); // offset 20 = version, set equal to v1

    const result = validator.validate({
      v1CellBytes: v1Cell,
      v2CellBytes: modifiedV2,
      semanticPath,
      v1ContentHash,
      v2ContentHash,
      ownerPubKey,
    });

    expect(result.valid).toBe(false);
    expect(result.reason).toContain('Version not monotonic');
  });

  // ── Utility methods ──

  test('requiresTransition returns true for LINEAR cells', () => {
    expect(validator.requiresTransition(v1Cell)).toBe(true);
  });

  test('requiresTransition returns false for AFFINE cells', async () => {
    const storage = new MemoryAdapter();
    const store = new CellStore(storage);
    const data = new TextEncoder().encode('affine test');
    await store.put('test/affine', data, { linearity: Linearity.AFFINE });
    const cell = (await storage.read('test/affine'))!;

    expect(validator.requiresTransition(cell)).toBe(false);
  });

  test('validateCell passes for well-formed cell', () => {
    const result = validator.validateCell(v1Cell);
    expect(result.valid).toBe(true);
    expect(result.linearity).toBe(Linearity.LINEAR);
  });

  test('validateCell fails for garbage bytes', () => {
    const garbage = new Uint8Array(CELL_SIZE);
    const result = validator.validateCell(garbage);
    expect(result.valid).toBe(false);
  });

  // ── AFFINE transitions ──

  test('valid AFFINE transition passes', async () => {
    const storage1 = new MemoryAdapter();
    const store1 = new CellStore(storage1);
    const data1 = new TextEncoder().encode(JSON.stringify({ type: 'note', text: 'v1' }));
    const ref1 = await store1.put('test/affine-trans', data1, { linearity: Linearity.AFFINE });
    const cell1 = (await storage1.read('test/affine-trans'))!;

    const storage2 = new MemoryAdapter();
    const store2 = new CellStore(storage2);
    const data2 = new TextEncoder().encode(JSON.stringify({ type: 'note', text: 'v2' }));
    const ref2 = await store2.put('test/affine-trans', data2, { linearity: Linearity.AFFINE });
    const cell2 = (await storage2.read('test/affine-trans'))!;

    // Bump v2 version for monotonicity
    const affineDv = new DataView(cell2.buffer, cell2.byteOffset, cell2.byteLength);
    affineDv.setUint32(20, 2, true);

    // Bind v2 to v1 via sha256(v1) in the prev-state-hash slot.
    cell2.set(sha256Bytes(cell1), 128);

    const result = validator.validate({
      v1CellBytes: cell1,
      v2CellBytes: cell2,
      semanticPath: 'test/affine-trans',
      v1ContentHash: hexToBytes(ref1.contentHash),
      v2ContentHash: hexToBytes(ref2.contentHash),
      ownerPubKey,
    });

    expect(result.valid).toBe(true);
    expect(result.v1Linearity).toBe(Linearity.AFFINE);
  });

  // ── Prev-state-hash binding (K6) ──

  test('rejects transition with corrupted prev-state-hash', () => {
    // Clobber v2.commercePrevState with 0xAA bytes — simulates a break-prev-hash
    // tamper where a successor cell is spliced in without correctly binding to
    // its predecessor. Must be detected before the on-chain operation.
    const modifiedV2 = new Uint8Array(CELL_SIZE);
    modifiedV2.set(v2Cell);
    for (let i = 0; i < 32; i++) {
      modifiedV2[128 + i] = 0xAA;
    }

    const result = validator.validate({
      v1CellBytes: v1Cell,
      v2CellBytes: modifiedV2,
      semanticPath,
      v1ContentHash,
      v2ContentHash,
      ownerPubKey,
    });

    expect(result.valid).toBe(false);
    expect(result.reason).toContain('Prev-state-hash mismatch');
  });

  test('rejects transition with zero prev-state-hash', () => {
    // A successor cell with a zero prev-state-hash is never valid — that's
    // the genesis convention, and genesis cells cannot be transitioned.
    const modifiedV2 = new Uint8Array(CELL_SIZE);
    modifiedV2.set(v2Cell);
    for (let i = 0; i < 32; i++) {
      modifiedV2[128 + i] = 0x00;
    }

    const result = validator.validate({
      v1CellBytes: v1Cell,
      v2CellBytes: modifiedV2,
      semanticPath,
      v1ContentHash,
      v2ContentHash,
      ownerPubKey,
    });

    expect(result.valid).toBe(false);
    expect(result.reason).toContain('zero');
  });
});

// ── Helpers ──

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

```
