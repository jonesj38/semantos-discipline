---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/SVELTE-HELM-DECISIONS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.723063+00:00
---

# Svelte-Helm — Decision Locks (SH0)

**Status**: LOCKED (SH0 entry gate)
**Matrix**: docs/canon/svelte-helm-matrix.yml
**Companions**: SVELTE-HELM-CONTRACTS.md, SVELTE-HELM-GOLDEN-SLICE.md

Answers to the open questions BEFORE code moves, mirroring canon C0's
decisions doc. Disputes resolve here. Each lock cites its source.

---

## D1 — Identity surfaces in BOTH the TALK tab AND a dedicated "me" affordance
**Locked**: 2026-06-06 (user decision).
Root BRC-52 cert custody, contacts, PKI/key REPL, wallet boot, and
PlexusRecoveryEnvelope download/enroll are reachable from **both**:
- the **TALK tab** — conversation + who-you're-talking-to + key management
  as one surface (the operator's stated model), and
- a dedicated **"me" affordance** (AppBar), parallel to canon C11.

**Why**: TALK is where the operator manages relationships and identity is
relational; the "me" affordance gives a stable always-present entry. Builds
on canon C11 substrate (cert custody, wallet, recovery) ported to the web
helm. Track: SH5.

---

## D2 — `surfacingMode` enum = {default, dedicated, passive}
**Locked**: matches `apps/semantos/lib/shell/helm_scaffold.dart:14-15` and
`cartridge_picker.dart:82-84` (`HelmSurfacingMode.defaultMode` / `passive`).
No new modes invented for the web helm — the Svelte router implements the
same three. `dedicated` is the whole-surface takeover; `default` shares the
body scoped to the active cartridge; `passive` is hidden from the picker.
Track: SH3.

---

## D3 — Manifests served on a SEPARATE route `/api/v1/cartridges`, not folded into `/api/v1/info`
**Locked**: `/api/v1/info` stays GET-only tenant/theme branding (existing
contract; see [[shell_cartridges_hats_model]] — `/info` stays GET-only). The
manifest list is a new bearer-gated route. Keeps branding and capability
projection separate concerns. Track: SH1.

> **REVISED 2026-06-07 (SH1-B discovery).** The premise above was wrong:
> `GET /api/v1/info` is **not** branding-only — it already serves a
> `cartridges[]` list (`info_http.CartridgeInfo {id, role,
> experience_package}`, CC2b Brain→PWA discovery, populated from
> `enumerateUserInstalled`). Standing up a parallel `/api/v1/cartridges`
> would duplicate that list and risk drift. **New decision: ENRICH the
> existing `/api/v1/info` cartridges[] entries with `surfacingMode` +
> `ui.verbs[]`** (the SH1-A loader fields). `/info` remains GET-only
> (read-only discovery), so the spirit of [[shell_cartridges_hats_model]]
> holds — we are not adding writes. A focused `/api/v1/cartridges` alias MAY
> be added later if the payload grows unwieldy, but is not required for SH1.
> CONTRACTS §1 to be updated to point at `/api/v1/info`'s cartridges[] as the
> source. This is reversible; flagged for user objection.

---

## D4 — Attention scope is HELM-OWNED policy; default scope = `shell`
**Locked**: the brain owns **no** scope policy — the caller passes the
in-scope namespace list (stated invariant in
`attention_source_registry.zig`). The helm decides ("shell only" vs "shell +
oddjobz + ecommerce") and passes it as `?ns=<csv>`. When `ns` is absent the
brain defaults to `shell` (the always-safe, isolation-preserving scope).
In-cartridge views pass just that cartridge's namespace ⇒ cross-cartridge
isolation by default. Track: SH8.

---

## D5 — REPL is the universal access layer; the shell imports ZERO cartridge packages
**Locked**: body-view data flows through the bearer-gated line REPL
(`find <resource>`) and verb dispatch via generic `dispatchByName` +
`POST /api/v1/cells` from the manifest's `ui.verbs[].dispatch.defaultPayload`.
The Svelte shell imports no cartridge code — the web analog of the canon C13
inversion. A cartridge's data lights up the moment its `registerInto`
registers its REPL verbs brain-side; only bespoke typed views require a
helm-side surface bundle. Tracks: SH2, SH4.

---

## D6 — Static-tunable weights (SH10) gate the slice; learning (SH11) does not
**Locked**: the SH12 golden slice proves the surface + operator-tunable
**static** weights. The learned-weights loop (AS1–AS5,
HELM-ATTENTION-SURFACE.md) is the optimisation layer and may land after the
slice passes. Rationale: legible, inspectable, roll-back-able static weights
are the substrate the learner drifts; shipping them first keeps learning
legible (re-weights existing factors, never invents new ones).

---

## D7 — Brain build verified via local `zig build`, NOT the Docker image
**Locked**: `runtime/semantos-brain/deploy/docker/Dockerfile` copies only
`runtime/semantos-brain` + `core`, but `build.zig` has ~93
`../../cartridges/...` refs ⇒ the image build fails as written. Fixing the
image is a canon C4-carve / Dockerfile concern, **out of scope** for this
matrix. SH1/SH6/SH7/SH8 brain changes are verified via `zig build` +
`zig build test -j1` in the worktree (which has `cartridges/`), and the
slice brain is built the same way. Flagged so the loop never blocks on the
broken image.

---

## D8 — Worktree-isolated; commit scoped to paths
**Locked**: all work happens in `worktrees/svelte-helm` (branch
`docs/svelte-helm-matrix`), never the dirty `semantos-core` main checkout
(see [[semantos_shared_checkout_reset_hazard]]). Commits are scoped to paths
(`git commit <paths> -m …`) because parallel sessions stage unrelated files
(see [[git_commit_scope_to_paths]]). Branch re-checked before every commit.

---

## D9 — `cartridge.json` is the single source of truth for the DECLARATIVE UI layer; rendering stays per-helm
**Locked**: 2026-06-07 (user delegated; reasoned below).

The open question was: can mobile (Flutter) and browser (Svelte) share one UI
source of truth when their screen real-estate and navigation differ so much?
Resolution: **separate the declarative/semantic layer from the rendering
layer.** A manifest declares WHAT a cartridge surfaces, never HOW a screen
lays it out.

- **Shared, brain-owned (in `cartridge.json`):** `ui.surfacingMode`
  (default/dedicated/passive — a semantic intent, not a layout), `ui.verbs[]`
  (`{modal, label, intentType, subtitle, icon}` — verb vocabulary +
  dispatch target, nothing positional), cellTypes, attention namespaces.
- **Per-helm, NOT in the manifest:** navigation chrome, real-estate split,
  gestures, and bespoke typed views (`JobDetailV2.svelte` vs a Flutter
  widget). Each helm interprets the same declaration into its own form
  factor (e.g. `dedicated` = full-screen route on mobile, full main-panel
  takeover in browser).

**Why cartridge.json (Option A) over the Flutter package manifest (B) or a
new shared file (C):** the brain is the always-on source — a pure-brain
cartridge with no Flutter package must still surface verbs to the web helm,
so the source cannot be a Flutter asset. `cartridge.json` already has a `ui`
block (`primaryAnchor`/`hierarchy`); we extend it. This matches the note
already in `cartridges/oddjobz/cartridge.json` ("this cartridge.json becomes
the primary registration source"). The Flutter package manifest
(`packages/<id>_experience/assets/manifest.json`) becomes a DERIVED artifact
— SH-era it may stay hand-maintained, but cartridge.json is canonical and a
later dedupe/generation step is tracked, not blocking.

**See also D10** — the helm this declarative layer feeds is the resurrected
loom-svelte (deliberate divergence from canon Q2).

---

## D10 — Resurrect loom-svelte as the brain's lean Svelte web helm (deliberate divergence from canon Q2)
**Locked**: 2026-06-07 (user decision).

Context surfaced during SH2 setup: `apps/loom-svelte` was archived to
`archive/apps-loom-svelte/` by canon track **C8** (commit `dbdd229`, "mass
archive sweep"), and canon **Q2** (matrix line 942) says the brain's web helm
should be `flutter build web` of `apps/semantos` — "not a separate codebase".

**Decision: override both.** The brain gets a **lean, separate Svelte web
helm** (loom-svelte), resurrected from archive. Rationale (user): a Flutter
web bundle is the wrong weight/shape for the always-on brain's default UI; a
purpose-built Svelte helm that talks to the brain purely over HTTP/REPL/WSS
is the right always-on surface. This **diverges from Q2** and **reverses the
C8 archival** for this one app — accepted, with eyes open that the
surfacingMode/verb-shelf/me inversion already done in Flutter (C9/C11/C13)
will be re-expressed in Svelte here (the declaration is shared via SH1's
`/api/v1/info`; only the rendering is duplicated, per D9).

**Mechanics:** `git mv archive/apps-loom-svelte apps/loom-svelte` (history
preserved). The resurrected tree already carries a partial `src/shell/`
(ExtensionSwitcher, OddjobzCartridge, AttentionSurface, Dock, context-weights)
— SH2-SH4/SH9 reassess against it rather than greenfield. Toolchain: vite +
svelte.config.js (+ bun/pnpm available); helm test gate = the package's own
test/build scripts.

**Reversible?** Yes — re-archive if the Flutter web-build path is later
preferred. SH1 (brain `/api/v1/info` enrichment) is helm-agnostic and stands
either way.

---

## D11 — Verb-shelf model: CSD pyramid default + cartridge overlay + hat-gating
**Locked**: 2026-06-07 (user decision).

The Svelte Dock already implements the canon **Q6 CSD 1-3-5-3-1 pyramid**
(DO/TALK/FIND modals → sub-verbs → type-weighted favourites). SH1's flat
`ui.verbs[]` (the Flutter ModalVerbShelf shape) is a *different* model. User
reconciliation — the shelf composes THREE layers:

1. **Default shell helm = the CSD 1-3-5-3-1 pyramid.** The substrate shell
   always surfaces the 5 sub-verbs per DO/TALK/FIND (kernel context-weights /
   `resolveFavourites`). This is the baseline every operator sees.
2. **Cartridge overlay.** A cartridge MAY keep the default verbs OR overlay
   its own. Its `ui.verbs[]` (SH1) augment/override per modal — so the flat
   verbs[] is RETAINED as the *overlay* mechanism (reconciles with D9; not
   discarded). Active-cartridge overlay composes onto the kernel pyramid.
3. **Hat-gating.** Verbs are scoped by the ACTIVE HAT:
   - **operator** hat → the same verbs as the default helm (base set).
   - **admin** hat → additional *managerial* verbs (manage the business
     website, the chat widget, policies that feed the widget, etc.).
   Each verb carries an optional role/hat scope (default = operator-visible;
   admin = the managerial extras). The shelf filters by the active hat.

**Implications:**
- `UiVerb` (brain `info_http`/loader + loom-svelte `extensions-api`) gains an
  optional `role` (or `minHat`) field — `"operator"` (default) | `"admin"`.
  The Dock filters verbs where `verb.role` is visible to the active hat.
- The Dock composes: kernel CSD pyramid (operator baseline) + active
  cartridge `ui.verbs[]` overlay, then filters by the HatSwitcher's active
  hat. Admin-only managerial verbs (website/widget/policy) are declared by
  the owning cartridge/surface with `role:"admin"` — same overlay mechanism,
  no new pipe.
- Connects to canon **Q6** (CSD pyramid), **C12** (cert-derived hats),
  **C13** (hat-gated shelf). loom-svelte's existing `HatSwitcher` supplies
  the active hat.

**Track impact:** SH2-B = render the pyramid default + cartridge overlay
(no hat filter yet); a new **SH-HAT** concern adds the `role` field +
hat-filtering; managerial admin verbs ride the overlay with `role:"admin"`.

---

## D12 — Hat role source: per-hat role on the cert/session (operator | admin)
**Locked**: 2026-06-07 (user decision).

SH14 hat-gating (D11) needs the active hat's operator/admin role, which the
hat model doesn't carry today. Decision: **each hat carries a role**
(operator | admin), assigned at hat creation / cert derivation. Switching
hats in the HatSwitcher switches the verb scope (matches "wearing their
operator hat vs the admin hat").

**Scoping (SH-era vs C12):**
- **SH-era source = the bearer token / session.** The helm auths via a bearer
  today; the hat role rides the bearer TokenRecord (default `operator`; an
  admin hat is issued explicitly, e.g. `brain bearer issue --role admin`).
  The brain surfaces it on the `/api/v1/info` hat block (`hat.role`) and the
  helm reads it via `getActiveHat`.
- **C12 evolution.** Once cert-derived hats land (canon C12), a hat's role is
  carried by its derived child cert. The SH14 helm code reads `hat.role`
  regardless of source, so the C12 swap is brain-side only.

**SH14 filter rule:** a verb carries an optional `role` (`operator` default |
`admin`). The Dock shows a verb iff its role is visible to the active hat:
operator hat → operator-only; admin hat → operator + admin. Managerial admin
verbs (website / chat-widget / policies) are declared `role:"admin"` by their
owning cartridge.

**Track impact:** SH14-A = add `role` to UiVerb (helm extensions-api + brain
info_http/loader + emit). SH14-B = Dock filters by `getActiveHat().role`.
SH14-D = brain hat-role on the bearer TokenRecord + `/api/v1/info` hat block
emit + getActiveHat surfaces it.

---

## D13 — The "me" panel houses wallet + identity cert + hat switching (with role)
**Locked**: 2026-06-07 (user decision).

The "me" panel (SH5) is the single identity surface, mirroring the Flutter
helm's "me" surface (canon C11). It shows:
- the **wallet** (BRC-100 / wallet-headers) in effect,
- the **identity cert in effect** (the operator's root/active cert),
- **hat switching** — and the active hat's **operator/admin role** (D12) is
  selected here.

**Concrete change:** today loom-svelte mounts `HatSwitcher` as a standalone
AppBar (bar-right) widget (App.svelte:327). It **moves into the me panel**.
Hat switching is an identity action, so it belongs with wallet + cert, not as
loose top-bar chrome.

**Coupling:** SH14's Dock verb-filter reads the active hat's role; that role
is chosen via the hat switcher **in the me panel**. So SH14-B (Dock filter)
depends on SH5 (me panel) surfacing the active-hat role selection. The brain
still emits `hat.role` (SH14-D / D12); the me panel is where the operator sees
and switches it.

**Recall (D1):** identity is reachable from BOTH the TALK tab and a dedicated
"me" affordance. D13 specifies the me panel's CONTENTS (wallet + cert + hat/
role) and relocates the hat switcher into it.

---

## D14 — Verb dispatch = open the cartridge surface (SH2-H)
**Locked**: 2026-06-07 (user decision).

A DO/FIND overlay verb does NOT mint a cell or run a REPL line directly.
Instead it **navigates into the active cartridge's own surface at the
relevant flow** — e.g. DO → "New job" (`oddjobz.job.create`) opens the
oddjobz surface's jobs view; FIND → "Find customer"
(`oddjobz.customer.find`) opens the customers view. The cartridge UI owns
the actual create/find forms (best UX for rich entities; no new manifest
schema; no generic input sheet).

**Mechanism:**
- A pure `parseVerbIntent(intentType)` → `{ cartridgeId, entity, action }`
  (e.g. `oddjobz.job.create` → `{oddjobz, job, create}`). Testable, generic.
- `handleDockInvoke`: for a verb whose `cartridgeId` has a registered
  surface, set `activeCartridge = cartridgeId` and pass an entry hint
  (entity/action) to the surface.
- The cartridge surface (e.g. `OddjobzCartridge`) maps the entity → its
  tab/flow and opens it. The entity→tab mapping is cartridge-specific.

This supersedes the SH2-H `dispatch`-block / cell-mint direction in the SH0
CONTRACTS draft (that was the Flutter C13/#725 model). The per-verb
`dispatch` block is NOT needed for the Svelte helm under D14.

---

## D15 — Shell-native attention signals (SH7) + skip weighting for now (SH10/SH11)
**Locked**: 2026-06-07 (user decision).

**SH7 — register exactly TWO shell-native attention sources** under namespace
`shell` (so a pure-brain shell with no cartridges still has a useful feed):
1. **Identity/recovery nudges** — cert expiry approaching, recovery-envelope
   missing, capability(bearer)-token expiry. Always-on identity health.
2. **Pending ratifications** — cells/actions awaiting the operator's sign-off.

DEFERRED (not now): inbound chat-widget leads; legacy-ingest proposals.

**SH10/SH11 — SKIP weighting/learning for now.** The WSS attention.poll
already returns per-source scores; use those. No central weight layer, no
learned loop yet. Static-tunable weights (SH10) and the AS1–AS5 learned loop
(SH11) are deferred (SH11 also needs a telemetry endpoint, which was deleted
with the REST surface — rebuild later if/when learning is wanted).

Implementation: each source is an attention_source_registry.AttentionSource
(namespace "shell", a collect fn emitting {kind,score,ref,summary,…}),
registered at serve boot UNCONDITIONALLY (not cartridge-gated). The collect
fns read existing brain state (bearer_tokens for token expiry; the
ratification store for pending items); availability of each on origin/main to
be assessed before wiring.

---

## D9 addendum — verb-entry shape (canonical)
**Verb-entry shape (canonical):** align to the existing Flutter shape —
`{ "modal": "do"|"talk"|"find", "label", "intentType", "subtitle"?, "icon"? }`
with an optional `"dispatch": { cellType, triple, defaultPayload }` block
(canon HelmUiVerbDispatch / PR #725) when a verb mints directly. The browser
helm dispatches the same `intentType` via the REPL / `POST /api/v1/cells`.
This supersedes the placeholder `{cellType,triple,defaultPayload}`-only shape
in the SH0 draft of CONTRACTS §1 (now corrected). Tracks: SH1, SH2, SH3.
