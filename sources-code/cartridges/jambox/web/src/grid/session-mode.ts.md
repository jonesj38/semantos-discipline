---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/grid/session-mode.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.606542+00:00
---

# cartridges/jambox/web/src/grid/session-mode.ts

```ts
/**
 * D-B.4 Session mode upgrade — clip-aware session view.
 *
 * Each cell is a `jam.clip` object with states:
 *   empty    → tap arms + starts recording
 *   armed    → recording in progress
 *   playing  → tap queues stop at current quantum
 *   queued   → waiting for quantum boundary
 *   muted    → clip exists but muted
 *
 * Right-edge column (col 7) = scene launch column.
 * Scene launch emits `jam.scene.launch` with the current quantum.
 *
 * Launch quantization defaults to 1 bar.
 */

import type { PadState, PadColor } from './surface';
import type {
  JamClipArm,
  JamClipRecordStart,
  JamClipLaunchQueue,
  JamClipStopQueue,
  JamSceneLaunch,
  JamInputPad,
} from '../semantic/events';

// ─── Types ────────────────────────────────────────────────────────────────────

export type ClipState = 'empty' | 'armed' | 'recording' | 'queued' | 'playing' | 'muted';

export interface ClipSlot {
  clipId: string;
  name: string;
  color: PadColor;
  state: ClipState;
  /** jam.scene id for this row. Auto-promoted from integer on first use. */
  sceneId?: string;
}

export interface SessionModeState {
  /** 8 tracks × 7 rows of clips (row 7 = scene launch strip). */
  slots: Array<ClipSlot | null>;  // 56 entries (rows 0-6, 8 cols each)
  /** Scene ids indexed by row (0-6). */
  sceneIds: (string | null)[];
  /** Quantum in beats for launch/stop alignment. Default 4 (= 1 bar). */
  quantum: number;
}

export type SessionEvent =
  | JamClipArm
  | JamClipRecordStart
  | JamClipLaunchQueue
  | JamClipStopQueue
  | JamSceneLaunch
  | JamInputPad;

// ─── renderSessionPads ───────────────────────────────────────────────────────

export function renderSessionPads(state: SessionModeState): PadState[] {
  const pads: PadState[] = [];

  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      if (row === 7) {
        // Mode nav row — rendered by surface; push placeholder
        pads.push({ color: 'off', brightness: 0, label: '', pulse: false, active: false });
        continue;
      }

      if (col === 7) {
        // Scene launch column
        const sceneId = state.sceneIds[row];
        pads.push({
          color: sceneId ? 'white' : 'dim',
          brightness: sceneId ? 0.7 : 0.2,
          label: sceneId ? '▶' : '',
          pulse: false,
          active: false,
        });
        continue;
      }

      const slotIdx = row * 8 + col;
      const slot = state.slots[slotIdx] ?? null;

      if (!slot) {
        pads.push({ color: 'dim', brightness: 0.05, label: '·', pulse: false, active: false });
        continue;
      }

      pads.push(slotToPad(slot));
    }
  }
  return pads;
}

function slotToPad(slot: ClipSlot): PadState {
  switch (slot.state) {
    case 'empty':
      return { color: 'dim', brightness: 0.05, label: '·', pulse: false, active: false };
    case 'armed':
      return { color: 'red', brightness: 0.7, label: slot.name.slice(0, 4), pulse: true, active: true };
    case 'recording':
      return { color: 'red', brightness: 1, label: slot.name.slice(0, 4), pulse: true, active: true };
    case 'queued':
      return { color: 'yellow', brightness: 0.8, label: slot.name.slice(0, 4), pulse: true, active: false };
    case 'playing':
      return { color: slot.color, brightness: 1, label: slot.name.slice(0, 4), pulse: true, active: true };
    case 'muted':
      return { color: 'dim', brightness: 0.3, label: slot.name.slice(0, 4), pulse: false, active: false };
  }
}

// ─── handleSessionPress ───────────────────────────────────────────────────────

export interface SessionPressResult {
  events: SessionEvent[];
  stateChanges: Partial<SessionModeState>;
}

export function handleSessionPress(
  padIndex: number,
  state: SessionModeState,
): SessionPressResult {
  const row = Math.floor(padIndex / 8);
  const col = padIndex % 8;
  const events: SessionEvent[] = [];
  const stateChanges: Partial<SessionModeState> = {};
  const ts = Date.now();

  // Emit jam.input.pad always
  events.push({
    family: 'jam.input.pad',
    surfaceId: 'grid-8x8',
    x: col,
    y: row,
    pressure: 0.8,
    velocity: 100,
    aftertouch: 0,
    ts,
    mode: 'session',
  });

  if (row === 7) return { events, stateChanges }; // nav row handled by surface

  // Scene launch column (col 7)
  if (col === 7) {
    const sceneId = state.sceneIds[row];
    if (sceneId) {
      events.push({
        family: 'jam.scene.launch',
        sceneId,
        quantum: state.quantum,
        ts,
      });
    }
    return { events, stateChanges };
  }

  const slotIdx = row * 8 + col;
  const slot = state.slots[slotIdx];

  if (!slot || slot.state === 'empty') {
    // Arm + start recording
    const clipId = `clip-${row}-${col}-${ts}`;
    events.push({ family: 'jam.clip.arm', clipId, owner: 'self' });
    events.push({ family: 'jam.clip.record.start', clipId, ts });

    const newSlots = [...state.slots];
    newSlots[slotIdx] = {
      clipId,
      name: `C${row}${col}`,
      color: 'red',
      state: 'recording',
    };
    stateChanges.slots = newSlots;
    return { events, stateChanges };
  }

  if (slot.state === 'armed' || slot.state === 'recording') {
    // Already armed/recording — do nothing (recording continues)
    return { events, stateChanges };
  }

  if (slot.state === 'playing' || slot.state === 'queued') {
    // Stop queue
    events.push({
      family: 'jam.clip.stop.queue',
      clipId: slot.clipId,
      quantum: state.quantum,
      ts,
    });
    const newSlots = [...state.slots];
    newSlots[slotIdx] = { ...slot, state: 'queued' };
    stateChanges.slots = newSlots;
    return { events, stateChanges };
  }

  if (slot.state === 'muted') {
    // Launch muted clip
    events.push({
      family: 'jam.clip.launch.queue',
      clipId: slot.clipId,
      quantum: state.quantum,
      ts,
    });
    const newSlots = [...state.slots];
    newSlots[slotIdx] = { ...slot, state: 'queued' };
    stateChanges.slots = newSlots;
    return { events, stateChanges };
  }

  return { events, stateChanges };
}

// ─── createSessionModeState ──────────────────────────────────────────────────

export function createSessionModeState(): SessionModeState {
  return {
    slots: Array(56).fill(null),
    sceneIds: [null, null, null, null, null, null, null],
    quantum: 4, // 1 bar default
  };
}

/**
 * Auto-promote integer scene index (0-3) to a jam.scene id.
 * Idempotent on (roomId, sceneIndex) per D-B.5.
 */
export function promoteSceneIndex(
  sceneIndex: number,
  roomId: string,
): string {
  return `jam.scene.${roomId}.${sceneIndex}`;
}

```
