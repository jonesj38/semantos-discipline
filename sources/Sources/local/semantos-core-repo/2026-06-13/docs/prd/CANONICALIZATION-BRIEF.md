---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/CANONICALIZATION-BRIEF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.667768+00:00
---

# Canonicalization Brief — collapsing to two canonical units

**Status**: source of truth for the consolidation push. Opened 2026-05-27. Pre-mortem-mitigated revision 2026-05-27.
**Target**: two canonical, cartridge-decoupled units (PWA + brain) primed for voice→economic execution.
**Slice green target**: 2026-06-15 (~3 weeks).
**Full-scope target**: 2026-07-31 (~9 weeks).
**Companion matrix**: `docs/canon/canonicalization-matrix.yml`.
**Companion glossary** (C0): `docs/canon/canonicalization-glossary.md` — vocabulary lock.
**Companion golden slice** (C0/C7): `docs/canon/canonicalization-golden-slice.md` — the executable test fixture.
**Renderer**: `docs/canon/render/canonicalization-to-roadmap.ts` → `docs/prd/CANONICALIZATION-ROADMAP.md`.

---

## §1 — The thesis, said precisely

Semantos has accreted multiple parallel surfaces — `apps/semantos` (monolith with self + oddjobz baked in), `apps/semantos` (newer registry-driven architecture), `apps/oddjobz-mobile` (empty relic), plus a brain that statically compiles cartridge handlers into its binary. Every variant solves a slightly different version of the same problem; together they fragment effort and ship slower than any one of them alone.

The end-game is **exactly two functional units**:

1. **The Semantos PWA** — `apps/semantos`. A neutral cartridge loader that ships the substrate primitives — contacts/PKI, conversation, pask, wallet-headers + headless-wallet, key REPL, gradient intent pipeline (SIR→OIR→opcode→kernel), identity + recovery, hat-switching, manifest provisioning. Loads cartridges as plugin packages.

2. **The Semantos Brain** — `runtime/semantos-brain`. A neutral peer-node / server / root-operator host that ships the same primitives + dispatcher + bearer-gated REPL HTTP. Cartridges load as plugins via an extension-loader seam; the brain binary itself knows nothing about oddjobz, self, jam, tessera, etc.

Both units share the unified wallet (wallet-headers + headless-wallet + plexusRecoveryEnvelope) so that a Root Operator can recover their identity from a single envelope and immediately drive economic action via voice on either unit.

Both units share the **canonical helm**: a home/attention surface plus the `do | find | talk` modal verb shelf (canon per [`WALLET-VOICE-SHELL-GRAMMAR.md`](../design/WALLET-VOICE-SHELL-GRAMMAR.md)). Cartridges declare their UI relationship to helm in their manifest — `default` (uses the helm verb surface), `dedicated` (own UI replaces helm when active), `passive` (background, REPL-only), or `priority` (always-on-top slot). The REPL is universal: every cartridge verb is REPL-addressable regardless of UI mode.

Everything in the substrate is a cell; every cell can optionally be anchored to BSV via the unified wallet. The intent pathway (SIR→OIR→opcode→kernel→wallet) terminates either in a local-only cell mutation or in an on-chain anchor — that choice is per-verb policy, not per-unit.

When this lands, every dev hour goes into one PWA and one brain. Every cartridge runs in both. Every operator gets the same substrate.

---

## §2 — Why now

Three forces motivate consolidation this week:

1. **The emulator hit it directly.** Setting up the Android emulator (2026-05-27) surfaced three parallel candidates for "the app to run": `apps/semantos` (monolith on the phone), `apps/semantos` (the target architecture), `apps/oddjobz-mobile` (empty relic). Picking one of the three required surveying all three. That's a tax we'll keep paying until consolidation lands.

2. **Cartridge identity is muddled.** `packages/jam_experience` and `packages/tessera_experience` are dead-end cartridges that still ship in `main.dart`. `self` exists only as a manifest at `cartridges/betterment/cartridge.json` — no Flutter package yet. `oddjobz_experience` has a bearer-login + job-list view but the full UI (jobs/quotes/invoices/customers) is stranded in the monolith's `lib/src/helm/`.

3. **The wallet/recovery story is fragmented.** `cartridges/wallet-headers/brain/` has a vault + anchor pipeline; `cartridges/shared/anchor/headless-wallet.ts` is a separate minimal wallet built to bypass Metanet round-trips; the `plexusRecoveryEnvelope` design (the Root-Operator recovery story) hasn't bound to either. The user's "voice to economic execution" vision requires these be one surface.

---

## §3 — The eleven tracks (C0..C10)

The matrix tracks 11 units of work × 10 axes. Each axis represents a conformance dimension that must hold for a track to be "done". Brief tour:

| Track | Name | What it does |
|-------|------|--------------|
| **C0** | Decision Locks + Glossary + Golden Slice | The entry gate. Glossary locks vocabulary; golden slice (`canonicalization-golden-slice.md`) defines the C7 test fixture; decisions doc answers open questions. Nothing else gets a ✓ until C0 is green. |
| **C1** | PWA Primitive Forklift | Move substrate subsystems from `apps/semantos/lib/src/` into the canonical shell. **Slice-scope first** — only the subsystems on the C7 critical path; remaining ~8 deferred. |
| **C2** | PWA Cartridge Extraction | Create `packages/betterment_experience` (slice-scope V1); extract oddjobz UI from monolith into `packages/oddjobz_experience` (post-slice). **Aggressive excision**: off-slice monolith features get DELETED, not preserved — re-built later against the clean substrate. Licensed because oddjobz is not in production. |
| **C3** | PWA Canonicalization | Rename `apps/semantos` → `apps/semantos`. Delete monolith. Update every workspace ref. **Deferred until C7 slice green** — premature rename breaks in-flight branches. |
| **C4** | Brain Cartridge Extraction | Move cartridge-specific `.zig` files out of `runtime/semantos-brain/src/` into `cartridges/{oddjobz,self}/brain/zig/`. **Slice-scope first**: only the self-cartridge handler for V1; full set after slice green. |
| **C5** | Brain Extension Loader | Wire `extension_manifest_loader.zig` into `cli/serve.zig` dispatcher init. Define cartridge `registerInto(*Dispatcher)` contract. REPL verbs register here regardless of UI surfacing mode. **Slice-scope first**: contract used by self handler only; expand to all cartridges in full-scope phase. |
| **C6a** | Wallet Code Unification | Collapse wallet-headers + headless-wallet into one canonical wallet module that ships in both units. Pure refactor + test. On the slice critical path. |
| **C6b** | Plexus Recovery Envelope | Write the spec for plexusRecoveryEnvelope (concept → `docs/design/PLEXUS-RECOVERY-ENVELOPE.md`), then implement. Off-slice — uses bearer token for V1. Closes the auth-model split between PWA design intent and brain deployed reality. |
| **C7** | Voice→Economic Golden Slice | **REFRAMED**: not the acceptance gate at the end, but the FIRST executable test, written day 1, red until further notice, re-run on every track-✓ claim. Fixture in `canonicalization-golden-slice.md`. |
| **C8** | Aggressive Dead-End Removal | **REFRAMED** ("make it a nice place to explore not a schizo archeological maze"): default action is DELETE (git history preserves); ARCHIVE only what has unique experimental value. Runs as we go — every forklift session also deletes the parallel dead path. |
| **C9** | Helm + Surfacing Modes | Canonical helm (home/attention + `do\|find\|talk` verb shelf) ships in BOTH units. Cartridge manifest declares surfacing mode (default/dedicated/passive/priority). REPL universal. Contacts filtered by (hat, cartridge). |
| **C10** | Real Kernel Executor (PR-2b) | **Cross-brain substrate gate.** Today's PolicyRuntime is in `syntactic_shim` mode — accepts cells without semantic enforcement. The 2-PDA executor with OP_CHECKLINEARTYPE / OP_ASSERTLINEAR is stubbed (returns `real_executor_not_wired_yet`). PR-2b wires the real executor into both Todd's `cells_mint_handler.zig` + Bridget's `cell_handler.zig`. **Gates V2 anchor** — no point anchoring cells the substrate would later reject. Bridget's "wow-moment" FundRelease demo also gated on C10. |

### §3.1 — Helm as default UI + the DO\|TALK\|FIND model

The **helm** is the canonical home surface that ships in both units. It composes two things:

1. **Attention surface** — the inferred ranked feed of what to look at next ([Phase 39A live; AS1–AS5 spec'd](../design/HELM-ATTENTION-SURFACE.md)). Right-panel in PWA, equivalent panel in brain web.
2. **The DO\|FIND\|TALK verb shelf** — three modal verbs with a `who:what:why` payload, [canon'd in `WALLET-VOICE-SHELL-GRAMMAR.md`](../design/WALLET-VOICE-SHELL-GRAMMAR.md):
   - **`do`** — state-mutating action; 5 substrate sub-verbs (`new`, `patch`, `transition`, `sign`, `publish`); hat-gated, Verifier-Sidecar-enforced
   - **`find`** — read-only retrieval; 4 substrate sub-verbs (`inspect`, `list`, `trace`, `verify`); pure VFS query + render
   - **`talk`** — conversational scope; opens a chat with self / object / another hat; each turn is itself a `do|find|talk` utterance

Voice utterance, typed REPL, and tap-to-act on a helm card all route through the **same** verb dispatcher. The voice path uses the LLM as parser-aid, not controller.

### §3.2 — Cartridge surfacing modes

Cartridges declare how they relate to the helm in their `cartridge.json` under `ui.surfacingMode`:

| Mode | When to use | Examples |
|------|-------------|----------|
| **`default`** | Cartridge consumes the shell's helm verb surface — operator sees its objects on the attention surface, addresses them with `do/find/talk` | `oddjobz`, `self` |
| **`dedicated`** | Cartridge has a fundamentally different UI than helm (e.g. a live audio mixer, a chess board) and displaces helm when active | `jam-room`, `chess` |
| **`passive`** | Cartridge runs in the background, no helm surfacing, REPL-only access | `wallet-headers`, `cell-relay` |
| **`priority`** | Cartridge claims an always-on-top helm slot (rare; e.g. an emergency-comms cartridge that must surface immediately) | (none currently) |

**Crucially**: surfacing mode controls UI presentation only. Every cartridge — `default`, `dedicated`, `passive`, `priority` — registers its REPL verbs via the C5 extension-loader seam. A jam operator can `find | self | recordings --since '1 week ago'` even though jam owns its own UI. Wallet-headers exposes `find | wallet | balance` even though it has no UI at all.

### §3.3 — Contact presentation: hat + cartridge filter

Contacts are universally available (PKI substrate, C1 primitive). The presentation layer filters them by the active (hat, cartridge) tuple:

- `oddjobz` hat + `oddjobz` cartridge → customers, contractors, REAs primary
- `self` hat + `self` cartridge → personal circle primary
- `oddjobz` hat + `jam-room` cartridge → fellow bandmates primary (cartridge takes precedence on dedicated surface)

Filter rules come from the cartridge manifest's `peerView` field (already present in `cartridges/oddjobz/cartridge.json` — extend the schema for the canonical filter contract).

### §3.4 — Everything is cells, everything is optionally anchorable

The intent pathway terminates in one of two places per-verb:
- **Local** — cell mutation in the local store, no on-chain artifact (most reads; cheap writes)
- **Anchored** — cell mutation + BSV anchor via the unified wallet (high-stakes writes, audit-trail-required actions)

The choice is per-verb policy declared in the cartridge manifest (`verbs[].anchor: required | optional | never`), enforced at dispatch time. No UI surface fork; no wallet code fork. The unified wallet (C6) is the single anchor path for both units.

---

### §3.5 — Thin-slice scope (post-mortem mitigation #1)

The canonicalization is gated on ONE operator action — the **golden slice** — exercising every layer end-to-end. Every track is first scoped to the slice critical path; off-path work is a separate, deferred phase.

**Chosen V1 slice** (see [`canonicalization-golden-slice.md`](../canon/canonicalization-golden-slice.md) for the full trace):

> Operator says into helm mic: *"release: I'm letting go of the pressure to make every interaction perfect."*
>
> Resolves to `do | betterment | release` → cartridge `self`, flow `daily-release`, sub-verb `do.new`, creates one `betterment.practice.release` cell, signed with hat:self key, persisted in brain, rendered as helm card. Anchor optional (deferred to V2 slice).

Why this one:
- **Self cartridge** has fewer accreted deps than oddjobz — smaller blast radius for C1+C2 first pass.
- **`do.new`** is the simplest of the 5 do-subverbs to wire end-to-end.
- **No external counterparty** (no contact lookup, no customer dereference) — minimum surface.
- **`anchor: optional`** lets V1 skip chain; V2 turns it on.
- **Operator-natural** — Todd actually does this practice.

Per-layer track contribution to the slice critical path:

| Track | Slice-scope work | Full-scope work (deferred) |
|-------|------------------|----------------------------|
| **C0** | All of it — glossary + slice spec + decisions doc | — |
| **C1** | Forklift `identity`, `voice`, `gradient`, `repl`, `talk` (SIR scope only), `shell` (helm host) | 8 other primitives |
| **C2** | Create minimal `packages/betterment_experience/` rendering release flow + card | Oddjobz full extraction |
| **C3** | Nothing — rename deferred | All of C3 |
| **C4** | Move self handler for `do.new betterment.practice.release` | All other brain handlers |
| **C5** | Generic `registerInto` contract, used by self handler only | Extension loader for all cartridges |
| **C6a** | `sign(hash, hat:self)` from PWA WalletService + brain HTTP | Full wallet parity |
| **C6b** | Off-slice. Spec writing in parallel | Implementation |
| **C7** | The fixture + runner stub | — |
| **C8** | Delete dead code touched by C1/C2/C4 as we go | Bulk archival |
| **C9** | Helm widget rendering verb shelf + release card; `default` surfacing mode only | `dedicated`/`passive`/`priority` modes |

## §4 — The ten axes

| Axis | Name | What it means |
|------|------|---------------|
| **A** | Source extracted | Files moved/created at target location |
| **B** | Target wired | Imports, registries, dispatchers hooked up |
| **C** | Tests pass | Existing test surface green in new location |
| **D** | Brain-side | Companion brain-side change landed (if applicable) |
| **E** | PWA-side | Companion PWA-side change landed (if applicable) |
| **F** | Wallet integration | Unified wallet wired through (C6) |
| **G** | Recovery envelope | plexusRecoveryEnvelope coverage for the unit |
| **H** | Intent pathway | Gradient pipeline (SIR→OIR→opcode→kernel) flows through |
| **I** | Docs | CLAUDE.md / module README / canon doc updated |
| **J** | Old code deleted | Zero remaining references to legacy path |

A track is **done** when every applicable cell is `✓`. `n/a` cells are explicit "doesn't apply here" — not pending work.

---

## §5 — Scope, in + out

### In scope

- All consolidation of Flutter app sources under `apps/`.
- All consolidation of brain Zig sources under `runtime/semantos-brain/src/`.
- All cartridge package restructure under `packages/`.
- Wallet unification across both canonical units.
- Documentation: CLAUDE.md, module READMEs, this brief + the matrix.

### Out of scope

- `apps/oddjobtodd` — external concern (the marketing site at oddjobtodd.info).
- The `cartridges/wallet-headers/brain/` brain-side TS code stays as a cartridge brain; C6 unifies the surface, not the location.
- The MNCA layer-collapse + C6 device tracks continue in parallel — canonicalization is a substrate cleanup, not a redirection of the demo program.
- Migration of any data on a running brain. The user's brain on `rbs` already has live bearer tokens + state; canonicalization is an architecture cleanup that doesn't require a data migration.

---

## §6 — Dependencies + ordering

Hard dependency edges:

- **C2** depends on **C1**: cartridges register against the shell's CartridgeRegistry which only exists after primitives are forklifted.
- **C3** depends on **C1 + C2**: cannot rename the shell while the monolith still imports its own subsystems.
- **C5** depends on **C4**: extension loader can't load handlers that haven't been moved into cartridge dirs yet.
- **C7** depends on **C1 + C4 + C5 + C6**: the voice→economic acceptance gate exercises every layer.
- **C0** gates everything. Until glossary + slice + decisions are locked, no other track can claim any ✓.
- **C7** is the executable gate from day 1 — its `A` axis (the fixture exists and runs red) is part of C0. Every other track's `C` axis (tests pass) requires re-running C7 and reporting the new state.
- **C8** runs continuously alongside every track — we delete dead code as we touch it.
- **C9** depends on **C1** (helm primitives come from monolith's `shell` + `talk` + `voice` subsystems) and informs **C2** (cartridges declare surfacing mode when extracted). **C9** also depends on **C5** (REPL verb registration is the universal access seam).
- **C6b** depends only on writing the plexusRecoveryEnvelope spec — runs in parallel, not on the slice critical path.
- **V2 anchored slice** depends on **C10** (cell legitimacy). Re-prioritized 2026-05-28 — V2 anchor work paused until PR-2b lands. Anchoring cells the substrate would later reject is worse than not anchoring; legitimacy first.
- **C10** is cross-brain substrate work (benefits Bridget's brain + Todd's brain equally). Coordinate with Bridget's team — if PR-2b lands on her brain first, Todd's brain absorbs the same wire.

Sequence to slice green:

```
  C0 locks ──► C7 fixture runs red ──┐
                                      │
                                      ▼
  C1 (slice-scope) ──► C2 (slice-scope) ──► C9 (helm slice) ──┐
                                                                ├──► C7 GREEN
  C4 (slice-scope) ──► C5 (slice-scope contract) ──────────────┤
                                                                │
  C6a (slice-scope) ──────────────────────────────────────────► ┘

  C8 dead-end deletion runs alongside every step
  C6b spec writing runs in parallel (off-slice)
  C3 rename deferred until C7 green
```

Sequence after slice green (full-scope phase):

```
  C7 V1 GREEN ──► C10 (real executor wire — cell legitimacy gate) ──┐
                                                                     │
                                                                     ▼
                                                              ┌─► V2 anchor (now legitimate cells)
                                                              │
              C1 full ──► C2 full ──► C3 rename ──────────────┤
                                                              ├──► canonicalization done
              C4 full ──► C5 full ──────────────────────────► │
                                                              │
              C6b implementation ──────────────────────────► │
                                                              │
              C8 bulk archival of remaining experiments ───► ┘
```

**V2 anchor PAUSED behind C10** per user direction 2026-05-28: "we shouldn't focus on anchoring until the cells are legitimate". Bridget's brain hit this gap first (her FundRelease wow-moment needs the executor to enforce purpose-matching); Todd's brain has the same gap on general cell semantics. Land C10 once across both brains via substrate work.

---

## §7 — Definition of done

The canonicalization push is done when **all of the following** hold:

1. `apps/semantos` exists, is the only Flutter app the team builds, and runs on Android emulator + iOS simulator + Chrome web + macOS desktop.
2. `apps/semantos`, `apps/semantos` (monolith), `apps/oddjobz-mobile` are gone from the active tree (archived or deleted).
3. `runtime/semantos-brain/src/` contains zero files with cartridge names (no `oddjobz_*`, no `self_*`, no `tessera_*`).
4. `extension_manifest_loader.zig` is the only path by which cartridge handlers reach the brain dispatcher.
5. One canonical wallet module is consumed by both the PWA's `WalletService` and the brain's HTTP surface.
6. A Root Operator can load a `plexusRecoveryEnvelope` and have a functional identity (cert + derivation seed + recovery anchor) on both units within minutes.
7. The C7 voice→economic test passes end-to-end on the canonical pair: voice utterance produces a signed cell + economic action traceable through the gradient pipeline log.
8. `archive/README.md` records what was archived, when, and why.
9. Helm ships as the canonical default UI in both units. Cartridge manifests declare `ui.surfacingMode` and the SemantosRouter respects it. REPL verbs are registered for every cartridge regardless of UI mode. Voice + typed REPL + helm-card-tap all route through the same `do|find|talk` dispatcher.

---

## §8 — Decisions log

- **2026-05-27** — User confirmed: `jam_experience` + `tessera_experience` are dead ends, archive both. All ambiguous apps (mud, world-apps, poker-agent, settlement, piggybank, navigation_app, demo-wasm-threejs) archive as experiments. Canonical name is `semantos` (rename `semantos-shell` → `semantos` after migration completes). `apps/oddjobtodd` is an external concern, untouched.
- **2026-05-27** — Canonicalization opened as a tracked effort; matrix + brief + roadmap renderer created in same session.
- **2026-05-27** — C9 added (helm + cartridge surfacing modes). Confirmed canon: `do|find|talk` per WALLET-VOICE-SHELL-GRAMMAR.md (5 do-subverbs, 4 find-subverbs, talk-as-scope). Confirmed naming clash: monolith's `lib/src/helm/` is oddjobz dashboard, must rename when moved to `oddjobz_experience` so "helm" is reclaimed as the canonical default-UI primitive. Confirmed surfacing modes: `default | dedicated | passive | priority`. Confirmed REPL universality regardless of UI mode. Confirmed everything-is-cells / optionally-anchorable terminating in the unified wallet.
- **2026-05-27** — Pre-mortem ran (6-month forward look). 14 failure modes identified. Plan restructured around 14 mitigations (§11). Key changes: **C0 added** (locks: glossary + golden slice + decisions); **C7 reframed** as day-1 executable test, not end acceptance; **C6 split** into C6a (wallet code unification, on-slice) + C6b (plexusRecoveryEnvelope spec then implementation, off-slice); **C8 reframed** from archival to aggressive delete-as-we-go; **thin-slice principle** applied — every track scoped first to one golden-slice critical path. Confirmed by user: oddjobz NOT in production, so aggressive excision of off-slice features is licensed (rebuild later on clean substrate).
- **2026-05-27** — Open questions enumerated in `canonicalization-golden-slice.md` §6 — must be answered in `canonicalization-decisions.md` before C1 code moves: (1) STT path on-device vs brain upload, (2) helm Flutter widget vs webview, (3) cell-store local vs brain-roundtrip, (4) wallet key custody location, (5) `anchor: optional` default behavior.
- **2026-05-27** — All 8 open decisions **LOCKED** in `canonicalization-decisions.md`. C1 unblocked. Headlines: brain upload STT for V1 (Q1), native Flutter helm widget (Q2), brain-roundtrip cell-store for V1 (Q3), reuse IdentityStore for wallet custody (Q4), default-local anchor (Q5), **two-tier verb canon anchored to CSD 1-3-5-3-1 — helm L3 surfaces 5 do + 4 find; REPL/voice access full 22 substrate** (Q6), side-by-side phone install (Q7), monolith → `archive/` on C7 green, delete at full-scope done (Q8). C0-A and C0-I matrix cells go ✓; C0-C (executable test stub) stays ⚠ until the test scaffolding lands.
- **2026-05-28** — V1 slice CODE-GREEN. End-to-end operator path verified: canonical PWA → live brain mint at oddjobtodd.info → helm card render. C1-A, C7-D, C7-E, C7-C, C9-A all flipped ✓. Real cell minted via PWA tap: `5977ce15993afa7dce855b093e8f6f50d48f1a29cc1425fec1634e02f9355c9a`.
- **2026-05-28** — **V2 anchor work paused; C10 added as priority.** Bridget's brain Claude-developer surfaced that the kernel-rejection promise of Semantos doesn't work today: PolicyRuntime runs in `syntactic_shim` mode (validates frame structure but no semantic enforcement). The 2-PDA real executor with custom Semantos opcodes (OP_CHECKLINEARTYPE, OP_ASSERTLINEAR, 0xC0-0xCF range) is stubbed — returns `real_executor_not_wired_yet`. PR-2b in Todd's roadmap wires it. **User direction**: "we shouldn't focus on anchoring until the cells are legitimate, then return to v2 slice". C10 (Real Kernel Executor / PR-2b) added to matrix as cross-brain substrate track — single wire benefits both Todd's `cells_mint_handler.zig` + Bridget's `cell_handler.zig`. V2 anchor work deferred behind C10.

### §8.1 — Open decisions (block C1 code moves)

These must be answered explicitly in `docs/canon/canonicalization-decisions.md` before any track moves code:

1. **STT path** — on-device whisper.cpp (FFI) vs brain `/api/v1/voice-extract` upload
2. **Helm Flutter widget vs webview** — native vs webview-hosting-brain-web-surface
3. **Cell-store on canonical PWA** — local sqflite/idb store vs roundtrip-everything-through-brain
4. **Wallet key custody** — Android Keystore (existing) vs unified-wallet self-custody
5. **`anchor: optional` default** — local-only by default vs chain by default when operator doesn't specify
6. **5 do-subverbs canon binding** — confirm `new/patch/transition/sign/publish` matches existing parser, not a competing set
7. **Phone update strategy** — when does Todd's phone get the canonical PWA replacing the monolith? (Pre-mortem failure mode #11)
8. **Monolith deletion timing** — confirm "after C7 slice green + 2 weeks of canonical-PWA daily use" or different bar

---

## §8.2 — Cross-brain substrate coordination (Bridget)

C10 (Real Kernel Executor / PR-2b) is **cross-brain substrate work**, not Todd-brain-specific. The 2-PDA executor + custom Semantos opcodes (OP_CHECKLINEARTYPE, OP_ASSERTLINEAR, etc.) live in `core/cell-engine/` — the shared kernel that both Todd's brain and Bridget's brain (Traceport / FundRelease cartridge) consume.

Surfaced 2026-05-28 by Bridget's brain developer/Claude investigating why her FundRelease wow-moment doesn't enforce: PolicyRuntime is in `syntactic_shim` mode in BOTH brains. The real executor returns `real_executor_not_wired_yet` until PR-2b lands.

Coordination opportunity:
- **Bridget's brain** has the cleanest forcing-function — her FundRelease purpose-matching is a concrete acceptance test for the executor (mismatched purpose → reject). Smaller, more testable surface than Todd's general cell semantics.
- **Todd's brain** absorbs the same wire change when it lands (PolicyRuntime invocation patches identically).
- **Land once at the substrate**, both brains benefit. Per Bridget's investigation: PolicyRuntime → real-executor call site is the single change point.

If Bridget's team picks up PR-2b first, Todd's brain can rebase the same change. If Todd's team picks it up first, Bridget gets her wow-moment demo. Either way, V2 anchor (deferred) becomes meaningful only after C10 — anchoring legitimate cells is the value, not anchoring any cell.

---

## §9 — Anti-goals

These are NOT what canonicalization is trying to do, and confusion about them would derail it:

- **Not** a rewrite of substrate primitives. The substrate code (cell-engine, pask kernel, identity primitives, gradient pipeline) already exists; we move and unify. **BUT** — new construction IS expected on the helm-in-brain web surface, the cartridge `registerInto` contract, the build.zig cartridge-Zig integration, the plexusRecoveryEnvelope spec, and the manifest `surfacingMode` field. The honest rule: **new code only on the slice critical path**. Off-path new construction is deferred. (Post-mortem mitigation: previous version of this anti-goal said "no new code" — that was false and led to under-rigored new construction.)
- **Not** a redesign of cartridges. The cartridge model (`registerXCartridge()`, `XManifestLoader.provisionFromAsset()`, `CartridgeRegistry.instance`) is correct as it stands. C2 just makes more code use it correctly.
- **Not** a freeze on substrate work. MNCA, C6 device firmware, the BSV anchor pipeline all continue. Canonicalization runs alongside.
- **Not** "preserve every monolith feature." Per user 2026-05-27, oddjobz is not in production. Off-slice features get DELETED on extraction, not forklifted — they return later, rebuilt against the clean substrate. Aspirational ≠ load-bearing.
- **Not** an unbounded matrix. The 10 tracks (C0..C9) are the matrix. New architectural axes that surface in conversation get their own brief, not a new column. Post-mortem mitigation #5.
- **Not** an unscheduled effort. **Slice green (V1) by 2026-06-15** (~3 weeks from start). Full-scope completion targeted at 2026-07-31 (~9 weeks). C6b spec writing on its own track. Realistic pacing, not the previous "2-week intense push" fantasy that drove the previous overrun in the post-mortem.

---

## §10 — Cross-references

- Companion matrix: `docs/canon/canonicalization-matrix.yml`
- Companion roadmap (generated): `docs/prd/CANONICALIZATION-ROADMAP.md`
- Renderer: `docs/canon/render/canonicalization-to-roadmap.ts`
- Pattern source: `docs/canon/singularity-matrix.yml` + `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md`
- Pattern source: `docs/canon/unification-matrix.yml` + `docs/prd/UNIFICATION-ROADMAP.md`
- Cartridge model canon: `docs/design/CANONICAL-CARTRIDGE-MODEL.md`
- Helm + verb grammar canon (C9): `docs/design/WALLET-VOICE-SHELL-GRAMMAR.md` (do|find|talk modal grammar) + `docs/design/HELM-ATTENTION-SURFACE.md` (attention surface AS1–AS5)
- Sample cartridge manifest with `ui` + `peerView` fields: `cartridges/oddjobz/cartridge.json`
- **C0 artifacts**: `docs/canon/canonicalization-glossary.md` (vocabulary lock) + `docs/canon/canonicalization-golden-slice.md` (C7 fixture)
- Memory: `[[shell-cartridges-hats-model]]`, `[[semantos-streams-shell-native]]`, `[[semantos-no-ai-in-substrate]]`, `[[semantos-dx-priorities]]`

---

## §11 — Pre-mortem mitigations

Captured 2026-05-27 after a 6-month forward post-mortem identified the failure modes the previous plan was prone to. Each mitigation maps to a structural change in C0–C9 or this brief.

| # | Failure mode it prevents | Mitigation | Where it lives in the plan |
|---|--------------------------|------------|----------------------------|
| **1** | Forklift braided dependencies → every "one subsystem" became a 3-subsystem move | **Thin-slice principle**: pick ONE operator action, scope every track to its critical path first | §3.5 + golden slice doc + slice-scope notes in C1/C2/C4/C5/C6a/C9 matrix cells |
| **2** | C7 was vapor — "passes end-to-end" had no fixture | **C7 first, executable on day 1, red until green**. Golden slice doc IS the fixture. Every track-✓ claim re-runs the test | C0 + reframed C7 in matrix; `canonicalization-golden-slice.md` |
| **3** | C5 build.zig cartridge-Zig integration disguised as wiring | **Slice-scope C5**: V1 uses the contract for self handler only; expand to all cartridges in full-scope phase after V1 green | C5 matrix cell + §3.5 |
| **4** | C6 carried unwritten spec (plexusRecoveryEnvelope) as if it were unification | **Split C6 into C6a (wallet code) + C6b (recovery spec)**. C6b writes a spec first, off-slice. C6a is pure refactor, on-slice. Slice uses bearer token until C6b lands | C6 split in matrix; brief §3 + §6 |
| **5** | "Oh and also" architectural axes kept growing matrix (C9 was bolt-on; more were latent) | **Cap matrix at C0–C9**. New axes get their own brief, not new columns | §9 anti-goals |
| **6** | "Not a rewrite" anti-goal was false and led to under-rigored new construction | **Honest anti-goal**: "new code only on slice critical path." Acknowledges what new construction is required | §9 anti-goals |
| **7** | Dead code lingered "for safety" creating archaeological-maze codebase | **Delete-as-we-go**: every forklift session deletes the parallel dead path. Git is safety | C8 reframed in matrix + §3 |
| **8** | Preserving every monolith feature blocked aggressive consolidation | **Aggressive excision**: oddjobz not in production → off-slice features get deleted, rebuilt later against clean substrate | §9 anti-goals + C2 matrix cell |
| **9** | Vocabulary drift ("the 5 verbs" meant three different things) | **Glossary as canonical source**: one definition per term, disputes resolve there | `canonicalization-glossary.md` |
| **10** | Naming churn during in-flight branches broke parallel sessions | **C3 rename deferred until C7 slice green**. Single-branch sweep when ready | C3 matrix cell + §6 |
| **11** | Phone-pass ≠ emulator-pass and there was no plan for the bridge | **Slice runs on canonical PWA against live brain from day 1**. Phone-pass is part of the V1 slice acceptance, not deferred | Golden slice §3 |
| **12** | Bearer-token auth (deployed) vs BRC-52 cert + cap (design intent) never reconciled | **C6b explicitly closes the auth-model split**, not just wallet code | C6 matrix cell + glossary `Root Operator` |
| **13** | Matrix never went green because total cells grew faster than ✓ count | **Track count capped (§9)** + slice-scope keeps per-track ✓ achievable within one session | §3.5 + §9 |
| **14** | Realistic pacing replaced by aspirational "2-week intense push" | **Concrete dates**: V1 slice green by 2026-06-15; full-scope done by 2026-07-31. Adjust on miss, don't pretend on miss | §9 anti-goals |
