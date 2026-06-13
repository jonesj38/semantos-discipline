---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/HintStrip.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.620096+00:00
---

# cartridges/jambox/web/src/svelte/components/HintStrip.svelte

```svelte
<script lang="ts">
  interface Props {
    connected?: boolean;
    peerCount?: number;
  }
  let { connected = false, peerCount = 0 }: Props = $props();
</script>

<div class="hint-strip">
  <span><kbd>space</kbd> play/stop</span>
  <span><kbd>1</kbd><kbd>2</kbd><kbd>3</kbd> pick rack</span>
  <span><kbd>⌘k</kbd> command palette</span>
  <span><kbd>⌘⇧c</kbd> capture last 4 bars</span>
  {#if peerCount > 0}
    <span class="live-dot">● live · {peerCount} in room</span>
  {:else}
    <span class="offline-dot">● offline</span>
  {/if}
</div>

<style>
  .hint-strip {
    display: flex; gap: 18px; flex-wrap: wrap;
    padding: 10px 14px; margin-top: 14px;
    background: var(--ink-1); border: 1px solid var(--line);
    border-radius: 8px; font-family: var(--f-mono); font-size: 10px;
    color: var(--muted); letter-spacing: 0.06em;
  }
  kbd {
    font-family: var(--f-mono); font-size: 10px;
    padding: 1px 6px; background: var(--ink-3);
    border: 1px solid var(--line); border-radius: 3px; color: var(--paper-2);
  }
  .live-dot { margin-left: auto; color: var(--accent-bright); }
  .offline-dot { margin-left: auto; color: var(--muted-2); }
</style>

```
