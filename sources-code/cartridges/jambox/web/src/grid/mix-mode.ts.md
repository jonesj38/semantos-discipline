---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/grid/mix-mode.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.604339+00:00
---

# cartridges/jambox/web/src/grid/mix-mode.ts

```ts
/**
 * D-B.3 Mix mode — full 8-track × 8-row FX grid.
 *
 * Grid layout:
 *   Row 0 = volume    brightness = level; swipe = adjust
 *   Row 1 = send A    (room reverb)
 *   Row 2 = send B    (room delay)
 *   Row 3 = mute      tap to toggle; red when muted
 *   Row 4 = solo      tap to toggle; yellow when soloed
 *   Row 5 = fx-1      filter / cutoff
 *   Row 6 = fx-2      drive
 *   Row 7 = fx-3      bitcrush
 *
 *   Col 0-6  = tracks 0-6
 *   Col 7    = "all" (master volume / mute / solo)
 *
 * Adjustments emit:
 *   jam.rack.macro.set   — for canonical 8 macros
 *   jam.control.change   — for track FX / master controls
 *
 * Mix peek (inline, D-B.3):
 *   Bottom 2 rows of Bass/Melody L2 pods = rows 0-1 (volume + send-A).
 *   This module exports renderMixPeek() for that use.
 */

import type { PadState } from './surface';
import type {
  JamRackMacroSet,
  JamControlChange,
  JamInputPad,
} from '../semantic/events';

// ─── Types ────────────────────────────────────────────────────────────────────

export type MixEvent = JamRackMacroSet | JamControlChange | JamInputPad;

export interface TrackMixState {
  rackId: string;
  label: string;
  volume: number;     // 0..1
  sendA: number;      // 0..1  reverb
  sendB: number;      // 0..1  delay
  muted: boolean;
  soloed: boolean;
  fx1: number;        // filter cutoff 0..1
  fx2: number;        // drive 0..1
  fx3: number;        // bitcrush 0..1
}

export interface MixModeState {
  tracks: TrackMixState[];      // length 7 visible tracks + 1 master
  masterVolume: number;
  masterMuted: boolean;
  masterSoloed: boolean;
}

// ─── Row → label map ──────────────────────────────────────────────────────────

const ROW_LABELS = ['VOL', 'SND-A', 'SND-B', 'MUTE', 'SOLO', 'FX1', 'FX2', 'FX3'];

// ─── renderMixPads ────────────────────────────────────────────────────────────

export function renderMixPads(state: MixModeState): PadState[] {
  const pads: PadState[] = [];
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      pads.push(renderMixCell(row, col, state));
    }
  }
  return pads;
}

function renderMixCell(row: number, col: number, state: MixModeState): PadState {
  // Col 7 = "all" master column
  const isMaster = col === 7;
  const track = isMaster ? null : state.tracks[col] ?? null;
  const rowLabel = ROW_LABELS[row] ?? '';

  if (row === 0) {
    // Volume
    const vol = isMaster ? state.masterVolume : (track?.volume ?? 0);
    return {
      color: isMaster ? 'white' : 'cyan',
      brightness: 0.15 + vol * 0.85,
      label: rowLabel,
      pulse: false,
      active: vol > 0,
    };
  }

  if (row === 1) {
    // Send A (reverb)
    const send = track?.sendA ?? 0;
    if (isMaster) return emptyMixCell();
    return {
      color: 'blue',
      brightness: 0.1 + send * 0.9,
      label: rowLabel,
      pulse: false,
      active: send > 0.05,
    };
  }

  if (row === 2) {
    // Send B (delay)
    const send = track?.sendB ?? 0;
    if (isMaster) return emptyMixCell();
    return {
      color: 'purple',
      brightness: 0.1 + send * 0.9,
      label: rowLabel,
      pulse: false,
      active: send > 0.05,
    };
  }

  if (row === 3) {
    // Mute
    const muted = isMaster ? state.masterMuted : (track?.muted ?? false);
    return {
      color: muted ? 'red' : 'dim',
      brightness: muted ? 0.9 : 0.25,
      label: 'MUTE',
      pulse: false,
      active: muted,
    };
  }

  if (row === 4) {
    // Solo
    const soloed = isMaster ? state.masterSoloed : (track?.soloed ?? false);
    return {
      color: soloed ? 'yellow' : 'dim',
      brightness: soloed ? 0.9 : 0.25,
      label: 'SOLO',
      pulse: false,
      active: soloed,
    };
  }

  if (row === 5) {
    // FX-1: filter
    const val = track?.fx1 ?? 0;
    if (isMaster) return emptyMixCell();
    return {
      color: 'green',
      brightness: 0.1 + val * 0.9,
      label: 'FLT',
      pulse: false,
      active: val > 0.1,
    };
  }

  if (row === 6) {
    // FX-2: drive
    const val = track?.fx2 ?? 0;
    if (isMaster) return emptyMixCell();
    return {
      color: 'orange',
      brightness: 0.1 + val * 0.9,
      label: 'DRV',
      pulse: false,
      active: val > 0.1,
    };
  }

  if (row === 7) {
    // FX-3: bitcrush
    const val = track?.fx3 ?? 0;
    if (isMaster) return emptyMixCell();
    return {
      color: 'pink',
      brightness: 0.1 + val * 0.9,
      label: 'BIT',
      pulse: false,
      active: val > 0.1,
    };
  }

  return emptyMixCell();
}

function emptyMixCell(): PadState {
  return { color: 'off', brightness: 0, label: '', pulse: false, active: false };
}

// ─── renderMixPeek ────────────────────────────────────────────────────────────

/**
 * Render just the bottom 2 rows (volume + send-A) for Mix peek.
 *
 * Returns 16 PadState values (2 rows × 8 cols) for the Bass/Melody L2 pods.
 */
export function renderMixPeek(state: MixModeState): PadState[] {
  const result: PadState[] = [];
  for (let row = 0; row < 2; row++) {
    for (let col = 0; col < 8; col++) {
      result.push(renderMixCell(row, col, state));
    }
  }
  return result;
}

// ─── handleMixPress ───────────────────────────────────────────────────────────

export interface MixPressResult {
  events: MixEvent[];
  stateChanges: Partial<MixModeState>;
}

/**
 * Handle a pad press in mix mode.
 *
 * Returns canonical events to dispatch and state changes.
 */
export function handleMixPress(
  padIndex: number,
  state: MixModeState,
  delta = 0.125,
): MixPressResult {
  const row = Math.floor(padIndex / 8);
  const col = padIndex % 8;
  const isMaster = col === 7;
  const track = isMaster ? null : state.tracks[col] ?? null;
  const events: MixEvent[] = [];
  const stateChanges: Partial<MixModeState> = {};

  // Always emit jam.input.pad
  const inputPad: JamInputPad = {
    family: 'jam.input.pad',
    surfaceId: 'grid-8x8',
    x: col,
    y: row,
    pressure: 0.8,
    velocity: 100,
    aftertouch: 0,
    ts: Date.now(),
    mode: 'mix',
  };
  events.push(inputPad);

  if (row === 0) {
    // Volume
    if (track) {
      const newVol = Math.max(0, Math.min(1, track.volume + delta));
      const updatedTracks = [...state.tracks];
      updatedTracks[col] = { ...track, volume: newVol };
      stateChanges.tracks = updatedTracks;

      events.push({
        family: 'jam.rack.macro.set',
        rackId: track.rackId,
        index: 5, // macro 5 = body (low-shelf/sub/compressor = volume proxy)
        value: newVol,
      });
    } else if (isMaster) {
      const newVol = Math.max(0, Math.min(1, state.masterVolume + delta));
      stateChanges.masterVolume = newVol;
      events.push({
        family: 'jam.control.change',
        target: 'master.volume',
        value: newVol,
        ts: Date.now(),
      });
    }
    return { events, stateChanges };
  }

  if (row === 1 && track) {
    // Send A (reverb)
    const newSend = Math.max(0, Math.min(1, track.sendA + delta));
    const updatedTracks = [...state.tracks];
    updatedTracks[col] = { ...track, sendA: newSend };
    stateChanges.tracks = updatedTracks;

    events.push({
      family: 'jam.rack.macro.set',
      rackId: track.rackId,
      index: 3, // macro 3 = space (reverb)
      value: newSend,
    });
    return { events, stateChanges };
  }

  if (row === 2 && track) {
    // Send B (delay)
    const newSend = Math.max(0, Math.min(1, track.sendB + delta));
    const updatedTracks = [...state.tracks];
    updatedTracks[col] = { ...track, sendB: newSend };
    stateChanges.tracks = updatedTracks;

    events.push({
      family: 'jam.control.change',
      target: `${track.rackId}.send-b`,
      value: newSend,
      ts: Date.now(),
    });
    return { events, stateChanges };
  }

  if (row === 3) {
    // Mute toggle
    if (isMaster) {
      stateChanges.masterMuted = !state.masterMuted;
      events.push({
        family: 'jam.control.change',
        target: 'master.mute',
        value: stateChanges.masterMuted ? 1 : 0,
        ts: Date.now(),
      });
    } else if (track) {
      const updatedTracks = [...state.tracks];
      updatedTracks[col] = { ...track, muted: !track.muted };
      stateChanges.tracks = updatedTracks;
      events.push({
        family: 'jam.control.change',
        target: `${track.rackId}.mute`,
        value: !track.muted ? 1 : 0,
        ts: Date.now(),
      });
    }
    return { events, stateChanges };
  }

  if (row === 4) {
    // Solo toggle
    if (isMaster) {
      stateChanges.masterSoloed = !state.masterSoloed;
      events.push({
        family: 'jam.control.change',
        target: 'master.solo',
        value: stateChanges.masterSoloed ? 1 : 0,
        ts: Date.now(),
      });
    } else if (track) {
      const updatedTracks = [...state.tracks];
      updatedTracks[col] = { ...track, soloed: !track.soloed };
      stateChanges.tracks = updatedTracks;
      events.push({
        family: 'jam.control.change',
        target: `${track.rackId}.solo`,
        value: !track.soloed ? 1 : 0,
        ts: Date.now(),
      });
    }
    return { events, stateChanges };
  }

  if (row === 5 && track) {
    // FX-1: filter
    const newVal = Math.max(0, Math.min(1, track.fx1 + delta));
    const updatedTracks = [...state.tracks];
    updatedTracks[col] = { ...track, fx1: newVal };
    stateChanges.tracks = updatedTracks;

    events.push({
      family: 'jam.rack.macro.set',
      rackId: track.rackId,
      index: 0, // macro 0 = brightness (filter)
      value: newVal,
    });
    return { events, stateChanges };
  }

  if (row === 6 && track) {
    // FX-2: drive
    const newVal = Math.max(0, Math.min(1, track.fx2 + delta));
    const updatedTracks = [...state.tracks];
    updatedTracks[col] = { ...track, fx2: newVal };
    stateChanges.tracks = updatedTracks;

    events.push({
      family: 'jam.rack.macro.set',
      rackId: track.rackId,
      index: 1, // macro 1 = dirt (drive)
      value: newVal,
    });
    return { events, stateChanges };
  }

  if (row === 7 && track) {
    // FX-3: bitcrush
    const newVal = Math.max(0, Math.min(1, track.fx3 + delta));
    const updatedTracks = [...state.tracks];
    updatedTracks[col] = { ...track, fx3: newVal };
    stateChanges.tracks = updatedTracks;

    events.push({
      family: 'jam.control.change',
      target: `${track.rackId}.bitcrush`,
      value: newVal,
      ts: Date.now(),
    });
    return { events, stateChanges };
  }

  return { events, stateChanges };
}

// ─── createMixModeState ───────────────────────────────────────────────────────

export function createMixModeState(
  trackInfos: Array<{ rackId: string; label: string }>,
): MixModeState {
  const tracks: TrackMixState[] = trackInfos.slice(0, 7).map((t) => ({
    rackId: t.rackId,
    label: t.label,
    volume: 0.8,
    sendA: 0,
    sendB: 0,
    muted: false,
    soloed: false,
    fx1: 0.5,
    fx2: 0,
    fx3: 0,
  }));
  return {
    tracks,
    masterVolume: 0.85,
    masterMuted: false,
    masterSoloed: false,
  };
}

```
