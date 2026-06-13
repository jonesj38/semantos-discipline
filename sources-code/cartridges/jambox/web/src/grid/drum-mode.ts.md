---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/grid/drum-mode.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.606248+00:00
---

# cartridges/jambox/web/src/grid/drum-mode.ts

```ts
/**
 * D-B.6 — Drum / Step (Sequencer) refinement.
 *
 * Step toggle emits `jam.pattern.step.toggle` referencing the selected
 * pattern's bound `rackId` from `jam.pattern`.
 *
 * Param pads bind to the rack's macro index when one matches the param name
 * (e.g. `decay → snap` macro on `jam.rack.drum-808`); fall back to raw
 * `jam.control.change` otherwise.
 *
 * Canonical macro name → drum param mapping (from contract.ts):
 *   0  brightness  → tone   (filter/spectral tilt)
 *   1  dirt        → drive  (waveshaper)
 *   2  wobble      → ring   (LFO depth / filter mod)
 *   3  space       → reverb (reverb send)
 *   4  snap        → decay  (envelope attack ↘ / transient)
 *   5  body        → volume (low-shelf / sub mix)
 *   6  chaos       → (no direct mapping)
 *   7  tension     → (no direct mapping)
 */

import type { ParamKey } from './surface';
import type {
  JamPatternStepToggle,
  JamRackMacroSet,
  JamControlChange,
  JamInputPad,
} from '../semantic/events';

// ─── Macro mapping ────────────────────────────────────────────────────────────

/**
 * Maps a drum param name to the rack macro index it drives.
 * Derived from the canonical macro vocabulary in contract.ts.
 * If a param has no macro match, returns -1 → fall back to jam.control.change.
 */
export const DRUM_PARAM_TO_MACRO_INDEX: Record<ParamKey, number> = {
  tone:   0,  // macro 0 = brightness (filter cutoff / spectral tilt)
  drive:  1,  // macro 1 = dirt (waveshaper / saturator)
  ring:   2,  // macro 2 = wobble (LFO depth)
  reverb: 3,  // macro 3 = space (reverb send)
  decay:  4,  // macro 4 = snap (envelope attack ↘ / transient ↗)
  volume: 5,  // macro 5 = body (low-shelf / sub mix)
  delay:  -1, // no canonical macro (raw CC)
  punch:  -1, // no canonical macro (raw CC)
  crack:  -1, // no canonical macro (raw CC)
  tune:   -1, // no canonical macro (raw CC)
  pan:    -1, // no canonical macro (raw CC)
};

// ─── Types ────────────────────────────────────────────────────────────────────

export type DrumStepEvent = JamPatternStepToggle | JamInputPad;
export type DrumParamEvent = JamRackMacroSet | JamControlChange | JamInputPad;

export interface DrumStepPressResult {
  events: DrumStepEvent[];
}

export interface DrumParamPressResult {
  events: DrumParamEvent[];
}

// ─── emitStepToggle ───────────────────────────────────────────────────────────

/**
 * Emit a canonical `jam.pattern.step.toggle` event for a step pad press.
 * The `patternId` is derived from the bound rackId + track name so it is
 * deterministic and idempotent on (rackId, track).
 *
 * Also always emits `jam.input.pad` alongside (additive).
 *
 * @param track    - The drum track name ('kick', 'snare', etc.)
 * @param stepIndex - 0-15 step index
 * @param on        - New on/off state
 * @param rackId    - The rack this pattern belongs to (from jam.pattern.racks[0])
 * @param row       - Grid row (for jam.input.pad)
 * @param col       - Grid column (for jam.input.pad)
 * @param patternId - Optional explicit patternId; auto-derived if omitted
 */
export function emitStepToggle(args: {
  track: string;
  stepIndex: number;
  on: boolean;
  rackId: string;
  row: number;
  col: number;
  patternId?: string;
}): DrumStepPressResult {
  const { track, stepIndex, on, rackId, row, col } = args;
  const patternId = args.patternId ?? `pattern:${rackId}:${track}`;

  const events: DrumStepEvent[] = [
    {
      family: 'jam.input.pad',
      surfaceId: 'grid-8x8',
      x: col,
      y: row,
      pressure: 0.8,
      velocity: 100,
      aftertouch: 0,
      ts: Date.now(),
      mode: 'step',
      target: track,
    },
    {
      family: 'jam.pattern.step.toggle',
      patternId,
      lane: track,
      step: stepIndex,
      on,
    },
  ];

  return { events };
}

// ─── emitParamChange ──────────────────────────────────────────────────────────

/**
 * Emit either `jam.rack.macro.set` (when the param maps to a canonical macro)
 * or `jam.control.change` (raw fallback) for a param pad press.
 *
 * Also emits `jam.input.pad` alongside (additive).
 *
 * @param track    - The drum track name
 * @param paramKey - Which param was pressed (e.g. 'decay')
 * @param normValue - New normalised value 0-1
 * @param rackId   - The rack this track is bound to
 * @param row      - Grid row (for jam.input.pad)
 * @param col      - Grid column (for jam.input.pad)
 */
export function emitParamChange(args: {
  track: string;
  paramKey: ParamKey;
  normValue: number;
  rackId: string;
  row: number;
  col: number;
}): DrumParamPressResult {
  const { track, paramKey, normValue, rackId, row, col } = args;
  const macroIndex = DRUM_PARAM_TO_MACRO_INDEX[paramKey];

  const events: DrumParamEvent[] = [
    {
      family: 'jam.input.pad',
      surfaceId: 'grid-8x8',
      x: col,
      y: row,
      pressure: 0.8,
      velocity: 100,
      aftertouch: 0,
      ts: Date.now(),
      mode: 'param',
      target: track,
    },
  ];

  if (macroIndex >= 0) {
    // Canonical macro path
    events.push({
      family: 'jam.rack.macro.set',
      rackId,
      index: macroIndex,
      value: normValue,
    });
  } else {
    // Raw CC fallback
    events.push({
      family: 'jam.control.change',
      target: `${rackId}.${track}.${paramKey}`,
      value: normValue,
      curve: 'linear',
      ts: Date.now(),
    });
  }

  return { events };
}

// ─── patternIdForTrack ────────────────────────────────────────────────────────

/**
 * Derive a deterministic patternId from a rackId + track name.
 * Idempotent on (rackId, track). Matches the auto-derive logic in emitStepToggle.
 */
export function patternIdForTrack(rackId: string, track: string): string {
  return `pattern:${rackId}:${track}`;
}

// ─── defaultRackForTrack ─────────────────────────────────────────────────────

/**
 * Returns the default rack id for a drum track.
 * All built-in drum tracks default to 'jam.rack.drum-808'.
 * Callers should override this from the pattern's .racks array when available.
 */
export function defaultRackForTrack(_track: string): string {
  return 'jam.rack.drum-808';
}

```
