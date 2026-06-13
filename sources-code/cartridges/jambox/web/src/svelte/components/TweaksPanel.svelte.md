---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/TweaksPanel.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.620386+00:00
---

# cartridges/jambox/web/src/svelte/components/TweaksPanel.svelte

```svelte
<script lang="ts">
  import type { ScaleId, ScalePalette, LabelMode } from '$lib/scale-colour.js';

  interface Tweaks {
    palette: ScalePalette;
    labelMode: LabelMode;
    viewport: string;
    density: string;
    accent: string;
    scaleLock: boolean;
    scaleRemap: boolean;
    showJambox: boolean;
    aesthetic: string;
    anchorVariant: string;
    root: number;
    scale: ScaleId;
  }

  interface Props {
    tweaks: Tweaks;
    onTweak: <K extends keyof Tweaks>(key: K, value: Tweaks[K]) => void;
  }

  let { tweaks, onTweak }: Props = $props();
  let open = $state(false);
</script>

<div class="tweaks-wrap">
  <button class="tweaks-toggle" onclick={() => open = !open} title="Tweaks">
    {open ? '✕' : '⚙'}
  </button>
  {#if open}
    <div class="tweaks-panel">
      <div class="tp-title">Tweaks</div>

      <div class="section">
        <div class="section-title">Colour</div>
        <label class="row">
          Palette
          <select value={tweaks.palette} onchange={(e) => onTweak('palette', (e.target as HTMLSelectElement).value as ScalePalette)}>
            <option value="boomwhacker">Boomwhacker</option>
            <option value="newton">Newton</option>
            <option value="scriabin">Scriabin</option>
            <option value="mono">Mono + pattern</option>
          </select>
        </label>
        <label class="row">
          Labels
          <select value={tweaks.labelMode} onchange={(e) => onTweak('labelMode', (e.target as HTMLSelectElement).value as LabelMode)}>
            <option value="off">Off</option>
            <option value="number">Degree</option>
            <option value="solfege">Solfège</option>
            <option value="note-name">Note name</option>
          </select>
        </label>
        <label class="row toggle">
          Scale lock
          <input type="checkbox" checked={tweaks.scaleLock} onchange={(e) => onTweak('scaleLock', (e.target as HTMLInputElement).checked)} />
        </label>
        <label class="row toggle">
          Scale remap
          <input type="checkbox" checked={tweaks.scaleRemap} onchange={(e) => onTweak('scaleRemap', (e.target as HTMLInputElement).checked)} />
        </label>
      </div>

      <div class="section">
        <div class="section-title">Layout</div>
        <div class="row">
          Viewport
          <div class="radio-group">
            {#each ['desktop','tablet','mobile'] as v}
              <button class:on={tweaks.viewport === v} onclick={() => onTweak('viewport', v)}>{v}</button>
            {/each}
          </div>
        </div>
        <div class="row">
          Density
          <div class="radio-group">
            {#each [['cosy','Cosy'],['standard','Std'],['compact','Tight']] as [v, l]}
              <button class:on={tweaks.density === v} onclick={() => onTweak('density', v)}>{l}</button>
            {/each}
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-title">Aesthetic</div>
        <label class="row">
          Preset
          <select value={tweaks.aesthetic} onchange={(e) => onTweak('aesthetic', (e.target as HTMLSelectElement).value)}>
            <option value="current">Studio (default)</option>
            <option value="hardware">Hardware</option>
            <option value="studio-warm">Studio-warm</option>
            <option value="playful">Playful</option>
          </select>
        </label>
        <div class="row">
          Accent
          <div class="radio-group">
            {#each [['amber','Am'],['cyan','Cy'],['magenta','Mg'],['lime','Li']] as [v, l]}
              <button class:on={tweaks.accent === v} onclick={() => onTweak('accent', v)}>{l}</button>
            {/each}
          </div>
        </div>
        <label class="row">
          Anchor
          <select value={tweaks.anchorVariant} onchange={(e) => onTweak('anchorVariant', (e.target as HTMLSelectElement).value)}>
            <option value="orb">Loop orb</option>
            <option value="dial">Bar/beat dial</option>
            <option value="wave">Live waveform</option>
          </select>
        </label>
        <label class="row toggle">
          3D jambox
          <input type="checkbox" checked={tweaks.showJambox} onchange={(e) => onTweak('showJambox', (e.target as HTMLInputElement).checked)} />
        </label>
      </div>
    </div>
  {/if}
</div>

<style>
  .tweaks-wrap {
    position: fixed; bottom: 24px; right: 24px; z-index: 50;
    display: flex; flex-direction: column; align-items: flex-end; gap: 8px;
  }
  .tweaks-toggle {
    width: 40px; height: 40px; border-radius: 50%;
    background: var(--ink-3); border: 1px solid var(--line);
    font-size: 16px; display: grid; place-items: center;
    transition: all 120ms;
  }
  .tweaks-toggle:hover { border-color: var(--accent); color: var(--accent-bright); }
  .tweaks-panel {
    background: var(--ink-2); border: 1px solid var(--line);
    border-radius: 12px; padding: 16px;
    width: 260px; max-height: 80vh; overflow-y: auto;
    box-shadow: 0 20px 60px rgba(0,0,0,0.5);
  }
  .tp-title {
    font-family: var(--f-mono); font-size: 10px;
    letter-spacing: 0.2em; text-transform: uppercase;
    color: var(--muted); margin-bottom: 12px;
  }
  .section { margin-bottom: 16px; }
  .section-title {
    font-family: var(--f-mono); font-size: 9px;
    letter-spacing: 0.18em; text-transform: uppercase;
    color: var(--muted-2); margin-bottom: 8px;
    padding-bottom: 4px; border-bottom: 1px solid var(--line);
  }
  .row {
    display: flex; align-items: center; justify-content: space-between;
    gap: 8px; margin-bottom: 6px;
    font-family: var(--f-mono); font-size: 11px; color: var(--paper-2);
  }
  .row.toggle { justify-content: space-between; }
  select {
    background: var(--ink-3); color: var(--paper-2);
    border: 1px solid var(--line); border-radius: 4px;
    padding: 3px 6px; font-family: var(--f-mono); font-size: 10px;
  }
  .radio-group { display: flex; gap: 3px; }
  .radio-group button {
    padding: 3px 7px; border-radius: 4px;
    background: var(--ink-3); border: 1px solid var(--line);
    font-family: var(--f-mono); font-size: 10px; color: var(--muted);
  }
  .radio-group button.on { background: var(--accent); color: var(--ink-0); border-color: var(--accent); }
  input[type="checkbox"] { accent-color: var(--accent); width: 14px; height: 14px; }
</style>

```
