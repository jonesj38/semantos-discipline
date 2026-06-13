---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase-consumer-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.565524+00:00
---

# tests/gates/phase-consumer-gate.test.ts

```ts
/**
 * Phase Consumer Gate Tests — Consumer UI Layer & Spinning Cards
 *
 * T1–T3:  Consciousness extension config validation
 * T4–T6:  Governance constraint engine (L0/L1)
 * T7–T8:  Version compatibility
 * T9–T12: Kernel bridge integration (LoomStore, FlowRunner, MemoryAdapter)
 * T13–T15: ConsumerBinding object lifecycle
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

const ROOT = join(import.meta.dir, '../..');

// ── T1–T3: Extension Config Validation ──────────────────────────

describe('D-Consumer.1 — Consciousness Extension Config', () => {
  test('T1: configs/extensions/consciousness.json passes validateExtensionConfig()', async () => {
    const { validateExtensionConfig } = await import(
      '../../runtime/services/src/config/extensionConfig'
    );
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    expect(existsSync(configPath)).toBe(true);

    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));
    const config = validateExtensionConfig(raw);

    expect(config.id).toBe('consciousness-process');
    expect(config.objectTypes.length).toBeGreaterThanOrEqual(12);
    expect(config.flows!.length).toBeGreaterThanOrEqual(12);
  });

  test('T2: all object types have valid 64-char hex typeHashes', async () => {
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));

    for (const ot of raw.objectTypes) {
      expect(ot.typeHash).toBeDefined();
      expect(typeof ot.typeHash).toBe('string');
      expect(ot.typeHash.length).toBe(64);
      expect(ot.typeHash).toMatch(/^[0-9a-f]{64}$/);
    }
  });

  test('T3: ConsumerBinding type exists in navigator config with correct fields', async () => {
    const configPath = join(ROOT, 'configs/packages/navigator.json');
    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));

    const binding = raw.objectTypes.find(
      (t: { name: string }) => t.name === 'ConsumerBinding',
    );
    expect(binding).toBeDefined();
    expect(binding.linearity).toBe('AFFINE');
    expect(binding.archetype).toBe('instrument');

    const fieldNames = binding.fields.map((f: { name: string }) => f.name);
    expect(fieldNames).toContain('consumerId');
    expect(fieldNames).toContain('extensionManifestId');
    expect(fieldNames).toContain('versionPin');
    expect(fieldNames).toContain('autoUpdate');
  });
});

// ── T4–T6: Governance Constraint Engine ─────────────────────────

describe('D-Consumer.2 — Governance Constraint Engine', () => {
  test('T4: enforceL0Constraints rejects object with out-of-range numeric field', async () => {
    const { enforceL0Constraints } = await import(
      '../../packages/extraction/src/governance/constraint-engine'
    );
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    const config = JSON.parse(readFileSync(configPath, 'utf-8'));

    const result = enforceL0Constraints(
      {
        type: 'Release',
        fields: { elevation: 99 }, // max is 6
      },
      config,
    );

    expect(result.valid).toBe(false);
    expect(result.violations.length).toBeGreaterThan(0);
    expect(result.violations[0]).toContain('elevation');
    expect(result.violations[0]).toContain('maximum');
  });

  test('T5: enforceL0Constraints accepts valid object matching type definition', async () => {
    const { enforceL0Constraints } = await import(
      '../../packages/extraction/src/governance/constraint-engine'
    );
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    const config = JSON.parse(readFileSync(configPath, 'utf-8'));

    const result = enforceL0Constraints(
      {
        type: 'Release',
        fields: {
          source: 'voice',
          rawText: 'I release all that no longer serves me',
          elevation: 3,
          valence: 0.5,
        },
      },
      config,
    );

    expect(result.valid).toBe(true);
    expect(result.violations).toHaveLength(0);
  });

  test('T6: enforceL1Constraints rejects mutation without required capability', async () => {
    const { enforceL1Constraints } = await import(
      '../../packages/extraction/src/governance/constraint-engine'
    );
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    const config = JSON.parse(readFileSync(configPath, 'utf-8'));

    const result = enforceL1Constraints(
      {
        type: 'Release',
        fields: { rawText: 'test' },
      },
      config,
      { capabilities: [] }, // Missing SELF_INQUIRY (cap 1)
    );

    expect(result.valid).toBe(false);
    expect(result.violations.length).toBeGreaterThan(0);
    expect(result.violations[0]).toContain('SELF_INQUIRY');
  });
});

// ── T7–T8: Version Compatibility ────────────────────────────────

describe('D-Consumer.3 — Version Compatibility', () => {
  test('T7: checkCompatibility returns compatible for matching version', async () => {
    const { checkCompatibility } = await import(
      '../../packages/extraction/src/governance/version-compat'
    );

    const result = checkCompatibility('0.3.0', '>=0.3.0');
    expect(result.compatible).toBe(true);
    expect(result.status).toBe('green');
  });

  test('T8: checkCompatibility returns incompatible for too-old version', async () => {
    const { checkCompatibility } = await import(
      '../../packages/extraction/src/governance/version-compat'
    );

    const result = checkCompatibility('0.2.0', '>=0.3.0');
    expect(result.compatible).toBe(false);
    expect(result.status).toBe('red');
  });
});

// ── T9–T12: Kernel Bridge Integration ───────────────────────────

describe('D-Consumer.4 — Kernel Bridge Integration', () => {
  test('T9: LoomStore creates object from navigation config type definition', async () => {
    const { LoomStore } = await import(
      '../../runtime/services/src/services/LoomStore'
    );
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    const config = JSON.parse(readFileSync(configPath, 'utf-8'));

    const store = new LoomStore();
    const releaseDef = config.objectTypes.find(
      (t: { name: string }) => t.name === 'Release',
    );
    expect(releaseDef).toBeDefined();

    const objectId = store.createObjectFromType(releaseDef);
    expect(typeof objectId).toBe('string');
    expect(objectId.length).toBeGreaterThan(0);

    const obj = store.getState().objects.get(objectId);
    expect(obj).toBeDefined();
    expect(obj!.typeDefinition.name).toBe('Release');
  });

  test('T10: FlowRunner starts and advances a navigation flow', async () => {
    const { FlowRunner } = await import(
      '../../runtime/services/src/services/FlowRunner'
    );
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    const config = JSON.parse(readFileSync(configPath, 'utf-8'));

    const runner = new FlowRunner();
    const releaseFlow = config.flows.find(
      (f: { id: string }) => f.id === 'daily-release',
    );
    expect(releaseFlow).toBeDefined();

    const step1 = runner.startFlow(releaseFlow);
    expect(step1).toBeDefined();
    expect(step1.id).toBe('source');
    expect(runner.isActive()).toBe(true);

    const step2 = runner.advanceFlow('keyboard');
    expect(step2).toBeDefined();
    expect(step2!.id).toBe('prompt-choice');
  });

  test('T11: object created via store is retrievable', async () => {
    const { LoomStore } = await import(
      '../../runtime/services/src/services/LoomStore'
    );
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    const config = JSON.parse(readFileSync(configPath, 'utf-8'));

    const store = new LoomStore();
    const insightDef = config.objectTypes.find(
      (t: { name: string }) => t.name === 'Insight',
    );
    const objectId = store.createObjectFromType(insightDef);

    const state = store.getState();
    expect(state.objects.has(objectId)).toBe(true);

    const obj = state.objects.get(objectId)!;
    expect(obj.typeDefinition.name).toBe('Insight');
    expect(obj.typeDefinition.linearity).toBe('RELEVANT');
  });

  test('T12: MemoryAdapter round-trips cell data', async () => {
    const { MemoryAdapter } = await import(
      '../../core/protocol-types/src/adapters/memory-adapter'
    );

    const adapter = new MemoryAdapter();
    const key = 'objects/navigation/release/test-001/payload';
    const data = new TextEncoder().encode('{"rawText":"hello world"}');

    await adapter.write(key, data);
    const readBack = await adapter.read(key);
    expect(readBack).not.toBeNull();
    expect(new TextDecoder().decode(readBack!)).toBe('{"rawText":"hello world"}');

    const stat = await adapter.stat(key);
    expect(stat).not.toBeNull();
    expect(stat!.size).toBe(data.byteLength);
  });
});

// ── T13–T15: ConsumerBinding Lifecycle ──────────────────────────

describe('D-Consumer.5 — ConsumerBinding', () => {
  test('T13: ConsumerBinding created via store links to extension', async () => {
    const { LoomStore } = await import(
      '../../runtime/services/src/services/LoomStore'
    );
    const navConfigPath = join(ROOT, 'configs/packages/navigator.json');
    const navConfig = JSON.parse(readFileSync(navConfigPath, 'utf-8'));

    const store = new LoomStore();
    const bindingDef = navConfig.objectTypes.find(
      (t: { name: string }) => t.name === 'ConsumerBinding',
    );
    expect(bindingDef).toBeDefined();

    const objectId = store.createObjectFromType(bindingDef);
    const obj = store.getState().objects.get(objectId);
    expect(obj).toBeDefined();
    expect(obj!.typeDefinition.name).toBe('ConsumerBinding');
  });

  test('T14: ConsumerBinding list filtered by type returns correct subset', async () => {
    const { LoomStore } = await import(
      '../../runtime/services/src/services/LoomStore'
    );
    const navConfigPath = join(ROOT, 'configs/packages/navigator.json');
    const navConfig = JSON.parse(readFileSync(navConfigPath, 'utf-8'));
    const conConfigPath = join(ROOT, 'configs/extensions/consciousness.json');
    const conConfig = JSON.parse(readFileSync(conConfigPath, 'utf-8'));

    const store = new LoomStore();
    const bindingDef = navConfig.objectTypes.find(
      (t: { name: string }) => t.name === 'ConsumerBinding',
    );
    const releaseDef = conConfig.objectTypes.find(
      (t: { name: string }) => t.name === 'Release',
    );

    store.createObjectFromType(bindingDef);
    store.createObjectFromType(bindingDef);
    store.createObjectFromType(releaseDef);

    const allObjects = Array.from(store.getState().objects.values());
    const bindings = allObjects.filter(o => o.typeDefinition.name === 'ConsumerBinding');
    const releases = allObjects.filter(o => o.typeDefinition.name === 'Release');

    expect(bindings).toHaveLength(2);
    expect(releases).toHaveLength(1);
  });

  test('T15: ConsumerBinding AFFINE linearity allows read after creation', async () => {
    const { LoomStore } = await import(
      '../../runtime/services/src/services/LoomStore'
    );
    const navConfigPath = join(ROOT, 'configs/packages/navigator.json');
    const navConfig = JSON.parse(readFileSync(navConfigPath, 'utf-8'));

    const store = new LoomStore();
    const bindingDef = navConfig.objectTypes.find(
      (t: { name: string }) => t.name === 'ConsumerBinding',
    );
    const objectId = store.createObjectFromType(bindingDef);

    const obj = store.getState().objects.get(objectId);
    expect(obj).toBeDefined();
    expect(obj!.typeDefinition.linearity).toBe('AFFINE');

    // AFFINE objects can be read multiple times (not consumed on read)
    const obj2 = store.getState().objects.get(objectId);
    expect(obj2).toBeDefined();
    expect(obj2!.typeDefinition.name).toBe('ConsumerBinding');
  });
});

```
