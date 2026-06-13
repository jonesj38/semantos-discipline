---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/jam-room/design/CSD-COMPRESSION-GRADIENT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.783747+00:00
---

# CSD Compression Gradient — 1-3-5-3-1 for the Jam Room

**Status**: Draft v0.1 — for design polish
**Audience**: Claude Design / a human designer
**Reads with**: `CSD_QUICK_REFERENCE.md` (repo root), textbook ch. 17b §17b.7

---

## The question

Conscious Stack Design's 1-3-5-3-1 pyramid disciplines a UI into
**1 anchor → 3 active → 5 support → 3 infrastructure → 1 device**.
The Loom (textbook 17b) is renderer-agnostic — same `LoomState`,
different shuttle. So the pyramid should compress gracefully as the
viewport shrinks. How do we wire the jam-room so the same `jam.world`
renders correctly on a phone, a tablet, and a desktop without losing
function and without per-platform branching?

---

## The mapping

A song really is a pyramid. The folk wisdom "song = drums + bass +
lead" is the *middle* layer, not the whole thing.

```
                     L1 — 1 ANCHOR
                     ┌─────────────────────────────┐
                     │   THE LOOP                  │
                     │   (active jam.scene/jam.clip)│
                     │   "what is playing right now"│
                     └─────────────────────────────┘

                     L2 — 3 ACTIVE   (the song's trinity)
            ┌──────────────┬──────────────┬──────────────┐
            │  RHYTHM      │   MELODY     │   BASSLINE   │
            │  drum rack   │  lead/keys   │   bass rack  │
            └──────────────┴──────────────┴──────────────┘

                     L3 — 5 SUPPORT  (reach when needed)
       ┌─────────┬─────────┬─────────┬─────────┬─────────┐
       │ pads /  │ effects │generative│ external│ capture │
       │ samples │ /sends  │(Strudel)│  MIDI / │ /takes  │
       │         │         │  / PD   │ hardware│         │
       └─────────┴─────────┴─────────┴─────────┴─────────┘

                     L4 — 3 INFRASTRUCTURE  (invisible)
            ┌──────────────┬──────────────┬──────────────┐
            │   CLOCK      │   IDENTITY   │ PERSISTENCE  │
            │  BEAMClock   │ hat / contrib│  cell-relay  │
            │              │  /license    │ /CAS/anchor  │
            └──────────────┴──────────────┴──────────────┘

                     L5 — 1 DEVICE
                     ┌─────────────────────────────┐
                     │  THE SURFACE                │
                     │  (8×8 grid / phone / Push / │
                     │   MPK49 / RX2 / touch)      │
                     └─────────────────────────────┘
```

### Why each row passes the Sincerity Filter

- **L1 = the loop**, not the transport. A room without a "thing
  currently playing" has no anchor; the user has nothing to sync to.
  The active scene + clock pulse must always dominate the top band of
  every viewport.
- **L2 = three racks: rhythm + melody + bassline.** Kick + lead + bass
  is how human beings have heard music since drum + voice + thumb-piano.
  The Phase A/MASTER "Jam Rack One" five-track list (drum, bass,
  chord/pad, sample, generative) is creep against this rule — chord/pad
  collapse into melody (or into support if textural); sample and
  generative are L3.
- **L3 = five supports.** Working-memory ceiling. Each support rack
  exposes **3 macros, not 8**. Eight is a per-active-rack budget.
- **L4 = three invariants** (Clock, Identity, Persistence). These are
  the four warp threads from Loom 17b collapsed: TypeSystem +
  Identity + Governance fold into Identity (one row); Time becomes
  Clock; substrate persistence becomes Persistence. The user never
  sees a Loom internals screen; the room holds these silently.
- **L5 = one device.** The literal thing in the user's hands or in
  front of them. In Phase C terms this is `surfaceShape`.

### Vocabulary alignment

The Phase A vocabulary is already shaped right; what's missing is the
*statement* that this is the priority order:

| L | Anchored objects                                                                                          |
| - | --------------------------------------------------------------------------------------------------------- |
| 1 | `jam.clip`, `jam.scene`                                                                                   |
| 2 | `jam.rack` (×3 active)                                                                                    |
| 3 | `jam.rack` (×5 support), `jam.gesture`, `jam.effect`, `jam.send`, `jam.sample-pack`                       |
| 4 | `jam.clock-calibration`, `jam.contribution`, `jam.permission`, `jam.player`, `jam.snapshot`               |
| 5 | `jam.mapping` (a mapping IS the device)                                                                   |

---

## The proposal — `viewportPlan` on `jam.world`

Add a `viewportPlan` field to `JamboxWorldPayload`:

```ts
export interface ViewportPlan {
  /** The pyramid is the same; only what's surfaced changes. */
  surfacedLayers: ('L1' | 'L2' | 'L3' | 'L4')[];
  /** Where each layer renders for this viewport. */
  placements: {
    anchor: 'top-band' | 'hero' | 'sticky-top';
    active: 'left-wall' | 'tab-row' | 'bottom-tab-bar';
    support: 'right-wall' | 'bottom-sheet' | 'overflow-menu';
    infrastructure: 'hover-hud' | 'hidden';
  };
  /** Default racks per L2 slot. */
  activeSlots: { rhythm: string; melody: string; bassline: string };
}
```

Three default plans ship:

```ts
const desktopPlan: ViewportPlan = {
  surfacedLayers: ['L1', 'L2', 'L3', 'L4'],
  placements: {
    anchor: 'top-band',
    active: 'left-wall',
    support: 'right-wall',
    infrastructure: 'hover-hud',
  },
  activeSlots: { rhythm: 'jam.rack.drum-808', melody: 'jam.rack.poly-keys', bassline: 'jam.rack.bass-mono' },
};

const tabletPlan: ViewportPlan = {
  surfacedLayers: ['L1', 'L2', 'L3'],
  placements: {
    anchor: 'top-band',
    active: 'tab-row',
    support: 'bottom-sheet',
    infrastructure: 'hidden',
  },
  activeSlots: { rhythm: 'jam.rack.drum-808', melody: 'jam.rack.poly-keys', bassline: 'jam.rack.bass-mono' },
};

const mobilePlan: ViewportPlan = {
  surfacedLayers: ['L1', 'L2'],
  placements: {
    anchor: 'hero',
    active: 'bottom-tab-bar',
    support: 'overflow-menu',
    infrastructure: 'hidden',
  },
  activeSlots: { rhythm: 'jam.rack.drum-808', melody: 'jam.rack.poly-keys', bassline: 'jam.rack.bass-mono' },
};
```

The renderer picks a plan from viewport size at boot and on resize.
The state itself is invariant; only the projection changes.

---

## The compression gradient

```
                         DESKTOP (full)              TABLET                  MOBILE
                         ───────────────             ──────────              ──────────
L1 ANCHOR        ✓  scene + clock dominant top-band ✓  same                  ✓  hero card
L2 ACTIVE (3)    ✓  three rack pods on left wall    ✓  three tabs            ✓  bottom 3-tab bar
L3 SUPPORT (5)   ✓  inline sheets on right wall     ▾  bottom sheet          ▾  long-press / overflow
L4 INFRA (3)     ▾  invisible (HUD only on hover)   ▾  invisible             ▾  invisible
L5 DEVICE        ─  grid + keys + ext. controllers  ─  touch + ext.          ─  touch + ext.
```

### The peel-from-bottom rule

> **As real estate compresses, peel layers from the bottom up.**
> Mobile shows L1 + L2. Tablet adds L3 (gated). Desktop adds L4
> hover-HUD. L5 is what it is.

Concrete implications:

- **L1 anchor** is non-negotiable on every viewport. The active scene
  + clock pulse is always visible.
- **L2 actives** are the three racks. On mobile they become the bottom
  tab bar — thumb-accessible, three-up. The currently-focused rack
  fills the centre; the loop hero stays pinned at the top.
- **L3 supports** never appear on the mobile home view. Long-press a
  L2 tab or pull from the right edge to reveal the support sheet.
- **L4 infrastructure** has no UI affordance ever, on any viewport.
  Hover-HUD on desktop is the maximum surface area it gets.
- **L5 device** drives the device adapter selection in Phase C; the
  same `jam.mapping` payload describes the surface across viewports.

### Phase E (3D room) is desktop-only

Phase E's three-room is a desktop-only projection. On tablet, the
canvas degrades to a 2D session view (still semantic, no 3D). On
mobile, it disappears entirely — the loop hero takes its place. This
is allowed because the canvas is a **projection**, not a source of
truth.

---

## What this means for the existing PRDs

- **Phase A** — no changes to vocabulary; add `viewportPlan` to
  `JamboxWorldPayload`.
- **Phase B** — the mode row needs revision. See
  [MODE-ROW-REVISION.md](./MODE-ROW-REVISION.md).
- **Phase C** — `surfaceShape: 'phone'` already exists; add a
  `phone-with-controller` variant for the iPhone-via-Flutter path.
- **Phase E** — explicit "desktop only; tablet 2D fallback; mobile
  hidden" rule. Already implied; make it loud.
- **Phase F** — takes / contributions / lineage are L3 (capture is
  L3 #5). The existing transport-Capture-button is correct on desktop;
  on mobile it gates behind the support overflow.
- **Phase G (new)** — see
  [MOBILE-AND-FLUTTER-SHELL.md](./MOBILE-AND-FLUTTER-SHELL.md).

---

## Open questions for design polish

`TODO(design)`:

1. **Mobile L2 tab labels and icons.** Three tabs labelled
   "Rhythm / Melody / Bass" is functionally correct but bland. What
   are the icons / glyphs?
2. **Tablet plan in landscape vs portrait.** Landscape can fit L3 as
   a right-side rail without a sheet. Portrait can't. Do we want
   four plans (desktop / tablet-landscape / tablet-portrait / mobile)?
3. **Anchor visual on mobile.** A "hero card" is hand-wavy. Is it the
   loop orb (Phase E visual language), the scene name + clock dial,
   or both? Probably both, but designed so neither is decoration.
4. **Support sheet ordering.** The five supports are (pads, effects,
   generative, external MIDI, capture). Stable order or
   most-recently-used? CSD says stable for habit formation; defer to
   that unless we have evidence otherwise.
5. **L4 infrastructure surfacing.** The hover-HUD on desktop is one
   concrete surface for L4. Should there be a "diagnostics" gesture on
   mobile (e.g. four-finger tap) that surfaces it? Probably yes, but
   guarded.
6. **What happens when the user has a single rack only?** The L2
   trinity assumes three actives. A boot state with one rack should
   degrade gracefully — show the one rack as L1's voice and the three
   tab slots as "Add rhythm / melody / bassline" prompts.
7. **Multiplayer presence on mobile.** Other players' avatars are L4
   (identity infrastructure) but their *contributions to L1* are
   first-class. How do we surface "Alice just changed the kick pattern"
   without crowding the loop hero?

---

## Coda

The pyramid is not a metaphor; it's a budget. Every UI decision asks:
*does this serve L0 (user cognition) and is it really 1 / 3 / 5 / 3 /
1?* If the answer is soft, delete it. The compression gradient is
just the same budget at different magnifications.
