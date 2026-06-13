---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/components/StageTrail.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.068912+00:00
---

# apps/loom-svelte/src/components/StageTrail.svelte

```svelte
<script lang="ts">
  // Helm v7 — horizontal stage trail for the job FSM.
  // Compact mode (default): 5px dots, no labels — for table rows.
  // Full mode: 8px dots with labels below — for detail views.

  const STAGES = ['lead','quoted','scheduled','in_progress','completed','invoiced','paid'] as const;
  const LABELS = ['lead','quote','sched','on-site','done','invoiced','paid'];

  let { state, compact = false }: { state: string; compact?: boolean } = $props();

  const idx = $derived(STAGES.indexOf(state as typeof STAGES[number]));
</script>

<div class="stage-trail" class:compact class:full={!compact} role="img" aria-label="Job stage: {state}">
  {#each STAGES as stage, i (stage)}
    <div class="stage" class:past={i < idx} class:current={i === idx} class:future={i > idx}>
      <div class="dot"></div>
      {#if !compact}
        <div class="label">{LABELS[i]}</div>
      {/if}
    </div>
    {#if i < STAGES.length - 1}
      <div class="connector" class:lit={i < idx}></div>
    {/if}
  {/each}
</div>

<style>
  .stage-trail {
    display: flex;
    align-items: center;
  }

  /* ── Compact (table row) ── */
  .compact {
    gap: 0;
  }

  .compact .dot {
    width: 5px;
    height: 5px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .compact .connector {
    width: 10px;
    height: 1px;
    flex-shrink: 0;
  }

  /* ── Full (detail view) ── */
  .full {
    gap: 0;
    align-items: flex-start;
  }

  .full .stage {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
  }

  .full .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .full .label {
    font-family: var(--mono);
    font-size: 9px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    white-space: nowrap;
  }

  .full .connector {
    width: 18px;
    height: 1px;
    flex-shrink: 0;
    margin-top: 3px; /* align with dot center */
  }

  /* ── Dot colors ── */
  .past .dot {
    background: rgba(127, 217, 255, 0.35);
  }

  .current .dot {
    background: var(--activation);
    box-shadow: 0 0 4px var(--activation-glow);
  }

  .future .dot {
    background: var(--rule);
    width: 6px;
    height: 6px;
  }

  /* Compensate for smaller future dot so connector stays centered */
  .full .future .dot {
    width: 6px;
    height: 6px;
  }

  /* ── Label colors ── */
  .past .label  { color: rgba(127, 217, 255, 0.5); }
  .current .label { color: var(--activation); }
  .future .label  { color: var(--ink-faint); }

  /* ── Connector colors ── */
  .connector {
    background: var(--rule);
  }

  .connector.lit {
    background: rgba(127, 217, 255, 0.3);
  }
</style>

```
