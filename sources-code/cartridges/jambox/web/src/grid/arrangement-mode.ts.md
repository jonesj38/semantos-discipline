---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/grid/arrangement-mode.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.604638+00:00
---

# cartridges/jambox/web/src/grid/arrangement-mode.ts

```ts
/**
 * D-B.5 Arrangement mode upgrade — jam.scene-aware timeline.
 *
 * Arrangement blocks reference `jam.scene` ids.
 * Integer scene 0-3 auto-promotes to jam.scene on first entry — idempotent
 * on (roomId, sceneIndex).
 *
 * Drag a scene onto the timeline emits:
 *   jam.arrangement.section.add { sceneId, lengthBars }
 */

import type { PadState, PadColor } from './surface';
import type {
  JamArrangementSectionAdd,
  JamInputPad,
} from '../semantic/events';
import { promoteSceneIndex } from './session-mode';

// ─── Types ────────────────────────────────────────────────────────────────────

export interface ArrangementSection {
  sceneId: string;
  startBar: number;
  lengthBars: number;
  color: PadColor;
  label: string;
}

export interface ArrangementModeState {
  /** Arranged sections on the timeline. */
  sections: ArrangementSection[];
  /** Scene bank: rows 1-6, 8 cols = 48 scene slots. */
  sceneBank: Array<{ sceneId: string; label: string; color: PadColor } | null>;
  /** Currently dragging scene (from bank). */
  dragSceneId: string | null;
  roomId: string;
  /** Auto-promoted scene ids from integer 0-3 on first entry. */
  promotedSceneIds: Map<number, string>;
}

export type ArrangementEvent = JamArrangementSectionAdd | JamInputPad;

// ─── renderArrangementPads ───────────────────────────────────────────────────

export function renderArrangementPads(state: ArrangementModeState): PadState[] {
  const pads: PadState[] = [];

  // First entry: auto-promote integer scenes 0-3
  const promoted = new Map(state.promotedSceneIds);
  for (let i = 0; i < 4; i++) {
    if (!promoted.has(i)) {
      promoted.set(i, promoteSceneIndex(i, state.roomId));
    }
  }

  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      if (row === 7) {
        pads.push({ color: 'off', brightness: 0, label: '', pulse: false, active: false });
        continue;
      }

      if (row === 0) {
        // Timeline row: each col = 2 bars
        const bar = col * 2;
        const section = state.sections.find(
          (s) => bar >= s.startBar && bar < s.startBar + s.lengthBars,
        );
        if (section) {
          pads.push({
            color: section.color,
            brightness: 0.8,
            label: section.label.slice(0, 4),
            pulse: false,
            active: true,
          });
        } else {
          pads.push({
            color: 'dim',
            brightness: 0.07,
            label: String(bar + 1),
            pulse: false,
            active: false,
          });
        }
        continue;
      }

      // Scene bank rows 1-6
      const bankIdx = (row - 1) * 8 + col;
      const entry = state.sceneBank[bankIdx] ?? null;
      if (entry) {
        pads.push({
          color: entry.color,
          brightness: 0.5,
          label: entry.label.slice(0, 4),
          pulse: false,
          active: false,
        });
      } else {
        pads.push({ color: 'dim', brightness: 0.05, label: '·', pulse: false, active: false });
      }
    }
  }
  return pads;
}

// ─── handleArrangementPress ──────────────────────────────────────────────────

export interface ArrangementPressResult {
  events: ArrangementEvent[];
  stateChanges: Partial<ArrangementModeState>;
}

export function handleArrangementPress(
  padIndex: number,
  state: ArrangementModeState,
): ArrangementPressResult {
  const row = Math.floor(padIndex / 8);
  const col = padIndex % 8;
  const events: ArrangementEvent[] = [];
  const stateChanges: Partial<ArrangementModeState> = {};
  const ts = Date.now();

  events.push({
    family: 'jam.input.pad',
    surfaceId: 'grid-8x8',
    x: col,
    y: row,
    pressure: 0.8,
    velocity: 100,
    aftertouch: 0,
    ts,
    mode: 'arrangement',
  });

  if (row === 7) return { events, stateChanges };

  if (row === 0) {
    // Timeline tap: place dragged scene here
    if (state.dragSceneId) {
      const bar = col * 2;
      const lengthBars = 4; // default 4-bar section
      events.push({
        family: 'jam.arrangement.section.add',
        arrangementId: `arr-${state.roomId}`,
        section: {
          patternObjectId: state.dragSceneId,
          startBar: bar,
          lengthBars,
        },
      });
      const newSections = [
        ...state.sections,
        {
          sceneId: state.dragSceneId,
          startBar: bar,
          lengthBars,
          color: 'cyan' as PadColor,
          label: state.dragSceneId.slice(-4),
        },
      ];
      stateChanges.sections = newSections;
      stateChanges.dragSceneId = null;
    }
    return { events, stateChanges };
  }

  // Scene bank: select as drag source
  const bankIdx = (row - 1) * 8 + col;
  const entry = state.sceneBank[bankIdx] ?? null;
  if (entry) {
    stateChanges.dragSceneId = entry.sceneId;
  }
  return { events, stateChanges };
}

// ─── createArrangementModeState ──────────────────────────────────────────────

export function createArrangementModeState(roomId: string): ArrangementModeState {
  // Auto-promote scenes 0-3 on creation
  const promotedSceneIds = new Map<number, string>();
  for (let i = 0; i < 4; i++) {
    promotedSceneIds.set(i, promoteSceneIndex(i, roomId));
  }

  const sceneBank: ArrangementModeState['sceneBank'] = Array(48).fill(null);
  const sceneColors: PadColor[] = ['orange', 'cyan', 'green', 'purple'];
  const sceneLabels = ['A', 'B', 'C', 'D'];
  for (let i = 0; i < 4; i++) {
    const id = promotedSceneIds.get(i)!;
    sceneBank[i] = { sceneId: id, label: sceneLabels[i] ?? String(i), color: sceneColors[i] ?? 'dim' };
  }

  return {
    sections: [],
    sceneBank,
    dragSceneId: null,
    roomId,
    promotedSceneIds,
  };
}

```
