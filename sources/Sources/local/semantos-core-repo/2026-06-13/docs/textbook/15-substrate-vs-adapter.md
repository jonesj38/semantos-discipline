---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/15-substrate-vs-adapter.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.647278+00:00
---

> **⚠ Reframed by Ch.37 (Wave Canonical-Cartridge, 2026-05-18).**
> The substrate/adapter *distinction* still holds, but "adapter" is no
> longer a separate concept: an adapter is an **infra cartridge**
> (`role: infra`) that `provides` a typed interface other cartridges
> `consume`. Substrate stays ✓-by-construction; the integration work
> still concentrates in cartridges. Read "adapter" as "infra
> cartridge". See Ch.37 + `docs/design/CANONICAL-CARTRIDGE-MODEL.md`.

# The Substrate / Adapter Distinction

Part V of this textbook covers boot steps 9 through 11: World Host starts its regions (step 9), the mesh adapter joins the multicast group (step 10), and Helm binds localhost (step 11). Before going inside each of those components, this chapter establishes the architectural frame they all live in — the distinction between the substrate and the adapters — and shows exactly where each named component sits on the unification matrix at the time of writing.

This is a structural chapter. It introduces no new protocols or proofs. Its job is to make one distinction precise, trace its consequences through the matrix, and leave the reader with a clear picture of which components are done by construction and which components carry open integration work.

---

## What the Distinction Is

The substrate is the set of components whose job is to implement the unification axes. Every substrate component is, in principle, correct by construction: if it fails an axis, that is a bug against its own specification, not a gap in an integration plan. The ten substrate components are:

- Cell engine (U1)
- Plexus core and vendor SDK (U2)
- Identity, derivation, and recovery (U3)
- Capability Domain (U4)
- Verifier Sidecar (U5)
- Mesh (U6)
- VFS (U7)
- SIR and lexicons (U8)
- Lean proof layer (U9)
- MFP engine (U10)

An adapter is a named consumer surface that exposes substrate capability to a user-, operator-, or peer-facing context. Adapters compose substrate components; they do not provide substrate primitives themselves. The eight adapters in the current matrix are:

- World Host (A1)
- World Client (A2)
- Helm (A3)
- Md Editor (A4)
- Calendar (A5)
- Settlement (A6)
- Extensions / Policy Runtime (A7)
- Voice (A8)

The split matters operationally because the ⚠ and ✗ cells in the matrix cluster almost entirely on the adapter side. Substrate components are mostly ✓ because that is their entire purpose; adapters accumulate gaps because they are built progressively on top of the substrate and not all integration work has landed. The matrix is therefore not a scorecard for the system as a whole — it is a work-tracking instrument specifically for the adapter integration program.

---

## The Seven Unification Axes

Every cell in the matrix is a (surface, axis) pair. A cell is ✓ when the surface fully participates in that axis, ⚠ when it participates partially and a named deliverable closes the gap, ✗ when it does not participate at all, and n/a when the axis is not meaningful for that surface.

The seven axes, with their four sub-axes for axis D, are:

**A. Identity.** Every actor binds to a BRC-52 certificate. Every action carries the cert_id and a BCA derived from it. The Verifier Sidecar enforces that the signing key matches certificate.subject.

**B. Storage.** Every datum is a cell with a CellHeader, addressable in an octave-based content-addressed VFS. Cell state advances only via hash-chained patches.

**C. Transport.** Every cross-process or cross-node message is a SignedBundle (BRC-100 signed request).

**D-sub. Type — substructural.** LINEAR, AFFINE, RELEVANT, and UNRESTRICTED enforcement at the kernel via the K1 gate.

**D-lex. Type — lexicon.** Domain-semantic types over SIR-shaped content via the eight registered lexicons.

**D-form. Type — formal.** Lean-proven invariants over SIR-typed content, with proofs riding alongside cells as their own provenance-bearing cells.

**D-cap. Type — capability.** Authority to act gated by an unspent BRC-108 UTXO, a capability token. Spending the UTXO atomically revokes the capability; capability tokens are LINEAR semantic resources.

**E. Time.** Every change advances a hash chain — per-cell, per-region, per-channel (MFP nSequence), per-domain (BKDS monotonic current_index).

**F. Recovery.** Every persistent surface holding derivation state can export to the Plexus Recovery service in canonical JSON and reconstruct via PBKDF2 root-seed regeneration on the client device.

**G. Metering.** Every paid resource flow advances an MFP 2-of-2 multisig channel with HMAC-authenticated ticks, settled off-chain and finalised on-chain via SPV. Capability tokens gate participation.

Axis D is split into four sub-axes because the four enforcement mechanisms are distinct: K1 (the linearity gate in the cell engine) enforces D-sub; SIR lexicons enforce D-lex; Lean proofs enforce D-form; BRC-108 UTXO spending enforces D-cap. A surface can be fully integrated on one sub-axis and completely absent on another.

---

## Why the Substrate Is Mostly Green

The substrate is green almost by definition. The cell engine's purpose is to enforce K1 (linearity) and K3 (domain isolation), so D-sub is ✓ for U1 by construction. Plexus core's purpose is to manage identity and mint capability tokens, so axes A, B, C, D-cap, E, F, and G are ✓ for U2 by construction. The remaining ⚠ cells inside the substrate are integration gaps where two substrate components do not yet communicate cleanly — U6 (mesh) on axis C because the SignedBundle wrap inside the codec port is pending; U7 (VFS) on axes D-lex, E, and F because the VFS path-resolution layer is not yet fully wired to lexicon constraints or hash-chain progression; U8 (SIR and lexicons) on axes E, F, and capability-adjacent rows because SIR documents do not yet carry their own hash-chain projection; U9 (Lean proof layer) on axis F because proof artifacts are not yet included in the recovery export.

None of these gaps represent fundamental design problems. Each has a named deliverable in the Unification Roadmap's Phase 3b–5 backlog. They are integration tasks, not architectural revisions.

---

## Why the Adapter Side Is Where Work Concentrates

Adapters accumulate ✗ cells for two reasons.

First, most adapters predate the unification program. World Host (A1) was built against Phoenix Channels and Elixir maps before the cell engine existed. Helm (A3) was built as a React application against local state before SignedBundle transport was defined. Adapters that were built Plexus-native from the start — notably Settlement (A6) — are largely ✓ because the design decisions that reduce later integration work were made up front.

Second, adapters interact with every axis simultaneously from the user's perspective, so gaps on any single axis are visible. A1 (World Host) may have ✓ on identity but ✗ on recovery and metering; those ✗ cells are user-facing gaps even though the substrate beneath A1 has the recovery and metering infrastructure fully in place.

The adapter integration program works surface by surface, axis by axis, in the phase ordering the Unification Roadmap defines: identity (A) must land before transport (C) and type (D) on a given surface; recovery (F) follows identity and type; metering (G) follows identity and transport. The phase ordering is a dependency graph over deliverables, not a global sequencing constraint — two surfaces can move through the same phase independently in parallel.

---

## The Two Surfaces That Straddle the Line

Two entries on the matrix do not sit cleanly on one side.

**SIR and lexicons (U8) and Lean proof layer (U9) are substrate rows** despite being tool surfaces that practitioners author and edit. The rationale: their job is to implement sub-axes D-lex and D-form for every adapter. That is a substrate function. At the same time, SIR documents are themselves cells with provenance (they live in the VFS, they carry hash chains, they can be recovered), which is why U8 and U9 have their own ⚠ cells on axes E and F — the infrastructure they use is substrate, but the act of wiring that infrastructure into their own storage paths is integration work.

**Extensions / Policy Runtime (A7) is deliberately straddling.** It is adapter-shaped in that it consumes identity, transport, and storage — but it also provides substrate-adjacent capabilities: minting lexicons and minting capability tokens. A7 is listed as an adapter because it does not itself implement any axis for other surfaces; it consumes axes to extend the governance domain model. The distinction matters when reading A7's ⚠ cells: the ✓ on D-lex (A7 is a lexicon authority) and D-cap (A7 mints capability tokens) reflect its outbound role, not that A7 has no integration work — it does, on axes A, C, B, D-sub, E, and F.

---

## Reading the Matrix

### Status Symbols

| Symbol | Meaning |
|--------|---------|
| ✓ | Unified — the surface participates in this axis with no further work required. |
| ⚠ | Partial — the surface participates partly; a named deliverable closes the gap. |
| ✗ | Island — the surface does not participate; private implementation or none. |
| n/a | Not meaningful for this surface. |

### Substrate

| Substrate ↓ / Axis → | A. Identity | B. Storage | C. Transport | D-sub | D-lex | D-form | D-cap | E. Time | F. Recovery | G. Metering |
|---|---|---|---|---|---|---|---|---|---|---|
| **U1 Cell Engine (Zig WASM)** | ✓ | ✓ | n/a | ✓ | ⚠ | n/a | n/a | ✓ | n/a | n/a |
| **U2 Plexus Core / Vendor SDK** | ✓ | ✓ | ✓ | n/a | n/a | n/a | ✓ | ✓ | ✓ | ✓ |
| **U3 Identity / Derivation / Recovery** | ✓ | ✓ | ✓ | n/a | n/a | n/a | n/a | ✓ | ✓ | n/a |
| **U4 Capability Domain** | ✓ | ✓ | ✓ | ✓ | n/a | n/a | ✓ | ✓ | ✓ | ✓ |
| **U5 Verifier Sidecar** | ✓ | n/a | ✓ | n/a | n/a | n/a | ✓ | n/a | n/a | n/a |
| **U6 Mesh (IPv6 multicast)** | ✓ | n/a | ⚠ D-C6 | n/a | n/a | n/a | n/a | ✓ | n/a | n/a |
| **U7 VFS (cells / octaves)** | ✓ | ✓ | n/a | ✓ | ⚠ D-Dlex-vfs | n/a | n/a | ⚠ D-E-vfs | ⚠ D-F6 | n/a |
| **U8 SIR + Lexicons** | ✓ | ✓ | ✓ | n/a | ✓ | n/a | ⚠ | ⚠ D-E-sir | ⚠ D-F-sir | n/a |
| **U9 Lean Proof Layer** | ✓ | ✓ | n/a | n/a | n/a | ✓ | n/a | n/a | ⚠ D-F-lean | n/a |
| **U10 MFP Engine** | ✓ | n/a | ✓ | ✓ | n/a | n/a | ✓ | ✓ | ✓ | ✓ |

U1's D-lex cell is ⚠ because SIR upcalls into the cell engine are not yet the default path for lexicon validation; the constraint enforcement happens in U8 and needs a clean wire into U1. U6's transport cell is ⚠ because the Prompt 38 codec port split (deliverable D-C6) is the prerequisite for wrapping mesh frames in SignedBundle without rewriting the multicast adapter wholesale.

### Adapters

| Adapter ↓ / Axis → | A. Identity | B. Storage | C. Transport | D-sub | D-lex | D-form | D-cap | E. Time | F. Recovery | G. Metering |
|---|---|---|---|---|---|---|---|---|---|---|
| **A1 World Host (OTP)** | ⚠ D-A1 | ⚠ D-B1 | ⚠ D-C1 | ✓ | ⚠ D-Dlex-world | n/a | ✗ D-Dcap-world | ✓ | ✗ D-F1 | ✗ D-G1 |
| **A2 World Client (three.js)** | ⚠ D-A2 | ⚠ D-B2 | ⚠ D-C2 | ✓ | ⚠ D-Dlex-wc | n/a | ✗ D-Dcap-wc | ✓ | ✗ D-F2 | n/a |
| **A3 Helm** | ⚠ D-A3 | ✓ | ⚠ D-C3 | ⚠ D-Dsub-helm | ⚠ D-Dlex-helm | ⚠ D-Dform-helm | ⚠ D-Dcap-helm | ⚠ D-E-helm | ⚠ D-F3 | ⚠ D-G2 |
| **A4 Md Editor (docs)** | ⚠ D-A4 | ⚠ D-B3 | ✗ D-C4 | ✗ D-Dsub-md | ✗ D-Dlex-md | ✗ D-Dform-md | ✗ D-Dcap-md | ✗ D-E-md | ✗ D-F4 | n/a |
| **A5 Calendar / Events** | ⚠ D-A5 | ⚠ D-B4 | ✗ D-C5 | ✗ D-Dsub-cal | ⚠ D-Dlex-cal | ✗ D-Dform-cal | ✗ D-Dcap-cal | ✗ D-E-cal | ✗ D-F5 | n/a |
| **A6 Settlement (Paskian)** | ✓ | ⚠ D-B5 | ✓ | ✓ | n/a | n/a | ✓ | ✓ | ✓ | ⚠ D-G3 |
| **A7 Extensions / Policy Runtime** | ⚠ D-A6 | ⚠ D-B6 | ⚠ D-C7 | ⚠ D-Dsub-ext | ✓ | ⚠ D-Dform-ext | ✓ | ⚠ D-E-ext | ⚠ D-F7 | n/a |
| **A8 Voice (input modality)** | ✗ D-A7 | ✗ D-B7 | ✗ D-C8 | ✗ | ✗ | n/a | ✗ | ✗ | ✗ | ✗ |

Three observations stand out.

**A6 Settlement is the reference implementation.** Built Plexus-native from the start (as part of the Paskian app, Prompt 44), it is ✓ across most axes. Its only open cells are D-B5 (settlement records still use ad-hoc storage rather than VFS-backed cells) and D-G3 (MFP channel integration for atomic on-chain finalisation). A6 is the worked example of what happens when an adapter is designed with the substrate in mind from day one.

**A3 Helm is the broadest ⚠ row.** Helm is the convergence surface — the three-panel React workbench where every axis becomes user-visible. Helm being ✓ everywhere is roughly equivalent to the unified user experience existing. Every axis has a named deliverable for Helm: D-A3 (identity), D-C3 (transport), D-Dsub-helm through D-Dcap-helm (types), D-E-helm (time), D-F3 (recovery), D-G2 (metering). The breadth of Helm's ⚠ row is a structural feature, not a quality signal — it reflects that Helm touches the output of every other component. Chapter 18 goes inside Helm specifically.

**A8 Voice is a placeholder.** Every cell in A8 is ✗, intentionally. The Voice row exists on the matrix to force the architectural conversation about the input modality the north-star sovereign node depends on. Until a Voice surface is built, the ✗ cells are accurate; they do not represent regression. The naming forces forward planning.

---

## The Axis D Split and Why It Matters

Axis D is named "type" in the unification matrix, but the single word covers four enforcement mechanisms that operate at different layers of the stack.

D-sub (substructural) is enforced at bytecode execution time by the K1 gate inside the cell engine. When a program attempts to consume a LINEAR cell a second time, the K1 gate rejects the transaction; no adapter-level code is involved. This means D-sub is either ✓ or ✗ per surface based on whether the surface routes its mutations through the cell engine — there is no middle state where the surface is "mostly" substructurally typed.

D-lex (lexicon) is enforced at the SIR layer. A surface participates in D-lex when its data payloads are validated against a registered lexicon before being lowered to bytecode. The eight registered lexicons (jural, CDM, circuit, project management, property management, risk assessment, bills of lading, control systems) define the domain-semantic types. A surface that stores entity state as raw Elixir maps or arbitrary JSON has ✗ on D-lex regardless of how well it participates on other axes. The World Host currently stores entity state in Elixir process maps; deliverable D-Dlex-world adds lexicon validation at the region boundary.

D-form (formal) is enforced by Lean proof artifacts. A surface participates in D-form when its SIR programs have associated Lean proofs that travel with the cells as provenance-bearing cells in their own right. D-form is the deepest layer: it cannot land until D-lex is ✓ (you cannot prove properties about typed content that is not yet typed) and until U9's proof layer is wired into the surface's VFS. For most adapter surfaces, D-form is a Phase 3 deliverable that depends on Phase 3 D-lex work completing first.

D-cap (capability) is enforced at the Verifier Sidecar boundary. A surface participates in D-cap when every action that crosses its boundary is gated by an unspent BRC-108 capability token, checked via SPV by the Verifier Sidecar. This is the axis where World Host (A1), World Client (A2), Md Editor (A4), and Calendar (A5) all show ✗ — none of them yet gate actions on capability token presence. The capability token is a LINEAR semantic resource; spending it atomically revokes the authority to act. Once D-Dcap-world lands, entering a World Host region requires a cap.experience token at WebSocket connect, and each entity action within the region requires a per-domain capability token checked at the region boundary.

The four sub-axes can be in different states for the same surface because they compose rather than substitute. A surface can be D-sub ✓ (routes mutations through the cell engine), D-lex ⚠ (lexicon validation is in flight), D-form ✗ (no Lean proofs yet), and D-cap ✗ (no capability gating yet). That is the current state of A1: K1 runs in-process, but lexicon validation, formal proofs, and capability gating are all open deliverables.

---

## What the Phase Ordering Implies

The matrix, read left to right per adapter row, has an implicit dependency chain. A surface's identity cell (axis A) must reach ✓ before its transport cell (axis C) or type cell (axis D) can land, because signing and verification presuppose cert-bound identity. Recovery (axis F) depends on identity and type being settled. Metering (axis G) depends on identity and transport.

This is the phase ordering from the Unification Roadmap's §4:

- Phase 1a: foundational identity contract (shared BCA library, BRC-52 cert flow contract) — sequential, days.
- Phase 1b: per-surface identity — parallel across adapters.
- Phases 2, 3, 4: transport, type, storage — parallel after Phase 1b lands per surface.
- Phase 5: recovery — after identity and type per surface.
- Phase 6: metering — after identity and transport per surface.

The matrix's current state reflects the substrate being complete through Phase 0 (cell engine, Plexus core, boot sequence steps 1–7) and the adapters being partway through Phase 1b and not yet at Phase 5 or 6 for most surfaces. The production boot sequence currently runs end-to-end through step 7 (kernel_set_enforcement(1)). Steps 8 through 15 operate in feasibility but are not yet enforced under full BRC verification across every adapter; each step past 7 that involves an adapter with ✗ or ⚠ cells is gated by the Unification Matrix completing those cells.

---

## Two Surfaces in Depth

### World Host (A1) — The Largest Adapter

World Host is the OTP/Elixir region runtime that hosts persistent shared spaces. It is large: approximately 10³–10⁴ entities per region, with one OTP supervisor per region and one PubSub topic per region. Its position on the matrix — ✓ on D-sub and E, ⚠ on A, B, and C, ✗ on D-cap, F, and G — reflects a surface built to a rigorous distributed-systems standard before the unification program existed.

The ✓ on D-sub (substructural types) is present because the cell engine's K1 gate runs in-process; World Host already routes entity actions through the WASM kernel. The ✓ on E (time) is present because WorldTick already advances a monotonic index. The ⚠ on A (identity) means session identifiers are not yet BRC-52 cert-bound; D-A1 replaces the random session_id with cert-based verification via the Verifier Sidecar. The ✗ on D-cap (capability) means entity actions are not yet gated by BRC-108 capability tokens; D-Dcap-world adds that gate at the WebSocket connect boundary and per-domain-action boundary. The ✗ on F (recovery) means region state is not yet exported to the Plexus Recovery service; D-F1 adds the kernel snapshot bundled as a recovery payload signed by RaaS. The ✗ on G (metering) means regions do not yet open MFP channels for paid clients; D-G1 adds MFP channel management per-region.

Each of these gaps has a concrete deliverable ID. None requires redesigning World Host's region model; all are integration points at the region's boundary.

### Helm (A3) — The Convergence Surface

Helm is the three-panel React workbench (currently shipped as apps/loom-react/) where identity hat, signed actions, cell evidence chains, live region tick deltas, capability state, and metered services all become user-visible. The breadth of its ⚠ row — ten cells, every axis either ⚠ or n/a — reflects that Helm is where the user observes the entire substrate simultaneously.

The single ✓ on axis B (storage) is notable: Helm already uses LoomObject as a storage layer. LoomObject is a runtime/services-layer wrapper that contains a cell along with UI-presentation metadata; the storage infrastructure is present even though the other axes have not yet landed. The cell is the canonical term; LoomObject is the wrapper type, not a synonym.

The ⚠ on D-form (formal) — deliverable D-Dform-helm — calls for Helm to surface Lean proof status alongside live cells in its inspector view. This is not a deep change to Helm's architecture; it is a display integration that consumes the U9 substrate component's proof cells. Proof cells are themselves cells with their own provenance and hash chains, so once U9's D-F-lean lands (proof artifacts in the recovery export), Helm's D-Dform-helm is a relatively narrow display-layer deliverable.

---

## A Note on Terminology

Within this matrix, the word "surface" appears in deliverable IDs and in the Unification Roadmap's original text as a synonym for what this chapter calls "adapter." The glossary's adapter entry notes this directly: the roadmap will be cleaned up to use "adapter" uniformly in the matrix sense. For this chapter and the rest of Part V, "adapter" is the canonical term. "Surface" is reserved for "surface grammar" — the Lisp surface, the LaTeX surface, and other input-syntax forms for the SIR layer — a distinct concept.

Similarly, the A3 row is Helm throughout this chapter. The older name "Loom" remains embedded in package and directory names (loom-react, LoomStore, runtime/services/src/services/loom/) and tolerating it in code-path references is acceptable; in prose, Helm is canonical.

---

## The Substrate / Adapter Boundary in the Boot Sequence

Steps 9–11 of the boot sequence are where the adapter integration work becomes executable:

- Step 9: World Host starts regions. This requires A1's identity cell (D-A1) and transport cell (D-C1) to be ✓, and A1's capability cell (D-Dcap-world) to be at minimum ⚠ — the region cannot gate entry without a capability token check, and the capability check presupposes the Verifier Sidecar (step 8, Phase 0.5) is running.
- Step 10: Mesh adapter joins the multicast group from cert_id. This requires U6's transport cell (D-C6) to reach ✓ — the SignedBundle wrap inside the codec port — and the shared BCA library (D-A0) to be available so the peer identifier can be derived from the cert.
- Step 11: Helm binds localhost. This requires A3's identity cell (D-A3) and transport cell (D-C3) to be ✓ — Helm can only show a trusted picture of the user's cells if it is cert-bound and routing its backend calls through the Plexus Network SDK.

In the current state, steps 1–7 run end-to-end in production-shaped form. Steps 8–11 work in feasibility: the components exist, the integration paths are defined, the Verifier Sidecar can be started, and World Host can start regions — but the BRC enforcement chains (cert-bound identity, SignedBundle transport, capability gating) are not yet wired across every adapter boundary. Each ⚠ and ✗ cell on the adapter side of the matrix is precisely one gap in those chains.

Steps 12–14 (time, recovery, metering) are covered in Part VI. Step 15 — the user fully online, sovereign, and federated — is where the matrix reaches all ✓ across every adapter row.

---

## Matrix Snapshot (at time of writing, 2026-04-26)

The table below consolidates the substrate and adapter status in a single snapshot. Substrate components are marked S; adapters are marked A. The snapshot is accurate as of the Unification Roadmap v0.3.

| Component | Role | A | B | C | D-sub | D-lex | D-form | D-cap | E | F | G |
|---|---|---|---|---|---|---|---|---|---|---|---|
| U1 Cell Engine | S | ✓ | ✓ | n/a | ✓ | ⚠ | n/a | n/a | ✓ | n/a | n/a |
| U2 Plexus Core / Vendor SDK | S | ✓ | ✓ | ✓ | n/a | n/a | n/a | ✓ | ✓ | ✓ | ✓ |
| U3 Identity / Derivation / Recovery | S | ✓ | ✓ | ✓ | n/a | n/a | n/a | n/a | ✓ | ✓ | n/a |
| U4 Capability Domain | S | ✓ | ✓ | ✓ | ✓ | n/a | n/a | ✓ | ✓ | ✓ | ✓ |
| U5 Verifier Sidecar | S | ✓ | n/a | ✓ | n/a | n/a | n/a | ✓ | n/a | n/a | n/a |
| U6 Mesh | S | ✓ | n/a | ⚠ | n/a | n/a | n/a | n/a | ✓ | n/a | n/a |
| U7 VFS | S | ✓ | ✓ | n/a | ✓ | ⚠ | n/a | n/a | ⚠ | ⚠ | n/a |
| U8 SIR + Lexicons | S | ✓ | ✓ | ✓ | n/a | ✓ | n/a | ⚠ | ⚠ | ⚠ | n/a |
| U9 Lean Proof Layer | S | ✓ | ✓ | n/a | n/a | n/a | ✓ | n/a | n/a | ⚠ | n/a |
| U10 MFP Engine | S | ✓ | n/a | ✓ | ✓ | n/a | n/a | ✓ | ✓ | ✓ | ✓ |
| A1 World Host | A | ⚠ | ⚠ | ⚠ | ✓ | ⚠ | n/a | ✗ | ✓ | ✗ | ✗ |
| A2 World Client | A | ⚠ | ⚠ | ⚠ | ✓ | ⚠ | n/a | ✗ | ✓ | ✗ | n/a |
| A3 Helm | A | ⚠ | ✓ | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ | ⚠ |
| A4 Md Editor | A | ⚠ | ⚠ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | n/a |
| A5 Calendar | A | ⚠ | ⚠ | ✗ | ✗ | ⚠ | ✗ | ✗ | ✗ | ✗ | n/a |
| A6 Settlement | A | ✓ | ⚠ | ✓ | ✓ | n/a | n/a | ✓ | ✓ | ✓ | ⚠ |
| A7 Extensions / Policy Runtime | A | ⚠ | ⚠ | ⚠ | ⚠ | ✓ | ⚠ | ✓ | ⚠ | ⚠ | n/a |
| A8 Voice | A | ✗ | ✗ | ✗ | ✗ | ✗ | n/a | ✗ | ✗ | ✗ | ✗ |

Reading across: the substrate half (rows U1–U10) is mostly ✓ with a cluster of ⚠ cells in U6–U9 representing inter-substrate integration gaps. The adapter half (rows A1–A8) carries all of the ✗ cells and most of the ⚠ cells. A6 is the cleanest adapter row; A8 is the most open; A3 is the broadest.

The three ✗ clusters on the adapter side — A1/A2's D-cap, F, and G columns; A4's C through G columns; A8's entire row — are the integration work that defines the roadmap's Phase 3 through Phase 6. Phase 3 deliverables close the ✗ on D-cap; Phase 5 closes the ✗ on F; Phase 6 closes the ✗ on G.

For the live state of this matrix — updated as cells move from ✗ to ⚠ to ✓ with each landing deliverable — see `docs/canon/unification-matrix.yml`.
