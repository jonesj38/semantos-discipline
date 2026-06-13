---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/svelte/components/CubePanel.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.431918+00:00
---

# cartridges/chess/web/src/svelte/components/CubePanel.svelte

```svelte
<script lang="ts">
  import type { Color } from '../../chess/types.js';

  interface Props {
    multiplier: number;
    stakeSats: number;
    cubeOwner: Color | null;
    pending: boolean;
    myColor: Color | null;
    canOffer: boolean;
    canAccept: boolean;
    canDecline: boolean;
    onOffer: () => void;
    onAccept: () => void;
    onDecline: () => void;
  }

  let {
    multiplier,
    stakeSats,
    cubeOwner,
    pending,
    canOffer,
    canAccept,
    canDecline,
    onOffer,
    onAccept,
    onDecline,
  }: Props = $props();

  // Six faces of the doubling cube — all show the same multiplier,
  // matching how a real backgammon doubling cube works.
  const FACES = ['front','back','right','left','top','bottom'] as const;

  let totalSats = $derived(stakeSats * multiplier);
</script>

<div class="cube-panel">
  <!-- 3D rotating die -->
  <div class="cube-scene" class:pending={pending}>
    <div class="cube-3d">
      {#each FACES as face}
        <div class="face {face}">
          <span class="mult-label">×{multiplier}</span>
        </div>
      {/each}
    </div>
  </div>

  <!-- Stake info -->
  <div class="cube-info">
    <div class="total-sats">{totalSats.toLocaleString()} sats</div>
    {#if multiplier > 1}
      <div class="stake-detail">{stakeSats.toLocaleString()} × {multiplier}</div>
    {/if}
    <div class="owner-badge"
      class:centred={cubeOwner === null}
      class:white-owned={cubeOwner === 'white'}
      class:black-owned={cubeOwner === 'black'}
    >
      {cubeOwner ?? 'centred'}
    </div>
    {#if pending}
      <div class="pending-notice">⚡ double offered</div>
    {/if}
  </div>

  <!-- Action buttons -->
  <div class="actions">
    {#if canOffer}
      <button class="primary" onclick={onOffer}>Offer Double</button>
    {/if}
    {#if canAccept}
      <button class="primary" onclick={onAccept}>Accept ×{multiplier * 2}</button>
    {/if}
    {#if canDecline}
      <button class="danger" onclick={onDecline}>Decline (forfeit)</button>
    {/if}
  </div>
</div>

<style>
  .cube-panel {
    border: 1px solid #2a2f3a;
    border-radius: 8px;
    background: #14171d;
    padding: 1em 0.9em;
    display: flex;
    flex-direction: column;
    gap: 0.85em;
    align-items: center;
    min-width: 190px;
  }

  /* ── 3D cube ──────────────────────────────────────────────── */

  .cube-scene {
    perspective: 380px;
    width: 96px;
    height: 96px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .cube-3d {
    width: 96px;
    height: 96px;
    position: relative;
    transform-style: preserve-3d;
    animation: spin-cube 12s linear infinite;
  }

  @keyframes spin-cube {
    from { transform: rotateX(22deg) rotateY(0deg); }
    to   { transform: rotateX(22deg) rotateY(360deg); }
  }

  /* Pending: speed up and add a golden glow to the faces */
  .pending .cube-3d {
    animation-duration: 2.5s;
  }

  .face {
    position: absolute;
    width: 96px;
    height: 96px;
    background: #ede4cc;
    border: 3px solid #c8a850;
    border-radius: 6px;
    display: flex;
    align-items: center;
    justify-content: center;
    box-sizing: border-box;
  }

  .pending .face {
    border-color: #f0b428;
    box-shadow: 0 0 10px rgba(240, 180, 40, 0.5);
  }

  .face.front  { transform: translateZ(48px); }
  .face.back   { transform: rotateY(180deg) translateZ(48px); }
  .face.right  { transform: rotateY(90deg)  translateZ(48px); }
  .face.left   { transform: rotateY(-90deg) translateZ(48px); }
  .face.top    { transform: rotateX(90deg)  translateZ(48px); }
  .face.bottom { transform: rotateX(-90deg) translateZ(48px); }

  .mult-label {
    font-size: 24px;
    font-weight: 800;
    color: #1a1100;
    font-variant-numeric: tabular-nums;
    letter-spacing: -0.02em;
    line-height: 1;
    user-select: none;
  }

  /* ── Info section ─────────────────────────────────────────── */

  .cube-info {
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.2em;
  }

  .total-sats {
    font-size: 18px;
    font-weight: 700;
    color: #e8eaed;
    font-variant-numeric: tabular-nums;
    letter-spacing: -0.02em;
  }

  .stake-detail {
    font-size: 11px;
    color: #5a6275;
    font-variant-numeric: tabular-nums;
  }

  .owner-badge {
    font-size: 10px;
    font-family: ui-monospace, monospace;
    padding: 2px 10px;
    border-radius: 4px;
    text-transform: lowercase;
    letter-spacing: 0.05em;
    margin-top: 0.15em;
    border: 1px solid transparent;
  }
  .owner-badge.centred     { background: #1a1d26; color: #505870; border-color: #252a38; }
  .owner-badge.white-owned { background: #2a2710; color: #d4c060; border-color: #3a3418; }
  .owner-badge.black-owned { background: #101824; color: #6aaee8; border-color: #1a2a3a; }

  .pending-notice {
    font-size: 11px;
    font-weight: 600;
    color: #f0b428;
    letter-spacing: 0.05em;
    margin-top: 0.1em;
    animation: pulse-text 1.2s ease-in-out infinite;
  }

  @keyframes pulse-text {
    0%, 100% { opacity: 1; }
    50%       { opacity: 0.45; }
  }

  /* ── Buttons ─────────────────────────────────────────────── */

  .actions {
    display: flex;
    flex-direction: column;
    gap: 0.4em;
    width: 100%;
  }

  button {
    padding: 0.45em 0.7em;
    font: inherit;
    font-size: 0.82rem;
    border-radius: 4px;
    cursor: pointer;
    border: 1px solid #2a2f3a;
    width: 100%;
  }
  button.primary { background: #4f8cff; color: #fff; border-color: #4f8cff; }
  button.danger  { background: #1a1d24; color: #e74c3c; border-color: #3a2020; }
</style>

```
