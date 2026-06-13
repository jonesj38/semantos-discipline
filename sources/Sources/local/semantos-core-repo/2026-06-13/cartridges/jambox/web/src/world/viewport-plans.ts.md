---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/world/viewport-plans.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.611822+00:00
---

# cartridges/jambox/web/src/world/viewport-plans.ts

```ts
/**
 * Default ViewportPlan constants for the CSD (Conscious Stack) compression gradient.
 *
 * Three plans ship as defaults. The `jam.world` factory auto-selects based on
 * boot viewport width:
 *   - width ≤ 600 px  → mobilePlan
 *   - width 601-1024  → tabletPlan
 *   - width > 1024    → desktopPlan
 *
 * Phase A ships these as contracts so Phase G's renderer can read them.
 * Phase B's mode row and Phase G's Flutter shell both key off these plans.
 *
 * The Conscious Stack mapping:
 *   L1 — 1 ANCHOR       : the loop (active jam.scene/jam.clip)
 *   L2 — 3 ACTIVE        : rhythm + melody + bassline (jam.rack ×3)
 *   L3 — 5 SUPPORT       : pads, effects, generative, external MIDI, capture
 *   L4 — 3 INFRASTRUCTURE: clock, identity, persistence (invisible)
 */

import type { ViewportPlan } from '../semantic/objects';

/**
 * Desktop plan — shows all four layers.
 * Real estate is not a constraint; infrastructure is available via hover-HUD.
 */
export const desktopPlan: ViewportPlan = {
  surfacedLayers: ['L1', 'L2', 'L3', 'L4'],
  placements: {
    anchor: 'top-band',
    active: 'left-wall',
    support: 'right-wall',
    infrastructure: 'hover-hud',
  },
  activeSlots: {
    rhythm: 'jam.rack.drum-808',
    melody: 'jam.rack.poly-keys',
    bassline: 'jam.rack.bass-mono',
  },
};

/**
 * Tablet plan — shows L1, L2, L3. Infrastructure is hidden.
 * L3 is gated (shows on demand via bottom-sheet).
 */
export const tabletPlan: ViewportPlan = {
  surfacedLayers: ['L1', 'L2', 'L3'],
  placements: {
    anchor: 'hero',
    active: 'tab-row',
    support: 'bottom-sheet',
    infrastructure: 'hidden',
  },
  activeSlots: {
    rhythm: 'jam.rack.drum-808',
    melody: 'jam.rack.poly-keys',
    bassline: 'jam.rack.bass-mono',
  },
};

/**
 * Mobile plan — shows L1 and L2 only.
 * Maximum compression: anchor card + three L2 buttons visible.
 */
export const mobilePlan: ViewportPlan = {
  surfacedLayers: ['L1', 'L2'],
  placements: {
    anchor: 'sticky-top',
    active: 'bottom-tab-bar',
    support: 'overflow-menu',
    infrastructure: 'hidden',
  },
  activeSlots: {
    rhythm: 'jam.rack.drum-808',
    melody: 'jam.rack.poly-keys',
    bassline: 'jam.rack.bass-mono',
  },
};

/**
 * Auto-select the appropriate viewport plan based on the given width in pixels.
 * Used by createDefaultWorldObject when no explicit plan is provided.
 */
export function selectViewportPlan(widthPx: number): ViewportPlan {
  if (widthPx <= 600) return mobilePlan;
  if (widthPx <= 1024) return tabletPlan;
  return desktopPlan;
}

```
