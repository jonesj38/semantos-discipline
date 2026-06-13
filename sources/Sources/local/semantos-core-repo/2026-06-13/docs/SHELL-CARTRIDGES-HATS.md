---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/SHELL-CARTRIDGES-HATS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.335214+00:00
---

# Shell, Cartridges, Hats — The PWA Architecture Model

**Status:** Living document. Captures the architectural model behind the PWA shell, the cartridge apps that drop into it, and the hat-typed tenant contexts that govern visibility. Pairs with the V1 reactor decision D11 (`docs/REACTOR-PORT-TRACKER.md`) and memory `shell_cartridges_hats_model.md`.

---

## 1. The model in one sentence

**The PWA is a shell. Apps are cartridges. Hats are tenant contexts.** The shell stays one binary; the cartridges swap in and out; the hat the user is wearing decides which cartridge surfaces render and which substrate cells are visible.

| Layer | Role | Examples |
|---|---|---|
| **Shell** | One PWA install per device. Hosts cartridges. Manages auth, sync, attention. | `apps/oddjobz-mobile/`, `apps/semantos/` |
| **Cartridge** | Domain app bundled into the shell. Surfaces, FSMs, lexicon contributions. | oddjobz, jamroom, calendar, future verticals |
| **Hat** | A tenant context — one identity, multiple roles. Switches scope, not identity. | `oddjobtodd.info` (tradie), `oddjobtodd.jamroom` (musician) |

Switching hats does not log out and back in. The cert chain (BRC-52) stays; the hat-id changes which cells the substrate reveals and which extensions the shell renders.

---

## 2. Why this model exists

Three problems the shell-cartridges-hats model solves:

### Problem 1: One physical person, multiple roles

A tradie who runs oddjobz also plays in a jam band. They have one phone, one device pairing, one root identity — but the work-side calendar should not bleed into the rehearsal-side calendar; the work-side ledger should not be mixed with the band's gig payouts.

The naive solution is one app per role. The substrate's solution is **one shell, multiple hats**: the user toggles between roles inside the same PWA, and the substrate filters everything (visible cells, accessible sites, attention surfaces) by the active hat.

### Problem 2: Modular vertical onboarding

Adding a new vertical (lender, accountant, property manager) means adding a new cartridge to the shell — not building a new mobile app and resubmitting through app review. The shell ships the framework once; cartridges ship as substrate cells with extension manifests.

### Problem 3: Config that doesn't conflate with code

There are four kinds of "settings", each with its own lifecycle and storage. They can't all live in the same config file or under the same endpoint. The shell-cartridges-hats model maps each category to a distinct mechanism (§4 below).

---

## 3. PWA as shell

The PWA shell (e.g. `apps/oddjobz-mobile/` for Flutter, `apps/semantos/` for the web shell) is **one container** per device. It owns:

- **Pairing flow.** The device-pairing handshake (D-O5p QR-pair) that links this device's cert to the user's root identity.
- **Bearer-token caching.** Bearer tokens for `/api/v1/repl` and `/api/v1/wallet` — eventually superseded by the BRC-52 + capability + Plexus-challenge model (tracker T7).
- **Sync coordination.** Polling / subscription against `/api/v1/events` and pre-tick-drained event queues (per the operator-internal NATS bridge — `runtime/semantos-brain/src/nats_event_bridge.zig`).
- **Attention surface routing.** Which cartridge's current view is rendered.
- **Hat switcher.** Local UI for the user to flip between available hats.

The shell does **not** own:

- **Domain logic.** That's the cartridge's job.
- **Cell types.** Cells are defined by extensions (`extensions/oddjobz/`, `extensions/calendar/`, etc.), not by the shell.
- **Hat issuance.** Hats are derived from BRC-52 certificates; the shell never invents them.
- **Server-side state about which hat is active.** Hat switching is purely client-side (§5).

Per the V1 reactor recovery (memory `brain_reactor_v1_recovery_complete.md`), the shell talks to the brain through five endpoints today: `/api/v1/info`, `/api/v1/attachments/upload`, `/api/v1/attachments/<id>/blob`, `/api/v1/voice-extract`, and `/api/v1/events`. Hat-awareness lives in the request semantics (`hat=` filter on events, `hatId` in intent envelopes), not in additional endpoints.

---

## 4. Apps as cartridges

A cartridge is a packaged combination of:

1. **Extension** — substrate-side cell types, FSMs, lexicon contributions. Lives in `extensions/<name>/`. Example: `extensions/oddjobz/` with its eight canonical cell types per `docs/design/ODDJOBZ-EXTENSION-PLAN.md`.
2. **Shell surface** — the React/Svelte/Flutter components that render the cartridge's UI. Lives alongside the shell or in a sibling app package.
3. **Manifest** — extension metadata declaring what cell types the cartridge owns, which capabilities it requires, which sites it serves. Possibly aligned with **BRC-102** (`deployment-info.json` Specification) per §11.6's Tier-3 reference — audit deferred.

Cartridges are discoverable via `/api/v1/info`, which returns the list of available extensions on the brain. The shell uses this list to render available cartridges; no separate cartridge registry is needed.

### What a cartridge can do

- Mint new cell types (within its declared schema scope)
- Register accept-handlers for `extensions/dispatch/` cross-vertical envelopes
- Contribute lexicon types per its registered `domainFlag` (per `core/plexus-contracts/src/domain-flags.ts` client range)
- Surface its own React/Svelte/Flutter components

### What a cartridge cannot do

- Issue hats (hats are derived from BRC-52 cert chain, not minted by extensions)
- Read other cartridges' AFFINE patches (per chapter 29 cross-vertical dispatch semantics)
- Modify the shell's pairing or sync infrastructure
- Open new HTTP endpoints on the brain without operator approval

This is the substrate/adapter discipline applied to cartridges: cartridges consume substrate primitives; they don't redefine them.

### The clean cartridge contract — five parts

The sharpened model, after the cross-stream synthesis in `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md`. A cartridge is **one thing made of five parts**:

1. **Grammar** — a declarative JSON document conforming to Phase 36A's Extension Grammar JSON Schema (shipped per `docs/prd/PHASE-36A-ERRATA.md` 2026-04-12). Declares source entities, field mappings, object-type declarations, capability requirements, taxonomy coordinates, migration rules. Validated by the Phase 36A validator; semver'd; safe-compute expressions only (regex-gated per the errata's adversarial review).
2. **Walkers** — functions implementing the cartridge's declared verbs. Registered with `runtime/semantos-brain/src/verb_dispatcher.zig` at brain boot. Shape: `(allocator, ctx, params_json) → result_json`. One JSON-RPC method (`verb.dispatch`) routes every verb; new verbs add walkers, not new endpoints.
3. **Cell types** — typed data the cartridge owns, declared in the grammar's object-type section. Each cell has a linearity class (`LINEAR` / `AFFINE` / `RELEVANT` / `DEBUG`; `FUNGIBLE` bridges to RELEVANT per `PHASE-36A-ERRATA.md` §1). Cell typeHash is computed and registered; the kernel verifies linearity at execution time (K1 invariant).
4. **Bindings** — Level-2 consumer-binding objects per the Phase 36 three-tier governance model (`docs/prd/PHASE-36D-EXTENSION-GOVERNANCE-MODEL.md`). Operator-edited credentials, field overrides, version pinning. AFFINE cells scoped to the consumer's node.
5. **(Optional) WASM module** — if the cartridge needs in-host execution beyond what walkers cover, a hash-pinned WASM module loaded by `module_loader.zig`. Host imports brokered through `broker.zig`'s module-isolation policy (deny-by-default, audited per call).

A cartridge consumes substrate services via **four adapter interfaces** (Phase 26, all shipped — see `core/protocol-types/src/`):

- `StorageAdapter` — for persistence
- `IdentityAdapter` — for hat/cert binding
- `AnchorAdapter` — for timestamp-pinning of state hashes
- `NetworkAdapter` — for federation transport

The cartridge ships a `release.config.ts` declaring its name, room, maintainer hat, version, artifacts, and dependencies (other cartridge releases pinned by stateHash). Releases land in the substrate's cell-relay versioning room (`release.<kind>.<name>`).

### Two cartridge homes — same contract, different bundle shape

Per memory `semantos_two_cartridge_kinds.md` and `docs/ADAPTER-TAXONOMY.md` §7a:

- **Operational/FSM cartridges** live in `extensions/<name>/`. TS/Zig libraries, walker registration, cell types, optional REPL commands. Examples: `extensions/oddjobz/` (90 src files, 8 canonical cell types), `extensions/calendar/`, `extensions/dispatch/`, `extensions/scada/`, `extensions/games/` (144 src files).
- **World-app cartridges** live in `apps/world-apps/<name>/`. UI bundle (Svelte / three.js / Flutter / WebAudio) + cell types + release.config.ts, running inside a world region (BEAM-backed). Example: `apps/world-apps/jam-room/` (93 src files, 13 `jam.*` cell kinds, `BEAMClock` NTP sync, BSV PushDrop session anchoring).

Both kinds load through the same dispatcher + verb-dispatcher + module-loader machinery. The contract is identical; only the bundle shape differs.

### Default install bundle (under design)

The Linux-distro analogue requires that **naked brain ships with N first-party "substrate-exposing" cartridges pre-loaded** so a fresh spin-up feels alive without exposing substrate internals as a kitchen sink built into the binary. Candidate bundle for the default install:

- An identity/hat-setup cartridge (substrate-exposing: cert chain bootstrap)
- A peer-pair cartridge (substrate-exposing: NetworkAdapter operator surface)
- A status-dashboard cartridge (substrate-exposing: audit log + loaded modules + peer state)
- A minimal talk cartridge (so two paired brains can chat out of the box)

These are cartridges in the architecture (loadable, removable) but ship with the default install by convention — same shape as Debian shipping bash + ls + cat. The default install bundle is **not currently defined**; see `docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md` §10.3 (D-Distro-default-install).

### Boundaries to maintain

- **Anything user-visible must load as a cartridge.** The moment something user-facing gets compiled into the brain binary, the loader story dies.
- **Cartridges declare capability for every command.** Deny-by-default per `dispatcher.zig` — a handler that fails to declare a capability for one of its commands returns `error.capability_not_declared` and dispatches fail loud.
- **Cartridges consume the four adapter interfaces.** Don't hand-roll storage/identity/anchor/network — fork the substrate seam and you're off-axis.

---

## 5. Hats as tenant contexts

A **hat** is a tenant context — an identity-scoped role the user can wear. The model is "one identity, many roles" rather than "many identities."

### What a hat is

- **A cert chain leaf.** Each hat corresponds to a derived BRC-52 cert under the user's root cert. The hatId is the derived cert id.
- **A tag on requests.** Outgoing requests carry the active hat as metadata (e.g. `?hat=oddjobtodd.info` on `/api/v1/events`, `hatId` field in intent envelopes per `runtime/semantos-brain/src/resources/intent_cells_handler.zig:240`).
- **A visibility filter.** The substrate's policy evaluator filters cells by hatId — AFFINE patches authored by other hats are stripped at query time (per chapter 29).
- **A capability scope.** Each hat carries its own capability domain (per `core/plexus-contracts/src/domain-flags.ts`) — what a tradie hat can do is not what a band-member hat can do, even for the same user.

### What a hat is NOT

- **Not a separate identity.** The root cert is shared across all hats. The hat is a child of the root, not an alternative root.
- **Not a stored "current state."** The brain doesn't track "Todd is currently wearing the tradie hat." Each request carries its own hat tag; the brain serves whichever hat the request asserts.
- **Not a sign-in change.** Switching hats is a client-side toggle, not an auth flow.

### Hat switching is local state

Per memory `shell_cartridges_hats_model.md`:

> Hat switching is local-only client state, not stored brain-side; only the *list* of available hats comes from `/api/v1/info`.

The shell reads the list of available hats from `/api/v1/info`, picks one locally, tags subsequent requests with that hat. The brain validates that the hatId presented in each request matches the chain binding for the certId (per `intent_cells_handler.zig:279-291` — "validate hatId matches the chain binding for certId").

There is no `POST /api/v1/set-current-hat` endpoint. There never will be. Hat is per-request, not per-session.

---

## 6. The four config categories

Settings fall into four categories. Each category lives in a different place and changes through a different mechanism. **Conflating them is the source of most config bugs.**

| Category | Examples | Storage | Endpoint |
|---|---|---|---|
| **Brain-operator** | Port, TLS, data dir, SNI map, federation peers, signing secrets | Operator-controlled config files | `/api/v1/repl` only |
| **Tenant** | Enabled extensions, site routes, theme defaults | Operator-controlled cells | `/api/v1/repl` only (today) |
| **Per-device shell** | Current hat, notification prefs, font size, dark mode | Client-local + (some) cells synced via verb.dispatch | `verb.dispatch` (config-as-intents) |
| **Per-cartridge** | Oddjobz default labor rate; jamroom BPM defaults | Cells | `verb.dispatch` (config-as-intents) |

The first two are operator-side; they require REPL access. The last two are user-side; they flow as **intents**, not as endpoint writes.

---

## 7. Config-as-intents

The load-bearing claim from `docs/REACTOR-PORT-TRACKER.md` D11:

> User-facing per-device + per-cartridge config (theme override, notification prefs, default labor rate, hat preference, etc.) is **NOT** written through `/api/v1/info` — it flows as intents through `verb.dispatch` on the existing `/api/v1/wallet` WSS or `/api/v1/repl`, ratifies as cell records, and syncs across the user's paired devices via the substrate. Same path as job creates and quote edits.

### The dispatch path

```
PWA shell
  │ user toggles "dark mode = on"
  │ (local state mutation; UI updates immediately)
  │
  ▼ also dispatches:
/api/v1/wallet WSS or /api/v1/repl
  │ JSON-RPC: verb.dispatch
  │ method: "set_theme"  (or similar canonical name)
  │ args: { theme: "dark" }
  │ signed by device cert
  │
  ▼
verb_dispatcher.Registry (runtime/semantos-brain/src/verb_dispatcher/)
  │ looks up "set_theme" handler
  │
  ▼
Handler in extension or shell registers:
  - Mutates the shell preference cell
  - Ratifies as a Phase-0x06 intent record
  - Anchors via chain-broadcast
  │
  ▼
Other paired devices subscribed to /api/v1/events?hat=...
  receive the change-event
  apply the same preference locally
```

This is the **same dispatch path as job creates and quote edits.** Settings are not a parallel pipeline; they ride the same intent rails.

### Why this matters

Three properties fall out for free:

1. **Cross-device sync.** Change theme on your phone; the laptop's shell picks it up on the next event tick.
2. **Audit trail.** Every settings change is an intent record with a hatId and a signature. Recoverable.
3. **No write-side `/api/v1/info`.** The endpoint stays GET-only, simplifying its auth model and caching story.

### What's still needed (pending design work)

Per memory `shell_cartridges_hats_model.md`:

> The canonical "config intents" don't exist yet in extension grammars. When wiring per-device + per-cartridge settings in the PWA shell, declare a small set (`set_theme`, `set_notification_pref`, `set_default_labor_rate`, …) routed through `verb.dispatch`. This is design work for the experience packages, not the brain.

This is captured as a sidequest. Today's `verb.dispatch` infrastructure (`runtime/semantos-brain/src/verb_dispatcher/`, `oddjobz_ratify_walker.zig`) is wired for domain intents (job creates, quote edits, voice notes); declaring the *settings* intents is a separate naming sprint.

---

## 8. The `/api/v1/info` contract

Per D11 of `docs/REACTOR-PORT-TRACKER.md` and the post-T8a implementation in `runtime/semantos-brain/src/info_http.zig`:

**`/api/v1/info` is GET-only.** It returns *brain-side facts*, not user preferences.

Returned fields (`info_http.handle` and `info_http_test.zig`):

- `brain_pin_cert_id` — operator's identity cert id
- `pubkey_hex` — operator's public key
- `shard_proxy` — overlay shard-proxy reference (when tenant manifest is loaded)
- `theme` — default theme (operator-set default, not user's preference)
- `available_hats` — list of hats this identity can wear
- `available_extensions` — list of cartridges installed on the brain
- `server_version` — brain binary version

**Returned info is per-identity, not per-user-session.** Two devices paired to the same identity get the same list of available_hats and available_extensions.

### What `/api/v1/info` does NOT return

- The user's *current* hat (no concept; per-request tag instead)
- The user's *preferences* (those are intents in cells)
- Authentication state (delegated to bearer-token middleware on other endpoints)

This narrow scope is what made T8a a one-day deploy (per `docs/REACTOR-PORT-TRACKER.md` T8a commit `6b7cb76`, deployed 2026-05-13).

---

## 9. BRC alignment (per §11.6 Tier-3)

Three BRCs that intersect this model, captured in §11.6 of UNIFICATION-ROADMAP as Tier-3 references worth tracking:

### BRC-46 — Wallet Transaction Output Tracking (Output Baskets)

Per-cartridge state organized into baskets. A future binding maps cartridge-owned cell collections to BRC-46 output baskets so wallet-side tooling can navigate them generically.

### BRC-99 — P Baskets: Future basket permission schemes

Permission gating on baskets — relevant when a cartridge needs hat-scoped read/write access to its own baskets. Aligns with the visibility filter in §5.

### BRC-102 — `deployment-info.json` Specification

The cartridge manifest format. Per §11.6 Tier-3, audit deferred. The current implicit manifest format inside the extension's `package.json` (e.g. `extensions/oddjobz/package.json`) should be cross-checked against BRC-102 before any new manifest fields are added.

### BRC-111 — P Labels: Future action label permissions

Per-action labels on intents — relevant for routing config intents through `verb.dispatch` with the right authorization scope. A `set_theme` intent has a different label scope than a `transfer_funds` intent; BRC-111 codifies the difference.

### BRC-116 — Wallet Permissions and Counterparty Trust

The permission scope for hat-aware features. When the shell asks "can this hat do that?" the answer is a BRC-116-style permission check against the hat's capability scope.

None of these is currently wired. They're the standards to bind to when the corresponding feature lands.

---

## 10. Common misclassifications

| Misclassification | Correction |
|---|---|
| "Add a `POST /api/v1/info` to save user preferences" | No. `/api/v1/info` is GET-only. Preferences are intents via `verb.dispatch`. |
| "Each hat is a separate user account" | No. Each hat is a child cert of one root identity. Same user, different scope. |
| "The brain tracks the user's current hat" | No. Hat is per-request tag. The brain only tracks the *list* of hats the user has access to. |
| "Hat switching requires re-authentication" | No. The cert chain stays valid across hats. Hat switching is a client-side toggle. |
| "Cartridges can issue new hat types" | No. Hats are derived from BRC-52 certs. Cartridges contribute lexicon types and cell schemas, not hats. |
| "Operator config and user preferences are the same thing" | No. Four distinct categories (brain / tenant / device / cartridge); first two via REPL, last two via verb.dispatch. |
| "Theme is a user preference so it lives in `/api/v1/info`" | No. `/api/v1/info.theme` is the **default** theme set by the operator. User overrides flow as intents. |
| "Shell-side state and brain-side state need to be merged into one config store" | No. They serve different lifecycles. Shell state is per-device + ephemeral; brain state is per-identity + persistent. Sync happens via intents, not via a unified store. |

---

## 11. Pending design work

Sidequests captured for future sprints:

1. **Canonical config-intent names.** Declare `set_theme`, `set_notification_pref`, `set_default_labor_rate`, `set_font_size`, etc. with explicit `verb.dispatch` handlers. Lives in extension grammars, not in the brain.
2. **Cartridge manifest standardization.** Cross-check against BRC-102; either align or document divergence. Lives alongside D-Doc-adapters and the per-extension README work.
3. **Hat-scoped capability tokens.** When D-Dcap-engine (per §11.6) lands its BRC-108/115 binding, hats become the natural unit of capability scope. Each hat carries a capability domain; capability checks become hat-scoped checks. Tracker should capture this composition.
4. **Bulk hat switching.** Today's per-request hat tag is fine for normal use. If a user needs to "show me everything across all hats" (e.g. a unified search) the shell needs a multi-hat tag or a fan-out call. Not blocking V1; surfaces when search lands.

---

## 12. Sources referenced

- Memory `shell_cartridges_hats_model.md` — the canonical model statement
- `docs/REACTOR-PORT-TRACKER.md` D11 — `/api/v1/info` GET-only decision (2026-05-12, refined)
- Memory `brain_reactor_v1_recovery_complete.md` — V1 endpoint set after T0–T5 + T8 landing
- `runtime/semantos-brain/src/info_http.zig` — `/api/v1/info` implementation
- `runtime/semantos-brain/tests/info_http_test.zig` — info endpoint test coverage
- `runtime/semantos-brain/src/resources/intent_cells_handler.zig:240, :279-291, :468` — hatId validation against cert chain
- `runtime/semantos-brain/src/oddjobz_ratify_walker.zig` — verb.dispatch registry wiring example
- `runtime/semantos-brain/src/verb_dispatcher/` — verb-dispatch infrastructure
- `core/plexus-contracts/src/domain-flags.ts` — capability domain partition
- `extensions/oddjobz/` — exemplar cartridge with 8 canonical cell types
- `docs/textbook/29-cross-vertical-dispatch-and-federation.md` — hat-typed AFFINE patches
- `docs/prd/UNIFICATION-ROADMAP.md` §11.6 — BRC-46 / 99 / 102 / 111 / 116 tier-3 references

PWA = shell. Apps = cartridges. Hats = tenant contexts. Config = intents. Four distinct things, four distinct mechanisms, one coherent model.
