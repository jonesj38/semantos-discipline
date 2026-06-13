---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/BrandBar.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.621588+00:00
---

# cartridges/jambox/web/src/svelte/components/BrandBar.svelte

```svelte
<script lang="ts">
  interface Props {
    roomId?: string;
    connected?: boolean;
  }
  let { roomId = 'shelf-cantor-fox', connected = false }: Props = $props();
</script>

<div class="brandbar">
  <div class="logo"><b>jam</b><i>·</i>room</div>
  <div class="crumb">
    sovereign-node POC<span class="dot" class:live={connected}>●</span>BEAM region · west-2
  </div>
  <div class="right">
    <div class="room-id">room <span class="room-name">{roomId}</span></div>
  </div>
</div>

<style>
  .brandbar {
    display: flex; align-items: baseline; gap: 14px;
    padding: 0 0 14px;
    border-bottom: 1px solid var(--line);
    margin-bottom: 14px;
  }
  .logo {
    font-family: var(--f-display); font-style: italic;
    font-size: 22px; letter-spacing: -0.01em; color: var(--paper);
  }
  .logo b { font-style: normal; color: var(--accent-bright); font-weight: 400; }
  .crumb {
    font-family: var(--f-mono); font-size: 10px;
    letter-spacing: 0.14em; text-transform: uppercase; color: var(--muted);
  }
  .dot { color: var(--muted-2); margin: 0 6px; }
  .dot.live { color: var(--live); }
  .right { margin-left: auto; display: flex; align-items: center; gap: 12px; }
  .room-id {
    font-family: var(--f-mono); font-size: 11px;
    color: var(--muted); padding: 4px 10px;
    border: 1px solid var(--line); border-radius: 4px;
  }
  .room-name { color: var(--paper); }
</style>

```
