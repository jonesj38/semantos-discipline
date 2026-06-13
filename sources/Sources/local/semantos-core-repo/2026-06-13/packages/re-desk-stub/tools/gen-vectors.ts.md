---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/tools/gen-vectors.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.535771+00:00
---

# packages/re-desk-stub/tools/gen-vectors.ts

```ts
/**
 * D-O11 phase O11a — generate conformance vectors for the
 * `re-desk.maintenance-request.v1` cell type.
 *
 * Mirrors `extensions/oddjobz/tools/gen-vectors.ts` in shape: writes
 * `tests/vectors/re-desk_maintenance-request.json` with deterministic
 * pack bytes for a small but covering set of MaintenanceRequest
 * shapes. The conformance vector is what downstream consumers
 * (dispatch handler, smoke test) load to assert byte-stability across
 * commits.
 */

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import {
  maintenanceRequestCellType,
  type MaintenanceRequest,
} from '../src/cell-types/index.js';

interface Vector {
  readonly name: string;
  readonly input: MaintenanceRequest;
  readonly packed: string;
  readonly typeHash: string;
  readonly linearity: 'LINEAR';
}

function toHex(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) {
    s += (bytes[i] as number).toString(16).padStart(2, '0');
  }
  return s;
}

const VECTORS: ReadonlyArray<{ name: string; cell: MaintenanceRequest }> = [
  {
    name: 'draft — fresh maintenance request, urgent HVAC failure',
    cell: {
      requestId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      customer: 'Tenant 4B, 12 Smith St, Sydney NSW 2000',
      description: 'HVAC unit in office failed; tenant reports 31°C ambient',
      dispatchTo: 'oddjobtodd.info#tradie-todd',
      state: 'draft',
      urgency: 'urgent',
      createdAt: '2026-05-01T09:00:00.000Z',
      updatedAt: '2026-05-01T09:00:00.000Z',
    },
  },
  {
    name: 'dispatched — envelope minted, waiting for tradie acceptance',
    cell: {
      requestId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      customer: 'Tenant 4B, 12 Smith St, Sydney NSW 2000',
      description: 'HVAC unit in office failed; tenant reports 31°C ambient',
      dispatchTo: 'oddjobtodd.info#tradie-todd',
      state: 'dispatched',
      urgency: 'urgent',
      envelopeId: 'env-aaaa-bbbb-cccc-dddd',
      createdAt: '2026-05-01T09:00:00.000Z',
      dispatchedAt: '2026-05-01T09:05:00.000Z',
      updatedAt: '2026-05-01T09:05:00.000Z',
    },
  },
  {
    name: 'invoiced — completion patch flowed back, ready for owner billing',
    cell: {
      requestId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      customer: 'Tenant 4B, 12 Smith St, Sydney NSW 2000',
      description: 'HVAC unit in office failed; tenant reports 31°C ambient',
      dispatchTo: 'oddjobtodd.info#tradie-todd',
      state: 'invoiced',
      urgency: 'urgent',
      envelopeId: 'env-aaaa-bbbb-cccc-dddd',
      createdAt: '2026-05-01T09:00:00.000Z',
      dispatchedAt: '2026-05-01T09:05:00.000Z',
      acceptedAt: '2026-05-01T09:08:00.000Z',
      completedAt: '2026-05-01T11:30:00.000Z',
      invoicedAt: '2026-05-01T11:35:00.000Z',
      updatedAt: '2026-05-01T11:35:00.000Z',
    },
  },
  {
    name: 'cancelled — operator withdrew the dispatch (e.g. tenant resolved)',
    cell: {
      requestId: 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff',
      customer: 'Strata 12, 5 Wattle Cres, Melbourne',
      description: 'Roof leak — tenant fixed it themselves',
      dispatchTo: 'oddjobtodd.info#tradie-todd',
      state: 'cancelled',
      urgency: 'flexible',
      envelopeId: 'env-bbbb-cccc-dddd-eeee',
      createdAt: '2026-05-02T08:00:00.000Z',
      dispatchedAt: '2026-05-02T08:15:00.000Z',
      updatedAt: '2026-05-02T08:30:00.000Z',
    },
  },
];

const out: Vector[] = VECTORS.map(({ name, cell }) => ({
  name,
  input: cell,
  packed: toHex(maintenanceRequestCellType.pack(cell)),
  typeHash: maintenanceRequestCellType.typeHashHex,
  linearity: 'LINEAR',
}));

const outPath = resolve(
  import.meta.dir,
  '..',
  'tests',
  'vectors',
  're-desk_maintenance-request.json',
);
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(out, null, 2) + '\n');
console.log(`wrote ${out.length} vectors → ${outPath}`);

```
