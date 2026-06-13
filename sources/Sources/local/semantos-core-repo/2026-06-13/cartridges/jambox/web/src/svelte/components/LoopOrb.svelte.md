---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/LoopOrb.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.619202+00:00
---

# cartridges/jambox/web/src/svelte/components/LoopOrb.svelte

```svelte
<script lang="ts">
  interface Props {
    size?: number;
    playing?: boolean;
    bpm?: number;
    beat?: number;
    density?: number[];
    variant?: 'orb' | 'dial' | 'wave';
  }

  let {
    size = 132,
    playing = false,
    bpm = 120,
    beat = 0,
    density = [],
    variant = 'orb',
  }: Props = $props();

  const cx = $derived(size / 2);
  const cy = $derived(size / 2);
  const rOuter = $derived(size / 2 - 4);
  const rTrack = $derived(rOuter - 8);
  const rInner = $derived(rTrack - 12);

  const sweep = $derived((beat / 16) * Math.PI * 2 - Math.PI / 2);
  const headX = $derived(cx + rTrack * Math.cos(sweep));
  const headY = $derived(cy + rTrack * Math.sin(sweep));

  const beatDur = $derived(`${60 / bpm}s`);

  const dots = $derived(
    Array.from({ length: 16 }, (_, i) => {
      const a = (i / 16) * Math.PI * 2 - Math.PI / 2;
      return {
        x: cx + rTrack * Math.cos(a),
        y: cy + rTrack * Math.sin(a),
        on: !!(density[i]),
        i,
      };
    })
  );

  // Wave variant points
  const waveW = $derived(size);
  const waveH = $derived(size / 2.5);
  const wavePts = $derived(
    Array.from({ length: 64 }, (_, i) => {
      const t = i / 64;
      const phase = (beat / 16 + t) * Math.PI * 2;
      const a = (density[Math.floor(t * 16) % 16] || 0.2) * 0.7 + 0.15;
      return `${i * (waveW / 63)},${waveH / 2 + Math.sin(phase * 4) * waveH * 0.4 * a}`;
    }).join(' ')
  );

  // Dial variant
  const beatMarks = $derived(
    [0, 1, 2, 3].map(i => {
      const a = (i / 4) * Math.PI * 2 - Math.PI / 2;
      return {
        x1: cx + (rOuter - 8) * Math.cos(a),
        y1: cy + (rOuter - 8) * Math.sin(a),
        x2: cx + (rOuter - 2) * Math.cos(a),
        y2: cy + (rOuter - 2) * Math.sin(a),
      };
    })
  );
</script>

{#if variant === 'dial'}
  <svg class="loop-orb" width={size} height={size} viewBox="0 0 {size} {size}">
    <circle {cx} {cy} r={rOuter} fill="rgba(0,0,0,0.4)" stroke="var(--line)" />
    {#each beatMarks as m}
      <line x1={m.x1} y1={m.y1} x2={m.x2} y2={m.y2} stroke="var(--paper-2)" stroke-width="1.5" />
    {/each}
    <line x1={cx} y1={cy} x2={headX} y2={headY} stroke="var(--accent-bright)" stroke-width="2" stroke-linecap="round" />
    <circle {cx} {cy} r="4" fill="var(--accent-bright)" />
  </svg>

{:else if variant === 'wave'}
  <svg class="loop-orb" width={waveW} height={waveH} viewBox="0 0 {waveW} {waveH}">
    <polyline points={wavePts} fill="none" stroke="var(--accent-bright)" stroke-width="2" />
  </svg>

{:else}
  <!-- Default: orb -->
  <svg class="loop-orb" width={size} height={size} viewBox="0 0 {size} {size}">
    <defs>
      <radialGradient id="orb-glow">
        <stop offset="0%" stop-color="var(--accent)" stop-opacity="0.5" />
        <stop offset="60%" stop-color="var(--accent)" stop-opacity="0.08" />
        <stop offset="100%" stop-color="var(--accent)" stop-opacity="0" />
      </radialGradient>
    </defs>
    <circle {cx} {cy} r={rOuter} fill="url(#orb-glow)" />
    <circle {cx} {cy} r={rTrack} fill="none" stroke="var(--line)" stroke-width="1" opacity="0.5" />
    {#each dots as d}
      <circle
        cx={d.x} cy={d.y}
        r={d.on ? 2.6 : 1.4}
        fill={d.on ? 'var(--accent-bright)' : 'var(--muted-2)'}
        opacity={d.on ? 0.9 : 0.45}
        class="step-dot"
      />
    {/each}
    {#if playing}
      <circle
        cx={headX} cy={headY} r="5"
        fill="var(--accent-bright)"
        style="filter: drop-shadow(0 0 6px var(--accent))"
      />
    {/if}
    <circle
      {cx} {cy} r={rInner * 0.6}
      fill="none" stroke="var(--accent)" stroke-width="1"
      opacity={playing ? 0.4 : 0.15}
    >
      {#if playing}
        <animate attributeName="r"
          values="{rInner * 0.5};{rInner * 0.85};{rInner * 0.5}"
          dur={beatDur} repeatCount="indefinite" />
        <animate attributeName="opacity"
          values="0.5;0.05;0.5"
          dur={beatDur} repeatCount="indefinite" />
      {/if}
    </circle>
  </svg>
{/if}

<style>
  .loop-orb { display: block; }
  .step-dot { transition: opacity 200ms; }
</style>

```
