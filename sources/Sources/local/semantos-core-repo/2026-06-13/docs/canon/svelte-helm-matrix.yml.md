---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/svelte-helm-matrix.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.627659+00:00
---

# docs/canon/svelte-helm-matrix.yml

```yml
# The Svelte-Helm Matrix — tracking artifact for turning loom-svelte
# (the always-on brain's default web UI) into a neutral, manifest-driven
# cartridge-loader helm with a configurable attention surface and a
# substrate identity surface.
#
# WHY THIS EXISTS
# ---------------
# The cartridge-as-whole-surface-takeover model ("activate the ecommerce
# cartridge and the surface totally switches, no evidence of oddjobz") is
# already built and verified — but in the FLUTTER helm (apps/semantos),
# via ui.surfacingMode + the C13 verb-shelf inversion + the C11 "me"
# surface. The brain's own DO|TALK|FIND Svelte helm (apps/loom-svelte) is
# still a hardwired single-cartridge (oddjobz) UI: static view imports, a
# fixed activeTab union, zero manifest awareness (App.svelte:44-57).
#
# This matrix tracks porting that model into loom-svelte AND finishing the
# brain-side seams it depends on, so a fresh "pure brain shell" boots with
# identity + a shell-native attention feed, and each activated cartridge
# extends or wholly replaces the surface.
#
# THE TWO UNITS THIS MATRIX TOUCHES
# ---------------------------------
#   1. Svelte helm — apps/loom-svelte
#      Becomes a neutral chrome (picker + DO|TALK|FIND shelf + attention
#      surface + me/identity) that renders entirely from cartridge
#      manifests fetched over HTTP. Ships zero cartridge imports.
#
#   2. Brain — runtime/semantos-brain
#      Gains the HTTP seams the web helm needs (manifest list), finishes
#      the C4 attention-source carve, registers shell-native attention
#      sources, and grows the attention scope/weights/learning loop.
#
# RELATION TO canonicalization-matrix.yml
# ---------------------------------------
# This is a DOWNSTREAM, scoped sibling. It assumes the canon matrix's
# C4/C5 (brain extraction + extension loader), C6/C6a (BRC-100 wallet),
# C9/C11/C13 (Flutter surfacingMode + me + verb-shelf inversion) as the
# proven reference implementation to port FROM. Where a seam is interim
# in the canon work (e.g. oddjobz attention sources still in serve.zig),
# this matrix owns finishing it for the web-helm path.
#
# Schema parallel to docs/canon/canonicalization-matrix.yml.
# Rendered via docs/canon/render/svelte-helm-to-roadmap.ts (track SH13)
# to docs/prd/SVELTE-HELM-ROADMAP.md.
#
# Status legend:
#   ✓   — implemented, tested, verifiable
#   ⚠   — partial / in progress / a related seam exists elsewhere but not
#         on this path / unverified
#   ✗   — not started
#   n/a — not applicable on this (track, axis) pair
#
# Each cell is `{ status, deliverable: D-SVHELM-<TrackID>-<Axis>, note }`.
# Deliverable IDs follow D-SVHELM-{TrackID}-{Axis} (e.g. D-SVHELM-SH2-A).
#
# Axis definitions (A..J) — same spine as the canon matrix:
#   A. Source extracted   — files moved/created at target location
#   B. Target wired       — imports, registry, dispatch, render hooked up
#   C. Tests pass         — test surface green (Svelte: vitest; brain: zig build test)
#   D. Brain-side         — companion brain change landed (HTTP seam, registry)
#   E. Helm-side          — companion loom-svelte change landed
#   F. Wallet integration — wallet-headers / BRC-100 wired through (identity tracks)
#   G. Recovery envelope  — plexusRecoveryEnvelope coverage (identity tracks)
#   H. Intent pathway     — gradient pipeline / verb dispatch flows through
#   I. Docs               — module README / canon doc / roadmap updated
#   J. Old code deleted   — zero remaining references to the hardwired path

# ─────────────────────────────────────────────────────────────────────
# PIPELINE METADATA — read by the autonomous loop.
# ─────────────────────────────────────────────────────────────────────
pipeline:
  id: SVELTE-HELM
  entry_gate: SH0          # nothing else gets a ✓ until SH0 is green
  golden_slice: SH12       # the operator-acceptance proof of the whole vision
  # Dependency DAG (track → tracks it requires complete or ⚠-sufficient):
  #   SH0  → (none, entry gate)
  #   SH1  → SH0
  #   SH2  → SH1
  #   SH3  → SH2
  #   SH4  → SH3
  #   SH5  → SH2            (+ canon C6/C6a/C11 substrate as reference)
  #   SH6  → SH0            (+ canon C4/C5 seam; can run parallel to SH2-4)
  #   SH7  → SH6, SH5
  #   SH8  → SH6, SH7
  #   SH9  → SH8, SH2
  #   SH10 → SH9
  #   SH11 → SH10
  #   SH12 → SH3, SH4, SH5, SH9, SH10   (full e2e; SH11 not required for slice)
  #   SH13 → cross-cutting (render + loop entry; bump as tracks land)
  #   SH14 → SH2-B, SH5    (hat-gated verbs: operator vs admin; DECISION D11)
  #   SH15 → SH2           (core read-path re-wire onto cell.query/cell.get;
  #                         brain seam already on main; feeds SH12 golden slice)
  complete_when: >
    Every track SH0..SH15 is ✓ on all non-n/a axes AND SH12 (golden slice)
    passes operator acceptance on the canonical loom-svelte build against a
    live brain. SH11 (learning) may trail SH12 — the slice proves the
    surface + static-tunable attention; learning is the optimisation layer.

# ─────────────────────────────────────────────────────────────────────
# AUTONOMOUS-LOOP PROTOCOL — how to chew through this matrix per tick.
# ─────────────────────────────────────────────────────────────────────
loop_protocol:
  worktree: worktrees/svelte-helm        # create off origin/main; do NOT work in the dirty main checkout
  first_bash_each_tick: >
    cd /Users/toddprice/projects/worktrees/svelte-helm && git rev-parse
    --abbrev-ref HEAD && git rev-list --left-right --count origin/main...HEAD
    && git status --porcelain | head. Surface branch + ahead/behind before any edit.
  test_gates:
    brain:  "zig build test -j1 --summary all   (run in runtime/semantos-brain; no summary line = success in zig 0.15)"
    helm:   "pnpm -C apps/loom-svelte test       (vitest) + pnpm -C apps/loom-svelte build (tsc/svelte-check)"
  select_next: >
    Pick the LOWEST-numbered track whose deps (see pipeline DAG) are all ✓
    (or ⚠-sufficient where the note says so) and that still has any ✗/⚠ axis.
    Work ONE axis (or one named sub-deliverable for SH11) per tick.
  on_complete_axis: >
    Flip the axis status, append a dated note with the commit hash, run the
    relevant test gate, then commit SCOPED TO PATHS (git commit <paths> -m …)
    — the checkout has parallel-session staged files; never `git commit -m`
    bare. Re-check the branch right before commit.
  hazards:
    - A parallel-session fast-forward (main ↔ feat) is sync, not divergence — do not bail the loop (see [[loops_branch_flexibility]]).
    - Never `reset --hard` / branch-switch in the semantos-core MAIN checkout — wipes uncommitted tracked edits (see [[semantos_shared_checkout_reset_hazard]]). Stay in the worktree.
    - Brain build needs cartridges/ in the build context (SH-DOCKER caveat below); the worktree has it, the Docker image does not yet.
  docker_caveat: >
    runtime/semantos-brain/deploy/docker/Dockerfile copies only
    runtime/semantos-brain + core, but build.zig has 93 ../../cartridges
    refs → the image build fails as written. Out of scope for this matrix
    (it's a canon C4-carve / Dockerfile fix), but flagged so the loop does
    not try to verify SH1/SH6 via the Docker image — verify via local
    `zig build` in the worktree instead.

# ─────────────────────────────────────────────────────────────────────
tracks:
  # ───────────────────────────────────────────────────────────────────
  - id: SH0
    name: Contracts + Decision Locks + Golden Slice
    note: |
      The entry gate. Locks the wire contracts and design forks BEFORE any
      code moves, mirroring canon C0. Ships THREE artifacts:
        1. docs/design/SVELTE-HELM-CONTRACTS.md — the HTTP contracts the
           web helm consumes:
             - GET /api/v1/cartridges  (SH1) JSON shape: per cartridge
               { id, role, ui.surfacingMode, ui.verbs[] (modal, label,
               inputShape, dispatch{cellType,triple,defaultPayload}),
               attention.namespaces[] }.
             - GET /api/v1/attention/snapshot + ?ns= scope param (SH8),
               POST /api/v1/attention/interact, GET/PUT /api/v1/attention/weights.
             - The {kind,score,ref,summary,[expiresAt],raw} attention
               signal shape (already owned by attention_source_registry.zig).
        2. docs/design/SVELTE-HELM-GOLDEN-SLICE.md — the SH12 operator
           tape: pure-shell boot → identity in TALK + me → shell-native
           attention → load oddjobz → load ecommerce (dedicated takeover,
           no oddjobz evidence) → scope toggle cross-business view.
        3. Decision locks: identity surfaces in BOTH the TALK tab AND a
           dedicated "me" affordance (user decision 2026-06-06);
           surfacingMode enum = {default, dedicated, passive} (matches
           helm_scaffold.dart:14-15); attention scope policy is
           helm-owned (brain owns no policy per attention_source_registry.zig).
    axes:
      A: { status: "✓", deliverable: D-SVHELM-SH0-A, note: "2026-06-06: authored docs/design/SVELTE-HELM-{CONTRACTS,GOLDEN-SLICE,DECISIONS}.md." }
      B: { status: "n/a", note: "Lock-in, not wiring." }
      C: { status: "n/a" }
      D: { status: "n/a" }
      E: { status: "n/a" }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✓", deliverable: D-SVHELM-SH0-I, note: "2026-06-06: the locks ARE the docs (DECISIONS D1-D8); CONTRACTS §1-7; slice tape 5 steps." }
      J: { status: "n/a" }
    done_when: "All three SH0 artifacts committed; contracts referenced by SH1/SH8; slice tape agreed."   # ✓ 2026-06-06

  # ───────────────────────────────────────────────────────────────────
  - id: SH1
    name: "Brain: manifest-list endpoint (/api/v1/cartridges)"
    note: |
      The web helm has no in-process GrammarRegistry (that's a Flutter/Dart
      thing), so the brain must expose each loaded cartridge's manifest over
      HTTP. NET-NEW seam. Reads the same manifests extension_manifest_loader
      already parses; projects ui.verbs[] + ui.surfacingMode + role +
      attention.namespaces[] into JSON. /api/v1/info exists today but only
      returns theme/tenant branding — extend it or add a sibling route.
    axes:
      A: { status: "✓", deliverable: D-SVHELM-SH1-A, note: "2026-06-07: extension_manifest_loader.zig now parses ui.surfacingMode + ui.verbs[] (UiVerbDecl: modal/label/intent_type/subtitle?/icon?) with legacy-ui back-compat; added ui.surfacingMode+verbs[] to cartridges/oddjobz/cartridge.json (6 verbs from the Flutter manifest). 15/15 isolated loader tests pass; `zig build` green. Per DECISION D9." }
      B: { status: "✓", deliverable: D-SVHELM-SH1-B, note: "2026-06-07: enriched info_http.CartridgeInfo with surfacing_mode + ui_verbs (UiVerb struct); serve.zig populates from loaded ExtensionManifest list (borrowed, process-lifetime); info_http.handle() emits flat surfacingMode + verbs[] on each cartridge entry. `zig build` green." }
      C: { status: "✓", deliverable: D-SVHELM-SH1-C, note: "2026-06-07: extended tests/info_http_test.zig — cartridges[] carry surfacingMode+verbs (do/find, intentType, icon); pure-shell ⇒ \"cartridges\":[]. Full `zig build test` green (exit 0)." }
      D: { status: "✓", deliverable: D-SVHELM-SH1-D, note: "2026-06-07: loader (SH1-A) + HTTP projection (SH1-B) both landed — the seam is complete; brain serves the declarative UI layer over /api/v1/info." }
      E: { status: "n/a", note: "Consumed by SH2." }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✓", deliverable: D-SVHELM-SH1-I, note: "2026-06-07: CONTRACTS §1 updated to the IMPLEMENTED shape (flat fields on /api/v1/info cartridges[]); D3 revision recorded." }
      J: { status: "n/a" }
    done_when: "GET /api/v1/info cartridges[] carries surfacingMode + verbs[] for 0..N loaded cartridges; bearer-gated; tests green."   # ✓ 2026-06-07

  # ───────────────────────────────────────────────────────────────────
  - id: SH2
    name: "Svelte shell chrome (neutral cartridge loader)"
    note: |
      New apps/loom-svelte/src/shell/: ManifestStore (consumes SH1),
      CartridgePicker.svelte, VerbShelf.svelte (DO|TALK|FIND rendered from
      verbsForModal(modal, activeCartridge)), a generic input sheet driven
      by ui.verbs[].inputShape (replaces hardcoded view forms), and generic
      dispatch (REPL verb OR POST /api/v1/cells from
      ui.verbs[].dispatch.defaultPayload). The shell imports ZERO cartridge
      packages — direct port of the C13 inversion (matrix C13-A/B ✓ on Flutter)
      into Svelte.
    axes:
      A: { status: "✓", deliverable: D-SVHELM-SH2-A, note: "2026-06-07 (DECISION D10): resurrected apps/loom-svelte from archive/ (git mv, history preserved). Toolchain up (pnpm install green; gate = pnpm -C apps/loom-svelte {test,check,build} — 131 tests + svelte-check 0 errors baseline). AUDIT: it already ships the inversion scaffold — ExtensionSwitcher (picker) ALREADY fetches /api/v1/info cartridges[] via lib/extensions-api.ts; App.svelte has activeCartridge state + ExtensionSwitcher. GAPS for SH2-B/SH3/SH4 below." }
      B: { status: "✓", deliverable: D-SVHELM-SH2-B, note: "2026-06-07: shelf renders from the ManifestStore, not static verbs. (1) data layer (extensions-api normalizes SH1-B fields); (2) composition logic (shelf-compose.ts: kernel CSD pyramid default + cartridge ui.verbs[] overlay per modal); (3) WIRED into Dock.svelte — tier-2 strip renders kernel contexts + active cartridge's overlay verbs as direct-dispatch tiles; ExtensionSwitcher emits verbs via onSwitch → App holds activeCartridgeVerbs → passes to Dock. svelte-check 0 errors, 136 tests, vite build ✓." }
      C: { status: "✓", deliverable: D-SVHELM-SH2-C, note: "2026-06-07: extensions-api.test.ts (8) + shelf-compose.test.ts (5) prove 'only the active cartridge's verbs per modal' + default/coerce/pure-shell. 136/136 helm tests pass; svelte-check 0 errors; build green. (No widget-test harness in-repo — codebase tests logic via node --test; render verified by check+build.)" }
      D: { status: "n/a", note: "Brain unchanged; consumes SH1." }
      E: { status: "✓", deliverable: D-SVHELM-SH2-E, note: "2026-06-07: helm-side wired — ExtensionSwitcher.onSwitch(id,peerView,verbs) → App.activeCartridgeVerbs → Dock.cartridgeVerbs → composeShelfModal overlay tiles." }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "✓", deliverable: D-SVHELM-SH2-H, note: "2026-06-07 RESOLVED by DECISION D14 (open the cartridge surface). src/shell/verb-intent.ts parseVerbIntent(intentType)→{cartridgeId,entity,action} (pure, 3 tests); App.handleDockInvoke routes a cartridge verb → set activeCartridge + pendingEntryEntity; the surface opens the matching flow (OddjobzCartridge entryEntity→tab map: job→jobs, customer→customers, …). No cell-mint dispatch block / generic sheet needed (the cartridge UI owns create/find). 157 tests + svelte-check 0 errors + build. (Refinement: action-specific auto-open of a create form — today the verb opens the entity's tab where the create affordance lives.)" }
      I: { status: "✗", deliverable: D-SVHELM-SH2-I }
      J: { status: "⚠", deliverable: D-SVHELM-SH2-J, note: "Hardwired view imports survive until SH4 moves them out." }
    done_when: "loom-svelte boots a manifest-driven DO|TALK|FIND shell with zero cartridge imports; picker switches active cartridge."

  # ───────────────────────────────────────────────────────────────────
  - id: SH3
    name: "surfacingMode surface routing (the takeover)"
    note: |
      Implement the three modes in the Svelte shell, matching
      helm_scaffold.dart:14-15 + cartridge_picker.dart:82-84:
        - dedicated → full route takeover (the ecommerce swap; no evidence
          of any other cartridge while active).
        - default   → shared body, scoped to the active cartridge.
        - passive   → excluded from the picker.
      This is the literal "load its cartridge and it totally switches"
      behaviour for the brain's web helm.
    axes:
      A: { status: "✓", deliverable: D-SVHELM-SH3-A, note: "2026-06-07: src/shell/body-route.ts — pure resolveBodyRoute (precedence: shell views > active cartridge > home; surfacingMode → dedicated takeover | default shared | passive→home defensive)." }
      B: { status: "✓", deliverable: D-SVHELM-SH3-B, note: "2026-06-07: App.svelte centre-slot driven by bodyRoute; `dedicated` class makes the cartridge surface full-bleed (padding:0). ExtensionSwitcher threads surfacingMode via onSwitch; passive filtered from the picker list." }
      C: { status: "✓", deliverable: D-SVHELM-SH3-C, note: "2026-06-07: tests/body-route.test.ts (6) — view precedence, home, default vs dedicated, passive→home. 142/142 helm tests; svelte-check 0 errors; build ✓." }
      D: { status: "n/a" }
      E: { status: "✓", deliverable: D-SVHELM-SH3-E, note: "2026-06-07: helm-side wired (ExtensionSwitcher.onSwitch surfacingMode → App.activeCartridgeSurfacingMode → bodyRoute → centre-slot)." }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✓", deliverable: D-SVHELM-SH3-I, note: "2026-06-07: routing semantics documented in body-route.ts + DECISION D11." }
      J: { status: "n/a" }
    done_when: "Switching to a dedicated-mode cartridge replaces the whole surface; default-mode coexists scoped; passive is hidden."   # routing+threading ✓ 2026-06-07; the VISIBLE dedicated-takeover demo needs a real non-oddjobz surface (SH4 generic surface loading + a 2nd cartridge).

  # ───────────────────────────────────────────────────────────────────
  - id: SH4
    name: "Oddjobz surface extraction (shell goes cartridge-neutral)"
    note: |
      Move the hardwired views (JobList, JobDetailV2, CustomerList, Calendar,
      Attention, VisitList, QuoteList, InvoiceList, Transcript, SiteConfigEditor,
      SiteDetail — App.svelte:44-57) OUT of the shell into an oddjobz surface
      bundle registered as its experience surface (default or dedicated). The
      shell then ships zero oddjobz knowledge. This is the J-axis payoff and
      the proof the inversion is real (mirrors canon C13's "drop the shell→
      cartridge import").
    axes:
      A: { status: "✓", deliverable: D-SVHELM-SH4-A, note: "2026-06-07: src/shell/surface-registry.ts — pure lookupSurface/isRegistered over an id→SurfaceEntry registry; unknown id → null (placeholder)." }
      B: { status: "✓", deliverable: D-SVHELM-SH4-B, note: "2026-06-07: App.svelte renders bodyRoute.kind==='cartridge' via lookupSurface(SURFACES, id) + a 'surface not available in this build' placeholder for unregistered ids. The hardcoded id==='oddjobz' check is GONE — App's only oddjobz reference is one SURFACES registration row." }
      C: { status: "✓", deliverable: D-SVHELM-SH4-C, note: "2026-06-07: tests/surface-registry.test.ts (4) — known id resolves, unknown/null → null, isRegistered. 146/146 helm tests; svelte-check 0 errors; build ✓." }
      D: { status: "n/a" }
      E: { status: "✓", deliverable: D-SVHELM-SH4-E, note: "2026-06-07: helm-side wired — SURFACES map + activeSurface derived + @const Surface render." }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✓", deliverable: D-SVHELM-SH4-I, note: "2026-06-07: surface-registry.ts documents the one-binding-point realism (bundled SPA; true zero-import = dynamic import, out of scope) per D9." }
      J: { status: "⚠", deliverable: D-SVHELM-SH4-J, note: "2026-06-07: FUNCTIONAL neutrality achieved — shell renders cartridges generically via the registry; App no longer hardcodes oddjobz routing. NOT done: physically relocating OddjobzCartridge + src/views/* into a separate oddjobz surface bundle (a large organizational file-move; deferred — the realistic web-helm decoupling is the single registry binding point, per surface-registry.ts + D9). The one OddjobzCartridge import for its registry row remains." }
    done_when: "Cartridge body renders via the surface registry (✓); unregistered ids show a placeholder (✓); dedicated takeover supported for a 2nd registered surface (mechanism ✓ — needs a real 2nd cartridge surface to demo). Physical view-package extraction (J) deferred as organizational."   # mechanism ✓ 2026-06-07

  # ───────────────────────────────────────────────────────────────────
  - id: SH5
    name: "Identity surface — cert / contacts / PKI in TALK + 'me' (both)"
    note: |
      Port the C11 "me" substrate into loom-svelte AND expose it from the
      TALK tab (user decision D1: BOTH). The "me" PANEL is the single identity
      surface (DECISION D13) — mirrors the Flutter helm's "me" surface. Contents:
        - the WALLET in effect (BRC-100 / wallet-headers boot).
        - the IDENTITY CERT in effect (root/active operator cert) + custody.
        - HAT SWITCHING with the active hat's operator/admin ROLE (D12/D13) —
          RELOCATED here from the standalone AppBar HatSwitcher (App.svelte:327).
        - Contacts / PKI (substrate contacts+pairing primitives).
        - Secret-question setup + PlexusRecoveryEnvelope download/enroll.
      TALK = conversation + who-you're-talking-to + key management; the "me"
      affordance opens the panel above. Substrate exists (canon C6/C6a/C11,
      Flutter) — this builds the web-helm surface against the brain's
      identity/cert/wallet endpoints. NOTE: SH14-B (Dock verb hat-filter) reads
      the active-hat role SELECTED in this panel — SH14-B depends on SH5.
    axes:
      A: { status: "✓", deliverable: D-SVHELM-SH5-A, note: "2026-06-07: src/shell/me/MePanel.svelte (identity cert in effect via getCert + RELOCATED HatSwitcher + operator/admin role badge + wallet section + contacts entry) + me-format.ts (shortId/roleLabel/formatIssued, pure)." }
      B: { status: "✓", deliverable: D-SVHELM-SH5-B, note: "2026-06-07: App renders MePanel as a modal; AppBar 'me' affordance (with role) opens it; view:me dispatch opens it from the Dock/TALK path (D1 BOTH); HatSwitcher MOVED out of AppBar bar-right into the panel; contacts opens NetworkView. Cert via /api/v1/identity/cert; role via activeHatRole (/api/v1/info)." }
      C: { status: "⚠", deliverable: D-SVHELM-SH5-C, note: "2026-06-07: me-format.test.ts (3) — shortId/roleLabel/formatIssued. 154 helm tests + svelte-check 0 errors + build. Panel itself is presentational (covered by check+build); no widget harness in-repo." }
      D: { status: "⚠", deliverable: D-SVHELM-SH5-D, note: "Cert auth seam exists (cert_request_auth.zig, PR #885 / T7); recovery-envelope endpoint may need exposing (→ SH5-G)." }
      E: { status: "✓", deliverable: D-SVHELM-SH5-E, note: "2026-06-07: helm-side me panel + affordance + view:me + HatSwitcher relocation wired; svelte-check 0 errors." }
      F: { status: "⚠", deliverable: D-SVHELM-SH5-F, note: "2026-06-07: wallet SURFACED in the me panel (origin + same-origin /api/v1/wallet WSS endpoint + Open-wallet link). Full BRC-100 wallet-headers boot (canon C6/C6a) not deeply wired into the web helm — reused existing walletOrigin; deeper boot deferred." }
      G: { status: "✗", deliverable: D-SVHELM-SH5-G, note: "PlexusRecoveryEnvelope download/enroll + secret-question setup NOT in the me panel yet — deferred (the panel ships cert+hat+wallet+contacts; recovery is a follow-on)." }
      H: { status: "n/a" }
      I: { status: "⚠", deliverable: D-SVHELM-SH5-I, note: "2026-06-07: D13 (me panel contents + HatSwitcher relocation) recorded. Module-level docs in MePanel.svelte + me-format.ts." }
      J: { status: "n/a" }
    done_when: "Pure-shell boot shows root cert + contacts + PKI from BOTH the TALK tab and a 'me' affordance; wallet boots; recovery envelope downloadable."

  # ───────────────────────────────────────────────────────────────────
  - id: SH6
    name: "Brain: finish attention-source carve into registerInto"
    note: |
      Close the C4 PR-J4 interim. Today oddjobz's 3 attention sources
      (dispatch/message/job) are registered in serve.zig:2523-2525 with the
      explicit comment "moves into the cartridge's registerInto later". Move
      them into the oddjobz cartridge's registerInto so ANY cartridge
      contributes namespaced attention sources purely by being loaded — the
      attention analog of the route/mint/store registries.
    axes:
      A: { status: "✗", deliverable: D-SVHELM-SH6-A, note: "Source collect fns move to cartridges/oddjobz/brain/zig." }
      B: { status: "⚠", deliverable: D-SVHELM-SH6-B, note: "Registry + namespace poll exist (attention_source_registry.zig, attention_poll_handler.zig); registration is serve-owned (interim)." }
      C: { status: "✗", deliverable: D-SVHELM-SH6-C, note: "zig test: a loaded cartridge's sources appear in-scope; absent when unloaded." }
      D: { status: "✗", deliverable: D-SVHELM-SH6-D, note: "This IS the brain-side change." }
      E: { status: "n/a" }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✗", deliverable: D-SVHELM-SH6-I }
      J: { status: "✗", deliverable: D-SVHELM-SH6-J, note: "Remove the serve.zig:2523-2525 hardcoded adds." }
    done_when: "Dropping/removing a cartridge adds/removes its attention sources with no serve.zig edit; oddjobz sources gone from serve.zig."

  # ───────────────────────────────────────────────────────────────────
  - id: SH7
    name: "Brain: shell-native attention sources (pure-brain mode)"
    note: |
      THE CORE of "configure the helm's attention surface in pure brain
      shell mode". Today the registry has ONLY oddjobz sources — with zero
      cartridges the snapshot is empty. Register sources under a "shell"/"me"
      namespace for always-on operator signals independent of any business
      cartridge:
        - cert-expiry / recovery-envelope-missing nudges (ties to SH5/C11)
        - pending ratifications awaiting operator sign-off
        - unread chat-widget leads (the inbound-leads signal)
        - legacy-ingest proposals needing review
        - capability-token expiry
      These are the signals that make a bare brain shell useful before any
      cartridge is loaded.
    axes:
      A: { status: "✓", deliverable: D-SVHELM-SH7-A, note: "2026-06-07 (D15): src/shell_attention_sources.zig — pure (std-only) JSON builders. buildShellIdentityJson = recovery-setup standing nudge + a token-expiry signal per bearer token expiring within 7d (score rises as expiry nears; expiresAt in ms). buildPendingRatificationsJson = [] PLACEHOLDER — origin/main has NO queryable pending-ratification queue (ratify is synchronous submit; ratify_builder_registry holds builders, not proposals). Gap noted." }
      B: { status: "✓", deliverable: D-SVHELM-SH7-B, note: "2026-06-07: serve.zig registers BOTH under namespace 'shell' UNCONDITIONALLY (ShellAttnCtx → token_store; shellIdentitySource maps TokenRecord→TokenExpiry; shellRatifySource→[]). build.zig: new shell_attention_sources_mod + cli_mod import + inline-test artifact. A pure-brain shell (empty extensions/) now returns a non-empty attention.poll(ns=['shell']) — the recovery nudge always fires." }
      C: { status: "✓", deliverable: D-SVHELM-SH7-C, note: "2026-06-07: 4 inline tests (recovery+token-expiry within window; has_recovery suppresses nudge; limit caps; ratify placeholder). zig build + zig build test green." }
      D: { status: "✓", deliverable: D-SVHELM-SH7-D, note: "2026-06-07: brain-side — token-expiry uses bearer_tokens.list/expires_at; recovery is a standing nudge (no envelope store on main); ratify placeholder pending a future queue." }
      E: { status: "n/a" }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✗", deliverable: D-SVHELM-SH7-I }
      J: { status: "n/a" }
    done_when: "A brain with empty extensions/ returns a non-empty, scored shell-native attention feed covering the named signal kinds."

  # ───────────────────────────────────────────────────────────────────
  - id: SH8
    name: "Brain: attention scope config + unify snapshot↔poll"
    note: |
      Today GET /api/v1/attention/snapshot (attention_http.zig) is bearer-only
      with NO namespace param, while the namespace-scoped path lives on the
      WSS attention.poll method (attention_poll_handler.zig, namespaceInList).
      Unify them: add a scope param (?ns=shell,oddjobz or a session-stored
      opt-in list) to the REST snapshot, routing through the scoped poll. The
      brain owns no policy — the helm passes which namespaces are in view.
      This scope toggle is the cross-business "operational brain" view
      (shell only ↔ shell + oddjobz + ecommerce).
    axes:
      A: { status: "⚠", deliverable: D-SVHELM-SH8-A, note: "2026-06-07 DISCOVERY: the REST attention_http (/api/v1/attention/*) was DELETED on origin/main (PR #921, 'superseded by the generic attention.poll'). The canonical surface is the WSS namespace-scoped attention.poll (attention_poll_handler.poll(namespaces); wss_backend.attention, serve.zig:2455). So SH8's 'unify REST↔poll + add ?ns=' premise is MOOT — the poll IS the unified, scoped surface, and the scope is its `namespaces` param. Brain-side scope = done on main. Reframed work = the HELM must call attention.poll (→ SH9). Surfaced to user." }
      B: { status: "✓", deliverable: D-SVHELM-SH8-B, note: "2026-06-07: MOOT/SATISFIED — the WSS attention.poll IS the unified namespace-scoped surface on main (REST deleted #921). The helm now calls it with a namespaces scope (SH9). No REST↔poll unify needed. The scope-toggle UI control is a SH9 follow-on." }
      C: { status: "✗", deliverable: D-SVHELM-SH8-C, note: "zig test: ?ns=shell excludes oddjobz; ?ns=shell,oddjobz merges." }
      D: { status: "✗", deliverable: D-SVHELM-SH8-D }
      E: { status: "n/a", note: "Consumed by SH9." }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✗", deliverable: D-SVHELM-SH8-I }
      J: { status: "n/a" }
    done_when: "One snapshot path honours an operator-supplied namespace scope; isolation default holds (in-cartridge ⇒ just that namespace)."

  # ───────────────────────────────────────────────────────────────────
  - id: SH9
    name: "Svelte AttentionSurface render + interaction telemetry"
    note: |
      Port AttentionSurface.svelte + attention-api.ts (exist in
      archive/apps-loom-svelte) into the canonical neutral shell, rendering
      the scoped feed of {kind,score,ref,summary,[expiresAt],raw}. Wire
      POST /api/v1/attention/interact (tapped/opened/dismissed/acted-on/
      ignored) — the telemetry the SH11 learner will consume. Scope toggle UI
      (shell only ↔ + cartridge namespaces) lives here.
    axes:
      A: { status: "✓", deliverable: D-SVHELM-SH9-A, note: "2026-06-07 REWORKED: attention-api.ts now calls the WSS attention.poll over /api/v1/wallet (reuses oddjobz-query WssJsonRpcTransport). New AttentionSignal {kind,score,ref,summary,expiresAt?}; parseAttentionPoll tolerant (bare array OR {items}). AttentionSurface.svelte rewritten to the signal shape (summary/kind/score; urgency derived from score). ⚠ wire contract INFERRED (method/params/result envelope) — NOT live-verified; documented in the file header + needs a brain check. fetchSnapshot/recordInteract (deleted REST) removed; App.handleItemTap → signal.ref." }
      B: { status: "✓", deliverable: D-SVHELM-SH9-B, note: "2026-06-07: AttentionSurface renders the namespace-scoped poll (namespaces param, default ['shell']). The user-facing scope TOGGLE control (shell-only ↔ +cartridge namespaces) is not a UI widget yet — default scope only; toggle UI is a follow-on." }
      C: { status: "✓", deliverable: D-SVHELM-SH9-C, note: "2026-06-07: tests/attention-poll.test.ts (4) — parseAttentionPoll: bare array, {items} envelope, empty/non-array→[], junk-drop+coerce. 161 helm tests; svelte-check 0 errors; build green." }
      D: { status: "n/a", note: "Brain seams are SH7/SH8." }
      E: { status: "✓", deliverable: D-SVHELM-SH9-E, note: "2026-06-07: helm wired — AttentionSurface (home) polls attention.poll; App.handleItemTap routes signal.ref → oddjobz." }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a", deliverable: D-SVHELM-SH9-H, note: "2026-06-07: interaction telemetry (POST interact) was DELETED with the REST surface (#921); no poll-era endpoint. Dropped from the helm; deferred to SH11 (learning loop)." }
      I: { status: "✗", deliverable: D-SVHELM-SH9-I }
      J: { status: "n/a" }
    done_when: "The shell renders a live scoped attention feed with working scope toggle; interactions POST telemetry; updates over WSS."

  # ───────────────────────────────────────────────────────────────────
  - id: SH10
    name: "Brain+helm: tunable static attention weights"
    note: |
      Make scoring legible and operator-tunable BEFORE learning. Today
      GET /api/v1/attention/weights returns hardcoded weights and PUT is a
      no-op (attention_http.zig:6-7). Persist PUT as signed cells (operator
      hat), add a helm weight-map editor, and a "why is X above Y" inspector
      with per-class boost/suppress ("trades.job.* +20%", "newsletter.*
      suppress"). This is the legible-learning substrate the canon design
      (HELM-ATTENTION-SURFACE.md §2) requires before AS1-AS5.
    axes:
      A: { status: "n/a", deliverable: D-SVHELM-SH10-A, note: "DEFERRED by DECISION D15 (2026-06-07): skip weighting for now — the attention.poll sources self-score. Revisit static-tunable weights later. (weights_store + editor when wanted.)" }
      B: { status: "⚠", deliverable: D-SVHELM-SH10-B, note: "GET returns hardcoded; PUT is a no-op stub — make it persist." }
      C: { status: "✗", deliverable: D-SVHELM-SH10-C }
      D: { status: "✗", deliverable: D-SVHELM-SH10-D, note: "Persist + apply weights in the scorer." }
      E: { status: "✗", deliverable: D-SVHELM-SH10-E, note: "Weight editor + ranking explainer in the helm." }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✗", deliverable: D-SVHELM-SH10-I }
      J: { status: "n/a" }
    done_when: "Operator edits weights + per-class boost/suppress; PUT persists (signed, audit-trailed); ranking respects them and is inspectable/rollback-able."

  # ───────────────────────────────────────────────────────────────────
  - id: SH11
    name: "Attention learning loop (AS1–AS5)"
    note: |
      The full learned-weights loop from docs/design/HELM-ATTENTION-SURFACE.md.
      LARGEST track — sub-phased; the loop may work one AS per several ticks.
      Not required for the SH12 golden slice (slice proves surface + tunable
      static weights); this is the optimisation layer.
        AS1 — interaction telemetry persisted as signed cells (consumes SH9 telemetry).
        AS2 — weight learner: per-factor drift, per-class boost/suppress,
              per-context profile (in-field vs at-desk); bounded (re-weights
              existing factors, never invents new ones).
        AS3 — new signal-source scoring branches (goal-alignment via
              embeddings, deadline, etc. — the 39A placeholders).
        AS4 — external-signal adapters (weather, Surfline, LI proposals,
              capability-state changes).
        AS5 — delivery beyond the panel: mobile push / voice "what's next".
    axes:
      A: { status: "n/a", deliverable: D-SVHELM-SH11-A, note: "DEFERRED by DECISION D15 (2026-06-07): the learned AS1-AS5 loop is out of scope for now (and needs a telemetry endpoint, deleted with the REST surface, rebuilt first). Sources self-score. Revisit if/when learning is wanted." }
      B: { status: "✗", deliverable: D-SVHELM-SH11-B, note: "Learner feeds weights back into the scorer (SH10 store)." }
      C: { status: "✗", deliverable: D-SVHELM-SH11-C, note: "Determinism + rollback tests; learned drift is inspectable." }
      D: { status: "✗", deliverable: D-SVHELM-SH11-D }
      E: { status: "✗", deliverable: D-SVHELM-SH11-E, note: "AS5 push/voice delivery surfaces." }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "✗", deliverable: D-SVHELM-SH11-H, note: "acted-on telemetry ties verb dispatch back to scoring." }
      I: { status: "✗", deliverable: D-SVHELM-SH11-I }
      J: { status: "n/a" }
    done_when: "Operator behaviour drifts weights legibly (inspect + rollback via REPL); AS1-AS5 each shipped or explicitly deferred with a note."

  # ───────────────────────────────────────────────────────────────────
  - id: SH12
    name: "Golden slice — operator acceptance of the whole vision"
    note: |
      The end-to-end proof, run on the canonical loom-svelte build against a
      live brain (per SH0 tape):
        1. Stand up pure brain shell (empty extensions/) → helm shows neutral
           DO|TALK|FIND, identity in TALK + me, shell-native attention feed.
        2. Activate oddjobz → its surface + verbs + attention namespace appear.
        3. Activate a SECOND (ecommerce) cartridge, dedicated mode → surface
           TOTALLY switches, ZERO evidence of oddjobz.
        4. Scope toggle → cross-business operational view (shell + both
           namespaces) in the attention feed.
        5. Tune a weight → ranking visibly responds, inspectable.
      This is the operator-acceptance gate the whole matrix exists to pass.
    axes:
      A: { status: "n/a" }
      B: { status: "✗", deliverable: D-SVHELM-SH12-B, note: "Wire the slice harness/tape." }
      C: { status: "✗", deliverable: D-SVHELM-SH12-C, note: "e2e run recorded green on canonical build + live brain." }
      D: { status: "n/a" }
      E: { status: "n/a" }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "✗", deliverable: D-SVHELM-SH12-H, note: "Verb dispatch flows end-to-end for both cartridges." }
      I: { status: "✗", deliverable: D-SVHELM-SH12-I }
      J: { status: "n/a" }
    done_when: "All five tape steps pass on the canonical loom-svelte build against a live brain; no oddjobz leakage in the ecommerce surface."

  # ───────────────────────────────────────────────────────────────────
  - id: SH13
    name: "Docs / render / autonomous-loop entry"
    note: |
      Cross-cutting, bumped as tracks land:
        - docs/canon/render/svelte-helm-to-roadmap.ts (mirror
          canonicalization-to-roadmap.ts) → docs/prd/SVELTE-HELM-ROADMAP.md.
        - apps/loom-svelte CANON-STATUS.md documenting the inversion.
        - This matrix's loop_protocol kept accurate as worktree/branch
          realities change.
    axes:
      A: { status: "✓", deliverable: D-SVHELM-SH13-A, note: "2026-06-07: docs/canon/render/svelte-helm-to-roadmap.ts (bun + yaml, mirrors canonicalization-to-roadmap) — track×axis status table + progress headline + done-when list." }
      B: { status: "✓", deliverable: D-SVHELM-SH13-B, note: "2026-06-07: renders docs/prd/SVELTE-HELM-ROADMAP.md (current: 36% — 29 ✓ / 13 ⚠ / 39 ✗ of 81 live axes)." }
      C: { status: "n/a" }
      D: { status: "n/a" }
      E: { status: "n/a" }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✓", deliverable: D-SVHELM-SH13-I, note: "2026-06-07: apps/loom-svelte/CANON-STATUS.md documents the inversion + D10/D11/D12/D13 + gaps; roadmap rendered. loop_protocol stays accurate." }
      J: { status: "n/a" }
    done_when: "Roadmap renders from this matrix; loop_protocol verified against the live worktree."

  # ───────────────────────────────────────────────────────────────────
  - id: SH14
    name: "Hat-gated verbs (operator vs admin)"
    note: |
      Added 2026-06-07 (DECISION D11). The verb shelf is scoped by the
      ACTIVE HAT, on top of the SH2-B pyramid+overlay composition:
        - operator hat → the base helm verbs (default CSD pyramid + any
          operator-scoped cartridge overlay verbs).
        - admin hat → ALSO the managerial verbs (manage the business
          website, the chat widget, the policies that feed the widget,
          etc.), declared by the owning cartridge/surface with role:"admin".
      Mechanism (no new pipe — rides the SH1/SH2 overlay):
        1. UiVerb gains an optional `role` ("operator" default | "admin")
           on BOTH sides — brain info_http/loader (SH1 addendum) +
           loom-svelte extensions-api UiVerb (SH2 addendum).
        2. The Dock filters composed verbs by the active hat: show a verb
           iff its role is visible to the current hat (operator sees
           operator-only; admin sees operator+admin).
        3. Active hat comes from loom-svelte's existing HatSwitcher
           (cert-derived per canon C12 once that lands; label-based today).
      Managerial admin verbs (website/widget/policy) are declared by their
      owning cartridge — e.g. the chat-widget cartridge (canon C4 CW-1) and
      the site-config surface (SiteConfigEditor.svelte) — with role:"admin".
    deps: "SH2-B (pyramid+overlay composition), SH5 (hat/identity context)"
    axes:
      A: { status: "✓", deliverable: D-SVHELM-SH14-A, note: "2026-06-07: per-verb role done BOTH sides. Helm: extensions-api UiVerb.role (HatRole) + normalizeVerb default 'operator'. Brain: extension_manifest_loader UiVerbDecl/UiVerbJson role (default operator, fail-safe coerce) + info_http UiVerb.role + emit + serve.zig map + tests. zig build + zig build test green; helm 148 tests + svelte-check 0 errors." }
      B: { status: "✓", deliverable: D-SVHELM-SH14-B, note: "2026-06-07: shelf-compose.filterVerbsByHatRole(verbs, hatRole) — operator hides admin verbs, admin shows both, missing role→operator (fail-safe). Dock gains hatRole prop + applies the filter to the overlay verbs. Active role sourced via fetchActiveHatRole (/api/v1/info hat.role, SH-era bearer-session source per D12) → App.activeHatRole → Dock. (Me-panel switcher UI is SH5; the filter works now off the bearer role.)" }
      C: { status: "✓", deliverable: D-SVHELM-SH14-C, note: "2026-06-07: filterVerbsByHatRole tests (operator hides admin / admin shows both / missing→operator) in shelf-compose.test.ts; brain verb-role + hat-role tests (loader + info_http + 5 bearer_tokens). 151 helm tests + svelte-check 0 errors + build; zig build test green." }
      D: { status: "✓", deliverable: D-SVHELM-SH14-D, note: "2026-06-07: per-verb role (loader+info_http+serve+tests) + per-hat role (bearer_tokens TokenRecord role, issueWithRole, JSONL replay back-compat, /api/v1/info hat.role emit, 5 bearer tests + hat-block test) + CLI `brain bearer issue --role operator|admin` (cli/bearer.zig parse + args_json; bearer_tokens_handler reads role → issueWithRole). zig build test green (unix_socket conformance flake confirmed env-only, unrelated). Helm role surfacing via fetchActiveHatRole (/api/v1/info hat.role) — SH-era bearer-session source per D12; C12 cert-derived roles later." }
      E: { status: "✓", deliverable: D-SVHELM-SH14-E, note: "2026-06-07: helm wired — extensions-api UiVerb.role + normalizeVerb + fetchActiveHatRole (/api/v1/info hat.role); Dock filterVerbsByHatRole applied to overlay verbs; App holds activeHatRole + passes to Dock." }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "⚠", deliverable: D-SVHELM-SH14-I, note: "2026-06-07: DECISIONS D11/D12/D13 recorded; CONTRACTS §1 verb shape gains role. TODO: CONTRACTS hat block gains role (with SH14-D hat-role)." }
      J: { status: "n/a" }
    done_when: "Switching operator↔admin hat changes the shelf: admin reveals the managerial verbs (website/widget/policy), operator hides them; verbs carry role end-to-end (cartridge.json → brain → helm)."

  # ───────────────────────────────────────────────────────────────────
  - id: SH15
    name: "Core read-path re-wire — oddjobz reads onto generic cell.query/cell.get"
    note: |
      Added 2026-06-09. The handoff's CORE mission: move the helm's cell
      READS off the retired oddjobz-specific graph-walk verbs
      (oddjobz.list_sites / list_customers / find_jobs_at_site /
      find_jobs_for_customer / get_site / get_customer / get_job /
      find_attachments_for_job) onto the brain's GENERIC, owner-bound
      cell-DAG primitive: cell.query {typeHash, filter?} / cell.get
      {typeHash, cellRef}, keyed by the oddjobz.{site,customer,job,
      attachment}.v2 aliases. The old verbs were already DELETED from the
      brain's WSS dispatch (cartridges/.../wss_wallet.zig) — so the helm was
      BROKEN against the live brain (every read → -32601 method not found).
      This re-wire is a correctness fix, not polish.
      Mechanism: the brain's cell.query/cell.get delegate to cartridge-
      registered decoders (cartridges/oddjobz/.../registration.zig) that
      reuse the SAME element encoders (siteToJson/jobToJson/…) + collection/
      singular envelope keys the old verbs emitted — so the helm's row types,
      envelope-unwrap, and all call sites (joblist-fetch, *-pivot, JobDetail)
      are unchanged. cell.query enumerates via cells_by_type → returns the
      canonical OWNER-BOUND v2 cells only (the old verbs returned mixed
      v1+v2): the intended clean break. The 66 legacy Gmail leads (minted as
      v2) now surface uniformly with widget leads.
      Follow-ups (separate PRs, NOT this track's done_when): live refresh via
      cell.created/customer.upserted push subscription; a source pill
      (widget|email|…) from job-payload provenance; live round-trip verify
      against a running brain (fold into SH12 golden slice).
    deps: "SH2 (helm toolchain up); brain-side cell.query/decoders already on main (canon C4 PR-J2/J4)"
    axes:
      A: { status: "n/a", note: "Re-wire of an existing client, not a file move." }
      B: { status: "✓", deliverable: D-SVHELM-SH15-B, note: "2026-06-09: src/lib/oddjobz-query.ts OddjobzQueryClient's 8 methods now call cell.query (sites/customers unfiltered; jobs filter {siteRef}/{customerRef}; attachments filter {jobRef}) + cell.get (site/customer/job by cellRef) on the oddjobz.*.v2 aliases (ODDJOBZ_TYPE consts). Envelope-unwrap + row types unchanged. Header + per-row docstrings rewritten." }
      C: { status: "✓", deliverable: D-SVHELM-SH15-C, note: "2026-06-09: tests re-pinned to the new wire — tests/oddjobz-query.test.ts (method+params per call), tests/joblist-fetch.test.ts (CountingTransport routes by typeHash; countQuery/countGet helpers; N+1 contract = 1 site-query + 1 customer-query + 2 job-queries), tests/customer-pivot.test.ts (getCustomer → cell.get). 161/161 helm tests pass; svelte-check 0 errors; vite build ✓." }
      D: { status: "✓", deliverable: D-SVHELM-SH15-D, note: "2026-06-09: brain-side seam ALREADY on main (not this PR): cell_query_handler.zig generic primitive + handleCellQuery/handleCellGet WSS dispatch (param contract typeHash/filter/cellRef) + oddjobz decoders in registration.zig (aliases, collection/singular keys, allow_unfiltered_list, matches_filter siteRef/customerRef/jobRef). Verified by reading source; the old graph-walk verbs confirmed removed from the WSS dispatch table." }
      E: { status: "✓", deliverable: D-SVHELM-SH15-E, note: "2026-06-09: helm-side migration landed (this PR)." }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a", note: "Reads are not verb-dispatch; actions stay on /api/v1/repl FSM verbs." }
      I: { status: "✓", deliverable: D-SVHELM-SH15-I, note: "2026-06-09: oddjobz-query.ts header + row + method docstrings rewritten to the cell.query/cell.get contract + brain references; this matrix track added + roadmap re-rendered." }
      J: { status: "✓", deliverable: D-SVHELM-SH15-J, note: "2026-06-09: zero old query-verb strings remain in src/ (grep clean); brain-side old verbs already retired upstream. (entity_cell_hash in the voice-note route is a different, live contract — not the retired entity_cell read shape.)" }
    done_when: "All oddjobz cell reads in the helm flow through cell.query/cell.get on oddjobz.*.v2; no old graph-walk verb strings in src/; helm gate green. (Live refresh + source pill + live round-trip verify are follow-ups.)"

  # ───────────────────────────────────────────────────────────────────
  - id: SH16
    name: "Helm live UX — cell.created/customer.upserted refresh + lead source pill"
    note: |
      Added 2026-06-09. The two SH15 follow-ups, both helm-client-side:
      LIVE REFRESH — the cell.query-backed lists now refresh on the brain's
      canonical mint/upsert push events (delivered as helm.event over the
      wallet WSS, HelmEventStream):
        - jobsTick bumps on `cell.created` (＋ job.transitioned) → newly-
          ingested leads (widget funnel / `do import legacy lead`) appear
          without a manual reload (previously only FSM moves refreshed).
        - customersTick bumps on `customer.upserted` — the event the brain
          ACTUALLY emits (helm_event_broker.zig); the prior wiring listened
          for `customer.created`, which is never emitted, so customer live
          refresh was silently dead. ＋ cell.created.
        Over-refetch is harmless (coarse "something changed" → cheap re-query).
      SOURCE PILL — job rows show a provenance pill (email | widget | other)
      derived from the PRIMARY customer's sourceProvenance.providerId (the job
      cell has no source field of its own); legacy Gmail leads read "email",
      widget leads "widget", operator-created show none. New pure module
      lib/job-source.ts; providerId threaded through PrimaryCustomer.
    deps: "SH15 (cell.query read path); brain helm_event_broker cell.created/customer.upserted (already on main)"
    axes:
      A: { status: "n/a", note: "Client-side feature on existing modules + one new pure lib." }
      B: { status: "✓", deliverable: D-SVHELM-SH16-B, note: "2026-06-09: jobs-store JOBS_TICK_EVENTS {job.transitioned, cell.created}; customers-store CUSTOMERS_TICK_EVENTS {customer.upserted, customer.created, cell.created}; lib/job-source.ts jobSourceFromProvider; PrimaryCustomer.providerId (resolvePrimaryCustomer); JobList source pill render + CSS." }
      C: { status: "✓", deliverable: D-SVHELM-SH16-C, note: "2026-06-09: +14 tests (tests/jobs-store, tests/customers-store live-tick {upserted,cell.created}, tests/job-source mapping, joblist-graph providerId). 175/175 pass; svelte-check 0 errors; build green. Previously-ungated store tests + new files added to the pnpm test gate." }
      D: { status: "n/a", note: "Brain already emits cell.created (anchor/mint) + customer.upserted (helm_event_broker)." }
      E: { status: "✓", deliverable: D-SVHELM-SH16-E, note: "2026-06-09: helm-side landed (PR #949)." }
      F: { status: "n/a" }
      G: { status: "n/a" }
      H: { status: "n/a" }
      I: { status: "✓", deliverable: D-SVHELM-SH16-I, note: "2026-06-09: module docstrings (jobs-store/customers-store/job-source) + this matrix track + roadmap re-rendered." }
      J: { status: "n/a", note: "Fixes the dead customer.created listener in passing; no parallel path left behind." }
    done_when: "Newly-minted leads appear in the helm without reload (cell.created); customer changes refresh (customer.upserted); job rows show a source pill distinguishing email vs widget leads; helm gate green."

```
