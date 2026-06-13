---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/UNIFICATION-ROADMAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.711633+00:00
---

# Semantos Unification Roadmap

**Version**: 0.2 (draft)
**Date**: April 2026
**Status**: Living progress tracker. Update the matrix as cells move from ✗ → ⚠ → ✓.
**Source materials**: Plexus Client Requirements v2.1, Plexus Technical Requirements v1.3, `docs/prd/WORLD-PROTOCOL.md`, `docs/prd/PHASE-35A-SESSION-PROTOCOL-PROMOTION.md`, the existing semantos-core monorepo, and the in-flight monolith refactor program (Prompts 11/14/31/32/35-37/38/43/44).

> **North star** — the substrate is a *sovereign node for voice to economic execution*. The world layer is one adapter among many. See the (forthcoming) `docs/prd/SOVEREIGN-NODE-NORTH-STAR.md` for the *why*. This document tracks the *what we have to make true* so the north-star is reachable.

---

## 0. Assumed dependencies

This roadmap composes with the monolith refactor program. Surface paths and port names below are the **post-split** forms; cross-references to refactor prompts are inline where load-bearing.

- **Prompt 14** (payment-channel ports): defines `walletPort` / `utxoProviderPort` / `broadcasterPort` / `signerPort` / `spvPort` / `loggerPort`. **Required by D-G1 and D-D1-cap.**
- **Prompt 38** (multicast adapter split): introduces a codec port. **Required by D-C6** — the SignedBundle wrap becomes a five-line change inside that codec port. Without 38, it's surgery on a 793 LOC file.
- **Prompts 11 / 31 / 32** (chat shell, ChatView, ConversationPanel splits): expose the seams **D-A3 and D-C3** plug into. Pre-split, those deliverables would mean rewriting through 600+ LOC components.
- **Prompts 35-37** (navigation_app split): TS path references in D-A2 / D-C2 / D-D2 / D-F2 assume the post-split layout. See §9 for the file path crosswalk.
- **Prompt 43** (extension grammar validator) and **Prompt 44** (Settlement / Paskian app): seed the new surface rows (S11, S12) added in this revision.

**Sequencing constraint**: this roadmap targets monolith Phase 6 as the assumed start state. Anything that lands before refactor Phase 6 either runs against current paths (with rework cost noted) or waits.

---

## 1. What this document is

A single-page picture of where each surface stands against each unification axis, plus a phased ordering of the work that closes the gaps. Read this before any new feature work; update it after.

The point isn't to list features. It's to show that **unification is a small set of properties holding everywhere**, not a parallel "unified" subsystem. Every cell in the matrix represents one (surface, property) pair; the work is moving every cell to ✓.

The matrix is split visually into two sections:

- **Substrate** — components whose job IS to implement the axes. They're ✓ by construction (or are bugs against their own spec).
- **Adapters** — surfaces that consume the substrate to deliver user-facing capability. These are where ⚠ and ✗ cells cluster, and where unification work happens.

Status legend:

- **✓** unified — surface participates in this axis with no further work required.
- **⚠** partial — surface participates partly; deliverable named in §5.
- **✗** island — surface does not participate; private implementation or none.
- **n/a** — not meaningful for this surface.

---

## 2. The matrix

Rows are surfaces. Columns are unification axes. Axis D is split into four sub-axes after the v0.1 review feedback (D-sub = substructural via K1; D-lex = lexicon-domain via SIR; D-form = formal via Lean; D-cap = capability via BRC-108 UTXO).

<!-- GENERATED:matrix-start (CC6.4 renderer-in-loop; do not edit between markers) -->
<!--
  This block is the verbatim output of `bun docs/canon/render/matrix-to-roadmap.ts`.
  The source of truth is `docs/canon/unification-matrix.yml`.
  To update: edit the YAML, re-run the renderer, paste the block.
  The `cc6-4-matrix-render-freshness.test.ts` gate re-runs the renderer at
  test-time and asserts the content between the markers matches.
-->

## §2. The matrix

> Rendered from `docs/canon/unification-matrix.yml`. Do not edit this
> section directly — edit the YAML and re-run
> `bun docs/canon/render/matrix-to-roadmap.ts`.
### §2a. Substrate (✓ by construction is the goal)

| Surface | A. Identity | B. Storage | C. Transport | D-sub | D-lex | D-form | D-cap | E. Time | F. Recovery | G. Metering |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **U3 Identity / Derivation / Recovery** | ✓ D-A0, D-A0b | ✓ (BRC-52 cert fields and id…) | ✓ (BRC-100 + BRC-52 cert car…) | n/a | n/a | n/a | n/a | ✓ (Monotonic childIndex (§4.…) | ✓ (BRC-69 edge-backup recipe…) | n/a |
| **U5 Verifier Sidecar** | ✓ D-V1 | n/a | ✓ D-V1 | n/a | n/a | n/a | ✓ D-V1 | n/a | n/a | n/a |
| **U1 Cell Engine (Zig WASM)** | ✓ (BCA derivation (core/cell…) | ✓ (PDA + cell as the canonic…) | n/a | ✓ (K1 LINEAR / AFFINE / RELE…) | ⚠ (Lexicon constraints are S…) | ⚠ D-LC2 | n/a | ✓ D-LC5 | n/a | n/a |
| **U2 Plexus Core / Vendor SDK** | ✓ (BRC-42 BKDS implementatio…) | ✓ (Tenant-node records persi…) | ✓ (BRC-100 signed-request en…) | n/a | n/a | n/a | ✓ (BRC-108 capability UTXO m…) | ✓ (Monotonic childIndex enfo…) | ✓ (BRC-69 edge-backup recipe…) | ✓ (MFP channel-funding keys …) |
| **U4 Capability Domain** | ✓ (Each capability UTXO is b…) | ✓ (UTXOs are the on-chain st…) | ✓ (Capability presentation i…) | ✓ (K1 instantiated at the on…) | n/a | n/a | ✓ (BRC-108 is THE capability…) | ✓ (On-chain ordering provide…) | ✓ (Capability set is part of…) | ✓ (cap.metered_access UTXOs …) |
| **U6 Mesh (IPv6 multicast)** | ✓ (BCA derived from cert_id …) | n/a | ⚠ D-C6 | n/a | n/a | n/a | n/a | ✓ (Heartbeat sequence number…) | n/a | n/a |
| **U7 VFS (cells / octaves)** | ✓ D-LC3 | ✓ (VFS IS the storage substr…) | ⚠ D-LC1 | ✓ (Linearity is honoured at …) | ⚠ D-Dlex-vfs | n/a | n/a | ⚠ D-E-vfs | ⚠ D-F6, D-LC4 | n/a |
| **U8 SIR + Lexicons** | ✓ (SIR documents are cert-si…) | ✓ (SIR documents stored as c…) | ✓ (SIR documents transit BRC…) | n/a | ✓ (Lexicon authority is the …) | n/a | ⚠ (Lexicon-mint capability c…) | ⚠ D-E-sir | ⚠ D-F-sir | n/a |
| **U9 Lean Proof Layer** | ✓ (Proof artifacts are cert-…) | ✓ (Proof cells live in the V…) | n/a | n/a | n/a | ✓ (Lean is THE formal-proof …) | n/a | n/a | ⚠ D-F-lean | n/a |
| **U10 Metering Engine (MFP)** | ✓ (Channel-funding key deriv…) | n/a | ✓ (Channel state-update mess…) | ✓ (Channel state is a LINEAR…) | n/a | n/a | ✓ (cap.metered_access UTXOs …) | ✓ (Settlement-sequence order…) | ✓ (Open channels are recover…) | ✓ (MFP IS the metering primi…) |
| **U11 Canonical Cartridge (manifest-driven model)** | ✓ CC1 | ✓ CC5.B1, CC5.B2a, CC5.B2b, CC6.2 | ✓ CC0, CC2, DLO.1c, CC6.2 | ✓ CC0 | ✓ CC0 | ⚠ (Per-lexicon header-inject…) | ⚠ CC0, CC5.B2a | ✓ (Append-only versioned cel…) | ⚠ (A schema-declared cell ex…) | n/a |

### §2b. Adapters (consumers — where the work concentrates)

| Surface | A. Identity | B. Storage | C. Transport | D-sub | D-lex | D-form | D-cap | E. Time | F. Recovery | G. Metering |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **A1 World Host (OTP)** | ✓ D-V3, D-A1 | ⚠ D-B1 | ⚠ D-C1 | ✓ (Via U1 (cell engine K1 ga…) | ⚠ D-Dlex-world | n/a | ✗ D-Dcap-world | ✓ (Per-region WorldTick + Me…) | ✗ D-F1 | ✗ D-G1 |
| **A2 World Client (browser)** | ✓ D-A2 | ⚠ D-B2 | ✓ D-A2 | n/a | ⚠ D-Dlex-wc | n/a | ✗ D-Dcap-wc | ✓ (Predictor (WASM) provides…) | ✗ D-F2 | n/a |
| **A5 Calendar** | ✓ D-A5 | ⚠ D-B5 | ⚠ D-C5 | ✓ (Schedule patch stream is …) | ⚠ D-Dlex-cal | ✗ D-Dform-cal | ✗ D-Dcap-cal | ✓ (Schedule fold + per-patch…) | ✗ D-F5 | ✗ D-G5 |
| **A8 Voice (input modality)** | ✓ D-A7 | ✗ D-B7 | ✗ D-C8 | ✗ | ✗ | n/a | ✗ D-Dcap-world | ⚠ (Client-side prediction vi…) | ✗ D-F2 | ✗ D-G2 |
| **A3 Helm / Loom** | ✓ D-A3 | ✓ (LoomObject + cell-backed …) | ⚠ D-C3 | ⚠ D-Dsub-helm | ⚠ D-Dlex-helm | ⚠ D-Dform-helm | ⚠ D-Dcap-helm | ⚠ D-E-helm | ⚠ D-F3 | ⚠ D-G3 |
| **A4 Md Editor (docs)** | ✓ D-A4 | ⚠ D-B3 | ✗ D-C4 | ✗ D-Dsub-md | ✗ D-Dlex-md | ✗ D-Dform-md | ✗ D-Dcap-md | ✗ D-E-md | ✗ D-F4 | n/a |
| **A7 Extensions / Policy Runtime** | ✓ D-A6 | ⚠ D-B6 | ⚠ D-C7 | ⚠ D-Dsub-ext | ✓ (Lexicon authority is the …) | ⚠ D-Dform-ext | ✓ D-A6 | ⚠ D-E-ext | ⚠ D-F7 | n/a |
| **A6 Settlement (Paskian)** | ✓ (Settlement signs every tr…) | ⚠ D-B5 | ✓ (Settlement messages ride …) | ✓ (Linearity is structural —…) | n/a | n/a | ✓ (Settlement gates on capab…) | ✓ (On-chain ordering provide…) | ✓ (Settled-channel state is …) | ⚠ D-G3 |
| **A9 Jam Room (world-app cartridge)** | ⚠ (ownerIdentity + ownerCert…) | ⚠ (Content-addressed cells v…) | ⚠ (CellRelay WebSocket trans…) | ⚠ (linearity field present i…) | ✗ (13 jam.* kinds declared i…) | n/a | ✗ (Blocked on D-Dcap-engine …) | ⚠ (previousStateHash + DAG h…) | ✗ (Plexus recovery wiring no…) | ✗ (Metering channels not ope…) |
| **A10 World-apps directory (doc closure)** | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| **A11 Tessera (care-chain provenance cartridge)** | ✗ (Identity (V4.1 NFC BCA + …) | ⚠ (StorageAdapter-consumer c…) | ✗ (Transport (V5.1 NetworkAd…) | ⚠ V0.5 | ✓ V0.4 | ✓ (Six Lean theorems (tamper…) | ⚠ V0.3 | ✓ (Time/DAG inherited from s…) | ⚠ (Recovery closes passively…) | ⚠ (Metering: per-scan / per-…) |

---

_11 substrate rows, 11 adapter rows._

<!-- GENERATED:matrix-end -->

### 2c. Reading the matrix

> **SIR and Lean are now substrate rows** (U8, U9), per v0.1 review: they're tools for achieving axis D on non-cell-engine surfaces, but they're also surfaces in their own right (you author / edit / version / formally verify SIR; Lean proofs are themselves cells with provenance). They sit in substrate because their job is to *implement* sub-axes D-lex and D-form for everyone else.

**Read-out, in plain English (post-review)**:

- **The substrate is mostly green** because Plexus + the cell engine are designed to implement the axes; that's their entire purpose. ⚠ cells inside the substrate (U6, U7, U8, U9) are integration gaps where two substrate components don't yet talk to each other cleanly.
- **The big islands** are A4 (Md Editor), A5 (Calendar), A8 (Voice — entirely placeholder), and A1's recovery/metering columns. These are where unification work concentrates.
- **A3 (Helm) is the broadest ⚠ row** because it touches all axes — it's the convergence surface where a user sees their entire node. Helm being ✓-everywhere is roughly equivalent to "the unified user experience exists."
- **A6 (Settlement) is mostly ✓** because it follows the Plexus spec directly; it's a worked example of "what happens when an adapter is built Plexus-native from day one."
- **A7 (Extensions) is partly ✓** because it's both a substrate-shaped thing (mints lexicons, defines capabilities) and an adapter (consumes identity, transport). It straddles, intentionally.
- **A8 (Voice) is intentionally placeholder** — naming it forces the conversation about the input modality the north-star depends on.
- **U11 Canonical Cartridge** is the wave-canonical-cartridge surface — its B/C axes carry the schema-spine + CC6 ingest deliverables (CC5.B1/2a/2b + CC6.2 on B; CC0/CC2/DLO.1c/CC6.2 on C). D-form + D-cap + F remain ⚠ (composition proofs, §9 cap-mirror generator, per-cartridge recovery — follow-ups beyond CC6).

---

## 3. The unification axes, defined

| Axis | Sub-axis | One-sentence definition | Reference / referent |
|---|---|---|---|
| **A. Identity** | — | Every actor binds to a BRC-52 certificate; every action carries the cert_id and a BCA derived from it; the Verifier Sidecar enforces signing-key matches certificate.subject. | Plexus Tech §1, §8, §9, §15 |
| **B. Storage** | — | Every datum is a cell with a `CellHeader`; addressable in an octave-based content-addressed VFS; cell state advances only via hash-chained patches. | `core/cell-engine/src/{pda,cell,octave}.zig`, `runtime/shell/src/vfs/` |
| **C. Transport** | — | Every cross-process or cross-node message is a `SignedBundle<T>` formatted as a BRC-100 signed request. | Plexus Tech §1, §4, §8; `runtime/session-protocol/src/bundle-envelope.ts` |
| **D-sub. Type (substructural)** | — | LINEAR / AFFINE / RELEVANT enforcement at the kernel via the K1 gate. | `core/cell-engine/src/linearity.zig` |
| **D-lex. Type (lexicon)** | — | Domain-semantic types (jural, CDM, BRAP, control-systems, calendar, etc.) over SIR-shaped content. | `core/semantos-sir/src/lexicons.ts` (referent **U8**) |
| **D-form. Type (formal)** | — | Lean-proven invariants over SIR-typed content; proofs ride alongside cells with their own provenance. | `proofs/lean/Semantos/Lexicons.lean` (referent **U9**) |
| **D-cap. Type (capability)** | — | Authority to act gated by an unspent BRC-108 UTXO; spending consumes the capability atomically (linear semantic resource). | Plexus Tech §7, §14 |
| **E. Time** | — | Every change advances a hash chain — per-entity, per-region, per-channel (MFP nSequence), per-domain (BKDS monotonic current_index). | `docs/prd/WORLD-PROTOCOL.md` §6, §10; Plexus Tech §10, §14, §23 |
| **F. Recovery** | — | Every persistent surface holding derivation state can export to the Plexus Recovery service in canonical JSON and reconstruct via PBKDF2 root-seed regeneration on the client device. | Plexus Tech §11, §16-§24 |
| **G. Metering** | — | Every paid resource flow advances an MFP 2-of-2 multisig channel with HMAC-authenticated ticks, settled off-chain and finalised on-chain via SPV; capability UTXOs gate participation. | Plexus Tech §14, §7 |

---

## 4. Phase ordering — what's sequential, what's parallel

```
                   ┌──────────────────────────────────────────────┐
                   │  Phase 0  — Foundation                        │
                   │  cell-engine + BCA + WORLD protocol working   │
                   │  STATUS: complete                             │
                   └──────────────────────┬───────────────────────┘
                                          │
                                          ▼
                   ┌──────────────────────────────────────────────┐
                   │  Phase 0.5  — Verifier Sidecar (SEQUENTIAL)   │
                   │  D-V1 stub, D-V2 deployment topology decision,│
                   │  D-V3 first integration. Days, not weeks.     │
                   │  Blocks Phase 1b's C/D cells.                 │
                   └──────────────────────┬───────────────────────┘
                                          │
                                          ▼
                   ┌──────────────────────────────────────────────┐
                   │  Phase 1a  — Foundational identity contract   │
                   │  (SEQUENTIAL, days)                           │
                   │  BRC-52 cert flow contract, BCA library       │
                   │  shared across surfaces, VerifierStub spec.   │
                   │  Single thread; small.                        │
                   └──────────────────────┬───────────────────────┘
                                          │
                                          ▼
                   ┌──────────────────────────────────────────────┐
                   │  Phase 1b  — Per-surface identity (PARALLEL)  │
                   │  Each adapter integrates A1's contract on its │
                   │  own A cell. Independent threads per surface. │
                   └──┬───────────┬───────────┬──────────────────┘
                      │           │           │
              ┌───────▼─┐  ┌──────▼──┐  ┌─────▼─────┐
              │ Phase 2 │  │ Phase 3 │  │ Phase 4   │   ── parallelisable per surface ──
              │Transport│  │  Type   │  │  Storage  │
              │ (axis C)│  │(axis D) │  │ (axis B)  │
              └────┬────┘  └────┬────┘  └─────┬─────┘
                   │            │             │
                   └─────┬──────┴─────────────┘
                         │
                         ▼
                   ┌─────────────────────┐         ┌────────────────────┐
                   │ Phase 5             │         │ Phase 3b           │
                   │ Recovery (axis F)   │         │ Time (axis E)      │  ← parallelisable
                   │ needs P1 + P3       │         │ per surface anytime│     anytime
                   └──────────┬──────────┘         └────────────────────┘
                              │
                              ▼
                   ┌──────────────────────┐
                   │ Phase 6              │
                   │ Metering (axis G)    │
                   │ needs P1 + P2        │
                   └──────────────────────┘
```

**Sequencing rules** (revised from v0.1):

1. **Phase 0 is done.** Don't relitigate.
2. **Phase 0.5 is sequential and blocking.** The Verifier Sidecar is load-bearing for axes A, C, and D-cap simultaneously. It needs to exist (at minimum as a `VerifierStub`) before any deliverable that consumes it can complete. Days, not weeks.
3. **Phase 1a is genuinely sequential and small** — define the BRC-52 cert flow contract, the shared BCA library, the VerifierStub interface as fixtures the rest of the work depends on. Single thread. Probably 2–3 days.
4. **Phase 1b is per-surface parallel.** For each adapter S, S's A cell must complete before S's C/D/F cells start. Different surfaces can advance through A → C/D → F as their own tracks simultaneously. The per-surface ordering matters; the cross-surface coordination doesn't.
5. **Phases 2, 3, 3b, 4** can run in parallel after Phase 1b lands per surface.
6. **Phase 5 (Recovery)** depends on Phase 1 + Phase 3 for a given surface.
7. **Phase 6 (Metering)** depends on Phase 1 + Phase 2 for a given surface, plus the U10 substrate component.

**Critical path** (the longest dependency chain): P0 → P0.5 → P1a → (any adapter's P1b → P3 → P5 → P6).

---

## 5. Per-cell deliverables

Format: `D-<axis><tag>: title — what's needed — phase`. IDs are stable; reference them in commits, PRs, and sub-PRDs.

### Phase 0.5 — Verifier Sidecar (sequential, blocking)

- **D-V1: VerifierStub interface + reference implementation.**
  Define the BRC-100 verification protocol as a TS interface (`packages/verifier-sidecar/src/types.ts` — post-refactor). Reference impl performs BRC-100 signature check, BRC-52 cert authenticity, identity binding (signing key == certificate.subject), and SPV checks for capability UTXOs. **Phase 0.5.**
- **D-V2: Deployment topology decision.**
  Decide where the Sidecar runs: per-surface in-process (cheap, hard to update independently), separate process per node (operational complexity), or edge gateway (single chokepoint, easier ops). Pick one default; document the others. **Phase 0.5.**
- **D-V3: First integration (consumed by Phase 1b).**
  Wire `VerifierStub` into a single adapter (recommended: A1 World Host) end-to-end, as the integration template. Becomes the reference everyone else copies. **Phase 0.5 → unblocks Phase 1b.**

### Phase 1a — Foundational identity contract (sequential)

- **D-A0: Shared BCA library.**
  TS package implementing BCA derivation per `core/cell-engine/src/bca.zig`, with vectors from `core/cell-engine/tests/vectors/bca_*.json`. Used by every adapter and substrate component that needs to derive identity. **Phase 1a.**
- **D-A0b: BRC-52 cert flow contract.**
  Canonical TS types for cert payloads, registration flow, and verification headers. Mirror to Elixir for world-host consumers. **Phase 1a.**

### Phase 1b — Per-surface identity (parallel)

- **D-A1 (A1×A): World Host accepts BRC-52 cert at WebSocket connect.**
  Replace random session_id in `apps/world-host/lib/world_host_web/user_socket.ex` with BRC-52 verification via D-V1 sidecar. Derive BCA from cert_id; expose as `socket.assigns.bca`. Phase 1b.
- **D-A2 (A2×A): World Client signs every action with the user's BRC-52 cert.**
  Replace random session_id in TS client with cert-based signing using the Plexus Network SDK. Post-refactor path: `apps/navigation-app/world-client/src/socket.ts` (verify via §9). Phase 1b.
- **D-A3 (A3×A): Helm wires to Plexus identity.**
  Helm boots after Plexus identity has issued a cert; helm uses the cert to authorise its own backend calls. Plug-in point is post-refactor `apps/navigation-app/chat-shell/` (Prompt 11). Phase 1b.
- **D-A4 (A4×A): Md Editor identifies authors via cert_id.**
  Every patch in a markdown doc carries the author's cert_id; replaces any opaque user-id field. Phase 1b.
- **D-A5 (A5×A): Calendar Hat → BRC-52 migration.**
  Calendar already has `HatPayload`/`HatRecord` doing structured identity work in `extensions/calendar/src/domain/hat.ts`. Migrate to BRC-52 cert backing: cert_id replaces hatId; HatPayload becomes a BRC-52 schema attached to the cert_id. Preserves existing semantics, gains cryptographic provenance. Phase 1b.
- **D-A6 (A7×A): Extensions runtime certs lexicon-authority via cert_id.**
  Extensions that mint capabilities or define lexicons must do so under a BRC-52-anchored authority cert. Replaces any current "trusted issuer" string with cryptographic binding. Phase 1b.
- **D-A7 (A8×A): Voice input session identifies via BRC-52.**
  Placeholder. When voice lands as a real surface, sessions are cert-bound (otherwise the voice channel is unauthenticated speech). Phase 1b.

**Phase 1 acceptance criterion**: every surface in §2 has cert-bound identity. `grep -r "session_id\|random_bytes" apps/` returns zero matches in identity-bearing code paths.

### Phase 2 — Transport (parallel after surface's P1b)

- **D-C1 (A1×C): World Host messages become SignedBundle on the wire.**
  Replace bare JSON over Phoenix Channels with BRC-100 signed envelopes. Verifier Sidecar pass before any action reaches `Region.apply_action`. Phase 2.
- **D-C2 (A2×C): World Client emits SignedBundle.**
  Pair with D-C1; client wraps every action in a BRC-100 signed envelope via the Plexus Network SDK. Phase 2.
- **D-C3 (A3×C): Helm uses Plexus Network SDK for backend calls.**
  No direct fetch / Phoenix calls; everything routes through the network SDK so signing, retries, and BRC-103 nonce handshakes are uniform. Plug-in point: post-refactor `apps/navigation-app/chat-shell/` and ConversationPanel split. Phase 2.
- **D-C4 (A4×C): Md Editor sync uses SignedBundle.** Phase 2.
- **D-C5 (A5×C): Calendar event sync uses SignedBundle.** Phase 2.
- **D-C6 (U6×C): Mesh codec port wraps frames in SignedBundle.**
  Five-line change inside the Prompt 38 codec port. Phase 2.
- **D-C7 (A7×C): Extensions runtime exposes its registry via BRC-100 endpoints.** Phase 2.
- **D-C8 (A8×C): Voice channel speaks SignedBundle (placeholder).** Phase 2.

### Phase 3 — Type (parallel after surface's P1b)

For each non-trivial surface, four sub-deliverables (one per sub-axis). Where a sub-axis doesn't apply, it's skipped.

- **D-Dsub-helm (A3×D-sub): Helm dispatches actions through K1 pre-check.**
  Helm consults the cell engine before sending any action that would mutate a typed cell. Phase 3.
- **D-Dsub-md (A4×D-sub): Md Editor cells get linearity classification.**
  Documents/sections/blocks per linearity (LINEAR for ratified, AFFINE for drafts, RELEVANT for published, UNRESTRICTED for scratch). K1 enforces edits at cell boundaries. Phase 3.
- **D-Dsub-cal (A5×D-sub): Calendar/Event cells get linearity.**
  Events as AFFINE; recurring rules as RELEVANT. Phase 3.
- **D-Dsub-ext (A7×D-sub): Extension capability cells routed through K1.** Phase 3.
- **D-Dlex-world (A1×D-lex): World Host validates entity payloads against a `world` lexicon.** Phase 3.
- **D-Dlex-wc (A2×D-lex): Client predictor validates outgoing actions against `world` lexicon.** Phase 3.
- **D-Dlex-helm (A3×D-lex): Helm renders cells per lexicon-typed rules.** Phase 3.
- **D-Dlex-md (A4×D-lex): Md Editor surfaces lexicon-violation diagnostics inline.** Phase 3.
- **D-Dlex-cal (A5×D-lex): Calendar lexicon: events, rules, attendees as typed cells.** Phase 3.
- **D-Dlex-vfs (U7×D-lex): VFS path resolution checks lexicon constraints on parent/child relationships.** Phase 3.
- **D-Dform-helm (A3×D-form): Helm shows Lean-proof status alongside live cells.** Phase 3.
- **D-Dform-md (A4×D-form): Md Editor surfaces "this edit invalidates proof X" warnings.** Phase 3.
- **D-Dform-cal (A5×D-form): Calendar's recurring-rule consistency checked via Lean (optional).** Phase 3.
- **D-Dform-ext (A7×D-form): Extension lexicons can carry Lean-proven invariants.** Phase 3.
- **D-Dcap-world (A1×D-cap): World Host capability gating.**
  Each Region requires `cap.experience` UTXO at WebSocket connect. Each entity action requires per-domain capability (e.g. `cap.world.move`). Verifier Sidecar performs SPV checks. Phase 3.
- **D-Dcap-wc (A2×D-cap): Client surfaces capability state.**
  UI shows which actions are presently authorised. Phase 3.
- **D-Dcap-helm (A3×D-cap): Helm checks capability before dispatching mutations.** Phase 3.
- **D-Dcap-md (A4×D-cap): Md Editor edits gated by `cap.doc.write` or similar.** Phase 3.
- **D-Dcap-cal (A5×D-cap): Calendar event creation gated by `cap.calendar.write`.** Phase 3.

### Phase 3b — Time (parallel, anytime after P1b)

Now expanded per-surface (v0.1 had a single bullet covering five surfaces).

- **D-E-helm (A3×E): Helm subscribes to per-cell tick streams, surfaces hash chain in inspector view.** Phase 3b.
- **D-E-md (A4×E): Md Editor per-doc hash chain with branching support.**
  Branching docs require a chain that forks (one parent → two children) and merges (two parents → one child). Closer to git semantics than to the linear region-tick chain. Decision required: do we treat this as a chain-of-chains (one per branch, with merge nodes) or a single DAG? Phase 3b.
- **D-E-cal (A5×E): Calendar recurring rules — chain semantics.**
  When a recurring rule is edited, do existing instances inherit the edit (chain-through) or fork off (chain-forks)? Both defensible; the choice is policy. Recommend chain-forks (existing instances retain their version, new instances follow the new rule) — preserves immutability of past calendar events. Phase 3b.
- **D-E-vfs (U7×E): VFS directory-mutation chain.**
  Directory creates/moves/deletes need their own chain story separate from per-cell chains. Recommend treating directory ops as cells with their own hash chain, with the VFS providing a unified-view query. Phase 3b.
- **D-E-sir (U8×E): SIR documents have a hash chain over their patch sequence.**
  Already partly there via cell mechanics; needs the per-SIR-doc projection. Phase 3b.
- **D-E-ext (A7×E): Extension manifests have a hash chain over their version history.** Phase 3b.

**Phase 3b acceptance criterion**: every cell shown in any UI has a verifiable hash chain from genesis to current state.

### Phase 4 — Storage (parallel after surface's P1b)

- **D-B1 (A1×B): World Host entity state stored as cells, not Elixir maps.**
  `WorldHost.Entity`'s state struct converts to a `CellHeader`-prefixed cell on each tick; persistence via kernel snapshot. Phase 4.
- **D-B2 (A2×B): World Client mirrors authoritative state as cells (via WASM kernel locally).** Phase 4.
- **D-B3 (A4×B): Md Editor docs are cell-backed.**
  Each section/block is a cell; document is a tree of cells in the VFS. Phase 4.
- **D-B4 (A5×B): Calendar events are cells with `calendar.event` lexicon type.** Phase 4.
- **D-B5 (A6×B): Settlement records as cells in the VFS (replaces ad-hoc storage).** Phase 4.
- **D-B6 (A7×B): Extension manifests + capability schemas as cells.** Phase 4.
- **D-B7 (A8×B): Voice transcripts and intent extractions as cells (placeholder).** Phase 4.

### Phase 5 — Recovery (sequential after surface's P1 + P3)

- **D-F1 (A1×F): World Host regions participate in Plexus recovery.**
  Region state exported via kernel snapshot bundled as recovery payload signed by RaaS. Phase 5.
- **D-F2 (A2×F): World Client restores from recovery payload on new device.** Phase 5.
- **D-F3 (A3×F): Helm participates in recovery (layout, open documents).** Phase 5.
- **D-F4 (A4×F): Md Editor docs included in recovery export.** Phase 5.
- **D-F5 (A5×F): Calendar events included in recovery export.** Phase 5.
- **D-F6 (U7×F): VFS slot/octave index included in recovery export.** Phase 5.
- **D-F7 (A7×F): Extension manifests included in recovery export.** Phase 5.
- **D-F-sir (U8×F): SIR documents and Lean proofs included in recovery export.** Phase 5.
- **D-F-lean (U9×F): Lean proof artifacts included in recovery export.** Phase 5.

### Phase 6 — Metering (sequential after surface's P1 + P2)

- **D-G1 (A1×G): World Host regions emit MeteringTicks.**
  Each region with paid clients opens an MFP channel (consumes Prompt 14's payment-channel ports); each WorldTick optionally advances the channel. Phase 6.
- **D-G2 (A3×G): Helm shows live metering state per region/service; recharge UI for low balances.** Phase 6.
- **D-G3 (A6×G): Settlement integrates with MFP channels for atomic on-chain finalisation.** Phase 6.

---

## 6. Boot sequence as the unifying narrative

Every phase enables a step. If the boot sequence runs end-to-end, the unification is real.

```
1. User provides email + answers challenges            ← P1a + Plexus existing
2. PBKDF2 100k iterations on device → root seed        ← Plexus core
3. Derive BRC-52 cert from root seed → cert_id         ← Plexus core
4. BCA(cert_id) computed via shared BCA library        ← P1a (D-A0)
5. Vendor SDK initializes tenant_nodes locally         ← Plexus Vendor SDK ✓
6. Capability Domain mints initial UTXOs               ← Plexus Capability Domain ✓
7. Cell engine boots, kernel_set_enforcement(1)        ← cell engine ✓
8. Verifier Sidecar starts (per topology decision)     ← P0.5
9. World Host (if needed) starts regions               ← P1b + P2 + P3-cap
10. Mesh adapter joins multicast group from cert_id    ← P1b + P2 (D-C6)
11. UI server (helm) binds localhost                   ← P1b + P2 + P3
12. Adapters subscribe, each to:                       ← P2 + P3b
       a) their region's PubSub topic for tick deltas   (transport + time compose)
       b) Plexus identity/edge event stream             (cross-surface change feed)
       c) capability UTXO change feed                   (auth state)
13. Recovery payload backed up to Plexus Cloud         ← P5
14. Metered services open cashlanes                    ← P6
15. User is fully online, sovereign, federated         ←
```

Step 12 is where transport (axis C) and time (axis E) compose — every adapter subscribes to *the same set of streams* via *the same envelope format* (`SignedBundle`) carrying *the same provenance metadata* (BCA, cert_id, hash chain). That's unification rendered concrete.

The boot sequence currently halts at step 9 in production-shaped form. Steps 1-7 work end-to-end; steps 8+ work in feasibility but not under proper BRC enforcement.

---

## 7. Suggested first slice (week 1)

After v0.1 review, the slice is restructured around the Verifier Sidecar prerequisite.

**Day 1-2** (sequential, blocking):
- D-V1 (VerifierStub interface + reference implementation)
- D-V2 (deployment topology decision)
- D-A0 (shared BCA library), D-A0b (BRC-52 cert flow contract)

**Day 3-5** (parallel, two engineers):
- Track A: D-A1 + D-V3 (world host integrates VerifierStub)
- Track B: D-A2 (world client signs)

**Day 6-7** (sequential):
- D-C1 (world-host SignedBundle wrap), assumed building on Day 5's identity work

**Acceptance** at end of week: opening `localhost:5176` in two tabs requires each to present a BRC-52 cert (mock issued by the local Plexus instance), the cube demo continues to work, the Verifier Sidecar logs every accepted/rejected action, and `grep -r "session_id\|random_bytes" apps/world-host apps/world-client` is clean in identity paths.

This is the smallest slice that turns world-host into a Plexus-compliant Tier-2 component and establishes the integration template the rest of the surfaces copy.

---

## 8. Governance questions — resolved (2026-04-26)

All five governance questions resolved this session. Decisions are normative; rationale is recorded for future reference. Each decision propagates into the canon and is enforced by the artifacts that hydrate from it (`docs/spec/protocol-v0.5.md`, `docs/canon/glossary.yml`, future deliverable PRs).

### Q1 — World Host as named Plexus component? **RESOLVED: yes; assign `0x0B EXPERIENCE`.**

World Host is named as a first-class Plexus well-known domain (flag `0x0B`, mnemonic `EXPERIENCE`) with capability mint authority for `cap.experience`. The flag is reserved in the Plexus well-known range (`0x00000001`–`0x000000FF`) per §4.5 of `docs/spec/protocol-v0.5.md`.

*Rationale.* World Host needs domain-flag-typed authority to mint `cap.experience` capabilities (entry to a region, avatar control rights, etc.). Naming it as a Plexus well-known flag rather than borrowing client-sovereignty space makes World Host first-class to the substrate and avoids retrofit cost when D-G1 lands. Phase 1b can proceed; D-G1 consumes the named flag rather than retrofitting one.

### Q2 — Where do new flag-typed id types live? **RESOLVED: codify the partition in `core/protocol-types/src/namespace.ts`.**

The same uint32 partition (Plexus reserved `0x00000001`–`0x000000FF`, extended Plexus `0x00000100`–`0x0000FFFF`, operator sovereignty `0x00010000`–`0xFFFFFFFF`) MUST apply to every flag-typed id type in the substrate: domain flags, lexicon ids, region types, world-frame `msgType`s, tenant types, and any future id type.

The partition MUST be codified once in `core/protocol-types/src/namespace.ts` exporting (at minimum) the predicates `isPlexusReserved(flag) | isExtendedPlexus(flag) | isOperatorSovereign(flag)` and the named ranges. Every new id type MUST import and apply these predicates rather than re-deriving the partition convention.

*Rationale.* Single source of truth eliminates a class of bug where two id types independently re-derive the partition and disagree at the boundary. Resolution falls under Phase 1a (foundational identity contract) since it is consumed by D-A0 / D-A0b.

### Q3 — Verifier Sidecar deployment topology default. **RESOLVED: per-node sidecar process.**

The default deployment topology for the Verifier Sidecar is **per-node sidecar process**. Two exception cases are explicitly permitted:

- **Per-surface in-process** for tightly-coupled pairs where byte-budget or latency tightness demands it (notably cell engine + World Host on the same node).
- **Edge gateway** for centralised deployments where audit-at-a-single-point is the operational priority.

*Rationale.* The per-surface in-process option couples sidecar releases to surface releases — bad for security patches that need to land independently. The edge-gateway option creates both a single chokepoint and a single point of failure. The per-node process is independently deployable, independently observable, independently replaceable, and matches the "sovereign node" deployment model architecturally. Documented in `docs/spec/protocol-v0.5.md` §9.5.

### Q4 — Branching semantics for the markdown editor (D-E-md). **RESOLVED: tree-of-chains.**

Documents in the markdown editor adopt **tree-of-chains** branching semantics. Each branch is its own hash chain forked from a parent commit; merge nodes have two parent-hashes; the document's history is a directed tree of independent chains rather than a single DAG.

*Rationale.* User mental model matches git. Tree-of-chains makes branching explicit, merging unambiguous, and authority traceable per branch (each branch has a single hat-signed series of patches). Single-DAG is structurally more general but adds cognitive load that v1 readers don't need. The migration cost from tree-of-chains to single-DAG (if a future use case demands it) is lower than the cost of training users on single-DAG semantics upfront. Resolution lands when D-E-md kickoff begins; the protocol-level constraint is recorded here so the implementation has a fixed target.

### Q5 — Recurring-rule chain policy for the calendar (D-E-cal). **RESOLVED: chain-forks.**

When a recurring rule is edited, existing instances retain their version (the original recurring rule remains the authority for those instances). Future instances follow the new rule. The chain forks at the edit point.

*Rationale.* Preserves the immutability of past calendar events — a regulatory and audit property — while letting the new rule shape future instances. The "chain-through" alternative (existing instances inherit edits) is operationally convenient for ad-hoc rescheduling but breaks audit: someone reviewing what was scheduled at time T sees the edited rule, not the rule that was actually in force. The trade-off is firmly in favour of forks. Resolution lands when D-E-cal kickoff begins.

---

## 9. File path crosswalk (post-monolith-refactor)

Selected paths referenced in deliverables, with current vs post-split locations. Treat post-split forms as authoritative; current forms only matter if work starts before refactor Phase 6 lands.

| Surface | Current path | Post-split path (post Prompts 11/31/32/35-37/38) |
|---|---|---|
| World host socket | `apps/world-host/lib/world_host_web/user_socket.ex` | unchanged (Elixir, untouched by refactor) |
| World client socket | `apps/world-client/src/socket.ts` | `apps/navigation-app/world-client/src/socket.ts` |
| Helm chat shell | `apps/loom-react/src/canvas/ChatView.tsx` (et al.) | `apps/navigation-app/chat-shell/` (Prompt 11) |
| Helm conversation | `apps/loom-react/src/canvas/ConversationPanel.tsx` | `apps/navigation-app/chat-shell/conversation/` (Prompts 31/32) |
| Multicast adapter | `runtime/session-protocol/src/adapters/multicast-adapter.ts` | adapter + `codec` port (Prompt 38) |
| Calendar identity | `extensions/calendar/src/domain/hat.ts` | unchanged (extension layout stable) |
| Payment-channel ports | scattered in `runtime/services/src/plexus/` | dedicated port modules (Prompt 14) |
| Extension grammar | embedded in extension validators | dedicated package (Prompt 43) |
| Settlement | `apps/settlement/` (new per Prompt 44) | `apps/settlement/` |

---

## 10. How to use this document

- **Update the matrix** (§2) every time a deliverable lands. Cells move ✗ → ⚠ → ✓.
- **Reference deliverable IDs** (D-A1, D-V1, D-Dsub-md, etc.) in commits, PRs, and sub-PRDs.
- **Walk the boot sequence** (§6) every release; if a step fails, that's the unification regression.
- **Don't add features** that aren't on the matrix without first updating the matrix.
- **The governance questions** (§8) should be resolved before the deliverables they gate, not deferred indefinitely.
- **Follow the TDD ladder** for every deliverable (§11.3) — failing test lands first.

---

## 11. Truth-alignment supplement (fact-check 2026-05-13)

A fact-check sweep on 2026-05-13 against the substrate paper / public framing surfaced systematic gaps between *claimed* architecture and *shipped* code. Rather than spawn a parallel tracker, this section pins the gaps onto existing deliverable IDs and adds new IDs only where the matrix doesn't yet have a home. Closes [`docs/GAP-CLOSURE-ROADMAP.md`](../GAP-CLOSURE-ROADMAP.md) by folding its content here.

### 11.1 The eight gaps and where they live

| Gap (claim vs reality) | Closed by | New ID? |
|---|---|---|
| **G1.** "Capability tokens bound to UTXOs" — currently bearer tokens at [bearer_tokens.zig](../../runtime/semantos-brain/src/bearer_tokens.zig); `OP_CHECKCAPABILITY (0xC3)` checks a `u32` index | D-Dcap-engine (new), D-Dcap-world, D-Dcap-wc, D-Dcap-helm, D-Dcap-md, D-Dcap-cal | **D-Dcap-engine** (U1×D-cap) |
| **G2.** "Universal intent pipeline" closing the API loophole — [INTENT-PIPELINE.md](INTENT-PIPELINE.md) marked *"design only"*; `chat.ts` produces JSON, not cells | D-Dlex-voice (new), D-Dcap-voice (new), D-IP-equiv (new), D-IP-e2e (new) | **D-Dlex-voice** (A8×D-lex), **D-Dcap-voice** (A8×D-cap), **D-IP-equiv**, **D-IP-e2e** |
| **G3.** "Mathematically proven correct" — 55 Lean files prove theorems on abstract spec; no property tests derived from theorems, no runtime extraction | D-Dform-property (new), D-Dform-coverage (new), existing D-Dform-* | **D-Dform-property**, **D-Dform-coverage** |
| **G4.** World host with 20 Hz tick — single hardcoded region with 3 LinearCubes; cross-region two-phase commit specified but never run | D-W1 (new), D-W2 (new), D-W3 (new) | **D-W1** (multi-region supervisor), **D-W2** (cross-region 2PC), **D-W3** (tick-decoupling proof) |
| **G5.** Federation transport — Phase-35A UDP multicast partial; Phase-35B WSS NodeAdapter not shipped; no NetworkAdapter contract suite | D-C6 (existing, ⚠), D-C6b (new), D-C6c (new), D-C6d (new) | **D-C6b** (Phase-35B WSS), **D-C6c** (NetworkAdapter contract suite), **D-C6d** (peer locator) |
| **G6.** Markdown editor + tree-of-chains — stub `extensions/md-editor/`; tree-of-chains decided (Q4) but unimplemented | D-E-md (existing, ✗), D-Dsub-md, D-Dlex-md, D-Dform-md, D-Dcap-md, D-B3 — all existing | none |
| **G7.** 1024-byte cell alignment story is undocumented (UDP frame ↔ LMDB 4KB page ↔ WASM 1MB stack ↔ K5 bounded termination) | D-Doc-1024 (new) | **D-Doc-1024** |
| **G8.** Pask, HRR, chain-broadcast, MFP, verb-dispatch, shell-cartridges-hats absent from public architecture story | D-Doc-three-kernels, D-Doc-fed, D-Doc-adapters, D-Doc-shell-cartridges-hats (all new) | **D-Doc-*** family |

### 11.2 New deliverables defined here

These get added to the relevant phase sections in §5 once any work begins. For now they live here as the canonical definition.

- **D-Dcap-engine (U1×D-cap):** `OP_CHECKCAPABILITY` queries the Verifier Sidecar for SPV-checked BRC-108 UTXO state, replacing the `u32` bearer-token index. Substrate gap; blocks every adapter `D-Dcap-*`. Depends on D-V1, D-V3. **Phase 3.**
- **D-Dlex-voice (A8×D-lex):** NL → SIR extractor with deterministic feature extraction + LLM-assisted refinement on ambiguity. Same NL + same scope + same lexicon ⇒ same SIR (determinism property). Replaces "Voice is intentionally placeholder." Per memory `no_hardcoded_workarounds.md`: LLM is structured-output extractor over fixed schema, not free-form mapper. **Phase 3.**
- **D-Dcap-voice (A8×D-cap):** Voice-originated intents verify caller's BRC-52 cert proves ownership of capability UTXO before lowering to OIR. Closes Todd's "BRC-52 + capability + Plexus-challenge" auth model (memory `brain_auth_model_intent.md`, tracker T7). **Phase 3.**
- **D-IP-equiv (cross-cutting):** Property test that all five input modes (voice, click, NL chat, governance ballot, batch CSV) lower to **identical SIR** for semantically equivalent intent. Existence proof for the "API loophole closed" claim. Tests in `runtime/intent/tests/input-equivalence.test.ts`. **Phase 3.**
- **D-IP-e2e (cross-cutting):** End-to-end integration test: speech-act → NL→SIR → SIR→OIR → OIR→bytecode → 2PDA execution → cell write → BSV anchor. Single test asserts cell exists with correct provenance chain. **Phase 3.**
- **D-Dform-property (cross-cutting):** Property tests derived from Lean theorems for K1, K4, K5, K7, K9. Generated property statements over `core/cell-engine/`. Per GD8 below: theorem-statement translation, not mechanized extraction. Hand-written acceptable where Lean coverage absent. **Phase 3.**
- **D-Dform-coverage:** Public-facing honest map of all substrate-paper claims × proof status (Lean theorem ✓ / property test ✓ / integration test ✓ / unproved). New `docs/PROOF-COVERAGE.md`. Replaces "correct by construction" framing per GD3 below. Depends on D-Dform-property. **Phase 3.**
- **D-W1 (A1 internal):** Multi-region supervisor in `runtime/world-beam/apps/world_host/`. Each region is independently supervised with its own tick scheduler. Test: spawn region B alongside A; ticks can diverge; entities don't cross. **Phase 4.**
- **D-W2 (A1 internal):** Cross-region two-phase commit per [docs/textbook/16-world-host-regions.md](../textbook/16-world-host-regions.md) §11. Intent issued in A → accept on B → despawn in A → spawn in B. Per-entity hash chain preserved. K4 rollback on phase failure. Depends on D-W1. **Phase 4.**
- **D-W3 (A1 internal):** Tick-decoupling test. Freeze region A's tick for 5 sec; entities in region B continue to advance their own hash chains. Anti-claim test for the "20 Hz orders everything" framing. Depends on D-W1. **Phase 4.**
- **D-C6b (U6×C):** Phase-35B `WsNodeAdapter` for cross-internet federation. Passes the D-C6c contract suite. New `runtime/session-protocol/src/adapters/ws-node-adapter.ts`. **Phase 2.**
- **D-C6c (U6×C):** NetworkAdapter contract test suite (Phase-26D). Every implementation must pass: publish-then-resolve roundtrip, idempotent publish, ordered delivery within topic, backpressure under N×fanout. Reusable across MulticastAdapter, WsNodeAdapter, InMemoryAdapter. **Phase 2.**
- **D-C6d (U6 substrate):** Peer locator service in `runtime/session-protocol/src/locator/`. Resolves peer NetworkAdapter endpoints by BRC-52 cert_id. Backed by BSV-anchored registry cell. Bootstraps `WsNodeAdapter` peer addresses. **Phase 2.**
- **D-Doc-1024:** New `docs/textbook/N-cell-alignment.md`. Single doc explaining 1024 = UDP-fragment-friendly (≤65,507 B datagram) ∧ LMDB-4KB-page = 4 cells ∧ WASM-1MB-stack = 1024 cells × 1024 B = 16 pages ∧ K5 bounded-termination unit. **No code dependencies — writable now.**
- **D-Doc-three-kernels:** New `docs/textbook/N-three-kernels.md`. Pask (constraint-graph learner) + HRR (semantic encoding) + 2PDA (deterministic execution). Distinguishes the guarantee each layer provides. **No code dependencies — writable now.**
- **D-Doc-fed:** New `docs/textbook/N-federation-transport.md`. Four-layer story: UDP multicast (Phase-35A) → WSS (Phase-35B) → NetworkAdapter interface (Phase-26D) → verb dispatch (`extensions/dispatch/`). Depends on memory `semantos_federation_transport.md` update (done 2026-05-13).
- **D-Doc-intent:** Replace [INTENT-PIPELINE.md](INTENT-PIPELINE.md) "design only" preamble with shipped status. Walks the leaky-tap example through all stages with real code refs. Depends on D-IP-e2e.
- **D-Doc-capability:** New `docs/textbook/N-capability-utxo.md`. Mint → check → revoke lifecycle. Depends on D-Dcap-engine landed.
- **D-Doc-adapters:** New `docs/ADAPTER-TAXONOMY.md`. Per-adapter status table: dispatch (✓ shipped), metering (✓ shipped), chain-broadcast (✓ shipped), world-host (DESIGN — single region), md-editor (STUB), home-ui (NOT STARTED). Honest reckoning per GD3. **No code dependencies — writable now.**
- **D-Doc-shell-cartridges-hats:** New `docs/SHELL-CARTRIDGES-HATS.md` or chapter. PWA = shell, apps = cartridges, hats = tenant contexts. References memory `shell_cartridges_hats_model.md`. **No code dependencies — writable now.**

### 11.3 Governance additions

Numbered to continue from §8 (Q1–Q5 already resolved). These are normative.

- **GD1 — TDD mandatory.** Every deliverable above (and every D-* in §5) lands a failing test commit *before* implementation. CI must show red on the failing-test commit. Reviewers reject PRs that skip the red bar. Status transitions: `✗ → RED (failing test) → ⚠ (minimum impl passes) → REFACTOR → ✓ (shipped)`. (Conversation 2026-05-13.)
- **GD2 — Property tests preferred over example tests for kernel invariants.** Where a deliverable touches K1–K14, generalize the example test to a property using fast-check or equivalent. Example tests remain in place alongside the property; they're not replaced. (Conversation 2026-05-13.)
- **GD3 — Aspirational claims are labelled "DESIGN", not buried.** If a public-facing claim isn't yet backed by code + test, the relevant doc says so. No "correct by construction" or "production-ready" framing for design-only work. (Fact-check 2026-05-13.)
- **GD4 — Memory `semantos_federation_transport.md` updated 2026-05-13** to clarify PHASE-26D = transport-agnostic NetworkAdapter interface; Phase-35A = `MulticastAdapter` (UDP multicast, local mesh default); Phase-35B = `WsNodeAdapter` (WSS for cross-internet federation, not shipped).
- **GD5 — Lower-priority gaps.** W-WORLD (multi-region) and W-MD (md editor real implementation) are post-V1. The substrate paper claims that hinge on them stay in `DESIGN` status until those deliverables land. Don't block V1 pilot on either. (Fact-check 2026-05-13.)
- **GD6 — Lean → runtime mechanized extraction is out of scope.** D-Dform-property derives runtime tests from theorem *statements*, not from extracted code. Full mechanized extraction is a future workstream noted in D-Dform-coverage. (Conversation 2026-05-13.)

### 11.4 Recommended first sprint (post-V1-pilot)

Writable-now items that establish the truthful narrative spine without blocking on code:

- D-Doc-1024 (1024-byte alignment story)
- D-Doc-three-kernels (Pask + HRR + 2PDA)
- D-Doc-adapters (honest adapter taxonomy)
- D-Doc-shell-cartridges-hats (PWA / cartridges / hats model)
- D-Doc-fed (federation transport E2E — depends on GD4 memory update, done)
- D-Dform-coverage skeleton (matrix of claims × proof status, populated as D-Dform-property lands)

Failing-test items that establish the TDD ladder for code work:

- D-Dcap-engine RED (failing test for `OP_CHECKCAPABILITY` against unspent vs spent UTXO)
- D-Dlex-voice RED (failing test for `intent.dispatch("tap is dripping", scope=apt/3a)` producing SIR declaration)
- D-C6c RED (NetworkAdapter contract test suite committed as failing across all current adapters that don't pass)
- D-Dform-property RED for K1 (linearity property test that catches any future violation)

### 11.5 Matrix delta (deferred — apply when first deliverable lands)

When the first §11 deliverable moves out of `✗`, also:
- Add row **U1 D-cap** to §2a (currently `n/a`; becomes `⚠ D-Dcap-engine` until SPV-checked UTXO lookup wires)
- Add row **A8 D-lex** to §2b (currently `✗`; becomes the home for D-Dlex-voice)
- Add row **A8 D-cap** to §2b (currently `✗`; becomes the home for D-Dcap-voice)
- Note **D-W1/W2/W3** as A1-internal milestones under A1's D-cap column

### 11.6 BRC alignment additions (BRC index sweep 2026-05-13)

A pass over the [bitcoin-sv/BRCs](https://github.com/bitcoin-sv/BRCs) index found that several §11 deliverables — and a few existing §5 cells — would be re-inventing standards that already exist. This subsection pins deliverables to BRC numbers so we get free interop and avoid divergent re-specification. **The roadmap already references BRC-32/42/52/62/69/100/103/108**; those don't change. The additions below are new bindings.

#### Deliverable bindings

| Deliverable | Bind to | What we get |
|---|---|---|
| **D-Dcap-engine (U1×D-cap)** | **BRC-108** + **BRC-115** | BRC-115 specifies a deterministic 5-stage verification pipeline (encoding → commitment → SPV → certificate → derivation match → compliance) designed for opcode-level enforcement. `OP_CHECKCAPABILITY` executes this stack. Replaces hand-rolled verification. |
| **D-C6 / D-C6b / D-C6c / D-C6d** (federation transport family) | **BRC-22, 23, 24, 87, 88, 101, 124, 82** | NetworkAdapter contract = BRC-22 (data sync) + BRC-24 (`/lookup` over `{service, query}` returning BEEF) + BRC-87 (naming) + BRC-88 (sync architecture). Multicast wire = BRC-124 (92-byte header + payload). Multicast routing = BRC-82 (IPv6 layered MLDv2/mBGP). Peer advertisement = BRC-101 (SHIP/SLAP). |
| **D-IP-e2e + D-Dlex-voice** (intent pipeline, voice surface) | **BRC-122 ARIA** | Auditable Real-time Inference Architecture. EPOCH_OPEN commits LLM model version on-chain; each NL→SIR inference hashes into a Merkle tree; EPOCH_CLOSE seals the batch. ~$2/year continuous at 1.5 s epochs. Closes the LLM-determinism / audit gap for the structured-extraction layer. |
| **Axis G (U10 + adapter D-G* cells)** | **BRC-120** primary, **BRC-105 + BRC-118** fallback | External monetization wire = BRC-120 (x402 stateless 402-gated HTTP — aligns with sovereign-node statelessness). MFP is the internal channel optimization underneath. BRC-105 (session-stateful) + BRC-118 (multipart body) available as fallback if BRC-120 ecosystem lags. Open: pick canonical. |
| **U7 (VFS)** | **BRC-26** | Universal Hash Resolution Protocol. Cell ID = SHA-256 of canonical state maps directly. VFS `runtime/shell/src/vfs/` exposes a BRC-26 endpoint for cell lookup. |
| **D-V1 (Verifier Sidecar) + axis E proof formats** | **BRC-9, 74, 95, 96, 119** | Pin versions: BRC-9 SPV semantics, BRC-74 BUMP, BRC-95 Atomic BEEF, BRC-96 BEEF V2 (txid-only extension), BRC-119 STUMP (subtree-anchored proofs, optional). The three-phase fail-fast verification I described earlier in the substrate paper pops BRC-74 then BRC-95 then envelope. |

#### Open decisions surfaced by this sweep

- **OD-BRC-1: BRC-124 payload semantics.** BRC-124's payload must be BRC-12 raw transactions, but our cells are 1024 B content-addressed objects. Either (a) wrap cells in a stub BRC-12 envelope, or (b) propose a BRC-124-extension carrying cell payloads. Lands during D-C6b.
- **OD-BRC-2: BRC-120 vs BRC-105 for axis G.** BRC-120 is stateless and aligns with sovereign-node story; BRC-105 has more ecosystem and richer header set. Pick one as canonical external interface. Lands during D-G1.
- **OD-BRC-3: BRC-101 transport for federation advertisements.** BRC-101 currently only specifies plain HTTPS; composite schemes (`wss://`, `https+bsvauth+smf://`) are aspirational. D-C6d locks to HTTPS for V1 with hook for future schemes. Lands during D-C6d.

#### Divergences worth recording (new governance)

- **GD7 — Tree-of-chains diverges from BRC-60.** §8 Q4 decided md editor uses tree-of-chains (multi-parent merge nodes). BRC-60 (Simplifying State Machine Event Chains) only specifies linear event chains with `hash(preceding event)` references — **no merge nodes.** D-E-md ships as BRC-60-compatible for linear branches + a documented extension for merges. Propose merge-node extension upstream as part of D-E-md kickoff. Don't ship a private chain format. (Conversation 2026-05-13.)
- **GD8 — BRC-108 + BRC-103 composition is unspecified upstream.** BRC-108 binds tokens to BRC-52 certificates but does **not** specify how the bind composes with BRC-103 mutual-auth challenges. Our auth model intent (memory `brain_auth_model_intent.md`, tracker T7) requires both. D-Dcap-engine + D-Dcap-voice must specify the composition explicitly: cert-id from BRC-103 handshake → token-ownership check via BRC-108 → SPV check via BRC-115 stage 3. Worth proposing upstream as a BRC-108 supplement. (Fact-check 2026-05-13.)
- **GD9 — Namespace partition cross-check pending.** §8 Q2 codified our uint32 partition in `core/protocol-types/src/namespace.ts`. **BRC-43** (Security Levels, Protocol IDs, Key IDs, Counterparties) and **BRC-123** (Basket Identifier Namespace Framework) may already provide a compatible partition. Pre-implementation audit required: align or document intentional divergence. Not a new deliverable; a constraint on the next change to `namespace.ts`. (BRC sweep 2026-05-13.)

#### Tier 3 — worth tracking, not blocking

These don't block any current deliverable but inform future work. Don't bind without a concrete reason.

| BRC | Why it might matter later |
|---|---|
| BRC-35 (Layered KV Store for Overlays) | Possible reference architecture for VFS storage layer below the cell engine |
| BRC-46 / 65 / 99 / 111 / 114 (Baskets, labels, P-baskets, time-labels) | Shell-cartridges-hats integration — wallet metadata permission framework |
| BRC-116 (Wallet Permissions and Counterparty Trust) | D-Dcap-helm + hats permission model |
| BRC-102 (deployment-info.json) | D-Doc-adapters cartridge manifest format |
| BRC-53 (Certificate Creation and Revelation) | Cert lifecycle complement to BRC-52 |
| BRC-63 / 68 / 85 (Genealogical identity, DNS anchors, PIKE) | A-axis depth — identity derivation tree and trust anchor publication |
| BRC-77 / 78 (Message signature, portable encrypted messages) | Possible internals for `SignedBundle` envelope |
| BRC-45 / 113 / 117 (UTXOs-as-tokens, proof-backed tokens) | Foundational token-spec depth for D-Dcap |
| BRC-76 (Graph Aware Sync Protocol) | Possible reference for D-C6c contract suite — audit during D-C6c RED |
| BRC-81 (Private Overlays with P2PKH) | Relevant if D-C6 ever needs per-tenant overlay isolation |
| BRC-31 (Authrite Mutual Auth) | Predecessor to BRC-103 — only matters if migration code exists |

#### Tier 4 — explicit non-binds (decided this sweep)

- **BRC-92, BRC-107 (Mandala Token Protocols)** — BRC-108 builds on these but we use BRC-108/115 directly; don't reference the older Mandala specs.
- **BRC-109 (PCW-1 Peer Cash Wallet)** — alternative wallet protocol; not aligned with our W2A model (BRC-100).
- **BRC-1–7 basic wallet ops** — covered by BRC-100; don't reference individually.
- **BRC-13, 17–19, 21 basic script templates** — too low-level; no unification-axis bearing.
- **BRC-49, 51, 57, 80, 89–91, 110 (opinions)** — not normative.

---

### 11.7 Lean + TLA+ both-sides coverage plan (proof-engineering sweep 2026-05-13)

Per the directive "Lean for everything possible, TLA+ to cover from both sides if possible." Audit of `proofs/lean/Semantos/` + `proofs/tla/` reveals current state is **better than `docs/PROOF-COVERAGE.md` first iteration claimed**: 14 K-invariants have Lean theorems (after K6 landed `6e35346` on 2026-05-13), and 14 TLA+ specs already exist. The remaining gap is mapping TLA+ specs to K-invariants and adding missing TLA+ coverage on the high-leverage invariants.

#### 11.7.1 Current coverage matrix (verified 2026-05-13)

| K | Statement | Lean | TLA+ | Status |
|---|---|---|---|---|
| K1 | Linearity | `LinearityK1.lean` | `Linearity.tla` (2026-05-13) | **both sides ✓** (newly closed) |
| K2 | Authorization soundness | `AuthSoundnessK2.lean` | `ReplayPrevention.tla` (partial); `CertRevocation.tla` (partial) | both sides (partial TLA+) |
| K3 | Domain isolation | `DomainIsolationK3.lean` | `ZoneBoundary.tla`, `SemanticTypes.tla` | **both sides ✓** |
| K4 | Failure atomicity | `FailureAtomicK4.lean` | `FailureAtomicity.tla` (2026-05-13) | **both sides ✓** (newly closed) |
| K5 | Deterministic termination | `TerminationK5.lean` | — | Lean only (TLA+ adds little — bounded by construction) |
| K6 | Hash-chain integrity | `HashChainIntegrityK6.lean` (2026-05-13) | `EvidenceChain.tla` | **both sides ✓** (newly closed) |
| K7 | Cell immutability | `CellImmutabilityK7.lean` | `CellImmutability.tla` (2026-05-13) | **both sides ✓** (newly closed) |
| K8 | Demotion safety | `DemotionK8.lean` | `DemotionSafety.tla` | **both sides ✓** |
| K9 | Temporal morphism | `TemporalMorphismK9.lean` | `TransactionDAG.tla` | **both sides ✓** |
| K10 | Non-Turing-completeness | `TuringCompletenessK10.lean` | n/a | Lean-only by nature (negative property over instruction set) |
| K11 | Sign soundness | `SignSoundnessK11.lean` | n/a | Lean-only (TLA+ can't model SHA/ECDSA) |
| K12 | Key custody | `KeyCustodyK12.lean` | `KeyCustody.tla`, `TierEscalation.tla` | **both sides ✓** |
| K13 | Budget monotonicity | `BudgetMonotonicityK13.lean` | `MeteringFSM.tla` | **both sides ✓** |
| K14 | Vault multisig | `VaultMultisigK14.lean` | `VaultCooldownNsequence.tla` | **both sides ✓** |

**Current state: 13 of 18 K-invariants have both-sides coverage** (10 base + 3 proposed):
- Base K1, K3, K4, K6, K7, K8, K9, K12, K13, K14 — both sides
- K10, K11 — inherently Lean-only (negative property; crypto axioms)
- K5 — intentional Lean-only (bounded by construction)
- K2 — partial TLA+ coverage via `ReplayPrevention` + `CertRevocation`
- **NEW 2026-05-13 (forward-looking):** K15 (`CapabilityUtxoK15.lean` + `CapabilityRace.tla`), K17 (`TreeOfChainsK17.lean` + `TreeOfChainsMerge.tla`), K18 (`FederationPropagationK18.lean` + `FederationPropagation.tla`)
- **K16 input-mode equivalence:** genuinely gated on D-Dlex-voice — needs SIR runtime to formalize against

**Phase P1 complete** 2026-05-13: K1 (`Linearity.tla`), K4 (`FailureAtomicity.tla`), K7 (`CellImmutability.tla`).
**Phase P3 partial:** 3 of 4 proposed K-invariants (K15, K17, K18) shipped forward-looking; K16 truly gated.

#### 11.7.2 Proposed new K-invariants from §11.2 — both-sides target

| K | Statement | Lean | TLA+ | Strategy |
|---|---|---|---|---|
| K15 | Capability-UTXO binding | `CapabilityUtxoK15.lean` (2026-05-13) | `CapabilityRace.tla` (2026-05-13) | **both sides ✓ (NEW)** — forward-looking spec; D-Dcap-engine implementation must conform |
| K16 | Input-mode equivalence | — | — | Lean primary (deterministic lowering); TLA+ if surface concurrency surfaces in practice |
| K17 | Tree-of-chains merge | `TreeOfChainsK17.lean` (2026-05-13) | `TreeOfChainsMerge.tla` (2026-05-13) | **both sides ✓ (NEW)** — forward-looking; D-E-md implementation must conform |
| K18 | Federation propagation independence | `FederationPropagationK18.lean` (2026-05-13) | `FederationPropagation.tla` (2026-05-13) | **both sides ✓ (NEW)** — algebraic core (Lean) + distributed-protocol traces (TLA+); anti-claim test for "20 Hz orders all cells" |

#### 11.7.3 Standalone TLA+ specs not yet K-mapped

These 5 TLA+ specs ship today but aren't bound to a numbered K-invariant. They cover real properties; either map to existing/new K's or document their independent role:

| TLA+ spec | Likely K mapping | Action |
|---|---|---|
| `ReplayPrevention.tla` | K2 (supplement) or new K | Document supplemental role under K2, OR propose K19 (replay protection) |
| `CertRevocation.tla` | K2 (supplement) | Document under K2 — cert lifecycle is part of authorization soundness |
| `PartitionResilience.tla` | K18 (proposed) | Adopt as the TLA+ side of K18 when authored |
| `ReactorIsolation.tla` | K3 (supplement) | Document under K3 — runtime-level domain isolation |
| `RecoveryFlow.tla` | n/a (axis F, not a K) | Document as axis-F (recovery) coverage, not a K-invariant |

#### 11.7.4 Work plan

**Phase P1 — close the easy TLA+ gaps (highest leverage):**

- **D-Proof-1: TLA+ for K1 (Linearity)** — `proofs/tla/Linearity.tla`. Model: cells with linearity class transitions over a multi-step trace; invariant = no LINEAR cell appears twice on stacks. Bounded model-check catches consume/produce-sequence bugs the Lean proof can't reach.
- **D-Proof-2: TLA+ for K4 (Failure atomicity)** — `proofs/tla/FailureAtomicity.tla`. Model: PDA state pre/post failed opcode across all 16 Plexus opcodes; invariant = state byte-identical on every failure path. Complements the existing `plexus_atomic_fuzz.zig` empirical coverage with state-space exhaustion.
- **D-Proof-3: TLA+ for K7 (Cell immutability)** — `proofs/tla/CellImmutability.tla`. Model: cell header bytes across all opcode applications; invariant = header unchanged. Catches "opcode accidentally mutates header" bugs that fuzz alone may miss.

**Phase P2 — map standalone TLA+ specs to K's:**

- **D-Proof-4: Document `ReplayPrevention.tla` and `CertRevocation.tla` as K2 supplements** in `docs/PROOF-COVERAGE.md`
- **D-Proof-5: Document `ReactorIsolation.tla` as K3 supplement**
- **D-Proof-6: Promote `PartitionResilience.tla` to K18 TLA+ side** when K18 lands

**Phase P3 — author new K-invariants in both formalisms:**

- **D-Proof-7: K15 (Capability-UTXO binding)** — Lean + TLA+. Depends on D-Dcap-engine landing first (need the verification path to formalize).
- **D-Proof-8: K16 (Input-mode equivalence)** — Lean primary. Depends on D-Dlex-voice + D-IP-equiv.
- **D-Proof-9: K17 (Tree-of-chains merge)** — TLA+ primary + Lean for merge algebra. Depends on D-E-md.
- **D-Proof-10: K18 (Federation propagation)** — TLA+ primary (adopt PartitionResilience.tla) + Lean for cell-algebra. Depends on D-C6c + D-W3.

**Phase P4 — CI integration:**

- **D-Proof-11: Wire `lake build Semantos` + `tlc` into CI**. Make Lean / TLA+ divergence (Lean says yes, TLA+ finds counterexample) a build break. Establishes both-sides as a hard contract, not a manual discipline.

#### 11.7.5 Out of scope (per existing GD)

- **Mechanized extraction from Lean to running code** — explicitly out of scope per GD6.
- **TLA+ proofs of crypto primitives (SHA, ECDSA)** — TLA+ can't reason about them; they stay axiomatic in `CryptoAxioms.lean`.
- **TLA+ for K10 (Non-Turing-completeness)** — instruction-set enumeration is symbolic; TLA+ doesn't add.

#### 11.7.6 Estimated effort and order

Realistic phasing for a focused proof-engineering sprint:

| Phase | Effort | Output |
|---|---|---|
| P1 (TLA+ K1/K4/K7) | ~1 week each, parallelizable | 3 new TLA+ specs; coverage doc updated |
| P2 (standalone-spec mapping) | ~2 days | PROOF-COVERAGE.md updates |
| P3 (new K-invariants) | gated on §11.2 code deliverables landing | 4 new theorems (Lean + TLA+ each) |
| P4 (CI integration) | ~1 week | `lake build` + `tlc` gating PR merges |

Total: ~6-8 weeks of focused proof-engineering work to reach "both sides on everything possible" for the current 14 K-invariants and 4 proposed new ones.

#### 11.7.7 Governance addition

- **GD10 — Both-sides coverage is the proof-engineering target.** New K-invariants ship with both Lean and TLA+ unless one side is inherently inapplicable (K10/K11-style). Existing K-invariants get TLA+ retrofits per phases P1-P3. Standalone TLA+ specs without a K-binding either get mapped to a K or moved out of the K-invariant table (axis-F specs stay in axis-F coverage).

---

### 11.8 Customer-conversations workstream (2026-05-14)

Adapter slice on the **oddjobz** extension (A4-adjacent — operator-to-customer messaging, NOT in the original 10-surface matrix). Adds two new HTTP endpoints on the brain + a PWA UI for operator-initiated SMS dispatch via Twilio.

**New surface entries (status — refs):**

| Deliverable | Axis bindings | Status | Refs |
|---|---|---|---|
| **D-OJC1-twilio-adapter** | A4 × C × G (transport) | ✓ shipped | `runtime/semantos-brain/src/twilio_adapter.zig` — formatE164 + sendSms (injectable HTTP sender) + parseConfig/loadConfig. 28 inline tests. |
| **D-OJC2-conv-send-endpoint** | A4 × D-cap | ⚠ partial | `POST /api/v1/conversation/<id>/send` — wire surface live; persist_message stays no-op (Twilio sid is receipt). Lookup_contact backed by customers_store.findById (conversation_id = customer_id). 13 orchestration tests. |
| **D-OJC3-search-endpoint** | A4 × D-form | ✓ shipped | `POST /api/v1/search/contacts` — name + suburb/full-address substring; deduped by customer.id; name-first ordering. 7 pure-logic tests + 7 orchestration tests. |
| **D-OJC4-pwa-flow** | A4 × U1 | ✓ shipped | home→job→contact-tile→ContactConversationScreen (W5) AND Talk\|Direct→search→tap→same screen (W6). Dio-backed `ConversationSendApi` + `SearchContactsApi`. |
| **D-OJC5-pre-flight-smoke** | A4 × U2 (testing) | ✓ shipped | `scripts/conv-send-smoke.sh` — curl-based 4-test wire smoke (bearer-missing 401 ×2 + bearer-bogus 404/503 + bearer-valid-query 200). |

**Deferred follow-ups (debt register):**

- **D-OJC2.followup-persist** — brain-side cell-write or audit-log line for outbound SMS (`persist_message` is currently no-op). Twilio sid covers external receipt but local audit + message-history-list UI both depend on this landing.
- **D-OJC2.followup-history** — Flutter message-history list in `ContactConversationScreen` (placeholder text today). Gated on persist + a brain-side `oddjobz.message.list` verb.
- **D-OJC2.followup-callsites** — thread `conversationSendApi` + `talkSurface` through the seven other JobDetailScreen call sites (calendar / attention feed / attention screen / site / customer / find / job-list). Currently only the home→tap path is fully wired.
- **D-OJC2.followup-verify** — customer-side Twilio Verify loop (the chat-widget intake path). Yesterday's design §3.5 — deferred for this loop; conversation_send is operator-initiated only.
- **D-OJC3.followup-job-context** — search currently returns `{id, display_name, phone, siteRef}`. Per Todd's verbatim "matching jobs surface with their contact names" the response should also include the linked job(s) per contact. Trivial server-side, UI placeholder ready.

**Process notes:**

- All work followed GD1 TDD ladder (RED commits visible in git log: `f974f68` `43f9359` `747b716` `906abe6`).
- Parallel-session fast-forward of feat/customer-conversations → main mid-loop handled via revised loop-doc constraint + memory `loops_branch_flexibility.md`.
- 28 path-scoped commits `67cb11f → 441e5a7` on main; full ledger in `docs/design/CUSTOMER-CONV-LOOP-PLAN.md` retrospective.

### 11.9 Typed-NL intent pipeline progress (2026-05-14)

**D-Dlex-voice (§11.2) transitioned ✗ → ⚠ in parallel session.** The "NL → SIR extractor with LLM-assisted refinement" deliverable is now partially implemented: an Anthropic-Claude-backed L1 extractor + intent inspector that visualises the pipeline end-to-end. Determinism property (same NL + scope + lexicon ⇒ same SIR) is NOT yet asserted via property test — that gate is still open.

**Landed (origin/main, 2026-05-14):**

| SHA | What |
|---|---|
| `fb8fddd` | feat(pwa): live-elapsed inspector + Anthropic L1 extractor backend |
| `6e20a0c` | fix(pwa): bake Intent schema into the extractor prompt |
| `d95f329` | fix(pwa): surface stack frames on pipeline_threw rejections |
| `b48e96f` | fix(pwa): defensive constraint lowering + tell Claude to leave constraints empty |
| `febabc3` | fix(pwa): emit no opcodes for logical_and/or with <2 operands |
| `5d55e58` | fix(pwa): substitute capability(0) for empty constraints |
| `4100ba8` | fix(pwa): skip outer logical_and when constraint side is empty |
| `e87bf37` | fix(pwa): emit OP_1 for vacuous scripts (substrate gap workaround) |
| `992a395` | feat(pwa): inspector surfaces TextIntentService short-circuits |

**Debt flagged for the lower SIR→OIR→bytecode path (per memory `no_hardcoded_workarounds.md`):**

The last four `fix(pwa)` commits are explicit substrate-gap workarounds. Each papers over a missing OIR primitive or kernel-side semantic; tagging here so the underlying gaps don't ossify:

- **D-IP-gap-vacuous-script (febabc3 + 5d55e58 + 4100ba8 + e87bf37):** the OIR lowering can produce empty `logical_and`/`logical_or` operand lists when Claude generates an Intent with `constraints: []`. Today the PWA emits `OP_1` (vacuous true) or skips the operator entirely to keep the kernel happy. Real fix is either (a) OIR rejects vacuous logical operators at lowering, with a typed error surfaced through the inspector, or (b) kernel-side accepts `(logical_and)` → true by convention. Pick one, codify in the IR spec, retire the workaround.
- **D-IP-gap-constraint-kind (b48e96f):** Claude emits constraints without a `kind` field; sir_to_oir crashes the null-cast. Defensive skip is in; canonical fix is either prompt-tightening to a stricter constraint schema (preferred per `no_hardcoded_workarounds`) OR a schema validator at the SIR boundary that rejects malformed constraints BEFORE lowering. Currently both are absent.

**Determinism gate still open:**

D-IP-equiv (§11.2) — "all five input modes lower to identical SIR for semantically equivalent intent" — was a Phase-3 deliverable that anchors the determinism property. With Claude now in the loop as a non-deterministic L1 extractor, the property test needs an explicit definition of what "same NL" means when Claude is the lowerer. Options being deferred:
1. Seed the Anthropic API call with a fixed value (Anthropic doesn't expose this today)
2. Cache by NL+scope+lexicon hash and replay (deterministic-modulo-cache)
3. Restrict the property test to the deterministic feature-extraction path; treat LLM-assisted refinement as best-effort with no determinism claim
Decision blocked on (a) whether Anthropic's API gains seeding and (b) Todd's call on which behaviour is canonical.

**Matrix delta — apply when D-Dlex-voice transitions ⚠ → ✓:**
- Update §2b A8 row: `D-lex: ✗` → `D-lex: ⚠ D-Dlex-voice (partial: Claude-backed L1; deterministic feature-extraction path TBD)`.
- Once determinism gate closes, → `✓`.

---

### 11.10 Kernel-enforcement program sequencing (2026-05-25, reframed twice)

**Status reconciliation 2026-05-25 (tick 6.5):** the autonomous loop landed Gap A + orders 2b/2c/2d in PRs #637/#639/#640/#641 (Zig PolicyRuntime seam + intent_cells_handler + cell_handler opt-in). Then ground-state verification for orders 3 and 4 revealed BOTH carves are already substantially done — same pattern as tick 2's PHASE-29.5 reconciliation:
- `cartridges/bsv-anchor-bundle/brain/zig/` has wallet_op_http, output_store_fs, wss_wallet, headers_http, payment_verifier, header_store_fs, refund_tx, reorg_sink (D-LIFT-BSV-ANCHOR ~90%)
- `cartridges/oddjobz/brain/zig/src/` has all stores, FSMs, handlers, intent_action_router (D-LIFT-ODDJOBZ ~95%; only `runtime/semantos-brain/src/repl/oddjobz_cmds.zig` remains)
- `cartridges/wallet-headers/brain/` (TS, Bun-based) has SPV verifier + wallet ops + cell-anchor tests + setup-wizard
- `core/protocol-types/src/anchor.ts` ships the AnchorAdapter interface; `core/anchor-attestation/` ships AnchorAttestation cell minting

**Per Todd 2026-05-25 (response to tick 6 pause):** no production callers — free to change wire shapes. New explicit directive: **brain emits an on-chain tx for every cell write** (LINEAR + AFFINE at minimum; "easier to just do it for all"). This becomes order 3a below. DECISION-PENDINGs in D-LIFT-BSV-ANCHOR.md resolved: PENDING-1 = `cartridges/` location (already done); PENDING-2 = recommendation (c) mark-as-unverified-until-backend-loads.

**Status reconciliation 2026-05-25 (tick 2 of autonomous loop):** v0.10 §11.10 named PHASE-29.5 as the keystone. Ground-state verification found `packages/policy-runtime/` already exists (`PolicyRuntime`, `PolicyContext` / `PolicyResult` / `HostCallRecord`, `anchor-emitter`, `authority` verifier) and is consumed by `packages/cdm/cdm/src/lifecycle/policy-gate.ts` + `packages/scada/scada/demo-kernel.ts`. Phase 29.5's TS-side substrate shipped at some prior point. **Per Todd 2026-05-25: CDM and SCADA were prototypes exploring extension-grammar shape, NOT load-bearing for the product.** The real enforcement target is the brain's Zig write path, which today still uses `runtime/semantos-brain/src/kernel_zig.zig`'s syntactic shim — not 2-PDA execution. The Zig-side gap matches the same three Phase 29.5 gaps but at the substrate boundary that actually serves Bridget's "what goes on chain when" question.

The program below is the reframed sequence. PHASE-29.5 PRD is kept as the **design reference** for what a kernel-enforcement substrate looks like — its three-gap framing remains the right mental model. The implementation site moves from TS packages to Zig brain modules.

| Order | Site | Closes | Output | Status |
|---|---|---|---|---|
| 0 (prelude) | Gap A | Cert+hat as brain primitive | `identity_certs.verifyCertHatBinding` | ✓ shipped ([PR #637](https://github.com/semantos/semantos-core/pull/637)) |
| 1 | [BRAIN-DISPATCHER-UNIFICATION.md](../design/BRAIN-DISPATCHER-UNIFICATION.md) Phase 0 → Phase 1 | one-write-path seam | `dispatcher.zig` + per-resource migration | Phase 0 ✓; Phase 1 incremental |
| 2a (TS reference) | PHASE-29.5 substrate | TS-side Gaps 1+2+3 | `packages/policy-runtime/` + CDM/SCADA wired | ✓ shipped (prototype reference; NOT load-bearing) |
| 2b (Zig keystone) | `runtime/semantos-brain/src/policy_runtime.zig` | Zig-side Gaps 1+2 in brain's write path | `PolicyRuntime.evaluate(policy_bytes, context) → PolicyResult` mirroring TS shape; backend = `kernel_zig` syntactic shim first | ✓ shipped ([PR #639](https://github.com/semantos/semantos-core/pull/639)) |
| 2c | intent_cells_handler refactor | oddjobz routes through Zig PolicyRuntime | Step 6 calls `PolicyRuntime.evaluate` | ✓ shipped ([PR #640](https://github.com/semantos/semantos-core/pull/640)) |
| 2d | `cell_handler.zig` PolicyRuntime integration | generic `cell.create` routes through Zig PolicyRuntime when payload carries opcode bytes | Optional `opcode_bytes_b64` opt-in | ✓ shipped ([PR #641](https://github.com/semantos/semantos-core/pull/641)) |
| 2e (DEFERRED) | Real `executor.zig` wiring | Layer 2 K1 / K3 / type-hash enforcement for real | 14-module `core/cell-engine/` pull-in per [`kernel_zig.zig:17`](../../runtime/semantos-brain/src/kernel_zig.zig) — backend swap inside `PolicyRuntime` | ✗ deferred (large, separate program). **Pre-flight audit pending — see task #18** |
| 3 | [D-LIFT-BSV-ANCHOR.md](D-LIFT-BSV-ANCHOR.md) | Cartridge carve of wallet/headers/payment/anchor | `cartridges/bsv-anchor-bundle/brain/zig/` + `cartridges/wallet-headers/brain/` | ~90% ✓ — files already lifted out of brain-core. Remaining: docs reconciliation. DECISION-PENDING-1 RESOLVED (`cartridges/` per CC4); DECISION-PENDING-2 RESOLVED (recommendation c) |
| **3a (NEW)** | Brain anchor-every-cell wiring | Layer 3 of Bridget's table — every cell write emits an on-chain tx | `runtime/semantos-brain/src/anchor_emitter.zig` (mirrors PolicyRuntime pattern) called after every `cell_store.put` / `store.create`; bridges to `cartridges/wallet-headers/` for the real tx broadcast | ✗ to build (THIS reframe's new keystone). Per Todd 2026-05-25: anchor everything (simpler than filtering LINEAR/AFFINE) |
| 4 | [D-LIFT-ODDJOBZ.md](D-LIFT-ODDJOBZ.md) | Cartridge-shaped code in brain-core | oddjobz Zig half → `cartridges/oddjobz/brain/zig/src/` | ~95% ✓ — all stores/FSMs/handlers/intent_action_router lifted. Remaining: relocate `runtime/semantos-brain/src/repl/oddjobz_cmds.zig`; decide whether `intent_cells_handler.zig` is cartridge-specific or shared infra |

**Sequencing notes (reframed twice):**
- Orders 0/2b/2c/2d ✓ shipped. The PolicyRuntime structural seam exists in the brain and both cartridge handlers call through it. Backend = syntactic shim; real-executor swap (2e) is a backend-only change.
- Order 3 is ~90% done (cartridges shipped); just needs the docs reconciled. DECISION-PENDINGs resolved.
- **Order 3a is now the critical path.** This is Layer 3 of Bridget's table — anchor every cell on chain. The cartridges that DO the anchoring exist (wallet-headers TS cartridge, bsv-anchor-bundle Zig cartridge); the brain just doesn't call into them on cell write. Subtasks: (i) `anchor_emitter.zig` brain primitive mirroring PolicyRuntime; (ii) wire into `cell_handler` + `intent_cells_handler` + store layers; (iii) real backend bridge to wallet cartridge.
- Order 4 is ~95% done; one file (`oddjobz_cmds.zig`) + one decision (intent_cells_handler placement) remain.
- Order 2e (real executor wiring) — pre-flight audit task #18 inventories the 14-module dep chain + build-graph cost before committing.

**Order 3a architecture sketch (proposed; can be revised in implementation):**

Pattern mirrors PolicyRuntime: brain primitive (`anchor_emitter.zig`) with stub backend first, real backend later. Differs from PolicyRuntime in one key way — anchoring is OUT-OF-PROCESS (the wallet lives in a TS cartridge), so the brain primitive's "real" backend is a bridge across the language boundary.

Three viable bridge shapes:
1. **Event-bus async** (recommended): brain emits `cell.created` on `helm_event_broker` after every `cell_store.put`. Wallet cartridge subscribes; mints an `AnchorAttestation` cell via `@semantos/anchor-attestation`; broadcasts the BSV tx via the `AnchorAdapter` interface; persists the attestation cell back through `cell.create`. Anchoring is eventually-consistent — cell writes don't block on tx confirmation.
2. **Synchronous HTTP** to wallet cartridge — brain blocks until txid returned. Slow; bad for write throughput.
3. **In-process Zig FFI** — brain links the lifted Zig wallet code directly. Tight coupling against the cartridge boundary the lift just established.

**Recommendation: (1) async.** Honors the cartridge boundary, scales, fits the existing `helm_event_broker` pattern, and matches D-LIFT-BSV-ANCHOR PENDING-2 resolution (mark cells anchor-pending until backend confirms). Anchor cells DON'T re-anchor (entity_tag check in `anchor_emitter` to break the recursive loop).

Per Todd 2026-05-25: no production callers; this can be changed if the implementation surfaces problems.

**Matrix delta (apply incrementally as each order lands):**
- §2a U1 row D-cap: `n/a` → `⚠ D-Dcap-engine` (current — seam exists, enforcement syntactic-only); → `✓` after 2e (real K1/K3 enforcement via executor).
- §2b cartridge rows (A9 Jam Room, A11 Tessera, future oddjobz row): D-cap and D-sub cells move ⚠ → ✓ once the cartridge calls through Zig `PolicyRuntime`.
- §11.1 G1 row "Closed by" column: D-Dcap-engine ID unchanged; the IMPLEMENTATION vehicle is the 2b/c/d/e sequence above. PHASE-29.5 stays a design reference, not the vehicle.
- After 3a lands: §2a U2/U4 axis-G rows (already ✓ at the Plexus layer) gain a brain-side note that anchoring is wired in the substrate write path.

**Why this subsection exists (revised):** Bridget Doran's 2026-05-25 question was informational — she was understanding the brain↔kernel relationship and what goes on chain. Her conclusion was correct: the brain's generic `cell.create` path doesn't touch the kernel; oddjobz's `intent_cells.submit` has a syntactic shim only; BSV anchoring isn't wired in the brain. She wasn't blocked — Traceport would cover any on-chain need she had today (she has none). The §11.10 reframe makes the implementation path legible so the next contributor doesn't re-discover that the TS PolicyRuntime exists but isn't where the brain's write-path gap closes.

---

## Changelog

- **v0.12** (2026-05-25) — §11.10 reconciliation tick 6.5. Marks orders 0/2b/2c/2d ✓ shipped (PRs #637/#639/#640/#641). Discovers D-LIFT-BSV-ANCHOR ~90% done (cartridges/bsv-anchor-bundle/brain/zig/ + cartridges/wallet-headers/brain/ both exist) and D-LIFT-ODDJOBZ ~95% done (all stores/FSMs/handlers/intent_action_router at cartridges/oddjobz/brain/zig/src/) — PRDs were stale, same pattern as the tick-2 PHASE-29.5 discovery. Resolves D-LIFT-BSV-ANCHOR DECISION-PENDING-1 (`cartridges/` per CC4) and PENDING-2 (recommendation c: mark-as-unverified-until-backend-loads). **Adds NEW order 3a: anchor every cell on write** — per Todd 2026-05-25 directive. Architecture sketch: brain `anchor_emitter.zig` (mirrors PolicyRuntime pattern) → event-bus async to `cartridges/wallet-headers` → AnchorAttestation cell minted + BSV tx broadcast → attestation persisted (recursion broken by entity_tag check). Anchor cells DON'T re-anchor. Names #18 pre-flight audit task for the deferred order 2e real-executor wiring.
- **v0.11** (2026-05-25) — §11.10 reframed after tick-2 ground-state verification revealed `packages/policy-runtime/` + CDM/SCADA already shipped (TS prototype). Per Todd: CDM/SCADA are prototypes exploring shape, not load-bearing; the real target is the brain's Zig write path. Reframed program orders the Zig PolicyRuntime seam (NEW order 2b, mirrors TS shape for cross-substrate consistency), `intent_cells_handler` + `cell_handler` refactors (2c/2d), and real `executor.zig` pull-in (2e — deferred per `kernel_zig.zig:17` 14-module dep, but explicitly NOT a prerequisite for 2b/c/d). PHASE-29.5 PRD kept as design reference with in-band status reconciliation note added. Gap A ✓ shipped earlier 2026-05-25 (PR #637). Companion edits to PHASE-29.5 + D-LIFT-ODDJOBZ + D-LIFT-BSV-ANCHOR updated to point at the Zig PolicyRuntime analogue.
- **v0.10** (2026-05-25) — Added §11.10 kernel-enforcement program sequencing. Cross-links BRAIN-DISPATCHER-UNIFICATION + PHASE-29.5 + D-LIFT-BSV-ANCHOR + D-LIFT-ODDJOBZ as one program closing §11.1 G1 (D-Dcap-engine) and the "layers 2 and 3 unwired" picture surfaced by external review (Bridget Doran). Names Gap A prelude (extract `verifyCertHatBinding` from `intent_cells_handler.zig` into `identity_certs.zig` as a brain primitive). Companion edits to the three PRDs add "Related sweep" cross-references threading the program together. **Superseded by v0.11 reframe.**
- **v0.9** (2026-05-14) — **Added §11.8 customer-conversations workstream + §11.9 typed-NL intent pipeline progress.** §11.8: 5 new oddjobz-customer-comms deliverables (D-OJC1-twilio-adapter ✓, D-OJC2-conv-send-endpoint ⚠ partial, D-OJC3-search-endpoint ✓, D-OJC4-pwa-flow ✓, D-OJC5-pre-flight-smoke ✓). 28 commits `67cb11f → 441e5a7` on main; full ledger in `docs/design/CUSTOMER-CONV-LOOP-PLAN.md`. Five debt entries (persist / history / 7 other JobDetailScreen call sites / customer-side Twilio Verify / search-job-context) named. §11.9: **D-Dlex-voice transitioned ✗ → ⚠** with Anthropic-Claude L1 extractor + live intent inspector (commits `fb8fddd → 992a395`). Two D-IP-gap-* debt entries named for the four `fix(pwa)` substrate-gap workaround commits (vacuous-script + constraint-kind), per `no_hardcoded_workarounds` memory. Determinism gate (D-IP-equiv) explicitly still open — three resolution options listed, blocked on Anthropic API seeding + Todd's canonical-behaviour call.
- **v0.8** (2026-05-13, late evening) — **Phase P3 partial: K15 + K17 + K18 forward-looking both-sides specs shipped.** K15 (capability-UTXO binding): `CapabilityUtxoK15.lean` (5 sub-theorems proven) + `CapabilityRace.tla` (56 distinct states, no-double-spend invariant). K17 (tree-of-chains merge): `TreeOfChainsK17.lean` (3 tampering-detection lemmas — composite deferred) + `TreeOfChainsMerge.tla` (1465 distinct states). K18 (federation propagation independence): `FederationPropagationK18.lean` (algebraic core: advance/tipHash independent of tick state) + `FederationPropagation.tla` (1024 distinct states, anti-claim for "20 Hz orders all cells"). All Lean modules verified via `lake build Semantos`. All TLA+ specs added to Makefile SPECS list — flow through CI via gate.yml. **Both-sides coverage 10/14 → 13/18** in one session. K16 (input-mode equivalence) genuinely gated on D-Dlex-voice — needs SIR runtime to formalize against.
- **v0.7** (2026-05-13, evening) — **Phases P1 + P2 of §11.7 complete.** K6 Lean theorem landed (`6e35346` — `HashChainIntegrityK6.lean`, lake build green, zero `sorry`). Three TLA+ specs added closing the high-leverage TLA+ gaps: `Linearity.tla` (K1, 54 distinct states), `FailureAtomicity.tla` (K4, 106 distinct states), `CellImmutability.tla` (K7, 8073 distinct states) — all TLC-green. Existing standalone TLA+ specs (`ReplayPrevention`, `CertRevocation`, `ReactorIsolation`, `SemanticTypes`) mapped to K-supplements in `docs/PROOF-COVERAGE.md` (D-Proof-4/5). **Both-sides coverage 7 → 10 of 14 K-invariants in one session.** Phase P4 (CI integration) already in `.github/workflows/gate.yml` — `lake build` + `make check` + no-sorry + no-vacuous-models checks run on every push; new specs flow through automatically. Phase P3 (K15-K18 new invariants) remains gated on §11.2 code deliverables landing.
- **v0.6** (2026-05-13) — Added §11.7 Lean + TLA+ both-sides coverage plan. Audit findings: 14 of 14 K-invariants now have Lean theorems (K6 landed `6e35346` closing the one acknowledged gap); 14 TLA+ specs ship today covering 5 K-invariants explicitly (K3, K8, K9, K12, K13, K14) plus K6 via EvidenceChain.tla. **7 of 14 K-invariants have full both-sides coverage.** Genuine TLA+ gaps named: K1, K4, K7 (P1 work plan). 11 new D-Proof-* deliverables across 4 phases (P1 close easy TLA+ gaps; P2 map standalone specs; P3 new K-invariants K15-K18; P4 lake+tlc CI integration). GD10 added — both-sides is the proof-engineering target.
- **v0.5** (2026-05-13) — Added §11.6 BRC alignment additions after sweeping the [bitcoin-sv/BRCs](https://github.com/bitcoin-sv/BRCs) index. Six deliverable bindings (D-Dcap-engine → BRC-108+115; D-C6 family → BRC-22/23/24/82/87/88/101/124; D-IP-e2e + D-Dlex-voice → BRC-122 ARIA; axis G → BRC-120 primary / BRC-105+118 fallback; U7 VFS → BRC-26; D-V1 + axis E → BRC-9/74/95/96/119). Three open decisions (BRC-124 payload wrapping; BRC-120 vs BRC-105 canonical; BRC-101 transport scheme). Three new governance items: GD7 tree-of-chains diverges from BRC-60 (propose merge extension upstream); GD8 BRC-108 + BRC-103 composition unspecified upstream (specify in D-Dcap-engine); GD9 namespace partition cross-check vs BRC-43/BRC-123 pending.
- **v0.4** (2026-05-13) — Added §11 Truth-alignment supplement folding `docs/GAP-CLOSURE-ROADMAP.md` (now deleted). 18 new deliverables across capability/UTXO binding, intent pipeline, federation transport, multi-region, property tests, and documentation. Six governance decisions added: GD1 TDD mandatory, GD2 property tests preferred, GD3 aspirational claims labelled DESIGN, GD4 federation transport memory updated, GD5 W-WORLD and W-MD post-V1, GD6 Lean extraction out of scope. §10 updated to reference TDD ladder.
- **v0.3** (2026-04-26) — Resolved §8 governance questions: world-host gets `0x0B EXPERIENCE`; namespace partition codified in `core/protocol-types/src/namespace.ts`; Verifier Sidecar default = per-node process; md editor branching = tree-of-chains; calendar recurring rules = chain-forks. Cross-referenced `docs/spec/protocol-v0.5.md` (cut this session, absorbing Plexus Tech v1.3 §4) and `docs/canon/glossary.yml` (canonical-decision pass complete this session, 51/51 entries).
- **v0.2** — Restructured matrix into substrate vs adapter sections. Split axis D into four sub-axes (sub / lex / form / cap). Added Verifier Sidecar as Phase 0.5 with D-V1/V2/V3. Split Phase 1 into 1a (sequential, foundational) and 1b (per-surface, parallel). Expanded Phase 3b into per-surface deliverables. Added rows for Settlement (A6), Extensions/Policy Runtime (A7), Voice (A8). Upgraded Calendar identity from ✗ to ⚠ (HatPayload migration path). Promoted SIR (U8) and Lean (U9) to substrate rows acknowledging their dual role. Added §0 (monolith refactor dependency footnote with named cross-refs), §8 (governance questions), §9 (file path crosswalk). Made boot-sequence step 12 explicit about subscription topics.
- **v0.1** — Initial matrix with 10 surfaces × 7 axes, 23 deliverables, six phases.
