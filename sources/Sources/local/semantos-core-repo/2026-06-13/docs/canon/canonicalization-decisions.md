---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/canonicalization-decisions.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.635437+00:00
---

# Canonicalization Decisions

**Status**: LOCKED 2026-05-27. User accepted all 8 recommendations; Q6 verb-canon anchored to CSD 1-3-5-3-1 pyramid (`docs/prd/jam-room/design/CSD-COMPRESSION-GRADIENT.md` + `docs/design/SHELL-CARTRIDGE-MODEL.md`). C1 unblocked.

**Companion glossary**: `docs/canon/canonicalization-glossary.md`
**Companion golden slice**: `docs/canon/canonicalization-golden-slice.md`
**Companion matrix**: `docs/canon/canonicalization-matrix.yml`
**Companion brief**: `docs/prd/CANONICALIZATION-BRIEF.md` §8.1

---

## Q1 — STT path

**Question**: How does the canonical PWA turn the operator's mic audio into a transcript for the V1 golden slice?

**Why now**: The C1 forklift of the `voice` subsystem branches based on the answer. The monolith currently uses `apps/semantos/lib/src/voice/voice_extract_uploader.dart` — uploads audio to brain `/api/v1/voice-extract`, brain runs the STT, returns transcript. There's also an `anthropic_llm_completer.dart` for LLM-aided extraction. No on-device whisper.cpp wired into the monolith today, even though `platforms/flutter/whisper_cpp/` exists as a Flutter FFI plugin.

**Options**:

**A. Brain upload (status quo)** — `POST /api/v1/voice-extract` from the canonical PWA. Brain runs whisper or Anthropic. Same code path as the monolith.
- ✅ Already works on the monolith; smallest C1 forklift
- ✅ No emulator/device mic-permission complexity in V1
- ✅ Brain can use bigger models for accuracy
- ❌ Requires brain reachability for every voice action
- ❌ Audio round-trip adds 1–3s latency
- ❌ Sends raw audio off-device (privacy implication)

**B. On-device whisper.cpp (FFI)** — wire `platforms/flutter/whisper_cpp/` into the canonical PWA. STT runs locally on the operator's device.
- ✅ Sub-second latency
- ✅ Audio never leaves device (privacy win)
- ✅ Works offline
- ❌ Needs whisper model bundled or downloaded (~100MB+)
- ❌ Native FFI path complexity on Android emulator + iOS
- ❌ Larger first C1 forklift (voice + whisper_cpp plugin)

**C. Hybrid with fallback** — try on-device first, fall back to brain upload on failure.
- ❌ Most complex; defer until both paths work independently

**Recommendation**: **A for V1 slice**, B as a follow-up enhancement after slice green. Smallest scope, fastest to green, same code as monolith. The on-device path becomes its own track post-slice.

**Decision**: ✅ **A** (2026-05-27, user accepted recommendation)

---

## Q2 — Helm: native Flutter widget vs webview

**Question**: Is the canonical PWA's helm a Flutter widget or a webview hosting the brain's helm web surface?

**Why now**: C9 first-pass implementation depends on this. The "brain helm web surface" doesn't exist yet (`apps/brain-helm-viewer/` is a meetup demo, not production). The Phase 39A monolith helm is `apps/loom-react/src/helm/` (React) — different framework entirely.

**Options**:

**A. Native Flutter helm widget** — port the React `AttentionSurface.tsx` logic into a new Flutter widget at `apps/semantos/lib/src/helm/`. Brain serves its helm as a separate Flutter web build of the same canonical PWA.
- ✅ One canonical UI codebase (Flutter widget renders on iOS, Android, web, desktop)
- ✅ Brain helm = `flutter build web` of the canonical PWA, configured to talk to localhost brain
- ✅ Hot reload + tooling consistency across the two units
- ❌ Loses the existing React helm code (port required)
- ❌ The "brain helm" is a Flutter web SPA, not a Zig-native HTML surface

**B. Brain serves an HTML/JS helm; PWA wraps it in webview** — brain hosts a hand-written web helm; canonical PWA embeds a webview pointing to it.
- ✅ Single helm code path (lives in brain)
- ❌ Webview = different code path than the rest of the Flutter PWA (gestures, theming, navigation all fork)
- ❌ Worse offline story
- ❌ New construction (the brain web helm doesn't exist)

**C. Two separate helms** — Flutter widget for PWA, hand-built web helm served by brain. Same design, different codebases.
- ❌ Drift inevitable

**Recommendation**: **A**. Canonical PWA = Flutter helm widget. Brain helm = `flutter build web` of the same PWA wired to localhost brain. Same code, two deploys.

**Decision**: ✅ **A** (2026-05-27, user accepted recommendation)

---

## Q3 — Cell-store on canonical PWA

**Question**: Does the canonical PWA carry a local cell-store, or does every state mutation roundtrip through the brain?

**Why now**: C1 forklift of the `outbox` subsystem depends on this. The monolith uses sqflite (`apps/semantos/lib/src/outbox/outbox_db.dart`) as a local queue/store. The shell currently has no equivalent — every cartridge call goes through `BrainWalletService` / `BrainVerbDispatchClient` to the brain.

**Options**:

**A. Local cell-store (sqflite/idb) with brain sync** — PWA has its own LMDB-equivalent (sqflite on native, idb_shim on web). Mutations land locally first, then flush to brain. Offline-capable.
- ✅ Operator can work offline; brain catches up later
- ✅ Matches monolith outbox semantics
- ✅ Fits the cell-as-wire-format principle (same bytes whether local or transit)
- ❌ Sync logic + conflict resolution complexity
- ❌ Larger C1 forklift (outbox + cell-store)

**B. Brain-roundtrip-everything** — PWA holds no persistent cell state. Every mutation hits brain HTTP. Helm reads via brain queries.
- ✅ Smallest PWA — pure UI + intent dispatch
- ✅ No sync complexity
- ✅ Smallest C1 forklift
- ❌ No offline operation
- ❌ Latency per action
- ❌ Brain unreachable = PWA unusable

**Recommendation**: **B for V1 slice**, A added in a follow-up after slice green. The slice's `do | betterment | release` doesn't need offline; round-trip is fine for proof-of-substrate. Local cell-store is a real feature with its own design surface — give it its own phase.

**Decision**: ✅ **B** for V1 slice; A as a follow-up phase (2026-05-27, user accepted recommendation)

---

## Q4 — Wallet key custody

**Question**: Where does the hat:self privkey live on the canonical PWA?

**Why now**: C6a wallet code unification depends on this. `platforms/flutter/semantos_shell_native_identity/` already provides a flutter_secure_storage-backed IdentityStore (Android Keystore / iOS Keychain / macOS Keychain / Linux libsecret / Windows DPAPI). The web path uses idb_shim (IndexedDB). The headless-wallet (`cartridges/shared/anchor/headless-wallet.ts`) currently expects a 64-hex env var (`BRIDGE_WALLET_KEY`).

**Options**:

**A. Reuse existing IdentityStore** — unified wallet pulls key from `semantos_shell_native_identity` (native) or `idb_shim` (web). Matches existing pairing/BRC-42 derivation flow.
- ✅ Existing path — no new key-management code
- ✅ OS-grade custody on native
- ✅ Matches plexusRecoveryEnvelope direction (C6b will write envelope → IdentityStore)
- ❌ Web has no OS-grade store — IndexedDB is the platform reality

**B. Unified wallet self-custody** — wallet module owns key storage independent of IdentityStore.
- ❌ Parallel custody adapter; doubles attack surface
- ❌ Forks the C6b recovery story
- ❌ No clear benefit

**Recommendation**: **A**. Existing IdentityStore is correct. Unified wallet calls `IdentityStore.read('hat:self:privkey')`. C6b plexusRecoveryEnvelope writes into the same store.

**Decision**: ✅ **A** (2026-05-27, user accepted recommendation)

---

## Q5 — `anchor: optional` default behavior

**Question**: When a cartridge verb declares `anchor: optional` and the operator doesn't explicitly opt in, does the verb anchor or not?

**Why now**: The unified wallet's hot path depends on this. The golden slice's `do | betterment | release` has `anchor: optional`. If default-anchor, V1 needs chain wired up. If default-local, V1 skips chain and anchoring becomes the V2 slice.

**Options**:

**A. Default local-only** — `optional` means "operator can request anchor with `--anchor` flag"; absent the flag, mutation lands locally / in brain only.
- ✅ Cheap default; no chain fees per release-writing entry
- ✅ Matches "anchor on demand for important things" intuition
- ✅ V1 slice skips chain — slice green doesn't depend on ARC/BSV reachability
- ❌ Operator must remember to anchor; easy to miss

**B. Default anchor** — `optional` means "operator can suppress anchor with `--no-anchor`"; absent the flag, mutation gets a BSV pushdrop.
- ✅ Strong audit trail by default
- ❌ Cost (~$0.0001 per anchor) accumulates fast for high-frequency cartridges
- ❌ V1 slice needs chain wired — adds dependency on brain wallet + ARC + WhatsOnChain reachability
- ❌ "Optional" doesn't read as "default on"

**C. Per-cartridge default** — manifest carries `anchor.default: local | chain` in addition to the per-verb policy. Cartridge author picks the sensible default for the cartridge's economics.
- ✅ Most flexible
- ❌ Schema addition during slice — keep simple

**Recommendation**: **A**. Default local-only. C9-grade slice keeps chain off the critical path. Operators opt in with explicit `--anchor` when they want it. Re-evaluate if a pattern emerges where defaults need flipping per cartridge.

**Decision**: ✅ **A** (2026-05-27, user accepted recommendation)

---

## Q6 — Verb canon (this corrects the glossary)

**Question**: The user mentioned "5 verbs on DO and 5 on FIND" in a prior message. The actual parser at `runtime/shell/src/parser.ts` declares **22+ verbs**, not 5+4. What's the canon?

**Why now**: Glossary lists "5 do-subverbs / 4 find-subverbs" pulled from `WALLET-VOICE-SHELL-GRAMMAR.md` §2.3. Code reality is different. Slice spec uses `do.new` which IS in both, but other tracks (helm verb shelf, REPL grammar) need to agree on the full canon.

**Grounded reality** — actual verbs declared in `runtime/shell/src/parser.ts`:

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

The grammar doc's "5 do-subverbs / 4 find-subverbs" is a smaller MENTAL MODEL the user has internalized; the parser is the full reality. The mental model is useful for the helm verb shelf (don't show 22 buttons); the full set is what the REPL accepts.

**Options**:

**A. Canon = parser reality (22 verbs)** — glossary corrected; helm verb shelf shows a curated subset (5+4 from the grammar doc) but REPL accepts the full set.
- ✅ Reflects what the code actually does
- ✅ Helm UX stays simple; REPL stays powerful
- ✅ Matches the user's mental model for the surface, code for the substrate

**B. Trim parser to 5+4** — refactor `parser.ts` to drop verbs (`revoke`, `stake`, `vote`, `dispute`, `transfer`, `flow`, `eval`, `compile`, `bind`, `identity`, `whoami`, `capabilities`, `taxonomy`).
- ❌ Aggressive deletion of working substrate code; outside C0 scope
- ❌ Likely breaks existing brain dispatch / wallet flows
- ❌ Resurfaces the "preserve every feature" tension

**C. Two-tier canon** — "user-surfaced verbs" (5+4 per grammar doc, on helm) vs "substrate verbs" (parser's 22, on REPL). Glossary documents both as distinct tiers.
- ✅ Clean separation of concerns
- ✅ Future cartridges can extend substrate verbs without touching helm surface
- ✅ Helm-shelf design problem becomes "pick which verbs surface per cartridge/hat"

**Recommendation**: **C**. Two-tier canon. Update glossary to distinguish **Surfaced verbs** (helm verb shelf default: `do | find | talk` modals expanding into the 5+4 user-facing primitives per WALLET-VOICE-SHELL-GRAMMAR.md) vs **Substrate verbs** (full 22-verb REPL surface per `parser.ts`). Cartridges declare which substrate verbs they expose under each surfaced modal in their manifest.

**Decision**: ✅ **C** anchored to **CSD 1-3-5-3-1 pyramid** (2026-05-27).

User confirmation: "there is a 1-3-5-3-1 design principle document which shows the 5 do verbs that I had in mind for the helm, but i like the 22 as well (maybe they function more as REPL verbs of intent and execution and will be available under voice command)".

Mapping: per `docs/prd/jam-room/design/CSD-COMPRESSION-GRADIENT.md` + `docs/design/SHELL-CARTRIDGE-MODEL.md`, the helm follows the 1-3-5-3-1 cognitive-load pyramid. Tapping/speaking a modal (DO/FIND/TALK — L2 active layer) surfaces its L3-support sub-verbs:

- **DO modal → 5 surfaced sub-verbs**: `new`, `patch`, `transition`, `sign`, `publish` (per WALLET-VOICE-SHELL-GRAMMAR.md §2.3, matches first 5 do-verbs of parser.ts)
- **FIND modal → 4 surfaced sub-verbs**: `inspect`, `list`, `trace`, `verify` (per same source — note FIND has 4 not 5; the L3 support budget is per-modal but doesn't have to fill exactly)
- **TALK modal → scoped conversation primitives** (not a verb-button list; opens a chat scope per WALLET-VOICE-SHELL-GRAMMAR.md §2.1)

Below the helm surface, the **full 22-verb substrate** stays available via REPL and voice. Voice utterances that resolve to non-surfaced verbs (e.g. `do | betterment | stake`, `do | betterment | revoke`) dispatch the same way — voice as the universal verb accessor, helm as the curated subset.

Cartridges declare in `cartridge.json` which substrate verbs they expose under each surfaced modal slot. Default behavior: a cartridge that doesn't customize gets the canonical 5 do / 4 find / talk surface.

---

## Q7 — Phone update strategy

**Question**: When does Todd's phone get the canonical PWA replacing the monolith oddjobz app?

**Why now**: Pre-mortem failure mode #11 — phone-pass ≠ emulator-pass and the previous plan had no bridge. The canonical PWA has a different `applicationId` (`com.semantos.shell` or whatever C0-Q is decided) — it installs as a separate app, doesn't auto-replace.

**Options**:

**A. Side-by-side install, manual swap** — canonical PWA installs alongside the monolith for the V1 slice testing period. Todd uses both for ~2 weeks; if canonical proves itself, uninstalls the monolith.
- ✅ Safe — no functionality cliff
- ✅ Real-world testing happens on the phone, not just emulator
- ✅ User can compare side-by-side
- ❌ Two apps on the home screen until cutover

**B. Hard cutover** — when canonical PWA goes green on emulator + golden slice, Todd uninstalls monolith and installs canonical.
- ✅ Clean
- ❌ Any monolith-only feature Todd uses regularly silently breaks until rebuilt on canonical
- ❌ Pre-mortem failure mode

**C. Canonical takes the monolith's package ID** — canonical PWA published under monolith's existing applicationId so it OTA-replaces the monolith on next install.
- ❌ Requires signing-key continuity + a clean migration path for any local SharedPreferences/Keystore state
- ❌ Aggressive; high risk

**Recommendation**: **A**. Canonical PWA installs as a distinct package (`com.semantos.app` or similar — confirm). Side-by-side for the slice testing window. Monolith uninstalled when canonical demonstrates parity on the operator's actual workflow. Aligns with the user's "oddjobz not in production" license — there's no user other than Todd whose phone we need to coordinate.

**Decision**: ✅ **A** (2026-05-27, user accepted recommendation)

---

## Q8 — Monolith deletion timing

**Question**: When does `apps/semantos/` (the monolith Flutter app) get deleted from the tree?

**Why now**: C3 includes monolith deletion. Pre-mortem warned against premature deletion (phone Tuesday-quoting story). The "oddjobz not in production" license loosens this — but the in-tree code is still a reference for what features existed.

**Options**:

**A. Delete after C7 slice green + 2 weeks of canonical daily use** — monolith stays in tree as a parallel build target during the slice testing window. After 2 weeks of Todd using the canonical PWA on his phone, monolith is deleted in one PR.
- ✅ Reference available during full-scope phase (C1+C2 full extraction can grep the monolith for stragglers)
- ✅ Phone fallback if canonical hits a regression
- ❌ Active maintenance tax (two builds, two test runs)

**B. Delete on C7 slice green** — monolith goes the moment the slice passes. Aggressive.
- ✅ Forces commitment; no fallback temptation
- ✅ Smallest in-tree footprint
- ❌ Loses the reference for C1+C2 full-scope work
- ❌ No phone fallback

**C. Move to `archive/apps/semantos-monolith/` immediately on C7 green** — out of active build, still grep-able in tree.
- ✅ Best of both — out of active maintenance, still available as reference
- ✅ Git history clean; archive folder convention matches other parked work
- ❌ Slightly larger tree until deleted later

**Recommendation**: **C**. On C7 slice green, monolith moves to `archive/apps/semantos-monolith/` (out of pubspec workspace, out of CI). Stays there during full-scope phase as a reference. Permanent delete (rm + archive/README.md entry) at full-scope done (~2026-07-31 target).

**Decision**: ✅ **C** (2026-05-27, user accepted recommendation)

---

## Q9 — Wallet interface canon (course correction)

**Question**: What's the canonical wallet interface that PWA + brain consumers code against? Bespoke `UnifiedWallet` (drafted in C6a tick 1) or BSV ecosystem standard?

**Why now**: Q1-Q8 didn't surface this. The C6a tick 1 commit (975c760) shipped a bespoke `UnifiedWallet` interface with invented method names (`signCellHash`, `pubkeyForHat`). Tick 2 (5760f82) landed a headless adapter against it. User flagged BRC-100 (https://bsv.brc.dev/wallet/0100) as the north star. Investigation revealed:

- `cartridges/wallet-headers/brain/src/brc100.ts` is only the BRC-100 signed-request *envelope* (transport auth headers) — NOT the wallet RPC surface.
- `cartridges/wallet-headers/brain/src/metanet-client.ts` is a BRC-100 *client* (HTTP-posts `/getPublicKey`, `/createAction` to Metanet Desktop). Not a server.
- `@bsv/sdk` 2.x (already installed at repo root) ships:
  - `Wallet.interfaces.d.ts` — ~40 canonical BRC-100 TypeScript types (`CreateActionArgs/Result`, `SignActionArgs/Result`, `GetPublicKeyArgs`, `ListOutputsArgs`, certificates, key-linkage, encryption, HMAC — full surface)
  - `ProtoWallet` class — in-process implementation of BRC-100's crypto subset (`getPublicKey`, `createSignature`, `encrypt/decrypt`, `createHmac`, `revealCounterpartyKeyLinkage`) wrapping a `KeyDeriver` (BRC-42 implementation)
  - `WalletClient` — canonical ABI client for talking to any BRC-100 wallet

The bespoke interface re-fragments the surface in a different way. Adopting BRC-100 is a *simplification* — we get ~40 method types, an in-process reference implementation, BRC-42 derivation, and ecosystem interop for free.

**Options**:

**A. Keep bespoke `UnifiedWallet`** — invent our own interface, build adapters.
- ❌ Re-fragments instead of unifying
- ❌ Loses ecosystem interop (Metanet Desktop, other BRC-100 wallets, third-party tooling all speak BRC-100)
- ❌ Throws away `@bsv/sdk`'s `ProtoWallet` reference implementation
- ❌ Have to design + maintain method semantics from scratch

**B. Adopt `@bsv/sdk`'s `WalletInterface` (full BRC-100)** — replace bespoke types; rewrite adapters as thin wrappers over `ProtoWallet` + existing tx-building.
- ✅ Smaller code surface (~140 lines of adapter crypto → ~30 lines delegating to ProtoWallet)
- ✅ Ecosystem interop (any BRC-100 wallet works)
- ✅ BRC-42 `KeyDeriver` already provides counterparty-derived keys — first-class Bridget-payment support
- ✅ `createAction` is the canonical way to construct any tx (payment, anchor, multi-output) — one call subsumes both `anchorCell` and `sendPayment`
- ✅ Reference implementation exists for conformance comparisons

**C. Hybrid — wrap @bsv/sdk types in our own re-export module for namespace control** — same as B but with a thin shim file we control.
- ✅ Lets us extend the BRC-100 surface (e.g. helm-specific helpers) without polluting consumer imports
- ✅ Same ecosystem interop as B
- ⚠ Marginal value over B; the namespace control matters only if we frequently extend

**Recommendation**: **B** — adopt `WalletInterface` from `@bsv/sdk` directly. Re-exports add no value when consumers can import from `@bsv/sdk` themselves.

**Decision**: ✅ **B** (2026-05-28, user confirmed BRC-100 as north star)

Cost: C6a tick 1 + tick 2 commits (975c760, 5760f82) get superseded by a single tick 3 commit that reshapes the three files (unified-wallet.ts, headless-unified-wallet.ts, conformance test) against BRC-100. ~250 lines of code reshaped; architectural intent unchanged. Net simplification.

Glossary correction: "Unified wallet" terminology replaced by "BRC-100 wallet" throughout. `signCellHash` → `createSignature`. `pubkeyForHat` → `getPublicKey`. `hatId` → BRC-43 (security level + protocolID + keyID + counterparty) tuple.

---

## Decisions summary table

**All 9 decisions LOCKED.** Q1-Q8 locked 2026-05-27; Q9 locked 2026-05-28. C1 + C6a unblocked.

| # | Question | Decision |
|---|----------|----------|
| Q1 | STT path | ✅ A — brain upload via `/api/v1/voice-extract` for V1 (on-device whisper.cpp as follow-up enhancement) |
| Q2 | Helm widget vs webview | ✅ A — native Flutter helm widget; brain helm = `flutter build web` of same PWA |
| Q3 | Cell-store local vs roundtrip | ✅ B for V1 — brain-roundtrip-everything; local cell-store (A) as a follow-up phase |
| Q4 | Wallet key custody | ✅ A — reuse `semantos_shell_native_identity` IdentityStore; plexusRecoveryEnvelope writes into same store |
| Q5 | `anchor: optional` default | ✅ A — default local-only; operator opts in to anchor with explicit `--anchor` |
| Q6 | Verb canon | ✅ C — two-tier anchored to **CSD 1-3-5-3-1**: helm L3-support surfaces 5 do + 4 find sub-verbs; REPL/voice accesses the full 22-verb substrate |
| Q7 | Phone update | ✅ A — canonical PWA installs as distinct package, side-by-side with monolith during slice testing |
| Q8 | Monolith deletion timing | ✅ C — archive to `archive/apps/semantos-monolith/` on C7 green; permanent delete at full-scope done |
| **Q9** | **Wallet interface canon** | ✅ **B — `@bsv/sdk` `WalletInterface` (full BRC-100)**; `ProtoWallet` is the crypto reference; adapters wrap implementations (Metanet Desktop client, headless, future plexus-recovery) |

---

## What unblocks once these land

- **All Q1-Q6 answered** → C1 forklift can start with concrete scope (which voice path, which helm shape, no/yes outbox, custody path, anchor wiring, verb-tier handling)
- **Q7 answered** → phone-pass strategy locks; canonical PWA package ID decided
- **Q8 answered** → C3 timing locked; C1+C2 full-scope phase knows when the reference is going away

If you take the recommendations as-is, C1 can start tomorrow. If any of the ⚠ are contested, that question becomes a follow-up design conversation before its dependent track moves.
