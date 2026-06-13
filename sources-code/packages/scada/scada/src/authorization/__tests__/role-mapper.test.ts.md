---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/__tests__/role-mapper.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.475860+00:00
---

# packages/scada/scada/src/authorization/__tests__/role-mapper.test.ts

```ts
/**
 * Unit tests — role-mapper (pure).
 */

import { describe, expect, test } from 'bun:test';

import {
  capabilitiesForRole,
  isSupervisorRole,
  ROLE_CAPABILITIES,
} from '../role-mapper';

describe('capabilitiesForRole', () => {
  test('junior-operator has caps [1,2]', () => {
    expect([...capabilitiesForRole('junior-operator')]).toEqual([1, 2]);
  });
  test('safety-officer has all 10 caps', () => {
    expect([...capabilitiesForRole('safety-officer')]).toEqual([
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    ]);
  });
  test('matches the ROLE_CAPABILITIES table verbatim', () => {
    for (const role of Object.keys(ROLE_CAPABILITIES) as Array<keyof typeof ROLE_CAPABILITIES>) {
      expect(capabilitiesForRole(role)).toBe(ROLE_CAPABILITIES[role]);
    }
  });
});

describe('isSupervisorRole', () => {
  test('true for supervisory roles', () => {
    expect(isSupervisorRole('shift-supervisor')).toBe(true);
    expect(isSupervisorRole('plant-manager')).toBe(true);
    expect(isSupervisorRole('safety-officer')).toBe(true);
  });
  test('false for non-supervisory roles', () => {
    expect(isSupervisorRole('junior-operator')).toBe(false);
    expect(isSupervisorRole('senior-operator')).toBe(false);
  });
});

```
