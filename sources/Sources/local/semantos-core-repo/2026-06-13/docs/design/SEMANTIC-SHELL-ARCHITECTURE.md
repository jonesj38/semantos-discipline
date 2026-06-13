---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/SEMANTIC-SHELL-ARCHITECTURE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.733903+00:00
---

# The Semantic Shell: Lisp, Unix, Conversation, and the Compilation Pipeline

> The conversation UI, the CLI, and the Lisp axiom layer are not three
> separate systems. They are three compression levels of the same intent.
>
> A user says "I need a plumber for a leaking tap."
> The classifier resolves it to `create trades.job.plumbing --urgency=high`.
> The axiom compiler renders it as `(create :type trades.job.plumbing :urgency high :linearity AFFINE)`.
> The Forth kernel executes `S" trades.job.plumbing" AFFINE THING`.
> The cell engine packs a 256-byte header.
>
> Same intent. Four representations. Each one is inspectable, composable,
> and deterministic from the previous one.
>
> This document defines the architecture that unifies them.

---

## The Core Thesis

**Conversation is for discovery. CLI is for commitment. Lisp is for composition. Forth is for execution.**

The system has one semantic routing layer. It has multiple frontends that
address that routing layer at different levels of precision:

| Input Style | Precision | Who Uses It | Example |
|---|---|---|---|
| Natural language | Ambiguous | End users, onboarding | "I need a plumber for a leaking tap" |
| Guided command | Resolved | Power users, operators | `create trades.job.plumbing` |
| Explicit action | Fully specified | Scripts, automation | `flow start new-job-intake --category plumbing --urgency high` |
| Lisp axiom | Formally verified | Policy authors, auditors | `(policy :subject homeowner :action approve-repair :constraint (> amount 500))` |
| Forth word | Stack-executable | Cell engine, on-chain | `500 AMOUNT-GT HOMEOWNER-FLAG CHECK-DOMAIN BOOLAND` |

All five forms resolve to the same semantic operation on the same object
through the same flow registry and the same capability checks.

---

## Architecture: Four Layers, One Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│  CONVERSATION / UI                                              │
│  React loom, ConversationPanel, CommandBar                 │
│  Input: natural language, slash commands, canvas actions        │
│  Output: classified intent + extracted parameters               │
├─────────────────────────────────────────────────────────────────┤
│  SEMANTIC SHELL                                                 │
│  CLI / tmux / REPL / API                                        │
│  Input: resolved commands, piped object streams, Lisp exprs     │
│  Output: transition requests against the object store           │
├─────────────────────────────────────────────────────────────────┤
│  AXIOM LAYER (Lisp → Forth)                                     │
│  Macro expansion, policy compilation, constraint generation     │
│  Input: s-expressions (policies, contracts, governance rules)   │
│  Output: Forth words / capability token scripts                 │
├─────────────────────────────────────────────────────────────────┤
│  EXECUTION LAYER (Forth / Cell Engine / WASM)                   │
│  2-PDA evaluation, cell packing, linearity enforcement          │
│  Input: Forth words, opcodes, cell headers                      │
│  Output: state transitions, evidence patches, proofs            │
└─────────────────────────────────────────────────────────────────┘
```

Each layer has a clean API boundary. Each layer is independently
inspectable. Each layer preserves the semantic invariants of the layers
above it.

---

## Layer 1: Conversation → Intent

This already exists (Phase 9). The loom has:

- `IntentClassifier` — LLM-driven classification via OpenRouter
- `FlowRegistry` — maps intents to multi-step flows
- `FlowRunner` — executes flow steps, collects data, validates
- `ConversationPanel` — chat UI on action-type cards
- `CommandBar` — typed command input in the canvas

The conversation layer's job is to compress ambiguity into a resolved
intent. Once the intent is classified and the parameters extracted, it
becomes a structured command.

```
"I need a plumber for a leaking tap"
  ↓ IntentClassifier
{ intent: "create", type: "trades.job.plumbing", params: { issue: "leaking tap" } }
  ↓ FlowRegistry
flow: "new-job-intake" (3 steps: urgency, location, description)
  ↓ FlowRunner
{ type: "trades.job.plumbing", urgency: "high", location: "northcote", description: "leaking tap in bathroom" }
```

**The output of this layer is identical to a CLI command.**

---

## Layer 2: The Semantic Shell

### What It Is

A command execution environment where semantic objects are first-class
citizens. Think `bash` but typed, evidence-bearing, and capability-aware.

The semantic shell can be hosted in:
- The loom UI (conversation mode → shell mode transition)
- A terminal (standalone CLI binary)
- A tmux session (multi-pane operator console)
- An API (headless, for automation and agents)

### The Command Grammar

Every shell command follows one pattern:

```
semantos <verb> [<type-path>] [--flags] [<object-id>]
```

Verbs map to the universal operation set:

| Verb | Operation | Linearity Effect |
|---|---|---|
| `new` | Create object | Allocates cell |
| `patch` | Apply mutation | Appends to evidence chain |
| `transition` | Change state | Linearity/visibility/commerce phase |
| `inspect` | Read object | No mutation |
| `trace` | View evidence chain | No mutation |
| `verify` | Check proofs | No mutation |
| `sign` | Attach facet signature | Appends auth patch |
| `publish` | Visibility: draft→published | AFFINE-only |
| `revoke` | Visibility: published→revoked | AFFINE-only |
| `stake` | Lock value against object | Creates LINEAR token |
| `vote` | Cast ballot | Requires govern capability |
| `dispute` | File dispute against object | Creates AFFINE dispute |
| `transfer` | Change ownership | Triggers Plexus Transfer Domain |
| `flow` | Start/advance a multi-step flow | Delegates to FlowRunner |
| `eval` | Evaluate a Lisp expression | Compiles + executes |

### Unix Composability

The shell outputs structured data (JSON by default, cell bytes with `--raw`).
This means Unix pipes work naturally:

```bash
# Find all disputed jobs and inspect them
semantos list --type governance.dispute --status open | \
  jq '.[].targetObjectId' | \
  xargs -I{} semantos inspect {}

# Export an object's evidence chain as CSV
semantos trace job-1774 --format csv > evidence.csv

# Verify all objects in a directory
find ./exports -name "*.cell" | xargs semantos verify

# Count objects by type
semantos list --format json | jq 'group_by(.type) | map({type: .[0].type, count: length})'

# Pipe an object through a policy check
semantos export job-1774 | semantos eval '(check-policy homeowner-approval)'
```

### The tmux Operator Console

For operators, auditors, and power users, the shell runs in a tmux
session with purpose-built panes:

```
┌──────────────────────┬──────────────────────────────────────┬─────────────────────┐
│ OBJECTS              │ SEMANTIC SHELL                       │ INSPECTOR           │
│                      │                                      │                     │
│ trades.job           │ > create trades.job.plumbing         │ object: job-1774    │
│   job-1774 [AFFINE]  │ flow: new-job-intake                │ linearity: AFFINE   │
│   job-1775 [REL]     │ step 1/3: urgency?                  │ phase: SOURCE       │
│                      │ > high                               │ visibility: draft   │
│ governance           │ step 2/3: location?                  │ owner: facet-3a2b   │
│   dispute-42 [AFF]   │ > northcote                         │ patches: 3          │
│   ballot-17 [REL]    │ step 3/3: describe the issue        │ typeHash: 7f3a...   │
│                      │ > leaking tap in bathroom            │                     │
│ taxonomy             │                                      │ EVIDENCE CHAIN      │
│   services.trades    │ created: job-1774                    │ #0 create [facet-3] │
│   services.trades    │ type: trades.job.plumbing            │ #1 patch  [facet-3] │
│     .plumbing        │ linearity: AFFINE                    │ #2 patch  [facet-3] │
│     .electrical      │ visibility: draft                    │                     │
│     .carpentry       │                                      │                     │
│                      │ > publish job-1774                   │                     │
│                      │ capability check: publish (5) ✓      │                     │
│                      │ linearity gate: AFFINE → RELEVANT ✓  │                     │
│                      │ published.                           │                     │
├──────────────────────┴──────────────────────────────────────┴─────────────────────┤
│ EVENT LOG                                                                         │
│ 14:32:01 [flow]   new-job-intake started for facet-3a2b                          │
│ 14:32:15 [create] job-1774 type=trades.job.plumbing linearity=AFFINE             │
│ 14:32:16 [patch]  job-1774 field=urgency value=high by=facet-3a2b                │
│ 14:32:22 [trans]  job-1774 visibility: draft→published cap=5 ✓                   │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

**The panes map directly to the loom panels:**
- Left pane = Sidebar (ObjectTree + TaxonomyBrowser)
- Center pane = Canvas conversation / CommandBar
- Right pane = Inspector
- Bottom pane = Event log / debug output

Same renderer-agnostic services. Different renderer.

---

## Layer 3: The Axiom Layer (Lisp → Forth)

### What Already Exists

The `lisp-forth-script.md` doc defines a three-stage compilation pipeline:

```
Lisp Macro → Forth Words → Bitcoin Script
 (symbolic)  (concatenative)  (stack ops)
```

The `COMMERCIAL-CONTEXT.md` shows the practical application:

```
Natural language     "Only the homeowner can approve repairs over $500"
    ↓ LLM
Lisp axiom           (policy :subject homeowner :action approve-repair
                             :constraint (> amount 500) :linearity LINEAR)
    ↓ Compiler
Bitcoin Script       OP_DUP OP_CHECKDOMAINFLAG 0x01 OP_SWAP OP_PUSH 500
                     OP_GREATERTHAN OP_BOOLAND OP_CHECKLINEAR
    ↓ Cell packer
Capability token     type=CAPABILITY, linearity=LINEAR, payload=script_bytes
    ↓ Cell engine
Result               TRUE/FALSE
```

### Where Lisp Fits in the Shell

Lisp is the **policy authoring language**. When conversations compress to
repeatable patterns, those patterns become Lisp axioms. When CLI commands
need conditional logic that exceeds simple flags, Lisp expresses the
constraints.

The shell integrates Lisp through the `eval` verb:

```bash
# Evaluate a policy expression against an object
semantos eval '(check-policy homeowner-approval)' --object job-1774

# Compile a policy to a capability token
semantos compile '(policy :subject homeowner
                          :action approve-repair
                          :constraint (> amount 500)
                          :linearity LINEAR)' \
  --output homeowner-approval.cell

# Apply a compiled policy to an object type
semantos bind homeowner-approval.cell --type trades.job.plumbing

# Verify a policy holds
semantos verify job-1774 --policy homeowner-approval
```

### The Compression Gradient

This is the key architectural insight: **conversation, CLI, and Lisp form
a compression gradient.** Each level is more precise and less ambiguous
than the previous one.

```
DISCOVERY ←————————————————————————————————→ COMMITMENT

"only homeowners     semantos bind         (policy :subject       HOMEOWNER-FLAG
 can approve          policy.cell           homeowner              CHECK-DOMAIN
 big repairs"         --type job            :action approve        500 AMOUNT-GT
                                            :constraint            BOOLAND
                                            (> amount 500)         CHECKLINEAR
                                            :linearity LINEAR)

  Natural language   CLI command            Lisp axiom             Forth/Script
  (ambiguous)        (resolved)             (formal)               (executable)
```

Users enter at whatever level matches their expertise. The system compiles
down to the same executable form regardless.

### When Does Lisp Enter the Phase Plan?

Lisp is NOT part of the near-term loom phases (10-17). It is a
separate product that **consumes** the cell engine and the loom's
type system. From `COMMERCIAL-CONTEXT.md`:

> "The Lisp compilation layer and natural language interface are separate
> products that consume the cell engine — they don't change it."

However, the **shell layer** should be designed now to accommodate Lisp
later. This means:

1. The `eval` verb is reserved in the shell grammar
2. The shell's command routing supports s-expression input
3. The output of Lisp compilation is a standard capability token cell
4. Policy objects in extension configs can reference compiled cell payloads

---

## Layer 4: Execution (Forth / Cell Engine / WASM)

This already exists. The 29KB WASM cell engine evaluates scripts
deterministically. The Forth kernel (`kernel.fs`) is the semantic atom.

The shell's job is to never bypass this layer. Every state change that
matters goes through cell packing and linearity enforcement.

```
Shell command → resolve intent → check capabilities → pack cell → evaluate → commit
```

---

## Unifying Semantos and Unix

### The Principle

Unix provides the universal host substrate for computation.
Semantos provides the universal semantic substrate for verifiable state.

**Unix moves bytes. Semantos governs meaning.**

They are complementary, not competing. The unification is by layering:

| Unix Concept | Semantos Equivalent | Relationship |
|---|---|---|
| File | Object snapshot | Object serializes to file-like artifact |
| Process | Transition executor | Process invokes Semantos kernel for validation |
| Pipe | Typed semantic channel | Unix pipe carries typed cells or JSON objects |
| User/permissions | Identity/capabilities | Coarse host security + fine semantic security |
| Filesystem path | Type path / object path | Both navigable, both hierarchical |
| Append-only log | Evidence chain | Same concept, semantic structure added |
| Executable | Script / transition program | Same concept, deterministic + verifiable |
| Environment variable | Facet context | Active identity/capability scope |

### Semantos as VFS (Virtual Filesystem)

The deepest Unix integration is exposing semantic objects through a
virtual filesystem:

```
/semantos/
  identities/
    facet-3a2b/
      cert.json          ← Plexus cert metadata
      capabilities.json  ← active capability set
      glowweight.json    ← reputation score
  objects/
    job-1774/
      header.bin         ← 256-byte cell header
      payload.json       ← typed payload
      patches/
        0000-create.json
        0001-patch.json
        0002-transition.json
      proof.spv          ← SPV proof if anchored
  flows/
    new-job-intake/
      schema.json        ← flow definition
      active/
        session-xyz.json ← in-progress flow state
  taxonomy/
    services/
      trades/
        plumbing.json    ← taxonomy node metadata
        electrical.json
  governance/
    ballots/
      ballot-17.json
    disputes/
      dispute-42.json
```

Under this model:
- `cat /semantos/objects/job-1774/header.bin | xxd` shows raw cell header
- `echo '{"urgency":"critical"}' > /semantos/objects/job-1774/patches/apply` triggers a validated patch
- `ls /semantos/taxonomy/services/trades/` shows available categories
- `cat /semantos/identities/facet-3a2b/capabilities.json` shows what you can do

Writes to certain paths are not raw writes — they are transition requests
validated by the Semantos engine. This is the Plan 9 pattern: represent
system resources uniformly through the filesystem interface.

### What NOT to Force

Some Unix/Semantos analogies should stay separate:

- Unix file permissions ≠ Semantos capabilities (different granularity, different semantics)
- POSIX process model ≠ semantic flow model (flows are multi-step, stateful, evidence-bearing)
- Shell text parsing ≠ semantic typing (typed intents, not regex)
- Filesystem hierarchy ≠ taxonomy (taxonomy is a DAG with dimensions, not a tree)

Unix is intentionally dumb and universal. Semantos is intentionally typed
and constrained. That tension is healthy.

---

## Semantic-Seed Grafts That Enable This

### Graft: FSM Constraint Guards → Shell Policy Evaluation

The FSM constraint types from `semantic-seed/src/fsm/FSMTypes.ts`
(value, time, count, capability, relationship, spatial, contextual)
become the guard language for shell commands.

When a user runs `semantos publish job-1774`, the shell evaluates guards:

```
Guard 1: capability check → facet has publish capability (5)? ✓
Guard 2: linearity gate   → object is AFFINE? ✓
Guard 3: value constraint  → all required fields populated? ✓
Guard 4: time constraint   → within publication window? ✓
```

These guards are the same constraints that FlowRunner evaluates for
guided flows. The shell and the conversation UI share the guard engine.

### Graft: Constitution as Policy Object → Shell `bind` Command

The SemanticConstitution concept becomes a RELEVANT policy object that
the shell can bind to type paths:

```bash
# Create a constitution for the trades extension
semantos new governance.constitution \
  --extension trades-services \
  --proposal-threshold 100 \
  --voting-quorum 0.6 \
  --amendment-quorum 0.75

# Bind it — all governance actions in this extension now check it
semantos bind constitution-001 --type trades.*
```

### Graft: Patch Log Witness Proofs → Shell `trace` Command

The PatchLogEngine's witness hash chain becomes the shell's `trace`
output format:

```bash
semantos trace job-1774

EVIDENCE CHAIN for job-1774
──────────────────────────────────────────────────
#  HASH           AUTHOR      ACTION     TIMESTAMP
0  7f3a2b...1e    facet-3a2b  create     2026-03-29T14:32:15Z
1  a91c4d...3f    facet-3a2b  patch      2026-03-29T14:32:16Z
   witness: sha256(7f3a2b...1e || patch_content || facet-3a2b) = a91c4d...3f ✓
2  c82e5f...7a    facet-3a2b  publish    2026-03-29T14:32:22Z
   witness: sha256(a91c4d...3f || transition_content || facet-3a2b) = c82e5f...7a ✓

CHAIN VALID: all witness hashes verify ✓
```

---

## PRD Additions for the Shell

The semantic shell is not a new phase — it's a **renderer** that sits
alongside the React loom. Both consume the same Phase 9 services.
But it needs explicit deliverables to exist.

### Phase 13 Addition: Shell Scaffolding

Add to Phase 13 (PlexusAdapter + Stub):

- **D13.6**: `packages/shell/` — standalone CLI package consuming loom services
- **D13.7**: Shell command parser (verb + type-path + flags + object-id grammar)
- **D13.8**: JSON and cell output formatters (for Unix pipe composability)
- **D13.9**: Shell config: `~/.semantos/config.toml` (adapter mode, active identity, default extension)

### Phase 14 Addition: Shell Identity

Add to Phase 14 (Production Plexus):

- **D14.8**: Shell authentication via Plexus (BRC-100 signed requests from CLI)
- **D14.9**: `SEMANTOS_FACET` env var for active facet selection (like `AWS_PROFILE`)

### Future Phase (18+): tmux Loom + VFS

- **D18.1**: tmux layout config for the operator console (4 panes as shown above)
- **D18.2**: Live object tree pane (watches LoomStore, updates on change)
- **D18.3**: Inspector pane (watches selected object, shows header + evidence)
- **D18.4**: Event log pane (subscribes to TypedEventEmitter)
- **D18.5**: FUSE-based VFS mount at `/semantos/` (read-only initially, write paths for transitions later)

### Future Phase (20+): Lisp Axiom Compiler

- **D20.1**: S-expression parser (standalone, no dependencies on Scheme/CL runtime)
- **D20.2**: Macro expander (Lisp → Forth word definitions)
- **D20.3**: Policy type in extension config (references compiled cell payloads)
- **D20.4**: `semantos eval` and `semantos compile` shell verbs
- **D20.5**: Shell integration: pipe Lisp output to cell packer

---

## How the Three Documents Fit Together

```
SHOMEE-TO-SEMANTOS-MAPPING.md
  "93 packages collapse to ~20 object types on one engine"
  Maps: 5 conceptual domains → loom cores
  Focus: what objects exist and what they mean

PLEXUS-SEMANTOS-INTEGRATION.md
  "Plexus owns crypto. Loom owns meaning."
  Maps: 20 Plexus components + semantic-seed salvage → adapter + phases 13-17
  Focus: how identity/graph infrastructure plugs in without lock-in

SEMANTIC-SHELL-ARCHITECTURE.md (this document)
  "Conversation for discovery. CLI for commitment. Lisp for composition."
  Maps: 4 execution layers → unified command routing
  Focus: how users interact with the system at every level of expertise
```

Together they define:
- **What** the system models (Shomee mapping)
- **How** the crypto substrate connects (Plexus integration)
- **Where** users enter and how intent flows to execution (this doc)

---

## The One-Liner

Semantos is a semantic shell: a system where natural language, CLI
commands, Lisp axioms, and Forth execution all resolve through the same
typed, evidence-bearing, capability-gated pipeline — and the Unix
substrate carries it all without knowing or caring what it means.
