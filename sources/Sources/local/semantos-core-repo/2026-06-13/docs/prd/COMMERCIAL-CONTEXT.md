---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/COMMERCIAL-CONTEXT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.702782+00:00
---

# Commercial Context — Why Each Phase Matters

This document maps the Oddjobz/Semantos business model to the technical phases. It exists so that implementation decisions can be evaluated against commercial outcomes, not just technical correctness.

---

## The Business Model

**One-time platform purchase** ($500). No SaaS subscription. Tradie owns it outright.

**Extension marketplace**. One-time purchases ($29-$79). REA module, tool tracking, route optimisation, Xero integration, messaging adapters (WhatsApp, Google Business Messages). Third parties can build and sell — 70/30 split.

**RaaS** ($20/year). Sovereign identity (BRC-52), key recovery, 50c bootstrap float that seeds the first payment channel. Bundled free in year one with platform purchase.

**Plexus Node** (upsell, ~$15-20/month equivalent via streaming). Always-on cloud endpoint: webhook receiver for messaging, persistent message store, cloud drive, BSV anchoring, local SPV via block headers. Not a subscription to software — infrastructure the tradie rents, identity-integrated.

**Resource streaming via MFP**. No fixed plans. Storage, compute, and bandwidth streamed through BSV micropayment channels. Wholesale cost + margin. The tradie pays exactly for what they use. Quiet winter months cost almost nothing. Busy months scale proportionally.

**Bring your own keys**. OpenRouter for AI inference (tradie's own API key, their own model choice). WhatsApp/Google/Twilio for messaging (tradie's own credentials). The platform is never in the billing relationship for AI or messaging costs.

---

## Phase-to-Revenue Mapping

### Phase 0: Scaffolding
**Commercial relevance**: None directly. Foundation for everything else. If constants or types are wrong, every subsequent phase inherits the error.

### Phase 1: Cell Packing
**Commercial relevance**: The node stores all business data as 1KB semantic cells. Job intake records, quotes, invoices, customer records — all packed into cells. Bit-identical packing between Zig (node) and TypeScript (browser portal) means the tradie sees the same data regardless of where they access it.

**Revenue connection**: Platform purchase ($500). The cell packer is what makes the data portable and verifiable.

### Phase 2: BCA Derivation
**Commercial relevance**: Every object in the cloud drive gets a BCA IPv6 address derived from the tradie's public key. Tools in the Makita integration have BCA addresses. Job sites have BCA addresses. The tradie's business identity resolves to their node.

**Revenue connection**: Extension marketplace (tool tracking, asset management). Plexus Node (always-on BCA endpoint).

### Phase 3: 2-PDA and Linearity Enforcement
**Commercial relevance**: This is what makes the data model trustworthy.

- **LINEAR** objects (messages, job intake records) are consumed on read — the tradie knows nobody has silently duplicated their customer's message. A quote sent to a customer is a LINEAR object: it exists once, the customer accepts or rejects it, and the outcome is deterministic.
- **RELEVANT** objects (cloud drive files, reference documents) are always accessible and copyable — job photos, compliance certificates, insurance docs.
- **AFFINE** objects (payment tokens, capability grants) can be used or discarded but never duplicated.

**Revenue connection**: Platform purchase ($500). This is core differentiator — "own your business data with cryptographic guarantees" is a different pitch to "we store your stuff in our cloud."

### Phase 4: Script Evaluation
**Commercial relevance**: Capability token verification. The REA extension needs to verify that a property manager has the right to access tenant records. The Makita integration needs to verify tool recall authorisations. Script evaluation is the enforcement mechanism.

**Revenue connection**: Extension marketplace. Extensions that need access control depend on script evaluation.

### Phase 5: BEEF/BUMP and Capability Tokens
**Commercial relevance**: SPV verification on the node. The tradie's node validates its own transactions against block headers without trusting a third party. BEEF envelopes prove that a job completion record is anchored on-chain. Capability tokens gate extension features.

**Revenue connection**: Plexus Node ($15-20/month). The node running its own SPV is the "genuinely sovereign" pitch. Also: RaaS ($20/year) — recovery requires verifying the identity certificate chain via SPV.

### Phase 6: TypeScript Bindings
**Commercial relevance**: The browser portal (customer-facing intake, tradie dashboard) calls the same cell engine via WASM. The Bun server running the node loads the same binary. One engine, two deployment targets, identical behaviour.

**Revenue connection**: Platform purchase ($500). The browser experience and the server experience are the same engine — no sync bugs, no format mismatches.

### Phase 7: Metering and Settlement Integration
**Commercial relevance**: This is the MFP payment channel that streams resources to the node. Storage consumed → micropayment streamed. Compute used → micropayment streamed. The 50c RaaS bootstrap float seeds this channel. Auto-topup when balance drops.

**Revenue connection**: Plexus Node (streaming revenue). This is the recurring revenue engine — not a subscription, but metered consumption with margin. Quiet months cost the tradie almost nothing. Busy months generate proportional revenue.

### Phase 8: Embedded Target
**Commercial relevance**: A tradie can run their node on a Raspberry Pi at home instead of paying for cloud infrastructure. Or an edge device at a job site. Or IoT-connected tools reporting status back to the node.

**Revenue connection**: Platform purchase ($500) — the "own it completely" pitch extends to the hardware. Also opens the door for tool manufacturers (Makita, DeWalt) to embed the cell engine in connected tools.

---

## The Node Architecture (What Uses the Cell Engine)

```
Plexus Node (customer's sovereign cloud)
├── Webhook receiver        → routes WhatsApp/Google Messages to intake pipeline
├── Message store           → LINEAR semantic cells (consumed on read)
├── Cloud drive             → RELEVANT semantic cells (BCA addressed)
├── BSV anchor service      → BEEF envelopes, BUMP proofs (Phase 5)
├── Block headers service   → local SPV (INFRA:HEADERS)
├── MFP payment channels    → resource streaming (Phase 7, CashLanes patterns)
└── Extension runtime       → capability-gated features (Phase 4/5)
```

The cell engine is the data layer for all of this. It doesn't know about tradies or WhatsApp or Makita. It packs cells, enforces linearity, derives BCAs, verifies proofs, and evaluates scripts. The application layer above it gives those primitives commercial meaning.

---

## Upsell Sequence (Natural Progression)

```
1. Buy platform ($500)
   → Uses: Phase 1 (cells), Phase 3 (linearity), Phase 6 (browser WASM)

2. Activate RaaS ($20/year, first year bundled)
   → Uses: Phase 2 (BCA identity), Phase 5 (SPV for cert chain)
   → Seeds: 50c payment channel float

3. Wire up messaging (bring own key)
   → Uses: MessagingAdapter interface (application layer, not cell engine)
   → Needs: webhook ingress → motivates node upgrade

4. Upgrade to Plexus Node (~$15-20/month streamed)
   → Uses: Phase 7 (MFP metering), Phase 5 (local SPV), Phase 8 (if self-hosted)
   → Revenue: streaming margin on storage/compute/bandwidth

5. Buy extensions as needed (one-time, marketplace)
   → Uses: Phase 4 (script eval for access control), Phase 5 (capability tokens)
```

Each step solves a problem the tradie is already experiencing from using the previous step. It's not manufactured upselling — it's natural progression as usage grows.

---

## Script IDE and Natural Language Policy Compiler

A partner is building a Bitcoin Script IDE with stack tracing, debugging, macro storage, and an AI agent that writes Script. The cell engine is the natural backend for this IDE — the same WASM binary that runs on the node and in the browser becomes the IDE's script simulator.

### What the cell engine already provides

The Phase 3 WASM exports are most of a simulator API:

```
kernel_load_script    → load locking script
kernel_load_unlock    → load unlock script
kernel_execute        → run to completion
kernel_stack_depth    → inspect main stack
kernel_stack_peek     → read stack values
kernel_get_opcount    → execution cost
kernel_get_error      → error state
```

Phase 3 should additionally export debug/stepping functions for the IDE use case:

```
kernel_step           → execute one opcode, return (IDE inspects state between steps)
kernel_get_pc         → current program counter
kernel_alt_stack_depth + kernel_alt_stack_peek → alt stack inspection
kernel_get_current_op → next opcode about to execute
```

These are 4-5 additional exports, not a separate product. They land naturally in Phase 3 when the 2-PDA and opcode dispatch are implemented.

### The compilation pipeline

The IDE is the middle layer of a larger pipeline that connects natural language business rules to on-chain enforcement:

```
Natural language          "Only the homeowner can approve repairs over $500"
        ↓  (LLM extraction)
Lisp axioms               (policy :subject homeowner
                                  :action approve-repair
                                  :constraint (> amount 500)
                                  :linearity LINEAR)
        ↓  (Lisp → Script compiler, DOC:PIPELINE / DOC:LINEAR-COMPILER)
Bitcoin Script            OP_DUP OP_CHECKDOMAINFLAG 0x01
                          OP_SWAP OP_PUSH 500 OP_GREATERTHAN
                          OP_BOOLAND OP_CHECKLINEAR
        ↓  (packed into capability token cell)
Semantic cell             type=CAPABILITY, linearity=LINEAR, payload=script_bytes
        ↓  (cell engine evaluates at runtime)
Result                    kernel_execute → TRUE/FALSE
```

Each layer has a debugging surface:

- **Natural language**: the customer-facing interface. Policy violations trace back to plain English — "This failed because the requester isn't flagged as homeowner on this property."
- **Lisp axioms**: the formal policy representation. Editable by the AI agent or by a power user. The axiom structure maps directly to semantic types (`DOC:LISP`).
- **Bitcoin Script**: the IDE layer. Stack trace, breakpoints, macro inspection. The friend's IDE lives here.
- **Cell engine**: the execution layer. WASM exports, deterministic evaluation, same engine everywhere.

### What already exists in the codebase

The pipeline isn't theoretical — pieces already exist:

- `DOC:PIPELINE` — "SOURCE → LEXER → PARSER → AST → TYPE CHECK → OPTIMISE → CODEGEN → RUNTIME"
- `DOC:LISP` — "symbolic composition → concatenative assembly → stack operations"
- `DOC:LINEAR-COMPILER` — "linearity-aware macro compilation with resource signatures on macros"
- `KERNEL:TRADES-POLICY` — 4 policy templates (homeowner, short/long-term tenant, landlord) already defining business rules
- `KERNEL:RISK-POLICY` — 5 risk policy templates
- `KERNEL:POLICY` — `evaluateChannelPolicy()`, `checkContributionRight()` — runtime policy evaluation in TypeScript

The policy templates in the trades and risk extensions are natural language business rules evaluated by TypeScript today. The compilation pipeline replaces that TypeScript evaluation with on-chain Script enforcement — same policies, cryptographic guarantees instead of application-layer trust.

### Commercial model for the IDE

The IDE is a natural extension marketplace product. Possible structures:

- **Free IDE, paid macros**: the base IDE ships free (drives adoption), Craig macro packs and Plexus opcode libraries are marketplace extensions
- **IDE as developer tool**: $99-199 one-time for the full IDE with AI agent, targets developers building extensions for the Oddjobz platform
- **Revenue share**: scripts deployed to production nodes generate a per-deployment fee split between the script author and the platform

The IDE also serves as the testing surface for extension developers — they write a capability token script, debug it in the IDE against the same WASM engine that will evaluate it in production, and publish it to the marketplace.

### What this means for the phase plans

No phase changes needed. The cell engine phases already build everything the IDE needs:

- Phase 3 (2-PDA) → script execution, the simulator backend
- Phase 4 (Plexus opcodes) → custom opcodes the IDE's macros compile to
- Phase 5 (capability tokens) → the object type that carries compiled scripts

The stepping/debug exports (4-5 functions) should be added to Phase 3's deliverables as they're trivial additions to the opcode dispatch loop. The Lisp compilation layer and natural language interface are separate products that consume the cell engine — they don't change it.

---

## What This Means for Implementation Priorities

The phase ordering is already correct for this commercial model. Phase 0-3 delivers the platform purchase value. Phase 4-5 enables the extension marketplace and the Script IDE. Phase 6 bridges server and browser. Phase 7 enables the node revenue stream. Phase 8 enables self-hosting.

The debug exports for the IDE should be added to Phase 3's deliverable list. No other phase changes needed. This document exists for context, not scope adjustment.
