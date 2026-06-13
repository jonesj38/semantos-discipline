---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/spec/protocol-v0.5.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.744445+00:00
---

# Semantos Protocol Specification

**Version:** v0.5
**Date:** 2026-04-26
**Status:** Frozen baseline. Supersedes `Semantos-Protocol-Spec-v0.01.docx`.
**Steward:** Real Blockchain Solutions (RBS), Queensland, Australia.
**Canon snapshot:** `docs/canon/` as of 2026-04-26 (post canonical-decision pass; 51 glossary entries).

> This specification absorbs the protocol-level content of *Plexus Technical Requirements v1.3* (Dusk Inc) into a single Semantos document, per the integrated-stack treatment recorded in `docs/SEMANTOS-DOC-PLAN.md` §5. Implementation details specific to the Plexus reference deployment (Go service operations, PostgreSQL schema specifics) remain in the Plexus Technical Requirements; protocol invariants live here.

---

## 1. Introduction

### 1.1 Purpose and scope

This document specifies the wire formats, identity protocols, kernel invariants, and capability lifecycle that constitute a conformant Semantos implementation. It defines what implementations MUST, SHOULD, and MAY do at the protocol layer. It does NOT specify: vertical-specific grammars, application-layer APIs, UI/UX, deployment topology beyond what the architecture requires, or commercial product packaging.

A conformant Semantos implementation:

- MUST implement the cell wire format (§3) bit-for-bit.
- MUST enforce kernel invariants K1–K5, K7 at the bytecode gate (§9).
- MUST verify BRC-100 signed envelopes on every cross-process and cross-node message (§12).
- MUST implement the four-phase recovery protocol (§6).
- MUST treat capability tokens as LINEAR semantic resources (§5).
- SHOULD provide a Verifier Sidecar (§9.5) per the deployment topology of choice.
- SHOULD implement at least one surface grammar that compiles to SIR (§7); the reference implementation is Lisp.
- MAY implement additional surface grammars, additional adapters, and additional lexicons.

### 1.2 Document conventions

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, MAY, REQUIRED, RECOMMENDED, and OPTIONAL in this document are to be interpreted as described in RFC 2119.

Code identifiers (`cell_id`, `OP_CHECKCAPABILITY`) appear in monospace. Multi-byte values are little-endian unless otherwise noted. Hash function references default to SHA-256 unless otherwise specified.

### 1.3 Terminology

This document uses the canonical terms of `docs/canon/glossary.yml` as of the snapshot recorded in the frontmatter. Where this document uses a term that is also a glossary entry, the term carries its glossary definition. Significant terms include: **cell**, **cell engine**, **SIR**, **OIR**, **SignedBundle**, **BCA**, **cert_id**, **hat**, **capability token**, **boot sequence**, **substrate**, **adapter**, **Verifier Sidecar**, **lexicon**, **jural category**, **governance domain**, **MFP**, **VFS**, **octave**, **tick** (with disambiguation: WorldTick, MeteringTick).

### 1.4 Conformance levels

| Level | Implements | Notes |
|---|---|---|
| **Kernel-conformant** | §3 + §8 + §9 (cell wire format, cell engine, K1–K5, K7) | Minimum substrate; can run a sovereign node |
| **Identity-conformant** | Kernel + §4 + §6 (identity protocol + recovery) | Enables BRC-100 signed envelopes and Plexus recovery |
| **Capability-conformant** | Identity + §5 + §10 (capability tokens + on-chain anchoring) | Enables BRC-108 capability authority and SPV verification |
| **Pipeline-conformant** | Capability + §7 (SIR/OIR pipeline) | Enables the compression gradient and multi-surface-grammar support |
| **Mesh-conformant** | Pipeline + §11 + §12 (MFP + mesh transport) | Federation-ready sovereign node |

A "fully-conformant" Semantos implementation implements every level above. The reference implementation (`semantos-core`) targets full conformance.

---

## 2. Architecture overview

### 2.1 The substrate

A Semantos implementation is built around ten substrate components (per the Unification Roadmap §2):

| # | Component | Role |
|---|-----------|------|
| U1 | Cell engine | 2-PDA execution; K1/K3/K4/K5/K7 enforcement |
| U2 | Plexus core / vendor SDK | Identity recovery; control-plane API |
| U3 | Identity / derivation / recovery | BRC-42 BKDS keys, BRC-52 certs, monotonic indices |
| U4 | Capability domain | LINEAR BRC-108 UTXO capabilities |
| U5 | Verifier Sidecar | BRC-100 enforcement; SPV checks |
| U6 | Mesh | IPv6 multicast over `SignedBundle`; BCA peer ID |
| U7 | VFS / octaves | Content-addressed storage |
| U8 | SIR + lexicons | Jural categories; governance context |
| U9 | Lean proof layer | Mechanised K1–K10 proofs |
| U10 | MFP engine | 8-state channel FSM; tick proofs; settlement |

A conformant implementation MUST implement U1, U3, U4, U5 at minimum; U2, U6, U7, U8, U9, U10 SHOULD be implemented for full conformance.

### 2.2 The compression gradient

A Semantos implementation compresses surface input through a sequence of typed transformations:

```
Surface grammar  (Lisp; LaTeX, Lean-ish, Ricardian, EDI optional)
       │
       ▼
SIR (Semantic IR — jural category, taxonomy, identity, governance)
       │  lowerSIR()    — refuses malformed claims structurally
       ▼
OIR (Opcode IR, ANF — named bindings, predicates)
       │  emit()
       ▼
Opcode bytes (0x4C–0xD0 Plexus extension range, plus standard Bitcoin Script)
       │
       ▼
Cell engine (2-PDA bounded execution)
       │
       ▼
Cell + receipt, persisted via storage adapter
```

Each layer MUST satisfy the validation rule, loss boundary, and emit-pass discipline specified in §7. Two SIR programs that express the same semantic intent MUST produce α-equivalent OIR programs (§7.4).

### 2.3 The boot sequence

A conformant sovereign node MUST be bootable end-to-end via the canonical 15-step boot sequence:

1. User supplies email + answers to challenge set
2. PBKDF2 100 000 iterations on device → root seed (client-only)
3. Derive BRC-52 cert from root seed → `cert_id` (client-only)
4. BCA(`cert_id`) computed via shared BCA library (deterministic)
5. Plexus vendor SDK initialises tenant nodes locally
6. Capability domain mints initial capability UTXOs
7. Cell engine boots; `kernel_set_enforcement(1)` is called
8. Verifier Sidecar starts (per topology decision; §9.5)
9. World Host (if installed) starts authoritative regions
10. Mesh adapter joins multicast group derived from `cert_id`
11. UI server (Helm) binds localhost
12. Adapters subscribe to: region tick deltas; Plexus identity event stream; capability UTXO change feed
13. Recovery payload backed up to Plexus Recovery Service
14. Metered services open MFP cashlanes
15. User is online, sovereign, federated

A conformant implementation MUST be able to reach step 7 (`kernel_set_enforcement(1)`) without external network dependencies. Steps 8–15 MAY require external services for certain capabilities.

---

## 3. Cell wire format

### 3.1 Cell structure

A *cell* is a 1024-byte binary structure. A simple cell consists of one *cell unit* (header + payload). A composite cell consists of one cell unit followed by one or more *continuation cells*.

| Byte range | Content |
|-----------|---------|
| 0–255 | Cell header (256 bytes; §3.2) |
| 256–1023 | Semantic payload (≤ 768 bytes) |
| 1024–N | Continuation cells (1024 bytes each; §3.3) |

Cells MUST be exactly 1024 bytes per cell unit, zero-padded if content is shorter. Composite cells MUST serialise sequentially in byte layout (Cell 0, Cell 1, Cell 2, …).

### 3.2 Cell header (256 bytes)

All multi-byte integers little-endian. The header layout is the canonical input to the type-hash registry, the cell packer (`core/cell-ops/src/packer/cell-packer.ts`), and the Zig cell engine (`core/cell-engine/src/cell.zig`).

| Offset | Size | Field          | Description                                                 |
|--------|------|----------------|-------------------------------------------------------------|
| 0      | 16   | Magic          | `0xDEADBEEF CAFEBABE 13371337 42424242` (16 bytes total)    |
| 16     | 4    | Linearity      | uint32 LE: 1=LINEAR, 2=AFFINE, 3=RELEVANT, 4=DEBUG          |
| 20     | 4    | Version        | uint32 LE: object state version (monotonic)                 |
| 24     | 4    | DomainFlag     | uint32 LE: domain flag (per §4.5)                           |
| 28     | 2    | RefCount       | uint16 LE: reference count                                  |
| 30     | 32   | TypeHash       | SHA-256(`whatPath:howSlug:instPath`)                        |
| 62     | 16   | OwnerID        | 16-byte owner identifier                                    |
| 78     | 8    | Timestamp      | uint64 LE: milliseconds since epoch                         |
| 86     | 4    | CellCount      | uint32 LE: total cells (header + continuations)             |
| 90     | 4    | PayloadSize    | uint32 LE: semantic payload bytes in Cell 0 (≤ 768)         |
| 94     | 1    | Phase          | Pipeline phase (0x00=source, 0x01=parse, …, 0x07=outcome)   |
| 95     | 1    | Dimension      | 0x00=composite, 0x01=what, 0x02=how, 0x03=instrument        |
| 96     | 32   | ParentHash     | SHA-256 of parent cell (zero if root)                       |
| 128    | 32   | PrevStateHash  | SHA-256 of previous state (zero if genesis)                 |
| 160    | 96   | Reserved       | Zero-padded; reserved for future use                        |

The magic bytes MUST validate at byte offset 0 before any other parsing. The `isValidCell()` function MUST check these 16 bytes and refuse cells that do not match. Reserved bytes MUST be zero on encode and SHOULD be ignored on decode (forward-compatible).

### 3.3 Continuation cells

Continuation cells follow Cell 0 in serialisation order. Each continuation cell has an 8-byte header followed by up to 1016 bytes of payload.

| Offset | Size | Field        | Description                                                  |
|--------|------|--------------|---------------------------------------------------------------|
| 0      | 1    | CellType     | 0x01=BUMP, 0x02=ATOMIC_BEEF, 0x03=ENVELOPE, 0x04=DATA, 0x05=STATE |
| 1      | 2    | CellIndex    | uint16 LE: 1-based position in continuation sequence          |
| 3      | 2    | TotalCells   | uint16 LE: total continuation cells (excludes Cell 0)         |
| 5      | 2    | PayloadSize  | uint16 LE: actual data bytes (≤ 1016)                         |
| 7      | 1    | Reserved     | Zero                                                          |
| 8      | 1016 | Payload      | Cell-type-specific data (zero-padded to 1016)                 |

The 2-PDA interpreter MUST push continuation cells onto the auxiliary stack in reverse order so that LIFO popping yields BUMP first, then ATOMIC_BEEF, then ENVELOPE/DATA/STATE. This ordering enables fail-fast verification (§8.4).

### 3.4 Linearity classes

The linearity class at header offset 16 determines consumption rules. The cell engine MUST enforce these at the bytecode gate (K1).

| Class       | Code | Rule                                           |
|-------------|------|-----------------------------------------------|
| LINEAR      | 1    | Consumed exactly once. No DUP. No DROP.        |
| AFFINE      | 2    | Used at most once. No DUP. DROP permitted.     |
| RELEVANT    | 3    | Used at least once. DUP permitted. No DROP.    |
| DEBUG       | 4    | Unrestricted — development only. DUP and DROP both permitted. |

Source of truth: [`core/cell-engine/src/linearity.zig:10-14`](../../core/cell-engine/src/linearity.zig) (`LinearityType` enum) and [`proofs/lean/Semantos/Cell.lean:13-17`](../../proofs/lean/Semantos/Cell.lean) (inductive `Linearity` type). [`proofs/lean/Semantos/Linearity.lean`](../../proofs/lean/Semantos/Linearity.lean)'s file header explicitly says it transliterates the Zig source and "Every row must match." K1 (`LinearityK1.lean`) proves the consumption invariants for LINEAR/AFFINE/RELEVANT.

A linearity violation (e.g., attempting to consume an already-consumed LINEAR cell) MUST result in immediate state rollback (K4 failure atomicity). The cell engine MUST NOT apply any state delta from the violating execution.

### 3.5 Pipeline phases

Each cell carries a pipeline phase byte (offset 94) identifying where in the semantic compiler pipeline it was produced. Each phase has a default linearity that the producer SHOULD honour:

| Byte | Phase     | Default linearity | Description                                              |
|------|-----------|-------------------|----------------------------------------------------------|
| 0x00 | source    | RELEVANT          | Raw evidence (messages, documents, voice)                |
| 0x01 | parse     | LINEAR            | Extraction consumed once to merge into state             |
| 0x02 | ast       | AFFINE            | Accumulated state container (updatable)                  |
| 0x03 | typecheck | RELEVANT          | Classification and scoring                               |
| 0x04 | optimise  | LINEAR            | Scoring result consumed once                             |
| 0x05 | codegen   | RELEVANT          | Instrument generation                                    |
| 0x06 | action    | LINEAR            | Operator/user decision consumed once                     |
| 0x07 | outcome   | RELEVANT          | Diagnostic feedback                                      |

Producers MAY override the default linearity per cell when the domain semantics demand it; the override MUST be reflected in the linearity field of the cell header.

### 3.6 Hash chain

Every state transition MUST produce: a new state snapshot with incremented version (offset 20); a typed patch recording the delta, source, and evidence reference; a fresh `stateHash` (SHA-256 of the canonical serialised state); and a `prevStateHash` (offset 128) set to the previous state's `stateHash`.

The chain MUST be: genesis state (`prevStateHash = 0x00…00`) → state 1 → state 2 → … → state N. Each state's `prevStateHash` MUST equal the previous state's `stateHash`. Violation indicates tampering and MUST trigger audit logging and state rollback.

### 3.7 Type hash construction

The type hash (header offset 30) is a deterministic SHA-256 digest computed from the cell's three classification dimensions:

```
typeHash = SHA-256(whatPath || ":" || howSlug || ":" || instPath)
```

where `whatPath`, `howSlug`, and `instPath` are UTF-8 encoded strings representing the WHAT (domain classification), HOW (operation mode), and INSTRUMENT (artefact type) dimensions respectively.

Example: `SHA-256("services.trades.carpentry:hire:inst.contract.service-agreement")` produces a 32-byte type hash uniquely identifying carpentry hire service-agreement cells.

The type hash registry (`core/cell-ops/`) maps known type hashes to their pre-image strings; implementations MAY cache the registry but MUST treat it as authoritative when a type hash matches.

### 3.8 HTTP transport: layer-collapse MIME types

The 1024-byte cell layout defined in §3.1–3.3 is the same byte sequence whether the cell is at rest in the cell store, in memory, or on the wire. The HTTP read surface that exposes raw cells therefore carries them unmodified — no JSON envelope, no SignedBundle wrapping, no endianness translation at the wire layer. Multi-byte integers MUST already be little-endian per §3.2; the HTTP layer treats the body as opaque bytes.

Canonical source of the layout: `core/cell-engine/src/constants.zig` (`CELL_SIZE = 1024`, `HEADER_SIZE = 256`, `PAYLOAD_SIZE = 768`, `CONTINUATION_PAYLOAD_SIZE = 1016`) and `core/cell-engine/src/cell.zig` (`packCell` / `unpackCell`). Design intent and rationale: deliverable [`D-LC1`](../canon/deliverables.yml) ("layer collapse for read paths").

#### 3.8.1 MIME types

| Content-Type                       | Body shape          | Endpoint                                          | Required response headers                                |
|------------------------------------|---------------------|---------------------------------------------------|----------------------------------------------------------|
| `application/x-semantos-cell`      | exactly 1024 bytes  | `GET /api/v1/cell/<sha256hex>`                    | `x-cell-sha256: <64-hex>`; optionally `x-cell-anchor: pending\|confirmed` |
| `application/x-semantos-cells`     | N × 1024 bytes (N ≥ 0) | `GET /api/v1/cell/since/<prev_hash_hex>`        | `x-cell-count: <N>`; optionally `x-next-cursor: <hex>` when paginated |

Body length divided by 1024 MUST equal `x-cell-count`. An empty `application/x-semantos-cells` body (N = 0) is a valid response indicating the chain tip — the given `prev_state_hash` has no known forward children.

#### 3.8.2 Endpoint semantics

- **`GET /api/v1/cell/<sha256hex>`** — singular fetch by content hash. Responses: `200` (raw cell bytes), `400` (malformed hash), `401` (bearer invalid), `404` (acceptor absent or hash unknown), `405` (non-GET). `cache-control: immutable` is set because the hash uniquely identifies the bytes. Anchor-status surface is defined in [`D-LC5`](../canon/deliverables.yml): when the brain has an opinion about on-chain anchoring for the cell, `x-cell-anchor` is set to `pending` (anchor TX not yet observed) or `confirmed` (anchor-attestation cell landed); absence of the header means no opinion.
- **`GET /api/v1/cell/since/<prev_hash_hex>`** — forward-walk by `prev_state_hash`. Returns every cell whose header `prev_state_hash` (§3.2 offset 128) equals the supplied hash, concatenated. Today's implementation caps at 1024 cells per response (1 MiB body); cursor pagination via `?after=<hex>&limit=<N>` query parameters and an `x-next-cursor` response header is the [`D-LC4`](../canon/deliverables.yml) follow-up (in flight). Conforming clients SHOULD treat `x-next-cursor` as opaque.

#### 3.8.3 Vendor-prefix note

Both types use the RFC 6838 §3.4 vendor `x-` prefix — they are **provisional** and not IANA-registered. Implementations MUST treat the names as the wire identity for now. If Semantos pursues formal MIME registration, the canonical names would drop the `x-` prefix (`application/semantos-cell`, `application/semantos-cells`); a future revision of this specification will document the transition.

Wire-handler source of truth: `runtime/semantos-brain/src/site_server/reactor.zig` (`reactorHandleCellRaw`, `reactorHandleCellSince`) and `runtime/semantos-brain/src/cell_raw_http.zig` (path parsers + the `CELL_BYTES` re-export).

---

## 4. Identity protocol

This section absorbs the protocol-level content of Plexus Technical Requirements v1.3 §1, §4, §9, §10, §12, §15, §19, §25, §29.

### 4.1 Root key derivation

A user's root seed MUST be derived client-side via PBKDF2 over the user's challenge-set answers:

- Hash function: SHA-256
- Iterations: minimum 100 000
- Salt: deterministic per user (derivable from email + a per-deployment salt)
- Output length: 32 bytes (256 bits)

The root seed MUST NEVER be transmitted to or stored on any server. Server-side storage of challenge-answer hashes (for recovery-session authentication) MUST use SHA-256 over normalised + salted answers.

### 4.2 BRC-52 certificate format

A *BRC-52 certificate* encodes a node's identity in the Plexus DAG. Required fields:

| Field          | Type         | Description                                                  |
|----------------|--------------|--------------------------------------------------------------|
| `subject`      | bytes(33)    | Compressed secp256k1 public key                              |
| `issuerCertId` | bytes(32) \| null | `cert_id` of the parent cert (null for root)            |
| `appId`        | bytes(32)    | Application namespace identifier                             |
| `childIndex`   | uint32       | Strictly monotonic per parent                                |
| `createdAt`    | uint64       | Milliseconds since epoch                                     |
| `domainFlags`  | bytes(N)     | Optional sequence of associated domain flag values (uint32) |
| `signature`    | bytes(64+)   | Issuer signature over canonical preimage                     |

The `cert_id` is `SHA-256(canonical_preimage)`, where the canonical preimage is a deterministic byte serialisation of all fields *except* `signature`. The `cert_id` MUST be 32 bytes.

Issuance flow:

1. Parent entity derives a `CHILD_CREATION` key (domain flag `0x06`, §4.5).
2. Child generates a key pair client-side via BRC-42 derivation from a parent secret never available to the server.
3. Parent signs the child's BRC-52 certificate using the `CHILD_CREATION` key.
4. Child's certificate is assigned a monotonic `childIndex` (max existing for this parent + 1; never reused).
5. Certificate is enrolled in the Plexus recovery substrate.

All signatures MUST use the BRC-100 wallet interface format (§4.6).

### 4.3 BCA derivation

A *BCA* (Blockchain Channel Address) is a deterministic IPv6-shaped address derived from a `cert_id`. Used as a peer identifier in the mesh and as the channel-funding key for MFP payment channels.

The derivation function is implemented in `core/cell-engine/src/bca.zig` and conformance vectors live at `core/cell-engine/tests/vectors/bca_*.json`. A conformant implementation MUST produce IPv6 addresses byte-identical to the reference implementation for all conformance vectors. The TS mirror of the BCA library is the D-A0 deliverable.

### 4.4 The identity DAG

Plexus identity is a directed acyclic graph of BRC-52 certificates. Each node has:

- A `cert_id` (the node's identifier)
- An `issuerCertId` (the parent edge in the DAG; null for the user's root)
- A monotonic `childIndex` per parent
- An optional `domainFlags` sequence

A single identity (BRC-52 cert) MAY exist in multiple *contexts* within the DAG — the same person as customer and as employee, for example. Each context is uniquely identified by the tuple `(cert_id, appId, parentCertId, tenantPathSteps)`. Key universes for distinct contexts MUST be mathematically isolated via divergent BRC-42 derivation paths using domain flags (§4.5); keys derived in one context MUST NOT be mathematically related to keys in another, even if the root secret is compromised.

### 4.5 Domain flag namespace

A *domain flag* is a 4-byte uint32 namespace identifier. The namespace MUST be partitioned exactly as follows:

| Range                          | Use                                              |
|--------------------------------|--------------------------------------------------|
| `0x00000001`–`0x000000FF`      | Plexus reserved (well-known well-defined flags)  |
| `0x00000100`–`0x0000FFFF`      | Extended Plexus standards                        |
| `0x00010000`–`0xFFFFFFFF`      | Operator sovereignty (client-defined)            |

The Plexus reserved range includes the following well-known flags. Implementations MUST NOT redefine these:

| Flag   | Name              | Use                                                  |
|--------|-------------------|------------------------------------------------------|
| `0x01` | EDGE_CREATION     | Peer-to-peer ECDH edge derivation                    |
| `0x02` | SIGNING           | Digital signature operations                         |
| `0x03` | ENCRYPTION        | Field-level encryption                               |
| `0x04` | MESSAGING         | Secure message channels                              |
| `0x05` | ATTESTATION       | Third-party attestation                              |
| `0x06` | CHILD_CREATION    | Certificate child issuance                           |
| `0x07` | PERMISSION_GRANT  | Capability token minting                             |
| `0x08` | DATA_SOVEREIGNTY  | Data export / portability                            |
| `0x09` | SCHEMA_SIGNING    | Schema version attestation                           |
| `0x0A` | METERING          | Payment channel operations                           |
| `0x0B` | EXPERIENCE        | World Host region authority (per Roadmap §8 Q1)      |
| `0x0C` | HOST_EXEC         | Host command execution (Phase 38)                    |

Domain flag enforcement at the cell engine is via `OP_CHECKDOMAINFLAG` (§8.2); the Lean K3 invariant proves the check is total and correct.

The namespace partition MUST be codified in `core/protocol-types/src/namespace.ts` so that lexicon ids, region types, world-frame `msgType`s, tenant types, and any future id-type can cite a single source of truth (per Unification Roadmap §8 Q2).

### 4.6 Edge protocol

An *edge* is a peer-to-peer cryptographic relationship between two cert nodes, established via ECDH using BRC-85 PIKE (Proven Identity Key Exchange). Edge creation:

1. Both parties derive keys from the `EDGE_CREATION` domain (flag `0x01`).
2. Public keys are exchanged out-of-band; ECDH shared secret is computed client-side.
3. Edge recipe (BRC-69 key linkage revelation) is computed.
4. Recipe is enrolled per the recovery policy: `BACKUP_ON_CREATE` (atomic), `BACKUP_ON_CONFIRM` (deferred), or `NONE` (ephemeral).

Edge uniqueness is enforced by the tuple `(cert_id, appId, counterpartyCert, edgeType)`. ECDH shared secrets MUST be derived using secp256k1 and MUST NOT be transmitted over any channel. All edge operations MUST use constant-time comparison.

The *edge backup recipe* (BRC-69) is the deterministic data the system stores so that a recovering device can reconstruct the shared secret without Plexus ever holding it. Per Plexus Tech §12, the edge is the "primary recoverable unit."

### 4.7 Hat (role-identity dimension)

A *hat* is a role-or-capacity dimension under which a user signs actions: "Bob-as-tenant" vs "Bob-as-friend" vs "Bob-as-trustee." Each hat is associated with a distinct BRC-52 cert (or, transitionally, a distinct hat record backed by a single cert) and a distinct capability scope.

Hat identity is the per-action signing principal. The SIR layer (§7.1) carries a hat identity binding in every node's `identity` field; trust-tier enforcement at SIR refuses cross-role authoritative claims structurally. A renter cannot sign actions as a landlord even with a syntactically valid SIR program — the SIR refuses to lower it.

The migration path from `facet` (the older term) to `hat` is documented in `docs/prd/refactor-monoliths/00A-facet-to-hat-rename.md`.

---

## 5. Capability tokens

### 5.1 Token format

A *capability token* is a UTXO formatted per BRC-108 (Identity-Linked Token Protocol). The token MUST:

- Be bound to a BRC-52 certificate's `subject` (33-byte compressed public key).
- Be represented as a BSV UTXO with a locking script encoding the constraint structure.
- Be classified as a LINEAR semantic resource.
- Be immutable after creation (the only state transition is revocation via spending).

Spending the UTXO is the consumption proof. The spending transaction MUST be the on-chain record of revocation.

### 5.2 Capability classes

The substrate defines six well-known capability classes:

| Class                      | Use                                                   |
|----------------------------|-------------------------------------------------------|
| `cap.recovery`             | Identity recovery authorisation                       |
| `cap.permission`           | General permission grant                              |
| `cap.data_access`          | Read access to encrypted fields                       |
| `cap.compute_delegation`   | Delegated computation authority                       |
| `cap.metered_access`       | Rate-limited resource access (gates MFP participation)|
| `cap.transfer`             | Ownership transfer authorisation                      |

Recovery capabilities MUST be segregated from operational capabilities in separate UTXOs to limit exposure. Implementations MAY define additional capability classes in the operator-sovereign domain-flag range.

### 5.3 Token lifecycle

**Mint.** Parent context constructs a BRC-108 UTXO. The locking script encodes: `ownerCertId`, capability class, and constraints (expiry, geo bounds, max invocations, required domain flags). The output is locked to the recipient's `certificate.subject`.

**Verify.** Any party with the public key can verify the token via SPV: BUMP (BRC-74) proves the minting transaction is in a block; atomic-BEEF (BRC-95) proves transaction ancestry. The token's spent/unspent status requires an additional liveness check (§5.4).

**Consume.** The token holder spends the UTXO. The spending transaction IS the consumption proof. LINEAR semantics: spent once, permanently revoked.

**Revoke.** The issuer MAY force-revoke by spending from the issuer's side (if the locking script permits). Revocation is instant and on-chain.

### 5.4 SPV validation and liveness

Token verification uses BEEF (BRC-62) and BUMP (BRC-74) from `@bsv/sdk` for transaction inclusion proofs:

1. Parse the BEEF envelope to extract the transaction and merkle path.
2. Verify the merkle path against the block header.
3. Verify the transaction output matches the expected locking script.

SPV proves transaction inclusion in a block. It does NOT prove a UTXO is unspent. Determining whether a capability token has been consumed requires one of:

- Direct query to a BSV overlay service or UTXO lookup node.
- Application-layer liveness protocol (token holder periodically provides a signed timestamp proving continued possession of the spending key).
- Watchman pattern (a designated node monitors the UTXO set for spends of known capability tokens and broadcasts revocation events).

Implementations MUST NOT claim SPV alone proves a token is valid. The inclusion proof establishes the token was minted; the liveness check establishes it has not been revoked.

### 5.5 Locking script structure

Capability locking scripts encode constraints directly in Bitcoin Script on-chain:

- Time locks: `OP_CHECKLOCKTIMEVERIFY` for expiry enforcement.
- Identity binding: `OP_CHECKSIG` against `certificate.subject`.

Additional Plexus-specific constraints (type enforcement, domain flag checks) are evaluated by the local 2-PDA cell engine (§8), NOT on-chain. The on-chain script handles standard Bitcoin Script predicates (signature, timelock); the cell engine handles semantic predicates (linearity, capability class, participant role, domain flag).

---

## 6. Recovery protocol

### 6.1 Four-phase recovery flow

Recovery MUST follow a four-phase protocol. No single phase is sufficient to authorise reconstruction.

**Phase 1 — Email OTP.** User initiates recovery; server sends OTP to the registered email. OTP validates the user's email-address claim.

**Phase 2 — Challenge-response.** User answers pre-registered challenge questions (challenge set; §4.1, §6.5). Server validates using constant-time comparison against stored hashes. Maximum 10 attempts per hour; 5 consecutive failures lock the account for 24 hours.

**Phase 3 — Recovery payload export.** Server exports recovery payload (~3.4 KB compressed). Contains: derivation state records, resource registrations, functional domain records, edge backup recipes, tenant path steps, algorithm version records, schema mappings. The payload MUST NOT include raw private keys, root seeds, or plaintext challenge answers.

**Phase 4 — Client-side reconstruction.** Client receives the recovery payload. Derives the root key from challenge answers via PBKDF2 (SHA-256, minimum 100 000 iterations; §4.1). Reconstructs the full identity DAG by re-deriving all keys from the root using the BRC-42 paths encoded in the metadata. Server has zero knowledge of reconstruction material.

### 6.2 Recovery payload format

The recovery payload is a BRC-100-signed JSON blob, approximately 3.4 KB compressed. Required fields:

| Field                    | Description                                                          |
|--------------------------|----------------------------------------------------------------------|
| `version`                | Recovery payload format version                                      |
| `userCertId`             | Root cert id                                                         |
| `derivationStates`       | Sequence of `(resourceId, domainFlag, currentIndex, algorithmVersion)` |
| `domainCeilings`         | Per-domain monotonic-index ceiling (so reconstruction can validate)   |
| `edgeBackupRecipes`      | Sequence of BRC-69 key linkage revelation recipes                    |
| `tenantPathSteps`        | DAG-traversal path for each enrolled tenant                          |
| `schemaMappings`         | Deterministic mappings between schema versions                       |
| `signature`              | BRC-100 signature over the canonical preimage                        |

The payload is *useless without the user's challenge answers*. An attacker with full server access cannot impersonate the user, derive their keys, or decrypt their data.

### 6.3 Threshold recovery

For high-security roots and high-value capabilities, the substrate MUST support Shamir Secret Sharing (t-of-n) fragmentation:

- When an entity designates a root key or on-chain capability as "high-security," the substrate MUST apply Shamir Secret Sharing.
- Recovery of a higher-security construct (e.g., a Vault) MUST require additional challenge sets gated behind the user's capacity to exercise rights over their standard root key.
- The client's local device MUST execute the mathematical reassembly of threshold shares; raw high-security private keys MUST NOT be reconstructed, exposed, or transmitted to the server-side infrastructure.

### 6.4 Multi-party group recovery

For multi-party environments (e.g., a corporate domain with multiple authorised users), the substrate MUST support recovery via individual bilateral edges:

- The system SHALL NOT store a central group key anywhere in the server-side architecture.
- Recovery of a multi-party environment SHALL rely entirely on the stored individual bilateral edge backup recipes to reconstruct the relationships.
- If a recovering party lacks one of the required bilateral shared secrets to reconstruct the group key (e.g., they hold only two out of three secrets), the system SHALL enable the missing secret to be securely communicated to them via an existing bilateral edge.

The group's cryptographic foundation MUST be restorable without the system ever knowing the shared secrets.

### 6.5 Brute-force mitigation

| Surface                  | Limit                                                               |
|--------------------------|---------------------------------------------------------------------|
| Recovery initialisation  | Maximum 10 attempts per hour                                        |
| Challenge answers        | 5 consecutive failures locks the account for 24 hours               |
| PBKDF2 iterations        | Minimum 100 000 (SHA-256)                                           |
| Context enrollment       | Rate limited to prevent enumeration                                  |
| Edge creation            | Rate limited to prevent enumeration                                  |

---

## 7. The compression gradient

This section specifies the SIR / OIR pipeline that all surface-language compilation MUST target.

### 7.1 Semantic IR (SIR)

A SIR program is a sequence of *SIR nodes*. Each node MUST carry:

- **Identifier** (`id`: counter-based, e.g. `$s0`, `$s1`).
- **Jural category** (`category`): one of `declaration`, `obligation`, `permission`, `prohibition`, `power`, `condition`, `transfer`. The seven-category set is the minimum vocabulary sufficient to distinguish every act the substrate performs (per `docs/SEMANTIC-IR-ARCHITECTURE.md` §3 and the canon's `jural-category` entry; adapted from Hohfeld 1913).
- **Taxonomy coordinates** (`taxonomy`): `{what, how, why, where?}` locating the node in the domain ontology.
- **Identity binding** (`identity`): subject hat reference; optional cert reference.
- **Governance context** (`governance`):
  - `trustClass`: `cosmetic` | `interpretive` | `authoritative`
  - `proofRequirement`: `none` | `attestation` | `formal`
  - `executionAuthority`: `local_facet` | `hat_scoped` | `delegated`
  - `linearity`: `LINEAR` | `AFFINE` | `RELEVANT` | `FUNGIBLE`
  - `allowedEmitOps`: optional whitelist of OIR binding kinds the lower pass may emit
  - `domainBinding`: optional governance domain (per `docs/SEMANTIC-IR-ARCHITECTURE.md` §10)
- **Action** (`action`): the verb being expressed.
- **Constraint structure** (`constraint`): typed predicate tree.
- **Provenance** (`provenance`): source, confidence, timestamp.
- **Optional**: `target`, `transferTo`, `gate`, `fulfillment`.

The SIR's canonical form MUST be checkable in time linear in the size of the program.

### 7.2 Opcode IR (OIR, ANF)

The OIR is administrative normal form. Each binding MUST have:

- **Name** (`$0`, `$1`, …, monotonic).
- **Kind**: one of `comparison`, `logical`, `capability`, `domainCheck`, `timeConstraint`, `hostCall`, `typeHashCheck`, `deref`.
- **Operands**: names of prior bindings or literal constants only. Operands MUST NOT contain nested computation.

A complete OIR program has:
- A sequence of bindings.
- A designated `result` binding (the program's return value).

### 7.3 Lowering rules

The `lowerSIR(SIRProgram → IRProgram)` pass MUST translate each jural category into the canonical OIR pattern:

| Category       | OIR pattern                                                                       |
|----------------|-----------------------------------------------------------------------------------|
| `declaration`  | identity check + field assertions + VERIFY                                        |
| `obligation`   | temporal gate (deadline) + capability check (metering) + VERIFY                   |
| `permission`   | single capability check                                                           |
| `prohibition`  | constraint check + logical negation + VERIFY                                       |
| `power`        | identity check + capability check + type-hash check + VERIFY                      |
| `condition`    | inline temporal or state predicate gating its containing expression               |
| `transfer`     | sender identity check + receiver identity check + transfer cap + metering + VERIFY|

The lower pass MUST refuse to produce OIR for any of the following malformed claims:

- A node with `trustClass: authoritative` but `proofRequirement` other than `formal`.
- A node whose emitted OIR bindings would fall outside `allowedEmitOps`.
- A node with `executionAuthority: delegated` for a vertical that has not configured delegation.
- An action verb not in the active extension's vocabulary.
- A constraint field reference that does not resolve in the active extension's field schema.

These refusals are static (compile-time) and produce structured errors carrying the failing node id, the failed predicate, and a remediation suggestion.

### 7.4 α-equivalence requirement

Two SIR programs that express the same semantic intent MUST produce α-equivalent OIR programs. Under canonical variable naming, the OIR programs MUST emit byte-identical opcode bytes via `emit()`.

The α-equivalence requirement is the contract that licenses multi-surface-grammar support: any new surface grammar (Lisp today; LaTeX, Lean-ish, Ricardian, EDI as they ship) MUST produce the same OIR (and therefore the same opcode bytes) as the existing surface grammars for the same intent. The cell engine MUST NOT depend on which surface produced the bytes.

A conformant implementation MUST exercise the α-equivalence corpus (`core/semantos-sir/__tests__/equivalence.test.ts`) on every release.

---

## 8. The 2-PDA cell engine

### 8.1 Architecture

The cell engine is a deterministic, bounded two-stack pushdown automaton (2-PDA):

- Main stack: 1024 cells.
- Auxiliary stack: 256 cells.
- No loops, no jumps, no garbage collection.
- Execution time MUST be proportional to opcount.
- Bounded by `opcountLimit` (configurable; default 1 000 000 opcodes per script).

The reference implementation is approximately 4 900 lines of Zig compiled to WebAssembly. Two profiles:

| Profile  | Size    | Crypto                                          | Use                                |
|----------|---------|------------------------------------------------|------------------------------------|
| Full     | ~185 KB | Native (SHA-256, RIPEMD-160, secp256k1)        | Standalone server, CLI            |
| Embedded | ~29 KB  | Host-provided via WASM imports                 | Browser apps with their own crypto |

Both profiles MUST execute byte-identical opcode programs and produce byte-identical results. The only difference between profiles is the source of cryptographic primitives.

### 8.2 Plexus opcode range (`0x4C`–`0xD0`)

The cell engine extends standard Bitcoin Script (`0x00`–`0x4B`) with the Plexus extension range (`0x4C`–`0xD0`). The full range is documented in `core/cell-engine/src/opcodes.zig` (canonical) and rendered to `docs/canon/opcodes.yml`.

Key opcodes (the Plexus subrange `0xC0`–`0xCF`):

| Opcode | Mnemonic                | Behaviour                                                                  |
|--------|-------------------------|-----------------------------------------------------------------------------|
| `0xC0` | `OP_CHECKLINEARTYPE`    | Pop type tag from stack; verify object linearity matches.                   |
| `0xC1` | `OP_CHECKAFFINETYPE`    | Assert top-of-stack object is AFFINE.                                       |
| `0xC2` | `OP_CHECKRELEVANTTYPE`  | Assert top-of-stack object is RELEVANT.                                     |
| `0xC3` | `OP_CHECKCAPABILITY`    | Verify capability token UTXO is unspent via BUMP proof in Cell 1.           |
| `0xC4` | `OP_CHECKIDENTITY`      | Verify BRC-52 cert binding against participant graph.                       |
| `0xC5` | `OP_ASSERTLINEAR`       | Assert object is unconsumed LINEAR; abort if already consumed.              |
| `0xC6` | `OP_CHECKDOMAINFLAG`    | Read bytes 24–27 of cell header as uint32; compare against expected.        |
| `0xC7` | `OP_VERIFYVERSION`      | Assert object state version hash matches expected (`prevStateHash` chain).  |
| `0xC8` | `OP_CHECKDOMAIN`        | Verify domain flag is within authorised range for current context.          |
| `0xC9` | `OP_ASSERTPHASE`        | Assert pipeline phase matches expected (`source`, `parse`, `ast`, …).        |
| `0xCA` | `OP_CHECKCELL`          | Validate continuation cell header: type tag, index, payload size bounds.    |
| `0xCB` | `OP_VERIFYBUMP`         | Delegate BUMP verification to host: parse BRC-74, compute merkle root.      |
| `0xCC` | `OP_VERIFYBEEF`         | Delegate atomic-BEEF verification: validate `0x01010101` prefix + ancestry. |
| `0xCD`–`0xCF` | reserved          | Reserved for future Plexus extensions.                                      |

The Protocol Spec v0.01 documented this range as `0xC0`–`0xCF`; the broader Plexus extension range is `0x4C`–`0xD0` per the current implementation. Implementations MUST follow `core/cell-engine/src/opcodes.zig` and `docs/canon/opcodes.yml` as authoritative.

### 8.3 WASM interface contract

The Zig/WASM module MUST export at least the following functions:

| Function                                        | Purpose                                       |
|-------------------------------------------------|-----------------------------------------------|
| `validateCell(cellPtr, cellLen)`                | Pre-validate a cell against header invariants  |
| `executeScript(scriptPtr, scriptLen, stackPtr)` | Execute opcode bytes against the stack         |
| `verifyStateChain(chainPtr, chainLen)`          | Validate `prevStateHash` chain integrity      |
| `checkLinearity(objectPtr, operation)`          | Enforce K1 at the gate                        |
| `kernel_init()`                                 | Initialise kernel state                       |
| `kernel_load_script(scriptPtr, scriptLen)`      | Load a script for execution                   |
| `kernel_execute()`                              | Execute the loaded script                     |
| `kernel_set_enforcement(enabled)`               | Enable/disable invariant enforcement          |

The host MUST provide at least the following imports:

| Import                                                 | Purpose                                     |
|--------------------------------------------------------|---------------------------------------------|
| `hostSha256(dataPtr, dataLen, outPtr)`                 | SHA-256 hash                                |
| `hostHmacSha256(keyPtr, keyLen, dataPtr, dataLen, outPtr)` | HMAC-SHA-256                            |
| `hostVerifySignature(pubkeyPtr, msgPtr, sigPtr)`       | ECDSA verify                                |
| `hostCheckBump(bumpPtr, bumpLen, txidPtr)`             | BUMP merkle proof verification              |

This separation ensures the kernel never touches private keys or network I/O directly. All cryptographic operations are delegated to the host, which uses `@bsv/sdk` internally in the reference implementation.

### 8.4 Three-phase verification pipeline

When the 2-PDA evaluates a multi-cell object, continuation cells are popped from the auxiliary stack in LIFO order, yielding three verification phases:

**Phase 1 (BUMP).** Is the anchor transaction mined? The kernel MUST call `hostCheckBump` with the BRC-74 merkle path from Cell 1. If the merkle root does not match the block header, execution MUST halt immediately (fail-fast). This prevents wasting computation on objects with invalid anchors.

**Phase 2 (atomic-BEEF).** Is the transaction ancestry valid? The kernel MUST delegate BRC-95 atomic-BEEF validation to the host, which recursively verifies the full transaction graph using the `@bsv/sdk` BEEF parser.

**Phase 3 (state envelope).** Which semantic states are under this merkle root? The kernel MUST deserialise the custom envelope format and verify selective disclosure proofs against the inscribed root. Only then does payload evaluation begin.

Failure at any phase MUST result in execution halt with the failed phase number reported.

### 8.5 Profiles

The full and embedded profiles MUST execute byte-identical opcode programs against byte-identical inputs and produce byte-identical outputs. Implementations MAY build either profile from the same source under different compile-time flags; the production WASM MUST be built with `embedded = true` to strip debug code paths.

---

## 9. Kernel invariants

### 9.1 Execution invariants (K1–K5)

A conformant cell engine MUST enforce the following invariants. Each invariant has a corresponding Lean 4 mechanised proof (in `proofs/lean/Semantos/Theorems/`).

| ID | Invariant                                                                     | Proof                          |
|----|-------------------------------------------------------------------------------|---------------------------------|
| K1 | A LINEAR cell is consumed exactly once; never duplicated, never discarded     | `LinearityK1.lean`              |
| K2 | Any state-changing transition requires successful identity verification       | `AuthSoundnessK2.lean`          |
| K3 | `OP_CHECKDOMAINFLAG` is total and correct                                     | `DomainIsolationK3.lean`        |
| K4 | Failed Plexus opcodes leave the PDA state byte-for-byte unchanged             | `FailureAtomicK4.lean`          |
| K5 | Every execution terminates within `opcountLimit` steps                        | `TerminationK5.lean`            |

### 9.2 Object integrity (K7)

| ID | Invariant                                                                     | Proof                          |
|----|-------------------------------------------------------------------------------|---------------------------------|
| K7 | The 256-byte cell header is read-only after packing                           | `CellImmutabilityK7.lean`       |

No opcode in the instruction set modifies the linearity class, type hash, owner ID, or hash-chain pointers of a cell on the stack.

### 9.3 Additional invariants (K8, K9, K10)

| ID  | Invariant                                                                    | Proof                          |
|-----|------------------------------------------------------------------------------|---------------------------------|
| K8  | AFFINE → RELEVANT promotion preserves consumability                          | `DemotionK8.lean` (+ TLA+)      |
| K9  | Hash chains compose under projection (temporal morphism)                     | `TemporalMorphismK9.lean`       |
| K10 | 2-PDA + bounded opcount yields a decidable execution model                   | `TuringCompletenessK10.lean`    |

### 9.4 Distributed invariants (K6 + protocol properties)

| ID           | Invariant                                                                | Method                       |
|--------------|--------------------------------------------------------------------------|------------------------------|
| K6           | Hash-chain integrity: `prevStateHash` chain is append-only               | TLA+ model check (bounded)   |
| Replay imp.  | Once a LINEAR cell is consumed, no future action can re-consume it       | TLA+ (`ReplayPrevention.tla`)|
| Revocation   | Once a cert is revoked, no future signature with it succeeds             | TLA+ (`CertRevocation.tla`)  |
| Partition    | Local cert cache permits validation under network partition              | TLA+ (`PartitionResilience.tla`) |
| Metering FSM | The 8-state MFP FSM admits no invalid transitions                        | TLA+ (`MeteringFSM.tla`)     |
| Zone bound.  | Domain-flag isolation holds under interleavings                          | TLA+ (`ZoneBoundary.tla`)    |

### 9.5 Verifier Sidecar

The Verifier Sidecar is the runtime gate that turns BRC-100, BRC-52 cert authenticity, identity binding, and capability UTXO SPV checks into a single chokepoint at every adapter boundary. A conformant deployment MUST run a Verifier Sidecar in one of three topologies:

| Topology                  | Pros                                          | Cons                                              |
|---------------------------|-----------------------------------------------|---------------------------------------------------|
| Per-surface in-process    | Lowest latency; trivial to deploy             | Couples sidecar to each adapter's release cycle   |
| Per-node sidecar process  | Independent deployment; moderate latency      | One additional process per node                   |
| Edge gateway              | Operationally cleanest; single audit point    | Single chokepoint; adds network hop               |

**Recommended default: per-node sidecar process** (per Unification Roadmap §8 Q3). The per-surface in-process option SHOULD be used for tightly-coupled pairs (cell engine + World Host on the same node). The edge-gateway topology MAY be used for centralised deployments where audit is paramount.

---

## 10. On-chain anchoring

### 10.1 Anchor request lifecycle

Anchor requests follow a finite-state machine: `pending` → `broadcasting` → `anchored | failed`.

1. **Request.** Application creates an anchor request with state hash, object reference, and priority.
2. **Construct.** Anchor service builds an atomic-BEEF transaction (BRC-95) with an `OP_RETURN` output containing the state merkle root.
3. **Broadcast.** Transaction is submitted to BSV via ARC.
4. **Confirm.** On block inclusion, request is updated with `txId`, `vout`, merkle root. Object's `anchorStatus` is set to `0x02` (anchored).

The `OP_RETURN` output MUST be immutable once broadcast. If correction is needed, a new anchor transaction MUST be created with an updated state chain pointing to the corrected state.

### 10.2 BUMP merkle proof

The BUMP (BSV Unified Merkle Path, BRC-74) proof MUST be carried in continuation cell type `0x01`. The proof MUST contain sufficient sibling hashes to recompute the merkle root from the anchored leaf.

### 10.3 BEEF transaction envelope

The atomic-BEEF envelope (BRC-95) MUST be carried in continuation cell type `0x02`. The envelope MUST start with the prefix `0x01010101` followed by the subject `txId` followed by the BRC-62 BEEF body for recursive ancestor validation.

### 10.4 State merkle envelope

Rather than inscribing N state hashes on-chain, Semantos inscribes one merkle root computed over the state hash chain. The merkle envelope (continuation cell type `0x03`) maps individual state hashes to that root via selective disclosure proofs.

Envelope wire format:

```
[1 byte: version] [4 bytes: leafCount LE] [32 bytes: merkle root]
[4 bytes: proofCount LE]
Per proof: [4 bytes: leafIndex LE] [32 bytes: leafHash]
           [4 bytes: siblingCount LE]
           Per sibling: [1 byte: position (0=left, 1=right)] [32 bytes: hash]
```

Internal nodes use double-SHA-256 (Bitcoin convention). Odd leaf counts are padded by duplicating the last leaf.

---

## 11. Metered Flow Protocol

### 11.1 Channel lifecycle (8-state FSM)

MFP channels use `nSequence`-based state progression. Each `nSequence` increment represents a new channel state; miners accept the transaction with the highest `nSequence`. The uint32 `nSequence` field allows approximately 4.3 billion state updates per input.

The 8-state FSM:

| From                | To                  | Trigger                              |
|---------------------|---------------------|--------------------------------------|
| NEGOTIATING         | FUNDED              | Both parties sign funding tx          |
| FUNDED              | ACTIVE              | Funding tx confirmed on-chain         |
| ACTIVE              | PAUSED              | Either party requests pause           |
| PAUSED              | ACTIVE              | Both parties agree to resume          |
| ACTIVE              | CLOSING_REQUESTED   | Either party initiates close          |
| PAUSED              | CLOSING_REQUESTED   | Either party initiates close          |
| CLOSING_REQUESTED   | CLOSING_CONFIRMED   | Counterparty acknowledges close       |
| CLOSING_CONFIRMED   | SETTLED             | Settlement tx broadcast and confirmed |
| (any)               | DISPUTED            | Fraud detected (stale `nSequence`)    |

Invalid transitions MUST be rejected by the state machine. Each transition MUST be atomic and idempotent.

### 11.2 Tick proof format

Each metering tick MUST produce a cryptographic proof of resource consumption:

```
{
  tick:               uint32,
  hmac:               bytes(32),
  timestamp:          uint64,
  cumulativeSatoshis: uint64
}
```

where `hmac = HMAC-SHA-256(key=channel_shared_secret, message=tick||cumulativeSatoshis||timestamp)`.

Tick proofs MUST be dual-signed (both parties) before settlement. The HMAC provides non-repudiation. Verification MUST use constant-time comparison.

### 11.3 Settlement via `nSequence`

Settlement uses Bitcoin's original `nSequence` mechanism for payment-channel state updates:

- Each tick increments `nSequence` on the spending input.
- Either party MAY broadcast the settlement transaction at any time.
- The transaction spends the 2-of-2 multisig funding output.
- Outputs: one to recipient (`cumulativeSatoshis`), one to sender (remaining balance).
- Miners accept the transaction with the highest `nSequence`, so only the most recent state settles.

Dispute resolution: if a party broadcasts a transaction with a stale (lower) `nSequence`, the counterparty broadcasts the latest tick's transaction with the higher `nSequence`. Since miners prefer higher `nSequence`, only the most recent state settles. This is the original Satoshi payment-channel design.

---

## 12. Mesh transport

### 12.1 SignedBundle envelope

Every cross-process or cross-node message MUST be wrapped in a `SignedBundle<T>` envelope, encoded as CBOR. The envelope MUST carry:

| Header                          | Type        | Description                                |
|---------------------------------|-------------|--------------------------------------------|
| `x-brc100-identitykey`          | bytes(33)   | Sender's compressed secp256k1 pubkey       |
| `x-brc100-nonce`                | bytes(32)   | Anti-replay nonce                          |
| `x-brc100-timestamp`            | uint64      | Milliseconds since epoch                   |
| `x-brc100-signature`            | bytes(64+)  | ECDSA over canonical preimage              |
| `x-brc52-certificate`           | bytes       | Sender's BRC-52 cert (or cert reference)   |
| `payload`                       | T (CBOR)    | Vertical-specific payload                  |

The Verifier Sidecar (§9.5) MUST verify every header before the payload is processed. JSON fallback MAY be used where CBOR is impractical, but the canonical wire format is CBOR.

### 12.2 IPv6 multicast

The default mesh transport is IPv6 multicast. Peers join groups derived from topic identifiers via a `topicToGroup` hook. The default mapping is `() => 'ff02::1'` (one group, software demux); the Phase 34 mapping derives a distinct group per type hash for transport-level filtering.

The 12-byte adapter header carried on each multicast frame:

| Offset | Size | Field    | Description                                                    |
|--------|------|----------|----------------------------------------------------------------|
| 0      | 1    | Magic    | Frame magic byte                                               |
| 1      | 1    | Version  | Adapter wire version                                           |
| 2      | 1    | MsgType  | 0x01=heartbeat, 0x02=cell, 0x03=control, 0x04=world_frame      |
| 3      | 1    | Reserved | Zero                                                           |
| 4      | 8    | Nonce    | 8-byte randomness                                              |

A maximum payload size MUST be enforced; oversized publishes MUST reject with `PayloadTooLargeError` rather than silently dropping. The default limit is 65 507 - HEADER_SIZE bytes (UDP datagram limit minus header); compact-network-adapter implementations for non-IP transports MUST enforce their own MTU.

### 12.3 Six-piece session skeleton

Above the transport, the substrate provides a domain-neutral session skeleton implemented in `runtime/session-protocol/`. The six pieces:

| Piece               | Role                                                              |
|---------------------|-------------------------------------------------------------------|
| Discovery           | Peer discovery via heartbeats; BCA → endpoint resolution           |
| Formation           | Multi-party session formation (proposal, acceptance, FormationPolicy) |
| Runtime             | Per-session state-machine driver; consumes a `StateMachine<E,S>`   |
| Broadcast           | Multi-recipient publish; fan-out via mesh                          |
| Transport           | NetworkAdapter abstraction (multicast, WSS, etc.)                  |
| Metering Hook       | Optional MFP integration; ticks emitted on FSM transitions         |

The only domain-specific piece a vertical must contribute is its `StateMachine<Event, State>` implementation. Verticals supplied today: poker (reference), CDM lifecycle, SCADA event flow, World Host region authority.

---

## 13. Security considerations

### 13.1 Zero-knowledge property

The server MUST NOT hold private keys at any time. All key derivation and reconstruction MUST be client-side. Recovery metadata MUST be cryptographically useless without the root secret (challenge answers). An attacker with full server access MUST NOT be able to impersonate a user, derive their keys, or decrypt their data.

### 13.2 Monotonic guarantees

Child indices, rotation indices, and state versions MUST be strictly monotonic. They MUST only increase and MUST never be reused. This prevents rollback attacks on the derivation path or state chain. Any attempt to use a previous `childIndex` or `stateVersion` MUST be rejected as a cryptographic-integrity violation.

### 13.3 Constant-time operations

All secret-comparison operations (challenge answers, HMAC verification, signature validation) MUST use constant-time comparison to prevent timing attacks. The 2-PDA cell engine MUST delegate all comparisons to host imports that guarantee constant-time behaviour.

### 13.4 Brute-force mitigation

See §6.5. In addition: rate limits SHOULD apply on context enrollment, edge creation, and capability-token mint requests to prevent enumeration.

### 13.5 Kernel isolation

The Zig/WASM cell engine MUST run in a sandboxed WASM environment with no direct access to the filesystem, network, or private keys. All I/O MUST cross the WASM FFI boundary via explicitly typed host imports. The kernel MUST NOT make network requests, read files, or access memory outside its linear memory space. This containment ensures that even a compromised kernel module cannot exfiltrate data.

The production WASM binary's SHA-256 hash MUST be anchored on BSV at release time. Devices MUST verify `SHA-256(loaded_wasm) == anchored_hash` at boot, before the engine initialises. A hash mismatch MUST refuse to load and SHOULD alert operators (per the Compliance Demonstration Test 6.2).

### 13.6 Honest assumption register

The verification posture rests on a small, explicit set of assumptions. Implementations and audits MUST acknowledge these:

- **Cryptographic primitives** (SHA-256, ECDSA over secp256k1, HMAC-SHA-256) are axiomatised as ideal functions in the Lean model under standard computational assumptions.
- **Hardware correctness**: assumes the CPU correctly executes WASM instructions.
- **Host imports**: the WASM kernel imports `host_*` functions from a TS host; the host is not formally verified.
- **Side channels**: timing attacks, power analysis, cache attacks, etc. are not modelled.
- **BSV chain availability**: the on-chain anchoring story depends on chain availability for verification.
- **Trusted boot**: the binary-integrity claim depends on the loader correctly verifying the anchored hash.
- **Application-layer correctness**: certain compliance properties depend on the application correctly routing operations through the kernel.

These assumptions are not weaknesses; they are explicit boundary conditions that make the verification posture honest.

---

## 14. References

### 14.1 Normative references

- **BRC-42**: BSV Key Derivation Scheme (BKDS).
- **BRC-43**: Security Levels, Protocol IDs, Key IDs, and Counterparties.
- **BRC-52**: Identity Certificates.
- **BRC-53**: Certificate Creation and Revelation.
- **BRC-62**: Background Evaluation Extended Format (BEEF).
- **BRC-69**: Revealing Key Linkages.
- **BRC-74**: BSV Unified Merkle Path (BUMP).
- **BRC-85**: Proven Identity Key Exchange (PIKE).
- **BRC-94**: Verifiable Revelation of Shared Secrets via Schnorr.
- **BRC-95**: Atomic BEEF Transactions.
- **BRC-100**: Wallet-to-Application Interface.
- **BRC-103**: Peer-to-Peer Mutual Authentication and Certificate Exchange.
- **BRC-108**: Identity-Linked Token Protocol.
- **`@bsv/sdk`**: BSV TypeScript SDK (github.com/bsv-blockchain/ts-sdk).
- **`wallet-toolbox`**: BRC-100 reference implementation.

### 14.2 Informative references

- *Plexus Technical Requirements v1.3* (Dusk Inc, 2026) — protocol-level content absorbed into §4 and §6 of this specification.
- *Plexus Client Requirements v2.1* (Dusk Inc, 2026) — overview of the recovery substrate.
- *Semantos Whitepaper v3* — narrative architecture overview.
- *Semantos: Compression Gradients for Deterministic Semantic Execution* (Paper A1) — the SIR/OIR pipeline as a discipline.
- *Semantos Formal Verification Strategy* (`docs/FORMAL-VERIFICATION-STRATEGY.md`) — the K1–K10 proof posture.
- *Semantos Unification Roadmap* (`docs/prd/SEMANTOS-UNIFICATION-ROADMAP.md`) — the integration matrix and per-deliverable status.
- *Hohfeld, W. N.* (1913). *Some Fundamental Legal Conceptions as Applied in Judicial Reasoning*. Yale Law Journal — the theoretical source for the seven jural categories adapted in §7.1.

---

## Appendix A — BRC suite reference

| BRC     | Implemented in                                               | Specification §                                       |
|---------|--------------------------------------------------------------|--------------------------------------------------------|
| BRC-42  | `core/plexus-vendor-sdk/src/crypto.ts`; client devices       | §4.1, §4.2, §4.4                                      |
| BRC-43  | `core/protocol-types/src/namespace.ts` (target)              | §4.5, §8.2                                            |
| BRC-52  | `core/plexus-contracts/src/identity.ts`                       | §4.2, §4.4                                            |
| BRC-53  | Plexus Recovery Service                                       | §6.1, §6.2                                            |
| BRC-62  | `core/cell-engine/src/beef.zig`; `@bsv/sdk`                  | §10.3                                                 |
| BRC-69  | Plexus Recovery Service                                       | §4.6, §6.2                                            |
| BRC-74  | `core/cell-engine/src/bump.zig`; `@bsv/sdk`                  | §10.2                                                 |
| BRC-85  | Plexus Identity Service                                       | §4.6                                                  |
| BRC-94  | Plexus attestation flow                                       | §4.6 (informative)                                    |
| BRC-95  | `core/cell-engine/src/beef.zig`                              | §10.3                                                 |
| BRC-100 | `runtime/session-protocol/src/bundle-envelope.ts`             | §12.1                                                 |
| BRC-103 | Plexus recovery + edge enrollment                             | §6.1                                                  |
| BRC-108 | `core/identity-ports/src/types.ts`                            | §5                                                    |

## Appendix B — Canon snapshot

This specification was cut against the canon snapshot dated 2026-04-26 — the post-canonical-decision-pass state in which all 51 glossary entries have a decided canonical alias. Significant terms used in this document and their canon references:

| Term in spec       | Canon `id`            | Notes                                                                  |
|--------------------|-----------------------|-------------------------------------------------------------------------|
| cell               | `cell`                | Primary unit of the cell engine; LoomObject is a wrapper, not synonym  |
| cell engine        | `cell-engine`         | The 2-PDA; "kernel" is overloaded and avoided                           |
| SIR                | `sir`                 | Semantic IR; expand on first use                                        |
| OIR                | `oir`                 | Opcode IR (ANF); expand on first use                                    |
| SignedBundle       | `signed-bundle`       | PascalCase canonical (matches TS type)                                  |
| BCA                | `bca`                 | Initialism canonical                                                    |
| `cert_id`          | `cert-id`             | snake_case canonical (wire format); `certId` is the TS spelling         |
| hat                | `hat`                 | Renamed from `facet`                                                    |
| capability token   | `capability-token`    | `permission` retired for this concept                                   |
| jural category     | `jural-category`      | Seven-category adapted set (declaration, obligation, …)                |
| governance domain  | `trust-domain`        | Renamed from `trust domain` to avoid ambiguity with the `trust` kind   |
| Verifier Sidecar   | `verifier-sidecar`    | Proper noun for the component                                           |
| Helm               | `helm`                | New name; `Loom` retained in code paths                                 |
| MFP                | `mfp`                 | Initialism canonical                                                    |
| World Host         | `world-host`          | Proper noun for the component                                           |
| sovereign node     | `sovereign-node`      | Descriptive canonical                                                   |
| boot sequence      | `boot-sequence`       | Generic canonical (count may change)                                    |

---

*End of Semantos Protocol Specification v0.5.*

*Next revision: increment to v0.6 when (a) the Unification Matrix progresses by a phase that introduces normative protocol changes, or (b) a substantive addition/correction is identified by a conformant implementation. Per `docs/SEMANTOS-DOC-PLAN.md` §4, every cut tags the canon snapshot it pinned to.*
