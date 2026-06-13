---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/cell-engine.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.990147+00:00
---

# core/cell-engine/tests-bun/cell-engine.test.ts

```ts
/**
 * CellEngine typed API tests (D7.3 — Tier A + Tier B).
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { loadCellEngine } from '../bindings/bun/loader';
import { CellEngine } from '../bindings/bun/cell-engine';
import { createOctaveCellStore, seedCellInStore, type OctaveCellStore } from '../bindings/host-functions';
import {
  buildCellHeader,
  packCell as tsPackCell,
  unpackCell as tsUnpackCell,
  computeTypeHash,
  LINEARITY,
} from '@semantos/cell-ops';
import {
  computeDomainPayloadRoot,
  commerceSchemaV1,
  commercePayload,
} from '@semantos/plexus-schema-registry';

// ── Test data ──
const FIXED_TIMESTAMP = BigInt(1700000000000);
const TYPE_HASH = computeTypeHash(
  'services.trades.carpentry',
  'hire',
  'inst.contract.service-agreement',
);
const OWNER_ID = Buffer.alloc(16, 0);
Buffer.from('0123456789abcdef', 'hex').copy(OWNER_ID, 0, 0, 8);

// RM-041: commerce phase/dimension move into payload via
// commerceSchemaV1. Test cells encode (parse, what) once and reuse the
// root for every cell built by this helper.
const TEST_DOMAIN_PAYLOAD = Buffer.from(
  computeDomainPayloadRoot(
    commerceSchemaV1,
    commercePayload({ phase: 'parse', dimension: 'what' }),
  ),
);

function buildHeader(linearity: number, payloadSize: number): Buffer {
  const origDateNow = Date.now;
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
    Date.now = origDateNow;
  }
}

// ── Tier A Tests ──

describe('CellEngine Tier A — Typed API', () => {
  let engine: CellEngine;

  beforeAll(async () => {
    engine = await loadCellEngine();
  });

  test('packCell → unpackCell round-trip matches', () => {
    const payload = new Uint8Array(32);
    for (let i = 0; i < 32; i++) payload[i] = i;
    const header = new Uint8Array(buildHeader(LINEARITY.LINEAR, 32));

    const cell = engine.packCell(header, payload);
    expect(cell.length).toBe(1024);

    const unpacked = engine.unpackCell(cell);
    expect(unpacked.header.length).toBe(256);
    expect(unpacked.payloadLen).toBe(32);
    // First 32 bytes of payload should match
    for (let i = 0; i < 32; i++) {
      expect(unpacked.payload[i]).toBe(i);
    }
  });

  test('validateMagic returns true for valid cell', () => {
    const header = new Uint8Array(buildHeader(LINEARITY.LINEAR, 16));
    const payload = new Uint8Array(16);
    const cell = engine.packCell(header, payload);
    expect(engine.validateMagic(cell)).toBe(true);
  });

  test('validateMagic returns false for garbage', () => {
    const garbage = new Uint8Array(1024);
    expect(engine.validateMagic(garbage)).toBe(false);
  });

  test('deriveBCA returns typed BCAOutput', () => {
    const pubkey = new Uint8Array(33);
    pubkey[0] = 0x02; // compressed pubkey prefix
    for (let i = 1; i < 33; i++) pubkey[i] = i;

    const result = engine.deriveBCA({
      publicKey: pubkey,
      subnetPrefix: new Uint8Array(8),
      modifier: new Uint8Array(16),
    });

    expect(result.ipv6Address).toBeInstanceOf(Uint8Array);
    expect(result.ipv6Address.length).toBe(16);
    expect(typeof result.collisionCount).toBe('number');
  });

  test('verifyBCA round-trips with deriveBCA', () => {
    const pubkey = new Uint8Array(33);
    pubkey[0] = 0x02;
    for (let i = 1; i < 33; i++) pubkey[i] = i;
    const prefix = new Uint8Array(8);
    const modifier = new Uint8Array(16);

    const derived = engine.deriveBCA({ publicKey: pubkey, subnetPrefix: prefix, modifier });
    const valid = engine.verifyBCA(derived.ipv6Address, { publicKey: pubkey, subnetPrefix: prefix, modifier });
    expect(valid).toBe(true);
  });

  test('executeScript with OP_TRUE returns success', () => {
    const script = new Uint8Array([0x51]); // OP_1 (OP_TRUE)
    const result = engine.executeScript(script);
    expect(result.success).toBe(true);
    expect(result.error).toBeNull();
  });

  test('executeScript with OP_1 OP_1 OP_ADD → stackPeek returns [2]', () => {
    const script = new Uint8Array([0x51, 0x51, 0x93]); // OP_1 OP_1 OP_ADD
    const result = engine.executeScript(script);
    expect(result.success).toBe(true);

    const depth = engine.stackDepth();
    expect(depth).toBe(1);

    const top = engine.stackPeek(0);
    expect(top).not.toBeNull();
    // Stack value should start with [2] (the result of 1+1)
    expect(top![0]).toBe(2);
  });

  test('executeScript with OP_0 returns failure', () => {
    const script = new Uint8Array([0x00]); // OP_0 (OP_FALSE)
    const result = engine.executeScript(script);
    expect(result.success).toBe(false);
  });

  test('step() advances PC correctly', () => {
    // Load a script manually via executeScript won't work for stepping.
    // Use kernel_reset + kernel_load_script + step sequence.
    engine.kernelReset();

    // We need to load a script via the low-level interface first,
    // then step through it. Let's use executeScript's internal pattern.
    const script = new Uint8Array([0x51, 0x51, 0x93]); // OP_1 OP_1 OP_ADD

    // Access raw WASM for script loading
    const wasm = (engine as any).wasm;
    const writeBytes = (engine as any).writeBytes.bind(engine);
    const IO_SCRIPT = 0x300000 + 1024 * 4;

    writeBytes(IO_SCRIPT, script);
    wasm.kernel_load_script(IO_SCRIPT, script.length);

    const step1 = engine.step();
    expect(step1.status).toBe(0); // success, more to execute
    expect(step1.pc).toBeGreaterThan(0);
  });

  test('verifyBEEF on embedded profile throws', async () => {
    const embedded = await loadCellEngine({ profile: 'embedded' });
    expect(() =>
      embedded.verifyBEEF(new Uint8Array(10), new Uint8Array(32))
    ).toThrow('SPV not available in embedded profile');
  });

  test('verifyCapability with OP_TRUE script returns valid', () => {
    const lockScript = new Uint8Array([0x51]); // OP_TRUE
    const ownerPubkey = new Uint8Array(33);
    ownerPubkey[0] = 0x02;
    const result = engine.verifyCapability(lockScript, ownerPubkey, 0, 1, 1000);
    expect(result.valid).toBe(true);
    expect(result.errorCode).toBe(0);
  });

  test('verifyCapability with OP_FALSE script returns invalid', () => {
    const lockScript = new Uint8Array([0x00]); // OP_FALSE
    const ownerPubkey = new Uint8Array(33);
    ownerPubkey[0] = 0x02;
    const result = engine.verifyCapability(lockScript, ownerPubkey, 0, 1, 1000);
    expect(result.valid).toBe(false);
  });

  test('checkLinearity returns type classification', () => {
    // After running a script, checkLinearity reports the type class
    engine.executeScript(new Uint8Array([0x51]));
    const tc = engine.checkLinearity();
    expect(typeof tc).toBe('number');
  });

  test('setEnforcement toggles without error', () => {
    expect(() => engine.setEnforcement(true)).not.toThrow();
    expect(() => engine.setEnforcement(false)).not.toThrow();
  });

  test('kernelReset clears state', () => {
    engine.executeScript(new Uint8Array([0x51, 0x51])); // OP_1 OP_1
    expect(engine.stackDepth()).toBe(2);
    engine.kernelReset();
    expect(engine.stackDepth()).toBe(0);
  });
});

// ── Tier B Tests — Octave ──

describe('CellEngine Tier B — Octave', () => {
  let engine: CellEngine;
  let cellStore: OctaveCellStore;

  beforeAll(async () => {
    cellStore = createOctaveCellStore();
    engine = await loadCellEngine({ cellStore });
  });

  test('createPointerCell → isPointerCell returns true', () => {
    const cell = engine.createPointerCell({
      octave: 1,
      slot: 7,
      offset: 0,
      contentHash: new Uint8Array(32),
      typeHash: new Uint8Array(32),
      totalSize: BigInt(1024),
      flags: 0,
      fragmentCount: 1,
    });
    expect(cell.length).toBe(1024);
    expect(engine.isPointerCell(cell)).toBe(true);
  });

  test('createPointerCell → parsePointerCell round-trips', () => {
    const payload = {
      octave: 2,
      slot: 42,
      offset: 3,
      contentHash: new Uint8Array(32).fill(0xAB),
      typeHash: new Uint8Array(32).fill(0xCD),
      totalSize: BigInt(4096),
      flags: 5,
      fragmentCount: 4,
    };
    const cell = engine.createPointerCell(payload);
    const parsed = engine.parsePointerCell(cell);

    expect(parsed.octave).toBe(payload.octave);
    expect(parsed.slot).toBe(payload.slot);
    expect(parsed.offset).toBe(payload.offset);
    expect(parsed.totalSize).toBe(payload.totalSize);
    expect(parsed.flags).toBe(payload.flags);
    expect(parsed.fragmentCount).toBe(payload.fragmentCount);
    expect(Buffer.from(parsed.contentHash)).toEqual(Buffer.from(payload.contentHash));
    expect(Buffer.from(parsed.typeHash)).toEqual(Buffer.from(payload.typeHash));
  });

  test('isPointerCell returns false for non-pointer cell', () => {
    const notPointer = new Uint8Array(1024);
    notPointer[0] = 0x04; // DATA type
    expect(engine.isPointerCell(notPointer)).toBe(false);
  });

  test('derefPointer with seeded cell store returns data', () => {
    // Seed a cell at octave 1, slot 7
    const targetCell = new Uint8Array(1024);
    targetCell[0] = 0xDE;
    targetCell[1] = 0xAD;
    targetCell[1023] = 0xFF;
    seedCellInStore(cellStore, 1, 7, targetCell);

    const pointerCell = engine.createPointerCell({
      octave: 1,
      slot: 7,
      offset: 0,
      contentHash: new Uint8Array(32),
      typeHash: new Uint8Array(32),
      totalSize: BigInt(1024),
      flags: 0,
      fragmentCount: 1,
    });

    const fetched = engine.derefPointer(pointerCell);
    expect(fetched.length).toBe(1024);
    expect(fetched[0]).toBe(0xDE);
    expect(fetched[1]).toBe(0xAD);
    expect(fetched[1023]).toBe(0xFF);
  });
});

```
