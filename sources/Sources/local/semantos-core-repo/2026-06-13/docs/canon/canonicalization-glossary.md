---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/canonicalization-glossary.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.627350+00:00
---

# Canonicalization Glossary

**Status**: canonical source of truth for the vocabulary used in the canonicalization effort. Disputes resolve here.
**Companion matrix**: `docs/canon/canonicalization-matrix.yml`
**Companion brief**: `docs/prd/CANONICALIZATION-BRIEF.md`

Every term below has ONE definition. When a doc, comment, commit, or PR uses one of these terms in a different sense, that doc/comment/commit/PR is wrong and gets corrected — not this glossary.

---

## Units

### Semantos (the system)
The whole. Includes both canonical units below + the cartridges that load into them + the shared cell substrate + the deployment infrastructure. When unqualified, "Semantos" means the system.

### Semantos PWA
The Flutter app at `apps/semantos/` (formerly `apps/semantos/`; rename happens during C3). The single canonical PWA. Builds for Android, iOS, web (PWA), macOS, Linux, Windows. The neutral cartridge loader running on the operator's device.

### Semantos Brain
The Zig binary at `runtime/semantos-brain/`. The single canonical brain. Runs as a peer node / server / root operator host. Same substrate primitives as the PWA, served over bearer-gated HTTP.

### Canonical unit
Either of the above. The plan ends with exactly two: PWA + Brain. Everything else is a cartridge, an archive, or a delete.

---

## Architectural roles

### Shell
The PWA's neutral host code: cartridge loader, registry, hat switcher, manifest provisioner, platform context, router. The "shell" is the part of the PWA that is NOT cartridge-specific and NOT a primitive substrate (those are below). Memory: `[[shell-cartridges-hats-model]]`.

The word **"shell"** is canon-load-bearing. It survives the `apps/semantos` → `apps/semantos` rename — the directory is renamed but "the shell" remains the term for the loader-layer code inside it.

**The shell brand ("Semantos") sits ONE LEVEL ABOVE any cartridge.** When the operator is inside a cartridge, the shell's identity is intentionally subordinated — it surfaces in the cartridge switcher (the step-up route, `/cartridges`) but never as the helm AppBar title. See `Helm` for the L1-anchor hierarchy on the helm surface.

### Cartridge
A pluggable extension that adds capability to a canonical unit. Defined by:
- `cartridges/<name>/cartridge.json` — the manifest
- `cartridges/<name>/brain/` — optional brain-side Zig handlers/walkers/stores
- `packages/<name>_experience/` — optional PWA-side Flutter experience package
Loads into either or both canonical units via the manifest. Examples: oddjobz, self, jam-room (dedicated UI), wallet-headers (passive).

### Experience (package)
The PWA-side Flutter package for a cartridge: `packages/<name>_experience/`. Owns the cartridge's UI surface (when applicable) + intent grammar fragment + lexicon fragment + manifest loader. NOT all cartridges have an experience package — passive cartridges may have only a brain side.

### Primitive (substrate)
A capability that ships in BOTH canonical units regardless of which cartridges are loaded. Per the canonicalization scope: contacts/PKI, conversation, pask, wallet-headers + headless-wallet (unified per C6), key REPL, gradient intent pipeline, identity + plexus recovery, hat-switching, manifest provisioning, cell-store, cell-engine. Primitives are NOT cartridges.

---

## Surfaces

### Helm
The canonical default UI surface in both units. Composes the **attention surface** (the inferred ranked feed of what to look at next, per `docs/design/HELM-ATTENTION-SURFACE.md`) and the **DO|FIND|TALK verb shelf** (per `docs/design/WALLET-VOICE-SHELL-GRAMMAR.md`).

**Helm L1 anchor = CARTRIDGE, not SHELL.** Per CSD 1-3-5-3-1, the L1 anchor of the helm is the active **cartridge** (with hat as companion), not the shell brand. The shell ("Semantos") lives ONE LEVEL ABOVE any cartridge — visible when stepping out via the cartridge switcher to pick a different cartridge. Inside a cartridge, the helm AppBar reads:

| Slot | Content | Why |
|------|---------|-----|
| Leading | Cartridge-switcher icon | Step UP into the shell to switch cartridges |
| Title | Active cartridge name ("Self", "Oddjobz") | L1 anchor — what cartridge you're operating within |
| Actions | HatSwitcher | L1 anchor companion — what hat you're wearing |

The shell brand "Semantos" never appears as the helm title. If it does, it's a bug — file a fix against HelmHomeScreen.

**Naming clash to fix**: the monolith has `apps/semantos/lib/src/helm/` containing oddjobz's job dashboard UI, NOT the helm primitive. When extracted to `packages/oddjobz_experience/`, that directory must be renamed (e.g. `dashboard/`) so "helm" is reclaimed for the canonical default-UI primitive.

### Surface
Generic term for a UI surface that a cartridge contributes — could be a screen, a widget, a card on the helm, a verb-shelf addition, etc. A cartridge's surface is governed by its `ui.surfacingMode` in the manifest.

### Surfacing mode
Per-cartridge UI relationship to the helm, declared in `cartridge.json` under `ui.surfacingMode`:
- **`default`** — cartridge uses the helm's DO|FIND|TALK verb surface (oddjobz, betterment)
- **`dedicated`** — cartridge ships its own UI surface that displaces helm when active (jam-room, chess)
- **`passive`** — cartridge runs in background, REPL-only, no helm presence (wallet-headers, cell-relay)
- **`priority`** — cartridge claims an always-on-top helm slot (none currently)

Surfacing mode controls UI ONLY. Every cartridge — regardless of mode — registers REPL verbs.

### Hat
The active identity context of the operator. A cartridge can declare multiple hat roles in its manifest (`hatRoles`). The PWA's `HatSwitcher` widget switches the active hat. Used for capability scoping + presentation filtering.

---

## Verbs

### The DO|FIND|TALK trio
The canonical modal verb set per `docs/design/WALLET-VOICE-SHELL-GRAMMAR.md` §2.1. Three modal verbs, every operator action maps to exactly one:
- **`do`** — state-mutating action (write a cell, sign, transition a flow, send a message)
- **`find`** — read-only retrieval (surface objects, render history, compute aggregates)
- **`talk`** — open a conversational scope (with self, with object, with another hat)

### Surfaced verbs (helm shelf)
The curated user-facing sub-verbs exposed beneath each modal in the helm verb shelf. Anchored to the **CSD 1-3-5-3-1 pyramid's L3-support layer** (see `docs/prd/jam-room/design/CSD-COMPRESSION-GRADIENT.md` + `docs/design/SHELL-CARTRIDGE-MODEL.md`).

- **DO modal → 5 surfaced sub-verbs**: `new`, `patch`, `transition`, `sign`, `publish` (per WALLET-VOICE-SHELL-GRAMMAR.md §2.3). Hat-policy-gated, Verifier-Sidecar-enforced.
- **FIND modal → 4 surfaced sub-verbs**: `inspect`, `list`, `trace`, `verify` (per same source). Pure VFS query + render. (FIND has 4 not 5 — the L3 budget is per-modal but doesn't need to fill the whole 5-slot ceiling.)
- **TALK modal → scoped conversation primitives**: not a verb-button list; opens a chat scope (self / direct / squad / agent / broadcast).

Per the 1-3-5-3-1 pyramid the helm UI presents at most **5 supporting actions per active modal**, keeping cognitive load within working-memory.

### Substrate verbs (REPL / voice)
The full parser-declared verb set per `runtime/shell/src/parser.ts`:

```
'new', 'patch', 'transition',     // mutate
'inspect', 'trace', 'verify',     // read
'sign', 'publish', 'revoke',      // cryptographic
'stake', 'vote', 'dispute',       // governance
'transfer',                       // ownership
'flow', 'eval', 'compile', 'bind', // composition
'list',                           // enumeration
'identity', 'whoami', 'capabilities', 'taxonomy'  // introspection
```

All 22 are addressable through the REPL and through voice — every utterance the parser can parse dispatches. The helm shelf curates a subset (5+4 per modal) per the pyramid; voice/REPL access the full substrate.

Cartridges declare in `cartridge.json` which substrate verbs they expose under each helm-surfaced modal slot. Default behavior: a cartridge that doesn't customize gets the canonical 5 do / 4 find / talk surface.

(Note: when a doc says "the 5 verbs" it means the 5 DO-modal surfaced sub-verbs. The 22 are the substrate.)

### Verb (cartridge-declared)
A higher-level action a cartridge exposes, declared in `cartridge.json` under `verbs`. Bound to capability requirements. Example: `oddjobz.job.create`, `oddjobz.quote.draft`. Cartridge verbs compose down into one or more do/find substrate sub-verbs at dispatch time.

---

## Substrate

### Cell
The 1024-byte canonical unit of storage in Semantos. Defined by `core/cell-engine/src/constants.zig`. Same bytes in NVS, LMDB, filesystem, RAM, IPv6mc transport, BSV pushdrop. Per `[[cell-is-the-wire-format]]`.

### Cell-engine
The Zig kernel that operates on cells. Lives at `core/cell-engine/`. Compiled to WASM for the C6 embedded carve. Per `[[cell-engine-static-5mb-unfit-for-mcu]]`.

### Cell linearity (intrinsic consumption discipline)
How many times a cell can be consumed. Enforced by the cell-engine + `cell_store` regardless of whether the cell is ever bound to chain. Four values, all declared at the cellType level in `cartridge.json`:

| Value | Consumption rule | Plexus opcode |
|---|---|---|
| `LINEAR` | Consumed exactly once. Successor must replace it. | `OP_CHECKLINEARTYPE` |
| `AFFINE` | Consumed at most once. May be discarded without successor. | `OP_CHECKAFFINETYPE` |
| `RELEVANT` | Never consumed. Multi-read; arbitrary number of readers. | `OP_CHECKRELEVANTTYPE` |
| `EPHEMERAL` | Transient. Lifetime bounded by a single request/response pair. | (no opcode; brain-side TTL) |

**Cell linearity is orthogonal to anchor shape.** A `LINEAR` cell can be brain-internal (no anchor at all), externally provable (existence anchor), or cross-brain dispatchable (`utxo_state_anchor`). The linearity rule says *how many times* the cell can be consumed; the anchor shape says *where the proof of state lives*. Conflating these two is what produced the "every linear cell needs on-chain wiring" misframe — see the **Anchor shape** section below.

### Anchor
A BSV on-chain commitment binding a cell's state to the chain. The act, not the bytes — what gets committed depends on the **anchor shape** (next entry). Per `[[mnca-anchor-onchain-mainnet]]`.

The simple-anchor pipeline (task #16 / `docs/prd/ANCHOR-BACKEND-BRIDGE.md`) is the auto-anchor path: `cell_handler` mint → `AnchorEmitter.emitBsv` (`.bsv` mode) → `broker.publish("cell.created")` → `AnchorQueueWriter` → JSONL queue file → `anchor-runner.ts` → `anchor-subscriber.ts` builds a PushDrop UTXO via BRC-42 + Metanet Desktop. The substrate plumbing is shipped; runner daemon supervision is the remaining glue.

The legacy `verbs[].anchor: required | optional | never` knob in older cartridge manifests is the v0.1 ergonomic over the same pipeline; the new cellType-level taxonomy below subsumes it.

### Anchor shape (the binding choice)
What an on-chain commitment commits to. A cellType declares zero or more shapes via the **domain flags** bitfield. The pipeline engaged differs per shape:

| Shape | What's committed | When you want it | Pipeline |
|---|---|---|---|
| `existence` | `cell_hash + type_hash + timestamp` | Cheap auditable "this cell existed at time T" — default for most cellTypes | Simple PushDrop pipeline (task #16) |
| `transition` | `cell_hash + predecessor_hash + transition rule hash` | Each state transition is independently chain-verifiable | Cell-engine script via PolicyRuntime (the "cleavage apparatus" — only when explicitly requested) |
| `utxo_state` | A live UTXO whose presence in the UTXO set *is* the cell's authoritative state | Cross-brain dispatch — another party needs to verify the cell hasn't been consumed. Spending the UTXO = consuming the cell. | `cartridges/wallet-headers/brain/src/cell-anchor.ts` (BRC-42-derived spending key) |
| `identity` | `cell_hash + owner_cert_hash + cert_chain_root` | Cell is bound to a verified BRC-52 identity (Phase-1b BCA dep) | `OP_CHECKIDENTITY` at script layer |
| `capability` | `cell_hash + capability_token` | Cell binds a capability grant on chain | `OP_CHECKCAPABILITY` at script layer |

Shapes compose freely. A `bsv.linear.anchor` cell typically declares `utxo_state` + `identity` together. A `oddjobz.job` typically declares only `existence`. A purely brain-internal `workflow_step` LINEAR cell declares no anchor shape at all — its linearity is enforced by `cell_store`, no chain footprint needed.

`utxo_state` semantically subsumes `existence` (a live UTXO proves the cell existed). Declaring both is harmless but redundant; the more specific flag wins.

### Receipt
A response cell correlated to a request cell. Brain-internal by default. Both cells exist in `cell_store`; the cellType pair (`*.intent` → `*.result`) is the convention. The intent carries a correlation id; the result echoes it.

Receipts are NOT anchors. A receipt can be anchored (declare `existence` on the result cellType) but the receipt mechanism itself is brain-internal cell mint + reply. Example pair: `bsv.spv.verify.intent` → `bsv.spv.verify.result`.

### Log entry
An append-only audit record of an action. Brain-internal (`audit_log_mod.AuditLog`). NOT a cell, NOT on chain, NOT a receipt. Every cell mint / dispatch / broker call optionally writes one; controlled by the `logs_to_audit` domain flag (default on for almost all cellTypes).

Periodic batch anchoring of log entries (Merkle root → one anchor per N entries) is a possible future shape but not yet wired.

### Attestation
A signed claim *about* a cell, exchanged peer-to-peer between brains. Federation primitive. The attesting brain signs `{cell_hash, attestation_kind, timestamp}` with its operator cert; the receiving brain verifies the signature against the attester's known cert.

Attestations are not anchors but CAN be anchored — anchoring an attestation commits the claim to chain, making it verifiable by any third party (not just the recipient). Controlled by the `attestation_request` domain flag.

### Domain flags (the binding bitfield)
Per-cellType bitfield declared in `cartridge.json` as `cellTypes[i].domainFlags`. Checked at script time via `OP_CHECKDOMAINFLAG`. Tells the brain (a) which pipelines to engage on mint and (b) which checks the cell-engine script must perform.

| Bit | Name | Effect on mint pipeline |
|---|---|---|
| 0x01 | `existence_anchor` | `AnchorEmitter` publishes `cell.created` → simple PushDrop pipeline |
| 0x02 | `transition_anchor` | Cell-engine script verifies + commits transition rule |
| 0x04 | `utxo_state_anchor` | `cell-anchor.ts` spends predecessor UTXO + mints successor (UTXO-as-token) |
| 0x08 | `identity_anchor` | Script must `OP_CHECKIDENTITY` (owner_id bound; Phase-1b BCA dep) |
| 0x10 | `capability_anchor` | Script must `OP_CHECKCAPABILITY` (cap token bound) |
| 0x20 | `emits_receipt` | Script is expected to `OP_CELLCREATE` one or more response cells |
| 0x40 | `logs_to_audit` | Broker writes `audit_log` entry (default on for almost all cellTypes; off = silent) |
| 0x80 | `attestation_request` | Cross-brain attestation cell emitted (federation) |

A cellType with `domainFlags: ["logs_to_audit"]` and no other bits is a purely brain-internal cell — minted, logged, never anchored, never federated. A cellType with `domainFlags: ["existence_anchor", "logs_to_audit"]` rides the simple-anchor pipeline. A cellType with `domainFlags: ["utxo_state_anchor", "identity_anchor"]` is a state-machine cell with cross-brain proof.

**No handler script is required** for cellTypes whose flags only engage the generic existence-anchor or audit pipelines. A script is required when any of `transition_anchor`, `utxo_state_anchor`, `identity_anchor`, `capability_anchor`, `emits_receipt`, or `attestation_request` is set — those bits drive logic the cell-engine has to execute.

### REPL
The bearer-gated HTTP endpoint at `/api/v1/repl` that accepts typed verb invocations and returns results. The universal access layer — every cartridge verb is REPL-addressable regardless of UI surfacing mode. The PWA's typed shell and the helm verb-shelf both dispatch through REPL.

---

## Wallet + identity

### Wallet-headers
The cartridge at `cartridges/wallet-headers/brain/` — BSV wallet + anchor + chess submitter + vault. Brain-side TS code. Includes `metanet-client.ts` (BRC-100 *client* posting to Metanet Desktop) and `brc100.ts` (BRC-100 *envelope*/transport-auth parser — narrower than the full BRC-100 wallet RPC).

### Headless-wallet
The minimal BSV wallet at `cartridges/shared/anchor/headless-wallet.ts` — eliminates the 7.3s Metanet Desktop round-trip, cuts settlement latency to ~100ms. Brain-side TS code. Single privkey from env, no UI, programmatic sign + ARC broadcast.

### BRC-100 wallet (C6a target — supersedes "unified wallet")
The canonical wallet interface for both PWA and brain after C6a lands: **`@bsv/sdk` 2.x `WalletInterface`** per the [BRC-100 specification](https://bsv.brc.dev/wallet/0100). Same interface across implementations — Metanet Desktop client, in-process headless adapter, future plexus-recovery adapter. Consumers (PWA `WalletService`, brain anchor pipeline) import types from `@bsv/sdk` directly.

Method surface (per BRC-100): `createAction`, `signAction`, `abortAction`, `listActions`, `internalizeAction`, `listOutputs`, `relinquishOutput`, `getPublicKey`, `revealCounterpartyKeyLinkage`, `revealSpecificKeyLinkage`, `acquireCertificate`, `proveCertificate`, `listCertificates`, `relinquishCertificate`, `discoverByIdentityKey`, `discoverByAttributes`, `encrypt`, `decrypt`, `createHmac`, `verifyHmac`, `createSignature`, `verifySignature`, `getHeight`, `getHeaderForHeight`, `getNetwork`, `getVersion`, `isAuthenticated`, `waitForAuthentication`.

(Earlier drafts used a bespoke "UnifiedWallet" with invented `signCellHash` / `pubkeyForHat` / `hatId` — superseded by BRC-100 per Q9 decision 2026-05-28.)

### ProtoWallet
`@bsv/sdk`'s in-process implementation of BRC-100's cryptographic subset: `getPublicKey`, `createSignature`/`verifySignature`, `encrypt`/`decrypt`, `createHmac`/`verifyHmac`, `revealCounterpartyKeyLinkage`/`revealSpecificKeyLinkage`. Constructor: `new ProtoWallet(privateKey)`. Wraps a `KeyDeriver` (BRC-42 derivation). Does NOT implement transaction-building (`createAction`/`signAction`) or output management (`listOutputs`) — that's the wallet adapter's responsibility.

### KeyDeriver (BRC-42)
The BRC-42 derivation implementation inside `@bsv/sdk`. Given `(protocolID, keyID, counterparty)` it deterministically derives a child key. When `counterparty` is another party's identity pubkey, this produces a shared key only both parties can derive — the foundation for P2P payments, encrypted channels, and contact-scoped data. THIS is what makes "pay bridget 10000 sats" work: her identity key as `counterparty` derives her payment destination from Todd's POV.

### plexusRecoveryEnvelope (C6b target — concept, not yet a spec)
The user's recovery story for Root Operator identity. ONE envelope that carries the cert + derivation seed + recovery anchor, such that loading it onto a freshly-provisioned PWA or brain re-establishes the Root Operator's identity within minutes. Spec to be written as `docs/design/PLEXUS-RECOVERY-ENVELOPE.md` during C6b — does NOT block C6a wallet code unification or the C7 golden slice.

### Root Operator
The principal identity that owns a Semantos instance (one PWA + one brain). Authenticated via BRC-52 cert + capability + plexus-challenge per `[[brain-auth-model-intent]]` (aspirational; brain currently demands bearer tokens). C6b is what aligns the design intent with the deployed reality.

---

## Process terms

### Slice / Golden slice
The ONE operator action that gates the canonicalization. Defined in `docs/canon/canonicalization-golden-slice.md`. The C7 test fixture. All other tracks are scoped FIRST to the slice critical path; off-path work is deferred.

### Slice-scope vs full-scope
A track's first pass extracts/wires/tests only the code on the golden-slice critical path (slice-scope). The full set of code under that track's responsibility (full-scope) gets a second pass after the slice goes green. This is post-mortem mitigation #1.

### DELETE vs ARCHIVE (per C8)
- **DELETE** = remove from working tree. Git history preserves it. Default action.
- **ARCHIVE** = move to `archive/<name>/` with a one-line README explaining what it was and why it's parked. Reserved for code with genuine unique experimental value worth a future revisit.
