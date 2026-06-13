---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/CANONICALIZATION-ROADMAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.670755+00:00
---

# Canonicalization Roadmap — collapsing to two canonical units

> Rendered from `docs/canon/canonicalization-matrix.yml`. Do not edit this
> document directly — edit the YAML and re-run
> `bun docs/canon/render/canonicalization-to-roadmap.ts > docs/prd/CANONICALIZATION-ROADMAP.md`.

Companion document: [`docs/prd/CANONICALIZATION-BRIEF.md`](./CANONICALIZATION-BRIEF.md).

## §1. The thesis

Semantos collapses into exactly **two canonical units**: a neutral PWA
(`apps/semantos`) and a neutral brain (`runtime/semantos-brain`). Both
ship the substrate primitives — contacts/PKI, conversation, pask,
wallet-headers + headless-wallet, key REPL, gradient intent pipeline,
identity + plexus recovery — and load cartridges as plugins. Together
they are primed for voice→economic execution with recoverable
Root-Operator onboarding.

The matrix below tracks the **8 consolidation tracks × 10 conformance
axes**. Each ✓ cell is a verifiable claim that the (track, axis) pair
is done.

## §2. The matrix

| Track | A. Extract | B. Wired | C. Tests | D. Brain | E. PWA | F. Wallet | G. Recov | H. Intent | I. Docs | J. Deleted |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **C0 Decision Locks + Glossary + Golden Slice** | ✓ D-CANON-C0-A | n/a | ✓ D-CANON-C0-C | n/a | n/a | n/a | n/a | n/a | ✓ D-CANON-C0-I | n/a |
| **C1 PWA Primitive Forklift** | ✓ D-CANON-C1-A | ✗ D-CANON-C1-B | ✗ D-CANON-C1-C | n/a | ✗ (All of C1's work IS PWA-s…) | ⚠ D-CANON-C1-F | ✗ D-CANON-C1-G | ✗ D-CANON-C1-H | ✗ D-CANON-C1-I | ✗ D-CANON-C1-J |
| **C2 PWA Cartridge Extraction** | ✓ D-CANON-C2-A | ✓ D-CANON-C2-B | n/a | ✗ D-CANON-C2-D | ✗ (C2 is PWA-side; brain pie…) | n/a | n/a | ✓ D-CANON-C2-H | ⚠ D-CANON-C2-I | ⚠ D-CANON-C2-J |
| **C3 PWA Canonicalization** | ✓ D-CANON-C3-A | ✓ D-CANON-C3-B | ✓ D-CANON-C3-C | n/a | ✓ (C3 IS the PWA rename + cl…) | n/a | n/a | n/a | ✓ D-CANON-C3-I | ✓ D-CANON-C3-J |
| **C4 Brain Cartridge Extraction** | ✓ D-CANON-C4-A | ✓ D-CANON-C4-B | ✓ D-CANON-C4-C | ✓ D-CANON-C4-D | n/a | n/a | n/a | ✓ D-CANON-C4-H | ⚠ D-CANON-C4-I | ⚠ D-CANON-C4-J |
| **C5 Brain Extension Loader** | ⚠ D-CANON-C5-A | ✗ D-CANON-C5-B | ✗ D-CANON-C5-C | ✗ (C5 IS the brain-side seam.) | n/a | n/a | n/a | ⚠ D-CANON-C5-H | ✗ D-CANON-C5-I | ✗ D-CANON-C5-J |
| **C6 BRC-100 Wallet + Plexus Recovery** | ✓ D-CANON-C6-A | ⚠ D-CANON-C6-B | ✓ D-CANON-C6-C | ⚠ D-CANON-C6-D | ✗ D-CANON-C6-E | ⚠ (C6 IS the wallet integrat…) | ✗ D-CANON-C6-G | ⚠ D-CANON-C6-H | ✗ D-CANON-C6-I | ✗ D-CANON-C6-J |
| **C7 Voice→Economic Golden Slice** | ✓ D-CANON-C7-A | ⚠ D-CANON-C7-B | ✓ D-CANON-C7-C | ✓ D-CANON-C7-D | ✓ D-CANON-C7-E | ✗ (Depends on C6.) | ✗ (Depends on C6 — a freshly…) | ✗ (C7 IS the end-to-end inte…) | ✗ D-CANON-C7-I | n/a |
| **C8 Aggressive Dead-End Removal** | ✓ D-CANON-C8-A | ⚠ D-CANON-C8-B | n/a | ✗ D-CANON-C8-D | ⚠ D-CANON-C8-E | n/a | n/a | n/a | ✓ D-CANON-C8-I | ⚠ D-CANON-C8-J |
| **C9 Helm + Surfacing Modes** | ✓ D-CANON-C9-A | ✓ D-CANON-C9-B | ✗ D-CANON-C9-C | ✗ D-CANON-C9-D | ✗ D-CANON-C9-E | n/a | n/a | ✗ D-CANON-C9-H | ✓ D-CANON-C9-I | ✗ D-CANON-C9-J |
| **C10 Real Kernel Executor (PR-2b — Cell Legitimacy Gate)** | ✓ D-CANON-C10-A | ✓ D-CANON-C10-B | ✓ D-CANON-C10-C | ✓ D-CANON-C10-D | n/a | n/a | n/a | n/a | ✓ D-CANON-C10-I | n/a |
| **C11 Root Identity Primitive ("me" surface on the helm)** | ✓ D-CANON-C11-A | ⚠ D-CANON-C11-B | ⚠ D-CANON-C11-C | ⚠ D-CANON-C11-D | ⚠ D-CANON-C11-E | ✓ D-CANON-C11-F | ✗ D-CANON-C11-G | ✗ D-CANON-C11-H | ⚠ D-CANON-C11-I | n/a |
| **C12 Cert-Derived Hats (BRC-42 children of the root cert)** | ✗ D-CANON-C12-A | ✗ D-CANON-C12-B | ✗ D-CANON-C12-C | ✗ D-CANON-C12-D | ✗ D-CANON-C12-E | ✓ D-CANON-C12-F | n/a | ⚠ D-CANON-C12-H | ✗ D-CANON-C12-I | ⚠ D-CANON-C12-J |
| **C13 Verb-Shelf Inversion (shell goes cartridge-neutral)** | ✓ D-CANON-C13-A | ✓ D-CANON-C13-B | ⚠ D-CANON-C13-C | n/a | ✓ D-CANON-C13-E | n/a | n/a | ✓ D-CANON-C13-H | ⚠ D-CANON-C13-I | ✓ D-CANON-C13-J |

_14 tracks, 10 axes — 42 ✓ / 24 ⚠ / 36 ✗ / 38 n/a._

## §3. Legend

### Axis legend

- **A. Extract** — source files moved or created at target location
- **B. Wired** — imports, registries, dispatch tables hooked up at target
- **C. Tests** — existing test surface green in new location
- **D. Brain** — companion brain-side change landed (if applicable)
- **E. PWA** — companion PWA-side change landed (if applicable)
- **F. Wallet** — wallet-headers/headless-wallet integration wired (C6 surface)
- **G. Recov** — plexusRecoveryEnvelope coverage for the unit
- **H. Intent** — gradient pipeline (SIR→OIR→opcode→kernel) flows through
- **I. Docs** — CLAUDE.md / module README / canon doc updated
- **J. Deleted** — zero remaining references to legacy path

### Status legend

- ✓ implemented, tested, verifiable
- ⚠ partial / in progress / unverified
- ✗ not started
- n/a not applicable for this (track, axis) pair

## §4. Track notes

### C0 Decision Locks + Glossary + Golden Slice

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

### C1 PWA Primitive Forklift

Move the 14 substrate subsystems out of the monolith
`apps/semantos/lib/src/` and into the canonical shell at
`apps/semantos/lib/src/` (later renamed to `apps/semantos/`).
Dependency-respecting order: identity → contacts → pairing → mesh →
repl → pask → talk → voice → gradient → outbox → push → sensors →
theme → shell. Each forklift includes its tests + any FFI bindings.
Subsystems are PRIMITIVE per the C1 survey — they ship in the
neutral loader regardless of which cartridges are installed.

### C2 PWA Cartridge Extraction

The monolith carries cartridge UI directly in its lib/src tree:
`helm/` (full jobs/quotes/invoices/customers/leads UI), `attachments/`,
`ratification/` belong to oddjobz; `self/` belongs to self. Extract
them out of the monolith and into proper cartridge packages so they
load into the canonical shell via the same CartridgeRegistry path as
any third-party cartridge.

### C3 PWA Canonicalization

With primitives (C1) and cartridges (C2) migrated, rename
`apps/semantos` → `apps/semantos` and delete the monolith.
Update Android applicationId to a stable canonical
(`info.semantos.shell` or similar — confirm with user). Update all
pubspec paths, CI configs, deploy scripts that reference either old
app path. The phone artifact built from the canonical app should
be functionally identical to the old monolith from the operator's
POV.

### C4 Brain Cartridge Extraction

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

### C5 Brain Extension Loader

extension_manifest_loader.zig exists but isn't wired into the
dispatcher initialization. C5 builds the seam: (1) discover cartridge
handlers via manifest, (2) call each cartridge's `pub fn registerInto(disp:
*Dispatcher)`, (3) wire build.zig to compile cartridge-provided .zig
modules into the brain binary via a cartridge manifest list. After
C5, adding a cartridge = drop manifest + brain/zig/ dir under
cartridges/<name>/; no edits to the brain binary code.

### C6 BRC-100 Wallet + Plexus Recovery

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

### C7 Voice→Economic Golden Slice

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

### C8 Aggressive Dead-End Removal

REFRAMED 2026-05-27 (per user: "make it a nice place to come and explore not a schizo archeological maze").

Apps and packages that aren't the canonical PWA, the canonical brain, or actively-loaded cartridges. The default action is DELETE (git history preserves them); archive only what has genuine unique value worth a future revisit.

Two modes:
  DELETE — confirmed dead, nothing valuable, git history is the artifact. (oddjobz-mobile empty shell; loom-react if its helm code is ported, otherwise port-then-delete; demo-collab-versioning; legacy-cli; brain-helm-viewer once canonical brain helm lands.)
  ARCHIVE — unique experimental code that might inform future work, moved to archive/<name>/ with a one-line README explaining what it was and why it's parked. (mud, world-apps, poker-agent, settlement, piggybank, navigation_app, demo-wasm-threejs, monolith apps/semantos after C2 absorbs slice-path cartridge UI.)

DELETE-AS-WE-GO principle (post-mortem mitigation #7): every forklift session also deletes the parallel dead code path it replaces. We don't let dead code linger "for safety" — git is safety. The codebase shrinks per session.

### C9 Helm + Surfacing Modes

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

### C10 Real Kernel Executor (PR-2b — Cell Legitimacy Gate)

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

### C11 Root Identity Primitive ("me" surface on the helm)

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

### C12 Cert-Derived Hats (BRC-42 children of the root cert)

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

### C13 Verb-Shelf Inversion (shell goes cartridge-neutral)

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

