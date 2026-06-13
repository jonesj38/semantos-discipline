---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/takes/capturer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.614381+00:00
---

# cartridges/jambox/web/src/takes/capturer.ts

```ts
/**
 * D-F.1 — TakeCapturer
 *
 * Subscribes to the cell-relay channel for a room and records cells
 * emitted during a capture window. On stop(), emits one jam.contribution
 * per active player and one jam.take cell covering the full range.
 */

import type { SerializedCell } from '../core/sync';
import {
  semanticObjectId,
  createContribution,
  type JamboxTakeObject,
  type JamboxContributionObject,
} from '../semantic/objects';
import { computeContributionSplits } from '../contrib/policy';

export type CaptureStatus = 'idle' | 'capturing' | 'stopping' | 'captured';

export interface CapturedCell {
  cell: SerializedCell;
  roomTimeMs: number;
  player: string;
  family?: string;
}

export interface CaptureResult {
  take: JamboxTakeObject;
  contributions: JamboxContributionObject[];
  cells: SerializedCell[];
}

export interface TakeCapturerOptions {
  roomId: string;
  ownerIdentity: string;
  onCell?: (cell: SerializedCell, player: string) => void;
}

export class TakeCapturer {
  private _status: CaptureStatus = 'idle';
  private _capturedCells: CapturedCell[] = [];
  private _startSnapshotHash: string = '';
  private _startRoomTimeMs: number = 0;
  private _takeCounter: number = 0;

  readonly roomId: string;
  readonly ownerIdentity: string;

  constructor(private readonly options: TakeCapturerOptions) {
    this.roomId = options.roomId;
    this.ownerIdentity = options.ownerIdentity;
  }

  get status(): CaptureStatus {
    return this._status;
  }

  start(startSnapshotHash: string, roomTimeMs: number): void {
    if (this._status !== 'idle') {
      throw new Error(`TakeCapturer.start() called in state: ${this._status}`);
    }
    this._capturedCells = [];
    this._startSnapshotHash = startSnapshotHash;
    this._startRoomTimeMs = roomTimeMs;
    this._status = 'capturing';
  }

  recordCell(cell: SerializedCell, player: string, roomTimeMs: number, family?: string): void {
    if (this._status !== 'capturing') return;
    this._capturedCells.push({ cell, roomTimeMs, player, family });
    this.options.onCell?.(cell, player);
  }

  stop(endRoomTimeMs: number, barsHint?: number): CaptureResult {
    if (this._status !== 'capturing') {
      throw new Error(`TakeCapturer.stop() called in state: ${this._status}`);
    }
    this._status = 'stopping';

    const cells = this._capturedCells.map((c) => c.cell);

    const playerCells = new Map<string, CapturedCell[]>();
    for (const cc of this._capturedCells) {
      const existing = playerCells.get(cc.player);
      if (existing) {
        existing.push(cc);
      } else {
        playerCells.set(cc.player, [cc]);
      }
    }

    const players = Array.from(playerCells.keys());

    const splits = computeContributionSplits(this._capturedCells.map((c) => ({
      player: c.player,
      roomTimeMs: c.roomTimeMs,
      family: c.family,
    })));

    const takeCounter = ++this._takeCounter;
    const takeId = semanticObjectId(
      'jam.take',
      this.ownerIdentity,
      `${this.roomId}-take-${takeCounter}-${this._startRoomTimeMs}`,
    );

    const contributions: JamboxContributionObject[] = players.map((player) => {
      const pCells = playerCells.get(player) ?? [];
      const cellRange = {
        from: pCells[0]?.roomTimeMs ?? this._startRoomTimeMs,
        to: pCells[pCells.length - 1]?.roomTimeMs ?? endRoomTimeMs,
      };
      const splitBps = splits.get(player) ?? 0;
      return createContribution({
        ownerIdentity: this.ownerIdentity,
        room: this.roomId,
        playerIdentity: player,
        objectIds: [takeId],
        shareBps: splitBps,
        startMs: this._startRoomTimeMs,
        cellRange,
        license: 'personal',
      });
    });

    const contributionIds = contributions.map((c) => c.id);

    const CELL_INLINE_THRESHOLD_BYTES = 256 * 1024;
    const serialisedSize = JSON.stringify(cells).length;
    const cellsField: JamboxTakeObject['payload']['cells'] =
      serialisedSize > CELL_INLINE_THRESHOLD_BYTES
        ? { ref: `cas:${this.roomId}:take-${takeCounter}`, sha256: '' }
        : cells;

    const now = Date.now();
    const localId = `${this.roomId}-take-${this._startRoomTimeMs}`;
    const id = semanticObjectId('jam.take', this.ownerIdentity, localId);

    const take: JamboxTakeObject = {
      id,
      header: {
        version: 1,
        objectType: 'jam.take',
        semanticPath: `/jam/v1/take/${slug(this.roomId)}/${this._startRoomTimeMs}`,
        linearity: 'linear',
        ownerIdentity: this.ownerIdentity,
        parents: contributionIds,
        createdAt: now,
      },
      payload: {
        name: `take-${this._startRoomTimeMs}`,
        sourceObjectId: this.roomId,
        startMs: this._startRoomTimeMs,
        durationMs: endRoomTimeMs - this._startRoomTimeMs,
        state: 'captured',
        room: this.roomId,
        range: { startRoomTimeMs: this._startRoomTimeMs, endRoomTimeMs },
        lengthBars: barsHint,
        cells: cellsField,
        players,
        racks: [],
        mappings: [],
        startSnapshotHash: this._startSnapshotHash,
      },
    };

    this._status = 'captured';
    return { take, contributions, cells };
  }

  reset(): void {
    this._status = 'idle';
    this._capturedCells = [];
  }
}

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') || 'object';
}

```
