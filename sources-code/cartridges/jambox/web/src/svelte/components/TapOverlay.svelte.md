---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/TapOverlay.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.620966+00:00
---

# cartridges/jambox/web/src/svelte/components/TapOverlay.svelte

```svelte
<script lang="ts">
  interface Props {
    onTap: () => void;
  }
  let { onTap }: Props = $props();
  let tapping = $state(false);

  function handle() {
    if (tapping) return;
    tapping = true;
    onTap();
  }
</script>

<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
<div class="tap-overlay" class:go={tapping} onclick={handle}>
  <div class="tap-card">
    <div class="word">tap to <b>start</b></div>
    <div class="breathe">▶</div>
    <div class="sub">loads a groove · drops you in</div>
  </div>
</div>

<style>
  .tap-overlay {
    position: fixed; inset: 0; z-index: 100;
    display: grid; place-items: center;
    background: radial-gradient(ellipse at center, rgba(212,166,85,0.08), var(--ink-0) 60%);
    backdrop-filter: blur(2px);
    cursor: pointer;
    animation: tap-fade-in 400ms ease-out;
  }
  @keyframes tap-fade-in { from { opacity: 0; } to { opacity: 1; } }
  .tap-overlay.go { animation: tap-fade-out 480ms ease-out forwards; }
  @keyframes tap-fade-out { to { opacity: 0; pointer-events: none; } }

  .tap-card {
    text-align: center;
    display: flex; flex-direction: column; align-items: center; gap: 26px;
  }
  .word {
    font-family: var(--f-display); font-style: italic;
    font-size: 96px; line-height: 0.95;
    color: var(--paper); letter-spacing: -0.01em;
  }
  .word b { font-style: normal; font-weight: 400; color: var(--accent-bright); }
  .sub {
    font-family: var(--f-mono); font-size: 11px;
    letter-spacing: 0.24em; text-transform: uppercase;
    color: var(--muted);
  }
  .breathe {
    width: 96px; height: 96px; border-radius: 50%;
    border: 2px solid var(--accent);
    animation: tap-breathe 2s ease-in-out infinite;
    display: grid; place-items: center;
    color: var(--accent-bright); font-size: 28px;
  }
  @keyframes tap-breathe {
    0%, 100% { transform: scale(1); box-shadow: 0 0 0 0 rgba(212,166,85,0.5); }
    50% { transform: scale(1.06); box-shadow: 0 0 0 24px rgba(212,166,85,0); }
  }
</style>

```
