---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/PadGrid.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.621277+00:00
---

# cartridges/jambox/web/src/svelte/components/PadGrid.svelte

```svelte
<script lang="ts">
  import { onMount } from 'svelte';
  import { colourForPitch, specToCss, isLightHue, SCALE_INTERVALS } from '$lib/scale-colour.js';
  import type { ScalePalette, ScaleId, LabelMode } from '$lib/scale-colour.js';
  import { startAudio, playDrum, playNote } from '../../audio.js';
  import type { DrumKind } from '../../audio.js';

  // ── Keyboard → pad mapping ──────────────────────────────────────────────────
  //
  // Three QWERTY rows map to three pad rows depending on active rack:
  //
  //   Melody / Bass:
  //     Q W E R T Y U I  →  pad row 5  (upper range — melody: C6+, bass: C4+)
  //     A S D F G H J K  →  pad row 6  (mid range  — melody: C5+, bass: C3+)
  //     Z X C V B N M ,  →  pad row 7  (low range  — melody: C4,  bass: C2)
  //
  //   Chord rack:
  //     Q–I  →  quality row 0 (Maj),  columns 0–7
  //     A–K  →  quality row 1 (min),  columns 0–7
  //     Z–,  →  quality row 2 (dom7), columns 0–7
  //
  //   Rhythm: no keyboard pads (step buttons need intentional placement).
  //
  // Multiple keys held simultaneously work independently — true polyphony.

  const KB_Q = ['q','w','e','r','t','y','u','i'];
  const KB_A = ['a','s','d','f','g','h','j','k'];
  const KB_Z = ['z','x','c','v','b','n','m',','];

  function keyToPad(key: string): number {
    const qIdx = KB_Q.indexOf(key);
    const aIdx = KB_A.indexOf(key);
    const zIdx = KB_Z.indexOf(key);

    if (activeRack === 'melody' || activeRack === 'bass') {
      // Q = upper range, A = mid, Z = lowest (visually lower on keyboard = lower pitch)
      if (qIdx >= 0) return 5 * 8 + qIdx;
      if (aIdx >= 0) return 6 * 8 + aIdx;
      if (zIdx >= 0) return 7 * 8 + zIdx;
    } else if (activeRack === 'chord') {
      // Q/A/Z target 3 consecutive quality rows, shifted by chordKbOffset
      if (qIdx >= 0) return (chordKbOffset + 0) * 8 + qIdx;
      if (aIdx >= 0) return (chordKbOffset + 1) * 8 + aIdx;
      if (zIdx >= 0) return (chordKbOffset + 2) * 8 + zIdx;
    }
    return -1;
  }

  // Track which pad indices are currently held by a key (for visual flash)
  let keyHeld = $state<Set<number>>(new Set());

  // Chord rack: which block of 3 quality rows Q/A/Z currently targets.
  // 0 = rows 0-2 (Maj/min/dom7), 1 = rows 1-3, ..., 5 = rows 5-7 (dim/sus2/aug)
  // Use [ / ] to shift.
  let chordKbOffset = $state(0);

  onMount(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLSelectElement) return;
      if (e.repeat) return;

      // [ / ] shift the chord keyboard row offset
      if (activeRack === 'chord') {
        if (e.key === '[') { chordKbOffset = Math.max(0, chordKbOffset - 1); e.preventDefault(); return; }
        if (e.key === ']') { chordKbOffset = Math.min(5, chordKbOffset + 1); e.preventDefault(); return; }
      }

      const idx = keyToPad(e.key.toLowerCase());
      if (idx < 0) return;
      e.preventDefault();
      startAudio();
      pads[idx]?.onClick();
      keyHeld = new Set([...keyHeld, idx]);
    }
    function onKeyUp(e: KeyboardEvent) {
      const idx = keyToPad(e.key.toLowerCase());
      if (idx < 0) return;
      const next = new Set(keyHeld);
      next.delete(idx);
      keyHeld = next;
    }
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    return () => {
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
    };
  });

  function midiToHz(midi: number): number {
    return 440 * Math.pow(2, (midi - 69) / 12);
  }

  type DrumTrack = 'kick' | 'snare' | 'hat' | 'clap' | 'cb' | 'tom' | 'sub' | 'perc';

  const DRUM_LAYOUT: DrumTrack[] = ['kick','snare','hat','clap','cb','tom','sub','perc'];
  const DRUM_TONES = [30,56,190,132,282,228,0,330];

  const STARTER_KIT: Record<DrumTrack, number[]> = {
    kick:  [1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0],
    snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
    hat:   [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0],
    clap:  [0,0,0,0, 0,0,0,0, 0,0,0,0, 1,0,0,0],
    cb:    [0,0,0,0, 0,0,0,0, 0,0,0,1, 0,0,0,0],
    tom:   Array(16).fill(0),
    sub:   Array(16).fill(0),
    perc:  [0,0,1,0, 0,0,0,1, 0,0,1,0, 0,1,0,0],
  };

  /**
   * Expand a scale's interval array to exactly 8 column offsets by wrapping
   * into the next octave.  For diatonic (7 notes) this gives [0,2,4,5,7,9,11,12]
   * exactly matching the old SCALE_DEGREES constant.  For pentatonic (5 notes)
   * it gives [0,3,5,7,10, 12,15,17] — all in-scale, no locked columns.
   */
  function getColumnOffsets(intervals: number[]): number[] {
    const cols: number[] = [];
    let octave = 0;
    let i = 0;
    while (cols.length < 8) {
      cols.push(octave * 12 + intervals[i % intervals.length]!);
      i++;
      if (i > 0 && i % intervals.length === 0) octave++;
    }
    return cols;
  }

  interface Props {
    activeRack: string;
    modeIdx: Record<string, number>;
    palette: ScalePalette;
    scale: ScaleId;
    root: number;
    labelMode: LabelMode;
    scaleLock: boolean;
    beat: number;
    /**
     * Step page for rhythm mode: 0 = steps 0–7, 1 = steps 8–15.
     * Controlled externally so the parent (App.svelte / StageHead) can show
     * the page indicator and drive the page-flip button.
     */
    stepPage: 0 | 1;
    setStepPage: (p: 0 | 1) => void;
    drumState: Record<DrumTrack, number[]>;
    setDrumState: (s: Record<DrumTrack, number[]>) => void;
    melodyOn: Record<string, number>;
    setMelodyOn: (f: (prev: Record<string, number>) => Record<string, number>) => void;
    bassOn: Record<string, number>;
    setBassOn: (f: (prev: Record<string, number>) => Record<string, number>) => void;
    chordOn: Record<string, number>;
    setChordOn: (f: (prev: Record<string, number>) => Record<string, number>) => void;
    /**
     * Overlay state from the intent reducer, used to tint control pads.
     * { latched: string | null }
     */
    overlayLatched?: string | null;
    /**
     * When true, the note/bass grid maps columns to scale degrees instead of
     * chromatic semitones. Each row is one "octave" of scale degrees.
     */
    scaleRemap?: boolean;
    /**
     * Called when a melody or bass note pad is played (keyboard or click).
     * Lets App.svelte broadcast the note to peers via RoomSync.sendNote().
     */
    onNote?: (pitch: number, vel: number, duration: number, mode: 'melody' | 'bass') => void;
    /**
     * Called when a control-strip pad (mute, page-flip, etc.) is tapped.
     * selector follows the 'ctrl.<kind>.<index>' convention used by the
     * intent reducer — e.g. 'ctrl.mute.0', 'ctrl.page.flip'.
     */
    onControlPad?: (selector: string) => void;
  }

  let {
    activeRack, modeIdx, palette, scale, root, labelMode, scaleLock,
    beat, stepPage, setStepPage, drumState, setDrumState,
    melodyOn, setMelodyOn, bassOn, setBassOn,
    overlayLatched = null,
    scaleRemap = false,
    onNote = undefined,
    onControlPad = undefined,
    chordOn = {} as Record<string, number>,
    setChordOn = (_f: (prev: Record<string, number>) => Record<string, number>) => {},
  }: Props = $props();

  // Current sequencer step (0..15) within the 16-step loop
  const cur = $derived(Math.floor(beat) % 16);
  // Whether the active step is on the current page
  const curOnPage = $derived(stepPage === 0 ? cur < 8 : cur >= 8);
  const curCol = $derived(curOnPage ? (cur % 8) : -1);

  export { STARTER_KIT };

  // ── Pad model ───────────────────────────────────────────────────────────────

  interface PadInfo {
    bg: string;
    border: string;
    label?: string;
    dim: boolean;
    locked: boolean;
    lit: boolean;
    /** Sequencer playhead is on this pad this tick. */
    active: boolean;
    isRoot: boolean;
    isModal: boolean;
    light: boolean;
    /** Pad is a control surface (page flip, mute toggle, etc.) not a note/step. */
    isControl: boolean;
    onClick: () => void;
  }

  const pads = $derived<PadInfo[]>(buildPads(activeRack, cur));

  function buildPads(rack: string, curStep: number): PadInfo[] {
    if (rack === 'rhythm') return buildRhythm(curStep);
    if (rack === 'melody') return buildNote(curStep, 'melody', scaleRemap);
    if (rack === 'chord')  return buildChord(curStep);
    return buildBass(curStep);
  }

  // ── Rhythm mode — 8 tracks × 16 steps (page A/B) ──────────────────────────
  //
  // Layout (8×8 visible):
  //   Rows 0–6: drum tracks (7 tracks visible, page-dependent labels)
  //   Row 7:    control strip
  //     cols 0–5: track mutes (latched via intent reducer)
  //     col 6:    page indicator (dim on current page, bright on other)
  //     col 7:    PAGE FLIP — tap to toggle page A/B

  function buildRhythm(curStep: number): PadInfo[] {
    const result: PadInfo[] = [];
    const pageOffset = stepPage * 8; // 0 or 8

    for (let r = 0; r < 7; r++) {
      const trk = DRUM_LAYOUT[r] as DrumTrack;
      const hue = DRUM_TONES[r] as number;
      const tone = `hsl(${hue} 75% 55%)`;
      for (let c = 0; c < 8; c++) {
        const stepIdx = pageOffset + c;
        const on = !!(drumState[trk]?.[stepIdx]);
        const isActive = (stepPage === 0 ? stepIdx : stepIdx) === curStep && curOnPage;
        result.push({
          bg: on ? tone : 'var(--ink-3)',
          border: on ? tone : 'var(--line)',
          label: c === 0 ? trk.toUpperCase() : undefined,
          dim: false, locked: false,
          lit: on,
          active: isActive,
          isRoot: false, isModal: false,
          light: on && [190,132,228,282].includes(hue),
          isControl: false,
          onClick: () => {
            const next = { ...drumState, [trk]: drumState[trk].slice() };
            next[trk][stepIdx] = on ? 0 : 1;
            setDrumState(next);
            if (!on) { startAudio(); playDrum(trk as DrumKind, 0.9); }
          },
        });
      }
    }

    // ── Row 7: control strip ─────────────────────────────────────────────────
    const mutedColor = overlayLatched === 'mute' ? 'var(--brass-bright)' : 'var(--muted-2)';
    for (let c = 0; c < 6; c++) {
      const trk = DRUM_LAYOUT[c] as DrumTrack;
      const hue = DRUM_TONES[c] as number;
      result.push({
        bg: overlayLatched === 'mute' ? `hsl(${hue} 75% 35%)` : 'var(--ink-3)',
        border: mutedColor,
        label: c === 0 ? 'MUTE' : undefined,
        dim: overlayLatched !== 'mute', locked: false, lit: false, active: false,
        isRoot: false, isModal: false, light: false, isControl: true,
        onClick: () => {
          // Route through intent reducer (muteLatchReducer handles 'ctrl.mute.*')
          onControlPad?.(`ctrl.mute.${c}`);
        },
      });
    }
    // col 6: page indicator dots
    result.push({
      bg: 'var(--ink-3)',
      border: 'var(--line)',
      label: stepPage === 0 ? '1–8' : '9–16',
      dim: true, locked: false, lit: false, active: false,
      isRoot: false, isModal: false, light: false, isControl: true,
      onClick: () => {},
    });
    // col 7: page flip button
    result.push({
      bg: 'var(--ink-4)',
      border: 'var(--brass)',
      label: stepPage === 0 ? '▶▶' : '◀◀',
      dim: false, locked: false, lit: false, active: false,
      isRoot: false, isModal: false, light: false, isControl: true,
      onClick: () => setStepPage(stepPage === 0 ? 1 : 0),
    });

    return result;
  }

  // ── Melody / bass — unchanged ───────────────────────────────────────────────

  function buildNote(curStep: number, mode: 'melody' | 'bass', useScaleRemap: boolean = false): PadInfo[] {
    const result: PadInfo[] = [];
    const baseMidi = mode === 'melody' ? 60 : 36;
    const intervals = SCALE_INTERVALS[scale] ?? SCALE_INTERVALS.major;
    // Column offsets: when not using scaleRemap we derive from the actual scale
    // intervals extended to 8 positions (handles pentatonic, hexatonic, etc.).
    const colOffsets = getColumnOffsets(intervals);
    for (let r = 0; r < 8; r++) {
      for (let c = 0; c < 8; c++) {
        let pitch: number;
        if (useScaleRemap) {
          pitch = baseMidi + (7 - r) * 12 + intervals[c % intervals.length]!;
        } else {
          pitch = baseMidi + (7 - r) * 12 + colOffsets[c]!;
        }
        const spec = colourForPitch(pitch, scale, root, palette, labelMode);
        const isCh = spec.cls === 'chromatic';
        // With colOffsets all pitches are in-scale, so isCh will be false and
        // nothing is locked; the flag is kept for the scaleRemap=true branch
        // where chromatic may appear if root shifts the grid.
        const locked = !useScaleRemap && scaleLock && isCh;
        const bg = specToCss(spec);
        const activeOn = mode === 'melody' ? melodyOn : bassOn;
        const isOn = !!activeOn[String(pitch)];
        result.push({
          bg, border: bg, label: spec.label,
          dim: !useScaleRemap && isCh && !locked,
          locked,
          lit: isOn || spec.cls === 'root',
          active: false,
          isRoot: spec.cls === 'root', isModal: spec.cls === 'modal',
          light: isLightHue(spec.hue) && !isCh,
          isControl: false,
          onClick: () => {
            if (locked) return;
            startAudio();
            if (mode === 'melody') {
              playNote(midiToHz(pitch), 0.7, 0.4);
              onNote?.(pitch, 0.7, 0.4, 'melody');
              setMelodyOn(prev => ({ ...prev, [String(pitch)]: Date.now() }));
              setTimeout(() => setMelodyOn(prev => { const n = {...prev}; delete n[String(pitch)]; return n; }), 300);
            } else {
              playNote(midiToHz(pitch), 0.9, 0.32);
              onNote?.(pitch, 0.9, 0.32, 'bass');
              setBassOn(prev => ({ ...prev, [String(pitch)]: Date.now() }));
              setTimeout(() => setBassOn(prev => { const n = {...prev}; delete n[String(pitch)]; return n; }), 240);
            }
          },
        });
      }
    }
    return result;
  }

  function buildBass(curStep: number): PadInfo[] {
    const PERF_LABELS = ['SLIDE','ACCT','PROB','PROB','OCT+','OCT-'];
    const result: PadInfo[] = [];
    for (let r = 0; r < 8; r++) {
      if (r >= 6) {
        const notePads = buildNote(curStep, 'bass', scaleRemap);
        // Keep visual row order = pitch order: higher row index = lower pitch.
        // buildNote: pitch = baseMidi + (7 - noteRow) * 12 + offset
        //   noteRow 6 → (7-6)=1 octave up → 48+ = C3  (top playable row, higher pitch)
        //   noteRow 7 → (7-7)=0 octaves   → 36+ = C2  (bottom row, lower pitch ✓)
        const noteRow = r; // r=6→C3, r=7→C2 — bottom = lowest, as expected
        for (let c = 0; c < 8; c++) result.push(notePads[noteRow * 8 + c]!);
      } else {
        for (let c = 0; c < 8; c++) {
          result.push({
            bg: 'var(--ink-3)', border: 'var(--line)',
            label: c === 0 ? PERF_LABELS[r] : undefined,
            dim: true, locked: false, lit: false, active: false,
            isRoot: false, isModal: false, light: false, isControl: true,
            onClick: () => {},
          });
        }
      }
    }
    return result;
  }

  // ── Chord rack — quality × root launcher ──────────────────────────────────
  //
  // Layout:
  //   Rows 0–6: 7 chord qualities × 8 scale-degree roots
  //     row 0 = maj, 1 = min, 2 = dom7, 3 = maj7, 4 = m7, 5 = dim, 6 = sus2
  //   Row 7:    aug/aug7 quality + 7 save slots (future: chord memory)
  //
  // Tap a pad → play all notes of that chord quality rooted at that scale degree.
  // The played notes are shown as "lit" for 400 ms via chordOn.

  const CHORD_QUALITIES: Array<{
    name: string;
    intervals: number[];
    hue: number;
  }> = [
    { name: 'M',    intervals: [0, 4, 7],       hue: 40  },
    { name: 'm',    intervals: [0, 3, 7],       hue: 220 },
    { name: '7',    intervals: [0, 4, 7, 10],   hue: 30  },
    { name: 'M7',   intervals: [0, 4, 7, 11],   hue: 60  },
    { name: 'm7',   intervals: [0, 3, 7, 10],   hue: 200 },
    { name: 'dim',  intervals: [0, 3, 6],       hue: 280 },
    { name: 'sus2', intervals: [0, 2, 7],       hue: 160 },
    { name: 'aug',  intervals: [0, 4, 8],       hue: 330 },
  ];

  const CHORD_SUSTAIN_MS = 400;

  function buildChord(_curStep: number): PadInfo[] {
    const result: PadInfo[] = [];
    const scaleIntervals = SCALE_INTERVALS[scale] ?? SCALE_INTERVALS.major;
    // 8 column roots = 8 scale degrees starting from root midi
    const baseMidi = 60; // C4

    for (let r = 0; r < 8; r++) {
      const quality = CHORD_QUALITIES[r]!;
      const qualHue = quality.hue;
      const qualColor = `hsl(${qualHue} 65% 52%)`;
      const qualColorLit = `hsl(${qualHue} 75% 58%)`;

      for (let c = 0; c < 8; c++) {
        // Root pitch for this column: scale degree c
        const degreeOffset = scaleIntervals[c % scaleIntervals.length] ?? (c * 2);
        const chordRootMidi = baseMidi + root + degreeOffset;

        // All notes of this chord
        const pitches = quality.intervals.map((iv) => chordRootMidi + iv);
        const key = `chord.${r}.${c}`;
        const isLit = !!chordOn[key];

        // Root note of chord gets the scale-colour treatment; quality label on col 0
        result.push({
          bg: isLit ? qualColorLit : 'var(--ink-3)',
          border: isLit ? qualColorLit : qualColor,
          label: c === 0 ? quality.name : undefined,
          dim: false, locked: false,
          lit: isLit,
          active: false,
          isRoot: c === 0, isModal: false,
          light: [40, 60, 160].includes(qualHue), // lighter text for bright hues
          isControl: false,
          onClick: () => {
            startAudio();
            // Play all chord tones
            for (const pitch of pitches) {
              playNote(midiToHz(pitch), 0.65, 0.45);
            }
            // Light the pad for sustain duration
            setChordOn((prev) => ({ ...prev, [key]: Date.now() }));
            setTimeout(() => {
              setChordOn((prev) => {
                const n = { ...prev };
                delete n[key];
                return n;
              });
            }, CHORD_SUSTAIN_MS);
          },
        });
      }
    }

    return result;
  }
</script>

<div class="pad-frame">
  <div class="pad-grid">
    {#each pads as pad, i}
      {@const padRow = Math.floor(i / 8)}
      {@const inKbRange = activeRack === 'chord' && padRow >= chordKbOffset && padRow <= chordKbOffset + 2}
      {@const kbRowLabel = inKbRange && i % 8 === 0
        ? (['Q','A','Z'] as const)[padRow - chordKbOffset]
        : null}
      <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
      <div
        class="pad"
        class:dim={pad.dim}
        class:locked={pad.locked}
        class:lit={pad.lit}
        class:active={pad.active}
        class:keyheld={keyHeld.has(i)}
        class:kbrow={inKbRange}
        class:root={pad.isRoot}
        class:modal={pad.isModal}
        class:control={pad.isControl}
        style="--pad-bg: {pad.bg}; --pad-border: {pad.border}"
        onclick={pad.onClick}
        ontouchstart={(e) => { e.preventDefault(); pad.onClick(); }}
      >
        {#if pad.label}
          <div class="lbl" class:light={pad.light}>{pad.label}</div>
        {/if}
        {#if kbRowLabel}
          <div class="kb-badge">{kbRowLabel}</div>
        {/if}
      </div>
    {/each}
  </div>

  {#if activeRack === 'chord'}
    <div class="chord-kb-hint">
      <span class="kb-key">[</span> / <span class="kb-key">]</span>
      shift rows · {chordKbOffset + 1}–{chordKbOffset + 3} of 8
    </div>
  {/if}
</div>

<style>
  .pad-frame {
    position: relative;
    display: grid; place-items: center;
    padding: 18px;
  }
  .pad-grid {
    display: grid;
    grid-template-columns: repeat(8, var(--d-pad));
    grid-template-rows: repeat(8, var(--d-pad));
    gap: var(--d-gap);
  }
  .pad {
    position: relative;
    border-radius: 8px;
    background: var(--pad-bg, var(--ink-3));
    border: 1px solid var(--pad-border, var(--line));
    cursor: pointer;
    transition: transform 60ms, filter 80ms;
    overflow: hidden;
    user-select: none;
  }
  .pad:active { transform: scale(0.94); }
  .pad.dim { opacity: 0.32; }
  .pad.locked { opacity: 0.12; cursor: not-allowed; }
  .pad.lit {
    filter: brightness(1.0) saturate(1.1);
    box-shadow: 0 0 0 1px var(--pad-border, var(--accent)),
                0 4px 18px -4px var(--pad-bg);
  }
  /* Chord kb-active rows — subtle brass left-edge glow */
  .pad.kbrow {
    border-color: rgba(212,166,85,0.45);
  }
  .pad.kbrow:first-child {
    border-left-color: var(--brass);
  }

  /* Small key badge on col-0 of each kb-mapped chord row */
  .kb-badge {
    position: absolute; bottom: 3px; right: 4px;
    font-family: var(--f-mono); font-size: 8px; font-weight: 700;
    color: var(--brass-bright); opacity: 0.8;
    pointer-events: none; line-height: 1;
  }

  /* [ ] shift hint below chord grid */
  .chord-kb-hint {
    margin-top: 8px;
    font-family: var(--f-mono); font-size: 9.5px;
    color: var(--muted); text-align: center; letter-spacing: 0.06em;
  }
  .kb-key {
    display: inline-block;
    background: var(--ink-4); border: 1px solid var(--line);
    border-radius: 3px; padding: 1px 4px;
    color: var(--paper-2); font-size: 9px;
  }

  /* Key held — white ring to show which key is down */
  .pad.keyheld {
    transform: scale(0.92);
    filter: brightness(1.25) saturate(1.15);
    box-shadow: 0 0 0 2px rgba(255,255,255,0.6),
                0 4px 16px -4px var(--pad-bg);
    z-index: 2;
    transition: transform 40ms, filter 40ms;
  }
  /* Sequencer playhead — bright flash on the current step */
  .pad.active {
    filter: brightness(1.35) saturate(1.2);
    box-shadow: 0 0 0 2px var(--brass-bright),
                0 0 12px 2px var(--brass-bright);
    z-index: 1;
  }
  .pad.root::after {
    content: ''; position: absolute; inset: 3px;
    border: 2px solid var(--brass-bright);
    border-radius: 6px; pointer-events: none;
  }
  .pad.modal::after {
    content: '◆'; position: absolute; top: 3px; right: 4px;
    font-size: 8px; color: rgba(255,255,255,0.85); pointer-events: none;
  }
  /* Control pads (page flip, mute strip) — subtler base style */
  .pad.control {
    border-radius: 5px;
    opacity: 0.75;
  }
  .pad.control:hover { opacity: 1; }
  .lbl {
    position: absolute; inset: 0;
    display: grid; place-items: center;
    font-family: var(--f-mono); font-size: 11px; font-weight: 600;
    color: rgba(0,0,0,0.55); letter-spacing: 0.04em;
    pointer-events: none;
  }
  .lbl.light { color: rgba(255,255,255,0.85); }
  .pad.lit .lbl { color: rgba(0,0,0,0.7); }
  .pad.control .lbl { font-size: 9px; color: var(--muted); }
</style>

```
