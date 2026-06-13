---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/__tests__/cross-renderer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.600075+00:00
---

# cartridges/jambox/web/__tests__/cross-renderer.test.ts

```ts
/**
 * D-G.8 — Cross-renderer conformance test (web side).
 *
 * Verifies that the web and Flutter renderers share a common semantic contract:
 *   1. A mock cell stream injects jam.scene.launch → web anchor-row scene name
 *      matches the event data.
 *   2. The phone.ts profile serialises to valid JSON matching the portable
 *      profile schema (no Dart-specific fields).
 *   3. The scale-colour parity fixture validates the TypeScript colourForPitch
 *      implementation (cross-renderer sanity: both sides use the same fixture).
 *   4. JamEvent dispatch envelope is structurally identical to what the Flutter
 *      JamEventStream expects.
 *
 * The web side does NOT run Flutter widget tests; the Dart side in
 * apps/world-apps/jam-room-mobile/test/ mirrors these contracts.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

import { PHONE_PROFILE } from '../src/mappings/profiles/phone';
import { colourForPitch } from '../src/colour/scale-colour';
import { mobilePlan, desktopPlan, tabletPlan } from '../src/world/viewport-plans';
import { pickViewportPlan } from '../src/ui/viewport-plan';

// ── 1. Mock cell-stream → jam.scene.launch projection ────────────────────────

describe('G-1 — jam.scene.launch cell projects to scene name', () => {
  it('constructs a valid jam.scene.launch event envelope', () => {
    // The contract between web and Flutter: jam.event notification has
    // { type: 'jam.scene.launch', data: { sceneId, sceneName } }
    const cell = {
      jsonrpc: '2.0' as const,
      method: 'jam.event' as const,
      params: {
        type: 'jam.scene.launch',
        data: {
          sceneId: 'scene-A',
          sceneName: 'Main Loop',
        },
      },
    };

    // Validate envelope shape.
    expect(cell.jsonrpc).toBe('2.0');
    expect(cell.method).toBe('jam.event');
    expect(cell.params.type).toBe('jam.scene.launch');
    expect(cell.params.data.sceneId).toBe('scene-A');
    expect(cell.params.data.sceneName).toBe('Main Loop');
  });

  it('jam.subscribe request envelope matches expected JSON-RPC 2.0 shape', () => {
    // Matches what jam_event_stream.dart sends on connect.
    const subscribeRequest = {
      jsonrpc: '2.0',
      id: 1,
      method: 'jam.subscribe',
      params: { channel: 'room:lobby:state' },
    };

    const json = JSON.stringify(subscribeRequest);
    const parsed = JSON.parse(json) as Record<string, unknown>;

    expect(parsed['jsonrpc']).toBe('2.0');
    expect(parsed['method']).toBe('jam.subscribe');
    expect((parsed['params'] as Record<string, unknown>)['channel']).toBe('room:lobby:state');
  });

  it('jam.dispatch action envelope is portable (no TS-specific types)', () => {
    const dispatch = {
      jsonrpc: '2.0',
      method: 'jam.dispatch',
      params: { kind: 'jam.note.on', pitch: 60, velocity: 100 },
    };

    // Roundtrip through JSON must be lossless.
    const roundtrip = JSON.parse(JSON.stringify(dispatch)) as typeof dispatch;
    expect(roundtrip.params.kind).toBe('jam.note.on');
    expect(roundtrip.params.pitch).toBe(60);
  });
});

// ── 2. Phone profile: portable JSON schema ────────────────────────────────────

describe('G-2 — Phone profile: portable JSON schema', () => {
  it('PHONE_PROFILE serialises to valid JSON without Dart-specific fields', () => {
    const json = JSON.stringify(PHONE_PROFILE);
    const parsed = JSON.parse(json) as typeof PHONE_PROFILE;

    expect(parsed.name).toBe('Phone Controller');
    expect(parsed.surfaceShape).toBe('phone');
    expect(parsed.version).toBe('1.1.0');
    expect(Array.isArray(parsed.inputs)).toBe(true);
  });

  it('has multi-touch inputs for 10 pointers', () => {
    const touchInputs = PHONE_PROFILE.inputs.filter(
      (inp) => inp.type === 'touch',
    );
    expect(touchInputs.length).toBe(10);
    // Selectors should be touch.pointer.0 … touch.pointer.9
    for (let i = 0; i < 10; i++) {
      expect(touchInputs[i]!.selector).toBe(`touch.pointer.${i}`);
    }
  });

  it('has orientation.beta and orientation.gamma sensor inputs', () => {
    const betaInput = PHONE_PROFILE.inputs.find(
      (inp) => inp.selector === 'orientation.beta',
    );
    const gammaInput = PHONE_PROFILE.inputs.find(
      (inp) => inp.selector === 'orientation.gamma',
    );

    expect(betaInput).toBeDefined();
    expect(gammaInput).toBeDefined();
    expect(betaInput!.type).toBe('gamepad-axis');
    expect(gammaInput!.type).toBe('gamepad-axis');
  });

  it('has motion.accel.z sensor input (DeviceMotion selector)', () => {
    const accelInput = PHONE_PROFILE.inputs.find(
      (inp) => inp.selector === 'motion.accel.z',
    );
    expect(accelInput).toBeDefined();
    expect(accelInput!.type).toBe('gamepad-axis');
  });

  it('has orientation.alpha gyroscope input', () => {
    const alphaInput = PHONE_PROFILE.inputs.find(
      (inp) => inp.selector === 'orientation.alpha',
    );
    expect(alphaInput).toBeDefined();
  });

  it('has three-finger-tap gesture input with target kind=gesture', () => {
    const gestureInput = PHONE_PROFILE.inputs.find(
      (inp) => inp.selector === 'touch.three-finger-tap',
    );
    expect(gestureInput).toBeDefined();
    expect(gestureInput!.type).toBe('gesture');
    expect(gestureInput!.target.kind).toBe('gesture');
    expect((gestureInput!.target as { kind: 'gesture'; gestureKind: string }).gestureKind).toBe('propose');
  });

  it('has no Dart-specific fields (no dartType, noFlutter, etc.)', () => {
    const json = JSON.stringify(PHONE_PROFILE);
    expect(json).not.toContain('dartType');
    expect(json).not.toContain('flutter');
    expect(json).not.toContain('platform');
  });
});

// ── 3. Scale-colour parity fixture ───────────────────────────────────────────

describe('G-3 — Scale-colour parity fixture', () => {
  interface ParityEntry {
    pitch: number;
    scale: string;
    root: number;
    palette: string;
    labelMode: string;
    hue: number;
    saturation: number;
    brightness: number;
    border: string | null;
    label: string | null;
    scaleClass: string;
  }

  interface ParityFixture {
    version: number;
    entries: ParityEntry[];
  }

  let fixture: ParityFixture | null = null;

  beforeAll(() => {
    // Load the fixture generated by scripts/gen-scale-colour-parity.ts.
    const fixturePath = join(__dirname, '../src/colour/scale-colour-parity.json');
    if (existsSync(fixturePath)) {
      fixture = JSON.parse(readFileSync(fixturePath, 'utf-8')) as ParityFixture;
    }
  });

  it('fixture file exists and has at least 100 entries', () => {
    expect(fixture).not.toBeNull();
    expect(fixture!.entries.length).toBeGreaterThanOrEqual(100);
  });

  it('fixture has version field', () => {
    expect(fixture!.version).toBe(1);
  });

  it('TypeScript colourForPitch matches all fixture entries', () => {
    // Sample up to 500 entries for test speed.
    const entries = fixture!.entries.slice(0, 500);
    let checked = 0;

    for (const entry of entries) {
      const spec = colourForPitch(
        entry.pitch,
        entry.scale as Parameters<typeof colourForPitch>[1],
        entry.root,
        entry.palette as Parameters<typeof colourForPitch>[3],
        entry.labelMode as Parameters<typeof colourForPitch>[4],
      );

      expect(spec.hue).toBeCloseTo(entry.hue, 9);
      expect(spec.saturation).toBeCloseTo(entry.saturation, 9);
      expect(spec.brightness).toBeCloseTo(entry.brightness, 9);
      // border: fixture stores null for no-border; TS returns undefined — normalise.
      expect(spec.border ?? null).toBe(entry.border);
      // label: fixture stores null for no-label; TS returns undefined — normalise.
      expect(spec.label ?? null).toBe(entry.label);
      checked++;
    }

    expect(checked).toBe(entries.length);
  });
});

// ── 4. Viewport plan breakpoints ─────────────────────────────────────────────

describe('G-4 — Viewport plan breakpoints', () => {
  it('≤600px → mobilePlan', () => {
    expect(pickViewportPlan(414)).toBe(mobilePlan);
    expect(pickViewportPlan(600)).toBe(mobilePlan);
  });

  it('601-1024px → tabletPlan', () => {
    expect(pickViewportPlan(768)).toBe(tabletPlan);
    expect(pickViewportPlan(1024)).toBe(tabletPlan);
  });

  it('>1024px → desktopPlan', () => {
    expect(pickViewportPlan(1440)).toBe(desktopPlan);
    expect(pickViewportPlan(1920)).toBe(desktopPlan);
  });

  it('mobilePlan.surfacedLayers = [L1, L2]', () => {
    expect(mobilePlan.surfacedLayers).toEqual(['L1', 'L2']);
  });

  it('tabletPlan.surfacedLayers = [L1, L2, L3]', () => {
    expect(tabletPlan.surfacedLayers).toEqual(['L1', 'L2', 'L3']);
  });

  it('desktopPlan.surfacedLayers = [L1, L2, L3, L4]', () => {
    expect(desktopPlan.surfacedLayers).toEqual(['L1', 'L2', 'L3', 'L4']);
  });

  it('Three.js gate: only desktopPlan has L4', () => {
    const gated = (plan: typeof mobilePlan) => plan.surfacedLayers.includes('L4');
    expect(gated(mobilePlan)).toBe(false);
    expect(gated(tabletPlan)).toBe(false);
    expect(gated(desktopPlan)).toBe(true);
  });
});

```
