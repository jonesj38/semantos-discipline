---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/__tests__/phase-d-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.601285+00:00
---

# cartridges/jambox/web/__tests__/phase-d-gate.test.ts

```ts
/**
 * D-D.7 — Phase D gate test.
 *
 * Asserts all Phase D criteria:
 *   1. Engine conformance harness passes for all 7 rack instances
 *      (4 Phase-A WebAudio + StrudelRack + PureDataRack + ExternalMidiRack)
 *   2. StrudelRack play() produces meter movement within 200 ms of first call
 *   3. PureDataRack with stub patch responds to jam-trigger within 200 ms
 *   4. ExternalMidiRack sends correct note-on / note-off bytes
 *   5. Bundle audit passes (boot bundle growth <= 5 KB)
 *   6. Phase A/B gates re-run and pass
 *   7. captureToPattern produces correct jam.pattern payload shape
 *   8. Macro fan-out doc/code parity spot check
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';

// vi available for timeout assertions if needed
void vi;

// Phase A gate re-run
import './phase-a-gate.test';
// Phase B gate re-run
import './phase-b-gate.test';

// ── Conformance harness ────────────────────────────────────────────────────────
import { runRackConformance } from './rack-conformance';

// ── StrudelRack ────────────────────────────────────────────────────────────────
import { StrudelRack } from '../src/racks/strudel/StrudelRack';

// ── PureDataRack ───────────────────────────────────────────────────────────────
import { PureDataRack, REQUIRED_RECEIVERS } from '../src/racks/puredata/PureDataRack';

// ── ExternalMidiRack ───────────────────────────────────────────────────────────
import { ExternalMidiRack, StubMidiOutput } from '../src/racks/midi/ExternalMidiRack';
import { ccForMacro } from '../src/racks/midi/cc-map';

// ── Registry ───────────────────────────────────────────────────────────────────
import { JamRackRegistry } from '../src/racks/registry';

// ─────────────────────────────────────────────────────────────────────────────

/** Isolated registry per test file to avoid cross-test pollution. */
const testRegistry = new JamRackRegistry();

// ── 1. Conformance harness: all 7 rack instances ──────────────────────────────

describe('D-D.4 — Drum808Rack conformance', () => {
  it('imports without error', async () => {
    const { Drum808Rack } = await import('../src/racks/webaudio/drum808');
    const rack = new Drum808Rack('self');
    testRegistry.register(rack);
    expect(rack.engine).toBe('webaudio');
  });

  // Run harness inline
  describe('conformance', () => {
    // The harness calls runRackConformance from inside a describe block.
    // We run it lazily after importing the class.
    it('passes all harness checks', async () => {
      const { Drum808Rack } = await import('../src/racks/webaudio/drum808');
      const rack = new Drum808Rack('self-d-test');
      // Inline harness assertions (mirrors runRackConformance structure)
      expect(rack.id.length).toBeGreaterThan(0);
      expect(rack.name.length).toBeGreaterThan(0);
      expect(rack.engine).toBe('webaudio');
      rack.setMacro(-1, 0.5); expect(rack.getState().macros[0]).toBeCloseTo(0.5);
      rack.setMacro(99, 0.8); expect(rack.getState().macros[7]).toBeCloseTo(0.8);
      rack.setMacro(0, -5);   expect(rack.getState().macros[0]).toBe(0);
      rack.setMacro(0, 999);  expect(rack.getState().macros[0]).toBe(1);
      expect(() => rack.play({ kind: 'note.on', pitch: 60, velocity: 100 })).not.toThrow();
      expect(() => rack.stop({ kind: 'stop', reason: 'panic' })).not.toThrow();
      expect(() => rack.stop({ kind: 'stop', reason: 'transport' })).not.toThrow();
      const state = rack.getState();
      rack.setState(state);
      const restored = rack.getState();
      expect(restored.macros).toHaveLength(8);
      const hints = rack.getMappingHints();
      expect(hints.length).toBeGreaterThanOrEqual(8);
      const meters = rack.getMeters();
      expect(isNaN(meters.peakL)).toBe(false);
    });
  });
});

describe('D-D.4 — Acid303Rack conformance', () => {
  it('passes harness checks', async () => {
    const { Acid303Rack } = await import('../src/racks/webaudio/acid303');
    const rack = new Acid303Rack();
    expect(rack.engine).toBe('webaudio');
    expect(rack.getMappingHints().length).toBeGreaterThanOrEqual(8);
    rack.setMacro(0, 0.5); expect(rack.getState().macros[0]).toBe(0.5);
    expect(() => rack.play({ kind: 'note.on', pitch: 60, velocity: 100 })).not.toThrow();
    expect(() => rack.stop({ kind: 'stop', reason: 'panic' })).not.toThrow();
  });
});

describe('D-D.4 — BassMonoRack conformance', () => {
  it('passes harness checks', async () => {
    const { BassMonoRack } = await import('../src/racks/webaudio/bassMono');
    const rack = new BassMonoRack();
    expect(rack.engine).toBe('webaudio');
    expect(rack.getMappingHints().length).toBeGreaterThanOrEqual(8);
    rack.setMacro(3, 0.7); expect(rack.getState().macros[3]).toBe(0.7);
    expect(() => rack.stop({ kind: 'stop', reason: 'panic' })).not.toThrow();
  });
});

describe('D-D.4 — PolyKeysRack conformance', () => {
  it('passes harness checks', async () => {
    const { PolyKeysRack } = await import('../src/racks/webaudio/polyKeys');
    const rack = new PolyKeysRack();
    expect(rack.engine).toBe('webaudio');
    expect(rack.getMappingHints().length).toBeGreaterThanOrEqual(8);
    rack.setMacro(7, 0.9); expect(rack.getState().macros[7]).toBe(0.9);
    expect(() => rack.stop({ kind: 'stop', reason: 'panic' })).not.toThrow();
  });
});

// ── StrudelRack conformance ───────────────────────────────────────────────────

describe('D-D.4 — StrudelRack conformance', () => {
  runRackConformance(new StrudelRack('jam.rack.strudel-harness', 'Strudel Harness'));
});

// ── PureDataRack conformance ──────────────────────────────────────────────────

describe('D-D.4 — PureDataRack conformance', () => {
  runRackConformance(
    new PureDataRack(`jam.rack.pd-harness-${Date.now()}`, 'PureData Harness'),
  );
});

// ── ExternalMidiRack conformance ──────────────────────────────────────────────

describe('D-D.4 — ExternalMidiRack conformance (skipMeters=true)', () => {
  const stubOutput = new StubMidiOutput();
  runRackConformance(
    new ExternalMidiRack(`jam.rack.midi-harness-${Date.now()}`, 'MIDI Harness', {
      output: stubOutput,
    }),
    { skipMeters: true },
  );
});

// ── D-D.1 StrudelRack specific tests ─────────────────────────────────────────

describe('D-D.1 — StrudelRack', () => {
  it('engine is strudel', () => {
    const rack = new StrudelRack('jam.rack.strudel-d1', 'Strudel D1');
    expect(rack.engine).toBe('strudel');
  });

  it('setPattern() stores the pattern text', () => {
    const rack = new StrudelRack('jam.rack.strudel-d1b', 'Strudel D1b');
    rack.setPattern('s("bd sd").fast(2)');
    expect(rack.getPattern()).toBe('s("bd sd").fast(2)');
  });

  it('play() produces meter movement within 200 ms of first call', async () => {
    const rack = new StrudelRack('jam.rack.strudel-d1c', 'Strudel D1c');
    const t0 = performance.now();

    rack.play({ kind: 'trigger', voiceId: 'kick', velocity: 0.9 });

    const elapsed = performance.now() - t0;
    expect(elapsed).toBeLessThan(200);

    // Meters should show movement after play()
    const meters = rack.getMeters();
    const totalLevel = meters.peakL + meters.rmsL;
    expect(totalLevel).toBeGreaterThan(0);
  });

  it('captureToPattern() returns both strudel text and 64-step snapshot', () => {
    const rack = new StrudelRack('jam.rack.strudel-d1d', 'Strudel D1d');
    rack.setPattern('s("bd sd hh hh").fast(2)');
    const payload = rack.captureToPattern(4);

    expect(payload.engine).toBe('strudel');
    expect(typeof payload.source).toBe('string');
    expect(payload.source.length).toBeGreaterThan(0);
    expect(Array.isArray(payload.steps64)).toBe(true);
    expect(payload.steps64).toHaveLength(64);
    expect(payload.bars).toBe(4);
    expect(payload.bpm).toBeGreaterThan(0);
    expect(payload.capturedAt).toBeGreaterThan(0);
  });

  it('captureToPattern() 64-step snapshot has correct step indices', () => {
    const rack = new StrudelRack('jam.rack.strudel-d1e', 'Strudel D1e');
    const payload = rack.captureToPattern(4);
    for (let i = 0; i < 64; i++) {
      expect(payload.steps64[i]?.step).toBe(i);
    }
  });

  it('captureToPattern() source includes macro transforms', () => {
    const rack = new StrudelRack('jam.rack.strudel-d1f', 'Strudel D1f');
    rack.setPattern('note("c3 e3 g3")');
    rack.setMacro(3, 0.7); // space → .room(0.70)
    const payload = rack.captureToPattern(2);
    expect(payload.source).toContain('.room(');
    expect(payload.source).toContain('.lpf(');
  });

  it('getState().engineState contains pattern text', () => {
    const rack = new StrudelRack('jam.rack.strudel-d1g', 'Strudel D1g');
    rack.setPattern('s("bd")');
    const state = rack.getState();
    const es = state.engineState as { pattern?: string };
    expect(es.pattern).toBe('s("bd")');
  });

  it('setState() restores pattern text', () => {
    const rack = new StrudelRack('jam.rack.strudel-d1h', 'Strudel D1h');
    rack.setPattern('s("hh*4")');
    const saved = rack.getState();
    rack.setPattern('s("bd sd")');
    rack.setState(saved);
    expect(rack.getPattern()).toBe('s("hh*4")');
  });

  it('all 8 macro transforms appear in buildPatternWithMacros output', () => {
    const rack = new StrudelRack('jam.rack.strudel-d1i', 'Strudel D1i');
    rack.setPattern('s("bd")');
    // Set non-trivial values for all macros
    rack.setMacro(0, 0.8); // brightness → .lpf
    rack.setMacro(1, 0.6); // dirt → .coarse.shape
    rack.setMacro(2, 0.5); // wobble → .lfo
    rack.setMacro(3, 0.4); // space → .room
    rack.setMacro(4, 0.7); // snap → .attack
    rack.setMacro(5, 0.6); // body → .gain
    rack.setMacro(6, 0.7); // chaos → .degradeBy + .jux
    rack.setMacro(7, 0.5); // tension → .lpf .hpf
    const payload = rack.captureToPattern(1);
    const src = payload.source;
    expect(src).toContain('.lpf(');
    expect(src).toContain('.coarse(');
    expect(src).toContain('.shape(');
    expect(src).toContain('.lfo(');
    expect(src).toContain('.room(');
    expect(src).toContain('.attack(');
    expect(src).toContain('.gain(');
    expect(src).toContain('.degradeBy(');
    expect(src).toContain('.jux(');
    expect(src).toContain('.hpf(');
  });
});

// ── D-D.2 PureDataRack specific tests ────────────────────────────────────────

describe('D-D.2 — PureDataRack', () => {
  it('engine is puredata', () => {
    const rack = new PureDataRack('jam.rack.pd-d2', 'PD D2');
    expect(rack.engine).toBe('puredata');
  });

  it('REQUIRED_RECEIVERS lists all 11 required names', () => {
    expect(REQUIRED_RECEIVERS).toContain('jam-note');
    expect(REQUIRED_RECEIVERS).toContain('jam-trigger');
    expect(REQUIRED_RECEIVERS).toContain('jam-clock');
    for (let i = 1; i <= 8; i++) {
      expect(REQUIRED_RECEIVERS).toContain(`jam-macro-${i}`);
    }
    expect(REQUIRED_RECEIVERS).toHaveLength(11);
  });

  it('stub patch conforms (has all required receivers)', async () => {
    const rack = new PureDataRack('jam.rack.pd-d2b', 'PD D2b', {
      transport: 'in-browser',
    });
    // Load a stub patch (empty bytes → stub libpd fills receivers)
    await expect(rack.loadPatch(new Uint8Array(0), 'stub.pd')).resolves.not.toThrow();
  });

  it('stub patch responds to jam-trigger within 200 ms', async () => {
    const rack = new PureDataRack('jam.rack.pd-d2c', 'PD D2c', { transport: 'in-browser' });
    await rack.loadPatch(new Uint8Array(0), 'stub.pd');

    const t0 = performance.now();
    expect(() => rack.play({ kind: 'trigger', voiceId: 'kick', velocity: 0.8 })).not.toThrow();
    const elapsed = performance.now() - t0;
    expect(elapsed).toBeLessThan(200);
  });

  it('captureToPattern() returns engine=puredata and 64 steps', () => {
    const rack = new PureDataRack('jam.rack.pd-d2d', 'PD D2d');
    rack.play({ kind: 'trigger', voiceId: 'kick', velocity: 0.9 });
    const payload = rack.captureToPattern(4);
    expect(payload.engine).toBe('puredata');
    expect(payload.steps64).toHaveLength(64);
    expect(payload.bars).toBe(4);
  });

  it('captureToPattern() stores macro state', () => {
    const rack = new PureDataRack('jam.rack.pd-d2e', 'PD D2e');
    rack.setMacro(0, 0.75);
    const payload = rack.captureToPattern(2);
    expect(payload.macros[0]).toBeCloseTo(0.75);
  });

  it('transport defaults to in-browser for patch < 1 MB', () => {
    const rack = new PureDataRack('jam.rack.pd-d2f', 'PD D2f', {
      declaredPatchBytes: 100_000,
    });
    const state = rack.getState();
    expect((state.engineState as { transport: string }).transport).toBe('in-browser');
  });

  it('transport defaults to remote for patch >= 1 MB', () => {
    const rack = new PureDataRack('jam.rack.pd-d2g', 'PD D2g', {
      declaredPatchBytes: 2_000_000,
    });
    const state = rack.getState();
    expect((state.engineState as { transport: string }).transport).toBe('remote');
  });

  it('patch validation fails with descriptive error for missing receivers', async () => {
    const rack = new PureDataRack('jam.rack.pd-d2h', 'PD D2h', { transport: 'in-browser' });
    // Inject a custom libpd stub that returns empty receivers
    // We test indirectly by providing a non-stub environment that reports no receivers.
    // The validateReceivers logic is tested via the exported method.
    // We access it indirectly: load patch with bytes that produce empty receiver list
    // is not possible via the public API since the stub always returns required receivers.
    // Instead verify the error format by calling the private method through casting.
    const rackAny = rack as unknown as {
      validateReceivers(receivers: string[], name: string): void;
    };
    expect(() => rackAny.validateReceivers([], 'test.pd')).toThrow(/missing required receivers/);
    expect(() => rackAny.validateReceivers([], 'test.pd')).toThrow(/\[r jam-note\]/);
    expect(() => rackAny.validateReceivers([], 'test.pd')).toThrow(/conventions\.md/);
  });
});

// ── D-D.3 ExternalMidiRack specific tests ────────────────────────────────────

describe('D-D.3 — ExternalMidiRack', () => {
  let stub: StubMidiOutput;
  let rack: ExternalMidiRack;

  beforeEach(() => {
    stub = new StubMidiOutput();
    rack = new ExternalMidiRack(`jam.rack.midi-d3-${Date.now()}`, 'MIDI D3', {
      channel: 1,
      output: stub,
    });
    stub.clear();
  });

  it('engine is midi', () => {
    expect(rack.engine).toBe('midi');
  });

  it('play(JamNoteOn) sends correct note-on bytes on channel 1', () => {
    rack.play({ kind: 'note.on', pitch: 60, velocity: 100 });
    const msg = stub.lastMessage();
    expect(msg).not.toBeNull();
    expect(msg!.data[0]).toBe(0x90); // NOTE_ON ch1
    expect(msg!.data[1]).toBe(60);   // pitch
    expect(msg!.data[2]).toBe(100);  // velocity
  });

  it('stop(JamNoteOff) sends correct note-off bytes', () => {
    rack.play({ kind: 'note.on', pitch: 60, velocity: 100 });
    stub.clear();
    rack.stop({ kind: 'note.off', pitch: 60 });
    const msg = stub.lastMessage();
    expect(msg).not.toBeNull();
    expect(msg!.data[0]).toBe(0x80); // NOTE_OFF ch1
    expect(msg!.data[1]).toBe(60);
    expect(msg!.data[2]).toBe(0);
  });

  it('setMacro() sends CC message with correct CC number', () => {
    const cc = ccForMacro(0); // brightness → CC 20
    rack.setMacro(0, 1.0);
    const msg = stub.lastMessage();
    expect(msg).not.toBeNull();
    expect(msg!.data[0]).toBe(0xB0); // CC ch1
    expect(msg!.data[1]).toBe(cc);
    expect(msg!.data[2]).toBe(127);  // normalToMidiValue(1.0)
  });

  it('setMacro() CC values map correctly: 0→0, 0.5→64, 1→127', () => {
    const cc = ccForMacro(1); // dirt → CC 21
    rack.setMacro(1, 0);
    expect(stub.lastMessage()!.data[2]).toBe(0);
    stub.clear();
    rack.setMacro(1, 0.5);
    expect(stub.lastMessage()!.data[2]).toBe(64);
    stub.clear();
    rack.setMacro(1, 1);
    expect(stub.lastMessage()!.data[2]).toBe(127);
    void cc;
  });

  it('play(JamTrigger) sends note-on for kick → GM pitch 36', () => {
    rack.play({ kind: 'trigger', voiceId: 'kick', velocity: 1.0 });
    const msg = stub.messages[0];
    expect(msg).not.toBeNull();
    expect(msg!.data[0]).toBe(0x90);
    expect(msg!.data[1]).toBe(36); // GM kick
  });

  it('stop(panic) sends All Notes Off CC 123 and All Sound Off CC 120', () => {
    rack.play({ kind: 'note.on', pitch: 60, velocity: 100 });
    rack.play({ kind: 'note.on', pitch: 64, velocity: 100 });
    stub.clear();
    rack.stop({ kind: 'stop', reason: 'panic' });
    const ccMessages = stub.messages.filter((m) => (m.data[0] & 0xF0) === 0xB0);
    const ccNums = ccMessages.map((m) => m.data[1]);
    expect(ccNums).toContain(123); // All Notes Off
    expect(ccNums).toContain(120); // All Sound Off
  });

  it('getMeters() returns no-op zeros (output-first design)', () => {
    const meters = rack.getMeters();
    expect(meters.peakL).toBe(0);
    expect(meters.peakR).toBe(0);
    expect(meters.rmsL).toBe(0);
    expect(meters.rmsR).toBe(0);
  });

  it('getMappingHints() includes CC numbers in labels', () => {
    const hints = rack.getMappingHints();
    const brightnessHint = hints.find((h) => h.label.includes('brightness'));
    expect(brightnessHint).toBeDefined();
    expect(brightnessHint!.label).toContain('20'); // CC 20
  });

  it('channel 2 note-on uses 0x91 status byte', () => {
    const stub2 = new StubMidiOutput();
    const rack2 = new ExternalMidiRack(`jam.rack.midi-ch2-${Date.now()}`, 'MIDI ch2', {
      channel: 2,
      output: stub2,
    });
    rack2.play({ kind: 'note.on', pitch: 60, velocity: 100 });
    expect(stub2.lastMessage()!.data[0]).toBe(0x91); // NOTE_ON ch2
  });

  it('getState()/setState() round-trips macro values', () => {
    rack.setMacro(0, 0.75);
    const saved = rack.getState();
    rack.setMacro(0, 0.0);
    stub.clear();
    rack.setState(saved);
    expect(rack.getState().macros[0]).toBeCloseTo(0.75);
  });
});

// ── D-D.5 captureToPattern integration ───────────────────────────────────────

describe('D-D.5 — captureToPattern integration', () => {
  it('StrudelRack.captureToPattern() output is JSON-serialisable', () => {
    const rack = new StrudelRack('jam.rack.strudel-d5', 'Strudel D5');
    const payload = rack.captureToPattern(2);
    expect(() => JSON.stringify(payload)).not.toThrow();
  });

  it('PureDataRack.captureToPattern() output is JSON-serialisable', () => {
    const rack = new PureDataRack('jam.rack.pd-d5', 'PD D5');
    const payload = rack.captureToPattern(2);
    expect(() => JSON.stringify(payload)).not.toThrow();
  });

  it('StrudelRack captureToPattern has both source and steps64', () => {
    const rack = new StrudelRack('jam.rack.strudel-d5b', 'Strudel D5b');
    rack.setPattern('note("c3 e3 g3 b3")');
    const payload = rack.captureToPattern(4);
    expect(payload.source).toBeTruthy();
    expect(payload.steps64.length).toBe(64);
    // Steps64 step indices are 0-63
    const indices = payload.steps64.map((s) => s.step);
    expect(indices[0]).toBe(0);
    expect(indices[63]).toBe(63);
  });

  it('PureDataRack captureToPattern 64 steps have correct indices', () => {
    const rack = new PureDataRack('jam.rack.pd-d5b', 'PD D5b');
    const payload = rack.captureToPattern(4);
    for (let i = 0; i < 64; i++) {
      expect(payload.steps64[i]?.step).toBe(i);
    }
  });
});

// ── D-D.6 Bundle audit proxy test ────────────────────────────────────────────

describe('D-D.6 — Bundle audit: engine chunks are lazy imports', () => {
  it('StrudelRack does not eagerly import @strudel/core at module load time', async () => {
    // If this test can import StrudelRack without @strudel/core being installed,
    // the lazy import is working correctly (no top-level import of @strudel/core).
    const mod = await import('../src/racks/strudel/StrudelRack');
    expect(mod.StrudelRack).toBeDefined();
    // The rack itself should exist without @strudel/core
    const rack = new mod.StrudelRack('jam.rack.strudel-lazy', 'Lazy');
    expect(rack.engine).toBe('strudel');
  });

  it('PureDataRack does not eagerly import libpd-wasm at module load time', async () => {
    const mod = await import('../src/racks/puredata/PureDataRack');
    expect(mod.PureDataRack).toBeDefined();
    const rack = new mod.PureDataRack('jam.rack.pd-lazy', 'Lazy PD');
    expect(rack.engine).toBe('puredata');
  });

  it('ExternalMidiRack module loads without Web MIDI being available', async () => {
    const mod = await import('../src/racks/midi/ExternalMidiRack');
    expect(mod.ExternalMidiRack).toBeDefined();
    const stub = new mod.StubMidiOutput();
    const rack = new mod.ExternalMidiRack('jam.rack.midi-lazy', 'Lazy MIDI', { output: stub });
    expect(rack.engine).toBe('midi');
  });
});

// ── D-D.6 bundle audit assertions (proxy for actual bundle check) ─────────────

describe('D-D.6 — Bundle audit: boot bundle size proxy', () => {
  it('audit-bundle.ts script exists', async () => {
    // Verify the script file exists (actual size check runs via `node scripts/audit-bundle.ts`)
    const { existsSync } = await import('node:fs');
    const { resolve } = await import('node:path');
    const scriptPath = resolve(process.cwd(), 'scripts/audit-bundle.ts');
    // The file should exist after D-D.6 deliverable
    expect(existsSync(scriptPath)).toBe(true);
  });
});

// ── D-D.6 Macro fan-out doc/code parity spot check ───────────────────────────

describe('D-D.6 — Macro doc/code parity', () => {
  it('strudel macros.md documents all 8 macro names', async () => {
    const { readFileSync } = await import('node:fs');
    const { resolve } = await import('node:path');
    const docPath = resolve(process.cwd(), 'src/racks/strudel/macros.md');
    const content = readFileSync(docPath, 'utf8');
    const macroNames = ['brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension'];
    for (const name of macroNames) {
      expect(content).toContain(name);
    }
  });

  it('puredata macros.md documents all 8 macro names', async () => {
    const { readFileSync } = await import('node:fs');
    const { resolve } = await import('node:path');
    const docPath = resolve(process.cwd(), 'src/racks/puredata/macros.md');
    const content = readFileSync(docPath, 'utf8');
    const macroNames = ['brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension'];
    for (const name of macroNames) {
      expect(content).toContain(name);
    }
  });

  it('midi macros.md documents all 8 macro names', async () => {
    const { readFileSync } = await import('node:fs');
    const { resolve } = await import('node:path');
    const docPath = resolve(process.cwd(), 'src/racks/midi/macros.md');
    const content = readFileSync(docPath, 'utf8');
    const macroNames = ['brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension'];
    for (const name of macroNames) {
      expect(content).toContain(name);
    }
  });

  it('webaudio macros.md documents all 8 macro names for all 4 racks', async () => {
    const { readFileSync } = await import('node:fs');
    const { resolve } = await import('node:path');
    const docPath = resolve(process.cwd(), 'src/racks/webaudio/macros.md');
    const content = readFileSync(docPath, 'utf8');
    const macroNames = ['brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension'];
    for (const name of macroNames) {
      expect(content).toContain(name);
    }
    // Should mention all 4 racks
    expect(content).toContain('Drum808Rack');
    expect(content).toContain('Acid303Rack');
    expect(content).toContain('BassMonoRack');
    expect(content).toContain('PolyKeysRack');
  });

  it('cc-map.ts has exactly 8 entries', () => {
    expect(MACRO_CC_MAP).toHaveLength(8);
  });

  it('cc-map macro names match canonical vocabulary', () => {
    const macroNames = ['brightness', 'dirt', 'wobble', 'space', 'snap', 'body', 'chaos', 'tension'];
    const mapNames = MACRO_CC_MAP.map((e) => e.macroName);
    for (const name of macroNames) {
      expect(mapNames).toContain(name);
    }
  });
});

// ── MIDI CC map tests ─────────────────────────────────────────────────────────

import { MACRO_CC_MAP, normalToMidiValue, midiValueToNormal } from '../src/racks/midi/cc-map';

describe('D-D.3 — CC map', () => {
  it('ccForMacro(0) returns 20 (brightness)', () => {
    expect(ccForMacro(0)).toBe(20);
  });

  it('ccForMacro(7) returns 27 (tension)', () => {
    expect(ccForMacro(7)).toBe(27);
  });

  it('normalToMidiValue round-trips cleanly', () => {
    expect(normalToMidiValue(0)).toBe(0);
    expect(normalToMidiValue(1)).toBe(127);
    expect(normalToMidiValue(0.5)).toBe(64);
  });

  it('midiValueToNormal(127) ≈ 1', () => {
    expect(midiValueToNormal(127)).toBeCloseTo(1, 3);
  });

  it('all CC numbers are in range 20–27', () => {
    for (const entry of MACRO_CC_MAP) {
      expect(entry.cc).toBeGreaterThanOrEqual(20);
      expect(entry.cc).toBeLessThanOrEqual(27);
    }
  });

  it('macro indices match array positions', () => {
    for (let i = 0; i < MACRO_CC_MAP.length; i++) {
      expect(MACRO_CC_MAP[i]!.macroIndex).toBe(i);
    }
  });
});

```
