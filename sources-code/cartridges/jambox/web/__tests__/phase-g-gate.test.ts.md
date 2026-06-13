---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/__tests__/phase-g-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.601876+00:00
---

# cartridges/jambox/web/__tests__/phase-g-gate.test.ts

```ts
/**
 * D-G.11 — Phase G gate test (web side).
 *
 * Asserts:
 *   1. Responsive layout breakpoints are correct at 1440/1024/768/414px.
 *   2. Mobile-plan boot does NOT include L4 (Three.js bundle gate).
 *   3. Phone profile D-G.7 additions: gyroscope, accelerometer, multi-touch.
 *   4. Scale-colour: colourForPitch spot checks (parity smoke test).
 *   5. Phase A / B / C / D / E gate re-runs.
 */

import { describe, it, expect } from 'vitest';

import { PHONE_PROFILE } from '../src/mappings/profiles/phone';
import { colourForPitch, classifyPitch } from '../src/colour/scale-colour';
import { mobilePlan, tabletPlan, desktopPlan } from '../src/world/viewport-plans';
import { pickViewportPlan } from '../src/ui/viewport-plan';

// ── Prior phase gates ─────────────────────────────────────────────────────────
import './phase-a-gate.test';
import './phase-b-gate.test';
import './phase-c-gate.test';
import './phase-d-gate.test';
// Phase E gate is in jam-room-e-3d-surface branch; not yet merged into this branch.

// ─────────────────────────────────────────────────────────────────────────────

// ── G-1. Responsive layout breakpoints ───────────────────────────────────────

describe('G-1 — Responsive layout breakpoints', () => {
  it('1440px → desktopPlan', () => {
    expect(pickViewportPlan(1440)).toBe(desktopPlan);
  });

  it('1920px → desktopPlan', () => {
    expect(pickViewportPlan(1920)).toBe(desktopPlan);
  });

  it('1024px → tabletPlan', () => {
    expect(pickViewportPlan(1024)).toBe(tabletPlan);
  });

  it('768px → tabletPlan', () => {
    expect(pickViewportPlan(768)).toBe(tabletPlan);
  });

  it('601px → tabletPlan', () => {
    expect(pickViewportPlan(601)).toBe(tabletPlan);
  });

  it('600px → mobilePlan', () => {
    expect(pickViewportPlan(600)).toBe(mobilePlan);
  });

  it('414px → mobilePlan', () => {
    expect(pickViewportPlan(414)).toBe(mobilePlan);
  });

  it('mobilePlan active placement = bottom-tab-bar', () => {
    expect(mobilePlan.placements.active).toBe('bottom-tab-bar');
  });

  it('tabletPlan active placement = tab-row', () => {
    expect(tabletPlan.placements.active).toBe('tab-row');
  });

  it('desktopPlan active placement = left-wall', () => {
    expect(desktopPlan.placements.active).toBe('left-wall');
  });

  it('mobilePlan anchor = sticky-top', () => {
    expect(mobilePlan.placements.anchor).toBe('sticky-top');
  });

  it('tabletPlan anchor = hero', () => {
    expect(tabletPlan.placements.anchor).toBe('hero');
  });

  it('desktopPlan anchor = top-band', () => {
    expect(desktopPlan.placements.anchor).toBe('top-band');
  });
});

// ── G-2. Mobile-plan Three.js gate ────────────────────────────────────────────

describe('G-2 — Mobile-plan Three.js bundle gate', () => {
  it('mobilePlan does NOT surface L4', () => {
    expect(mobilePlan.surfacedLayers).not.toContain('L4');
  });

  it('tabletPlan does NOT surface L4', () => {
    expect(tabletPlan.surfacedLayers).not.toContain('L4');
  });

  it('desktopPlan surfaces L4 (Three.js permitted)', () => {
    expect(desktopPlan.surfacedLayers).toContain('L4');
  });

  it('Three.js gate: surfacedLayers.includes(L4) is false for mobile', () => {
    const shouldLoadThree = mobilePlan.surfacedLayers.includes('L4');
    expect(shouldLoadThree).toBe(false);
  });

  it('Three.js gate: surfacedLayers.includes(L4) is true for desktop', () => {
    const shouldLoadThree = desktopPlan.surfacedLayers.includes('L4');
    expect(shouldLoadThree).toBe(true);
  });
});

// ── G-3. Phone profile D-G.7: gyroscope + accelerometer routing ──────────────

describe('G-3 — Phone profile D-G.7 gyroscope + accelerometer routing', () => {
  it('has orientation.alpha input (gyroscope Z / compass heading)', () => {
    const inp = PHONE_PROFILE.inputs.find(
      (i) => i.selector === 'orientation.alpha',
    );
    expect(inp).toBeDefined();
    expect(inp!.type).toBe('gamepad-axis');
    expect(inp!.target).toMatchObject({ kind: 'rack.macro', macro: 6 });
  });

  it('has motion.accel.z input (DeviceMotion accelerometer Z)', () => {
    const inp = PHONE_PROFILE.inputs.find(
      (i) => i.selector === 'motion.accel.z',
    );
    expect(inp).toBeDefined();
    expect(inp!.type).toBe('gamepad-axis');
    expect(inp!.target).toMatchObject({ kind: 'rack.macro', macro: 7 });
  });

  it('has orientation.beta input (forward tilt → macro 4)', () => {
    const inp = PHONE_PROFILE.inputs.find(
      (i) => i.selector === 'orientation.beta',
    );
    expect(inp).toBeDefined();
    expect(inp!.target).toMatchObject({ kind: 'rack.macro', macro: 4 });
  });

  it('has orientation.gamma input (side tilt → macro 5)', () => {
    const inp = PHONE_PROFILE.inputs.find(
      (i) => i.selector === 'orientation.gamma',
    );
    expect(inp).toBeDefined();
    expect(inp!.target).toMatchObject({ kind: 'rack.macro', macro: 5 });
  });

  it('has 10 multi-touch inputs', () => {
    const touchInputs = PHONE_PROFILE.inputs.filter((i) => i.type === 'touch');
    expect(touchInputs).toHaveLength(10);
  });

  it('multi-touch pointers are sequentially numbered', () => {
    const touchInputs = PHONE_PROFILE.inputs.filter((i) => i.type === 'touch');
    for (let idx = 0; idx < 10; idx++) {
      expect(touchInputs[idx]!.selector).toBe(`touch.pointer.${idx}`);
    }
  });

  it('three-finger-tap gesture routes to gesture:propose', () => {
    const g = PHONE_PROFILE.inputs.find(
      (i) => i.selector === 'touch.three-finger-tap',
    );
    expect(g).toBeDefined();
    expect(g!.type).toBe('gesture');
    expect((g!.target as { kind: string; gestureKind: string }).gestureKind).toBe('propose');
  });

  it('PHONE_PROFILE version is 1.1.0', () => {
    expect(PHONE_PROFILE.version).toBe('1.1.0');
  });
});

// ── G-4. Scale-colour parity smoke test ──────────────────────────────────────

describe('G-4 — Scale-colour parity smoke tests', () => {
  it('C (60) in C major, boomwhacker → root class, gold-ring border', () => {
    const cls = classifyPitch(60, 'major', 0);
    expect(cls).toBe('root');
    const spec = colourForPitch(60, 'major', 0, 'boomwhacker', 'off');
    expect(spec.border).toBe('gold-ring');
  });

  it('D (62) in C major → in-scale, no border', () => {
    const cls = classifyPitch(62, 'major', 0);
    expect(cls).toBe('in-scale');
    const spec = colourForPitch(62, 'major', 0, 'boomwhacker', 'off');
    expect(spec.border).toBeUndefined();
  });

  it('C# (61) in C major → chromatic, chromatic-edge border', () => {
    const cls = classifyPitch(61, 'major', 0);
    expect(cls).toBe('chromatic');
    const spec = colourForPitch(61, 'major', 0, 'boomwhacker', 'off');
    expect(spec.border).toBe('chromatic-edge');
  });

  it('Dorian characteristic note (A=9 from root C=0) → modal, modal-tick border', () => {
    const cls = classifyPitch(9, 'dorian', 0);
    expect(cls).toBe('modal');
    const spec = colourForPitch(9, 'dorian', 0, 'boomwhacker', 'off');
    expect(spec.border).toBe('modal-tick');
  });

  it('Chromatic pads have reduced saturation and brightness', () => {
    const chromSpec = colourForPitch(61, 'major', 0, 'boomwhacker', 'off');
    const inScaleSpec = colourForPitch(62, 'major', 0, 'boomwhacker', 'off');
    expect(chromSpec.saturation).toBeLessThan(inScaleSpec.saturation);
    expect(chromSpec.brightness).toBeLessThan(inScaleSpec.brightness);
  });

  it('note-name label mode returns correct pitch name', () => {
    // MIDI 60 = C4 (standard: octave = floor(60/12) - 1 = 4)
    const spec = colourForPitch(60, 'major', 0, 'boomwhacker', 'note-name');
    expect(spec.label).toBe('C4');
  });

  it('off label mode returns no label', () => {
    const spec = colourForPitch(60, 'major', 0, 'boomwhacker', 'off');
    expect(spec.label).toBeUndefined();
  });
});

```
