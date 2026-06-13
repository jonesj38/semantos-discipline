---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/SHELL-CARTRIDGE-MODEL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.725546+00:00
---

# Shell ↔ Cartridge Composition Model

**Status:** draft — design locked, implementation pending
**Date:** 2026-05-26
**Author:** Todd Price + Claude (co-design)
**Supersedes:** the flat-tab nav that landed in PR #676/#680
**Anchors:** CSD 1-3-5-3-1 pyramid (docs/prd/jam-room/design/CSD-COMPRESSION-GRADIENT.md); HELM-ATTENTION-SURFACE.md; canon/kernel-composition.md ("Pask is not a recommendation engine"); the `Shell-cartridges-hats + config-as-intents` memory note (user prefs flow as intents → cells, never to a config endpoint)

---

## 1. Problem

The first cut of the semantos shell (PRs #675, #676, #680) put every cartridge's UI into a single flat `NavigationBar`:

> **Talk → Contacts → Self → Home → Do → Find**

This co-mingled three different kinds of cartridge surface into one bar:

- Shell-native primitives (Talk, Contacts) sat next to
- Self-cartridge entry (Self) sat next to
- oddjobz-cartridge entries (Home, Do, Find)

Two consequences fell out:

1. **Cartridges lost their identity.** Self and oddjobz looked like sibling tabs of the same app rather than two separate apps with their own UI. They had no chrome distinguishing one from the other.
2. **Cartridges could not dictate their own UI.** A cartridge like jam-room — which wants an 8×8 grid, a transport bar, and zero of Home/Do/Talk/Find — had nowhere to take over the whole screen. The only contribution surface was a single nav tab.

The CSD 1-3-5-3-1 pyramid was also violated. Pask was given a top-level tab even though it is L4 infrastructure (kernel-composition canon: "not a recommendation engine"). The pyramid's *peel-from-bottom* rule says L4 doesn't appear on mobile. PR #680 closed that specific cut.

This document defines the architecture that fixes the rest.

---

## 2. The model in one paragraph

The **shell** is root identity — sudo for the operator. It owns the cell DAG, all hats, all capabilities, Pask, TalkService, ContactsRepository, FindService, DoActionRegistry, and the cartridge registry. Daily use never happens at the shell level; the shell is only visible via the cartridge switcher and a future admin surface. **Cartridges** are focused contexts. Each cartridge is one app. Most cartridges **inherit** the shell's canonical UI grammar — `Home | Do | Talk | Find` — and contribute only the *contents* of those four slots. Cartridges that don't fit the grammar can **opt out** with a `customSurface` and own the whole body. Cartridges come in four **presentation roles** (foreground / background / latent / companion) so that wallet-headers, ratification cards, and oddjobz can all be "in effect" simultaneously without UI conflict — there is exactly one foreground at a time, but background and latent cartridges layer freely.

---

## 3. The four shell-native primitives

These stay shell-owned. Cartridges *use* them via `ShellDeps`, *contribute* to them, and *choose* whether to surface them as visible tabs.

| Primitive | What it owns |
|-----------|--------------|
| **TalkService** | Conversation graph, NATS-backed thread streams, talk-surface windows. The conversation engine ships with the shell — see the `Streams + conversation are shell-native` memory note. |
| **ContactsRepository** | BRC-52 cert-identified peer book, hat-scoped. The PKI identity layer. |
| **FindService** | Cell-store query layer over the operator's hat-entity data. |
| **DoActionRegistry** | Typed intent dispatcher. Cartridges register `triggerIntents` from their `cartridge.json` flows; the shell routes voice/text intents to the right cartridge handler. |

Whether a cartridge surfaces these as visible tabs is the cartridge's call. The API is always there; the screen slot is at the cartridge's discretion.

---

## 4. The canonical UI grammar

For cartridges that inherit (the common case), the shell provides:

| Slot | What it means | L-level (CSD 1-3-5-3-1) |
|------|---------------|--------------------------|
| **Header** | Cartridge-specific AppBar contents. Long-press cartridge name → switcher. | L1 anchor |
| **Home** | Attention surface for this cartridge — Pask-ranked items that matter now | L2 active |
| **Do** | Actions / creation — start a new thing in this domain | L2 active |
| **Talk** | Conversation, scoped to this cartridge's counterparties | L2 active |
| **Find** | Search within this cartridge's data (cartridge can omit; API still usable) | L3 support |

That's `1 anchor + 3 active + 1 support` for the visible surface. Infrastructure (Pask, talkSurface, contacts plumbing, cell DAG) is L4, invisible. The phone is L5. The pyramid budget closes cleanly with the cartridge itself as the L1 anchor.

### Why Home | Do | Talk | Find

Users learn one navigation pattern that works across all cartridges — the *grammar* stays the same, the *content* changes per cartridge. This is the Slack-workspaces-as-separate-contexts insight inverted: shared vocabulary, isolated content.

- **oddjobz Home** = jobs that need attention today
- **self Home** = today's intention + dimensions in low elevation + due reviews
- **jam-room Home** = (opted out — owns the screen)

Same word, different domain. The operator never has to relearn where things live.

---

## 5. Cartridge presentation roles

Cartridges aren't all the same kind. The shell composes them by role, not by ranking.

```dart
enum ShellPresentation {
  /// Owns the screen when selected.  One visible at a time.
  /// Appears in the cartridge switcher.  Examples: oddjobz, self,
  /// jam-room, welcome.
  foreground,

  /// Always-on infrastructure.  No screen.  No switcher entry.
  /// Many run in parallel.  Examples: wallet-headers, push-registration,
  /// attention-engine, pask-snapshot scheduler.
  background,

  /// Usually invisible.  Interrupts the foreground when a trigger fires
  /// (sheet / route / banner).  Returns control when dismissed.
  /// Examples: wallet-payment, ratification cards, incoming-call screens.
  latent,

  /// Augments a foreground cartridge by contributing widgets to its
  /// declared slot extension points (header.right, do.fab, talk.compose).
  /// Scoped by host cartridge id.  Example: a wallet-balance pill that
  /// lives in oddjobz's header.
  companion,
}
```

### "Which UI wins" resolves trivially by role

| Layer | Rule |
|-------|------|
| Body | Exactly one foreground visible. Long-press Home switches it. |
| HTTP / event spine | All background cartridges' interceptors stacked in declaration order. |
| Interruptions | Latent cartridge → modal route or sheet over the current foreground; foreground stays warm underneath. |
| Slots | Companion widgets injected into the foreground's declared slots, scoped by cartridge id. |

There's no user-facing primacy ranking because the roles encode primacy. The operator never has to choose "which app wins"; the cartridge author declared it when they wrote the manifest.

### Mapping onto what already exists

These roles already exist *implicitly* in the shell — they're just hardcoded in `HomeScreen.initState()` instead of declared in manifests:

| Today (hardcoded) | New (declared) |
|-------------------|----------------|
| `WalletHeaderInterceptor` added to Dio chain in initState | `background` cartridge with an `onActivate(deps)` hook that registers the interceptor |
| `RatificationCardScreen` pushed via `/ratify` route from PushNotificationRouter | `latent` cartridge with a trigger condition + route builder |
| `PushNotificationRouter` registered in main.dart | `background` cartridge with `onActivate(deps)` registering handlers |
| oddjobz nodes (HomeNode/DoNode/FindNode/TalkNode) flat-mapped into the nav | `foreground` cartridge with `defaultNav` filling the four slots |

No new infrastructure is invented — the existing pieces get a coherent place to live.

---

## 6. The cartridge entry contract

```dart
abstract class CartridgeEntry {
  CartridgeDescriptor get descriptor;     // brain-side manifest shape
  IconData get icon;
  String get label;

  /// What kind of cartridge this is.  Determines composition rules.
  ShellPresentation get presentation;

  /// Header content for the AppBar.  Cartridge-specific.
  ///   oddjobz   : calendar + mic + active conversation chip
  ///   self      : today's intention status + elevation gauge + mic
  ///   jam-room  : BPM + transport + project name
  /// null = shell default (cartridge name + long-press handle).
  /// Only meaningful when presentation == foreground.
  Widget Function(BuildContext, ShellDeps)? get headerBuilder;

  /// Exactly one of these is non-null when presentation == foreground:
  CartridgeDefaultNav? get defaultNav;     // inherit Home|Do|Talk|Find
  Widget Function(BuildContext, ShellDeps)? get customSurface;  // takeover

  /// Lifecycle hook fired when the cartridge becomes active.
  /// Background cartridges use this to register interceptors / handlers.
  /// Latent cartridges use this to arm their trigger conditions.
  /// Companion cartridges use this to register their slot contributions
  /// against a host cartridge.
  /// Foreground cartridges may use it to warm caches before first paint.
  Future<void> onActivate(ShellDeps deps) async {}

  /// Companion-only: which foreground host this cartridge augments,
  /// and which slot it fills.  Ignored for non-companion roles.
  CompanionAttachment? get companionAttachment;
}

class CartridgeDefaultNav {
  /// Slot builders.  Each receives ShellDeps so the cartridge can pull
  /// from any shell-native primitive without reaching past the boundary.
  Widget Function(BuildContext, ShellDeps) buildHome;
  Widget Function(BuildContext, ShellDeps) buildDo;

  /// Scope filters applied to shell-native services.  Each cartridge
  /// declares "who counts" for its domain.
  TalkScope talkScope;            // filters TalkSurfaceService threads
  FindScope? findScope;           // null = no Find tab (API still usable)
  ContactsScope contactsScope;    // who is a counterparty here
}

class CompanionAttachment {
  String hostCartridgeId;         // "oddjobz", "self", etc.
  String slot;                    // "header.right", "do.fab", "talk.compose"
  Widget Function(BuildContext, ShellDeps) build;
}
```

### Latent-API surfacing for opted-out cartridges

Jam-room opts out of `defaultNav` → no Find tab visible. But it can still call `deps.findService.search(query, scope: jamScope)` from its own "find a recording" button. The mechanic stays available; the screen slot is the cartridge's choice. Same for Talk and Do — APIs are latent, surfaces are at the cartridge's discretion.

---

## 7. The cartridge switcher

Long-press anywhere on the Home tab → full-screen modal:

```
┌──────────────────────────────┐
│  🔍 Search cartridges…       │
├──────────────────────────────┤
│  ⚡ oddjobz       (last used) │
│  ✨ self                      │
│  🎵 jam-room                  │
│  📊 brem                      │
│  ⚙️  Settings                 │  ← gear at bottom
└──────────────────────────────┘
```

- **Ranking** comes from a new `cartridge_dwell` signal Pask collects (interaction count + recency, same shape as cell scoring).
- **Search** is a substring match over `descriptor.title` + `descriptor.id`.
- **Only foreground cartridges appear.** Background, latent, and companion cartridges aren't switchable — they have no screen to switch to.
- **Settings** is reached from the gear at the bottom.

This is the only place where cartridges are "co-mingled" — and even there they're a ranked list, not a flattened nav.

---

## 8. Cold start

The shell ships with a **welcome** cartridge:
- `presentation: foreground`
- Auto-selected on first launch when no `shell.config.welcomed.v0` cell exists.
- Walks pairing → first hat → default cartridge pick.
- On completion mints `shell.config.welcomed.v0` (linear, consumed once) + `shell.config.default_cartridge.v0` (operator's pick).
- Stays available from settings so the operator can re-run it deliberately.

On subsequent launches, the shell reads the most recent `shell.config.default_cartridge.v0` cell. If the operator pinned a specific cartridge, that wins; otherwise the *last-used* cartridge is opened (also cell-backed, written on every cartridge switch).

---

## 9. Settings as cells

Per the `config-as-intents` canon (memory note: `shell-cartridges-hats + config-as-intents`), shell settings are **cells minted via verb.dispatch**, never writes to a config endpoint. New cell types:

| Cell type | Purpose | Linearity |
|-----------|---------|-----------|
| `shell.config.welcomed.v0` | Marks first-run wizard complete | LINEAR |
| `shell.config.default_cartridge.v0` | Pinned default OR last-used | RELEVANT (latest wins) |
| `shell.config.cartridge_order.v0` | Manual override of Pask ranking (optional) | RELEVANT |
| `shell.config.header_layout.v0` | Per-cartridge header widget config (future WYSIWYG) | RELEVANT |

Shell reads them on boot via cell query (`GET /api/v1/cells?typePath=shell.config.*`). Toggling a setting mints a new settings cell. Consistent with the cell-DAG-as-truth model — no new storage layer, no new API surface.

Settings UI is reached from the gear in the cartridge switcher. It's a thin wrapper that mints settings cells when the operator toggles options.

---

## 10. Contacts as cartridge-scoped query

A global "contacts" tab is the wrong shape. Each cartridge has its own notion of "who is a counterparty":

| Cartridge | contactsScope |
|-----------|---------------|
| oddjobz | `source IN ('oddjobz-customer', 'job-counterparty')` — customers, not friends |
| self | `tag IN ('accountability', 'family', 'mentor')` — your inner-development orbit |
| jam-room | `tag = 'collaborator'` — people on shared sessions |
| social (future) | non-cartridge personal messaging — friends, family that don't fit elsewhere |

The Talk tab inside each cartridge uses its `contactsScope` to populate the "Direct" and "Squad" picker. ContactsRepository stays shell-native (the underlying storage and BRC-52 identity layer); the *query* is per-cartridge.

---

## 11. Composition diagram — runtime

```
                ┌─────────────────────────────────┐
   foreground   │  oddjobz (selected)             │  ← visible body
                │                                 │
                │  ┌─────────────────────────┐    │
                │  │ Header (oddjobz-defined)│    │
                │  │  📅 today · 🎙 mic · 💬 │    │
                │  └─────────────────────────┘    │
                │  ┌─────────────────────────┐    │
                │  │ Home | Do | Talk | Find │    │
                │  └─────────────────────────┘    │
                └─────────────────────────────────┘
                ┌─────────────────────────────────┐
   companion    │  wallet-balance-pill (in slot)  │  ← decorates oddjobz
                └─────────────────────────────────┘

   background   wallet-headers      ← injects X-Brain-Cert on every request
                push-registration   ← maintains FCM/UnifiedPush token
                attention-engine    ← scoring loop
                pask-snapshot       ← periodic save

   latent       wallet-payment      ← armed; fires on Do action requiring sats
                ratification        ← armed; fires on brain-pushed consent
                incoming-call       ← armed; fires on WebRTC SDP arrival
```

All of these are "in effect" simultaneously without conflict because they claim different layers. There is always exactly one foreground; everything else stacks freely.

---

## 12. Migration plan

Three commits, each independently reviewable. The current shell stays functional throughout.

### Commit 1 — Contract

- Introduce `ShellPresentation` enum.
- Introduce `CartridgeDefaultNav`, `CompanionAttachment`, `TalkScope`, `FindScope`, `ContactsScope` types.
- Extend `CartridgeEntry` with `presentation`, `headerBuilder`, `defaultNav`, `customSurface`, `onActivate`, `companionAttachment`.
- Backwards-compatible defaults so the existing flat-nav still renders: any entry missing `presentation` is treated as `foreground` with a `defaultNav` synthesised from the existing `buildTab`.
- No behaviour change.

### Commit 2 — Composition

- `ShellNav` becomes a cartridge-holder (one foreground at a time) + inner nav.
- `oddjobz` becomes a single `CartridgeEntry` (`presentation: foreground`, `defaultNav` filling Home/Do/Talk/Find from its existing nodes).
- `self` becomes a single `CartridgeEntry` (`presentation: foreground`, `defaultNav` filling Home from a new self-attention widget; Do from the practice flow picker; talkScope/contactsScope scoped appropriately).
- `WalletHeaderInterceptor` becomes a `background` cartridge with an `onActivate` that registers the interceptor.
- `RatificationCardScreen` becomes a `latent` cartridge that arms `/ratify` route handling on activate.
- Old top-level `Talk` / `Contacts` / `Pask` tabs removed from the flat nav (they're now inside each cartridge's scope, and Pask stays headless).

### Commit 3 — Switcher, welcome, settings

- Long-press Home → cartridge switcher modal with Pask-ranked list + search + settings gear.
- `welcome` cartridge: `presentation: foreground`, walks first-run pairing flow, mints `shell.config.welcomed.v0` on completion.
- Settings cells (`shell.config.*` schemas) — read path in `ShellNav.initState`, mint path in the settings UI.
- `cartridge_dwell` signal collected by Pask on every cartridge switch.

---

## 13. Out of scope (named gaps)

These are real follow-ups, captured here so they don't drift:

- **WYSIWYG cartridge layout editor.** Operator-driven slot configuration (drag widgets into header/nav slots). Persisted as `shell.config.header_layout.v0` cells. Latent in the contract — the slot model supports it — but no UI yet.
- **Social cartridge.** A built-in `foreground` cartridge for non-cartridge personal messaging (friends/family that don't fit oddjobz/self). For now self holds the "personal" Talk scope.
- **Split-screen / tablet multi-foreground.** On phone there is exactly one foreground. On tablet/desktop, two-foreground side-by-side is a possible future. The contract doesn't preclude it (each foreground is independent).
- **Cartridge marketplace.** Discovery + install of third-party cartridges. Out of shell scope; see `docs/design/CARTRIDGE-MARKETPLACE-OWNERSHIP.md`.
- **Companion contribution conflict resolution.** When two companion cartridges target the same slot on the same host, the shell currently picks first-registered. A future cell-backed `shell.config.companion_priority.v0` could let the operator order them.

---

## 14. What does not change

- The brain's cartridge manifest format (`cartridge.json`) — no schema changes needed for v1. `ShellPresentation` is shell-side metadata; future versions can lift it into the manifest if cross-platform Flutter+web cartridges need to declare it.
- The cell DAG, Pask, NATS event spine, capability model — all untouched. This is a shell composition refactor, not a substrate change.
- Existing cartridges already on rbs (self, oddjobz's brain handlers). The brain doesn't care about UI taxonomy.
- The single-brain-single-shell-many-cartridges deployment shape.

---

## 15. Decisions locked in this design

1. Shell = root identity / sudo. Daily use is in cartridges.
2. Canonical UI grammar = `Home | Do | Talk | Find`, plus cartridge-specific Header.
3. Cartridge presentation taxonomy: `foreground` / `background` / `latent` / `companion`. Exactly one foreground visible.
4. Cartridges inherit the grammar by default; opt out via `customSurface` for full-screen takeover.
5. APIs (Talk, Find, Do, Contacts) are always available via `ShellDeps`; visible surfaces are at the cartridge's discretion.
6. Long-press Home → cartridge switcher, Pask-ranked, searchable.
7. Cold start → `welcome` cartridge; subsequent starts → last-used (cell-backed).
8. Settings stored as cells via verb.dispatch (per `config-as-intents` canon).
9. Contacts is a cartridge-scoped query against the shell-native ContactsRepository, not a global tab.
10. Pask stays headless (per CSD + kernel-composition canon). Its output reaches the operator through ranked attention items in each cartridge's Home and through the cartridge-switcher ranking.

---

*This document is the source of truth for the shell composition model.  Implementation deviations require a design-note amendment here, not silent code drift.*
