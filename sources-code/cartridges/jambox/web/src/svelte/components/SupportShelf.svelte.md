---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/SupportShelf.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.618590+00:00
---

# cartridges/jambox/web/src/svelte/components/SupportShelf.svelte

```svelte
<script lang="ts">
  type DrumTrack = 'kick' | 'snare' | 'hat' | 'clap' | 'cb' | 'tom' | 'sub' | 'perc';

  const DRUM_LAYOUT: DrumTrack[] = ['kick','snare','hat','clap','cb','tom','sub','perc'];
  const DRUM_TONES = [30,56,190,132,282,228,0,330];

  interface ShelfItem {
    id: string;
    icon: string;
    name: string;
    sub: string;
  }

  const SHELF_ITEMS: ShelfItem[] = [
    { id:'sequencer', icon:'⌗', name:'Sequencer', sub:'full' },
    { id:'mix',       icon:'◧', name:'Mix',       sub:'strips' },
    { id:'session',   icon:'⊞', name:'Session',   sub:'clips' },
    { id:'arrange',   icon:'⊐', name:'Arrange',   sub:'timeline' },
    { id:'custom',    icon:'✦', name:'Custom',    sub:'BYO' },
  ];

  interface Props {
    activeRack: string;
    beat: number;
    stepPage: 0 | 1;
    activeTrack: string;
    setActiveTrack: (t: string) => void;
    drumState: Record<DrumTrack, number[]>;
    setDrumState: (s: Record<DrumTrack, number[]>) => void;
  }

  let { activeRack, beat, stepPage, activeTrack, setActiveTrack, drumState, setDrumState }: Props = $props();

  let open = $state<string | null>('sequencer');
  const cur = $derived(Math.floor(beat) % 16);

  function toggle(id: string) {
    open = open === id ? null : id;
  }
</script>

<div class="shelf">
  <div class="shelf-head">L3 · Support</div>
  {#each SHELF_ITEMS as it}
    <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
    <div class="shelf-item" class:open={open === it.id} onclick={() => toggle(it.id)}>
      <span class="icon">{it.icon}</span>
      <span class="ttl">{it.name}</span>
      <span class="sub">{it.sub}</span>

      {#if open === it.id}
        <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
        <div class="shelf-body" onclick={(e) => e.stopPropagation()}>
          {#if it.id === 'sequencer'}
            <div class="seq-tracks">
              {#each DRUM_LAYOUT as trk, ti}
                {@const hue = DRUM_TONES[ti] as number}
                {@const trkColor = `hsl(${hue} 75% 50%)`}
                {@const isActive = trk === activeTrack}
                <div class="trk-row" class:active-trk={isActive}>
                  <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
                  <div class="trk-name" onclick={() => setActiveTrack(trk)} title="Select {trk}">{trk.toUpperCase().padEnd(4)}</div>
                  <div class="step-row">
                    {#each (drumState[trk] ?? Array(16).fill(0)) as on, i}
                      <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
                      <div
                        class="step"
                        class:on={!!on}
                        class:cur={i === cur}
                        style="--trk-color: {trkColor}"
                        onclick={() => {
                          const steps = (drumState[trk] ?? Array(16).fill(0)).slice();
                          steps[i] = steps[i] ? 0 : 1;
                          setDrumState({ ...drumState, [trk]: steps });
                        }}
                      ></div>
                    {/each}
                  </div>
                </div>
              {/each}
            </div>

            <!-- Velocity editor for activeTrack -->
            <div class="vel-section">
              <div class="vel-label">{activeTrack.toUpperCase()} · velocity</div>
              <div class="vel-row">
                {#each (drumState[activeTrack as DrumTrack] ?? Array(16).fill(0)) as on, i}
                  <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
                  <div
                    class="vel-bar"
                    class:on={!!on}
                    class:cur={i === cur}
                    onclick={() => {
                      const steps = (drumState[activeTrack as DrumTrack] ?? Array(16).fill(0)).slice();
                      steps[i] = steps[i] ? 0 : 1;
                      setDrumState({ ...drumState, [activeTrack]: steps });
                    }}
                  >
                    <div class="vel-fill" style="height: {on ? 100 : 0}%"></div>
                  </div>
                {/each}
              </div>
              <!-- Probability dots (placeholder) -->
              <div class="prob-row">
                {#each Array(16) as _, i}
                  <div class="prob-dot" class:cur={i === cur}></div>
                {/each}
              </div>
            </div>

          {:else if it.id === 'mix'}
            <div class="faders">
              {#each ['kick','snare','hat','clap','lead','bass'] as nm, i}
                <div class="fader">
                  <div class="fader-name">{nm}</div>
                  <div class="fader-track"><div class="fader-fill" style="width: {60 + (i*7)%30}%"></div></div>
                  <div class="fader-val">{60 + (i*7)%30}</div>
                </div>
              {/each}
            </div>
          {:else if it.id === 'session'}
            <div class="session-grid">
              {#each { length: 16 } as _, i}
                <div class="clip" class:active={i === 5}>{i === 5 ? '▶ A' : ''}</div>
              {/each}
            </div>
          {:else if it.id === 'arrange'}
            <div>
              <div class="arrange-row">
                {#each { length: 32 } as _, i}
                  <div
                    class="arrange-block"
                    style="background: {i < 8 ? 'var(--pc-2)' : i < 16 ? 'var(--pc-7)' : i < 24 ? 'var(--pc-11)' : 'var(--ink-3)'}"
                  ></div>
                {/each}
              </div>
              <div class="arrange-label">32 bars · A · B · C · ░</div>
            </div>
          {:else if it.id === 'custom'}
            <div class="custom-body">
              BYO mapping — bind any CC / pad / key to any rack target.
              <span class="learn">+ learn</span>
            </div>
          {/if}
        </div>
      {/if}
    </div>
  {/each}
</div>

<style>
  .shelf { display: flex; flex-direction: column; gap: 8px; position: sticky; top: 14px; }
  .shelf-head {
    font-family: var(--f-mono); font-size: 10px;
    letter-spacing: 0.18em; text-transform: uppercase; color: var(--muted);
    padding: 6px 0;
  }
  .shelf-item {
    position: relative; background: var(--ink-2);
    border: 1px solid var(--line); border-radius: 10px;
    padding: 12px 14px; cursor: pointer;
    display: flex; align-items: center; gap: 10px;
    transition: all 140ms; flex-wrap: wrap;
  }
  .shelf-item:hover { border-color: var(--accent); }
  .shelf-item.open { border-color: var(--accent); padding-bottom: 16px; }
  .icon {
    font-family: var(--f-mono); font-size: 14px;
    color: var(--accent-bright); width: 20px; text-align: center;
  }
  .ttl { font-weight: 500; font-size: 13px; }
  .sub {
    font-family: var(--f-mono); font-size: 9.5px;
    color: var(--muted); letter-spacing: 0.08em; text-transform: uppercase;
    margin-left: auto;
  }
  .shelf-body {
    width: 100%; margin-top: 12px; padding-top: 12px;
    border-top: 1px dashed var(--line);
    font-family: var(--f-mono); font-size: 11px;
    color: var(--paper-2); line-height: 1.5;
  }

  /* Sequencer track grid */
  .seq-tracks { display: flex; flex-direction: column; gap: 3px; }
  .trk-row {
    display: flex; align-items: center; gap: 4px;
    padding: 2px 4px; border-radius: 4px;
    border: 1px solid transparent;
  }
  .trk-row.active-trk {
    border-color: var(--brass, #b8860b);
    background: rgba(184,134,11,0.08);
  }
  .trk-name {
    font-size: 8px; color: var(--muted); min-width: 32px;
    letter-spacing: 0.06em; cursor: pointer; user-select: none;
  }
  .trk-name:hover { color: var(--paper-2); }
  .step-row { display: grid; grid-template-columns: repeat(16, 1fr); gap: 1px; flex: 1; }
  .step {
    height: 10px; border-radius: 1px; background: var(--ink-3);
    cursor: pointer; transition: background 60ms;
  }
  .step.on { background: var(--trk-color, var(--accent)); }
  .step.cur { outline: 1px solid var(--paper); outline-offset: 1px; }

  /* Velocity editor */
  .vel-section { margin-top: 10px; padding-top: 8px; border-top: 1px dashed var(--line); }
  .vel-label { font-size: 8px; color: var(--muted); margin-bottom: 4px; letter-spacing: 0.1em; text-transform: uppercase; }
  .vel-row { display: grid; grid-template-columns: repeat(16, 1fr); gap: 1px; height: 40px; align-items: end; }
  .vel-bar {
    position: relative; height: 100%; cursor: pointer;
    background: var(--ink-3); border-radius: 2px;
    overflow: hidden;
  }
  .vel-bar.cur { outline: 1px solid var(--paper); outline-offset: 1px; }
  .vel-fill {
    position: absolute; bottom: 0; left: 0; right: 0;
    background: var(--accent); border-radius: 2px;
    transition: height 80ms;
  }

  /* Probability dots */
  .prob-row { display: grid; grid-template-columns: repeat(16, 1fr); gap: 1px; margin-top: 3px; }
  .prob-dot {
    height: 4px; border-radius: 50%;
    background: var(--ink-4); opacity: 0.5;
  }
  .prob-dot.cur { background: var(--muted); opacity: 1; }

  .faders { display: grid; gap: 8px; }
  .fader { display: grid; grid-template-columns: 60px 1fr 30px; gap: 8px; align-items: center; }
  .fader-name { font-size: 10px; color: var(--muted); text-transform: uppercase; }
  .fader-track { height: 6px; background: var(--ink-3); border-radius: 3px; position: relative; }
  .fader-fill { position: absolute; left: 0; top: 0; bottom: 0; background: var(--accent); border-radius: 3px; }
  .fader-val { font-size: 10px; color: var(--paper-2); text-align: right; }
  .session-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 4px; }
  .clip {
    aspect-ratio: 1; background: var(--ink-3); border-radius: 4px;
    font-size: 9px; padding: 4px; color: var(--muted); cursor: pointer;
  }
  .clip.active { background: var(--accent); color: var(--ink-0); }
  .arrange-row { display: flex; gap: 1px; margin-bottom: 6px; }
  .arrange-block { flex: 1; height: 24px; opacity: 0.7; border-radius: 1px; }
  .arrange-label { font-size: 9px; color: var(--muted); }
  .custom-body { color: var(--muted); }
  .learn { color: var(--accent-bright); }
</style>

```
