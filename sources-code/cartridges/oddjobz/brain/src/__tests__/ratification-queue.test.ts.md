---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/ratification-queue.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.511888+00:00
---

# cartridges/oddjobz/brain/src/__tests__/ratification-queue.test.ts

```ts
/**
 * D-O6b — Deliverable 3 — ratification queue tests.
 *
 * Acceptance:
 *  - enqueue persists a pending entry; list_pending returns it.
 *  - reject marks an entry as rejected (no cells emitted).
 *  - ratify emits Estimate + Lead + Job cells, marks the entry as
 *    ratified, and the cells round-trip through their cell-types.
 *  - ratify with a wrong cap fails with a kernel-gate K3a failure;
 *    the queue entry remains pending (no state mutation on failure).
 *  - file-backed storage survives a re-instantiation (operator
 *    restart) — pending entries are still pending.
 */

import { describe, expect, test, beforeEach } from 'bun:test';
import {
  RatificationQueue,
  makeMemoryStorage,
  makeFileStorage,
  type QueueEntry,
  type RatifyInput,
} from '../ratification-queue.js';
import { capWriteCustomer } from '../capabilities.js';
import type { OddjobzEstimate } from '../cell-types/estimate.js';
import { estimateCellType } from '../cell-types/estimate.js';
import { leadCellType } from '../cell-types/lead.js';
import { jobCellType } from '../cell-types/job.js';
import { mkdtempSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const NOW = '2026-05-01T09:00:00Z';
const RATIFY_TIME = '2026-05-01T09:30:00Z';
const OP_CERT = '20202020202040208020202020202020';
const SESSION = 'session-abc';

const DRAFT_EST: OddjobzEstimate = {
  estimateId: '13131313-1313-4131-8131-131313131313', // placeholder
  jobId: '00000000-0000-4000-8000-000000000000', // placeholder
  estimateType: 'auto_rom',
  effortBand: 'half_day',
  costMin: 250000,
  costMax: 350000,
  materialsNote: 'Replace 12 sqm of rotting deck boards',
  assumptionNotes: 'Joists assumed sound',
  createdAt: NOW,
  updatedAt: NOW,
};

const validCap = { kind: 'structural', domainFlag: capWriteCustomer.domainFlag } as const;
const wrongCap = { kind: 'structural', domainFlag: 0xdeadbeef } as const;

let queue: RatificationQueue;

beforeEach(() => {
  queue = new RatificationQueue(makeMemoryStorage());
});

describe('§O6b — ratification queue — enqueue', () => {
  test('enqueue persists a pending entry', () => {
    const e = queue.enqueue({
      provenance: 'from_chat',
      chatSessionId: SESSION,
      customerHint: 'Sam Tradie / 0400-111-222 / Coogee',
      draftEstimate: DRAFT_EST,
      nowIso: NOW,
      queueIdOverride: '40404040-4040-4040-8040-404040404040',
    });
    expect(e.status).toBe('pending');
    expect(e.queueId).toBe('40404040-4040-4040-8040-404040404040');
    expect(queue.listPending()).toHaveLength(1);
  });

  test('listPending hides ratified / rejected entries', () => {
    const a = queue.enqueue({
      provenance: 'from_chat',
      chatSessionId: SESSION,
      customerHint: 'Sam',
      draftEstimate: DRAFT_EST,
      nowIso: NOW,
      queueIdOverride: '40404040-4040-4040-8040-404040404040',
    });
    queue.enqueue({
      provenance: 'from_chat',
      chatSessionId: 'other',
      customerHint: 'Pat',
      draftEstimate: DRAFT_EST,
      nowIso: NOW,
      queueIdOverride: '41414141-4141-4141-8141-414141414141',
    });
    queue.reject(a.queueId);
    const pending = queue.listPending();
    expect(pending).toHaveLength(1);
    expect(pending[0]!.queueId).toBe('41414141-4141-4141-8141-414141414141');
  });
});

describe('§O6b — ratification queue — reject', () => {
  test('reject marks entry as rejected; no cells emitted', () => {
    const e = queue.enqueue({
      provenance: 'from_chat',
      chatSessionId: SESSION,
      customerHint: 'Sam',
      draftEstimate: DRAFT_EST,
      nowIso: NOW,
      queueIdOverride: '40404040-4040-4040-8040-404040404040',
    });
    expect(queue.reject(e.queueId)).toBe(true);
    const after = queue.getEntry(e.queueId);
    expect(after!.status).toBe('rejected');
    expect(queue.listPending()).toHaveLength(0);
  });

  test('reject on unknown queueId returns false', () => {
    expect(queue.reject('99999999-9999-4999-8999-999999999999')).toBe(false);
  });

  test('reject on already-rejected entry returns false', () => {
    const e = queue.enqueue({
      provenance: 'from_chat',
      chatSessionId: SESSION,
      customerHint: 'Sam',
      draftEstimate: DRAFT_EST,
      nowIso: NOW,
      queueIdOverride: '40404040-4040-4040-8040-404040404040',
    });
    queue.reject(e.queueId);
    expect(queue.reject(e.queueId)).toBe(false);
  });
});

describe('§O6b — ratification queue — ratify (happy path)', () => {
  let entry: QueueEntry;

  beforeEach(() => {
    entry = queue.enqueue({
      provenance: 'from_chat',
      chatSessionId: SESSION,
      customerHint: 'Sam Tradie / 0400-111-222 / Coogee',
      draftEstimate: DRAFT_EST,
      nowIso: NOW,
      queueIdOverride: '40404040-4040-4040-8040-404040404040',
    });
  });

  function ratifyArgs(): RatifyInput {
    return {
      queueId: entry.queueId,
      operatorCertId: OP_CERT,
      nowIso: RATIFY_TIME,
      writeCustomerCap: validCap,
      newJobId: '50505050-5050-4050-8050-505050505050',
      newEstimateId: '51515151-5151-4151-8151-515151515151',
      newLeadId: '52525252-5252-4252-8252-525252525252',
    };
  }

  test('emits Estimate + Lead + Job cells under operator hat', () => {
    const r = queue.ratify(ratifyArgs());
    expect(r.ok).toBe(true);
    if (!r.ok) return;

    expect(r.value.estimate.estimateId).toBe('51515151-5151-4151-8151-515151515151');
    expect(r.value.estimate.jobId).toBe('50505050-5050-4050-8050-505050505050');
    expect(r.value.estimate.materialsNote).toContain('rotting deck boards');

    expect(r.value.lead.leadId).toBe('52525252-5252-4252-8252-525252525252');
    expect(r.value.lead.extractedEstimateId).toBe('51515151-5151-4151-8151-515151515151');
    expect(r.value.lead.jobId).toBe('50505050-5050-4050-8050-505050505050');
    expect(r.value.lead.chatSessionId).toBe(SESSION);
    expect(r.value.lead.customerHint).toBe('Sam Tradie / 0400-111-222 / Coogee');
    expect(r.value.lead.provenance).toBe('from_chat');
    expect(r.value.lead.ratifiedBy).toBe(OP_CERT);

    expect(r.value.job.jobId).toBe('50505050-5050-4050-8050-505050505050');
    expect(r.value.job.status).toBe('lead');
  });

  test('packed bytes round-trip via the canonical cell-types', () => {
    const r = queue.ratify(ratifyArgs());
    expect(r.ok).toBe(true);
    if (!r.ok) return;

    const e = estimateCellType.unpack(r.value.estimateBytes);
    const l = leadCellType.unpack(r.value.leadBytes);
    const j = jobCellType.unpack(r.value.jobBytes);
    expect(e.estimateId).toBe(r.value.estimate.estimateId);
    expect(l.leadId).toBe(r.value.lead.leadId);
    expect(j.jobId).toBe(r.value.job.jobId);
    expect(j.status).toBe('lead');
  });

  test('marks the queue entry as ratified', () => {
    queue.ratify(ratifyArgs());
    const after = queue.getEntry(entry.queueId);
    expect(after!.status).toBe('ratified');
    expect(queue.listPending()).toHaveLength(0);
  });
});

describe('§O6b — ratification queue — ratify (failure modes)', () => {
  let entry: QueueEntry;

  beforeEach(() => {
    entry = queue.enqueue({
      provenance: 'from_chat',
      chatSessionId: SESSION,
      customerHint: 'Sam',
      draftEstimate: DRAFT_EST,
      nowIso: NOW,
      queueIdOverride: '40404040-4040-4040-8040-404040404040',
    });
  });

  test('wrong cap → K3a wrong_cap failure; entry stays pending', () => {
    const r = queue.ratify({
      queueId: entry.queueId,
      operatorCertId: OP_CERT,
      nowIso: RATIFY_TIME,
      writeCustomerCap: wrongCap,
    });
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.error.kind).toBe('wrong_cap');
    // Entry still pending (failure-atomicity).
    expect(queue.getEntry(entry.queueId)!.status).toBe('pending');
  });

  test('unknown queueId → unknown_queue_id sentinel', () => {
    const r = queue.ratify({
      queueId: '99999999-9999-4999-8999-999999999999',
      operatorCertId: OP_CERT,
      nowIso: RATIFY_TIME,
      writeCustomerCap: validCap,
    });
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.error.kind).toBe('unknown_queue_id');
  });

  test('already-ratified queueId → unknown_queue_id (replay defence)', () => {
    queue.ratify({
      queueId: entry.queueId,
      operatorCertId: OP_CERT,
      nowIso: RATIFY_TIME,
      writeCustomerCap: validCap,
      newJobId: '50505050-5050-4050-8050-505050505050',
      newEstimateId: '51515151-5151-4151-8151-515151515151',
      newLeadId: '52525252-5252-4252-8252-525252525252',
    });
    const r = queue.ratify({
      queueId: entry.queueId,
      operatorCertId: OP_CERT,
      nowIso: RATIFY_TIME,
      writeCustomerCap: validCap,
    });
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.error.kind).toBe('unknown_queue_id');
  });
});

describe('§O6b — ratification queue — file-backed persistence', () => {
  test('pending entries survive a queue re-instantiation', () => {
    const dir = mkdtempSync(join(tmpdir(), 'oddjobz-rat-q-'));
    const path = join(dir, 'queue.json');
    try {
      const q1 = new RatificationQueue(makeFileStorage(path));
      q1.enqueue({
        provenance: 'from_chat',
        chatSessionId: SESSION,
        customerHint: 'Sam',
        draftEstimate: DRAFT_EST,
        nowIso: NOW,
        queueIdOverride: '40404040-4040-4040-8040-404040404040',
      });
      expect(existsSync(path)).toBe(true);

      // Operator restart: spin up a fresh queue from the same path.
      const q2 = new RatificationQueue(makeFileStorage(path));
      expect(q2.listPending()).toHaveLength(1);
      expect(q2.listPending()[0]!.queueId).toBe('40404040-4040-4040-8040-404040404040');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

```
