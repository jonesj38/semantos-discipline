---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/RackButtons.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.619489+00:00
---

# cartridges/jambox/web/src/svelte/components/RackButtons.svelte

```svelte
<script lang="ts">
  interface RackDef {
    id: string;
    name: string;
    sub: string;
    tone: string;
    modes: string[];
  }

  interface Props {
    active: string;
    modeIdx: Record<string, number>;
    racksLive: Record<string, number[]>;
    beat: number;
    onSelect: (id: string) => void;
    onSecondary: (id: string) => void;
  }

  const RACK_DEFS: RackDef[] = [
    { id: 'rhythm', name: 'Rhythm', sub: 'Drum · Step',    tone: 'var(--pc-2)',  modes: ['STEP','PARAM'] },
    { id: 'melody', name: 'Melody', sub: 'Note · Mix',     tone: 'var(--pc-7)',  modes: ['NOTE','MIX'] },
    { id: 'bass',   name: 'Bass',   sub: 'Bassline · Mix', tone: 'var(--pc-11)', modes: ['BASS','MIX'] },
    { id: 'chord',  name: 'Chord',  sub: 'Build · Recall', tone: 'var(--pc-4)',  modes: ['PLAY','SEQ'] },
  ];

  let { active, modeIdx, racksLive, beat, onSelect, onSecondary }: Props = $props();

  const cur = $derived(Math.floor(beat) % 16);
</script>

<div class="racks">
  {#each RACK_DEFS as r}
    {@const isActive = active === r.id}
    {@const live = racksLive[r.id] ?? []}
    {@const mi = modeIdx[r.id] ?? 0}
    <button
      class="rack-btn"
      class:active={isActive}
      style="--rack-tone: {r.tone}"
      onclick={() => isActive ? onSecondary(r.id) : onSelect(r.id)}
    >
      <div class="row1">
        <span class="dot"></span>
        <span>{r.id.toUpperCase()}</span>
      </div>
      <div class="name">{r.name}</div>
      <div class="sub">{r.sub}</div>
      <div class="mini">
        {#each { length: 16 } as _, i}
          <div class="step" class:on={!!live[i]} class:cur={i === cur && isActive}></div>
        {/each}
      </div>
      <div class="secondary-mode">
        {r.modes[mi]}
        <span class="dotline">
          {#each r.modes as _, i}
            <span class="d" class:on={mi === i}></span>
          {/each}
        </span>
      </div>
    </button>
  {/each}
</div>

<style>
  .racks {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 12px; margin: 14px 0;
  }
  .rack-btn {
    position: relative; padding: 14px 18px;
    background: var(--ink-2); border: 1px solid var(--line);
    border-radius: 12px; text-align: left;
    display: flex; flex-direction: column; gap: 8px;
    cursor: pointer; transition: all 160ms;
    overflow: hidden; min-height: 88px;
  }
  .rack-btn::before {
    content: ''; position: absolute; inset: 0;
    background: linear-gradient(180deg, transparent, var(--rack-tone, transparent) 200%);
    opacity: 0.18; pointer-events: none;
  }
  .rack-btn:hover { border-color: var(--rack-tone, var(--accent)); transform: translateY(-1px); }
  .rack-btn.active {
    border-color: var(--rack-tone, var(--accent));
    background: linear-gradient(180deg, var(--ink-2), color-mix(in srgb, var(--rack-tone) 12%, var(--ink-2)));
    box-shadow: inset 0 0 0 1px var(--rack-tone, var(--accent)),
                0 8px 30px -12px var(--rack-tone, var(--accent));
  }
  .row1 {
    display: flex; align-items: baseline; gap: 8px;
    font-family: var(--f-mono); font-size: 10px;
    letter-spacing: 0.18em; text-transform: uppercase; color: var(--muted);
  }
  .dot {
    width: 8px; height: 8px; border-radius: 50%;
    background: var(--rack-tone, var(--muted));
    box-shadow: 0 0 0 2px color-mix(in srgb, var(--rack-tone) 25%, transparent);
  }
  .name {
    font-family: var(--f-display); font-style: italic;
    font-size: 30px; line-height: 1; color: var(--paper);
  }
  .sub { font-family: var(--f-mono); font-size: 10.5px; color: var(--muted-2); letter-spacing: 0.04em; }
  .mini { display: flex; gap: 2px; height: 18px; align-items: end; margin-top: 4px; }
  .step {
    flex: 1; background: var(--ink-3); border-radius: 1px;
    height: 30%; transition: height 120ms, background 120ms;
  }
  .step.on { background: var(--rack-tone); height: 100%; }
  .step.cur { background: var(--accent-bright); }
  .secondary-mode {
    position: absolute; top: 10px; right: 12px;
    font-family: var(--f-mono); font-size: 9px;
    color: var(--muted-2); letter-spacing: 0.12em;
    display: flex; align-items: center; gap: 6px;
  }
  .dotline { display: inline-flex; gap: 3px; }
  .d { width: 4px; height: 4px; border-radius: 50%; background: var(--ink-4); }
  .d.on { background: var(--rack-tone); }
</style>

```
