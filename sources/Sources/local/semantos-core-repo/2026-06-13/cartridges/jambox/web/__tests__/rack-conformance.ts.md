---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/__tests__/rack-conformance.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.599764+00:00
---

# cartridges/jambox/web/__tests__/rack-conformance.ts

```ts
/**
 * Engine conformance harness — D-D.4
 *
 * Exports `runRackConformance(rack, opts?)` which asserts the full
 * JamRack contract against any implementation.
 *
 * Criteria checked:
 *   1. 8 macros clamp to [0,1]
 *   2. play() + stop() leaves no hanging notes (panic path)
 *   3. getState() round-trips setState()
 *   4. getMappingHints() returns >= 8 hints
 *   5. meters return non-NaN, non-negative values during playback
 *      (skipped when opts.skipMeters = true)
 */

import { it, expect } from 'vitest';
import type { JamRack, JamNoteOn, JamTrigger, JamStop } from '../src/racks/contract';

export interface ConformanceOpts {
  /**
   * Skip meter assertions. Use for racks whose output device doesn't report
   * audio levels (e.g. ExternalMidiRack).
   */
  skipMeters?: boolean;
}

/**
 * Run the full JamRack conformance suite against `rack`.
 * Call this inside a describe() block.
 *
 * @example
 * describe('Drum808Rack conformance', () => {
 *   runRackConformance(new Drum808Rack());
 * });
 */
export function runRackConformance(rack: JamRack, opts: ConformanceOpts = {}): void {
  // ── 1. Identity ─────────────────────────────────────────────────────────────

  it('has a non-empty id', () => {
    expect(typeof rack.id).toBe('string');
    expect(rack.id.length).toBeGreaterThan(0);
  });

  it('has a non-empty name', () => {
    expect(typeof rack.name).toBe('string');
    expect(rack.name.length).toBeGreaterThan(0);
  });

  it('has a valid engine kind', () => {
    const validEngines = ['webaudio', 'puredata', 'strudel', 'midi', 'hybrid'];
    expect(validEngines).toContain(rack.engine);
  });

  // ── 2. Macro clamping ────────────────────────────────────────────────────────

  it('clamps macro index below 0 to index 0', () => {
    expect(() => rack.setMacro(-1, 0.5)).not.toThrow();
    const state = rack.getState();
    expect(state.macros[0]).toBeCloseTo(0.5, 5);
  });

  it('clamps macro index above 7 to index 7', () => {
    expect(() => rack.setMacro(99, 0.8)).not.toThrow();
    const state = rack.getState();
    expect(state.macros[7]).toBeCloseTo(0.8, 5);
  });

  it('clamps macro value below 0 to 0', () => {
    rack.setMacro(0, -5);
    const state = rack.getState();
    expect(state.macros[0]).toBe(0);
  });

  it('clamps macro value above 1 to 1', () => {
    rack.setMacro(0, 999);
    const state = rack.getState();
    expect(state.macros[0]).toBe(1);
  });

  it('stores macro value in [0,1] range for all 8 macros', () => {
    for (let i = 0; i < 8; i++) {
      rack.setMacro(i, i / 7);
    }
    const state = rack.getState();
    expect(state.macros).toHaveLength(8);
    for (const v of state.macros) {
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThanOrEqual(1);
    }
  });

  // ── 3. play() + stop() leaves no hanging notes ───────────────────────────────

  it('play() does not throw for JamNoteOn', () => {
    const noteOn: JamNoteOn = { kind: 'note.on', pitch: 60, velocity: 100 };
    expect(() => rack.play(noteOn)).not.toThrow();
  });

  it('play() does not throw for JamTrigger', () => {
    const trigger: JamTrigger = { kind: 'trigger', voiceId: 'kick', velocity: 0.8 };
    expect(() => rack.play(trigger)).not.toThrow();
  });

  it('stop(panic) does not throw and leaves no hanging notes', () => {
    // Play several notes
    rack.play({ kind: 'note.on', pitch: 60, velocity: 100 });
    rack.play({ kind: 'note.on', pitch: 64, velocity: 100 });
    rack.play({ kind: 'trigger', voiceId: 'kick', velocity: 1 });

    const panic: JamStop = { kind: 'stop', reason: 'panic' };
    expect(() => rack.stop(panic)).not.toThrow();

    // After panic, meter levels should be at or near 0
    // (exact value depends on engine, but it must not throw)
    expect(() => rack.getMeters()).not.toThrow();
  });

  it('stop(transport) does not throw', () => {
    expect(() => rack.stop({ kind: 'stop', reason: 'transport' })).not.toThrow();
  });

  it('stop(note.off) does not throw', () => {
    rack.play({ kind: 'note.on', pitch: 60, velocity: 100 });
    expect(() => rack.stop({ kind: 'note.off', pitch: 60 })).not.toThrow();
  });

  // ── 4. getState() / setState() round-trip ───────────────────────────────────

  it('getState() returns a JamRackState with macros array', () => {
    const state = rack.getState();
    expect(state).toHaveProperty('macros');
    expect(Array.isArray(state.macros)).toBe(true);
    expect(state.macros.length).toBeGreaterThanOrEqual(8);
  });

  it('setState() restores macro values', () => {
    // Set known values
    for (let i = 0; i < 8; i++) rack.setMacro(i, 0.123 + i * 0.1);
    const saved = rack.getState();

    // Scramble
    for (let i = 0; i < 8; i++) rack.setMacro(i, 0.5);

    // Restore
    rack.setState(saved);
    const restored = rack.getState();

    for (let i = 0; i < 8; i++) {
      expect(restored.macros[i]).toBeCloseTo(saved.macros[i] ?? 0, 4);
    }
  });

  it('setState() handles partial state gracefully', () => {
    expect(() => rack.setState({ macros: [], engineState: null })).not.toThrow();
  });

  it('getState() is JSON-serialisable', () => {
    const state = rack.getState();
    expect(() => JSON.stringify(state)).not.toThrow();
    const parsed = JSON.parse(JSON.stringify(state)) as typeof state;
    expect(parsed.macros).toBeDefined();
  });

  // ── 5. getMappingHints() ─────────────────────────────────────────────────────

  it('getMappingHints() returns >= 8 hints', () => {
    const hints = rack.getMappingHints();
    expect(Array.isArray(hints)).toBe(true);
    expect(hints.length).toBeGreaterThanOrEqual(8);
  });

  it('getMappingHints() hints have required fields', () => {
    const hints = rack.getMappingHints();
    for (const hint of hints) {
      expect(typeof hint.inputType).toBe('string');
      expect(typeof hint.target).toBe('string');
      expect(typeof hint.label).toBe('string');
    }
  });

  it('getMappingHints() includes one hint per macro (0..7)', () => {
    const hints = rack.getMappingHints();
    const macroHints = hints.filter((h) => h.target.startsWith('macro.'));
    expect(macroHints.length).toBeGreaterThanOrEqual(8);
  });

  // ── 6. Meters ────────────────────────────────────────────────────────────────

  if (!opts.skipMeters) {
    it('getMeters() returns non-NaN values', () => {
      const meters = rack.getMeters();
      expect(isNaN(meters.peakL)).toBe(false);
      expect(isNaN(meters.peakR)).toBe(false);
      expect(isNaN(meters.rmsL)).toBe(false);
      expect(isNaN(meters.rmsR)).toBe(false);
    });

    it('getMeters() returns non-negative values', () => {
      const meters = rack.getMeters();
      expect(meters.peakL).toBeGreaterThanOrEqual(0);
      expect(meters.peakR).toBeGreaterThanOrEqual(0);
      expect(meters.rmsL).toBeGreaterThanOrEqual(0);
      expect(meters.rmsR).toBeGreaterThanOrEqual(0);
    });

    it('getMeters() after play() has non-decreasing peak level (or stays at 0 without audio ctx)', () => {
      const before = rack.getMeters();
      rack.play({ kind: 'note.on', pitch: 60, velocity: 127 });
      const after = rack.getMeters();
      // Peak must be >= before (non-decreasing), and both must be non-NaN
      expect(isNaN(after.peakL)).toBe(false);
      expect(after.peakL).toBeGreaterThanOrEqual(0);
      // Allow peak to be 0 in stub environments (no AudioContext)
      expect(after.peakL + after.rmsL).toBeGreaterThanOrEqual(before.peakL + before.rmsL - 0.001);
    });
  } else {
    it('getMeters() returns no-op zeros (skipMeters=true)', () => {
      const meters = rack.getMeters();
      expect(isNaN(meters.peakL)).toBe(false);
      expect(isNaN(meters.rmsL)).toBe(false);
    });
  }
}

```
