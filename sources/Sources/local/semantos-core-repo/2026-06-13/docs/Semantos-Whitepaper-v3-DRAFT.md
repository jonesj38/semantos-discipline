---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/Semantos-Whitepaper-v3-DRAFT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.332495+00:00
---

# Semantos
## A Sovereign Node from Voice to Economic Execution

**Technical Whitepaper v3.0 — Draft**
**Todd Price — Founder, Real Blockchain Solutions**
**April 2026**
**todd@realblockchainsolutions.com**

> **Status:** Draft for review. Pin to Unification Matrix snapshot at publication date.
>
> **Note for layout pass:** sections marked `[FIGURE — needs real graphic]` currently render as ASCII / numbered lists / tables. The content is the priority; the rendering is provisional. Six figures in particular deserve real graphics before public release: the boot sequence (§2), the Adapter Matrix (§2.1), the substrate / adapter layered architecture (§3.1), the compression gradient (§3.6), the six-piece session skeleton (§3.9), and the cell wire format reference (Appendix B).

---

## Abstract

DNS resolves names to addresses. Databases record state. Blockchains prove existence. None of them resolve *meaning*. Semantos is a sovereign node — a single deployable substrate that takes voice in, produces cryptographically anchored economic effect out, and proves every step in between. The substrate is one Zig/WASM kernel running across three deployment scales (microcontroller, $5 VPS, federated full node), four pluggable adapter axes (Storage, Identity, Anchor, Network), seven jural categories of meaning, ten machine-checked invariants, and one canonical compression gradient from natural language to opcode bytes. This paper describes the architecture, the boot sequence, the verification posture, and what gets built next.

---

## 0.5 About this work

Semantos is a project of Real Blockchain Solutions, founded by Todd Price (Queensland, Australia). Development began in early 2024 and the substrate has been under continuous engineering since. The repository is a polyglot monorepo (Zig, TypeScript, Elixir, Lean 4, TLA+) of approximately 200,000 lines of code, organised into five mechanically-enforced tiers (`core/`, `runtime/`, `extensions/`, `apps/`, plus formal `proofs/`), with phase-gated tests and a continuous-integration architectural-import gate. The kernel ships as a 29 KB embedded WASM profile and a 185 KB full WASM profile, both under the same source. Identity and recovery substrate (Plexus) is RBS-owned IP implemented to an RBS-authored requirements specification by Dusk Inc.

This whitepaper describes what the substrate provides and what it has been formally proved to guarantee. RBS is the steward of the substrate and provides commercial support and reference deployments; the substrate itself is designed to run on operator-owned hardware under operator-owned identity, with no intrinsic dependency on RBS or any other third party.

---

## 1. The Naming Problem

The infrastructure we rely on every day operates through layers of indirection, each incomplete in critical ways. The systems that connect identity to value have evolved in isolation, leaving gaps that make digital objects ambiguous, counterfeitable, and semantically opaque.

### 1.1 DNS resolves location, not identity

A name like `example.com` tells you where to find a service, not what it is or who owns it. Two DNS records can point to identical addresses and represent entirely different entities with different permissions, governance, and value. DNS has no semantic awareness.

### 1.2 Databases record state, not meaning

A database stores the current state of a record — a customer name, an account balance, an inventory count — but that state is hostage to the application that interprets it. Change the code, change the schema, redeploy the service, and the meaning of that data shifts. An object stored in one system's database may be invisible, meaningless, or misinterpreted by another.

### 1.3 Blockchains prove existence, not type

A blockchain anchors data on-chain, creating an immutable record of what was committed and when. But immutability is not enough. A blob of bytes on a blockchain proves it existed at block height N — it does not prove what it is, who owns it, or whether consuming it is permissible. Semantics remain off-chain, subjective, and unverifiable.

### 1.4 LLMs add a fourth layer of confusion

Voice and natural-language interfaces hold the promise of dramatic productivity gains, but in production they fail by misinterpretation, hallucination, and unauthorised action. The failure mode is structural: language models are asked to jump directly from text to action with no verifiable intermediate forms. There is nothing to inspect, nothing to ratify, nothing the system can refuse. The missing layer is not more clever prompting — it is a substrate that makes execution **operationally boring** even when the input is ambiguous, by forcing the input through a stack of typed transformations that the system can stop at any layer.

### 1.5 The missing layer

The gap across all four is the same: a layer that operates at the level of **meaning** — that resolves a name not to an address, not to an application-specific interpretation, not to a blob of bytes, not to a one-shot LLM guess, but to a **cryptographically-bound, type-enforced, linearly-governed, history-anchored, capability-gated semantic object**. That is the layer Semantos provides.

> The fundamental primitive of the digital economy is not a database record, a token, a blockchain transaction, or an LLM completion. It is a typed semantic object with provable identity, linearity-constrained consumption, a cryptographic evidence chain, and a verifiable lineage from intent to effect.

---

## 2. The Sovereign Node

A sovereign node is a single deployable that takes voice in, produces cryptographically anchored economic effect out, and proves every intervening step. The target M3 installer is one command:

```
curl -fsSL https://get.semantos.sh | sh
```

On a clean Ubuntu 22.04 $5-tier VPS, the M3 acceptance criterion is that this command produces, in ≤5 minutes wall-clock: a running Semantos node, a BRC-100 wallet on disk, a BRC-52 identity certificate, optional DNS publication, and a healthy node URL. The output is the operator's identity key, the node URL, and an admin token. The node is then a sovereign participant on the federated mesh.

Behind that one command is a 15-step boot sequence that runs every primitive in the system end-to-end. The sequence is the unification claim made concrete — when it runs without error, the substrate is real.

> **Figure 1 — The boot sequence.** *[FIGURE — needs real graphic for layout pass; current rendering is provisional.]*

```
 1. User provides email + answers identity challenges
 2. PBKDF2 100,000 iterations on device → root seed             (client-only)
 3. Derive BRC-52 cert from root seed → cert_id                 (client-only)
 4. BCA(cert_id) computed via shared BCA library                (deterministic)
 5. Vendor SDK initialises tenant_nodes locally
 6. Capability Domain mints initial UTXOs
 7. Cell engine boots, kernel_set_enforcement(1)
 8. Verifier Sidecar starts (per topology decision)
 9. World Host (if needed) starts authoritative regions
10. Mesh adapter joins multicast group derived from cert_id
11. UI server (helm) binds localhost
12. Adapters subscribe to:
       — region tick deltas        (transport + time compose)
       — Plexus identity events    (cross-surface change feed)
       — capability UTXO changes   (auth state)
13. Recovery payload backed up to Plexus Recovery service
14. Metered services open MFP cashlanes
15. User is online, sovereign, federated
```

Steps 1–7 currently run end-to-end in production form. Steps 8 onward run in feasibility but not yet under proper BRC enforcement across every adapter. Closing that gap is a measurable engineering programme tracked in the **Unification Roadmap** (§7); the substrate is *architecturally complete*, the work that remains is *integrative*.

The sovereign node has no intrinsic dependency on any company, network, or third-party service. It runs on the operator's hardware, signs with the operator's keys, persists to the operator's storage, and federates over a transport the operator chooses. The substrate is sovereign by construction.

### 2.1 The Adapter Matrix

The same kernel runs at three deployment scales. At each scale, four pluggable adapter axes determine how the node interacts with the world.

> **Figure 2 — The Adapter Matrix.** *[FIGURE — needs real graphic for layout pass; the table below is the canonical content.]*

| Adapter      | IoT (esp32-class)            | Edge / VPS (self-hosted)                       | Federated full node              |
|--------------|------------------------------|-------------------------------------------------|----------------------------------|
| **Storage**  | USB, SD, LittleFS, PSRAM     | Local FS, MinIO, UHRP host (self-hosted)        | UHRP cluster, federated          |
| **Identity** | Flash cert, BLE-provisioned  | `wallet-toolbox` BRC-100 on disk                | HSM, per-tenant issuance         |
| **Anchor**   | LoRa, ESP-NOW, gateway POST  | Direct BSV node, bundled miner gateway          | Own mining / overlay relay       |
| **Network**  | MQTT, ESP-NOW, BLE, mDNS     | MessageBox WSS via `ws-node-adapter`            | Federated peer registry, BRC-56  |

The same Zig/WASM kernel binary (29 KB embedded profile, 185 KB full profile) runs across all three columns. The only thing that changes is the adapter set. There is no edge / cloud duality at the protocol layer — there is one substrate, three deployment scales, four adapter axes, and a finite set of choices per cell.

### A worked scenario, threaded through this paper

To make every section concrete, one scenario will recur. A renter's avatar inside a shared 3D space — a World Host Region — speaks: *"there's a leak under the kitchen sink, photos taking now."* The system extracts the intent, types it as a maintenance Obligation, gates it through a property-management lexicon, dispatches an envelope to a registered tradie's flat 2D inbox, the tradie books a visit, the work is done, and payment settles on-chain via the Metered Flow Protocol. Voice in, economic effect out, every step proved.

By the end of this paper the reader has seen which substrate component does what at each boundary in that scenario.

---

## 3. The Substrate

Semantos is not a single program. It is a substrate of ten components whose job is to implement the unification axes, plus a set of adapters that consume them. The components are designed to cohere — every component speaks the same envelope, references the same identity model, anchors to the same hash chain, and produces the same evidence shape.

### 3.1 The substrate at a glance

> **Figure 3 — Substrate / adapter layered architecture.** *[FIGURE — needs real graphic for layout pass; the list below is the canonical content.]*

Ten substrate components, each implementing one or more unification axes:

| # | Component | What it provides |
|---|-----------|------------------|
| U1 | **Cell Engine** (Zig/WASM) | 2-PDA execution, cell packing, K1/K3/K4/K5/K7 enforcement |
| U2 | **Plexus Core / Vendor SDK** | Identity, recovery substrate, BRC-100 control plane |
| U3 | **Identity / Derivation / Recovery** | BRC-42 BKDS keys, BRC-52 certs, monotonic indices |
| U4 | **Capability Domain** | LINEAR BRC-108 UTXO capabilities, mint and revoke |
| U5 | **Verifier Sidecar** | BRC-100 enforcement, BRC-52 cert authenticity, SPV checks |
| U6 | **Mesh** | IPv6 multicast over `SignedBundle`, BCA peer ID, heartbeats |
| U7 | **VFS / Octaves** | Content-addressed storage, hash-chained patches |
| U8 | **SIR + Lexicons** | Jural categories, governance context, lexicon-domain types |
| U9 | **Lean Proof Layer** | Mechanised K1–K10 + lexicon substrate proofs |
| U10 | **Metering Engine (MFP)** | 8-state channel FSM, tick proofs, settlement |

The substrate is held to mechanically-enforced architectural-import rules: `core/` may import nothing outside `core/`; `runtime/` may import `core/` + `runtime/`; `extensions/` may import `core/` + `runtime/` + `extensions/`; `apps/` may import everything except another app. The full set of tier rules and import gate is enforced in continuous integration (`tests/gates/import-boundaries.test.ts`) and described in Appendix B.

The remainder of §3 is a depth tour for the technical reader. The skim-reader can jump to §4 (the worked scenario) and return here as needed.

### 3.2 The Cell Engine

The execution heart of the substrate is a deterministic, bounded **two-stack pushdown automaton** (2-PDA), implemented in Zig (~4,900 LOC) and compiled to WebAssembly. Two stacks: a 1024-cell main stack and a 256-cell auxiliary stack. No loops, no jumps, no garbage collection. Execution time is proportional to opcount.

The instruction set is standard Bitcoin Script extended with a Plexus opcode range (`0xC0`–`0xCF`) that adds VM-level type enforcement: linearity checks, capability checks, identity binding, domain-flag isolation, version assertions, and SPV-delegation primitives. The full opcode reference is in **Appendix B**.

The engine ships in two profiles. The **full profile** (185 KB) embeds native crypto (SHA-256, RIPEMD-160, secp256k1) for standalone server and CLI use. The **embedded profile** (29 KB) imports crypto from the host, enabling browser deployments, embedded firmware, and any environment where the host has its own crypto stack. Thirteen WASM exports cover kernel ops, debug helpers, cell packing, BCA validation, SPV verification, and capability checks. Nine host imports cover crypto.

Every datum the engine touches is a **cell** — a fixed-size 1024-byte structure with a 256-byte typed header. Header offsets carry the magic bytes, the linearity class (LINEAR, AFFINE, or RELEVANT), the version, the type hash (`SHA256(whatPath:howSlug:instPath)`), the owner identifier, the timestamp, the cell count, the payload size, the pipeline phase, and the hash chain pointers (`parentHash`, `prevStateHash`). Continuation cells carry an 8-byte header followed by 1016 bytes of cell-type-specific payload. The full wire format reference is in Appendix B. No opcode in the instruction set modifies the linearity class of a cell on the stack (invariant K7).

### 3.3 Linearity as an Economic Constraint

Every cell carries a **linearity class** that determines its consumption rules. Linearity is not a database hint; it is enforced by the kernel at the gate (invariant K1). The proof that a LINEAR cell has been consumed is non-repudiable.

| Class         | Rule                                                                            | Examples                                                     |
|---------------|---------------------------------------------------------------------------------|---------------------------------------------------------------|
| **LINEAR**    | Consumed exactly once. Cannot be reused, double-spent, or replicated.            | Voting ballots, capability tokens, payment-channel states     |
| **AFFINE**    | Used multiple times but must be acknowledged or revoked in full.                 | Drug-product recalls, certificate revocation, draft documents |
| **RELEVANT**  | No consumption constraint. Read, referenced, validated unbounded times.          | Educational credentials, public records, licences             |

Linearity makes substructural economics enforceable at bytecode. A capability token in Semantos is a LINEAR semantic resource: spending the token is its consumption. There is no application-layer revocation list because there is no need for one.

### 3.4 Plexus — The Identity Substrate

Identity in Semantos is a Plexus directed acyclic graph of cryptographic certificates. The root key is generated client-side via PBKDF2 (100,000 iterations) over the user's challenge answers and never leaves the device. All keys derive from the root via BRC-42's deterministic key derivation; certificates are BRC-52; signed requests follow BRC-100; merkle proofs follow BRC-74 (BUMP) and BRC-62 (BEEF) with BRC-95 atomic-BEEF semantics where applicable.

Plexus contributes four properties to every sovereign node:

1. **Disaster recovery.** No identity or relationship is permanently lost. The Plexus recovery payload (~3.4 KB compressed) holds the deterministic metadata required to reconstruct any key; the server never holds, computes, or transmits raw private keys.
2. **Zero-knowledge security.** Server holds challenge hashes and recovery metadata only. Reconstruction is mathematically impossible without the user's challenge answers.
3. **Canonical identity registry.** A versioned, isolated registry of an identity's derivation state across functional domains and hierarchical contexts within the DAG. Domain flag namespaces are partitioned: `0x00000001`–`0x000000FF` is reserved (Plexus well-known), `0x00000100`–`0x0000FFFF` is extended, `0x00010000`–`0xFFFFFFFF` is the operator's sovereign space.
4. **Attestation authority.** Plexus proves an identity's validity and continuity to third parties without dedicated attestation infrastructure — a natural byproduct of the continuous derivation state.

Recovery comes in two shapes. **Standard recovery** uses the four-phase protocol (email OTP, challenge-response, metadata export, client-side reconstruction). **Threshold recovery** uses Shamir Secret Sharing (t-of-n) for high-security roots and high-value capabilities — the system cryptographically guarantees the operator's local device executes the threshold reassembly, never the server.

### 3.5 Capability Tokens

Authority in Semantos is gated by capability tokens — BRC-108 identity-linked tokens implemented as BSV UTXOs whose locking scripts encode the constraint structure (expiry, geo bounds, max invocations, required domain flags). A capability is a LINEAR semantic resource: spending the UTXO IS the consumption proof. Issuer-side revocation is a force-spend from the issuer's side; instant and on-chain.

SPV verification of a capability token uses BUMP for transaction inclusion and atomic-BEEF for ancestry. Determining whether a token has been *consumed* requires either a UTXO-set query, an application-layer liveness protocol, or a watchman pattern — implementations must not claim SPV alone proves a token is unspent.

### 3.6 The Compression Gradient and the Two-IR Pipeline

Surface input — natural language, voice, a UI button, a shell command, an inbound network frame — does not reach the kernel directly. It passes through a **compression gradient**: a stack of typed transformations, each layer reducing entropy and increasing determinism.

> **Figure 4 — The compression gradient.** *[FIGURE — needs real graphic for layout pass; the diagram below is the canonical content.]*

```
Surface grammar  (Lisp ✓; LaTeX, Lean-ish, Ricardian, EDI in design)
       │
       ▼
Semantic IR (SIR)        ← jural category, taxonomy, identity, governance
       │  lowerSIR()      (rejects malformed claims structurally)
       ▼
Opcode IR (OIR, ANF)     ← named bindings, explicit data flow, predicates
       │  emit()
       ▼
Opcode bytes (0x4C–0xD0)
       │
       ▼
Cell engine (Zig/WASM 2-PDA)
       │
       ▼
Economic effect          (cell signed, anchored, side effect produced)
```

Each layer compresses the previous and adds something new. SIR carries the meaning; OIR carries the mechanism. The same intent expressed in two surface grammars (Lisp and LaTeX, say) should produce OIR programs that are α-equivalent — that equivalence is what makes "semantic compression" a verifiable claim rather than a marketing line, and what makes paid extension grammars commercially viable: every grammar lowers into the same OIR; the kernel doesn't care which surface produced it.

A small example. The policy *"any party with the SIGNING capability for protocol 0x02 may perform this action"* compresses across the gradient:

| Stage | Approx. size | Form |
|---|---|---|
| Natural language | ~14 words | "any party with the SIGNING capability for protocol 0x02 …" |
| Lisp surface     | 3 forms   | `(check-cap SIGNING 0x02)` |
| OIR (ANF)        | 1 binding | `$0 := check-cap(SIGNING, 0x02)` |
| Opcode bytes     | 4 bytes   | `0xC3 0x01 0x02` |

The dramatic compression at the bottom is what makes the kernel small. The dramatic compression at the top is what makes domain-specific grammars feasible without forking the kernel.

### 3.7 The Seven Jural Categories

The semantic IR is grounded in **Hohfeldian jural analysis** — the standard 1913 decomposition of legal relations adapted for computational governance. Every meaningful expression in the system reduces to one of seven categories:

| Category        | What it expresses                                   | Default linearity | Examples                                                         |
|-----------------|------------------------------------------------------|--------------------|------------------------------------------------------------------|
| **Declaration** | Assertion of fact or state                           | RELEVANT           | sensor reading, attestation, regulatory report                   |
| **Obligation**  | Duty that must be fulfilled                          | LINEAR             | margin call, alarm acknowledgement, payment due                  |
| **Permission**  | Authorisation to act                                 | RELEVANT           | capability grant, operator shift token                           |
| **Prohibition** | Constraint that an action must NOT occur             | RELEVANT           | interlock policy, safety constraint, denylist                    |
| **Power**       | Authority to change legal or economic relations      | varies             | publish, novate, govern, vote                                    |
| **Condition**   | Temporal or state-dependent trigger                  | AFFINE             | time-after, deadline, vesting condition                          |
| **Transfer**    | Movement of value, rights, or obligations            | LINEAR             | settlement, conveyance, capability handoff, shift handover       |

The seven categories are not arbitrary; they are the minimum set sufficient to distinguish every act the system performs. A CDM novation and a SCADA alarm acknowledgement are both exercises of *power*, but the SIR makes the difference structural — one is a transfer-power over financial obligations, the other is a consume-power over a safety event. The OIR cannot make this distinction. The SIR can, and must, before any opcode bytes are emitted.

Trust-tier enforcement happens at the SIR-to-OIR boundary. A node claiming `authoritative` trust without a `formal` proof requirement is rejected at the IR level — not at runtime, not at the governance plane, *at compile time*. This is defence-in-depth: governance-plane checks remain in place; the IR refuses to lower invalid claims to bytes.

### 3.8 The Verifier Sidecar

Static IR-level enforcement is necessary but not sufficient. A second component — the **Verifier Sidecar** — enforces the runtime gate: BRC-100 signature checks, BRC-52 cert authenticity, identity-binding (the signing key matches `certificate.subject`), and SPV checks for capability UTXOs. Three deployment topologies are supported: per-surface in-process (cheapest, hardest to update), per-node sidecar process (the recommended default), and edge gateway (operationally cleanest, single chokepoint).

The Sidecar is load-bearing for three of the unification axes simultaneously (Identity, Transport, Capability). Without it, the boot sequence stops at step 8.

### 3.9 The Mesh and the Six-Piece Skeleton

Cross-process and cross-node messages travel as `SignedBundle<T>` envelopes — a CBOR shape carrying a BRC-100 signed request with the sender's BRC-52 cert reference. On the wire, the multicast adapter joins one IPv6 group per topic, with topic-derivation pluggable per Phase 34 (default behaviour: one group, software demux).

Above the transport, the substrate provides a **six-piece domain-neutral session skeleton**:

> **Figure 5 — The six-piece session skeleton.** *[FIGURE — needs real graphic for layout pass; the diagram below is the canonical content.]*

```
┌───────────────────────────────────────────────────────────┐
│   Session Consumer (poker, CDM, SCADA, world, …)          │
│   ┌─────────────────────────────────────────────────────┐ │
│   │ Domain StateMachine (the only vertical-specific     │ │
│   │ piece — implements StateMachine<Event, State>)      │ │
│   └─────────────────────────────────────────────────────┘ │
└───────────────────────────▲───────────────────────────────┘
                            │
┌───────────────────────────┴───────────────────────────────┐
│   session-protocol package (substrate)                    │
│   ┌──────────┬──────────┬──────────┬─────────────────┐   │
│   │ Discovery│ Formation│ Runtime  │ Broadcast Engine│   │
│   ├──────────┼──────────┼──────────┴─────────────────┤   │
│   │Transport │ Metering │                              │   │
│   │(via      │ Hook     │                              │   │
│   │interface)│(optional)│                              │   │
│   └──────────┴──────────┴──────────────────────────────┘   │
└───────────────────────────▲───────────────────────────────┘
                            │ NetworkAdapter interface
┌───────────────────────────┴───────────────────────────────┐
│   Adapter implementations (substrate-specific)            │
│   ┌──────────┬──────────┬──────────┬────────────────┐   │
│   │ Multicast│ WebSocket│ WebRTC   │ 6LoWPAN /      │   │
│   │ Adapter  │ Node     │ Adapter  │ Compact        │   │
│   │          │ Adapter  │          │ Adapter        │   │
│   └──────────┴──────────┴──────────┴────────────────┘   │
└───────────────────────────────────────────────────────────┘
```

The frame is: **every vertical is a state machine over a shared session skeleton.** Poker is one consumer. CDM lifecycle is another. SCADA event flow is another. Calls, auctions, oracles — each vertical contributes its `StateMachine<Event, State>` and inherits the rest of the six-piece skeleton for free.

A compact NetworkAdapter for non-IP transports (LoRa, ESP-NOW, 6LoWPAN, BLE) is in the design phase, with a target envelope size of ≤200 bytes per signed frame and per-frame independent verifiability. The same `SessionRuntime` state machine runs unchanged against both the WSS adapter and the compact adapter — swapping the adapter swaps the physical layer, not the protocol above it.

### 3.10 Storage, Time, Recovery, Metering

Four orthogonal axes complete the substrate.

**Storage** is content-addressed via a shared `ContentStore` interface with three reference adapters: `content-store-uhrp-http` (UHRP client, configurable base URL — works against `nanostore.babbage.systems`, a self-hosted UHRP host, or localhost), `content-store-local-fs` (filesystem, `{root}/<hash[0:2]>/<hash>` layout), and `content-store-usb-cdn` (same layout plus an optional manifest signed by a BRC-52 cert for offline PAN distribution).

**Time** is a stack of hash chains: per-cell (`prevStateHash` chain), per-region (Merkle root over entity hashes per WorldTick), per-channel (MFP nSequence), and per-domain (BKDS monotonic `current_index`). Every cell shown in any UI has a verifiable hash chain from genesis to current state. Branching policy is per-surface: documents in the markdown editor adopt git-like tree-of-chains semantics; calendar recurring rules adopt chain-forks (existing instances retain their version).

**Recovery** uses the Plexus four-phase protocol described in §3.4. The recovery export payload is canonical JSON, ~3.4 KB compressed, and reconstructs the entire identity DAG client-side. Threshold recovery via Shamir Secret Sharing protects high-security roots without single-point-of-failure exposure.

**Metering** is the **Metered Flow Protocol** (MFP): an 8-state channel finite-state machine over a 2-of-2 multisig UTXO. Each tick produces an HMAC-authenticated proof; settlement uses Bitcoin's original `nSequence` mechanism — miners accept the highest `nSequence`, so dispute resolution converges on the latest tick. Capability UTXOs gate participation. Tick proofs must be dual-signed before settlement; verification uses constant-time comparison. The MFP is **operationally boring** by design: there is no protocol-level negotiation past channel formation, no off-chain consensus, and no central settlement party — counterparties simply accumulate dual-signed ticks and broadcast the latest one when they want finality.

---

## 4. The Pipeline, In Operation

This section threads the worked scenario through the substrate. A renter named Sam lives in a property managed by an agency. Sam's avatar is in a shared 3D space — the building's virtual lobby, hosted in a World Host Region. Sam speaks: *"there's a leak under the kitchen sink, photos taking now."*

§4.1 walks the depth of one intent — voice in, signed cell out. §4.2 walks the composition — how that cell crosses the organisational boundary into a tradie's separate workflow.

### 4.1 A single intent, end-to-end

What happens, step by step, when Sam's voice arrives at the substrate:

1. **Voice transcription.** The voice-input modality returns a transcript with speaker attribution. The transcript carries Sam's BRC-52 certificate via the active session — it is signed at source.

2. **Intent extraction.** A grammar-parameterised LLM call returns an `Intent` with an inferred jural category (`obligation`), a taxonomy coordinate (`property.maintenance.plumbing.leak`), a target (Sam's residence), and a constraint set. Confidence is computed from schema-completeness and vocabulary-match against the active extension's grammar — not from LLM self-report. Confidence ≥ 0.9 routes the Intent to the pipeline; lower confidence rejects with a clarifying turn.

3. **Triage.** The triage classifier separates conversation patches (no_intent), proposed actions (proposes), and ratifications (ratifies). Sam's message proposes; the system writes a cheap conversation patch on the property's evidence chain *and* dispatches the Intent to `processIntent`.

4. **`buildSIR(intent, hatContext)`.** A Semantic IR program is constructed: jural category `obligation`, governance context with `trustClass: interpretive`, `proofRequirement: attestation`, `executionAuthority: hat_scoped`, `linearity: LINEAR`, `domainBinding: { flag: 0x000200A1, domainType: 'estate', realm: 'au.qld' }`. The agency's certificate authority issued the property-management lexicon under flag `0x000200A1`; the SIR carries that binding.

5. **`lowerSIR()`.** Static check: Sam's hat holds the `tenant.report` capability for this property's domain; the trust tier is within the hat's ceiling; the action verb exists in the active extension's vocabulary. The SIR program lowers to an OIR program in administrative normal form — bindings for the capability check, the domain-flag check, the type-hash check, a logical-and over them, and a VERIFY.

6. **`emit()`.** The OIR program emits to opcode bytes in the `0x4C`–`0xD0` range. The bytes are deterministic, golden-file tested, byte-identical to those produced by alternative surface grammars (Lisp and a future LaTeX/Lean-ish/Ricardian frontend) for the same intent.

7. **Cell engine execution.** The opcode bytes execute in the 2-PDA. The Plexus opcodes verify the capability is held (`OP_CHECKCAPABILITY`), the domain flag matches (`OP_CHECKDOMAINFLAG`), the type hash matches the registered maintenance-request type (`OP_PUSHCELLTYPEHASH` + comparison), the cell's linearity is LINEAR (`OP_CHECKLINEARTYPE`), and the participant's signature matches the certificate subject (`OP_CHECKIDENTITY`). The K1 gate refuses to duplicate or discard the LINEAR cell at any later step.

8. **Receipt and evidence chain.** The kernel returns success. A `Receipt` is constructed (correlation ID, hat ID, cell ID, kernel result, opcount, signed by Sam's cert). The cell is persisted via the storage adapter and joins the property's hash-chained evidence record. Eight stage events fire to the structured logger, all tagged with the same correlation ID — the entire turn is one greppable trace.

Eight steps from voice to a signed, persisted, evidence-chain-anchored cell. The economic intent now exists, with cryptographic provenance, in a form the rest of the substrate can compose against. Steps 1–8 execute under proper BRC enforcement today: live tests against the Anthropic API for intent extraction; real signed cells written to disk; real DER-encoded ECDSA receipts.

### 4.2 Composing across organisational boundaries

The maintenance request now exists as a typed cell on the property agency's evidence chain. The agency does not do the work; it has to dispatch it to a tradie. That dispatch crosses an organisational boundary, but the substrate handles the boundary as a single semantic object with per-hat visibility — not as a copy, an integration, or a hand-off.

9. **The dispatch envelope.** The maintenance request projects into a new semantic object: a **dispatch envelope**. The envelope is RELEVANT and visible to two sets of hats: the property agency's PM hat (sees property address, description, photos, urgency, internal cost expectations) and the registered tradie's hat (sees property address, description, photos, urgency, contact for access — but *not* the agency's internal cost expectations or the rental tenant's payment history). Per-hat visibility is enforced by the policy evaluator at field level, not at object level. Every patch records its hat provenance. The dispatch envelope pattern is depicted in §6.2.

10. **The tradie's flat 2D inbox.** On the other side of the dispatch, a tradie operating from a phone or laptop sees the envelope arrive in their inbox app — the same shape as a job lead in their existing trades workflow. They quote, schedule, complete, attach photos, invoice. Each step is a patch on the envelope's evidence chain, signed by the tradie's hat, carrying its own jural category (`declaration` for completion notes, `transfer` for the invoice).

11. **Settlement.** The agency's MFP cashlane with the tradie advances by one tick when the invoice is approved. The tick proof is HMAC-authenticated and dual-signed. At any point either party can broadcast the latest settlement transaction; miners accept the highest-`nSequence` version. Settlement is off-chain until finalised, finalised on-chain via SPV.

12. **Owner notification.** Sam's landlord — a separate identity with their own hat on the property's evidence chain — sees a notification: *"Maintenance completed at [address]. Tap replaced. $280 labour + parts."* They can approve, query, or escalate. Their visibility on the dispatch envelope is RELEVANT (read-only with approval capability).

Four steps from a signed cell to a multi-organisation workflow with finalised payment, every transition gated by a kernel invariant, every visibility decision enforced at the byte level. The audit trail is regulator-grade by construction.

Steps 9–12 work in feasibility — the dispatch envelope object type and the cross-hat policy evaluator are both built — and reach proper BRC enforcement across every adapter when the Unification Matrix completes (§7). The pattern is described in more depth in §6.2.

---

## 5. Verification

Compliance is treated as a property of the architecture, not a process. Most compliance properties — that records cannot be tampered with, that authority cannot be bypassed, that consumed capabilities cannot be re-spent, that logs cannot be selectively erased — reduce to a small set of kernel invariants. If those invariants hold for the abstract execution model, the implementation conforms to the abstract model with strong empirical evidence, and the binary's integrity is anchored externally, then the compliance argument rests on a layered technical foundation rather than on organisational process.

### 5.1 The Ten Invariants

Eight execution invariants and two distributed-protocol invariants form the kernel's guarantee surface.

| ID  | Invariant                                                                 | Where enforced                          | Proof method        |
|-----|---------------------------------------------------------------------------|------------------------------------------|----------------------|
| K1  | **Linearity**: a LINEAR cell is consumed exactly once                      | `linearity.zig`, `executor.zig`           | Lean 4               |
| K2  | **Authorisation soundness**: state transitions require valid identity proof | `executor.zig` + `plexus.zig`           | Lean 4               |
| K3  | **Domain isolation**: `OP_CHECKDOMAINFLAG` is total and correct            | `plexus.zig`                              | Lean 4               |
| K4  | **Failure atomicity**: failed Plexus opcodes leave PDA state unchanged     | `plexus.zig` (peek-then-mutate)           | Lean 4               |
| K5  | **Deterministic termination**: bounded opcount, no loops, no jumps         | `pda.zig`                                 | Lean 4               |
| K6  | **Hash-chain integrity**: `prevStateHash` chain is append-only             | `semantic-objects.ts` + BSV anchor        | TLA+ model checker   |
| K7  | **Cell immutability**: 256-byte header is read-only after packing          | `cellPacker.ts` / Zig                    | Lean 4               |
| K8  | **Demotion safety**: AFFINE → RELEVANT promotion preserves consumability  | `linearity.zig`                           | Lean 4 + TLA+        |
| K9  | **Temporal morphism**: hash chains compose under projection                | `semantic-objects.ts`                     | Lean 4               |
| K10 | **Turing-completeness bound**: 2-PDA + bounded opcount is decidable        | `pda.zig` + `executor.zig`               | Lean 4               |

K1–K5, K7, K8, K9, K10 are mechanically proved in Lean 4 over an abstract 2-PDA model. K6 plus a set of distributed-protocol properties (replay impossibility, revocation immediacy, partition resilience, metering FSM correctness, evidence chain monotonicity, certificate revocation propagation, transaction DAG well-formedness, demotion safety, semantic-types correctness, zone boundary enforcement) are exhaustively model-checked in TLA+ over bounded state spaces.

### 5.2 The Three-Layer Argument

Compliance reduces to a layered argument. Each layer uses the right tool.

> **Figure 6 — The three-layer verification argument.** *[FIGURE — needs real graphic for layout pass; the diagram below is the canonical content.]*

```
┌──────────────────────────────────────────────────────────────────┐
│  Layer 3 — Composition + Regulatory Mapping                      │
│  "Given K1–K10 plus stated assumptions, each compliance test     │
│   is supported by identified proof obligations."                 │
│  Tool: TLA+ for protocol properties; paper proofs + explicit     │
│        assumption register for regulatory mapping.               │
├──────────────────────────────────────────────────────────────────┤
│  Layer 2 — Kernel Invariant Proofs (Lean 4)                      │
│  "K1–K5, K7–K10 hold for the abstract 2-PDA model."              │
│  "K6 holds under model checking for bounded state spaces."       │
│  Tool: Lean 4 theorem prover + TLA+ / TLC.                        │
├──────────────────────────────────────────────────────────────────┤
│  Layer 1 — Implementation Conformance (empirical evidence)       │
│  "Strong empirical evidence that the Zig implementation          │
│   conforms to the abstract semantics."                           │
│  Tool: 240+ conformance tests, property-based fuzzing,           │
│        differential testing, mutation testing, code review,     │
│        WASM binary hash anchoring on BSV.                         │
└──────────────────────────────────────────────────────────────────┘
```

Layer 2 is machine-checked proof. Layer 3 is paper proof citing Layer 2 lemmas. Layer 1 is empirical evidence — strong, but not proof in the Layer 2 sense. A verified compiler from Zig to WASM does not exist; we close the gap with conformance testing, property-based fuzzing, mutation testing (target: 100% kill rate), and reproducible builds with the SHA-256 of the production WASM anchored on BSV.

### 5.3 Compliance Mapping (Excerpt)

Each compliance test in the standards map to one or more kernel invariants plus stated assumptions. A representative subset of the full mapping:

| Standard      | Test                                  | Kernel contribution        | Additional assumptions           |
|---------------|----------------------------------------|----------------------------|----------------------------------|
| IEC 62443     | Replay prevention                      | K1                         | Crypto axioms                    |
| IEC 62443     | Zone boundary enforcement              | K3                         | —                                |
| EU AI Act     | AI decision traceable                  | K6 + K7                    | Application records all decisions|
| EU AI Act     | Model version recorded                 | K7                         | Application populates field      |
| GDPR          | Right to erasure                       | K6 (payload ≠ stateHash)   | Application separates PII        |
| GDPR          | Privacy by design                      | K3                         | Domain flags used for access     |
| Basel III/IV  | Settlement integrity                   | K1 + K6                    | Crypto axioms, BSV available     |
| HIPAA         | Every access recorded                  | K6                         | All access through kernel        |
| NIS2          | Partition resilience                   | K2 + K5                    | Local cert cache pre-partition   |

The full mapping covers IEC 62443, EU AI Act, GDPR, Basel III/IV, HIPAA, and NIS2 across roughly forty individual tests. Every test cell identifies the *kernel contribution* — no claim is made that the kernel alone satisfies the regulation; the kernel provides the structural foundation that makes the procedural layer auditable and tamper-evident rather than trust-dependent.

### 5.4 Honest Limitations

The verification posture is layered and explicit, not monolithic. Several assumptions are stated outright:

- **Cryptographic primitives are axiomatised.** SHA-256, ECDSA, HMAC are treated as ideal functions in the Lean model. This is standard practice in mechanised verification (seL4, CertiKOS, CompCert). The proofs hold conditional on the real primitives behaving as their idealised versions.
- **Implementation conformance is empirical, not proved.** A verified compiler for Zig→WASM does not exist. We mitigate with 240+ conformance tests, property-based fuzzing, differential testing against the Lean model, and 100%-kill mutation testing — but a non-zero gap remains.
- **Trusted boot is a prerequisite for binary-integrity claims.** The "cannot be disabled" property depends on a boot/loader sequence that verifies the WASM binary hash before loading. If the loader is compromised, binary replacement is undetectable. This is the standard root-of-trust problem.
- **Host imports are not formally verified.** The WASM binary imports `host_checksig`, `host_sha256`, etc. from the TypeScript host. These are assumed correct; strengthening would require a verified crypto library (HACL*, Fiat-Crypto).
- **Application-layer correctness is required.** Several compliance properties depend on the application correctly routing all operations through the kernel. The kernel cannot prevent an application from writing directly to a database without creating a semantic object.

These limitations are not weaknesses of the verification posture — they are the explicit boundary conditions that make the posture honest. The deliverable for regulators is not the Lean source code; it is a paper argument, citing the mechanised proofs, the TLA+ model results, the conformance evidence, the assumption register, and the BSV-anchored WASM hash. That is fundamentally different from "we have controls; trust us."

### 5.5 What this paper does not claim

To prevent overreach, the following are *not* claimed:

- That the boot sequence runs end-to-end under proper BRC enforcement *today*. It runs to step 7 in production form; closing the remaining gap is the Unification Matrix programme (§7). The whitepaper claims the substrate is *architecturally complete*, not that every adapter is integrated.
- That the cryptographic primitives (SHA-256, ECDSA, HMAC) are themselves verified. They are axiomatised in the Lean model under standard computational assumptions; no claim is made beyond what decades of cryptanalytic literature supports.
- That a verified compiler from Zig to WASM exists. It does not. Implementation conformance is established empirically (240+ tests, fuzzing, mutation testing, differential testing); the gap is acknowledged in §5.4.
- That Semantos replaces the BSV blockchain, the BRC-100 wallet, the `@bsv/sdk`, or any of the underlying primitives it composes. It complements them; it depends on them where they exist; it adds where they don't.
- That the lexicon inventory is complete. Eight lexicons ship today; healthcare, government, and many others are roadmap items. The cost of adding one is documented; no claim is made that it has already been paid.
- That any specific named commercial deployment is in production. None are named in this paper. Reference deployments are described only as architectural patterns.

The substrate is a foundation, not a finished product. This whitepaper describes what the foundation provides and what it has been formally proved to guarantee — no more, no less.

---

## 6. Adapters and Verticals

The substrate's guarantees are invisible until adapters consume them. The Unification Roadmap names eight active adapter surfaces; each consumes a subset of the substrate to deliver user-facing capability.

| Adapter                | Status          | Role                                                           |
|------------------------|------------------|----------------------------------------------------------------|
| World Host (OTP/Elixir)| Built, integrating | Authoritative runtime for persistent shared 3D spaces         |
| World Client (three.js)| Built, integrating | Browser-side prediction + rendering against the World Host    |
| Helm                   | Built            | The convergence surface — every axis meets in one workbench (currently shipped as `apps/loom-react/`; renamed in code paths in due course) |
| Markdown Editor        | Building         | Versioned documents with hash-chained patches and BRC-52 author binding |
| Calendar / Events      | Building         | Events + recurring rules as cells with chain-forks semantics  |
| Settlement (Paskian)   | Built            | BSV settlement, border-router aggregation, Merkle batching     |
| Extensions / Policy    | Built            | Mints lexicons, defines capabilities, hosts vertical grammars |
| Voice                  | Placeholder      | Input modality; the north-star depends on it                   |

### 6.1 World Host

The World Host is the authoritative runtime for persistent shared 3D spaces. It is implemented in Elixir over OTP — process-per-entity, supervision trees, distributed registry, PubSub fan-out — running atop the BEAM virtual machine, which has thirty years of soft-realtime distributed-systems engineering behind it.

Concepts:

- **Region**: a logical shard of the world hosted by exactly one OTP process at a time. Authority is exclusive — one region commits state for a given entity. Migration between OTP nodes is supported without changing `regionId`.
- **WorldEntity**: a `LoomObject` with a `spatial` extension (position, orientation, velocity, bbox) and a `regionId` pointer. Linearity lives in the cell header, enforced by the cell engine on the region.
- **WorldTick**: a per-region monotonic counter at ~20 Hz, distinct from MeteringTick. `tick[N].prevStateHash == tick[N-1].stateHash`. `stateHash` is a Merkle root over entity hashes at tick commit time.
- **Client prediction**: clients run the same WASM kernel locally, predict immediately, render at frame rate. Authoritative `stateHash` arrives on the next tick; match → confirmed; mismatch → snap and roll back.

Because the kernel's substructural types are enforced on the region, conflict resolution is discrete. There is no continuous drift, no partial-credit merge, no CRDT machinery — a LINEAR resource cannot be in two places by construction. The cost: actions on a given entity are serialised through a single mailbox. The benefit: "simultaneous" is an unambiguous concept, and the audit trail is a single ordered hash chain rather than a reconstructed causal order.

Bandwidth at scale is tractable. With ~100 entities visible per client at 20 Hz, throughput is on the order of 100 KB/s per client per region, with interest management scaling further via region subdivision. Persistent multi-user worlds — what one might call a "Ready Player One"-class persistent 3D space — are a finite delta on the existing primitives, not a fresh stack.

### 6.2 The Dispatch Envelope

The dispatch envelope is the canonical pattern for cross-organisational workflows. It is a single semantic object that two (or more) verticals reference. Patches from each side carry the patcher's hat provenance; per-field visibility rules determine what each hat sees. The envelope object lives once; every hat sees a filtered projection.

Walked through the leaky-tap scenario:

```
Dispatch Envelope (one semantic object, multiple per-hat projections)
│
├── Property-agency hat (RELEVANT patches):
│   address, description, photos, urgency, PM contact, tenant access
│
├── Property-agency hat (AFFINE — agency-only):
│   owner details, lease info, cost expectations, internal PM notes
│
├── Tradie hat (RELEVANT):
│   ROM estimate, quote, schedule, completion photos, invoice
│
├── Tradie hat (AFFINE — tradie-only):
│   internal cost calculations, supplier quotes, margin notes
│
├── Tenant hat (RELEVANT, read-only):
│   status updates only
│
└── Owner hat (RELEVANT, approval capability):
    approval / rejection of cost
```

Each party sees exactly what they should. AFFINE patches are encrypted to the authoring hat's key; the wrong hat cannot decrypt them, full stop. The patch log is append-only; every patch records its hat provenance. The result is a workflow that previously required point-to-point integration, written audit policies, and a manual reconciliation pass — replaced by one semantic object whose visibility is enforced cryptographically.

### 6.3 Verticals as State Machines

Phase 35A's session protocol promotion exposes a single cross-cutting frame: **every vertical is a state machine over a shared session skeleton.** A vertical contributes its `StateMachine<Event, State>`; it inherits the rest of the six-piece skeleton (Discovery, Formation, Runtime, Broadcast, Transport, Metering Hook) for free.

This makes the cost of adding a new vertical small. CDM lifecycle? `CdmLifecycleStateMachine`. SCADA shift handover? `ShiftHandoverStateMachine`. Auctions, oracles, calls — each is a thin consumer of the same skeleton plus its own state machine and its own lexicon. The substrate does not know what the vertical is; the vertical does not know what the transport is. The decoupling is total.

### 6.4 The Lexicon Inventory

Eight Lean-formalised lexicons ship with the substrate today, each a substrate-polymorphic registration over the generic `Lexicon` typeclass:

| Lexicon              | Domain                                              | Canonical use                                          |
|----------------------|-----------------------------------------------------|---------------------------------------------------------|
| `Jural`              | Hohfeldian legal acts (the canonical lexicon)       | Reference for every other lexicon's category derivation |
| `CDM`                | ISDA Common Domain Model — derivatives lifecycle    | Settlement, novation, clearing, margin, default         |
| `PropertyManagement` | Real estate operations                              | Properties, leases, tenants, maintenance, compliance    |
| `ProjectManagement`  | Work-breakdown and assignment                       | Tasks, dependencies, milestones, kanban                 |
| `RiskAssessment`     | Structural failure analysis (BREM-aligned)          | Exposure, mitigation, dispute resolution                |
| `BillsOfLading`      | Supply-chain provenance                             | Custody, origin tracking, certification                 |
| `ControlSystems`     | Industrial / SCADA                                  | Telemetry, alarms, interlocks, shift handovers          |
| `CircuitCommands`    | Firmware / embedded                                 | Sensor commands, capability gating on devices           |

Each lexicon is roughly forty lines of Lean: an `inductive` for the categories, a `header` function, a proof of header injectivity, and an `instance` registration. Once registered, every substrate-level theorem (M1–M4, D1–D3, the renderCard correctness lemmas) automatically applies — no per-lexicon re-proof of the substrate invariants.

The cost of adding a ninth lexicon is a few hours, not weeks. The cost of having it *formally verified* against the substrate's existing theorems is zero — the substrate carries the proofs.

---

## 7. Where This Is Going

The substrate is architecturally complete. The work that remains is integrative — getting every adapter cell-bound, signed-bundle-wrapped, K1-gated, lexicon-typed, capability-gated, hash-chained, recovery-included, and metered, in that order. This work is tracked in the **Unification Roadmap** — a single matrix of (surface × axis) pairs with an explicit deliverable for each unfilled cell.

Unification status, current snapshot:

- **10 substrate components** (cell engine, Plexus core, identity, capability domain, verifier sidecar, mesh, VFS, SIR, Lean, MFP) — mostly ✓ by construction; gaps are component-to-component integration.
- **8 adapter surfaces** (World Host, World Client, Helm, Markdown Editor, Calendar, Settlement, Extensions, Voice) — ⚠ on most cells; ✗ on Voice (placeholder).
- **10 axes** (Identity, Storage, Transport, Substructural, Lexicon, Formal, Capability, Time, Recovery, Metering — axis D in the matrix splits into four sub-axes covering substructural, lexicon-domain, formal-proof, and capability typing respectively).

The boot sequence (§2) currently halts at step 9 in production-shaped form. Steps 1–7 work end-to-end under proper BRC enforcement; steps 8 onward work in feasibility but not yet under proper enforcement across every adapter. Three near-term engineering tracks close the gap:

1. **ContentStore interface + reference adapters.** A shared content-addressed storage contract under `core/protocol-types/`, with three reference adapters (UHRP HTTP, local filesystem, USB-mounted PAN). One of the existing extension consumers (`extensions/extraction`) rewires through the new interface. This is the smallest change that turns "your storage is whatever you define" from an aspiration into a contract.

2. **Compact NetworkAdapter for non-IP transports.** The existing transport assumes IP and full MTUs. The IoT row of the adapter matrix needs a connectionless, sign-per-frame variant with a ≤200-byte envelope, fragment-aware over arbitrary-MTU transports (LoRa, ESP-NOW, 6LoWPAN, BLE). The same `SessionRuntime` state machine runs unchanged — swapping the adapter swaps the physical layer.

3. **One-command sovereign-node installer.** `curl -fsSL https://get.semantos.sh | sh` on a fresh Ubuntu 22.04 $5 VPS produces a working node in ≤5 minutes, with identity, wallet, storage, messaging, and admin all wired up. This is the M3 milestone — when it runs reliably, the whitepaper's headline picture becomes the production reality and the textbook teaching the substrate is ready to ship.

These three tracks compose with the broader Unification Matrix. M3 — the curl-one-URL milestone — and the matrix's "boot sequence runs end-to-end under proper BRC enforcement" milestone are the same date by construction.

Beyond the immediate matrix, the substrate has room to extend along three axes simultaneously. **Lexicons** continue to accrete: eight ship today, and additional lexicons (healthcare, government, energy markets, education credentials, others) are roadmap items — each is one Lean file plus a domain grammar, with the substrate's verification already covering the structural invariants. **Federation** matures through Phase 35B: node-as-service, federated peer registry, NAT-relay, public-internet deployment patterns; once shipping, a Semantos node is reachable from any browser on any network without the operator surrendering identity, anchor, or storage to a third party. **The substrate frontier** continues to project into new dimensions as new domains are encoded — each new domain inherits identity, storage, transport, verification, time, recovery, and metering from the substrate by construction, so the marginal cost of a new vertical is the cost of its grammar and its state machine.

The end state is a federation of sovereign nodes, each running the same kernel, each owning its own identity, each federating through whatever transport its operator chooses, each running the verticals its operator installs, each cryptographically attesting every state transition it commits.

---

## 8. Conclusion

DNS told the network where to find things. Semantos tells the network *what they are*, *who owns them*, *what consuming them costs*, *what their history proves*, and *whether the action you are about to take is permitted*.

By layering cryptographic type, linearity, jural meaning, and provable history onto the primitives of sovereignty, Semantos creates digital objects with cryptographically verifiable provenance, type, and ownership lineage. The substrate is built on open standards (BRC, `@bsv/sdk`, deterministic cryptography, Lean 4, TLA+). It is designed to be operationally boring: no special tokens, no voting on business logic, no consensus delay on local operations, no third-party trust requirements for any property the kernel guarantees. Each vertical defines its own grammar. Each operator controls its own keys. The substrate is the foundation; what gets built on it is the operator's choice.

The substrate is not a blockchain project. It is a sovereign node — voice in, economic effect out, every step proved — that uses the blockchain as a timestamping and settlement layer when it needs one and not when it doesn't. A thousand of them, cooperating, are the foundation for the next decade of digital infrastructure.

---

## Contact

Todd Price | Founder, Real Blockchain Solutions
Real Blockchain Solutions | Queensland, Australia
todd@realblockchainsolutions.com

---

## Appendix A — References

The substrate composes the following published work:

- **BRC standards** (Bitcoin Request for Comments): BRC-42 (BSV Key Derivation Scheme), BRC-43 (Security Levels and Protocol IDs), BRC-52 (Identity Certificates), BRC-53 (Certificate Creation and Revelation), BRC-62 (BEEF — Background Evaluation Extended Format), BRC-69 (Revealing Key Linkages), BRC-74 (BUMP — BSV Unified Merkle Path), BRC-85 (PIKE — Proven Identity Key Exchange), BRC-94 (Verifiable Revelation of Shared Secrets), BRC-95 (Atomic BEEF), BRC-100 (Wallet-to-Application Interface), BRC-103 (Peer-to-Peer Mutual Authentication), BRC-108 (Identity-Linked Token Protocol).
- **`@bsv/sdk`**: BSV TypeScript SDK (github.com/bsv-blockchain/ts-sdk).
- **`wallet-toolbox`**: BRC-100 reference implementation.
- **Lean 4** + Mathlib4 (mathlib-community.github.io).
- **TLA+** + Apalache symbolic model checker.
- **Hohfeld, W. N.** (1913). *Some Fundamental Legal Conceptions as Applied in Judicial Reasoning.* Yale Law Journal.

The substrate cites prior work in: substructural type systems and linear logic (Girard, Wadler), proof-carrying code (Necula), abstract state machines (Gurevich), bounded model checking (Clarke), formally verified operating systems (seL4, CertiKOS), and verified cryptographic primitives (HACL*, Fiat-Crypto).

---

## Appendix B — Reference: Opcode Set, Cell Wire Format, Component Index

### B.1 Plexus opcode range (`0xC0`–`0xCF`)

The cell engine extends standard Bitcoin Script with a Plexus opcode range that adds VM-level type enforcement. All opcodes operate on cells already pushed to the stack; failure leaves stack state unchanged (invariant K4).

| Opcode | Mnemonic                | Behaviour                                                                 |
|--------|-------------------------|----------------------------------------------------------------------------|
| `0xC0` | `OP_CHECKLINEARTYPE`    | Pop type tag from stack. Verify object linearity matches. Fail if mismatch.|
| `0xC1` | `OP_CHECKAFFINETYPE`    | Assert top-of-stack object is AFFINE. Used for transfer record validation. |
| `0xC2` | `OP_CHECKRELEVANTTYPE`  | Assert top-of-stack object is RELEVANT. Used for certificate validation.   |
| `0xC3` | `OP_CHECKCAPABILITY`    | Verify capability token UTXO is unspent via BUMP proof in Cell 1.          |
| `0xC4` | `OP_CHECKIDENTITY`      | Verify BRC-52 certificate binding against participant graph.               |
| `0xC5` | `OP_ASSERTLINEAR`       | Assert object is unconsumed LINEAR. Abort if already-consumed flag is set. |
| `0xC6` | `OP_CHECKDOMAINFLAG`    | Verify domain flag at header offset 24–27 matches expected u32.            |
| `0xC7` | `OP_VERIFYVERSION`      | Assert object state version hash matches expected (`prevStateHash` chain). |
| `0xC8` | `OP_CHECKDOMAIN`        | Verify domain flag is within authorised range for current context.         |
| `0xC9` | `OP_ASSERTPHASE`        | Assert pipeline phase matches expected (source, parse, ast, etc.).         |
| `0xCA` | `OP_CHECKCELL`          | Validate continuation cell header: type tag, index, payload size bounds.   |
| `0xCB` | `OP_VERIFYBUMP`         | Delegate BUMP verification to host: parse BRC-74, compute merkle root.     |
| `0xCC` | `OP_VERIFYBEEF`         | Delegate Atomic BEEF verification: validate `0x01010101` prefix + ancestry.|
| `0xCD`–`0xCF` | reserved          | Reserved for future Plexus kernel extensions.                              |

### B.2 Cell wire format

> **Figure 7 — Cell wire format.** *[FIGURE — needs real graphic for layout pass; the tables below are the canonical content.]*

**Cell 0 (header + payload).** Fixed-size 1024-byte structure. All multi-byte integers little-endian.

| Offset | Size | Field          | Description                                                |
|--------|------|----------------|------------------------------------------------------------|
| 0      | 16   | Magic          | `0xDEADBEEF CAFEBABE 13371337 42424242`                     |
| 16     | 4    | Linearity      | u32 LE: 1=LINEAR, 2=AFFINE, 3=RELEVANT                      |
| 20     | 4    | Version        | u32 LE: object state version                                |
| 24     | 4    | Flags / DomFlag| u32 LE: bitfield (`0x01`=immutable, `0x02`=spent) / domain  |
| 28     | 2    | RefCount       | u16 LE: reference count                                     |
| 30     | 32   | TypeHash       | SHA-256(`whatPath:howSlug:instPath`)                        |
| 62     | 16   | OwnerID        | 16-byte owner identifier                                    |
| 78     | 8    | Timestamp      | u64 LE: milliseconds since epoch                            |
| 86     | 4    | CellCount      | u32 LE: total cells (header + continuation)                 |
| 90     | 4    | PayloadSize    | u32 LE: semantic IR payload bytes in Cell 0                 |
| 94     | 1    | Phase          | Pipeline phase (`0x00`=source .. `0x07`=outcome)            |
| 95     | 1    | Dimension      | `0x00`=composite, `0x01`=what, `0x02`=how, `0x03`=instrument|
| 96     | 32   | ParentHash     | SHA-256 of parent object (zero if root)                     |
| 128    | 32   | PrevStateHash  | SHA-256 of previous state (zero if genesis)                 |
| 160    | 96   | Reserved       | Zero-padded; reserved for future use                        |

Bytes 256–1023 hold the semantic IR payload.

**Continuation cells (Cell 1+).** 8-byte header + up to 1016 bytes of cell-type-specific payload.

| Offset | Size | Field        | Description                                                  |
|--------|------|--------------|---------------------------------------------------------------|
| 0      | 1    | CellType     | `0x01`=BUMP, `0x02`=ATOMIC_BEEF, `0x03`=ENVELOPE, `0x04`=DATA, `0x05`=STATE |
| 1      | 2    | CellIndex    | u16 LE: 1-based position in continuation sequence             |
| 3      | 2    | TotalCells   | u16 LE: total continuation cells (excludes Cell 0)            |
| 5      | 2    | PayloadSize  | u16 LE: actual data bytes (max 1016)                          |
| 7      | 1    | Reserved     | Zero                                                          |
| 8      | 1016 | Payload      | Cell-type-specific data (zero-padded)                         |

### B.3 Component index

The substrate as code, organised by tier (per the import-boundary gate):

```
core/             imports nothing outside core/
  cell-engine     Zig 2-PDA + WASM bindings + cell packing
  cell-ops        Type hash registry, merkle envelopes, opcode enum
  protocol-types  Bridge types between TS and the WASM contract
  constants       constants.json → constants.zig + constants.ts codegen
  semantos-ir     Opcode IR (ANF)
  semantos-sir    Semantic IR (jural categories + governance)
  plexus-contracts  Plexus type definitions
  plexus-vendor-sdk Plexus vendor SDK (BRC-42 + SQLite)

runtime/          imports core/ + runtime/
  shell           semantos-shell REPL + CLI + 30+ verbs
  node            Semantos node daemon, admin API, CLI
  services        Renderer-agnostic stores (Loom, Identity, Config, …)
  session-protocol Domain-neutral session skeleton
  peer-locator    BCA → endpoint resolution
  ws-node-adapter NetworkAdapter over WSS
  intent          Universal intent pipeline
  compact-network-adapter (in design — Part 2 of Sovereign Node Plan)

extensions/       imports core/ + runtime/ + extensions/
  policy-runtime  Routes extension grammars through the WASM 2-PDA
  cdm             ISDA CDM lifecycle, regulatory reporting
  extraction      Semantic extraction pipeline
  metering        MFP 8-state FSM, tick proofs, settlement
  chain-broadcast Bulk on-chain anchoring
  recovery        Recovery export payload + challenge-response
  scada           SCADA industrial-control integration
  navigator       Core navigation layer
  calendar        Calendar lexicon + extension
  game-sdk, games Game engine + example games
  
apps/             imports core/ + runtime/ + extensions/, never another app
  loom-react      Three-panel React workbench
  loom-svelte     Svelte UI proving framework-quarantine
  demo-wasm-threejs Three.js scene driven by cell-engine WASM
  mud, piggybank, poker-agent, settlement, navigation_app, world-client, world-host
  node-installer  (in design — Part 3 of Sovereign Node Plan)
  
proofs/           Lean 4 + TLA+ proof artefacts
  lean/Semantos/Theorems/  K1, K2, K3, K4, K5, K7, K8, K9, K10
  lean/Semantos/Lexicons/  Jural, CDM, PropertyManagement, … (8 total)
  lean/Semantos/Substrate/ Lexicon typeclass + substrate lemmas
  tla/  CertRevocation, DemotionSafety, EvidenceChain, MeteringFSM,
        PartitionResilience, ReplayPrevention, SemanticTypes,
        TransactionDAG, ZoneBoundary
```

Mechanical import-boundary enforcement at `tests/gates/import-boundaries.test.ts`. The tier rules above are not architectural recommendations; they are CI-enforced invariants.

*("What this whitepaper does not claim" was inlined as §5.5.)*
