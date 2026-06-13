---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/StageHead.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.620677+00:00
---

# cartridges/jambox/web/src/svelte/components/StageHead.svelte

```svelte
<script lang="ts">
  import type { ScaleId } from '$lib/scale-colour.js';

  const ROOT_NAMES = ['C','C♯','D','D♯','E','F','F♯','G','G♯','A','A♯','B'];
  const SCALES: { id: ScaleId; label: string }[] = [
    { id:'major',            label:'Major' },
    { id:'minor',            label:'Minor' },
    { id:'pentatonic',       label:'Pent maj' },
    { id:'pentatonic-minor', label:'Pent min' },
    { id:'dorian',           label:'Dorian' },
    { id:'phrygian',         label:'Phrygian' },
    { id:'lydian',           label:'Lydian' },
    { id:'mixolydian',       label:'Mixolyd' },
    { id:'locrian',          label:'Locrian' },
    { id:'blues',            label:'Blues' },
  ];
  const BLACK_KEYS = new Set([1,3,6,8,10]);

  interface Props {
    activeRack: string;
    activeMode: string;
    root: number;
    scale: ScaleId;
    scaleLock: boolean;
    scaleRemap: boolean;
    onRootChange: (v: number) => void;
    onScaleChange: (v: ScaleId) => void;
    onScaleRemapToggle: () => void;
  }

  let { activeRack, activeMode, root, scale, scaleLock, scaleRemap, onRootChange, onScaleChange, onScaleRemapToggle }: Props = $props();

  const scaleLabel = $derived((SCALES.find(s => s.id === scale) ?? { label: scale }).label.toUpperCase());
  const lockLabel  = $derived(scaleLock ? `${ROOT_NAMES[root]} ${scaleLabel} · LOCKED` : 'CHROMATIC');
</script>

<div class="stage-head">
  <div class="label">{activeRack} · {activeMode}</div>
  <div class="lock-label">{lockLabel}</div>
  <button
    class="remap-btn"
    class:active={scaleRemap}
    onclick={onScaleRemapToggle}
    title="Toggle scale remap mode"
  >{scaleRemap ? 'SCALE' : 'CHROM'}</button>

  <div class="scale-picker">
    <div class="keys">
      {#each ROOT_NAMES as name, i}
        <button
          class="key"
          class:black={BLACK_KEYS.has(i)}
          class:on={root === i}
          onclick={() => onRootChange(i)}
          title={name}
        >{name}</button>
      {/each}
    </div>
    <select
      value={scale}
      onchange={(e) => onScaleChange((e.target as HTMLSelectElement).value as ScaleId)}
      class="scale-select"
    >
      {#each SCALES as s}
        <option value={s.id}>{s.label}</option>
      {/each}
    </select>
  </div>
</div>

<style>
  .stage-head {
    display: flex; align-items: center; gap: 14px;
    margin-bottom: 16px; flex-wrap: wrap;
  }
  .label {
    font-family: var(--f-mono); font-size: 10px;
    letter-spacing: 0.18em; text-transform: uppercase; color: var(--muted);
  }
  .lock-label {
    font-family: var(--f-mono); font-size: 10px;
    letter-spacing: 0.1em; color: var(--muted);
  }
  .remap-btn {
    padding: 3px 8px;
    border: 1px solid var(--line); border-radius: 4px;
    font-family: var(--f-mono); font-size: 9px; font-weight: 600;
    letter-spacing: 0.08em;
    background: var(--ink-3); color: var(--muted);
    cursor: pointer; transition: all 100ms;
  }
  .remap-btn:hover { border-color: var(--accent); color: var(--paper-2); }
  .remap-btn.active { background: var(--brass, #b8860b); color: var(--ink-0); border-color: var(--brass-bright, #d4a017); }
  .scale-picker {
    margin-left: auto; display: flex; gap: 8px; align-items: center;
  }
  .keys {
    display: flex; gap: 2px; padding: 3px;
    background: var(--ink-3); border-radius: 6px; border: 1px solid var(--line);
  }
  .key {
    padding: 4px 6px; min-width: 22px;
    border: none; border-radius: 3px;
    font-family: var(--f-mono); font-size: 10px; font-weight: 600;
    background: var(--ink-2); color: var(--paper-2); cursor: pointer;
    transition: background 100ms, color 100ms;
  }
  .key.black { background: var(--ink-1); color: var(--muted); }
  .key.on { background: var(--accent); color: var(--ink-0); }
  .scale-select {
    background: var(--ink-3); color: var(--paper-2);
    border: 1px solid var(--line); border-radius: 6px;
    padding: 5px 8px; font-family: var(--f-mono); font-size: 11px;
    letter-spacing: 0.04em; cursor: pointer; outline: none;
  }
</style>

```
