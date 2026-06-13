---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/ratification-queue.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.473087+00:00
---

# cartridges/oddjobz/brain/src/ratification-queue.ts

```ts
/**
 * D-O6b — Public chat v1.0 — ratification queue resource.
 *
 * The bridge between the lead-extraction service path and the operator-
 * signed canonical-cell path. Commands:
 *
 *   • `enqueue`      — service-side, called when `oddjobz.lead_extract`
 *                       returns has_lead=true. Persists the draft
 *                       Estimate shape + chatSessionId + customerHint
 *                       on disk.
 *   • `list_pending` — operator reads pending entries.
 *   • `ratify`       — operator signs. Spends
 *                       `cap.oddjobz.write_customer`, mints the §O2
 *                       `oddjobz.estimate.v1` cell, mints the §O6b
 *                       `oddjobz.lead.v1` cell, drives the §O4 Job FSM
 *                       `∅ → lead` genesis transition.
 *   • `reject`       — operator drops the draft.
 *
 * The queue persists to disk so operator restart doesn't lose pending
 * leads. Storage shape: a single JSON file at
 * `<data_dir>/ratification-queue.json` keyed by queueId.
 *
 * For TS-layer testability the storage backend is abstracted behind a
 * `QueueStorage` interface; the Semantos Brain-side dispatcher registration plugs
 * in a node-fs implementation, while tests use an in-memory one.
 */

import { randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';

import type { OddjobzEstimate } from './cell-types/estimate.js';
import { estimateCellType } from './cell-types/estimate.js';
import {
  leadCellType,
  type OddjobzLead,
  type LeadProvenance,
} from './cell-types/lead.js';
import { messageCellType } from './cell-types/message.js';
import {
  genesisJobLead,
  type JobGenesisInput,
} from './state-machines/job-fsm.js';
import type {
  PresentedCap,
  KernelGateFailure,
  Result,
} from './state-machines/kernel-gate.js';
import { ok, err } from './state-machines/kernel-gate.js';
import { jobCellType, type OddjobzJob } from './cell-types/job.js';

/* ══════════════════════════════════════════════════════════════════════
 * Queue entry — what gets persisted on `enqueue`
 * ══════════════════════════════════════════════════════════════════════ */

export interface QueueEntry {
  /** Stable queue-entry id (UUID v4). */
  readonly queueId: string;
  /** ISO-8601 timestamp at which the draft was enqueued. */
  readonly enqueuedAt: string;
  /** Where the lead came from. */
  readonly provenance: LeadProvenance;
  /**
   * Chat session id (opaque visitor-supplied string) — empty for
   * non-chat provenances.
   */
  readonly chatSessionId: string;
  /**
   * Customer-hint extracted from the chat (or operator notes for
   * non-chat provenances).
   */
  readonly customerHint: string;
  /**
   * The draft Estimate shape — NOT yet a signed cell. The
   * `estimateId` and `jobId` fields are placeholders the ratify step
   * substitutes with freshly-minted UUIDs.
   */
  readonly draftEstimate: OddjobzEstimate;
  /** Status of this entry. */
  readonly status: 'pending' | 'ratified' | 'rejected';
}

/* ══════════════════════════════════════════════════════════════════════
 * Storage abstraction — JSON file in production; in-memory for tests
 * ══════════════════════════════════════════════════════════════════════ */

export interface QueueStorage {
  /** Read all entries. Returns an empty array if the backing store is empty. */
  load(): readonly QueueEntry[];
  /** Atomically replace the stored entry set. */
  save(entries: readonly QueueEntry[]): void;
}

/** In-memory storage — for tests + e2e fixtures. */
export function makeMemoryStorage(): QueueStorage {
  let state: readonly QueueEntry[] = [];
  return {
    load: () => state,
    save: (entries) => {
      state = entries.slice();
    },
  };
}

/** Node-fs storage — used by the Semantos Brain-side dispatcher registration. */
export function makeFileStorage(path: string): QueueStorage {
  return {
    load(): readonly QueueEntry[] {
      if (!existsSync(path)) return [];
      const raw = readFileSync(path, 'utf-8');
      try {
        const parsed = JSON.parse(raw) as { entries?: QueueEntry[] };
        return Array.isArray(parsed.entries) ? parsed.entries : [];
      } catch {
        return [];
      }
    },
    save(entries: readonly QueueEntry[]): void {
      mkdirSync(dirname(path), { recursive: true });
      const json = JSON.stringify({ version: 1, entries }, null, 2) + '\n';
      writeFileSync(path, json, 'utf-8');
    },
  };
}

/* ══════════════════════════════════════════════════════════════════════
 * Inputs / outputs
 * ══════════════════════════════════════════════════════════════════════ */

export interface EnqueueInput {
  readonly provenance: LeadProvenance;
  readonly chatSessionId: string;
  readonly customerHint: string;
  readonly draftEstimate: OddjobzEstimate;
  readonly nowIso: string;
  /** Override the auto-generated queueId — for deterministic tests. */
  readonly queueIdOverride?: string;
}

export interface RatifyInput {
  /** Which queue entry to ratify. */
  readonly queueId: string;
  /** Operator cert id (16-byte hex). */
  readonly operatorCertId: string;
  /** ISO-8601 ratification timestamp. */
  readonly nowIso: string;
  /**
   * `cap.oddjobz.write_customer` UTXO presented for the §O4 `∅ → lead`
   * genesis transition. The kernel-gate stub asserts the domain flag
   * matches.
   */
  readonly writeCustomerCap: PresentedCap;
  /**
   * Fresh UUID v4 for the materialised Job. Tests pass a deterministic
   * value; production calls `randomUUID`.
   */
  readonly newJobId?: string;
  /** Fresh UUID v4 for the signed Estimate cell. */
  readonly newEstimateId?: string;
  /** Fresh UUID v4 for the Lead cell. */
  readonly newLeadId?: string;
}

export interface RatifyResult {
  /** The minted Estimate cell — signed under the operator's hat. */
  readonly estimate: OddjobzEstimate;
  /** The minted Lead cell. */
  readonly lead: OddjobzLead;
  /** The materialised Job in `lead` state. */
  readonly job: OddjobzJob;
  /** Packed bytes of each minted cell (ready for `files.write`). */
  readonly estimateBytes: Uint8Array;
  readonly leadBytes: Uint8Array;
  readonly jobBytes: Uint8Array;
}

/* ══════════════════════════════════════════════════════════════════════
 * RatificationQueue — the resource implementation
 * ══════════════════════════════════════════════════════════════════════ */

export class RatificationQueue {
  private storage: QueueStorage;

  constructor(storage: QueueStorage) {
    this.storage = storage;
  }

  /**
   * Service-side enqueue — called when `oddjobz.lead_extract.extract`
   * returns has_lead=true. Persists the draft Estimate shape on disk.
   */
  enqueue(input: EnqueueInput): QueueEntry {
    const entries = this.storage.load();
    const queueId = input.queueIdOverride ?? randomUUID();
    const entry: QueueEntry = {
      queueId,
      enqueuedAt: input.nowIso,
      provenance: input.provenance,
      chatSessionId: input.chatSessionId,
      customerHint: input.customerHint,
      draftEstimate: input.draftEstimate,
      status: 'pending',
    };
    this.storage.save([...entries, entry]);
    return entry;
  }

  /** Operator-side list of pending entries. */
  listPending(): readonly QueueEntry[] {
    return this.storage.load().filter((e) => e.status === 'pending');
  }

  /** Operator-side: drop a pending draft. */
  reject(queueId: string): boolean {
    const entries = this.storage.load();
    const idx = entries.findIndex((e) => e.queueId === queueId);
    if (idx < 0) return false;
    if (entries[idx]!.status !== 'pending') return false;
    const next = entries.slice();
    next[idx] = { ...entries[idx]!, status: 'rejected' };
    this.storage.save(next);
    return true;
  }

  /**
   * Operator-side ratify. Spends `cap.oddjobz.write_customer`, mints
   * the Estimate + Lead cells under the operator's hat, drives the
   * §O4 Job FSM `∅ → lead` genesis transition.
   *
   * Returns a `Result` so caller distinguishes between:
   *   - successful ratification (cells emitted)
   *   - kernel-gate failure (cap mismatched, etc.)
   *   - queue lookup miss (unknown_queue_id sentinel error)
   */
  ratify(
    input: RatifyInput,
  ): Result<RatifyResult, KernelGateFailure | { kind: 'unknown_queue_id'; message: string }> {
    const entries = this.storage.load();
    const idx = entries.findIndex((e) => e.queueId === input.queueId);
    if (idx < 0) {
      return err({
        kind: 'unknown_queue_id',
        message: `no queue entry with id ${input.queueId}`,
      } as const);
    }
    const entry = entries[idx]!;
    if (entry.status !== 'pending') {
      return err({
        kind: 'unknown_queue_id',
        message: `queue entry ${input.queueId} is not pending (status=${entry.status})`,
      } as const);
    }

    // Mint a fresh Job in `lead` state — drives §O4 ∅ → lead under
    // operator authority spending cap.oddjobz.write_customer.
    const newJobId = input.newJobId ?? randomUUID();
    const genInput: JobGenesisInput = {
      jobId: newJobId,
      principal: 'operator',
      presentedCap: input.writeCustomerCap,
      nowIso: input.nowIso,
    };
    const genResult = genesisJobLead(genInput);
    if (!genResult.ok) {
      return err(genResult.error);
    }
    const job: OddjobzJob = genResult.value;

    // Sign the Estimate — substitute the placeholder jobId with the
    // freshly-minted Job's id, and stamp a fresh estimateId.
    const newEstimateId = input.newEstimateId ?? randomUUID();
    const signedEstimate: OddjobzEstimate = {
      ...entry.draftEstimate,
      estimateId: newEstimateId,
      jobId: newJobId,
      authoredByOperatorId: undefined,
      updatedAt: input.nowIso,
    };

    // Mint the Lead cell — the audit-anchor.
    const newLeadId = input.newLeadId ?? randomUUID();
    const lead: OddjobzLead = {
      leadId: newLeadId,
      chatSessionId: entry.chatSessionId,
      extractedEstimateId: newEstimateId,
      customerHint: entry.customerHint,
      jobId: newJobId,
      ratifiedBy: input.operatorCertId,
      ratifiedAt: input.nowIso,
      provenance: entry.provenance,
    };

    // Pack each cell — the byte-level representation that would be
    // handed to `files.write` per D-W1 Phase 2.
    const estimateBytes = estimateCellType.pack(signedEstimate);
    const leadBytes = leadCellType.pack(lead);
    const jobBytes = jobCellType.pack(job);

    // Mark the queue entry ratified.
    const next = entries.slice();
    next[idx] = { ...entry, status: 'ratified' };
    this.storage.save(next);

    return ok({
      estimate: signedEstimate,
      lead,
      job,
      estimateBytes,
      leadBytes,
      jobBytes,
    });
  }

  /** Direct readback of a single entry by id — useful for tests. */
  getEntry(queueId: string): QueueEntry | undefined {
    return this.storage.load().find((e) => e.queueId === queueId);
  }

  /** All entries regardless of status — for inspection. */
  allEntries(): readonly QueueEntry[] {
    return this.storage.load();
  }
}

/* Re-export the message-cell pack so the e2e test has access without
 * pulling the cell-types module. */
export { messageCellType };

```
