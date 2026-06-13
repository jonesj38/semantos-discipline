---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/unification-matrix.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.628546+00:00
---

# docs/canon/unification-matrix.yml

```yml
# The Unification Matrix from SEMANTOS-UNIFICATION-ROADMAP.md §2.
# Schema: docs/canon/README.md#unification-matrixyml.
#
# Stage: scaffold. Stage 1 imports the v0.2 matrix into structured form
# (10 substrate rows × 10 axes + 8 adapter rows × 10 axes). Each cell is
# `{ status: ✓|⚠|✗|n/a, deliverable: D-XX, note: "..." }`.
#
# The matrix-to-roadmap.ts renderer turns this back into the MD tables in
# the unification roadmap. Updating a cell's status in YAML auto-flows
# back to the rendered roadmap.
#
# Once `makeRegistry<DeliverableId, DeliverableStatus>` from PR #184 has
# a Plexus-backed binding, this file becomes the persistence target for
# the registry.

substrate:
  - id: U3
    name: Identity / Derivation / Recovery
    note: |
      The identity substrate provides BRC-52 cert issuance, BRC-42 BKDS key
      derivation, and BCA (Blockchain Channel Address) derivation. D-A0b sealed
      the cross-language cert contract (canonical Brc52Cert types,
      canonicalCertPreimage, computeCertId in TS at
      core/plexus-contracts/src/identity.ts with an Elixir mirror at
      apps/world-host/lib/world_host/identity.ex; 100 conformance vectors at
      core/plexus-contracts/tests/vectors/cert_id_vectors.json pass byte-identical
      on both sides). D-A0 delivers the canonical TypeScript mirror of the Zig
      BCA reference implementation (core/cell-engine/src/bca.zig), enabling every
      adapter (D-A1..D-A7) to derive peer identity from a BRC-52 cert via a single
      conformance-vector-covered library at core/protocol-types/src/bca.ts.
    axes:
      A:
        status: "✓"
        deliverables:
          - D-A0
          - D-A0b
        note: |
          D-A0b: cross-language BRC-52 cert contract sealed. Canonical types +
          canonicalCertPreimage + computeCertId in TS
          (core/plexus-contracts/src/identity.ts); Elixir mirror in
          apps/world-host/lib/world_host/identity.ex; 100 conformance vectors
          pass byte-identical on both sides.
          D-A0: canonical TS BCA library (deriveBca / verifyBca) at
          core/protocol-types/src/bca.ts, mirror of bca.zig, covered by all
          core/cell-engine/tests/vectors/bca_*.json. Every adapter that needs
          to derive a BCA from cert.subjectPublicKey imports from this module;
          this closes the TS-mirror gap so axis A is satisfied in every adapter.
      B:
        status: "✓"
        note: "BRC-52 cert fields and identity DAG entries persisted via Plexus DAG (PlexusCert / Elixir brc52_cert type) — content-addressed cells per axis B."
      C:
        status: "✓"
        note: "BRC-100 + BRC-52 cert carried in SignedBundle envelope (§12.1); constants in transport.ts."
      D-sub:
        status: "n/a"
        note: "Substructural enforcement is a kernel (cell engine / U1) concern."
      D-lex:
        status: "n/a"
        note: "Lexicon authority is a SIR concern; identity is a pre-lexicon primitive."
      D-form:
        status: "n/a"
        note: "Formal proof of identity is a Lean concern (U9); this row implements the algorithm."
      D-cap:
        status: "n/a"
        note: "Capability binding is U4's domain; U3 provides the cert subject that caps are bound to."
      E:
        status: "✓"
        note: "Monotonic childIndex (§4.2) + createdAt timestamp on each cert; algorithm_version on derivation state records."
      F:
        status: "✓"
        note: "BRC-69 edge-backup recipes (§6.2) use identity keys derived under U3; monotonic child indices prevent rollback."
      G:
        status: "n/a"
        note: "Identity substrate does not implement metering — MFP keys are derived from identity but metering is U10's domain."

  - id: U5
    name: Verifier Sidecar
    note: |
      The Verifier Sidecar is the substrate component that enforces BRC-100
      signed envelopes, BRC-52 cert authenticity, identity binding, and
      capability UTXO SPV checks at every adapter boundary.
      D-V1 (VerifierStub interface + reference implementation) is complete.
      D-V2 resolved: per-node sidecar process (see §8 Q3, protocol-v0.5.md §9.5).
      D-V3 merged (#193): first integration into World Host — POST /verify returns
      BCA derived from the verified cert's subjectPublicKey via the D-A0 library.
    axes:
      A:
        status: "✓"
        deliverable: D-V1
        note: "BRC-52 cert authenticity + identity binding (signing key == certificate.subject) enforced at boundary. Satisfies K2."
      B:
        status: "n/a"
        note: "Not applicable — sidecar is verification infrastructure, not a data-model surface."
      C:
        status: "✓"
        deliverable: D-V1
        note: "BRC-100 signed-request standard enforced on every cross-process message."
      D-sub:
        status: "n/a"
        note: "Linearity enforcement is a kernel (cell engine) concern; sidecar operates at the transport boundary."
      D-lex:
        status: "n/a"
        note: "Lexicon authority is a SIR concern, not a verification boundary concern."
      D-form:
        status: "n/a"
        note: "Formal proof (Lean/TLA+) is a proof-layer concern; K2's assumption that boundary verification is done is what the sidecar satisfies."
      D-cap:
        status: "✓"
        deliverable: D-V1
        note: "Capability UTXO SPV checks (BRC-74 BUMP + BRC-95 atomic-BEEF + liveness) via SpvProvider."
      E:
        status: "n/a"
      F:
        status: "n/a"
      G:
        status: "n/a"

  # ─────────────────────────────────────────────────────────────────
  # Remaining substrate rows hydrated 2026-04-29 (canon-bookkeeping
  # pass) from docs/prd/UNIFICATION-ROADMAP.md §2a. Status values are
  # the post-Wave-1.5 state the roadmap asserts. U3 and U5 above were
  # hydrated during Wave 1.5; these eight complete the substrate side.
  # ─────────────────────────────────────────────────────────────────

  - id: U1
    name: Cell Engine (Zig WASM)
    note: |
      The 2-PDA cell engine. Implements K1 (linearity), K4 (failed
      opcodes leave PDA byte-for-byte unchanged), K5 (opcount-bounded
      termination). Source of truth for cell semantics; every adapter
      that classifies cells delegates linearity enforcement here.
      D-DOG.1.0c (2026-05-05) materialised the first end-to-end
      cell-DAG application atop this substrate: the oddjobz domain
      now mints a connected graph of `oddjobz.{site,customer,job,
      attachment}.v2` cells per ratify, signed by per-cell BRC-42
      BKDS-derived keys.  Every cell is content-addressed via SHA-256
      and signed under `protocolID = "oddjobz.cell-sign/v1"` with
      `keyID = <cell-content-hash>`; derived signing keys exist for
      one signature then are discarded (full recovery via the root).
    axes:
      A:
        status: "✓"
        note: "BCA derivation (core/cell-engine/src/bca.zig); cert-bound only via U3 / D-A0."
      B:
        status: "✓"
        note: "PDA + cell as the canonical storage unit; 1 KB cell with 256-byte typed header.  D-DOG.1.0c proves the substrate by minting `oddjobz.{site,customer,job,attachment}.v2` cells linked by typed edges (graph-DAG) per ratify."
      C:
        status: "n/a"
        note: "Cell engine is in-process; transport is a U2 / U6 / U10 concern."
      D-sub:
        status: "✓"
        note: "K1 LINEAR / AFFINE / RELEVANT / UNRESTRICTED gating at the bytecode boundary via OP_ASSERTLINEAR."
      D-lex:
        status: "⚠"
        note: "Lexicon constraints are SIR-layer; the kernel sees the upcalled type-hash but does not itself parse lexicons."
      D-form:
        status: "⚠"
        deliverable: D-LC2
        note: "Formal verification is U9's domain; the kernel runs the bytecode the proofs are about. D-LC2 wires the Lean test vectors (proofs/vectors/) into the brain executor's conformance suite to bridge the model↔runtime gap noted in P4.1-CAPSTONE.md:178."
      D-cap:
        status: "n/a"
        note: "Capability mint/spend lives in U4; the kernel evaluates OP_CHECKDOMAINFLAG on already-minted tokens."
      E:
        status: "✓"
        deliverable: D-LC5
        note: "Opcount + state-version monotonicity enforced inside the WASM execution loop. D-LC5 layers an anchor-watch / pending_anchor projection on top so brain surfaces speculative-vs-confirmed without changing K1–K7."
      F:
        status: "n/a"
      G:
        status: "n/a"

  - id: U2
    name: Plexus Core / Vendor SDK
    note: |
      Plexus client library — BRC-42 BKDS, tenant-node records, BRC-100
      signed envelopes, BRC-69 edge-backup recipes, MFP key derivation.
      Sits between the application layer and the on-chain layer; every
      adapter that talks to the network goes through here.
    axes:
      A:
        status: "✓"
        note: "BRC-42 BKDS implementation in core/plexus-vendor-sdk/src/crypto.ts."
      B:
        status: "✓"
        note: "Tenant-node records persisted to local SQLite (~/.semantos/plexus.db)."
      C:
        status: "✓"
        note: "BRC-100 signed-request envelope is the wire format; constants in transport.ts."
      D-sub:
        status: "n/a"
      D-lex:
        status: "n/a"
      D-form:
        status: "n/a"
      D-cap:
        status: "✓"
        note: "BRC-108 capability UTXO mint/spend dispatch through the SDK's wallet binding."
      E:
        status: "✓"
        note: "Monotonic childIndex enforced at the SQLite append-only constraint per spec §13.2."
      F:
        status: "✓"
        note: "BRC-69 edge-backup recipes are the recovery payload's structural backbone."
      G:
        status: "✓"
        note: "MFP channel-funding keys derived under the SDK's BCA module (U10 consumes)."

  - id: U4
    name: Capability Domain
    note: |
      The on-chain capability layer — BRC-108 UTXOs as authorisation
      resources, classified as LINEAR semantic resources. cap.recovery,
      cap.permission, cap.data_access minted at boot step 6;
      cap.experience, cap.world.*, cap.doc.*, cap.calendar.*, cap.social.*
      added by adapters/extensions on demand.
    axes:
      A:
        status: "✓"
        note: "Each capability UTXO is bound to a cert subject pubkey; spending requires the cert's signing key."
      B:
        status: "✓"
        note: "UTXOs are the on-chain storage form; mirrored locally as capability cells in the VFS."
      C:
        status: "✓"
        note: "Capability presentation in BRC-100 envelopes; SPV proofs ride the same transport."
      D-sub:
        status: "✓"
        note: "K1 instantiated at the on-chain layer: a UTXO can be spent exactly once (the consumption proof)."
      D-lex:
        status: "n/a"
      D-form:
        status: "n/a"
      D-cap:
        status: "✓"
        note: "BRC-108 is THE capability mechanism; this row is its substrate home."
      E:
        status: "✓"
        note: "On-chain ordering provides the global time anchor for capability lifecycle events."
      F:
        status: "✓"
        note: "Capability set is part of the recovery payload (steps 6 + 13)."
      G:
        status: "✓"
        note: "cap.metered_access UTXOs gate MFP channel opening (U10)."

  - id: U6
    name: Mesh (IPv6 multicast)
    note: |
      Peer-to-peer transport using IPv6 multicast groups derived from
      cert_id. BCA addresses are the peer identifiers; the heartbeat
      mechanism uses BCA as the payload identifier. Boot sequence step
      10 joins the multicast group.
    axes:
      A:
        status: "✓"
        note: "BCA derived from cert_id is the canonical peer identifier."
      B:
        status: "n/a"
        note: "Mesh is transport, not storage."
      C:
        status: "⚠"
        deliverable: D-C6
        note: "Frames are not yet uniformly wrapped in SignedBundle; D-C6 is a five-line change inside the Prompt 38 codec port."
      D-sub:
        status: "n/a"
      D-lex:
        status: "n/a"
      D-form:
        status: "n/a"
      D-cap:
        status: "n/a"
      E:
        status: "✓"
        note: "Heartbeat sequence numbers provide per-peer monotonic ordering."
      F:
        status: "n/a"
      G:
        status: "n/a"

  - id: U7
    name: VFS (cells / octaves)
    note: |
      The virtual filesystem rooted at the octave path tree. Each cell
      lives at a stable octave path; directory operations are themselves
      cells. Every adapter persists state through the VFS.
    axes:
      A:
        status: "✓"
        deliverable: D-LC3
        note: "VFS path resolution honours cert-bound ownership; only the owning cert can write to a path it controls. D-LC3 adds a BCA-keyed secondary index on the cell store so cells are also addressable by owner-BCA, not only by content hash."
      B:
        status: "✓"
        note: "VFS IS the storage substrate for cells; the octave tree is the canonical layout."
      C:
        status: "⚠"
        deliverable: D-LC1
        note: "VFS is local-first; cross-node sync rides U2 / U6 transports. D-LC1 promotes this from n/a by exposing raw 1024B cells on the brain HTTP surface as `application/x-semantos-cell` — the first read-path transport that ships the wire format verbatim (no SignedBundle wrapping)."
      D-sub:
        status: "✓"
        note: "Linearity is honoured at write time — a LINEAR cell cannot be re-written under the same path without the predecessor being consumed."
      D-lex:
        status: "⚠"
        deliverable: D-Dlex-vfs
        note: "Lexicon constraints on parent/child relationships not yet enforced at path resolution."
      D-form:
        status: "n/a"
      D-cap:
        status: "n/a"
      E:
        status: "⚠"
        deliverable: D-E-vfs
        note: "Directory-mutation chain not yet a first-class hash chain separate from per-cell chains."
      F:
        status: "⚠"
        deliverables:
          - D-F6
          - D-LC4
        note: "Slot/octave index not yet included in the recovery export (D-F6). D-LC4 adds a complementary `since:prev_state_hash` diff endpoint per BCA — a stateless Git-style reconciliation primitive for federation transports that drop frames; the cell header already carries prev_state_hash, this exposes a forward-index plus streaming read."
      G:
        status: "n/a"

  - id: U8
    name: SIR + Lexicons
    note: |
      Semantic IR and the eight lexicons (jural, CDM, circuit,
      project-mgmt, property-mgmt, risk-assessment, bills-of-lading,
      control-systems). SIR is both substrate (it implements axes
      D-lex / D-form for everyone else) and surface (you author /
      edit / version SIR documents).
    axes:
      A:
        status: "✓"
        note: "SIR documents are cert-signed; lexicon authority cert binding closed by D-A6."
      B:
        status: "✓"
        note: "SIR documents stored as cells with sir.* type-hashes."
      C:
        status: "✓"
        note: "SIR documents transit BRC-100 envelopes like any other cell."
      D-sub:
        status: "n/a"
        note: "Linearity decisions delegate to U1 (cell engine)."
      D-lex:
        status: "✓"
        note: "Lexicon authority is the Lexicon<Cat> typeclass — `core/semantos-sir/src/lexicons.ts` — closed by D-A6 cert binding."
      D-form:
        status: "n/a"
        note: "Formal proof delegates to U9."
      D-cap:
        status: "⚠"
        note: "Lexicon-mint capability cells exist but are not yet uniformly enforced at every entry point."
      E:
        status: "⚠"
        deliverable: D-E-sir
        note: "Per-SIR-doc hash chain projection not yet first-class."
      F:
        status: "⚠"
        deliverable: D-F-sir
        note: "SIR documents not yet included in recovery export."
      G:
        status: "n/a"

  - id: U9
    name: Lean Proof Layer
    note: |
      Mechanised proofs of K1–K10 invariants and per-lexicon obligation
      proofs (M1–M4, D1–D3 per FORMAL-VERIFICATION-STRATEGY.md). Lean
      proofs are themselves cells with provenance — proof artifacts
      have type-hashes, cert binding, and recovery semantics like any
      other cell.
    axes:
      A:
        status: "✓"
        note: "Proof artifacts are cert-signed by the prover."
      B:
        status: "✓"
        note: "Proof cells live in the VFS like any other cell."
      C:
        status: "n/a"
        note: "Proofs are typically resident; verification is local."
      D-sub:
        status: "n/a"
      D-lex:
        status: "n/a"
      D-form:
        status: "✓"
        note: "Lean is THE formal-proof mechanism; this row is the canonical home of axis D-form."
      D-cap:
        status: "n/a"
      E:
        status: "n/a"
      F:
        status: "⚠"
        deliverable: D-F-lean
        note: "Proof artifacts not yet included in recovery export."
      G:
        status: "n/a"

  - id: U10
    name: Metering Engine (MFP)
    note: |
      The Metered Flow Protocol — 2-of-2 multisig payment channels with
      nSequence-based state progression. Channel-funding keys derived
      from BCA. Settlement integrates with on-chain finalisation.
    axes:
      A:
        status: "✓"
        note: "Channel-funding key derived from BCA(cert_id); 2-of-2 multisig binds both parties' identities."
      B:
        status: "n/a"
        note: "MFP state lives in the channel; settlement records persist as cells (A6×B → D-B5)."
      C:
        status: "✓"
        note: "Channel state-update messages ride BRC-100 envelopes."
      D-sub:
        status: "✓"
        note: "Channel state is a LINEAR resource — current state replaces predecessor under nSequence monotonicity."
      D-lex:
        status: "n/a"
      D-form:
        status: "n/a"
      D-cap:
        status: "✓"
        note: "cap.metered_access UTXOs gate channel-open eligibility per service."
      E:
        status: "✓"
        note: "Settlement-sequence ordering on each channel is monotonic and structurally enforced."
      F:
        status: "✓"
        note: "Open channels are recoverable from the recovery payload + the latest signed channel state."
      G:
        status: "✓"
        note: "MFP IS the metering primitive; this row is the canonical home of axis G."

  - id: U11
    name: Canonical Cartridge (manifest-driven model)
    note: |
      The canonical-cartridge axis (ratified 2026-05-19 — `docs/design/CANONICAL-CARTRIDGE-MODEL.md`
      C1–C7; companion `docs/canon/commissions/wave-canonical-cartridge.md`). One unit (cartridge)
      with one manifest (`cartridge.json`) and two parts (Brain + PWA-experience), loaded by two
      shells from the same manifest. The schema-spine sub-thread
      (`docs/design/CARTRIDGE-CANONICAL-SCHEMA-SPINE.md` + CC5/CC6/CC7) makes the manifest's
      `objectTypes`/`payloadSchema` section *load-bearing*: every cartridge's data-plane
      (encode/validate/render/ingest-adapter/surfacing) flows from the manifest, not from
      hand-coded TS/Zig hand-mirrors. As of 2026-05-21 the cell-identity registry seam (P3a #458,
      P3b #460), the schema contract (CC5.B1 #469), oddjobz's declarative `objectTypes` (CC5.B2a
      #478 — first load-bearing use), the v2 hand-mirror retirement (CC5.B2b #482), the
      per-cartridge surfacing declaration (CC7 v0.3 `primaryAnchor`/`hierarchy` #473), the
      schema-extension mechanism (a)/(b)/(c) ratification (#475), and the CC6 ingest
      source-adapter retirement (CC6.1 inference-pipeline ratification #486, CC6.2 adapter-config
      cell type at the substrate primitive #491, CC6.3a runtime hardcode retirement #495, CC6.3b
      PROMPT_TEMPLATE parameterization #499) are all on `main`. CC7 implementation is the
      remaining active front; CC6 is closed at this row.
    axes:
      A:
        status: "✓"
        deliverables:
          - CC1
        note: |
          Cartridge identity = license-UTXO holder (Decision A: affine PushDrop license UTXO;
          Marketplace-Ownership A/B/C ratified). DLO.1c Option-C disk registry + `setLicenseGate`
          loader hook. First-party (no license yet) escape hatch documented (CC3 golden path test
          covers it). Each cartridge has a single owner identity by construction.
      B:
        status: "✓"
        deliverables:
          - CC5.B1
          - CC5.B2a
          - CC5.B2b
          - CC6.2
        note: |
          The biggest schema-spine deliverable. Cartridge declares its payload schema in
          `cartridge.json` `objectTypes[]` with per-field `tier:'core'|'operator-extensible'` and
          optional `carrier:{octave:1}` annotation (PR #469). oddjobz authored its job/site/customer
          objectTypes name-preservingly (PR #478) and retired the 514-LOC `job.v2.ts` hand-mirror
          + siblings (PR #482, -1596/+84). Octave-1 escalation is the *default* read/write path
          (UNIVERSAL-CARTRIDGE-BOOT §3.6) — `carrier` is a render hint, not a mechanism. The
          encode/validate path consumes the declared schema via the landed
          `grammar-config-bridge.mapPayloadSchema` carry-through (carrier-less ⇒ byte-identical).
          CC6.2 (#491) added the platform-level `SPEC_ADAPTER_CONFIG` (TAG_ADAPTER_CONFIG = 0x10)
          to `substrate_entity.zig` — adapter-config is a typed substrate primitive (linearity =
          AFFINE for drafts, RELEVANT for active configs), persisted through the existing
          `substrate.entity.encode` walker. The substrate's verb-set stays orthogonal; domain
          meaning stays at the edge.
      C:
        status: "✓"
        deliverables:
          - CC0
          - CC2
          - DLO.1c
          - CC6.2
        note: |
          `verb.dispatch(extensionId, verb, params_json)` is the single canonical cartridge
          boundary (BRAIN-DISPATCHER-UNIFICATION + `verb_dispatcher.zig` walker registry, both
          landed). CC2 dual-shell loader landed; CC3 golden path proves both shells load the same
          manifest. CC6.2 (#491) ratified adapter-config-as-intents over the same verb.dispatch
          primitive — adapter-config cells persist through the existing `substrate.entity.encode`
          walker; no new endpoint; `/api/v1/info` stays GET-only per SHELL-CARTRIDGES-HATS and
          the `tests/gates/cc6-2-info-get-only.test.ts` regression gate.
      D-sub:
        status: "✓"
        deliverables:
          - CC0
        note: |
          Cartridge declares per-objectType `linearity: LINEAR|AFFINE|RELEVANT|FUNGIBLE` in the
          manifest (CC0 grammar-section fold-in). oddjobz/cartridge.json U11 uses AFFINE for
          site/customer/job. K1 substrate gate (U1) enforces it at the cell level.
      D-lex:
        status: "✓"
        deliverables:
          - CC0
        note: |
          Lexicon is a manifest section (CC0). `docs/canon/lexicons.yml` is a derived index per
          C2 (manifest-as-source). Per-cartridge lexicon overlays follow the same pattern. 12
          canonical lexicons enumerated in `core/semantos-sir/src/lexicons.ts`.
      D-form:
        status: "⚠"
        note: |
          Per-lexicon header-injectivity proven via `proofs/lean/Semantos/Lexicons/*`. The
          canonical-cartridge composition rules (`consumes`/`provides`, Decision B; brain.surface
          C7) and the schema-spine (objectTypes/tier/carrier) are amenable to Lean property proofs
          (manifest-as-source totality, carrier overflow size-preservation, entityMapping totality)
          but those proofs are not written. Future deliverable.
      D-cap:
        status: "⚠"
        deliverables:
          - CC0
          - CC5.B2a
        note: |
          `cartridge.json` `verbs[]` declare `capability_required`; CC5.B2a `objectTypes[].capabilities`
          block exists per the contract but oddjobz currently has empty `{}` stubs (the runtime
          capability registry is externalised to `brain/src/capabilities.ts` + the §9 Zig mirror).
          The CANONICAL-CARTRIDGE-MODEL §4.3 rebase ("§9 cap mirror-list = manifest → generated
          Zig, not hand-maintained") is canonical but not yet implemented — the generator step is
          a follow-up. Promoted from ✗ to ⚠ by the §4.3 ratification; promoted to ✓ when the
          generated Zig cap table replaces the hand-mirror.
      E:
        status: "✓"
        note: |
          Append-only versioned cells preserved by construction. FSM transitions append state-only
          cells (`{ts,kind:updated,id,state,scheduled_at}`); the FSM is *verified-orthogonal* to
          the payload (CC5 v0.3 §2.1 coupling-map — `job_fsm.zig` reads only state strings, zero
          payload refs). The schema-spine refactor preserves all time-axis invariants.
      F:
        status: "⚠"
        note: |
          A schema-declared cell exports canonically by virtue of being content-addressed +
          manifest-described — the *capability* for manifest-driven recovery is present
          (cartridge.json + cell DAG + BRC-69-style recipe). The wired flow is partial: cells
          replay deterministically, but a recovery payload "include this cartridge's full
          object-type set + per-cell content-hashes" pass isn't implemented as a
          cartridge-bounded operation yet. Per-cartridge recovery is a follow-up cell.
      G:
        status: "n/a"
        note: |
          Metering is orthogonal — per-verb `mfp_keys` live on U10 (MFP). The canonical-cartridge
          model doesn't add to the metering substrate; it consumes it (`role:infra` wallet/headers
          cartridges provide SpvVerifier; cartridge license-gate enforces entitlement; metering
          remains U10's home).

  # ----------------------------------------------------------------------------
  # U12 — Conversation Graph (SCG)
  # ----------------------------------------------------------------------------
  # Design choice (audit 2026-05-21): Option α — new substrate row.
  #
  # Rationale: SCG promotes "typed relation" to a first-class primitive (`scg.relation`
  # objects on `sem_objects`) with its own substrate package (`core/scg-relations`),
  # its own conversation-graph primitive (`core/conversation-graph`), its own payload
  # schema (`core/plexus-schema-registry/.../scg-relation.ts` under
  # `SemantosDomainFlags.SCG_RELATION = 0x0001FE03`), its own capability slots
  # (`RELATION_MINT`/`RELATION_REVOKE`), and its own intent-reducer pass
  # (`runtime/intent/src/reducer/relation-pass.ts`). This is structurally a new
  # substrate surface — wider than "another lexicon under U8" (Option β rejected) and
  # not orthogonal to the existing A–G axes (Option γ rejected).
  #
  # Distinction from U11 (Canonical Cartridge): U11 is the manifest+loader machinery
  # that any cartridge uses. U12 is a *substrate primitive* (typed relations + turn
  # pipeline) that cartridges consume. `packages/scg/` is U12's declarative-cartridge
  # face; the substrate work lives in `core/scg-relations` + `core/conversation-graph`.
  # See `docs/SCG-IMPLEMENTATION-TRACKING.md` §13 for the cartridge-shape pin.
  - id: U12
    name: Conversation Graph (SCG)
    note: |
      The Semantos Conversation Graph (SCG). Typed relations on `sem_objects`
      (`core/scg-relations`), generic turn pipeline (`core/conversation-graph`), payload
      schema registered at `SemantosDomainFlags.SCG_RELATION = 0x0001FE03`, capability
      slots `RELATION_MINT`/`RELATION_REVOKE`, 10th intent-reducer pass (`relation-pass`).
      Phase 1 (substrate bolt-on) substantially landed via Waves 1-8 (RM-010..082); the
      Oddjobz consumer cut-over and Phase 2 projection demos are the remaining work.
      Companion doc: `docs/SCG-IMPLEMENTATION-TRACKING.md`.
    axes:
      A:
        status: "✓"
        deliverable: D-SCG-relations
        note: |
          Relations carry `createdByCertId` via `createObject` inheritance from
          `core/semantic-objects`; `requireRelationMint` (RM-022) gates creation via
          `capabilityPort`. Identity binding is by construction.
      B:
        status: "✓"
        deliverables:
          - D-SCG-relations
          - D-SCG-payload-schema
        note: |
          Relations are `sem_objects` rows of `objectKind='scg.relation'` — no schema
          migration. The on-chain anchored-cell variant has a registered payload schema
          under `SemantosDomainFlags.SCG_RELATION = 0x0001FE03` (RM-082) committing
          `kind`/`source`/`target`/`amount`/`currency`/`txAnchor`/`attestation` fields.
      C:
        status: "✓"
        note: |
          Relation patches transit BRC-100 envelopes like any other `sem_objects` patch.
          No new transport surface.
      D-sub:
        status: "n/a"
        note: |
          Linearity decisions delegate to U1 (cell engine) for the on-chain anchored
          variant. Jsonb-backed relation rows in `sem_objects` use the linearity declared
          on the parent objectKind.
      D-lex:
        status: "✓"
        deliverable: D-SCG-lexicon
        note: |
          `relationLexicon` registered in `ALL_LEXICONS` (`core/scg-relations/src/lexicon.ts`).
          15 canonical `RelationKind` values; `verifyLexiconInjective` test passes.
      D-form:
        status: "n/a"
        note: |
          No Lean proof required for the relation primitive at this layer. Future work
          could prove injectivity of the relation-lexicon header function.
      D-cap:
        status: "✓"
        deliverable: D-SCG-capabilities
        note: |
          `ClientDomainFlags.RELATION_MINT = 0x0001000c`, `RELATION_REVOKE = 0x0001000d`
          (`core/plexus-contracts/src/domain-flags.ts`). `requireRelationMint` enforced at
          `createRelation` and via the SIR `relation` constraint lowering composite.
      E:
        status: "✓"
        note: |
          Relation patches inherit `appendPatch` timestamps and the optimistic-concurrency
          hash chain from `sem_objects`. `foldRelationGraph` is deterministic over the
          patch sequence; `relation-pass` is deterministic over the reducer input.
      F:
        status: "⚠"
        deliverable: D-SCG-recovery
        note: |
          Relations live in `sem_objects.payload` and are recovered via the standard
          `sem_objects` recovery path. The on-chain anchored variant (RM-082 schema) is
          not yet part of an explicit BRC-69-style recovery recipe; tagged ⚠ until a
          relation-aware recovery export is wired.
      G:
        status: "n/a"
        note: |
          SCG does not implement metering — paid-content `requirePaymentRelation` (RM-063
          access gate) consults `PAYS` relations but the metering channel itself remains
          U10's domain.

  # ----------------------------------------------------------------------------
  # U13 — Oddjobz Conversation Engine
  # ----------------------------------------------------------------------------
  # Design choice (added 2026-05-21 by docs/oddjobz-conversation-architecture):
  # new SUBSTRATE row, NOT new adapter rows.
  #
  # Rationale (see docs/design/ODDJOBZ-CONVERSATION-ARCHITECTURE.md Appendix C):
  #
  # • The Oddjobz conversation engine sits on U12 (SCG) but is not U12. U12 is
  #   the generic typed-relations primitive (`scg.relation` rows, the
  #   conversation-graph Turn type, `autoEmitReplyRelation`). U13 is the
  #   entity-anchored, multi-party, multi-surface conversation engine — adds
  #   `BELONGS_TO_ENTITY` anchoring, the participantRole identity model, the
  #   surface-adapter contract, the AI-participant integration, and the
  #   conversation-as-higher-order-SIR aggregate. Substrate-shaped enough to
  #   warrant its own row.
  #
  # • The surface adapters (widget / meta-inbox / email / voice / sms / import)
  #   are NOT cartridges per project memory `semantos_streams_shell_native`.
  #   They don't deserve adapter-row slots (A1..A11 are cartridges + verticals).
  #   They live as sub-deliverables of U13.
  #
  # • Voice already has its own adapter row (A8) for the input-modality
  #   primitive (D-A7 stub). U13 consumes that primitive via its voice surface
  #   adapter (D-OJ-conv-voice-intake); no new A* row.
  #
  # Companion design doc: `docs/design/ODDJOBZ-CONVERSATION-ARCHITECTURE.md`.
  - id: U13
    name: Oddjobz Conversation Engine
    note: |
      Entity-anchored, multi-party, multi-surface conversation engine built on
      U12 (SCG). Every turn is a `sem_objects` row of
      `objectKind='oddjobz.conversation.turn'`, anchored to a job/site/customer
      cell by a `BELONGS_TO_ENTITY` SCG relation (new kind, D-OJ-conv-entity-
      anchoring). Multiple participants — `operator`, `ai`, `tenant`, `agent`,
      `owner`, `subcontractor`, `tradesman`, `external` — share one stream over
      the entity. Multiple inbound surfaces — Oddjobz chat widget, Meta Inbox
      (IG/FB DMs), email (gmail reingest), voice notes, SMS (Twilio), historical
      CSV import — all normalise onto the same canonical turn shape via the
      surface-adapter contract (`docs/design/ODDJOBZ-CONVERSATION-
      ARCHITECTURE.md` §6). The AI agent is a first-class participant with its
      own narrow operator-issued child cert and a draft/approve/send state
      machine structurally enforced at SIR lowering. Talk renders the unified
      thread; outbound replies are symmetric (same turn shape, the surface
      adapter's `send` method routes back to the surface the customer uses).
      Companion design doc:
      `docs/design/ODDJOBZ-CONVERSATION-ARCHITECTURE.md`.
    axes:
      A:
        status: "✓"
        deliverables:
          - D-OJ-conv-multiparty-identity
          - D-OJ-conv-ai-participant
        note: |
          Turns carry both `actorCertId` (cert-bound participants — operator,
          AI, subcontractor) and `identityHandle` (un-cert'd parties —
          tenant/owner/agent identified by phone/email/IG/FB handle).
          AI-agent child cert shipped via P3.4 (`cartridges/oddjobz/brain/src/
          conversation/agent-cert-provider.ts`).
      B:
        status: "⚠"
        deliverables:
          - D-ODDJOBZ-turns-as-sem-objects
          - D-OJ-conv-entity-anchoring
        note: |
          Turns become `sem_objects` rows of `oddjobz.conversation.turn` via
          D-ODDJOBZ-turns-as-sem-objects (today they jsonl-append). Once that
          lands plus D-OJ-conv-entity-anchoring (the `BELONGS_TO_ENTITY` SCG
          kind), this axis closes to ✓. Status ⚠ until both deliverables ship.
      C:
        status: "✓"
        note: |
          Turns ride the existing intake submission path (the detached
          grandchild submitter pattern). No new transport surface; PROJECTION
          doc DECISION-A3 Option-C (2026-05-17) pinned this.
      D-sub:
        status: "✓"
        note: |
          Turn patches are append-only; corrections are new turns;
          ratifications are signed patches. K1 substrate guarantees inherit
          from `sem_objects`.
      D-lex:
        status: "⚠"
        deliverable: D-OJ-conv-entity-anchoring
        note: |
          New SCG relation kinds (`BELONGS_TO_ENTITY`, optionally
          `REFERENCES_OBJECT`) added to `relationLexicon`; `participantRole`
          enum needs lexicon registration. Status ⚠ until the lexicon-
          injectivity test is extended with the new kinds.
      D-form:
        status: "n/a"
        note: |
          Lean proofs not required at this layer. Substrate proofs cover the
          underlying `sem_objects` and SCG-relation primitives.
      D-cap:
        status: "⚠"
        deliverable: D-OJ-conv-ai-participant
        note: |
          The AI participant's outbound-send capability scope is structurally
          enforced at SIR lowering (see design doc §9.2 + open question 13.3).
          Status ⚠ until the SIR-constraint-kind shape lands.
      E:
        status: "✓"
        note: |
          Turn patches carry persisted-at timestamps; the conversation
          aggregate (D-OJ-conv-aggregate-sir) is deterministic over the patch
          stream per the `semantos_dx_priorities` snapshot/replay constraint.
      F:
        status: "⚠"
        deliverable: D-OJ-conv-aggregate-sir
        note: |
          Turns recover via the standard `sem_objects` recovery path. The
          conversation-aggregate higher-order SIR (D-OJ-conv-aggregate-sir)
          isn't yet wired into the recovery export.
      G:
        status: "n/a"
        note: |
          Metering attaches at SCG Phase-3 (D-SCG-economic-port +
          D-SCG-wallet-integration) via `PAYS` / `GRANTS_ACCESS` relations on
          turns. U13 itself doesn't add a metering primitive.

  # ----------------------------------------------------------------------------
  # U14 — Semantic Routing Substrate (SNS / SRv6 type-network)
  # ----------------------------------------------------------------------------
  # Design choice (unification 2026-05-23): Option α — new substrate row.
  #
  # Rationale: SRS promotes "the type hash IS the network address" to a
  # first-class substrate. It maps the six-axis taxonomy onto IPv6 address space
  # (per-axis hash projections → multicast group bits, longest-prefix-match =
  # hierarchical semantic routing — the "SNS"), encodes BCA + segment-function
  # into SRv6 SIDs, and learns its own routing (Steiner/TSP approximation) from
  # the SRv6 provenance DAG via Paskian/HRR. This is wider than "more transport
  # on U6" — U6 is raw IPv6 multicast (peer = BCA, heartbeat sequencing); U14 is
  # the type-aware routing/learning/metering plane that rides on U6.
  #
  # Distinction from U6 (Mesh): U6 is the multicast pipe. U14 is what makes the
  # pipe type-routed, paid (End.S.TICK), provenance-bearing (SRH), and
  # access-controlled (End.S.LICENSE) — driven entirely by the semantic type
  # system, zero network config per vertical.
  #
  # Distinction from U12 (SCG): U12 is typed relations on sem_objects (a graph of
  # meaning); U14 is typed routing of cells (a graph of delivery). They compose —
  # U14 can carry SCG relation cells like any other typed cell.
  #
  # Prior art / implementation tickets: docs/prd/PHASE-34-SRV6-TYPE-NETWORK-MASTER.md
  # (D34A.1..D34D.2), docs/prd/PHASE-34E-PASKIAN-MESH-LEARNING.md (D34E.1..D34E.6).
  # Unification + new glue: docs/design/SEMANTIC-ROUTING-SUBSTRATE.md (D-SRS-*).
  # Exercised end-to-end by the MNCA layer-collapse demo (singularity-matrix
  # L3-F/G, L4-F/G/I; docs/demo/MNCA-MESH-DEMO.md).
  - id: U14
    name: Semantic Routing Substrate (SNS / SRv6 type-network)
    note: |
      The type hash IS the network address. Per-axis taxonomy projections
      (computeWhatHash/computeHowHash/computeInstHash) map onto IPv6 multicast
      group bits so native longest-prefix-match gives hierarchical semantic
      routing — the Semantic Name System (SNS), a registry-free alternative to
      DNS. BCA + segment-function encode into SRv6 SIDs; segment functions
      (CREATE/VALIDATE/TICK/ANCHOR/ATTEST/FILTER/METER/DISPATCH/LICENSE) run the
      cell engine at each hop. The substrate learns its own routing: Paskian/HRR
      observes the SRv6 provenance DAG and converges toward the Steiner/TSP
      optimum via economic pressure (End.S.TICK), constraint pruning, and
      semantic clustering (Phase 34E). The MNCA layer-collapse demo is the live
      exercise: MNCA tiles ARE cells flowing through this plane (mnca.tile.tick →
      mnca.snapshot), with transform-on-hop, source-routed traversal, and an
      on-chain anchor all proven (singularity L3-F, L4-F/H). New unification glue
      (docs/design/SEMANTIC-ROUTING-SUBSTRATE.md): two-tier multitenant multicast
      to N≈100 (intra-Pi ff15::5e:2 ↔ inter-Pi ff15::5e:1 via per-Pi gateway),
      coverage-guided type-path fuzzing (MNCA state = the coverage signal), and
      MNCA-as-routing-substrate (tile rows carry pheromone/queue/who density).
      Companion: docs/prd/PHASE-34-SRV6-TYPE-NETWORK-MASTER.md +
      docs/prd/PHASE-34E-PASKIAN-MESH-LEARNING.md.
    axes:
      A:
        status: "✓"
        note: |
          BCA (Ducroux, core/cell-engine/src/bca.zig + protocol-types/src/bca.ts)
          is the peer identifier AND the WHO field of the SRv6 SID. Every hop is
          cert-attributable; routing decisions carry the relaying node's cert.
      B:
        status: "⚠"
        deliverables:
          - D-SRS-mnca-cell-source
        note: |
          The learned routing graph persists as cells — RELEVANT
          paskian.graph.edge / .node / .stable, LINEAR paskian.graph.pruned
          (Phase 34E, via StorageAdapter). ⚠ until that graph-as-cells flow is
          wired into the live mesh (D-SRS-mnca-cell-source replaces the random
          tile seed with real input so the graph learns over real data).
      C:
        status: "✓"
        deliverables:
          - D-SRS-tenant-gateway
          - D-SRS-multitenant-spawn
        note: |
          This row IS type-aware transport over U6. Source-routed cell traversal
          (1- and 2-relay, payload bit-intact) is live on real multicast
          (singularity L3-F, routing.zig processHop). Two-tier multitenant mesh
          (D-SRS-tenant-gateway bidirectional ff15::5e:2↔ff15::5e:1 relay +
          D-SRS-multitenant-spawn ~16 tenants/Pi) scales it to N≈100.
      D-sub:
        status: "✓"
        note: |
          Segment-function chains respect linearity: LINEAR →
          CREATE→VALIDATE→TICK→ANCHOR (must prove consumption + pay + anchor);
          AFFINE → CREATE→VALIDATE→METER (End.S.METER consumes an AFFINE
          bandwidth slot, drop = backpressure); RELEVANT → CREATE→ATTEST. Pruning
          events are LINEAR (consumed once). K1 substrate gate (U1) enforces.
      D-lex:
        status: "⚠"
        deliverable: D-SRS-typepath-fuzzer
        note: |
          Jural categories (Hohfeld: declaration/obligation/permission/
          prohibition/power/condition/transfer, U8) extend the type path by a
          segment → one hop deeper in the SNS tree; grammar licensing
          (End.S.LICENSE) gates routing by jural standing — "routing IS
          compliance". Lexicon authority delegates to U8. ⚠ until jural namespace
          depth is enforced at the gateway and the type-path fuzzer
          (D-SRS-typepath-fuzzer) is scoped to safe *.fuzz.* paths.
      D-form:
        status: "n/a"
        note: |
          Formal proof delegates to U9. Note: Phase 34E's TSP-convergence proof
          (T15 — approximation ratio < 2.0, re-converges after perturbation) is
          an empirical integration gate, not a Lean proof; a Lean property proof
          of the SNS prefix-trie / segment-function-chain invariants is a future
          U9 deliverable.
      D-cap:
        status: "⚠"
        note: |
          Grammar licensing is a RELEVANT plexus.capability.grammar_license token
          (permanent proof-of-purchase, anti-clone via OP_CHECKIDENTITY on the
          cert chain), checked by segment function End.S.LICENSE (0x09);
          revocation is a separate LINEAR cell. Designed in Phase 34
          §"Grammar Licensing"; ⚠ until End.S.LICENSE + the edge-cached
          attestation land.
      E:
        status: "✓"
        note: |
          SRH In-situ OAM timestamps (RFC 9486) + cell header timestamp (offset
          78) give per-hop temporal provenance; Paskian stability windows
          (ΔH < ε over minInteractions) and End.S.TICK sequence give monotonic
          ordering. WHEN is a routable axis.
      F:
        status: "⚠"
        note: |
          The learned routing/correlation graph is recoverable from its RELEVANT
          edge/node/stable cell DAG (content-addressed, anchored). ⚠ until the
          graph is included in the recovery export as a bounded operation (mirrors
          U7-F / U8-F open recovery-export work).
      G:
        status: "✓"
        note: |
          End.S.TICK (0x03) per-hop BSV micropayment IS the economic pheromone
          that drives TSP convergence — senders pay per hop, relays earn per hop,
          the gradient finds minimum-cost routes with no global optimiser. This
          row is a primary consumer/driver of U10 (MFP) metering; per-hop payment
          plans (buildPathPaymentPlans, singularity L6-F) are index-aligned with
          processHop's spendSegmentIndex.

adapters:
  - id: A1
    name: World Host (OTP)
    note: |
      The OTP/Elixir authoritative-region runtime (apps/world-host/). A1
      is the first adapter to integrate the Verifier Sidecar (per
      Unification Roadmap §5 D-V3 / §7 day 3-5 track A): every inbound
      WebSocket presents a BRC-100 SignedBundle wrapping a BRC-52 cert,
      verified at connect/3 over loopback HTTP. D-V3 laid the verification
      path; D-A1 completes the full A×A binding with cert_id ownership
      at every action, cap_token authorisation at the channel-join
      boundary, and a `/healthz` boot gate that ensures the sidecar is
      ready before the Endpoint accepts sockets.
    axes:
      A:
        status: "✓"
        deliverables:
          - D-V3
          - D-A1
        note: |
          D-A1 completed: cert_id ownership at every action; cap_token
          at join; boot order awaits sidecar /healthz.
          Connect/3 calls `WorldHost.VerifierClient` which dispatches to
          the per-node Verifier Sidecar (D-V2 topology) over loopback
          HTTP; on success, socket.assigns.bca and socket.assigns.cert_id
          are populated. `world_channel.ex` `join/3` lifts cap_token
          verification from connect/3 (Phase-3 SPV checks happen at the
          channel-join boundary, refusing joins on missing or
          UTXO-spent tokens). The `entity_action` wire key is `cert_id`,
          matched against the entity's `controller` to enforce ownership
          (K2). Boot ordering: `WorldHost.SidecarHealthcheck` polls the
          sidecar's `/healthz` with exponential backoff before the
          Phoenix Endpoint starts. Tests use real ECDSA-signed BRC-52
          certs + BRC-100 SignedBundles via
          `WorldHost.Test.SignedBundleFixture`; the mock verifies them
          locally with the same Phase-1 + Phase-2 logic the production
          sidecar runs.
      B:
        status: "⚠"
        deliverable: D-B1
      C:
        status: "⚠"
        deliverable: D-C1
      D-sub:
        status: "✓"
        note: "Via U1 (cell engine K1 gate) at the Region.apply_action boundary."
      D-lex:
        status: "⚠"
        deliverable: D-Dlex-world
      D-form:
        status: "n/a"
      D-cap:
        status: "✗"
        deliverable: D-Dcap-world
      E:
        status: "✓"
        note: "Per-region WorldTick + Merkle-rooted state hash (per WORLD-PROTOCOL.md §6, §10)."
      F:
        status: "✗"
        deliverable: D-F1
      G:
        status: "✗"
        deliverable: D-G1

  - id: A2
    name: World Client (browser)
    note: |
      The Three.js browser client (apps/world-client/). D-A2 makes the client
      a first-class BRC-100 participant: every outbound action is signed with
      the session's BRC-52 cert keypair and every inbound server response is
      signature-verified before being delivered to application code.
      D-A2: client signs every outbound action with the cert keypair; verifies
      server response signatures; replaces random session_id with the §12.1
      SignedBundle handshake.
    axes:
      A:
        status: "✓"
        deliverable: D-A2
        note: |
          D-A2 delivered: WorldSocket.connect() sends a §12.1 SignedBundle as
          the signed_bundle socket param (BRC-100 envelope with
          x-brc100-identitykey, x-brc100-nonce, x-brc100-timestamp,
          x-brc100-signature, x-brc52-certificate). Every sendAction() call
          wraps the EntityAction payload in a fresh BRC-100 signed envelope with
          cert_id (not a random id). Inbound server messages carrying BRC-100
          headers are ECDSA-verified before delivery; bad signatures are dropped.
          IdentityProvider interface is the D-A3 (Helm) plug point for real
          BRC-42-derived keypairs.
      B:
        status: "⚠"
        deliverable: D-B2
      C:
        status: "✓"
        deliverable: D-A2
        note: "BRC-100 signed envelopes on both outbound actions and inbound server responses."
      D-sub:
        status: "n/a"
        note: "Substructural enforcement is a kernel (cell engine) concern, not the browser client."
      D-lex:
        status: "⚠"
        deliverable: D-Dlex-wc
        note: "Client predictor will validate outgoing actions against the `world` lexicon — Phase 3."
      D-form:
        status: "n/a"
      D-cap:
        status: "✗"
        deliverable: D-Dcap-wc
        note: "UI surfacing of capability state — Phase 3."
      E:
        status: "✓"
        note: "Predictor (WASM) provides client-side prediction with monotonic ordering; state hash verification post-D-B2."
      F:
        status: "✗"
        deliverable: D-F2
        note: "Restore-from-recovery on a new device — Phase 5."
      G:
        status: "n/a"

  - id: A5
    name: Calendar
    note: |
      The calendar extension (extensions/calendar/) attributes patches to
      hats — the per-action signing principal. D-A5 (Phase 1b) migrates
      HatPayload / HatRecord onto BRC-52 cert backing: the opaque hatId
      is now a cert_id (= computeCertId of the hat's BRC-52 cert) and
      HatPayload carries an optional certBacking record. Cross-context
      isolation per protocol-v0.5.md §4.4 is enforced by the
      deriveHatCertId() helper, which threads the contextTag into the
      BRC-52 preimage so two hats in two contexts produce divergent
      cert_ids; the underlying mathematical isolation lives in BRC-42
      BKDS at the wallet (subject pubkey derivation under per-context
      domain flags, §4.5). Backward compatibility via the legacy
      opaque-id path: existing seed fixtures and tests continue to work
      with arbitrary string ids treated as self-issued cert_ids and
      certBacking == null.
    axes:
      A:
        status: "✓"
        deliverable: D-A5
        note: |
          D-A5: HatPayload/HatRecord migrated to BRC-52 cert backing.
          extensions/calendar/src/domain/hat.ts gains deriveHatCertId() +
          buildHatCert() that compute cert_id via @plexus/contracts'
          computeCertId; the cert preimage carries contextTag in fields
          for §4.4 cross-context isolation. createHat asserts
          input.id === computeCertId(cert) when a Brc52Cert is supplied,
          and rejects contextTag mismatches between input.contextTag and
          cert.fields.contextTag. Tests at
          extensions/calendar/src/__tests__/hat.test.ts cover round-trip,
          cross-context isolation (H3, H4), id↔cert mismatch (H5),
          contextTag mismatch (H6), and pre-D-A5 record migration (H9).
      B:
        status: "⚠"
        deliverable: D-B5
      C:
        status: "⚠"
        deliverable: D-C5
      D-sub:
        status: "✓"
        note: "Schedule patch stream is the linear resource; one-schedule-one-stream invariant enforced via @semantos/semantic-objects appendPatch."
      D-lex:
        status: "⚠"
        deliverable: D-Dlex-cal
      D-form:
        status: "✗"
        deliverable: D-Dform-cal
      D-cap:
        status: "✗"
        deliverable: D-Dcap-cal
      E:
        status: "✓"
        note: "Schedule fold + per-patch monotonic ordering inside @semantos/semantic-objects."
      F:
        status: "✗"
        deliverable: D-F5
      G:
        status: "✗"
        deliverable: D-G5

  - id: A8
    name: Voice (input modality)
    note: |
      Voice is a placeholder surface in the matrix (§2 row A8). The cert-bound
      contract for voice sessions and transcripts is fixed before any
      voice-transcription implementation arrives so that whoever lands the real
      surface inherits a typed, testable boundary. D-A7 lands the stub at
      runtime/intent/src/voice/: createVoiceSession refuses to construct a
      session without a bound BRC-52 cert; addTranscript produces a signed
      Transcript whose signature.keyId equals the speaker's cert_id;
      verifyTranscript re-checks the cert binding and the signature. Session
      ids are deterministic — SHA-256(cert_id ‖ started_at_be_u64), 64-char
      hex — so two transcripts in the same session share a session-bound
      identifier without a server-side session registry.
    axes:
      A:
        status: "✓"
        deliverable: D-A7
        note: |
          D-A7 (Path B, stub) — cert-bound voice-session + transcript
          interface at runtime/intent/src/voice/ (types.ts, preimage.ts,
          voice-session.ts, index.ts). Producer rejects sessions without a
          cert; transcripts carry the speaker's cert_id; signer keyId
          mismatch and bad signatures are rejected; deterministic session id
          derived from (cert_id, started_at). 15 unit tests in
          runtime/intent/src/__tests__/voice-session.test.ts. Future
          voice-transcription work consumes this contract — see deliverables
          D-B7 (transcripts as cells), D-C8 (voice channel speaks
          SignedBundle).
      B:
        status: "✗"
        deliverable: D-B7
      C:
        status: "✗"
        deliverable: D-C8
      D-sub:
        status: "✗"
      D-lex:
        status: "✗"
      D-form:
        status: "n/a"
      D-cap:
        status: "✗"
        deliverable: D-Dcap-world
      E:
        status: "⚠"
        note: "Client-side prediction via Predictor (WASM); state hash not yet verified client-side."
      F:
        status: "✗"
        deliverable: D-F2
      G:
        status: "✗"
        deliverable: D-G2

  - id: A3
    name: Helm / Loom
    note: |
      The convergence surface — the three-panel React workbench
      (currently shipped as `apps/loom-react/`, post-refactor target
      `apps/navigation-app/chat-shell/` per Prompt 11; see
      UNIFICATION-ROADMAP §9 file-path crosswalk) where every
      unification axis becomes user-visible. A3 is canonically "Helm";
      "Loom" is the legacy name still embedded in the existing package
      and directory paths.
      D-A3 (Phase 1b) wires Helm to Plexus identity: Helm boots after
      Plexus has issued a cert; the IdentityStore exposes the active
      hat's cert (getCert / getCertId / whenCertReady) and fires a
      `cert-ready` event; the intent pipeline's `buildHatContext`
      production path requires a real cert, with the dev no-cert stub
      path gated behind the explicit env flag SEMANTOS_DEV_IDENTITY=stub.
      Cert absence in production raises `MissingCertError` whose message
      names the env flag — boot fails fast with a fix-on-the-error.
    axes:
      A:
        status: "✓"
        deliverables:
          - D-A3
        note: |
          D-A3: Helm boots after Plexus issues cert; buildHatContext
          production path requires real cert; dev stub gated behind
          SEMANTOS_DEV_IDENTITY env flag. IdentityStore now exposes
          getCert() / getCertId() / whenCertReady() so authenticated
          backend calls authorise via a real cert; pipeline production
          path raises MissingCertError on cert absence (message names
          the env flag). Tests at runtime/intent/src/__tests__/
          hat-context.test.ts and runtime/services/src/services/
          __tests__/IdentityStore.test.ts pin both halves of the
          contract (production-required + dev-stub-gated).
      B:
        status: "✓"
        note: "LoomObject + cell-backed identity / hat / policy state."
      C:
        status: "⚠"
        deliverable: D-C3
      D-sub:
        status: "⚠"
        deliverable: D-Dsub-helm
      D-lex:
        status: "⚠"
        deliverable: D-Dlex-helm
      D-form:
        status: "⚠"
        deliverable: D-Dform-helm
      D-cap:
        status: "⚠"
        deliverable: D-Dcap-helm
      E:
        status: "⚠"
        deliverable: D-E-helm
      F:
        status: "⚠"
        deliverable: D-F3
      G:
        status: "⚠"
        deliverable: D-G3

  - id: A4
    name: Md Editor (docs)
    note: |
      Markdown / document-editing adapter. Per Unification Roadmap §5 the
      A4 row is the broadest island after A8 (Voice): every axis but B
      starts at ✗. The Md Editor surface itself is in design — only an
      in-progress CodeMirror wrapper exists at
      apps/loom-react/src/helm/MarkdownEditor.tsx. D-A4 (Phase 1b) takes
      Path B from the wave-1.5 brief: it lands the cert-bound stub
      interface that future Md Editor work consumes, ahead of the surface
      itself. This sets axis A to ✓ at the contract level; D-B3, D-C4,
      D-Dsub-md, D-Dlex-md, D-Dcap-md, D-E-md, D-F4 follow in their
      respective phases.
    axes:
      A:
        status: "✓"
        deliverable: D-A4
        note: |
          D-A4 (Path B): MarkdownPatch type carries author_cert_id (==
          computeCertId(cert)) and a DER-ECDSA signature over the
          canonical preimage (sorted-key UTF-8 JSON over
          {authorCertId, content (hex), createdAt, docId, parentPatchId},
          mirroring brc52CertIdPreimage in
          runtime/verifier-sidecar/src/verifier.ts). createPatch rejects
          cert-less authoring (MISSING_CERT) and empty signatures
          (INVALID_SIGNATURE); verifyPatch returns discriminated
          UNKNOWN_AUTHOR / CERT_ID_MISMATCH / INVALID_SIGNATURE /
          MALFORMED_PATCH errors. Implementation in
          extensions/md-editor/ — a new workspace package depending only
          on @plexus/contracts (Brc52Cert + computeCertId from D-A0b);
          SignatureVerifier is a callback seam so the package itself has
          no @bsv/sdk runtime dependency. Future Md Editor surface work
          consumes createPatch / verifyPatch from here without changing
          the contract.
      B:
        status: "⚠"
        deliverable: D-B3
        note: "Md Editor docs as cell-backed (each section/block a cell, document a tree of cells in the VFS) — Phase 4."
      C:
        status: "✗"
        deliverable: D-C4
        note: "Md Editor sync uses SignedBundle — Phase 2."
      D-sub:
        status: "✗"
        deliverable: D-Dsub-md
        note: "Md Editor cells get linearity classification (LINEAR ratified, AFFINE drafts, RELEVANT published, UNRESTRICTED scratch) — Phase 3."
      D-lex:
        status: "✗"
        deliverable: D-Dlex-md
        note: "Md Editor surfaces lexicon-violation diagnostics inline — Phase 3."
      D-form:
        status: "✗"
        deliverable: D-Dform-md
        note: "Md Editor surfaces 'this edit invalidates proof X' warnings — Phase 3."
      D-cap:
        status: "✗"
        deliverable: D-Dcap-md
        note: "Md Editor edits gated by cap.doc.write — Phase 3."
      E:
        status: "✗"
        deliverable: D-E-md
        note: "Per-doc hash chain with branching support (tree-of-chains per Roadmap §8 Q4) — Phase 3b."
      F:
        status: "✗"
        deliverable: D-F4
        note: "Md Editor docs included in recovery export — Phase 5."
      G:
        status: "n/a"
        note: "Metering does not apply to a personal-document editor in v0.5."

  - id: A7
    name: Extensions / Policy Runtime
    note: |
      The extension subsystem — `extensions/policy-runtime/` (host-call
      dispatch + WASM 2-PDA evaluation) and `core/semantos-sir/`
      (semantic IR + lowering pass). A7 straddles substrate and adapter:
      it both consumes identity (cert-bound authorities, axis A) and
      produces lexicons / mints capabilities (axes D-lex / D-cap) for
      every other adapter. D-A6 closes axis A by replacing pre-existing
      "trusted issuer" string fields with a BRC-52-anchored
      `LexiconAuthority` (cert + grammar signature); the lowering pass
      refuses any program whose authority fails verification, and the
      runtime refuses to register an extension whose authority fails at
      `loadExtension` time. Capability scope is keyed on the verified
      `cert_id` — two extensions with distinct cert_ids inhabit
      structurally disjoint OIR domain-flag scopes.
    axes:
      A:
        status: "✓"
        deliverable: D-A6
        note: |
          D-A6: extensions runtime certs lexicon-authority via cert_id.
          `LexiconAuthority` (BRC-52 cert + grammar signature over
          canonical grammar bytes) replaces "trusted issuer" strings.
          `lowerSIRWithAuthority` (core/semantos-sir/) and
          `PolicyRuntime.loadExtension` (extensions/policy-runtime/)
          drive a `BrcVerifier`-shaped `AuthorityVerifier`; failure
          surfaces as `LEXICON_AUTHORITY_INVALID` /
          `GRAMMAR_SIGNATURE_INVALID` at lowering or
          `ExtensionAuthorityError` at load. Capability-scope isolation
          is enforced by emitting the verified `cert_id` as a
          `domainCheck` binding the kernel evaluates per-call;
          cross-authority mints fail `OP_CHECKDOMAINFLAG` because the
          domain-flag value is a different cert_id string.
      B:
        status: "⚠"
        deliverable: D-B6
      C:
        status: "⚠"
        deliverable: D-C7
      D-sub:
        status: "⚠"
        deliverable: D-Dsub-ext
      D-lex:
        status: "✓"
        note: "Lexicon authority is the Lexicon<Cat> typeclass — `core/semantos-sir/src/lexicons.ts` — with Lean injectivity proofs per lexicon. D-A6 closes the cert binding; the typeclass itself was the substrate piece."
      D-form:
        status: "⚠"
        deliverable: D-Dform-ext
      D-cap:
        status: "✓"
        deliverable: D-A6
        note: "Capability mint is gated on the authority cert's verified `cert_id` — the OIR carries a `domainCheck` binding whose flag IS the cert_id, so mints from a different authority's program structurally fail OP_CHECKDOMAINFLAG."
      E:
        status: "⚠"
        deliverable: D-E-ext
      F:
        status: "⚠"
        deliverable: D-F7
      G:
        status: "n/a"

  - id: A6
    name: Settlement (Paskian)
    note: |
      The on-chain settlement adapter — converts MFP channel finals
      into atomic on-chain transactions. ✓ by construction across
      most axes because Settlement IS a UTXO consumer (linear by
      nature). Hydrated 2026-04-29 (canon-bookkeeping pass) from
      docs/prd/UNIFICATION-ROADMAP.md §2b.
    axes:
      A:
        status: "✓"
        note: "Settlement signs every transaction with the user's BRC-52 cert; cert-binding is structural (UTXOs spend under the cert's signing key)."
      B:
        status: "⚠"
        deliverable: D-B5
        note: "Settlement records as cells in the VFS — replaces ad-hoc storage."
      C:
        status: "✓"
        note: "Settlement messages ride BRC-100 envelopes; on-chain broadcasts use the standard BSV transport."
      D-sub:
        status: "✓"
        note: "Linearity is structural — a UTXO is consumed exactly once at the chain layer."
      D-lex:
        status: "n/a"
      D-form:
        status: "n/a"
      D-cap:
        status: "✓"
        note: "Settlement gates on capability UTXOs presented at finalisation time; spending the cap consumes it."
      E:
        status: "✓"
        note: "On-chain ordering provides global time anchor; settlement-sequence numbers monotonic per channel."
      F:
        status: "✓"
        note: "Settled-channel state is recoverable from on-chain history + the recovery payload's channel index."
      G:
        status: "⚠"
        deliverable: D-G3
        note: "MFP integration for atomic on-chain finalisation; Phase 6."

  - id: A9
    name: Jam Room (world-app cartridge)
    note: |
      Collaborative music sequencer running inside a Semantos world region
      (BEAM-backed). Multi-platform: Svelte+three.js web at
      apps/world-apps/jam-room/ (93 src files, v0.2.0); Flutter mobile at
      apps/world-apps/jam-room-mobile/; brain hooks at
      runtime/semantos-brain/src/{jam_clip_state_store,jambox_walkers}.zig.
      Declares 13 jam.* SemanticObjectKind in src/semantic/objects.ts.
      Anchors session snapshots via BSV PushDrop (src/core/anchor.ts).
      First documented world-app cartridge — closes the apps/world-apps/
      doc gap previously flagged in docs/ADAPTER-TAXONOMY.md §9.
      PRD: docs/prd/jam-room/MASTER.md Phases A-G (13–17 weeks, 0/7 shipped).
      Hydrated 2026-05-15 via docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md.
    axes:
      A:
        status: "⚠"
        note: "ownerIdentity + ownerCertId on every JamboxObject header; BRC-52 cert wiring partial."
      B:
        status: "⚠"
        note: "Content-addressed cells via SemanticObjectHeader.previousStateHash; not yet conformance-tested vs cell-relay canonical."
      C:
        status: "⚠"
        note: "CellRelay WebSocket transport; SignedBundle wrapping unverified."
      D-sub:
        status: "⚠"
        note: "linearity field present in SemanticObjectHeader; K1 enforcement at-relay unverified."
      D-lex:
        status: "✗"
        note: "13 jam.* kinds declared in code, not registered with canonical lexicon authority."
      D-form:
        status: "n/a"
        note: "World-app surface; formal proof is U9's domain."
      D-cap:
        status: "✗"
        note: "Blocked on D-Dcap-engine landing BRC-108/115 capability UTXO checks."
      E:
        status: "⚠"
        note: "previousStateHash + DAG helpers in src/core/dag.ts; BEAMClock NTP sync via clock_ping/pong; full anchor chain via PushDrop."
      F:
        status: "✗"
        note: "Plexus recovery wiring not connected."
      G:
        status: "✗"
        note: "Metering channels not opened; jam.world commercial info fields exist but no MFP."

  - id: A10
    name: World-apps directory (doc closure)
    note: |
      Documentation row closing the apps/world-apps/ gap flagged in
      docs/ADAPTER-TAXONOMY.md §9 prior to 2026-05-15. Catalog of
      world-app cartridges (currently jam-room — see A9 — and
      jam-room-mobile + packages/jam_experience companion) is at
      docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md §5.2; characterization of
      world-app cartridge contract at docs/ADAPTER-TAXONOMY.md §7a;
      clean cartridge contract at docs/SHELL-CARTRIDGES-HATS.md §4 "The
      clean cartridge contract — five parts". Not an adapter axis row;
      tracks documentation closure for the world-app cartridge home.
    axes:
      A:
        status: "n/a"
        note: "Documentation closure row, not an adapter axis."
      B:
        status: "n/a"
      C:
        status: "n/a"
      D-sub:
        status: "n/a"
      D-lex:
        status: "n/a"
      D-form:
        status: "n/a"
      D-cap:
        status: "n/a"
      E:
        status: "n/a"
      F:
        status: "n/a"
      G:
        status: "n/a"

  - id: A11
    name: Tessera (care-chain provenance cartridge)
    note: |
      Grape-to-glass-shaped traceability over physically handed-off
      objects whose value depends on a verifiable care chain (wine,
      cold-chain pharma, premium coffee, art transit). Golden-path
      cartridge at cartridges/tessera/ (cartridge.json + brain/),
      mirroring cartridges/oddjobz/. PRD docs/prd/TESSERA-CARTRIDGE.md;
      commission docs/canon/commissions/wave-tessera.md (§8 = the
      end-of-wave target this row converges toward — NOT current
      state). Greenfield (§0.1): zero `tessera` under
      runtime/semantos-brain/src/; build.zig wiring (outside src/) is
      the only brain-side reference, gate-safe per chess. Status below
      is the honest in-progress state, not the §8 target: the
      pre-loader cohort (V0.4 lexicon, V5.2–V5.7 Lean) landed on main;
      the post-loader cohort (V0.3 walkers, V0.5 cells/stores) is
      implemented to the chess-equivalent PRE-BOOT bar — boot-time
      registerAll/Store + octave-registry registration is the
      shared-brain-boot-path step deferred for review (chess parity).
    axes:
      A:
        status: "✗"
        note: "Identity (V4.1 NFC BCA + V5.1) not started."
      B:
        status: "⚠"
        note: "StorageAdapter-consumer contract landed (cartridges/tessera/brain/src/store-adapter.ts, @semantos/protocol-types only; adapter-consumption CI gate green). Concrete adapter injection = deferred boot step. V5.4 blend-conservation Lean proven (pre-loader)."
      C:
        status: "✗"
        note: "Transport (V5.1 NetworkAdapter federation) not started."
      D-sub:
        status: "⚠"
        deliverable: V0.5
        note: "Linearity classes for all 10 cell types machine-checked against the REAL kernel (cartridges/tessera/brain/tessera_cells.zig: linearity.zig checkLinearity + header round-trip, test-substrate green). Octave-registry registration at brain boot is the deferred shared-boot-path step (no pre-boot seam; chess/oddjobz parity)."
      D-lex:
        status: "✓"
        deliverable: V0.4
        note: "TesseraLexicon registered in @semantos/semantos-sir ALL_LEXICONS; cartridges/tessera/brain/src/lexicon.ts re-export; tesseraHeader_injective proven (V5.7). Landed on main (pre-loader)."
      D-form:
        status: "✓"
        note: "Six Lean theorems (tamper_one_shot V5.2, care_score_monotonic V5.3, blend_conservation V5.4, custody_linear V5.5, scan_evidence_present V5.6, tesseraHeader_injective V5.7) proven; landed on main (pre-loader). Domain-layer shadow re-checked in tessera_store.zig."
      D-cap:
        status: "⚠"
        deliverable: V0.3
        note: "13 verb walkers + registerAll over the real verb_dispatcher Registry (cartridges/tessera/brain/tessera_walkers.zig, test-substrate green). Uncapped (chess Phase-1 parity, no §9 cap mirror yet). ✓ requires V0.3+V5.1 + boot threading (deferred)."
      E:
        status: "✓"
        note: "Time/DAG inherited from substrate (passive); no tessera-specific deliverable per §8."
      F:
        status: "⚠"
        note: "Recovery closes passively against substrate F; ✓ after end-to-end pilot (§8 — single post-wave acceptance pass, not a V-row)."
      G:
        status: "⚠"
        note: "Metering: per-scan / per-care-event MFP channels attach in V3 acceptance (§8)."

```
