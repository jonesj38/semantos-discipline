---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/talk/TalkContextStub.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.088745+00:00
---

# apps/loom-svelte/src/views/talk/TalkContextStub.svelte

```svelte
<script lang="ts">
  /**
   * TalkContextStub — placeholder for Talk sub-contexts not yet implemented.
   * Shown for: direct / squad / agent / broadcast.
   */
  let {
    contextId,
    icon,
    label,
    description,
    nextDeliverable,
  }: {
    contextId: string;
    icon: string;
    label: string;
    description: string;
    nextDeliverable?: string;
  } = $props();
</script>

<div class="stub">
  <div class="stub-icon">{icon}</div>
  <div class="stub-label">{label}</div>
  <div class="stub-description">{description}</div>
  {#if nextDeliverable}
    <div class="stub-tag">{nextDeliverable}</div>
  {/if}
</div>

<style>
  .stub {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    gap: 0.5rem;
    padding: 2rem;
    background: #0f172a;
    color: #e2e8f0;
    text-align: center;
  }

  .stub-icon { font-size: 2.5rem; color: #334155; }

  .stub-label {
    font-size: 1rem;
    font-weight: 600;
    color: #94a3b8;
  }

  .stub-description {
    font-size: 0.8125rem;
    color: #475569;
    max-width: 240px;
  }

  .stub-tag {
    margin-top: 0.5rem;
    font-size: 0.6875rem;
    font-family: monospace;
    color: #3b82f6;
    background: rgba(59, 130, 246, 0.1);
    border: 1px solid rgba(59, 130, 246, 0.2);
    border-radius: 999px;
    padding: 0.125rem 0.625rem;
  }
</style>

```
