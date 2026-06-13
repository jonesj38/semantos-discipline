---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/profiles/phone.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.627721+00:00
---

# cartridges/jambox/web/src/mappings/profiles/phone.ts

```ts
/**
 * D-C.3 + D-G.7 Phone-as-controller built-in profile.
 *
 * Phase C baseline:
 *   XY touch (pointer)         = rack macro 0 (brightness) / macro 1 (dirt)
 *   Accelerometer Z            = macro 7 (chaos)  — phone shake
 *   Gyroscope Y (tilt forward) = macro 6 (body)   — phone tilt
 *   Tap buttons (8 pads)       = trigger drum rack
 *
 * Phase G additions (D-G.7):
 *   Multi-touch grid (up to 10 touches)  = melodic pad notes on poly-keys
 *   Tilt → XY  (DeviceOrientation beta/gamma) = macro 4 (brightness) / macro 5 (tension)
 *   Accelerometer Z (DeviceMotion) → macro 7 (chaos)   — updated to DeviceMotion selector
 *   Gyroscope Z (DeviceOrientation alpha) → macro 6 (body)   — full rotation axis
 *   Three-finger-tap → jam.gesture { kind: 'propose' }
 *
 * ALL sensors work via DeviceMotion / DeviceOrientation / PointerEvents —
 * NO Web MIDI required.  Works on iPhone Safari (iOS 13+ with one-time
 * permission prompt for DeviceMotion/Orientation).
 *
 * The iOS DeviceMotion permission prompt is handled in the phone adapter
 * (src/mappings/devices/phone-adapter.ts) on first activation — the profile
 * JSON itself is portable and carries no platform-specific fields.
 *
 * Profile JSON is UNCHANGED from desktop format.  No Dart-specific fields.
 */

import type { JamboxMappingPayload, MappingInput } from '../../semantic/objects';

// ─── Phase C: XY single-touch ────────────────────────────────────────────────

function xyInputs(): MappingInput[] {
  return [
    {
      type: 'xy',
      selector: 'touch.xy',
      target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 0 },
      transform: { kind: 'linear', min: 0, max: 1 },
    },
  ];
}

// ─── Phase G: Multi-touch grid (up to 10 simultaneous touches) ───────────────

/**
 * Multi-touch grid: each pointer index maps to a scale-locked melodic note.
 * Pointer IDs 0-9 correspond to up to 10 simultaneous touches.
 * Note selection is handled by the phone adapter which projects pointer
 * position onto the current scale's note grid.
 */
function multiTouchInputs(): MappingInput[] {
  return Array.from({ length: 10 }, (_, i): MappingInput => ({
    type: 'touch',
    selector: `touch.pointer.${i}`,
    target: {
      kind: 'rack.trigger',
      rackId: 'jam.rack.poly-keys',
      voiceId: `touch${i}`,
    },
  }));
}

// ─── Phase C + G: Sensor inputs ──────────────────────────────────────────────

function sensorInputs(): MappingInput[] {
  return [
    // ── Phase G: Tilt → XY (DeviceOrientation beta / gamma) ──────────────────
    // beta  = forward/back tilt (−180..180° when held portrait)  → macro 4 (brightness)
    // gamma = left/right tilt  (−90..90°)                        → macro 5 (tension)
    {
      type: 'gamepad-axis',
      selector: 'orientation.beta',
      target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 4 },
      transform: { kind: 'linear', min: -90, max: 90 },
    },
    {
      type: 'gamepad-axis',
      selector: 'orientation.gamma',
      target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 5 },
      transform: { kind: 'linear', min: -45, max: 45 },
    },

    // ── Phase G: Accelerometer Z (DeviceMotion) → macro 7 (chaos) ────────────
    // Updated selector from Phase C's 'accel.z' to 'motion.accel.z' for
    // DeviceMotion API alignment.  The Phase C selector is kept as an alias
    // in the device adapter for backwards compatibility.
    {
      type: 'gamepad-axis',
      selector: 'motion.accel.z',
      target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 7 },
      transform: { kind: 'clamp', min: 0, max: 1 },
    },

    // ── Phase G: Gyroscope Z (DeviceOrientation alpha) → macro 6 (body) ──────
    // alpha = compass heading (0..360° on iOS; unreliable without calibration).
    // Normalised to 0-1 by the transform.
    {
      type: 'gamepad-axis',
      selector: 'orientation.alpha',
      target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 6 },
      transform: { kind: 'linear', min: 0, max: 360 },
    },
  ];
}

// ─── Phase C: 8 tap-pad inputs ───────────────────────────────────────────────

function padInputs(): MappingInput[] {
  return Array.from({ length: 8 }, (_, i): MappingInput => ({
    type: 'pad',
    selector: i,
    target: {
      kind: 'rack.trigger',
      rackId: 'jam.rack.drum-808',
      voiceId: `pad${i}`,
    },
  }));
}

// ─── Phase C: Transport buttons ──────────────────────────────────────────────

function transportInputs(): MappingInput[] {
  return [
    { type: 'transport', selector: 'btn.play', target: { kind: 'transport', verb: 'play' } },
    { type: 'transport', selector: 'btn.stop', target: { kind: 'transport', verb: 'stop' } },
  ];
}

// ─── Phase G: Three-finger-tap → jam.gesture { kind: 'propose' } ─────────────

/**
 * Three-finger-tap gesture: a simultaneous 3-pointer touch event dispatches
 * a jam.gesture cell with kind='propose', allowing the phone to propose a
 * scene transition or arrangement action to all room participants.
 *
 * Detected in the phone adapter as a PointerEvent cluster with pointerCount=3
 * and a tap duration < 300 ms.
 */
function gestureInputs(): MappingInput[] {
  return [
    {
      type: 'gesture',
      selector: 'touch.three-finger-tap',
      target: { kind: 'gesture', gestureKind: 'propose' },
    },
  ];
}

// ─── Profile export ───────────────────────────────────────────────────────────

export const PHONE_PROFILE: JamboxMappingPayload = {
  name: 'Phone Controller',
  author: 'semantos-built-in',
  surfaceShape: 'phone',
  inputs: [
    ...xyInputs(),
    ...multiTouchInputs(),
    ...sensorInputs(),
    ...padInputs(),
    ...transportInputs(),
    ...gestureInputs(),
  ],
  outputs: [],
  version: '1.1.0',   // bumped for Phase G additions
  license: 'personal',
};

```
