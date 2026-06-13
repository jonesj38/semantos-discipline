---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/__tests__/phase-c-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.602479+00:00
---

# cartridges/jambox/web/__tests__/phase-c-gate.test.ts

```ts
/**
 * D-C.8 — Phase C gate test.
 *
 * Covers all criteria from PRD §D-C.8:
 *
 * 1. JamboxSemanticObject<JamboxMappingPayload> round-trips through JSON.
 * 2. Installing a QWERTY profile produces the expected pads-by-key behaviour.
 * 3. Simulated MIDI note-on through the router emits the correct semantic event.
 * 4. Forking a mapping: new id, parents[0] = original id.
 * 5. Phase A and Phase B gates re-run and pass (imports).
 * 6. MappingRegistry install / uninstall / list work correctly.
 * 7. Router: chromatic quantise in Note mode emits onChromaticQuantised.
 * 8. Router: Custom mode bypasses chromatic guardrail.
 * 9. Device adapters compile (structural).
 * 10. Built-in profiles are complete and well-formed.
 */

import { describe, it, expect, vi } from 'vitest';

// ── Phase A + B re-run (gate cumulation) ─────────────────────────────────────
import { createRack, createMapping } from '../src/semantic/objects';
import { colourForPitch } from '../src/colour/scale-colour';
import { SUPPORT_ENTRIES } from '../src/ui/support-sheet';
import { L2_CONFIGS } from '../src/ui/mode-row';

// ── Phase C: types + registry + router ───────────────────────────────────────
import type {
  JamboxMappingPayload,
} from '../src/semantic/objects';
import { MappingRegistry } from '../src/mappings/registry';
import { MappingRouter } from '../src/mappings/router';
import type { DeviceEvent, SemanticEvent } from '../src/mappings/router';

// ── Profiles ──────────────────────────────────────────────────────────────────
import { QWERTY_PROFILE } from '../src/mappings/profiles/qwerty';
import { TOUCH_PROFILE } from '../src/mappings/profiles/touch';
import { LAUNCHPAD_PROFILE } from '../src/mappings/profiles/launchpad';
import { LAUNCHPAD_PRO_PROFILE } from '../src/mappings/profiles/launchpad-pro';
import { PUSH3_PROFILE } from '../src/mappings/profiles/push3';
import { CIRCUIT_PROFILE } from '../src/mappings/profiles/circuit';
import { MPK49_PROFILE } from '../src/mappings/profiles/mpk49';
import { RX2_PROFILE } from '../src/mappings/profiles/rx2';
import { GAMEPAD_PROFILE } from '../src/mappings/profiles/gamepad';
import { PHONE_PROFILE } from '../src/mappings/profiles/phone';
import { profileForDevice } from '../src/mappings/profiles/index';

// ── Surface ───────────────────────────────────────────────────────────────────
import { GridSurface, type GridSurfaceCallbacks } from '../src/grid/surface';

const OWNER = 'gate-c-owner';
const ROOM  = 'gate-c-room';

// ─────────────────────────────────────────────────────────────────────────────

// ─── 1. JamboxSemanticObject<JamboxMappingPayload> round-trip ─────────────────

describe('1. JamboxMappingPayload round-trip', () => {
  it('createMapping produces a valid object that round-trips through JSON', () => {
    const obj = createMapping({
      ownerIdentity: OWNER,
      room: ROOM,
      name: 'Test Mapping',
      surfaceShape: 'qwerty',
      inputs: [
        {
          type: 'key',
          selector: 'z',
          target: { kind: 'rack.note', rackId: 'jam.rack.poly-keys' },
        },
      ],
      outputs: [
        {
          type: 'led',
          selector: 0,
          source: 'scale.degree',
          projection: 'colour',
        },
      ],
      version: '1.0.0',
      license: 'remixable',
    });

    expect(obj.id).toBeTruthy();
    expect(obj.header.objectType).toBe('jam.mapping');
    expect(obj.header.linearity).toBe('linear');
    expect(obj.payload.name).toBe('Test Mapping');
    expect(obj.payload.surfaceShape).toBe('qwerty');
    expect(obj.payload.inputs).toHaveLength(1);
    expect(obj.payload.outputs).toHaveLength(1);

    // Round-trip
    const json = JSON.stringify(obj);
    const parsed = JSON.parse(json) as typeof obj;
    expect(parsed.id).toBe(obj.id);
    expect(parsed.header.objectType).toBe('jam.mapping');
    expect(parsed.payload.inputs[0]?.selector).toBe('z');
    expect(parsed.payload.outputs[0]?.source).toBe('scale.degree');
  });

  it('payload author and license fields survive round-trip', () => {
    const obj = createMapping({
      ownerIdentity: OWNER,
      room: ROOM,
      name: 'Commercial Mapping',
      surfaceShape: 'push',
      license: 'commercial',
    });
    const rt = JSON.parse(JSON.stringify(obj)) as typeof obj;
    expect(rt.payload.license).toBe('commercial');
    expect(rt.payload.author).toBe(OWNER);
  });
});

// ─── 2. QWERTY profile pads-by-key behaviour ─────────────────────────────────

describe('2. QWERTY profile: pads-by-key behaviour', () => {
  it('QWERTY profile has inputs for bottom row (z-m)', () => {
    const bottomKeys = ['z','s','x','d','c','v','g','b','h','n','j','m'];
    for (const key of bottomKeys) {
      const found = QWERTY_PROFILE.inputs.some(
        (i) => i.type === 'key' && i.selector === key,
      );
      expect(found, `QWERTY missing binding for key "${key}"`).toBe(true);
    }
  });

  it('QWERTY key z targets rack.note on jam.rack.poly-keys', () => {
    const binding = QWERTY_PROFILE.inputs.find(
      (i) => i.type === 'key' && i.selector === 'z',
    );
    expect(binding).toBeDefined();
    expect(binding!.target.kind).toBe('rack.note');
    expect((binding!.target as { rackId: string }).rackId).toBe('jam.rack.poly-keys');
  });

  it('QWERTY profile has mode shortcut keys 1-5', () => {
    const modeKeys = ['1', '2', '3', '4', '5'];
    for (const key of modeKeys) {
      const found = QWERTY_PROFILE.inputs.some(
        (i) => i.type === 'key' && i.selector === key && i.target.kind === 'mode',
      );
      expect(found, `QWERTY missing mode shortcut for "${key}"`).toBe(true);
    }
  });

  it('Installing QWERTY profile registers it in the registry', () => {
    const registry = new MappingRegistry();
    const obj = createMapping({
      ownerIdentity: OWNER,
      room: ROOM,
      name: QWERTY_PROFILE.name,
      surfaceShape: QWERTY_PROFILE.surfaceShape,
      inputs: QWERTY_PROFILE.inputs,
      outputs: QWERTY_PROFILE.outputs,
    });
    registry.install(obj, 'qwerty');
    const active = registry.active('qwerty');
    expect(active).not.toBeNull();
    expect(active!.name).toBe(QWERTY_PROFILE.name);
  });
});

// ─── 3. Simulated MIDI note-on through router ─────────────────────────────────

describe('3. Router: MIDI note-on emits correct semantic event', () => {
  it('MIDI pad.on selector=60 with rack.note target emits jam.note.on', () => {
    const emitted: SemanticEvent[] = [];
    const router = new MappingRouter({
      onSemanticEvent: (ev) => emitted.push(ev),
      onFeedback: () => {},
    });
    router.setMode('midi-surface', 'note');
    // Scale: C major — includes MIDI note 60 (C4, pitch class 0)
    router.setScale(0, [0, 2, 4, 5, 7, 9, 11]);

    const mapping: JamboxMappingPayload = {
      name: 'MIDI Test',
      author: OWNER,
      surfaceShape: 'grid-8x8',
      inputs: [
        {
          type: 'pad',
          selector: 60,
          target: { kind: 'rack.note', rackId: 'jam.rack.poly-keys' },
        },
      ],
      outputs: [],
      version: '1.0.0',
      license: 'personal',
    };

    const noteOnEvent: DeviceEvent = {
      kind: 'pad.on',
      selector: 60,
      value: 0.8,
      channel: 1,
      deviceName: 'Test MIDI Device',
      ts: Date.now(),
    };

    router.route(noteOnEvent, 'midi-surface', mapping);

    expect(emitted).toHaveLength(1);
    expect(emitted[0]!.family).toBe('jam.note.on');
    expect(emitted[0]!.target.kind).toBe('rack.note');
    expect((emitted[0]!.target as { rackId: string }).rackId).toBe('jam.rack.poly-keys');
  });

  it('MIDI CC knob emits jam.rack.macro.set', () => {
    const emitted: SemanticEvent[] = [];
    const router = new MappingRouter({
      onSemanticEvent: (ev) => emitted.push(ev),
      onFeedback: () => {},
    });
    router.setMode('midi-surface', 'mix');

    const mapping: JamboxMappingPayload = {
      name: 'MIDI CC Test',
      author: OWNER,
      surfaceShape: 'mpk49',
      inputs: [
        {
          type: 'knob',
          selector: 'cc71',
          target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 0 },
          transform: { kind: 'linear', min: 0, max: 1 },
        },
      ],
      outputs: [],
      version: '1.0.0',
      license: 'personal',
    };

    const ccEvent: DeviceEvent = {
      kind: 'knob',
      selector: 'cc71',
      value: 0.75,
      channel: 1,
      deviceName: 'MPK49',
      ts: Date.now(),
    };

    router.route(ccEvent, 'midi-surface', mapping);

    expect(emitted).toHaveLength(1);
    expect(emitted[0]!.family).toBe('jam.rack.macro.set');
    expect(emitted[0]!.target.kind).toBe('rack.macro');
  });
});

// ─── 4. Fork a mapping: new id, parents[0] = original id ─────────────────────

describe('4. Fork: new id, parents[0] = original id', () => {
  it('fork produces a distinct id with correct lineage', () => {
    const registry = new MappingRegistry();
    const original = createMapping({
      ownerIdentity: OWNER,
      room: ROOM,
      name: 'Original',
      surfaceShape: 'qwerty',
      inputs: [],
      outputs: [],
    });
    registry.install(original, 'qwerty');

    const forked = registry.fork(original.id, 'forker-identity');

    expect(forked.id).not.toBe(original.id);
    expect(forked.header.parents[0]).toBe(original.id);
    expect(forked.payload.name).toContain('fork');
    expect(forked.payload.author).toBe(OWNER); // original author preserved
  });

  it('fork emits jam.mapping.fork event', () => {
    const registry = new MappingRegistry();
    const forkEvents: string[] = [];
    registry.onEvent((ev) => { if (ev.family === 'jam.mapping.fork') forkEvents.push(ev.newMappingId); });

    const original = createMapping({
      ownerIdentity: OWNER,
      room: ROOM,
      name: 'Source',
      surfaceShape: 'launchpad',
    });
    registry.install(original, 'launchpad');
    const forked = registry.fork(original.id, 'other-user');

    expect(forkEvents).toContain(forked.id);
  });

  it('fork from nonexistent id throws', () => {
    const registry = new MappingRegistry();
    expect(() => registry.fork('nonexistent-id', OWNER)).toThrow();
  });
});

// ─── 5. Phase A / B gate re-run ──────────────────────────────────────────────

describe('5. Phase A + B re-run: key assertions', () => {
  it('Phase A: createRack produces valid jam.rack object', () => {
    const rack = createRack({ ownerIdentity: OWNER, rackId: 'jam.rack.drum-808', name: 'Drum', engine: 'webaudio' });
    expect(rack.header.objectType).toBe('jam.rack');
    expect(rack.header.linearity).toBe('linear');
  });

  it('Phase A: colourForPitch returns a colour for root note', () => {
    const c = colourForPitch(60, 'major', 0, 'boomwhacker', 'off');
    expect(c.hue).toBeGreaterThanOrEqual(0);
    expect(c.saturation).toBeGreaterThanOrEqual(0);
  });

  it('Phase B: L2_CONFIGS has exactly 3 entries', () => {
    expect(L2_CONFIGS).toHaveLength(3);
  });

  it('Phase B: SUPPORT_ENTRIES has 5 entries', () => {
    expect(SUPPORT_ENTRIES).toHaveLength(5);
  });

  it('Phase C: SUPPORT_ENTRIES custom is now enabled', () => {
    const custom = SUPPORT_ENTRIES.find((e) => e.id === 'custom');
    expect(custom).toBeDefined();
    expect(custom!.disabled).toBe(false);
    expect(custom!.mode).toBe('custom');
  });
});

// ─── 6. MappingRegistry: install / uninstall / list ──────────────────────────

describe('6. MappingRegistry install / uninstall / list', () => {
  it('install makes mapping active for surface', () => {
    const registry = new MappingRegistry();
    const obj = createMapping({ ownerIdentity: OWNER, room: ROOM, name: 'M1', surfaceShape: 'touch' });
    registry.install(obj, 'touch');
    expect(registry.active('touch')).not.toBeNull();
    expect(registry.list()).toHaveLength(1);
  });

  it('install emits jam.mapping.install event', () => {
    const registry = new MappingRegistry();
    const events: string[] = [];
    registry.onEvent((ev) => events.push(ev.family));
    const obj = createMapping({ ownerIdentity: OWNER, room: ROOM, name: 'M2', surfaceShape: 'push' });
    registry.install(obj, 'push');
    expect(events).toContain('jam.mapping.install');
  });

  it('uninstall removes mapping and emits jam.mapping.uninstall', () => {
    const registry = new MappingRegistry();
    const events: string[] = [];
    registry.onEvent((ev) => events.push(ev.family));
    const obj = createMapping({ ownerIdentity: OWNER, room: ROOM, name: 'M3', surfaceShape: 'gamepad' });
    registry.install(obj, 'gamepad');
    registry.uninstall(obj.id);
    expect(registry.active('gamepad')).toBeNull();
    expect(events).toContain('jam.mapping.uninstall');
  });

  it('list returns all installed mappings', () => {
    const registry = new MappingRegistry();
    const a = createMapping({ ownerIdentity: OWNER, room: ROOM, name: 'A', surfaceShape: 'qwerty' });
    const b = createMapping({ ownerIdentity: OWNER, room: ROOM, name: 'B', surfaceShape: 'touch' });
    registry.install(a, 'qwerty');
    registry.install(b, 'touch');
    expect(registry.list()).toHaveLength(2);
  });
});

// ─── 7. Router: chromatic quantise in Note mode ───────────────────────────────

describe('7. Router: chromatic quantise in Note mode', () => {
  it('chromatic note in Note mode triggers onChromaticQuantised', () => {
    const quantised: Array<string | number> = [];
    const emitted: SemanticEvent[] = [];
    const router = new MappingRouter({
      onSemanticEvent: (ev) => emitted.push(ev),
      onFeedback: () => {},
      onChromaticQuantised: (sel) => quantised.push(sel),
    });

    // C major scale (no C# = pitch class 1)
    router.setScale(0, [0, 2, 4, 5, 7, 9, 11]);
    router.setMode('surface', 'note');

    const mapping: JamboxMappingPayload = {
      name: 'Chromatic Test',
      author: OWNER,
      surfaceShape: 'grid-8x8',
      inputs: [
        {
          type: 'pad',
          selector: 61, // MIDI 61 = C# which is pitch class 1 — not in C major
          target: { kind: 'rack.note', rackId: 'jam.rack.poly-keys' },
        },
      ],
      outputs: [],
      version: '1.0.0',
      license: 'personal',
    };

    const ev: DeviceEvent = {
      kind: 'pad.on',
      selector: 61,
      value: 0.8,
      deviceName: 'Test',
      ts: Date.now(),
    };

    router.route(ev, 'surface', mapping);

    // Chromatic note should have been quantised
    expect(quantised).toHaveLength(1);
    expect(quantised[0]).toBe(61); // original selector reported
    // Event still emitted (quantised to nearest in-scale pitch)
    expect(emitted).toHaveLength(1);
    expect(emitted[0]!.family).toBe('jam.note.on');
  });

  it('chromatic permission bypass: mapping with requires-permission:chromatic emits without quantise', () => {
    const quantised: Array<string | number> = [];
    const emitted: SemanticEvent[] = [];
    const router = new MappingRouter({
      onSemanticEvent: (ev) => emitted.push(ev),
      onFeedback: () => {},
      onChromaticQuantised: (sel) => quantised.push(sel),
    });

    router.setScale(0, [0, 2, 4, 5, 7, 9, 11]); // C major
    router.setMode('surface', 'note');

    const mapping: JamboxMappingPayload = {
      name: 'Chromatic Permitted',
      author: OWNER,
      surfaceShape: 'launchpad',
      inputs: [
        {
          type: 'pad',
          selector: 61,
          target: { kind: 'rack.note', rackId: 'jam.rack.poly-keys' },
        },
      ],
      outputs: [],
      constraints: [{ kind: 'requires-permission', value: 'chromatic' }],
      version: '1.0.0',
      license: 'personal',
    };

    const ev: DeviceEvent = {
      kind: 'pad.on',
      selector: 61,
      value: 0.8,
      deviceName: 'Test',
      ts: Date.now(),
    };

    router.route(ev, 'surface', mapping);

    // No quantisation — permission granted
    expect(quantised).toHaveLength(0);
    expect(emitted).toHaveLength(1);
    expect(emitted[0]!.family).toBe('jam.note.on');
  });
});

// ─── 8. Router: Custom mode bypasses built-in rules ──────────────────────────

describe('8. Router: Custom mode bypass', () => {
  it('custom mode routes mapping-direct without chromatic guardrail', () => {
    const quantised: Array<string | number> = [];
    const emitted: SemanticEvent[] = [];
    const router = new MappingRouter({
      onSemanticEvent: (ev) => emitted.push(ev),
      onFeedback: () => {},
      onChromaticQuantised: (sel) => quantised.push(sel),
    });

    router.setScale(0, [0, 2, 4, 5, 7, 9, 11]); // C major
    router.setMode('surface', 'custom'); // ← Custom mode

    const mapping: JamboxMappingPayload = {
      name: 'Custom Mode Test',
      author: OWNER,
      surfaceShape: 'custom',
      inputs: [
        {
          type: 'pad',
          selector: 61, // chromatic
          target: { kind: 'rack.note', rackId: 'jam.rack.poly-keys' },
        },
      ],
      outputs: [],
      version: '1.0.0',
      license: 'personal',
    };

    const ev: DeviceEvent = {
      kind: 'pad.on',
      selector: 61,
      value: 0.8,
      deviceName: 'Test',
      ts: Date.now(),
    };

    router.route(ev, 'surface', mapping);

    // Custom mode: no quantisation
    expect(quantised).toHaveLength(0);
    expect(emitted).toHaveLength(1);
  });
});

// ─── 9. Surface: GridModeKind includes 'custom' ───────────────────────────────

describe('9. Surface: custom mode in GridModeKind', () => {
  it('GridSurface.setMode("custom") is accepted without throwing', () => {
    const surface = new GridSurface(makeSurface());
    // Register a rack so mix doesn't throw
    surface.registerRack('jam.rack.drum-808');
    expect(() => surface.setMode('custom')).not.toThrow();
    expect(surface.getMode()).toBe('custom');
  });

  it('GridSurface in custom mode returns 64 pads from render()', () => {
    const surface = new GridSurface(makeSurface());
    surface.setMode('custom');
    const pads = surface.render();
    expect(pads).toHaveLength(64);
  });
});

// ─── 10. Built-in profiles are well-formed ────────────────────────────────────

describe('10. Built-in profiles well-formed', () => {
  const PROFILES: Array<{ name: string; profile: JamboxMappingPayload }> = [
    { name: 'QWERTY',        profile: QWERTY_PROFILE },
    { name: 'Touch',         profile: TOUCH_PROFILE },
    { name: 'Launchpad',     profile: LAUNCHPAD_PROFILE },
    { name: 'Launchpad Pro', profile: LAUNCHPAD_PRO_PROFILE },
    { name: 'Push 3',        profile: PUSH3_PROFILE },
    { name: 'Circuit',       profile: CIRCUIT_PROFILE },
    { name: 'MPK49',         profile: MPK49_PROFILE },
    { name: 'RX2',           profile: RX2_PROFILE },
    { name: 'Gamepad',       profile: GAMEPAD_PROFILE },
    { name: 'Phone',         profile: PHONE_PROFILE },
  ];

  for (const { name, profile } of PROFILES) {
    it(`${name} profile has required fields`, () => {
      expect(profile.name).toBeTruthy();
      expect(profile.author).toBe('semantos-built-in');
      expect(typeof profile.surfaceShape).toBe('string');
      expect(Array.isArray(profile.inputs)).toBe(true);
      expect(Array.isArray(profile.outputs)).toBe(true);
      expect(profile.version).toMatch(/^\d+\.\d+\.\d+$/);
      expect(['personal', 'remixable', 'commercial']).toContain(profile.license);
    });

    it(`${name} profile has at least one input`, () => {
      expect(profile.inputs.length).toBeGreaterThan(0);
    });

    it(`${name} profile inputs have valid target kinds`, () => {
      const validKinds = [
        'mode', 'rack.macro', 'rack.note', 'rack.trigger',
        'pattern.step', 'clip.launch', 'scene.launch', 'transport',
        'gesture', // D-G.7: gesture target kind for phone three-finger-tap
      ];
      for (const input of profile.inputs) {
        expect(validKinds).toContain(input.target.kind);
      }
    });
  }

  it('profileForDevice("Launchpad Pro") returns LAUNCHPAD_PRO_PROFILE', () => {
    const result = profileForDevice('Launchpad Pro MK3');
    expect(result).not.toBeNull();
    expect(result!.name).toBe(LAUNCHPAD_PRO_PROFILE.name);
  });

  it('profileForDevice("Launchpad X") returns LAUNCHPAD_PROFILE (not Pro)', () => {
    const result = profileForDevice('Launchpad X');
    expect(result).not.toBeNull();
    // Should match generic Launchpad, not Pro
    expect(result!.name).not.toBe(LAUNCHPAD_PRO_PROFILE.name);
  });

  it('profileForDevice("Unknown Device XYZ") returns null', () => {
    expect(profileForDevice('Unknown Device XYZ')).toBeNull();
  });
});

// ─── 11. Conflict resolution (D-C.7) ─────────────────────────────────────────

describe('11. Conflict resolution: last-touched wins feedback', () => {
  it('two devices on same target: last-touched recorded', () => {
    const feedbackDevices: string[] = [];
    const emitted: SemanticEvent[] = [];
    const router = new MappingRouter({
      onSemanticEvent: (ev) => emitted.push(ev),
      onFeedback: (fb) => feedbackDevices.push(fb.deviceName),
    });
    router.setMode('surface', 'mix');

    const mapping: JamboxMappingPayload = {
      name: 'Conflict Test',
      author: OWNER,
      surfaceShape: 'grid-8x8',
      inputs: [
        {
          type: 'pad',
          selector: 0,
          target: { kind: 'rack.macro', rackId: 'jam.rack.poly-keys', macro: 0 },
        },
      ],
      outputs: [
        { type: 'led', selector: 0, source: 'rack.macro', projection: 'colour' },
      ],
      version: '1.0.0',
      license: 'personal',
    };

    const ev1: DeviceEvent = { kind: 'pad.on', selector: 0, value: 0.5, deviceName: 'Device-A', ts: 1 };
    const ev2: DeviceEvent = { kind: 'pad.on', selector: 0, value: 0.7, deviceName: 'Device-B', ts: 2 };

    router.route(ev1, 'surface', mapping);
    router.route(ev2, 'surface', mapping);

    // Both produce semantic events
    expect(emitted).toHaveLength(2);

    // Device-B was last-touched; Device-A's feedback was suppressed on second call
    const lastTouchedKey = 'macro:jam.rack.poly-keys:0';
    expect(router.getLastTouched(lastTouchedKey)).toBe('Device-B');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function makeSurface(): GridSurfaceCallbacks {
  return {
    onStepToggle: vi.fn(),
    onParamChange: vi.fn(),
    onPatternSlot: vi.fn(),
    onArrangementPlace: vi.fn(),
    onModeChange: vi.fn(),
  };
}

```
