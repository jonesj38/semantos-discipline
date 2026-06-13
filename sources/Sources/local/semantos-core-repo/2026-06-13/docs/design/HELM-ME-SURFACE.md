---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/HELM-ME-SURFACE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.728357+00:00
---

# HELM-ME-SURFACE — C11 Root Identity Primitive on the Helm

**Status**: Design lock for C11 (Track B per Todd's 2026-05-29 architecture call). Owner: PWA shell.
**Companion**: HELM-CANONICAL-SURFACE.md (PR #714), CERT-DERIVED-HATS.md (C12, not yet written).
**Predecessors**: post-#722 (rename), post-#724/#725 (verb-shelf inversion), post-#726 (V1 slice green).

---

## 1. Goal

Add the **shell-level identity surface** to the canonical helm: a single tappable affordance that surfaces *who the operator is* (root BRC-52 cert), composes *what they use to act* (wallet-headers wallet.html), and *how they recover* (PlexusRecoveryEnvelope + secret questions). Frees the word **self** from the cartridge namespace (which is now `betterment`, PR #722) and makes the cert the unforgeable parent from which **C12 (Cert-Derived Hats)** can derive per-cartridge keys via BRC-42.

> **The architecture lock this closes** (Todd, 2026-05-29 emulator-test pushback): hats today are UI state. They leak across cartridges, they're forgeable, they require manual selection. With a real root cert pinned in the shell + BRC-42 child derivation per cartridge, hats become *cryptographically anchored*. The operator can't accidentally show "oddjobz · admin" on a screen that has nothing to do with oddjobz, because the hat IS a derived key tied to a cartridge context.

---

## 2. What already exists

Survey 2026-05-29 (post-#726). Status per primitive:

| Primitive | Status | Location |
|---|---|---|
| BRC-52 cert custody (Flutter side) | **READY** | `apps/semantos/lib/src/identity/child_cert_store.dart` — persists `device_priv_hex`, `child_pub_hex`, `operator_root_pub`, `operator_cert_id`, `brain_pair_endpoint`, `bearer_token` |
| Pairing flow (paste-pair-URL) | **READY** | `apps/semantos/lib/main.dart::_PairingScreen` — fallback when no creds in IdentityStore |
| Boot routing | **READY** | `_BootstrapAppState._boot()` routes to `_PairingScreen` on `StateError`; success continues to `_AsyncShell` |
| Brain `/api/v1/identity/cert` | **READY** | `runtime/semantos-brain/src/identity_http.zig` returns cert snapshot (cert_id, label, issued_at, push_platform, active) |
| Brain `/api/v1/identity/hat` + `/switch` | **READY** | Same file. Hat-level state already lives on brain. |
| Plexus envelope (TS) | **READY** | `cartridges/wallet-headers/brain/src/plexus/envelope.ts` — full `PlexusRecoveryEnvelope` v1 schema + `buildEnvelope()` + `decryptRecoverySeed()` + invariant checks 1–5 |
| Plexus operator endpoints | **READY** | `cartridges/wallet-headers/brain/src/plexus/operator.ts` — `/enrollment/dispatch`, `/recovery/initiate`, etc. |
| Secret questions (3-of-3 fixed) | **READY** | `cartridges/wallet-headers/brain/src/popup-create.ts` — `DEFAULT_CHALLENGE_QUESTIONS` + `validateChallengeAnswers` + normalization (NFKC + lowercase + collapse-ws + trim) |
| wallet-headers `wallet.html` | **READY (server-side)** | `cartridges/wallet-headers/brain/src/wallet-page.ts` — browser entry point; today accessed via cloud-hosted URL or external browser tab |
| BRC-42 derivation (Dart) | **PARTIAL** | `platforms/flutter/semantos_core/lib/src/brc42_verifier.dart` — *verifier* exists; *derivation helper* lives only TS-side (wallet-headers `storage.ts::allocateNextIndex`). C12 will need a Dart deriver. |
| n-of-m threshold (Shamir etc.) | **MISSING** | Only 3-of-3 mandatory. Out of scope for C11 V1. |
| `shell.identity.*` cartridge namespace | **MISSING** | No "me cell" namespace yet. C11 introduces minimal `shell.identity.envelope` (one cell per recovery envelope minted). |

**Architectural consequence**: most of C11 is *composition + UX*, not greenfield. The substrate is mostly in place; the gap is a single helm widget + a small brain cell-type for envelope minting.

---

## 3. The "me" surface UX

A single affordance on the helm AppBar (right side, where the HatSwitcher used to live before PR-C9-7a stripped it). Tap → bottom sheet with four sections:

```
┌─────────────────────────────────────────────┐
│ ▾ Me                                        │
│ ─────────────────────────────────────────── │
│ Identity                                    │
│   cert_id    af90d1d6…59ce873  (truncated) │
│   pubkey     029cf8e4…2a08dfec              │
│   paired to  oddjobtodd.info • since today  │
│   [Re-pair]                                 │
│ ─────────────────────────────────────────── │
│ Wallet                                      │
│   wallet-headers      [Open ⟶]              │
│   (creates/loads via wallet.html)           │
│ ─────────────────────────────────────────── │
│ Recovery                                    │
│   Secret questions    ✗ not set             │
│   [Set up secret questions ⟶]               │
│                                             │
│   Recovery envelope   ✗ not generated       │
│   [Generate + download ⟶]                   │
│                                             │
│   Plexus RaaS         ☐ not enrolled        │
│   [Enroll with Plexus ⟶]   (optional)       │
└─────────────────────────────────────────────┘
```

Each row is a state + action. Three workflows fan out:

**A. Secret questions setup** — opens a child sheet that walks the operator through 3 questions (default + custom override) + answers (with retype-confirm + normalization preview). On Save, the sheet:
1. PBKDF2(normalize(concat(answers)), salt, 100k) → `recoveryKey`
2. Stores `ChallengeBundle` (question + salt + sha256(salt||normalize(answer))×3 + kdfIterations) in IdentityStore
3. Surfaces success + offers "Generate recovery envelope now"

**B. Recovery envelope generation + download** — calls `buildEnvelope({identityKey, certId, contactEmail, challengeBundle, recoveryKey})` from `plexus/envelope.ts` via a thin Dart wrapper → AES-256-GCM-encrypted `EncryptedRecoverySeed` + `DerivationContext`s + `RelationshipRecipe`s → downloads as `<contactEmail>-recovery-envelope-v1.json`. Mints one `shell.identity.envelope` cell on the brain (carries cert_id + envelope hash + generated timestamp — *not* the envelope content; that's local-only).

**C. Plexus RaaS enroll** — default OFF. If the operator opts in: posts to Plexus operator's `/enrollment/dispatch` endpoint with the envelope hash + challenge bundle metadata (no seed material). Plexus returns enrollment token; helm stores it + flips the row to "enrolled". Future recovery can go through Plexus instead of needing the local envelope file.

**Wallet** row launches wallet.html — see Decision 2 below for binding shape.

---

## 4. Architecture seam

```
                ┌──────────────────────────────────────────────────────┐
                │ apps/semantos/lib/shell/me/                          │
                │   me_sheet.dart            ← the affordance + 4 rows │
                │   secret_questions_flow.dart                         │
                │   recovery_envelope_flow.dart                        │
                │   plexus_raas_flow.dart                              │
                │   wallet_headers_launch.dart                         │
                └────────┬─────────────────────────────────────────────┘
                         │
        ┌────────────────┼───────────────────────────┐
        ▼                ▼                           ▼
┌───────────────┐  ┌─────────────────────┐  ┌──────────────────────┐
│ IdentityStore │  │ BrainHttpClient     │  │ PlexusEnvelopeDart   │
│  (existing)   │  │  /api/v1/identity/  │  │  (NEW thin wrapper)  │
│               │  │     cert            │  │  over TS envelope.ts │
└───────────────┘  │  /api/v1/identity/  │  │  via FFI or copied   │
                   │     hat             │  │  pure-Dart port      │
                   │  /api/v1/cells      │  └──────────────────────┘
                   │  (mint envelope     │
                   │   metadata cell)    │
                   └─────────────────────┘
```

**Helm AppBar wiring** (in `helm_home_screen.dart`):
```dart
actions: [
  IconButton(
    icon: const Icon(Icons.account_circle_outlined),
    tooltip: 'Me',
    onPressed: () => showMeSheet(context),
  ),
],
```

The `Me` affordance was *deliberately empty* per PR-C9-7a (helm chrome neutrality). C11 adds it back — but it's a SHELL primitive (always present, regardless of active cartridge), not a cartridge-scoped affordance. Different concept from the old HatSwitcher.

**Cartridge boundary**: `apps/semantos/lib/shell/me/` is shell-internal, imports `semantos_core` (for IdentityStore, BrainHttpClient, PlexusEnvelopeDart). It does **not** import any cartridge package — the "me" surface is shell-level identity, not a cartridge feature.

---

## 5. Implementation tracks (C11 axes A–J)

| Axis | Scope | Status today |
|---|---|---|
| A. Source extracted | `apps/semantos/lib/shell/me/{me_sheet,secret_questions_flow,recovery_envelope_flow,plexus_raas_flow,wallet_headers_launch}.dart` + `apps/semantos/lib/src/plexus/envelope_dart.dart` | ✗ |
| B. Target wired | `helm_home_screen.dart` AppBar action; first-run guard if no cert (route to pairing or set-up wizard) | ✗ |
| C. Tests | Widget tests for the four rows + state machines; envelope round-trip test (build → load → decrypt with answers) | ✗ |
| D. Brain-side | `shell.identity.envelope` cell type (one per generated envelope; mints to brain so operator can list envelopes from any paired device) | ✗ |
| E. PWA-side | Entire deliverable is PWA-side | ✗ |
| F. Wallet integration | wallet-headers launch (see Decision 2) | ⚠ (depends on decision) |
| G. Recovery envelope | Plexus envelope generation + download + RaaS opt-in | ✗ |
| H. Intent pathway | Recovery envelope mint → IntentDispatcher.dispatchByName('GenerateRecoveryEnvelope', ...) using the same name-keyed path as PR-C9-7d | ✗ |
| I. Docs | This doc. CERT-DERIVED-HATS.md (C12) is the natural companion. | ⚠ (this PR) |
| J. Old code | `_BootIncompleteScreen` superseded (it was the empty placeholder for what becomes the "me" first-run path) | n/a (was scaffold) |

Sequencing for implementation (each ⇢ separate PR):

1. **PR-C11-1**: Design doc (this) + add `Me` AppBar action (no-op tap shows a placeholder) + `me_sheet.dart` scaffold with Identity row (read from `IdentityStore` + `GET /api/v1/identity/cert`)
2. **PR-C11-2**: Plexus envelope Dart wrapper (port or FFI) + envelope flow UI + download
3. **PR-C11-3**: Secret-questions setup flow + ChallengeBundle storage in IdentityStore
4. **PR-C11-4**: Wallet row (per Decision 2 below) — webview or external tab launch
5. **PR-C11-5**: Plexus RaaS enroll flow (opt-in)
6. **PR-C11-6**: Brain-side `shell.identity.envelope` cell type + handler + matrix C11 axes flip ✓

---

## 6. Five architectural decisions

Defaults below — please override any you disagree with before I start PR-C11-1.

### D1 — n-of-m threshold flexibility

**Recommendation: 3-of-3 fixed (defer threshold flexibility to C11.5).**

Matches current wallet-headers + Plexus envelope schema. Threshold logic (Shamir, threshold signatures) is its own substrate — adds material complexity without unblocking V1. Document as known constraint.

### D2 — wallet-headers binding (native vs webview vs external)

**Recommendation: native webview embedded in the canonical app.**

- External browser tab (current reference): bad UX on mobile, breaks operator-sovereign feel
- Cloud-hosted URL: same problem + dependency on operator-hosted infra
- **Native webview** (flutter_inappwebview): keeps everything in-app, operator never sees a separate browser, wallet.html bundles into the cartridge asset bundle (`packages/wallet_headers_experience/assets/wallet.html`). Bridge to Dart via the platform channel for credential injection / response capture.

Adds one Flutter plugin dependency. ~3 days of work. Right call for the operator-acceptance story.

### D3 — Plexus RaaS enrollment (opt-in vs default-off)

**Recommendation: default OFF + opt-in toggle.**

Aligns with Q5 (default-local-only). The recovery envelope is generated + downloaded locally by default; the operator never has to trust an external Plexus operator unless they choose to. Cross-ref the "Bridget federation-ready" memory note (a potential RaaS counterparty) — that's an enrollment the operator opts into when ready.

### D4 — Cert minting ownership (helm vs brain)

**Recommendation: brain owns the cert. Helm displays + acts through it.**

The pairing flow (existing) already establishes the cert on the brain. C11 doesn't mint a new cert — it surfaces the existing one + composes recovery primitives on top. This locks the "brain is the canonical identity store" invariant from C7 + simplifies C12 (BRC-42 children derive from a brain-pinned root).

### D5 — Challenge question UX (hardcoded vs custom)

**Recommendation: defaults shown, override allowed.**

The wallet-headers `DEFAULT_CHALLENGE_QUESTIONS` ("Mother's maiden name?", "City of birth?", "First pet?") are decent defaults but trivially guessable. Show them pre-filled so the operator has anchor questions, but allow each to be replaced with a custom question. Track a `quality` warning if questions look low-entropy (single word answer, common date, etc.) but don't block.

---

## 7. Out of scope

- **Multi-device hat sync** — C12 ground (cert-derived hats per device per cartridge).
- **n-of-m threshold recovery** — see D1.
- **Web build of the "me" surface** — same `flutter build web` path as everything else; will work automatically once the brain web helm flips on (separate scope per Q2).
- **Migration of existing operators** — the brain at `oddjobtodd.info` already has cert metadata; C11 surfaces it. Pre-C11 paired devices get the new "me" surface on next app update with no migration needed.

---

## 8. Glossary additions (for canonicalization-glossary.md)

- **"me" surface** — the helm-level identity primitive. Shell-internal widget that surfaces root BRC-52 cert, wallet-headers actions, and recovery flows. Replaces the empty placeholder that was where the HatSwitcher lived pre-PR-C9-7a.
- **PlexusRecoveryEnvelope** — the canonical v1 recovery format (`cartridges/wallet-headers/brain/src/plexus/envelope.ts`). Operator-portable; encrypts BRC-42 derivation state under PBKDF2(normalized secret answers, salt, 100k).
- **shell.identity.envelope** — the cell type minted on the brain when an operator generates a recovery envelope (carries cert_id + envelope hash + generated timestamp + optional Plexus enrollment ref; *not* the envelope contents).
