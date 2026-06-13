---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/namespace-partition-single-source.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.573475+00:00
---

# tests/gates/namespace-partition-single-source.test.ts

```ts
/**
 * R-1 Gate: the domain-flag namespace partition has ONE definition.
 *
 * Per audit docs/audits/2026-05-16-domain-flag-vs-plexus-derivation.md
 * §4a R-1: `core/protocol-types/src/namespace.ts` is the single source
 * of truth for the 3-tier partition (Plexus reserved / Extended Plexus /
 * Operator sovereignty). `core/plexus-contracts/src/domain-flags.ts`
 * must re-export it, not re-define a divergent boundary.
 *
 * This gate fails if:
 *   - the boundary constants disagree across the two TS modules, or
 *   - the Zig kernel constant disagrees, or
 *   - domain-flags.ts re-introduces a divergent numeric literal for
 *     PLEXUS_RESERVED_MAX (the historical two-tier-collapse defect D-1).
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';

import {
  PLEXUS_RESERVED_MAX as PT_PLEXUS_RESERVED_MAX,
  EXTENDED_PLEXUS_MAX as PT_EXTENDED_PLEXUS_MAX,
  OPERATOR_BASE as PT_OPERATOR_BASE,
} from '../../core/protocol-types/src/namespace';
import {
  PLEXUS_RESERVED_MAX as PC_PLEXUS_RESERVED_MAX,
  EXTENDED_PLEXUS_MAX as PC_EXTENDED_PLEXUS_MAX,
  OPERATOR_BASE as PC_OPERATOR_BASE,
  CLIENT_BASE as PC_CLIENT_BASE,
} from '../../core/plexus-contracts/src/domain-flags';

const ROOT = join(import.meta.dir, '../..');

describe('R-1 — namespace partition single source of truth', () => {
  test('canonical 3-tier boundary values', () => {
    expect(PT_PLEXUS_RESERVED_MAX).toBe(0x000000ff);
    expect(PT_EXTENDED_PLEXUS_MAX).toBe(0x0000ffff);
    expect(PT_OPERATOR_BASE).toBe(0x00010000);
  });

  test('plexus-contracts re-exports the SAME values (no divergence)', () => {
    expect(PC_PLEXUS_RESERVED_MAX).toBe(PT_PLEXUS_RESERVED_MAX);
    expect(PC_EXTENDED_PLEXUS_MAX).toBe(PT_EXTENDED_PLEXUS_MAX);
    expect(PC_OPERATOR_BASE).toBe(PT_OPERATOR_BASE);
  });

  test('CLIENT_BASE is the value-identical deprecated alias of OPERATOR_BASE', () => {
    expect(PC_CLIENT_BASE).toBe(PT_OPERATOR_BASE);
  });

  test('Zig kernel constant matches Tier-1 max (0xFF)', () => {
    const zig = readFileSync(
      join(ROOT, 'core/cell-engine/src/constants.zig'),
      'utf-8',
    );
    expect(zig).toContain('pub const DOMAIN_FLAG_PLEXUS_RESERVED_MAX: u32 = 255;');
  });

  test('domain-flags.ts does NOT re-introduce the two-tier-collapse literal', () => {
    const src = readFileSync(
      join(ROOT, 'core/plexus-contracts/src/domain-flags.ts'),
      'utf-8',
    );
    // The defect was `export const PLEXUS_RESERVED_MAX = 0x0000ffff`.
    // It must now be re-exported, never locally re-defined.
    expect(src).not.toMatch(/export\s+const\s+PLEXUS_RESERVED_MAX\s*=/);
    expect(src).toContain("from '@semantos/protocol-types'");
  });
});

```
