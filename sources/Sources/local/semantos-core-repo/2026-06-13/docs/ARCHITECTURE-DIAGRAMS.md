---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/ARCHITECTURE-DIAGRAMS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.331036+00:00
---

# Semantos Core — Architectural Diagrams

Source of truth: `docs/canon/` — all canonical terminology from the 2026-04-26 glossary decision pass.

**Canonical term quick-ref**: cell (not SemanticObject), hat (not facet), Helm (not Loom), capability token (not permission-token), cell engine (not PDA/2-PDA in prose), governance domain (not trust domain).

---

## 1. Three Cybernetic Orders

The substrate is structurally three-order cybernetic. This is the fundamental architectural claim.

```mermaid
graph TB
    subgraph Third["3rd Order — Many observers observing each other"]
        direction LR
        F1["Federation\nmany Pask kernels on sovereign nodes\nobserving each other via Pravega streams"]
        GD["Five Governance Domains\nTrust · Estate · Realm · Corporate · Cooperative\neach a distinct 3rd-order structure"]
        LEX["Lexicons\nformalised community vocabularies\nLean proof of headerInjective per lexicon"]
        EG["Extension Grammar\nmeta-mechanism for communities entering substrate\nextension manifest = community's self-observation\nagainst lexicon obligations"]
        K3["K3 Domain Isolation\nenforced at cell engine boundary\nOP_CHECKDOMAINFLAG"]
    end

    subgraph Second["2nd Order — System observing itself"]
        direction LR
        PK["Pask Kernel\nConversation Theory (Pask 1976) in Zig\npask_node_is_stable = system watching own learning\nstable thread = confirmed cross-kernel agreement"]
        CG["Compression Gradient\nteachback pipeline\nsource→AST→SIR→OIR→bytecode→action→outcome\neach stage reflects on previous"]
        JUR["Jural Categories\ndeclaration · obligation · permission\nprohibition · power · condition · transfer\n2nd-order attribution of meaning to mechanism"]
        K2["K2 Authorisation\nstate change requires identity verification\nsystem reflects on who acts"]
    end

    subgraph First["1st Order — Observer-independent control"]
        direction LR
        CE["Cell Engine\n2-PDA, ~4,900 LOC Zig\nK1–K7 invariants at bytecode gate\nno self-reference (breaks K5 argument)"]
        LMDB["LMDB Storage\ndumb observer-independent storage\ncell engine is the verifier"]
        K1["K1 Linearity\nK4 Failure Atomicity\nK5 Bounded Termination\nK6 Hash-chain Integrity\nK7 Cell Immutability"]
    end

    Third -->|"K3 boundary enforcement"| Second
    Second -->|"OIR → 1st-order mechanism"| First

    style Third fill:#e8f5e9,stroke:#388e3c
    style Second fill:#e3f2fd,stroke:#1565c0
    style First fill:#fff3e0,stroke:#e65100
```

---

## 2. Compression Gradient — Teachback Pipeline

Each stage is the system explaining the previous stage to itself. Pask's teachback criterion compiled into a static-analysis pipeline.

```mermaid
flowchart LR
    S0["0x00 source\nRELEVANT\nraw evidence\nnot yet reflected upon"]
    S1["0x01 parse\nLINEAR\nAST extracted\nstructural extraction of surface"]
    S2["0x02 ast\nAFFINE\naccumulated state\nsubstrate has structural object"]
    S3["0x03 typecheck\nRELEVANT\nclassification scores\njural category attributed"]
    S4["0x04 optimise\nLINEAR\nSIR program\nmeaning in typed annotations"]
    S5["0x05 codegen\nRELEVANT\nOIR + bytecode\nmechanism produced from meaning"]
    S6["0x06 action\nLINEAR\ncell engine executes\nbytecode runs"]
    S7["0x07 outcome\nRELEVANT\nresult cell\nnew source for next pass"]

    S0 -->|"parse\nK4 atomicity on fail\nno trace left"| S1
    S1 --> S2
    S2 -->|"AST→SIR\nSTRONGEST GATE\njural category\ntaxonomy\ngovernance context\nidentity binding"| S3
    S3 --> S4
    S4 -->|"SIR→OIR\nlowerSIR : SIR → Error + OIR\nalpha-equivalence guarantee\nsame meaning → byte-identical bytecode"| S5
    S5 -->|"OIR→bytecode\nANF-to-opcode\nnear-mechanical"| S6
    S6 -->|"K1 K3 K4 K5 K6 K7\nviolation halts + rolls back"| S7
    S7 -.->|"outcome becomes new source\nloop closes"| S0

    subgraph Levels["Cybernetic order at each stage"]
        L1["source: pre-cybernetic"]
        L2["AST: 1st-order (mechanism, no meaning)"]
        L3["SIR: 2nd-order (system's reflection: jural category, lexicon, who acts)"]
        L4["OIR: 1st-order (mechanism checking 2nd-order claim)"]
        L5["outcome cell: 2nd-order (persistent self-observation record)"]
        L6["Pravega event: 3rd-order (federation's record of local observation)"]
    end
```

---

## 3. System Layer Architecture

Five tiers with enforced unidirectional imports. Gate: `tests/gates/import-boundaries.test.ts`.

```mermaid
graph TB
    subgraph APPS["APPS (Tier 3)"]
        A1[oddjobtodd\ntrades vertical]
        A2[property-mgmt\nproperty vertical]
        A3[Helm\nworkbench shell]
        A4[demo-collab\nversioning demo]
        A5[poker-agent]
        A6[piggybank]
    end

    subgraph EXT["EXTENSIONS (Tier 2 — Domain Algorithms)"]
        E1[policy-runtime\nopcode evaluator +\nD-A6 authority gate]
        E2[cdm\nISDA CDM lifecycle]
        E3[extraction\n5-stage ETL pipeline]
        E4[chain-broadcast\nBSV tx + BEEF]
        E5[metering\npayment-channel FSM]
        E6[oddjobz\nD-O1–O11 deliverables]
        E7[navigator\ntype-driven routing]
        E8[calendar\nbooking/scheduling]
    end

    subgraph RUNTIME["RUNTIME (Tier 1 — Entry Surfaces)"]
        R1[shell\nCLI/REPL + Lisp compiler]
        R2[node\ndaemon + admin API]
        R3[services\nrenderer-agnostic stores]
        R4[session-protocol\nmulti-party FSM]
        R5[peer-locator\nBCA → WSS endpoint]
        R6[ws-node-adapter\nfederation transport]
        R7[intent\nNLU pipeline]
        R8[world-beam\nElixir bridge]
        R9[verifier-sidecar\nD-V1–V3 crypto verification]
    end

    subgraph CORE["CORE (Tier 0 — Kernel Foundation)"]
        C1[cell-engine\nZig WASM 2-PDA\nK1–K7 enforcement]
        C2[pask\nZig WASM learning kernel\nConversation Theory]
        C3[pask-and-cell\ncombined build\nshared linear memory]
        C4[protocol-types\nbridge + ContentStore interfaces]
        C5[cell-ops\ncell packing + type-hash registry]
        C6[semantic-objects\nappend-only patch substrate\nDrizzle + Postgres]
        C7[semantos-ir\nANF OIR layer]
        C8[semantos-sir\nSIR + jural types]
        C9[identity-ports\nport-based DI surface]
        C10[plexus-contracts\nBRC-52/42/100 types]
        C11[plexus-vendor-sdk\nidentity DAG + BKDS]
        C12[state\nreactive cell primitives]
        C13[world-sdk\nRelay client + CellDag]
    end

    subgraph PLATFORMS["PLATFORMS"]
        P1[browser\nembedded WASM 29 KB]
        P2[node.js\nfull WASM 185 KB]
        P3[esp32\nIoT embedded]
    end

    APPS -->|"may import"| EXT
    APPS -->|"may import"| RUNTIME
    EXT -->|"may import"| RUNTIME
    EXT -->|"may import"| CORE
    RUNTIME -->|"may import"| CORE
    CORE --> PLATFORMS
```

---

## 4. Cell Wire Format (1024 bytes)

The canonical data primitive. Everything stored, evaluated, and chained is a cell.

```
┌────────────────────────────────────────────────────────────────────────┐
│  CELL HEADER  (256 bytes, offsets 0–255)                               │
├─────────┬──────┬─────────────────────────────────────────────────────  │
│ offset  │ size │ field                                                  │
├─────────┼──────┼─────────────────────────────────────────────────────  │
│ 0       │ 16   │ Magic  DE AD BE EF  CA FE BA BE  13 37 13 37  42 42   │
│ 16      │ 4    │ Linearity  uint32 LE  0=LINEAR 1=AFFINE 2=RELEVANT    │
│ 20      │ 4    │ Version  uint32 LE  monotonic state counter            │
│ 24      │ 4    │ DomainFlag  uint32 LE  §4.5 governance domain          │
│ 28      │ 2    │ RefCount  uint16 LE                                    │
│ 30      │ 32   │ TypeHash  SHA-256(whatPath : howSlug : instPath)       │
│ 62      │ 16   │ OwnerID  BCA-derived identifier                        │
│ 78      │ 8    │ Timestamp  uint64 LE  ms since Unix epoch              │
│ 86      │ 4    │ CellCount  total cells incl. continuations             │
│ 90      │ 4    │ PayloadSize  payload bytes in Cell 0 (≤ 768)           │
│ 94      │ 1    │ Phase  0x00–0x07  compression-gradient stage           │
│ 95      │ 1    │ Dimension  0x00=composite 0x01=WHAT 0x02=HOW 0x03=INST │
│ 96      │ 32   │ ParentHash  SHA-256 of parent cell (structural)        │
│ 128     │ 32   │ PrevStateHash  SHA-256 of previous state (temporal)    │
│ 160     │ 96   │ Reserved  zero-padded forward-compat                   │
└─────────┴──────┴─────────────────────────────────────────────────────  │
                                                                          │
┌────────────────────────────────────────────────────────────────────────┐
│  SEMANTIC PAYLOAD  (768 bytes, offsets 256–1023)                       │
│  domain-specific content, zero-padded                                  │
└────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────┐
│  CONTINUATION CELLS  (1024 bytes each, optional)                       │
│                                                                        │
│  0x01 BUMP         Bitcoin UTXO merkle proof                           │
│  0x02 ATOMIC_BEEF  SPV ancestry proof (0x01010101 prefix, BRC-95)     │
│  0x03 ENVELOPE     multi-cell container                                │
│  0x04 DATA         untyped data                                        │
│  0x05 STATE        mutable state snapshot                              │
│                                                                        │
│  Auxiliary stack pops in reverse order so BUMP is verified first       │
│  (fail-fast: bad anchor → skip BEEF + STATE computation)               │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Linearity Type System

```mermaid
graph LR
    subgraph Types["Four Linearity Classes (header offset 16)"]
        L0["LINEAR — code 0\nConsumed EXACTLY ONCE\nDUP refused · DROP refused\n─────────────────\nCapability tokens (BRC-108)\nPayment-channel states\nAction decisions (phase 0x06)\nExtraction results (phase 0x01)"]
        L1["AFFINE — code 1\nConsumed AT MOST ONCE\nDUP refused · DROP permitted\n─────────────────\nDraft inspection reports\nTransfer records\nProof-of-custody\nMaintenanceRequest before dispatch"]
        L2["RELEVANT — code 2\nUsed AT LEAST ONCE\nDUP permitted · DROP refused\n─────────────────\nCertificates (BRC-52)\nSchema definitions\nTaxonomy nodes\nDispatched envelopes"]
        L3["UNRESTRICTED — code 3\nNo constraint\nDUP permitted · DROP permitted\n─────────────────\nScratch values\nTemporary working data"]
    end

    subgraph Enforcement["Bytecode Gate (K1 + K7)"]
        OP0["OP_CHECKLINEARTYPE 0xC0\nreads Linearity field offset 16"]
        OP5["OP_ASSERTLINEAR 0xC5\naborts if already consumed"]
        K4R["K4 Failure Atomicity\nfull PDA state rolls back\nbyte-for-byte on any violation"]
    end

    subgraph Chain["K7 — Cell Immutability"]
        K7["256-byte header is read-only after packing\nlinearity class set at pack time is enforced forever\nno opcode can rewrite header mid-execution"]
    end

    L0 -->|"K1 enforced"| OP0
    OP0 --> K4R
    K7 --> OP0
    OP5 --> K4R
```

---

## 6. Kernel Composition (Cell Engine + Pask + DB)

```mermaid
flowchart TB
    subgraph CellEngine["Cell Engine — 1st-order invariants"]
        CE1["Zig WASM 2-PDA\n~4,900 LOC\n185 KB full / 29 KB embedded"]
        CE2["Enforces K1–K7 at bytecode gate\nDeterministic, bounded, auditable"]
        CE3["29 WASM exports\nkernel_load_script\nkernel_execute\nkernel_set_enforcement\ncell_pack · bca_derive · spv_verify"]
    end

    subgraph PaskKernel["Pask Kernel — 2nd-order self-observation"]
        PK1["Zig WASM\nConversation Theory (Pask 1976)\n~7 KB"]
        PK2["pask_node_is_stable\npask_stable_threads_into\npask_node_h_state\npask_upsert_node"]
        PK3["Bounded fixed-size state\nNode × MAX_NODES (16k)\nEdge × MAX_EDGES (32k)\nDelta ring × MAX_DELTAS (64k)"]
        PK4["Deterministic — no host-clock reads\nIdentical inputs → bit-identical snapshots\nSnapshot fits in one cell (208B Node + 40B Edge)"]
    end

    subgraph Combined["pask-and-cell — Combined Build"]
        COMB["Single WASM module\ncore/pask-and-cell/src/combined.zig\nShared linear memory\nCell IDs from cell engine passed\nzero-copy into pask_upsert_node"]
    end

    subgraph DB["DB Topology — vtable discipline"]
        LMDB["LMDB (hot path)\nHeaderStore · OutputStore\nDerivationStateStore\nPaskSnapshotStore\n(observer-independent, dumb storage)"]
        PG["Postgres (reasoning)\npask_node_view\npask_entailment\npask_stable_thread\nmaterialised views\nBert's intent reducer queries here"]
        SQLITE["SQLite (browser)\nOPFS-backed snapshot"]
        PRAVEGA["Pravega (federation)\npask-interactions stream (6th stream)\ndeterministic replay → bit-identical graphs\nstream is canonical; snapshot is convenience"]
    end

    CellEngine --> Combined
    PaskKernel --> Combined
    Combined --> DB

    subgraph FederatedConvergence["Federated Convergence Property"]
        FC["Two nodes subscribing to same Pravega stream\nproduce bit-identical Pask graphs\nSame interactions in same order → same state\n(K5-style argument; no host clock)"]
    end

    PRAVEGA --> FederatedConvergence
```

---

## 7. Boot Sequence — Cold Start to K1–K10 Compliance

```mermaid
flowchart TD
    B1["Step 1\nEmail + challenge registration\nPlexus identity creation\nBRC-52 cert issued"]
    B2["Steps 2–3\nIdentity DAG bootstrap\nBRC-42 key hierarchy derived\nBRC-85 PIKE ECDH edges established"]
    B3["Steps 4–6\nHats & capability tokens\nBRC-108 capability UTXOs minted\nDomain flags assigned (§4.5)\nhat-key root encrypted under wallet KEK"]
    B4["Step 7\nkernel_set_enforcement(1)\ncell engine transitions to full K1–K7 gate\nCells now evaluated under invariant enforcement\n(before step 7: cells stored but not enforced)"]
    B5["Steps 8–9\nVerifier sidecar (D-V1–V3)\nBRC-52 cert authenticity + binding\ncapability UTXO SPV checks\nK2 Authorisation layer active"]
    B6["Steps 10–11\nAdapters + mesh\nVFS octave paths populated\npeer-locator DNS TXT lookups\nws-node-adapter WSS handshake"]
    B7["Steps 12–13\nRecovery substrate\nBRC-69 key linkage revelation\nBRC-103 mutual-auth handshake\nchallenge-response recovery enrolled"]
    B8["Steps 14–15\nMetering layer\nPayment-channel FSM initialised\ncapability token spending active\nK8–K10 compliance achieved"]

    B1 --> B2 --> B3 --> B4 --> B5 --> B6 --> B7 --> B8

    style B4 fill:#fff3e0,stroke:#e65100
    style B1 fill:#e8f5e9
    style B8 fill:#e3f2fd
```

---

## 8. Identity Architecture — BRC Standards Stack

```mermaid
flowchart TB
    subgraph BRCStack["BRC Standards (BRC-42/52/69/85/94/95/100/103/108)"]
        BRC42["BRC-42 — Client-side Key Derivation\nPBKDF2 100k iterations\ndeterministic child keys under parent cert\nBKDS: (protocolID, keyID, counterparty)"]
        BRC52["BRC-52 — Certificate ID Standard\ncertId = SHA-256(JSON { public_key,\n  parent_cert_id, child_index, email, resource_id })\n33-byte secp256k1 pubkey"]
        BRC69["BRC-69 — Key Linkage Revelation\nRecovery substrate\nrecovering device reconstructs ECDH\nPlexus never holds secret"]
        BRC85["BRC-85 — PIKE Protocol\nECDH for edge establishment in identity DAG"]
        BRC94["BRC-94 — Verifiable Revelation\nSchnorr ZK proof\nedge-presence proof in attestations"]
        BRC100["BRC-100 — Signed Request Standard\nEvery cross-process message:\n  x-brc100-identitykey\n  x-brc100-nonce (replay protection)\n  x-brc100-timestamp\n  x-brc100-signature (secp256k1)\n  x-brc52-certificate"]
        BRC103["BRC-103 — Mutual Auth Handshake\nedge-creation transcript binding\nTOFU prevention in recovery"]
        BRC108["BRC-108 — Identity-Linked Token\nCapability UTXOs bound to BRC-52 cert\nSpending atomically revokes token\nLINEAR semantic resource (K1 enforced)"]
    end

    subgraph PortLayer["Port-Based DI (core/identity-ports)"]
        IP["identityPort\nregisterIdentity · resolveIdentity\nderiveChild · createEdge · querySubtree"]
        RP["recoveryPort\ninitiateRecovery · submitChallenge"]
        AP["attestationPort\nattest SPV · verifyAttestable"]
        CP["capabilityPort\ncheckCapability · tokenIsValid"]
        BIND["identityPort.bind(impl) at boot\nTest: stub adapter\nProduction: VendorSDK adapter"]
    end

    subgraph BKDS["Sovereignty — BKDS Key Derivation"]
        ROOT["hat-key root\n32-byte secret\nAES-GCM-encrypted\n~/.semantos/data/brain/hat-root.enc"]
        DERIVED["Per-cell signing key\nBRC-42 BKDS under\n(protocolID='oddjobz.cell-sign/v1',\n keyID=<cell-content-hash>,\n counterparty=<operator-domain-identity>)\nKey exists for ONE signature, then discarded"]
        THREAT["Compromise classes:\n- Single derived key → only that cell\n- Wallet KEK leak → rotate root immediately\n- hat-key root → re-derive via BRC-52 + BRC-42 recovery\n- Cell payload tamper → signature fails (keyID changes)"]
    end

    BRC42 --> BKDS
    BRC52 --> PortLayer
    BRC108 --> CP
    ROOT --> DERIVED
    DERIVED --> THREAT
```

---

## 9. Five Governance Domain Types (3rd-order structures)

```mermaid
graph TB
    subgraph Trust["Trust Domain\nFiduciaries observing themselves observing beneficiaries\nTrust deed = formal mutual-observation record\nK3 enforces domain boundary"]
        T1["Trustee hats\nBeneficiary hats\nTrust deed cell (RELEVANT)"]
    end

    subgraph Estate["Estate Domain\nOwners observing themselves managing rights bundle\nRights & obligations = multi-party recognition record"]
        E1["Owner hats\nProperty cells (RELEVANT)\nLease cells (LINEAR — one active at a time)"]
    end

    subgraph Realm["Realm Domain\nMany participants under same external legal framework\nFramework = shared observation lens"]
        R1["Participant hats\nJurisdiction-scoped cells\nCompliance cells (RELEVANT)"]
    end

    subgraph Corporate["Corporate Domain\nOfficers observing themselves under articles\nDelegation chain = who delegated what"]
        CO1["Officer hats\nBoard resolution cells\nDelegation capability tokens (BRC-108)"]
    end

    subgraph Cooperative["Cooperative Domain\nMembers observing each other via ballots & proposals\nQuorum thresholds = formal mutual-recognition criteria"]
        C1["Member hats\nProposal cells\nBallot cells (LINEAR — voted once)\nQuorum enforced at cell engine gate"]
    end

    K3["K3 — Domain Isolation\nOP_CHECKDOMAINFLAG at cell engine boundary\nDifferent governance domains cannot cross-contaminate\nDomainFlag field at header offset 24"]

    Trust --- K3
    Estate --- K3
    Realm --- K3
    Corporate --- K3
    Cooperative --- K3
```

---

## 10. MNCA as Pask Federation

```mermaid
flowchart LR
    subgraph Agent["One Pask Kernel = One MNCA Agent"]
        A1["Bounded, deterministic, generalist\nlearns via interaction\nfixed-size memory layout"]
        A2["Multiple Pravega stream subscriptions\nbilateral + regional + domain + lexicon-scoped\n= 'Multiple Neighborhood' in MNCA"]
    end

    subgraph Federation["Federation Topology"]
        F1["Node A\nPask kernel\n+ cell engine"]
        F2["Node B\nPask kernel\n+ cell engine"]
        F3["Node C\nPask kernel\n+ cell engine"]
        PV["Pravega\npask-interactions stream\ncanonical; snapshot is convenience"]
        F1 <-->|"subscribe/publish"| PV
        F2 <-->|"subscribe/publish"| PV
        F3 <-->|"subscribe/publish"| PV
    end

    subgraph Convergence["Convergence Property"]
        CV1["Overlapping stream subscriptions\n→ overlapping Pask graphs"]
        CV2["Stable threads emerge where\nlocal coherence holds across\nenough neighbourhood overlap\nconfirmed by independent kernels"]
        CV3["K9 Temporal Morphism:\nprojections across orders compose\n3rd-order federated agreement consistent\nwith 2nd-order kernels consistent\nwith 1st-order cell history"]
    end

    subgraph Mandala["Small-World Topology"]
        SW["Mandala edge-composition policy\nacross federated Pask graphs\nsubstrate-permitted, application-realised"]
    end

    Agent --> Federation
    Federation --> Convergence
    Convergence --> Mandala
```

---

## 11. Two-IR Pipeline (SIR + OIR)

The fundamental reason for two intermediate representations: SIR carries meaning, OIR carries mechanism.

```mermaid
flowchart TD
    INPUT["Surface input\nLisp text or NL-derived intent\ne.g. (check-cap SIGNING 0x02)"]

    subgraph LispParser["Lisp Parser (runtime/shell/src/lisp/)"]
        LP1["text → SExpression parse tree"]
        LP2["interpretConstraint()\nSExpression → ConstraintExpr (AST)"]
    end

    subgraph SIR["SIR Layer (core/semantos-sir/) — 2nd ORDER MEANING"]
        SIR1["compileToSIR()\nWrap ConstraintExpr with GovernanceContext:\n  trustClass: cosmetic|interpretive|authoritative\n  proofRequirement: none|attestation|formal\n  executionAuthority\n  linearity mode"]
        SIR2["JuralCategory annotation\ndeclaration · obligation · permission\nprohibition · power · condition · transfer"]
        SIR3["TaxonomyCoordinates\nwhat/how/why/where domain axes"]
        SIR4["lowerSIR() — THE TEACHBACK GATE\ntrust-tier enforcement\nD-A6 BRC-52-anchored authority\nRejection reasons:\n  - no plausible jural category\n  - taxonomy mismatch (lexicon unknown)\n  - malformed governance context\n  - identity binding failure"]
    end

    subgraph OIR["OIR / ANF Layer (core/semantos-ir/) — 1st ORDER MECHANISM"]
        OIR1["lower()\nConstraintExpr → IRProgram\nAdministrative Normal Form\neliminates evaluation-order ambiguity"]
        OIR2["IRBinding kinds (closed set):\ncomparison · logical_and/or/not · capability\ndomainCheck · timeConstraint · hostCall\ntypeHashCheck · deref"]
        OIR3["emit()\nIRProgram → Uint8Array\nopcodes 0x4C–0xD0\nalpha-equivalence: same SIR → byte-identical bytecode"]
    end

    subgraph KernelExec["Cell Engine Execution — 1st ORDER"]
        KE1["kernel_load_script(ptr, len)"]
        KE2["kernel_execute()"]
        KE3["PolicyResult { ok, stack, error?, anchorEvents? }"]
    end

    INPUT --> LispParser
    LispParser --> SIR1
    SIR1 --> SIR2 --> SIR3 --> SIR4
    SIR4 -->|"if governance valid: lowers to OIR"| OIR1
    SIR4 -->|"if invalid: structured compile-time error\n(not runtime exception)"| ERROR["Structured Error\nrecoverable explanation chain\nwalk prevStateHash back to source"]
    OIR1 --> OIR2 --> OIR3
    OIR3 --> KE1 --> KE2 --> KE3

    style SIR fill:#e3f2fd,stroke:#1565c0
    style OIR fill:#fff3e0,stroke:#e65100
```

---

## 12. BRC Standards Mapping

```mermaid
graph LR
    subgraph Identity["Identity Layer"]
        BRC42["BRC-42\nClient-side key derivation\nPBKDF2 100k + deterministic children"]
        BRC52["BRC-52\nCertificate ID standard\ncertId = SHA-256(preimage)"]
        BRC69["BRC-69\nKey linkage revelation\nrecovery without Plexus holding secret"]
        BRC85["BRC-85\nPIKE ECDH\nedge establishment in identity DAG"]
    end

    subgraph Transport["Transport & Proofs"]
        BRC94["BRC-94\nVerifiable revelation\nSchnorr ZK edge-presence proof"]
        BRC95["BRC-95\nAtomic BEEF\n0x01010101 prefix\nSingle-tx SPV envelope"]
        BRC100["BRC-100\nSigned-request standard\nEvery cross-process message envelope"]
        BRC103["BRC-103\nMutual-auth handshake\nTOFU prevention"]
    end

    subgraph Capability["Capability"]
        BRC108["BRC-108\nIdentity-Linked Token\ncapability UTXO bound to BRC-52 cert\nspending = atomic revocation\nLINEAR cell (K1 enforced)"]
    end

    subgraph SPV["SPV"]
        BRC74["BRC-74\nBUMP\nBSV Unified Merkle Path\ncontinuation cell 0x01"]
        BRC43["BRC-43\nCustom opcode range allocation\nSemantos claims 0x4C–0xD0\n(v0.01 spec says 0xC0–0xCF — reconciliation pending)"]
    end

    BRC42 --> BRC52
    BRC52 --> BRC85
    BRC52 --> BRC108
    BRC74 --> BRC95
    BRC100 --> BRC103
    BRC43 --> BRC108
```

---

## 13. Cell Patch Substrate — Hash Chain

```mermaid
flowchart LR
    subgraph Tables["Four Drizzle Tables"]
        T1["sem_objects\naggregates\n{ id, objectKind, current_state_hash,\ncurrent_version, payload, created_by_cert_id }"]
        T2["sem_object_patches\nappend-only changelog\n{ id, object_id, kind, delta,\nprev_state_hash, new_state_hash,\nlexicon, facet_id, facet_capabilities }"]
        T3["sem_object_states\noptional snapshots\nfor expensive folds"]
        T4["sem_participants\naccess list with soft-delete\n{ cert_id, role, joined_at, left_at }"]
    end

    subgraph HashChain["Per-Cell Hash Chain (K6 append-only)"]
        H0["State 0 (genesis)\nprevStateHash = 0x00×32\nstateHash_0 = SHA-256(cell_bytes)"]
        H1["State 1\nprevStateHash = stateHash_0\nstateHash_1 = SHA-256(cell_v2)"]
        HN["State N\nprevStateHash = stateHash_N-1\nstateHash_N = SHA-256(cell_vN)"]
        H0 -->|"verify: SHA-256(state_0) == state_1.prevStateHash"| H1
        H1 -->|"N SHA-256 ops to verify full chain"| HN
    end

    subgraph Concurrency["Optimistic Concurrency"]
        OC1["appendPatch(db, { expectedPrevStateHash })"]
        OC2{"rows affected?"}
        OC3["StaleStateHashError → retry with new tip"]
        OC4["Success → update current_state_hash + version"]
        OC1 --> OC2
        OC2 -->|"0 (contention)"| OC3
        OC2 -->|"1 (success)"| OC4
    end

    Tables --> HashChain
    HashChain --> Concurrency
```

---

## 14. Cross-Vertical Dispatch (Trades ↔ Property)

```mermaid
flowchart TD
    subgraph PM["Property Vertical"]
        PM1["MaintenanceRequest cell\nAFFINE — PM-internal\ncreated when tenant reports issue"]
        PM2["Owner approval gate\nbelow threshold: auto-approve\nabove threshold: notify + await RELEVANT patch"]
        PM3["PM policy evaluation:\nresponsibleParty: landlord|tenant|strata\nurgency: emergency|urgent|routine|cosmetic"]
    end

    subgraph Envelope["Dispatch Envelope — Shared Cell (RELEVANT)"]
        direction TB
        ENV_ID["Single RELEVANT cell\nsame objectId referenced by both verticals\nfaceted visibility via policy engine"]
        
        PMR["PM facet patches — RELEVANT\nproperty address · description · photos\nurgency · contacts · approval status"]
        PMA["PM facet patches — AFFINE (PM-only)\nowner details · lease info · cost expectations\ninternal notes (never leaves PM facet)"]
        
        TRR["Tradie facet patches — RELEVANT\nROM estimate · quote · schedule\ncompletion photos · invoice amount"]
        TRA["Tradie facet patches — AFFINE (tradie-only)\ncost calcs · margin notes"]
        
        TENR["Tenant facet — RELEVANT read-only\nstatus updates only"]
        OWR["Owner facet — RELEVANT approval only\napprove/reject cost above threshold"]
    end

    subgraph Tradie["Trades Vertical (OddJobTodd)"]
        T1["Job cell (LINEAR during work)\nauto-ROM fires if enough sizing info\nor tradie chats to clarify"]
        T2["Completion + invoice\npublished as RELEVANT patches\non shared envelope cell"]
    end

    subgraph Policy["Policy Engine (policyEvaluator.ts)"]
        PE1["filterState(role)\nstrips AFFINE fields\nredacts wrong-facet content"]
        PE2["checkContributionRight(role)\nread_only | contribute | approve"]
        PE3["filterStateForAi(channelPolicy)\nper-channel AI context\nPM's AI ≠ tradie's AI (different visibility)"]
    end

    subgraph Evolution["Storage Evolution V1 → V3"]
        V1["V1: Shared Postgres + webhook trigger\nboring, ships first"]
        V2["V2: Supabase Realtime push subscriptions"]
        V3["V3: BSV Overlay\ncell-tokens on tm_semantos_objects\nshard multicast · no central server\nBsvOverlayAdapter implements StorageAdapter\n→ config change, not rewrite"]
        V1 --> V2 --> V3
    end

    PM1 --> PM2 --> PM3 --> Envelope
    T1 --> T2 --> Envelope
    Envelope --> Policy
    Policy --> Evolution

    style Envelope fill:#e8f5e9,stroke:#388e3c
```

---

## 15. Federation Transport & Relay Protocol

```mermaid
sequenceDiagram
    participant A as Node A
    participant DNS as DNS TXT\n_semantos-node.<host>
    participant B as Node B
    participant PR as Pravega\npask-interactions stream
    participant Relay as cell-relay\nWebSocket room

    Note over A: peer-locator: DnsPeerLocator with TTL cache
    A->>DNS: lookup _semantos-node.<host>
    DNS-->>A: { endpoint: wss://..., bca: "..." }

    Note over A,B: ws-node-adapter
    A->>B: WSS connect
    B->>A: BRC-100 SignedBundle license handshake
    A->>B: BRC-103 mutual-auth response
    Note over A,B: CBOR envelope codec active

    Note over A,B: session-protocol MulticastAdapter
    A->>B: broadcast cell (CBOR)
    B->>B: appendPatch(db, { facetId: Node A's BCA })
    B-->>A: acknowledgement patch (RELEVANT)

    Note over A,PR: pask-interactions stream
    A->>PR: publish pask interaction event
    PR-->>B: deliver same event (6th Pravega stream)
    B->>B: pask_upsert_node (zero-copy from cell engine)
    Note over A,B: Both nodes produce bit-identical Pask graphs\n(K5-style determinism; no host clock)

    Note over A,Relay: world-sdk RelayClient
    A->>Relay: subscribe room=release.kernel.pask
    Relay-->>A: release manifest (BRC-100 SignedBundle CBOR)
    A->>A: validate parentChain + content hashes
    A->>A: fetch WASM via ContentStore (6 adapter options)
```

---

## 16. Lexicon Architecture

```mermaid
graph TB
    subgraph Built["Built Lexicons (Lean proofs + TS authority)"]
        L1["Trades\nSpeech acts in oddjobz:\nlead · estimate · quote · dispatch\nvisit · invoice · settle · message\nLean proof: tradesHeader_injective"]
        L2["Jural\nHohfeldian decomposition:\ndeclaration · obligation · power · immunity\ncondition · transfer · null"]
        L3["Calendar\nSlots · windows · conflicts · hats\n(Lean pending)"]
        L4["BRAP\nRisk scoring:\nna · nc · ns · se · sm · sf · ls · lr · lp\n(Lean pending)"]
    end

    subgraph Planned["Planned Lexicons"]
        PL1["CDM — derivatives lifecycle (ISDA)"]
        PL2["Circuit — electrical interlocks (SCADA)"]
        PL3["Property-Mgmt — leases, inspections"]
        PL4["Risk-Assessment"]
        PL5["Bills-of-Lading"]
        PL6["Control-Systems"]
    end

    subgraph Obligations["Per-Lexicon Lean Obligations"]
        OB1["headerInjective\ncategory names mutually distinguishable\n(precondition for coherent shared vocabulary)"]
        OB2["renderCard_deterministic\ncanonical card rendering"]
        OB3["renderCard_depends_only_on_render_fields\nno state escape"]
        OB4["renderCard_distinguishes_categories\ncategories separable by card"]
    end

    subgraph MergeOps["Substrate-level Lexicon Operations"]
        M1["M1 — merge: left wins on conflict"]
        M2["M2 — merge: right wins on conflict"]
        M3["M3 — merge: error on conflict"]
        M4["M4 — merge: union (additive only)"]
        D1["D1 — diff: additions only"]
        D2["D2 — diff: removals only"]
        D3["D3 — diff: full symmetric diff"]
    end

    Built --> Obligations
    Planned --> Obligations
    Obligations --> MergeOps
```

---

## 17. End-to-End: Tradie Job (Concrete Trace)

```mermaid
flowchart TD
    A["PM receives: 'tap's dripping in the kitchen'\n(tenant message — NL input)"]

    subgraph NLU["Intent Layer (runtime/intent)"]
        B["EmbeddingService → vector"]
        C["TaxonomyCoherence → services.trades.plumbing"]
        D["confidence ≥ threshold → intent confirmed"]
        B --> C --> D
    end

    subgraph SemObj["Cell Created (phase 0x01 parse → 0x02 ast)"]
        E["MaintenanceRequest cell\nlinearity: AFFINE\nobjectKind = maintenance_request\ncreated_by_cert_id = PM's BRC-52 certId\nstateHash_0 = SHA-256(genesis cell)"]
    end

    subgraph SIR_OIR["Policy Compile (SIR → OIR → bytecode)"]
        F["Lisp: (check-cap ATTESTATION 0x05)"]
        G["compileToSIR(): JuralCategory=permission, trustClass=interpretive"]
        H["lowerSIR(): governance valid → emit OIR"]
        I["emit() → Uint8Array opcodes"]
        J["kernel_execute() → PolicyResult { ok: true }"]
        F --> G --> H --> I --> J
    end

    subgraph Dispatch["Cross-Vertical Dispatch (K6 hash chain)"]
        K["Dispatch Envelope cell (RELEVANT)\nappendPatch({ kind: 'dispatch',\n  expectedPrevStateHash: stateHash_0,\n  facetId: PM's BCA })\nnew_state_hash = SHA-256(stateHash_0 + delta)"]
    end

    subgraph BSV["On-Chain Anchoring (chain-broadcast)"]
        L["CellTxBuilder: envelope cell → BSV tx"]
        M["MapiBroadcaster: broadcast → txid"]
        N["BeefStore: BEEF proof persisted (BRC-95)"]
        O["Envelope cell anchored on BSV mainnet\nSPV verifiable via BRC-74 BUMP"]
        L --> M --> N --> O
    end

    subgraph Completion["Job Completion"]
        P["Tradie patches: completion photos + invoice\nfacetId = Tradie's BRC-52 certId\nlinearity: RELEVANT (both sides can read)"]
        Q["Owner approves cost (RELEVANT patch)\nor rejects → back to approval queue"]
        R["MaintenanceRequest → invoiced → closed\nFull audit trail: walk prevStateHash chain\nfrom outcome back to source (phase 0x07 → 0x00)"]
        P --> Q --> R
    end

    A --> NLU --> SemObj --> SIR_OIR --> Dispatch --> BSV --> Completion
```

---

*All diagrams grounded in `docs/canon/` as the source of truth.*  
*Canonical terminology enforced: cell (not SemanticObject), hat (not facet), Helm (not Loom), governance domain (not trust domain).*  
*Kernel invariants K1–K10: `proofs/lean/Semantos/Theorems/` + `docs/canon/theorems.yml`.*
