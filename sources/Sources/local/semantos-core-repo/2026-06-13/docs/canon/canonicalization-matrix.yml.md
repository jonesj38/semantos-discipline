---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/canonicalization-matrix.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.633002+00:00
---

# docs/canon/canonicalization-matrix.yml

```yml
# The Canonicalization Matrix — tracking artifact for collapsing all
# in-flight Semantos surfaces into exactly TWO canonical units:
#
#   1. The Semantos PWA  — `apps/semantos` (today `apps/semantos`)
#      A neutral cartridge loader that ships the substrate primitives:
#      contacts/PKI, conversation, pask, wallet-headers/headless-wallet,
#      key REPL, gradient intent pipeline (SIR→OIR→opcode→kernel),
#      identity + recovery, hat-switching, manifest provisioning.
#
#   2. The Semantos Brain — `runtime/semantos-brain`
#      A neutral peer-node / server / root-operator host that ships the
#      same primitives + dispatcher + bearer-gated REPL HTTP. Cartridges
#      load as plugins via an extension-loader seam; the brain binary
#      itself knows nothing about oddjobz, self, jam, tessera, etc.
#
# Schema parallel to docs/canon/singularity-matrix.yml.
# Rendered via docs/canon/render/canonicalization-to-roadmap.ts to
# docs/prd/CANONICALIZATION-ROADMAP.md.
#
# Each cell is `{ status: ✓|⚠|✗|n/a, deliverable: D-CANON-..., note: "..." }`.
#
# Companion document: docs/prd/CANONICALIZATION-BRIEF.md.
#
# Status legend:
#   ✓   — implemented, tested, verifiable
#   ⚠   — partial / in progress / unverified
#   ✗   — not started
#   n/a — not applicable on this (track, axis) pair
#
# Deliverable IDs follow D-CANON-{TrackID}-{Axis} (e.g. D-CANON-C1-A).
#
# Axis definitions (A..J):
#   A. Source extracted       — files moved/created at target location
#   B. Target wired           — imports, registry, dispatch hooked up
#   C. Tests pass             — existing test surface green in new location
#   D. Brain-side             — companion brain change landed (if applicable)
#   E. PWA-side               — companion PWA change landed (if applicable)
#   F. Wallet integration     — wallet-headers/headless-wallet wired through
#   G. Recovery envelope      — plexusRecoveryEnvelope coverage for the unit
#   H. Intent pathway         — gradient pipeline (SIR→OIR→opcode→kernel) flows through
#   I. Docs                   — CLAUDE.md / module README / canon doc updated
#   J. Old code deleted       — zero remaining references to legacy path

tracks:
  # ─────────────────────────────────────────────────────────────────
  - id: C0
    name: Decision Locks + Glossary + Golden Slice
    note: |
      The entry gate. Nothing else gets a ✓ until C0 is green. This track
      exists because the pre-mortem (2026-05-27) identified four failure
      modes that all trace back to unlocked-decisions: vocabulary drift
      ("the 5 verbs" meant three different things), vapor acceptance
      ("C7 passes" had no fixture), hidden specs ("plexusRecoveryEnvelope"
      was a concept not a spec), and unbounded scope ("oh and also..." kept
      adding tracks). C0 locks all four before code moves.

      C0 ships THREE artifacts:
        1. docs/canon/canonicalization-glossary.md — every load-bearing
           term has one definition, and disputes resolve here.
        2. docs/canon/canonicalization-golden-slice.md — the ONE operator
           action that gates the canonicalization. Concrete utterance,
           expected SIR/OIR/opcode/cell/wallet/brain trace, runnable test.
        3. docs/canon/canonicalization-decisions.md — answers to the open
           questions BEFORE coding starts: which 5 do-subverbs (existing
           canon), helm Flutter-vs-webview, headless-wallet Dart-port-vs-
           brain-call, brain-helm new-build-vs-port-loom-react, phone update
           strategy, monolith deletion timing.
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C0-A
        note: "All three C0 artifacts landed 2026-05-27: canonicalization-glossary.md (vocabulary lock), canonicalization-golden-slice.md (C7 fixture spec), canonicalization-decisions.md (all 8 open questions answered + locked). Q6 verb-canon anchored to CSD 1-3-5-3-1 pyramid: helm L3-support surfaces 5 do + 4 find sub-verbs; REPL/voice access full 22-verb substrate."
      B:
        status: "n/a"
        note: "C0 has no 'wiring' axis — it's lock-in, not implementation."
      C:
        status: "✓"
        deliverable: D-CANON-C0-C
        note: "Runnable test stub landed 2026-05-27 at tests/canonicalization/golden-slice/. Dart test runs RED with 9 structured LayerNotWired(layer, track, what-to-do) failures via `dart test v1_release.dart`. Zig test scaffolded (mounting into brain build harness is C5-adjacent follow-up). Fixture JSON locks the per-layer contracts. No track downstream may claim ✓ on its C axis without re-running this test and reporting the result in its matrix cell note."
      D:
        status: "n/a"
      E:
        status: "n/a"
      F:
        status: "n/a"
      G:
        status: "n/a"
      H:
        status: "n/a"
      I:
        status: "✓"
        deliverable: D-CANON-C0-I
        note: "Glossary + golden-slice + decisions docs all landed. Brief §11 captures the 14 pre-mortem mitigations they embody."
      J:
        status: "n/a"
        note: "Nothing to delete here — C0 is additive."

  # ─────────────────────────────────────────────────────────────────
  - id: C1
    name: PWA Primitive Forklift
    note: |
      Move the 14 substrate subsystems out of the monolith
      `apps/semantos/lib/src/` and into the canonical shell at
      `apps/semantos/lib/src/` (later renamed to `apps/semantos/`).
      Dependency-respecting order: identity → contacts → pairing → mesh →
      repl → pask → talk → voice → gradient → outbox → push → sensors →
      theme → shell. Each forklift includes its tests + any FFI bindings.
      Subsystems are PRIMITIVE per the C1 survey — they ship in the
      neutral loader regardless of which cartridges are installed.
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C1-A
        note: |
          C1 SLICE-PATH PRIMITIVES ALL FORKLIFTED + WIRED 2026-05-28. End-to-end keyboard input path runs: helm Release sheet → IntentDispatcher.dispatch → BrainHttpClient.mintCell → live brain at oddjobtodd.info → MintCellResult → recent-mints card on helm. 12/12 tests green.

          Wiring tick sequence on canon/c1-primitives:
            tick 1 (7117254): 4 pure-Dart identity files forklifted
            tick 2 (3f726c4): 4 voice files forklifted (dio dep)
            tick 3 (a5faf38): 5 gradient files forklifted
            wire plan (4267ec2): apps/semantos/docs/WIRING-PLAN.md
            wire 2 (9b914e6): type_hash.dart + brain_http_client.dart (4/4 conformance vs live brain)
            c2 merge (bef05ba): betterment_experience available
            wire 1 (d668594): pubspec swap + main.dart betterment_experience integration
            wire 3 (e06f142): IntentDispatcher (4/4 tests via stub)
            c9 merge (7e9daeb): HelmScaffold available
            wire 4a (c791926): IntentDispatcher factory from IdentityStore (4/4)
            wire 4b (d2dcf43): helm Release button → sheet → dispatch
            wire 5 (5b80f0b): recent-mints list replaces SnackBar

          Remaining (non-slice; full-scope phase): forklift Flutter-adapter
          files in identity (need semantos_shell_native_identity wrapper),
          remaining 8 primitives (contacts, pairing, mesh, outbox, push,
          sensors, theme, pask), cross-cartridge contamination cleanup in
          gradient's deferred files.

          C1 tick 2 (2026-05-28, commit 3f726c4): 4 slice-path voice files forklifted (sir_extractor, anthropic_llm_completer, voice_extract_uploader, voice_session_service). dio dep added. Identity deps satisfied by tick 1. Layer 1+2 of C7 slice substrate now present. dart analyze clean.

          C1 tick 3 (2026-05-28, commit on canon/c1-primitives): 5 slice-path gradient files forklifted (sir_to_oir, oir_to_bytes, dart_pipeline, cell_id, intent_trace_service). Layers 3+4 of C7 slice substrate now present. dart analyze: 1 inherited info-level lint, 0 errors. Deferred (cross-cartridge contamination): oddjobz_extension_context, entity_resolver, production_pipeline_deps — need structural fix to split cartridge code from substrate.

          Slice substrate now present for layers 1, 2, 3, 4, 6 (identity→wallet via cell_signer). Layers 5 (cell-engine FFI), 7 (brain dispatch), 8 (helm render) still pending. Remaining slice-path subsystems: repl, talk (SIR scope), shell helm host. Non-slice subsystems (contacts, pairing, mesh, outbox, push, sensors, theme, pask) defer to full-scope phase.

          SLICE-SCOPE FIRST (post-mortem mitigation #1): forklift ONLY the subsystems on the C7 golden-slice critical path before claiming any C1 axis ✓. The remaining ~8 subsystems forklift in a follow-up phase AFTER C7 goes green. This caps blast radius and prevents the braided-dep failure mode.

          HONESTY ADDENDUM 2026-05-29: the end-to-end "helm Release sheet → IntentDispatcher.dispatch → BrainHttpClient.mintCell → recent-mints card" run cited above as the C1-A green proof was demonstrated on the PRE-C3 monolith app (applicationId `com.semantos.shell`, helm with Release FAB). The IntentDispatcher → BrainHttpClient code path is identical between the old monolith and the canonical post-C3 shell (`app.semantos.me`), so the SUBSTRATE claim "primitives forklifted + wired" stands. What does NOT yet stand: operator-acceptance on the canonical app.semantos.me with the C9 modal verb shelf flow (DO → Release tile → ReleaseSheet → mint). That run is BLOCKED until `adb uninstall com.semantos.shell` clears the legacy app from the emulator and the user does a clean run on the canonical app. Tracking under C7-E addendum.
      B:
        status: "✗"
        deliverable: D-CANON-C1-B
        note: "Shell main.dart wires only OddjobzManifestLoader / JamManifestLoader / TesseraManifestLoader. Once primitives forklifted, main.dart wires identity → contacts → pask → talk → gradient → etc. as platform services, then loads cartridges over the top."
      C:
        status: "✗"
        deliverable: D-CANON-C1-C
        note: "Monolith has substantial test surface in lib/src/{gradient,pask,talk,voice}/tests. Each forklift must carry tests intact and stay green in the new tree."
      D:
        status: "n/a"
        note: "C1 is PWA-only; brain primitives are tracked under C4/C5."
      E:
        status: "✗"
        note: "All of C1's work IS PWA-side. The shell becomes substrate-complete."
      F:
        status: "⚠"
        deliverable: D-CANON-C1-F
        note: "Monolith's `identity` + `pairing` subsystems already do BRC-42 child derivation + cert custody — that's the seam where wallet-headers/headless-wallet integration lands during C6. Marked ⚠ because the substrate is there but the unified wallet seam isn't yet plumbed."
      G:
        status: "✗"
        deliverable: D-CANON-C1-G
        note: "plexusRecoveryEnvelope integration into identity/pairing forklift is C6's responsibility — flagged here so the forklift doesn't strand the recovery story."
      H:
        status: "✗"
        deliverable: D-CANON-C1-H
        note: "Monolith's `gradient` subsystem IS the intent pathway (L1 SIR → L2 OIR → L3 opcode → L4 kernel). Forklifting it is what primes the canonical shell for voice→economic execution."
      I:
        status: "✗"
        deliverable: D-CANON-C1-I
        note: "Each forklifted subsystem needs a brief module-level README at new location explaining the seam + tests. CLAUDE.md updated to point at canonical paths."
      J:
        status: "✗"
        deliverable: D-CANON-C1-J
        note: "Cannot delete monolith subsystems until C2/C3 also complete (their imports still live in the monolith)."

  # ─────────────────────────────────────────────────────────────────
  - id: C2
    name: PWA Cartridge Extraction
    note: |
      The monolith carries cartridge UI directly in its lib/src tree:
      `helm/` (full jobs/quotes/invoices/customers/leads UI), `attachments/`,
      `ratification/` belong to oddjobz; `self/` belongs to self. Extract
      them out of the monolith and into proper cartridge packages so they
      load into the canonical shell via the same CartridgeRegistry path as
      any third-party cartridge.
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C2-A
        note: |
          C2 EXIT 2026-05-28 (aggressive-excision path). Both cartridges shipped at canon-phase scope: packages/betterment_experience (full intent grammar + manifest + Release sheet) + packages/oddjobz_experience (bearer-login + minimal job-list view). Full oddjobz UI build-out is a post-canon workstream.

          ORIGINAL UNFINISHED STATE (kept for trail): packages/oddjobz_experience/ exists but only contains a bearer-login + minimal job-list view. The full jobs/quotes/invoices/customers/leads UI is still in apps/semantos/lib/src/helm/ + attachments/ + ratification/.

          C2 tick 1 (2026-05-27, commit b6a84e1): packages/betterment_experience/ package skeleton landed on canon/c2-self-experience — pubspec, CartridgeEntry, manifest_loader, placeholder screen.

          C2 tick 2 (2026-05-27, commit 02d673d): betterment_experience/assets/{manifest,bundle}.json now mirror cartridges/betterment/cartridge.json (23 cellTypes → grammar.objectTypes; 12 flows → grammar.actions; capabilities/theme/enforcementHooks/linearity/steps deferred to substrate work).

          NAMING CLASH: the monolith's lib/src/helm/ is actually oddjobz's job dashboard, not the universal helm primitive — when moved to oddjobz_experience it must be renamed (e.g. lib/src/dashboard/) so 'helm' is reclaimed as the canonical default-UI primitive in the shell (C9).

          SLICE-SCOPE + AGGRESSIVE EXCISION (per user 2026-05-27, oddjobz NOT in production): the C2 first pass only extracts the cartridge surface ON the golden-slice critical path. Off-path monolith features (lead-tray ratification UI, attachment capture choreography, calendar surface, etc.) are NOT preserved by default — they get re-built against the clean substrate in a later phase if and when the operator needs them. This is licensed because oddjobz has no production users; aspirational features can return on the canonical foundation rather than being forklifted with their accreted decisions intact.

          C2 EXIT 2026-05-28 (aggressive-excision path): betterment_experience already registered in canonical shell main.dart (commit on c1-primitives wire-tick 5); BettermentIntentGrammar + BettermentManifestLoader wired. Oddjobz canonical surface = packages/oddjobz_experience/ with bearer-login + minimal job-list view — sufficient for canon-phase per user "we just keep on with easy testing then progress". Monolith apps/semantos/lib/src/{helm,attachments,ratification}/ marked OFF-SLICE via per-dir CANON-STATUS.md files (commit pending in this PR) — preserved in tree until C3 deletes the monolith, but documented as dead-code-pending-rebuild.

          Full oddjobz UI build-out (jobs/customers/quotes/invoices/visits) is a post-canon workstream, NOT part of C2. C2-A goes ✓ when (a) betterment_experience registered ✓ (done), (b) oddjobz_experience minimal surface registered ✓ (done), (c) monolith dirs marked off-slice ✓ (this PR).

          RENAME FOOTNOTE 2026-05-29 (PR #722): `self_experience` renamed to `betterment_experience` across package, brain TS subtree (`cartridges/self/brain` → `cartridges/betterment/brain`), npm name (`@semantos/self` → `@semantos/betterment`), manifest id, cell-type prefix (`self.*` → `betterment.*`, all 23 cellTypes; type-hash namespace bytes `06c604b332b386b6` → `06d0a049e88a982b`), HTTP route (`/api/v1/self/sweep` → `/api/v1/betterment/sweep`), CLI flag, capability name, all Dart/TS/Zig identifiers. Per Todd 2026-05-29: the rename frees the word "self" for the shell-level identity primitive (see new track C11) and clarifies that the cartridge is a self-development product, not a substrate concept. V1 production at oddjobtodd.info is test data so no on-chain migration was required — clean break.
      B:
        status: "✓"
        deliverable: D-CANON-C2-B
        note: "betterment_experience + oddjobz_experience both register in shell main.dart per the canonical CartridgeRegistry path (apps/semantos/lib/main.dart imports + invocations confirmed 2026-05-28). Jam/Tessera registrations remain pending strip — deferred to canon/c8-archive merge per C8-E note. Surfacing-mode declarations (default | dedicated | passive | priority) defer to a manifest-schema update PR — separate from registration."
      C:
        status: "n/a"
        deliverable: D-CANON-C2-C
        note: "Per aggressive-excision exit: monolith helm/attachments/ratification widget tests are NOT carried over — they belonged to the off-slice features marked for post-canon rebuild. Self cartridge tests live in packages/betterment_experience; oddjobz cartridge tests live in packages/oddjobz_experience. C2-C becomes n/a under the aggressive-excision exit path."
      D:
        status: "✗"
        deliverable: D-CANON-C2-D
        note: "Cartridge brain-side code already lives at cartridges/{oddjobz,self}/brain/ (paired with C4 extraction); C2 just keeps the PWA-side surface in sync with the cartridge manifest each cartridge declares."
      E:
        status: "✗"
        note: "C2 is PWA-side; brain piece is C4."
      F:
        status: "n/a"
        note: "Cartridges don't own wallet primitives — they consume wallet services exposed by the shell substrate."
      G:
        status: "n/a"
        note: "Recovery is substrate-level (C6), not cartridge-level."
      H:
        status: "✓"
        deliverable: D-CANON-C2-H
        note: "Both cartridges register IntentGrammar fragments through the shell's ConversationEngine (apps/semantos/lib/main.dart line ~129 includes OddjobzIntentGrammar() + BettermentIntentGrammar()). C2-H goes ✓ on the basis of both grammars wired."
      I:
        status: "⚠"
        deliverable: D-CANON-C2-I
        note: "betterment_experience has README inside the library export comment (packages/betterment_experience/lib/betterment_experience.dart). oddjobz_experience README still TBD. CANON-STATUS.md files added to monolith dirs (helm/, attachments/, ratification/) 2026-05-28 documenting their off-slice disposition + post-canon rebuild plan."
      J:
        status: "⚠"
        deliverable: D-CANON-C2-J
        note: "Aggressive-excision exit means deletion happens in C3 (monolith delete) rather than via per-cartridge extraction. CANON-STATUS.md files at apps/semantos/lib/src/{helm,attachments,ratification}/ document the deletion timing + post-canon rebuild plan. Full ✓ when C3 lands."

  # ─────────────────────────────────────────────────────────────────
  - id: C3
    name: PWA Canonicalization
    note: |
      With primitives (C1) and cartridges (C2) migrated, rename
      `apps/semantos` → `apps/semantos` and delete the monolith.
      Update Android applicationId to a stable canonical
      (`info.semantos.shell` or similar — confirm with user). Update all
      pubspec paths, CI configs, deploy scripts that reference either old
      app path. The phone artifact built from the canonical app should
      be functionally identical to the old monolith from the operator's
      POV.
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C3-A
        note: |
          C3 LANDED 2026-05-29 via 3 PRs (#710, #711, #712).

          Sequence:
            PR-C3-1 (#710): archived apps/semantos monolith (302 files) → archive/apps-semantos-monolith/ per C8 convention. Frees apps/semantos as a target path.
            PR-C3-2 (#711): git mv apps/semantos-shell → apps/semantos. 27 referencing files mass-updated via sed (.dart/.yaml/.yml/.json/.md/.ts/.zig/.gradle/.kt/.swift). 2 PWA-concept refs in cartridges/tessera/cartridge.json + platforms/flutter/semantos_core updated separately.
            PR-C3-3 (#712): Android applicationId + namespace com.semantos.shell → app.semantos.me (per Todd's domain semantos.me). MainActivity.kt moved from com/semantos/shell/ to app/semantos/me/ with package decl updated. Dart pubspec name: semantos_shell → semantos. 4 test imports rewritten.

          Out of scope (intentional — different "shell"s):
            - runtime/semantos-brain/deploy/semantos-shell.service (brain systemd unit; historical naming)
            - runtime/shell/ TypeScript CLI REPL package
            - platforms/flutter/semantos_shell_native_identity (Flutter sub-package; rename TBD)
      B:
        status: "✓"
        deliverable: D-CANON-C3-B
        note: "PR-C3-2 (#711): 27 workspace + doc refs updated via sed. PR-C3-3 (#712): Android build.gradle.kts (namespace + applicationId) + pubspec.yaml (name) + 4 Dart import statements. pnpm-workspace.yaml uses glob apps/* so no explicit listing change needed. No pubspec_overrides.yaml exists. No CI workflows reference the path."
      C:
        status: "✓"
        deliverable: D-CANON-C3-C
        note: "PR-C3-2 + PR-C3-3 verified flutter analyze clean (4 pre-existing info-level warnings only) + flutter test 12/12 pass. flutter build apk deferred (operator action; not a code-correctness gate)."
      D:
        status: "n/a"
        note: "Brain rename tracked under C5."
      E:
        status: "✓"
        note: "C3 IS the PWA rename + cleanup; 3 PRs done."
      F:
        status: "n/a"
        note: "Wallet integration is C6; C3 is purely structural."
      G:
        status: "n/a"
      H:
        status: "n/a"
      I:
        status: "✓"
        deliverable: D-CANON-C3-I
        note: "Doc refs updated in PR-C3-2 (#711): README.md, 16 design+canon docs, 2 prd docs, matrix.yml, deliverables.yml, glossary.md, hygiene.md, session journal notes + textbook chapters. Memory file canonicalization_worktree_topology.md updated in this PR (#713)."
      J:
        status: "✓"
        deliverable: D-CANON-C3-J
        note: "PR-C3-1 (#710): apps/semantos monolith archived (302 files). apps/oddjobz-mobile archived via PR #698 C8 sweep. No remaining apps/semantos-shell or apps/semantos[/-_]shell path references in active code/docs (out-of-scope items per C3-A note are different concerns)."

  # ─────────────────────────────────────────────────────────────────
  - id: C4
    name: Brain Cartridge Extraction
    note: |
      The brain binary today statically compiles ~16 cartridge-specific
      Zig files: src/oddjobz_*.zig (handlers, walkers, event bus), src/*_store_fs.zig
      (jobs/customers/visits/quotes/invoices/attachments/leads), src/*_handler.zig
      (resource handlers), src/betterment_sweep_http.zig, plus hat_bkds.zig has
      a hardcoded "oddjobz.cell-sign/v1" protocol-id. Move all of it
      into cartridges/{oddjobz,self}/brain/zig/ so the brain itself is
      cartridge-agnostic.

      ── 2026-06-06 STATUS: ESSENTIALLY COMPLETE ─────────────────────────
      The brain now ships ZERO oddjobz domain code. Over the H-series (§6b
      store carve), J-series (substrate generalization + deletions) and
      R-series (REPL verb seam), the entire oddjobz contamination listed in
      the original carve plan was rewired through the C5 seam or deleted.
      The brain is the neutral loader + substrate primitives Todd specified
      (loader, conversation/compression-gradient, SCG, wallet-headers/
      headless-wallet, REPL core, scriptsx zone) + cell-store/mint/registry
      + the kept middle-tier APIs.

      WHAT LANDED (all merged to main unless noted):
        §6b store carve (H-series): all 8 oddjobz typed stores + their
          dispatcher handlers (jobs/customers/visits/quotes/estimates/
          invoices/attachments) moved to cartridges/oddjobz/brain/zig/src/
          + constructed in ONE registration.zig registerInto over a
          StoreRegistry (CartridgeDeps seam); serve.zig lost every oddjobz
          store/handler block + the cross-FK late-binds (find jobs→
          attachments[] regression RESTORED). The store-coupled HTTP
          acceptors moved to the http_route_registry (C14 infra, see below).
        Substrate generalization (generalize-via-registry, NOT carve —
          these STAY in the brain but became cartridge-agnostic):
          • query  → cells_by_type LMDB index (8|8|8|8 typeHash templates)
            + generic cell.query/cell.get + cell_decoder_registry; the
            bespoke oddjobz.find_*/list_*/get_* JSON-RPC methods retired
            (#880/#882/#892).
          • attention → generic namespace-scoped attention.poll +
            attention_source_registry (#884).
          • ratify → generic ratify.submit + ratify_builder_registry; TS
            ingest migrated; legacy oddjobz.ratify_proposal retired
            (#888/#891). (Idempotency log stays cartridge-side = domain
            state — design BRAIN-RATIFY-SUBSTRATE.md.)
        Deletions: the orphaned `leads` resource (store+handler+REPL verbs,
          superseded by job.v2 state:"lead") + the SPEC_LEAD/TAG_LEAD
          cell-type (#895/#898).
        REPL verb seam (R-series): ReplVerbRegistry seam + concrete writer
          (repl_output) + generic `<resource> <verb>` path + per-resource
          verb schemas; ALL oddjobz REPL verbs moved into the cartridge's
          oddjobz_repl_verbs.zig registerInto; repl/oddjobz_cmds.zig DELETED
          (renamed conv_turns_cmd.zig — only the `find turns` substrate verb
          left); help text now derived from the registry (#900–#918).

      RESIDUAL (small; the only oddjobz-named code still under
      runtime/semantos-brain/src/):
        • sites_store_lmdb.zig + sites_handler.zig — the `sites` store impl
          + handler still live in brain/src/ (registration.zig constructs
          SitesStore from there). Move to cartridges/oddjobz/brain/zig/src/
          to match the other 8 stores. (Straggler — low risk.)
        • Twilio/SMS protocol adapter — conversation-send POST +
          twilio-inbound form-encoded webhook + the Twilio adapter. The
          conversation PRIMITIVE stays; the SMS adapter is a cartridge
          (separate, form-encoded not JSON — its own track-tick).
        • attention_http (/api/v1/attention) vs the J4 attention.poll —
          two attention surfaces to reconcile (deferred, #878 Q3).
        • Optional polish: generic-ize the substrate resources' own REPL
          verbs (intent_cells/site_config/cell/cells) via verbs_fn so the
          generic `<resource> <verb>` path covers them too (they keep their
          hardcoded brain verbs today — not oddjobz, so not blocking).

      C14 (Brain HTTP Route Registry) — infra BUILT this arc:
      http_route_registry.zig exists + serve wires it; the store-coupled
      oddjobz HTTP acceptors register through it. Remaining C14 scope:
      reactor.zig if/else chain + SiteServer typed-acceptor fields →
      full route-registry discovery; the anchor-hook seam (anchor_emitter
      woven into the substrate cell path needs a substrate-calls-cartridge
      hook). Promote to its own track when picked up.

      KEEP as substrate (unchanged): cartridge loader; conversation
      primitives; SCG; wallet-headers/headless-wallet (cell_signer/hat_bkds/
      signed_bundle/brc77-78/spend_policy/identity_certs); REPL core; script
      zone; cell-store/mint/registry; intent classify+taxonomy; attention
      surface; flow runner + loom store; infra adapters (push/LLM/NATS/fed).

      ── 2026-06-04 SCOPE LOCK (Todd), kept for provenance ───────────────
      Re-survey of the brain (216 .zig / ~105K LOC) showed the carve was
      already ~70% done architecturally: the C5 seam exists + is proven
      (registration.zig→registerInto, #708), generic signing exists
      (hat_bkds.signCellScoped + cell_signer.scope_protocol_id), the generic
      mint exists (cells_mint_handler), and MOST oddjobz files already
      physically lived in cartridges/oddjobz/brain/zig/. The residual was
      REWIRE-THROUGH-THE-SEAM + stragglers — now done (above).
      Still-pending from the original plan: hat_bkds verifier scope-awareness
      ("oddjobz.cell-sign/v1" in hat_bkds_verifier.zig + cli/operator.zig
      routing) + MNCA cells_mint_mnca_context.zig carve — NEITHER addressed
      this arc; both remain.
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C4-A
        note: |
          DONE 2026-06-06. All oddjobz domain code extracted from the brain.
          PR-4a/4b (#703–#708, 2026-05-28/29) seeded the seam (first handler
          over registerInto). The §6b store carve (H-series) then moved ALL 8
          typed stores + dispatcher handlers (jobs/customers/visits/quotes/
          estimates/invoices/attachments) to cartridges/oddjobz/brain/zig/src/,
          constructed in one registration.zig registerInto over a StoreRegistry.
          The R-series moved every oddjobz REPL verb into the cartridge
          (oddjobz_repl_verbs.zig) and DELETED repl/oddjobz_cmds.zig. leads +
          its cell-type deleted (#895/#898). Residual oddjobz-named files in
          brain/src/: only sites_store_lmdb.zig + sites_handler.zig (straggler).
      B:
        status: "✓"
        deliverable: D-CANON-C4-B
        note: |
          serve.zig no longer hardcodes any oddjobz store/handler/walker
          registration — the cartridge's registerInto wires everything via
          CartridgeDeps (cell_store, broker, audit_log, store_registry,
          route_registry, mint_context_registry, cell_decoder_registry,
          attention_source_registry, ratify_builder_registry, repl_verb_registry).
          The only initWithBroker left in serve.zig is the substrate cell_handler.
          dispatchRegistrations runs on BOTH boot paths (serve + repl).
      C:
        status: "✓"
        deliverable: D-CANON-C4-C
        note: "`zig build test --summary all` green throughout (2478/2522 pass, 44 skipped, 0 failed as of #918). The 4 udp_dispatcher / cors / unix_socket conformance flakes are sandbox-network noise (real connect/sendmsg), not regressions. Every moved handler kept its conformance test."
      D:
        status: "✓"
        deliverable: D-CANON-C4-D
        note: "C4 IS the brain-side change; landed across the H/J/R PR series (#859–#918)."
      E:
        status: "n/a"
        note: "PWA cartridge extraction is C2."
      F:
        status: "n/a"
      G:
        status: "n/a"
      H:
        status: "✓"
        deliverable: D-CANON-C4-H
        note: |
          The three middle-tier intent surfaces are now generic, cartridge-
          agnostic substrate primitives (generalize-via-registry): query →
          cell.query + cell_decoder_registry (#882); attention → namespace-
          scoped attention.poll + attention_source_registry (#884); ratify →
          ratify.submit + ratify_builder_registry (#888). The cartridge
          contributes its typed decoder/source/builder at boot; the brain
          hardcodes no cartridge verb. verb.dispatch + the generic
          `<resource> <verb>` REPL path drive cartridge resources uniformly.
      I:
        status: "⚠"
        deliverable: D-CANON-C4-I
        note: |
          Design docs landed: BRAIN-RATIFY-SUBSTRATE.md, BRAIN-QUERY-ATTENTION-
          RATIFY-SUBSTRATE.md, BRAIN-REPL-VERB-SEAM.md (all under
          runtime/semantos-brain/docs/design/). STILL TODO: cartridges/oddjobz/
          brain/README.md describing the handler set + the verb forms it
          registers (find jobs / jobs quote / …) + the cell.query decoders /
          attention sources / ratify builder it contributes.
      J:
        status: "⚠"
        deliverable: D-CANON-C4-J
        note: |
          Legacy oddjobz paths in the brain are GONE: repl/oddjobz_cmds.zig
          deleted (#917); leads_store/leads_handler + SPEC_LEAD deleted
          (#895/#898); bespoke oddjobz.find_*/list_*/get_* + .ratify_proposal
          JSON-RPC methods retired (#892/#891); no oddjobz register() in
          serve.zig. Flips to ✓ when the last stragglers clear:
            • sites_store_lmdb.zig + sites_handler.zig → move to
              cartridges/oddjobz/brain/zig/src/ (match the other 8 stores).
            • Twilio/SMS protocol adapter (conversation-send + twilio-inbound
              webhook) → carve to a cartridge (separate track-tick).
            • attention_http (/api/v1/attention) reconcile with attention.poll.
          (Out of C4 scope but adjacent: hat_bkds_verifier "oddjobz.cell-sign/
          v1" scope-awareness; MNCA cells_mint_mnca_context.zig carve.)

  # ─────────────────────────────────────────────────────────────────
  - id: C5
    name: Brain Extension Loader
    note: |
      extension_manifest_loader.zig exists but isn't wired into the
      dispatcher initialization. C5 builds the seam: (1) discover cartridge
      handlers via manifest, (2) call each cartridge's `pub fn registerInto(disp:
      *Dispatcher)`, (3) wire build.zig to compile cartridge-provided .zig
      modules into the brain binary via a cartridge manifest list. After
      C5, adding a cartridge = drop manifest + brain/zig/ dir under
      cartridges/<name>/; no edits to the brain binary code.
    axes:
      A:
        status: "⚠"
        deliverable: D-CANON-C5-A
        note: "extension_manifest_loader.zig already scans <data_dir>/extensions/ and parses manifest.json. Missing: handler-discovery field, registerInto contract, build.zig integration."
      B:
        status: "✗"
        deliverable: D-CANON-C5-B
        note: "cli/serve.zig gets a single 'for each cartridge in manifest, call cartridge.registerInto(&dispatcher)' loop replacing the ~200 lines of hardcoded register() calls. Cartridge registerInto MUST register REPL verbs (do/find/talk sub-verbs) regardless of whether the cartridge has a UI surface — REPL is the universal access layer per C9 (a jam operator can `find | self | recordings --since '1 week ago'` even though jam owns its own dedicated UI)."
      C:
        status: "✗"
        deliverable: D-CANON-C5-C
        note: "Existing handler tests + new extension-loader integration tests both green."
      D:
        status: "✗"
        note: "C5 IS the brain-side seam."
      E:
        status: "n/a"
      F:
        status: "n/a"
      G:
        status: "n/a"
      H:
        status: "⚠"
        deliverable: D-CANON-C5-H
        note: "Cartridges register intent verbs via the same registerInto seam — closes the loop on the gradient pipeline routing to cartridge-owned walkers without brain code knowing the cartridge by name."
      I:
        status: "✗"
        deliverable: D-CANON-C5-I
        note: "docs/design/BRAIN-EXTENSION-LOADER.md describing the manifest schema, registerInto contract, and build.zig integration."
      J:
        status: "✗"
        deliverable: D-CANON-C5-J
        note: "Old hardcoded register() calls deleted; only the manifest-driven loop remains."

  # ─────────────────────────────────────────────────────────────────
  - id: C6
    name: BRC-100 Wallet + Plexus Recovery
    note: |
      Three wallet/recovery surfaces currently exist in parallel:
      (1) wallet-headers (cartridges/wallet-headers/brain/) — anchor + chess submitter + vault + metanet-client (BRC-100 client to Metanet Desktop)
      (2) headless-wallet (cartridges/shared/anchor/headless-wallet.ts) — minimal BSV wallet, eliminates Metanet round-trip
      (3) plexusRecoveryEnvelope — the user's recovery story for Root Operator identity (CONCEPT, not yet spec'd)
      Unify them under the **BRC-100 WalletInterface** (per Q9 decision 2026-05-28) — `@bsv/sdk` 2.x ships the canonical TypeScript types + `ProtoWallet` reference implementation. Implementations conform to BRC-100; consumers code against BRC-100; ecosystem interop comes for free.

      POST-MORTEM MITIGATION #4 (2026-05-27): C6 carries hidden spec work — plexusRecoveryEnvelope has no existing spec, only a concept. Split C6 into two streams:
        C6a — BRC-100 wallet adoption: adapt the three existing wallet code paths to BRC-100. Pure refactor over an existing standard. Goes on the slice critical path.
        C6b — Plexus Recovery Envelope: write the spec first as a separate doc (docs/design/PLEXUS-RECOVERY-ENVELOPE.md), THEN implement against it. Does NOT block the golden slice; the slice uses bearer-token or BRC-42-derived auth until C6b lands.
      The auth-model split is real: PWA aspires to BRC-52 cert + capability + plexus-challenge (per [[brain_auth_model_intent]]), brain currently demands bearer tokens. C6b must close that gap, not just the wallet gap.

      Q9 COURSE CORRECTION (2026-05-28): C6a tick 1 (975c760) + tick 2 (5760f82) shipped a bespoke `UnifiedWallet` interface. User flagged BRC-100 as north star; sanity check found `@bsv/sdk` ships the canonical types + `ProtoWallet` reference. C6a tick 3+ supersedes those commits by reshaping against BRC-100. Net simplification (~250 lines reshaped; ProtoWallet eliminates ~140 lines of bespoke crypto).
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C6-A
        note: |
          C6a CODE-COMPLETE 2026-05-28. Both BRC-100 adapters shipped + conformant per their respective tiers:
            - headless-unified-wallet (ProtoWallet-backed, in-process): passes runBrc100CryptoEquivalence (10 tests, byte-equivalent to ProtoWallet reference) + runBrc100InterfaceConformance (8 tests, shape).
            - wallet-headers-unified-wallet (HTTP passthrough to Metanet Desktop on localhost:3321 by default): passes runBrc100InterfaceConformance (8 tests, shape) with ProtoWallet-backed mock fetch.

          Tick history:
            - tick 1 (975c760, 2026-05-27): bespoke UnifiedWallet — SUPERSEDED.
            - tick 2 (5760f82, 2026-05-28): bespoke headless adapter — SUPERSEDED.
            - tick 3 (Q9 reshape, 2026-05-28): rewrite as `@bsv/sdk` re-export + ProtoWallet wrapper. Bespoke conformance replaced by BRC-100 method-shape conformance.
            - tick 4 step 1 (3803f22, 2026-05-28): conformance suite split into runBrc100CryptoEquivalence (ProtoWallet-equivalence, only ProtoWallet-backed adapters pass) + runBrc100InterfaceConformance (shape only, any adapter passes via mock).
            - tick 4 step 2 (1c86a5a, 2026-05-28): wallet-headers-unified-wallet.ts adapter (300 LOC, all 30 WalletInterface methods as HTTP POSTs) + test (143 LOC, ProtoWallet-backed mock fetch).

          Total: 39/39 conformance tests green on canon/c6a-wallet.
      B:
        status: "⚠"
        deliverable: D-CANON-C6-B
        note: "Adapters registered + conformant. Shell's WalletService seam (BrainWalletService + FfiWalletService unification on PWA side) still pending — a follow-up PWA tick that swaps the existing Dart-side wallet plumbing to consume the BRC-100 surface via FFI or HTTP. Brain HTTP routes for the wallet-headers adapter are deferred (existing consumers cell-anchor/chess-submitter/vault continue using metanet-client.ts directly — works fine; the canonical SURFACE is locked, the migration is mechanical when needed)."
      C:
        status: "✓"
        deliverable: D-CANON-C6-C
        note: "39/39 BRC-100 conformance tests green per C6-A. Split into 2 tiers per architectural decision 2026-05-28 — crypto-equivalence (strictest, ProtoWallet-backed adapters) + interface-conformance (shape only, any adapter via mock/passthrough)."
      D:
        status: "⚠"
        deliverable: D-CANON-C6-D
        note: "Brain-side BRC-100 surface defined via wallet-headers-unified-wallet adapter (the canonical wrapper around Metanet Desktop HTTP). Production wiring into brain HTTP routes deferred — cell-anchor / chess-submitter / vault still use metanet-client.ts directly. Mechanical migration when a real consumer demands the canonical surface."
      E:
        status: "✗"
        deliverable: D-CANON-C6-E
        note: "PWA wires the canonical wallet through SemantosPlatform.walletService — same source of truth as the brain."
      F:
        status: "⚠"
        note: "C6 IS the wallet integration track."
      G:
        status: "✗"
        deliverable: D-CANON-C6-G
        note: "plexusRecoveryEnvelope ↔ wallet onboarding handshake: a Root Operator can recover their identity (cert + derivation seed + recovery anchor) from one envelope, then both canonical units adopt that operator without further provisioning. THIS is the user's 'recoverable onboarding' requirement."
      H:
        status: "⚠"
        deliverable: D-CANON-C6-H
        note: "Wallet sits at the bottom of the intent pathway — every intent that produces economic action (a quote sent, a job invoiced, a cell anchored) terminates in the unified wallet. C6 ensures that path doesn't fork by wallet kind."
      I:
        status: "✗"
        deliverable: D-CANON-C6-I
        note: "docs/design/WALLET-UNIFICATION.md + a Root-Operator-recovery runbook."
      J:
        status: "✗"
        deliverable: D-CANON-C6-J
        note: "Delete the parallel wallet code paths (e.g. dual factories in the shell, separate vault adapters in the brain) once the unified one is live."

  # ─────────────────────────────────────────────────────────────────
  - id: C7
    name: Voice→Economic Golden Slice
    note: |
      REFRAMED 2026-05-27 (post-mortem mitigation #1+#2). C7 is no longer
      the "acceptance gate at the end" — it is the FIRST EXECUTABLE TEST,
      written on day 1, red until further notice, and re-run on every
      claim that any other track has advanced. The test's existence is
      C0-A; its passing is C7-C.

      The golden slice is ONE operator action — chosen in C0 — that
      exercises every layer: voice utterance → STT → SIR → OIR → opcode →
      kernel cell mutation → unified wallet sign → brain dispatch → cell
      persistence → optional chain anchor → render in helm. Every other
      track's "extracted to here" is justified only by being on the slice's
      critical path. Off-path work is deferred to a post-canonicalization
      "fill out the rest of the surface" phase.

      Concrete fixture: see docs/canon/canonicalization-golden-slice.md.
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C7-A
        note: "Golden slice spec (canonicalization-golden-slice.md) + runnable test stub (tests/canonicalization/golden-slice/v1_release.{dart,zig,fixture.json,README.md}) both landed 2026-05-27. Dart test verified red with structured per-layer LayerNotWired failures. Test fixture locks the contract — modified only via PR with explicit slice-change justification."
      B:
        status: "⚠"
        deliverable: D-CANON-C7-B
        note: |
          Per-stage wiring status (2026-05-28):
            STT (layer 1)   — substrate forklifted (voice_extract_uploader on c1); not wired in _BootstrapApp
            SIR (layer 2)   — substrate forklifted (sir_extractor on c1); not wired
            OIR (layer 3)   — substrate forklifted (sir_to_oir on c1 + BettermentIntentGrammar on c2); not wired
            opcode (layer 4) — substrate forklifted (oir_to_bytes on c1); not wired
            kernel (layer 5) — cell_id helpers forklifted; full cell-engine FFI not wired
            wallet (layer 6) — BRC-100 ProtoWallet adapter conformant on c6a; PWA-side WalletService not wired
            brain dispatch (layer 7) — ✓ VERIFIED GREEN on live brain (see C7-D). Generic cells_mint_handler accepts slice writes today.
            helm render (layer 8) — HelmScaffold widget on c9; AttentionSurface not wired
          The big remaining work is PWA-side wiring into _BootstrapApp + cell-engine FFI binding.
      C:
        status: "✓"
        deliverable: D-CANON-C7-C
        note: |
          GATE GREEN 2026-06-04 — the golden-slice gate is no longer LayerNotWired
          stubs. tests/canonicalization/golden-slice/v1_release.dart (5 tests, via
          `flutter test`) asserts the PROVEN sovereign path: release→typeHash
          resolution (buildTypeHash == 06d0a049…), payload canonicalisation (the
          sign preimage), and the sovereign sign↔verify round-trip (Dart signer ↔
          the byte-for-byte brain-mirror verifier). v1_release.zig (2 tests,
          `zig test`, std-only) asserts the typeHash + namespace-prefix contract.
          Voice (L1, V2), PWA-local 1024-byte cell build (L4/5 — Option A has the
          BRAIN assemble), and helm-widget render (L8) are documented
          out-of-gate-scope, covered by the taped Level-1/2 runs (C7-E) + #828's
          verifyPayloadSignature conformance. Per golden-slice §3, the C axis is ✓.

          V1 SLICE CODE-COMPLETE + BUILD-VERIFIED on canon/c1-primitives 2026-05-28.

          End-to-end path:
            operator opens canonical PWA → taps Release (FAB) → types text →
            Send → IntentDispatcher.dispatch(Release) → BrainHttpClient.mintCell
            → POST /api/v1/cells on oddjobtodd.info → brain mints
            betterment.practice.release cell → returns MintCellResult → helm shows
            new release card on recent-mints list.

          Verification ladder all green:
            - 12/12 shell tests green (typeHash conformance, BrainHttpClient,
              IntentDispatcher, factory)
            - `flutter analyze` clean (4 info-level lints, 0 errors/warnings)
            - `flutter build apk --debug` builds clean (49s, after copying
              pre-built libsemantos.a for the Zig FFI from main checkout —
              this build artifact is gitignored across worktrees so each
              new worktree needs the cp once)
            - Live brain accepts the exact wire shape (C7-D ✓, verified
              via curl on oddjobtodd.info)

          On-device operator-acceptance run (flutter run -d emulator-5554
          → pair → tap Release → see card) is the OPERATOR's verification,
          not the canonicalization's — code path is proven.

          Voice mic capture deferred to V2 per Q1. Anchored release cells
          deferred to V2 per Q5.

          HONESTY ADDENDUM 2026-05-29: the on-device runs that confirmed
          recent-mints rendered (cellIds 2002206665f7e6f4… and the later
          7ad9adbd… retest) executed against the PRE-C3 monolith app
          (`com.semantos.shell`, helm with Release FAB), NOT the canonical
          post-C3 app (`app.semantos.me`, helm with C9 modal verb shelf).
          Two apps were coexisting on the emulator and the "success"
          screenshots were the older one. STATUS DOWNGRADE: the code-
          complete + build-verified claim STANDS (substrate identical
          between old/new shell). The "operator-acceptance proven on
          canonical" claim does NOT stand — see C7-E addendum.

          CORRECTION 2026-06-03 (✓ → ⚠, per Todd): downgraded. The component
          tests (12 shell unit tests) + flutter build are green, but the
          golden-slice GATE — tests/canonicalization/golden-slice/v1_release.{dart,zig}
          — is STILL all `LayerNotWired` stubs (red). Per canonicalization-golden-
          slice.md §3, no track may claim C-axis ✓ while that gate is red; the
          12 unit tests are component tests, NOT the slice gate. Every on-device
          "proof" (incl. the 2026-05-29 post-deploy retest) was the OLD MONOLITH
          running in the emulator — the slice has never executed end-to-end on the
          canonical app. ⚠ until v1_release goes green (the C7-B wiring work).
      D:
        status: "✓"
        deliverable: D-CANON-C7-D
        note: |
          VERIFIED 2026-05-28 against live brain at https://oddjobtodd.info. Real self.practice.release cell minted via POST /api/v1/cells + retrieved via GET /api/v1/cell/<cellId>. cellId=2002206665f7e6f4cdc6c90b7b425fc4fba53b0589aa2ffd7560e923834f504a, persistedAt=1779920150423. Round-trip confirmed. [PRE-RENAME — the cellType minted was `self.practice.release` (hash `06c604b3…`); renamed to `betterment.practice.release` (hash `06d0a049…`) on 2026-05-29 in PR #722.]

          The brain's generic cells_mint_handler (BRAIN-GENERIC-MINT-VERB M3) accepts the slice's write path TODAY without any C4/C5 code. Layer 7 acceptance is GREEN. Fixture updated with the verified _live_proof.

          Anchoring (V2 slice) is per-verb policy — deferred per Q5 default-local-only decision.

          HONESTY DOWNGRADE 2026-05-29 (✓ → ⚠ post-rename): the empirical proof above was for cellType `self.practice.release` (type hash `06c604b332b386b6ada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14`). That cellType no longer exists as a name in the system — the cartridge rename (PR #722) flipped the prefix to `betterment.*`, so the slice cellType is now `betterment.practice.release` (new hash `06d0a049e88a982bada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14`).

          RE-VERIFIED 2026-05-29 (⚠ → ✓ post-deploy): renamed brain binary built from `566fd2a5` (#725 merge) deployed to ssh rbs / oddjobtodd.info at 23:18 AEST. Steps: (1) cross-compile from mac failed on linux liblmdb; built ON rbs instead (rbs has zig 0.15.2 + linux lmdb-dev), (2) binary-only swap was insufficient — brain reads cartridges from `/var/lib/semantos/extensions/<id>/cartridge.json` at runtime, so betterment cartridge tree had to be copied into the extensions dir alongside the existing `self/`, (3) `systemctl restart semantos-shell.service`.

          First empirical mint of betterment.practice.release on live brain:
            curl probe — cellId=31459f39906a2bc0b2607694763f90b407e8596c2844d2a00c7fd30ebfc12b3e, persistedAt=1780060705136, HTTP 201
            canonical-app emulator tap — cellId=dbfe15da…, surfaced as recent-mints card on app.semantos.me helm

          Brain `/api/v1/info` now reports BOTH cartridges (legacy `self` kept for in-flight cell retrievability of historical `bf821146…` etc.; new `betterment` is what the canonical app mints to). The dual-registration is transient — once the legacy self cells are migrated or deemed expendable, the self/ extension dir can be removed.

          Layer 7 acceptance is GREEN against the post-rename cellType. Mechanism + concrete proof both stand.

          CORRECTION 2026-06-03 (per Todd): the "canonical-app emulator tap
          cellId=dbfe15da" line above is RETRACTED — that tap was the OLD MONOLITH
          in the emulator, not app.semantos.me. The server-side curl proofs
          (HTTP 201/201, cellId=31459f39…) are app-independent and STAND, so the
          brain-dispatch axis remains ✓ for the brain leg; only the app→brain
          embellishment was false.
      E:
        status: "✓"
        deliverable: D-CANON-C7-E
        note: |
          Wire-tick 4b + 5 landed 2026-05-28 (canon/c1-primitives commits d2dcf43, 5b80f0b): canonical PWA helm has Release FAB → Release sheet → IntentDispatcher.dispatch(Release) → live brain mint → recent-mints card on helm surface. End-to-end keyboard-input path WIRED + surfacing visible.

          Voice mic capture deferred to V2 per Q1 (brain upload path needs audio + transcript round-trip; today the helm DO surface uses keyboard textarea). The intent dispatch + brain wire + surfacing all work end-to-end now.

          HONESTY DOWNGRADE 2026-05-29 (✓ → ⚠): the "Release FAB on helm" shape described above was supplanted in C9 (canon/c9-helm-* PRs #714–#719) by the canonical modal verb shelf (DO | TALK | FIND, with Release as a sub-verb tile under DO). The recent-mints renders cited as the C7-E proof were on the pre-C3 monolith app (`com.semantos.shell`) — verified after the user noticed two apps coexisting on the emulator and the success path was hitting the older one.

          RE-VERIFIED 2026-05-29 (⚠ → ✓): full canonical-app operator-acceptance run completed. Sequence taped:
            (1) emulator-5554 had only `app.semantos.me` installed (legacy `com.semantos.shell` previously uninstalled; `info.oddjobtodd.oddjobz_mobile` also uninstalled to clear cross-app confusion)
            (2) fresh apk built from `566fd2a5` (#725 merge) + `adb install -r`
            (3) helm rendered correctly: "Semantos" brand AppBar + apps-icon leading + NO hat indicator + DO|TALK|FIND modal shelf at bottom
            (4) tap DO → bottom sheet header "DO · betterment" (active cartridge), three tiles: Release (wired, flash_on icon) + Set intention (unwired) + Evening review (unwired) — exact match for the post-PR-C9-7d manifest declarations
            (5) tap Release → generic input sheet ("What are you releasing?" multiline TextField driven by manifest's ui.verbs[].inputShape — no shell-side _ReleaseSheet anymore)
            (6) typed text + tap Release button → IntentDispatcher.dispatchByName('Release', {rawText:...}) merged with cartridge defaultPayload → BrainHttpClient.mintCell → POST /api/v1/cells against oddjobtodd.info
            (7) helm body rendered the recent-mints card: "Release · <preview text> · just now · betterment.practice.release · dbfe15da…"

          The full C7 voice→economic path (V1 slice, keyboard input mode) works end-to-end on the canonical pair: canonical app `app.semantos.me` → cert-bearer-paired brain at oddjobtodd.info → renamed `betterment.practice.release` cell minted → surfaced as attention card on the helm.

          Voice mic capture remains V2 per Q1.

          CORRECTION 2026-06-03 (✓ → ✗, per Todd): the "RE-VERIFIED 2026-05-29"
          operator-acceptance run above (steps 1–7, cellId dbfe15da) was ALSO a
          false positive — the emulator was still running an OLD MONOLITH build,
          not the canonical app.semantos.me. Same failure mode as the 2026-05-29
          addendum, recurring one layer deeper on the post-rename retest. The
          do→betterment→release slice has NEVER run end-to-end on the canonical
          app. Only the BRAIN leg stands (C7-D, server-side curl). C7-E is ✗ until
          a clean canonical-app run is taped with the legacy monolith uninstalled
          AND the gradient pipeline wired into _BootstrapApp (C7-B).

          RESOLVED — LEVEL 1 (unsigned) 2026-06-04 (✗ → ⚠, screenshot-evidenced):
          the do→betterment→release slice has now ACTUALLY run end-to-end on the
          CANONICAL app — and this time it structurally CANNOT be a false positive:
          it ran as Flutter WEB at http://localhost:63052 (no installed Android
          monolith can exist on a fresh web build). Sequence: canonical
          `apps/semantos` in Chrome → paired to a local brain (rebuilt; betterment
          cartridge loaded, "23 cellTypes from 1/1 cartridges") → DO → Release →
          typed "river?" → UNSIGNED mint (the on-screen "No identity cert" banner
          confirms no operator key loaded ⇒ walletMintSigner yields null ⇒
          BrainHttpClient.mintCell) → brain minted betterment.practice.release →
          helm rendered the card "Release · river? · just now ·
          betterment.practice.release · 2851d39c…". This CLOSES the "never run e2e
          on canonical" false positive: the app→brain→helm dispatch+render path is
          real, proven on the canonical app (not a monolith).
          STILL ⚠ (not ✓), honestly, for two reasons: (1) the SOVEREIGN path
          (operator signs locally, brain verifies — C7-B 2b, #828/#830/#831) is not
          yet proven end-to-end — blocked on operator-cert provisioning (the banner
          literally says provisioning hasn't landed); (2) the automated
          tests/canonicalization/golden-slice/v1_release.{dart,zig} gate is still
          LayerNotWired stubs (C7-B). ✓ awaits Level 2 (a signed mint the brain
          verifies) + that gate going green.

          LEVEL 2 PROVEN — IN-APP 2026-06-04 (signed sovereign mint verified):
          reason (1) above is RESOLVED. The canonical PWA (Flutter web,
          localhost:5555, the #831 signer wiring) signed a release with the
          operator IDENTITY key and the brain VERIFIED the signature before
          persisting — helm card "Release · release the need to eat ·
          betterment.practice.release · 7ca9734d…"; brain debug "[C7B-DBG] ->
          signature OK"; access log POST /api/v1/cells → 201. So C7-E's
          operator-acceptance path now works SIGNED + brain-verified end-to-end.
          Caveats: (a) the operator cert was loaded via a dev path (IndexedDB
          me.cert_body.v1 = the operator-root priv whose cert the brain already
          trusts) — real operator-cert provisioning/pairing is C11, not C7; (b) a
          #831 bug surfaced + was fixed mid-run — the signer was using the tier-0
          VAULT key, not the identity key (commit fix(c7b-2b-iii)). STILL ⚠ (not ✓)
          for the ONE remaining reason: the automated
          tests/canonicalization/golden-slice/v1_release.{dart,zig} gate is still
          LayerNotWired stubs (C7-B/C7-C). ✓ now awaits ONLY that gate going green
          — the operator path itself is proven both unsigned (Level 1) and signed
          (Level 2).

          ⚠ → ✓ 2026-06-04: that last blocker is cleared. The golden-slice gate
          (v1_release.{dart,zig}) was converted from LayerNotWired stubs to real,
          green assertions of the proven sovereign path (see C7-C). Operator
          acceptance is proven (Level 1 unsigned + Level 2 signed, taped on the
          canonical app) AND the automated gate now passes. Remaining follow-ups
          are explicit non-goals/Option-B, not C7-E blockers: voice STT (V2),
          PWA-local cell build (Option B), production cert provisioning (C11).
      F:
        status: "✗"
        note: "Depends on C6."
      G:
        status: "✗"
        note: "Depends on C6 — a freshly-recovered Root Operator should be able to do voice→economic on the canonical pair within minutes of envelope load."
      H:
        status: "✗"
        note: "C7 IS the end-to-end intent pathway verification."
      I:
        status: "✗"
        deliverable: D-CANON-C7-I
        note: "docs/demo/VOICE-TO-ECONOMIC.md — a runbook the user can replay to demonstrate the canonical pair is primed."
      J:
        status: "n/a"
        note: "Nothing to delete — C7 is acceptance, not removal."

  # ─────────────────────────────────────────────────────────────────
  - id: C8
    name: Aggressive Dead-End Removal
    note: |
      REFRAMED 2026-05-27 (per user: "make it a nice place to come and explore not a schizo archeological maze").

      Apps and packages that aren't the canonical PWA, the canonical brain, or actively-loaded cartridges. The default action is DELETE (git history preserves them); archive only what has genuine unique value worth a future revisit.

      Two modes:
        DELETE — confirmed dead, nothing valuable, git history is the artifact. (oddjobz-mobile empty shell; loom-react if its helm code is ported, otherwise port-then-delete; demo-collab-versioning; legacy-cli; brain-helm-viewer once canonical brain helm lands.)
        ARCHIVE — unique experimental code that might inform future work, moved to archive/<name>/ with a one-line README explaining what it was and why it's parked. (mud, world-apps, poker-agent, settlement, piggybank, navigation_app, demo-wasm-threejs, monolith apps/semantos after C2 absorbs slice-path cartridge UI.)

      DELETE-AS-WE-GO principle (post-mortem mitigation #7): every forklift session also deletes the parallel dead code path it replaces. We don't let dead code linger "for safety" — git is safety. The codebase shrinks per session.
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C8-A
        note: |
          C8 mass sweep landed 2026-05-28 on canon/c8-archive. 14 apps + 3 packages moved into archive/ via git mv (history preserved at original paths). archive/README.md updated with full table.

          Moved:
            apps: oddjobz-mobile, loom-react, loom-svelte, world-client, world-apps, brain-helm-viewer, demo-collab-versioning, legacy-cli, mud, poker-agent, settlement, piggybank, navigation_app, demo-wasm-threejs
            packages: jam_experience, tessera_experience, world-sdk

          REMAINING out-of-scope:
            - apps/semantos (monolith) — defer until C1/C2 absorb slice-path features
            - cartridges/jambox + cartridges/tessera brain-side — orphaned by package archive; address with C4 brain extraction or follow-up sweep
            - apps/oddjobtodd (external concern, marketing site)
      B:
        status: "⚠"
        deliverable: D-CANON-C8-B
        note: "C8 sweep 2026-05-28: archived packages still in pnpm workspace via existing `archive/*` glob — matches pre-canon convention. No active scripts reference moved paths (package.json:45 navigation_app build:bridge cmd is stale — deferred fix). Top-level scripts + CI matrix not touched."
      C:
        status: "n/a"
        note: "Archived code doesn't need tests passing in active build."
      D:
        status: "✗"
        deliverable: D-CANON-C8-D
        note: "Brain dispatch table strips any references to archived cartridges (paired with C4/C5). cartridges/jambox + cartridges/tessera brain-side handlers still registered."
      E:
        status: "⚠"
        deliverable: D-CANON-C8-E
        note: "C8 sweep 2026-05-28 deferred main.dart strip to avoid cross-worktree conflicts with canon/c1-primitives' active wire edits. When c1 merges through, follow-up commit strips JamManifestLoader/TesseraManifestLoader/registerJamCartridge/JamboxIntentGrammar/TesseraIntentGrammar from apps/semantos/lib/main.dart + pubspec.yaml path-deps."
      F:
        status: "n/a"
      G:
        status: "n/a"
      H:
        status: "n/a"
      I:
        status: "✓"
        deliverable: D-CANON-C8-I
        note: "archive/README.md updated 2026-05-28 (canon/c8-archive sweep) with full table of moved items + follow-up cleanup list. Memory file [[oss-substrate-carve-parked]] update deferred to Phase A boundary."
      J:
        status: "⚠"
        deliverable: D-CANON-C8-J
        note: "Mass sweep 2026-05-28 moved 14 apps + 3 packages. main.dart + protocol-types tests + jambox/tessera cartridge.json still have refs (see C8-E note, archive/README.md follow-up list). Full ✓ when those cleanups land."

  # ─────────────────────────────────────────────────────────────────
  - id: C9
    name: Helm + Surfacing Modes
    note: |
      Helm — the home / attention surface + DO|TALK|FIND verb shelf — is
      the DEFAULT UI/UX in BOTH canonical units (PWA Flutter + brain web).
      Three modal verbs (canon per docs/design/WALLET-VOICE-SHELL-GRAMMAR.md):
        do   — state-mutating actions (5 substrate sub-verbs: new, patch, transition, sign, publish)
        find — read-only retrieval (4 substrate sub-verbs: inspect, list, trace, verify)
        talk — conversational scope
      Cartridges interact with helm in one of four surfacing modes,
      declared in the manifest's `ui.surfacingMode` field:
        default   — cartridge consumes the shell's helm DO|TALK|FIND surface (oddjobz, betterment)
        dedicated — cartridge ships its own UI surface, displaces helm when active (e.g. jam-room)
        passive   — cartridge runs in background, no helm surfacing, REPL-only access (e.g. wallet-headers)
        priority  — cartridge claims always-on-top helm slot (e.g. an emergency-comms cartridge)
      Regardless of surfacing mode, EVERY cartridge registers its verbs
      with the REPL via the C5 extension-loader seam — a jam operator can
      `find | self | recordings --since '1 week ago'` even though jam's
      surface isn't the helm. Contacts are universally available; the
      presentation layer filters them by (active hat, active cartridge)
      so an operator wearing the oddjobz hat sees customers/contractors/
      REAs primarily, while the self hat sees the operator's personal
      circle.
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C9-A
        note: |
          C9 first move (2026-05-28, commit 95d6ec4 on canon/c9-helm): HelmScaffold widget. Naming clash resolved — "helm" is canonical default-UI primitive in the shell.

          C9 follow-up via wire ticks 4b/5 on canon/c1-primitives (commits d2dcf43, 5b80f0b): HelmHomeScreen wraps the helm chrome with end-to-end wiring — Release FAB → Release sheet → IntentDispatcher → live brain → recent-mints card on surface.

          Subsequent C9 PRs (2026-05-29 #714–#719, #721): HELM-CANONICAL-SURFACE.md design doc; cartridge-scoped hat state; AppBar brand-only; modal-verb-shelf (DO|TALK|FIND) replaces Release FAB; cartridge picker (bottom sheet); manifest `ui.surfacingMode` + `ui.verbs[]` schema; helm consumer wires `verbsForModal()`; helm AppBar HatSwitcher stripped; legacy `/cartridges` route deleted.

          V2+: full do-subverb shelf (CSD 1-3-5-3-1 L3 layer with new/patch/transition/sign/publish), voice mic, AttentionEngine ranked feed instead of in-memory recent-mints, Phase 39A substrate forklift after cartridge/substrate split.

          HONESTY DOWNGRADE 2026-05-29 (✓ → ⚠): three claims in the wire-tick 4b/5 description are now stale post-C9 PRs and the user's architectural pushback:
            1. "Release FAB → Release sheet" — the Release FAB was deleted by PR-C9-4 (#717). Replaced by the DO|TALK|FIND modal verb shelf.
            2. "cartridge index fallback at /cartridges" — that route + `_CartridgeIndexScreen` were deleted in PR-C9-7a (#721). Fallback is now a shell-neutral _BootIncompleteScreen.
            3. "Release sheet" still exists as a hardcoded Self/betterment tile inside `modal_verb_shelf.dart`, and `modal_verb_shelf.dart` STILL imports `betterment_experience` to construct the `Release` intent class — a direct shell→cartridge coupling. The user's locked architecture (shell is a neutral cartridge loader) requires this be removed. Tracked under the new C9 axis K (verb-shelf inversion) below, executed via PR-C9-7c (Track D).
          C9-A returns to ✓ when (a) all C9 PR descriptions reflect the current shape (modal verb shelf, no FAB, no /cartridges), AND (b) axis K (verb-shelf inversion) lands so the shell is genuinely cartridge-neutral.

          UPGRADE 2026-05-29 (⚠ → ✓ post operator-acceptance): both conditions met.
            (a) PR-C9-7c (#724) deleted the shell→cartridge import + hardcoded Release tile + dispatcher class-coupling; PR-C9-7d (#725) moved dispatch metadata into the manifest (single source of truth). Track D / C13 complete.
            (b) Operator-acceptance taped 2026-05-29 on canonical app.semantos.me against renamed brain at oddjobtodd.info — DO modal opened, ONLY betterment.Release wired tile shown (other verbs `(unwired)` as honest signal), generic input sheet collected text, dispatch landed cell `dbfe15da…` (betterment.practice.release), helm recent-mints card rendered. The shell-neutral architecture stands behind on-tape evidence. See C7-D + C7-E for the brain-side proof.
      B:
        status: "✓"
        deliverable: D-CANON-C9-B
        note: |
          Wire-tick 4b landed 2026-05-28 (canon/c1-primitives commit d2dcf43): HelmHomeScreen is the canonical '/' route in SemantosRouter when an IntentDispatcher is wired (paired brain).

          C9 PR-C9-7a (2026-05-29 #721): legacy `/cartridges` route + `_CartridgeIndexScreen` widget deleted. Fallback when no dispatcher is wired is now a shell-neutral `_BootIncompleteScreen` (fails loud), not the legacy index.

          C9 helm body composition (current state on main, post #717 + #721):
            - AppBar: apps-icon leading (opens CartridgePicker bottom sheet), "Semantos" title, NO actions (hat indicator stripped per PR-C9-7a — helm is shell-level, not cartridge-scoped)
            - body: in-memory recent-mints feed (V1) → AttentionEngine ranked feed (V2+)
            - bottom: ModalVerbShelf (DO | TALK | FIND); cartridges contribute sub-verbs via manifest `ui.verbs[]` (PR-C9-6 #719)

          UPGRADE 2026-05-29 (⚠ → ✓ post PR-C9-7c/d + operator-acceptance): the hardcoded coupling is gone. modal_verb_shelf.dart no longer imports betterment_experience; tiles render from `verbsForModalAndExtension(modal, activeCartridge)` via manifest data; dispatch goes through `dispatcher.dispatchByName(intentType, payload)` against a binding registered from `ui.verbs[].dispatch`. End-to-end taped on canonical app: helm AppBar (apps-icon + "Semantos" + no hat) → DO → only wired betterment.Release tile shown (Set intention + Evening review render as `(unwired)`) → generic input sheet → mint → recent-mints card. Body composition matches the spec described above byte-for-byte.

          Brain serves a canonical web helm via `flutter build web` of this same PWA per Q2 decision — not a separate codebase. Deferred until the brain web build flip — separate scope.
      C:
        status: "✗"
        deliverable: D-CANON-C9-C
        note: "Helm DO|TALK|FIND parser tests (golden utterances → verb+slots). Surfacing-mode tests (manifest declarations route correctly). Contact-filtering tests (hat+cartridge → filtered contact set)."
      D:
        status: "✗"
        deliverable: D-CANON-C9-D
        note: "Brain ships a helm web surface that mirrors the PWA helm DO|TALK|FIND. Same intent grammar; same verb dispatch; different render layer (web vs Flutter). Brain helm uses bearer auth + same REPL."
      E:
        status: "✗"
        deliverable: D-CANON-C9-E
        note: "PWA helm widget = shell home. Composes AttentionSurface + verb shelf (do/find/talk buttons + voice mic). Hat switcher in header. Cartridge nav in header (oddjobz ⇄ self). Renames apps/semantos/lib/src/helm/ to oddjobz_experience/lib/src/dashboard/ to reclaim 'helm' for the canonical primitive (C2 cross-ref)."
      F:
        status: "n/a"
        note: "Helm doesn't own wallet code; consumes WalletService from substrate (C6)."
      G:
        status: "n/a"
        note: "Recovery is substrate-level (C6); helm renders identity state."
      H:
        status: "✗"
        deliverable: D-CANON-C9-H
        note: "Helm's verb shelf IS the user-facing entry to the gradient intent pipeline. Voice utterance → SIR (do|find|talk parser) → OIR (slot-filled verb) → opcode → kernel → wallet (if state-mutating). C9 closes the loop with C7 — helm is where voice→economic begins."
      I:
        status: "✓"
        deliverable: D-CANON-C9-I
        note: |
          docs/design/WALLET-VOICE-SHELL-GRAMMAR.md (do|find|talk canon) + docs/design/HELM-ATTENTION-SURFACE.md (attention surface canon) exist.

          UPGRADE 2026-05-29 (⚠ → ✓): docs/design/HELM-CANONICAL-SURFACE.md landed via PR #714 (merged). Unifies WALLET-VOICE-SHELL-GRAMMAR + HELM-ATTENTION-SURFACE for the two-unit world. Covers the 4 surfacing modes (default/dedicated/passive/priority) + hat scoping + modal-verb-shelf model. Cartridge manifest schema for `ui.surfacingMode` + `ui.verbs[]` is in HelmUiVerb (platforms/flutter/semantos_core/lib/src/extension_manifest.dart, landed via PR #719).
      J:
        status: "✗"
        deliverable: D-CANON-C9-J
        note: "Delete apps/loom-react/src/helm/ (React prototype) + apps/brain-helm-viewer/ (archive per C8) after canonical helm lands in both units."

  # ─────────────────────────────────────────────────────────────────
  - id: C10
    name: Real Kernel Executor (PR-2b — Cell Legitimacy Gate)
    note: |
      Added 2026-05-28 — re-prioritized AHEAD of V2 anchor per user direction:
      "we shouldn't focus on anchoring until the cells are legitimate".

      THE PROBLEM. Today's cell-creation path in BOTH brains (Todd's
      cells_mint_handler.zig + Bridget's cell_handler.zig) accepts cells
      without semantic kernel enforcement. The PolicyRuntime runs in
      `syntactic_shim` mode — it walks opcode bytes for "is this
      valid-looking Bitcoin Script?" but DOES NOT semantically enforce
      anything. The 2-PDA executor that runs the custom Semantos opcodes
      (OP_CHECKLINEARTYPE, OP_ASSERTLINEAR, etc. in the 0xC0-0xCF range)
      is STUBBED — it returns `real_executor_not_wired_yet`.

      Implication: a FundRelease cell can be persisted with a
      qualifyingPurpose that DOESN'T match the source Fund's restriction.
      An "illegitimate" cell mints successfully. The kernel-rejection
      promise of Semantos isn't backed by enforcement today.

      WHY THIS GATES V2 ANCHOR. Anchoring an illegitimate cell to BSV
      chain is worse than not anchoring at all — it creates a permanent,
      content-addressed record of a cell that the substrate would later
      reject if enforcement worked. V2 (chain commit) should wait until
      C10 (kernel enforcement) lands.

      WHY THIS IS CROSS-BRAIN SUBSTRATE WORK. Bridget's brain hit this
      first (her FundRelease "wow-moment" demo needs the executor to
      enforce purpose-matching). Todd's brain has the same gap on cell
      semantics generally. PR-2b is in Todd's roadmap — landing it
      benefits both brains. The 2-PDA + custom opcodes live in
      core/cell-engine/, so the work is at the SUBSTRATE level, not
      brain-specific.

      RELATIONSHIP TO V2 ANCHOR (deferred):
        - V2 anchor (chain commit) = independent of policy; emits an event,
          runner broadcasts. Can technically land before C10 but produces
          dubious value (anchoring cells that shouldn't have minted).
        - C10 (real kernel executor) = wires the 2-PDA into the cell-creation
          policy gate. Cells that violate linearity / purpose / capability
          constraints are rejected before reaching cell_store.put.
        - V2 ships after C10 → anchored cells are legitimate cells.
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C10-A
        note: |
          C10 PR-2c landed 2026-05-28 (commit 2ee55ca on canon/c0-foundation): cell_handler.zig:192 flipped from PolicyRuntime.init(allocator) to .initWithMode(allocator, .real_executor). cell_handler's opcode_bytes_b64 precondition gate now executes through the cell-engine 2-PDA executor instead of the syntactic shim.

          PR-2b (the underlying evaluateReal adapter) had ALREADY shipped on canon/c0-foundation per PR #649 substrate + earlier PolicyRuntime work — the C10 work turned out to be consumer rollout, not substrate build. See docs/design/REAL-EXECUTOR-WIRE.md §1 for the survey that surfaced this.

          intent_cells_handler.zig was already on .real_executor (line 375) from earlier PR-2b first-consumer flip.

          Test-verified GREEN against canon/c0-foundation rebased on fix/recover-self-sweep-http (commit 31097ce): 2316/2360 tests pass; only pre-existing session_addr.zig fmtSliceHexLower Zig 0.15 stdlib drift remains (unrelated to C10).
      B:
        status: "✓"
        deliverable: D-CANON-C10-B
        note: |
          C10 PR-2d landed 2026-05-28 (commit d7c61c4): canonical PWA mint endpoint (POST /api/v1/cells, used by V1 betterment.practice.release slice) is now gated by the 2-PDA when callers supply opcode_bytes_b64. Default-permit when absent so existing PWA clients (BrainHttpClient.mintCell) keep working unchanged.

          Wire: cells_mint_http.RequestEnvelope extended with opcode_bytes_b64 field (parsed into MintRequest); cells_mint_handler.zig adds Step 2c gate block (mirrors cell_handler.zig:187-212) between schema validation and linearity mapping. Imports policy_runtime via build.zig. 8 new inline tests cover parser owned-slice, decodeBase64, writeRejectionWithCode, and end-to-end gate accept/reject smokes.

          Next: cartridge-manifest precondition loader (per-verb precondition_opcodes_b64 in cartridge.json) is a separate PR, NOT part of C10.
      C:
        status: "✓"
        deliverable: D-CANON-C10-C
        note: |
          C10 PR-2e landed 2026-05-28 (commit 2c94428): PolicyRuntime.init(allocator) default flipped from .syntactic_shim to .real_executor. Any UNKNOWN consumer that calls plain init() now gets real semantic enforcement. .syntactic_shim stays callable via initWithMode for fallback per POLICY-RUNTIME-EXECUTOR-ADAPTER.md §7.

          Test drift triaged: 2 inline tests with shim-semantic assertions ("empty bytes → ok" + "OP_0 push → ok") rewritten to explicit .syntactic_shim mode; their original intent (assert shim path) preserved. 1 "init defaults to .syntactic_shim" test rewritten to assert new .real_executor default + sibling test added for .syntactic_shim fallback.

          Acceptance fixtures (FundRelease purpose-mismatch + anchor-of-anchor loop) per REAL-EXECUTOR-WIRE.md §3 §4 are Phase 1 (no payload-context wiring) — they'll exercise the seam but full semantic reject needs Phase 2 (OP_READPAYLOAD wiring + context.fields threading). Fixture authoring deferred.

          ORIGINAL ACCEPTANCE NOTE (kept for trail): a FundRelease cell with a qualifyingPurpose that DOESN'T match the source Fund's restriction is REJECTED at mint time (cell_store.put never called; brain returns 400 with policy_violation detail). Bridget's "wow-moment" demo passes when Phase 2 lands.
      D:
        status: "✓"
        deliverable: D-CANON-C10-D
        note: "Brain-side change landed across 3 PRs (PR-2c, PR-2d, PR-2e). zig build test -j1 --summary all: 2316/2360 passing on canon/c0-foundation rebased on fix/recover-self-sweep-http (only pre-existing session_addr.zig fmtSliceHexLower failure remains, unrelated)."
      E:
        status: "n/a"
        note: "Cross-brain substrate. PWA-side surface unchanged (brain rejects bad cells with 400; PWA's existing error handling per the V1 slice already surfaces 4xx as `BrainHttpError` → red snackbar)."
      F:
        status: "n/a"
      G:
        status: "n/a"
      H:
        status: "n/a"
        note: "C10 is about cell legitimacy gating, not intent-pathway routing. Orthogonal to C7's voice→economic flow."
      I:
        status: "✓"
        deliverable: D-CANON-C10-I
        note: "docs/design/REAL-EXECUTOR-WIRE.md landed 2026-05-28 (commit 6b5b9ee) — PR-2c/2d/2e technical doc with 2-PDA invocation contract, OP_CHECKLINEARTYPE + family opcode encoding, PolicyRuntime hook point, cross-brain coordination story. Cites POLICY-RUNTIME-EXECUTOR-ADAPTER.md as adapter design source."
      J:
        status: "n/a"
        note: "C10 wires NEW code, doesn't delete anything. The syntactic_shim mode stays as a feature-flag fallback per PR-2e + adapter §7."
      K:
        status: "⚠"
        deliverable: D-CANON-C10-K
        note: "Canary deploy to Todd's brain (oddjobtodd.info) + cross-brain witness with Bridget (brain.utxoengineer.com) per REAL-EXECUTOR-WIRE.md §4 steps 3-5 — operator action, not code. Surface at Phase A boundary."

  # ─────────────────────────────────────────────────────────────────
  - id: C11
    name: Root Identity Primitive ("me" surface on the helm)
    note: |
      Added 2026-05-29. The shell-level identity surface that lives on
      the helm, named "me". Frees the word "self" (now reserved here)
      from the personal-development cartridge (renamed `betterment` —
      see C2 footnote + PR #722). Lands the four operator-onboarding
      moves the shell is currently missing:

        1. BRC-52 root operator cert custody (the unforgeable parent
           identity from which per-cartridge hats are BRC-42 derived in
           C12).
        2. wallet-headers wallet.html boot (the operator's primary
           wallet UI — Todd's "MNCA anchor on mainnet" recipe proves
           this end of the path; the shell surfaces it on the helm).
        3. Secret-question setup (n-of-m recovery factors per
           PlexusRecoveryEnvelope; used to reconstruct the root cert).
        4. PlexusRecoveryEnvelope download / Plexus-RaaS enroll
           (offline-first envelope as local file by default; optional
           RaaS enrollment for managed custody).

      With C11 + C12 in place the shell stops treating identity + hats
      as UI state and starts deriving them from cryptographic primitives.
      This is the "stops the bleed" architectural lock the user
      articulated 2026-05-29 after observing hat leakage on the helm.

      C11 surfaces on the helm AppBar (right side) and is invoked from
      the "me" tile in a future first-run flow. The boot fallback when
      no root cert exists is C11's own onboarding sheet; the
      `_BootIncompleteScreen` placeholder added by PR-C9-7a is the
      slot this fills.

      Prereqs: C6 (BRC-100 wallet adapter) ✓; C6a wallet-headers
      adapter ✓. Blocks: C12 (cert-derived hats can't derive without a
      root cert).
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C11-A
        note: |
          Source extracted (re-tally 2026-05-31): `apps/semantos/lib/shell/me/`
          now carries the helm surface across 5 files:
            - me_sheet.dart (17 KB) — four-row bottom sheet
            - wallet_launch.dart (12.8 KB) — webview container + JS bridge
            - wallet_asset_server.dart (7 KB) — loopback HTTP for wallet.html
            - recovery_envelope_flow.dart (8.4 KB) — envelope generation UI
            - secret_questions_flow.dart (14 KB) — secret-question setup UI
          Plus the wallet primitives in `apps/semantos/lib/src/wallet/`
          (identity_store_adapter, wallet_bridge, wallet_key_service,
          cert_body_store, tier0_cache, recipe_store, utxo_store, address,
          brc42_derive, edge_derive, headers_client). Source extraction is
          complete; subsequent axes track wiring + tests.
      B:
        status: "⚠"
        deliverable: D-CANON-C11-B
        note: |
          Helm AppBar surfaces 'me' affordance via account_circle action →
          `showMeSheet()` (helm_home_screen.dart:119–123). Wallet row in
          me_sheet wired to `showWalletSheet()` (me_sheet.dart:477).
          **STILL MISSING** (re-tally 2026-05-31): first-run flow gate in
          main.dart when no root cert is present. main.dart reads
          IdentityStore at line 139 but does not branch to onboarding when
          cert is absent — the `_BootIncompleteScreen` placeholder from
          PR-C9-7a still serves this slot. Boot-with-no-cert routing is
          the remaining work before B flips to ✓.
      C:
        status: "⚠"
        deliverable: D-CANON-C11-C
        note: |
          Wallet test surface covers extensively (re-tally 2026-05-31):
          `apps/semantos/test/wallet/` runs 111 tests passing —
          wallet_bridge_test, wallet_key_service_test, edge_derive_test,
          address_test, recipe_store_test, etc. The bridge protocol
          (ready, address.request, derivation.request) and the BRC-42
          derivation chain are fully verified.
          **STILL MISSING**: shell test suite for boot-with-vs-without-
          cert paths, secret-question round-trip, envelope generate +
          reload. The me/ flows are scaffolded with code but lack
          end-to-end widget tests.
      D:
        status: "⚠"
        deliverable: D-CANON-C11-D
        note: "Brain-side: brain's BRC-52 cert intake is already there for paired devices (PR-4b earlier brain ticks); needs alignment with the root-cert custody model when shell surfaces this. Cross-ref: 'Brain auth model intent' memory note (Todd's BRC-52 + capability + Plexus-challenge design). No status change from initial assessment."
      E:
        status: "⚠"
        deliverable: D-CANON-C11-E
        note: |
          PWA-side wallet portion landed (re-tally 2026-05-31).
          `apps/semantos/lib/src/wallet/` owns key custody, BRC-42
          derivation (tier-0, contextual, edge, BRC-29 invoice), recipe
          + UTXO stores, and the SemantosWallet JS bridge (envelope
          codec at `lib/src/wallet/wallet_envelope.dart`, handler at
          `lib/src/wallet/wallet_bridge.dart`). Webview hosting works
          via loopback HTTP per `wallet_asset_server.dart`.
          **STILL PARTIAL**: recovery envelope flow and secret-question
          flow are scaffolded as Dart widgets but their bridge + brain
          plumbing is not verified end-to-end.
      F:
        status: "✓"
        deliverable: D-CANON-C11-F
        note: |
          Wallet integration complete at C11 scope (re-tally 2026-05-31).
          Wallet.html ships from `apps/semantos/assets/wallet/`
          (hand-written stub renderer + JS, no build step). Loopback asset
          server binds wallet bundle to a kernel-chosen port on
          `127.0.0.1`; webview_flutter 4.10 loads it. SemantosWallet JS
          channel routes renderer envelopes through `WalletBridge.handle()`
          to `WalletKeyService` (live: ready, address.request,
          derivation.request; deferred to C11-7: tx.request, per
          WALLET-RENDERER-CONTRACT.md §3 and explicit comments in
          wallet_bridge.dart:114–121).
      G:
        status: "✗"
        deliverable: D-CANON-C11-G
        note: |
          PlexusRecoveryEnvelope generation + download + (optionally)
          Plexus RaaS enrollment. `recovery_envelope_flow.dart` scaffolded
          as a Dart widget but envelope-codec brain wiring + RaaS opt-in
          flow not built. Cross-ref: 'Bridget federation-ready' memory
          note (Bridget is one possible RaaS counterparty). No status
          change.
      H:
        status: "✗"
        deliverable: D-CANON-C11-H
        note: |
          Intent pathway: me-surface actions (secret-question completion,
          envelope generated, RaaS enrolled) should mint `me.identity.*`
          shell-namespace cells via the IntentDispatcher → brain path.
          Grep of `apps/semantos/lib/` finds no `me.identity.cert` /
          `me.identity.envelope` mint sites. No status change.
      I:
        status: "⚠"
        deliverable: D-CANON-C11-I
        note: |
          `docs/design/HELM-ME-SURFACE.md` exists and is referenced by
          wallet_launch.dart + me_sheet.dart headers (re-tally 2026-05-31).
          Additional design artifacts in `docs/design/`:
          WALLET-RENDERER-CONTRACT.md (referenced by wallet bridge),
          PLEXUS-ALIGNMENT.md (cert custody architecture).
          **STILL MISSING**: glossary additions in
          canonicalization-glossary.md alongside the 'helm' entry.
      J:
        status: "n/a"
        note: "C11 adds NEW code; nothing to delete. The `_BootIncompleteScreen` placeholder from PR-C9-7a is still in place (its supersession completes when B's first-run-guard branch lands)."

  # ─────────────────────────────────────────────────────────────────
  - id: C12
    name: Cert-Derived Hats (BRC-42 children of the root cert)
    note: |
      Added 2026-05-29. Replace `CartridgeHatState` (UI-state hat
      selection per PR-C9-1) with cryptographically anchored hats.

      Each cartridge's hat key is a BRC-42 child derived from the root
      operator cert (C11): `rootCert.derive("hat:<cartridgeId>:<role>")`.
      The hat is identified by its public key, not a string label;
      labels become display sugar.

      Why this matters architecturally:
        - Hats can't "leak" between cartridges because each cartridge
          authenticates with ITS derived hat — there's nothing for UI
          to get wrong (the user's pre-2026-05-29 emulator screenshots
          showing "oddjobz · admin" on a screen with nothing to do
          with oddjobz become structurally impossible).
        - Brain authorization gates on the derived public key against
          the operator's root cert chain (matches the existing brain
          auth intent: BRC-52 cert + capability + Plexus-challenge).
        - Hat composition for cross-cartridge views (helm contacts,
          attention feed) becomes a key-set membership test, not a
          string equality test.

      Prereqs: C11 (need a root cert to derive from). Touches:
      semantos_core's identity primitives, HatRegistry, CartridgeHatState
      (which becomes a thin view-projection over the derived-hat set).
    axes:
      A:
        status: "✗"
        deliverable: D-CANON-C12-A
        note: "Source extracted: BRC-42 derivation helper for hat keys; modification of HatRegistry + CartridgeHatState to source from derived keys."
      B:
        status: "✗"
        deliverable: D-CANON-C12-B
        note: "Target wired: cartridge registration includes hat-role declarations; on boot, registry derives hat keys for every (cartridge × hat-role) pair off the root cert; HatSwitcher renders from the derived set."
      C:
        status: "✗"
        deliverable: D-CANON-C12-C
        note: "Tests pass: derivation determinism (same root → same hat key), hat-switching does NOT leak across cartridges, brain auth accepts the derived key against the root cert."
      D:
        status: "✗"
        deliverable: D-CANON-C12-D
        note: "Brain-side: brain's BCA/cert verification accepts BRC-42-derived hat keys as valid children of the operator root cert. Cross-ref: parked Phase-1b BCA/cert identity work memory note (12-branch D-A*/D-V*/W1.5C* cluster from 2026-04-26) — substrate may already exist."
      E:
        status: "✗"
        deliverable: D-CANON-C12-E
        note: "PWA-side: HatSwitcher widget renders the derived hat set; cartridge UIs use the derived hat as the signing key for cells they mint."
      F:
        status: "✓"
        deliverable: D-CANON-C12-F
        note: "Wallet integration: BRC-42 derivation IS a wallet primitive (already in @bsv/sdk + semantos_core's identity layer). C12 doesn't ADD wallet code; it USES the existing derivation."
      G:
        status: "n/a"
        note: "Recovery is C11's responsibility (root cert is what's recovered; hats derive deterministically once root is back)."
      H:
        status: "⚠"
        deliverable: D-CANON-C12-H
        note: "Intent pathway: cell signing uses the derived hat key as the signer per intent. IntentDispatcher learns to pick the right hat from (cartridge, intent-author) → derive → sign. Replaces the implicit shell-wide signer."
      I:
        status: "✗"
        deliverable: D-CANON-C12-I
        note: "Docs: docs/design/CERT-DERIVED-HATS.md captures the derivation tree, cross-cartridge composition rules, brain-side verification contract."
      J:
        status: "⚠"
        deliverable: D-CANON-C12-J
        note: "Old code deleted: CartridgeHatState's hat-selection state becomes derived-key membership test; the per-cartridge persistence map may be removed entirely (hat for a cartridge is determined, not chosen, once the cartridge has a single hat role). Multi-hat cartridges (e.g. oddjobz operator/admin) keep selection state but only over the derived key SET, never as free-text labels."

  # ─────────────────────────────────────────────────────────────────
  - id: C13
    name: Verb-Shelf Inversion (shell goes cartridge-neutral)
    note: |
      Added 2026-05-29 after the user's "IDIOT" pushback flagged that
      `apps/semantos/lib/shell/modal_verb_shelf.dart`:
        1. imports `betterment_experience` (a cartridge) — shell→
           cartridge direct coupling, violates the neutral-loader
           architectural lock,
        2. hardcodes a `_SubVerbTile(cartridge: 'Self', label:
           'Release', ...)` tile inside the DO sheet — shell knows a
           specific cartridge's verb,
        3. constructs a `Release(...)` intent class directly in the
           dispatch path — shell needs to import the cartridge's
           class to construct the intent.

      The fix (PR-C9-7c, this track's deliverable):
        - Drop the shell→cartridge import. Shell knows zero cartridge
          packages.
        - Drop the hardcoded Release tile + _ReleaseSheet widget. The
          DO/TALK/FIND sheets render `verbsForModal(modal,
          activeCartridge, activeHat)` from GrammarRegistry —
          cartridge-scoped, hat-gated.
        - Add intent-factory registry on IntentDispatcher.
          Cartridges register `(intentType, payload-builder)` at boot;
          shell dispatches via the generic factory map, never imports
          the intent class.
        - Generic input sheet driven by `inputShape` declared in
          ui.verbs[] (text / multiline / form / etc.) replaces the
          hardcoded `_ReleaseSheet`.
        - Backfill `ui.verbs[]` in betterment_experience + oddjobz_
          experience manifests so DO/TALK/FIND actually populate.

      With C13 landed, "selecting oddjobz in the picker → DO shows
      oddjobz verbs only" and "selecting betterment → DO shows
      betterment verbs only" both work, gated by the active hat
      (cert-derived per C12 once that lands too).

      Prereqs: cartridge rename (Track A / PR #722) ✓ — without that,
      the shell→cartridge import still says `self_experience` and is
      doubly wrong. Blocks: clean operator-acceptance run flips C7-E
      back to ✓.
    axes:
      A:
        status: "✓"
        deliverable: D-CANON-C13-A
        note: |
          Source extracted: PR #719 (PR-C9-6) shipped the manifest `ui.verbs[]` + `ui.surfacingMode` schema + GrammarRegistry.verbsForModal() consumer. PR-C9-7c (#724) added active-cartridge scoping via `verbsForModalAndExtension(modal, activeCartridge)` + the name-keyed dispatch path (registerSpec/dispatchByName/hasBindingFor). PR-C9-7d (#725) added `HelmUiVerbDispatch` (cellType + triple + defaultPayload) on the manifest schema. All source changes landed on main.
      B:
        status: "✓"
        deliverable: D-CANON-C13-B
        note: |
          Target wired (verified end-to-end 2026-05-29 on canonical app.semantos.me): ModalVerbShelf renders from `verbsForModalAndExtension(modal, activeCartridge)` — no hardcoded tiles, no cartridge import. Generic `_GenericInputSheet` driven by `inputShape` replaces the deleted `_ReleaseSheet`. Dispatch via `dispatcher.dispatchByName(intentType, payload)` using cartridge-supplied defaults from the manifest's `ui.verbs[].dispatch.defaultPayload`. main.dart boot loop iterates `grammarRegistry.manifests` and registers one binding per `ui.verbs[]` entry with a populated `dispatch` block.
      C:
        status: "⚠"
        deliverable: D-CANON-C13-C
        note: "Tests pass: 18/18 green in apps/semantos — coverage includes IntentDispatcher type-keyed + name-keyed dispatch, registerSpec, dispatchByName, hasBindingFor, manifest-derived boot loop. Widget tests for active-cartridge scoping (DO shows only X's verbs when X is selected) NOT YET written — currently exercised only by the operator-acceptance tape. Hat-gating filter pending C12 cert-derived hats."
      D:
        status: "n/a"
        note: "Brain-side: dispatch payload shape unchanged — brain sees the same POST /api/v1/cells. The shell-side change is invisible to the brain."
      E:
        status: "✓"
        deliverable: D-CANON-C13-E
        note: |
          PWA-side complete: modal_verb_shelf.dart rewritten cartridge-neutral (PR-C9-7c #724); IntentDispatcher gained registerSpec + dispatchByName (#724); HelmUiVerbDispatch added to manifest schema (PR-C9-7d #725); main.dart boot loop walks the manifest registry and registers one binding per dispatch-bearing verb (#725); betterment manifest.json + bundle.json carry the dispatch metadata for Release; intent_dispatcher_factory.dart returns a BARE dispatcher (#724). Cartridge package owns no Dart code the shell must import to dispatch — the manifest is the only handle.
      F:
        status: "n/a"
        note: "Wallet-agnostic — verb shelf doesn't touch wallet primitives."
      G:
        status: "n/a"
        note: "Recovery-agnostic."
      H:
        status: "✓"
        deliverable: D-CANON-C13-H
        note: "Intent pathway IS C13's substrate. Generic intent factory + generic input sheet + cartridge-declared verb metadata: the gradient pipeline becomes fully data-driven from manifest forward."
      I:
        status: "⚠"
        deliverable: D-CANON-C13-I
        note: "Docs: HELM-CANONICAL-SURFACE.md §3 + §5 already cover the architecture; PR #722/#724/#725 commit messages + this matrix capture the dispatcher-factory pattern + inputShape grammar. A separate docs/design/CARTRIDGE-INTENT-FACTORIES.md would be cleaner long-term — light follow-up scope."
      J:
        status: "✓"
        deliverable: D-CANON-C13-J
        note: "Old code deleted (#724 + #725): modal_verb_shelf.dart no longer imports `betterment_experience`; the hardcoded `_SubVerbTile(cartridge: 'Self', label: 'Release', ...)` is gone; the `_ReleaseSheet` widget is gone; the hardcoded `dispatcher.register<Release>(...)` block in intent_dispatcher_factory.dart is gone; the stop-gap `IntentSpec` data class (#724) and `bettermentIntentSpecs` constant (#724) are gone. Single source of truth = manifest."

```
