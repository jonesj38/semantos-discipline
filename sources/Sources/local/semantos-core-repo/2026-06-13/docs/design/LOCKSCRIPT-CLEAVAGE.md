---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/LOCKSCRIPT-CLEAVAGE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.735520+00:00
---

# Script Cleavage: lockScript, unlockScript, and the Cell-Engine Boundary

**Status:** design — gates PR6/PR7 sectioned-assembler + sighash-hostcall
work. PR-1 ships this doc only; PRs against §11's table implement the
apparatus piece by piece.

**Date:** 2026-05-31 (revised to incorporate BSV v1.2.0 "Chronicle" — see §1.1)

**Owner:** the cell-engine substrate track (cross-cut with C11 wallet +
MNCA + any cartridge authoring on-chain-anchored cells).

**Companions:**
- `docs/design/LINEAR-CELL-SPV-STATE.md` — linear cells as SPV state
  machines (this doc generalizes its handler.script ↔ on-chain binding)
- `docs/design/BRAIN-GENERIC-MINT-VERB.md` — the mint pipeline this
  apparatus plugs into
- `docs/design/REAL-EXECUTOR-WIRE.md` — PolicyRuntime adapter (the
  cell-engine execution surface)
- `docs/textbook/11-2pda-cell-engine.md` — the cell-engine 2PDA
- `memory/mnca_anchor_onchain_mainnet.md` — proven MNCA anchor path
- `memory/bsv_no_cltv_use_nlocktime.md` — BSV consensus constraint

**Existing code this composes:**
- `core/cell-engine/src/opcodes/{standard,plexus,routing,macro,hostcall}.zig`
  — the unified opcode vocabulary
- `core/cell-engine/tools/asm.zig` — the assembler (PR5a) this extends
- `runtime/semantos-brain/src/policy_runtime.zig` + `cells_mint_handler.zig`
  — the dispatcher (PR4b) this hooks into
- `core/protocol-types/src/cell-pushdrop.ts::buildPushdropLockingScript`
  — the on-chain anchor template
- `proofs/tla/ScriptBroadcastCleavage.tla` — formal model (companion)

---

## §0 TL;DR

The cell-engine 2PDA accepts a **superset** of Bitcoin Script: standard
opcodes (0x00–0xAF) + Craig macros (0xB0–0xBF) + Plexus (0xC0–0xCF) +
hostcall (0xD0) + routing (0xE0–0xEF). Of these, only the standard
subset **plus the Chronicle additions at 0xB6 and 0xB7** is
consensus-valid (see §1.1 for the BSV v1.2.0 Chronicle release impact).

This means there are **four distinct byte-regions** in a fully realized
on-chain-anchored cell transition, and each is signed under different
rules:

| Region | Vocabulary | On-chain? | In sighash? | Author writes it as |
|--------|------------|-----------|-------------|---------------------|
| **`lockScript`** (scriptPubKey on the new UTXO) | Standard only | YES | YES (when consumed by future spend) | `.lockScript {}` section |
| **`unlockScript`** (scriptSig on the spending tx) | Standard only | YES | NO (it IS the witness) | `.unlockScript {}` section, with `<SIG>` / `<PUBKEY>` template slots |
| **`handler.script`** (cell-engine bytecode in manifest) | Full superset | NO | NO | `.handler {}` section |
| **cell payload** (header + 768B inline + carriage) | Application bytes | NO (committed-to via PushDrop hash) | NO directly; YES indirectly via the hash committed in `lockScript` | cell construction in the handler script |

The **one-line cleavage invariant**:

> **No byte authored in the `.handler` section ever appears in any
> Bitcoin sighash.**

The handler script *runs before* signing happens, *produces* the bytes
that get signed (as `OP_CELLCREATE` emissions carrying consensus-subset
`lockScript` / `unlockScript` cells), and *triggers* signing (by
emitting a `bsv.tx.sign.request` cell carrying a precomputed digest).
It never lives inside the bytes the wallet hashes.

Get this invariant right and **every BSV signature pattern composes
trivially** — `SIGHASH_ALL`, `SIGHASH_SINGLE | ANYONECANPAY`, partial
co-signing, payment channels, multisig escrow, MNCA-anchor transitions,
BRC-29 internalize, distributed supply-chain custody handoffs — all
become permutations of a single state machine driven by EPHEMERAL
intent cells + LINEAR state cells + Dart-side custody.

---

## §1 Terminology

We use `lockScript` and `unlockScript` (BSV / `@bsv/sdk` convention) for
the on-chain locking and unlocking scripts. They map 1:1 to
`scriptPubKey` and `scriptSig` in the Bitcoin protocol; the BSV SDK
types are `LockingScript` and `UnlockingScript` respectively.

**Definitions used throughout:**

- **`lockScript`** — the locking script in an output's `scriptPubKey`.
  Determines who can spend the UTXO. Standard opcodes only.
- **`unlockScript`** — the unlocking script in an input's `scriptSig`.
  Provides the witness data (signatures, pubkeys) that satisfies the
  predecessor UTXO's `lockScript`. Standard opcodes only.
- **`handler.script`** — the cell-engine bytecode declared in the
  cartridge manifest under `cellTypes[i].handler.script`. Runs in the
  brain via the PR4b dispatcher (`cells_mint_handler` →
  `dispatchCellScriptHandler`). Full vocabulary. Never broadcast.
- **cell payload** — the 768-byte inline region of a 1024-byte cell
  (or the head of a carriage chain for larger payloads). Application
  state. Hash-committed by the on-chain `lockScript` via PushDrop.
- **sighash** — the 32-byte digest the wallet signs. Computed over
  some subset of the transaction depending on the `sighashFlags` byte
  appended to the signature. BSV post-Chronicle (v1.2.0, mainnet
  2026-04-07) supports **two algorithms**; see §1.1.
- **sighashFlags** (Chronicle expands the flag space):
  - `SIGHASH_ALL` (0x01): signs all inputs + all outputs
  - `SIGHASH_NONE` (0x02): signs all inputs, no outputs
  - `SIGHASH_SINGLE` (0x03): signs all inputs + one output (the one at
    the same index as the input being signed)
  - `SIGHASH_ANYONECANPAY` (0x80): signs only this input, not others
  - `CHRONICLE` (`0x20`): when set, use OTDA (Original Transaction
    Digest Algorithm — pre-segwit Satoshi); when clear, use BIP-143.
  - `FORKID` (`0x40`): required for BIP-143; ignored under OTDA.
  - Common BIP-143 flag bytes: `0x41` (ALL+FORKID), `0x43`
    (SINGLE+FORKID), `0xC3` (SINGLE+ANYONECANPAY+FORKID).
  - Common OTDA flag bytes: `0x21` (ALL+CHRONICLE), `0x23`
    (SINGLE+CHRONICLE), `0xA3` (SINGLE+ANYONECANPAY+CHRONICLE).

**The "cleavage" is the boundary between the handler.script vocabulary
and the lockScript/unlockScript vocabulary** — a structural property of
how cell types are designed and assembled, NOT a runtime byte-strip.

---

## §1.1 BSV v1.2.0 "Chronicle" — what the consensus subset means now

BSV v1.2.0 (the "Chronicle" release; mainnet activation 2026-04-07)
makes two changes that directly affect this apparatus.

### Two sighash algorithms coexist

The Original Transaction Digest Algorithm (OTDA — the pre-segwit
Satoshi algorithm) is reinstated alongside BIP-143. Selection happens
per-signature via the new **`CHRONICLE` sighash bit (0x20)**:

- `CHRONICLE` bit set (`0x20`) → OTDA
- `CHRONICLE` bit clear → BIP-143 (current default; what existing code
  produces)

Mixed within a single transaction is permitted: each signature
independently selects its algorithm. **The apparatus's
`host_compute_sighash` hostcall takes the full sighashFlags byte and
dispatches to the appropriate digest routine.** OTDA serialises the
transaction with all sig scripts blanked, replaces the spending input's
script with the scriptCode being signed, then double-SHA256s. BIP-143
commits to precomputed `prevouts_hash` / `sequence_hash` /
`outputs_hash` to enable efficient signing in larger transactions.

For cartridge authors: choose BIP-143 unless interoperating with
pre-Genesis tooling that emits OTDA-style signatures. The apparatus
treats both as first-class.

### Restored + new consensus opcodes

Chronicle restores and adds opcodes that BSV nodes accept as valid
consensus operations:

| Opcode | Byte | Status under Chronicle | Cell-engine vocabulary |
|--------|------|------------------------|------------------------|
| `OP_VER` | 0x62 | Restored — pushes tx version | Recognised in assembler |
| `OP_VERIF` | 0x65 | Restored — version-conditional IF | Recognised in assembler |
| `OP_VERNOTIF` | 0x66 | Restored — version-conditional NOTIF | Recognised in assembler |
| `OP_2MUL` | 0x8d | Restored — doubles top | Recognised in assembler |
| `OP_2DIV` | 0x8e | Restored — halves top | Recognised in assembler |
| `OP_LSHIFTNUM` | 0xb6 | New — numerical left shift | **Collides with Craig `OP_XROT_3`** |
| `OP_RSHIFTNUM` | 0xb7 | New — numerical right shift | **Collides with Craig `OP_XROT_4`** |

The cell-engine's Craig macros at 0xB6 and 0xB7 now share bytes with
two consensus opcodes. The sectioned assembler **refuses Craig
mnemonics in `.lockScript` and `.unlockScript`** to prevent silent
semantic divergence: a script using `OP_XROT_3` in a consensus section
would be CONSENSUS-VALID (byte 0xB6 = OP_LSHIFTNUM under BSV) but the
cartridge author's intent (rotate top 3) differs from what BSV would
do (numerical left shift). Source-level rejection forces authors to
either use `OP_LSHIFTNUM` (declaring Chronicle intent) or move the
operation into `.handler` (where Craig semantics apply).

See §12 for the open question on relocating Craig `XROT_3`/`XROT_4` to
non-conflicting bytes (e.g., 0xBA / 0xBB).

### Updated consensus subset (the cleavage threshold)

Bytes that are **consensus-valid in `.lockScript` / `.unlockScript`**
after Chronicle:

- `0x00..0xAF` — standard Bitcoin Script (incl. the five restored
  opcodes above)
- `0xB6` — `OP_LSHIFTNUM` (Chronicle)
- `0xB7` — `OP_RSHIFTNUM` (Chronicle)

OP_NOPs at `0xB0..0xB5`, `0xB8`, `0xB9` are *technically* consensus
NOPs, but the cell-engine's Craig macros occupy those bytes — the
assembler refuses Craig mnemonics in consensus sections to keep
cell-engine and consensus semantics aligned.

The walker at `core/cell-engine/tools/asm.zig::findFirstSemantosOpcode`
exempts 0xB6 and 0xB7 from the semantos check; the source-level
`lookupOpcodeConsensus` (same file) refuses the Craig mnemonics via
`isCellEngineOnlyMnemonic`.

### Selective malleability relaxation

Transactions signed with `nVersion > 1` (version field greater than
`0x01000000`) opt into relaxed rules — Chronicle removes
minimal-encoding, low-S, NULLFAIL, NULLDUMMY, MINIMALIF, clean-stack,
and data-only-in-unlocking-script enforcement for those transactions.

Cartridges that need predictable, locked-down behaviour should sign
with version 1 (current default). Cartridges that need the relaxed
rules (non-trivial unlocking-script computation, or script numbers
larger than 750KB up to the new 32MB consensus cap) opt in by setting
a higher version field. The apparatus's `host_assemble_tx` hostcall
takes the version as a parameter; the constructor handler choosing
the version is the explicit policy decision.

---

## §2 The four-region apparatus

```
┌──────────────────────────────────────────────────────────────────────┐
│                       CELL-TYPE DEFINITION                           │
│                                                                      │
│  ┌─────────────────────────────┐  ┌────────────────────────────────┐│
│  │ .lockScript { }             │  │ .handler { }                   ││
│  │                             │  │                                ││
│  │   Standard opcodes only.    │  │   Full vocabulary:             ││
│  │   Validated as consensus    │  │     standard 0x00-0xAF         ││
│  │   subset at assembler-      │  │     Craig 0xB0-0xBF            ││
│  │   compile time.             │  │     Plexus 0xC0-0xCF           ││
│  │                             │  │     OP_CALLHOST 0xD0           ││
│  │   Goes into the BSV         │  │     routing 0xE0-0xEF          ││
│  │   tx output scriptPubKey.   │  │                                ││
│  │                             │  │   Runs in PolicyRuntime via    ││
│  │   Author writes once;       │  │   the PR4b dispatcher.         ││
│  │   may include template      │  │                                ││
│  │   placeholders for          │  │   Never broadcast.             ││
│  │   payload-hash, leafPubKey, │  │                                ││
│  │   etc., resolved at         │  │   Author writes the validation,││
│  │   handler-emission time.    │  │   capability-gating, identity- ││
│  │                             │  │   checking, and tx-construction││
│  └─────────────────────────────┘  │   logic here.                  ││
│                                   └────────────────────────────────┘│
│  ┌─────────────────────────────┐                                    │
│  │ .unlockScript { }           │  ┌────────────────────────────────┐│
│  │                             │  │ cell payload                   ││
│  │   Standard opcodes only.    │  │                                ││
│  │   Template — slots like     │  │   768-byte inline + optional   ││
│  │   <SIG>, <PUBKEY> filled    │  │   carriage chain for larger    ││
│  │   in by the broker at       │  │   payloads. Application state. ││
│  │   sign-and-broadcast time.  │  │                                ││
│  │                             │  │   Hash-committed by lockScript ││
│  │   Goes into the spending    │  │   via PushDrop. The hash       ││
│  │   tx scriptSig.             │  │   appears IN the sighash       ││
│  │                             │  │   (because it's in lockScript).││
│  │                             │  │   The payload bytes themselves ││
│  │                             │  │   do NOT.                      ││
│  └─────────────────────────────┘  └────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  │  Compile via the sectioned assembler:
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                        ASSEMBLER OUTPUTS                             │
│                                                                      │
│  <name>.lockScript.hex           ← bytes for tx output scriptPubKey  │
│  <name>.unlockScript.template.hex ← template; broker fills slots     │
│  <name>.handler.hex              ← bytes for manifest handler.script │
│  <name>.handler.sha256           ← scriptHash for manifest pinning   │
└──────────────────────────────────────────────────────────────────────┘
```

The assembler refuses to compile if any byte ≥ 0xB0 appears in
`.lockScript` or `.unlockScript`. The consensus-subset check is
structural, not a runtime gate.

---

## §3 The event cycle

The end-to-end "mint a cell, build a tx, sign it, broadcast it,
reconcile on-chain" cycle has **seven phases**. Each phase has explicit
entry/exit invariants the handler script + broker enforce.

```
[1. Intent received] ─→ [2. Handler dispatched] ─→ [3. Validation]
                                                       │
                          ┌────────────────────────────┘
                          ▼
                    [4. Emission] ─→ [5. Sign request] ─→ [6. Broadcast]
                                                                │
                          ┌─────────────────────────────────────┘
                          ▼
                    [7. Reconcile (status flip)]
```

### Phase 1 — Intent received

An EPHEMERAL intent cell of some `<thing>.create.intent` /
`<thing>.consume.intent` / `<thing>.update.intent` type arrives via
`POST /api/v1/cells` (or via federation gossip). The mint pipeline
looks up `req.type_hash` in `cartridge_cell_registry` to find the
cellType metadata.

**Invariants:**
- The intent cell's `linearity` is EPHEMERAL (single-shot; never
  persists as long-term state)
- The caller's bearer + cert pass the existing auth gate (eventually
  per Phase-1b BCA; today bearer-only)

### Phase 2 — Handler dispatched

`cells_mint_handler` looks up `cell_script_handler_registry` for a
handler entry. If one exists, the PR4b dispatcher
(`dispatchCellScriptHandler`):

1. Heap-allocates a fresh `PDA` via `initInPlace(opcount_budget)`
2. Allocates a 64 KB `ScriptArena`
3. Builds `ExecutionContext.init(pda, arena)`
4. Pushes the encoded intent cell onto the main stack at slot 0
5. Loads `hentry.script_bytes` via `ctx.loadScript`
6. Calls `executor.execute(&ctx)`

**Invariants:**
- The intent cell IS on the stack as slot 0 before execution begins
- No emitted cells exist yet (empty emit set)
- The opcount budget reflects the manifest's
  `handler.opcountBudget` (or `DEFAULT_MAX_OPS = 500_000`)

### Phase 3 — Validation (inside the handler script)

The handler script's first responsibility is **Plexus-side validation**.
A typical pattern:

```
# Validate the intent's structural shape via Plexus opcodes
OP_DUP                                  # [intent, intent]
OP_CHECKTYPEHASH                        # is this the expected type?
PUSH <expected_caller_cert_id>
OP_CHECKIDENTITY                        # was this minted by an authorized caller?
PUSH "cap.<cartridge>.<action>"
OP_CHECKCAPABILITY                      # does the caller hold the required capability?

# Run cartridge-specific business logic via OP_CALLHOST
PUSH "host_<cartridge>_<verb>_valid"
OP_CALLHOST                             # → 0|1
OP_VERIFY                               # abort if the business check fails

# Optionally validate domain-specific arithmetic
OP_DUP OP_READPAYLOAD                   # [intent, payload]
# ... extract fields, compare against thresholds, etc.
```

**Invariants:**
- All validation gates run BEFORE any `OP_CELLCREATE` (no cells emit
  until validation completes)
- Any `OP_VERIFY` failure traps execution → dispatcher returns
  `.rejection` → no cells persist → no signature is requested
- The intent cell on the stack is treated as read-only (linearity
  EPHEMERAL doesn't forbid this; the validation only inspects it)

### Phase 4 — Emission (inside the handler script)

If validation succeeds, the handler emits cells. There are **three
canonical emission kinds** for any cell that interacts with the chain:

#### 4a. The successor LINEAR cell (the new application state)

```
# Construct the new linear cell via OP_CELLCREATE
PUSH 1                                  # linearity = LINEAR (consumed once)
PUSH <domain_flag>                      # domain
PUSH <bsv.<thing>.state.vN+1 typeHash>  # successor cell type
PUSH <owner_id>                         # 16 bytes
OP_CELLCREATE                           # [..., successor_cell]
# Construct the payload via standard arithmetic + OP_READPAYLOAD
# of the predecessor, then write into the cell's payload region via
# (planned) OP_WRITEPAYLOAD or via emit-and-recompose pattern
```

#### 4b. The on-chain `lockScript` cell (consensus-subset bytes)

The handler script doesn't write standard-only bytes directly — it
references a pre-assembled `lockScript.hex` from the manifest and emits
a cell whose payload IS those bytes. Concretely:

```
# Push the manifest's lockScript template
PUSH <lockScript_template_cell_hash>
PUSH "host_resolve_lockscript_template"
OP_CALLHOST                             # → cell_hash of resolved template
# (resolves payload-hash placeholder, leafPubKey placeholder, etc.,
#  substituting the values the handler computed; emits a new cell
#  containing the resolved standard-only bytes)
```

The `host_resolve_lockscript_template` hostcall (new — see §8) validates
the resolved bytes are still consensus-subset and emits them as a cell
the broker can include in the tx output.

#### 4c. The `bsv.tx.sign.request` cell (the digest to sign)

```
# Compute the sighash for the spending input the wallet will sign
PUSH <input_index>                      # which input
PUSH 0x41                               # SIGHASH_ALL | FORKID
PUSH <scriptCode_cell_hash>             # the prev-output lockScript
PUSH <input_value_sats>                 # input value (for BIP-143 commit)
PUSH <prevouts_hash>                    # double-SHA256 of all prev outpoints
PUSH <sequence_hash>                    # double-SHA256 of all sequences
PUSH <outputs_hash>                     # double-SHA256 of outputs
PUSH "host_compute_sighash"
OP_CALLHOST                             # → 32-byte digest

# Construct the bsv.tx.sign.request cell carrying the digest
PUSH 2                                  # EPHEMERAL (or AFFINE if draftable)
PUSH <bsv.tx.sign.request typeHash>
PUSH <owner_id>
OP_CELLCREATE                           # the sign-request cell
# (payload contains digest + recipe_id + index + derivation_model)
```

**Invariants:**
- Every byte the wallet will hash via SHA-256 lives in cells whose
  payloads are consensus-subset (§8's validator hostcall enforces)
- The `host_compute_sighash` arguments reference cell hashes; the
  hostcall validates each referenced cell's payload is consensus-subset
  before incorporating into the digest

### Phase 5 — Sign request

The dispatcher post-execution walks the PDA main stack. For each
1024-byte cell at any slot above the input cell, it:

1. Extracts the cell's `typeHash` at header offset 30
2. Validates the typeHash is in `hentry.emits[]` (the manifest's emits
   allowlist resolved via `cartridge_cell_registry.lookupByName`)
3. Persists the cell via `cell_store.put`

When a `bsv.tx.sign.request` cell is persisted, the broker dispatches
it to the Dart wallet via the CellDispatcher (HTTP/WSS per
`LINEAR-CELL-SPV-STATE.md` §6). Dart's `WalletKeyService`:

1. Derives the leaf key per recipe + index
2. Signs the digest (which has already committed to the right scope via
   SIGHASH flags)
3. Returns a `bsv.tx.sign.response` cell carrying the 64-byte (r,s)
   signature

**Invariants:**
- The wallet NEVER sees the handler script. It sees only the
  precomputed digest + the derivation context.
- The signature covers exactly what the SIGHASH flags say it covers,
  and nothing else (the digest is the source of truth)

### Phase 6 — Broadcast

The broker receives the sign response cell. It dispatches a `bsv.tx.
assemble.intent` cell (or proceeds inline) that:

1. Loads the `lockScript` cell (the resolved standard-only bytes)
2. Builds the `unlockScript` from the template by filling `<SIG>` +
   `<PUBKEY>` slots
3. Assembles the full tx (inputs + outputs + nLockTime)
4. Optionally builds the extended BEEF (existing BEEF chain + new tx)
5. Calls `host_broadcast_arc` → returns (status, txid)
6. Emits a `bsv.linear.anchor` cell with status=pending pointing at
   the new UTXO + the new BEEF carriage chain

**Invariants:**
- The broadcast bytes are byte-identical to the bytes whose digest the
  wallet signed
- The `unlockScript` slot-filling only replaces `<SIG>` / `<PUBKEY>` —
  no other bytes change post-signing
- If broadcast fails, the local-store delta of phases 4-5 rolls back
  (PolicyRuntime + cell_store transactional posture)

### Phase 7 — Reconcile

The new `bsv.linear.anchor` cell carries status=pending. The brain's
header tracker watches new blocks; on a header that includes a merkle
proof for the broadcast txid, the brain emits a `bsv.linear.status`
cell flipping pending → confirmed and updates the anchor cell.

On reorg, the cell flips back to pending (or to failed if the spent
input was double-spent in the reorg-winning branch).

**Invariants:**
- Status transitions are themselves LINEAR cells consuming the prior
  status cell (so reorg histories are auditable)
- The UTXO's existence on the consensus chain is the source of truth
  for whether the cell-engine state is reflected on-chain

---

## §4 SIGHASH discipline

The sighash flag determines what part of the transaction the signature
commits to. The cell-engine handler script CHOOSES the flag based on
the workflow:

### §4.1 `SIGHASH_ALL | FORKID` (0x41) — the canonical full-tx signature

Used when the entire tx is built atomically by the brain (single-party
spend; constructor of a fresh linear cell from a single funding source;
destructor of a linear cell with a known successor lockScript).

The digest commits to: all inputs, all outputs, nLockTime,
scriptCode of the input being signed.

**Cell-type pattern:** the handler script knows ALL outputs at emit
time (it constructed them via `OP_CELLCREATE` emitting lockScript
cells). It computes `outputs_hash` over all of them, then computes the
sighash. The wallet signs. Broadcast.

### §4.2 `SIGHASH_SINGLE | FORKID` (0x43) — sign this input + the matching output

Used when the spender wants to bind their input to exactly one output
(e.g., "I'll fund this transition iff the output going to me matches
my expectations"). Co-signers may add/remove other outputs without
invalidating this signature.

The digest commits to: all inputs, the output at the same index as
this input, nLockTime, scriptCode.

**Cell-type pattern:** the spender's handler script constructs only
their input + their matching output. They emit a partially-signed tx
in a `bsv.tx.partial.contribution` cell carrying (input, output, sig).
Counterparties can append their own contributions; the final assembler
combines them all.

### §4.3 `SIGHASH_SINGLE | SIGHASH_ANYONECANPAY | FORKID` (0xC3)

Used for fully-decoupled co-signing — each party signs only their own
(input, matching-output) pair. Reorderings, additions, or removals of
other inputs/outputs don't invalidate any party's signature.

The digest commits to: this input, the output at the same index as
this input, nLockTime, scriptCode.

**Cell-type pattern:** payment channels, supply-chain custody handoffs
where multiple parties sign sequentially. Each `bsv.tx.partial.
contribution` cell is independently valid; the brain (or a coordinator
node) assembles all contributions into the final tx.

### §4.4 `SIGHASH_NONE | SIGHASH_ANYONECANPAY | FORKID` (0xC2)

Used when the signer wants to release a UTXO with no commitment to
outputs — typically the "I'm donating this UTXO to anyone" pattern,
or fee bumps where the recipient is unknown at sign time.

The digest commits to: this input only.

**Cell-type pattern:** discretionary funding pools, faucets, tip jars.
Rare in cartridge workflows but supported.

### §4.5 The discipline summary

The handler script:
1. CHOOSES the sighash flag based on the workflow's semantics (encoded
   in the cell-type design — see §6 for examples)
2. CONSTRUCTS the bytes the flag says will be committed to (the
   relevant subset of the tx)
3. COMPUTES the digest via `host_compute_sighash`
4. EMITS the digest as a `bsv.tx.sign.request` cell
5. NEVER touches the digest bytes after computing

The wallet:
1. SIGNS the digest (under the recipe + index it was asked to use)
2. RETURNS the signature in a `bsv.tx.sign.response` cell
3. NEVER sees the unsigned tx or the handler script

The broker:
1. ASSEMBLES the signed tx by filling slots in the `unlockScript`
   template
2. VERIFIES (via existing BEEF infrastructure) that the assembled tx
   would pass mempool / consensus checks
3. BROADCASTS via ARC
4. UPDATES the linear-cell state on success

**The key property**: every signature is over a digest computed before
the script that constructed the digest finished running. The constructing
script's bytes never enter the digest. The cleavage holds.

---

## §5 Constructors and destructors

Every cell type that participates in on-chain anchoring ships as a
**constructor / destructor pair** (or pair-of-pairs for partial-tx
workflows). The pattern:

### Naming convention

```
For an on-chain-anchored thing called <thing>:

CONSTRUCTORS:
  <thing>.create.intent       EPHEMERAL  Caller-emitted; carries inputs
  <thing>.create.result       EPHEMERAL  Handler-emitted; success / failure
  <thing>                     LINEAR     The actual state cell

DESTRUCTORS:
  <thing>.consume.intent      EPHEMERAL  Caller-emitted; nominates the
                                          predecessor LINEAR cell to consume
  <thing>.consume.result      EPHEMERAL  Handler-emitted; carries the
                                          successor (or null on rejection)
```

### Constructor handler script — canonical shape

```
# Phase 3: validate intent
OP_DUP OP_CHECKTYPEHASH <thing.create.intent>
PUSH <required_caller_cert_id> OP_CHECKIDENTITY
PUSH "cap.<cartridge>.create" OP_CHECKCAPABILITY
PUSH "host_<cartridge>_create_valid" OP_CALLHOST OP_VERIFY

# Phase 4a: emit the LINEAR state cell
PUSH 1                              # LINEAR
PUSH <domain_flag>
PUSH <thing typeHash>
PUSH <owner_id>
OP_CELLCREATE                       # successor cell on stack

# Phase 4b: emit the on-chain lockScript cell
PUSH <thing.lockScript template ref>
PUSH "host_resolve_lockscript_template"
OP_CALLHOST

# Phase 4c: emit the sign request for the funding tx
PUSH 0                              # input_index = 0
PUSH 0x41                           # SIGHASH_ALL | FORKID
PUSH <funding_utxo_scriptCode>
PUSH <funding_value>
PUSH <prevouts_hash> PUSH <sequence_hash> PUSH <outputs_hash>
PUSH "host_compute_sighash" OP_CALLHOST
# ... emit bsv.tx.sign.request cell carrying the digest

OP_1                                # truthy — handler succeeds
```

### Destructor handler script — canonical shape

```
# Phase 3: validate intent + predecessor existence
OP_DUP OP_CHECKTYPEHASH <thing.consume.intent>
OP_DUP OP_READPAYLOAD               # extract predecessor cell hash
PUSH "host_load_predecessor"
OP_CALLHOST                         # loads + verifies predecessor exists
OP_ASSERTLINEAR                     # predecessor must be LINEAR
PUSH <required_caller_cert_id> OP_CHECKIDENTITY
PUSH "cap.<cartridge>.consume" OP_CHECKCAPABILITY

# Phase 4: emit the spending-tx lockScript (for the SUCCESSOR if any) +
#          unlockScript template + sign request
# (similar pattern to constructor; details per workflow)

# Phase 5: the dispatcher persists the new bsv.linear.anchor (pending)
#          consuming the predecessor's UTXO and marking it spent.

OP_1
```

### The pair-of-pairs pattern for partial-tx workflows

When multiple parties co-sign, expand the destructor pair into a
contribution → assembly sequence:

```
PARTIAL CONSTRUCTORS / DESTRUCTORS:

  <thing>.partial.intent      EPHEMERAL  Initiator's request: "start a
                                          co-signed tx of shape T"
  <thing>.partial.shell       LINEAR     The accumulating skeleton —
                                          known inputs/outputs but not all
                                          sigs collected yet
  <thing>.partial.contribution EPHEMERAL Each co-signer's signed
                                          (input, matching-output) pair
  <thing>.partial.assemble    EPHEMERAL  "All sigs in; assemble and
                                          broadcast" trigger
  <thing>.partial.result      EPHEMERAL  Final txid + confirmation status
```

The shell cell is LINEAR — it can be consumed only once, by either:
- A `<thing>.partial.assemble` that broadcasts the final tx
- A `<thing>.partial.cancel` that aborts the workflow

Each `<thing>.partial.contribution` is EPHEMERAL (single-shot) and is
validated against the shell's expected counterparty set before being
recorded in the shell's payload. This is **exactly the place where
EPHEMERAL linearity earns its keep** — see §6.

---

## §6 Ephemeral linearity for partial-tx workflows

EPHEMERAL Linearity (the variant preserved in PR1.5; tracked at
`cartridge_cell_registry.zig::Linearity.EPHEMERAL`) is the wire-level
linearity for cells that are by-definition transient: intent + result
pairs, sign request + response, contribution + acknowledgment.

For partial-tx workflows EPHEMERAL provides two critical properties:

### §6.1 Inability to replay

Because EPHEMERAL cells are single-shot, a stale contribution cell
cannot be re-submitted to a later phase of the workflow. Once the
dispatcher has processed an EPHEMERAL contribution and updated the
LINEAR shell with the contribution recorded, the contribution cell is
effectively "consumed" — any later attempt to mint a cell with the
same content-hash trips the dispatcher's idempotency check (because
the contribution's effects are already reflected in the LINEAR shell's
state hash).

### §6.2 Audit without persistence

EPHEMERAL cells flow through the mint pipeline → handler dispatch →
emit-or-reject. They are persisted (currently — see open question in
LINEAR-CELL-SPV-STATE.md §13) but with semantics that the substrate
treats them as auditable but non-load-bearing. A future EPHEMERAL
storage tier could auto-prune them after a retention window without
breaking any LINEAR cell's consumption history (LINEAR cells never
reference EPHEMERAL cells as predecessors).

### §6.3 The partial-tx state machine using EPHEMERAL + LINEAR

For a 3-party co-signed payment:

```
T=0:  Initiator mints <thing>.partial.intent (EPHEMERAL)
      ─→ Handler validates initiator + emits <thing>.partial.shell (LINEAR)
         carrying { expected_counterparties: [A, B, C], collected_sigs: [] }

T=1:  Party A mints <thing>.partial.contribution{partyA, sig_A} (EPHEMERAL)
      ─→ Handler:
         1. Loads the LINEAR shell
         2. Verifies sig_A against the BIP-143 digest the shell expects
         3. Emits successor LINEAR shell with collected_sigs = [sig_A]
         4. Consumes (via OP_DEMOTE chain) the previous shell

T=2:  Party B contributes (same pattern as T=1, with collected_sigs [A, B])

T=3:  Party C contributes (collected_sigs [A, B, C] — full)

T=4:  Initiator mints <thing>.partial.assemble (EPHEMERAL)
      ─→ Handler:
         1. Loads the LINEAR shell
         2. Verifies collected_sigs is complete per expected_counterparties
         3. Constructs the broadcast unlockScript (slotting in each sig)
         4. Emits bsv.tx.broadcast.intent
         5. Final shell.consume_status transitions to "broadcast_pending"
```

The shell is LINEAR throughout — each contribution mints a successor
shell consuming the predecessor. Contributions are EPHEMERAL — they
flow in, validate, update the shell, and disappear.

If a party tries to contribute the same signature twice, the second
attempt fails because the predecessor shell (the one the duplicate
contribution would consume) no longer exists. Linearity prevents the
race.

---

## §7 Worked examples

### §7.1 Document management — versioned approvals

A document cartridge wants:
- Documents have versions; each version is a LINEAR cell
- Approval requires signatures from a configurable set of approvers
- Once approved, the document version is on-chain anchored
- Revoking approval requires a new approval cycle

**Cell types:**

```
doc.version.create.intent           EPHEMERAL
doc.version                         LINEAR    (the current approved version)
doc.version.approval.intent         EPHEMERAL  (initiator triggers approval)
doc.version.approval.shell          LINEAR    (accumulating approver sigs)
doc.version.approval.contribution   EPHEMERAL (one approver's sig)
doc.version.approval.finalize       EPHEMERAL (last approver — triggers broadcast)
doc.version.revoke.intent           EPHEMERAL (creates a new version succeeding the old)
```

**Lock-script pattern**: each `doc.version` UTXO uses
`SIGHASH_ALL | FORKID` for the finalization tx (single-broadcast event),
locks with multisig-by-approver-set (m-of-n). The `doc.version.approval.
contribution` validates each signature off-chain (the handler runs
`host_compute_sighash` + `host_verify_partial_sig`) before recording
into the LINEAR shell.

### §7.2 MNCA — anchor transitions

MNCA cell anchoring (per `mnca_anchor_onchain_mainnet`) generalizes
beautifully into this apparatus:

```
mnca.anchor.create.intent           EPHEMERAL
mnca.anchor                         LINEAR    (the anchor cell)
mnca.anchor.transition.intent       EPHEMERAL  (consume old, mint new)
mnca.anchor.transition.result       EPHEMERAL
```

The `mnca.anchor` LINEAR cell carries the MNCA grid state in its
payload (cellular automaton 1B/grid-cell payload per the locked design
in memory `mnca_design_decisions`). The `mnca.anchor.transition.intent`
carries the deterministic next-state computation result. The handler:

1. Validates the next-state was computed deterministically
   (`host_mnca_verify_transition` runs the same transition fn the cell-
   engine would, asserts the result matches)
2. Constructs the spending tx that consumes the predecessor anchor
   UTXO and mints a new one committing to the new payload hash
3. Uses `SIGHASH_ALL | FORKID` (single-party — the operator owns
   sequential MNCA transitions)
4. Emits the sign request

The on-chain anchor proves the transition was applied; SPV proves the
chain; the cell-engine proves the determinism. All three pieces
compose.

### §7.3 Project management — task graphs

A project management cartridge models tasks as LINEAR cells with
dependency edges:

```
task.create.intent          EPHEMERAL
task                        LINEAR    (the task cell, with status + deps)
task.update.intent          EPHEMERAL  (assign, comment, status-change)
task.complete.intent        EPHEMERAL  (close the task; check deps)
task.partial.review.shell   LINEAR    (reviewer-collection for completion)
task.partial.review.contribution EPHEMERAL
```

Completion that requires reviewer approval uses the partial-tx
pattern: the `task.complete.intent` opens a `task.partial.review.shell`
LINEAR cell collecting reviewer signatures (off-chain, no broadcast
needed — pure cell-engine flow). When all reviewers sign, a final
EPHEMERAL `task.complete.finalize` transitions the task LINEAR cell to
status=completed.

If the task has an on-chain stake (completion releases funds to the
assignee), the finalize handler also constructs and broadcasts the
release tx. If purely off-chain (no payment), the finalize handler
just transitions the cell.

The apparatus handles both with the same pattern — the handler's
emission set determines whether broadcast happens.

### §7.4 Distributed supply chain — custody handoff

A shipping container with multiple legs (manufacturer → freight →
customs → distributor → retailer), each leg sealed by the responsible
party:

```
shipment.create.intent              EPHEMERAL
shipment                            LINEAR
shipment.handoff.intent             EPHEMERAL (current custodian initiates)
shipment.partial.handoff.shell      LINEAR    (accumulating sigs from both
                                                outgoing + incoming party)
shipment.partial.handoff.contribution EPHEMERAL
shipment.handoff.finalize           EPHEMERAL (broadcast)
```

The `shipment.partial.handoff.shell` requires sigs from BOTH the
outgoing custodian AND the incoming one (2-of-2 multisig on the
on-chain UTXO). The handler uses
`SIGHASH_SINGLE | SIGHASH_ANYONECANPAY | FORKID` so each party's
signature is independently valid — neither can prevent the other from
signing later, and the order doesn't matter.

On finalize, the broadcast tx spends the previous shipment UTXO and
creates a new one with the next custodian's lockScript. The chain of
shipment.* LINEAR cells is the auditable custody history; SPV proves
each handoff was on-chain anchored.

---

## §8 New hostcalls + assembler sections

To realize this apparatus, the substrate gets these additions:

### §8.1 Assembler sections

The PR5a assembler grows three section directives:

```
.lockScript { ... }       # standard subset only; refuses 0xB0+
.unlockScript { ... }     # standard subset only; supports <SIG> / <PUBKEY> slots
.handler { ... }          # full vocabulary
```

Output artifacts per source file:

| Artifact | Contents | Where it lives |
|----------|----------|----------------|
| `<name>.lockScript.hex` | Bytes for the tx output scriptPubKey | Embedded in handler.script's lockScript-template cells |
| `<name>.unlockScript.template.hex` | Bytes with `<SIG>` / `<PUBKEY>` slot markers | Embedded in handler.script for slot-filling at broadcast |
| `<name>.handler.hex` | Bytes for `cellTypes[i].handler.script` | Cartridge manifest |
| `<name>.handler.sha256` | sha256 of handler.hex | Cartridge manifest `handler.scriptHash` |

The assembler verifies the `.lockScript` and `.unlockScript` sections
contain only standard opcodes (byte ≤ 0xAF) + IF/ELSE/ENDIF balance +
no truncated pushdata.

### §8.2 Hostcalls

| Hostcall | Capability | Purpose |
|----------|------------|---------|
| `host_compute_sighash` | `cap.tx.sign` | Compute BSV sighash digest from (input_index, sighashFlags, scriptCode_cell_hash, input_value, prevouts_hash, sequence_hash, outputs_hash). **Dispatches on the `CHRONICLE` bit (0x20) of sighashFlags**: clear → BIP-143; set → OTDA (the pre-segwit Satoshi algorithm; OTDA ignores the precomputed hash arguments and serialises the tx directly). Validates scriptCode bytes are consensus-subset via `findFirstSemantosOpcode`. |
| `host_verify_partial_sig` | `cap.tx.sign` | Verify a partial sig against a sighash digest + pubkey. Returns 0/1. Used by partial-tx contribution handlers. |
| `host_resolve_lockscript_template` | `cap.tx.build` | Take a lockScript template cell hash + a list of (slot_name, value) bindings; emit a cell containing the resolved standard-only bytes. |
| `host_resolve_unlockscript_template` | `cap.tx.build` | Same shape for unlockScript templates (slots for SIG/PUBKEY). |
| `host_assemble_tx` | `cap.tx.build` | Take (inputs, outputs, nLockTime); produce a fully-serialized tx cell ready for `host_broadcast_arc`. |
| `host_compute_prevouts_hash` | (none — pure) | Helper: double-SHA256 of concatenated prev outpoints. |
| `host_compute_sequence_hash` | (none — pure) | Helper: double-SHA256 of concatenated sequences. |
| `host_compute_outputs_hash` | (none — pure) | Helper: double-SHA256 of concatenated serialized outputs. |
| `host_load_predecessor` | `cap.cell.read` | Load a LINEAR cell by content hash; assert linearity == LINEAR. |

The capability strings are declared in each cell-type handler's
manifest `capabilities[]` array (PR3 schema). The brain's
`host_capability_table` registers each hostcall + its required
capability. PR4b's dispatcher refuses scripts that lack the declared
capabilities for hostcalls they invoke.

### §8.3 New EPHEMERAL cell types (substrate-level)

The substrate adds these standard cell types (in `core/protocol-types/
src/bsv/`):

```
bsv.tx.partial.shell.<workflow>   LINEAR    workflow-keyed shell
bsv.tx.partial.contribution       EPHEMERAL one party's signed input/output
bsv.tx.partial.assemble           EPHEMERAL trigger broadcast
bsv.tx.partial.cancel             EPHEMERAL abort the workflow
bsv.tx.sign.request               EPHEMERAL (already in §3.5)
bsv.tx.sign.response              EPHEMERAL (already in §3.5)
bsv.tx.assemble.intent            EPHEMERAL the broker's assemble-and-broadcast trigger
bsv.tx.broadcast.intent           EPHEMERAL standalone broadcast (not bundled)
bsv.tx.broadcast.result           EPHEMERAL { txid, accepted, arcStatus }
```

Cartridges declare workflow-specific contribution/assemble cell types
that wrap these substrate primitives.

---

## §9 TDD framework

The apparatus is testable at five levels. Each level corresponds to a
test directory + a discipline for what's covered.

### §9.1 Level 0 — Assembler

`core/cell-engine/tools/asm.zig` already has 13 tests (PR5a). Adds:

| Test class | Examples |
|------------|----------|
| Sectioned compile | Source with `.lockScript / .handler` → both artifacts emit |
| Consensus-subset enforcement | `.lockScript { OP_CELLCREATE }` → assemble error `non_standard_in_lockscript` |
| Slot resolution | `.unlockScript { PUSH <SIG> PUSH <PUBKEY> }` → template with slot positions recorded |
| Round-trip | Assemble + disassemble produces source-equivalent output |

### §9.2 Level 1 — Hostcall units

Each new hostcall in §8.2 gets a focused unit test:

| Hostcall | Test class examples |
|----------|---------------------|
| `host_compute_sighash` | Golden BIP-143 vectors AND golden OTDA vectors from the BSV spec; selection via CHRONICLE bit (0x20); non-standard bytes in scriptCode → error |
| `host_verify_partial_sig` | Known-good (sig, digest, pubkey) tuples; invalid sig → 0; tampered digest → 0 |
| `host_resolve_lockscript_template` | Slot substitution preserves byte-length; missing slot → error; non-standard result → error |
| `host_assemble_tx` | Round-trip with `@bsv/sdk` serialization; nLockTime + sequence flags preserved |

### §9.3 Level 2 — Handler conformance (per cell-type)

Each cell type ships a `*.conformance.spec.ts` fixture file containing
known-good `(intent, expected_emits, expected_sign_request)` triples.
The conformance harness:

1. Registers the handler bytecode in the script-handler registry
2. Mints the intent cell against a test cell_store
3. Captures emitted cells
4. Compares against the expected set (by typeHash + payload-bytewise)
5. Validates the sign-request digest matches an externally-computed
   BIP-143 digest (via `@bsv/sdk`)

This is the **golden cross-validation** layer — the same place
PR5a's Rúnar `Always` test lives, generalized to entire handlers.

### §9.4 Level 3 — Adversarial fixtures

For each cell type:

| Adversary | Expected outcome |
|-----------|------------------|
| Intent with wrong typeHash | Handler rejects at `OP_CHECKTYPEHASH` |
| Intent with non-allowlisted caller | Handler rejects at `OP_CHECKIDENTITY` |
| Capability not granted | Dispatcher rejects via `broker.checkInvocationCapabilities` (Phase-1b BCA-pending today) |
| Handler tries to emit cell outside `emits[]` | Dispatcher rejects at `host_emit_cell` (PR4b emits allowlist) |
| Handler tries to invoke hostcall outside `capabilities[]` | Broker rejects (PR4b+ capability-gating, gap noted in §9 of LINEAR-CELL-SPV-STATE) |
| Tampered partial-sig contribution | `host_verify_partial_sig` returns 0 → handler rejects |
| Replay of an already-processed contribution | Predecessor shell already consumed → no successor exists → second mint trapped |
| Tampered lockScript bytes (post-resolution) | sighash mismatch at sign time → wallet declines |

These are explicit Zig tests in
`runtime/semantos-brain/tests/cleavage_adversarial_conformance.zig`.

### §9.5 Level 4 — End-to-end via fake-brain harness

A test harness that:
1. Runs cell-engine inline (no HTTP transport)
2. Stubs ARC (broadcast accepts return canned txids)
3. Stubs the headers tracker (canonical chain + reorg fixtures)
4. Drives the Dart wallet (signing per recipe)
5. Mints cells of the worked-example cell types from §7

Each worked example becomes a test:
- `tests-e2e/document-mgmt-3-approvers.spec.ts`
- `tests-e2e/mnca-anchor-transition.spec.ts`
- `tests-e2e/project-mgmt-task-with-review.spec.ts`
- `tests-e2e/supply-chain-multi-leg-handoff.spec.ts`

The end-to-end tests assert:
- The final on-chain state matches the cell-engine's projection
- A reorg fixture flips status cells appropriately
- Adversarial scenarios produce specific rejection cells (not undefined
  behavior)

### §9.6 Property-based testing

Where the workflow has combinatorial complexity (multi-party orderings,
SIGHASH-flag mixtures), use property tests:

| Property | Tested how |
|----------|------------|
| Order-independence of `SIGHASH_SINGLE\|ANYONECANPAY` contributions | Shuffle the contribution sequence; assert final broadcast tx is identical |
| Idempotency of EPHEMERAL retries | Replay a contribution N times; assert exactly one updates state |
| Linearity of the shell across contributions | Property: count of historical shell cells = count of contributions + 1 (the original) |
| Reorg recoverability | Generate random reorg depths up to N; assert status cells flip back correctly |

These run as fuzz suites under `core/cell-engine/fuzz/` alongside the
existing opcode_fuzz.zig.

---

## §10 TLA+ specification

The companion spec at `proofs/tla/ScriptBroadcastCleavage.tla`
formalizes the cleavage invariant + the partial-tx state machine.

### §10.1 What it models

**State variables:**
- `cells` : map from content_hash → (typeHash, linearity, payload, status)
- `pendingTxs` : set of transactions awaiting broadcast
- `confirmedTxs` : set of transactions on-chain
- `signedDigests` : set of digests the wallet has signed
- `partialShells` : map from workflow_id → (expected_parties, collected_sigs)

**Actions:**
- `IntentArrives(intent)` — caller mints an EPHEMERAL intent
- `HandlerValidates(intent)` — dispatcher runs validation
- `HandlerEmits(intent, emissions)` — handler produces output cells
- `WalletSigns(digest, sig)` — wallet signs a digest
- `BrokerBroadcasts(tx)` — broker submits to ARC
- `HeaderConfirms(txid)` — header tracker observes the tx
- `Reorg(depth)` — adversarial reorg flips status cells

### §10.2 Invariants checked

The TLC model checker verifies:

1. **`NoSemantosBytesInAnySignedDigest`** — for every digest in
   `signedDigests`, the scriptCode it covers contains no opcode ≥ 0xB0.
   *This is the cleavage invariant.*

2. **`LinearityOneShot`** — for every LINEAR cell, at most one cell in
   any reachable state has it as predecessor.

3. **`EphemeralBoundedLifetime`** — every EPHEMERAL cell either has a
   successor reflecting its effects, OR is rejected; no EPHEMERAL cell
   persists across more than one mint-and-result cycle without effect.

4. **`PartialShellMonotonicCollection`** — the `collected_sigs` field
   on a `*.partial.shell` cell can only grow, never shrink, across
   shell-successor transitions.

5. **`CapabilityGated`** — every hostcall invocation by a handler
   script is in the handler's declared `capabilities[]`.

6. **`SighashCommitsToBroadcastBytes`** — the digest the wallet signed
   for a tx is byte-equivalent to the BIP-143 digest computed over the
   tx's actual broadcast bytes.

### §10.3 What TLA+ catches that Lean doesn't

Lean's K1-K8 proofs (per `docs/FORMAL-VERIFICATION-STRATEGY.md`)
verify per-opcode semantics. TLA+ verifies trace-level properties:

- "Can a sequence of valid mints lead to a state where someone signed
  a digest containing Plexus bytes?" — TLA+ explores the state space
- "Can a reorg + concurrent contribution create a divergent shell?"
  — TLA+ models concurrency
- "Can an EPHEMERAL replay race a LINEAR consumption?" — TLA+ checks
  interleavings

Lean proves "each opcode preserves invariants." TLA+ proves "no
sequence of opcode applications violates the invariants." Together
they cover the substrate.

---

## §11 PR sequence

| PR | Scope | Depends on |
|----|-------|------------|
| **PR-1** | This design doc + `proofs/tla/ScriptBroadcastCleavage.tla` skeleton. | — |
| **PR-2** | Sectioned assembler: `.lockScript / .unlockScript / .handler` directives + consensus-subset validator + multi-artifact output. Tests per §9.1. | PR-1 |
| **PR-3** | `host_compute_sighash` (BIP-143 + OTDA dispatch on CHRONICLE bit 0x20) + helpers (`host_compute_prevouts_hash`, `host_compute_sequence_hash`, `host_compute_outputs_hash`). Golden vectors for both algorithms per §9.2. | PR-2 |
| **PR-4** | `host_resolve_lockscript_template` + `host_resolve_unlockscript_template` + the slot-fill machinery. | PR-3 |
| **PR-5** | `host_verify_partial_sig` + `host_assemble_tx`. Adversarial fixtures per §9.4 for forged contributions. | PR-3 |
| **PR-6** | `bsv.tx.partial.*` cell types + the substrate-level handlers (shell creation, contribution accumulation, assemble trigger). | PR-5 |
| **PR-7** | First on-chain-anchored worked example: `bsv-spv-verify` extended with constructor pair using the assembler sections. This is the actual PR5b deferred from the recovery sequence. | PR-6 |
| **PR-8** | Worked example #2: MNCA anchor transition (closes the MNCA on-chain anchoring loop with the proper cleavage discipline). | PR-7 |
| **PR-9** | TLA+ model: complete spec + TLC config + CI run + documented model size. | PR-1 (TLA+ skeleton); independent of code work |
| **PR-10** | End-to-end harness for document-mgmt / project-mgmt / supply-chain examples. Optional after PR-6+. | PR-6 |

PR-9 (TLA+) runs in parallel with PR-2 through PR-8 — it's documentation
+ formal verification, independent of code shipping.

---

## §12 Open questions

- **Craig macro relocation**: BSV v1.2.0 Chronicle introduced
  `OP_LSHIFTNUM` (0xB6) and `OP_RSHIFTNUM` (0xB7) at byte positions
  the cell-engine had assigned to `OP_XROT_3` and `OP_XROT_4`. The
  current sectioned assembler refuses Craig mnemonics in consensus
  sections (preventing silent semantic divergence), but the cell-engine
  executor's `macro.zig` still dispatches 0xB6 → `xrot(3)`, 0xB7 →
  `xrot(4)`. **Proposed resolution**: relocate the two Craig macros to
  the reserved range 0xBA / 0xBB so that the cell-engine dispatch table
  and the BSV consensus opcode table no longer collide. This requires
  touching:
  - `core/cell-engine/src/opcodes/macro.zig` (dispatch table)
  - Any conformance tests exercising XROT_3 / XROT_4 directly
  - The assembler's `OPCODES` table (move the entries)
  Estimated 1–2 hour change. Until then, the assembler's source-level
  guard (`isCellEngineOnlyMnemonic`) keeps the collision out of
  consensus sections.

- **`OP_WRITEPAYLOAD`**: the cell-engine has `OP_READPAYLOAD` (0xCC)
  but no opcode for writing payload bytes back. Handlers currently
  construct cell payloads via `OP_CELLCREATE`'s header-only path,
  meaning the payload must come from a hostcall (e.g.,
  `host_assemble_cell_payload`). Whether to add `OP_WRITEPAYLOAD`
  vs. always-route-through-hostcalls is a design call — likely the
  hostcall path is right (keeps PDA stack-only; payload assembly is a
  bounded operation that benefits from Zig-side validation).

- **Cell-payload encoding standardization**: cartridges currently choose
  their own payload formats (JSON, CBOR, custom binary). For partial-tx
  workflows where the `*.partial.shell` payload must contain signature
  arrays + counterparty sets, a canonical encoding spec is helpful.
  Defer to a separate doc (CARTRIDGE-PAYLOAD-CODING.md) but reference
  here.

- **Sighash for nested partial flows**: when a contribution itself
  contains a nested partial workflow (e.g., a counterparty's input is
  itself spent from a multisig), the sighash chain becomes recursive.
  v1 doesn't support this; sets a flat 1-level nesting limit.

- **Federation-distributed shells**: when the LINEAR shell lives on
  one operator's brain but contributions come from federated peers, the
  state replication semantics need care. PR4b's dispatcher assumes
  local cell_store; federated state requires a separate replication
  story (cross-cuts with the federation track).

- **Hostcall ABI versioning**: as new hostcalls land (PR-3 through
  PR-5), some scripts will use older hostcall names. Cartridge handlers
  should pin a substrate-version hostcall-set to avoid breaking on
  upgrade. Track separately as part of the broader
  hostcall-versioning question.

- **Mid-execution capability revocation**: closed in
  `LINEAR-CELL-SPV-STATE.md` §14 as "structurally impossible" for
  loop-free scripts. For partial-tx flows that span many cells, the
  question moves to "does revoking a party's capability mid-workflow
  invalidate their already-signed contribution?" v1 default: no
  (contributions already in the shell are immutable). Future:
  optionally taint shells whose contributors lost capability.

- **Bypass-cell payments**: spending a UTXO that has no cell-store
  backing (per `LINEAR-CELL-SPV-STATE.md` §8.3) still goes through the
  apparatus — the `bsv.tx.broadcast.intent` carries the UTXO explicitly
  rather than referencing a predecessor LINEAR cell. v1 has this path
  defined but not exercised; first real test once PR-7 lands.

---

## §13 What this commits us to

Adopting this apparatus means:

- Every on-chain-anchored cell type ships with `.lockScript /
  .unlockScript / .handler` sections in its source `.cs` file. The
  assembler enforces the cleavage; cartridge authors can't accidentally
  leak Plexus bytes into a broadcast script.
- Every signature in the system is over a digest computed BEFORE the
  bytes are assembled into a broadcastable form. The wallet never
  signs cell-engine bytecode; it signs precomputed digests over
  consensus-subset scripts.
- Every multi-party workflow uses the `*.partial.*` cell-type family
  (or a cartridge-specific specialization). EPHEMERAL contributions +
  LINEAR shell is the universal pattern.
- Every cell type that needs hostcalls declares its capabilities; the
  brain enforces; tests verify rejection paths.
- The TLA+ spec stays in sync with implementation; new cell types add
  to the model, not bypass it.

The cost is real engineering work (PR-2 through PR-7 is multi-week).
The payoff is a substrate where adding a new on-chain-anchored cell
type is "write the .cs file, declare the manifest entry, ship the
hostcall implementations" — instead of "design a bespoke tx-builder
for this workflow."

Document management, MNCA, project management, supply chain — all
become permutations of the same apparatus. Composable on-chain
business logic, host-enforced cartridge semantics, formally verified
cleavage between them.
