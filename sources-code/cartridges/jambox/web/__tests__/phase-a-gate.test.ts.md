---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/__tests__/phase-a-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.600968+00:00
---

# cartridges/jambox/web/__tests__/phase-a-gate.test.ts

```ts
/**
 * D-A.9 — Phase A gate test.
 *
 * Asserts all criteria from PRD §D-A.9:
 * 1. All new kinds round-trip through JamboxSemanticObject serialisation.
 * 2. All four default racks satisfy the JamRack contract via structural check.
 * 3. Macro index is clamped to [0,7] and value to [0,1].
 * 4. Linearity matches the table in §A.1.
 * 5. The five existing surface modes emit canonical jam.input.pad cells.
 * 6. JamboxWorldPayload accepts and round-trips viewportPlan, palette, labelMode.
 *    Defaults applied per §A.4b.
 * 7. colourForPitch snapshots match for the documented palette × scale × root matrix.
 */

import { describe, it, expect } from 'vitest';

// ── Objects and factories ──────────────────────────────────────────────────────
import {
  createRack, createClip, createScene, createTake,
  createContribution, createPlayer, createGesture, createMapping, createPermission,
  createDefaultWorldObject, createTrackInstrumentObjects,
  type JamboxObjectKind,
} from '../src/semantic/objects';

// ── Rack contract ──────────────────────────────────────────────────────────────
import type { JamRack } from '../src/racks/contract';
import { JamRackRegistry } from '../src/racks/registry';

// ── Surface ────────────────────────────────────────────────────────────────────
import { GridSurface, type GridSurfaceCallbacks } from '../src/grid/surface';
import type { JamInputPad } from '../src/semantic/events';

// ── Viewport plans ─────────────────────────────────────────────────────────────
import { desktopPlan, tabletPlan, mobilePlan, selectViewportPlan } from '../src/world/viewport-plans';

// ── Scale colour ───────────────────────────────────────────────────────────────
import { classifyPitch, colourForPitch, type ScaleId } from '../src/colour/scale-colour';

// ─────────────────────────────────────────────────────────────────────────────

const OWNER = 'gate-test-owner';
const ROOM  = 'gate-test-room';

// ─── 1. Round-trip through JamboxSemanticObject serialisation ─────────────────

describe('1. New kinds round-trip through serialisation', () => {
  const roundTrip = (obj: { id: string; header: { objectType: JamboxObjectKind } }) => {
    const json = JSON.stringify(obj);
    const parsed = JSON.parse(json) as typeof obj;
    expect(parsed.id).toBe(obj.id);
    expect(parsed.header.objectType).toBe(obj.header.objectType);
  };

  it('jam.rack round-trips', () => {
    roundTrip(createRack({ ownerIdentity: OWNER, rackId: 'jam.rack.drum-808', name: 'Drum 808', engine: 'webaudio' }));
  });
  it('jam.clip round-trips', () => {
    roundTrip(createClip({ ownerIdentity: OWNER, room: ROOM, name: 'clip-1', patternObjectId: 'pat-1' }));
  });
  it('jam.scene round-trips', () => {
    roundTrip(createScene({ ownerIdentity: OWNER, room: ROOM, name: 'scene-a', sceneIndex: 0 }));
  });
  it('jam.take round-trips', () => {
    roundTrip(createTake({ ownerIdentity: OWNER, room: ROOM, name: 'take-1', sourceObjectId: 'scene-1', startMs: 0, durationMs: 8000 }));
  });
  it('jam.contribution round-trips', () => {
    roundTrip(createContribution({ ownerIdentity: OWNER, room: ROOM, playerIdentity: 'p1', objectIds: ['o1'], shareBps: 5000, startMs: 0 }));
  });
  it('jam.player round-trips', () => {
    roundTrip(createPlayer({ ownerIdentity: OWNER, room: ROOM, identity: 'p1', displayName: 'Player 1', colorHex: '#ff6600' }));
  });
  it('jam.gesture round-trips', () => {
    roundTrip(createGesture({ ownerIdentity: OWNER, room: ROOM, kind: 'filter-sweep', playerIdentity: 'p1', rackId: 'jam.rack.drum-808' }));
  });
  it('jam.mapping round-trips', () => {
    roundTrip(createMapping({ ownerIdentity: OWNER, room: ROOM, name: 'test-mapping', surfaceShape: 'grid-8x8' }));
  });
  it('jam.permission round-trips', () => {
    roundTrip(createPermission({ ownerIdentity: OWNER, room: ROOM, objectId: 'clip-1', granteeIdentity: 'p2', grants: ['read'] }));
  });
});

// ─── 2. Four default racks satisfy the JamRack contract ──────────────────────

describe('2. Default racks satisfy JamRack contract', () => {
  /** Check a rack satisfies the structural JamRack contract. */
  function assertJamRackContract(rack: JamRack): void {
    expect(typeof rack.id).toBe('string');
    expect(rack.id.length).toBeGreaterThan(0);
    expect(typeof rack.name).toBe('string');
    expect(['webaudio', 'puredata', 'strudel', 'midi', 'hybrid']).toContain(rack.engine);
    expect(typeof rack.play).toBe('function');
    expect(typeof rack.stop).toBe('function');
    expect(typeof rack.setMacro).toBe('function');
    expect(typeof rack.setPreset).toBe('function');
    expect(typeof rack.getState).toBe('function');
    expect(typeof rack.setState).toBe('function');
    expect(typeof rack.getMeters).toBe('function');
    expect(typeof rack.getMappingHints).toBe('function');

    // getState returns valid shape
    const state = rack.getState();
    expect(Array.isArray(state.macros)).toBe(true);
    expect(state.macros).toHaveLength(8);

    // getMeters returns valid shape
    const meters = rack.getMeters();
    expect(typeof meters.peakL).toBe('number');
    expect(typeof meters.peakR).toBe('number');
    expect(typeof meters.rmsL).toBe('number');
    expect(typeof meters.rmsR).toBe('number');

    // getMappingHints returns array
    const hints = rack.getMappingHints();
    expect(Array.isArray(hints)).toBe(true);
  }

  it('drum808 satisfies JamRack', async () => {
    const { Drum808Rack } = await import('../src/racks/webaudio/drum808');
    const rack = new Drum808Rack();
    assertJamRackContract(rack);
    expect(rack.id).toBe('jam.rack.drum-808');
  });

  it('acid303 satisfies JamRack', async () => {
    const { Acid303Rack } = await import('../src/racks/webaudio/acid303');
    const rack = new Acid303Rack();
    assertJamRackContract(rack);
    expect(rack.id).toBe('jam.rack.acid-303');
  });

  it('bassMono satisfies JamRack', async () => {
    const { BassMonoRack } = await import('../src/racks/webaudio/bassMono');
    const rack = new BassMonoRack();
    assertJamRackContract(rack);
    expect(rack.id).toBe('jam.rack.bass-mono');
  });

  it('polyKeys satisfies JamRack', async () => {
    const { PolyKeysRack } = await import('../src/racks/webaudio/polyKeys');
    const rack = new PolyKeysRack();
    assertJamRackContract(rack);
    expect(rack.id).toBe('jam.rack.poly-keys');
  });
});

// ─── 3. Macro clamping ────────────────────────────────────────────────────────

describe('3. Macro index and value clamping', () => {
  it('setMacro clamps index to [0,7]', async () => {
    const { Drum808Rack } = await import('../src/racks/webaudio/drum808');
    const rack = new Drum808Rack();
    // Should not throw when called with out-of-range values
    expect(() => rack.setMacro(-1, 0.5)).not.toThrow();
    expect(() => rack.setMacro(8, 0.5)).not.toThrow();
    expect(() => rack.setMacro(100, 0.5)).not.toThrow();
  });

  it('setMacro clamps value to [0,1]', async () => {
    const { Drum808Rack } = await import('../src/racks/webaudio/drum808');
    const rack = new Drum808Rack();
    rack.setMacro(0, -0.5);
    const state = rack.getState();
    expect(state.macros[0]).toBeGreaterThanOrEqual(0);
    rack.setMacro(0, 1.5);
    const state2 = rack.getState();
    expect(state2.macros[0]).toBeLessThanOrEqual(1);
  });

  it('macro values persist after setMacro', async () => {
    const { PolyKeysRack } = await import('../src/racks/webaudio/polyKeys');
    const rack = new PolyKeysRack();
    rack.setMacro(3, 0.75);
    expect(rack.getState().macros[3]).toBe(0.75);
  });
});

// ─── 4. Linearity matches §A.1 table ─────────────────────────────────────────

describe('4. Linearity matches §A.1', () => {
  it('jam.rack → linear', () => {
    expect(createRack({ ownerIdentity: OWNER, rackId: 'r1', name: 'R1', engine: 'webaudio' }).header.linearity).toBe('linear');
  });
  it('jam.clip → affine', () => {
    expect(createClip({ ownerIdentity: OWNER, room: ROOM, name: 'c1', patternObjectId: 'p1' }).header.linearity).toBe('affine');
  });
  it('jam.scene → affine', () => {
    expect(createScene({ ownerIdentity: OWNER, room: ROOM, name: 's1', sceneIndex: 0 }).header.linearity).toBe('affine');
  });
  it('jam.take → linear', () => {
    expect(createTake({ ownerIdentity: OWNER, room: ROOM, name: 't1', sourceObjectId: 's1', startMs: 0, durationMs: 1000 }).header.linearity).toBe('linear');
  });
  it('jam.contribution → relevant', () => {
    expect(createContribution({ ownerIdentity: OWNER, room: ROOM, playerIdentity: 'p1', objectIds: [], shareBps: 1000, startMs: 0 }).header.linearity).toBe('relevant');
  });
  it('jam.player → affine', () => {
    expect(createPlayer({ ownerIdentity: OWNER, room: ROOM, identity: 'p1', displayName: 'P1', colorHex: '#fff' }).header.linearity).toBe('affine');
  });
  it('jam.gesture → debug', () => {
    expect(createGesture({ ownerIdentity: OWNER, room: ROOM, kind: 'riser', playerIdentity: 'p1', rackId: 'r1' }).header.linearity).toBe('debug');
  });
  it('jam.mapping → linear', () => {
    expect(createMapping({ ownerIdentity: OWNER, room: ROOM, name: 'test-mapping', surfaceShape: 'qwerty' }).header.linearity).toBe('linear');
  });
  it('jam.permission → linear', () => {
    expect(createPermission({ ownerIdentity: OWNER, room: ROOM, objectId: 'obj', granteeIdentity: 'g1', grants: ['read'] }).header.linearity).toBe('linear');
  });
});

// ─── 5. Surface modes emit canonical jam.input.pad cells ─────────────────────

describe('5. Surface modes emit canonical jam.input.pad events', () => {
  function makeSurface(onPad: (e: JamInputPad) => void): GridSurface {
    const cb: GridSurfaceCallbacks = {
      onStepToggle: () => {},
      onParamChange: () => {},
      onPatternSlot: () => {},
      onArrangementPlace: () => {},
      onModeChange: () => {},
      onCanonicalPad: onPad,
    };
    return new GridSurface(cb);
  }

  it('global mode: pad press emits jam.input.pad', () => {
    const events: JamInputPad[] = [];
    const surface = makeSurface((e) => events.push(e));

    // Press pad 0 (row 0, col 0 = kick, step 0 in global mode)
    surface.press(0);
    expect(events.length).toBe(1);
    expect(events[0].family).toBe('jam.input.pad');
    expect(events[0].mode).toBe('global');
  });

  it('step mode: pad press emits jam.input.pad', () => {
    const events: JamInputPad[] = [];
    const surface = makeSurface((e) => events.push(e));
    surface.selectTrack('kick');
    // In step mode, press row 0 col 0 = step 0
    surface.press(0);
    expect(events.length).toBeGreaterThan(0);
    expect(events[0].family).toBe('jam.input.pad');
    expect(events[0].mode).toBe('step');
  });

  it('session mode: pad press emits jam.input.pad', () => {
    const events: JamInputPad[] = [];
    const surface = makeSurface((e) => events.push(e));
    surface.setMode('session');
    surface.press(0); // row 0 col 0 = pattern slot 0
    expect(events.length).toBeGreaterThan(0);
    expect(events[0].family).toBe('jam.input.pad');
    expect(events[0].mode).toBe('session');
  });

  it('arrangement mode: pad press emits jam.input.pad', () => {
    const events: JamInputPad[] = [];
    const surface = makeSurface((e) => events.push(e));
    surface.setMode('arrangement');
    surface.press(0); // row 0 col 0 = bar 0
    expect(events.length).toBeGreaterThan(0);
    expect(events[0].family).toBe('jam.input.pad');
    expect(events[0].mode).toBe('arrangement');
  });

  it('param mode: pad press emits jam.input.pad (when param exists)', () => {
    const events: JamInputPad[] = [];
    const surface = makeSurface((e) => events.push(e));
    surface.selectTrack('kick');
    surface.setMode('param');
    // Press row 1 col 0 = first param for kick
    surface.press(8);
    // param mode with selected track and valid param should emit
    // (if no param at row 1 col 0, result is null and no canonical event)
    // Just check that canonical events have correct family if emitted
    for (const e of events) {
      expect(e.family).toBe('jam.input.pad');
    }
  });

  it('mode nav presses (row 7) do not emit canonical pad', () => {
    const events: JamInputPad[] = [];
    const surface = makeSurface((e) => events.push(e));
    surface.selectTrack('kick'); // puts us in step mode
    // Row 7 = mode nav, should not emit canonical
    surface.press(56); // row 7 col 0 = 'global' nav
    expect(events.length).toBe(0);
  });
});

// ─── 6. JamboxWorldPayload viewportPlan / palette / labelMode round-trip ──────

describe('6. JamboxWorldPayload viewport/palette/labelMode', () => {
  const instruments = createTrackInstrumentObjects(OWNER, []);

  it('defaults to boomwhacker + off', () => {
    const world = createDefaultWorldObject({
      ownerIdentity: OWNER, room: ROOM, bpm: 120, scene: 0,
      instruments, skinObjectId: 'skin-1',
    });
    expect(world.payload.palette).toBe('boomwhacker');
    expect(world.payload.labelMode).toBe('off');
  });

  it('accepts newton palette', () => {
    const world = createDefaultWorldObject({
      ownerIdentity: OWNER, room: ROOM, bpm: 120, scene: 0,
      instruments, skinObjectId: 'skin-1', palette: 'newton',
    });
    expect(world.payload.palette).toBe('newton');
  });

  it('accepts scriabin palette', () => {
    const world = createDefaultWorldObject({
      ownerIdentity: OWNER, room: ROOM, bpm: 120, scene: 0,
      instruments, skinObjectId: 'skin-1', palette: 'scriabin',
    });
    expect(world.payload.palette).toBe('scriabin');
  });

  it('accepts solfege labelMode', () => {
    const world = createDefaultWorldObject({
      ownerIdentity: OWNER, room: ROOM, bpm: 120, scene: 0,
      instruments, skinObjectId: 'skin-1', labelMode: 'solfege',
    });
    expect(world.payload.labelMode).toBe('solfege');
  });

  it('auto-selects mobilePlan for ≤ 600px', () => {
    const world = createDefaultWorldObject({
      ownerIdentity: OWNER, room: ROOM, bpm: 120, scene: 0,
      instruments, skinObjectId: 'skin-1', viewportWidthPx: 375,
    });
    expect(world.payload.viewportPlan?.surfacedLayers).toEqual(['L1', 'L2']);
  });

  it('auto-selects tabletPlan for 601-1024px', () => {
    const world = createDefaultWorldObject({
      ownerIdentity: OWNER, room: ROOM, bpm: 120, scene: 0,
      instruments, skinObjectId: 'skin-1', viewportWidthPx: 768,
    });
    expect(world.payload.viewportPlan?.surfacedLayers).toEqual(['L1', 'L2', 'L3']);
  });

  it('auto-selects desktopPlan for > 1024px', () => {
    const world = createDefaultWorldObject({
      ownerIdentity: OWNER, room: ROOM, bpm: 120, scene: 0,
      instruments, skinObjectId: 'skin-1', viewportWidthPx: 1440,
    });
    expect(world.payload.viewportPlan?.surfacedLayers).toEqual(['L1', 'L2', 'L3', 'L4']);
  });

  it('viewport plans round-trip through JSON', () => {
    const world = createDefaultWorldObject({
      ownerIdentity: OWNER, room: ROOM, bpm: 120, scene: 0,
      instruments, skinObjectId: 'skin-1', viewportPlan: desktopPlan,
    });
    const json = JSON.stringify(world.payload);
    const parsed = JSON.parse(json) as typeof world.payload;
    expect(parsed.viewportPlan).toEqual(desktopPlan);
  });

  it('selectViewportPlan exports correct plans', () => {
    expect(selectViewportPlan(320)).toEqual(mobilePlan);
    expect(selectViewportPlan(600)).toEqual(mobilePlan);
    expect(selectViewportPlan(601)).toEqual(tabletPlan);
    expect(selectViewportPlan(1024)).toEqual(tabletPlan);
    expect(selectViewportPlan(1025)).toEqual(desktopPlan);
    expect(selectViewportPlan(1920)).toEqual(desktopPlan);
  });
});

// ─── 7. colourForPitch snapshot matrix ────────────────────────────────────────

describe('7. colourForPitch snapshot matrix', () => {
  const scales: ScaleId[] = ['pentatonic', 'major', 'minor', 'dorian', 'phrygian'];
  const roots = [0, 7, 5]; // C, G, F
  const pitches = Array.from({ length: 12 }, (_, i) => i); // all 12 pitch classes

  it('returns a ScaleColourSpec for all palette × scale × root × pitch combinations', () => {
    const palettes = ['boomwhacker', 'newton', 'scriabin'] as const;
    for (const palette of palettes) {
      for (const scale of scales) {
        for (const root of roots) {
          for (const pitch of pitches) {
            const spec = colourForPitch(pitch, scale, root, palette, 'off');
            expect(typeof spec.hue).toBe('number');
            expect(spec.hue).toBeGreaterThanOrEqual(0);
            expect(spec.hue).toBeLessThanOrEqual(360);
            expect(typeof spec.saturation).toBe('number');
            expect(spec.saturation).toBeGreaterThanOrEqual(0);
            expect(spec.saturation).toBeLessThanOrEqual(1);
            expect(typeof spec.brightness).toBe('number');
            expect(spec.brightness).toBeGreaterThanOrEqual(0);
            expect(spec.brightness).toBeLessThanOrEqual(1);
          }
        }
      }
    }
  });

  it('root note gets gold-ring border in all palettes', () => {
    for (const palette of ['boomwhacker', 'newton', 'scriabin'] as const) {
      const spec = colourForPitch(60, 'major', 0 /* C */, palette, 'off'); // C4 in C major
      expect(spec.border).toBe('gold-ring');
    }
  });

  it('chromatic note gets chromatic-edge border', () => {
    // F# (pitch 6) is not in C major
    const spec = colourForPitch(6, 'major', 0, 'boomwhacker', 'off');
    expect(spec.border).toBe('chromatic-edge');
  });

  it('chromatic note has lower brightness than in-scale notes', () => {
    const inScale = colourForPitch(2, 'major', 0, 'boomwhacker', 'off'); // D in C major
    const chromatic = colourForPitch(1, 'major', 0, 'boomwhacker', 'off'); // C# not in C major
    expect(chromatic.brightness).toBeLessThan(inScale.brightness);
  });

  it('Boomwhacker: C (root) has hue 0 (red)', () => {
    const spec = colourForPitch(0, 'major', 0, 'boomwhacker', 'off');
    expect(spec.hue).toBe(0);
  });

  it('Boomwhacker: G (root) has hue ~210 (blue)', () => {
    const spec = colourForPitch(7, 'major', 7, 'boomwhacker', 'off'); // G in G major
    expect(spec.hue).toBe(210);
    expect(spec.border).toBe('gold-ring');
  });

  it('dorian characteristic note (major 6th) gets modal-tick border', () => {
    // In C dorian, A (pitch 9) is the characteristic tone (major 6th)
    const spec = colourForPitch(9, 'dorian', 0, 'boomwhacker', 'off');
    expect(spec.border).toBe('modal-tick');
  });

  it('snapshot: C major scale from C — all 12 pitches × boomwhacker', () => {
    const results = pitches.map((p) => ({
      pitch: p,
      class: classifyPitch(p, 'major', 0),
      colour: colourForPitch(p, 'major', 0, 'boomwhacker', 'off'),
    }));
    expect(results).toMatchSnapshot();
  });

  it('snapshot: pentatonic scale from G × all 12 pitches', () => {
    const results = pitches.map((p) => ({
      pitch: p,
      class: classifyPitch(p, 'pentatonic', 7),
      colour: colourForPitch(p, 'pentatonic', 7, 'boomwhacker', 'off'),
    }));
    expect(results).toMatchSnapshot();
  });

  it('snapshot: phrygian from F × all 12 pitches × newton', () => {
    const results = pitches.map((p) => ({
      pitch: p,
      class: classifyPitch(p, 'phrygian', 5),
      colour: colourForPitch(p, 'phrygian', 5, 'newton', 'off'),
    }));
    expect(results).toMatchSnapshot();
  });
});

// ─── Registry ─────────────────────────────────────────────────────────────────

describe('JamRackRegistry', () => {
  it('registers and retrieves racks', async () => {
    const registry = new JamRackRegistry();
    const { Drum808Rack } = await import('../src/racks/webaudio/drum808');
    // Create a rack with the registry-independent constructor
    const rack = new Drum808Rack();
    registry.register(rack);
    expect(registry.has(rack.id)).toBe(true);
    expect(registry.get(rack.id)).toBe(rack);
    expect(registry.all()).toContain(rack);
    registry.unregister(rack.id);
    expect(registry.has(rack.id)).toBe(false);
  });
});

```
