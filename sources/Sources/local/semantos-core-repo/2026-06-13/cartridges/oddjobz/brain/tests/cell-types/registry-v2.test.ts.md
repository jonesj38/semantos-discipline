---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/cell-types/registry-v2.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.483618+00:00
---

# cartridges/oddjobz/brain/tests/cell-types/registry-v2.test.ts

```ts
/**
 * Cell-types registry coexistence test.
 *
 * Post-CC5.B2b (2026-05-20, PR will follow): the v2 TS hand-mirrors for
 * job/customer/site were retired; their canonical schema now lives
 * declaratively in `cartridges/oddjobz/cartridge.json` `objectTypes` per
 * CC5.B2a (#478). The v2 *cell-type registry* on the TS side is therefore
 * trimmed to a single entry: `oddjobz.attachment.v2` (which stays;
 * attachment was out of CC5.B2's deletion scope).
 *
 * This test asserts the registry still resolves v1 + the remaining v2,
 * and the PRD-mandated `ATTACHMENT_TYPE` default still aliases the v2
 * variant. The `JOB_TYPE` / `CUSTOMER_TYPE` / `SITE_TYPE` aliases now
 * point back at v1 (their v2 variants no longer exist as TS cell-types).
 */

import { describe, expect, test } from 'bun:test';
import {
  ODDJOBZ_CELL_TYPES,
  ODDJOBZ_CELL_TYPES_V2,
  ODDJOBZ_CELL_TYPES_ALL,
  cellTypeByName,
  cellTypeByHashHex,
  jobCellType,
  customerCellType,
  siteCellType,
  attachmentCellType,
  attachmentCellTypeV2,
  JOB_TYPE,
  JOB_TYPE_V1,
  CUSTOMER_TYPE,
  CUSTOMER_TYPE_V1,
  SITE_TYPE,
  SITE_TYPE_V1,
  ATTACHMENT_TYPE,
  ATTACHMENT_TYPE_V1,
  ATTACHMENT_TYPE_V2,
} from '../../src/cell-types/index.js';

describe('cell-types registry — v1 + attachment-v2 coexistence (post-CC5.B2b)', () => {
  test('ODDJOBZ_CELL_TYPES (v1) is unchanged at length 10', () => {
    expect(ODDJOBZ_CELL_TYPES).toHaveLength(10);
  });

  test('ODDJOBZ_CELL_TYPES_V2 contains exactly attachment.v2 (job/customer/site v2 retired by CC5.B2b)', () => {
    expect(ODDJOBZ_CELL_TYPES_V2).toHaveLength(1);
    expect(ODDJOBZ_CELL_TYPES_V2.map((t) => t.name)).toEqual([
      'oddjobz.attachment.v2',
    ]);
  });

  test('ODDJOBZ_CELL_TYPES_ALL is the union of v1, attachment-v2, and config (12)', () => {
    // 10 v1 entities + 1 v2 (attachment) + 1 config (pricing_policy) = 12.
    expect(ODDJOBZ_CELL_TYPES_ALL).toHaveLength(12);
  });

  test('cellTypeByName resolves v1 for all 10 + v2 for attachment only', () => {
    const v1Pairs = [
      ['oddjobz.job.v1', jobCellType],
      ['oddjobz.customer.v1', customerCellType],
      ['oddjobz.site.v1', siteCellType],
      ['oddjobz.attachment.v1', attachmentCellType],
    ] as const;
    for (const [n, t] of v1Pairs) {
      expect(cellTypeByName[n]).toBe(t);
    }
    expect(cellTypeByName['oddjobz.attachment.v2']).toBe(attachmentCellTypeV2);
    // The three retired v2 names MUST NOT resolve post-B2b:
    expect(cellTypeByName['oddjobz.job.v2']).toBeUndefined();
    expect(cellTypeByName['oddjobz.customer.v2']).toBeUndefined();
    expect(cellTypeByName['oddjobz.site.v2']).toBeUndefined();
  });

  test('cellTypeByHashHex resolves every registered cell type', () => {
    for (const t of ODDJOBZ_CELL_TYPES_ALL) {
      expect(cellTypeByHashHex[t.typeHashHex]).toBe(t);
    }
  });

  test('all 12 type hashes are pairwise distinct', () => {
    const seen = new Set<string>();
    for (const t of ODDJOBZ_CELL_TYPES_ALL) {
      expect(seen.has(t.typeHashHex)).toBe(false);
      seen.add(t.typeHashHex);
    }
    expect(seen.size).toBe(12);
  });

  test('aliases — V1 explicit + attachment V2 explicit', () => {
    expect(JOB_TYPE_V1).toBe(jobCellType);
    expect(CUSTOMER_TYPE_V1).toBe(customerCellType);
    expect(SITE_TYPE_V1).toBe(siteCellType);
    expect(ATTACHMENT_TYPE_V1).toBe(attachmentCellType);
    expect(ATTACHMENT_TYPE_V2).toBe(attachmentCellTypeV2);
  });

  test('default JOB/CUSTOMER/SITE_TYPE point at v1 (their v2 was retired); ATTACHMENT_TYPE keeps v2', () => {
    expect(JOB_TYPE).toBe(JOB_TYPE_V1);
    expect(CUSTOMER_TYPE).toBe(CUSTOMER_TYPE_V1);
    expect(SITE_TYPE).toBe(SITE_TYPE_V1);
    expect(ATTACHMENT_TYPE).toBe(ATTACHMENT_TYPE_V2);
  });
});

```
