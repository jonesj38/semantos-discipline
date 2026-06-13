---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/Anchor.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.618897+00:00
---

# cartridges/jambox/web/src/svelte/components/Anchor.svelte

```svelte
<script lang="ts">
  import LoopOrb from './LoopOrb.svelte';

  interface Props {
    playing: boolean;
    bpm: number;
    scene: string;
    beat: number;
    recording: boolean;
    density: number[];
    anchorVariant?: 'orb' | 'dial' | 'wave';
    onTogglePlay: () => void;
    onBpmChange: (v: number) => void;
    onSceneCycle: () => void;
    onToggleRec: () => void;
    onCapture: () => void;
  }

  let {
    playing, bpm, scene, beat, recording, density,
    anchorVariant = 'orb',
    onTogglePlay, onBpmChange, onSceneCycle, onToggleRec, onCapture,
  }: Props = $props();

  const bar  = $derived(Math.floor(beat / 4) + 1);
  const step = $derived((Math.floor(beat) % 4) + 1);
</script>

<div class="anchor">
  <div class="orb-wrap">
    <LoopOrb size={132} {playing} {bpm} {beat} {density} variant={anchorVariant} />
  </div>

  <div class="meta">
    <div class="block">
      <div class="k">scene</div>
      <button class="v scene-btn" onclick={onSceneCycle}>{scene}</button>
    </div>
    <div class="block">
      <div class="k">tempo</div>
      <div class="v mono">
        <input
          type="number" min="40" max="240" value={bpm}
          oninput={(e) => onBpmChange(parseInt((e.target as HTMLInputElement).value) || 120)}
          class="bpm-input"
        />
        <span class="bpm-unit">bpm</span>
      </div>
    </div>
    <div class="block">
      <div class="k">bar · beat</div>
      <div class="v mono bar-beat">{bar}<span class="sep">·</span>{step}</div>
    </div>
  </div>

  <div class="actions">
    <button class="pill primary" onclick={onTogglePlay}>
      <span class="glyph">{playing ? '■' : '▶'}</span>
      {playing ? 'STOP' : 'PLAY'}
    </button>
    <button class="pill rec" class:armed={recording} onclick={onToggleRec}>
      <span class="glyph">●</span>REC
    </button>
    <button class="pill" onclick={onCapture} title="Capture last 4 bars">
      <span class="glyph">⌃</span>CAP
    </button>
  </div>
</div>

<style>
  .anchor {
    display: grid;
    grid-template-columns: auto 1fr auto;
    gap: 24px; align-items: center;
    padding: 14px 18px;
    background: linear-gradient(180deg, var(--ink-2), var(--ink-1));
    border: 1px solid var(--line); border-radius: 14px;
    position: relative; overflow: hidden;
  }
  .anchor::before {
    content: ''; position: absolute; inset: 0;
    background: radial-gradient(ellipse 400px 80px at 50% 100%, rgba(212,166,85,0.08), transparent 70%);
    pointer-events: none;
  }
  .meta { display: flex; align-items: center; gap: 22px; flex: 1; }
  .block { display: flex; flex-direction: column; gap: 2px; }
  .k {
    font-family: var(--f-mono); font-size: 9.5px;
    letter-spacing: 0.16em; text-transform: uppercase; color: var(--muted);
  }
  .v {
    font-family: var(--f-display); font-style: italic;
    font-size: 28px; line-height: 1; color: var(--paper);
  }
  .v.mono {
    font-family: var(--f-mono); font-style: normal;
    font-weight: 500; font-size: 22px;
    display: flex; align-items: baseline; gap: 4px;
  }
  .scene-btn {
    background: none; border: none; padding: 0;
    font: inherit; color: inherit; cursor: pointer;
  }
  .scene-btn:hover { color: var(--accent-bright); }
  .bpm-input {
    background: transparent; border: none; color: inherit;
    font: inherit; width: 2.5em; padding: 0; outline: none;
  }
  .bpm-unit { font-family: var(--f-mono); font-size: 11px; color: var(--muted); }
  .bar-beat { font-size: 22px; }
  .sep { color: var(--muted-2); margin: 0 2px; }
  .actions { display: flex; gap: 8px; align-items: center; }
  .pill {
    padding: 8px 14px; border-radius: 999px;
    background: var(--ink-3); border: 1px solid var(--line);
    color: var(--paper); font-size: 12px; font-weight: 500;
    letter-spacing: 0.02em;
    display: inline-flex; align-items: center; gap: 6px;
    transition: all 120ms;
  }
  .pill:hover { border-color: var(--accent); color: var(--accent-bright); }
  .pill.primary {
    background: linear-gradient(180deg, var(--accent-bright), var(--accent));
    color: var(--ink-0); border-color: var(--accent-bright); font-weight: 600;
  }
  .pill.primary:hover { filter: brightness(1.08); }
  .pill.rec { color: var(--record); border-color: rgba(239,77,106,0.3); }
  .pill.rec:hover { background: rgba(239,77,106,0.1); }
  .pill.rec.armed {
    background: var(--record); color: var(--ink-0); border-color: var(--record);
    animation: pulse-rec 1.6s ease-in-out infinite;
  }
  @keyframes pulse-rec {
    50% { box-shadow: 0 0 0 6px rgba(239,77,106,0.18); }
  }
  .glyph { font-size: 14px; line-height: 1; }
</style>

```
