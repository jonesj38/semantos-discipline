---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30A-PATCH-TX-CHAIN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.719823+00:00
---

# Phase 30A Patch — Transaction Chain FFI & SIGHASH State Machine

**Version**: 1.1
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 5–6 weeks (8 sub-phases)
**Prerequisites**: Phase 30A complete (C ABI header). No dependency on 30B or 30C — this patch defines its own callback registration for `host_identity_sign` and `host_network_broadcast` (sub-phase 30A.3), and uses `linearity.zig` internally (Zig-to-Zig, no C ABI needed). When 30B is built, its callback table should absorb these two callbacks.
**Master document**: `PHASE-30-FFI-MASTER.md`
**Supersedes**: `PHASE-30D-ANCHOR-FFI.md` (simple hash-in/proof-out model)
**Branch**: `phase-30a-patch-tx-chain`

---

## Context

Phase 30A delivered a clean C ABI with cell read/write/verify and memory management. Phase 30D specced anchor functions as a simple hash-in, proof-out model: submit state hashes to a callback, get SPV proofs back. That model treats the blockchain as a timestamping service.

The actual requirement is stronger. The blockchain is not a timestamp log — it is the enforcement layer for the state machine. Each state transition in a semantic object's lifecycle is a BSV transaction that spends the output of the previous transition. SIGHASH flags on each input define what the signer commits to, creating one-way data check valves that make the audit log structurally meaningful. Identity actions are separated by signature: each participant's contribution is independently verifiable without trusting any other party.

This requires the kernel to understand transaction structure. The kernel must select SIGHASH flags based on the vertical config's FSM rules, construct transaction templates, and verify transaction chains offline via SPV. The host provides signing keys (via IdentityAdapter callbacks) and network submission (via NetworkAdapter callbacks), but the kernel owns the transaction logic because it lives inside the proof boundary.

### Why This Lives in the Kernel (Not the Host)

SIGHASH selection determines what a participant is committing to. If the host controls SIGHASH selection, a compromised host can change a SIGHASH_ALL (immutable commitment) to SIGHASH_NONE|ANYONECANPAY (delegation) without the signer knowing. By keeping SIGHASH selection inside the kernel's proof boundary, the formal proofs guarantee that the correct SIGHASH scheme is applied for every FSM transition. The host only signs the preimage the kernel gives it — it cannot influence what that preimage commits to.

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `PHASE-30A` | `docs/prd/PHASE-30A-C-ABI-HEADER.md` | Existing C ABI pattern, error codes, function signatures |
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | Architecture, memory ownership model, callback table |
| `SIGHASH-ZIG` | `packages/cell-engine/src/sighash.zig` | BIP143 preimage computation, TxContext, SIGHASH flags, parseTxContext |
| `BEEF-ZIG` | `packages/cell-engine/src/beef.zig` | BEEF envelope structure for SPV proofs |
| `LINEARITY-ZIG` | `packages/cell-engine/src/linearity.zig` | LINEAR/AFFINE resource tracking |
| `CELL-TOKEN-TS` | `packages/protocol-types/src/cell-token.ts` | PushDrop output script layout (port to Zig) |
| `MULTICELL-ZIG` | `packages/cell-engine/src/multicell.zig` | Continuation cell packing/unpacking, ContinuationHeader, cell types (BUMP=1, ATOMIC_BEEF=2, ENVELOPE=3, DATA=4, STATE=5), MAX_CONTINUATIONS=64 |
| `CONSTANTS-ZIG` | `packages/cell-engine/src/constants.zig` | CELL_SIZE=1024, PAYLOAD_SIZE=768, CONTINUATION_PAYLOAD_SIZE=1016 |
| `CELL-STORE-TS` | `packages/protocol-types/src/cell-store.ts` | Version chaining via prevStateHash |
| `PHASE-30B` | `docs/prd/PHASE-30B-ADAPTER-CALLBACKS.md` | Callback registration pattern |
| `PHASE-30C` | `docs/prd/PHASE-30C-CAPABILITY-FFI.md` | Capability token + linearity FFI |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming, branch rules |

---

## Existing Foundation

This patch builds on code that already exists in the kernel:

- **sighash.zig** — BIP143 preimage for ALL/NONE/SINGLE with FORKID and ANYONECANPAY. TxContext struct with 256 max inputs/outputs. Transaction parsing via parseTxContext. Streaming hash for large inputs. This patch adds `computeSigHashOriginal()` for the pre-BIP143 algorithm (required by Chronicle mandatory upgrade April 7 2026).
- **beef.zig** — SPV proof structure (BEEF envelope) for transaction verification without a full node.
- **linearity.zig** — LINEAR (exactly-once), AFFINE (at-most-once) resource tracking. Already enforced at cell level.
- **cell-token.ts** — PushDrop output script: cell header + payload + semantic path + content hash + OP_DROP + pubkey + OP_CHECKSIG. This becomes the output script template for transaction chain outputs. Needs porting from TS to Zig.
- **cell-store.ts** — Version chaining via prevStateHash. Each cell write already links to its predecessor — the transaction chain mirrors this at the protocol level.

The critical insight: sighash.zig already computes BIP143 preimages for any SIGHASH combination. CellStore already chains cells via prevStateHash. CellToken already packs cells into PushDrop output scripts. multicell.zig already handles continuation cell packing with typed cell carriage (BUMP, BEEF, ENVELOPE, DATA, STATE). This patch connects these pieces through the FFI boundary.

---

## Multi-Object Output Map

A single transaction may carry multiple semantic objects, each with overflow data and SPV proof attachments. Each primary CellToken output declares its own output span via an **output map** embedded in the PushDrop script.

### Output Map Encoding

The CellToken PushDrop script gains two additional push fields before the OP_DROP sequence:

```
OP_PUSH(cell_header)
OP_PUSH(cell_payload)
OP_PUSH(semantic_path)
OP_PUSH(content_hash)
OP_PUSH(output_map)          ← NEW: 2 bytes [overflow_count:u8, proof_count:u8]
OP_DROP OP_DROP OP_DROP OP_DROP OP_DROP
OP_PUSH(owner_pubkey)
OP_CHECKSIG
```

The `output_map` is a 2-byte push: byte 0 is the number of PushDrop overflow outputs that immediately follow this output, byte 1 is the number of OP_RETURN proof outputs that follow those.

### Transaction Output Layout

```
Output 0:  CellToken A (PushDrop)  [overflow:2, proof:1]
Output 1:  PushDrop continuation   (A state overflow 1/2, cell_type=DATA)
Output 2:  PushDrop continuation   (A state overflow 2/2, cell_type=STATE)
Output 3:  OP_RETURN              (A's BEEF/BUMP proof data)
Output 4:  CellToken B (PushDrop)  [overflow:0, proof:1]
Output 5:  OP_RETURN              (B's BEEF/BUMP proof data)
Output 6:  P2PKH payment output   (change, settlement, etc.)
```

**Navigation rule**: To walk primary outputs in a TX, read output 0's output_map, skip forward by `overflow_count + proof_count`, read the next output — it's either another primary CellToken or a payment output (identifiable by script pattern). Chain verification only follows primary outputs (output_map present).

### Overflow Continuation Outputs (PushDrop)

Each overflow output carries a continuation cell matching the multicell.zig format:

```
OP_PUSH(continuation_header)   ← 8 bytes: cell_type, cell_index, total_cells, payload_size, reserved
OP_PUSH(continuation_payload)  ← up to 1016 bytes
OP_DROP OP_DROP
OP_PUSH(owner_pubkey)
OP_CHECKSIG
```

Overflow outputs are spendable (same owner pubkey as the primary output). Cell types DATA=4 and STATE=5 carry semantic data that exceeds Cell 0's 768-byte payload. The chain spending rule only ever spends the primary output (output 0 of the object's span); overflow outputs are spent in the same TX that spends the primary, keeping the object atomic.

### Proof Carriage Outputs (OP_RETURN)

Proof outputs carry BEEF/BUMP data for the transaction's ancestors:

```
OP_FALSE OP_RETURN
OP_PUSH(proof_type)            ← 1 byte: BUMP=1, ATOMIC_BEEF=2, ENVELOPE=3
OP_PUSH(proof_payload)         ← variable length (no 1KB constraint — BSV OP_RETURN has no size limit post-Genesis)
```

OP_RETURN outputs are provably unspendable — no UTXO set pollution. Unlike overflow PushDrop outputs, proof data is NOT chunked into 1016-byte continuations at the TX level. The full BEEF envelope goes in a single OP_RETURN output. The continuation cell model (1024-byte alignment) is used when proof data is unpacked into the storage layer.

**Streaming case**: When transactions stream unconfirmed between trusted parties, proof outputs may be absent (proof_count=0 in the output_map). The BEEF/BUMP data arrives later when the ancestor TX is mined. The receiving party's `tx_stream_accept` validates the chain without proof outputs; `tx_verify_spv` is called later when proof arrives.

### Mapping to multicell.zig

| multicell.zig layer | Transaction layer |
|---|---|
| Cell 0 (header + 768B payload) | Primary CellToken PushDrop output (output_map present) |
| Continuation cells (DATA=4, STATE=5) | PushDrop overflow outputs (1 per continuation cell) |
| Continuation cells (BUMP=1, ATOMIC_BEEF=2, ENVELOPE=3) | OP_RETURN proof outputs (collapsed: full proof per output, not chunked) |
| MAX_CONTINUATIONS=64 | Max 64 overflow outputs per primary (practical limit ~65KB state data) |
| CELL_SIZE=1024 alignment | Preserved in PushDrop overflow; relaxed in OP_RETURN (proof data unchunked) |

---

## Chronicle Release (Mandatory April 7 2026)

BSV Chronicle is a mandatory node upgrade effective April 7 2026. It re-enables opcodes in both locking and unlocking scripts, restores OP_VER, OP_VERIF, and OP_VERNOTIF, and supports the original SIGHASH algorithm alongside BIP143. This is the network the kernel's transactions land on.

### Dual SIGHASH Algorithm Support

Chronicle enables both SIGHASH algorithms on the network simultaneously:

- **BIP143** (current): structured field-level preimage. Used with FORKID flag.
- **Original** (restored by Chronicle): hash entire serialised TX with modifications per flag type. No FORKID.

Both produce valid signatures post-Chronicle. The kernel must support both because different transitions may warrant different algorithms. The `sighashPolicy` config specifies which:

```json
{
  "from": "completed",
  "to": "approved",
  "role": "approver",
  "sighash": "ALL|FORKID",
  "algorithm": "bip143",
  "linear": true
}
```

Valid values: `"bip143"` (default) and `"original"`. FORKID is BIP143-specific — if algorithm is `"original"`, the SIGHASH flags must NOT include FORKID. The policy loader validates this at init and rejects misconfiguration.

### Opcodes in Unlock Scripts

Chronicle re-enables script execution in input scripts. TxBuilder provides two unlock paths:

- `insertSignature` — P2PKH: `OP_PUSH(sig) + OP_PUSH(pubkey)`. Standard FSM transitions.
- `insertUnlockScript(input_index, script_bytes)` — arbitrary unlock script. Kernel constructs the script; host does not influence it.

### OP_VER Covenants (Deferred)

OP_VER/OP_VERIF/OP_VERNOTIF enable locking script covenants. Not required for this patch. The PushDrop layout doesn't preclude it — covenant logic can be added after OP_CHECKSIG in a future patch.

### Implementation

1. `sighash.zig` gains `computeSigHashOriginal(tx, subscript, sighash_type)` alongside existing `computeSigHash` (BIP143).
2. `SighashPolicy.lookupSighash` returns `SighashResult { flags: u8, algorithm: enum { bip143, original } }`.
3. Policy loader validates FORKID/algorithm consistency at init.
4. TxBuilder selects preimage function based on algorithm field.

---

## The SIGHASH State Machine Model

Each semantic object's lifecycle is a chain of BSV transactions. Each transition creates a new transaction that spends the previous transaction's output. The SIGHASH flags selected for each input determine what the signer commits to.

### SIGHASH Flags as Access Control

| SIGHASH Combination | What the Signer Commits To | Semantic Meaning | Use Case |
|---|---|---|---|
| ALL\|FORKID | All inputs and all outputs. Nothing can change. | Final lock. Immutable commitment. | Approvals, completions, invoice acceptance, final settlement. |
| SINGLE\|ACP\|FORKID | This input and its corresponding output. Others can add inputs/outputs. | Collaboration. Each party signs independently. | Dispatch envelope: REA signs their part, tradie adds theirs. |
| NONE\|ACP\|FORKID | This input only. No commitment to outputs. | Delegation. Staking identity, delegating execution. | Owner pre-authorising maintenance below $X. |
| ALL\|ACP\|FORKID | All outputs but only this input. Others can add funding. | Co-payment. | Strata levies: multiple owners fund one maintenance job. |

### Transaction Chain Example: Dispatch Envelope

| TX | Action | Signer | SIGHASH | Spends | Creates |
|---|---|---|---|---|---|
| TX0 | REA creates maintenance request | REA cert | ALL\|FORKID | — (genesis) | CellToken: MaintenanceRequest in AFFINE state |
| TX1 | REA dispatches to tradie | REA cert | SINGLE\|ACP\|FORKID | TX0:0 | Envelope (RELEVANT) + tradie co-sign slot |
| TX2 | Tradie accepts + adds ROM | Tradie cert | SINGLE\|ACP\|FORKID | TX1:0 | Updated envelope with ROM estimate |
| TX3 | Tradie completes + attaches invoice | Tradie cert | ALL\|FORKID | TX2:0 | Completion state with photos, invoice |
| TX4 | REA approves completion | REA cert | ALL\|FORKID (LINEAR) | TX3:0 | Approval consumed (exactly once) |
| TX5 | Payment settles | REA cert | ALL\|FORKID | TX4:0 | Payment output to tradie address |

Each TX is SPV-verifiable. The chain IS the audit log. The SIGHASH flags ARE the access control.

### SIGHASH Selection is Policy

The kernel selects SIGHASH flags from the vertical config FSM. The host never chooses flags directly.

Example mapping (trades-services.json):

| State Transition | Participant Role | SIGHASH Selection | Rationale |
|---|---|---|---|
| new → dispatched | PM (creator) | SINGLE\|ACP\|FORKID | Opens for tradie co-signature |
| dispatched → in_progress | Tradie (executor) | SINGLE\|ACP\|FORKID | Tradie commits, PM can still add metadata |
| in_progress → completed | Tradie (executor) | ALL\|FORKID | Locks completion evidence |
| completed → approved | PM (approver) | ALL\|FORKID (LINEAR consume) | Exactly-once approval, triggers payment |
| owner pre-auth | Owner (approver) | NONE\|ACP\|FORKID | Delegates output selection to PM |

### Trusted Workflow Streaming

In established relationships, transactions stream unconfirmed between parties. TX1 goes to the tradie's phone immediately; they chain TX2 off it immediately. The whole flow completes in seconds. Transactions hit the chain for anchoring, but participants don't wait for confirmation because the SIGHASH scheme guarantees that neither party can repudiate their signed state transition even before it's mined.

---

## Deliverables

### Sub-Phase 30A.1 — TxBuilder (Zig)

**New file**: `src/ffi/tx_builder.zig`

Transaction template construction in Zig. Constructs raw BSV transactions with multi-object output maps, overflow continuations, and OP_RETURN proof carriage. Manages input/output lists and serialises to wire format.

**Depends on**: sighash.zig (TxContext, TxInput, TxOutput), cell-token.ts (port PushDrop layout to Zig), multicell.zig (ContinuationHeader, cell types)

**Content**:
- `TxBuilder` struct: accumulates inputs and outputs, serialises to raw transaction bytes
- `addInput(prev_txid, prev_vout, script, sequence)` — adds an input referencing a previous output

**Primary output (with output map)**:
- `addCellTokenOutput(cell_header, cell_payload, semantic_path, content_hash, owner_pubkey, overflow_count, proof_count) → u32` — constructs PushDrop output script with embedded output_map `[overflow_count:u8, proof_count:u8]`. Returns output index. The overflow_count and proof_count declare how many subsequent outputs belong to this object.

**Overflow continuation outputs**:
- `addOverflowOutput(continuation_header, continuation_payload, owner_pubkey) → u32` — constructs PushDrop continuation output matching multicell.zig ContinuationHeader format. Used for state data exceeding Cell 0's 768-byte payload (cell_type DATA=4, STATE=5).

**Proof carriage outputs**:
- `addProofOutput(proof_type, proof_payload) → u32` — constructs OP_FALSE OP_RETURN output with proof_type byte (BUMP=1, ATOMIC_BEEF=2, ENVELOPE=3) followed by the full proof payload. No 1KB chunking — BSV OP_RETURN is unconstrained post-Genesis.

**Other outputs**:
- `addPaymentOutput(value, script)` — generic P2PKH or P2SH output
- `serialize() → []u8` — wire format serialisation (version + inputs + outputs + locktime)
- `computePreimage(input_index, subscript, sighash_flags, algorithm) → [32]u8` — delegates to sighash.zig `computeSigHash` (BIP143) or `computeSigHashOriginal` based on algorithm enum
- `insertSignature(input_index, signature_der)` — places DER signature + pubkey into input script (P2PKH path)
- `insertUnlockScript(input_index, script_bytes)` — places arbitrary unlock script bytes (Chronicle-era scripted unlocks)

**Output navigation**:
- `walkPrimaryOutputs() → iterator` — yields primary CellToken output indices by reading each output_map and skipping forward by `overflow_count + proof_count`
- `getObjectOutputSpan(primary_index) → { overflow_start, overflow_count, proof_start, proof_count }` — returns the output range belonging to a primary output

**Verification**:
- Round-trip: `serialize → parseTxContext → serialize` produces identical bytes
- Output map consistency: sum of all `(1 + overflow_count + proof_count)` spans plus payment outputs equals total output count

**Duration**: 4–5 days

---

### Sub-Phase 30A.2 — SIGHASH Policy Engine

**New file**: `src/ffi/sighash_policy.zig`

Reads vertical config FSM rules, maps `(state_transition, participant_role) → SIGHASH flags`. Pure lookup, no I/O.

**Depends on**: 30A.1, vertical config schema

**Content**:
- `SighashAlgorithm` enum: `bip143` (default), `original` (Chronicle-era)
- `SighashResult` struct: `{ flags: u8, algorithm: SighashAlgorithm }`
- `SighashPolicy` struct: loaded from JSON config at init
- `lookupSighash(from_state, to_state, role) → ?SighashResult` — returns SIGHASH flags AND algorithm for the transition
- Unknown transition → returns null (not a default/fallback — the kernel rejects undefined transitions)
- Policy loaded from vertical config's `sighashPolicy` block (new field in config schema)
- Each rule optionally specifies `"algorithm": "bip143"` or `"algorithm": "original"`. Default is `"bip143"`.
- Different verticals produce different SIGHASH mappings (trades vs property management)

**Duration**: 2–3 days

---

### Sub-Phase 30A.3 — FFI: tx_chain_create + tx_chain_extend

**In file**: `src/ffi/exports.zig` (additions to existing)
**Updated file**: `src/ffi/semantos.h` (new declarations)

Wire TxBuilder + SIGHASH policy + host_identity_sign callback through the C ABI.

**Depends on**: 30A.1, 30A.2

This sub-phase includes its own callback registration (`semantos_register_tx_callbacks`) since Phase 30B has not been built. Defines `IdentitySignFn` and `NetworkBroadcastFn` callback types, stored as module-level function pointers. When 30B is eventually built, these callbacks should be absorbed into its unified callback table.

**New functions**:

`semantos_register_tx_callbacks(identity_sign, network_broadcast) → i32`
- Register host-provided callbacks for signing and network broadcast
- `identity_sign` is mandatory (returns SEMANTOS_ERR_CALLBACK_NOT_REGISTERED if null)
- `network_broadcast` is optional (only needed for tx_stream_queue drain)
- Must be called after `semantos_init` and before any `tx_chain_*` function

`semantos_tx_chain_create(path, path_len, state_json, json_len, signer_cert, cert_len, out_tx, out_tx_len) → i32`
- Create genesis transaction for a new semantic object
- Kernel constructs CellToken PushDrop output with output_map, selects SIGHASH_ALL|FORKID for genesis (BIP143 algorithm by default)
- If state_json payload exceeds 768 bytes, kernel packs overflow into continuation outputs (PushDrop, cell_type DATA/STATE) and sets overflow_count in the output_map
- Computes SIGHASH preimage via sighash.zig (algorithm selected from policy)
- Calls `host_identity_sign` callback with preimage, receives DER signature
- Inserts signature, serialises TX
- Returns serialised raw transaction (kernel-allocated, host calls semantos_free)

`semantos_tx_chain_extend(prev_tx, prev_tx_len, prev_vout, state_json, json_len, signer_cert, cert_len, beef, beef_len, out_tx, out_tx_len) → i32`
- Extend a transaction chain by spending prev_tx's primary output
- Kernel parses prev_tx, reads output_map to identify primary vs overflow vs proof outputs, extracts state from primary output to determine current FSM state
- Reads new state from state_json, determines FSM transition
- Looks up SIGHASH result (flags + algorithm) from policy engine (30A.2)
- If beef/beef_len are non-null, attaches BEEF proof data as OP_RETURN output and sets proof_count in the output_map. If null, proof_count=0 (streaming case — proof arrives later).
- Constructs new TX with output_map, overflow outputs if needed, proof outputs if provided
- Computes preimage (BIP143 or original per policy), calls host_identity_sign, inserts signature
- Returns serialised raw transaction

**Duration**: 3–4 days

---

### Sub-Phase 30A.4 — FFI: tx_chain_cosign

**In file**: `src/ffi/exports.zig`
**Updated file**: `src/ffi/semantos.h`

**Depends on**: 30A.3

`semantos_tx_chain_cosign(tx, tx_len, input_index, signer_cert, cert_len, out_tx, out_tx_len) → i32`
- Add a co-signature to an existing transaction (for SINGLE|ANYONECANPAY workflows)
- Kernel adds a new input signed by signer_cert, preserving existing signatures
- Validates that existing signatures remain valid after co-sign
- Returns updated serialised transaction

**Duration**: 2–3 days

---

### Sub-Phase 30A.5 — FFI: tx_chain_verify

**In file**: `src/ffi/exports.zig`
**Updated file**: `src/ffi/semantos.h`

**Depends on**: 30A.3, linearity.zig

`semantos_tx_chain_verify(chain_txs, chain_len, tx_count) → i32`
- Verify a complete transaction chain from genesis to tip
- For each TX: read output_map on primary outputs to identify object spans. Skip overflow and proof outputs when walking the chain — only primary outputs participate in the chain graph.
- Checks: each TX spends correct primary output of previous TX (navigated via output_map)
- All signatures valid under their declared SIGHASH flags and algorithm (recomputes preimage independently using BIP143 or original per the SIGHASH type byte in the signature)
- Output map consistency: overflow_count + proof_count matches actual subsequent output types
- State transitions valid per vertical FSM rules
- LINEAR consumptions are exactly-once (no double-spend in chain)
- Pure computation — no callbacks, no network

**Wire format for chain_txs**: 4-byte count (LE) + for each TX: [4-byte length (LE) + raw TX bytes]. Same pattern as anchor proof serialisation from 30D.

**Duration**: 3–4 days

---

### Sub-Phase 30A.6 — FFI: tx_verify_spv

**In file**: `src/ffi/exports.zig`
**Updated file**: `src/ffi/semantos.h`

**Depends on**: 30A.5, beef.zig

`semantos_tx_verify_spv(tx, tx_len, beef, beef_len) → i32`
- SPV-verify a single transaction against a BEEF envelope (Merkle proof + block headers)
- Offline. No callbacks. Pure computation.
- Returns: 0 (valid), SEMANTOS_ERR_INVALID_PROOF, or other error

**Duration**: 2–3 days

---

### Sub-Phase 30A.7 — FFI: tx_stream_accept + tx_stream_queue

**In file**: `src/ffi/exports.zig`
**Updated file**: `src/ffi/semantos.h`

**Depends on**: 30A.5

`semantos_tx_stream_accept(tx, tx_len, expected_prev_txid) → i32`
- Accept an unconfirmed TX from a trusted counterparty
- Validates: signature correct, SIGHASH flags match expected FSM transition, TX correctly spends expected previous output
- Accepts into local state without chain confirmation
- Returns 0 if valid

`semantos_tx_stream_queue(tx, tx_len) → i32`
- Queue a locally-constructed transaction for network submission
- Stored via StorageAdapter under `_tx_queue/` prefix
- Host's NetworkAdapter drains the queue when connected

**Duration**: 2–3 days

---

### Sub-Phase 30A.8 — Integration Test Suite + Header Update

**Updated files**: `src/ffi/semantos.h`, `src/ffi/exports.zig`
**New file**: `src/ffi/tests/tx_chain_test.zig`

Full integration tests exercising the complete transaction chain round-trip. Updated header with all 8 new function declarations (7 tx_chain functions + 1 callback registration). Verification that header still compiles with `gcc -c`.

**Duration**: 2–3 days

---

## New Callback Signatures

Two new host callbacks, registered via `semantos_register_tx_callbacks()` (defined in sub-phase 30A.3). When Phase 30B is built, these should be absorbed into its unified callback table:

### host_identity_sign
`(cert_id: *const u8, cert_len: u32, sighash_preimage: *const u8, preimage_len: u32, out_sig: **u8, out_sig_len: *u32) → i32`

**Direction**: Kernel → Host

Sign a SIGHASH preimage using the private key associated with cert_id. Host accesses Keychain/Keystore/HSM. Returns DER-encoded signature. The private key never enters the kernel. The preimage never leaves the host's hardware security module.

### host_network_broadcast
`(raw_tx: *const u8, tx_len: u32, out_txid: *u8) → i32`

**Direction**: Kernel → Host

Broadcast a raw transaction to the BSV network. Returns 32-byte txid on success. Host uses platform transport (URLSession, dio, fetch, gRPC).

---

## New Error Codes

Add to the existing error code enum in semantos.h:

- `SEMANTOS_ERR_INVALID_TX = -10` — malformed transaction bytes
- `SEMANTOS_ERR_INVALID_SIGHASH = -11` — SIGHASH flags don't match FSM policy
- `SEMANTOS_ERR_CHAIN_BROKEN = -12` — TX doesn't spend expected previous output
- `SEMANTOS_ERR_FSM_VIOLATION = -13` — state transition not permitted by vertical config
- `SEMANTOS_ERR_SIGNATURE_INVALID = -14` — signature verification failed
- `SEMANTOS_ERR_CALLBACK_NOT_REGISTERED = -15` — required callback not set
- `SEMANTOS_ERR_OUTPUT_MAP_INVALID = -16` — output_map declares overflow/proof counts that don't match actual outputs

---

## Impact on Downstream Phases

| Phase | Current Spec | Required Update |
|---|---|---|
| 30D (Anchor FFI) | Simple hash-in/proof-out | SUPERSEDED. Transaction chain functions replace simple anchoring. 30D becomes a thin wrapper or is deleted entirely, gate tests migrate to 30A.5/30A.6. |
| 30E (WASM) | host_anchor_submit import | Add host_identity_sign and host_network_broadcast to WASM import table. Update JS host reference. |
| 30F (XCFramework/Swift) | HttpAnchorProvider | Implement KeychainSigningProvider for host_identity_sign (Secure Enclave). HttpBroadcastProvider for host_network_broadcast. |
| 30G (Dart FFI) | HttpAnchorAdapter | Implement PlatformSigningAdapter for host_identity_sign (platform channel). HttpBroadcastAdapter for host_network_broadcast. |
| 30I (Offline Queue) | FIFO queue for generic ops | Queue stores serialised raw transactions from semantos_tx_stream_queue. Replay calls host_network_broadcast. Conflict = double-spend detection. |

---

## TDD Gate Tests

### 30A.1 Gates — TxBuilder
- T1: Construct genesis TX with one CellToken PushDrop output with output_map [0,0]. Serialise. Deserialise. Fields match. Output_map bytes parseable.
- T2: Construct spending TX (one input ref genesis output, one new CellToken output). Wire format round-trips.
- T3: TX with 256 inputs (MAX_INPUTS) serialises without overflow.
- T4: Output script matches CellToken PushDrop layout (header + payload + path + hash + output_map + OP_DROP*5 + pubkey + OP_CHECKSIG).
- T30: Construct TX with primary output [overflow:2, proof:1] + 2 PushDrop continuation outputs + 1 OP_RETURN proof output. walkPrimaryOutputs yields correct indices. getObjectOutputSpan returns correct ranges.
- T31: Construct TX with TWO primary outputs (object A [overflow:1, proof:1] + object B [overflow:0, proof:0]) + payment output. Walk primary outputs: yields index 0, then index 3, then index 4 (payment). Output count consistency check passes.
- T32: OP_RETURN proof output contains OP_FALSE OP_RETURN + proof_type byte + raw payload. Payload round-trips.
- T33: PushDrop overflow output contains valid ContinuationHeader matching multicell.zig format.
- T34: State payload >768 bytes produces correct overflow_count in output_map and matching PushDrop continuation outputs.

### 30A.2 Gates — SIGHASH Policy
- T5: Given FSM transition (new → dispatched) and role (PM), returns SighashResult { flags: SIGHASH_SINGLE|ANYONECANPAY|FORKID, algorithm: bip143 }.
- T6: Given FSM transition (completed → approved) and role (approver), returns SighashResult { flags: SIGHASH_ALL|FORKID, algorithm: bip143 }.
- T7: Unknown transition returns null/error (not a default/fallback).
- T8: Policy loaded from vertical config JSON. Different vertical = different SIGHASH mapping.
- T35: Policy rule with `"algorithm": "original"` returns SighashResult with algorithm=original. Omitted algorithm field defaults to bip143.

### 30A.3 Gates — Chain Create/Extend
- T9: semantos_tx_chain_create() returns serialised TX parseable by parseTxContext.
- T10: semantos_tx_chain_extend() produces TX whose input references prev TX's output.
- T11: host_identity_sign callback invoked with correct SIGHASH preimage (verified via mock).
- T12: Signature in output TX validates against signer's public key using computeSigHash.
- T13: SIGHASH flags in signed input match what the policy engine selected.

### 30A.4 Gates — Co-Sign
- T14: semantos_tx_chain_cosign() adds new input without invalidating previous signatures.
- T15: Original signer's SINGLE|ACP signature remains valid after co-sign.
- T16: Co-signer's signature validates independently.

### 30A.5 Gates — Chain Verify
- T17: Valid 3-TX chain (genesis → extend → extend) verifies successfully.
- T18: Tampered transaction in chain (modified output) fails verification.
- T19: Missing transaction in chain (gap) fails verification.
- T20: LINEAR double-consumption returns SEMANTOS_ERR_ALREADY_CONSUMED.
- T21: FSM violation (e.g., new → completed, skipping dispatched) returns SEMANTOS_ERR_FSM_VIOLATION.
- T36: Chain where TX has overflow outputs: verify correctly skips overflow/proof outputs and follows primary output only.
- T37: Chain with mismatched output_map (overflow_count says 2 but only 1 overflow output exists) returns SEMANTOS_ERR_OUTPUT_MAP_INVALID.
- T38: Chain verify with dual-algorithm: TX0 uses BIP143, TX1 uses original SIGHASH. Both verify correctly.

### 30A.6 Gates — SPV Verify
- T22: Valid BEEF envelope with correct Merkle proof returns 0.
- T23: Tampered BEEF (wrong Merkle path) returns SEMANTOS_ERR_INVALID_PROOF.
- T24: BEEF with unknown block header returns error.

### 30A.7 Gates — Stream Accept/Queue
- T25: semantos_tx_stream_accept() with valid unconfirmed TX referencing expected previous returns 0.
- T26: semantos_tx_stream_accept() with TX referencing wrong previous output returns SEMANTOS_ERR_CHAIN_BROKEN.
- T27: semantos_tx_stream_accept() with invalid SIGHASH for FSM transition returns SEMANTOS_ERR_INVALID_SIGHASH.
- T28: semantos_tx_stream_queue() stores TX retrievable via StorageAdapter under _tx_queue/ prefix.
- T29: Queued TXs survive kernel shutdown/restart (persisted, not in-memory).

---

## Security Considerations

### Private Key Isolation
The kernel never holds private keys. Transaction construction: (1) kernel builds TX template with unsigned inputs, (2) kernel computes SIGHASH preimage using sighash.zig, (3) kernel sends preimage to host_identity_sign which signs in hardware, (4) kernel inserts DER signature into input script. Key material never crosses the FFI boundary.

### SIGHASH Preimage Validation
When verifying chains (semantos_tx_chain_verify), the kernel recomputes the SIGHASH preimage independently for each input and verifies the signature against it. A compromised host that returns incorrect signatures produces transactions that fail verification on any other node.

### LINEAR Consumption Atomicity
When a LINEAR cell is consumed via transaction chain, the kernel marks it consumed locally before broadcasting. If broadcast fails, the TX remains in the offline queue. If two nodes attempt to consume the same LINEAR cell, the first TX mined wins — the second is a double-spend rejected by the network.

---

## Open Questions

| # | Question | Impact | Decision By |
|---|---|---|---|
| 1 | Should the SIGHASH policy engine support custom scripts beyond P2PKH + CellToken PushDrop? | 30A.2 | Start of 30A.2 |
| 2 | How to handle first-party transaction malleability (signer changes non-committed fields)? | 30A.5 | Start of 30A.5 |
| 3 | Should tx_chain_verify accept partial chains (last N TXs) or require full genesis-to-tip? | 30A.5 | Start of 30A.5 |
| 4 | Maximum chain depth before performance degrades? sighash.zig handles 256 inputs; chain verification may need pagination. | 30A.5/30A.8 | During 30A.5 testing |
| 5 | Should the offline queue (30A.7) have a maximum size or TTL? | 30A.7 | Start of 30A.7 |
| 6 | When spending a primary output that has overflow outputs, should the overflow outputs be spent in the same TX or left as dust? Spending keeps UTXO set clean; leaving simplifies the chain graph. | 30A.3 | Start of 30A.3 |
| 7 | Chronicle release timeline — when to switch default algorithm from bip143 to original? Feature flag or network height activation? | 30A.2 | Chronicle release date confirmed |
| 8 | Should OP_RETURN proof outputs use a Semantos-specific protocol prefix (e.g., `0x534D5453` = "SMTS") for identification on the public chain? | 30A.1 | Start of 30A.1 |

---

## Completion Criteria

- [ ] `src/ffi/semantos.h` updated with all 8 new function declarations (7 tx_chain + 1 callback registration) and 7 new error codes. Compiles with `gcc -c`.
- [ ] `src/ffi/tx_builder.zig` constructs valid BSV transactions with output_map, overflow PushDrop outputs, and OP_RETURN proof outputs. Parseable by parseTxContext and third-party tools.
- [ ] `src/ffi/tx_builder.zig` supports multi-object transactions: walkPrimaryOutputs navigates correctly across multiple objects with different overflow/proof spans.
- [ ] `src/ffi/sighash_policy.zig` loads rules from vertical config JSON. Returns SighashResult with flags + algorithm. Different verticals produce different SIGHASH selections. Algorithm field defaults to bip143.
- [ ] `sighash.zig` has both `computeSigHash` (BIP143) and `computeSigHashOriginal` (pre-BIP143). Both return `[32]u8`.
- [ ] `src/ffi/exports.zig` implements all 8 new functions with `export fn` and `callconv(.C)`.
- [ ] `host_identity_sign` callback invoked correctly. Private key never enters kernel memory.
- [ ] `host_network_broadcast` callback invoked correctly for queue drain.
- [ ] All 38 gate tests pass across sub-phases 30A.1–30A.7 (original 29 + 9 new for overflow/Chronicle).
- [ ] Chain verification catches: tampered TX, missing TX, FSM violation, double LINEAR consumption, output_map mismatch.
- [ ] SPV verification works offline with BEEF envelopes.
- [ ] Offline queue persists across kernel restart.
- [ ] No stubs, mocks, or hardcoded responses in production code.
- [ ] Phase 30D PRD marked as superseded with cross-reference to this patch.
- [ ] Branch `phase-30a-patch-tx-chain` created, commits follow naming convention, merged to main.
