---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/router.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.613433+00:00
---

# cartridges/jambox/web/src/mappings/router.ts

```ts
/**
 * D-C.1 / D-C.7 Five-layer mapping pipeline router.
 *
 * Pipeline (strictly ordered — no layer skips):
 *
 *   1. Device     raw input → normalised DeviceEvent
 *   2. Surface    DeviceEvent → SurfaceEvent (pad / key / knob / fader / touch / xy / gamepad)
 *   3. Mode       Current GridMode decides meaning; chromatic guardrail enforced here
 *   4. Semantic   Emits canonical jam.input.* / jam.note.* / jam.rack.* cells
 *   5. Feedback   Reads room state → produces device-specific LED/label/haptic instructions
 *
 * Hard rules:
 *   - Devices emit DeviceEvent only — never jam.* cells directly.
 *   - Transforms are declarative (linear/exp/log/clamp); no eval().
 *   - Conflict resolution: last-touched device wins visual feedback; both produce events.
 *   - Note-mode chromatic guardrail: silently quantise unless mapping has
 *     `requires-permission: chromatic`.
 */

import type {
  JamboxMappingPayload,
  MappingInput,
  MappingTarget,
  MappingOutput,
  MappingTransform,
  MappingConstraint,
} from '../semantic/objects';
import type { JamEvent } from '../semantic/events';
import type { SurfaceId } from './registry';
import { intentReducer } from '../grid/intent-reducer';
import type { OverlayState } from '../grid/intent-reducer';

// ─── Layer 1: DeviceEvent ─────────────────────────────────────────────────────

export type DeviceEventKind =
  | 'pad.on'
  | 'pad.off'
  | 'key.on'
  | 'key.off'
  | 'knob'
  | 'fader'
  | 'touch.start'
  | 'touch.move'
  | 'touch.end'
  | 'xy'
  | 'gamepad.button.on'
  | 'gamepad.button.off'
  | 'gamepad.axis'
  | 'transport';

/**
 * Normalised event emitted exclusively by device adapters.
 * Values are always 0..1 (buttons) or -1..1 (axes / pitch-bend).
 */
export interface DeviceEvent {
  /** Discriminator. */
  kind: DeviceEventKind;
  /** Stable selector that matches MappingInput.selector. */
  selector: string | number;
  /** Primary value: 0..1 for notes/pads/knobs/faders, -1..1 for axes. */
  value: number;
  /** Secondary value for XY events (y axis). */
  value2?: number;
  /** MIDI channel (1-16) or undefined for non-MIDI devices. */
  channel?: number;
  /** Source device name for conflict resolution. */
  deviceName: string;
  /** Monotonic timestamp (ms). */
  ts: number;
}

// ─── Layer 2: SurfaceEvent ────────────────────────────────────────────────────

export interface SurfaceEvent {
  inputType: MappingInput['type'];
  selector: string | number;
  /** Transformed value (0..1 or -1..1 depending on axis). */
  value: number;
  value2?: number;
  deviceName: string;
  ts: number;
}

// ─── Layer 3: ModeEvent ───────────────────────────────────────────────────────

export interface ModeEvent {
  surface: SurfaceEvent;
  /** The resolved MappingInput from the active mapping. null if no binding. */
  binding: MappingInput | null;
  /** Whether this input is allowed in the current mode. */
  allowed: boolean;
  /** Set to true when a chromatic note was quantised to scale. */
  chromaticQuantised?: boolean;
  currentMode: string;
  surfaceId: SurfaceId;
}

// ─── Layer 4: SemanticEvent ───────────────────────────────────────────────────

export type SemanticEventKind =
  | 'jam.input.pad'
  | 'jam.input.key'
  | 'jam.input.knob'
  | 'jam.input.fader'
  | 'jam.input.touch'
  | 'jam.input.gamepad'
  | 'jam.note.on'
  | 'jam.note.off'
  | 'jam.note.expression'
  | 'jam.rack.macro.set'
  | 'jam.rack.trigger'
  | 'jam.pattern.step.toggle'
  | 'jam.clip.launch.queue'
  | 'jam.scene.launch'
  | 'jam.transport'
  | 'jam.mode.set';

export interface SemanticEvent {
  family: SemanticEventKind;
  target: MappingTarget;
  value: number;
  value2?: number;
  deviceName: string;
  surfaceId: SurfaceId;
  ts: number;
}

// ─── Layer 5: FeedbackInstruction ────────────────────────────────────────────

export interface FeedbackInstruction {
  deviceName: string;
  output: MappingOutput;
  /** The resolved colour / brightness / label value to send. */
  resolved: string | number;
}

// ─── Conflict state (D-C.7) ──────────────────────────────────────────────────

interface ConflictState {
  /** Last device to touch a given selector. */
  lastTouched: Map<string, string>;
}

// ─── MappingRouter ────────────────────────────────────────────────────────────

export interface RouterCallbacks {
  /** Called for each SemanticEvent that exits the pipeline. */
  onSemanticEvent(event: SemanticEvent): void;
  /** Called when a feedback instruction is ready for a device. */
  onFeedback(instruction: FeedbackInstruction): void;
  /** Called when a chromatic note is quantised (warning toast). */
  onChromaticQuantised?(selector: string | number, surfaceId: SurfaceId): void;
  /** Called when the intent reducer changes overlay state. */
  onOverlayChange?(state: Readonly<OverlayState>): void;
  /** Called when a JamEvent is emitted by the intent reducer. */
  onJamEvent?(event: JamEvent): void;
}

export interface RouterState {
  /** Current mode per surface. */
  modes: Map<SurfaceId, string>;
  /** Active scale for Note-mode guardrail (MIDI semitones 0..11 in the active scale). */
  scaleDegrees: Set<number>;
  /** Scale root MIDI note (0..11, default 0 = C). */
  scaleRoot: number;
}

export class MappingRouter {
  private readonly conflict: ConflictState = { lastTouched: new Map() };
  private readonly state: RouterState = {
    modes: new Map(),
    scaleDegrees: new Set([0, 2, 4, 5, 7, 9, 11]), // major scale default
    scaleRoot: 0,
  };

  constructor(private readonly cb: RouterCallbacks) {
    intentReducer.setFireCallback((ev) => {
      this.cb.onJamEvent?.({
        family: 'jam.extension.fire',
        extensionId: ev.extensionId,
        ownerIdentity: ev.ownerIdentity,
        intent: ev.intent,
        surfaceId: ev.surfaceId,
        ts: ev.ts,
      });
    });
  }

  // ── State setters ─────────────────────────────────────────────────────────

  setMode(surfaceId: SurfaceId, mode: string): void {
    this.state.modes.set(surfaceId, mode);
  }

  setScale(root: number, degrees: number[]): void {
    this.state.scaleRoot = root;
    this.state.scaleDegrees = new Set(degrees);
  }

  // ── Pipeline entry point ──────────────────────────────────────────────────

  /**
   * Route a DeviceEvent through all five layers.
   *
   * @param deviceEvent  Raw normalised event from a device adapter (layer 1).
   * @param surfaceId    Surface this device is mapped to.
   * @param mapping      Active mapping payload for this surface.
   */
  route(
    deviceEvent: DeviceEvent,
    surfaceId: SurfaceId,
    mapping: JamboxMappingPayload,
  ): void {
    // ── Layer 2: surface ──────────────────────────────────────────────────
    const surfaceEvent = this.toSurfaceEvent(deviceEvent);

    // ── Layer 3: mode ─────────────────────────────────────────────────────
    const modeEvent = this.applyMode(surfaceEvent, surfaceId, mapping);
    if (!modeEvent.allowed && !modeEvent.chromaticQuantised) return;

    // ── Layer 3½: intent reduction ──────────────────────────────────────────
    const isPress = deviceEvent.kind === 'pad.on' || deviceEvent.kind === 'key.on';
    const isRelease = deviceEvent.kind === 'pad.off' || deviceEvent.kind === 'key.off';
    if (isPress || isRelease) {
      intentReducer.trackHold(surfaceEvent, isPress);
    }
    const currentMode = this.state.modes.get(surfaceId) ?? 'global';
    const reduction = intentReducer.reduce(surfaceEvent, currentMode, surfaceId, {
      root: this.state.scaleRoot,
      degrees: this.state.scaleDegrees,
    });
    if (reduction.kind === 'suppress' || reduction.kind === 'momentary' || reduction.kind === 'latch') {
      this.cb.onOverlayChange?.(intentReducer.getOverlayState());
      return;
    }
    if (reduction.kind === 'compound' || reduction.kind === 'emit') {
      for (const ev of reduction.events ?? []) {
        this.cb.onJamEvent?.(ev);
      }
      this.cb.onOverlayChange?.(intentReducer.getOverlayState());
      return;
    }
    // 'pass' → fall through to Layer 4

    // ── Layer 4: semantic ─────────────────────────────────────────────────
    if (!modeEvent.binding) return;
    const semEvent = this.toSemanticEvent(modeEvent, mapping);
    if (!semEvent) return;
    this.cb.onSemanticEvent(semEvent);

    // ── Conflict resolution (D-C.7) ───────────────────────────────────────
    const conflictKey = targetKey(modeEvent.binding.target);
    this.conflict.lastTouched.set(conflictKey, deviceEvent.deviceName);

    // ── Layer 5: feedback ─────────────────────────────────────────────────
    this.applyFeedback(deviceEvent.deviceName, conflictKey, mapping);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Layer 2 — Device → Surface
  // ─────────────────────────────────────────────────────────────────────────

  private toSurfaceEvent(de: DeviceEvent): SurfaceEvent {
    const inputType = deviceKindToInputType(de.kind);
    return {
      inputType,
      selector: de.selector,
      value: de.value,
      value2: de.value2,
      deviceName: de.deviceName,
      ts: de.ts,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Layer 3 — Surface → Mode
  // ─────────────────────────────────────────────────────────────────────────

  private applyMode(
    se: SurfaceEvent,
    surfaceId: SurfaceId,
    mapping: JamboxMappingPayload,
  ): ModeEvent {
    const currentMode = this.state.modes.get(surfaceId) ?? 'global';
    const binding = findBinding(mapping, se) ?? null;

    // In Custom mode: bypass built-in mode rules entirely (§C.5/§C.6)
    if (currentMode === 'custom') {
      return { surface: se, binding, allowed: binding !== null, currentMode, surfaceId };
    }

    if (!binding) {
      // No binding → allowed to pass through as raw input.pad/key/etc.
      return { surface: se, binding: null, allowed: true, currentMode, surfaceId };
    }

    // Chromatic guardrail in Note mode (D-B.7 / D-C.7)
    if (currentMode === 'note' && binding.target.kind === 'rack.note') {
      const hasChromaticPermission = (mapping.constraints ?? []).some(
        (c: MappingConstraint) => c.kind === 'requires-permission' && c.value === 'chromatic',
      );
      if (!hasChromaticPermission) {
        const pitch = Math.round(se.value * 127);
        const pitchClass = (pitch - this.state.scaleRoot + 1200) % 12;
        if (!this.state.scaleDegrees.has(pitchClass)) {
          // Quantise: find the nearest in-scale pitch class
          const quantised = nearestScalePitch(pitch, this.state.scaleRoot, this.state.scaleDegrees);
          const quantisedSurface: SurfaceEvent = {
            ...se,
            value: quantised / 127,
          };
          this.cb.onChromaticQuantised?.(se.selector, surfaceId);
          return {
            surface: quantisedSurface,
            binding,
            allowed: true,
            chromaticQuantised: true,
            currentMode,
            surfaceId,
          };
        }
      }
    }

    return { surface: se, binding, allowed: true, currentMode, surfaceId };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Layer 4 — Mode → Semantic
  // ─────────────────────────────────────────────────────────────────────────

  private toSemanticEvent(me: ModeEvent, _mapping: JamboxMappingPayload): SemanticEvent | null {
    const { binding, surface, surfaceId } = me;
    if (!binding) return null;

    const transformed = applyTransform(surface.value, binding.transform);
    const target = binding.target;

    const family = targetToFamily(target, surface.value, binding.type);
    if (!family) return null;

    return {
      family,
      target,
      value: transformed,
      value2: surface.value2,
      deviceName: surface.deviceName,
      surfaceId,
      ts: surface.ts,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Layer 5 — Feedback
  // ─────────────────────────────────────────────────────────────────────────

  private applyFeedback(
    deviceName: string,
    conflictKey: string,
    mapping: JamboxMappingPayload,
  ): void {
    // Conflict resolution: only the last-touched device gets visual feedback
    const lastDevice = this.conflict.lastTouched.get(conflictKey);
    if (lastDevice && lastDevice !== deviceName) return;

    for (const output of mapping.outputs) {
      const resolved = resolveOutput(output);
      if (resolved === null) continue;
      this.cb.onFeedback({
        deviceName,
        output,
        resolved,
      });
    }
  }

  // ── Accessors ─────────────────────────────────────────────────────────────

  getLastTouched(conflictKey: string): string | undefined {
    return this.conflict.lastTouched.get(conflictKey);
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function deviceKindToInputType(kind: DeviceEventKind): MappingInput['type'] {
  switch (kind) {
    case 'pad.on': case 'pad.off': return 'pad';
    case 'key.on': case 'key.off': return 'key';
    case 'knob': return 'knob';
    case 'fader': return 'fader';
    case 'touch.start': case 'touch.move': case 'touch.end': return 'touch';
    case 'xy': return 'xy';
    case 'gamepad.button.on': case 'gamepad.button.off': return 'gamepad-button';
    case 'gamepad.axis': return 'gamepad-axis';
    case 'transport': return 'transport';
  }
}

function findBinding(mapping: JamboxMappingPayload, se: SurfaceEvent): MappingInput | undefined {
  return mapping.inputs.find(
    (i) => i.type === se.inputType && selectorMatch(i.selector, se.selector),
  );
}

function selectorMatch(a: string | number, b: string | number): boolean {
  if (typeof a === typeof b) return a === b;
  return String(a) === String(b);
}

function applyTransform(value: number, t: MappingTransform | undefined): number {
  if (!t) return value;
  const v = Math.max(0, Math.min(1, value));
  switch (t.kind) {
    case 'linear': {
      const lo = t.min ?? 0;
      const hi = t.max ?? 1;
      return lo + v * (hi - lo);
    }
    case 'exp': {
      const g = t.gamma ?? 2;
      return Math.pow(v, g);
    }
    case 'log': {
      const g = t.gamma ?? 2;
      return v <= 0 ? 0 : Math.pow(v, 1 / g);
    }
    case 'clamp': {
      const lo = t.min ?? 0;
      const hi = t.max ?? 1;
      return Math.max(lo, Math.min(hi, v));
    }
  }
}

function targetToFamily(
  target: MappingTarget,
  value: number,
  inputType: MappingInput['type'],
): SemanticEventKind | null {
  switch (target.kind) {
    case 'mode': return 'jam.mode.set';
    case 'rack.macro': return 'jam.rack.macro.set';
    case 'rack.note': return value > 0 ? 'jam.note.on' : 'jam.note.off';
    case 'rack.trigger': return 'jam.rack.trigger';
    case 'pattern.step': return 'jam.pattern.step.toggle';
    case 'clip.launch': return 'jam.clip.launch.queue';
    case 'scene.launch': return 'jam.scene.launch';
    case 'transport': return 'jam.transport';
  }
  // Input-type fallback for unbound pass-through
  if (inputType === 'pad') return 'jam.input.pad';
  if (inputType === 'key') return 'jam.input.key';
  if (inputType === 'knob') return 'jam.input.knob';
  if (inputType === 'fader') return 'jam.input.fader';
  if (inputType === 'touch') return 'jam.input.touch';
  if (inputType === 'xy' || inputType === 'gamepad-axis') return 'jam.input.gamepad';
  if (inputType === 'gamepad-button') return 'jam.input.gamepad';
  return null;
}

function targetKey(target: MappingTarget): string {
  switch (target.kind) {
    case 'mode': return `mode:${target.mode}`;
    case 'rack.macro': return `macro:${target.rackId}:${target.macro}`;
    case 'rack.note': return `note:${target.rackId}`;
    case 'rack.trigger': return `trigger:${target.rackId}:${target.voiceId}`;
    case 'pattern.step': return `step:${target.patternId}:${target.lane}:${target.step}`;
    case 'clip.launch': return `clip:${target.clipId}`;
    case 'scene.launch': return `scene:${target.sceneId}`;
    case 'transport': return `transport:${target.verb}`;
    default: return 'unknown';
  }
}

function resolveOutput(output: MappingOutput): string | number | null {
  // Placeholder: in the full implementation the feedback layer reads live room
  // state.  Here we return a sentinel so tests can verify feedback is produced.
  switch (output.source) {
    case 'scale.degree': return output.projection === 'colour' ? '#ffffff' : 1;
    case 'clip.state':   return output.projection === 'colour' ? '#00ff00' : 1;
    case 'scene.state':  return output.projection === 'colour' ? '#0000ff' : 1;
    case 'transport.state': return output.projection === 'colour' ? '#ff0000' : 1;
    default: return 1;
  }
}

function nearestScalePitch(pitch: number, root: number, degrees: Set<number>): number {
  let nearest = pitch;
  let bestDist = Infinity;
  for (let delta = -6; delta <= 6; delta++) {
    const candidate = pitch + delta;
    const pc = (candidate - root + 1200) % 12;
    if (degrees.has(pc)) {
      const dist = Math.abs(delta);
      if (dist < bestDist) { bestDist = dist; nearest = candidate; }
    }
  }
  return Math.max(0, Math.min(127, nearest));
}

/** Singleton router — share across the jam-room. */
export const mappingRouter = new MappingRouter({
  onSemanticEvent: (_ev) => { /* default: no-op; main.ts overrides via setCallbacks */ },
  onFeedback: (_fb) => { /* default: no-op */ },
});

```
