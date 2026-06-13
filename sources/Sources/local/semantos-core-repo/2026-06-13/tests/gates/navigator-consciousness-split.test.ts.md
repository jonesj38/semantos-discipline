---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/navigator-consciousness-split.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.576378+00:00
---

# tests/gates/navigator-consciousness-split.test.ts

```ts
/**
 * Navigator / Consciousness Split Tests
 *
 * Validates the refactor from monolithic navigation.json into:
 *   - navigator.json (core layer: ConsumerBinding + lens infrastructure)
 *   - consciousness.json (extension: 14 domain types + 12 flows)
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

const ROOT = join(import.meta.dir, '../..');

// ── Navigator Core Config ──────────────────────────────────────────

describe('Navigator Core Config', () => {
  test('configs/packages/navigator.json passes validateExtensionConfig()', async () => {
    const { validateExtensionConfig } = await import(
      '../../runtime/services/src/config/extensionConfig'
    );
    const configPath = join(ROOT, 'configs/packages/navigator.json');
    expect(existsSync(configPath)).toBe(true);

    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));
    const config = validateExtensionConfig(raw);

    expect(config.id).toBe('navigator-core');
    expect(config.objectTypes.length).toBe(1);
  });

  test('navigator has ConsumerBinding only', () => {
    const configPath = join(ROOT, 'configs/packages/navigator.json');
    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));
    const typeNames = raw.objectTypes.map((t: { name: string }) => t.name);

    expect(typeNames).toContain('ConsumerBinding');
    expect(typeNames).toHaveLength(1);
  });

  test('navigator has no flows (infrastructure only)', () => {
    const configPath = join(ROOT, 'configs/packages/navigator.json');
    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));
    expect(raw.flows).toBeUndefined();
  });

  test('all navigator type hashes are valid 64-char hex', () => {
    const configPath = join(ROOT, 'configs/packages/navigator.json');
    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));
    for (const ot of raw.objectTypes) {
      expect(ot.typeHash).toMatch(/^[0-9a-f]{64}$/);
    }
  });
});

// ── Consciousness Extension Config ─────────────────────────────────

describe('Consciousness Extension Config', () => {
  test('configs/extensions/consciousness.json passes validateExtensionConfig()', async () => {
    const { validateExtensionConfig } = await import(
      '../../runtime/services/src/config/extensionConfig'
    );
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    expect(existsSync(configPath)).toBe(true);

    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));
    const config = validateExtensionConfig(raw);

    expect(config.id).toBe('consciousness-process');
    expect(config.objectTypes.length).toBe(14);
    expect(config.flows!.length).toBeGreaterThanOrEqual(12);
  });

  test('consciousness has all 14 domain types', () => {
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));
    const typeNames = raw.objectTypes.map((t: { name: string }) => t.name);

    const expectedTypes = [
      'Release', 'Session', 'Intention', 'Insight', 'Pattern',
      'Connection', 'VacuumSession', 'GoldSeal',
      'DailyReview', 'MorningIntention', 'DimensionPulse', 'AccountabilityStreak',
      'DimensionState', 'ElevationState',
    ];

    for (const name of expectedTypes) {
      expect(typeNames).toContain(name);
    }
  });

  test('all consciousness type hashes are valid 64-char hex', () => {
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));
    for (const ot of raw.objectTypes) {
      expect(ot.typeHash).toMatch(/^[0-9a-f]{64}$/);
    }
  });

  test('consciousness references consciousness taxonomy', () => {
    const configPath = join(ROOT, 'configs/extensions/consciousness.json');
    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));
    expect(raw.taxonomyPath).toBe('configs/taxonomy/consciousness.json');
  });

  test('DimensionState and ElevationState are in consciousness, not navigator', () => {
    const navPath = join(ROOT, 'configs/packages/navigator.json');
    const conPath = join(ROOT, 'configs/extensions/consciousness.json');

    const navTypes = JSON.parse(readFileSync(navPath, 'utf-8'))
      .objectTypes.map((t: { name: string }) => t.name);
    const conTypes = JSON.parse(readFileSync(conPath, 'utf-8'))
      .objectTypes.map((t: { name: string }) => t.name);

    expect(navTypes).not.toContain('DimensionState');
    expect(navTypes).not.toContain('ElevationState');
    expect(conTypes).toContain('DimensionState');
    expect(conTypes).toContain('ElevationState');
  });
});

// ── No Overlap ─────────────────────────────────────────────────────

describe('Navigator / Consciousness Type Separation', () => {
  test('no type name overlap between navigator and consciousness', () => {
    const navPath = join(ROOT, 'configs/packages/navigator.json');
    const conPath = join(ROOT, 'configs/extensions/consciousness.json');

    const navTypes = JSON.parse(readFileSync(navPath, 'utf-8'))
      .objectTypes.map((t: { name: string }) => t.name);
    const conTypes = JSON.parse(readFileSync(conPath, 'utf-8'))
      .objectTypes.map((t: { name: string }) => t.name);

    const overlap = navTypes.filter((n: string) => conTypes.includes(n));
    expect(overlap).toHaveLength(0);
  });

  test('old navigation.json is marked deprecated', () => {
    const configPath = join(ROOT, 'configs/extensions/navigation.json');
    const raw = JSON.parse(readFileSync(configPath, 'utf-8'));
    expect(raw.deprecated).toBe(true);
    expect(raw.supersededBy).toContain('navigator-core');
    expect(raw.supersededBy).toContain('consciousness-process');
  });
});

```
