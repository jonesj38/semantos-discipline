---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/PeerRail.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.618284+00:00
---

# cartridges/jambox/web/src/svelte/components/PeerRail.svelte

```svelte
<script lang="ts">
  interface Peer {
    id: string;
    name: string;
    role: string;
    color: string;
    drift: number;
    rack: string;
  }

  interface Props {
    bpm: number;
    peers?: Peer[];
  }

  const DEFAULT_PEERS: Peer[] = [
    { id:'me',    name:'you',   role:'host',   color:'#d4a655', drift:0,  rack:'rhythm' },
    { id:'alice', name:'alice', role:'guest',  color:'#65d6f5', drift:-8, rack:'melody' },
    { id:'sam',   name:'sam',   role:'guest',  color:'#82e2a8', drift:3,  rack:'bass' },
    { id:'kx',    name:'kx_42', role:'lurker', color:'#c466ff', drift:22, rack:'—' },
  ];

  let { bpm = 120, peers = DEFAULT_PEERS }: Props = $props();

  const periodMs = $derived(60_000 / bpm);

  function driftClass(drift: number): string {
    if (Math.abs(drift) < 5) return 'ok';
    if (Math.abs(drift) < 15) return '';
    return 'warn';
  }
</script>

<div class="peers-rail">
  <div class="ttl">in this room · {peers.length}</div>
  {#each peers as p}
    <div class="peer">
      <div
        class="av"
        style="background: {p.color}; --peer-period: {periodMs + p.drift * 4}ms"
      >
        {p.name[0].toUpperCase()}
      </div>
      <div class="nm">
        {p.name}
        <span class="role">{p.role} · {p.rack}</span>
      </div>
      <div class="drift {driftClass(p.drift)}">
        {p.drift > 0 ? '+' : ''}{p.drift}<span class="ms">ms</span>
      </div>
    </div>
  {/each}
  <div class="sync-drop">
    <span class="sync-label">SYNC DROP</span> in 4 bars ·
    <span class="sync-sub">everyone locks</span>
  </div>
</div>

<style>
  .peers-rail {
    display: flex; flex-direction: column; gap: 8px;
    padding: 14px; background: var(--ink-2);
    border: 1px solid var(--line); border-radius: 12px;
  }
  .ttl {
    font-family: var(--f-mono); font-size: 10px;
    color: var(--muted); letter-spacing: 0.18em; text-transform: uppercase;
  }
  .peer {
    display: grid; grid-template-columns: 28px 1fr auto; gap: 10px;
    align-items: center; padding: 8px 0;
    border-bottom: 1px dashed var(--line);
  }
  .peer:last-of-type { border-bottom: none; }
  .av {
    width: 28px; height: 28px; border-radius: 50%;
    display: grid; place-items: center;
    font-family: var(--f-mono); font-size: 11px; font-weight: 600;
    color: #0e1014; position: relative;
  }
  .av::after {
    content: ''; position: absolute; inset: -3px;
    border-radius: 50%; border: 1.5px solid currentColor;
    opacity: 0.4; animation: peer-pulse var(--peer-period, 500ms) ease-in-out infinite;
  }
  @keyframes peer-pulse {
    0%, 100% { transform: scale(1); opacity: 0.2; }
    50% { transform: scale(1.18); opacity: 0.5; }
  }
  .nm { font-size: 12px; font-weight: 500; }
  .role {
    display: block; font-family: var(--f-mono); font-size: 9px;
    color: var(--muted); letter-spacing: 0.08em; text-transform: uppercase; margin-top: 2px;
  }
  .drift { font-family: var(--f-mono); font-size: 10px; color: var(--muted); }
  .drift.warn { color: var(--warn); }
  .drift.ok { color: var(--live); }
  .ms { color: var(--muted-2); }
  .sync-drop {
    margin-top: 8px; padding: 8px 10px;
    background: var(--ink-3); border-radius: 6px;
    font-family: var(--f-mono); font-size: 10px; color: var(--muted);
    letter-spacing: 0.04em;
  }
  .sync-label { color: var(--accent-bright); }
  .sync-sub { color: var(--paper-2); }
</style>

```
