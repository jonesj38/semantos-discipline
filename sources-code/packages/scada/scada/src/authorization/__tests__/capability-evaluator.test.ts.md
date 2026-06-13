---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/__tests__/capability-evaluator.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.475560+00:00
---

# packages/scada/scada/src/authorization/__tests__/capability-evaluator.test.ts

```ts
/**
 * Unit tests — capability-evaluator (pure module).
 */

import { describe, expect, test } from 'bun:test';

import type { SCADACapabilityToken } from '../../types';
import {
  evaluateCapability,
  getRequiredCapabilityForCommand,
  tokenHasCapability,
} from '../capability-evaluator';

function makeToken(overrides: Partial<SCADACapabilityToken> = {}): SCADACapabilityToken {
  return {
    tokenId: 'tkn-1',
    operatorId: 'op-1',
    role: 'senior-operator',
    capabilities: [1, 2, 3, 4],
    shiftStart: '2030-01-01T00:00:00.000Z',
    shiftEnd: '2030-12-31T23:59:59.000Z',
    grantedBy: 'plant-manager-1',
    consumed: false,
    cellBytes: new Uint8Array(32),
    ...overrides,
  };
}

describe('getRequiredCapabilityForCommand', () => {
  test('valve commands need cap 3', () => {
    expect(getRequiredCapabilityForCommand('valve.open')).toBe(3);
    expect(getRequiredCapabilityForCommand('valve.close')).toBe(3);
    expect(getRequiredCapabilityForCommand('valve.set-position')).toBe(3);
  });
  test('motor commands need cap 4', () => {
    expect(getRequiredCapabilityForCommand('motor.start')).toBe(4);
    expect(getRequiredCapabilityForCommand('motor.set-speed')).toBe(4);
  });
  test('alarm acknowledgement needs cap 2', () => {
    expect(getRequiredCapabilityForCommand('alarm.acknowledge')).toBe(2);
    expect(getRequiredCapabilityForCommand('alarm.silence')).toBe(2);
  });
  test('mode change needs cap 6, emergency shutdown cap 8', () => {
    expect(getRequiredCapabilityForCommand('mode.change')).toBe(6);
    expect(getRequiredCapabilityForCommand('emergency.shutdown')).toBe(8);
  });
});

describe('evaluateCapability', () => {
  const NOW = Date.parse('2030-06-01T00:00:00Z');

  test('passes for token with required capability', () => {
    const token = makeToken();
    const decision = evaluateCapability(token, 'valve.open', NOW);
    expect(decision.ok).toBe(true);
    if (decision.ok) expect(decision.required).toBe(3);
  });

  test('rejects consumed token', () => {
    const token = makeToken({ consumed: true });
    const decision = evaluateCapability(token, 'valve.open', NOW);
    expect(decision.ok).toBe(false);
    if (!decision.ok) expect(decision.reason).toBe('CONSUMED_CAPABILITY');
  });

  test('rejects token consumed in external set', () => {
    const token = makeToken();
    const consumed = new Set([token.tokenId]);
    const decision = evaluateCapability(token, 'valve.open', NOW, consumed);
    expect(decision.ok).toBe(false);
    if (!decision.ok) expect(decision.reason).toBe('CONSUMED_CAPABILITY');
  });

  test('rejects expired token', () => {
    const token = makeToken({ shiftEnd: '2025-01-01T00:00:00.000Z' });
    const decision = evaluateCapability(token, 'valve.open', NOW);
    expect(decision.ok).toBe(false);
    if (!decision.ok) expect(decision.reason).toBe('EXPIRED_CAPABILITY');
  });

  test('rejects insufficient role', () => {
    const token = makeToken({ capabilities: [1, 2] });
    const decision = evaluateCapability(token, 'emergency.shutdown', NOW);
    expect(decision.ok).toBe(false);
    if (!decision.ok) expect(decision.reason).toBe('INSUFFICIENT_ROLE');
  });
});

describe('tokenHasCapability', () => {
  test('true when capability number listed', () => {
    expect(tokenHasCapability(makeToken({ capabilities: [5] }), 5)).toBe(true);
  });
  test('false when capability number absent', () => {
    expect(tokenHasCapability(makeToken({ capabilities: [1, 2] }), 5)).toBe(false);
  });
});

```
