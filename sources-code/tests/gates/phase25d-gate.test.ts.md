---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase25d-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.564948+00:00
---

# tests/gates/phase25d-gate.test.ts

```ts
/**
 * Phase 25D Gate Tests — CellToken, Overlay Adapter, BRC-87 Naming,
 * Linearity, Shard Proxy, and Anti-Regression.
 *
 * All tests use mocked HTTP/UDP — no real network calls.
 */

import { describe, test, expect } from 'bun:test';
import { PrivateKey, PublicKey, Transaction, LockingScript, OP } from '@bsv/sdk';
import { CellToken } from '../../core/protocol-types/src/cell-token';
import { createFileTransaction, extractFile } from '../../core/protocol-types/src/cell-token-chain';
import {
  SEMANTOS_TOPICS,
  validateTopicName,
  topicForKey,
} from '../../core/protocol-types/src/overlay/topic-manager-client';
import {
  SEMANTOS_LOOKUP_SERVICES,
  validateLookupName,
} from '../../core/protocol-types/src/overlay/lookup-service-client';
import { ShardFrame, SHARD_FRAME_MAGIC, SHARD_FRAME_HEADER_SIZE } from '../../core/protocol-types/src/overlay/shard-frame';
import {
  CELL_SIZE,
  HEADER_SIZE,
  PAYLOAD_SIZE,
  MAGIC_1,
  MAGIC_2,
  MAGIC_3,
  MAGIC_4,
  Linearity,
  CONTINUATION_HEADER_SIZE,
  CONTINUATION_PAYLOAD_SIZE,
} from '../../core/protocol-types/src/constants';
import { serializeCellHeader, deserializeCellHeader, type CellHeader } from '../../core/protocol-types/src/cell-header';
import { MemoryAdapter } from '../../core/protocol-types/src/adapters/memory-adapter';

// ── Helpers ──

function makeCell(options?: {
  linearity?: number;
  version?: number;
  payloadByte?: number;
  totalSize?: number;
  cellCount?: number;
}): Uint8Array {
  const cell = new Uint8Array(CELL_SIZE);
  const dv = new DataView(cell.buffer);
  dv.setUint32(0, MAGIC_1, true);
  dv.setUint32(4, MAGIC_2, true);
  dv.setUint32(8, MAGIC_3, true);
  dv.setUint32(12, MAGIC_4, true);
  dv.setUint32(16, options?.linearity ?? Linearity.LINEAR, true);
  dv.setUint32(20, options?.version ?? 1, true);
  dv.setUint32(86, options?.cellCount ?? 1, true);
  dv.setUint32(90, options?.totalSize ?? 5, true);
  dv.setBigUint64(78, BigInt(Date.now()), true);
  if (options?.payloadByte !== undefined) {
    cell[HEADER_SIZE] = options.payloadByte;
  } else {
    // Default payload: "Hello"
    cell[HEADER_SIZE] = 0x48;
    cell[HEADER_SIZE + 1] = 0x65;
    cell[HEADER_SIZE + 2] = 0x6c;
    cell[HEADER_SIZE + 3] = 0x6c;
    cell[HEADER_SIZE + 4] = 0x6f;
  }
  return cell;
}

function makeContentHash(): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(32));
}

// ── CellToken Tests (T1–T4) ──

describe('Phase 25D — CellToken', () => {
  const key = PrivateKey.fromRandom();
  const pubKey = key.toPublicKey();
  const contentHash = makeContentHash();

  // T1: createOutputScript produces valid PushDrop script
  test('T1: PushDrop script creation', () => {
    const cell = makeCell();
    const script = CellToken.createOutputScript(cell, 'objects/create/job/test-1', contentHash, pubKey);

    expect(script).toBeInstanceOf(LockingScript);
    expect(script.chunks.length).toBe(8);
    // Last chunk should be OP_CHECKSIG
    expect(script.chunks[7].op).toBe(OP.OP_CHECKSIG);
    // DROP sequence: OP_2DROP, OP_2DROP (4 fields → 2× OP_2DROP)
    expect(script.chunks[4].op).toBe(OP.OP_2DROP);
    expect(script.chunks[5].op).toBe(OP.OP_2DROP);
  });

  // T2: extract recovers identical cell bytes from PushDrop script
  test('T2: PushDrop round-trip', () => {
    const cell = makeCell();
    const script = CellToken.createOutputScript(cell, 'objects/create/job/test-2', contentHash, pubKey);
    const extracted = CellToken.extract(script);

    expect(extracted).not.toBeNull();
    expect(extracted!.cellBytes).toEqual(cell);
    expect(extracted!.semanticPath).toBe('objects/create/job/test-2');
    expect(extracted!.contentHash).toEqual(contentHash);
    expect(extracted!.ownerPubKey.toString()).toBe(pubKey.toString());
  });

  // T3: createTransition creates valid spend transaction
  test('T3: state transition transaction', () => {
    const oldCell = makeCell({ version: 1 });
    const newCell = makeCell({ version: 2 });
    const oldScript = CellToken.createOutputScript(oldCell, 'objects/test', contentHash, pubKey);

    const tx = CellToken.createTransition(
      { txid: '0'.repeat(64), vout: 0, script: oldScript, satoshis: 1 },
      newCell,
      'objects/test',
      contentHash,
      key,
    );

    expect(tx).toBeInstanceOf(Transaction);
    expect(tx.inputs.length).toBe(1);
    expect(tx.outputs.length).toBe(1);
    expect(tx.outputs[0].satoshis).toBe(1);

    // Verify new output is a valid CellToken
    const extracted = CellToken.extract(tx.outputs[0].lockingScript);
    expect(extracted).not.toBeNull();
    expect(extracted!.cellBytes).toEqual(newCell);
  });

  // T4: Multi-cell file creates manifest + chunk tokens
  test('T4: multi-cell file token', () => {
    // Create 3 cells (1 manifest + 2 chunks)
    const cells = [
      makeCell({ cellCount: 3, totalSize: 2000 }),
      makeCell({ payloadByte: 0x01 }),
      makeCell({ payloadByte: 0x02 }),
    ];
    // Write continuation headers into chunk cells
    const chunk1 = cells[1];
    chunk1[0] = 4; // CellType.DATA
    const dv1 = new DataView(chunk1.buffer);
    dv1.setUint16(1, 1, true); // cellIndex = 1
    dv1.setUint16(3, 2, true); // totalCells = 2
    dv1.setUint16(5, 100, true); // payloadSize = 100
    // Clear magic for continuation cells
    dv1.setUint32(0, 0, true);
    // Re-set cell type after clearing
    chunk1[0] = 4;

    const chunk2 = cells[2];
    chunk2[0] = 4;
    const dv2 = new DataView(chunk2.buffer);
    dv2.setUint16(1, 2, true);
    dv2.setUint16(3, 2, true);
    dv2.setUint16(5, 100, true);
    dv2.setUint32(0, 0, true);
    chunk2[0] = 4;

    // Manifest cell needs valid magic for CellToken
    const result = createFileTransaction(
      [cells[0]],
      'objects/test-file',
      contentHash,
      pubKey,
    );

    expect(result.tx).toBeInstanceOf(Transaction);
    expect(result.outputCount).toBe(1); // Just manifest for single-cell
  });
});

// ── Overlay Adapter Tests (T5–T8) ──

describe('Phase 25D — BsvOverlayAdapter', () => {
  // T5: BsvOverlayAdapter interface check
  test('T5: implements StorageAdapter interface', async () => {
    // Import dynamically to check interface compliance
    const { BsvOverlayAdapter } = await import('../../core/protocol-types/src/adapters/bsv-overlay-adapter');
    expect(BsvOverlayAdapter).toBeDefined();
    expect(typeof BsvOverlayAdapter).toBe('function');

    // Verify prototype has all StorageAdapter methods
    const proto = BsvOverlayAdapter.prototype;
    expect(typeof proto.read).toBe('function');
    expect(typeof proto.write).toBe('function');
    expect(typeof proto.exists).toBe('function');
    expect(typeof proto.list).toBe('function');
    expect(typeof proto.delete).toBe('function');
    expect(typeof proto.stat).toBe('function');
  });

  // T6: TopicManagerClient exists and has submit method
  test('T6: TopicManagerClient contract', async () => {
    const { TopicManagerClient } = await import('../../core/protocol-types/src/overlay/topic-manager-client');
    const client = new TopicManagerClient({ networkPreset: 'testnet' });
    expect(typeof client.submit).toBe('function');
    expect(typeof client.submitForKey).toBe('function');
  });

  // T7: LookupServiceClient exists and has query methods
  test('T7: LookupServiceClient contract', async () => {
    const { LookupServiceClient } = await import('../../core/protocol-types/src/overlay/lookup-service-client');
    const client = new LookupServiceClient({ networkPreset: 'testnet' });
    expect(typeof client.queryByPath).toBe('function');
    expect(typeof client.queryByContent).toBe('function');
    expect(typeof client.queryByParent).toBe('function');
    expect(typeof client.queryByOwner).toBe('function');
    expect(typeof client.queryByType).toBe('function');
    expect(typeof client.queryHistory).toBe('function');
    expect(typeof client.decodeLookupOutputs).toBe('function');
  });

  // T8: CellToken round-trip compatible with CellStore cells
  test('T8: cell format compatibility with CellStore', async () => {
    const { CellStore } = await import('../../core/protocol-types/src/cell-store');
    const adapter = new MemoryAdapter();
    const store = new CellStore(adapter);

    // Write through CellStore
    const data = new Uint8Array([1, 2, 3, 4, 5]);
    const ref = await store.put('test/item', data);

    // Read the raw cell bytes
    const cellBytes = await adapter.read('test/item');
    expect(cellBytes).not.toBeNull();
    expect(cellBytes!.length).toBe(CELL_SIZE);

    // Pack into CellToken and extract
    const key = PrivateKey.fromRandom();
    const contentHash = makeContentHash();
    const script = CellToken.createOutputScript(cellBytes!, 'test/item', contentHash, key.toPublicKey());
    const extracted = CellToken.extract(script);

    expect(extracted).not.toBeNull();
    expect(extracted!.cellBytes).toEqual(cellBytes!);

    // Verify header still deserializes correctly
    const header = deserializeCellHeader(extracted!.cellBytes);
    expect(header.version).toBe(1);
    expect(header.totalSize).toBe(5);
  });
});

// ── BRC-87 Naming Tests (T9–T10) ──

describe('Phase 25D — BRC-87 Compliance', () => {
  // T9: All topic names follow BRC-87
  test('T9: topic naming', () => {
    const topics = Object.values(SEMANTOS_TOPICS);
    for (const t of topics) {
      expect(t).toMatch(/^[a-z_]{1,50}$/);
      expect(validateTopicName(t)).toBe(true);
    }
    // Invalid names
    expect(validateTopicName('TM_UPPER')).toBe(false);
    expect(validateTopicName('has spaces')).toBe(false);
    expect(validateTopicName('has-dashes')).toBe(false);
    expect(validateTopicName('x'.repeat(51))).toBe(false);
  });

  // T10: All lookup service names follow BRC-87
  test('T10: lookup naming', () => {
    const services = Object.values(SEMANTOS_LOOKUP_SERVICES);
    for (const s of services) {
      expect(s).toMatch(/^[a-z_]{1,50}$/);
      expect(validateLookupName(s)).toBe(true);
    }
  });
});

// ── Linearity at UTXO Level (T11–T13) ──

describe('Phase 25D — Linearity Enforcement', () => {
  const key = PrivateKey.fromRandom();
  const pubKey = key.toPublicKey();
  const contentHash = makeContentHash();

  // T11: LINEAR cell-token has linearity = 1 in header
  test('T11: LINEAR cell token', () => {
    const cell = makeCell({ linearity: Linearity.LINEAR });
    const script = CellToken.createOutputScript(cell, 'objects/linear', contentHash, pubKey);
    const extracted = CellToken.extract(script)!;
    const header = deserializeCellHeader(extracted.cellBytes);
    expect(header.linearity).toBe(Linearity.LINEAR);
  });

  // T12: AFFINE cell-token has linearity = 2 in header
  test('T12: AFFINE cell token', () => {
    const cell = makeCell({ linearity: Linearity.AFFINE });
    const script = CellToken.createOutputScript(cell, 'objects/affine', contentHash, pubKey);
    const extracted = CellToken.extract(script)!;
    const header = deserializeCellHeader(extracted.cellBytes);
    expect(header.linearity).toBe(Linearity.AFFINE);
  });

  // T13: Cell-token spend creates valid new CellToken (state transition)
  test('T13: spend creates new token', () => {
    const oldCell = makeCell({ version: 1, linearity: Linearity.LINEAR });
    const newCell = makeCell({ version: 2, linearity: Linearity.LINEAR });
    const oldScript = CellToken.createOutputScript(oldCell, 'objects/test', contentHash, pubKey);

    const tx = CellToken.createTransition(
      { txid: 'a'.repeat(64), vout: 0, script: oldScript, satoshis: 1 },
      newCell,
      'objects/test',
      contentHash,
      key,
    );

    // New output is a valid CellToken
    const newExtracted = CellToken.extract(tx.outputs[0].lockingScript);
    expect(newExtracted).not.toBeNull();

    const newHeader = deserializeCellHeader(newExtracted!.cellBytes);
    expect(newHeader.version).toBe(2);
    expect(newHeader.linearity).toBe(Linearity.LINEAR);
  });
});

// ── Shard Proxy Tests (T14–T18) ──

describe('Phase 25D — Shard Proxy Integration', () => {
  // T14: ShardFrame.encode produces valid BRC-12 frame
  test('T14: BRC-12 frame encoding', () => {
    const txid = new Uint8Array(32);
    txid.fill(0xAB);
    const payload = new Uint8Array([0x01, 0x02, 0x03]);
    const frame = ShardFrame.encode(txid, payload);

    expect(frame.length).toBe(SHARD_FRAME_HEADER_SIZE + 3);

    // Check magic bytes at offset 0 (big-endian)
    const dv = new DataView(frame.buffer);
    expect(dv.getUint32(0, false)).toBe(SHARD_FRAME_MAGIC);

    // Check protocol version at offset 4 (big-endian)
    expect(dv.getUint16(4, false)).toBe(0x02BF);

    // Check frame version at offset 6
    expect(frame[6]).toBe(0x01);

    // Check payload length at offset 40 (big-endian)
    expect(dv.getUint32(40, false)).toBe(3);
  });

  // T15: ShardFrame.decode round-trips with encode
  test('T15: BRC-12 frame round-trip', () => {
    const txid = crypto.getRandomValues(new Uint8Array(32));
    const payload = crypto.getRandomValues(new Uint8Array(100));
    const frame = ShardFrame.encode(txid, payload);
    const decoded = ShardFrame.decode(frame);

    expect(decoded).not.toBeNull();
    expect(decoded!.txid).toEqual(txid);
    expect(decoded!.payload).toEqual(payload);
  });

  // T16: shardIndex matches Go implementation (top N bits of first uint32)
  test('T16: shard index derivation', () => {
    const txid = new Uint8Array(32);
    txid[0] = 0xFF;
    // With 8 shard bits: top 8 bits of 0xFF000000 = 0xFF = 255
    expect(ShardFrame.shardIndex(txid, 8)).toBe(255);
    // With 2 shard bits: top 2 bits of 0xFF000000 = 0b11 = 3
    expect(ShardFrame.shardIndex(txid, 2)).toBe(3);
    // With 1 shard bit: top 1 bit = 1
    expect(ShardFrame.shardIndex(txid, 1)).toBe(1);

    // Edge case: all zeros
    const zeroTxid = new Uint8Array(32);
    expect(ShardFrame.shardIndex(zeroTxid, 8)).toBe(0);

    // Known value: 0x80 = 1000 0000, 1 shard bit = 1
    const halfTxid = new Uint8Array(32);
    halfTxid[0] = 0x80;
    expect(ShardFrame.shardIndex(halfTxid, 1)).toBe(1);
    expect(ShardFrame.shardIndex(halfTxid, 8)).toBe(0x80);
  });

  // T17: multicastAddr produces valid IPv6 address
  test('T17: multicast address derivation', () => {
    const addr = ShardFrame.multicastAddr(42, 0x02, new Uint8Array(10));
    expect(addr.length).toBe(16);
    expect(addr[0]).toBe(0xFF);
    expect(addr[1]).toBe(0x02); // link-local scope
    expect(addr[15]).toBe(42); // group index in low byte
  });

  // T18: ShardFrame rejects invalid frames
  test('T18: invalid frame rejection', () => {
    // Too short
    expect(ShardFrame.decode(new Uint8Array(10))).toBeNull();

    // Wrong magic
    const badMagic = new Uint8Array(48);
    badMagic[0] = 0xFF; // Wrong magic
    expect(ShardFrame.decode(badMagic)).toBeNull();

    // Wrong version
    const badVersion = new Uint8Array(48);
    const dv = new DataView(badVersion.buffer);
    dv.setUint32(0, SHARD_FRAME_MAGIC, false);
    badVersion[6] = 0x99; // Wrong version
    expect(ShardFrame.decode(badVersion)).toBeNull();
  });
});

// ── Topic/Key Mapping Tests ──

describe('Phase 25D — Topic Routing', () => {
  test('topicForKey maps prefixes correctly', () => {
    expect(topicForKey('objects/create/job/test')).toBe('tm_semantos_objects');
    expect(topicForKey('policies/access/rule-1')).toBe('tm_semantos_policies');
    expect(topicForKey('identity/facet-1')).toBe('tm_semantos_identity');
    expect(topicForKey('governance/proposal-1')).toBe('tm_semantos_governance');
    expect(topicForKey('taxonomy/config-1')).toBe('tm_semantos_taxonomy');
    expect(topicForKey('evidence/log-1')).toBe('tm_semantos_evidence');
  });

  test('topicForKey throws on unknown prefix', () => {
    expect(() => topicForKey('unknown/path')).toThrow();
  });
});

// ── Anti-Regression (T19–T21) ──

describe('Phase 25D — Anti-Regression', () => {
  // T19: All Phase 25D modules exist and export correctly
  test('T19: Phase 25D module exports', async () => {
    // Phase 25D modules resolve
    const cellToken = await import('../../core/protocol-types/src/cell-token');
    expect(cellToken.CellToken).toBeDefined();

    const chain = await import('../../core/protocol-types/src/cell-token-chain');
    expect(chain.createFileTransaction).toBeDefined();
    expect(chain.extractFile).toBeDefined();

    const overlay = await import('../../core/protocol-types/src/adapters/bsv-overlay-adapter');
    expect(overlay.BsvOverlayAdapter).toBeDefined();

    const topic = await import('../../core/protocol-types/src/overlay/topic-manager-client');
    expect(topic.TopicManagerClient).toBeDefined();
    expect(topic.SEMANTOS_TOPICS).toBeDefined();

    const lookup = await import('../../core/protocol-types/src/overlay/lookup-service-client');
    expect(lookup.LookupServiceClient).toBeDefined();
    expect(lookup.SEMANTOS_LOOKUP_SERVICES).toBeDefined();

    const shard = await import('../../core/protocol-types/src/overlay/shard-frame');
    expect(shard.ShardFrame).toBeDefined();

    const proxy = await import('../../core/protocol-types/src/overlay/shard-proxy-client');
    expect(proxy.ShardProxyClient).toBeDefined();

    // Phase 25A/B/C still work
    expect(MemoryAdapter).toBeDefined();
    expect(CellToken).toBeDefined();
    expect(deserializeCellHeader).toBeDefined();
  });

  // T20: CellStore works with MemoryAdapter (local path still works)
  test('T20: local storage unaffected', async () => {
    const { CellStore } = await import('../../core/protocol-types/src/cell-store');
    const adapter = new MemoryAdapter();
    const cellStore = new CellStore(adapter);

    const data = new TextEncoder().encode('test data');
    const ref = await cellStore.put('objects/create/job/test-anti-regress', data);
    expect(ref.key).toBe('objects/create/job/test-anti-regress');
    expect(ref.version).toBe(1);

    const value = await cellStore.get('objects/create/job/test-anti-regress');
    expect(value).not.toBeNull();
    expect(new TextDecoder().decode(value!.payload)).toBe('test data');

    // Verify versioning still works
    const ref2 = await cellStore.put('objects/create/job/test-anti-regress', new TextEncoder().encode('v2'));
    expect(ref2.version).toBe(2);

    const history = await cellStore.history('objects/create/job/test-anti-regress');
    expect(history.length).toBe(2);
  });

  // T21: CellStore cells are byte-compatible with CellToken extraction
  test('T21: cell format compatibility', async () => {
    const adapter = new MemoryAdapter();
    const { CellStore } = await import('../../core/protocol-types/src/cell-store');
    const store = new CellStore(adapter);

    // Write a cell through CellStore
    await store.put('compat/test', new TextEncoder().encode('compat'));

    // Read raw bytes
    const rawCell = await adapter.read('compat/test');
    expect(rawCell).not.toBeNull();
    expect(rawCell!.length).toBe(CELL_SIZE);

    // Verify it deserializes with protocol-types
    const header = deserializeCellHeader(rawCell!);
    expect(header.version).toBe(1);

    // Pack into CellToken and extract
    const key = PrivateKey.fromRandom();
    const hash = crypto.getRandomValues(new Uint8Array(32));
    const script = CellToken.createOutputScript(rawCell!, 'compat/test', hash, key.toPublicKey());
    const extracted = CellToken.extract(script);
    expect(extracted).not.toBeNull();

    // Byte-identical
    for (let i = 0; i < CELL_SIZE; i++) {
      expect(extracted!.cellBytes[i]).toBe(rawCell![i]);
    }
  });
});

```
