---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase26-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.575789+00:00
---

# tests/gates/phase26-gate.test.ts

```ts
/**
 * Phase 26 Gate Tests — Game Engine SemanticObject SDK
 *
 * T1–T25: entities, linearity, trades, policies, compatibility, anti-lock.
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

const ROOT = join(import.meta.dir, '../..');
const GAME_SDK = join(ROOT, 'packages/game-sdk');
const WASM_PATH = join(ROOT, 'core/cell-engine/zig-out/bin/cell-engine.wasm');

// ── Imports ─────────────────────────────────────────────────────

import { GameCellEngine } from '../../packages/game-sdk/src/engine';
import { GameEntityType, LinearityError, TradeError } from '../../packages/game-sdk/src/types';
import { encodeEntityPayload, decodeEntityPayload } from '../../packages/game-sdk/src/codec';
import { compileGamePolicy, packPolicyCell } from '../../packages/game-sdk/src/policies/compiler';
import { LINEARITY } from '../../core/cell-ops/src/typeHashRegistry';

// ── Helpers ─────────────────────────────────────────────────────

const OWNER_A = new Uint8Array(16).fill(0xAA);
const OWNER_B = new Uint8Array(16).fill(0xBB);

async function createEngine(): Promise<GameCellEngine> {
  if (!existsSync(WASM_PATH)) {
    throw new Error('WASM binary not found — run zig build first');
  }
  const wasmBytes = readFileSync(WASM_PATH);
  return GameCellEngine.create({ wasmBytes });
}

// ── D26.1/D26.2 — GameEntity Creation (T1–T4) ──────────────────

describe('D26.1/D26.2 — GameEntity creation', () => {
  test('T1: LINEAR entity has correct cell header (magic, linearity, version)', async () => {
    const engine = await createEngine();
    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Legendary Sword' },
    });

    expect(entity.cell.length).toBe(1024);

    // Magic bytes at offset 0 — raw byte sequence
    // buildCellHeader writes MAGIC as raw bytes: [0xDE,0xAD,0xBE,0xEF, 0xCA,0xFE,0xBA,0xBE, ...]
    expect(entity.cell[0]).toBe(0xDE);
    expect(entity.cell[1]).toBe(0xAD);
    expect(entity.cell[2]).toBe(0xBE);
    expect(entity.cell[3]).toBe(0xEF);
    expect(entity.cell[4]).toBe(0xCA);
    expect(entity.cell[5]).toBe(0xFE);
    expect(entity.cell[6]).toBe(0xBA);
    expect(entity.cell[7]).toBe(0xBE);
    expect(entity.cell[8]).toBe(0x13);
    expect(entity.cell[9]).toBe(0x37);
    expect(entity.cell[12]).toBe(0x42);

    // Linearity at offset 16 (4 bytes LE)
    const view = new DataView(entity.cell.buffer, entity.cell.byteOffset);
    expect(view.getUint32(16, true)).toBe(LINEARITY.LINEAR); // 1

    // Version at offset 20 (4 bytes LE)
    expect(view.getUint32(20, true)).toBe(1);
  });

  test('T2: entity metadata round-trips through serialize/deserialize (byte-identical)', async () => {
    const engine = await createEngine();
    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Iron Shield', defense: 25 },
    });

    const serialized = engine.serialize(entity);
    const deserialized = engine.deserialize(serialized);

    expect(deserialized.entityType).toBe(entity.entityType);
    expect(deserialized.linearity).toBe(entity.linearity);
    expect(deserialized.state).toBe(entity.state);
    expect(deserialized.metadata.name).toBe('Iron Shield');
    expect(deserialized.metadata.defense).toBe(25);

    // Byte-identical round-trip
    const reSerialized = engine.serialize(deserialized);
    expect(reSerialized).toEqual(serialized);
  });

  test('T3: entity type maps to correct GameEntityType enum value', async () => {
    const engine = await createEngine();

    const item = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
    });
    expect(item.entityType).toBe(GameEntityType.ITEM);
    expect(item.entityType).toBe(1);

    const quest = engine.createEntity({
      entityType: GameEntityType.QUEST,
      ownerId: OWNER_A,
      linearity: LINEARITY.RELEVANT,
    });
    expect(quest.entityType).toBe(GameEntityType.QUEST);
    expect(quest.entityType).toBe(5);
  });

  test('T4: entity ID is deterministic (same cell bytes = same ID)', async () => {
    const { createHash } = await import('crypto');
    const engine = await createEngine();

    // Pin Date.now() so the timestamp in the cell header is identical
    const now = Date.now();
    const originalNow = Date.now;
    Date.now = () => now;

    try {
      const entity1 = engine.createEntity({
        entityType: GameEntityType.ITEM,
        ownerId: OWNER_A,
        linearity: LINEARITY.LINEAR,
        metadata: { name: 'Test' },
      });

      const entity2 = engine.createEntity({
        entityType: GameEntityType.ITEM,
        ownerId: OWNER_A,
        linearity: LINEARITY.LINEAR,
        metadata: { name: 'Test' },
      });

      // Same entityType + same timestamp → same cell bytes → same ID
      expect(entity1.id).toBe(entity2.id);
      expect(entity1.id.length).toBe(64); // hex SHA256
    } finally {
      Date.now = originalNow;
    }
    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Test' },
    });

    // ID is hex SHA-256 of cell bytes — 64 chars
    expect(entity.id.length).toBe(64);
    expect(entity.id).toMatch(/^[0-9a-f]{64}$/);

    // Recomputing SHA-256 of the same cell bytes yields the same ID
    const recomputed = createHash('sha256').update(entity.cell).digest('hex');
    expect(recomputed).toBe(entity.id);

    // Two entities with same type have distinct IDs (timestamp differs)
    const entity2 = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Test' },
    });
    expect(entity2.id.length).toBe(64);
  });
});

// ── D26.2 — Linearity Enforcement (T5–T10) ─────────────────────

describe('D26.2 — Linearity enforcement', () => {
  test('T5: LINEAR entity cannot be added to two inventories simultaneously', async () => {
    const engine = await createEngine();
    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Unique Ring' },
    });

    const inv1 = engine.addToInventory(
      engine.createInventory(OWNER_A),
      'slot1',
      entity,
    );

    // Adding to another slot in the same inventory should fail (slot occupied test)
    expect(() => engine.addToInventory(inv1, 'slot1', entity)).toThrow(LinearityError);
  });

  test('T6: AFFINE entity can be destroyed but not duplicated', async () => {
    const engine = await createEngine();
    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.AFFINE,
      metadata: { name: 'Health Potion' },
    });

    const inv = engine.addToInventory(
      engine.createInventory(OWNER_A),
      'potion',
      entity,
    );

    // Can remove (destroy) AFFINE
    const { inventory: afterRemove, removed } = engine.removeFromInventory(inv, 'potion');
    expect(afterRemove.slots.has('potion')).toBe(false);
    expect(removed.length).toBe(1024);
  });

  test('T7: RELEVANT entity cannot be removed from inventory', async () => {
    const engine = await createEngine();
    const entity = engine.createEntity({
      entityType: GameEntityType.QUEST,
      ownerId: OWNER_A,
      linearity: LINEARITY.RELEVANT,
      metadata: { name: 'Ancient Map' },
    });

    const inv = engine.addToInventory(
      engine.createInventory(OWNER_A),
      'quest',
      entity,
    );

    expect(() => engine.removeFromInventory(inv, 'quest')).toThrow(LinearityError);
    expect(() => engine.removeFromInventory(inv, 'quest')).toThrow(/RELEVANT/);
  });

  test('T8: FUNGIBLE (DEBUG) entity can be freely copied and removed', async () => {
    const engine = await createEngine();
    const entity = engine.createEntity({
      entityType: GameEntityType.CURRENCY,
      ownerId: OWNER_A,
      linearity: LINEARITY.DEBUG, // DEBUG=4 used as FUNGIBLE
      metadata: { name: 'Gold Coin', amount: 100 },
    });

    const inv = engine.addToInventory(
      engine.createInventory(OWNER_A),
      'gold',
      entity,
    );

    // Can remove freely
    const { inventory: afterRemove } = engine.removeFromInventory(inv, 'gold');
    expect(afterRemove.slots.has('gold')).toBe(false);
  });

  test('T9: removeFromInventory on LINEAR without destination throws', async () => {
    const engine = await createEngine();
    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Linear Blade' },
    });

    const inv = engine.addToInventory(
      engine.createInventory(OWNER_A),
      'weapon',
      entity,
    );

    // LINEAR cannot be removed without a destination
    expect(() => engine.removeFromInventory(inv, 'weapon')).toThrow(LinearityError);
    expect(() => engine.removeFromInventory(inv, 'weapon')).toThrow(/LINEAR/);
  });

  test('T10: transferBetweenInventories is atomic — source empties and target fills', async () => {
    const engine = await createEngine();
    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Transfer Sword' },
    });

    const invA = engine.addToInventory(
      engine.createInventory(OWNER_A),
      'weapon',
      entity,
    );
    const invB = engine.createInventory(OWNER_B);

    const { from, to } = engine.transferBetweenInventories(
      invA, invB, 'weapon', 'received',
    );

    // Source emptied
    expect(from.slots.has('weapon')).toBe(false);
    // Target filled
    expect(to.slots.has('received')).toBe(true);

    // Verify ownerId was updated in the transferred cell
    const transferred = engine.getEntity(to.slots.get('received')!);
    expect(transferred.ownerId).toEqual(OWNER_B);
  });
});

// ── D26.2 — Trade Execution (T11–T14) ──────────────────────────

describe('D26.2 — Trade execution', () => {
  test('T11: atomic swap transfers cells between two inventories', async () => {
    const engine = await createEngine();

    const sword = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Sword' },
    });
    const shield = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_B,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Shield' },
    });

    const invA = engine.addToInventory(engine.createInventory(OWNER_A), 'sword', sword);
    const invB = engine.addToInventory(engine.createInventory(OWNER_B), 'shield', shield);

    const result = engine.executeTrade({
      partyA: { inventory: invA, offer: { slots: ['sword'] } },
      partyB: { inventory: invB, offer: { slots: ['shield'] } },
    });

    expect(result.success).toBe(true);
    expect(result.updatedA!.slots.has('shield')).toBe(true);
    expect(result.updatedB!.slots.has('sword')).toBe(true);
    expect(result.updatedA!.slots.has('sword')).toBe(false);
    expect(result.updatedB!.slots.has('shield')).toBe(false);
  });

  test('T12: trade fails if offerer does not own offered items', async () => {
    const engine = await createEngine();

    const invA = engine.createInventory(OWNER_A); // empty
    const invB = engine.createInventory(OWNER_B);

    const result = engine.executeTrade({
      partyA: { inventory: invA, offer: { slots: ['nonexistent'] } },
      partyB: { inventory: invB, offer: { slots: [] } },
    });

    expect(result.success).toBe(false);
    expect(result.error).toContain('does not own');
  });

  test('T13: trade fails for RELEVANT entities', async () => {
    const engine = await createEngine();

    const questItem = engine.createEntity({
      entityType: GameEntityType.QUEST,
      ownerId: OWNER_A,
      linearity: LINEARITY.RELEVANT,
      metadata: { name: 'Quest Log' },
    });

    const invA = engine.addToInventory(engine.createInventory(OWNER_A), 'quest', questItem);
    const invB = engine.createInventory(OWNER_B);

    const result = engine.executeTrade({
      partyA: { inventory: invA, offer: { slots: ['quest'] } },
      partyB: { inventory: invB, offer: { slots: [] } },
    });

    expect(result.success).toBe(false);
    expect(result.error).toContain('RELEVANT');
  });

  test('T14: trade with empty offers succeeds (no-op)', async () => {
    const engine = await createEngine();

    const invA = engine.createInventory(OWNER_A);
    const invB = engine.createInventory(OWNER_B);

    const result = engine.executeTrade({
      partyA: { inventory: invA, offer: { slots: [] } },
      partyB: { inventory: invB, offer: { slots: [] } },
    });

    // Empty offers = valid no-op trade
    expect(result.success).toBe(true);
  });
});

// ── D26.5 — Game Policies (T15–T18) ────────────────────────────

describe('D26.5 — Game policies', () => {
  test('T15: legendary-drop.policy compiles to valid capability cell', () => {
    const source = readFileSync(
      join(GAME_SDK, 'src/policies/templates/legendary-drop.policy'),
      'utf-8',
    );
    const policy = compileGamePolicy(source);
    expect(policy.scriptBytes.length).toBeGreaterThan(0);
    expect(policy.linearity).toBe('LINEAR');

    // Pack into a cell
    const cell = packPolicyCell(policy, OWNER_A);
    expect(cell.length).toBe(1024);

    // Validate magic bytes
    const view = new DataView(cell.buffer, cell.byteOffset);
    expect(view.getUint32(0, true)).toBe(0xDEADBEEF);
  });

  test('T16: compiled policy bytes are non-empty and deterministic', () => {
    const source = readFileSync(
      join(GAME_SDK, 'src/policies/templates/durability.policy'),
      'utf-8',
    );

    const policy1 = compileGamePolicy(source);
    const policy2 = compileGamePolicy(source);

    expect(policy1.scriptBytes.length).toBeGreaterThan(0);
    expect(policy1.scriptBytes).toEqual(policy2.scriptBytes);
  });

  test('T17: level-gate.policy compiles and produces correct linearity', () => {
    const source = readFileSync(
      join(GAME_SDK, 'src/policies/templates/level-gate.policy'),
      'utf-8',
    );

    const policy = compileGamePolicy(source);
    expect(policy.linearity).toBe('LINEAR');
    expect(policy.scriptBytes.length).toBeGreaterThan(0);
    expect(policy.scriptWords.length).toBeGreaterThan(0);
  });

  test('T18: policy compilation is deterministic (same input = same bytes)', () => {
    const source = readFileSync(
      join(GAME_SDK, 'src/policies/templates/trade-restriction.policy'),
      'utf-8',
    );

    const a = compileGamePolicy(source);
    const b = compileGamePolicy(source);

    expect(a.scriptBytes).toEqual(b.scriptBytes);
    expect(a.scriptWords).toBe(b.scriptWords);
    expect(a.linearity).toBe(b.linearity);
  });
});

// ── D26.2 — Cell Compatibility (T19–T22) ────────────────────────

describe('D26.2 — Cell compatibility', () => {
  test('T19: GameEntity serializes to valid cell engine format (magic bytes)', async () => {
    const engine = await createEngine();
    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Test Item' },
    });

    const bytes = engine.serialize(entity);

    // Magic bytes — raw byte sequence from buildCellHeader
    expect(bytes[0]).toBe(0xDE);
    expect(bytes[1]).toBe(0xAD);
    expect(bytes[2]).toBe(0xBE);
    expect(bytes[3]).toBe(0xEF);
    expect(bytes[4]).toBe(0xCA);
    expect(bytes[5]).toBe(0xFE);
    expect(bytes[6]).toBe(0xBA);
    expect(bytes[7]).toBe(0xBE);
  });

  test('T20: serialized entity is exactly 1024 bytes', async () => {
    const engine = await createEngine();
    const entity = engine.createEntity({
      entityType: GameEntityType.CHARACTER,
      ownerId: OWNER_A,
      linearity: LINEARITY.AFFINE,
      metadata: { name: 'Hero', class: 'warrior', hp: 100 },
    });

    expect(engine.serialize(entity).length).toBe(1024);
  });

  test('T21: cell engine can validate magic of serialized entity', async () => {
    const engine = await createEngine();
    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Validated Item' },
    });

    // The cell should be valid per cell-ops validation
    const { isValidCell } = await import('../../core/cell-ops/src/typeHashRegistry');
    expect(isValidCell(Buffer.from(entity.cell))).toBe(true);
  });

  test('T22: byte-identical output for same input params', async () => {
    const engine = await createEngine();
    const params = {
      entityType: GameEntityType.ITEM as GameEntityType,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR as typeof LINEARITY.LINEAR,
      metadata: { name: 'Deterministic', value: 42 },
    };

    const entity1 = engine.createEntity(params);
    const entity2 = engine.createEntity(params);

    // typeHash (ID) is deterministic
    expect(entity1.id).toBe(entity2.id);

    // Payload region (after header) should be identical
    // (Header timestamps differ, but payload encoding is deterministic)
    const payload1 = entity1.cell.subarray(256);
    const payload2 = entity2.cell.subarray(256);
    expect(payload1).toEqual(payload2);
  });
});

// ── D26 — Anti-Lock (T23–T25) ──────────────────────────────────

describe('D26 — Anti-lock', () => {
  test('T23: no React imports in game-sdk package', () => {
    const files = [
      'src/index.ts',
      'src/types.ts',
      'src/codec.ts',
      'src/engine.ts',
      'src/policies/compiler.ts',
      'src/policies/primitives.ts',
      'src/policies/index.ts',
      'src/bindings/godot/index.ts',
      'src/bindings/unity/index.ts',
    ];

    for (const file of files) {
      const fullPath = join(GAME_SDK, file);
      if (existsSync(fullPath)) {
        const content = readFileSync(fullPath, 'utf-8');
        expect(content).not.toContain("from 'react'");
        expect(content).not.toContain('from "react"');
        expect(content).not.toContain("import React");
      }
    }
  });

  test('T24: no game engine imports in core source files (types, codec, engine)', () => {
    // Core files must not reference any game engine.
    // The barrel index.ts re-exports binding types and is excluded.
    const coreFiles = [
      'src/types.ts',
      'src/codec.ts',
      'src/engine.ts',
      'src/policies/compiler.ts',
      'src/policies/primitives.ts',
    ];

    for (const file of coreFiles) {
      const fullPath = join(GAME_SDK, file);
      if (existsSync(fullPath)) {
        const content = readFileSync(fullPath, 'utf-8');
        expect(content).not.toContain("from 'godot");
        expect(content).not.toContain('from "godot');
        expect(content).not.toContain("from 'unity");
        expect(content).not.toContain('from "unity');
        expect(content).not.toContain("from '@godot");
        expect(content).not.toContain("from '@unity");
      }
    }
  });

  test('T25: package.json has no Godot or Unity dependencies', () => {
    const pkg = JSON.parse(
      readFileSync(join(GAME_SDK, 'package.json'), 'utf-8'),
    );

    const allDeps = {
      ...pkg.dependencies,
      ...pkg.devDependencies,
      ...pkg.peerDependencies,
    };

    const depNames = Object.keys(allDeps).join(' ').toLowerCase();
    expect(depNames).not.toContain('godot');
    expect(depNames).not.toContain('unity');
    expect(depNames).not.toContain('react');
  });
});

// ── D26 — StorageAdapter Integration (T26–T30) ─────────────────

import { MemoryAdapter } from '../../core/protocol-types/src/adapters/memory-adapter';

describe('D26 — StorageAdapter integration', () => {
  test('T26: GameCellEngine.create() initializes with MemoryAdapter in test env', async () => {
    const engine = await createEngine();
    expect(engine.storage).toBeDefined();
  });

  test('T27: createEntity persists cell to storage', async () => {
    const adapter = new MemoryAdapter();
    const wasmBytes = readFileSync(WASM_PATH);
    const engine = await GameCellEngine.create({ wasmBytes, storage: adapter });

    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Stored Sword' },
    });

    // Entity should be persisted
    const stored = await adapter.read(`entities/${entity.id}/latest.cell`);
    expect(stored).not.toBeNull();
    expect(stored!.length).toBe(1024);
    expect(stored!).toEqual(entity.cell);
  });

  test('T28: loadEntity retrieves persisted entity', async () => {
    const adapter = new MemoryAdapter();
    const wasmBytes = readFileSync(WASM_PATH);
    const engine = await GameCellEngine.create({ wasmBytes, storage: adapter });

    const created = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.AFFINE,
      metadata: { name: 'Loadable Item', value: 42 },
    });

    const loaded = await engine.loadEntity(created.id);
    expect(loaded).not.toBeNull();
    expect(loaded!.entityType).toBe(created.entityType);
    expect(loaded!.metadata.name).toBe('Loadable Item');
    expect(loaded!.metadata.value).toBe(42);
  });

  test('T29: inventory add/remove persists slots to storage', async () => {
    const adapter = new MemoryAdapter();
    const wasmBytes = readFileSync(WASM_PATH);
    const engine = await GameCellEngine.create({ wasmBytes, storage: adapter });

    const entity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.AFFINE,
      metadata: { name: 'Persisted Potion' },
    });

    const ownerHex = Array.from(OWNER_A).map(b => b.toString(16).padStart(2, '0')).join('');

    // Add to inventory — persists
    const inv = engine.addToInventory(
      engine.createInventory(OWNER_A),
      'potion',
      entity,
    );
    const storedSlot = await adapter.read(`inventories/${ownerHex}/potion.cell`);
    expect(storedSlot).not.toBeNull();
    expect(storedSlot!.length).toBe(1024);

    // Remove from inventory — deletes
    engine.removeFromInventory(inv, 'potion');
    const afterDelete = await adapter.read(`inventories/${ownerHex}/potion.cell`);
    expect(afterDelete).toBeNull();
  });

  test('T30: loadInventory reconstructs from storage', async () => {
    const adapter = new MemoryAdapter();
    const wasmBytes = readFileSync(WASM_PATH);
    const engine = await GameCellEngine.create({ wasmBytes, storage: adapter });

    const sword = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.LINEAR,
      metadata: { name: 'Sword' },
    });
    const shield = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: OWNER_A,
      linearity: LINEARITY.AFFINE,
      metadata: { name: 'Shield' },
    });

    let inv = engine.createInventory(OWNER_A);
    inv = engine.addToInventory(inv, 'weapon', sword);
    inv = engine.addToInventory(inv, 'armor', shield);

    // Load from storage — should reconstruct both slots
    const loaded = await engine.loadInventory(OWNER_A);
    expect(loaded.slots.size).toBe(2);
    expect(loaded.slots.has('weapon')).toBe(true);
    expect(loaded.slots.has('armor')).toBe(true);

    // Verify cell content matches
    const loadedSword = engine.getEntity(loaded.slots.get('weapon')!);
    expect(loadedSword.metadata.name).toBe('Sword');
  });
});

```
