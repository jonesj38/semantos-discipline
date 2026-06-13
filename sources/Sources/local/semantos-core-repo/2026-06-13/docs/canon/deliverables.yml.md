---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/deliverables.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.625705+00:00
---

# docs/canon/deliverables.yml

```yml
# All per-cell deliverables D-V1, D-A0..7, D-B1..7, D-C1..8, D-Dxxx,
# D-E-*, D-F1..7, D-G1..3 from SEMANTOS-UNIFICATION-ROADMAP.md §5.
# Schema: docs/canon/README.md#deliverablesyml.
#
# Stage: scaffold. Stage 1 imports all 70+ deliverables in structured form.
# Status field is the lifecycle hook: pending → in_progress → merged.
# When a PR lands a deliverable, this file is the canonical record;
# the matrix re-renders accordingly.

deliverables:
  # ── Octave-escalation unification (5-step decomposition, §7 of the design doc) ──
  # Design doc: docs/design/OCTAVE-ESCALATION-UNIFICATION.md
  # All steps target the single unified primitive: inline → octave-escalated → merkle-rooted.
  - id: D-OCT-escalation-descriptor
    title: "Unified escalation descriptor wire format — TS oracle + Zig mirror (NO behaviour change)"
    phase: "1"
    status: merged
    owner: "feat/oct-escalation-descriptor"
    deps: []
    pr_url: "https://github.com/semantos/semantos-core/pull/573"
    notes: |
      Step 1 of 5 in the octave-escalation unification (see design doc §7).
      Defines the 16-byte payload-side escalation descriptor wire format:
        off  size  field          meaning
         0   1     rung           u8: 0=inline, 1=octave-escalated, 2=merkle-rooted-hierarchy
         1   1     octave_level   u8: 0..3 (base 1KiB / kilo 1MiB / mega 1GiB / giga 1TiB)
         2   2     child_count    u16 LE
         4   8     total_bytes    u64 LE (resolves O-1: payload-side source of truth for blob size)
        12   4     reserved       u32 LE: 0
      Total = 16 bytes.
      Resolved design decisions O-1..O-4 baked into module doc-comments.
      TS oracle: core/protocol-types/src/escalation-descriptor.ts (57 tests).
      Zig mirror: core/cell-engine/src/escalation_descriptor.zig (26 tests).
      Both sides agree on CANONICAL_VECTOR / CANONICAL_DESCRIPTOR_BYTES byte-for-byte.
  - id: D-OCT-data-octave-bump
    title: "Wire rung 0→1 for data payloads (retire too_many_continuations, land u64 total_bytes)"
    phase: "1"
    status: merged
    owner: ""
    deps:
      - D-OCT-escalation-descriptor
    pr_url: "https://github.com/semantos/semantos-core/pull/574"
    notes: >
      Step 2 of 5. Octave-0/1 data only.
      Zig: multicell.zig — packEscalated/unpackEscalated/isEscalated + ESCALATION_CELL_COUNT_SENTINEL
        sentinel (0xFFFFFFFF at cell_count offset 86), O-1 total_size=16, 16-byte descriptor at
        payload offset 0, raw child data at buffer offset 1024.
        18 conformance tests in tests/multicell_octave_bump_conformance.zig (454 total passing).
      TS oracle: multicell-assembler.ts — byte-identical mirror; 24 new tests (tests 9-24);
        canonical byte-vector test proves oracle↔mirror agreement; 158 total cell-ops tests passing.
      Public surface: packEscalated, unpackEscalated, isEscalated, ESCALATION_CELL_COUNT_SENTINEL,
        OCTAVE0_FLAT_CAPACITY, OCTAVE1_CELL_SIZE, MAX_CONTINUATIONS, EscalatedObject.
      Backward-compat: rung-0 packMultiCell/unpackMultiCell bytes byte-identical.
      Branch: feat/oct-data-octave-bump.
  - id: D-OCT-merkle-hierarchy
    title: "Rung 1→2 for data: domainPayloadRoot commit + inclusion-proof verifier"
    phase: "1"
    status: merged
    owner: ""
    pr_url: "https://github.com/semantos/semantos-core/pull/576"
    deps:
      - D-OCT-data-octave-bump
    notes: "Step 3 of 5. Removes MAX_CONTINUATIONS=64 hard cap entirely. Hash: single-SHA-256 over full 1024B cells. verifyCellInclusion is the shared verifier step 4 will reuse."
  - id: D-OCT-path-merkle-unify
    title: "Point FLAG_PATH_MERKLE_OVERLOAD at the shared descriptor + verifier"
    phase: "1"
    status: merged
    owner: ""
    pr_url: "https://github.com/semantos/semantos-core/pull/588"
    deps:
      - D-OCT-merkle-hierarchy
    notes: |
      Step 4 of 5. MNCA-LAYER-COLLAPSE-BRIEF line ~429 becomes real.
      Generalised verifyInclusion in cell-merkle.ts + cell_merkle.zig (leaf-size-agnostic).
      New path-merkle TS oracle (core/protocol-types/src/mnca/path-merkle.ts) + 30 tests.
      New path_merkle.zig Zig mirror + 13 tests (needs cell_merkle module).
      routing.zig overload branch inlined (std-only, 12 new tests, all 19 pass).
      build.zig: path_merkle_mod + test-routing + test-path-merkle steps added.
      Canonical root: a3f0c5b3c8eee4209b5870b16efb7ac2619ee29f949fd56b62664711642abb44.
      All pre-existing inline FLAG_PATH_IN_PAYLOAD tests (19 Zig + 12 TS) pass byte-identical.
  - id: D-OCT-octave-2-plus
    title: "Mega/giga octaves — pricing + u64 header total_size semantics"
    phase: "1"
    status: merged
    owner: ""
    deps:
      - D-OCT-escalation-descriptor
    notes: >
      Step 5 of 5. minimumOctaveForSize() selects octave-0/1/2/3; MAX_OCTAVE=3; >1TiB errors.
      packMerkleHierarchy gains octave_level param (Zig positional, TS default-arg for compat).
      O-1 rule (total_size=16 for all rung≥1) enforced uniformly. OCTAVE_LEVEL_{BASE,KILO,MEGA,GIGA}
      constants exported from both Zig and TS oracle. No header bytes added/moved.
      Zig: 542/542; TS: 203/203.

  - id: D-V1
    title: "VerifierStub interface + reference implementation"
    phase: "0.5"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps: []
    pr_url: "https://github.com/semantos/semantos-core/pull/191"
  - id: D-V2
    title: "Codify per-node sidecar topology default"
    phase: "0.5"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps: []
    pr_url: "https://github.com/semantos/semantos-core/pull/192"
  - id: D-V3
    title: "Integrate VerifierStub into World Host UserSocket (incl. sidecar HTTP server)"
    phase: "0.5"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps:
      - D-V1
      - D-V2
    pr_url: "https://github.com/semantos/semantos-core/pull/193"
  - id: D-A0b
    title: "BRC-52 cert flow contract (TS + Elixir)"
    phase: "1a"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps: []
    pr_url: "https://github.com/semantos/semantos-core/pull/194"
  - id: D-A0
    title: "Shared BCA library (TypeScript mirror of Zig)"
    phase: "1a"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps: []
    pr_url: "https://github.com/semantos/semantos-core/pull/195"
  - id: D-A1
    title: "World Host cert-bound identity"
    phase: "1b"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps:
      - D-V3
      - D-A0b
    pr_url: "https://github.com/semantos/semantos-core/pull/200"
  - id: D-A2
    title: "World Client signs every action"
    phase: "1b"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps:
      - D-V3
      - D-A0
      - D-A0b
    pr_url: "https://github.com/semantos/semantos-core/pull/201"
  - id: D-A3
    title: "Helm wires to Plexus identity"
    phase: "1b"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps:
      - D-A0
      - D-A0b
    pr_url: "https://github.com/semantos/semantos-core/pull/198"
  - id: D-A4
    title: "Md Editor patches identify authors via cert_id"
    phase: "1b"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps:
      - D-A0b
    pr_url: "https://github.com/semantos/semantos-core/pull/197"
  - id: D-A5
    title: "Calendar Hat → BRC-52 cert backing migration"
    phase: "1b"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps:
      - D-A0
      - D-A0b
    pr_url: "https://github.com/semantos/semantos-core/pull/202"
  - id: D-A6
    title: "Extensions runtime certs lexicon-authority via cert_id"
    phase: "1b"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps:
      - D-V1
      - D-A0b
    matrix_cell: "A7×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/199"
  - id: D-A7
    title: "Voice input session identifies via BRC-52 (placeholder)"
    phase: "1b"
    status: merged
    owner: "wave-1.5-orchestrator"
    deps:
      - D-A0
      - D-A0b
    pr_url: "https://github.com/semantos/semantos-core/pull/196"
    note: |
      Path B (stub) — no voice transcription is wired in the repo (zero
      hits for transcribe / speechToText / VoiceSession outside D-A7
      itself). Lands the cert-bound interface that future voice work
      consumes at runtime/intent/src/voice/. Surface: createVoiceSession
      (rejects without a cert), addTranscript (signed; keyId == cert_id),
      verifyTranscript (re-checks cert binding + signature). Session id
      is deterministic — SHA-256(cert_id ‖ started_at_be_u64) — so two
      transcripts in the same session share a session-bound id without
      a server-side registry.
      Status flipped to merged 2026-04-29 (canon-bookkeeping pass —
      code merged in 6c10bd0; YAML had not caught up).
  - id: W1.5C-5
    title: "Wave 1.5 docs cleanup — textbook chapters 4/5/14/16/17/18"
    phase: "cleanup"
    status: merged
    owner: "wave-1.5-cleanup-orchestrator"
    deps: []
    pr_url: "https://github.com/semantos/semantos-core/pull/206"
  - id: W1.5C-4
    title: "Fix canon renderer field-access mismatch"
    phase: "cleanup"
    status: merged
    owner: "wave-1.5-cleanup-orchestrator"
    deps: []
    pr_url: "https://github.com/semantos/semantos-core/pull/205"
  - id: W1.5C-2
    title: "(reserved id — no work landed under this number)"
    phase: "cleanup"
    status: superseded
    owner: null
    deps: []
    pr_url: null
    note: |
      Tombstone (added 2026-04-29 canon-bookkeeping pass). The W1.5C-*
      cleanup numbering was assigned reactively at PR time, not from a
      central plan, and this id was never claimed. No git footprint, no
      branch, no commit. Recorded as `superseded` so the gap between
      W1.5C-1 and W1.5C-4 is explicit rather than implicit.
  - id: W1.5C-3
    title: "(reserved id — no work landed under this number)"
    phase: "cleanup"
    status: superseded
    owner: null
    deps: []
    pr_url: null
    note: |
      Tombstone (added 2026-04-29 canon-bookkeeping pass). See W1.5C-2.
  - id: W1.5C-1
    title: "Promote canonical identity types + IdentityProvider to protocol-types"
    phase: "cleanup"
    status: in_progress
    owner: "wave-1.5-cleanup-orchestrator"
    deps: []
    pr_url: "https://github.com/semantos/semantos-core/pull/207"
    note: |
      Promotes Brc52Cert, CertIdPreimage, canonicalCertPreimage, computeCertId,
      SignedBundle<T>, Brc100Headers, CertRegistrationRequest/Result from
      core/plexus-contracts/src/identity.ts → core/protocol-types/src/identity.ts.
      Defines canonical IdentityProvider interface unifying D-A2 (signing) and
      D-A3 (cert-manager) surfaces via CertHandle union type. @plexus/contracts
      re-exports with @deprecated shim for backward compat. IdentityStore
      implements IdentityProvider. EphemeralIdentityProvider updated to import
      from @semantos/protocol-types. Conformance vectors mirrored to canonical
      home. Spec source: docs/spec/protocol-v0.5.md §4 (Identity).

  # ─────────────────────────────────────────────────────────────────
  # Future-phase deliverables — imported 2026-04-29 from
  # docs/prd/UNIFICATION-ROADMAP.md §5. All status: pending until a
  # wave dispatches against them. Each entry carries matrix_cell so
  # the renderer can flow status changes back to the matrix.
  # ─────────────────────────────────────────────────────────────────

  # Phase 2 — Transport (axis C). Parallel after each surface's P1b.
  - id: D-C1
    title: "World Host messages become SignedBundle on the wire"
    phase: "2"
    status: pending
    owner: null
    deps: [D-V1, D-A1]
    matrix_cell: "A1×C"
    pr_url: null
  - id: D-C2
    title: "World Client emits SignedBundle on every action"
    phase: "2"
    status: pending
    owner: null
    deps: [D-A2, D-C1]
    matrix_cell: "A2×C"
    pr_url: null
  - id: D-C3
    title: "Helm uses Plexus Network SDK for backend calls"
    phase: "2"
    status: pending
    owner: null
    deps: [D-A3]
    matrix_cell: "A3×C"
    pr_url: null
  - id: D-C4
    title: "Md Editor sync uses SignedBundle"
    phase: "2"
    status: pending
    owner: null
    deps: [D-A4]
    matrix_cell: "A4×C"
    pr_url: null
  - id: D-C5
    title: "Calendar event sync uses SignedBundle"
    phase: "2"
    status: pending
    owner: null
    deps: [D-A5]
    matrix_cell: "A5×C"
    pr_url: null
  - id: D-C6
    title: "Mesh codec port wraps frames in SignedBundle"
    phase: "2"
    status: pending
    owner: null
    deps: []
    matrix_cell: "U6×C"
    pr_url: null
    note: |
      Five-line change inside the Prompt 38 codec port (the multicast
      adapter split). Without Prompt 38 this would be surgery on a
      793-LOC file.
  - id: D-C7
    title: "Extensions runtime exposes registry via BRC-100 endpoints"
    phase: "2"
    status: pending
    owner: null
    deps: [D-A6]
    matrix_cell: "A7×C"
    pr_url: null
  - id: D-C8
    title: "Voice channel speaks SignedBundle (placeholder)"
    phase: "2"
    status: pending
    owner: null
    deps: [D-A7]
    matrix_cell: "A8×C"
    pr_url: null

  # Phase 3 — Type (axis D, four sub-axes). Parallel after each surface's P1b.
  # D-sub
  - id: D-Dsub-helm
    title: "Helm dispatches actions through K1 pre-check"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A3]
    matrix_cell: "A3×D-sub"
    pr_url: null
  - id: D-Dsub-md
    title: "Md Editor cells get linearity classification"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A4]
    matrix_cell: "A4×D-sub"
    pr_url: null
    note: |
      LINEAR for ratified, AFFINE for drafts, RELEVANT for published,
      UNRESTRICTED for scratch. K1 enforces edits at cell boundaries.
  - id: D-Dsub-cal
    title: "Calendar / Event cells get linearity"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A5]
    matrix_cell: "A5×D-sub"
    pr_url: null
    note: "Events as AFFINE; recurring rules as RELEVANT."
  - id: D-Dsub-ext
    title: "Extension capability cells routed through K1"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A6]
    matrix_cell: "A7×D-sub"
    pr_url: null
  # D-lex
  - id: D-Dlex-world
    title: "World Host validates entity payloads against `world` lexicon"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A1]
    matrix_cell: "A1×D-lex"
    pr_url: null
  - id: D-Dlex-wc
    title: "Client predictor validates outgoing actions against `world` lexicon"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A2]
    matrix_cell: "A2×D-lex"
    pr_url: null
  - id: D-Dlex-helm
    title: "Helm renders cells per lexicon-typed rules"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A3]
    matrix_cell: "A3×D-lex"
    pr_url: null
  - id: D-Dlex-md
    title: "Md Editor surfaces lexicon-violation diagnostics inline"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A4]
    matrix_cell: "A4×D-lex"
    pr_url: null
  - id: D-Dlex-cal
    title: "Calendar lexicon: events, rules, attendees as typed cells"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A5]
    matrix_cell: "A5×D-lex"
    pr_url: null
  - id: D-Dlex-vfs
    title: "VFS path resolution checks lexicon constraints on parent/child relationships"
    phase: "3"
    status: pending
    owner: null
    deps: []
    matrix_cell: "U7×D-lex"
    pr_url: null
  # D-form
  - id: D-Dform-helm
    title: "Helm shows Lean-proof status alongside live cells"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A3]
    matrix_cell: "A3×D-form"
    pr_url: null
  - id: D-Dform-md
    title: "Md Editor surfaces 'this edit invalidates proof X' warnings"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A4]
    matrix_cell: "A4×D-form"
    pr_url: null
  - id: D-Dform-cal
    title: "Calendar recurring-rule consistency checked via Lean (optional)"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A5]
    matrix_cell: "A5×D-form"
    pr_url: null
  - id: D-Dform-ext
    title: "Extension lexicons can carry Lean-proven invariants"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A6]
    matrix_cell: "A7×D-form"
    pr_url: null
  # D-cap
  - id: D-Dcap-world
    title: "World Host capability gating (cap.experience at connect; per-action caps)"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A1, D-V1]
    matrix_cell: "A1×D-cap"
    pr_url: null
  - id: D-Dcap-wc
    title: "Client surfaces capability state in UI"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A2]
    matrix_cell: "A2×D-cap"
    pr_url: null
  - id: D-Dcap-helm
    title: "Helm checks capability before dispatching mutations"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A3]
    matrix_cell: "A3×D-cap"
    pr_url: null
  - id: D-Dcap-md
    title: "Md Editor edits gated by `cap.doc.write`"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A4]
    matrix_cell: "A4×D-cap"
    pr_url: null
  - id: D-Dcap-cal
    title: "Calendar event creation gated by `cap.calendar.write`"
    phase: "3"
    status: pending
    owner: null
    deps: [D-A5]
    matrix_cell: "A5×D-cap"
    pr_url: null

  # Phase 3b — Time (axis E). Parallel anytime after P1b.
  - id: D-E-helm
    title: "Helm subscribes to per-cell tick streams; surfaces hash chain in inspector"
    phase: "3b"
    status: pending
    owner: null
    deps: [D-A3]
    matrix_cell: "A3×E"
    pr_url: null
  - id: D-E-md
    title: "Md Editor per-doc hash chain with branching support (tree-of-chains)"
    phase: "3b"
    status: pending
    owner: null
    deps: [D-A4]
    matrix_cell: "A4×E"
    pr_url: null
    note: "Tree-of-chains semantics (per Roadmap §8 Q4)."
  - id: D-E-cal
    title: "Calendar recurring-rule chain-fork semantics"
    phase: "3b"
    status: pending
    owner: null
    deps: [D-A5]
    matrix_cell: "A5×E"
    pr_url: null
    note: "Chain-forks (per Roadmap §8 Q5) — past instances retain their version."
  - id: D-E-vfs
    title: "VFS directory-mutation chain"
    phase: "3b"
    status: pending
    owner: null
    deps: []
    matrix_cell: "U7×E"
    pr_url: null
  - id: D-E-sir
    title: "SIR documents have a hash chain over their patch sequence"
    phase: "3b"
    status: pending
    owner: null
    deps: []
    matrix_cell: "U8×E"
    pr_url: null
  - id: D-E-ext
    title: "Extension manifests have a hash chain over their version history"
    phase: "3b"
    status: pending
    owner: null
    deps: [D-A6]
    matrix_cell: "A7×E"
    pr_url: null

  # Phase 4 — Storage (axis B). Parallel after each surface's P1b.
  - id: D-B1
    title: "World Host entity state stored as cells, not Elixir maps"
    phase: "4"
    status: pending
    owner: null
    deps: [D-A1]
    matrix_cell: "A1×B"
    pr_url: null
  - id: D-B2
    title: "World Client mirrors authoritative state as cells (via local WASM kernel)"
    phase: "4"
    status: pending
    owner: null
    deps: [D-A2]
    matrix_cell: "A2×B"
    pr_url: null
  - id: D-B3
    title: "Md Editor docs are cell-backed (section/block per cell, doc as VFS tree)"
    phase: "4"
    status: pending
    owner: null
    deps: [D-A4]
    matrix_cell: "A4×B"
    pr_url: null
  - id: D-B4
    title: "Calendar events are cells with `calendar.event` lexicon type"
    phase: "4"
    status: pending
    owner: null
    deps: [D-A5]
    matrix_cell: "A5×B"
    pr_url: null
  - id: D-B5
    title: "Settlement records as cells in the VFS"
    phase: "4"
    status: pending
    owner: null
    deps: []
    matrix_cell: "A6×B"
    pr_url: null
  - id: D-B6
    title: "Extension manifests + capability schemas as cells"
    phase: "4"
    status: pending
    owner: null
    deps: [D-A6]
    matrix_cell: "A7×B"
    pr_url: null
  - id: D-B7
    title: "Voice transcripts and intent extractions as cells (placeholder)"
    phase: "4"
    status: pending
    owner: null
    deps: [D-A7]
    matrix_cell: "A8×B"
    pr_url: null

  # Phase 5 — Recovery (axis F). Sequential after each surface's P1 + P3.
  - id: D-F1
    title: "World Host regions participate in Plexus recovery"
    phase: "5"
    status: pending
    owner: null
    deps: [D-A1, D-B1]
    matrix_cell: "A1×F"
    pr_url: null
  - id: D-F2
    title: "World Client restores from recovery payload on new device"
    phase: "5"
    status: pending
    owner: null
    deps: [D-A2, D-B2]
    matrix_cell: "A2×F"
    pr_url: null
  - id: D-F3
    title: "Helm participates in recovery (layout, open documents)"
    phase: "5"
    status: pending
    owner: null
    deps: [D-A3]
    matrix_cell: "A3×F"
    pr_url: null
  - id: D-F4
    title: "Md Editor docs included in recovery export"
    phase: "5"
    status: pending
    owner: null
    deps: [D-B3]
    matrix_cell: "A4×F"
    pr_url: null
  - id: D-F5
    title: "Calendar events included in recovery export"
    phase: "5"
    status: pending
    owner: null
    deps: [D-B4]
    matrix_cell: "A5×F"
    pr_url: null
  - id: D-F6
    title: "VFS slot/octave index included in recovery export"
    phase: "5"
    status: pending
    owner: null
    deps: []
    matrix_cell: "U7×F"
    pr_url: null
  - id: D-F7
    title: "Extension manifests included in recovery export"
    phase: "5"
    status: pending
    owner: null
    deps: [D-B6]
    matrix_cell: "A7×F"
    pr_url: null
  - id: D-F-sir
    title: "SIR documents included in recovery export"
    phase: "5"
    status: pending
    owner: null
    deps: []
    matrix_cell: "U8×F"
    pr_url: null
  - id: D-F-lean
    title: "Lean proof artifacts included in recovery export"
    phase: "5"
    status: pending
    owner: null
    deps: []
    matrix_cell: "U9×F"
    pr_url: null

  # Phase 6 — Metering (axis G). Sequential after each surface's P1 + P2.
  - id: D-G1
    title: "World Host regions emit MeteringTicks"
    phase: "6"
    status: pending
    owner: null
    deps: [D-A1, D-C1]
    matrix_cell: "A1×G"
    pr_url: null
    note: |
      Each region with paid clients opens an MFP channel (consumes
      Prompt 14's payment-channel ports); each WorldTick optionally
      advances the channel.
  - id: D-G2
    title: "Helm shows live metering state per region/service; recharge UI for low balances"
    phase: "6"
    status: pending
    owner: null
    deps: [D-A3, D-G1]
    matrix_cell: "A3×G"
    pr_url: null
  - id: D-G3
    title: "Settlement integrates with MFP channels for atomic on-chain finalisation"
    phase: "6"
    status: pending
    owner: null
    deps: []
    matrix_cell: "A6×G"
    pr_url: null

  # ─────────────────────────────────────────────────────────────────
  # Wave 2 — Socials extension (D-S1 .. D-S12). Reserved 2026-04-29
  # per docs/design/SOCIALS-EXTENSION-PLAN.md. Substrate prereqs S1→S2
  # →S3→S4 sequential; adapter work S5+ parallel after S4 lands.
  # ─────────────────────────────────────────────────────────────────
  - id: D-S1
    title: "Socials cell type definitions + conformance vectors"
    phase: "S1"
    status: pending
    owner: null
    deps: []
    pr_url: null
    note: |
      Defines social.credential.v1, social.post.v1, social.thread.v1,
      social.engagement.v1 with stable type-hashes and packing-vector
      coverage at packages/socials-types/tests/vectors/social_*.json.
  - id: D-S2
    title: "Capability mint integration with first-boot (cap.social.{publish,delete,config_credential})"
    phase: "S2"
    status: pending
    owner: null
    deps: [D-S1]
    pr_url: null
  - id: D-S3
    title: "SocialPost state machine + kernel-gated transitions"
    phase: "S3"
    status: pending
    owner: null
    deps: [D-S1, D-S2]
    pr_url: null
    note: |
      draft → awaiting_ratification → ratified → published | failed,
      gated at the kernel via OP_ASSERTLINEAR + OP_CHECKDOMAINFLAG.
  - id: D-S4
    title: "SpeechActPolicy in policy-runtime (brand voice / topic gates)"
    phase: "S4"
    status: pending
    owner: null
    deps: [D-S3]
    pr_url: null
  - id: D-S5
    title: "Bluesky adapter (OAuth + publish + delete + engagement poll)"
    phase: "S5"
    status: pending
    owner: null
    deps: [D-S3]
    pr_url: null
    note: "Integration template for subsequent platform adapters."
  - id: D-S6
    title: "Mobile-auth ratification payload type (social.publish.approve)"
    phase: "S6"
    status: pending
    owner: null
    deps: [D-S3]
    pr_url: null
  - id: D-S7
    title: "Helm pending-approvals widget"
    phase: "S7"
    status: pending
    owner: null
    deps: [D-S6]
    pr_url: null
  - id: D-S8
    title: "Engagement webhook receiver + patch-cell schema"
    phase: "S8"
    status: pending
    owner: null
    deps: [D-S5]
    pr_url: null
  - id: D-S9
    title: "X (Twitter) adapter"
    phase: "S9"
    status: pending
    owner: null
    deps: [D-S5]
    pr_url: null
    note: "Idempotency keys = SHA-256(cellHash); paid API tier required."
  - id: D-S10
    title: "LinkedIn adapter"
    phase: "S10"
    status: pending
    owner: null
    deps: [D-S5]
    pr_url: null
  - id: D-S11
    title: "Editorial-calendar composition (calendar extension hook)"
    phase: "S11"
    status: pending
    owner: null
    deps: [D-S6]
    pr_url: null
  - id: D-S12
    title: "Recovery-payload extension for OAuth credentials"
    phase: "S12"
    status: pending
    owner: null
    deps: [D-S1]
    pr_url: null

  # ─────────────────────────────────────────────────────────────────
  # brain substrate — dispatcher unification (D-W1). Reserved 2026-04-30
  # per docs/design/BRAIN-DISPATCHER-UNIFICATION.md. Architectural backbone
  # the oddjobz wave 3 work lands on: one dispatcher mediates every
  # mutation against every brain-managed resource (bearer tokens, sites,
  # modules, headers, sessions, capabilities, identity_certs, files,
  # audit). Transports — in-process shell, Unix-socket CLI-RPC, HTTP/WSS,
  # and (post-D-O5m) SignedBundle mesh — are thin adapters into the
  # dispatcher, not parallel code paths. Resolves the four post-D-O5/O5a
  # brain issues (bearer path divergence, log-not-watched, no OPTIONS, no
  # directory route) as side effects of phased migration.
  # ─────────────────────────────────────────────────────────────────
  - id: D-W1
    title: "brain dispatcher unification — one dispatcher, many transports"
    phase: "W1"
    status: in_progress
    owner: null
    deps: []
    pr_url: null
    note: |
      Five-phase migration:
        Phase 0 — dispatcher core + wire codec + in-process transport
                  (no resources moved yet); ~3 days. ✅ MERGED — PR #269.
        Phase 1 — bearer_tokens + identity_certs + llm.complete +
                  Unix-socket CLI-RPC transport; retires brain issues
                  #1+#2; ~3 days. Required by D-O5p.
                    Part 1 — bearer_tokens handler + Unix socket
                             transport + CLI rewiring + daemon
                             binding.  ✅ MERGED — PR #270.
                    Part 2 — identity_certs handler (substrate for
                             D-O5p) + BKDS leaf derivation + proof
                             verification + brain device list|revoke CLI/
                             REPL surface.  ✅ MERGED — PR #275.
                    Part 3 (follow-up) — llm.complete handler (unblocks
                             D-O6a) + llm.transcribe_audio / llm.embed
                             stubs + brain device pair|claim CLI + REPL
                             surface.  IN FLIGHT — draft PR
                             https://github.com/semantos/semantos-core/pull/281.
        Phase 2 — sites, modules, headers behind dispatcher; ~5 days.
                  Required by D-O7 (substrate cutover) and D-O6 v1.0
                  (canon-aligned chat persistence).
                  IN FLIGHT — draft PR (TBD). Resource handlers shipped:
                  sites_handler.zig (init/route_add/route_remove/
                  set_listen_port/list/get_config/validate), modules_
                  handler.zig (get_hash/verify/list — register/
                  unregister deferred to D-O7's hot-reload story),
                  headers_handler.zig (read MVP: tip/byHeight/byHash/
                  range/sync_state — append_validated deferred until
                  the headers-verifier-WASM-only system-caller auth
                  context lands as its own design step). CLI rewires:
                  `brain hash`, `brain site init|list|validate`,
                  `brain headers tip` all go through the dispatcher;
                  `brain headers serve` HTTP migration deferred per the
                  brief's option-(c). Audit-reads opt-out (§10) lands
                  on the dispatcher with `audit_reads = false` +
                  `is_read_fn` classifier so high-frequency
                  headers.byHeight reads emit a single skip line
                  instead of the full begin/complete pair.
        Phase 3 — HTTP transport polish (OPTIONS preflight, per-site
                  CORS, gzip negotiation on directory routes, optional
                  Content-Security-Policy header); retires brain issues
                  #3+#4. IN REVIEW — draft PR (TBD).
                    Tier 1 (shipped): per-site CORS config in site.json,
                    OPTIONS preflight short-circuit + ACAO/ACAM/ACAH/
                    ACMA emission, CORS-header echo on non-OPTIONS
                    responses (static + directory + API stubs + 404).
                    Wildcard "*" supported; refused at parse time when
                    combined with cors_allow_credentials = true.
                    Directory polish: gzip-sibling fast path (.gz file
                    + Content-Encoding: gzip + Vary: Accept-Encoding)
                    when client sent Accept-Encoding: gzip.
                    Tier 2 (shipped): per-site Content-Security-Policy
                    header (empty default, no header emitted).
                    Tier 3 (deferred, follow-up TODOs): Range request
                    support, full HTTP/1.1 stdlib rewrite, HTTPS
                    termination (operator runs Caddy in front).
        Phase 4 — SignedBundle mesh transport for D-O5m peer nodes
                  and D-O11 federation; ~5 days.
                  IN FLIGHT — draft PR (TBD).  Closes the original
                  D-W1 transport-unification scope: Phases 0-3 + Phase
                  4 cover all four transports spec'd in §5
                  (in-process, Unix socket, HTTP/WSS, SignedBundle
                  mesh).  signed_bundle.zig codec (BRC-52 cert chain
                  + ECDSA-secp256k1-SHA256 + nonce + timestamp +
                  addressed-bundle posture) + transport/signed_bundle
                  .zig HTTP receive seam (POST /api/v1/bundle, opt-in
                  via `brain serve --signed-bundle-endpoint <path>`) +
                  TS sender helper at extensions/oddjobz/tools/send-
                  bundle.ts.  Audit pair fires under
                  transport=signed_bundle.  When this PR merges, D-W1
                  flips to `merged`.
      Phase 0 + Phase 1 = minimum to unblock D-O5p. Phases 2–4 land
      alongside the deliverables that consume them.

  # ─────────────────────────────────────────────────────────────────
  # brain substrate — extension delivery + revocation (D-W2). Reserved
  # 2026-05-02 per docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md.
  # Sister deliverable to D-W1 — D-W1 unified the operator/transport
  # surface (one dispatcher, many transports); D-W2 unifies the
  # extension distribution + integrity surface (one signer model, one
  # delivery substrate, one revocation primitive). Three-tier signer
  # model (platform / tenant-elected / community-future) + Plexus-
  # nullifier-based revocation + shard-proxy as p2p delivery + on-chain
  # bundle commitment as integrity foundation. Software updates and
  # revocation notices use the same code path: signed frames on a
  # shard group, differentiated only by frame type.
  # ─────────────────────────────────────────────────────────────────
  - id: D-W2
    title: "brain extension delivery + revocation (signer tiers, p2p delivery, on-chain integrity)"
    phase: "W2"
    status: in_review
    owner: null
    deps: [D-W1, D-O8]
    pr_url: null
    note: |
      Five-phase migration:
        Phase 0 — `[trusted_signers]` manifest schema extension (~1 day).
                  Extends D-O8's TOML parser. Backward-compatible —
                  manifest with no [trusted_signers] block runs in
                  legacy mode. D-O10 lays down the `platform` entry
                  with `removable = false` at brain creation. This
                  phase makes brains forward-compat with the runtime
                  work below.
        Phase 1 — Extension publishing flow (~3 days).
                  Phase 1: IN FLIGHT — draft PR (TBD).
                  `brain extension publish` constructs OP_RETURN-bearing
                  tx (commits bundle hash), broadcasts via ARC,
                  publishes bundle bytes to the derived shard group via
                  the TS shard-proxy helper at extensions/oddjobz/
                  tools/publish-bundle.ts.  Cross-language seam: Zig
                  owns tx + signing + ARC; TS owns BRC-12 framing +
                  UDP push.  D-W2 itself stays `pending` until all
                  phases land; this status note tracks Phase 1 only.
        Phase 2 — Subscription + receive + verify + apply (~3 days).
                  Phase 2: IN FLIGHT — draft PR (TBD).
                  `runtime/semantos-brain/src/extension_subscriber.zig` ships
                  the §5.2 verify pipeline (decode → SPV → hash →
                  sig → signer → scope) + applyVerifiedFrame
                  (writes <data_dir>/extensions/<ns>/<v>/bundle.bin,
                  hot-registers via dispatcher).
                  `runtime/semantos-brain/src/transport/extension_subscribe.zig`
                  is the transport-agnostic processFrame core +
                  POST /api/v1/bundle-frame HTTP wrapper (mirrors
                  D-W1 Phase 4's signed_bundle pattern).
                  TS sidecar at extensions/oddjobz/tools/subscribe-
                  bundles.ts joins each trusted-signer multicast
                  group + forwards received BRC-12 frames to brain.
                  Late-joiner replayHistorical interface
                  implemented; v0.1 SPV client + ReplaySource are
                  deny-all stubs (production wires real BSV-node
                  adapters per the runbook). Phases 3-4 (nullifier
                  + quarantine) are the next deliverable.
        Phase 3 — Nullifier + rotation flow (~2 days).
                  Phase 3: IN FLIGHT — draft PR (TBD).
                  Plexus nullifier tx with replacement-key payload
                  signed by rotation authority; atomic revoke +
                  promote. CLIs: `brain signer rotate`,
                  `brain signer revoke`.
                  `runtime/semantos-brain/src/extension_nullifier.zig` ships the
                  §4.2-§4.3 codec + verify + apply (manifest text
                  rewrite + revoked-keys index).  Receive pipeline
                  switches on frame_type — bundle frames take the
                  Phase 2 path, nullifier frames take the new path.
                  Same `POST /api/v1/bundle-frame` HTTP wire; inner
                  payload tag (`extension-bundle-v1` vs.
                  `nullifier-frame-v1`) selects the dispatch.
                  CLI verbs construct + sign + broadcast the
                  Plexus nullifier tx; rotation case adds the
                  rotation-authority signature over
                  `sha256d(revoked || replacement || ts)`.
                  v0.1: platform-tier revocations ALLOWED on the
                  on-chain path (the operator's own rotation
                  authority is the legitimate revoker; the
                  hand-edit-refusal path stays for direct manifest
                  edits).  Audit log carries CRITICAL warning on
                  platform-tier revocation events.
        Phase 4 — Quarantine runtime behaviour (~2 days).
                  Phase 4: IN REVIEW — draft PR (TBD).
                  Default on revocation: extensions installed under
                  the revoked key are disabled (dispatcher routes
                  return `error.handler_quarantined`, mapped to 503
                  Service Unavailable on wire transports), files
                  preserved on disk.  `brain extension quarantine
                  list|evaluate|remove` operator surface (CLI + REPL)
                  drives the state machine.  `quarantine_on_revoke
                  = false` opts into hard-delete on the revoke path.
                  `runtime/semantos-brain/src/extension_quarantine.zig` ships
                  the four-state machine (active / quarantined /
                  pending_evaluation / removed) + the persistent
                  JSON-lines index at <data_dir>/extension-
                  quarantine.json + the per-extension meta.json
                  (signer pubkey + publish txid + applied_at) the
                  apply path now writes to identify which installs
                  belong to a revoked signer.  Phase 3's
                  `applyNullifier` gains a `applyNullifierWith
                  Quarantine` wrapper that drives the bulk-quarantine
                  walk after the manifest mutation.  Dispatcher
                  gains `markQuarantined` / `unmarkQuarantined` /
                  `isQuarantined` + the typed
                  `error.handler_quarantined` dispatch outcome.
                  Phase 4 closes D-W2's full scope: with this PR
                  merged, D-W2's status flips from in_review →
                  merged.
      Total: ~11 days estimated. Phase 0 lands first (parallel-
      mergeable with D-O10). Phases 1-4 sequence after.

  # ─────────────────────────────────────────────────────────────────
  # Wave 3 — Oddjobz extension (D-O1 .. D-O11 + D-O5p, D-O5m). Reserved
  # 2026-04-29 per docs/design/ODDJOBZ-EXTENSION-PLAN.md (v0.2). Carves
  # the existing Next.js OJT prototype into extensions/oddjobz/ with
  # dual operator surfaces: Svelte desktop helm (D-O5) and Flutter
  # mobile shell as a peer node (D-O5p pairing + D-O5m mobile shell).
  # The Flutter shell consumes src/ffi/exports.zig wasm32 build via
  # dart:ffi; phone is a real Semantos peer in the operator's
  # identity DAG, not a thin client.
  # ─────────────────────────────────────────────────────────────────
  - id: D-O1
    title: "Trades lexicon formalisation (Lean + TS + canon)"
    phase: "O1"
    status: in_review
    owner: null
    deps: []
    pr_url: null
    note: |
      Promotes existing schema.trades.ts to the canonical Trades
      lexicon with Lean spec at proofs/lean/Semantos/Lexicons/Trades.lean
      (tradesHeader_injective, lake build clean, no sorry/admit), TS
      authority at core/semantos-sir/src/lexicons.ts (TradesLexicon +
      TradesCategory + ALL_LEXICONS registration), and re-export at
      extensions/oddjobz/src/lexicon.ts mirroring the calendar pattern.
      Adds docs/canon/lexicons.yml entry id: trades. The 8 categories
      (lead, estimate, quote, dispatch, visit, invoice, settle,
      message) cover every §O4 FSM transition and §O3 cap-gated
      discourse act.
  - id: D-O2
    title: "Oddjobz cell types + conformance vectors"
    phase: "O2"
    status: merged
    owner: null
    deps: [D-O1]
    pr_url: "https://github.com/semantos/semantos-core/pull/276"
    note: |
      8 types: oddjobz.{job,quote,visit,invoice,customer,site,
      estimate,message}.v1 with stable type-hashes and packing
      vectors at extensions/oddjobz/tests/vectors/.
      Landed without D-O1 (soft dep) — cell-type identity is
      namespaced oddjobz.* and does not depend on lexicon authority
      for type-hash stability. D-O1 will replace the
      extensions/oddjobz/src/lexicon.ts stub with the canonical
      TradesLexicon authority + Lean obligations.
      Linearity wire-codes use the kernel's canonical numbering
      (1=LINEAR, 2=AFFINE, 3=RELEVANT, 4=DEBUG) per Cell.lean +
      core/cell-engine/src/linearity.zig — protocol-v0.5 §3.4
      stale-spec erratum landed in PR #277.
  - id: D-O3
    title: "Oddjobz capability mints (cap.oddjobz.{quote,dispatch,invoice,close,write_customer,public_chat_serve})"
    phase: "O3"
    status: in_progress
    owner: null
    deps: [D-O2]
    pr_url: null
    note: |
      Six caps with canonical, page-aligned domain flags on the oddjobz
      page 0x000101xx in the Plexus client-sovereignty tier (per
      client-spec requirement 2.2.2 + tech-spec §30) — flags
      0x00010101..0x00010106 in declaration order quote/dispatch/
      invoice/close/write_customer/public_chat_serve. The page-aligned
      scheme lines up with `runtime/shell/src/capabilities.ts` (loom-
      shell verbs at 0x000100xx) so any deployment of this extension
      uses identical numbers. Manifest at
      extensions/oddjobz/src/manifest.ts; first-boot integration in
      runtime/semantos-brain/src/extensions.zig (called from cmdServe's existing
      post-cert-init phase — no new top-level boot step per §9.8).
      Conformance vectors at
      extensions/oddjobz/tests/vectors/capabilities/. Lean obligation
      at proofs/lean/Semantos/Capabilities/Oddjobz.lean specialises
      DomainIsolationK3 to the six caps and proves §2.5 hat-isolation
      cryptographically via BKDS injectivity-in-context_tag + ECDSA
      EUF-CMA (axioms in proofs/lean/Semantos/CryptoAxioms.lean
      mirroring the production BKDS invoice format from
      runtime/semantos-brain/src/bkds.zig). Initial 6 commits shipped the
      0x4F4A_<ordinal> scheme + structural hat-isolation; follow-up
      commits on the same branch flipped to the canonical page-aligned
      scheme and replaced the structural proof with the cryptographic
      one.
  - id: D-O4
    title: "Oddjobz state machines + kernel-gated transitions"
    phase: "O4"
    status: done
    owner: null
    deps: [D-O2, D-O3]
    pr_url: null
    note: |
      Job FSM (lead → quoted → scheduled → in_progress →
      completed → invoiced → paid → closed); Quote FSM
      (draft → presented → {accepted|rejected|expired|superseded});
      Visit FSM (scheduled → in_progress → completed | cancelled);
      Invoice FSM (draft → sent → {viewed, partial, paid, overdue,
      cancelled}). TS modules at extensions/oddjobz/src/state-machines/
      (job-fsm.ts, quote-fsm.ts, visit-fsm.ts, invoice-fsm.ts,
      kernel-gate.ts shared verifier stub, index.ts registry). Lean
      specs at proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/
      (Common.lean + per-FSM totality + K1 + K2 + K4 theorems with
      no `sorry`/`admit`). Three §O4 acceptance tests
      (`[§O4 K1/K2/K4]`-tagged in test titles): K2 — quoted →
      scheduled WITHOUT cap.oddjobz.dispatch fails at the kernel
      gate; K1 — two quoted → scheduled on the same Job cell-id
      fail on the second; K4 — induced HTTP failure on
      invoiced → paid leaves cell byte-for-byte unchanged AND retry
      succeeds. Conformance vectors at
      extensions/oddjobz/tests/vectors/state-machines/ (32
      transition vectors total). The TS-layer kernel-gate is a
      verifier stub (in-memory ConsumedCellSet for K1, structural
      domain-flag check for K3a) so D-O4 lands ahead of D-O7's
      substrate-truth cutover; the Lean specs carry the
      substrate-level guarantees by specialising K1 (LinearityK1)
      and K2 (AuthSoundnessK2) to the per-FSM transition tables.

      D-O4 followup-1 — the Semantos Brain-side Zig port of the Job FSM lands as
      `runtime/semantos-brain/src/job_fsm.zig` + the typed `jobs.transition`
      dispatcher resource + helm action buttons on both surfaces.
      See `D-O4.followup-1-job-fsm-cutover` for the closed_by_pr.

      D-O4 followup-2 — the Semantos Brain-side Zig port of the Visit FSM lands
      as `runtime/semantos-brain/src/visit_fsm.zig` + the typed `visits.*`
      dispatcher resource (find / create / find_by_id / transition,
      with FK validation against the jobs store on create) + helm
      surfaces on both helms (loom-svelte VisitList / VisitDetail
      tabs; oddjobz-mobile VisitListScreen / VisitDetailScreen + a
      Visits section under JobDetail).  See `D-O4.followup-2-visit-
      fsm-cutover` for the closed_by_pr.

      D-O4 followup-3 — the Semantos Brain-side Zig port of the Quote FSM lands
      as `runtime/semantos-brain/src/quote_fsm.zig` + the typed `quotes.*`
      dispatcher resource (find / create / find_by_id / transition,
      with FK validation against the jobs store on create) + helm
      surfaces on both helms (loom-svelte QuoteList / QuoteDetail
      tabs; oddjobz-mobile QuoteListScreen / QuoteDetailScreen + a
      Quotes section under JobDetail).  See `D-O4.followup-3-quote-
      fsm-cutover` for the closed_by_pr.

      D-O4 followup-4 — the Semantos Brain-side Zig port of the Invoice FSM
      lands as `runtime/semantos-brain/src/invoice_fsm.zig` + the typed
      `invoices.*` dispatcher resource (find / create / find_by_id /
      transition, with FK validation against the jobs store on
      create) + helm surfaces on both helms (loom-svelte InvoiceList
      / InvoiceDetail tabs; oddjobz-mobile InvoiceListScreen /
      InvoiceDetailScreen + an Invoices section under JobDetail).
      See `D-O4.followup-4-invoice-fsm-cutover` for the closed_by_pr.

      All 4 of 4 FSMs (Job + Visit + Quote + Invoice) are now
      brain-side.  Cross-language parity is enforced for every FSM
      via the canonical `<fsm>_fsm.json` oracle driven through the
      Zig dispatcher.  D-O4 itself flips to `done` here — the
      original TS-layer K1 / K2 / K4 acceptance tests still hold,
      and every transition table is now mirrored on the Semantos Brain side
      with a parity proof attached.

  - id: D-O4.followup-1-job-fsm-cutover
    title: "brain-side Zig port of Job FSM + jobs.transition dispatcher resource"
    phase: "O4"
    status: done
    owner: null
    deps: [D-O4]
    pr_url: null
    note: |
      Closes the Semantos Brain-side Job FSM cutover.  Pre-followup-1 the helms
      (loom-svelte JobList/CustomerList/Calendar/Attention + oddjobz-
      mobile equivalents) could READ + CREATE jobs through the
      typed dispatcher resources from #307 / #308 / #310 — but the
      FSM only had a TS implementation and no brain-side substrate, so
      every job stayed in `lead` forever.

      Shipped:
        • runtime/semantos-brain/src/job_fsm.zig — port of the canonical seven-
          row JOB_TRANSITIONS table + `validateTransition` (mirror of
          extensions/oddjobz/src/state-machines/job-fsm.ts; field
          name capRequired → cap_required, same value semantics).
        • runtime/semantos-brain/src/resources/jobs_handler.zig — `jobs.transition`
          command (dispatcher-gated on cap.oddjobz.read_jobs; per-row
          caps validated inside the handler against ctx.capabilities
          and surfaced as typed JSON bodies on mismatch).
        • runtime/semantos-brain/src/jobs_store_fs.zig — `updateState` op +
          `appendUpdated` log-line + `applyLogLine` `updated`-kind
          replay support.
        • runtime/semantos-brain/src/repl.zig — `quote job <id>`, `schedule
          job <id> [--at X]`, `start job <id>`, `complete job <id>`,
          `invoice job <id>`, `mark job paid <id>`, `close job <id>`
          + generic `transition job <id> <to_state> [--cap X]`.
        • runtime/semantos-brain/tests/jobs_handler_conformance.zig — 16+ new
          tests including a cross-language parity oracle that drives
          the canonical job_fsm.json conformance vector through the
          Zig dispatcher.
        • apps/oddjobz-mobile/lib/src/repl/jobs_repository.dart —
          7 typed transition methods (quoteJob / scheduleJob / etc.)
          + JobTransitionResult sealed type.
        • apps/oddjobz-mobile/lib/src/helm/job_detail_screen.dart —
          state-aware action buttons.
        • apps/loom-svelte/src/views/JobDetail.svelte — new view
          with the same state-aware button surface.
        • apps/loom-svelte/tests/job-detail-parse.test.ts — parser
          tests for the transition response shape.
        • Glossary: job-transition-resource, job-fsm-zig-port,
          cross-language-fsm-parity.

      Future PRs close the equivalent followups for Quote / Visit /
      Invoice FSMs (D-O4.followup-2 / -3 / -4 reserved).

  - id: D-O4.followup-2-visit-fsm-cutover
    title: "brain-side Zig port of Visit FSM + visits.* dispatcher resource"
    phase: "O4"
    status: done
    owner: null
    deps: [D-O4, D-O4.followup-1-job-fsm-cutover]
    pr_url: null
    note: |
      Closes the Semantos Brain-side Visit FSM cutover.  Sequential mirror of
      D-O4.followup-1 (Job FSM cutover) for `oddjobz.visit.v1` cells;
      Visits link to Jobs (FK) and represent operator site events.

      Shipped:
        • runtime/semantos-brain/src/visit_fsm.zig — port of the canonical four-
          row VISIT_TRANSITIONS table + `validateTransition` (mirror
          of extensions/oddjobz/src/state-machines/visit-fsm.ts).
        • runtime/semantos-brain/src/visits_store_fs.zig — JSONL store +
          findAll / findById / findByJobId / updateState; uses heap-
          stable per-record OwnedStrings (sidesteps the cross-record
          dangling-slice hazard tracked separately for the older
          jobs/customers stores).
        • runtime/semantos-brain/src/resources/visits_handler.zig —
          visits.find / find_by_id / create (with FK validation
          against the jobs store, returning typed
          `{error: "job_not_found", job_id}` on miss) / transition
          (dispatcher-gated on cap.oddjobz.read_visits; per-FSM-row
          caps checked inside the handler — every Visit row is
          ungated today but the shape mirrors jobs.transition).
        • cap.oddjobz.read_visits (0x00010109) +
          cap.oddjobz.write_visit (0x0001010A) added with conformance
          vectors at extensions/oddjobz/tests/vectors/capabilities/.
        • runtime/semantos-brain/src/repl.zig — `find visits [--job-id <id>]`,
          `find visit <id>`, `add visit --job <id> --type <type>
          [--notes "..."]`, plus FSM verbs (`start visit <id>`,
          `complete visit <id> [--outcome X]`, `cancel visit <id>`)
          and a generic `transition visit <id> <to_state>` fallback.
        • runtime/semantos-brain/src/cli.zig — VisitsStoreFs wired in cmdRepl +
          cmdServe alongside JobsStoreFs and CustomersStoreFs.
        • runtime/semantos-brain/tests/visits_handler_conformance.zig — ~17
          new tests covering FK validation, every FSM transition,
          typed errors (not_reachable, wrong_principal,
          unknown_state, not_found), idempotent already_in_state,
          cap-gating, audit-pair invariant, and the cross-language
          parity oracle driven from visit_fsm.json.
        • extensions/oddjobz/tests/capabilities.test.ts — updated
          for the 10-cap shape (was 8).
        • apps/oddjobz-mobile/lib/src/repl/visits_repository.dart —
          VisitsRepository + sealed VisitTransitionResult /
          VisitCreateResult types + 4 transition wrappers
          (startVisit, completeVisit, cancelVisit, transitionVisit).
        • apps/oddjobz-mobile/lib/src/helm/visit_list_screen.dart +
          visit_detail_screen.dart — new screens with state-aware
          action buttons.
        • apps/oddjobz-mobile/lib/src/helm/job_detail_screen.dart —
          new "Visits" section listing visits for the parent job
          plus a "Schedule visit" CTA driving visits.create.
        • apps/oddjobz-mobile/lib/src/helm/home_screen.dart — Visits
          tab (bottom nav grew 5 → 6).
        • apps/loom-svelte/src/views/VisitList.svelte +
          VisitDetail.svelte — new views.
        • apps/loom-svelte/src/views/JobDetail.svelte — visits-
          for-this-job section.
        • apps/loom-svelte/src/App.svelte — Visits tab.
        • apps/loom-svelte/tests/visit-list-parse.test.ts +
          visit-detail-parse.test.ts — parser tests.
        • apps/oddjobz-mobile/test/repl/visits_repository_test.dart —
          parser + transition + create response shape tests.
        • Glossary: find-visits-resource, visits-store,
          visit-fsm-zig-port, oddjobz-cap-read-visits,
          oddjobz-cap-write-visit.

      Result: 2 of 4 oddjobz FSMs are now brain-side (Job + Visit).
      Quote and Invoice FSMs are tracked as D-O4.followup-3 / -4.

  - id: D-O4.followup-3-quote-fsm-cutover
    title: "brain-side Zig port of Quote FSM + quotes.* dispatcher resource"
    phase: "O4"
    status: done
    owner: null
    deps: [D-O4, D-O4.followup-2-visit-fsm-cutover]
    pr_url: null
    note: |
      Closes the Semantos Brain-side Quote FSM cutover.  Sequential mirror of
      D-O4.followup-2 (Visit FSM cutover) for `oddjobz.quote.v1` cells;
      Quotes link to Jobs (FK) and represent priced offers.

      Shipped:
        • runtime/semantos-brain/src/quote_fsm.zig — port of the canonical six-
          row QUOTE_TRANSITIONS table + `validateTransition` (mirror
          of extensions/oddjobz/src/state-machines/quote-fsm.ts).
        • runtime/semantos-brain/src/quotes_store_fs.zig — JSONL store +
          findAll / findById / findByJobId / updateState; uses heap-
          stable per-record OwnedStrings (sidesteps the cross-record
          dangling-slice hazard tracked separately for the older
          jobs/customers stores).  Cost fields are i64 cents so the
          canonical TS shape's `costMin`/`costMax` round-trip without
          precision loss.
        • runtime/semantos-brain/src/resources/quotes_handler.zig —
          quotes.find / find_by_id / create (with FK validation
          against the jobs store, returning typed
          `{error: "job_not_found", job_id}` on miss) / transition
          (dispatcher-gated on cap.oddjobz.read_quotes; per-FSM-row
          caps checked inside the handler — every Quote row is
          ungated today but the shape mirrors visits.transition).
        • cap.oddjobz.read_quotes (0x0001010B) +
          cap.oddjobz.write_quote (0x0001010C) added with conformance
          vectors at extensions/oddjobz/tests/vectors/capabilities/.
        • runtime/semantos-brain/src/repl.zig — `find quotes [--job-id <id>]`,
          `find quote <id>`, `add quote --job <id> [--cost-min N]
          [--cost-max N] [--notes "..."]`, plus FSM verbs (`present
          quote <id>`, `accept quote <id>`, `decline quote <id>
          [--reason X]`, `expire quote <id>`, `supersede quote <id>`)
          and a generic `transition quote <id> <to_state>` fallback.
        • runtime/semantos-brain/src/cli.zig — QuotesStoreFs wired in cmdRepl +
          cmdServe alongside JobsStoreFs / CustomersStoreFs /
          VisitsStoreFs.
        • runtime/semantos-brain/tests/quotes_handler_conformance.zig — ~20
          new tests covering FK validation, every FSM transition,
          typed errors (not_reachable, wrong_principal,
          unknown_state, not_found), idempotent already_in_state,
          cap-gating, audit-pair invariant, and the cross-language
          parity oracle driven from quote_fsm.json.
        • extensions/oddjobz/tests/capabilities.test.ts — updated
          for the 12-cap shape (was 10).
        • apps/oddjobz-mobile/lib/src/repl/quotes_repository.dart —
          QuotesRepository + sealed QuoteTransitionResult /
          QuoteCreateResult types + 5 transition wrappers
          (presentQuote, acceptQuote, declineQuote, expireQuote,
          supersedeQuote, transitionQuote).
        • apps/oddjobz-mobile/lib/src/helm/quote_list_screen.dart +
          quote_detail_screen.dart — new screens with state-aware
          action buttons (draft → Present + Supersede; presented →
          Accept + Decline + Expire + Supersede).
        • apps/oddjobz-mobile/lib/src/helm/job_detail_screen.dart —
          new "Quotes" section listing quotes for the parent job
          plus a "Create quote" CTA driving quotes.create.
        • apps/oddjobz-mobile/lib/src/helm/home_screen.dart — Quotes
          tab (bottom nav grew 6 → 7).
        • apps/loom-svelte/src/views/QuoteList.svelte +
          QuoteDetail.svelte — new views.
        • apps/loom-svelte/src/views/JobDetail.svelte — quotes-
          for-this-job section.
        • apps/loom-svelte/src/App.svelte — Quotes tab.
        • apps/loom-svelte/tests/quote-list-parse.test.ts +
          quote-detail-parse.test.ts — parser tests.
        • apps/oddjobz-mobile/test/repl/quotes_repository_test.dart —
          parser + transition + create response shape tests.
        • Glossary: find-quotes-resource, quotes-store,
          quote-fsm-zig-port, oddjobz-cap-read-quotes,
          oddjobz-cap-write-quote.

      Result: 3 of 4 oddjobz FSMs are now brain-side (Job + Visit +
      Quote).  Invoice FSM is tracked as D-O4.followup-4.

  - id: D-O4.followup-4-invoice-fsm-cutover
    title: "brain-side Zig port of Invoice FSM + invoices.* dispatcher resource"
    phase: "O4"
    status: done
    owner: null
    deps: [D-O4, D-O4.followup-3-quote-fsm-cutover]
    pr_url: null
    note: |
      Closes the Semantos Brain-side Invoice FSM cutover.  Sequential mirror of
      D-O4.followup-3 (Quote FSM cutover) for `oddjobz.invoice.v1`
      cells; Invoices link to Jobs (FK) and represent billing cells.
      This is the FOURTH and FINAL FSM cutover — after this PR all 4
      oddjobz FSMs (Job + Visit + Quote + Invoice) are brain-side.

      Shipped:
        • runtime/semantos-brain/src/invoice_fsm.zig — port of the canonical
          fifteen-row INVOICE_TRANSITIONS table + `validateTransition`
          (mirror of extensions/oddjobz/src/state-machines/
          invoice-fsm.ts).
        • runtime/semantos-brain/src/invoices_store_fs.zig — JSONL store +
          findAll / findById / findByJobId / updateState; uses
          heap-stable per-record OwnedStrings (sidesteps the
          cross-record dangling-slice hazard tracked separately for
          the older jobs/customers stores).  Amount fields are i64
          cents so the canonical TS shape's `amount` /
          `amountPaid` round-trip without precision loss.
        • runtime/semantos-brain/src/resources/invoices_handler.zig —
          invoices.find / find_by_id / create (with FK validation
          against the jobs store, returning typed
          `{error: "job_not_found", job_id}` on miss) / transition
          (dispatcher-gated on cap.oddjobz.read_invoices; per-FSM-row
          caps checked inside the handler — every Invoice row is
          ungated today but the shape mirrors quotes.transition).
        • cap.oddjobz.read_invoices (0x0001010D) +
          cap.oddjobz.write_invoice (0x0001010E) added with
          conformance vectors at extensions/oddjobz/tests/vectors/
          capabilities/.
        • runtime/semantos-brain/src/repl.zig — `find invoices [--job-id <id>]`,
          `find invoice <id>`, `add invoice --job <id> [--amount N]
          [--notes "..."]`, plus FSM verbs (`send invoice <id>`,
          `mark invoice paid <id> [--amount N]`, `mark invoice
          partial <id> --amount N`, `mark invoice viewed <id>`, `mark
          invoice overdue <id>`, `cancel invoice <id>`, `void invoice
          <id>` alias) and a generic `transition invoice <id>
          <to_state>` fallback.
        • runtime/semantos-brain/src/cli.zig — InvoicesStoreFs wired in cmdRepl
          + cmdServe alongside JobsStoreFs / CustomersStoreFs /
          VisitsStoreFs / QuotesStoreFs.
        • runtime/semantos-brain/tests/invoices_handler_conformance.zig — ~20
          new tests covering FK validation, every FSM transition
          (draft → sent / cancelled; sent → viewed / partial / paid
          / overdue / cancelled; viewed → partial / paid / overdue /
          cancelled; partial → paid / overdue; overdue → paid /
          partial), typed errors (not_reachable, wrong_principal,
          unknown_state, not_found), idempotent already_in_state,
          cap-gating, audit-pair invariant, and the cross-language
          parity oracle driven from invoice_fsm.json (15
          transitions).
        • extensions/oddjobz/tests/capabilities.test.ts — updated
          for the 14-cap shape (was 12).
        • apps/oddjobz-mobile/lib/src/repl/invoices_repository.dart
          — InvoicesRepository + sealed InvoiceTransitionResult /
          InvoiceCreateResult types + 6 transition wrappers
          (sendInvoice, markPaid, markPartial, markViewed,
          markOverdue, cancelInvoice, transitionInvoice).
        • apps/oddjobz-mobile/lib/src/helm/invoice_list_screen.dart
          + invoice_detail_screen.dart — new screens with
          state-aware action buttons.
        • apps/oddjobz-mobile/lib/src/helm/job_detail_screen.dart —
          new "Invoices" section listing invoices for the parent
          job plus a "Create invoice" CTA driving invoices.create.
        • apps/oddjobz-mobile/lib/src/helm/home_screen.dart —
          Invoices tab (bottom nav grew 7 → 8).
        • apps/loom-svelte/src/views/InvoiceList.svelte +
          InvoiceDetail.svelte — new views.
        • apps/loom-svelte/src/views/JobDetail.svelte — invoices-
          for-this-job section.
        • apps/loom-svelte/src/App.svelte — Invoices tab.
        • apps/loom-svelte/tests/invoice-list-parse.test.ts +
          invoice-detail-parse.test.ts — parser tests.
        • apps/oddjobz-mobile/test/repl/invoices_repository_test.dart
          — parser + transition + create response shape tests.
        • Glossary: find-invoices-resource, invoices-store,
          invoice-fsm-zig-port, oddjobz-cap-read-invoices,
          oddjobz-cap-write-invoice.

      Result: All 4 oddjobz FSMs are now brain-side (Job + Visit +
      Quote + Invoice) — closes the Semantos Brain-side cutover of the entire
      §O4 FSM canon.  D-O4 itself flips to `done` in the same PR.

  - id: D-O5
    title: "Desktop helm SPA wired to existing tenant"
    phase: "O5"
    status: in_progress
    owner: null
    deps: [D-O4]
    pr_url: null
    note: |
      MVP shipped: RouteType.directory landed in site_config +
      site_server (closes brain issue #274), apps/loom-svelte rewired
      from runtime-services demo into a real helm SPA shell with
      JobList view backed by the bearer-gated POST /api/v1/repl
      endpoint, identity-cert gate via WSITE3 + bearer-token capture
      from /auth/callback redirect.  Operator-deploy script lives
      at runtime/semantos-brain/deploy/oddjobz-helm-deploy.sh.

      Tier-2 deferrals tracked as D-O5.followup-N:
        1. Typed dispatcher resource for `find_jobs` — DONE (closes
           D-O5.followup-1 + D-O5m.followup-4 together; closed_by_pr:
           feat/d-o5-followup-1-typed-find-jobs).  Shipped:
           runtime/semantos-brain/src/jobs_store_fs.zig + resources/
           jobs_handler.zig + REPL `find jobs [--state X]` / `find
           job <id>` / `add job <name> <state> [scheduled-at]` verbs
           + cap.oddjobz.read_jobs cap mint at 0x00010107.  Both
           helms (loom-svelte JobList + oddjobz-mobile
           JobsRepository) consume the typed JSON branch verbatim
           per the integration tests at apps/loom-svelte/tests/
           job-list-parse.test.ts + apps/oddjobz-mobile/test/repl/
           jobs_repository_test.dart.
        2. brain-side mint of bearer alongside the session cookie at
           /auth/callback — DONE (closes D-O5.followup-2; closed_by_pr:
           feat/d-o5-followup-2-bearer-mint).  The /auth/callback
           handler now mints a helm bearer via
           `bearer_tokens.TokenStore.issue("helm-cookie", ttl)` and
           emits two Set-Cookie headers: HttpOnly
           `__semantos_session` (unchanged shape) + non-HttpOnly
           `__semantos_helm_bearer=<64-hex>; SameSite=Lax`.  The
           redirect target no longer carries `?bearer=...` in the
           query string — the bearer rides exclusively on the cookie.
           The Svelte SPA's `repl-client.ts:getStoredBearer` reads
           the cookie on first call, promotes it to
           `localStorage["helm.bearer"]`, and clears the cookie via
           `Max-Age=0` — so the bearer is on the wire for exactly
           one round-trip.  Backward-compat: the legacy
           `?bearer=...` query path still flows through
           `captureBearerFromUrl` so older deploys keep working
           during the transition window.  Mobile (device-pair flow)
           is unchanged — it doesn't go through `/auth/callback`.
           Security improvement: bearer no longer leaks to URL
           history, Referer headers, server access logs, or
           analytics beacons.  Glossary: helm-bearer-cookie,
           auth-callback-dual-cookie (2 entries).  Tests: 3 new
           brain conformance + 5 new svelte bearer-cookie tests.
        3. Customer / Calendar / Attention views — DONE (closes
           D-O5.followup-3 in full).  Shipped across two PRs:
           - Customers slice (closed_by_pr: feat/d-o5-followup-3a-
             typed-customers, #308): runtime/semantos-brain/src/customers_store_
             fs.zig + resources/customers_handler.zig + REPL `find
             customers [--name X]` / `find customer <id>` / `add
             customer <name> [--phone X] [--email X] [--address X]
             [--notes X]` verbs + cap.oddjobz.read_customers cap mint
             at 0x00010108.  Both helms (loom-svelte CustomerList +
             oddjobz-mobile CustomersRepository) consume the typed
             JSON branch verbatim per the integration tests.  Same PR
             also polished JobDetailScreen to use jobs.find_by_id
             directly (pre-followup-3 stopgap was a filter over find-
             all).
           - Calendar + Attention slice (closed_by_pr: feat/d-o5-
             followup-3b-calendar-attention): jobs_handler.zig
             extended with `jobs.find_calendar` + `jobs.find_
             attention` (derived queries over the existing jobs_
             store_fs; reuse cap.oddjobz.read_jobs — no new caps, no
             new stores) + REPL `find calendar [--from X] [--to X]`
             / `find attention` verbs.  Both helms gain Calendar +
             Attention nav-bar tiles (oddjobz-mobile
             calendar_screen.dart + attention_screen.dart;
             loom-svelte Calendar.svelte + Attention.svelte) wired
             through the existing JobsRepository pattern.  Per-day
             grouping for Calendar with empty-day buckets present so
             helm renders a calendar grid without missing-key checks;
             three operator-action buckets for Attention (lead →
             pending_quote, quoted → pending_schedule, completed →
             pending_invoice).
        4. WSS live-tick stream (/api/v1/helm-stream or the wallet
           WSS reused).  Status: done (D-O5.followup-4, 2026-05-02) —
           substrate (#318) + every helm-facing emitter wired in
           followup-emitters PR (#319) + every cell-type
           repository (mobile) and store (svelte) wired through to
           the same broker via client-hooks PR.
           Closed_by_pr: feat/d-o5-followup-4-wss-live-tick (#318)
           + feat/d-o5-followup-4-emitters (#319)
           + feat/d-o5-followup-4-client-hooks.
           Shipped in #318:
           - runtime/semantos-brain/src/helm_event_broker.zig — process-scoped
             pub/sub broker.  Single Broker per `brain repl` /
             `brain serve` instance, owned by cli.zig.
           - runtime/semantos-brain/src/wss_wallet.zig — `helm.subscribe` /
             `helm.unsubscribe` JSON-RPC methods + `helm.event`
             notification frame format on the existing
             /api/v1/wallet WSS endpoint.  Topic filter enforced
             per-connection (singular→plural map: job →jobs,
             customer→customers, etc.).
           - runtime/semantos-brain/src/resources/jobs_handler.zig — emits
             `job.transitioned` after a successful jobs.transition
             store-write.  Audit pair preserved (phase=publish).
             Substrate scope: this is the ONLY emitter wired in this
             PR — customers / visits / quotes / invoices /
             attachments emitters are followup PRs and are
             mechanical (just call broker.publish after each
             handler's store write).
           - apps/oddjobz-mobile/lib/src/repl/helm_event_stream.dart
             — Dart client over web_socket_channel; auto-reconnect
             with exponential backoff (1s/2s/4s/8s/16s/30s); state
             stream for the AppBar live indicator.  JobsRepository
             wires `job.transitioned` events into a cacheEvents
             stream JobListScreen + JobDetailScreen subscribe to
             for live refresh.
           - apps/loom-svelte/src/lib/helm-event-stream.ts +
             jobs-store.ts — same shape on the SPA side.  App.svelte
             instantiates the stream on auth + renders a live /
             reconnecting / offline indicator dot in the helm
             header; JobList re-fetches on every jobsTick increment.
           - Tests: 7 broker inline + 5 wss_wallet conformance + 4
             jobs_handler emit + 9 mobile + 9 svelte = 34 new tests.
           - Glossary: helm-event-broker, helm-subscribe-rpc,
             helm-event-stream-mobile, helm-event-stream-svelte (4
             entries).
           Shipped in feat/d-o5-followup-4-emitters (this followup
           PR; closes the deliverable):
           - runtime/semantos-brain/src/resources/customers_handler.zig — emits
             `customer.created` after `customers.create`.  No FSM on
             customers.
           - runtime/semantos-brain/src/resources/visits_handler.zig — emits
             `visit.created` after `visits.create` and
             `visit.transitioned` after `visits.transition`.
           - runtime/semantos-brain/src/resources/quotes_handler.zig — emits
             `quote.created` after `quotes.create` and
             `quote.transitioned` after `quotes.transition`.
           - runtime/semantos-brain/src/resources/invoices_handler.zig — emits
             `invoice.created` after `invoices.create` and
             `invoice.transitioned` after `invoices.transition`.
           - runtime/semantos-brain/src/resources/attachments_handler.zig — emits
             `attachment.created` after `attachments.create_metadata`.
             No FSM on attachments (affine write-once).
           - runtime/semantos-brain/src/cli.zig — every helm-facing handler in
             cmdRepl + cmdServe now constructed via initWithBroker
             so the shared broker fans out across all event sources.
           - 8 new conformance tests across the 5 handler suites
             asserting each emit fires with the expected payload
             shape.  Substrate's audit-pair invariant preserved
             (phase=publish + op="publish" + detail=<event-type>).
           Architectural payoff (substrate brief, restated): broker
           is event-type-agnostic, both helm clients accept any
           event type, so the brain-side PR added zero client-side
           code.  Full event list: job.transitioned,
           customer.created, visit.created, visit.transitioned,
           quote.created, quote.transitioned, invoice.created,
           invoice.transitioned, attachment.created.
           Shipped in feat/d-o5-followup-4-client-hooks (the
           deferred close-out from #319's brief — every cell-type
           list/detail in both helms now updates live):
           - apps/oddjobz-mobile/lib/src/repl/{customers,visits,
             quotes,invoices,attachments}_repository.dart — each
             grew an optional `eventStream` ctor arg, a private
             HelmEventStream subscription, and a public
             `Stream<<Type>CacheEvent> cacheEvents` broadcast that
             list/detail screens listen to.  `dispose()` cancels
             the subscription.  Pattern is the cargo-cult of
             jobs_repository.dart post-#318.
           - apps/oddjobz-mobile/lib/src/helm/{customer,visit,
             quote,invoice}_{list,detail}_screen.dart +
             visit_detail_screen.dart's attachments slice — each
             subscribes to the relevant cacheEvents and re-fetches
             on emission (id-filtered for detail screens).
           - apps/oddjobz-mobile/lib/src/helm/home_screen.dart —
             topic subscription widened from ['jobs'] to all six
             topics; every repo now constructed with the shared
             eventStream + disposed on logout/unpair.
           - apps/loom-svelte/src/lib/{customers,visits,quotes,
             invoices,attachments}-store.ts — five new tick stores
             cargo-culted from jobs-store.ts.  Each accepts the
             HelmEventStream via wire<X>Tick(stream) and bumps a
             monotonic Writable<number> on the relevant event
             types.
           - apps/loom-svelte/src/views/{CustomerList,VisitList,
             QuoteList,InvoiceList}.svelte +
             {VisitDetail,QuoteDetail,InvoiceDetail}.svelte — each
             subscribes to the matching tick store and re-fetches
             on increment (mirrors JobList.svelte's first-seen
             gate).
           - apps/loom-svelte/src/App.svelte — topic subscription
             widened to all six topics; every store wired via the
             new helpers; teardown unwires all.
           - 18 new mobile cache-event tests (3 customers + 4
             visits + 4 quotes + 4 invoices + 4 attachments — each
             group covers `<type>.created`, `<type>.transitioned`
             where applicable, ignored unrelated events, and
             dispose-cancels-subscription) + 18 new svelte store
             tests (3 + 4 + 4 + 4 + 3 across the five new test
             files — tick increment, ignored unrelated event type,
             disposer cleanup).
           - Glossary helm-event-broker.notes appended with the
             client-side adoption summary + this PR reference.
        5. site_config.json editor view — DONE (closes
           D-O5.followup-5; closed_by_pr:
           feat/d-o5-followup-5-site-config-editor).  Shipped:
           runtime/semantos-brain/src/resources/site_config_handler.zig —
           dispatcher resource exposing `read` + `write` for
           `<sites_dir>/<domain>/site.json` as a single atomic
           blob; cap-gated on `cap.brain.admin` (reuses the
           existing root authority cap rather than minting a
           new `cap.helm.admin`).  `write` validates the
           payload via `site_config.parseJson` before doing a
           write-to-temp + rename so a rejected payload never
           replaces the on-disk file; a `dry_run` flag runs
           validation only and returns
           `{ok:true, dry_run:true}` so the editor's Validate
           button can pre-flight a draft.  REPL verbs `site
           config show / set / validate` route through the
           same handler.  apps/loom-svelte/src/lib/site-
           config-store.ts wraps the dispatcher seam with
           typed helpers (loadSiteConfig / saveSiteConfig /
           validateSiteConfig + sniffRoutes / sniffDomain),
           minifies JSON before send so the REPL splitArgs
           tokeniser carries the blob as a single token, and
           re-maps the brain's typed errors into a
           SiteConfigSaveError enum the view uses for inline
           UX.  apps/loom-svelte/src/views/SiteConfigEditor.
           svelte renders a Load / Save / Discard / Validate
           top bar, a monospace textarea editor with dirty-
           tracking, an inline status row (ok / err / parse-
           err), and a side panel of parsed routes (path /
           type / auth) that jumps the textarea selection to
           the clicked path.  apps/loom-svelte/src/App.svelte
           adds a "Site config" tab alongside the existing
           tabs.  Tests: 11 brain conformance + 3 brain REPL +
           12 svelte helper = 26 new tests.  Glossary: site-
           config-resource + site-config-editor-helm (2
           entries).  No new caps minted — the existing
           `cap.brain.admin` is the canonical operator-root
           marker and is the cap `sites_handler` already gates
           on, so the two handlers cohabit cleanly with the
           same authorisation surface.
        6. Per-tenant theming — DONE (closes D-O5.followup-6;
           closed_by_pr:
           feat/d-o5-followup-6-per-tenant-theming).  Shipped:
           runtime/semantos-brain/src/tenant_manifest.zig — optional `[theme]`
           section with five fields (`primary_hex`, `accent_hex`,
           `logo_url`, `font_family`, `mode`); validator enforces
           7-char `#RRGGBB` colors, `/`-or-`https://` logo URL with a
           500-char cap, ≤ 200-char font-family stack, and the
           `light|dark|auto` mode enum.  `resolvedTheme()` accessor
           pairs each operator-supplied value with the canonical
           defaults (`THEME_DEFAULT_*` constants in the same module).
           runtime/semantos-brain/src/info_http.zig — `Acceptor.theme` field
           added; `/api/v1/info` response now carries the resolved
           theme block alongside mesh / pin / version, with defaults
           substituted inline so clients don't ship their own.  The
           wire shape preserves JSON null for `logo_url` when no
           logo is configured.  apps/loom-svelte/src/lib/theme-
           store.ts — Svelte writable + `loadTheme(brainBaseUrl,
           bearer)` initialiser; `applyThemeToDocument` writes
           `--color-primary`, `--color-accent`, `--theme-font-family`
           CSS custom properties on `:root` + toggles `data-mode` on
           `<html>` based on mode + `prefers-color-scheme`.  CSS
           migrated for the load-bearing surfaces (top nav active
           button, primary action color, links, body font, brand
           logo placement, footer link).  apps/oddjobz-mobile/lib/
           src/theme/theme_service.dart — pure-Dart core
           (`ThemeServiceCore`, `TenantTheme`, `parseTenantTheme`)
           that fetches `/api/v1/info` post-pairing, caches the
           resolved theme to SecureStore (under
           `d-o5.followup-6.v1.tenant_theme`) so subsequent launches
           don't flash defaults, and falls back to cached values on
           network error.  apps/oddjobz-mobile/lib/src/theme/
           theme_service_flutter.dart — thin Flutter wrapper that
           projects `TenantTheme` to `ThemeData` /
           `ThemeMode` and adapts the core's stream to the
           `ValueNotifier` MaterialApp's `ValueListenableBuilder`
           consumes.  Tests: 5 brain `[theme]` parse + validate +
           encode round-trip in tenant_manifest_conformance.zig + 3
           info_http_test.zig theme block tests + 16 loom-svelte
           theme-store unit tests + 10 oddjobz-mobile theme-service
           unit tests = 34 new tests.  Glossary entries (4):
           tenant-theme-config, theme-store-helm, tenant-theme-
           mobile, theme-default-fallback.  Backward compat:
           manifests without `[theme]` continue parsing + rendering
           with the canonical defaults; the brain is the single
           source of truth for those defaults so a future schema
           rev only touches one constant table.
        7. Helm-side REPL transcript visibility — DONE (closes
           D-O5.followup-7; closed_by_pr:
           feat/d-o5-followup-7-repl-transcript).  Shipped:
           apps/loom-svelte/src/lib/repl-transcript-store.ts —
           ring-buffer Svelte writable (cap MAX_ENTRIES=200) +
           per-entry result-text truncation cap (MAX_TEXT_BYTES=8192)
           + push-pending → complete-entry lifecycle so mid-flight
           REPL exchanges render with a yellow ⏳ badge until they
           resolve.  ReplClient.send (apps/loom-svelte/src/lib/
           repl-client.ts) now wraps the existing _sendInner wire
           call with pushPending + completeEntry — every helm REPL
           call records timestamp / cmd / latency / status (ok | err
           with statusCode | pending) on the way through, no view-
           layer changes required.  apps/loom-svelte/src/views/
           Transcript.svelte renders the buffer newest-first with a
           filter dropdown (all / ok / err / pending) + Clear button
           + per-entry expandable raw-text panel; styling matches
           the JobList minimalist theme.  apps/loom-svelte/src/
           App.svelte adds a "Transcript" tab alongside the existing
           Jobs / Calendar / Attention / Customers / Visits / Quotes
           / Invoices tabs.  Tests: 8 store-unit + 5 client-
           integration = 13 new tests across tests/repl-transcript-
           store.test.ts + tests/repl-client-transcript-
           integration.test.ts.  Glossary: repl-transcript-store-
           svelte + helm-transcript-view (2 entries).  No brain
           changes — the transcript is purely an SPA-side
           debugging/training surface; the brain's audit log
           remains the canonical post-hoc record.
        8. Multi-window / multi-hat helm UX — DONE (closes
           D-O5.followup-8; closed_by_pr:
           feat/d-o5-followup-8-multi-window-helm).  Final D-O5
           follow-up.  Shipped:
           apps/loom-svelte/src/lib/hat-sessions.ts — typed
           multi-bearer session store backed by
           `localStorage["helm.hat-sessions.v1"]`.  Each
           HatSession carries id / hatId / hatName / certId /
           bearer / brainBaseUrl / colorHex / loggedInAt /
           lastUsedAt.  Public API: loadSessions (with one-
           time migration of legacy helm.bearer →
           Default session), addSession, removeSession (active
           re-points to most-recently-used remaining session),
           setActive, getActiveSession, bumpLastUsed,
           updateSession.
           apps/loom-svelte/src/lib/repl-client.ts —
           ReplClient now reads the active session from the
           store on every send (when no explicit `bearer`
           callback is set), so hat switches take effect
           immediately on the next REPL call.  401s auto-
           remove the active session.  The active session's
           brainBaseUrl overrides the constructor's baseUrl
           (per-tenant multi-hat).
           apps/loom-svelte/src/components/HatSwitcher.svelte
           — top-right Svelte dropdown rendering the active
           hat name + color avatar + a Switch/Remove menu +
           "Pair another hat" CTA that opens the wallet
           origin in a new tab.  Switches fire a `hat-
           switched` CustomEvent on document; App.svelte
           listens and re-loads the per-tenant theme for the
           new context.
           apps/loom-svelte/src/App.svelte — HatSwitcher
           wired into the top nav; per-hat 3px color strip
           rendered above the header (sticky, tints to active
           hat's colorHex with theme primary fallback).  On
           mount: hydrate the multi-hat store first (legacy
           helm.bearer migration runs here), then derive auth
           state from currentAuthState.
           runtime/semantos-brain/src/info_http.zig — `hat` block added
           to /api/v1/info response.  Carries the calling
           bearer's TokenRecord id + label + an empty
           cert_id (cert linkage waits on D-O11 federation
           work; field is on the wire so future PR populates
           without a schema rev).
           Tests: 9 hat-sessions store-unit + 6 ReplClient
           multi-hat integration + 3 brain info_http hat-
           block = 18 new tests.  Glossary entries (3):
           multi-hat-helm-sessions, hat-switcher-component,
           hat-info-endpoint-extension.  Backward compat:
           legacy helm.bearer localStorage migrates cleanly
           on first load; mobile shell unchanged (different
           UX constraints — mobile stays single-hat for now).

      All eight tier-1 follow-ups closed.  Status flips to `done` once
      the tier-2 follow-ups are scheduled and the production deploy on
      oddjobtodd.info is verified by hand.
  - id: D-O5p
    title: "Child-cert pairing flow (REPL device pair + QR + acceptor)"
    phase: "O5p"
    status: in_progress
    owner: null
    deps: [D-O4, D-W1]
    pr_url: null
    note: |
      One-shot QR-encoded pairing payload signed by operator root;
      device derives child cert via BRC-42 BKDS with a per-device
      contextTag (spec v0.5 §4.4 isolation); brain registers in
      identity DAG with capability allowlist from the payload.
      REPL verbs: device pair, device list, device revoke. Depends
      specifically on D-W1 Phase 1 PART 2 (identity_certs resource
      handler — bearer_tokens + Unix socket transport from PART 1
      are not enough on their own), so cert issuance is atomic +
      immediately visible to the daemon.

      Production close-out (this PR) on top of PR #281's lab fixture:
      v2 wire format with brain-WSS-endpoint + cert-pinning fields,
      QR rendering + URL fallback, POST /api/v1/device-pair production
      acceptor, list/revoke polish + revocation kernel-gate test, TS
      stub mobile-client BRC-42 cross-language parity, recovery
      round-trip (§9.4) + conformance vectors (§9.3).
  - id: D-O5m
    title: "Flutter mobile shell — Phase 28 brought into oddjobz"
    phase: "O5m"
    status: in_progress
    owner: null
    deps: [D-O4, D-O5p, D-W1]
    pr_url: null
    note: |
      Flutter app at apps/oddjobz-mobile/ consuming src/ffi/exports.zig
      wasm32 build via dart:ffi (or native ARM64 build for iOS where
      JIT restrictions matter). Cell engine on-device, voice-shell
      grammar pipeline (whisper.cpp + small Llama), camera/GPS/mic
      sensor adapters, mesh sync via SignedBundle, push subscription
      via APNs/FCM, offline mode with K1-conflict-resolution surface.
      The substantive engineering pole of the wave (~3-5 weeks).
      Depends on D-W1 Phase 4 (SignedBundle mesh transport — phone
      and brain are peers running identical dispatchers).

      §O5m-MVP — Phase 1 (in flight on feat/d-o5m-flutter-shell-mvp):

      Shipped:
      - O5m-a — apps/oddjobz-mobile/ scaffolded on top of
        platforms/flutter/semantos_ffi (path dep). flutter_create
        baseline + clean main.dart entrypoint + auth-gated router.
      - O5m-b — pairing-handshake end to end. brain-device-pair-v2
        decode + BRC-42 child derivation in pure Dart via
        pointycastle (cross-language parity asserted vs the
        canonical fixture at extensions/oddjobz/tests/vectors/
        device-pair/v2-fixture.json — derived child pubkey hex
        matches the TS reference byte for byte). PairingService
        orchestrates decode -> derive -> POST -> persist. Child
        cert + bearer + brain endpoints persisted via
        flutter_secure_storage (SecureStore abstraction with
        InMemorySecureStore for tests).
      - O5m-h subset — pairing screen (QR scan via mobile_scanner +
        paste-fallback), home screen, JobList screen (REPL
        `find jobs`), JobDetail screen (read-only summary),
        settings/unpair screen. Voice/text input bar + attention
        feed + ratification card deferred to D-O5m.followup-7.
      - O5m-i skeleton — sqflite-backed outbox queue
        (enqueue/peek/dequeue/recordFailure/count) + OutboxService
        flush-on-reconnect through helm-repl-mobile. Full K1
        conflict resolution UI deferred to D-O5m.followup-5.
      - Canon: glossary entries for oddjobz-mobile-shell,
        child-cert-custody, pairing-handshake, helm-repl-mobile,
        outbox-queue.

      Tests (pure Dart, runnable via `dart test` — no Flutter SDK
      gate; full count = 33 tests, all passing):
      - test/pairing/decode_token_test.dart (6 tests)
      - test/pairing/brc42_derive_test.dart (4 tests, including the
        load-bearing cross-language parity assertion)
      - test/pairing/pairing_service_test.dart (5 tests, full
        decode -> derive -> POST -> persist orchestration)
      - test/repl/repl_client_test.dart (6 tests, all four HTTP
        outcomes + bearer header propagation + connection error)
      - test/repl/jobs_repository_test.dart (5 tests, JSON + TSV
        + empty + malformed parser branches)
      - test/outbox/outbox_db_test.dart (7 tests, schema +
        enqueue/dequeue/recordFailure + flush happy path + 401
        halt + 400 leave-queued)

      Deferred (D-O5m.followup-N):
      - followup-1: O5m-c on-device cell engine bring-up — the
        FFI surface is fully wired and the real cell-engine 2-PDA
        runs on-device.
        Status: DONE (closed_by_pr:
        feat/d-o5m-followup-1-real-2pda-ffi).
        D-O5m.followup-3 Phase 3 brought up the executeScript FFI
        surface with a syntactic-only validator and cellWrite /
        cellRead. This entry replaces that scope-shaved validator
        with the real cell-engine 2-PDA executor:
          - `core/cell-engine/build.zig:createModules` is now `pub`
            so callers can build the cell-engine module graph.
          - `src/ffi/build.zig` inlines an embedded-profile slice
            of that graph (executor + pda + linearity + standard +
            macro + plexus + hostcall + allocator + sighash +
            host) and wires it into the native dylib + static_lib
            + WASM exports modules.  The native test runner pulls
            in the same modules so cross-language tests can build
            cells directly.
          - `src/ffi/exports.zig:semantos_execute_script` now
            heap-allocates a PDA + ScriptArena, turns on K1-K4
            enforcement (`pda.enableEnforcement()`), calls
            `executor.execute(&ctx)`, and maps the ExecuteError
            enum to a stable `errorKind` taxonomy:
            "k1_linearity_violation", "k2_auth_failed",
            "k3_domain_mismatch", "k4_atomicity_violation",
            "script_invalid".
          - The Dart wrapper surfaces a sealed [ScriptOutcome]
            type (ScriptOk | ScriptViolation) with a typed
            [ScriptViolationKind] enum so the helm UI can switch
            on the K1-K4 verdict.
          - `apps/oddjobz-mobile/lib/src/gradient/dart_pipeline.dart`
            extends [IntentRejection] with a typed
            `kernelViolation` field; the kernel-stage rejection
            uses the FFI's `errorKind` as the rejection `code` so
            a single grep finds every K1/K2/K3/K4 surface across
            logs + audit + helm.
          - `apps/oddjobz-mobile/lib/src/helm/voice_command_sheet.dart`
            renders K-violation-specific operator messages
            ("K1 violation: cell already used. Refresh and retry.",
            "K3 violation: hat doesn't have access. Switch to the
            right hat.", etc.) — same pattern as the
            `failure_messages` surface from D-O5m.followup-5.

        Tests (12 FFI Zig tests, 22 Flutter kernel tests, 11
        DartIntentPipeline tests including K1-K4 routing):
        - `src/ffi/tests/execute_script_test.zig` (extended to 12
          tests; +1 happy-path arithmetic, +K1 LINEAR-DUP, +K2
          wrong-cap, +K3 wrong-flag, +K4 OP_VERIFY-falsy)
        - `platforms/flutter/semantos_ffi/test/kernel_test.dart`
          (extended to 22 with the same K1-K4 set hitting the
          real dylib)
        - `apps/oddjobz-mobile/test/gradient/dart_pipeline_test.dart`
          (extended with one test per typed `kernelViolation`
          kind)

        After this PR, the architectural promise from the paper
        (§4.6, §3, §4.4) is fully delivered on-device: a tradie
        says a sentence at a job site → phone runs whisper (STT)
        + llama (L0→L1 SIR) + DartIntentPipeline (L1→L2→L3) +
        SemantosKernel.executeScript (real L4 2-PDA via FFI) →
        produces a SIGNED + K1-K4-VALIDATED cell offline → outbox
        carries to brain → brain re-validates as defence in depth.
        The brain's receipt-side enforcement remains, but it is
        no longer the canonical authority — it is a second
        opinion.

        Note on scope: the wasm32-wasi FFI target keeps the
        diagnostic-only `validateOpcodeStreamSyntactic` walker
        until the wallet-browser host loader provides the
        cell-engine "host" extern namespace imports (host_log,
        host_get_blocktime, host_call_by_name, host_fetch_cell,
        etc.).  That's a follow-up — the phone (native dylib +
        static_lib) is the prize this PR closes.
      - followup-2: replace raw 64-hex device priv in
        flutter_secure_storage with a Keychain/Keystore-backed
        signing key handle so the priv bytes never leave the
        secure enclave.
        Status: DONE 2026-05-02 (closed_by_pr: feat/d-o5m-
        followup-2-secure-enclave-key).  Honest scope note: the
        migration adds at-rest encryption + biometric gating on
        every cell signature + key revocation via handle delete,
        but the priv DOES briefly enter process memory during
        sign operations because secp256k1 isn't a Secure Enclave
        / AndroidKeyStore-supported curve.  iOS Secure Enclave
        only does NIST P-256; AndroidKeyStore EC keys are
        restricted to NIST curves (P-256/P-384/P-521).  Bridging
        that gap requires either a curve change (Plexus would
        have to ship a P-256 cell signer alongside secp256k1) or
        a JNI/CMake-built libsecp256k1 running in a secure
        context (iOS CryptoKit extension or Android Keystore
        custom plugin), neither zero-effort.  A future revision
        (D-O5m.followup-2-bis) closes that gap.
        What landed in this PR:
          - iOS native: SecureSigningKey.swift wraps secp256k1.swift
            (GigaBitcoin maintained MIT-licensed Pod) with
            Keychain (`kSecClassGenericPassword` +
            `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` +
            `SecAccessControl(.userPresence)`).
            SecureSigningKeyChannel registers the
            `semantos.oddjobz/secure_signing_key` MethodChannel
            handler in AppDelegate.didInitializeImplicitFlutterEngine.
            Pod added to Podfile (`pod 'secp256k1.swift', '~> 0.15'`).
          - Android native: SecureSigningKey.kt uses BouncyCastle
            (`ECKeyPairGenerator` + `ECDSASigner(HMacDSAKCalculator)`)
            for the secp256k1 primitives + EncryptedSharedPreferences
            (with `setUserAuthenticationRequired(true, 0)` master
            key) for at-rest storage.  Three Gradle deps added:
            org.bouncycastle:bcprov-jdk18on,
            androidx.security:security-crypto,
            androidx.biometric:biometric.  MainActivity registers
            the channel in configureFlutterEngine.
          - Dart abstraction: SecureSigningKeyAdapter contract
            (generateNew / sign / delete / exists) with two impls
            — PlatformSecureSigningKeyAdapter (production
            MethodChannel-routed, in
            platform_secure_signing_key_adapter.dart so it stays
            isolated from the pure-Dart test path) and
            InMemorySecureSigningKeyAdapter (pointycastle-routed,
            used by tests + as a degraded fallback).
          - CellSigner class: wraps an adapter + keyHandle so call
            sites can opt into the secure path; legacy
            `signCellPayload(payload, priv)` stays in place for
            backward compat.
          - PairingService refactor: optional
            `secureSigningKeyAdapter` constructor param; when
            supplied, new pairings generate inside the platform
            store and persist only the handle.  Includes
            orphan-cleanup on every error path (network /
            rejection / response error) so failed pairings don't
            leak Keychain entries.  Adds
            PairingService.migrateToSecureKey() for the
            operator-initiated rewrite of legacy raw-priv records.
          - ChildCertRecord schema: adds `secureKeyHandle` field
            (defaults to empty string for backward compat) and a
            `usesSecureKeyHandle` getter.  ChildCertStore.read()
            accepts records with EITHER `device_priv_hex` OR
            `secure_key_handle` (but not requiring both); write()
            persists both slots uniformly.
          - SettingsScreen: new "Signing key" card surfaces three
            states — "migration not available in this build" (no
            adapter wired), "legacy storage + Migrate now button"
            (legacy record), and "Secure key active" green banner
            (post-migration).  HomeScreen forwards the
            secureSigningKeyAdapter through to the migration
            callback.
          - Tests: 18 new dart tests under
            test/identity/secure_signing_key_test.dart (~9 tests
            covering InMemoryAdapter generate/sign/exists/delete +
            CellSigner adapter routing),
            test/pairing/pairing_service_test.dart (~5 new tests
            covering secure-key generation flow + migration
            ceremony), test/helm/settings_migration_test.dart
            (~4 new tests covering the legacy-→-migrated record
            transition + idempotency + adapter-missing error
            path).
          - Runbook at
            docs/operator-runbooks/secure-signing-key-migration.md
            covers the honest-scope analysis, before-you-migrate
            checks, the operator-side migration steps, after-
            migration re-pair ceremony, verification methods,
            and troubleshooting (biometric prompt failing /
            Keychain wipe / build deps missing / etc).
          - 4 new glossary entries: secure-signing-key-mobile,
            keychain-backed-priv, androidkeystore-backed-priv,
            biometric-gated-signing.
        Cross-language signature parity from D-O5m.followup-8 is
        preserved: the wire shape of a Keychain-backed signature
        is identical to a raw-priv signature (64-byte r||s, low-s
        normalised), so the brain accepts both unchanged.
        Native iOS Swift / Android Kotlin code is reviewable but
        not unit-tested in this PR (would require simulator/
        emulator + integration tests, out of scope).
        Note: D-O5m.followup-8 capture+upload (2026-05-02) wires
        `cell_signer.dart` to read the priv bytes via the existing
        ChildCertStore raw-priv pattern; this followup-2 makes the
        secure-key path opt-in via the `SecureSigningKeyAdapter`
        constructor param so existing call sites that pass raw
        priv bytes keep working.
      - followup-3: O5m-d voice-shell pipeline (whisper.cpp +
        llama.cpp on-device).
        Status: DONE — voice-shell pipeline ships end-to-end with
        signed cells produced offline (closed_by_pr:
        feat/d-o5m-followup-3-voice-phase-1 +
        feat/d-o5m-followup-3-voice-phase-2 +
        feat/d-o5m-followup-3-voice-phase-3).
        After Phase 3 lands: a tradie says a sentence at a job site,
        the phone runs STT (whisper.cpp), L1 SIR extraction
        (llama.cpp), L1→L2 lowering (sir_to_oir.dart), and L2→L3
        emit (oir_to_bytes.dart) on-device, producing opcode bytes
        with no network round-trip needed for capture.  L4 is now
        also on-device — D-O5m.followup-1 wired the real
        cell-engine 2-PDA into the FFI library, so
        `semantos_execute_script` enforces K1/K2/K3/K4
        substructural invariants locally before the cell is signed
        and outboxed.  The brain re-runs the canonical 2-PDA on
        receipt as defence in depth, not as the canonical
        authority.  The byte-identical α-equivalence property
        from the paper §3, §4.4 is the load-bearing cross-language
        correctness proof for L2→L3: the Dart oirToBytes()
        produces byte-identical opcode output to the TS emit() for
        any well-formed OIR program.
        Phase 3 originally shipped `semantos_execute_script` with a
        scope-shaved syntactic validator (PUSHDATA bounds + opcode
        budget + truncation detection); D-O5m.followup-1 replaces
        that with the real cell-engine 2-PDA so K1-K4 enforcement
        runs on-device.  See `D-O5m.followup-1` above for the
        details of the build-graph + Dart-side wire-up.
        Phased plan:
          - Phase 1 (this PR): voice → STT → brain-side gradient →
            signed cell.  Phone records audio, runs whisper.cpp
            on-device for STT, and signs a cert-bound Transcript
            against the existing voice-session contract from
            runtime/intent/src/voice/.  Brain-side multipart
            endpoint (POST /api/v1/voice-extract) verifies the
            transcript + shells into bun runtime/intent/processIntent
            for the gradient pass.  IntentResult flows back to the
            helm.  Shipped:
              - platforms/flutter/whisper_cpp/ Flutter FFI plugin
                (whisper.cpp source NOT vendored — fetched at build
                time via CMake FetchContent on Android + CocoaPods
                prepare_command on iOS/macOS, pinned to v1.6.0;
                model file NOT bundled — downloaded on first use
                via WhisperModelManager + verified by SHA-256)
              - apps/oddjobz-mobile/lib/src/voice/
                voice_session_service.dart (Dart port of the TS
                voice-session contract; cross-language preimage
                parity proof at apps/oddjobz-mobile/test/fixtures/
                voice-session-fixture.json — same load-bearing
                pattern as cell-signing-fixture.json from #316)
              - apps/oddjobz-mobile/lib/src/voice/
                voice_command_service.dart (orchestrates record →
                transcribe → sign Transcript)
              - apps/oddjobz-mobile/lib/src/voice/
                voice_extract_uploader.dart (multipart POST to
                /api/v1/voice-extract via Dio; typed
                VoiceExtractResult branches for success / failed /
                network error)
              - apps/oddjobz-mobile/lib/src/helm/
                voice_command_sheet.dart (6-state UI: recording →
                transcribing → review → sending → done | failed)
              - apps/oddjobz-mobile/lib/src/helm/
                visit_detail_screen.dart (4th CTA "Voice command"
                alongside Capture / GPS / Record on scheduled +
                in_progress visits)
              - apps/oddjobz-mobile/lib/src/outbox/
                outbox_service.dart (extended with
                `oddjobz.voice_extract.v1` cell_type +
                VoiceExtractFlushUploader seam for offline support)
              - runtime/semantos-brain/src/voice_extract_http.zig (multipart
                endpoint with cert + transcript-signature
                verification; canonical preimage construction is
                byte-identical to the TS / Dart implementations,
                asserted via inline test against the cross-language
                fixture)
              - runtime/semantos-brain/src/site_server.zig wires the new
                voice_extract_acceptor route alongside the
                attachments_upload_acceptor
              - extensions/oddjobz/tools/voice-extract.ts (bun CLI
                wrapping processIntent — Phase 1 returns a
                placeholder IntentResult with the recognised text
                + visit binding; Phase 2 wires the real
                processIntent call)
              - 4 glossary entries: voice-shell-pipeline,
                voice-session-mobile, whisper-ffi-binding,
                voice-extract-endpoint
          - Phase 2 (this PR): on-device L1 SIR extraction via
            llama.cpp.  The L1 SIR build moves to the phone — a
            3B Q4-quantized "pleb" model produces an Intent
            candidate locally via grammar-constrained generation;
            the brain still runs L2-L4 against the supplied SIR.
            Backward compatible: devices without the model fall
            back to the Phase 1 brain-side path.  Operationalises
            the paper's "we can use a more pleb model because the
            gradient does the structural work" claim.  Shipped:
              - platforms/flutter/llama_cpp/ Flutter FFI plugin
                (llama.cpp source NOT vendored — fetched at build
                time via CMake FetchContent on Android + CocoaPods
                prepare_command on iOS/macOS, pinned to b3500;
                model file NOT bundled — downloaded on first use
                via LlamaModelManager + verified by SHA-256;
                grammar-constrained generation via the GBNF
                sampler is the load-bearing primitive)
              - apps/oddjobz-mobile/lib/src/voice/sir_extractor.dart
                (on-device L1 SIR producer; computes host-side
                confidence via the same scoring logic as the
                brain's sir-builder.ts::candidateTrustClass;
                refusals fall through to brain-side)
              - apps/oddjobz-mobile/lib/src/voice/
                voice_command_service.dart (extended with
                optional sirExtractor + hatContext params; Phase 2
                tests cover success / refused / exception /
                fallback paths)
              - apps/oddjobz-mobile/lib/src/voice/
                voice_extract_uploader.dart (extended with optional
                sirCandidate Map param; sends as `sir_candidate`
                multipart part when non-null; canonicaliseIntent +
                encodeCanonicalIntent guarantee byte-identical
                wire output to the TS reference encoder)
              - apps/oddjobz-mobile/lib/src/helm/
                voice_command_sheet.dart (review-state surface
                shows extracted SIR summary in plain English when
                available; "Brain will extract intent" fallback
                otherwise)
              - runtime/intent/scripts/gen-llama-grammar.ts +
                runtime/intent/assets/intent.gbnf +
                apps/oddjobz-mobile/assets/llama/intent.gbnf (GBNF
                grammar generated from the Intent type, bundled
                as a Dart asset; the load-bearing structural
                validator)
              - runtime/intent/scripts/gen-sir-roundtrip-fixture.ts +
                apps/oddjobz-mobile/test/fixtures/sir-roundtrip-
                fixture.json + matching TS + Dart parity tests
                (cross-language byte-identical canonical-Intent
                encoding asserted on both surfaces)
              - runtime/semantos-brain/src/voice_extract_http.zig extended
                with optional sir_candidate multipart part;
                forwards to the bun CLI as `--sir-candidate`
              - extensions/oddjobz/tools/voice-extract.ts extended
                with --sir-candidate flag; when present, skips the
                placeholder L0->L1 producer and reflects the
                supplied Intent through to the IntentResult
              - 3 new glossary entries: llama-ffi-binding,
                sir-extractor-mobile, gbnf-grammar-bundling
          - Phase 3 (this PR): L1-L3 gradient on-device.  L1 SIR
            build + L2 SIR->OIR lowering + L3 OIR->bytes emit all
            run pure-Dart on the phone, producing canonical opcode
            bytes that go into a signed cell.  This Phase 3 PR
            shipped `semantos_execute_script` with a scope-shaved
            syntactic validator (PUSHDATA bounds + opcode budget +
            truncation detection); D-O5m.followup-1 replaced that
            with the real cell-engine 2-PDA so K1-K4 substructural
            enforcement now runs on-device.  After
            D-O5m.followup-1 lands the brain's receipt-side
            enforcement becomes defence in depth, not the
            canonical authority — see the `D-O5m.followup-1` entry
            above for the full wire-up.  The bun shellout remains
            as a fallback path -- when the phone has whisper +
            llama models AND the FFI is loadable, the full
            L1->L4 + sign-and-outbox path runs offline; brain
            re-validates K1-K4 on flush.  Shipped:
              - src/ffi/exports.zig + src/ffi/semantos.h (new
                `semantos_execute_script` C export -- the brain-
                side authoring contract: validate opcode bytes
                + return JSON ScriptResult with opcount /
                stackDepth / errorCode / errorMessage; honours
                BUFFER_TOO_SMALL retry; ~7 new Zig gate tests)
              - platforms/flutter/semantos_ffi/lib/src/{bindings,
                kernel}.dart (Dart-side typedef + late-binding
                lookup + `executeScript({bytes, ctx}) ->
                Future<ScriptResult>` with BUFFER_TOO_SMALL retry;
                surfaces ScriptContext + ScriptResult typed
                wrappers re-exported from the package barrel; +5
                kernel tests)
              - apps/oddjobz-mobile/lib/src/gradient/sir_to_oir.dart
                (pure-Dart L1->L2 lowering; verbatim port of
                core/semantos-sir/src/lower-sir.ts; honours all
                four LoweringError refusal cases:
                trustTierMismatch, delegationUnconfigured,
                emitOpNotAllowed, primaryNodeNotFound)
              - apps/oddjobz-mobile/lib/src/gradient/oir_to_bytes.dart
                (pure-Dart L2->L3 emit; verbatim port of
                core/semantos-ir/src/emit.ts; produces
                byte-identical opcode bytes to the TS implementation
                for any well-formed OIR program -- the load-bearing
                α-equivalence property the paper commits to)
              - apps/oddjobz-mobile/lib/src/gradient/dart_pipeline.dart
                (top-level orchestrator; mirrors
                runtime/intent/src/pipeline.ts:processIntent
                stage-for-stage with `sir_built` /
                `sir_lowered` / `ir_emitted` / `script_executed`
                / `cell_written` / `intent_completed` events,
                consistent correlationId tagging, and structured
                IntentRejection on either the sir or kernel stage)
              - apps/oddjobz-mobile/test/fixtures/{sir-to-oir,
                oir-to-bytes,end-to-end-pipeline}-fixture.json
                (cross-language fixtures generated by
                runtime/intent/scripts/gen-phase3-fixtures.ts;
                the byte-identical α-equivalence claim is asserted
                at every stage boundary against the canonical TS
                output)
              - apps/oddjobz-mobile/lib/src/voice/
                voice_command_service.dart (extended with optional
                `localPipeline` + `pipelineHatContext` params; when
                non-null AND the SIR extractor produced a candidate,
                the orchestrator runs L1->L4 locally and surfaces
                IntentResult on VoiceCommandRecording.localPipelineResult.
                Failures fall through to the Phase 1/2 fallback path)
              - apps/oddjobz-mobile/lib/src/helm/voice_command_sheet.dart
                (the 6-state UI extends to surface local-pipeline
                outcomes: "Done (signed locally; syncing to brain)"
                for IntentSuccess, "Couldn't apply: <stage> -
                <message>" for IntentRejected; brain-side path
                still ends in "(brain confirmed)")
              - 5 glossary entries: dart-intent-pipeline,
                sir-to-oir-dart-port, oir-to-bytes-dart-port,
                semantos-ffi-execute-script,
                voice-shell-fully-on-device
            At that point a tradie says a sentence at a job site
            and the phone produces a signed cell entirely offline.
      - followup-4: typed dispatcher resource for `find jobs` and
        friends — DONE (closes D-O5m.followup-4 + D-O5.followup-1
        together; closed_by_pr: feat/d-o5-followup-1-typed-find-jobs).
        Shipped: jobs_store_fs.zig + resources/jobs_handler.zig +
        REPL `find jobs [--state X]` / `find job <id>` / `add job
        <name> <state> [scheduled-at]` verbs + cap.oddjobz.read_jobs
        cap mint at 0x00010107.  Both helms (loom-svelte JobList
        + oddjobz-mobile JobsRepository) consume the typed JSON
        branch verbatim; the TSV fallback stays in place for
        backwards-compat with any operator wiring a different
        upstream.
      - followup-5: K1 conflict resolution UI — "this didn't
        apply because state changed; here's the current state".
        DONE 2026-05-02 (closed_by_pr: feat/d-o5m-followup-5-k1-conflict-ui).
        Shipped:
          - apps/oddjobz-mobile/lib/src/outbox/outbox_db.dart
            (extended `outbox_v1` schema with five typed-failure
            columns: `failure_reason` / `failure_message` /
            `failure_at_ms` / `failure_count` / `last_brain_state`
            via soft ALTER migrations + new
            `recordTypedFailure` / `clearFailure` / `peekFailed` /
            `failedCount` ops; `OutboxFailureKind` enum +
            `OutboxFailedEntry` projection)
          - apps/oddjobz-mobile/lib/src/outbox/outbox_service.dart
            (`parseBrainError` mapper from brain wire kinds to typed
            kinds + `extractBrainState` for state-moved-on bodies;
            flush now records typed failures via `recordTypedFailure`
            + emits broadcast `failedEntries` + `pendingCount`
            streams for the AppBar indicator + conflicts screen;
            `retry(id)` / `discard(id)` mutate the queue + re-emit)
          - apps/oddjobz-mobile/lib/src/outbox/failure_messages.dart
            (single-source-of-truth operator-facing English per
            `OutboxFailureKind` — clear, actionable, no jargon)
          - apps/oddjobz-mobile/lib/src/repl/repl_errors.dart +
            apps/oddjobz-mobile/lib/src/repl/repl_client.dart
            (extended `ReplValidationError` with optional `body`
            field so the typed JSON body propagates to the outbox
            mapper + the 200-shaped `error` body path also surfaces
            the body)
          - apps/oddjobz-mobile/lib/src/helm/conflicts_screen.dart
            (new screen: subscribes to
            `OutboxService.failedEntries`, renders one row per
            failed entry with operator-facing English message +
            `lastBrainState` summary + per-row Retry / Discard /
            View-conflict actions; the View-conflict button opens a
            side-by-side dialog comparing the operator's offline
            payload to the brain's current state)
          - apps/oddjobz-mobile/lib/src/helm/home_screen.dart
            (AppBar status indicator: green/yellow/red dot reading
            from `OutboxService.failedEntries` + `pendingCount`;
            tap on red opens ConflictsScreen)
          - apps/loom-svelte/src/lib/repl-client.ts
            (typed error classes `ReplValidationError` +
            `ReplStateMovedOnError` + `ReplFkError` +
            `STATE_MOVED_ON_KINDS` / `FK_ERROR_KINDS` constants +
            `throwIfTypedConflict` dispatcher helper for 200-shape
            transition bodies; `ReplClient.send` now promotes 400
            typed bodies automatically)
          - apps/loom-svelte/src/views/JobDetail.svelte
            (catches typed errors + renders an inline conflict
            banner with Retry / Dismiss actions; the structured
            banner replaces the bare red "failed" banner for
            state_moved_on / fk_error / validation paths)
          - Canon: glossary entries `outbox-failure-model`,
            `k1-conflict-ui`, `state-moved-on-conflict`,
            `repl-typed-errors` (4 entries).
        Tests added:
          - apps/oddjobz-mobile/test/outbox/outbox_failure_test.dart
            (11 tests: one per `OutboxFailureKind` asserting
            `parseBrainError` wire mapping + `readableMessage`
            operator-facing copy + round-trip + unknown-fallback)
          - apps/oddjobz-mobile/test/outbox/outbox_db_test.dart
            (extended: 5 schema tests for `recordTypedFailure` /
            `clearFailure` / `peekFailed` / `failedCount` +
            `OutboxFailedEntry.fromEntry`; 5 flush-mapping tests
            for hash_mismatch / not_reachable / 401-typed /
            stream-emission / retry-discard call-throughs)
          - apps/oddjobz-mobile/test/helm/conflicts_screen_test.dart
            (6 widget tests: empty-state, row-rendering, retry +
            discard call-throughs, state_moved_on extras, multi-row)
          - apps/loom-svelte/tests/repl-error-types.test.ts
            (11 tests: each typed error class shape + the
            STATE_MOVED_ON / FK constant sets + throwIfTypedConflict
            dispatcher + ReplClient.send 400 promotion + 503
            untouched)
        No brain-side changes; the typed errors were already there
        post-#316.
      - followup-6: O5m-e real SignedBundle mesh sync (HTTP/WSS
        REPL is the MVP wire).
        DONE 2026-05-02 (closed_by_pr: #329 Phase 1 +
        feat/d-o5m-followup-6b-mesh-transport Phase 2).  Phased plan:
          Phase 1 (#329, feat/d-o5m-followup-6a-bundle-codec):
            SignedBundle Dart codec port + cross-language fixture
            parity proof.  Landed the load-bearing wire-layer
            correctness seam.
              - apps/oddjobz-mobile/lib/src/mesh/cert_ref.dart
                (Dart port of CertRef)
              - apps/oddjobz-mobile/lib/src/mesh/signature_metadata.dart
                (Dart port of SignatureMetadata)
              - apps/oddjobz-mobile/lib/src/mesh/signed_bundle.dart
                (struct + canonical preimage + sign + verify; reuses
                cell_signer ECDSA primitives with no crypto duplication)
              - apps/oddjobz-mobile/test/mesh/signed_bundle_test.dart
                (cross-language parity tests against the fixture)
              - runtime/semantos-brain/tests/signed_bundle_canonical_fixture_gen.zig
              - runtime/semantos-brain/tests/vectors/signed-bundle-canonical-fixture.json
              - 2 new glossary entries (signed-bundle-mobile-port,
                brain-signed-bundle-v1-canonical-preimage)
          Phase 2 (feat/d-o5m-followup-6b-mesh-transport):
            MeshTransport seam + outbox refactor + brain routing + UI.
            Phone+brain now structurally peer-equivalent (per D-W1
            Phase 4 architectural intent); HTTP-REPL fallback retained
            for environments without shard-proxy reachability.
              - apps/oddjobz-mobile/lib/src/mesh/shard_proxy_client.dart
                (pure-Dart HTTP client: publish + long-poll subscribe,
                exponential backoff on transient errors)
              - apps/oddjobz-mobile/lib/src/mesh/mesh_transport.dart
                (MeshTransport abstraction +
                ShardProxyMeshTransport + HttpReplFallbackTransport
                + MeshTransportFactory with reachability probe)
              - apps/oddjobz-mobile/lib/src/outbox/mesh_outbox_builder.dart
                (OutboxEntry → SignedBundle builder; cell_type →
                payload_type mapping)
              - apps/oddjobz-mobile/lib/src/outbox/outbox_service.dart
                (additive flushViaMesh + incoming bundle handler;
                legacy flush path preserved)
              - apps/oddjobz-mobile/lib/src/helm/settings_screen.dart
                (Mesh sync card with Refresh transport CTA)
              - runtime/semantos-brain/src/info_http.zig +
                tests/info_http_test.zig (GET /api/v1/info
                bearer-gated; surfaces shard-proxy URL + brain pin)
              - runtime/semantos-brain/src/payload_type_router.zig +
                signed_bundle_e2e_conformance unknown_payload_type
                tests (oddjobz.attachment.create / .voice-extract /
                .cell.create classification; unknown types fail
                closed)
              - runtime/semantos-brain/src/tenant_manifest.zig optional [mesh]
                section (shard_proxy_endpoint + shard_group_id;
                round-trips through encode())
              - 4 new glossary entries (mesh-transport-mobile,
                shard-proxy-client-dart, mesh-transport-fallback,
                info-endpoint)
              - +28 new mobile tests (mesh + outbox-mesh) + +12 new
                brain tests (info_http + payload_type_router +
                routing-gate e2e additions)
      - followup-7: O5m-h voice/text input bar, attention feed,
        ratification card.
        DONE 2026-05-02 (closed_by_pr:
        feat/d-o5m-followup-7a-leads-brain (Phase A, #332) +
        feat/d-o5m-followup-7b-mobile-ui (Phase B, this PR)).
        Phase A shipped brain-side primitives (leads_store +
        ratification REPL verbs + `lead.created` emit closing #326's
        deferred wiring); Phase B shipped the mobile surfaces that
        consume those primitives end-to-end (RatificationQueueClient,
        TextIntentService, RatificationCardScreen at /ratify,
        VoiceTextInputBar, LeadsListScreen + a Leads tab in HomeScreen).
        The chat-lead → push → ratify loop is now closed end-to-end:
        D-O6b chat extraction → leads_store.create →
        `lead.created` event with operator-attention=true → push
        dispatcher (D-O5m.followup-9 Phase B) → operator tap →
        PushNotificationRouter (#328) deep-links to /ratify →
        RatificationCardScreen → operator taps Ratify →
        RatificationQueueClient.ratify drives `ratify lead` REPL verb →
        brain produces signed lead cell → live-tick stream
        invalidates the Leads list cache.
        Phased plan:
          - Phase A (this PR): brain-side leads_store
            (runtime/semantos-brain/src/leads_store_fs.zig — append-only JSONL at
            <data_dir>/oddjobz/leads.jsonl with the per-string-heap
            allocation pattern from visits_store_fs post-#312/#319;
            5-state Lead FSM: pending|ratified|rejected|deferred|
            archived; 4-source enum: chat|voice|text|manual; per-hat
            scope via hat_id field) + leads_handler
            (runtime/semantos-brain/src/resources/leads_handler.zig — typed `leads`
            dispatcher resource with find / find_by_id / create /
            transition commands; inlined 7-row FSM table; reuses
            cap.oddjobz.read_jobs + cap.oddjobz.write_customer — no new
            caps; idempotent re-create with contents-differ rejection;
            broker emits lead.created with
            requires_operator_attention=true closing the wiring
            deferred from #326, and lead.transitioned with operator-
            attention=false) + REPL verbs in repl.zig (`find leads
            [--status X] [--hat Y]`, `find lead <id>`, `add lead
            <name> [--phone X] [--email X] [--summary X] [--source X]
            [--source-cid X] [--hat X]`, `ratify lead <id>`, `reject
            lead <id> [--reason X]`, `defer lead <id>`, generic
            `transition lead <id> <to_state>`) + cli.zig wires
            LeadsStoreFs in cmdRepl + cmdServe alongside the FSM
            handler set + 4 new glossary entries (leads-store,
            leads-fsm, find-leads-resource, ratify-lead-flow-brain).
            Test coverage: ~10 inline tests (leads_store_fs.zig) + ~12
            conformance tests (leads_handler_conformance.zig: create,
            find, find_by_id, status filter, idempotent re-create,
            contents-differ, cap-gating, 4 FSM transitions, broker
            emits) + ~6 REPL verb routing tests (repl_conformance.zig).
            Surface untouched: oddjobz extension (TS), intent (TS),
            mobile (Dart), loom-svelte (TS).
          - Phase B (this PR): mobile voice/text input bar +
            ratification card + leads-list screen + queue client.
            Consumes Phase A's `find leads` / `ratify lead` /
            `reject lead` / `defer lead` verbs via the existing typed
            REPL JSON path.  Wires the PushNotificationRouter's
            `/ratify` route target so the §O5m-g push pipeline reaches
            a real screen instead of falling through to home.
            Surface added:
              - apps/oddjobz-mobile/lib/src/ratification/
                ratification_queue_client.dart (typed Dart client over
                the REPL — findPending / findById / ratify / reject /
                defer + cache-event subscription on the live-tick
                stream's `lead.created` + `lead.transitioned`
                notifications)
              - apps/oddjobz-mobile/lib/src/ratification/
                ratification_card_controller.dart (pure-Dart state
                machine for the ratification card; phase enum loading
                → ready → submitting → succeeded | actionError;
                noLeadId + loadError edge states)
              - apps/oddjobz-mobile/lib/src/ratification/
                ratification_route.dart (`/ratify` onGenerateRoute
                factory + RatificationClientHolder process-level
                holder so PushNotificationRouter's deep link can build
                a screen against HomeScreen's bearer-gated client)
              - apps/oddjobz-mobile/lib/src/helm/
                ratification_card_screen.dart (full-screen widget:
                lead summary card + sticky bottom action bar +
                bottom-sheet reject-reason picker)
              - apps/oddjobz-mobile/lib/src/voice/
                text_intent_service.dart (typed-NL pipeline path —
                mirrors VoiceCommandService for typed text;
                Intent.source='nl')
              - apps/oddjobz-mobile/lib/src/voice/
                voice_text_input_bar_controller.dart (pure-Dart state
                machine; idle → sending → success → idle | refused;
                voice path feeds the same inline feedback area via
                reportVoiceOutcome)
              - apps/oddjobz-mobile/lib/src/helm/
                voice_text_input_bar.dart (persistent helm footer;
                TextField + mic + send; bottomSheet on the helm
                Scaffold; visible on every tab except Settings)
              - apps/oddjobz-mobile/lib/src/helm/
                leads_list_screen.dart (read-only ListView mirror of
                JobListScreen; live cache-event subscription; tap row
                → push /ratify)
              - HomeScreen wired: Leads tab (9 nav tabs total now,
                was 8); RatificationClientHolder.set/clear on
                mount/dispose; bottomSheet input bar gated off
                Settings; live-tick `leads` topic added to the
                HelmEventStream subscription set
              - main.dart wired: MaterialApp.onGenerateRoute now
                routes /ratify via buildRatificationRoute
              - 5 new glossary entries (ratification-queue-client-
                mobile, ratification-card-mobile, leads-list-screen,
                voice-text-input-bar, text-intent-service)
              - +40 new mobile tests (15 ratification client + 6
                text intent service + 8 ratification card controller
                + 8 voice/text input bar controller + 3 leads list
                integration); 409 mobile tests pass total (was 369)
      - followup-8: O5m-f camera / GPS / microphone sensors
        producing signed cells.
        DONE 2026-05-02 (closed_by_pr: feat/d-o5m-attachment-substrate
        substrate + feat/d-o5m-camera-capture capture+upload +
        feat/d-o5m-gps-voice-adapters GPS + voice memo).
        camera shipped via #316; GPS + voice memo via the sibling PR
        — sensor adapter trio (camera/GPS/mic) complete per §O5m-f.
        Substrate (#315) shipped: oddjobz.attachment.v1 cell type +
        AttachmentsStore JSONL + attachments dispatcher resource
        (read + create_metadata) + cap.oddjobz.read_attachments
        (0x0001010F) + cap.oddjobz.write_attachment (0x00010110) +
        read-only helm wires.
        Capture+upload PR shipped:
          - apps/oddjobz-mobile/lib/src/identity/cell_signer.dart
            (pure-Dart ECDSA-secp256k1-sha256 signer with Zig-stdlib-
            byte-compatible deterministic-k + low-s normalisation)
          - apps/oddjobz-mobile/test/fixtures/cell-signing-fixture.json
            (Zig-generated cross-language fixture; load-bearing parity
            proof — without it the brain might accept Dart-signed
            cells the Semantos Brain signer would reject or vice versa)
          - apps/oddjobz-mobile/lib/src/attachments/attachment_builder.dart
            (canonical-JSON encoder + signed metadata cell builder)
          - apps/oddjobz-mobile/lib/src/attachments/attachment_capture_service.dart
            (helm-side glue: camera → builder → outbox → flush)
          - apps/oddjobz-mobile/lib/src/sensors/camera_capture.dart
            (image_picker-adapted photo capture)
          - outbox extension: attachment_upload kind + blob_path
            column + DioAttachmentUploader + flush dispatch
          - runtime/semantos-brain/src/attachment_blobs_fs.zig
            (FS-backed sha256-keyed BlobStore + atomic write)
          - runtime/semantos-brain/src/attachments_upload_http.zig
            (multipart POST endpoint with sig verify + hash check
            + cert lookup + delegated metadata cell write)
          - runtime/semantos-brain/src/attachments_blob_http.zig
            (bearer-gated GET endpoint streaming the blob bytes)
          - VisitDetailScreen "Capture photo" CTA + thumbnail render
            (Flutter); VisitDetail.svelte thumbnail prefetch via
            client.fetchBlob + createObjectURL (Svelte)
          - 5 new glossary entries (cell-signing-mobile,
            attachment-blob-store, attachments-upload-endpoint,
            attachments-blob-endpoint, mobile-camera-adapter)
          - cross-language fixture parity test in both Zig (the
            generator) and Dart (the consumer)
          - +20 new brain tests (945+ total) + +14 new mobile tests
            (146 total) + +3 new svelte tests
        GPS + voice memo PR (sensor adapter trio completion) added:
          - apps/oddjobz-mobile/lib/src/sensors/gps_capture.dart
            (GeolocatorAdapter interface + captureCurrentLocation +
            gpsBlobBytes canonical-JSON encoder)
          - apps/oddjobz-mobile/lib/src/sensors/voice_memo_capture.dart
            (VoiceRecorderAdapter interface + VoiceRecorderController
            state machine + timeout watchdog)
          - apps/oddjobz-mobile/lib/src/helm/voice_memo_player_screen.dart
            (fullscreen playback modal with VoicePlaybackAdapter)
          - VisitDetailScreen 3-CTA layout (Capture photo / Drop GPS
            pin / Record voice memo) + kind-aware attachment row
            rendering (lat/lng caption for gps_pin, audio player
            modal for voice_memo) + recording sheet
          - VisitDetail.svelte kind-aware rendering (gps_pin lat/lng
            + Google Maps link, voice_memo inline <audio> element,
            file_other download link)
          - pubspec.yaml: geolocator + record + audioplayers
          - iOS NSLocationWhenInUseUsageDescription +
            NSMicrophoneUsageDescription
          - Android ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION /
            RECORD_AUDIO permissions
          - 2 new glossary entries (gps-sensor-adapter,
            voice-memo-adapter)
          - +12 new mobile sensor tests (gps_capture_test ~6 +
            voice_memo_capture_test ~6) — all pure-Dart runnable via
            `dart test`
        The architectural claim "phone is a peer node producing signed
        cells" is now load-bearing-proven by the cross-language signing
        fixture: the brain accepts a signature the Dart producer
        emits because both implementations agree byte-for-byte on
        the deterministic-k preimage.
      - followup-9: O5m-g APNs/FCM push subscription registered
        during pairing.
        Status: DONE 2026-05-02 (closed_by_pr: feat/d-o5m-followup-
        9a-push-substrate (#326) + feat/d-o5m-followup-9b-push-
        dispatchers (#327) + feat/d-o5m-followup-9c-flutter-firebase).
        The push notification feature is fully shipped end-to-end:
        brain emits requires_operator_attention=true → push_dispatcher
        routes via APNs/FCM → device receives notification → user taps
        → PushNotificationRouter deep-links to the relevant helm
        screen (or falls through to home + logs a warning when the
        target route hasn't been registered yet — e.g. /ratify
        before D-O5m.followup-7 lands).
        A previous review judged the full scope
        (brain APNs/FCM transports + Flutter Firebase wiring +
        ES256/OAuth2 crypto + iOS APNs entitlements + runbook) a
        3-PR effort, not 1.  The high-risk pieces (ES256 JWT signing,
        Google OAuth2 service-account flow, iOS APNs entitlements,
        untestable Firebase scaffolding) needed their own focus.
        Phased plan:
          - Phase A (closed_by_pr: feat/d-o5m-followup-9a-push-
            substrate, #326): substrate only.  Schema (apns_token /
            fcm_token / push_platform / push_registered_at fields on
            the cert record + updatePushToken store method + backward
            -compat log replay), POST/DELETE /api/v1/push-register
            endpoint (bearer-gated, typed errors, no transport),
            broker Event gains a `requires_operator_attention: bool`
            flag that jobs_handler sets to true on transitions into
            `lead`, mobile shell ships a typed PushPlatform /
            PushTokenRegistration model (no Firebase plugin yet, no
            actual subscription flow).
          - Phase B (closed_by_pr: feat/d-o5m-followup-9b-push-
            dispatchers): real APNs/FCM dispatchers with real crypto.
            Brain-side ApnsDispatcher uses Zig stdlib P-256 ECDSA
            (`std.crypto.sign.ecdsa.EcdsaP256Sha256`) for the ES256
            bearer JWT — Apple's spec requires the NIST P-256 curve,
            not Bitcoin's secp256k1, so bsvz is the wrong tool here.
            FcmDispatcher uses an RS256 JWT-bearer assertion to mint
            an OAuth2 access_token via oauth2.googleapis.com; Zig
            0.15.2 stdlib provides RSA verify but not RSA sign, so
            the v0.1 path shells out once per JWT regeneration to
            `openssl dgst -sha256 -sign <pem>` and caches the
            resulting access_token for ~55 minutes.  The HTTP layer
            is an injectable transport seam (push_http_transport.zig
            with a real std.http.Client adapter + a scripted
            MockTransport for tests — no live network in CI).  A
            top-level PushDispatcher routes per-cert based on
            cert.push_platform; helm_event_broker fires the push
            hook whenever `requires_operator_attention=true`.
            Token-expiry signals (Apple's 410+Unregistered, Google's
            404+UNREGISTERED) clear the cert's push_platform via
            CertStore.updatePushToken.  Push is best-effort:
            failures log to audit + don't break event publication.
            Config lives at `<data_dir>/push-config.json`; absent
            file = "push not configured" boot line.  ~21 new tests
            (apns + fcm + push + broker integration).
          - Phase C (closed_by_pr: feat/d-o5m-followup-9c-flutter-
            firebase): Flutter Firebase wiring + iOS APNs
            entitlement + Android Google-services hookup +
            PushRegistrationService that invokes
            POST /api/v1/push-register on pairing complete + the
            operator runbook.  pubspec gains firebase_core +
            firebase_messaging + flutter_local_notifications +
            permission_handler.  iOS scaffolding: AppDelegate.swift
            forwards the APNs device token via Messaging.messaging
            ().apnsToken; Runner.entitlements ships aps-environment
            =development (release flips to production per runbook);
            Info.plist gets NSUserNotificationsUsageDescription +
            UIBackgroundModes=[fetch, remote-notification] +
            FirebaseAppDelegateProxyEnabled.  Android scaffolding:
            POST_NOTIFICATIONS + WAKE_LOCK in AndroidManifest +
            default_notification_channel_id meta-data; placeholder
            google-services.json shipped (real swap at deploy);
            google-services Gradle classpath + plugin wired.  Lib
            files: push_registration_service.dart (pure-Dart, with
            PushPlatformAdapter abstraction + InMemoryPushAdapter
            test seam + sealed PushRegistrationResult); firebase_
            push_adapter.dart (production firebase_messaging
            wrapper, separate file so tests stay Flutter-SDK-
            free); push_notification_router.dart (pure-Dart deep-
            link routing core with NavigatorSink + LogSink seams);
            push_handlers.dart (Flutter wiring of the router into
            FirebaseMessaging.onMessage / onMessageOpenedApp /
            getInitialMessage callbacks + foreground in-app banner
            via flutter_local_notifications).  App-level wiring:
            main.dart fires Firebase.initializeApp +
            setupPushHandlers BEFORE runApp(); HomeScreen
            initState fires registerOnPair() once on first paired
            mount + startTokenRefreshListener() for OS-level
            rotations; SettingsScreen Notifications card surfaces
            registered/not-registered state + Re-register /
            Unregister / Open-Settings actions.  Runbook at
            docs/operator-runbooks/push-notification-setup.md
            covers APNs (Apple Developer Program enrollment + .p8
            key generation + tenant manifest [push.apns]
            section), FCM (Firebase project creation + google-
            services.json download + service-account JSON for the
            brain dispatcher + tenant manifest [push.fcm]
            section), verification (pair-and-trigger smoke test
            via REPL `job <id> mark-lead`), and troubleshooting
            (BadDeviceToken / Unregistered for APNs + UNREGISTERED
            / SENDER_ID_MISMATCH / UNAUTHENTICATED for FCM).
            ~10 new mobile push tests (push_registration_service:
            ~6 covering happy + permission-denied + unsupported +
            HTTP failure + cert-not-paired + token refresh +
            unregister; push_handlers: ~4 covering decodePushTap
            for ratify/job/unknown + routeTap navigator-ready and
            navigator-not-ready paths).  5 new glossary entries:
            firebase-messaging-flutter, push-registration-service-
            mobile, push-deep-link-routing, apns-entitlement-ios,
            google-services-json-android.
        Phases A + B + C together close the end-to-end push pipeline:
        a `lead.created` event published in cmdServe reaches Apple's
        APNs gateway (and Google's FCM via OAuth2 access_token) when
        push-config.json is present, the paired device receives the
        system notification, and tapping the notification deep-links
        into the helm via PushNotificationRouter.  The credentials
        (APNs .p8 key + FCM service account + per-tenant Firebase
        google-services files) are operator-side configuration per
        the runbook — the code path is complete.  The /ratify route
        target itself is owned by D-O5m.followup-7 (voice/text input
        bar + ratification card); until that PR lands the router
        falls through to home with a logged warning.

        D-O5m.followup-7 Phase A (2026-05-02, brain-side primitives):
        the `lead.created → push` wiring is now active.  Phases A/B/C
        of followup-9 staged the pipeline (broker Event flag + APNs/
        FCM dispatchers + Flutter Firebase) but no emitter actually
        set `requires_operator_attention=true` for `lead.created` —
        the only push-attention emit was `job.transitioned` to
        `lead`.  D-O5m.followup-7 Phase A's leads_handler.zig wires
        `requires_operator_attention=true` on every `lead.created`,
        so the helm_event_broker's PushHook now fans out to APNs/FCM
        whenever a chat-bot extraction calls `leads.create`.  The
        load-bearing glue of the §O5m-g push narrative is now end-
        to-end live (modulo the /ratify mobile route target — owned
        by D-O5m.followup-7 Phase B).

        Sovereign-push D.1 Phase 1 (2026-05-03, brain-side half):
        refactored the push pipeline to wake-only payloads so
        operator content never reaches Google/Apple.  The
        PushNotification struct now carries only an opaque
        `payload_json` envelope (`{event_id, ts, kind}`); APNs
        ships `aps.content-available=1` background pushes (push-
        type=`background`, priority=`5`); FCM ships data-only
        messages (no `notification` field, `priority: high`,
        plus per-platform overrides that mirror the APNs wake-only
        headers).  helm_event_broker assigns a monotonic
        `event_id` + wall-clock `ts` to every published event,
        keeps a bounded recent-event ring (MAX_RECENT_EVENTS =
        1024), and exposes it via the new `helm.fetch_since`
        JSON-RPC verb on the WSS wallet endpoint.  Devices wake
        via the opaque envelope, open WSS, and fetch the actual
        event content via `helm.fetch_since` — Google/Apple stay
        in the wake-up loop but see no operator content.  The
        former `titleForEvent` / `bodyForEvent` / `dataForEvent`
        helpers are removed; the cli's `pushBridgeSend` signature
        contracts to `(state, cert_ids, payload_json)` to enforce
        the new shape at the type system.  Closed by PR
        `sovereign-push-d1-wake-only`.  Phase D.2 = mobile silent
        handler + on-device `helm.fetch_since` consumption + local
        notification rendering.  Phase D.3 = UnifiedPush adapter
        + PushPlatform enum extension + settings-UI backend
        picker.  Until D.2 lands, push notifications wake the app
        but show no banner content (the brain is no longer sending
        title/body) — documented in the PR description as the
        cross-phase breaking change.  Glossary additions:
        `wake-only-push`, `sovereign-push`,
        `helm-fetch-since-rpc`.  Runbook:
        docs/operator-runbooks/push-architecture.md.

        Sovereign-push D.2 Phase 2 (2026-05-03, mobile-side half):
        device-side consumer of the wake-only envelope.  The Flutter
        push handler (`apps/oddjobz-mobile/lib/src/push/`) now
        decodes the opaque envelope, opens (or shares) a WSS to the
        brain, calls `helm.fetch_since` with the device's persisted
        last-seen cursor, and renders one local notification per
        returned event whose `kind` warrants a banner.  New surface:
        `last_seen_store.dart` (per-brain SecureStorage cursor with
        monotonic-write guard), `silent_push_handler.dart` (pure-
        Dart fetch + render + cursor-advance core, unit-tested in
        isolation), `helm_event_stream.dart::fetchSince` (request/
        response client over the same WSS the live-event subscribe
        rides on, with 10s timeout + JSON-RPC error/timeout typed
        exceptions).  Wake handling is split into a foreground path
        (`onMessage`) and a background-isolate path
        (`_backgroundHandler`); both drive the same
        `SilentPushHandler` core through injectable adapters.
        Failures (WSS refused, fetch timeout, broker error) are
        SILENT — no operator-facing "fetch failed" notification per
        spec; the next foregrounding back-fills missed events.  In-
        foreground dedupe via `LiveHelmEventDedupe` (1024-entry
        bounded set with sliding-window eviction) prevents a wake
        racing the live `helm.event` notify from double-rendering.
        Tap routing carries `{screen, lead_id|job_id, event_id,
        kind}` in the local-notification payload so
        `PushNotificationRouter.routeTap` works unchanged from D.1
        (no second fetch required at tap time).  Tests: 7 LastSeen
        round-trip + monotonic-write + per-brain isolation; 16
        HelmEventStream including the full fetchSince surface
        (request shape, paging, timeout, JSON-RPC error,
        disconnect-fails-pending, StateError-before-connect, sinceTs
        clamping); 8 SilentPushHandler covering wake-with-cursor,
        per-event banner render, cursor advance, dedupe, silent-on-
        failure, dispose-always (plus 5 composeBanner cases for the
        per-kind banner wiring).  Total push test count goes from 16
        → 36 + 16 helm = 52 in-suite assertions for the D.2 surface.
        End-to-end status: after this PR the wake-only flow is
        functional end-to-end on FCM/APNs — a smoke test on a phone
        today would surface a real lead/job notification within
        ~1s of the brain emitting the event.  Closed by PR
        `sovereign-push-d2-mobile-silent`.  Phase D.3 (UnifiedPush
        adapter + PushPlatform enum extension + settings backend
        picker + migrating off Firebase) is the remaining sovereign-
        push work.  Runbook update:
        docs/operator-runbooks/push-architecture.md §"Mobile silent-
        push flow (D.2)".

        Sovereign-push D.3 Phase 3 (2026-05-03, UnifiedPush
        adapter): closes the Android sovereignty gap.  Brain-side:
        runtime/semantos-brain/src/identity_certs.zig extends PushPlatform with
        a fourth variant `unifiedpush` and the CertRecord with an
        `up_endpoint: []u8` field (with backward-compat replay so
        legacy push_token log lines still parse).
        runtime/semantos-brain/src/push_register_http.zig accepts
        `platform=unifiedpush` and validates the supplied `token`
        starts with `https://` (otherwise 400 endpoint_invalid).
        New runtime/semantos-brain/src/unifiedpush_dispatcher.zig is the third
        dispatcher: POSTs the wake JSON envelope verbatim to
        cert.up_endpoint with `Content-Type: application/json` and
        no auth header; 410 Gone clears the cert's endpoint
        (mirrors APNs/FCM token-expiry); 4xx → unifiedpush_rejected,
        5xx → 3-attempt retry then transport_failed.  push_dispatcher
        fans out apns/fcm/unifiedpush; cmdServe always inits the UP
        dispatcher when push is enabled (no signing material to gate
        on).  Mobile side: pubspec gains `unifiedpush ^6.2.0` (the
        plugin auto-injects org.unifiedpush.android.connector
        .PUSH_EVENT into the merged AndroidManifest).
        apps/oddjobz-mobile/lib/src/push/unified_push_adapter.dart
        wraps the plugin behind the existing PushPlatformAdapter
        interface — getDeviceToken() drives UnifiedPush.register
        and waits up to 30s for the distributor's onNewEndpoint
        callback to deliver the URL; onMessage forwards the raw JSON
        bytes to the silent-push handler from D.2.  push_registration
        _service.dart adds PushBackendPreference enum + optional
        fallbackAdapter constructor — on Android the default
        preference for new installs is `unifiedpush` (sovereignty-
        first); when the primary returns no token (no distributor
        installed) the service silently falls back to FCM and
        exposes lastUsedFallback so SettingsScreen can render an
        "install a distributor" hint.  SettingsScreen → Notifications
        gains a "Push backend" sub-section with iOS read-only "Apple
        Push (APNs)", Android dropdown {UnifiedPush, FCM}, installed-
        distributor list with "Use" buttons, and Apply that swaps
        adapters + re-runs registerOnPair.  main.dart wires the
        UnifiedPushAdapter alongside FirebasePushAdapter, picks the
        initial primary based on the persisted preference, and
        threads the three new SettingsScreen callbacks through
        OddjobzMobileApp → AuthRouter → HomeScreen.  Build conflict
        resolved: tink (JVM) from unifiedpush_android's transitive
        webpush_encryption duplicates tink-android from
        firebase_messaging — excluded the JVM variant in
        android/app/build.gradle.kts so tink-android wins on Android
        builds.  Tests: 8 unified_push_adapter_test (platformName /
        getDeviceToken / refreshStream / onMessage / requestPermission);
        5 push_registration_service_test additions for D.3 (default
        preference, write/read round-trip, fallback path, primary-
        wins-when-token-available, swapAdapters); 2 push_platform
        _test additions (UP round-trip, wire-name contract); 1 Zig
        push_register_http inline test for endpoint_invalid plus
        2 round-trip tests in identity_certs_test (up_endpoint log
        replay + switching from unifiedpush back to fcm clears the
        endpoint); 1 new tests/unifiedpush_dispatcher_test.zig (8
        cases: 2xx body shape + no auth header, 410 clears endpoint,
        4xx surfaces typed error, 5xx-retry-budget, transient
        retry-and-recover, cert_not_found, no_up_endpoint); 4
        push_dispatcher_test.zig additions for the new fan-out arm
        (routes-to-up, skips-when-up-null, sendToCerts-fans-out-
        across-three-backends).  All sovereign-push phases (D.1 +
        D.2 + D.3) shipped — D-O5m.followup-9 is end-to-end
        complete: a sovereign operator can run an Android device on
        a self-hosted ntfy distributor with no Google services in
        the wake loop.  Runbook update:
        docs/operator-runbooks/push-architecture.md §"Phase D.3:
        UnifiedPush".  Glossary addition: `unifiedpush`.
  - id: D-O6a
    title: "Public chat v0.5 — widget + llm.complete passthrough (no persistence)"
    phase: "O6"
    status: in_progress
    owner: null
    deps: [D-W1]
    pr_url: null
    note: |
      Half-day deliverable on top of D-W1 Phase 1 PART 2 specifically
      (the llm.complete resource handler — Phase 1 Part 1 ships the
      bearer_tokens handler + transport, not the LLM seam).  Chat
      widget on oddjobtodd.info landing page posts to a native
      dynamic route that calls dispatcher.dispatch(llm.complete, ...)
      with anonymous-cap + tenant prompt. No cell persistence — proves
      the dispatcher pattern carries an LLM resource end-to-end and
      gives the site a product-shaped demo. Originally specced (per
      ODDJOBZ-EXTENSION-PLAN.md v0.2) as half-day independent of D-W1
      via host_llm WASM import or native chat route, but Path A's
      missing host import + Path B's lack of composition (carpenter +
      musician multi-vertical case) make Phase-1-first the right
      ordering. See BRAIN-DISPATCHER-UNIFICATION.md §2.5.

      Implementation seams (in_progress as of 2026-05-01):
      - `runtime/semantos-brain/src/site_config.zig` — RouteType.chat +
        SiteConfig.anonymous_caps allowlist + per-route scope/
        system_prompt/max_message_chars fields.
      - `runtime/semantos-brain/src/chat_http.zig` — native HTTP endpoint that
        constructs an anonymous DispatchContext and dispatches into
        `llm.complete` with the route's scope + tenant system prompt.
      - `runtime/semantos-brain/src/site_server.zig` — `attachChatBackend` +
        `RouteType.chat` branch in handleRequest.
      - `extensions/oddjobz/public/chat-widget/` — no-build vanilla-JS
        widget (chat-widget.js/css + index.html demo + README).
      - `runtime/semantos-brain/deploy/oddjobtodd-site-example.json` — operator-
        deployable example site.json with the chat route + canonical
        anonymous_caps grant.
      - `runtime/semantos-brain/tests/chat_http_conformance.zig` — full TCP-driven
        end-to-end coverage: 200 happy path, 401 cap denial, 400/413
        validation, 503 backend, 429 rate-limit, 503 unattached, 405
        method gate.
  - id: D-O6b
    title: "Public chat v1.0 — lead extraction + ratification + canon cells"
    phase: "O6"
    status: in_progress
    owner: null
    deps: [D-O2, D-O6a, D-W1]
    pr_url: null
    note: |
      Layers persistence onto D-O6a: oddjobz.message.v1 cells (the
      `chat.message.v1` vs `oddjobz.message.v1` naming-resolution
      defaults to reusing the §O2 message cell — see glossary
      `oddjobz-chat-persistence`), lead extraction prompt drafting
      oddjobz.estimate.v1, on-disk ratification queue, operator-side
      ratify command producing oddjobz.lead.v1 on sign + driving the
      §O4 Job FSM `∅ → lead` genesis transition under
      cap.oddjobz.write_customer. Depends on D-O2 (cell types) so
      persistence is canon-aligned from day one rather than migrated,
      and D-W1 Phase 2 (files + capabilities resource handlers) so
      the chat handler's writes go through the dispatcher's per-
      tenant cap scope.
  - id: D-O7
    title: "OJT salvage + substrate canon-alignment (no shadow-mode; OJT was test-only)"
    phase: "O7"
    status: in_progress
    owner: null
    deps: [D-O2, D-O3, D-O4, D-O6b, D-W1]
    pr_url: "https://github.com/semantos/semantos-core/pull/291"
    note: |
      REFRAMED 2026-05-01. The original deliverable spec called for a
      "shadow-mode for a week of measurement before authority flip".
      Operator confirmed OJT was NEVER live with real customers — the
      production deployment was test-only. D-O7 therefore becomes:
      salvage the load-bearing logic out of OJT into the canon
      substrate, drop the rest, single PR. No shadow mode, no data
      migration, no production cutover. The OJT repo at
      `/Users/toddprice/projects/oddjobtodd/` is to-be-archived after
      this PR merges; nothing in this PR touches it. Investigation
      report at docs/design/D-O7-OJT-SALVAGE-REPORT.md captures the
      six findings, the per-file salvage verdict, and the operator-
      facing TODO. Salvage shape: prompts (system / extraction / pdf)
      ported hat-keyed, conversation modules (state-manager, hat-
      scoping, accumulated-state, analyzer, substrate-bridge) ported
      as `extensions/oddjobz/src/{prompts,conversation}/`. Hat-scoping
      replaces OJT's filter-based isolation with K3 cryptographic
      isolation (oddjobz_cap_isolation_cryptographic, PR #279).
      Operator-facing TODO post-merge: archive oddjobtodd/, point
      production DNS away, snapshot test-data fixtures.
  - id: D-O8
    title: "Tenant manifest schema (TOML/YAML + validator)"
    phase: "O8"
    status: in_progress
    owner: null
    deps: []
    pr_url: null
    note: |
      Format choice: TOML (matches the canonical §11 example).  No
      third-party Zig TOML dep added — the schema is bounded enough
      that an in-tree TOML-subset parser is the simpler win.
      Schema covers [tenant], [extensions] (incl. opaque per-
      extension config_overrides), [branding], [network],
      [capabilities].  Single-file parser + validator at
      runtime/semantos-brain/src/tenant_manifest.zig with typed
      ProblemKind error reports (missing_field / invalid_domain /
      cert_not_found / invalid_enrolment_id / bad_extension_name /
      bad_color / bad_port / unknown_template /
      overrides_for_uninstalled_extension / bad_capability_name /
      bad_cors_origin).  Eight conformance vectors under
      runtime/semantos-brain/tests/vectors/tenant-manifests/ (4 valid, 4
      invalid).  Operator runbook at
      docs/operator-runbooks/tenant-manifest-schema.md.  D-O8 is
      additive only — no changes to site_config.zig (per-site
      schema is a downstream consumer; one tenant → one or more
      sites) or any merged D-O work.  D-O9 will consume this for
      systemd/Caddy templating; D-O10 will consume it + D-O9 for
      the `semantos node provision-tenant` CLI.
  - id: D-O9
    title: "Per-tenant systemd template (semantos-shell@.service) + Caddy templating"
    phase: "O9"
    status: in_progress
    owner: null
    deps: [D-O8]
    pr_url: null
    note: |
      Per-tenant systemd `@`-instance unit at
      runtime/semantos-brain/deploy/systemd/semantos-shell@.service —
      `%i` resolves to the tenant FQDN; the unit's ExecStart runs
      `/opt/semantos/brain serve --tenant-manifest=
      /etc/semantos/tenants/%i.toml`.  Pure Caddy v2 site-block
      renderer at runtime/semantos-brain/src/caddy_template.zig consumes a
      D-O8 `TenantManifest`, emits a byte-stable snippet for
      /etc/caddy/conf.d/<domain>.conf with `tls { on_demand }`
      LE termination, /api/v1 + /helm + catch-all reverse-proxies
      to localhost:<listen_port>, conditional CORS preflight
      matcher (wildcard echo via `{header.Origin}` if `*`, pinned
      via `@allowed_origins` matcher otherwise), and a per-tenant
      access log.  `brain serve --tenant-manifest <path>` (or
      `--tenant-manifest=<path>` glued for systemd ExecStart)
      parses + validates the manifest and uses its domain /
      listen_port_start / extensions to boot.  Three byte-stable
      conformance vectors under
      runtime/semantos-brain/tests/vectors/caddy-blocks/ (canonical-§11,
      minimal, with-network-cors).  Operator runbook at
      docs/operator-runbooks/multi-tenant-deployment.md.  D-O9 is
      additive only — no changes to the existing single-tenant
      `semantos-shell.service` unit (the two coexist; operator
      chooses based on tenancy model).  D-O10 will consume D-O9
      to write the per-tenant systemd unit + Caddy snippet during
      `semantos node provision-tenant`.
  - id: D-O10
    title: "`semantos node provision-tenant` CLI"
    phase: "O10"
    status: in_progress
    owner: null
    deps: [D-O8, D-O9, D-O5p, D-W1]
    pr_url: null
    note: |
      Reads tenant manifest, validates owner cert against Plexus,
      verifies recovery enrolment, allocates port, lays down dirs,
      copies extension bundles, writes systemd + Caddy units, runs
      first-boot, emits pairing token for Flutter shell. The
      productisation gate.

      Ships as `brain provision-tenant <manifest.toml>` (a future
      `semantos node provision-tenant` wrapper is documented as
      TODO).  Twelve numbered steps from "validating manifest"
      through "emit pairing token" with byte-stable
      `[provision] <message>...    <result>` log lines per
      ODDJOBZ-EXTENSION-PLAN.md §11.

      Plexus-side calls (steps 2 + 3) STUBBED for v0.1 with clear
      `(stubbed for v0.1)` log lines + `TODO(D-W2 Phase 1)` markers;
      real Plexus client is D-W2 Phase 1.  systemctl + caddy reload
      shell-outs gated behind `--dry-run` (default false; tests
      pass true) so the conformance suite drives the full flow
      without root.

      Multi-tenant port allocation:
      `/etc/semantos/port-allocations.json` JSON index.  Idempotent
      on re-provisioning; new tenant gets `manifest.listen_port_
      start + count_existing_tenants` if the start port is taken.

      Incorporates D-W2 Phase 0 (the `[trusted_signers]` manifest
      schema extension): between steps 1 and 2 the flow auto-injects
      `[trusted_signers.platform]` keyed off the operator's pubkey
      (derived from `<data_dir>/operator-root-priv.hex`,
      overridable via `--operator-priv`) with `removable = false`,
      `scope = "*"`, and a `plexus_identity_tx` from
      `--platform-plexus-identity-tx` (placeholder + warning when
      omitted).  Augmented manifest is what gets written to the
      canonical archive at `/etc/semantos/tenants/<domain>.toml`.
      Pre-flight refuses operator-edited `removable = true` on the
      platform entry.  Step 5 runs `compareImmutability(prev_archive,
      new_manifest)` before overwriting; immutable-signer drops/edits
      refuse.

      D-W2 Phase 0 schema (the parser + validator extension itself
      + the conformance vectors) is canonical in
      `docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md` §3
      (PR #294 — currently DRAFT; not yet on origin/main).  D-W2's
      full runtime (Phases 1-4: extension publishing, subscription,
      nullifier, rotation, quarantine) is subsequent commissions and
      remains `pending` after D-O10.
  - id: D-O11
    title: "Dispatch envelope smoke test (oddjobz ↔ stub re-desk)"
    phase: "O11"
    status: in_progress
    owner: null
    deps: [D-O4, D-O10, D-W1]
    pr_url: null
    note: |
      Validates chapter 29 federation primitive against real brain
      substrate before any RE-vertical work begins. PM tenant creates
      a MaintenanceRequest with dispatch_to=tradie tenant; envelope
      flows; tradie accepts; completion patches advance PM's FSM.
      AFFINE patches structurally invisible to the wrong hat. Depends
      on D-W1 Phase 4 (SignedBundle mesh transport) — federation is
      mesh-sync between two Semantos Brain nodes running identical dispatchers,
      symmetric with the mobile-peer flow in D-O5m.

      In-progress as of 2026-05-01 (this PR). Three sub-deliverables:

      O11a — Stub re-desk extension at `extensions/re-desk-stub/`.
      Single `re-desk.maintenance-request.v1` LINEAR cell type;
      single `cap.re-desk.dispatch` cap (domain flag 0x00010201);
      single MaintenanceRequest FSM (`draft → dispatched → accepted
      → in_progress → completed → invoiced → closed`, plus
      cancellation paths). 33 conformance tests pass.

      O11b — Dispatch envelope cell type + handler at
      `extensions/dispatch/`. Three LINEAR cell types
      (`dispatch.envelope.v1`, `dispatch.accepted.v1`,
      `dispatch.completion.v1`) and a payload-agnostic handler that
      routes envelopes by payloadType to a registered receiving-
      extension accept-handler. K1 (replay protection +
      payload_type_unsupported), K3 (hat_mismatch), and K4 (retry-
      safe via makeRollbackableConsumedCellSet) enforced. 30
      conformance tests pass.

      O11c — End-to-end smoke test at
      `extensions/dispatch/tests/smoke/`. Two in-process brains (PM
      running re-desk-stub; tradie running oddjobz + dispatch
      handler) communicate via an `InMemoryBundleTransport` that
      simulates the SignedBundle mesh wire. All six §3 phase O11
      acceptance criteria pass:
        (1) MaintenanceRequest dispatch materialises an oddjobz.job
        (2) tradie completion advances PM's FSM to invoiced
        (3) PM hat cannot read tradie margin-notes AFFINE
        (4) tradie hat cannot read PM owner-financial AFFINE
        (5) K1: tradie has no accept-handler → MaintenanceRequest
            stays in draft (rolled back)
        (6) replay: same envelope twice → second is idempotent

      Glossary entries added: `re-desk-stub-extension`,
      `dispatch-envelope-cell-type`, `cross-vertical-dispatch`,
      `tenant-hat-reference`. Cumulative test count: 41 in
      `extensions/dispatch` (cell-types + handler + smoke), 33 in
      `extensions/re-desk-stub` (cell-types + FSM + vectors).

  - id: D-OPS.mobile-smoke-test
    title: "Android cross-compile script + mobile-build-and-pair operator runbook"
    phase: "OPS"
    status: done
    owner: null
    deps: [D-O5m]
    pr_url: null
    closed_by_pr: feat/mobile-build-and-pair-runbook
    note: |
      Closes the gap between "419 dart tests pass" and "the
      operator can plug an Android phone in and exercise the
      voice → cell → outbox loop end-to-end".

      Shipped:

        * `scripts/build-android-libs.sh` — Bash driver that
          cross-compiles `libsemantos.a` for arm64-v8a +
          armeabi-v7a + x86_64 via `zig build static
          -Dtarget=<abi>` and stages the artifacts under
          `platforms/flutter/semantos_ffi/build/android/<abi>/`
          where the Flutter FFI plugin's CMakeLists.txt expects
          them.  Smoke-checks each output for the load-bearing
          FFI exports (`semantos_init`, `semantos_version`,
          `semantos_execute_script`) via `nm`.  Verbs: `--abi`,
          `--clean`, `--release`, `--release-safe`, `--debug`.

        * `src/ffi/build.zig` tweak — when target is Android
          (`target.result.abi.isAndroid()`), apply
          `single_threaded = true` + `stack_check = false` to
          the static-lib module.  Without these flags the
          resulting `.a` carries unresolved `__tls_get_addr` +
          `__zig_probe_stack` references that break the SHARED
          `libsemantos.so` wrapper the Flutter FFI plugin
          builds via the Android NDK linker.  Verified the
          three FFI surfaces (semantos_init / semantos_version
          / semantos_execute_script) remain byte-identical to
          the host build's exports.

        * `platforms/flutter/semantos_ffi/android/CMakeLists
          .txt` — added a SHARED-library shim
          (`semantos_ffi/android/stub.c` + `--whole-archive`
          link block) so Dart FFI's
          `DynamicLibrary.open('libsemantos.so')` succeeds.
          The static archive on its own isn't packageable into
          an APK; the wrapper preserves + re-exports every
          kernel symbol through the .so.

        * `apps/oddjobz-mobile/android/app/build.gradle.kts` +
          `platforms/flutter/semantos_ffi/android/build.gradle`
          — declared `ndk { abiFilters … }` for the three
          supported ABIs, enabled core library desugaring
          (required by `flutter_local_notifications` from
          D-O5m.followup-9 Phase C), and added a `packaging
          .resources.pickFirsts` rule for the
          bouncycastle/jspecify META-INF collision.

        * `apps/oddjobz-mobile/pubspec.yaml` — added
          `dependency_overrides: record_linux: ^1.0.0` to work
          around an upstream `record` package resolver bug
          where the 5.x branch declares loose constraints on
          record_linux 0.7.x but the platform-interface 1.5.0
          API broke compatibility.  Documented in the runbook's
          troubleshooting section so future bumps are
          self-service.

        * `docs/operator-runbooks/mobile-build-and-pair.md` —
          end-to-end walkthrough with sections B1-B11:
          prerequisites (Flutter ≥ 3.41 / adb / zig 0.15.2 /
          bun / cloudflared), one-time phone setup, brain build,
          native-libs build, HTTPS configuration (cloudflared
          recommended; mkcert + Android trust import as the
          offline alternative because device-pair v2 enforces
          `https://`/`wss://`), brain start, pair-token
          generation via `brain device pair`, APK build/install,
          phone pair flow, three smoke tests in order
          (REPL pull-to-refresh / WSS live-tick / voice command
          end-to-end), and a troubleshooting matrix that covers
          every failure mode the development cycle uncovered.
          Push notifications are explicitly OUT OF SCOPE — the
          runbook documents the placeholder behaviour from
          D-O5m.followup-9 Phase C and points at the planned
          sovereign-push refactor (Phase D).

        * `scripts/smoke-test-mobile.sh` — optional one-shot
          driver that automates brain + android-libs + APK builds
          in parallel, starts cloudflared + brain, mints the
          pair token, renders the QR via qrencode, and waits
          for the operator to complete the phone-side pair
          flow.  Tears down background processes via a trap on
          exit/INT/TERM.

        * Glossary entries added: `mobile-build-android-script`,
          `mobile-pair-and-smoke`.

      Verified end-to-end: `flutter build apk --debug` produces
      a 174 MB APK containing `lib/<abi>/libsemantos.so` for
      all three ABIs.  The phone-side smoke tests (Tests 1+2+3
      in the runbook) need a physical device connected; the
      script terminates with a printed QR + instructions at
      the same point a human operator would.

  - id: D-OPS.smoke-test-bug-pass-1
    title: "Smoke-test friction-removal pass #1 — 16 fixes from first hardware run"
    phase: "OPS"
    status: done
    owner: null
    deps: [D-OPS.mobile-smoke-test]
    pr_url: null
    closed_by_pr: fix/smoke-test-pass-1
    note: |
      First full end-to-end smoke test of the mobile shell against
      a Semantos Brain + cloudflared tunnel + a real Android phone
      SUCCEEDED (the phone paired, fetched a job, rendered the
      JobDetail FSM action buttons).  But the path to success
      surfaced 16 bugs.  This deliverable closes them.

      Land set:

        #1-5 (in-tree pickups from the live debugging session,
        committed as the first commit on the branch):
          1. cmdHeadersServe ServeContext construction-site fix
             (deferred to live with WH-Producer WIP).
          2. cmdServe cert_store unwrap guard — moved attachment
             acceptor wiring AFTER cert_store init so the "absent"
             message reflects reality.
          3. device_pair_http bearer minting — POST returns a 30-day
             bearer alongside the cert ids; mobile shell can hit
             /api/v1/repl directly post-pair.
          4. PairingScreen keyboard overflow — SafeArea +
             SingleChildScrollView with viewInsets-aware padding.
          5. _baseUrlFromBrainEndpoint URL bug — strips ALL path
             segments instead of just two; no more /api/api/v1/repl.

        #6-16 (this PR):
          6. REPL splitArgs honours double-quoted strings.
          7. resolveDataDir reads config.json:shell.data_dir with
             ~ expansion (was structurally dead code).
          8. `brain device init` — real subcommand bootstraps
             operator-root priv + cert in one step (path A).
          9. brain REPL embedded-vs-daemon banner (path B; full socket
             routing deferred).
          10. Android cross-compile cache isolation — script-private
              --cache-dir + --global-cache-dir.
          11. cmdServe per-connection HTTP read+write timeout (30s)
              — accept loop no longer blocks on a stuck request.
          12. Mobile shell — Dio with 10s connect/receive/send
              timeouts.
          13. WSS reconnect on resume + 30s heartbeat — WidgetsBinding
              observer + forceReconnect() on AppLifecycleState.resumed.
          14. Runbook §B5 — ngrok promoted to recommended; cloudflared
              zombie warning + named-tunnel-for-prod pointer.
          15. Runbook §B7-B10 — APK build precedes pair token mint
              (5-min TTL pacing fix).
          16. PairingScreen decode_token — accept either bare token
              OR full URL via strict Uri parsing + substring fallback.

      Tests: 20 new fix-anchored tests on the Semantos Brain side (1097 → 1113
      passes on `zig build test --summary all`), 5 new dart tests on
      the mobile side (419 → 424 passes).  No regressions on the
      bun / dart / loom / brain surfaces.  No test-process zombies
      after run.

  - id: D-DOG.1.0c
    title: "Layer 1 promotion + cell-DAG graph materialisation (jobs / sites / customers / attachments) + BKDS per-cell signing"
    phase: "DOG"
    status: done
    owner: null
    deps: [D-O5, D-O5m]
    pr_url: null
    closed_by_pr: feat/d-dog-1.0c-phase5-migration-docs
    note: |
      Promoted oddjobz from a single flat-row ratify into a connected
      cell-DAG: every ratified proposal mints site / customer / job /
      attachment cells linked by typed edges, with each cell signed by
      a BRC-42 BKDS-derived per-cell key.  Reference PRD:
      docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md.

      Phases (10 PRs across Phases 1-4 + this PR for Phase 5):

        Phase 1 — v2 cell schemas
          PR #367: job.v2 + customer.v2 + site.v2 + attachment.v2
                   schemas + typeHashRegistry bumps.

        Phase 2A — graph translator + 4 view stores
          PR #369: oddjobz_ratify_handler.zig graph rewrite.
          PR #370: sites_store_fs.zig + lookup-or-mint by
                   normalisedAddress.
          PR #371: customers_store_fs.zig + lookup-or-mint dedupe
                   ladder (phone → email → name+role+site).
          PR #372: jobs_store_fs.zig + attachments_store_fs.zig
                   v2 read+append paths.

        Phase 2B — TS + cross-store query + parity oracles
          PR #373: TS-side `BrainRpcCellWriter` FS-fallback graph
                   build mirrors the Zig handler.
          PR #374: cross-store query handler
                   (oddjobz.find_jobs_at_site,
                    oddjobz.find_jobs_for_customer,
                    oddjobz.list_*).
          PR #375: cross-language byte-parity oracles
                   (cellID generation parity Zig ↔ TS).
          PR #376: TS-side dedupe ladder + idempotency index.

        Phase 3 — helm + mobile graph-aware UI
          PR #377: helm JobList renders site/customer/due/photos.
          PR #380: helm site-pivot route /sites/[id].
          PR #379: helm customer-pivot route /customers/[id].
          PR #389: helm job-detail with attachments view.
          PR #378: mobile JobList graph-aware row.
          PR #386: mobile site-pivot screen.
          PR #388: mobile customer-pivot screen.
          PR #387: mobile attachment screen + inline PDF viewer.

        Phase 4 — BKDS per-cell signing
          PR #390: hat_bkds.zig + verifier + resign-pending admin
                   verb.  Per-cell derivation via
                   protocolID="oddjobz.cell-sign/v1",
                   keyID=<cell-content-hash>.  One root, KEK-encrypted;
                   derived keys discarded after one signature.

        Phase 5 — migration + docs (this PR)
          G.1: `legacy migrate-to-graph` verb walks v1 jobs.jsonl,
               matches each row to its source proposal via the
               receipt store, re-ratifies through the Phase 2A.4
               graph-walk handler.  Un-matchable rows flagged
               legacy_unsigned in a sidecar marker file.
          G.2: helm + mobile JobList paint a "legacy" pill on rows
               with the legacy_unsigned flag.
          H.1: docs/operator-runbooks/cell-signing-bkds.md — BKDS
               recovery + key re-derivation runbook.
          H.2: docs/operator-runbooks/job-graph.md — graph
               navigation guide for operators.
          H.3: this canon update.
          H.4: docs/operator-runbooks/dogfood-gmail.md — post-
               Layer-1 promotion section.
          H.5: docs/canon/sovereignty-cell-signing.md — what hot-key
               compromise means; cold-tier deferred until value
               enters the cell layer.

      Out of scope (deferred):
        - Cold-tier multisig vault (deferred to post-Stripe-
          integration when operator-held value enters cells).
        - BSV L1 anchoring (D-DOG.1.0e — separate deliverable).
        - Quote / Visit / Invoice / Message graph-promotion (Phase 6+).

  # ── Intent Reducer & Grammar Automation (2026-05-09) ─────────────────────

  - id: I-1
    title: "Intent type audit — confirm all fields align with taggedFacts output shape"
    phase: "intent-reducer"
    status: pending
    owner: todd
    deps: []

  - id: I-2
    title: "Trivium pass 1: Grammar — taggedFacts → taxonomy.what"
    phase: "intent-reducer"
    status: pending
    owner: bert
    deps: [I-1]
    file: runtime/intent/src/reducer/grammar-pass.ts

  - id: I-3
    title: "Trivium pass 2: Logic — taggedFacts + action → taxonomy.how"
    phase: "intent-reducer"
    status: pending
    owner: bert
    deps: [I-2]
    file: runtime/intent/src/reducer/logic-pass.ts

  - id: I-4
    title: "Trivium pass 3: Rhetoric — taggedFacts → TaggedCategory + action"
    phase: "intent-reducer"
    status: pending
    owner: bert
    deps: [I-3]
    file: runtime/intent/src/reducer/rhetoric-pass.ts

  - id: I-5
    title: "Quadrivium pass 1: Arithmetic — numeric fields → SIRConstraint value[]"
    phase: "intent-reducer"
    status: pending
    owner: bert
    deps: [I-4]
    file: runtime/intent/src/reducer/arithmetic-pass.ts

  - id: I-6
    title: "Quadrivium pass 2: Geometry — location fields → taxonomy.where"
    phase: "intent-reducer"
    status: pending
    owner: bert
    deps: [I-5]
    file: runtime/intent/src/reducer/geometry-pass.ts

  - id: I-7
    title: "Quadrivium pass 3: Music — urgency/deadline → SIRConstraint temporal[]"
    phase: "intent-reducer"
    status: pending
    owner: bert
    deps: [I-6]
    file: runtime/intent/src/reducer/music-pass.ts

  - id: I-8
    title: "Quadrivium pass 4: Astronomy — domain flag + confidence → GovernanceContext"
    phase: "intent-reducer"
    status: pending
    owner: bert
    deps: [I-7]
    file: runtime/intent/src/reducer/astronomy-pass.ts

  - id: I-9
    title: "Pass composer — reduce(passes, emptyPartialIntent, (acc, pass) => pass(...))"
    phase: "intent-reducer"
    status: pending
    owner: bert
    deps: [I-2, I-3, I-4, I-5, I-6, I-7, I-8]
    file: runtime/intent/src/reducer/index.ts

  - id: I-10
    title: "Rejection relay — relay SIR rejection reason to each pass on retry"
    phase: "intent-reducer"
    status: pending
    owner: bert
    deps: [I-9]
    file: runtime/intent/src/reducer/rejection-relay.ts

  - id: I-11
    title: "Integration test: trades vertical — AccumulatedJobState → Intent → Cell round-trip"
    phase: "intent-reducer"
    status: pending
    owner: bert
    deps: [I-9, I-10]
    file: runtime/intent/tests/reducer-trades.test.ts

  - id: I-12
    title: "Integration test: SCADA vertical — same round-trip with ControlSystemsLexicon"
    phase: "intent-reducer"
    status: pending
    owner: bert
    deps: [I-9, I-10]
    file: runtime/intent/tests/reducer-scada.test.ts

  - id: I-13
    title: "Wire reducer into chatService.ts (oddjobtodd) replacing direct AccumulatedJobState writes"
    phase: "intent-reducer"
    status: pending
    owner: todd
    deps: [I-11]
    file: apps/oddjobtodd/src/lib/services/chatService.ts

  - id: G-1
    title: "Pask store seed — pre-load known grammar fields as cells in grammar inference store"
    phase: "grammar-automation"
    status: pending
    owner: todd
    deps: []
    file: extensions/extraction/src/inference/pask-seed.ts

  - id: G-2
    title: "Pask TaxonomyMapper — Store.interact() propagation replaces Levenshtein heuristic"
    phase: "grammar-automation"
    status: pending
    owner: todd
    deps: [G-1]
    file: extensions/extraction/src/inference/pask-taxonomy-mapper.ts

  - id: G-3
    title: "API probe runner — live endpoint → EntityGraph"
    phase: "grammar-automation"
    status: pending
    owner: todd
    deps: []
    file: extensions/extraction/src/inference/api-probe.ts

  - id: G-4
    title: "Swagger/OpenAPI ingester — static spec → EntityGraph"
    phase: "grammar-automation"
    status: pending
    owner: todd
    deps: []
    file: extensions/extraction/src/inference/swagger-ingester.ts

  - id: G-5
    title: "Grammar automation entry point — orchestrates probe → Pask → Diff → Compose"
    phase: "grammar-automation"
    status: pending
    owner: todd
    deps: [G-2, G-3, G-4]
    file: extensions/extraction/src/auto-grammar.ts

  - id: G-6
    title: "AFFINE manifest wrapper — wraps composed grammar in ExtensionManifest draft"
    phase: "grammar-automation"
    status: pending
    owner: todd
    deps: [G-5]
    file: extensions/extraction/src/manifest-wrapper.ts

  - id: G-7
    title: "CLI entry point — zig build auto-grammar -- --api / --swagger"
    phase: "grammar-automation"
    status: pending
    owner: todd
    deps: [G-6]
    file: runtime/semantos-brain/src/auto_grammar_cli.zig

  - id: G-8
    title: "Integration test: PropertyMe swagger → ExtensionGrammar roundtrip"
    phase: "grammar-automation"
    status: pending
    owner: todd
    deps: [G-5]
    file: extensions/extraction/tests/propertyme-auto.test.ts

  - id: G-9
    title: "Integration test: SCADA probe → ExtensionGrammar roundtrip"
    phase: "grammar-automation"
    status: pending
    owner: todd
    deps: [G-5]
    file: extensions/extraction/tests/scada-auto.test.ts

  - id: T-1
    title: "Chapter 31: Extension Grammar"
    phase: "grammar-automation"
    status: merged
    owner: claude
    file: docs/textbook/31-extension-grammar.md

  - id: T-2
    title: "Chapter 32: Trivium/Quadrivium Intent Reducer"
    phase: "intent-reducer"
    status: merged
    owner: claude
    file: docs/textbook/32-trivium-quadrivium-intent-reducer.md

  - id: T-3
    title: "Chapter 33: Automated Grammar Synthesis"
    phase: "grammar-automation"
    status: merged
    owner: claude
    file: docs/textbook/33-automated-grammar-synthesis.md

  - id: D-Lift-oddjobz
    title: "Carve oddjobz code out of brain-core into extensions/oddjobz/"
    phase: "cartridge-distro"
    status: pending
    owner: todd
    deps: []
    file: docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md
    note: |
      Move oddjobz_attention_handler, oddjobz_derivations, oddjobz_event_bus,
      oddjobz_query_handler, oddjobz_ratify_handler, oddjobz_ratify_walker,
      repl/oddjobz_cmds, intent_action_router, all jobs/quotes/invoices/
      customers/leads/visits FSMs + stores + resources handlers out of
      runtime/semantos-brain/src/ into extensions/oddjobz/. Gate: brain
      core compiles + runs with oddjobz unloaded; brain core with oddjobz
      loaded passes existing oddjobz_*_test.zig.

  - id: D-Lift-bsv-anchor
    title: "Carve wallet + headers + payment + refund into bsv-anchor-bundle cartridge"
    phase: "cartridge-distro"
    status: pending
    owner: todd
    deps: []
    file: docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md
    note: |
      Move wallet_op_http, wss_wallet*, payment_ledger, payment_verifier*,
      refund_tx*, output_store_fs, lmdb/output_store_lmdb,
      lmdb/derivation_state_store_lmdb, cli/wallet, header_store_fs,
      lmdb/header_store_lmdb, headers_sync, headers_http,
      resources/headers_handler, cli/headers out of brain-core into a
      bsv-anchor-bundle cartridge. Brain core falls back to no-op
      AnchorAdapter when bundle not loaded. Unblocks OSS pitch — substrate
      no longer ships BSV-baked-in.

  - id: D-Lift-wsite
    title: "Carve operator-site (WSITE1–5.5) into operator-site cartridge"
    phase: "cartridge-distro"
    status: pending
    owner: todd
    deps: []
    file: docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md
    note: |
      Move site_server, site_server/{reactor,util}, sites_store_{fs,lmdb},
      resources/sites_handler, site_config, resources/site_config_handler,
      operator_site_renderer, operator_profile{,_loader,_export,_exit},
      caddy_ask_server, caddy_template, sni_domain_map, domain_allowlist,
      cli/site out of brain-core into an operator-site cartridge. WSITE1–5.5
      phases collapse into one cartridge.

  - id: D-Distro-default-install
    title: "Define default brain install bundle of first-party substrate-exposing cartridges"
    phase: "cartridge-distro"
    status: pending
    owner: todd
    deps: []
    file: docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md
    note: |
      Manifest declaring which cartridges ship pre-loaded in the default
      brain install. Candidate bundle: identity/hat-setup, peer-pair,
      status-dashboard, minimal-talk. Each is a cartridge architecturally
      (loadable, removable) but ships with the default install by
      convention. Linux-distro analogue: Debian shipping bash + ls + cat.
      Build/CI plumbing. Composes on top of Phase 26G installer.

  - id: D-Manifest-canonical
    title: "Resolve three-format cartridge manifest ambiguity"
    phase: "cartridge-distro"
    status: in_progress
    owner: todd
    deps: []
    file: docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md
    note: |
      Phase 36A grammar JSON, extensions/<name>/package.json, BRC-102 —
      three candidate manifest formats. Pick canonical, migrate
      extensions to it, audit alignment with BRC-102. Sidequest 2 from
      docs/SHELL-CARTRIDGES-HATS.md §11.

      DECISION (2026-05-16, Todd): ONE manifest is the single source of
      truth — the brain-side on-disk extensions/<id>/manifest.json. The
      Flutter shell manifest + bundle envelope are GENERATED from it,
      never hand-edited. Domain flags unify on the brain allocation
      registry (core/constants/constants.json extensionPages); the
      shell domainFlag is derived, not independently allocated.

      RESOLVED for tessera (this commit):
        - tools/cartridge-manifest/generate.ts — reads
          cartridges/tessera/cartridge.json + constants.json
          extensionPages + docs/canon/lexicons.yml categories →
          emits packages/tessera_experience/assets/{manifest,bundle}.json
          deterministically (constants/generate.ts contract).
        - cartridges/tessera/cartridge.json extended so the shell
          manifest is fully derivable: per-verb category/hats/
          description, shellGrammar block, cellTypes block.
        - tessera shell domainFlag unified 0x000105 → 0x00010400
          (constants.json TESSERA_PAGE; collision-free vs jambox
          shell 0x000104=260 as parsed ints).
        - CI gate tests/gates/manifest-consistency.test.ts —
          `generate.ts --check` fails on drift; idempotency proven.
      PER-CARTRIDGE ROLLOUT (still pending): apply the same generator
      ownership to oddjobz + jambox shell assets (currently still
      hand-written); retire the hollow validateExtensionManifest()
      passthrough in core/protocol-types (ignores verbs/consumes —
      ecosystem-wide, separate scoped change); audit BRC-102 alignment
      and reduce package.json to npm-identity only.

  # ── Wave Tessera (per docs/canon/commissions/wave-tessera.md) ──
  - id: V0.1
    title: "Tessera domain flag page + greenfield CI gate"
    phase: tessera
    status: completed
    owner: wave-tessera-orchestrator
    deps: []
    pr_url: ""
    note: |
      Allocates tessera page at 0x00010400 with seven hat sub-pages
      (producer 0x01, field-worker 0x1A, distributor 0x02,
      dock-handler 0x2A, retailer 0x03, club-member 0x04,
      consumer 0x05). Codegen flows to TS + Zig via the existing
      extensionPages section in core/constants/constants.json. Lands
      CI gate tests/gates/no-tessera-in-brain-core.test.ts enforcing
      TESSERA-CARTRIDGE.md §0.1 greenfield discipline (initially
      passes vacuously). No matrix cell — substrate plumbing + gate.
  - id: V0.2
    title: "Tessera cartridge scaffold"
    phase: tessera
    status: completed
    owner: wave-tessera-orchestrator
    deps:
      - V0.1
    pr_url: ""
    note: |
      Lands cartridges/tessera/ with the canonical cartridge directory
      layout mirroring extensions/bsv-anchor-bundle/: manifest.json
      (Phase 36A ExtensionManifest declaring 13 verbs + 4 consumes
      adapter interfaces), release.config.ts (dual-artifact release
      pipeline), package.json + tsconfig.json, src/index.ts +
      src/manifest.ts + src/capabilities.ts (8 caps on the 0x000104xx
      page at low byte 0x10..0x17, above the V0.1 hat byte range),
      and empty src/{object-types,flows,prompts,walkers,adapters}/
      placeholders for V0.4 / V0.5 / V0.3 fill-ins. Test acceptance:
      tests/manifest.test.ts — 9 assertions covering verb count,
      consume interfaces, capability page alignment, uniqueness,
      and the verb ↔ capability 1:1 cross-check.
  - id: V0.3
    title: "Tessera walker registration (13 verbs via verb_dispatcher)"
    phase: tessera
    status: in_progress
    owner: wave-tessera-orchestrator
    deps:
      - V0.2
    pr_url: ""
    matrix_cell:
      adapter: A11-tessera
      axis: D-cap
      transition: "✗ → ⚠"
    note: |
      cartridges/tessera/brain/tessera_walkers.zig — 14 walkers (13
      cartridge.json verbs + tessera.open-container) + registerAll over
      the real verb_dispatcher.Registry, wrapping tessera_store.zig
      (in-memory provenance state machine). Mirrors
      cartridges/chess/brain/chess_walkers.zig. Wired into
      runtime/semantos-brain/build.zig (module + inline test +
      substrate_test_step), outside src/ — greenfield §0.1 holds.
      zig build test-substrate green (registration count, spine,
      blend-conservation refusal, tamper one-shot, malformed params).
      PRE-BOOT BAR: registerAll exists + dispatcher-tested. Remaining
      for `completed`: boot-time registerAll + Store construction in
      serve/cmdServe + wss_wallet.Backend (shared-brain-boot-path step
      deferred for user review, chess parity); + the cap.tessera.*
      mirror (uncapped now, chess Phase-1 parity).
  - id: V0.5
    title: "Tessera cell-types + StorageAdapter-consumer stores"
    phase: tessera
    status: in_progress
    owner: wave-tessera-orchestrator
    deps:
      - V0.1
      - V0.6
    pr_url: ""
    matrix_cell:
      adapter: A11-tessera
      axis: D-sub
      transition: "✗ → ⚠"
    note: |
      cartridges/tessera/brain/tessera_cells.zig — 10 cell types with
      linearity classes machine-checked against the REAL cell-engine
      kernel (linearity.zig checkLinearity + getLinearity/getDomainFlag/
      getTypeHash header round-trip; constants.zig offsets). Marquee:
      tamper-event LINEAR ⇒ kernel forbids DROP/DUP. Plus
      cartridges/tessera/brain/src/store-adapter.ts — the
      provenance-cell persistence contract consuming ONLY
      @semantos/protocol-types StorageAdapter (the greenfield-correct
      alternative to oddjobz pre-DLO.3 *_store_lmdb.zig), and CI gate
      tests/gates/tessera-adapter-consumption.test.ts (green) enforcing
      §0.1 #2. Remaining for `completed`: octave-registry registration
      at brain boot — no pre-boot seam exists (kernel octave.zig is
      addressing, cell_registry.zig is brain-core runtime-populated;
      chess/oddjobz do no cartridge→octave registration). That is the
      shared-brain-boot-path step deferred for user review.
  - id: V0.4
    title: "Tessera lexicon canon registration"
    phase: tessera
    status: completed
    owner: wave-tessera-orchestrator
    deps:
      - V0.2
    pr_url: ""
    matrix_cell:
      adapter: A9-tessera
      axis: D-lex
      transition: "✗ → ⚠"
    note: |
      Registers the tessera lexicon across the canonical surfaces:
      docs/canon/lexicons.yml (status: built, headerInjective
      obligation pending pointing at the V5.7 Lean theorem),
      core/semantos-sir/src/lexicons.ts (TesseraLexicon added to
      ALL_LEXICONS with 13 categories from
      TESSERA-CARTRIDGE.md §3.4), core/semantos-sir/src/index.ts
      (TesseraLexicon + TesseraCategory re-exports),
      proofs/lean/Semantos/Lexicons/Tessera.lean (skeleton with
      tesseraHeader_injective using `sorry` until V5.7 lands the
      proof), and cartridges/tessera/brain/src/lexicon.ts (cartridge-side
      re-export mirroring extensions/oddjobz/src/lexicon.ts).
      Test acceptance: 11 TesseraLexicon tests in
      core/semantos-sir/src/__tests__/tessera-lexicon.test.ts
      (mirrors the Trades L1-L10 pattern + L11 for category-canon
      drift detection); existing trades/brap lexicon tests
      (including the cross-lexicon injectivity check on
      ALL_LEXICONS) continue passing.
  - id: V0.6
    title: "Tessera Zig project scaffold"
    phase: tessera
    status: completed
    owner: wave-tessera-orchestrator
    deps:
      - V0.2
    pr_url: ""
    note: |
      Lands cartridges/tessera/brain/zig/ with the canonical Zig scaffold
      mirroring extensions/oddjobz/zig/ (the post-DLO.2 precedent):
      build.zig + build.zig.zon + src/root.zig. The root module
      declares VERSION="0.0.1" and EXTENSION_ID="tessera" as the
      single source of truth that the generic cartridge loader
      (DLO.1) reads at brain boot, plus two scaffold tests. Real
      walker bodies, cell-type schemas, store wrappers, NATS event
      wiring, and hardware-peer integration land in the post-loader
      cohort (V0.3 / V0.5 / V3 / V4). Greenfield-side mirror of what
      DLO.2 establishes for the oddjobz carve. Test gate:
      `cd cartridges/tessera/zig && zig build test -j1 --summary all`
      → 3/3 steps succeeded; 2/2 tests passed.
  - id: V5.7
    title: "tesseraHeader_injective ritual obligation"
    phase: tessera
    status: completed
    owner: wave-tessera-orchestrator
    deps:
      - V0.4
    pr_url: ""
    matrix_cell:
      adapter: A9-tessera
      axis: D-lex
      transition: "⚠ → ✓"
    note: |
      Discharges the V0.4 skeleton `sorry` in
      proofs/lean/Semantos/Lexicons/Tessera.lean by exhaustive case
      analysis (analogue of tradesHeader_injective). Each of the
      13 × 13 = 169 category pairs is either reflexively equal or
      distinguished by a literally-distinct header string;
      `cases c₁ <;> cases c₂ <;> simp_all [tesseraHeader]` closes
      every branch. Build gate: `cd proofs/lean && lake build
      Semantos.Lexicons.Tessera` → built with zero `sorry`/`admit`
      warnings. Flips `docs/canon/lexicons.yml` `tesseraHeader_injective`
      status `pending → proven`. Substrate-level theorems
      (renderCard_deterministic, renderCard_depends_only_on_render_
      fields, renderCard_distinguishes_categories) now apply at
      `Patch TesseraCategory` by specialisation.
  - id: V5.2
    title: "tessera.tamper_one_shot Lean theorem"
    phase: tessera
    status: completed
    owner: wave-tessera-orchestrator
    deps:
      - V0.4
    pr_url: ""
    matrix_cell:
      adapter: A9-tessera
      axis: D-form
      transition: "improves toward ✓"
    note: |
      Lean theorem `tessera_tamper_one_shot` in
      proofs/lean/Semantos/Lexicons/Tessera/TamperOneShot.lean:
      once `tamper_loop = broken`, no patch sequence yields
      `intact`. Models the tamper-loop FSM abstractly as
      `TamperState := intact | broken` with single transition
      `TamperPatch.markBroken`; proves the FSM has a single sink
      state by induction over the patch list. The executor-level
      K1 in proofs/lean/Semantos/Theorems/LinearityK1.lean closes
      the loop by showing the LINEAR substrate cannot bypass FSM
      application. Build gate: `lake build
      Semantos.Lexicons.Tessera.TamperOneShot` → 2/2 jobs, zero
      `sorry`/`admit` warnings.
  - id: V5.5
    title: "tessera.custody_linear Lean theorem"
    phase: tessera
    status: completed
    owner: wave-tessera-orchestrator
    deps:
      - V0.4
    pr_url: ""
    matrix_cell:
      adapter: A9-tessera
      axis: D-form
      transition: "improves toward ✓"
    note: |
      Lean theorem `tessera_custody_linear` in
      proofs/lean/Semantos/Lexicons/Tessera/CustodyLinear.lean: a
      case / pallet / shipment cell has at most one open custodian
      at any time. Models the custody-transfer FSM as
      `CustodyState := unowned | heldBy OperatorCertId` with
      patches `transferTo op | release`; the invariant is encoded
      at the type level (no `heldByMany` constructor). `cases s
      <;> simp [openCustodiansCount]` discharges the count
      bound. The executor-level K1 closes the loop by refusing
      DUP on the LINEAR case cell. Build gate: `lake build
      Semantos.Lexicons.Tessera.CustodyLinear` → 2/2 jobs, zero
      `sorry`/`admit` warnings.
  - id: V5.3
    title: "tessera.care_score_monotonic Lean theorem"
    phase: tessera
    status: completed
    owner: wave-tessera-orchestrator
    deps:
      - V0.4
    pr_url: ""
    matrix_cell:
      adapter: A9-tessera
      axis: D-form
      transition: "improves toward ✓"
    note: |
      Lean theorem `tessera_care_score_monotonic` in
      proofs/lean/Semantos/Lexicons/Tessera/CareScoreMonotonic.lean:
      the score sequence is non-increasing as care-events arrive.
      Models the care-event AFFINE chain as `List CareEvent` with a
      `severity : Nat` per event; `careScore` folds with saturating
      Nat subtraction. Two theorems: the single-event monotonicity
      (`tessera_care_score_monotonic`) and the list-extension
      corollary (`tessera_care_score_monotonic_list`) that the V2.2
      Postgres view consumes. Proof: induction on the prefix list,
      delegating to `simp [careScore]` to unfold the fold and
      relying on built-in Nat subtraction saturation. The
      executor-level K1 AFFINE closes the gap by showing the
      substrate cannot retract a care-event cell. Build gate:
      `lake build Semantos.Lexicons.Tessera.CareScoreMonotonic`
      → 2/2 jobs, zero `sorry`/`admit` warnings.
  - id: V5.4
    title: "tessera.blend_conservation Lean theorem (K15 instantiation)"
    phase: tessera
    status: completed
    owner: wave-tessera-orchestrator
    deps:
      - V0.4
    pr_url: ""
    matrix_cell:
      adapter: A9-tessera
      axis: D-form
      transition: "improves toward ✓"
    note: |
      Lean theorem `tessera_blend_conservation` in
      proofs/lean/Semantos/Lexicons/Tessera/BlendConservation.lean:
      at any valid blend transition,
      Σinput.amount = Σoutput.amount. Models the blend FSM with a
      `BlendOp` structure that carries the conservation proof as a
      type-level field — the smart constructor `mkBlend` produces a
      single-output blend whose amount equals the input total,
      discharging the proof at construction. Two theorems:
      `tessera_blend_conservation` re-exposes the invariant for any
      BlendOp, `mkBlend_conserves` confirms the canonical
      constructor satisfies it. Maps to proposed K15
      (capability-UTXO conservation) per PROOF-COVERAGE.md. The
      production `tessera.blend` walker must construct BlendOps via
      `mkBlend` or supply the conservation proof explicitly; either
      way, no walker invocation can mint or burn volume. Build
      gate: `lake build Semantos.Lexicons.Tessera.BlendConservation`
      → 2/2 jobs, zero `sorry`/`admit` warnings.
  - id: V5.6
    title: "tessera.scan_evidence_present Lean theorem"
    phase: tessera
    status: completed
    owner: wave-tessera-orchestrator
    deps:
      - V0.4
    pr_url: ""
    matrix_cell:
      adapter: A9-tessera
      axis: D-form
      transition: "improves toward ✓ (D-Dform-tess complete with V5.6)"
    note: |
      Lean theorem `tessera_scan_evidence_present` in
      proofs/lean/Semantos/Lexicons/Tessera/ScanEvidencePresent.lean:
      if `renderCareScore` returns Some, the bottle's chain contains
      ≥1 scan-event cell. Models the chain as `List ChainCell` with
      `scanEvent | otherCell` distinction (the actual cell types are
      out of scope at the theorem level); `renderCareScore` gates
      on `hasScanEvidence`. Two theorems:
      `tessera_scan_evidence_present` (forward direction) and
      `tessera_no_scan_no_view` (contrapositive — what the V2.3 view
      actually consumes). Proof: case analysis on
      `hasScanEvidence chain` plus `simp [renderCareScore]`. The
      executor-level K1 RELEVANT closes the gap by showing the
      substrate cannot discard a scan-event cell once minted. With
      V5.6 the D-Dform-tess set of six theorems (V5.2–V5.7) is
      complete; A9 Tessera × D-form moves to ✓. Build gate: `lake
      build Semantos.Lexicons.Tessera.ScanEvidencePresent` → 2/2
      jobs, zero `sorry`/`admit` warnings. Whole-wave Lean
      composition: `lake build Semantos.Lexicons.Tessera{,.TamperOneShot,.CustodyLinear,.CareScoreMonotonic,.BlendConservation,.ScanEvidencePresent}`
      → 9/9 jobs successful.
  - id: V1.0
    title: "Tessera shell wire-in (semantos-shell experience package)"
    phase: tessera
    status: completed
    owner: wave-tessera-orchestrator
    deps:
      - V0.2
      - V0.4
    pr_url: ""
    note: |
      Wires tessera into the existing semantos-shell Flutter PWA,
      mirroring packages/oddjobz_experience + packages/jam_experience.
      Lands packages/tessera_experience/ (pubspec, lib barrel,
      intents.dart with 6 StructuredIntent subclasses,
      tessera_intent_grammar.dart implementing IntentGrammar with the
      GBNF fragment + 8 lexicon entries + onIntent recogniser,
      tessera_screen.dart placeholder, manifest_loader.dart,
      assets/manifest.json + assets/bundle.json in the Flutter shell
      manifest format, test/manifest_parse_test.dart). Adds hatRoles
      to the brain-side Phase 36A manifest
      (cartridges/tessera/cartridge.json) — six operator hats
      (producer, field-worker, distributor, dock-handler, retailer,
      club-member); tessera.consumer intentionally excluded (it is
      the standalone anonymous NFC-tap PWA, V1.6). Shell wiring:
      apps/semantos/pubspec.yaml dep, main.dart import +
      TesseraManifestLoader.provisionFromAsset + TesseraIntentGrammar
      registration, semantos_router.dart import + /tessera route +
      home-picker icon/route maps. After this, tessera surfaces in
      the shell home picker, the HatSwitcher offers all six operator
      hats, and /tessera routes to the placeholder screen. Gates:
      `flutter analyze` clean on tessera_experience + shell wiring
      files; `flutter test` 2/2 (manifest schema-parse + bundle
      envelope). NOTE — the interim manifest-layer drift this entry
      originally recorded (shell domainFlag 0x000105 vs brain
      0x00010400) is RESOLVED by D-Manifest-canonical: the shell
      assets are now generated from the canonical brain manifest and
      the domainFlag is unified on 0x00010400. The hand-written shell
      manifest this V1.0 commit added has been superseded by the
      generator output (tools/cartridge-manifest/generate.ts).

  # Layer-Collapse batch (post-V1, opportunistic). Five small unlocks that
  # expose substrate properties the code already satisfies but the surfaces
  # do not yet ship. Provenance: 2026-05-20 Gemini conversation fact-check
  # against semantos-core. Each is afternoon-to-day-sized and additive — no
  # existing K-invariants change, no schema migrations required.
  - id: D-LC1
    title: "Raw cell-over-HTTP endpoint (layer collapse for read paths)"
    phase: opportunistic
    status: merged
    owner: "loop-layer-collapse"
    deps: []
    matrix_cell: "U7×C"
    pr_url: null
    note: |
      `GET /api/v1/cell/<sha256hex>` on the brain HTTP surface returns the
      raw 1024-byte cell as `application/x-semantos-cell` straight out of
      LmdbCellStore (no JSON envelope, no SignedBundle wrapping). The on-disk
      format already equals the wire format equals the in-memory format —
      this endpoint is the first read path that exercises that identity.

      MIME-type + header surface specified normatively in
      `docs/spec/protocol-v0.5.md` §3.8 (layer-collapse HTTP transport).

      Landed:
      - `runtime/semantos-brain/src/cell_raw_http.zig` — Acceptor + pure
        helpers `decodeHashHex`, `parsePath`. 5 inline tests for the
        path-parse + hex-decode logic.
      - `runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig` — added
        `getCell(hash) StoreError!?[CELL_BYTES]u8` (copies 1024 bytes out of
        an LMDB read txn). Not in the CellStore vtable yet — the wider
        vtable change doesn't pay for itself for a single read path.
      - `runtime/semantos-brain/src/site_server.zig` — `cell_raw_acceptor`
        optional field + `attachCellRawAcceptor`.
      - `runtime/semantos-brain/src/site_server/reactor.zig` —
        `reactorHandleCellRaw` + dispatch entry for `/api/v1/cell/`.
        Returns 404 (acceptor absent or hash unknown), 400 (malformed
        path), 401 (bearer), 405 (non-GET), 200 (raw cell bytes with
        `x-cell-sha256` echo + `cache-control: immutable`).
      - `runtime/semantos-brain/src/cli/serve.zig` — cmdServe constructs
        the Acceptor when `entity_cell_store_impl_serve` AND `token_store`
        are both up.
      - `build.zig` — module + import + inline-test step.

      Build: `zig build --summary all` clean. Tests: cell_raw_http inline
      tests pass (5/5). Pre-existing unix_socket flake unrelated.
      Touches axis C on U7 by giving VFS its first cross-node read surface
      that isn't U2 (SignedBundle) or U6 (multicast).
  - id: D-LC2
    title: "Lean test-vector conformance (load JSON, run against PDA)"
    phase: opportunistic
    status: merged
    owner: "loop-layer-collapse"
    deps: []
    matrix_cell: "U1×D-form"
    pr_url: null
    note: |
      Made `proofs/vectors/plexus-vectors.json` (28 vectors) the literal
      source of truth for the K2/K3 plexus conformance check.

      Landed:
      - `core/cell-engine/tests/lean_vector_conformance.zig` — new test
        that opens `../../proofs/vectors/plexus-vectors.json`, parses each
        entry against a typed Zig schema (`Vector` / `VectorSetup` /
        `VectorOp` / `VectorExpected`), reconstructs each main_stack cell
        via `makeTestCell`, pushes the operation argument (capability /
        owner_id / domain_flag / type_hash) onto the main stack, then
        dispatches via `plexus.executePlexus`. Compares `result`,
        `error_code`, and `main_sp_after` against the JSON expectation.
      - `core/cell-engine/build.zig` — registers the test under both
        `zig build test-lean-vectors` (dedicated step) and the default
        `zig build test` aggregator.

      Result: 28/28 plexus vectors round-trip through the live PDA. Full
      cell-engine suite: 408/408 tests pass (66/66 steps).

      Scope note (corrected 2026-05-20 mid-implementation): the original
      D-LC2 note said "brain's executor path" but brain only imports
      cell-engine's *storage* modules (slot_store / derivation_state /
      headers / header_store / output_store); the PDA + linearity + plexus
      executor runs only inside cell-engine-embedded.wasm. The conformance
      test therefore lives in cell-engine where the executor is. The brain
      layer's bridge is the WASM instantiation itself, which the
      cell-engine reproducible-build hash already guarantees end-to-end.

      Known drift surfaced: 7 vectors (`K4_RESERVED_0xC9` through
      `K4_RESERVED_0xCF`) expect `reserved_opcode`, but those opcodes have
      since been implemented (`OP_READHEADER`, `OP_CELLCREATE`, `OP_DEMOTE`,
      `OP_READPAYLOAD`, `OP_SIGN`, `OP_DECREMENT_BUDGET`, `OP_REFILL_BUDGET`).
      The test annotates them as `drift_reserved_implemented` and tolerates
      mismatch rather than failing — comment in the test points at the
      generator (`proofs/vectors/generate-vectors.ts:327-337`) for the
      follow-up regeneration. The unfollowed-up cost is that the JSON
      doesn't yet test the actual semantics of those 7 opcodes; the
      hand-coded `differential_conformance.zig` still covers them.

      Follow-up (2026-05-20) — linearity + stack vectors landed:
      `lean_vector_conformance.zig` now also loads
      `proofs/vectors/linearity-vectors.json` (24 vectors) and
      `proofs/vectors/stack-vectors.json` (6 vectors). The runner is split
      into a top-level dispatcher (`runVector`) that switches on
      `operation.type`, plus per-type runners:
      - `runPlexusVector` — unchanged, `plexus.executePlexus`
      - `runLinearityCheckVector` — top main_stack cell → `linearity.getLinearity`
        + `linearity.checkLinearity` for op ∈ {duplicate,discard,consume,
        swap,inspect}
      - `runStackOpVector` — `sdup`/`sdrop`/`spop` (enforced variant when
        `setup.enforcement_enabled = true`) for op ∈ {dup,drop,pop}
      - `runBoundsCheckVector` — asserts `MAIN_STACK_DEPTH = 1024` /
        `AUX_STACK_DEPTH = 256` for the depth targets; loops `spush` /
        `apush` of 1-byte payloads to force `stack_overflow` for the
        overflow targets
      - `runRoundtripCheckVector` — K7 `k7a_push_preserves_cell`: push a
        fully-populated `makeTestCell` cell, `spop`, byte-equality check
        on the popped payload. No kernel-snapshot ABI dependency (the
        wasm-host `kernel_snapshot_state` / `kernel_restore_state`
        ABI in `main.zig` is not exposed as a Zig API on `PDA`, and K7
        is push→pop equality so the snapshot path is not required for
        this vector).

      All 30 newly-covered vectors pass; no drift surfaced (every
      expected error_code, ok-path, and `main_sp_after` / `aux_sp_after`
      assertion matched live PDA + linearity behavior). Full cell-engine
      suite: 410/410 tests pass (was 408/408; +2 new test functions in
      the same file, one per JSON).

      Closes the gap noted in proofs/paper/P4.1-CAPSTONE.md:178 ("The Lean
      proofs operate on an abstract model. The Zig implementation is a
      separate codebase") for the plexus opcode set.
  - id: D-LC3
    title: "Owner-keyed secondary index on the cell store"
    phase: opportunistic
    status: merged
    owner: "loop-layer-collapse"
    deps:
      - D-A0
    matrix_cell: "U7×A"
    pr_url: null
    note: |
      Added an LMDB sub-DB on LmdbCellStore that maps
      `op_pkh(8B) ‖ owner_id(16B) ‖ cell_hash(32B) → empty` so callers can
      cursor-prefix-scan every cell hash owned by a given owner_id under a
      given operator. Empty-value keys; the (owner_id, hash) tuple lives in
      the key itself. Maintained atomically by `doPut` in the same write
      txn as the primary cell write; idempotent under retry (LMDB put of
      the same key+empty-value is a no-op).

      Landed:
      - `runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig`
        - new constants `OWNER_ID_BYTES = 16`,
          `OWNER_ID_OFFSET_IN_CELL = 62`, `OWNER_KEY_BYTES = 56`
        - new field `dbi_by_owner: lmdb.Dbi`, opened in `initInternal`
          alongside the primary `cells` DB (lazily created so existing
          stores get an empty index)
        - `buildOwnerKey` helper
        - `doPut` extended to write the owner-index entry in the same txn
          on both the not-found and already-present branches (opportunistic
          backfill for pre-D-LC3 cells)
        - `pub fn cellsByOwner(allocator, owner_id) ![][32]u8` —
          cursor prefix-scan, returns owned slice
      - `core/cell-engine/tests/lmdb_cell_store_conformance.zig` — three
        new D-LC3 tests:
        - returns hashes for one owner, omits others
        - operator-scoped (op_pkh isolation — same owner_id seen by two
          stores stays disjoint)
        - re-putting same cell does not duplicate the index entry

      Tests: 3/3 new D-LC3 tests pass. Pre-existing M1.5 padding test
      failure in the same file is unrelated (it tests `txn.get(dbi, &hash)`
      with a 32-byte key against a store that since W7.1 keys by 40 bytes —
      latent bug from the W7.1 op_pkh prefixing landing without updating
      this test). Out of D-LC3 scope.

      Cell-engine `zig build test`: 408/408 pass. Brain `zig build test`:
      1832/1876 pass, 44 skipped.

      Follow-up landed (D-LC3 follow-up — pre-D-LC3 backfill bin):
      `LmdbCellStore.backfillSecondaryIndices()` + new bin target
      `brain-backfill-cell-indices` (src/backfill_cell_indices/main.zig)
      one-shot-walk the primary `cells` sub-DB and populate every
      secondary index (cells_by_owner, cells_by_prev_state,
      cells_anchor_status, cells_by_anchor_txid) for cells written
      before the D-LC3/D-LC4/D-LC5 indices existed. Idempotent
      (LMDB collapses same-key empty-value writes) and operator-scoped
      (only this store's op_pkh range is touched). Two-phase
      (read-only cursor scan → in-memory extract list → single write
      txn) mirrors `brain-migrate-entity-cells`. 5 new conformance
      tests in `core/cell-engine/tests/lmdb_cell_store_conformance.zig`:
        - populates indices for raw-inserted pre-existing cells
        - second run is a no-op (idempotent)
        - operator-scoped (the other op_pkh's indices stay empty)
        - attestation cells dispatch to anchor_status + anchor_txid
        - non-attestation cells only get owner + prev_state entries
      Also fixed the latent `test-lmdb-cell-store` step regression: it
      now wires the generated `constants` module through the
      `lmdb_cell_store_mod` (the D-Const-domainflag-genfix import was
      missing in `core/cell-engine/build.zig`, breaking the step
      since D-LC5 follow-up landed). All 29/29 lmdb-cell-store
      conformance tests + 410/410 cell-engine + 1878/1922 brain
      (44 skipped, 0 failed) green.

      Naming note: titled "owner-keyed" rather than "BCA-keyed" because
      `cell.owner_id` is documented in `substrate_entity.zig:18` as the
      "first 16 bytes of operator hat-id", not a strict BCA derivation.
      Per the design intent (BCA = the 16-byte cert-derived identifier
      that owner_id will carry), this index is BCA-ready whenever the mint
      path starts writing actual BCAs into the field; the index doesn't
      care about the bytes' provenance.

      Follow-up (vtable promotion): the read/query surface that landed on
      `LmdbCellStore` for D-LC1 / D-LC3 / D-LC4 / D-LC5 + reorg-sweep
      substrate has been promoted to the `CellStore` vtable, so external
      read-path callers depend on the seam rather than the LMDB impl
      module. Eight methods promoted: `getCell`, `cellsByOwner`,
      `cellsByPrevState`, `cellsByAnchorTxid`, `setAnchorStatus`,
      `getAnchorStatus`, `clearAnchorStatus`, `sweepPendingAnchors`. The
      `AnchorStatus` enum and `SweepResult` struct lifted to
      `cell_store.zig`; back-compat aliases re-exported from
      `cell_store_lmdb.zig`. `cell_raw_http.Acceptor.cell_store` now holds
      `*const CellStore` instead of `*LmdbCellStore`; the reactor
      handlers in `site_server/reactor.zig` go through the vtable seam.
      The direct methods on `LmdbCellStore` stay (back-compat for
      callers that still hold the concrete impl), and operator-exit
      primitives (`deleteAllCells`) plus impl-specific maintenance
      helpers stay on the impl by design — they're not part of the
      read/query surface.

      Deferred to follow-ups that own the relevant work:
      - `cellsByPrevStateRange` (pagination variant) — deferred until
        PR #505 lands; promotion happens in the same PR or a thin
        follow-up against it.
      - `backfillSecondaryIndices` — deferred until PR #508 lands; impl-
        specific by design (owns the LMDB sub-DB topology), likely stays
        on `LmdbCellStore` rather than promoting.

      Tests: 8 new vtable round-trip tests added to
      `core/cell-engine/tests/lmdb_cell_store_conformance.zig`; total
      32/32 in that suite pass via `zig build test-lmdb-cell-store`.
      Cell-engine `zig build test`: 410/410 (baseline preserved). Brain
      `zig build test`: 1865/1909 pass, 44 skipped, 3 pre-existing pda
      compile failures (no regression). Bonus side-fix: the
      `test-lmdb-cell-store` step's `lmdb_cell_store_mod` was missing
      its `constants` dep on baseline (it imports
      `DOMAIN_FLAG_ANCHOR_ATTESTATION_V1`); wired in this PR so the
      conformance suite actually compiles.
  - id: D-LC4
    title: "prev_state_hash forward-walk endpoint for cell-lineage sync"
    phase: opportunistic
    status: merged
    owner: "loop-layer-collapse"
    deps:
      - D-LC3
    matrix_cell: "U7×F"
    pr_url: null
    note: |
      `GET /api/v1/cell/since/<prev_hash_hex>` returns every cell whose
      header `prev_state_hash` equals the given hash, concatenated as raw
      bytes with `Content-Type: application/x-semantos-cells`. Body length
      is N × 1024 bytes; an `x-cell-count` header tells the client N
      without parsing. Empty body when the prev hash has no forward
      children (chain tip).

      MIME-type + header surface specified normatively in
      `docs/spec/protocol-v0.5.md` §3.8 (layer-collapse HTTP transport).
      Cursor-pagination follow-up (`?after=`/`?limit=` + `x-next-cursor`)
      lives on PR #505 / branch `feat/cell-since-pagination`.

      Landed:
      - `runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig`
        - new constants `PREV_STATE_HASH_BYTES = 32`,
          `PREV_STATE_HASH_OFFSET_IN_CELL = 128` (matches
          `HEADER_OFFSET_PREV_STATE_HASH` in
          `core/cell-engine/src/constants.zig:72`),
          `PREV_STATE_KEY_BYTES = 72`
        - new field `dbi_by_prev_state` opened alongside the primary cells
          DB and the D-LC3 owner index
        - `buildPrevStateKey` helper
        - `doPut` extended to write the prev-state-index entry atomically
          (same idempotent backfill posture as D-LC3)
        - `pub fn cellsByPrevState(allocator, prev_state_hash) ![][32]u8` —
          cursor prefix-scan, returns owned slice of forward children
      - `runtime/semantos-brain/src/cell_raw_http.zig`
        - new `SINCE_PREFIX = "/api/v1/cell/since/"` constant
        - new `parseSincePath(path)` pure helper
        - `parsePath` updated to reject the `/since/...` form so the two
          routes don't collide
        - 3 new inline tests for the path helpers
      - `runtime/semantos-brain/src/site_server/reactor.zig`
        - new `reactorHandleCellSince` handler (404 acceptor-absent,
          400 malformed-path, 401 bearer, 405 non-GET, 500 persistence-
          error, 200 cells concatenated). Caps response at 1024 cells
          (1 MiB) per request — pagination is a follow-up if needed.
        - new dispatch entry matched BEFORE the general `/api/v1/cell/`
          block so `/since/` doesn't fall through to D-LC1's handler
      - `core/cell-engine/tests/lmdb_cell_store_conformance.zig` — three
        new D-LC4 tests (one-step children, unknown prev returns empty,
        4-step chain walk).

      Tests: cell-engine `zig build test` — 408/408 pass; conformance
      step — 10/11 (the pre-existing M1.5 padding test still fails,
      unrelated). Brain `zig build test` — 439/439 steps, 1835/1879 tests
      pass, 44 skipped, 0 failures.

      Scope note: the original deliverable mentioned scoping the diff to
      a specific BCA (`/cell/by-bca/:bca/since/:prev_hash`). In practice
      `prev_state_hash` already uniquely identifies the parent state, so
      BCA scoping is redundant for a single-step lookup — kept the URL
      shape simpler. Callers can join with `cellsByOwner` (D-LC3) if they
      need per-owner filtering.

      Complements D-F6 (slot/octave index in recovery export) by giving
      nodes a stateless Git-style reconciliation primitive for chains
      independent of federation transport semantics.

      Follow-up (2026-05-21) — cursor pagination on the since endpoint.
      Silent truncation at the 1024-cell cap is now addressed; clients
      can walk past the cap when chains DO grow deep enough to matter.

      - `runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig`
        - new `pub fn cellsByPrevStateRange(allocator, prev_state_hash,
          after, limit) → PrevStateRangeResult{ hashes, has_more }` —
          paginated sibling of `cellsByPrevState`. Skip-on-equal seek
          handles the "strictly after" semantics inside one cursor scan;
          `has_more` is computed from the cursor position immediately
          after the slice fills (no second seek).
        - existing `cellsByPrevState` unchanged (callers + tests untouched).
      - `runtime/semantos-brain/src/cell_raw_http.zig`
        - `parseSincePath` extended to strip an optional `?…` query tail
          before hex-decoding the prev_state_hash segment.
        - new `splitPathQuery(path)` + `parseSinceQuery(query)` helpers
          (typed parse of `limit=` / `after=`, ignores unknown keys).
      - `runtime/semantos-brain/src/site_server/reactor.zig`
        - `reactorHandleCellSince` now parses `?limit=` and `?after=`;
          `0` and out-of-range/malformed values surface 400 with hints.
          `limit` clamps silently at `MAX_CELLS_PER_SINCE_RESPONSE`.
        - new `x-next-cursor: <hex>` response header — present IFF more
          results exist under the same prev_state_hash, value is the
          hash of the last cell in the response (clients pass it back
          as `?after=<hex>`). Absent on the last page. `x-cell-count`
          unchanged.
      - tests: 14 inline (cell_raw_http) + 10 reactor conformance
        (cell_raw_http_conformance) + 5 store conformance (cell-engine's
        lmdb_cell_store_conformance). Covers happy paths, empty pages,
        last-page absence-of-cursor, boundary-equal limits, malformed
        and out-of-range inputs, default-no-params back-compat.
  - id: D-LC5
    title: "Anchor-status projection + x-cell-anchor surface"
    phase: opportunistic
    status: merged
    owner: "loop-layer-collapse"
    deps: []
    matrix_cell: "U1×E"
    pr_url: null
    note: |
      Brain now tracks a per-cell anchor status that read paths surface as
      an `x-cell-anchor` header on D-LC1's raw-cell response. Three
      states: `pending` (cell minted speculatively, anchor TX not yet
      observed), `confirmed` (anchor-attestation cell for the
      corresponding txid has landed), absent (no anchor expected — the
      default).

      Landed:
      - `runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig`
        - new `AnchorStatus` enum (`pending = 0`, `confirmed = 1`) exposed
          publicly so callers can pattern-match
        - new `dbi_anchor_status` sub-DB opened in `initInternal` (lazy
          creation, same posture as D-LC3/D-LC4 indices). Key: op_pkh(8)
          ‖ cell_hash(32) = 40 bytes; value: 1 byte enum.
        - new `buildAnchorKey` helper
        - new methods `setAnchorStatus(hash, status)`, `getAnchorStatus(hash)
          → ?AnchorStatus`, `clearAnchorStatus(hash)`. clear is idempotent
          on missing keys (returns success) — gives the chain-reorg
          rollback path a no-op-safe primitive.
      - `runtime/semantos-brain/src/site_server/reactor.zig` —
        `reactorHandleCellRaw` (D-LC1) now looks up the anchor status for
        the requested hash and emits `x-cell-anchor: pending|confirmed`
        when set. Absent header = brain has no opinion.
      - `core/cell-engine/tests/lmdb_cell_store_conformance.zig` — four
        new D-LC5 tests:
        - status defaults to null
        - set / get round-trip across both enum values
        - clear returns to null and is idempotent on already-absent keys
        - status is op_pkh-scoped (two operators storing the same cell
          bytes see independent anchor projections)

      Tests: 4/4 new D-LC5 tests pass. Cell-engine `zig build test`: 408/408.
      Brain `zig build test`: 439/439 steps, 1835/1879 tests pass, 44
      skipped, 0 failures.

      Follow-up landed (D-LC5 follow-up — attestation observer):
      LmdbCellStore.doPut now peeks the cell's domain_flag at offset 24
      and, when it equals the canonical anchor-attestation wire value
      (0x0001FE02 per audit B-1; constants.zig
      `DOMAIN_FLAG_ANCHOR_ATTESTATION_V1`), extracts targetCellId from
      the payload at offset 256 (anchorAttestationSchemaV1 field 0,
      u256, 32B) and flips that target's anchor status to .confirmed
      inside the same write txn. The attestation cell and its
      projection update land atomically — same posture as the
      D-LC3/D-LC4 secondary indices. Re-puts of the same attestation
      are idempotent (the doPut backfill path re-asserts .confirmed).
      4 new conformance tests in
      `core/cell-engine/tests/lmdb_cell_store_conformance.zig`:
        - attestation cell flips target status to confirmed
        - non-attestation cell does not spuriously dispatch
        - re-storing the same attestation is idempotent
        - attestation confirmation overrides prior pending

      What's NOT in here (intentional follow-up scope):
      - Brain-side reorg watcher that automatically clears pending status
        on chain-reorg detection. Header store + headers_sync already
        detects reorgs (see `headers_sync.zig:reorg_detected`); hooking
        the clearAnchorStatus sweep into that signal is the next step.
        Partial closure landed as the reorg-sweep substrate follow-up:
        a `cells_by_anchor_txid` reverse index (op_pkh ‖ txid ‖
        target_hash) is now populated atomically by `doPut` whenever
        an attestation cell lands; a `sweepPendingAnchors(txid)`
        helper on `LmdbCellStore` clears every `.pending` projection
        bound to that txid in one write txn, leaving `.confirmed`
        entries untouched (past finality requires explicit
        invalidation, not silent reorg rollback) and returning
        (swept, kept) counts for audit. `cellsByAnchorTxid(allocator,
        txid)` exposes the raw target enumeration.

      Anchor-attestation schema v2 substrate landed (D-LC5-reorg-by-
      height): the schema v1 `bumpHash` field (zombie — BRC-74 BUMP
      carries `blockHeight` natively, not a 24B Merkle-root variant;
      no callers anywhere in the repo) was retired in a hard cutover
      (no v1 attestation cells in production per project memory
      `v1_production_is_test_data.md`). `anchor_height: u64` was
      promoted to a first-class queryable field at payload offset 64
      → cell offset 320. Brain now maintains a parallel
      `cells_by_anchor_height` reverse index (op_pkh ‖
      BIG-ENDIAN(anchor_height) ‖ target_hash; BE in the key so LMDB
      lex-sort matches numeric sort and the height-range scan is a
      straight cursor walk). Two new methods:
        - `cellsByAnchorHeightRange(low, high)` returns
          `[]AnchorHeightEntry{height, cell_hash}` ordered ascending
          by height, op_pkh-scoped.
        - `sweepReorgedFromHeight(rollback_from_height)` clears every
          `.pending` projection at heights >= floor with the same
          semantics as `sweepPendingAnchors`: confirmed entries
          preserved, idempotent, reverse-index entries retained.
      Both methods are on the CellStore vtable (PR #510 pattern).
      `core/cell-engine/tests/lmdb_cell_store_conformance.zig`
      gains six new tests + a re-export equality assertion (vtable
      type unification).

      Cartridge hook landed (D-LC5 — final closure): the cartridge
      now ships a `ReorgSink` callback interface
      (`cartridges/bsv-anchor-bundle/brain/zig/src/reorg_sink.zig`)
      with a single vtable method `sweepReorgedFromHeight(u64) →
      SweepReport`. `attemptReorgRecovery` accepts an optional
      `?*const ReorgSink` and, after a successful header-store
      rollback, invokes it with the `from_height` floor it just
      computed (`tip.height + 1 - rollback_blocks`, clipped to
      genesis). Sweep failures are captured in a new `ReorgReport`
      struct (`rolled`, `from_height`, `sweep`, `sweep_error`) but
      do NOT fail the recovery — the chain rollback is the load-
      bearing operation, the sweep is best-effort cleanup.
      Brain-side concrete impl lives in
      `runtime/semantos-brain/src/reorg_sink_cell_store.zig`: a
      zero-cost wrapper around `*LmdbCellStore` that maps
      `StoreError` onto the cartridge-side `persistence_failed`.
      `cmdHeadersServe` (the daemon entry-point for
      `brain headers serve`) opens the entity LMDB env, initialises
      an `LmdbCellStore`, wraps it in `ReorgSinkCellStore`, and
      attaches the sink to its `ServeContext`. Sweep results are
      logged alongside the existing rollback log line so operators
      get a single audit trail per reorg event.
      The cartridge no longer needs a txid → height lookup table —
      the substrate ranges directly by the height the cartridge
      already knows from `reorg_detected`.
      Tests:
        - cartridge-side `reorg_sink.zig` inline tests (2/2 —
          `StubReorgSink` round-trip + error surface)
        - `runtime/semantos-brain/tests/headers_sync_reorg_sink_conformance.zig`
          (7 tests — sink invocation, from_height correctness across
          depth=1/depth>chain/empty-store/null-sink/sweep-error
          paths)
        - `runtime/semantos-brain/tests/reorg_sink_cell_store_conformance.zig`
          (5 tests — end-to-end sweep, floor=0 sweeps-everything,
          floor>all is no-op, empty store, idempotency)
        - existing `headers_sync_reorg_conformance.zig` updated to
          the new return shape (preserves all 8 pre-existing
          rollback-count assertions)
      Suite gates: cartridge `zig build test` 3/3; brain
      `zig build test -j1` 1914/1958 pass + 44 skipped + 0 failures;
      cell-engine `zig build test` 410/410.

      Doesn't change K1–K7 or any opcode behaviour; the cell bytes are
      still immutable and content-addressed, and the anchor projection
      lives entirely in brain-side LMDB.

  # Tracker — surfaced 2026-05-20 during D-LC5 follow-up implementation.
  # Not blocking but worth tidying before the next person trips on it.
  - id: D-Const-domainflag-genfix
    title: "Reconcile legacy DOMAIN_FLAG_* sketch in constants.zig with canonical Plexus values"
    phase: opportunistic
    status: merged
    owner: null
    deps: []
    matrix_cell: "U1×D-cap"
    pr_url: null
    landed_note: |
      Promoted SemantosDomainFlags canonical schema-dispatch values into
      `core/constants/constants.json` (COMMERCE_V1=0x0001FE01,
      ANCHOR_ATTESTATION_V1=0x0001FE02, SCG_RELATION_V1=0x0001FE03);
      regenerated `core/cell-engine/src/constants.zig` via
      `bun run generate-constants`. Removed the 7 unreferenced legacy
      low-number entries (ATTESTATION=5, ENCRYPTION=3, MESSAGING=4,
      CHILD_CREATION=6, PERMISSION_GRANT=7, DATA_SOVEREIGNTY=8,
      SCHEMA_SIGNING=9) — `grep -rn "DOMAIN_FLAG_" --include="*.zig"`
      confirmed zero call-sites outside constants.zig itself, and the
      `*.ts`/`*.ex` cross-check came up empty too. Kept live: SIGNING,
      EDGE_CREATION, METERING (still used in test fixtures) plus the
      PLEXUS_RESERVED_MIN/MAX, EXTENDED_MIN/MAX, CLIENT_DEFINED_MIN/MAX
      tier-bound constants (range bounds in linearity.zig and
      tier-registry documentation). Updated
      `runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig` to import
      the `constants` module and reference
      `constants.DOMAIN_FLAG_ANCHOR_ATTESTATION_V1` instead of a local
      const; comment trail and stale workaround note removed. Wiring
      added in `runtime/semantos-brain/build.zig` so both the
      `lmdb_cell_store_mod` and its inline test step see the
      `constants` module. Suites green: cell-engine 410/410,
      brain 1878/1922 with 44 skipped (0 failed), `bun test
      core/constants/__tests__/constants.test.ts` 11/11 pass
      (generator idempotency + value assertions intact).
    note: |
      `core/cell-engine/src/constants.zig` has a `DOMAIN_FLAG_*` block
      (lines 93-109) that looks like the canonical Plexus domain-flag
      registry but isn't. It's a pre-audit-B-1 sketch in the Plexus-
      reserved range (1-255): SIGNING=2, ENCRYPTION=3, MESSAGING=4,
      ATTESTATION=5, etc. A reader would reasonably assume
      `DOMAIN_FLAG_ATTESTATION = 5` is the dispatch value for
      AnchorAttestation cells. It is not — the canonical value relocated
      to `0x0001FE02` per RM-042 / audit B-1 (see
      `core/plexus-contracts/src/domain-flags.ts`).

      Why this is non-trivial to fix:

      1. `constants.zig` is AUTO-GENERATED from
         `core/constants/constants.json` (file header: `// AUTO-GENERATED
         ... DO NOT EDIT`). Annotating in-place gets wiped on next regen.
         Fix must happen in constants.json + the generator step.
      2. Several of the constants are LIVE:
         `DOMAIN_FLAG_EDGE_CREATION`, `DOMAIN_FLAG_SIGNING`,
         `DOMAIN_FLAG_METERING` are referenced in 4 test fixture files
         (e.g. `core/cell-engine/tests/plexus_conformance.zig`) as
         placeholder fill values. `DOMAIN_FLAG_PLEXUS_RESERVED_MIN/MAX`
         and `DOMAIN_FLAG_EXTENDED_MIN/MAX` are range bounds used in
         `core/cell-engine/src/linearity.zig`. Outright deletion would
         break those tests.

      What "done" looks like:

      - Either (a) promote the canonical `SemantosDomainFlags` values
        (`COMMERCE = 0x0001FE01`, `ANCHOR_ATTESTATION = 0x0001FE02`,
        `SCG_RELATION = 0x0001FE03`) into `constants.json` so the Zig
        side has the same source of truth as TS; the new dispatch const
        in `cell_store_lmdb.zig`
        (`DOMAIN_FLAG_ANCHOR_ATTESTATION_V1 = 0x0001FE02`) then becomes
        a reference to the canonical generated constant.
      - And (b) clearly mark the legacy low-number block as legacy in
        `constants.json` so the generator emits a doc-comment in
        `constants.zig` that warns readers off using them as dispatch
        values. Live ones (SIGNING, EDGE_CREATION, METERING, range
        bounds) stay; clearly-dead ones (ATTESTATION=5, ENCRYPTION=3,
        MESSAGING=4, CHILD_CREATION=6, PERMISSION_GRANT=7,
        DATA_SOVEREIGNTY=8, SCHEMA_SIGNING=9) get removed or kept with a
        "LEGACY: pre-audit-B-1; not a wire value" doc-comment.

      Pre-V1 production cost is zero (V1 prod is test data). Cost is
      future-contributor confusion. Surfaced during D-LC5 follow-up
      (PR #487) when the dispatch landed as a local const in
      cell_store_lmdb.zig with a comment pointing at the source of
      truth — that local const is the workaround until this tracker is
      addressed.

  # ----------------------------------------------------------------------------
  # SCG (Semantos Conversation Graph) — U12 substrate row
  # Tracking doc: docs/SCG-IMPLEMENTATION-TRACKING.md
  # Waves 1-8 landed via commits b3b88ed, ad8eb14, ba310fb, 722586f, e75caf6
  # and merged through 60758c0; canonical SCG_RELATION flag promoted in
  # PR #498 (6d16437). Audit captured in this file 2026-05-21.
  # ----------------------------------------------------------------------------
  - id: D-SCG-relations
    title: "Typed relation primitive on sem_objects (@semantos/scg-relations)"
    phase: "1"
    status: merged
    owner: "scg-phase1"
    deps: []
    matrix_cell: "U12×A,B"
    pr_url: null
    note: |
      RM-010. `core/scg-relations/src/{types,operations,lexicon,capability,index}.ts`.
      Relations are `sem_objects` rows of `objectKind='scg.relation'` — no schema
      migration. 15 canonical `RelationKind` values. `createRelation` /
      `foldRelationGraph` ops, `relationLexicon` registered. Tests:
      `core/scg-relations/src/__tests__/relations.test.ts`,
      `lexicon-injective.test.ts`.

  - id: D-SCG-lexicon
    title: "Relation lexicon (15 canonical kinds, injective header)"
    phase: "1"
    status: merged
    owner: "scg-phase1"
    deps:
      - D-SCG-relations
    matrix_cell: "U12×D-lex"
    pr_url: null
    note: |
      `core/scg-relations/src/lexicon.ts::relationLexicon` registered in
      `core/semantos-sir/src/lexicons.ts::ALL_LEXICONS`. Header function is
      identity; `verifyLexiconInjective` test passes.

  - id: D-SCG-capabilities
    title: "RELATION_MINT / RELATION_REVOKE capability slots"
    phase: "1"
    status: merged
    owner: "scg-phase1"
    deps:
      - D-SCG-relations
    matrix_cell: "U12×D-cap"
    pr_url: null
    note: |
      RM-022. `core/plexus-contracts/src/domain-flags.ts` —
      `ClientDomainFlags.RELATION_MINT = 0x0001000c`,
      `RELATION_REVOKE = 0x0001000d`. `requireRelationMint` enforced at
      `createRelation` via `capabilityPort`.

  - id: D-SCG-sir-constraint
    title: "SIR `relation` constraint variant + Phase-1 lowering"
    phase: "1"
    status: merged
    owner: "scg-phase1"
    deps:
      - D-SCG-relations
    matrix_cell: "U12×D-cap"
    pr_url: null
    note: |
      RM-020. `core/semantos-sir/src/types.ts:159` — `{ kind: 'relation';
      relationKind: RelationKind; sourceId?; targetId? }` variant. Lowering
      case at `lower-sir.ts:167-195` emits a `typeHashCheck` placeholder
      composite. Full schema-offset composite is `D-SCG-sir-schema-composite`
      (pending — Phase 5 §7.3).

  - id: D-SCG-reducer-pass
    title: "Intent-reducer relation-pass (10th pass)"
    phase: "1"
    status: merged
    owner: "scg-phase1"
    deps:
      - D-SCG-relations
      - D-SCG-sir-constraint
    matrix_cell: "U12×D-lex"
    pr_url: null
    note: |
      RM-030. `runtime/intent/src/reducer/relation-pass.ts`; registered at
      position 10 in `runtime/intent/src/reducer/index.ts:33`, between
      `rhetoric` and `analogical-prefilter`.

  - id: D-SCG-cartridge-loader
    title: "Generic experience-cartridge loader + registry"
    phase: "1"
    status: merged
    owner: "scg-phase1"
    deps: []
    matrix_cell: "U11×C"
    pr_url: null
    note: |
      RM-011. `core/experience-cartridge/src/{loader,types,registry}.ts`. Lifted
      out of Oddjobz-specific first-boot wiring; `loadCartridge(manifest)` +
      `cartridgeRegistry`. Tests under `core/experience-cartridge/src/__tests__/`.

  - id: D-SCG-extension-grammar
    title: "SCG extension grammar + manifest (packages/scg)"
    phase: "1"
    status: merged
    owner: "scg-phase1"
    deps:
      - D-SCG-relations
      - D-SCG-capabilities
    matrix_cell: "U12×D-lex"
    pr_url: null
    note: |
      RM-021. `packages/scg/src/{grammar,manifest,index}.ts`. Declares
      `scg.cell` + `scg.relation` entity mappings and `RELATION_MINT`/
      `RELATION_REVOKE` capability requirements. Manifest-only today; the
      U11-canonical-cartridge layout (cartridges/scg/ + cartridge.json +
      objectTypes[] + verbs[]) is a follow-up — see D-SCG-cartridge-shape.

  - id: D-SCG-conversation-graph
    title: "Generic conversation-graph package (@semantos/conversation-graph)"
    phase: "1"
    status: merged
    owner: "scg-phase1"
    deps:
      - D-SCG-relations
    matrix_cell: "U12×A,B"
    pr_url: null
    note: |
      RM-031a (autoEmitReplyRelation hook) + RM-031b (generic
      `runConversationTurn<S, F>` pipeline). `core/conversation-graph/src/{pipeline,
      auto-emit,retrieve-context,rendering,types}.ts`. SUBSTRATE side only —
      Oddjobz consumer cut-over is `D-SCG-oddjobz-consumer-cutover` (pending).

  - id: D-SCG-phase1-e2e
    title: "Phase 1 substrate E2E acceptance test"
    phase: "1"
    status: merged
    owner: "scg-phase1"
    deps:
      - D-SCG-relations
      - D-SCG-sir-constraint
      - D-SCG-reducer-pass
      - D-SCG-conversation-graph
    matrix_cell: "U12×A"
    pr_url: null
    note: |
      RM-040. `core/conversation-graph/src/__tests__/phase1-e2e.test.ts`. Composes
      RM-010/020/022/030/031a against real `sem_objects` storage; meets the
      SCG §3 exit criteria.

  - id: D-SCG-payload-schema
    title: "SCG relation payload schema (SemantosDomainFlags.SCG_RELATION)"
    phase: "5"
    status: merged
    owner: "scg-phase5"
    deps:
      - D-SCG-relations
    matrix_cell: "U12×B"
    pr_url: "https://github.com/semantos/semantos-core/pull/498"
    note: |
      RM-082. `core/plexus-schema-registry/src/schemas/scg-relation.ts`. 113-byte
      encoded layout (kindByte/sourceId/targetId/amount/currency/txAnchor/
      attestation-prefix). Registered under `SemantosDomainFlags.SCG_RELATION =
      0x0001FE03` (canonical promotion in PR #498). Today's jsonb-backed rows
      don't pass through the 2PDA cell header; downstream RMs reusing this
      schema for on-chain anchored relations are `D-SCG-anchored-relations`.

  - id: D-SCG-economic-relations
    title: "Money-bearing relation kinds (PAYS/ESCROW_LOCKS/ESCROW_RELEASES)"
    phase: "3"
    status: merged
    owner: "scg-phase3"
    deps:
      - D-SCG-relations
    matrix_cell: "U12×D-cap"
    pr_url: null
    note: |
      RM-060. `RelationKind` extended with `PAYS`, `ESCROW_LOCKS`,
      `ESCROW_RELEASES`. `RelationPayload` carries `amount` / `currency` /
      `txAnchor` for these kinds. Tests at
      `core/scg-relations/src/__tests__/money-and-branching.test.ts`.

  - id: D-SCG-economic-port
    title: "EconomicPort (signSpend / verifyPayment)"
    phase: "3"
    status: merged
    owner: "scg-phase3"
    deps:
      - D-SCG-economic-relations
    matrix_cell: "U12×G"
    pr_url: null
    note: |
      RM-062. `core/identity-ports/src/{ports,types,stub-binding}.ts` —
      `EconomicPort` interface + `economicPort` port handle + stub binding.
      Companion `D-SCG-wallet-integration` (pending) covers real wallet wiring.

  - id: D-SCG-access-gate
    title: "402-style access gate (requirePaymentRelation)"
    phase: "3"
    status: merged
    owner: "scg-phase3"
    deps:
      - D-SCG-economic-relations
    matrix_cell: "U12×D-cap"
    pr_url: null
    note: |
      RM-063. `core/scg-relations/src/access-gate.ts::requirePaymentRelation`.
      Substrate-level access primitive returning either a decision or
      `AccessChallenge`. Latency budget ≤ 5ms in-memory cache (SCG §8.2).

  - id: D-SCG-retrieve-context
    title: "Conversation-graph retrieval surface (retrieveContext)"
    phase: "4"
    status: merged
    owner: "scg-phase4"
    deps:
      - D-SCG-conversation-graph
    matrix_cell: "U12×A"
    pr_url: null
    note: |
      RM-061. `core/conversation-graph/src/retrieve-context.ts::retrieveContext`.
      Returns a typed subgraph (cells + relations) with provenance, not flat
      text. Agent rewiring on top is `D-SCG-agent-rewiring` (pending).

  - id: D-SCG-branching
    title: "Branching operations (forkSubgraph / mergeSubgraph)"
    phase: "5"
    status: merged
    owner: "scg-phase5"
    deps:
      - D-SCG-relations
    matrix_cell: "U12×E"
    pr_url: null
    note: |
      RM-080. `core/scg-relations/src/branching.ts`. `FORKS` / `MERGES` kinds
      added; three-way comparison on `currentStateHash` for conflict
      detection. Tests at `money-and-branching.test.ts:235+`.

  - id: D-SCG-rendering-helpers
    title: "Thread + stream rendering helpers (renderThread / renderStream)"
    phase: "2"
    status: merged
    owner: "scg-phase2"
    deps:
      - D-SCG-conversation-graph
    matrix_cell: "U12×A"
    pr_url: null
    note: |
      RM-051 + RM-052. `core/conversation-graph/src/rendering.ts` — typed
      intermediate structures (not HTML/Markdown) for the canonical
      thread (Reddit-style) and stream (chat-style) projections. Demo apps
      consuming these helpers are `D-SCG-reddit-projection` and
      `D-SCG-stream-projection` (pending).

  # ----- Pending SCG work (per docs/SCG-IMPLEMENTATION-TRACKING.md audit) -----

  - id: D-SCG-oddjobz-consumer-cutover
    title: "Migrate cartridges/oddjobz to consume @semantos/conversation-graph"
    phase: "1"
    status: merged-with-caveat
    owner: "scg-phase1"
    deps:
      - D-SCG-conversation-graph
      - D-ODDJOBZ-turns-as-sem-objects
      - D-ODDJOBZ-quote-affordance
    matrix_cell: "U12×A"
    pr_url: null
    note: |
      **LANDED 2026-05-22 via feat/scg-oddjobz-cutover (Path B). STATUS =
      merged-with-caveat: the auto-emit wiring + canonical→Turn mapping +
      tests ship here; PRODUCTION ACTIVATION IS GATED on the real
      Database-backed sem_objects sink (`D-OJ-conv-sem-objects-sink-
      activation`).**

      DELIVERED:
      - `cartridges/oddjobz/brain/src/conversation/conversation-turn-patch.ts`
        gains a `RepliesToRelation` request type, a `buildReplyRelations(turn)`
        one-per-turn builder (returns ≤1; exactly one when `quotedTurnId` is
        set), and an INJECTED `replyRelationSink` dep. After each canonical
        turn's sem_objects row lands, the sink fires per-turn-that-quotes,
        ISOLATED (a failure NEVER regresses turn persistence or the jsonl
        audit write — mirrors the BELONGS_TO_ENTITY sink isolation, logged as
        `repliesToSinkError`). The cartridge stays Database-free (no
        `@semantos/semantic-objects` import) — honouring
        `semantos_brain_single_threaded_reactor`: the intake child NEVER
        sync-calls `createRelation`/`autoEmitReplyRelation`.
      - `core/conversation-graph/src/auto-emit.ts` gains the BRAIN-SIDE
        adapter `makeReplyRelationEmitter(db, opts) → (req) => autoEmitReplyRelation(db, Turn)`.
        It maps the cartridge's per-turn `{ turnId, quotedTurnId, authorCertId,
        conversationId }` request onto the substrate `Turn` shape and performs
        the actual Database write where the handle lives (the brain reactor),
        forwarding `capabilityCheck`. This is the seam the brain reactor wires
        once the sem_objects sink is real.

      CANONICAL→Turn MAPPING: turn.turnId → Turn.turnId (relation source);
      turn.quotedTurnId → Turn.quotedTurnId (relation target);
      turn.actorCertId (multiparty-identity binding) → Turn.authorCertId
      (→ relation.createdByCertId; null/omitted for un-cert'd turns — no
      fabricated cert); turn.conversationId → Turn.conversationId (carried,
      not yet persisted on the relation).

      CAPABILITY CHECK: forwarded end-to-end. `makeReplyRelationEmitter`
      accepts `AutoEmitOptions.capabilityCheck` and threads it to every
      `autoEmitReplyRelation` → `createRelation`. A denied check emits no
      relation; turn persistence (already landed) is unaffected. Production
      callers wire it to `capabilityPort.check({ capability: RELATION_MINT })`
      (RM-022) at the brain-reactor boundary alongside the sink activation.

      WHY merged-with-caveat (NOT merged): the production `semObjectSink` is
      STILL a no-op (foundation D-ODDJOBZ-turns-as-sem-objects deliberately
      left it dormant — no Database handle in the intake child). The
      `replyRelationSink` is likewise dormant in production until a real
      Database-backed sem_objects sink exists brain-side (the turn's
      `sem_objects.id` must exist before the relation source/target can bind).
      We did NOT fake a Database connection from the intake child to force a
      green-but-inert activation — that would reintroduce the self-call
      deadlock. Production flip-on is `D-OJ-conv-sem-objects-sink-activation`.

      TESTS (all green; logic fully exercised through an injected Database):
      - `cartridges/.../__tests__/conversation-turn-patch.test.ts`:
        buildReplyRelations one-per-turn + vacuous + authorCertId carry;
        recordIntakeTurn emit-on-quote (outbound→inbound), cross-interaction
        inbound `inReplyToTurnId`, AI cert author thread, dormant-when-absent,
        and reply-relation-emit-failure isolation.
      - `core/conversation-graph/src/__tests__/auto-emit.test.ts`:
        `makeReplyRelationEmitter` CUT1 emits REPLIES_TO with correct
        source/target/author against a real test Database, CUT2 vacuous no-op,
        CUT3 un-cert'd → null author, CUT4 capability-check forwarded + denied.

      ── ORIGINAL NOTE (retained) ──
      Tracking doc §3.6 / §14. The lifted package shipped (RM-031a/b) but the
      Oddjobz consumer was NOT migrated. `cartridges/oddjobz/brain/src/conversation/
      turn-handler.ts:24` still imports `runConversationTurn` from
      `./pipeline.js` (Oddjobz-local), not from `@semantos/conversation-graph`.
      `grep -rn "conversation-graph" cartridges/oddjobz/brain/src/` returns
      zero matches.

      RE-SCOPED 2026-05-21 — attempting the minimal cut-over (Path B: just
      wire `autoEmitReplyRelation` at turn-persistence time) surfaced two
      structural pre-reqs that the original deliverable note missed:

      1. **`D-ODDJOBZ-turns-as-sem-objects`** — Oddjobz today persists
         conversation turns to `oddjobz/conversation.jsonl` (a flat audit
         log). There is no `Database`/`sem_objects` row whose id could play
         the role of `Turn.turnId`. `autoEmitReplyRelation(db, turn, opts)`
         calls `createRelation(db, …)` against `sem_objects.id`, so without
         sem_objects-backed turns there's nothing to bind to. Also touches
         the canonical-schema-spine pattern (see project memory
         `semantos_canonical_schema_spine`).

      2. **`D-ODDJOBZ-quote-affordance`** — Oddjobz's `IntakeTurnBody`
         carries `{message, stateSummary, reply, action, model, prompt}`;
         threading is via `correlationId` (UUID chain), not "this turn
         quoted turn X". `grep -rn "quote|quoted|inReplyTo|reply_to|
         replyTo|parentTurn|prevTurn|priorTurn|threadId"` in oddjobz/brain/
         returns zero conversational-quote hits. `autoEmitReplyRelation`
         is a no-op without `Turn.quotedTurnId`. Oddjobz is a linear bot
         today — quoting needs product design (UI affordance + extractor
         detection) before plumbing.

      Once both pre-reqs land, this deliverable becomes small: after
      `recordIntakeTurn`, call `await autoEmitReplyRelation(db, {
      conversationId: session_id, turnId: <new sem_objects id>,
      quotedTurnId, authorCertId }, { capabilityCheck })`. Three tests
      (happy path, no-quote no-op, failing capability check).

      Investigation receipt: persistence call site is
      `cartridges/oddjobz/brain/src/intake-handler.ts:225-258` →
      `recordIntakeTurn` → `conversation-turn-patch.ts:96` →
      `writeConversationPatch` → `makeJsonlConversationSink`. Turn shape
      at `conversation/conversation-turn-patch.ts:38-69`; underlying
      patch shape at `runtime/intent/src/conversation-patch.ts:27-43`.

  - id: D-ODDJOBZ-turns-as-sem-objects
    title: "Persist Oddjobz intake turns as sem_objects rows (additionally to jsonl audit log)"
    phase: "1"
    status: merged
    owner: null
    deps: []
    matrix_cell: "U12×A"
    pr_url: null
    note: |
      Pre-req for `D-SCG-oddjobz-consumer-cutover`. Surfaced 2026-05-21
      while attempting that cut-over. Landed 2026-05-22 via the
      feat/oddjobz-turns-as-sem-objects branch.

      Landed shape (foundation; entityRef bound by D-OJ-conv-entity-
      anchoring as a follow-up):

      - `cartridges/oddjobz/brain/src/conversation/conversation-turn-patch.ts`
        is now dual-sink. The jsonl `writeConversationPatch` write is
        unchanged (V1 audit log preserved). A new optional
        `semObjectSink: (turn) => void` dep, when wired, receives the
        canonical `OddjobzConversationTurnPayload` (architecture doc
        §4) — one inbound (`direction='inbound'`, customer message)
        and one outbound (`direction='outbound'`, AI reply) per
        intake interaction.
      - `intake-handler.ts` call site now passes the canonical
        surface/role discriminators (`surface: 'widget'`,
        `inboundParticipantRole: 'external'`,
        `outboundParticipantRole: 'ai'`, optional `agentCertId` from
        env). The production `semObjectSink` stays unwired in this
        PR — the canonical-shape construction lives here; a future
        deliverable wires a brain-side adapter (detached grandchild
        submitter OR brain-reactor pre-record). The cartridge has no
        `@semantos/semantic-objects` dependency by design (Database
        handles belong with the brain reactor, not in the cartridge).
      - Mapping decisions (architecture doc §4.2 option (a)): the
        legacy `IntakeTurnBody` (the per-turn audit metadata) rides
        as `bodyParts[0] = { kind: 'oddjobz-intake-meta', payload:
        IntakeTurnBody }` on the outbound turn — forward-compatible,
        no field collisions on the canonical envelope.
      - Roles: inbound = `external` (widget intake is anonymous —
        no cert, no resolved tenant identity), outbound = `ai`
        (today's intake-handler routes EVERY reply through the
        haiku LLM via reply-generator.ts; no operator-typed path).
        Both overridable via the new args.
      - `quotedTurnId` is set on the outbound turn (→ inbound
        turnId) so REPLIES_TO can auto-emit at the SCG cut-over.
      - 10 new dual-sink tests in
        `cartridges/oddjobz/brain/src/conversation/__tests__/
        conversation-turn-patch.test.ts`; the 3 existing jsonl
        backward-compat tests still pass verbatim.

      Plumbing challenge resolved: the sink shape is the seam where
      a future brain-side `Database` write plugs in. The cartridge
      composes the payload (where intake context lives); the brain
      reactor will own the actual `createObject` call (avoiding the
      self-call deadlock from project memory
      `semantos_brain_single_threaded_reactor`).

      Adjacent to the canonical-schema-spine work (memory:
      `semantos_canonical_schema_spine`) — this IS the normalisation
      seam that spine pattern calls for.

  - id: D-OJ-conv-sem-objects-sink-activation
    title: "Wire the real Database-backed sem_objects sink for Oddjobz turns (brain-side)"
    phase: "1"
    status: merged
    owner: "oj-conv-sem-objects-sink-activation"
    deps:
      - D-ODDJOBZ-turns-as-sem-objects
    matrix_cell: "U12×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/555"
    note: |
      ADDED 2026-05-22 by `D-SCG-oddjobz-consumer-cutover` (Path B) — the
      gating deliverable that flips Oddjobz conversation persistence from
      "canonical-shape construction + dormant sinks" to a live substrate
      write.

      WHAT'S DORMANT TODAY: the foundation (D-ODDJOBZ-turns-as-sem-objects)
      deliberately left the production `semObjectSink` a no-op — the intake
      child has NO `Database` handle by design (it runs as a spawned bun of
      the single-threaded brain reactor and must NOT sync-call back into the
      brain; project memory `semantos_brain_single_threaded_reactor`). The
      cartridge composes the canonical `OddjobzConversationTurnPayload` where
      intake context lives; the Database write must happen brain-side.

      Because the sem_objects rows aren't persisted yet, BOTH downstream
      relation sinks are also dormant in production:
        - `relationSink` (BELONGS_TO_ENTITY — D-OJ-conv-entity-anchoring)
        - `replyRelationSink` (REPLIES_TO — D-SCG-oddjobz-consumer-cutover)
      Their logic + canonical→request mappings are shipped and fully tested
      against injected test Databases; only the brain-side activation is
      missing.

      WHAT THIS DELIVERABLE WIRES (brain-side, where the Database handle
      lives — no self-call from the intake child):
        1. A real `semObjectSink` that calls `createObject(db, { objectKind:
           'oddjobz.conversation.turn', payload })` for each canonical turn,
           via either (a) a brain-reactor pre-record before spawning the
           intake child, OR (b) the detached-grandchild submitter pattern
           (same as `intake-handler.ts --detached-submit` / `ensure-lead-job`),
           so the row exists and yields the `sem_objects.id` that becomes
           `Turn.turnId`.
        2. The `relationSink` bound to the brain-side BELONGS_TO_ENTITY
           emitter (target-must-exist enforced before `createRelation`).
        3. The `replyRelationSink` bound to
           `makeReplyRelationEmitter(db, { capabilityCheck:
           capabilityPort.check({ capability: RELATION_MINT }) })` from
           `core/conversation-graph/src/auto-emit.ts` — so a quoting turn
           emits REPLIES_TO from turn → quoted turn.

      ORDERING CONSTRAINT: the relation sinks must fire AFTER the turn's
      sem_objects row lands (the relation source/target are `sem_objects.id`s).
      The cartridge already orders the emit correctly within `recordIntakeTurn`
      (relations after `semObjectSink`); the brain-side wiring must preserve
      that the row write completes (or is durably enqueued) before the
      relation emit resolves.

      DO NOT fake a Database connection from the intake child to force
      activation — that reintroduces the self-call-deadlock (the 2026-05-18
      outage; project memory `semantos_brain_single_threaded_reactor`).

  - id: D-ODDJOBZ-quote-affordance
    title: "Add quoted-turn semantics to Oddjobz intake conversations"
    phase: "1"
    status: merged
    owner: "oj-conv-quote-affordance"
    deps: []
    matrix_cell: "U12×A"
    pr_url: null
    note: |
      Pre-req for `D-SCG-oddjobz-consumer-cutover`. Surfaced 2026-05-21
      while attempting that cut-over.

      **LANDED 2026-05-22 via feat/oj-conv-quote-affordance.** (The
      architecture doc §12 cross-references this under the alias
      `D-OJ-conv-quote-affordance`; only THIS id exists in canon — they
      are the same deliverable.)

      Oddjobz's `IntakeTurnBody` (`cartridges/oddjobz/brain/src/
      conversation/conversation-turn-patch.ts`) carried no concept of
      "this turn quoted turn X". Threading was a flat
      `correlationId`-keyed UUID chain.

      DELIVERED — explicit/structural quote detection (§13.8's
      explicit path):
        (i)  `RecordIntakeTurnArgs.inReplyToTurnId?: string` — the
             SURFACE-supplied reply reference (widget "reply to this
             message" affordance, email `In-Reply-To` resolved to a turn
             id, Meta Inbox reply reference). Maps onto the INBOUND
             canonical turn's `quotedTurnId`. (The OUTBOUND turn's
             `quotedTurnId` was already set by the foundation —
             intra-interaction reply; this field is the
             cross-interaction case where the customer's NEW message
             quotes an earlier turn.)
        (ii) Validation: CARRY, don't pre-verify. No sem_objects lookup
             from the intake child (single-thread-reactor self-call
             guard). One cheap structural guard: a self-reference (==
             the inbound turn's own id) is dropped. Target-existence +
             cross-conversation rejection deferred to the brain-side
             `createRelation` / `autoEmitReplyRelation` (which no-ops on
             absent target — `core/conversation-graph/src/auto-emit.ts`).

      DEFERRED follow-up (NOT built): inferred-from-content quote
      detection (NLP "as you said earlier…" → resolve which prior turn),
      which needs an entity/turn resolver. Mirrors §13.8's voice split.
      Surface adapters (D-OJ-conv-widget-intake / -email-intake /
      -meta-inbox-bridge) populate `inReplyToTurnId` — same pattern
      multiparty-identity used for `inboundPhone`/`inboundEmail`.

      Combined with `D-ODDJOBZ-turns-as-sem-objects`, the SCG cut-over
      (`D-SCG-oddjobz-consumer-cutover`) reduces to a single `await
      autoEmitReplyRelation(...)` per turn after `recordIntakeTurn`.

  - id: D-SCG-cartridge-shape
    title: "Align packages/scg to canonical-cartridge (U11) shape"
    phase: "1"
    status: merged
    owner: "scg-phase1"
    deps:
      - D-SCG-extension-grammar
    matrix_cell: "U11×B"
    pr_url: null
    note: |
      Landed via feat/scg-cartridge-relocation. `packages/scg/` →
      `cartridges/scg/brain/` (npm name `@semantos/scg` preserved); new
      `cartridges/scg/cartridge.json` declares CC0 manifest +
      `objectTypes[]` for `scg.cell` and `scg.relation` (CC5) +
      `verbs[]` (`scg.relation.mint`, `scg.relation.revoke`) bound to
      `ClientDomainFlags.RELATION_MINT/REVOKE`. Role=`infra` mirrors
      `wallet-headers` + `bsv-anchor-bundle` substrate cartridges; PWA-part
      empty per project memory `semantos_streams_shell_native`. Grammar
      remains the in-cartridge source of truth (`brain/src/grammar.ts`);
      cartridge.json is a derived/registry-facing view. Projection demos
      ship as separate dependent cartridges (D-SCG-reddit-projection /
      D-SCG-stream-projection).

  - id: D-SCG-persona-projection
    title: "Persona projection — federated user-owned identity surface"
    phase: "2"
    status: merged
    owner: "scg-phase2"
    deps:
      - D-SCG-rendering-helpers
      - D-SCG-relations
    matrix_cell: "U12×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/616"
    note: |
      Substrate-side primitive `projectPersona` ships next to
      `projectThread`/`projectStream` in
      `core/conversation-graph/src/rendering.ts`. Returns a typed
      `PersonaProjection { identity, viewerHat, social, topical,
      commercial, groups, edges }` composed of (a) the persona's
      authored-cell stream, (b) topical threads folded under owned
      roots via REPLIES_TO/CITES/SUPPORTS/DISPUTES/SUPERSEDES/FORKS/
      MERGES, (c) commercial party-to relations under PAYS/ATTESTS/
      GRANTS_ACCESS/APPROVES/etc., (d) pub-sub group memberships
      folded from the new `SUBSCRIBES_TO` relation kind, (e)
      contact-book identity edges (MESSAGING/ATTESTATION/...) passed
      through. No PWA part — directories like bsvradar consume the
      typed structure. Reddit-thread + Discourse-stream demos fall
      out as filters over `topical` / `social`; `D-SCG-reddit-projection`
      + `D-SCG-stream-projection` are superseded as standalone
      deliverables. New relation kind `SUBSCRIBES_TO = 0x10` added to
      `SCG_RELATION_KIND_BYTES`. Tests at
      `core/conversation-graph/src/__tests__/rendering.test.ts` (P1-P8).

  - id: D-SCG-reddit-projection
    title: "Reddit-style thread projection demo app"
    phase: "2"
    status: superseded
    owner: "scg-phase2"
    deps:
      - D-SCG-rendering-helpers
    matrix_cell: "U12×A"
    pr_url: null
    note: |
      SUPERSEDED 2026-05-23 by D-SCG-persona-projection — the
      Reddit-thread page falls out as `projectPersona(handle).topical`
      with the default face filter. A standalone reddit-shaped demo
      app is no longer a distinct deliverable; the persona projection
      is the substrate-side primitive any directory consumer renders.

  - id: D-SCG-stream-projection
    title: "Discourse/chat-style stream projection demo app"
    phase: "2"
    status: superseded
    owner: "scg-phase2"
    deps:
      - D-SCG-rendering-helpers
    matrix_cell: "U12×A"
    pr_url: null
    note: |
      SUPERSEDED 2026-05-23 by D-SCG-persona-projection — the
      chat-stream page falls out as `projectPersona(handle).social`
      (and `projectStream` directly for non-persona-scoped streams).
      No standalone demo-app deliverable.

  - id: D-SCG-wallet-integration
    title: "EconomicPort ↔ wallet-browser real binding"
    phase: "3"
    status: pending
    owner: "scg-phase3"
    deps:
      - D-SCG-economic-port
    matrix_cell: "U12×G"
    pr_url: null
    note: |
      Tracking doc §5.2. `EconomicPort` has a stub binding
      (`stub-binding.ts:460`); real wallet wiring (`apps/wallet-browser` or
      a wallet-agnostic facade) not on record. Decision-record artefact +
      integration test required.

  - id: D-SCG-revenue-split-e2e
    title: "Paid-content gate + revenue-split E2E"
    phase: "3"
    status: pending
    owner: "scg-phase3"
    deps:
      - D-SCG-access-gate
      - D-SCG-wallet-integration
    matrix_cell: "U12×D-cap"
    pr_url: null
    note: |
      Tracking doc §5.4. Gate tested in isolation; an end-to-end paid-content
      flow with a documented revenue-split scenario is not on record.

  - id: D-SCG-agent-rewiring
    title: "Wire Oddjobz LLM call-sites to retrieveContext (subgraph-aware prompting)"
    phase: "4"
    status: pending
    owner: "scg-phase4"
    deps:
      - D-SCG-retrieve-context
      - D-SCG-oddjobz-consumer-cutover
    matrix_cell: "U12×A"
    pr_url: null
    note: |
      Tracking doc §6.2. `cartridges/oddjobz/brain/src/conversation/turn-extractor.ts`
      and `reply-generator.ts` still use flat-history prompting; neither imports
      `retrieveContext` from `@semantos/conversation-graph`. Acceptance:
      measurable hallucination drop on a fixed Q&A set (covered by
      `D-SCG-hallucination-harness`).

  - id: D-SCG-hallucination-harness
    title: "Hallucination-reduction harness with baseline + post-rewire numbers"
    phase: "4"
    status: pending
    owner: "scg-phase4"
    deps:
      - D-SCG-agent-rewiring
    matrix_cell: "U12×A"
    pr_url: null
    note: |
      Tracking doc §6.3. Predefined accuracy metric on a fixed Q&A set against
      the substrate; baseline vs subgraph-aware-prompting comparison.

  - id: D-SCG-governance-projection
    title: "Governance projection: proposal → SUPPORTS/DISPUTES → EXECUTES"
    phase: "5"
    status: pending
    owner: "scg-phase5"
    deps:
      - D-SCG-relations
      - D-SCG-reducer-pass
    matrix_cell: "U12×D-cap"
    pr_url: null
    note: |
      Tracking doc §7.2. Relation kinds support the pattern (SUPPORTS/DISPUTES/
      APPROVES exist) but no governance-projection operator surface ties
      `foldRelationGraph` to a tally + `EXECUTES`-triggered `processIntent`.

  - id: D-SCG-sir-schema-composite
    title: "SIR lowerer emits full schema-offset composite against SCG schema"
    phase: "5"
    status: pending
    owner: "scg-phase5"
    deps:
      - D-SCG-sir-constraint
      - D-SCG-payload-schema
    matrix_cell: "U12×D-cap"
    pr_url: null
    note: |
      Tracking doc §7.3 / §7.4. `core/semantos-sir/src/lower-sir.ts:167-195`
      still emits the Phase-1 placeholder composite (`typeHashCheck` against
      `scg.relation:${kind}`). The full composite — read `source` u256 @
      offset 1, `target` u256 @ offset 33, etc. — over `domainPayloadRoot`-
      verified bytes is deferred.

  - id: D-SCG-anchored-relations
    title: "On-chain anchored SCG relations (cells, not jsonb)"
    phase: "5"
    status: pending
    owner: "scg-phase5"
    deps:
      - D-SCG-payload-schema
      - D-SCG-sir-schema-composite
    matrix_cell: "U12×B"
    pr_url: null
    note: |
      The downstream RMs implied by the schema header-comment: today's
      `scg.relation` rows live in `sem_objects.payload` (jsonb). Anchored
      relations pass through the 2PDA cell header with
      `domainPayloadRoot` committing the schema-encoded payload.

  - id: D-SCG-recovery
    title: "Relation-aware recovery export (BRC-69-style recipe)"
    phase: "5"
    status: pending
    owner: "scg-phase5"
    deps:
      - D-SCG-payload-schema
    matrix_cell: "U12×F"
    pr_url: null
    note: |
      Tracking doc §8.1. Relations recover via the standard `sem_objects`
      recovery today; an explicit relation-aware export (so a recovery
      payload includes the relation graph as a named slice) is not wired.

  # ──────────────────────────────────────────────────────────────────────
  # D-OJ-conv-* — Oddjobz Conversation Engine deliverables (U13).
  #
  # Added 2026-05-21 via docs/oddjobz-conversation-architecture, decomposing
  # the forward-looking architecture doc
  # `docs/design/ODDJOBZ-CONVERSATION-ARCHITECTURE.md` §12. Eleven new
  # entries here; two existing entries (D-ODDJOBZ-turns-as-sem-objects +
  # D-ODDJOBZ-quote-affordance, added 2026-05-21 via PR #529) and one
  # (D-SCG-oddjobz-consumer-cutover) are kept under their existing names
  # and cross-referenced from this set rather than renamed. 11 + 3 = 14
  # total deliverables tracking the U13 Oddjobz Conversation Engine row. Renaming was
  # considered but rejected — PR #529 just merged with the existing names
  # and renaming would invalidate the rationale captured in the cut-over
  # deliverable.
  #
  # Honest scope flag (per design doc §12):
  #   • mechanical (~1 day): D-OJ-conv-entity-anchoring,
  #     D-OJ-conv-per-turn-compression
  #   • medium (~1 week): D-OJ-conv-widget-intake, D-OJ-conv-email-intake,
  #     D-OJ-conv-sms-intake, D-OJ-conv-outbound-routing
  #   • large (multi-week, design + impl): D-OJ-conv-meta-inbox-bridge,
  #     D-OJ-conv-ai-participant, D-OJ-conv-multiparty-identity,
  #     D-OJ-conv-aggregate-sir
  # ──────────────────────────────────────────────────────────────────────

  - id: D-OJ-conv-entity-anchoring
    title: "Add BELONGS_TO_ENTITY SCG relation kind; anchor every turn to an entity"
    phase: "1"
    status: merged
    owner: "loop-oj-conv"
    deps:
      - D-ODDJOBZ-turns-as-sem-objects
      - D-SCG-relations
      - D-SCG-lexicon
    matrix_cell: "U13×B"
    pr_url: null
    note: |
      Design doc §7. New SCG `RelationKind` `BELONGS_TO_ENTITY` — source =
      `sem_objects.id` of a turn; target = `sem_objects.id` of the
      job/site/customer cell. Add to `RelationKind` union + `ALL_RELATION_KINDS`
      + `relationLexicon` in `core/scg-relations/`. Wire the
      mint-on-turn-create path (either in `relation-pass.ts` 10th reducer or
      in the turn-persistence call site — see open question 13.1). Constraint:
      one `BELONGS_TO_ENTITY` per turn; target must be an existing cell.

      Mechanical once `D-ODDJOBZ-turns-as-sem-objects` lands. Extend
      `verifyLexiconInjective` test with the new kind.

  - id: D-OJ-conv-multiparty-identity
    title: "participantRole enum + per-role identity binding"
    phase: "1"
    status: merged
    owner: "loop-oj-conv"
    deps:
      - D-ODDJOBZ-turns-as-sem-objects
      - D-OJ-conv-entity-anchoring
    matrix_cell: "U13×A"
    pr_url: null
    note: |
      Design doc §5 + §13.2 (tiered identity, RESOLVED 2026-05-21).
      `participantRole` enum
      (`operator|ai|tenant|agent|owner|subcontractor|tradesman|external`,
      plus `unknown` for legacy) landed with the foundation (#535). This
      deliverable adds per-role identity binding to the canonical turn
      shape (`cartridges/oddjobz/brain/src/conversation/
      conversation-turn-patch.ts`):

      • `identityHandle` field — `{kind:'cookie'|'phone'|'email'|'ig'|
        'fb'|'free', value}` (superset of §4.1; `cookie` is the §13.2 L0
        marker). Carries L0/L1 identity for un-cert'd parties.
      • `bindParticipantIdentity(role, ctx)` — operator → operator-root
        cert (L2); ai → agent cert or `AI_CERT_PENDING_SENTINEL`; cert'd
        sub/tradesman → own cert / un-cert'd → narrows to external + L1/L0
        handle (§5.4, no invented guest cert); tenant/owner/agent/external
        → null cert + handle (§5.5). actorCertId XOR identityHandle.
      • `identityTier(turn)` — L2 cert / L1 phone-email-social / L0 cookie;
        L0 floor when neither. For downstream queries + the future merge.

      Surfaced (not invented): AI cert binding awaits
      `D-OJ-conv-ai-participant` (sentinel until then); operator-root cert
      source must be threaded by the call site (binding empty + surfaced
      otherwise). The MERGES capability is a SEPARATE deliverable
      `D-OJ-conv-identity-merge` (open question 13.2) — NOT built here.
      Talk-render of the role is deferred to the surface-adapter
      deliverables (D-OJ-conv-widget-intake et al).

  - id: D-OJ-conv-widget-intake
    title: "Oddjobz chat-widget surface adapter"
    phase: "1"
    status: merged
    owner: "oj-conv-widget-intake"
    deps:
      - D-ODDJOBZ-turns-as-sem-objects
      - D-OJ-conv-entity-anchoring
      - D-OJ-conv-multiparty-identity
    matrix_cell: "U13×C"
    pr_url: "https://github.com/semantos/semantos-core/pull/564"
    note: |
      Design doc §6.2. Shipped 2026-05-22.

      WHAT LANDED:
      - NEW `cartridges/oddjobz/brain/src/surface-adapters/contract.ts`:
        the shared §6.1 abstract interface (`ConversationSurfaceAdapter` +
        `AdapterContext`) that email/sms/meta-inbox adapters will import.
        Uses `Brc52Cert` from `@semantos/protocol-types` (canonical W1.5C-1
        type; no new cert system invented).
      - NEW `cartridges/oddjobz/brain/src/surface-adapters/widget.ts`:
        `makeWidgetAdapter(deps)` implementing the contract for
        `surface='widget'`. Reuses `buildCanonicalTurns` from
        `conversation-turn-patch.ts` (no shape drift; live intake path
        unchanged). Identity binding: 'external' by phone (L1) > email (L1)
        > cookie (L0) via `bindParticipantIdentity`. §6.3 entity resolution:
        hit → `entityRef` set; miss → `entityRef` absent (SD2 lead-on-
        contact handled by detached-grandchild submitter out-of-band).
        `send` uses an injected `WidgetWsSender` (mockable in tests;
        production wires the brain's actual WS send function).
      - 35 new tests: ALL PASS. No new failures (pre-existing 8 fail +
        6 errors from missing @anthropic-ai/sdk / D-O7/MT-7 unchanged).

      LIVE WIDGET PATH PRESERVED:
      The existing `intake-handler.ts` → `recordIntakeTurn` entry point is
      completely unchanged. The adapter wraps/shares the same canonical-turn
      construction via `buildCanonicalTurns`; it is an ADDITIVE formalisation
      behind the §6.1 interface, not a fork or replacement.

      NO-BRAIN-SELF-CALL:
      `ctx.submitTurn` routes via the detached-grandchild submitter pattern
      (never a sync-call into the brain HTTP/REPL). At the brain-reactor
      boundary, the context is wired to write directly to Postgres via
      `makeOddjobzSinks(db)` (Postgres is external, not the reactor).

      BRC52CERT TYPE CHOICE:
      `AdapterContext.operatorCert` uses `Brc52Cert` from
      `@semantos/protocol-types` (W1.5C-1 canonical; already a dep of this
      package). No new cert system invented.

  - id: D-OJ-conv-legacy-ingest-bridge
    title: "Legacy ConversationTurnEvent → canonical sem_objects turn (keystone unification)"
    phase: "1"
    status: merged
    owner: null
    deps:
      - D-OJ-conv-widget-intake
      - D-ODDJOBZ-turns-as-sem-objects
    matrix_cell: "U13×C"
    pr_url: null
    note: |
      KEYSTONE UNIFICATION (2026-05-22). Bridges the OLD parallel conversation
      engine in `runtime/legacy-ingest/` onto the NEW canonical conversation
      spine so email/meta/sms surface-intake deliverables stop being three forks.

      DECISION: keep legacy-ingest's transport + extraction infra (gmail, meta,
      widget HTTP, OAuth — all WORKING LIVE). RETIRE only the conversation MODEL
      by migrating it onto the canonical spine. The live path (JSONL
      oddjobz.message.v1) is preserved as a dual-sink; nothing is deleted.

      SEAM: `ConversationTurnSink` in `runtime/legacy-ingest/src/conversation/types.ts`
      (injectable; the doc-comment explicitly designates it as the bridge point).

      WHAT LANDED (cartridges/oddjobz/brain/src/conversation/legacy-ingest-bridge.ts):
      1. `mapConversationTurnEventToCanonical(event)` — pure mapper.
         Mapping table (all combos tested):
           - channel='meta_messenger'/'meta_instagram' → surface='meta-inbox'
           - channel='widget'                          → surface='widget'
           - role='customer' → participantRole='external', direction='inbound'
           - role='assistant' → participantRole='ai', direction='outbound'
           - meta_messenger customer recipientId → identityHandle { kind:'fb', value:PSID }
           - meta_instagram customer recipientId → identityHandle { kind:'ig', value:PSID }
           - widget customer recipientId → identityHandle { kind:'cookie', value:sessionId }
           - assistant turn → actorCertId=AI_CERT_PENDING_SENTINEL (no identityHandle)
           - sessionId → conversationId (direct)
           - text → bodyText, timestamp → timestamp
           - turnId: deterministic FNV-1a-64 hash over (providerId, sessionId, channel,
             recipientId, role, timestamp, text) — stable across replays
           - correlationId: deterministic per (sessionId, 5-second bucket) so
             inbound+outbound turns from the same interaction share a correlationId
      2. `makeCanonicalTurnSink(db, opts?)` → `ConversationTurnSink` that maps each
         event and persists via `makeOddjobzSinks(db).semObjectSink`. Best-effort +
         isolated: sink failure is swallowed silently (legacy JSONL path unaffected).
      3. `@semantos/legacy-ingest: workspace:*` added to cartridge's package.json
         (cartridge → runtime direction: correct; no circular dep).
      4. 35 new tests (ALL PASS):
           (a) surface/role/direction/identity mapping for all channel×role combos
           (b) sem_objects row persisted via PGlite harness
           (c) determinism: same event → same turnId/correlationId
           (d) sink failure isolation: mapper errors and db errors swallowed
           (e) dual-sink: canonical + legacy coexist without interference
         No new failures (pre-existing 8 fail + 6 errors from missing
         @anthropic-ai/sdk / D-O7/MT-7 unchanged).

      INJECTION DECISION (marked-for-cutover, not wired):
      The serve entry points (`runtime/legacy-ingest/src/webhook/serve.ts`,
      `widget/serve.ts`) CANNOT import from `@semantos/oddjobz` without a
      circular dependency (cartridge → runtime direction). The injection MUST
      happen at the brain reactor boundary (the brain process that imports both
      packages). CLEARLY-MARKED INJECTION POINTS (with exact composition
      pattern) left in both serve.ts files.

      CUTOVER FOLLOW-UP:
      1. Wire the canonical sink at the brain reactor boundary (see injection
         point comments in both serve.ts files).
      2. Once canonical sem_objects rows are confirmed landing live, retire the
         legacy conversation model (ConversationEngine, turn-patch-store,
         graph-resolver, dispatch-router, dispatch-decision-store) in a separate
         rip-out PR. Transport infra (gmail/meta/widget HTTP/OAuth) is kept.

      UNBLOCKS: D-OJ-conv-meta-inbox-bridge (meta adapter: inject this sink into
      meta-server via the brain boundary); D-OJ-conv-email-intake (email extractor
      emits ConversationTurnEvents / maps Proposal through this bridge).

  - id: D-OJ-conv-meta-inbox-bridge
    title: "Meta Inbox (IG/FB DM) protocol-bridge adapter"
    phase: "2"
    status: merged
    owner: null
    deps:
      - D-OJ-conv-widget-intake
      - D-OJ-conv-legacy-ingest-bridge
    matrix_cell: "U13×C"
    pr_url: "https://github.com/semantos/semantos-core/pull/570"
    note: |
      D-OJ-conv-meta-inbox-bridge — go-live wiring (2026-05-22).

      SCOPE: META-ONLY, additive, gated. Wire `makeCanonicalTurnSink` at the
      live composition root `apps/legacy-cli` so META conversation turns persist
      to the canonical spine. Widget turns EXCLUDED — cartridge intake-handler.ts
      already owns canonical widget turns (#555); wiring widget here too would
      DOUBLE-WRITE (deliberately deferred).

      WHAT LANDED:
      1. `apps/legacy-cli/src/meta-fanout-sink.ts` — `makeMetaFanOutSink(opts)`.
         Fan-out `ConversationTurnSink` that calls BOTH:
           a. `legacySink(event)` — legacy JSONL (always, ALL providers)
           b. canonical sink via `makeCanonicalTurnSink(db)` — META-ONLY
              (`event.providerId === 'meta'`); widget events are skipped.
         Canonical-sink failure is ISOLATED (swallowed) so legacy path is
         never broken. When `db === null` (DATABASE_URL unset), canonical
         side is a no-op.

      2. `apps/legacy-cli/src/bootstrap.ts` — exposes `metaFanOutSink` on the
         `BootstrappedCli` interface. Constructed at bootstrap() time using:
           - legacy side: `messagePatchSink.append` (line ~152)
           - canonical side: `makeCanonicalTurnSink(getDatabaseOrNull())`
         Pass `metaFanOutSink` as `onConversationTurn` when constructing
         `MetaWebhookServer`.

      3. `cartridges/oddjobz/brain/package.json` — explicit exports for
         `./conversation/legacy-ingest-bridge`, `./conversation/db`, and
         `./conversation/conversation-turn-patch` (Bun wildcard resolution
         required explicit entries for cross-package imports to resolve).

      4. `apps/legacy-cli/package.json` — added `@semantos/oddjobz: workspace:*`,
         `@semantos/semantic-objects: workspace:*`, `@electric-sql/pglite` (devDep),
         `drizzle-orm` (devDep for PGlite tests).

      ADDITIVE + GATED + DORMANT-UNTIL-ENABLED:
        - No DATABASE_URL → canonical sink is a no-op; legacy JSONL unaffected.
        - Todd's Meta account is currently RESTRICTED; live meta DM traffic
          will not flow until he unrestricts it. The wiring activates
          automatically once (a) DATABASE_URL is set and (b) meta webhooks deliver.

      WIRING POINT: `bootstrap()` creates the fan-out sink. Callers that start
      a `MetaWebhookServer` (e.g. a `legacy serve` sub-command, or a standalone
      webhook serve script) should pass `b.metaFanOutSink` as `onConversationTurn`.
      The standalone `runtime/legacy-ingest/src/webhook/serve.ts` already has an
      injection-point comment for this; it cannot import from the cartridge directly
      (circular dep); the composition happens at the legacy-cli boundary.

      TESTS: 10 new tests in `apps/legacy-cli/src/__tests__/meta-fanout-sink.test.ts`.
      All 42 legacy-cli tests pass (10 new + 32 pre-existing, zero regressions).
      Bridge tests (35) unchanged and passing.

  - id: D-OJ-conv-legacy-serve
    title: "legacy serve command — boots MetaWebhookServer with canonical fan-out sink"
    phase: "1"
    status: merged
    owner: null
    deps:
      - D-OJ-conv-meta-inbox-bridge
    matrix_cell: "U13×C"
    pr_url: "https://github.com/semantos/semantos-core/pull/572"
    note: |
      D-OJ-conv-legacy-serve — final go-live connector (2026-05-22).

      The FINAL go-live connector. PR #570 wired metaFanOutSink and exposed
      it from bootstrap() — but MetaWebhookServer was never instantiated, so
      nothing served the meta webhook. This deliverable closes that gap.

      WHAT LANDED:
      1. `apps/legacy-cli/src/serve.ts` — `buildMetaServerOpts(args)` pure
         helper + `serveMeta(opts)` entrypoint.
         - `buildMetaServerOpts`: assembles `MetaWebhookServerOpts` from
           `metaFanOutSink` + env vars. Testable without a live socket.
         - `serveMeta`: reads WEBHOOK_PORT / META_WEBHOOK_VERIFY_TOKEN /
           META_PAGE_ACCESS_TOKEN, builds LLM from env (mirrors bootstrap.ts
           LlmRouter resolution), constructs + starts the server via
           `Bun.serve()`, logs readiness, and blocks until SIGINT/SIGTERM.
         - No-op LLM stub injected when no backend is configured so the
           server starts without crashing.

      2. `apps/legacy-cli/src/cli.ts` — `legacy serve` sub-command dispatch.
         Before the one-shot `routeLegacy` dispatcher, intercepts
         `positional[0] === 'serve'` and calls `serveMeta({
           metaFanOutSink: bootstrapped.metaFanOutSink,
           shutdown: bootstrapped.shutdown.bind(bootstrapped),
         })`.

      WIRING:
        bootstrap().metaFanOutSink → buildMetaServerOpts.metaFanOutSink
          → MetaWebhookServerOpts.onConversationTurn
          → MetaWebhookServer (listens on WEBHOOK_PORT, default 3002)

      ADDITIVE + GATED + DORMANT-UNTIL-ENABLED:
        - No DATABASE_URL → canonical sink is a no-op (from #570 base).
        - No live Meta account → server is idle (no traffic).
        - Activates automatically once DATABASE_URL is set AND Meta account
          is unrestricted in the developer portal.

      GO-LIVE CHECKLIST:
        1. Set DATABASE_URL on rbs (canonical Postgres spine).
        2. Unrestrict Todd's Meta account in the developer portal.
        3. Set META_WEBHOOK_VERIFY_TOKEN + META_PAGE_ACCESS_TOKEN on rbs.
        4. Run: ssh rbs bun run --cwd /opt/semantos legacy-cli -- serve
           (or via systemd unit with the same env vars).
        5. Register the webhook endpoint in the Meta developer portal
           using the server's HTTPS URL + the verify token.

      NO SELF-CALL DEADLOCK: legacy-cli serve is its OWN process (not the
      brain reactor). Postgres writes go directly to the database.

      STACKS ON: #570 (D-OJ-conv-meta-inbox-bridge) — mergeable after #570 lands.

      TESTS: 14 new tests in `apps/legacy-cli/src/__tests__/serve.test.ts`.
      All 56 legacy-cli tests pass (14 new + 42 from #570 + pre-existing baseline,
      zero regressions).

  - id: D-OJ-conv-email-intake
    title: "Email (gmail reingest) surface adapter"
    phase: "1"
    status: merged
    owner: "oj-conv-email-intake"
    deps:
      - D-OJ-conv-widget-intake
    matrix_cell: "U13×C"
    pr_url: "https://github.com/semantos/semantos-core/pull/569"
    note: |
      Design doc §6.2. Shipped 2026-05-22.

      WHAT LANDED:
      - NEW `cartridges/oddjobz/brain/src/surface-adapters/email.ts`:
        `makeEmailAdapter(deps)` implementing `ConversationSurfaceAdapter`
        for `surface='email'`. Pure RFC822→canonical-turn mapping.
        Reuses `parseRfc822` + `parseEmailMimeParts` from
        `@semantos/legacy-ingest` (no reimplementation of RFC822 parsing).

      MAPPING TABLE:
        RFC822 field        → canonical field
        ────────────────────────────────────────────────────────────────
        From (external)     → participantRole='external', direction='inbound',
                              identityHandle={kind:'email',value:<addr>}
        From (operator)     → participantRole='operator', direction='outbound',
                              actorCertId=ctx.operatorCert.certId (when available)
        Date header         → timestamp (unix ms)
        Plain-text body     → bodyText
        Attachments (PDF/   → bodyParts [{kind:'attachment', payload:{...}}]
          image/other)
        Message-ID /        → conversationId (root Message-ID from References
        References chain      chain; fallback to first message's Message-ID)
        In-Reply-To (when   → quotedTurnId (resolved to prior turn's turnId
          resolves to prior   via in-memory msgId→turnId map built during
          message in thread)  thread ingest)
        turnId              → FNV-1a-64 deterministic hash of [namespace,
                              messageId, conversationId, fromAddress,
                              direction, timestamp]

      THREAD SUPPORT:
        `ingest` accepts `{ kind: 'single', bytes }` OR
        `{ kind: 'thread', messages: Uint8Array[] }` (ordered oldest→newest).
        All messages in a thread share the same `conversationId` (derived
        from the root Message-ID in the References chain). The In-Reply-To
        header is resolved to the prior turn's `turnId` within the thread via
        a progressive msgId→turnId map — no database lookup needed.

      IDENTITY TREATMENT:
        - Inbound (FROM external): identityHandle={kind:'email', value:fromAddr}.
          actorCertId absent (XOR invariant; external party is un-cert'd).
        - Outbound (FROM operator): actorCertId from ctx.operatorCert.certId
          when the cert has a non-empty certId. When cert absent/empty →
          actorCertId absent (no fabrication; mirrors §5.2 widget adapter
          treatment). identityHandle absent for cert-bound operator role
          (XOR invariant).
        - Operator detection: From-address lowercased against
          `operatorEmailAddresses` dep (defaults to OJT_SELF_FORWARD_ADDRESSES
          from @semantos/legacy-ingest).

      §6.3 ENTITY RESOLUTION:
        Inbound turns: ctx.resolveEntity({kind:'email', value:fromAddr}).
        Hit → entityRef set. Miss → entityRef absent; SD2 lead-on-contact
        handled by detached-grandchild submitter out-of-band (mirrors
        widget adapter). Outbound operator turns: resolveEntity NOT called
        (operator knows the entity).

      NO LIVE GMAIL WIRING:
        The adapter is pure protocol↔canonical mapping. No Gmail watch/
        pubsub fetch loop is stood up. The live-wiring (which storage
        provider, which entity resolver, which email sender to inject) +
        the "which widget is canonical" composition question need Todd's
        steer. Tracked as a follow-up. See PR body.

      DETERMINISTIC IDS:
        turnId and correlationId use FNV-1a-64 (mirrors legacy-ingest-
        bridge.ts). Same RFC822 email → same turnId (determinism invariant).

      TESTS:
        39 new tests ALL PASS. No regressions (pre-existing 8 fail + 6
        errors from missing @anthropic-ai/sdk / D-O7/MT-7 unchanged).
        74 total surface-adapter tests pass (35 widget + 39 email).

      LIVES AT:
        `cartridges/oddjobz/brain/src/surface-adapters/email.ts`
        (next to widget.ts, as specified in deliverable spec).

      FOLLOW-UP (needs Todd):
        Composition-root wiring: which entity resolver / email sender /
        storage provider to inject. The "which widget is canonical"
        composition question. Live Gmail pull integration.

  - id: D-OJ-conv-voice-intake
    title: "Voice-note surface adapter (capture-time-bound + inferred)"
    phase: "2"
    status: merged
    pr_url: https://github.com/semantos/semantos-core/pull/605
    owner: null
    deps:
      - D-OJ-conv-widget-intake
      - D-A7
    matrix_cell: "U13×C"
    pr_url: null
    note: |
      Design doc §6.2 + open question 13.8. Voice notes are intent-grammar
      capture per project memory `voice_notes_workflow`. Two paths:
      (a) capture-time-bound (operator taps voice-note button on a job —
      entity is the open job); (b) inferred-from-content (talk-to-self
      mentions entities, transcript runs through an entity-resolver).
      Recommend shipping (a) first; (b) is harder and can ship later.
      Consumes the D-A7 cert-bound voice-session/transcript contract
      (runtime/intent/src/voice/). Lives at `runtime/surface-adapters/
      voice/` (new dir).

  - id: D-OJ-conv-historical-import
    title: "Historical CSV / IG legacy export surface adapter (import surface)"
    phase: "2"
    status: merged
    pr_url: https://github.com/semantos/semantos-core/pull/607
    owner: null
    deps:
      - D-OJ-conv-entity-anchoring
    matrix_cell: "U13×C"
    note: |
      §13.9 (historical import — un-anchored turns). Implements the `import`
      surface kind defined in contract.ts. Policy: auto-create leads for
      unmatched contacts (consistent with §6.3 lead-on-contact). Input shape:
      HistoricalMessagePayload (messages array with direction, body, contactHandle,
      timestamp). conversationId derived deterministically from contactHandle so
      re-imports are idempotent. send() always returns failed — import is read-only.
      26 tests.

  - id: D-OJ-conv-sms-intake
    title: "SMS (Twilio) surface adapter — per CUSTOMER-CONV-LOOP-PLAN"
    phase: "1"
    status: merged
    pr_url: https://github.com/semantos/semantos-core/pull/595
    owner: "loop-oj-conv"
    deps:
      - D-OJ-conv-widget-intake
    matrix_cell: "U13×C"
    pr_url: https://github.com/semantos/semantos-core/pull/595
    note: |
      OPEN PR #595 (2026-05-23). TypeScript ConversationSurfaceAdapter
      at `cartridges/oddjobz/brain/src/surface-adapters/sms.ts` (473 lines)
      + 39 tests (all pass). Twilio inbound webhook → canonical turn
      (E.164 phone, surface='sms', L1 identity tier). Outbound send via
      injectable Twilio REST sender. Lead-on-contact for unknown numbers
      (§6.3). Composition-root wiring (which port, which express
      middleware) is a follow-up pending Todd's deployment steer.

  - id: D-OJ-conv-ai-participant
    title: "AI agent draft/approve/send state machine (structural SIR enforcement)"
    phase: "2"
    status: merged
    pr_url: https://github.com/semantos/semantos-core/pull/597
    owner: null
    deps:
      - D-OJ-conv-multiparty-identity
      - D-OJ-conv-outbound-routing
    matrix_cell: "U13×D-cap"
    pr_url: "https://github.com/semantos/semantos-core/pull/597"
    note: |
      §9 / §13.3 RESOLVED: NOT a new SIR constraint kind; NOT a two-step
      intent. Enforcement = AI outbound turns start as 'proposed' (parked
      for operator approval), operator turns start as 'drafted'. Ships:
      - outboundState in buildCanonicalTurns (conversation-turn-patch.ts)
      - OutboundStateSink type (conversation-turn-patch.ts)
      - makeOutboundStateSink(db) — UPDATE payload JSONB, Option A, 0.309ms
      - OddjobzSinks.outboundStateSink in makeOddjobzSinks
      - outbound-approval.ts: approveOutboundTurn() + ApprovalError
      - 17 tests (AP1–AP10) all pass
      Confidence-gated auto-approval: D-OJ-conv-confidence-threshold (next).

  - id: D-OJ-conv-outbound-routing
    title: "Operator-approves-draft → ship to right surface"
    phase: "1"
    status: merged
    pr_url: https://github.com/semantos/semantos-core/pull/594
    owner: "loop-oj-conv"
    deps:
      - D-OJ-conv-widget-intake
    matrix_cell: "U13×C"
    pr_url: https://github.com/semantos/semantos-core/pull/594
    note: |
      Design doc §8. Implements the outbound state machine
      (`drafted → proposed → approved → sent → delivered|failed`). Surface
      selection: default is the surface the customer uses (most recent
      inbound from the same identity); operator override available. Calls
      the surface adapter's `send` method; persists state transitions as
      per-turn patches. Durability question (open 13.6) needs benchmark
      before final shape.

  - id: D-OJ-conv-per-turn-compression
    title: "Per-turn compression gradient + SCG-relation side-effects"
    phase: "1"
    status: merged
    owner: null
    deps:
      - D-ODDJOBZ-turns-as-sem-objects
      - D-OJ-conv-entity-anchoring
      - D-SCG-reducer-pass
    matrix_cell: "U13×D-lex"
    pr_url: https://github.com/semantos/semantos-core/pull/560
    note: |
      SHIPPED 2026-05-22.

      Closes the binding gap left open by RM-030 (the 10th reducer pass):
      the relation pass emitted `SIRConstraint { kind: 'relation', relationKind }`
      but deferred sourceId/targetId resolution. This deliverable wires the
      resolver layer and per-turn mint for the Oddjobz turn path.

      What ships:
        - `nl-relation-resolver.ts` — pure deterministic resolver:
            source = inbound turn's sem_objects.id
            target = inbound.quotedTurnId (explicit) > outbound.turnId (implicit prior)
          Skip (no throw, no fabricated row) when target unavailable.
        - `conversation-turn-patch.ts` — `reducerRelationConstraints` arg
          + `nlRelationSink` dep; fires resolveNlRelations + sink AFTER both
          turn rows land (source/target exist). Independently isolated —
          failure never blocks reply or other sinks.
        - `db.ts` — `makeNlRelationSink(db)` added; `makeOddjobzSinks` now
          returns 4 sinks (adds nlRelationSink).
        - `intake-handler.ts` — threads `result.intent.constraints` and wires
          `nlRelationSink`.
        - 22 new tests (per-turn-relation.test.ts): EC1-7 (filter), RNR1-6
          (pure resolution), NLS1-2 (DB-backed minting), INT-NL1-7
          (integration). All pass; no baseline regressions.

      Relation kinds that now mint per-turn (via NL-phrase detection):
        SUPPORTS, DISPUTES, SUPERSEDES, CITES, FORKS, REQUESTS_ACTION,
        FULFILLS, PAYS, ATTESTS, GRANTS_ACCESS, APPROVES.

      Excluded (by design):
        REPLIES_TO — handled by structural quotedTurnId / replyRelationSink.
        BELONGS_TO_ENTITY — entity-anchoring; separate injected sink.
        REFERENCES_OBJECT — INTENTIONALLY DEFERRED pending §13.10 design
          resolution (open question; needs Todd's input before wiring).
          A code comment at the exclusion site is greppable: "REFERENCES_OBJECT".

      Design doc §10. Turn shape (`OddjobzConversationTurnPayload`) untouched.

  - id: D-OJ-conv-aggregate-sir
    title: "Conversation as higher-order semantic object (deterministic aggregate)"
    phase: "2"
    status: merged
    owner: null
    deps:
      - D-OJ-conv-entity-anchoring
      - D-OJ-conv-per-turn-compression
    matrix_cell: "U13×F"
    pr_url: https://github.com/semantos/semantos-core/pull/563
    note: |
      Design doc §3.9 + §12. A conversation thread is itself a SIR-
      aggregable semantic object carrying (a) entityRef, (b) participants
      set, (c) summarised intent state (what's still open, what's
      ratified), (d) outbound state machine snapshot. Aggregate is
      deterministic over the patch stream per project memory
      `semantos_dx_priorities` (snapshot/replay determinism). Substrate-
      shaped work — needs a determinism vector test. Lives at
      `cartridges/oddjobz/brain/src/conversation/aggregate-sir.ts` (new).
      Compute-on-read (no materialized row). Added listObjectsByKind to
      core/semantic-objects for payload-filtered reads. 24 aggregate
      tests + 4 listObjectsByKind tests pass; determinism vector proves
      shuffle-invariance.

  # ──────────────────────────────────────────────────────────────
  # Deliverables added 2026-05-22 from architecture doc §13.2/13.3
  # resolutions. These were resolved in the architecture doc by Todd
  # 2026-05-21 (during PR #531) but not yet in this canon — added now
  # when the foundation D-ODDJOBZ-turns-as-sem-objects lands.
  # ──────────────────────────────────────────────────────────────

  - id: D-OJ-conv-re-anchor
    title: "§13.4 re-anchoring semantics — SUPERSEDES pattern + POST /api/v1/conversation/turn/:id/re-anchor"
    phase: "2"
    status: merged
    pr_url: https://github.com/semantos/semantos-core/pull/610
    owner: null
    deps:
      - D-OJ-conv-entity-anchoring
    matrix_cell: "U13×E"
    note: |
      Resolves §13.4. Re-anchoring uses the SUPERSEDES pattern (append-only):
      new BELONGS_TO_ENTITY minted, SUPERSEDES relation from new→old. Full
      audit history preserved. getActiveAnchor() finds the non-superseded
      anchor. HTTP: POST /api/v1/conversation/turn/:turnId/re-anchor,
      body {newEntityCellHash, newEntityKind}. Zig reactor + bun subprocess.
      8+ tests. CLI flag: --oddjobz-re-anchor-script.

  - id: D-OJ-conv-identity-merge
    title: "Operator-initiated identity merge for un-cert'd participants (§13.2 resolution)"
    phase: "2"
    status: merged
    pr_url: https://github.com/semantos/semantos-core/pull/604
    owner: null
    deps:
      - D-OJ-conv-multiparty-identity
    matrix_cell: "U13×A"
    note: |
      Resolves architecture doc §13.2 (Identity binding for un-cert'd
      parties). Same human appearing under a new phone / cleared cookie
      / new email enters as a NEW L0/L1 participant; an operator-
      initiated `identity.merge_request` intent emits a `MERGES` SCG
      relation `new identity → canonical identity`. Merge is GATED on
      a challenge the operator picks from the would-be-merged party's
      job history (e.g. "what was the address of the last job we did?",
      "what's the colour of the rear door we painted?"). Wrong answer
      → merge refused.

      Downstream queries that list "all conversations with tenant X"
      chase `MERGES` chains transitively (`X → Y → Z` returns the
      union; canonical identity's facets win on conflict per the
      operator's merge confirmation).

      Three tiers documented in §5: L0 browser cookie, L1 phone OR
      email, L2 Plexus cert (operators only; tenants/external parties
      stay at L1 indefinitely).

      Touches: `core/scg-relations/src/types.ts` (MERGES already in the
      canonical 15 — reuse, don't add); intake adapters that promote
      L0 → L1; new merge-challenge UI on Talk.

  - id: D-OJ-conv-identity-merge-endpoint
    title: "POST /api/v1/identity/merge — Zig reactor + bun subprocess HTTP endpoint"
    phase: "2"
    status: merged
    pr_url: https://github.com/semantos/semantos-core/pull/608
    owner: null
    deps:
      - D-OJ-conv-identity-merge
    matrix_cell: "U13×A-http"
    note: |
      HTTP surface for D-OJ-conv-identity-merge. Zig reactor handler
      (`identity_merge_http.zig`) + bun subprocess (`identity-merge-script.ts`)
      following the exact same pattern as D-OJ-conv-approve. Wired via
      `--oddjobz-identity-merge-script` CLI flag. Wire protocol:
      stdin: {sourceParticipantId, targetParticipantId, challengeQuestion,
      challengeAnswer, operatorConfirmed}; stdout: {ok:true,mergeId,chain}
      | {ok:false,error}. process.exit(0) prevents postgres.js pool linger.
      7 inline Zig tests + 5 bun integration tests (IMS1-IMS5).

  - id: D-OJ-conv-confidence-threshold
    title: "Cartridge-declared ratification threshold + per-turn confidence emission (§13.3 resolution)"
    phase: "2"
    status: merged
    pr_url: https://github.com/semantos/semantos-core/pull/599
    owner: null
    deps:
      - D-OJ-conv-per-turn-compression
      - D-OJ-conv-ai-participant
    matrix_cell: "U13×D-cap"
    pr_url: "https://github.com/semantos/semantos-core/pull/599"
    note: |
      Resolves architecture doc §13.3 (AI outbound ratification).
      Confidence-gated outbound — NOT a new SIR constraint kind, NOT a
      two-step intent.

      The compression gradient (NL → Intent → SIR → IR) emits a
      `confidence` score alongside the intent. The cartridge declares a
      `ratificationThreshold` in `cartridge.json` (default e.g. 0.85);
      intents at-or-above threshold can ship without operator
      ratification, intents below threshold park in `proposed` for
      operator review.

      Sidesteps the original two-option dilemma (new SIR kind vs forced
      two-step intent) — the confidence is reducer-output, not a
      structural constraint; the proposal-vs-send split is
      operationally available via the threshold, not structurally
      forced.

      Touches: `cartridge.json` schema (add `ratificationThreshold`);
      `runtime/intent/src/reducer/relation-pass.ts` (emit confidence
      alongside intents); the outbound-routing state machine (consume
      threshold + confidence on the outbound turn).

  - id: D-OJ-conv-prompt-versioning
    title: "Versioned prompt schema + content-addressed prompt storage (§13.3 resolution)"
    phase: "2"
    status: merged
    owner: null
    deps: []
    matrix_cell: "U13×D-lex"
    pr_url: null
    note: |
      Resolves architecture doc §13.3 (companion to D-OJ-conv-
      confidence-threshold + D-OJ-conv-reply-audit-log). Prompts are
      first-class artefacts, content-addressed and schemad like cells;
      bumping a prompt = new version with the OLD version retained for
      the audit chain (so a "the bot replied weirdly on 2026-05-12"
      query can recover the exact prompt that produced it).

      Mostly independent — landable without the AI participant or
      threshold work; consumers (audit-log) gate on it.

      LANDED 2026-05-22 (feat/oj-conv-prompt-versioning). Chose the
      per-cartridge EXTENSION path (no cross-cartridge query need yet):
      new `cartridges/oddjobz/brain/src/conversation/prompt-store.ts` —
      an ordered version registry per prompt id (extraction, pdf-
      extraction, system, reply) with `resolvePrompt(id, version?)`
      (latest by default, pinned historical otherwise), `promptVersion`
      / `promptVersionRef` exposing the (id, version, contentHash) pin
      triple the audit-log records. Content hashing REUSES the shared
      content-store primitive (`hashBytes` from @semantos/protocol-
      types — same SHA-256 that addresses cells), verified byte-for-
      byte equal to the registry's sync hex. Bumping appends a new
      version entry; old versions stay resolvable. Prompt files version-
      stamped + the registry re-exported through `template-version.ts`.
      `conversation-turn-patch.ts` UNTOUCHED (turn-payload wiring is the
      reply-audit-log deliverable's job, consuming this primitive).

  - id: D-OJ-conv-reply-audit-log
    title: "Durable AI-reply audit trail — sem_objects oddjobz.conversation.reply_audit (§13.3 resolution)"
    phase: "2"
    status: merged
    owner: null
    deps:
      - D-OJ-conv-prompt-versioning
      - D-ODDJOBZ-turns-as-sem-objects
    matrix_cell: "U13×F"
    pr_url: https://github.com/semantos/semantos-core/pull/556
    note: |
      Resolves architecture doc §13.3 (final piece). Every outbound —
      auto-sent (above threshold) OR ratified (below threshold + op
      approved) — is logged as a `sem_objects` row of
      `objectKind='oddjobz.conversation.reply_audit'` carrying:
        - the extracted intent + its confidence score
        - the versioned prompt schema (content-addressed prompt id +
          version + hash) used to generate the reply
        - operator's ratify/reject decision when applicable
        - resulting SIR / IR / cell hash chain

      Audit utility: when a reply turns out wrong, the operator can
      trace back to the specific prompt version + confidence score +
      reduction pass that produced it — and decide whether to (a)
      downgrade the prompt (revert), (b) tighten the threshold for
      that cartridge/role pair, or (c) re-train the extractor against
      the corrected reply.

      Separate objectKind from `oddjobz.conversation.turn` (kept clean
      — the audit row references the turn rather than expanding the
      turn shape).

  # Cross-references to existing deliverables (kept under current names):
  #
  #   D-ODDJOBZ-turns-as-sem-objects     — turns as sem_objects rows
  #     (above, added 2026-05-21 via PR #529; foundational pre-req for the
  #     D-OJ-conv-* deliverables here).
  #
  #   D-ODDJOBZ-quote-affordance         — quoting UI + extractor
  #     (above, added 2026-05-21 via PR #529; pairs with REPLIES_TO auto-
  #     emit so the conversation graph has a quoting affordance).
  #
  #   D-SCG-oddjobz-consumer-cutover     — REPLIES_TO auto-emit cutover
  #     (above, re-scoped 2026-05-21 with the two pre-reqs above; lands
  #     once both pre-reqs ship — three tests as a single small PR).

  # ── Semantic Routing Substrate (U14) — unification glue ──────────────────────
  # Design doc: docs/design/SEMANTIC-ROUTING-SUBSTRATE.md
  # These are the unification-specific deliverables that bind the Phase-34 /
  # Phase-34E implementation tickets (D34A.1..D34E.6, tracked in those PRDs) to
  # the live MNCA layer-collapse mesh. They make the type path actually drive
  # routing (today the typeHash is in the header but inert) and scale the mesh
  # from N=6 to N≈100 on the same hardware.
  - id: D-SRS-sns-multicast-wire
    title: "Wire deriveMulticastGroup into the live mesh so type paths drive multicast membership"
    phase: "U14"
    status: merged
    owner: "main"
    deps: []
    pr_url: null
    notes: |
      Landed 2026-05-23. Implemented in core/protocol-types/src/mnca/srv6.ts:
      - `deriveMulticastGroup({what, how, inst}, scope)` → ff15:WHAT[0:4]:HOW[0:4]:INST[0:4]:0000
      - `MNCA_TYPE_AXES`: canonical WHAT/HOW decomposition for all 5 MNCA types
      - `MNCA_MULTICAST_GROUPS`: pinned known-answer table (ff15 scope)
      - `MNCA_TILE_TICK_GROUP = "ff15:4ed1:aabd:873d:e970:0000:0000:0000"`
      Wired into docs/demo/run-local-mesh.ts: mesh-node configs now use
      type-derived group (replaces legacy ff15::5e:1 hand-assigned suffix).
      32 conformance tests in __tests__/mnca-srv6.test.ts (all pass).
      Pi mesh still uses ff15::5e:1 (existing deployed configs); upgrade
      requires redeploying node configs via D-SRS-tenant-gateway work.
      Reconciled ff15 vs ff03: keep ff15 (site-local) for Pi LAN demo;
      scope is a runtime parameter; Phase-34 spec's 0x03 maps to realm-local.
  - id: D-SRS-tenant-gateway
    title: "Bidirectional per-Pi gateway relaying intra-Pi loopback <-> inter-Pi SNS multicast"
    phase: "U14"
    status: merged
    owner: "main"
    deps:
      - D-SRS-sns-multicast-wire
    pr_url: null
    notes: |
      Landed 2026-05-23. docs/demo/mesh-tenant-gateway.py:
      - Joins the SAME SNS multicast group on TWO interfaces (--local-iface lo/lo0
        and --wan-iface end0/en8) using separate IPv6 sockets
      - select() loop relays: loopback→LAN (local brains visible to other Pis)
        and LAN→loopback (other Pis' tiles visible to local brains)
      - RecentCache (ttl-keyed SHA-256 digest, LRU 512-entry) suppresses self-echoes
      - 16 Python unit tests (test_mesh_tenant_gateway.py) cover: mark/detect,
        TTL expiry, eviction, idempotent mark, timestamp refresh — all pass
      docs/demo/run-multitenant-pi.sh: on-Pi spawn companion (see D-SRS-multitenant-spawn)
      docs/demo/run-real-mesh.ts: wired --multitenant flag; sets MCAST_GROUP to
      SNS-derived address when Pi cluster is running run-multitenant-pi.sh.
      Deployment: copy mesh-tenant-gateway.py + run-multitenant-pi.sh to each Pi;
      run `./run-multitenant-pi.sh --pi-index N --count 16` in place of systemd drop-in.
  - id: D-SRS-multitenant-spawn
    title: "run-multitenant-pi.sh — spawn ~16 mesh-node tenants per Pi with global tile coords"
    phase: "U14"
    status: merged
    owner: "main"
    deps:
      - D-SRS-tenant-gateway
    pr_url: null
    notes: |
      Landed 2026-05-23. docs/demo/run-multitenant-pi.sh:
      - Args: --pi-index N, --count M (default 4), --iface end0, --local-iface lo
      - Inline Python config generation (no Bun/npm needed on Pi Armbian)
      - Global tile coords: tileX = (piCol*localCols)+localX, tileY = (piRow*localRows)+localY
      - 6 Pis × 16 brains = 96 ≈ N100; 24×8 tile grid, 12×12 interior each
      - Spawns N mesh-node brains on loopback + mesh-tenant-gateway for LAN bridge
      - Graceful Ctrl+C (SIGINT/TERM trap kills all child PIDs)
      Local proof: run-local-mesh.ts --count 16 exercises the same spawn pattern
      on macOS loopback without Pi hardware (verified 4-node case in earlier slices).
  - id: D-SRS-mnca-cell-source
    title: "Replace the random MNCA tile seed with a real input window (data becomes the program)"
    phase: "U14"
    status: merged
    owner: "main"
    deps:
      - D-SRS-multitenant-spawn
    pr_url: null
    notes: |
      Landed 2026-05-23. docs/demo/mesh-data-cell-source.ts — standalone SSE server (:4402):
      - Polls bridge GET /tiles every POLL_MS (default 2000ms) for live mesh metrics
      - computeDataSeed(): maps 4 axes to initial cell density (halo stays zero):
          WHEN validity    ← tick freshness (more ticks → more alive)
          WHO density      ← peer count     (more peers → denser seed)
          WHERE gradient   ← (tileX, tileY) fast hash mix → spatial variation
          WHAT bits        ← SNS group bytes 1+2 (ff15:4ed1:aabd:...) → type signal
      - buildDataTile(): bigint tick, correct TileState shape for stepTile()
      - stepDataTile(): runs DEFAULT_MNCA_RULE for PRE_STEPS (default 3) generations
      - tileToSSEPayload(): source="data" tag distinguishes from raw mesh tiles
      15 Bun tests in __tests__/mnca-data-cell-source.test.ts (all pass).
      Wired into run-local-mesh.ts: starts alongside bridge (:4400) and anchor (:4401).
      Phase-2 (real instrument/sensor/cell data): connect via cell-store consumers once
      real cells flow through the network (ties to Phase 34E D34E.2 Layer-2 learning).
  - id: D-SRS-typepath-fuzzer
    title: "Coverage-guided semantic type-path fuzzer (MNCA state = the coverage signal)"
    phase: "U14"
    status: merged
    owner: ""
    deps:
      - D-SRS-sns-multicast-wire
      - D-SRS-mnca-cell-source
    pr_url: null
    notes: |
      Generate perturbations of dotted type paths, derive their SNS multicast
      addresses, probe the mesh, and read which gateways self-select. Novelty: the
      coverage signal is the emergent MNCA state — a fuzzed path that drives the CA
      into a novel state region discovered new subscriber topology (keep + anchor);
      an already-explored state is redundant (deprioritise). HRR makes the walk
      semantic (nearest-neighbour in binding space) rather than random. SAFETY:
      scope probe cells to *.fuzz.* type paths so production subscriber state is
      never perturbed. Design doc §3.3-3.4, §10 open-question 3.

  - id: D-SRS-bench-pask
    title: "Pask kernel benchmark suite — cross-compile for Pi, measure interact() throughput"
    phase: "U14"
    status: merged
    owner: "feat/bench-pask"
    deps:
      - D-SRS-typepath-fuzzer
    pr_url: "https://github.com/semantos/semantos-core/pull/602"
    notes: |
      Wire bench_pask.zig into build.zig with missing modules (pask_propagation,
      pask_stability, pask_pruner). Adds bench-pask + bench-pask-run build steps.
      tools/u2-mesh/run-bench-pask-on-pi.sh: ARP-scan, SCP, run on first reachable Pi.
      Mac M3 baseline (ReleaseFast):
        interact() 0 related: 10–15 M/s
        interact() 5 related: 1.5–4 M/s
        interact() 10 related: 2.2–2.6 M/s
        snapshot serialize: ~230 µs  restore: ~190 µs
      Pi numbers: pending ssh-add + run on H5 Cortex-A53.

  - id: D-SRS-pask-in-mesh
    title: "Live Pask graph in mesh-node: tile tick co-activation via --pask-cells"
    phase: "U14"
    status: merged
    owner: "feat/bench-pask"
    deps:
      - D-SRS-bench-pask
    pr_url: "https://github.com/semantos/semantos-core/pull/602"
    notes: |
      Embeds a live Pask Store inside mesh-node. --pask-cells <n> (n>0) enables.
      Every verified incoming tile tick becomes interact(peer, [self,...], 1.0, now_ms).
      Edge weights reflect tile co-activation; stability convergence events logged.
      pask_integration.zig: 6 MB Store in BSS, zero heap alloc, zero unsafe ops.
      Config: propagation_depth=2, stability_window=30s, learning_rate=0.1.
      At 500ms cadence × 6 peers: ~12 interact()/sec → 7500× headroom on H5.

  - id: D-SRS-hrr-zig
    title: "HRR circular convolution in Zig — D=256 FFT-based binding for the Pi"
    phase: "U14"
    status: merged
    owner: "feat/bench-pask"
    deps:
      - D-SRS-pask-in-mesh
    pr_url: "https://github.com/semantos/semantos-core/pull/602"
    notes: |
      runtime/semantos-brain/src/hrr.zig — full Zig port of role-vectors.ts at D=256 f32.
      Radix-2 DIT FFT; seedVec uses SHA-256("${seed}:${block}") int32-BE/2^31 normalisation.
      typepathVec superimposes bigram bindings (bind(seg[k], seg[k+1])); similarity=cosine.
      Module-level BSS scratch buffers; not thread-safe (single-threaded mesh-node).
      Wired into build.zig as hrr_mod (leaf) and imported by mesh_node_mod.
      Tests (6): unit norm, near-orthogonal seeds, bind/unbind roundtrip ≥0.85,
        same-path cosine=1, similar>unrelated, single-segment norm=1.
      Mac M3 + aarch64 cross-compile: all 6 tests pass.

  - id: D-SRS-typed-cell
    title: "Typed cell wire format in mesh-node: 1024-byte cell with mnca.tile.tick header"
    phase: "U14"
    status: merged
    owner: "feat/bench-pask"
    deps:
      - D-SRS-pask-in-mesh
    pr_url: "https://github.com/semantos/semantos-core/pull/602"
    notes: |
      runtime/semantos-brain/src/mnca_cell.zig — 1024-byte typed cell wrapper.
      Header (256 B): magic DEADBEEF+CAFEBABE+13371337+42424242, linearity=RELEVANT(3),
        version=2, typeHash=SHA-256("mnca.tile.tick"), domainPayloadRoot=SHA-256(tile).
      Payload (768 B): the MNCA tile bitfield at offset 256.
      broadcastTile now emits both plain 768-byte tile AND 1024-byte typed cell (backward compat).
      mesh-bridge.ts: tileFromDatagram validates typeHash; typed-cell path extracts tile
        from bytes [256..1024); typeHash exposed in SSE stream for viz identity display.
      Tests (12): magic, typeHash, linearity, version, payload bytes, timestamp, domainPayloadRoot,
        isValidMncaCell, corrupt-typeHash reject, tilePayload accessor, runtime SHA-256 verify.
      All 12 tests pass natively and cross-compiled to aarch64.

  - id: D-OJ-conv-propose-outbound
    title: "Operator/agent-initiated outbound SMS pipeline with customer reply link"
    phase: "2"
    status: merged
    pr_url: "https://github.com/semantos/semantos-core/pull/611"
    owner: null
    deps:
      - D-OJ-conv-outbound-routing
      - D-OJ-conv-entity-anchoring
    matrix_cell: "U13×F"
    note: |
      POST /api/v1/conversation/turn/propose → proposed outbound turn.
      Approve → Twilio SMS send. Widget/includeCustomerLink turns append
      ojt.info/{token} reply link. GET /api/v1/c/{token} resolves link.
      Widget JS: token-in-URL detection, context banner, reply submission.
      Customer replies → inbound turns on existing conversation.
      Text-only v1. No delivery callbacks (state ends at sent).

  - id: D-OJ-conv-gmail-canonical-bridge
    title: "mapMessagePatchToCanonical: Gmail/email JSONL rows → canonical conversation turns"
    phase: "2"
    status: merged
    pr_url: "https://github.com/semantos/semantos-core/pull/614"
    owner: null
    deps:
      - D-OJ-conv-legacy-ingest-bridge
    matrix_cell: "U13×G"
    note: |
      `mapMessagePatchToCanonical` maps `oddjobz.message.v1` JSONL rows
      (email/gmail surface) to canonical `OddjobzConversationTurnPayload`.
      Wired into `apps/legacy-cli/src/bootstrap.ts` `onItemPersisted` so
      new Gmail emails create `oddjobz.conversation.turn` sem_objects rows
      going forward (alongside the existing JSONL audit path).
      Email channel → surface='email'. role mapping: customer→external,
      assistant→ai (AI_CERT_PENDING_SENTINEL), operator→operator.
      source.from display-name stripping. correlationId from messageId.
      Best-effort + isolated — legacy JSONL path unaffected.

  - id: D-OJ-conv-messages-backfill
    title: "messages-backfill-script: one-shot CLI backfill of historical Gmail turns"
    phase: "2"
    status: merged
    pr_url: "https://github.com/semantos/semantos-core/pull/614"
    owner: null
    deps:
      - D-OJ-conv-gmail-canonical-bridge
    matrix_cell: "U13×H"
    note: |
      `messages-backfill-script.ts` reads `~/.semantos/data/oddjobz/messages.jsonl`
      and backfills all historical email turns as canonical sem_objects rows.
      Idempotent by correlationId (skip rows already in DB). --dry-run mode
      prints what WOULD be inserted without writing. --channel email (default)
      or --channel all. Progress to stderr; result JSON to stdout.
      process.exit(0) mandatory (postgres.js pool-linger).
      Prod-schema fix (PR #615): prod sem_objects requires vertical+type_hash
      (NOT NULL, no default); raw SQL INSERT bypasses Drizzle ORM.
      Backfill RAN on rbs 2026-05-23: 822/822 inserted, 0 errors.
      825 oddjobz.conversation.turn rows now in prod (822 email + 3 smoke).

  # ── Shell-port arc (2026-05-23) ─────────────────────────────────────
  # Architectural pivot: thin-client / brain-as-substrate (Pattern T).
  # loom-react gets deprecated; loom-svelte becomes the canonical desktop
  # operator console; intelligence currently in runtime-services (browser-
  # side: AttentionEngine, IntentClassifier, IntentTaxonomy, FlowRunner,
  # etc.) migrates into brain HTTP endpoints. Svelte UI becomes a reactive
  # view onto the brain. End state = sovereign p2p node where the brain is
  # the artefact; UIs are interchangeable.
  #
  # Audit findings (2026-05-23):
  #   - loom-svelte has its own parallel stores in lib/*-store.ts; zero
  #     imports of @semantos/runtime-services. It already follows
  #     Pattern T (POST /api/v1/repl + WSS /api/v1/wallet).
  #   - loom-react consumes runtime-services (workspace dep). Has the
  #     full Helm + Dock + AttentionSurface in ~110 files.
  #   - runtime-services is genuinely renderer-agnostic per its
  #     package.json; the framework-quarantine was designed but only
  #     loom-react realises it.
  #
  # This arc unwinds runtime-services into brain APIs, ports the
  # operator-relevant React surfaces to Svelte (against those APIs),
  # ships the peer-view contract that lets cartridges scope persona
  # views, and packages the sovereign-node compose stack.
  #
  # Decomposed into 7 phases; ~24 deliverables. Friend-peering chat
  # works end of phase 5.

  - id: D-brain-attention-api
    title: "Migrate AttentionEngine from runtime-services to brain HTTP"
    phase: "shell-port-1"
    status: in_review
    owner: claude
    deps: []
    matrix_cell: "U-shell×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/618"
    note: |
      Move runtime/services/src/services/AttentionEngine.ts (scoring +
      weights + 5 factors) behind a brain HTTP surface. New endpoints:
      `GET /api/v1/attention/snapshot` (ranked AttentionItem[]),
      `POST /api/v1/attention/interact` (telemetry: surfaced→clicked,
      surfaced→ignored), `GET /api/v1/attention/weights` +
      `PUT .../weights` (Phase-39B learning hook). Implementation
      lives in runtime/semantos-brain/ (Zig or thin-TS-on-brain;
      decide at impl time). loom-svelte consumes via the existing
      ReplClient-shaped pattern.

  - id: D-brain-intent-classifier-api
    title: "Migrate IntentClassifier + IntentTaxonomy to brain HTTP"
    phase: "shell-port-1"
    status: merged
    owner: claude
    deps: []
    matrix_cell: "U-shell×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/621"
    note: |
      runtime-services IntentClassifier + IntentTaxonomy run in-browser
      today; under Pattern T they move into brain. New endpoints:
      `POST /api/v1/intent/classify` (text → IntentClassification),
      `GET /api/v1/intent/taxonomy` (snapshot), `POST .../taxonomy/inject`
      (extension grammars). Existing FlowRegistry surface co-locates with
      this (intent → flow resolution). UI cache fast-path entries.

  - id: D-brain-identity-store-api
    title: "Migrate IdentityStore + hat-sessions to brain HTTP"
    phase: "shell-port-1"
    status: in_review
    owner: claude
    deps: []
    matrix_cell: "U-shell×G"
    pr_url: "https://github.com/semantos/semantos-core/pull/622"
    note: |
      Endpoints for active hat, hat list, hat switch, cert snapshot.
      Hat sessions become brain-side state (consistent with sovereign-
      node framing — identity belongs to the brain, not the browser).
      loom-svelte already has lib/hat-sessions.ts + lib/auth.ts; this
      deliverable promotes them to first-class brain endpoints.

  - id: D-brain-config-store-api
    title: "Migrate ConfigStore + SettingsStore to brain HTTP"
    phase: "shell-port-1"
    status: in_review
    owner: claude
    deps: []
    matrix_cell: "U-shell×B"
    pr_url: "https://github.com/semantos/semantos-core/pull/624"
    note: |
      Per shell-cartridges-hats canon: user prefs flow as intents via
      verb.dispatch, not as writes to a config endpoint. This
      deliverable wires the GET side: `/api/v1/info` returns shell
      capabilities, `/api/v1/config/scope/{path}` returns scoped config
      slice. The PUT side stays intent-shaped.

  - id: D-brain-flow-runner-api
    title: "Migrate FlowRunner to brain HTTP"
    phase: "shell-port-1"
    status: in_review
    owner: claude
    deps:
      - D-brain-intent-classifier-api
    matrix_cell: "U-shell×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/627"
    note: |
      Flow execution state (FlowRunState) becomes brain-side; UI polls
      or WSS-subscribes for transitions. Endpoints: `POST /api/v1/flow/run`
      (start), `GET .../flow/{runId}` (state), `POST .../flow/{runId}/step`
      (advance/approve/cancel). Existing extensions register flows via
      grammar; brain owns the runner.

  - id: D-brain-loom-store-api
    title: "Loom-object CRUD as first-class brain HTTP surface"
    phase: "shell-port-1"
    status: in_review
    owner: claude
    deps: []
    matrix_cell: "U-shell×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/625"
    note: |
      LoomStore today is browser-side. Under Pattern T, loom-objects are
      brain-resident (sem_objects already are; LoomObject is a richer
      browser view). Endpoints to fetch object trees, list by type,
      stream patches. Extends the existing /api/v1/repl find-* family
      with typed endpoints to avoid string-parsing every query.

  - id: D-brain-contacts-api
    title: "core/contact-book exposed via brain HTTP"
    phase: "shell-port-1"
    status: in_review
    owner: claude
    deps: []
    matrix_cell: "U-shell×G"
    pr_url: "https://github.com/semantos/semantos-core/pull/617"
    note: |
      Operator-level surface over core/contact-book: list, addContact,
      connectTo (BRC-52 ECDH MESSAGING edge), revokeEdge, resolveContact,
      discoverByEmail. Endpoints: `GET /api/v1/contacts`,
      `POST .../contacts`, `POST .../contacts/{certId}/edges`,
      `DELETE .../contacts/{certId}/edges/{edgeId}`. Bearer-gated.
      Precondition for D-helm-contacts-panel + D-svelte-find-network.

  # ── Phase 2 — Svelte shell skeleton ────────────────────────────────

  - id: D-svelte-shell-skeleton
    title: "Svelte shell layout: dock + attention + cartridge slot"
    phase: "shell-port-2"
    status: in_review
    owner: claude
    deps:
      - D-brain-attention-api
    matrix_cell: "U-shell×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/619"
    note: |
      Top-level App.svelte layout: bottom dock, centre attention surface
      (Home), middle cartridge slot, top status bar. Replaces the
      current loom-svelte App which is oddjobz-only. Existing oddjobz
      views move under a "cartridge slot" pattern. Foundation for the
      rest of phase 2.

  - id: D-svelte-dock
    title: "Do/Talk/Find dock ported to Svelte (Tier 1/2/3)"
    phase: "shell-port-2"
    status: in_review
    owner: claude
    deps:
      - D-svelte-shell-skeleton
    matrix_cell: "U-shell×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/619"
    note: |
      Port apps/loom-react/src/helm/dock/* (Dock.tsx, Tier3Popover.tsx,
      context-weights.ts, useSpeechInput.ts) to Svelte 5 runes. Same
      verb model: Do (transact/manage/create/play/offer) · Talk
      (self/direct/squad/agent/broadcast) · Find (memory/market/network/
      value/truth). Keyboard parity (D/T/F + first-letter contexts +
      1-5 favourites). SlotLauncher invocation via verb.dispatch.

  - id: D-svelte-attention-surface
    title: "Attention surface ported to Svelte, consuming brain API"
    phase: "shell-port-2"
    status: in_review
    owner: claude
    deps:
      - D-svelte-shell-skeleton
      - D-brain-attention-api
    matrix_cell: "U-shell×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/632"
    note: |
      Port apps/loom-react/src/helm/AttentionSurface.tsx +
      hooks/useAttention.ts to Svelte 5. Reactive over WSS stream from
      D-brain-attention-api. Linearity badges, urgency accents,
      reason-text, formatTimeSince — feature parity with React.
      Telemetry round-trip (surfaced→clicked) via the new POST endpoint.

  - id: D-svelte-hat-switcher
    title: "HatSwitcher ported to Svelte, consuming brain identity API"
    phase: "shell-port-2"
    status: in_review
    owner: claude
    deps:
      - D-brain-identity-store-api
    matrix_cell: "U-shell×G"
    pr_url: "https://github.com/semantos/semantos-core/pull/633"
    note: |
      Port apps/loom-react/src/helm/HatSwitcher.tsx + identity/
      HatManager.tsx + HatSelector.tsx + PolicyCreator.tsx to Svelte.
      Existing apps/loom-svelte/src/components/HatSwitcher.svelte is a
      partial skeleton — extend, don't re-roll. Hat switch goes through
      brain (not local state) for sovereign-node consistency.

  - id: D-svelte-extension-switcher
    title: "Cartridge/extension switcher in Svelte"
    phase: "shell-port-2"
    status: in_review
    owner: claude
    deps:
      - D-svelte-shell-skeleton
    matrix_cell: "U-shell×B"
    pr_url: "https://github.com/semantos/semantos-core/pull/634"
    note: |
      Port apps/loom-react/src/helm/ExtensionSwitcher.tsx to Svelte.
      Lists registered cartridges; switching loads the cartridge into
      the centre slot. Per shell-cartridges-hats canon: cartridges
      register CartridgePeerView (see D-cartridge-peer-view-contract);
      switcher honours those.

  # ── Phase 3 — Conversation-native primitives ───────────────────────

  - id: D-svelte-talk-mode
    title: "Talk top-level surface ported to Svelte"
    phase: "shell-port-3"
    status: in_review
    owner: claude
    deps:
      - D-svelte-dock
    matrix_cell: "U-shell×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/630"
    pr_url: null
    note: |
      Port apps/loom-react/src/helm/TalkMode.tsx + navigator/views/
      TalkView.tsx. Talk becomes the conversation-native spine. The
      five Talk contexts (self/direct/squad/agent/broadcast) become
      sub-routes within this surface.

  - id: D-svelte-talk-direct
    title: "Talk → Direct: 1:1 p2p messaging surface"
    phase: "shell-port-3"
    status: in_review
    owner: null
    deps:
      - D-svelte-talk-mode
      - D-brain-contacts-api
      - D-SCG-persona-projection
    matrix_cell: "U-shell×G"
    pr_url: "https://github.com/semantos/semantos-core/pull/631"
    note: |
      The single-most-important deliverable for "sovereign p2p node"
      framing. Compose-and-send → mint a cell with REPLIES_TO (if
      reply) or new top-level cell, deliver via NetworkAdapter binding
      on the recipient's MESSAGING edge (D-network-* phase 5). Receive
      → conversation-graph pipeline persists, projectStream surfaces
      it in the chat view. End-to-end encrypted via the BRC-52 ECDH
      shared secret. UI shows persona-projected handle for the peer.

  - id: D-svelte-talk-self-agent
    title: "Talk → Self + Talk → Agent contexts in Svelte"
    phase: "shell-port-3"
    status: in_review
    owner: null
    deps:
      - D-svelte-talk-mode
    matrix_cell: "U-shell×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/651"
    note: |
      Self = reflection / Paskian graph. Agent = LLM interaction. Both
      are existing React contexts to port. Squad + Broadcast are
      deferred (no consumers yet); add as separate deliverables when
      cartridges need them.

  # ── Phase 4 — Find→Network + persona + cartridge peer-view ─────────

  - id: D-svelte-find-network
    title: "Find → Network: contacts + persona browser in Svelte"
    phase: "shell-port-4"
    status: in_review
    owner: claude
    deps:
      - D-svelte-dock
      - D-brain-contacts-api
      - D-SCG-persona-projection
    matrix_cell: "U-shell×G"
    pr_url: "https://github.com/semantos/semantos-core/pull/629"
    note: |
      First real consumer of projectPersona (shipped 2026-05-23 under
      D-SCG-persona-projection). Lists peers via D-brain-contacts-api;
      tap → renders projectPersona(certId) with default face filter.
      Active cartridge's CartridgePeerView (D-cartridge-peer-view-
      contract) determines label vocab + face highlight (Customers in
      oddjobz · Friends in jambox · Handles in bsvradar).

  - id: D-helm-contacts-panel
    title: "Operator contacts panel: add cert, edge state, revoke"
    phase: "shell-port-4"
    status: in_review
    owner: null
    deps:
      - D-brain-contacts-api
      - D-svelte-find-network
    matrix_cell: "U-shell×G"
    pr_url: "https://github.com/semantos/semantos-core/pull/635"
    note: |
      Operator surface for contact-book ops not covered by the
      browse-shaped Find→Network. Add contact by certId/QR/email,
      revoke edge, view edge recovery state (BACKUP_ON_CREATE /
      BACKUP_ON_CONFIRM / NONE), trigger discovery.

  - id: D-cartridge-peer-view-contract
    title: "CartridgePeerView contract: cartridges scope persona views"
    phase: "shell-port-4"
    status: in_review
    owner: null
    deps:
      - D-svelte-find-network
    matrix_cell: "U-shell×B"
    pr_url: "https://github.com/semantos/semantos-core/pull/650"
    note: |
      Extension to core/experience-cartridge: cartridges declare a peer
      view as a top-level optional field in cartridge.json. Shape is
      declarative (not a function) so the brain can evaluate it
      server-side under Pattern T — label/pluralLabel/emptyState +
      filterRelationKinds[] + filterEdgeTypes[] + defaultFace +
      faceFilter + primaryRelationKinds[] + verbs[]. Find→Network
      honours the active cartridge's view; root view (no cartridge)
      always reachable. Substrate stays unaware — cartridges provide
      vocabulary on top, never inside, projectPersona.
      Design doc: docs/design/CARTRIDGE-PEER-VIEW.md.

  - id: D-oddjobz-peer-view
    title: "Oddjobz cartridge: peers shown as Customers"
    phase: "shell-port-4"
    status: in_review
    owner: null
    deps:
      - D-cartridge-peer-view-contract
    matrix_cell: "U13×G"
    pr_url: "https://github.com/semantos/semantos-core/pull/650"
    note: |
      Register CartridgePeerView for cartridges/oddjobz: label =
      "Customers", filter restricts to peers with REQUESTS_ACTION or
      FULFILLS edges, defaultFace = commercial. First consumer of the
      contract; validates the pattern.

  - id: D-jambox-peer-view
    title: "Jambox cartridge: peers shown as Jammates/Friends"
    phase: "shell-port-4"
    status: in_review
    owner: null
    deps:
      - D-cartridge-peer-view-contract
    matrix_cell: "U-shell×G"
    pr_url: "https://github.com/semantos/semantos-core/pull/650"
    note: |
      Register CartridgePeerView for the jambox world-app: label =
      "Jammates" or "Friends", filter restricts to peers in shared
      jam-room SUBSCRIBES_TO groups, defaultFace = social. Second
      consumer; shows the pattern generalises beyond oddjobz.

  # ── Phase 5 — NetworkAdapter / transport ───────────────────────────

  - id: D-network-wss-direct
    title: "NetworkAdapter Phase 35B: WSS direct cross-internet transport"
    phase: "shell-port-5"
    status: pending
    owner: null
    deps: []
    matrix_cell: "U-shell×F"
    pr_url: null
    note: |
      Ship the pending Phase 35B per semantos_federation_transport memory.
      WSS adapter for cross-internet brain-to-brain. Configuration:
      target IPv6/IPv4 + port + cert. Reachable-detection (v6 first,
      v4 fallback). Reconnect policy. Frame format consistent with the
      session-protocol + CBOR pattern from existing ws-node-adapter.

  - id: D-network-messagebox-first-class
    title: "MessageBox NetworkAdapter binding (Calhooon container or native)"
    phase: "shell-port-5"
    status: pending
    owner: null
    deps: []
    matrix_cell: "U-shell×F"
    pr_url: null
    note: |
      Promote bsv-messagebox-cloudflare from documented external dep
      (per SOVEREIGN-NODE-PLAN.md) to a first-class NetworkAdapter.
      Two implementation paths: (a) thin TS wrapper over Calhooon's
      container (faster shipping), (b) native Rust/Zig implementation
      (more sovereign). Adapter speaks the same NetworkAdapter
      interface as WSS-direct + multicast so callers don't care.
      End-to-end encryption via BRC-52 ECDH — relay sees ciphertext.

  - id: D-network-multicast-cross-net
    title: "NetworkAdapter Phase 35A: UDP multicast cross-internet"
    phase: "shell-port-5"
    status: pending
    owner: null
    deps: []
    matrix_cell: "U-shell×F"
    pr_url: null
    note: |
      Ship the pending Phase 35A per semantos_federation_transport.
      Lan-multicast (skyminer_n8_mesh_live) already works. This is the
      cross-internet variant — IPv6 source-specific multicast (SSM) or
      relayed multicast. Lower priority than 35B + messagebox for the
      friend-peering scenario; useful for federated mesh.

  # ── Phase 6 — Sovereign-node packaging ─────────────────────────────

  - id: D-sovereign-node-compose
    title: "docker-compose for full sovereign node"
    phase: "shell-port-6"
    status: pending
    owner: null
    deps:
      - D-network-messagebox-first-class
    matrix_cell: "U-shell×F"
    pr_url: null
    note: |
      Per SOVEREIGN-NODE-PLAN.md §424+: docker-compose.node.yml at repo
      root. Services: semantos-node, messagebox, uhrp-host, wallet,
      headers-mirror. Healthcheck endpoint roll-up. Sane defaults for
      bind addresses, persistent volumes, secrets injection. Tested
      against a fresh VPS.

  - id: D-sovereign-node-installer
    title: "One-command sovereign-node installer"
    phase: "shell-port-6"
    status: pending
    owner: null
    deps:
      - D-sovereign-node-compose
    matrix_cell: "U-shell×F"
    pr_url: null
    note: |
      Per SOVEREIGN-NODE-PLAN.md §40+: `curl … | sh` style installer
      that bootstraps identity, wallet, storage, messaging, and agent
      from a fresh VPS. The third gap identified in the plan. Friend-
      peering scenario then reduces to: she runs the installer once,
      tells you her v6 + cert, you add her as a contact.

  # ── Phase 7 — React deprecation ────────────────────────────────────

  - id: D-loom-react-deprecate
    title: "Mark loom-react deprecated, plan removal"
    phase: "shell-port-7"
    status: in_review
    owner: null
    deps:
      - D-svelte-dock
      - D-svelte-attention-surface
      - D-svelte-hat-switcher
      - D-svelte-talk-mode
      - D-svelte-find-network
    matrix_cell: "U-shell×A"
    pr_url: "https://github.com/semantos/semantos-core/pull/653"
    note: |
      Once Svelte has feature parity for the helm spine (Dock,
      Attention, Hat, Talk, Find→Network), update apps/loom-react/
      README to "DEPRECATED; see apps/loom-svelte/", freeze new
      feature work, schedule removal date. The non-helm parts of
      loom-react (canvas/, inspector/, panels/, swarm/, sidebar/) are
      separately evaluated — most are workbench/dev surfaces, not
      operator surfaces; they either move to a dedicated workbench
      app or get deleted.

```
