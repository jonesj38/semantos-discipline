---
slug: helm-canonical-surface
track: C9 — Helm + Surfacing Modes
status: DESIGN — gates the helm AppBar + cartridge-switcher + verb-shelf + hat-scope implementation work
date: 2026-05-29
related:
  - docs/design/HELM-ATTENTION-SURFACE.md (Phase 39A attention engine; canonical right-panel feed)
  - docs/design/WALLET-VOICE-SHELL-GRAMMAR.md (do | find | talk verb canon)
  - docs/canon/canonicalization-matrix.yml C9 (surfacing modes contract)
  - docs/canon/canonicalization-glossary.md (helm, shell, surfaced vs substrate verbs)
  - apps/semantos/lib/shell/helm_home_screen.dart (current state)
  - apps/semantos/lib/shell/semantos_router.dart (current routes)
  - apps/semantos/lib/shell/hat_switcher.dart (current global-hat anti-pattern)
---

# Helm — Canonical Surface

## 0. Headline

> The helm is the SHELL substrate, not a cartridge view. Cartridges contribute verb-shelf items, attention signals, and hat contexts INTO the helm without becoming it. The current implementation conflates the two — AppBar titled "Self" makes the helm look like the Self cartridge's surface; the apps-icon paging metaphor implies cartridges are alternative "apps" rather than overlapping surfaces; the verb-shelf is hardcoded to one cartridge's verb. This design locks the canonical helm shape — AppBar, cartridge switcher UX, dynamic verb shelf, cartridge-scoped hats, and the four surfacing modes (default / dedicated / passive / priority) from matrix C9.

---

## 1. What the operator currently experiences (the bug)

**On main 2026-05-29 after C3 PR sequence (PWA at `app.semantos.me`):**

| Surface | Observed | Why it's wrong |
|---|---|---|
| Helm home (`/`) AppBar title | `"Self"` (hardcoded default in HelmHomeScreen) | Makes the helm look like the Self cartridge's surface. The helm IS the shell. |
| Top-right of AppBar | `"oddjobz · admin"` regardless of active cartridge | Global `ActiveHatNotifier` — last-picked hat sticks across cartridges |
| Top-left of AppBar | 9-square apps icon → routes to `/cartridges` | Paging metaphor; cartridge tap → cartridge's OWN screen (the Self placeholder or the oddjobz lead list). Round-trip is confusing. |
| Floating Action Button | `"Release"` always (binds to `self.practice.release`) | Hardcoded to one cartridge's verb. Switching to oddjobz context doesn't change the FAB. |
| Cartridge index `/cartridges` | Lists Self + oddjobz as tiles | Implies cartridges are siblings of an "app picker" — but they're meant to overlap inside the helm per surfacing-mode design. |

Per Todd 2026-05-29: *"self is supposed to be a cartridge, not the helm... it feels like they're still tightly coupled with oddjobz admin across the top regardless of where you are, and then the back button on the menu that offers you both cartridges actually takes you back to a self release page that then has the 9 tile square rather than a back, indicating it's the root layer?"*

## 2. The four surfacing modes (matrix C9, locked)

Each cartridge declares `ui.surfacingMode` in its `cartridge.json`. The mode tells the helm HOW that cartridge contributes:

| Mode | Behaviour | Examples |
|---|---|---|
| **`default`** | Cartridge contributes verb-shelf items + recent-cells + attention signals INTO the canonical helm. Operator sees ONE helm; cartridge context is a thin overlay (tab indicator + hat). | `self`, `oddjobz` |
| **`dedicated`** | Cartridge replaces the helm with its own UI when active. Helm chrome (AppBar + hat-switcher) stays; body becomes cartridge's. | `jam-room` (a real-time music room needs full-screen UI, not a verb shelf) |
| **`passive`** | Cartridge runs in background. No helm surfacing. REPL-only access (e.g. via Talk modal). | `wallet-headers` (substrate service, not operator-facing) |
| **`priority`** | Cartridge claims always-on-top helm slot. Pre-empts other cartridges' contributions. | (hypothetical) `emergency-comms` |

**`default`** is the common case. `dedicated` is the per-vertical full-screen escape hatch. `passive` is the substrate runner. `priority` is the alarm pattern.

## 3. Canonical helm AppBar shape

```
┌───────────────────────────────────────────────────────────────────┐
│ ☰    Semantos              [self] oddjobz                  ◉ Todd │ ← AppBar
│                                                                   │
│   ┌─ Cartridge tab strip ─────────────────────────────────────┐  │
│   │  [self]    oddjobz    +                                   │  │ ← optional
│   └────────────────────────────────────────────────────────────┘  │
│                                                                   │
│                    [body: ranked attention feed]                  │
│                                                                   │
│                                                                   │
│                                            ┌────────────────┐    │
│                                            │ Release        │    │ ← verb-shelf FAB
│                                            │ + (more verbs) │    │   (active cartridge)
│                                            └────────────────┘    │
└───────────────────────────────────────────────────────────────────┘
```

Per surface:

| Element | Source |
|---|---|
| `☰` (drawer) | Reserved — future operator settings / cartridge install flow |
| `Semantos` title | **Shell-level brand** — NEVER changes per cartridge |
| `[self] oddjobz` segmented (or tab strip below) | Active cartridge highlighted; tap to switch active context. Replaces the 9-square apps icon. |
| `◉ Todd` (avatar + hat) | Hat-switcher — scoped to active cartridge per §6 |
| Body | Cartridge-contributed cells, ranked by AttentionEngine (per HELM-ATTENTION-SURFACE.md) |
| FAB (verb shelf) | Active cartridge's declared verb shelf (per `ui.verbShelf`); typically 1 primary + secondary verbs in CSD L3 |

**Cardinal rule**: AppBar title NEVER says a cartridge name. The shell is the shell. Cartridge context appears as a SECONDARY indicator (tab strip, hat label) — never as the primary identity.

## 4. Cartridge switcher UX — tab strip, not apps grid

**Reject**: the 9-square apps-icon → `/cartridges` index → cartridge-tile-picker → cartridge-screen flow. Paging metaphor. Implies cartridges are alternative apps you "launch into."

**Adopt**: a horizontal cartridge tab strip directly below the AppBar (or as a segmented control IN the AppBar for ≤3 cartridges). Active cartridge highlighted. Tap switches active context WITHOUT navigating away from the helm — the same body, just re-scored for the new active cartridge's verb-shelf + attention signals.

Implementation:

```dart
// At the top of HelmHomeScreen, below the AppBar:
CartridgeTabStrip(
  active: activeCartridge,
  cartridges: registry.entries.where((c) => c.surfacingMode == 'default'),
  onSelect: (cartridge) {
    activeCartridge.value = cartridge;
    // Hat resets to cartridge's default per §6 protocol
    activeHat.value = cartridge.defaultHat;
  },
)
```

The cartridge index `/cartridges` route stays REACHABLE (via the drawer or a "+" affordance for the install / add-cartridge flow) but is NO LONGER the primary navigation.

**Dedicated-mode cartridges** (e.g. `jam-room`) appear in the same tab strip but tapping them REPLACES the helm body with the cartridge's own surface, while the AppBar + tab strip stay. Operator can always tap back to a default-mode cartridge to escape.

## 5. Verb shelf dynamism — cartridge declares its FAB(s)

`cartridge.json` schema gains `ui.verbShelf`:

```json
{
  "ui": {
    "surfacingMode": "default",
    "verbShelf": {
      "primary": {
        "label": "Release",
        "intent": "self.practice.release",
        "icon": "Icons.flash_on"
      },
      "secondary": [
        { "label": "Intention", "intent": "self.practice.intention", "icon": "Icons.flag" },
        { "label": "Review", "intent": "self.practice.review",   "icon": "Icons.refresh" }
      ]
    }
  }
}
```

When active cartridge changes:
- `HelmHomeScreen` reads `activeCartridge.verbShelf.primary` → FAB label + intent
- Secondary verbs become a slide-out under the FAB OR a verb-shelf bar above the FAB (CSD 1-3-5-3-1 L3 layer)

For `oddjobz`, the primary verb might be `New Job` (intent `oddjobz.job.create`) with secondary `New Quote`, `Log Visit`, `Send Invoice`.

The FAB tap path is unchanged from today: `IntentDispatcher.dispatch(verb.intent, payload)` → brain mint → recent-mints card. The cartridge owns its intent + payload shape per the existing dispatcher contract.

## 6. Hat-switcher — cartridge-scoped protocol

`cartridge.json` gains `ui.hats` (or extends the existing `hat_roles` field already present in tessera's cartridge.json):

```json
{
  "ui": {
    "hats": [
      { "id": "self.operator", "label": "operator", "default": true },
      { "id": "self.reflection", "label": "in reflection" }
    ]
  }
}
```

For multi-tenant cartridges like oddjobz:

```json
{
  "ui": {
    "hats": [
      { "id": "oddjobz.admin", "label": "admin", "default": true },
      { "id": "oddjobz.contractor", "label": "as contractor" },
      { "id": "oddjobz.customer", "label": "as customer" }
    ]
  }
}
```

`HatRegistry` becomes:

```dart
class HatRegistry {
  /// Hats per cartridge — populated at boot from each manifest's ui.hats.
  final Map<String, List<Hat>> _hatsByCartridge;

  /// Per-cartridge active hat (last-selected for that cartridge).
  final Map<String, Hat> _activeByCartridge;

  Hat activeHat(String cartridgeId) =>
    _activeByCartridge[cartridgeId] ??
    _hatsByCartridge[cartridgeId]!.firstWhere((h) => h.isDefault);

  List<Hat> hatsFor(String cartridgeId) => _hatsByCartridge[cartridgeId] ?? const [];

  void setActive(String cartridgeId, Hat hat) {
    _activeByCartridge[cartridgeId] = hat;
  }
}
```

`HatSwitcher` widget reads `registry.hatsFor(activeCartridge.id)` for the dropdown options and `registry.activeHat(activeCartridge.id)` for the displayed value. Selection persists per-cartridge.

When `activeCartridge` changes, the displayed hat reactively recomputes from `registry.activeHat(newCartridge.id)` — no explicit reset call needed.

## 7. cartridge.json schema additions (consolidated)

```json
{
  "id": "self",
  "name": "Self",
  "ui": {
    "surfacingMode": "default",
    "verbShelf": {
      "primary": { "label": "Release", "intent": "self.practice.release", "icon": "Icons.flash_on" },
      "secondary": [ ... ]
    },
    "hats": [
      { "id": "self.operator", "label": "operator", "default": true },
      ...
    ]
  }
}
```

Validation:
- `surfacingMode` must be one of `default | dedicated | passive | priority`
- `verbShelf.primary` required for `default` mode; optional for `dedicated`/`priority`; n/a for `passive`
- `hats[]` must include exactly one `default: true`
- `hats[].id` must be globally unique (collision check at boot)

The existing `extension_manifest_loader.zig` already has the parsing scaffold (per C5 PR-5a step 1). Adding `ui.surfacingMode + verbShelf + hats` is a structural extension — same shape as `brain.handlers[]` addition.

## 8. PR sequencing

| PR | Effort | What |
|---|---|---|
| **PR-C9-1** | small | **Hat-switcher cartridge-scoping refactor** — `HatRegistry` reshape + `HatSwitcher` widget update + `self` + `oddjobz` cartridge.json gain `ui.hats[]`. Independent of helm-arch redesign; lands immediate visible UX win. |
| **PR-C9-2** | small | **Helm AppBar title** revert to shell brand. `HelmHomeScreen.cartridgeName` removed; title hardcoded `'Semantos'`. Cartridge context surfaces via tab strip (next PR). 1-LOC change + AppBar tweak. |
| **PR-C9-3** | medium | **Cartridge tab strip** in `HelmHomeScreen`. Replaces the 9-square apps-icon → `/cartridges` index path. Active cartridge state lifts into shell-level (`ActiveCartridgeNotifier`). Tap → re-scope hat + verb-shelf reactively. `/cartridges` route remains for explicit add/install flow. |
| **PR-C9-4** | medium | **Dynamic verb shelf** — cartridge.json `ui.verbShelf` declaration + `HelmHomeScreen` reads active cartridge's primary verb → FAB. `oddjobz` gets a real `verbShelf` declaration alongside `self`'s. |
| **PR-C9-5** | small | **Surfacing modes wired** — `extension_manifest_loader.zig` (or PWA-side equivalent) parses `ui.surfacingMode`; helm filters which cartridges appear in tab strip (default + dedicated), which run silent (passive). `jam-room` reactivation may follow as separate PR once dedicated-mode rendering exists. |

PR-C9-1 (hat scoping) runs in PARALLEL with this design doc. Others follow sequentially after the design lands.

## 9. Out of scope (intentional)

- **AttentionEngine integration** — body content (cartridge-contributed cells ranked by AttentionEngine) is the existing canonical helm body. This design doesn't redefine it; HELM-ATTENTION-SURFACE.md covers it.
- **Voice mic capture** — WALLET-VOICE-SHELL-GRAMMAR.md covers the voice path. Mic affordance lives on the helm but the audio → SIR pipeline is its own design.
- **Per-cartridge theming / palette** — cartridge.json could grow `ui.theme.primaryColor` etc.; deferred to a separate aesthetics pass.
- **Operator settings drawer** — the `☰` left-drawer hook is reserved but not designed here.
- **Notification badges on cartridge tabs** — attention signals could surface as red dots on tabs; deferred.
- **Multi-window / split-screen helm** — only relevant if a `priority` cartridge wants to overlay a `default` cartridge; no concrete consumer demands this yet.

## 10. Acceptance criteria for "C9 helm canonical"

- [ ] AppBar title shows `Semantos` (not a cartridge name) on every cartridge context
- [ ] Cartridge tab strip below the AppBar shows all active `default`/`dedicated`-mode cartridges; active is visually highlighted
- [ ] Tapping a cartridge tab swaps active context WITHOUT navigating away from the helm body
- [ ] Hat-switcher dropdown shows ONLY the active cartridge's declared hats
- [ ] Hat selection persists per-cartridge across tab switches
- [ ] FAB label + intent reflect the active cartridge's `ui.verbShelf.primary`
- [ ] Passive-mode cartridges (e.g. wallet-headers) NEVER appear in the tab strip
- [ ] Dedicated-mode cartridges (e.g. jam-room) appear as tabs; tap replaces body but keeps AppBar + tab strip
- [ ] On emulator after PR-C9-1..C9-5 land: testing Self + oddjobz round-trip shows correct hat per cartridge + correct FAB per cartridge + no confusion about "which is the shell"

Done means: operator can't confuse "where am I" — the shell is always above them; cartridges are explicitly contextual within it.
