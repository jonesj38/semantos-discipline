---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.658224+00:00
---

# Semantos-Core — PRD & Phase Prompts

## Two Tracks, Two Repos

Semantos has two implementation tracks:

| Track | Repo | Phases | What |
|-------|------|--------|------|
| **Zig/WASM Cell Engine** | `semantos` | 0–7 (+ embedded, CI/CD) | 256-byte cell packing, 2-PDA stack machine, linearity enforcement, BCA derivation, SPV, octave memory |
| **TypeScript Loom** | `semantos-core` (this repo) | 8.5+ | Renderer-agnostic services, React loom, identity, taxonomy governance, reputation, conversation flows |

The Zig-track PRDs (Phases 0–7, embedded target, CI/CD benchmarks) live in the `semantos` repo. This repo contains only the loom-track phases and shared reference documents.

## Document Structure

```
docs/prd/
├── README.md                              ← This file
├── SHOMEE-EXTRACTION-AUDIT-AND-ROADMAP.md ← Master audit: shomee→semantos mapping, full phase roadmap
├── COMMERCIAL-CONTEXT.md                  ← Business model → phase mapping
│
│  Zig/WASM Reference (shared, not executed from this repo)
├── SEMANTOS_ZIG_WASM_PRD.md              ← Master PRD: architecture, source registry, constants
├── PHASE-0-SCAFFOLDING.md                ← Constants, types, Zig scaffold
├── PHASE-0-PROMPT.md
├── PHASE-1-CELL-PACKING.md               ← 1KB cell serialisation
├── PHASE-1-PROMPT.md
├── PHASE-2-BCA-DERIVATION.md             ← Bitcoin-Certified Address IPv6
├── PHASE-2-PROMPT.md
├── PHASE-3-2PDA-CORE.md                  ← Dual-stack engine + opcodes
├── PHASE-3-PROMPT.md
├── PHASE-3-ERRATA-FIX-PROMPT.md
├── PHASE-4-PLEXUS-OPCODES.md             ← Custom opcodes + linearity
├── PHASE-4-PROMPT.md
├── PHASE-5-BEEF-BUMP-CAPABILITY.md        ← SPV + capability tokens
├── PHASE-5-PROMPT.md
├── PHASE-6-OCTAVE-MEMORY.md              ← Hierarchical cell addressing
├── PHASE-6-OCTAVE-PROMPT.md
├── PHASE-6-PROMPT.md
├── PHASE-6-TS-BINDINGS.md
├── PHASE-6-ERRATA.md
├── PHASE-7-BINDINGS.md                   ← Bun/browser bindings
├── PHASE-7-PROMPT.md
├── PHASE-7-ERRATA.md
│
│  Loom Track (EXECUTE THESE from this repo)
├── PHASE-8.5-IDENTITY-PLANE.md           ← Identity + facets + selective disclosure
├── PHASE-8.5-PROMPT.md                   ← Paste into fresh session
├── PHASE-9-PROMPT.md                     ← Intent classification + flow routing + IdentityStore with GIP
├── PHASE-9.5-PROMPT.md                   ← Publication + visibility + governance types
├── PHASE-10-PROMPT.md                    ← Three-axis taxonomy governance + reputation
├── PHASE-13-INTENT-TAXONOMY.md          ← Hierarchical intent taxonomy PRD
├── PHASE-13-PROMPT.md                   ← Paste into fresh session
│
│  Plexus Integration Track (Phases 14–18)
├── PLEXUS-INTEGRATION-MAP.md            ← Architecture reference: mappings, adapter interface, salvage, grafts
├── PHASE-14-PLEXUS-ADAPTER.md           ← PlexusAdapter + Stub PRD
├── PHASE-14-PROMPT.md                   ← Paste into fresh session
├── PHASE-15-PLEXUS-REAL-SDK.md          ← Production Plexus SDK PRD
├── PHASE-15-PROMPT.md                   ← Paste into fresh session
├── PHASE-16-PLEXUS-EDGES.md             ← Edge + Capability integration PRD
├── PHASE-16-PROMPT.md                   ← Paste into fresh session
├── PHASE-17-PLEXUS-TRANSFER.md          ← Transfer + Recovery PRD
├── PHASE-17-PROMPT.md                   ← Paste into fresh session
├── PHASE-18-METERING-CONTROL-PLANE.md   ← Channels as governed objects PRD
├── PHASE-18-PROMPT.md                   ← Paste into fresh session
│
│  Semantic Shell Track (Phases 19–21) — runs parallel to Plexus track
├── SEMANTIC-SHELL-ARCHITECTURE.md       ← Architecture reference: 4-layer pipeline, compression gradient
├── PHASE-19-SEMANTIC-SHELL.md           ← CLI scaffold, command grammar, formatters PRD
├── PHASE-19-PROMPT.md                   ← Paste into fresh session
├── PHASE-19.5-SHELL-PLEXUS-AUTH.md      ← Shell identity + capability auth PRD
├── PHASE-19.5-PROMPT.md                 ← Paste into fresh session
├── PHASE-20-TMUX-WORKBENCH.md           ← tmux operator console + VFS PRD
├── PHASE-20-PROMPT.md                   ← Paste into fresh session
├── PHASE-21-LISP-AXIOM-COMPILER.md      ← Policy DSL compiler (Lisp → Forth) PRD
├── PHASE-21-PROMPT.md                   ← Paste into fresh session
│
│  Platform Architecture (cross-vertical product context)
├── PLATFORM-ARCHITECTURE.md           ← Three products, one kernel: OJT + Property Mgmt + Dispatch Envelope
│
│  Kernel Isolation Track (Phases 26A–26G) — sovereign node deployment
├── PHASE-26-KERNEL-ISOLATION-MASTER.md  ← Master PRD: four adapter interfaces, node architecture
├── PHASE-26A-IDENTITY-EXTRACTION.md     ← Extract IdentityAdapter to protocol-types
├── PHASE-26A-PROMPT.md                  ← Paste into fresh session
├── PHASE-26B-LOCAL-IDENTITY.md          ← Offline capability validation (LocalIdentityAdapter)
├── PHASE-26B-PROMPT.md                  ← Paste into fresh session
├── PHASE-26C-ANCHOR-ADAPTER.md          ← AnchorAdapter interface + BSV implementation
├── PHASE-26C-PROMPT.md                  ← Paste into fresh session
├── PHASE-26D-NETWORK-ADAPTER.md         ← NetworkAdapter unifying overlay clients
├── PHASE-26D-PROMPT.md                  ← Paste into fresh session
├── PHASE-26E-NODE-BOOTSTRAP.md          ← NodeConfig + createNode() + self-object
├── PHASE-26E-PROMPT.md                  ← Paste into fresh session
├── PHASE-26F-VERTICAL-LOADING.md        ← Filesystem-based extension loading (pre-rename)
├── PHASE-26F-PROMPT.md                  ← Paste into fresh session
├── PHASE-26H-EXTENSION-RENAME.md       ← Vertical → Extension terminology alignment
├── PHASE-26H-PROMPT.md                  ← Paste into fresh session
├── PHASE-26G-NODE-PACKAGING.md          ← Docker + install.sh + CLI + admin API
├── PHASE-26G-PROMPT.md                  ← Paste into fresh session
│
│  Multi-Target FFI Track (Phases 30A–30J) — mobile FFI + multi-target compilation
├── PHASE-30-FFI-MASTER.md              ← Master PRD: C ABI surface, three targets, mobile integration
├── PHASE-30A-C-ABI-HEADER.md           ← C header + core FFI functions (init, shutdown, cell ops)
├── PHASE-30A-PROMPT.md                  ← Paste into fresh session
├── PHASE-30B-ADAPTER-CALLBACKS.md       ← Callback registration + storage callbacks
├── PHASE-30B-PROMPT.md                  ← Paste into fresh session
├── PHASE-30C-CAPABILITY-FFI.md          ← Capability check + LINEAR consume FFI
├── PHASE-30C-PROMPT.md                  ← Paste into fresh session
├── PHASE-30D-ANCHOR-FFI.md              ← Anchor batch + verify FFI
├── PHASE-30D-PROMPT.md                  ← Paste into fresh session
├── PHASE-30E-WASM-TARGET.md             ← WASM target + host import bindings + JS host
├── PHASE-30E-PROMPT.md                  ← Paste into fresh session
├── PHASE-30F-XCFRAMEWORK-SWIFT.md       ← XCFramework + Swift SDK + demo app
├── PHASE-30F-PROMPT.md                  ← Paste into fresh session
├── PHASE-30G-DART-FFI-PACKAGE.md        ← semantos_ffi Dart package + Flutter demo
├── PHASE-30G-PROMPT.md                  ← Paste into fresh session
├── PHASE-30H-CI-PIPELINE.md             ← GitHub Actions 7-target build matrix
├── PHASE-30H-PROMPT.md                  ← Paste into fresh session
├── PHASE-30I-OFFLINE-QUEUE.md           ← Offline queue + replay + conflict resolution
├── PHASE-30I-PROMPT.md                  ← Paste into fresh session
├── PHASE-30J-DOCKER-MULTIARCH.md        ← Docker multi-arch + node bootstrap
├── PHASE-30J-PROMPT.md                  ← Paste into fresh session
├── PHASE-30-ERRATA.md                   ← Errata verification template for FFI track
│
│  BSV Browser Mobile Client Track (Phases 31A–31F)
├── PHASE-31-MOBILE-CLIENT-MASTER.md    ← Master PRD: BSV Browser integration, Plexus WAB, mobile shell
├── PHASE-31A-PLEXUS-WAB.md             ← Plexus WAB service (replaces Babbage WAB in BSV Browser)
├── PHASE-31B-SHELL-WEB-APP.md          ← Semantos shell SPA for BSV Browser WebView
```

## How to Use These Documents

### For AI Implementation Sessions

Paste one `PHASE-N-PROMPT.md` into a fresh Claude Code session. Each prompt is self-contained:

1. **Context preamble** describes project state after the previous phase
2. **CRITICAL: READ THESE FILES FIRST** lists exact files to read, in order
3. **Anti-bullshit rules** prevent common AI failure modes (stubs, mocks, easy tests, etc.)
4. **Steps with gate tests** define deliverables and pass/fail criteria
5. **Completion criteria** is the explicit checklist
6. **Post-phase errata sprint** — mandatory adversarial review in a fresh session

Start with Phase 8.5. Do not proceed to Phase N+1 until Phase N's gate tests pass AND the errata sprint is complete.

**Critical anti-pattern**: AI agents adjust tests to match broken output instead of fixing code. Every prompt explicitly forbids this.

### For Human Review

The audit and roadmap (`SHOMEE-EXTRACTION-AUDIT-AND-ROADMAP.md`) contains the full extraction mapping from shomee-alpha to semantos-core, domain analysis, and phase-by-phase deliverables with completion criteria.

## Loom Track Dependencies

```
Phase 8.5 ──→ Phase 9 ──→ Phase 9.5 ──→ Phase 10 ──→ Phase 11 ──→ Phase 12 ──→ Phase 13
identity      services     visibility    taxonomy      formal        impl         intent
plane         + flows      + governance  + reputation  verification  bridge       taxonomy

Phase 14 ──→ Phase 15 ──→ Phase 16 ──→ Phase 17 ──→ Phase 18
plexus        plexus       edges +      transfer +   metering
adapter       real SDK     capabilities recovery     control plane

Phase 19 ──→ Phase 19.5 ──→ Phase 20 ──→ Phase 21
semantic      shell +        tmux +       lisp axiom
shell CLI     plexus auth    VFS          compiler

(Shell track runs parallel to Plexus track. Phase 19 needs Phase 9.
 Phase 19.5 needs Phase 14. Phase 21 needs Phase 12 cell engine bridge.)

Phase 26A ──→ 26B ──→ 26E ──→ 26F ──→ 26H ──→ 26G
  │                    ↑
  ├──→ 26C ────────────┤
  │                    │
  └──→ 26D ────────────┘
kernel       local      node       extension   terminology  node
isolation    identity   bootstrap  loading     alignment    packaging
             anchor     (all 4     filesystem  vertical→    Docker
             network    adapters)  extensions  extension    install.sh

(Kernel isolation track needs Phase 25A–D. Phase 26A is the entry point.
 26B/26C/26D run in parallel after 26A. 26E needs all three. 26F/26H/26G are serial.
 26H renames vertical→extension before 26G ships the public CLI.)

Phase 30A ──→ 30B ──→ 30C ──→ 30D ──→ 30E (WASM)
                                 │──→ 30F (Swift/XCFramework)  ──→ 30H (CI)
                                 │──→ 30G (Dart/Flutter)       ──→ 30I (offline queue)
                                 └──→ 30J (Docker multi-arch)
C ABI       adapter   capability  anchor   ┌─────────────────┐
header      callbacks  + LINEAR    FFI     │ 30E/F/G parallel │
                                           │ 30H needs all 3  │
                                           └─────────────────┘

(FFI track needs Phase 25A–D + Phase 26A–26C. Phase 30A is the entry point.
 30A→30B→30C→30D is the serial core. 30E/30F/30G run in parallel after 30D.
 30H needs all three platform phases. 30I needs 30F or 30G. 30J needs 30D + 26E.
 Critical path: ~7–8 weeks from 30A start.)

Phase 31A ──→ 31B ──→ 31C
  │             │──→ 31D
  │             │──→ 31F
  └──→ 31E ────┘
Plexus       shell     node admin    402 micro-    BYOK LLM
WAB          web app   bridge        payments      integration
service      (WebView)               (CWI)         (secure key)
                        biometric
                        + secure
                        storage

(Mobile client track needs Phase 26B + 26G. Phase 31A is the entry point.
 31B needs 31A. 31C/31D/31F parallel after 31B. 31E parallel with 31B after 31A.
 31F needs 31E for secure API key storage. Critical path: ~4–5 weeks from 31A start.)
```

Each phase merge is followed by a mandatory errata sprint (see `docs/BRANCHING-AND-CI-POLICY.md`).

## Key Design Decisions (Loom Track)

| Decision | Rationale |
|----------|-----------|
| Renderer agnosticism | Services in plain TypeScript. React wraps them. Game engines, CLIs subscribe directly. |
| Conversation-driven flows | All user actions (create, publish, dispute, vote) go through FlowRunner, not bespoke UIs. |
| Three-axis taxonomy | WHAT/HOW/WHY as governed LTREEs, not one flat tree. Object types are coordinate tuples. |
| Six-axis coordinate system | Three semantic (WHAT/HOW/WHY) + three optional context (WHERE/WHEN/WHO). Zero cell engine changes. |
| GIP identity model | Certificate-based with selective disclosure (disclosed/hashed split), delta graph, trait-derived keys. |
| Reputation as materialized view | Pure function over evidence chains, not a service. Family of views: global, contextual, ZK-provable. |
| Taxonomy nodes as semantic objects | Recursive: type space governed by taxonomy objects with patches, governance, schema children. |
| Governance via existing primitives | Disputes, ballots, stakes are ordinary semantic objects with ordinary flows. No GovernanceEngine. |
| Plexus via adapter interface | Loom never imports `@plexus/*` directly. PlexusAdapter interface with stub/real implementations. Containment boundary enforced by CI. |
| Semantic shell as second renderer | CLI/REPL/API consuming same services as React loom. Not a separate backend. Unix composability via structured output. |
| Compression gradient | Natural language → CLI → Lisp → Forth → cell execution. Users enter at their expertise level. Same executable form regardless. |
| Four adapter boundaries | Storage, Identity, Anchor, Network as pluggable interfaces. Node = four adapter choices + vertical config. Same kernel everywhere. |
| Node as semantic object | Running node creates a RELEVANT self-object. Admin manages node via conversational shell scoped to that object. |
| Extensions as config | Domain knowledge (trades, sovereignty, CDM) loads from filesystem as extensions, not compiled in. `semantos install extension trades` pattern. |

## Supporting Documents

| Document | Location |
|----------|----------|
| Branching & CI policy | `docs/BRANCHING-AND-CI-POLICY.md` |
| Taxonomy seed design (six-axis coordinate system) | `docs/TAXONOMY-SEED-DESIGN.md` |
| GIP types | `src/types/gip.ts` |
| Kernel types | `src/types/semantic-objects.ts` |
| Kernel adapter spec (Word doc) | `semantos-kernel-adapter-spec.docx` (project root) |
| Kernel isolation master PRD | `docs/prd/PHASE-26-KERNEL-ISOLATION-MASTER.md` |
| Platform architecture (3 products) | `docs/prd/PLATFORM-ARCHITECTURE.md` |
| Mobile client master PRD | `docs/prd/PHASE-31-MOBILE-CLIENT-MASTER.md` |
