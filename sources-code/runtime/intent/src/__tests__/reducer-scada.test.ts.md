---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/reducer-scada.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.356457+00:00
---

# runtime/intent/src/__tests__/reducer-scada.test.ts

```ts
/**
 * I-12 — Integration test: SCADA vertical intent reducer.
 *
 * RED commits — fail until I-2..I-9 are implemented.
 * Proves lexicon polymorphism: same reduceToIntent function,
 * ControlSystemsLexicon grammar, different category set.
 *
 * See docs/prd/INTENT-REDUCER-GRAMMAR-AUTOMATION-PLAN.md (I-12)
 */

import { describe, expect, test } from 'bun:test';
import { reduceToIntent } from '../reducer/index';
import {
  SCADA_FIXTURES,
  S1_READ_MEASUREMENT,
  S2_WRITE_SETPOINT,
  S3_ENGAGE_INTERLOCK,
  S4_ACKNOWLEDGE_ALARM,
  S5_OPEN_VALVE,
} from '../reducer/__fixtures__/scada-fixtures';

describe('SCADA vertical intent reducer', () => {
  describe('S-1: read_measurement — sensor telemetry', () => {
    test('produces action: read_measurement', async () => {
      const { intent } = await reduceToIntent(S1_READ_MEASUREMENT.input, S1_READ_MEASUREMENT.grammar);
      expect(intent.action).toBe('read_measurement');
    });

    test('produces control-systems measurement category', async () => {
      const { intent } = await reduceToIntent(S1_READ_MEASUREMENT.input, S1_READ_MEASUREMENT.grammar);
      expect(intent.category).toMatchObject({ lexicon: 'control-systems', category: 'measurement' });
    });

    test('taxonomy.what resolves to scada.equipment', async () => {
      const { intent } = await reduceToIntent(S1_READ_MEASUREMENT.input, S1_READ_MEASUREMENT.grammar);
      expect(intent.taxonomy.what).toBe('scada.equipment');
    });

    test('domainFlag 11 propagates (SCADA domain, distinct from trades)', async () => {
      const result = await reduceToIntent(S1_READ_MEASUREMENT.input, S1_READ_MEASUREMENT.grammar);
      const domainConstraints = result.intent.constraints.filter(c => c.kind === 'domain');
      expect(domainConstraints.length).toBeGreaterThan(0);
    });
  });

  describe('S-2: write_setpoint — authoritative trust tier', () => {
    test('produces action: write_setpoint', async () => {
      const { intent } = await reduceToIntent(S2_WRITE_SETPOINT.input, S2_WRITE_SETPOINT.grammar);
      expect(intent.action).toBe('write_setpoint');
    });

    test('produces control-systems setpoint category', async () => {
      const { intent } = await reduceToIntent(S2_WRITE_SETPOINT.input, S2_WRITE_SETPOINT.grammar);
      expect(intent.category).toMatchObject({ lexicon: 'control-systems', category: 'setpoint' });
    });

    test('value constraint present for setpoint change', async () => {
      const { intent } = await reduceToIntent(S2_WRITE_SETPOINT.input, S2_WRITE_SETPOINT.grammar);
      const valueConstraints = intent.constraints.filter(c => c.kind === 'value');
      expect(valueConstraints.length).toBeGreaterThan(0);
    });
  });

  describe('S-3: engage_interlock — safety-critical interlock constraint', () => {
    test('produces action: engage_interlock', async () => {
      const { intent } = await reduceToIntent(S3_ENGAGE_INTERLOCK.input, S3_ENGAGE_INTERLOCK.grammar);
      expect(intent.action).toBe('engage_interlock');
    });

    test('interlock constraint present', async () => {
      const { intent } = await reduceToIntent(S3_ENGAGE_INTERLOCK.input, S3_ENGAGE_INTERLOCK.grammar);
      const interlockConstraints = intent.constraints.filter(c => c.kind === 'interlock');
      expect(interlockConstraints.length).toBeGreaterThan(0);
    });
  });

  describe('S-4: acknowledge_alarm — temporal constraint for ack timestamp', () => {
    test('produces action: acknowledge_alarm', async () => {
      const { intent } = await reduceToIntent(S4_ACKNOWLEDGE_ALARM.input, S4_ACKNOWLEDGE_ALARM.grammar);
      expect(intent.action).toBe('acknowledge_alarm');
    });

    test('temporal constraint present for 14:32 ack timestamp', async () => {
      const { intent } = await reduceToIntent(S4_ACKNOWLEDGE_ALARM.input, S4_ACKNOWLEDGE_ALARM.grammar);
      const temporalConstraints = intent.constraints.filter(c => c.kind === 'temporal');
      expect(temporalConstraints.length).toBeGreaterThan(0);
    });
  });

  describe('S-5: open_valve — actuation', () => {
    test('produces action: open_valve', async () => {
      const { intent } = await reduceToIntent(S5_OPEN_VALVE.input, S5_OPEN_VALVE.grammar);
      expect(intent.action).toBe('open_valve');
    });

    test('produces control-systems actuation category', async () => {
      const { intent } = await reduceToIntent(S5_OPEN_VALVE.input, S5_OPEN_VALVE.grammar);
      expect(intent.category).toMatchObject({ lexicon: 'control-systems', category: 'actuation' });
    });
  });

  describe('Lexicon isolation', () => {
    test('SCADA intent category is never jural', async () => {
      for (const fixture of SCADA_FIXTURES) {
        const { intent } = await reduceToIntent(fixture.input, fixture.grammar);
        expect(intent.category).not.toMatchObject({ lexicon: 'jural' });
      }
    });

    test('SCADA domainFlag 11 never emits domainFlag 7 (trades domain)', async () => {
      for (const fixture of SCADA_FIXTURES) {
        const result = await reduceToIntent(fixture.input, fixture.grammar);
        const domainConstraints = result.intent.constraints.filter(c => c.kind === 'domain');
        for (const dc of domainConstraints) {
          if ('flag' in dc) expect((dc as { flag: number }).flag).not.toBe(7);
        }
      }
    });
  });
});

```
