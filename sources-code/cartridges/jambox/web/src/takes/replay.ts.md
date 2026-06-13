---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/takes/replay.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.614671+00:00
---

# cartridges/jambox/web/src/takes/replay.ts

```ts
/**
 * D-F.3 — Take replay.
 *
 * Given a take object, restores the room to its startSnapshotHash
 * and replays cells in order. Deterministic from cell stream + start snapshot.
 */

import type { SerializedCell } from '../core/sync';
import type { JamboxTakeObject } from '../semantic/objects';

export type ReplayStatus = 'idle' | 'restoring' | 'replaying' | 'done' | 'error';

export interface ReplayCallbacks {
  onRestoreSnapshot(snapshotHash: string): Promise<void>;
  onCell(cell: SerializedCell, index: number, total: number): Promise<void>;
  onMissingRack?(rackId: string): void;
  onDone?(): void;
  onError?(err: unknown): void;
}

export class TakeReplay {
  private _status: ReplayStatus = 'idle';

  constructor(
    private readonly take: JamboxTakeObject,
    private readonly callbacks: ReplayCallbacks,
  ) {}

  get status(): ReplayStatus {
    return this._status;
  }

  async run(): Promise<void> {
    if (this._status !== 'idle') {
      throw new Error(`TakeReplay.run() called in state: ${this._status}`);
    }

    try {
      const payload = this.take.payload;

      if (payload.racks && payload.racks.length > 0) {
        for (const rackId of payload.racks) {
          try {
            this.callbacks.onMissingRack?.(rackId);
          } catch {
            console.warn(`[TakeReplay] onMissingRack threw for rack: ${rackId}`);
          }
        }
      }

      this._status = 'restoring';
      const snapshotHash = payload.startSnapshotHash ?? '';
      await this.callbacks.onRestoreSnapshot(snapshotHash);

      this._status = 'replaying';
      // Sort by depth for deterministic replay (DAG topological order).
      const cells = extractCells(payload.cells).slice().sort((a, b) => a.depth - b.depth);

      for (let i = 0; i < cells.length; i++) {
        const cell = cells[i]!;
        await this.callbacks.onCell(cell, i, cells.length);
      }

      this._status = 'done';
      this.callbacks.onDone?.();
    } catch (err) {
      this._status = 'error';
      this.callbacks.onError?.(err);
      throw err;
    }
  }

  reset(): void {
    this._status = 'idle';
  }
}

function extractCells(
  cells: SerializedCell[] | { ref: string; sha256: string } | undefined,
): SerializedCell[] {
  if (!cells) return [];
  if (Array.isArray(cells)) return cells;
  console.warn(
    `[TakeReplay] cells stored by CAS reference: ${cells.ref}. ` +
    'Resolve via CAS before calling replay.',
  );
  return [];
}

```
