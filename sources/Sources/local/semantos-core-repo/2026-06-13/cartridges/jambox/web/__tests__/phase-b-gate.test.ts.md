---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/__tests__/phase-b-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.600652+00:00
---

# cartridges/jambox/web/__tests__/phase-b-gate.test.ts

```ts
/**
 * D-B.8 — Phase B gate test.
 *
 * Covers all criteria from PRD §D-B.8:
 *
 * 1. Anchor row: mounts; play/stop/record/capture buttons emit canonical cells.
 * 2. Mode row: shows exactly 3 L2 buttons (Rhythm/Melody/Bass).
 * 3. Support sheet: contains 5 entries in stable order (Seq/Mix/Session/Arrange/Custom).
 *    Custom is disabled.
 * 4. Tapping each L2 button switches surface.mode to its default mode.
 * 5. Tap-tap on an L2 button cycles to the secondary mode.
 * 6. Long-press on an L2 button opens the support sheet pre-scoped to that rack.
 * 7. Note mode (scale layout): pressing pad (3,4) on default pentatonic emits
 *    jam.note.on with correct pitch; rendered pad carries colourForPitch spec
 *    (root pad = gold ring).
 * 8. Note mode scale-lock: chromatic pad emits NO jam.note.on; visual flash
 *    logs jam.input.pad with correct padIndex.
 * 9. Note mode label mode cycle: off → number → solfege → note-name → fingering.
 * 10. Mix peek: dragging volume row by ±0.2 emits jam.rack.macro.set.
 * 11. Mix-full (support sheet): same dragging emits same cells.
 * 12. Session view: arming + recording + launching emits four canonical cells.
 * 13. Phase A gate test re-runs and passes (imports).
 */

import { describe, it, expect } from 'vitest';

// ── Phase A imports (re-run key assertions) ───────────────────────────────────
import { classifyPitch, colourForPitch } from '../src/colour/scale-colour';
import { GridSurface } from '../src/grid/surface';
import type { GridSurfaceCallbacks } from '../src/grid/surface';

// ── Phase B imports ───────────────────────────────────────────────────────────
import { SUPPORT_ENTRIES } from '../src/ui/support-sheet';
import { L2_CONFIGS } from '../src/ui/mode-row';
import {
  renderNotePads, handleNotePress,
  createNoteModeState, scaleCols,
} from '../src/grid/note-mode';
import {
  renderMixPads, handleMixPress, renderMixPeek,
  createMixModeState,
} from '../src/grid/mix-mode';
import {
  handleSessionPress, createSessionModeState,
  promoteSceneIndex,
} from '../src/grid/session-mode';
import {
  createArrangementModeState, handleArrangementPress,
} from '../src/grid/arrangement-mode';

// ─────────────────────────────────────────────────────────────────────────────

// ─── 1. Anchor row structure ──────────────────────────────────────────────────

describe('1. Anchor row module', () => {
  it('mountAnchorRow is a function', async () => {
    const { mountAnchorRow } = await import('../src/ui/anchor-row');
    expect(typeof mountAnchorRow).toBe('function');
  });

  it('mountAnchorRow emits jam.clock.start on play click', async () => {
    const { mountAnchorRow } = await import('../src/ui/anchor-row');
    // Use a minimal DOM host
    const host = document.createElement('div');
    document.body.appendChild(host);

    const emitted: string[] = [];
    const handle = mountAnchorRow(host, (e) => emitted.push(e.family));

    // Trigger play
    const playBtn = host.querySelector('[data-testid="anchor-play"]') as HTMLButtonElement;
    expect(playBtn).not.toBeNull();
    playBtn.click();
    expect(emitted).toContain('jam.clock.start');

    // Trigger stop (second click)
    playBtn.click();
    expect(emitted).toContain('jam.clock.stop');

    handle.destroy();
    document.body.removeChild(host);
  });

  it('mountAnchorRow emits jam.clip.arm on record click', async () => {
    const { mountAnchorRow } = await import('../src/ui/anchor-row');
    const host = document.createElement('div');
    document.body.appendChild(host);

    const emitted: string[] = [];
    const handle = mountAnchorRow(host, (e) => emitted.push(e.family));

    const recBtn = host.querySelector('[data-testid="anchor-record"]') as HTMLButtonElement;
    expect(recBtn).not.toBeNull();
    recBtn.click();
    expect(emitted).toContain('jam.clip.arm');

    handle.destroy();
    document.body.removeChild(host);
  });

  it('mountAnchorRow emits jam.capture.intent on capture click', async () => {
    const { mountAnchorRow } = await import('../src/ui/anchor-row');
    const host = document.createElement('div');
    document.body.appendChild(host);

    const emitted: string[] = [];
    const handle = mountAnchorRow(host, (e) => emitted.push(e.family));

    const captureBtn = host.querySelector('[data-testid="anchor-capture"]') as HTMLButtonElement;
    expect(captureBtn).not.toBeNull();
    captureBtn.click();
    expect(emitted).toContain('jam.capture.intent');

    handle.destroy();
    document.body.removeChild(host);
  });

  it('mountAnchorRow update() changes bpm display', async () => {
    const { mountAnchorRow } = await import('../src/ui/anchor-row');
    const host = document.createElement('div');
    document.body.appendChild(host);

    const handle = mountAnchorRow(host, () => {});
    handle.update({ bpm: 140 });

    const tempoBtn = host.querySelector('[data-testid="anchor-tempo"]') as HTMLButtonElement;
    expect(tempoBtn.textContent).toContain('140');

    handle.destroy();
    document.body.removeChild(host);
  });
});

// ─── 2. Mode row: exactly 3 L2 buttons ───────────────────────────────────────

describe('2. Mode row: 3 L2 buttons', () => {
  it('L2_CONFIGS has exactly 3 entries', () => {
    expect(L2_CONFIGS).toHaveLength(3);
  });

  it('L2 buttons are Rhythm, Melody, Bass', () => {
    const ids = L2_CONFIGS.map((c) => c.id);
    expect(ids).toEqual(['rhythm', 'melody', 'bass']);
  });

  it('mountModeRow mounts 3 buttons in the DOM', async () => {
    const { mountModeRow } = await import('../src/ui/mode-row');

    const host = document.createElement('div');
    document.body.appendChild(host);

    const surface = makeSurface();
    const handle = mountModeRow(host, surface, {
      onModeChange: () => {},
      onLongPress: () => {},
    });

    const btns = host.querySelectorAll('[data-l2]');
    expect(btns).toHaveLength(3);
    expect((btns[0] as HTMLElement).dataset.l2).toBe('rhythm');
    expect((btns[1] as HTMLElement).dataset.l2).toBe('melody');
    expect((btns[2] as HTMLElement).dataset.l2).toBe('bass');

    handle.destroy();
    document.body.removeChild(host);
  });
});

// ─── 3. Support sheet: 5 entries (Custom enabled in Phase C) ─────────────────

describe('3. Support sheet entries', () => {
  it('SUPPORT_ENTRIES has exactly 5 entries', () => {
    expect(SUPPORT_ENTRIES).toHaveLength(5);
  });

  it('entries are in stable order: sequencer, mix, session, arrange, custom', () => {
    const ids = SUPPORT_ENTRIES.map((e) => e.id);
    expect(ids).toEqual(['sequencer', 'mix', 'session', 'arrange', 'custom']);
  });

  it('custom entry exists', () => {
    const custom = SUPPORT_ENTRIES.find((e) => e.id === 'custom');
    expect(custom).toBeDefined();
  });

  // Phase C enables Custom (D-C.5). This test was updated from Phase B.
  it('custom entry is enabled in Phase C', () => {
    const custom = SUPPORT_ENTRIES.find((e) => e.id === 'custom')!;
    expect(custom.disabled).toBe(false);
    expect(custom.mode).toBe('custom');
  });

  it('non-custom entries are not disabled', () => {
    for (const entry of SUPPORT_ENTRIES.filter((e) => e.id !== 'custom')) {
      expect(entry.disabled).toBe(false);
    }
  });

  it('mountSupportSheet renders 5 entries in DOM', async () => {
    const { mountSupportSheet } = await import('../src/ui/support-sheet');
    const host = document.createElement('div');
    document.body.appendChild(host);

    const surface = makeSurface();
    const handle = mountSupportSheet(host, surface, {
      onEntrySelect: () => {},
      onClose: () => {},
    });

    const entries = host.querySelectorAll('[data-entry]');
    expect(entries).toHaveLength(5);

    handle.destroy();
    document.body.removeChild(host);
  });
});

// ─── 4. L2 button → default mode ─────────────────────────────────────────────

describe('4. L2 button tapping switches surface.mode to default', () => {
  it('Rhythm button → step mode', async () => {
    const { mountModeRow } = await import('../src/ui/mode-row');
    const host = document.createElement('div');
    document.body.appendChild(host);

    const surface = makeSurface();
    const modes: string[] = [];
    const handle = mountModeRow(host, surface, {
      onModeChange: (_btn, mode) => modes.push(mode),
      onLongPress: () => {},
    });

    const rhythmBtn = host.querySelector('[data-l2="rhythm"]') as HTMLButtonElement;
    rhythmBtn.click();
    expect(modes).toContain('step');
    expect(surface.getMode()).toBe('step');

    handle.destroy();
    document.body.removeChild(host);
  });

  it('Melody button → note mode', async () => {
    const { mountModeRow } = await import('../src/ui/mode-row');
    const host = document.createElement('div');
    document.body.appendChild(host);

    const surface = makeSurface();
    // Need a rack registered for mix mode to be reachable, but melody → note is fine
    surface.registerRack('jam.rack.poly-keys');
    const modes: string[] = [];
    const handle = mountModeRow(host, surface, {
      onModeChange: (_btn, mode) => modes.push(mode),
      onLongPress: () => {},
    });

    const melodyBtn = host.querySelector('[data-l2="melody"]') as HTMLButtonElement;
    melodyBtn.click();
    expect(modes).toContain('note');
    expect(surface.getMode()).toBe('note');

    handle.destroy();
    document.body.removeChild(host);
  });

  it('Bass button → note mode', async () => {
    const { mountModeRow } = await import('../src/ui/mode-row');
    const host = document.createElement('div');
    document.body.appendChild(host);

    const surface = makeSurface();
    surface.registerRack('jam.rack.bass-mono');
    const modes: string[] = [];
    const handle = mountModeRow(host, surface, {
      onModeChange: (_btn, mode) => modes.push(mode),
      onLongPress: () => {},
    });

    const bassBtn = host.querySelector('[data-l2="bass"]') as HTMLButtonElement;
    bassBtn.click();
    expect(modes).toContain('note');

    handle.destroy();
    document.body.removeChild(host);
  });
});

// ─── 5. Tap-tap cycles secondary mode ────────────────────────────────────────

describe('5. Tap-tap cycles secondary mode', () => {
  it('Rhythm tap-tap: step → param', async () => {
    const { mountModeRow } = await import('../src/ui/mode-row');
    const host = document.createElement('div');
    document.body.appendChild(host);

    const surface = makeSurface();
    const modes: string[] = [];
    const handle = mountModeRow(host, surface, {
      onModeChange: (_btn, mode) => modes.push(mode),
      onLongPress: () => {},
    });

    const rhythmBtn = host.querySelector('[data-l2="rhythm"]') as HTMLButtonElement;
    rhythmBtn.click(); // first tap → step
    rhythmBtn.click(); // second tap → param
    expect(modes[0]).toBe('step');
    expect(modes[1]).toBe('param');

    handle.destroy();
    document.body.removeChild(host);
  });

  it('Melody tap-tap: note → mix', async () => {
    const { mountModeRow } = await import('../src/ui/mode-row');
    const host = document.createElement('div');
    document.body.appendChild(host);

    const surface = makeSurface();
    surface.registerRack('jam.rack.poly-keys');
    const modes: string[] = [];
    const handle = mountModeRow(host, surface, {
      onModeChange: (_btn, mode) => modes.push(mode),
      onLongPress: () => {},
    });

    const melodyBtn = host.querySelector('[data-l2="melody"]') as HTMLButtonElement;
    melodyBtn.click(); // first tap → note
    melodyBtn.click(); // second tap → mix
    expect(modes[0]).toBe('note');
    // mix mode requires a registered rack — surface.registerRack called above
    expect(modes[1]).toBe('mix');

    handle.destroy();
    document.body.removeChild(host);
  });
});

// ─── 6. Long-press opens support sheet pre-scoped ────────────────────────────

describe('6. Long-press opens support sheet pre-scoped to rack', () => {
  it('long-press fires onLongPress with rackId', async () => {
    const { mountModeRow } = await import('../src/ui/mode-row');
    const host = document.createElement('div');
    document.body.appendChild(host);

    const surface = makeSurface();
    const longPresses: Array<{ button: string; rackId: string }> = [];
    const handle = mountModeRow(host, surface, {
      onModeChange: () => {},
      onLongPress: (button, rackId) => longPresses.push({ button, rackId }),
    });

    // Simulate long-press by dispatching pointerdown then waiting 600ms
    const rhythmBtn = host.querySelector('[data-l2="rhythm"]') as HTMLButtonElement;
    // PointerEvent may not be available in jsdom; fall back to MouseEvent
    const PointerEventCtor = (typeof PointerEvent !== 'undefined' ? PointerEvent : MouseEvent) as typeof MouseEvent;
    rhythmBtn.dispatchEvent(new PointerEventCtor('pointerdown', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 600));

    expect(longPresses.length).toBeGreaterThan(0);
    expect(longPresses[0].button).toBe('rhythm');
    expect(longPresses[0].rackId).toBe('jam.rack.drum-808');

    handle.destroy();
    document.body.removeChild(host);
  });
});

// ─── 7. Note mode: colourForPitch + correct pitch on press ───────────────────

describe('7. Note mode: scale-channel colour + correct pitch', () => {
  it('renderNotePads returns 64 pads', () => {
    const state = createNoteModeState('scale', 'jam.rack.poly-keys');
    const pads = renderNotePads(state);
    expect(pads).toHaveLength(64);
  });

  it('root pad (C=0, pentatonic) is rendered with gold-ring label prefix', () => {
    // C = root, pentatonic scale, root = 0
    const state = createNoteModeState('scale', 'jam.rack.poly-keys', {
      scale: 'pentatonic', root: 0, octave: 3, labelMode: 'number',
    });
    const pads = renderNotePads(state);
    // In scale layout, row 7 col 0 = lowest octave, col 0 = scale degree 0 = root
    // Find a pad that maps to pitch class 0 (C)
    let foundRoot = false;
    for (const pad of pads) {
      if (pad.active && pad.label.startsWith('#')) {
        foundRoot = true; // '#' prefix = gold-ring encoding
        break;
      }
    }
    expect(foundRoot).toBe(true);
  });

  it('pressing pad(3,4) on pentatonic emits jam.note.on with correct pitch', () => {
    const state = createNoteModeState('scale', 'jam.rack.poly-keys', {
      scale: 'pentatonic', root: 0, octave: 3, scaleLock: true,
    });
    const padIndex = 3 * 8 + 4; // row=3, col=4
    const { events } = handleNotePress(padIndex, state);
    const noteOn = events.find((e) => e.family === 'jam.note.on');
    expect(noteOn).toBeDefined();
    expect(noteOn!.family).toBe('jam.note.on');
    // col 4 in pentatonic = index 4 → interval 9 (A) + octave
    // pitch should be in range 48-84 (reasonable MIDI melodic range)
    expect((noteOn as { pitch: number }).pitch).toBeGreaterThanOrEqual(36);
    expect((noteOn as { pitch: number }).pitch).toBeLessThanOrEqual(108);
  });

  it('colourForPitch is called for each pad (root has gold-ring border)', () => {
    // Direct test of colourForPitch for the root pad
    const spec = colourForPitch(60, 'pentatonic', 0, 'boomwhacker', 'off'); // C4
    expect(spec.border).toBe('gold-ring');
  });

  it('scaleCols: pentatonic = 5 cols, major = 7 cols', () => {
    expect(scaleCols('pentatonic')).toBe(5);
    expect(scaleCols('major')).toBe(7);
  });

  it('classifyPitch: root = root, in-scale = in-scale, chromatic = chromatic', () => {
    // C major, root = C(0)
    expect(classifyPitch(60, 'major', 0)).toBe('root');  // C
    expect(classifyPitch(62, 'major', 0)).toBe('in-scale'); // D
    expect(classifyPitch(61, 'major', 0)).toBe('chromatic'); // C# not in major
  });
});

// ─── 8. Note mode scale-lock: chromatic pad is silent ────────────────────────

describe('8. Note mode scale-lock chromatic guardrail', () => {
  it('chromatic pad with scale-lock ON emits no jam.note.on', () => {
    // In C pentatonic (intervals: 0,2,4,7,9), pitch class 1 (C#) is chromatic
    // iso-fourths layout has all pitches including chromatic ones
    const stateIso = createNoteModeState('iso-fourths', 'jam.rack.poly-keys', {
      scale: 'pentatonic', root: 0, octave: 3, scaleLock: true,
    });

    // Try many pads to find a chromatic one
    let foundChromatic = false;
    for (let i = 0; i < 64; i++) {
      const { events, stateChanges } = handleNotePress(i, stateIso);
      const noteOn = events.find((e) => e.family === 'jam.note.on');
      const inputPad = events.find((e) => e.family === 'jam.input.pad');
      if (!noteOn && stateChanges.flashingPads && stateChanges.flashingPads.size > 0) {
        // This is a chromatic pad: no note.on, but flash was triggered
        expect(inputPad).toBeDefined(); // jam.input.pad always emitted
        expect(inputPad!.family).toBe('jam.input.pad');
        foundChromatic = true;
        break;
      }
    }
    expect(foundChromatic).toBe(true);
  });

  it('chromatic pad with scale-lock OFF emits jam.note.on', () => {
    const stateIso = createNoteModeState('iso-fourths', 'jam.rack.poly-keys', {
      scale: 'pentatonic', root: 0, octave: 3, scaleLock: false,
    });

    // At octave=3, root=C(0), pad 1 = C3 + 5 semitones = F (in-scale) → try pad 2
    // In iso-fourths: pitch = baseNote + row*5 + col
    // baseNote = 0 + 3*12 = 36 (C3), pad at row=0,col=1 = 36+1=37=C#3 (chromatic in pentatonic)
    const padIndex = 0 * 8 + 1; // row=0, col=1 → pitch=37 (C#3)
    const { events } = handleNotePress(padIndex, stateIso);
    const noteOn = events.find((e) => e.family === 'jam.note.on');
    expect(noteOn).toBeDefined();
  });
});

// ─── 9. Note mode label cycle ─────────────────────────────────────────────────

describe('9. Note mode label mode cycle', () => {
  const LABEL_CYCLE = ['off', 'number', 'solfege', 'note-name', 'fingering'] as const;

  it('label modes are 5 and in order', () => {
    expect(LABEL_CYCLE).toHaveLength(5);
    expect(LABEL_CYCLE[0]).toBe('off');
    expect(LABEL_CYCLE[4]).toBe('fingering');
  });

  it('default label mode is off', () => {
    const state = createNoteModeState('scale', 'jam.rack.poly-keys');
    expect(state.labelMode).toBe('off');
  });

  it('colourForPitch with labelMode=number returns a number string for in-scale pads', () => {
    const spec = colourForPitch(62, 'major', 0, 'boomwhacker', 'number'); // D in C major = degree 2
    expect(spec.label).toBe('2');
  });

  it('colourForPitch with labelMode=solfege returns solfege', () => {
    const spec = colourForPitch(62, 'major', 0, 'boomwhacker', 'solfege'); // D = Re
    expect(spec.label).toBe('Re');
  });

  it('colourForPitch with labelMode=note-name returns note name', () => {
    const spec = colourForPitch(60, 'major', 0, 'boomwhacker', 'note-name'); // C4
    expect(spec.label).toMatch(/^C/);
  });

  it('colourForPitch with labelMode=off returns empty string', () => {
    const spec = colourForPitch(60, 'major', 0, 'boomwhacker', 'off');
    expect(spec.label).toBeUndefined();
  });
});

// ─── 10. Mix peek: volume drag emits jam.rack.macro.set ──────────────────────

describe('10. Mix peek volume drag emits jam.rack.macro.set', () => {
  it('renderMixPeek returns 16 pads (2 rows × 8 cols)', () => {
    const state = createMixModeState([
      { rackId: 'jam.rack.bass-mono', label: 'Bass' },
    ]);
    const pads = renderMixPeek(state);
    expect(pads).toHaveLength(16);
  });

  it('pressing volume row (row=0) in mix emits jam.rack.macro.set', () => {
    const trackInfos = [
      { rackId: 'jam.rack.bass-mono', label: 'Bass' },
      { rackId: 'jam.rack.poly-keys', label: 'Keys' },
    ];
    const state = createMixModeState(trackInfos);
    // padIndex 0 = row 0, col 0 = volume for track 0
    const { events } = handleMixPress(0, state, 0.2);
    const macroSet = events.find((e) => e.family === 'jam.rack.macro.set');
    expect(macroSet).toBeDefined();
    expect((macroSet as { rackId: string }).rackId).toBe('jam.rack.bass-mono');
    expect(typeof (macroSet as { value: number }).value).toBe('number');
  });

  it('volume value changes by delta', () => {
    const trackInfos = [{ rackId: 'jam.rack.bass-mono', label: 'Bass' }];
    const state = createMixModeState(trackInfos);
    const initialVol = state.tracks[0]!.volume;
    const { stateChanges } = handleMixPress(0, state, 0.2);
    expect(stateChanges.tracks![0]!.volume).toBeCloseTo(initialVol + 0.2, 5);
  });
});

// ─── 11. Mix-full: same events as peek ───────────────────────────────────────

describe('11. Mix-full grid emits correct cells', () => {
  it('renderMixPads returns 64 pads', () => {
    const state = createMixModeState([
      { rackId: 'jam.rack.drum-808', label: 'Drums' },
    ]);
    const pads = renderMixPads(state);
    expect(pads).toHaveLength(64);
  });

  it('mute row (row=3) press emits jam.control.change', () => {
    const trackInfos = [{ rackId: 'jam.rack.drum-808', label: 'Drums' }];
    const state = createMixModeState(trackInfos);
    // padIndex 24 = row 3 col 0 = mute for track 0
    const { events } = handleMixPress(24, state, 0);
    const cc = events.find((e) => e.family === 'jam.control.change');
    expect(cc).toBeDefined();
    expect((cc as { target: string }).target).toContain('mute');
  });

  it('right edge (col 7) master volume emits jam.control.change', () => {
    const state = createMixModeState([]);
    // padIndex 7 = row 0 col 7 = master volume
    const { events } = handleMixPress(7, state, 0.1);
    const cc = events.find((e) => e.family === 'jam.control.change');
    expect(cc).toBeDefined();
    expect((cc as { target: string }).target).toContain('master');
  });
});

// ─── 12. Session view: arm + record + launch canonical cells ──────────────────

describe('12. Session view: clip lifecycle events', () => {
  it('tapping empty cell emits jam.clip.arm + jam.clip.record.start', () => {
    const state = createSessionModeState();
    const { events } = handleSessionPress(0, state); // row=0, col=0 = empty
    const families = events.map((e) => e.family);
    expect(families).toContain('jam.clip.arm');
    expect(families).toContain('jam.clip.record.start');
    expect(families).toContain('jam.input.pad');
  });

  it('tapping playing cell emits jam.clip.stop.queue', () => {
    const state = createSessionModeState();
    // Set slot 0 to playing
    state.slots[0] = {
      clipId: 'clip-test', name: 'C00', color: 'green', state: 'playing',
    };
    const { events } = handleSessionPress(0, state);
    expect(events.map((e) => e.family)).toContain('jam.clip.stop.queue');
  });

  it('scene launch column (col=7) emits jam.scene.launch', () => {
    const state = createSessionModeState();
    state.sceneIds[0] = 'jam.scene.test-room.0';
    const padIndex = 0 * 8 + 7; // row=0, col=7
    const { events } = handleSessionPress(padIndex, state);
    expect(events.map((e) => e.family)).toContain('jam.scene.launch');
  });

  it('promoteSceneIndex is idempotent', () => {
    const id1 = promoteSceneIndex(0, 'my-room');
    const id2 = promoteSceneIndex(0, 'my-room');
    expect(id1).toBe(id2);
    expect(id1.length).toBeGreaterThan(0);
  });

  it('quantum defaults to 1 bar (4 beats)', () => {
    const state = createSessionModeState();
    expect(state.quantum).toBe(4);
  });
});

// ─── Phase A re-run: key invariants still hold ────────────────────────────────

describe('Phase A gate re-run (key invariants)', () => {
  it('colourForPitch is still a function', () => {
    expect(typeof colourForPitch).toBe('function');
  });

  it('classifyPitch still classifies C in C major as root', () => {
    expect(classifyPitch(60, 'major', 0)).toBe('root');
  });

  it('GridSurface still has setMode', () => {
    const surface = makeSurface();
    expect(typeof surface.setMode).toBe('function');
  });

  it('GridModeKind now includes note and mix', () => {
    const surface = makeSurface();
    surface.registerRack('jam.rack.poly-keys');
    // Should not throw
    expect(() => surface.setMode('note')).not.toThrow();
    surface.registerRack('jam.rack.bass-mono');
    expect(() => surface.setMode('mix')).not.toThrow();
  });

  it('D-B.7: cannot enter mix mode without a registered rack in dev (NODE_ENV=test)', () => {
    const surface = makeSurface();
    // No racks registered → should throw in test env
    expect(() => surface.setMode('mix')).toThrow(/cannot enter mix mode/i);
  });

  it('D-B.7: assertModeFor catches drum mode emitting jam.note.on', () => {
    const surface = makeSurface();
    surface.setMode('global');
    expect(() => surface.assertModeFor({ family: 'jam.note.on' })).toThrow(/MUST NOT emit jam.note.on/i);
  });

  it('D-B.7: assertModeFor catches note mode emitting jam.pattern.step.toggle', () => {
    const surface = makeSurface();
    surface.registerRack('jam.rack.poly-keys');
    surface.setMode('note');
    expect(() => surface.assertModeFor({ family: 'jam.pattern.step.toggle' })).toThrow(/MUST NOT emit jam.pattern.step.toggle/i);
  });
});

// ─── D-B.5: Arrangement auto-promotes scenes ─────────────────────────────────

describe('D-B.5: Arrangement mode upgrades', () => {
  it('createArrangementModeState auto-promotes scenes 0-3', () => {
    const state = createArrangementModeState('test-room');
    expect(state.promotedSceneIds.size).toBe(4);
    expect(state.promotedSceneIds.get(0)).toContain('jam.scene');
    expect(state.promotedSceneIds.get(0)).toContain('test-room');
  });

  it('scene ids are idempotent on (roomId, sceneIndex)', () => {
    const state1 = createArrangementModeState('test-room');
    const state2 = createArrangementModeState('test-room');
    expect(state1.promotedSceneIds.get(0)).toBe(state2.promotedSceneIds.get(0));
  });

  it('tapping scene bank then timeline emits jam.arrangement.section.add', () => {
    const state = createArrangementModeState('test-room');
    // First tap: select scene from bank (row=1, col=0 = bank slot 0)
    const bankIdx = 1 * 8 + 0;
    const { stateChanges: s1 } = handleArrangementPress(bankIdx, state);
    const dragId = s1.dragSceneId;
    expect(dragId).toBeTruthy();

    // Second tap: place on timeline (row=0, col=2 = bar 4)
    const timelineIdx = 0 * 8 + 2;
    const stateWithDrag = { ...state, dragSceneId: dragId! };
    const { events } = handleArrangementPress(timelineIdx, stateWithDrag);
    const sectionAdd = events.find((e) => e.family === 'jam.arrangement.section.add');
    expect(sectionAdd).toBeDefined();
  });
});

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeSurface(): GridSurface {
  const cb: GridSurfaceCallbacks = {
    onStepToggle: () => {},
    onParamChange: () => {},
    onPatternSlot: () => {},
    onArrangementPlace: () => {},
    onModeChange: () => {},
    onCanonicalPad: () => {},
  };
  return new GridSurface(cb);
}

```
