---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30A-PATCH-TX-CHAIN-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.715526+00:00
---

# Phase 30A Patch Execution Prompt — Transaction Chain FFI & SIGHASH State Machine

> Paste this prompt into a fresh session to execute the Phase 30A Patch.

## Context
You are working in the Semantos kernel (Zig). Phase 30A delivered the C ABI header and core FFI functions (init, shutdown, cell read/write, verify, free, version, last_error). Phases 30B and 30C have NOT been built yet — this patch does NOT depend on them. This patch defines its own callback registration for `host_identity_sign` and `host_network_broadcast` directly in exports.zig, and uses `linearity.zig` internally (Zig-to-Zig) without needing a C ABI linearity surface.

Your task is the Phase 30A Patch: build the transaction chain FFI and SIGHASH state machine. The blockchain is not a timestamping service — it is the enforcement layer. Each state transition is a BSV transaction spending the previous transition's output. SIGHASH flags determine what each signer commits to, creating one-way data check valves. The kernel owns the transaction logic because SIGHASH selection lives inside the proof boundary.

A single transaction can carry multiple semantic objects. Each primary CellToken output declares an **output map** specifying how many subsequent outputs belong to it (overflow PushDrop continuations for state data >768 bytes, OP_RETURN outputs for BEEF/BUMP proof carriage). The chain graph follows primary outputs only — overflow and proof outputs are passengers.

The BSV Chronicle release (mandatory node upgrade April 7 2026) re-enables opcodes in unlock scripts and adds the original SIGHASH algorithm alongside BIP143. This is the network the kernel's transactions land on. This patch implements dual SIGHASH algorithm support (BIP143 and original) and provides both P2PKH and arbitrary unlock script interfaces for Chronicle-era scripted unlocks.

### The Boundary Rule
The kernel computes SIGHASH preimages (BIP143 or original per policy), constructs transaction templates with output maps, and manages overflow/proof output layout. The host signs preimages via `host_identity_sign` (hardware keystore) and broadcasts via `host_network_broadcast` (network transport). The host never sees or influences SIGHASH flag selection or algorithm choice. Private keys never enter the kernel. Every FFI function is `export fn` with `callconv(.C)`.

---

## CRITICAL: READ THESE FILES FIRST
1. **PHASE-30A-PATCH-TX-CHAIN.md** — Phase specification with deliverables 30A.1–30A.8, all 38 gate tests, output map model, and Chronicle forward-compatibility
2. **PHASE-30-FFI-MASTER.md** — FFI architecture, memory ownership model, complete C ABI surface
3. **PHASE-30A-C-ABI-HEADER.md** — Existing Phase 30A pattern, error codes, function signatures you are extending
4. **packages/cell-engine/src/sighash.zig** — BIP143 preimage computation, TxContext, SIGHASH flags, parseTxContext
5. **packages/cell-engine/src/beef.zig** — BEEF envelope structure for SPV proofs
6. **packages/cell-engine/src/linearity.zig** — LINEAR/AFFINE resource tracking
7. **packages/cell-engine/src/multicell.zig** — Continuation cell packing/unpacking, ContinuationHeader (cell_type, cell_index, total_cells, payload_size), MAX_CONTINUATIONS=64
8. **packages/cell-engine/src/constants.zig** — CELL_SIZE=1024, PAYLOAD_SIZE=768, CONTINUATION_PAYLOAD_SIZE=1016
9. **packages/protocol-types/src/cell-token.ts** — PushDrop output script layout (port to Zig)
10. **packages/protocol-types/src/cell-store.ts** — Version chaining via prevStateHash
11. **src/ffi/exports.zig** — Existing FFI exports you are adding to
12. **src/ffi/semantos.h** — Existing C header you are updating
13. **docs/BRANCHING-AND-CI-POLICY.md** — Commit naming conventions, branch rules, CI requirements

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO STUBS
Every function does real work. No `@panic` placeholders, no `return 0 // TODO`, no functions that accept input but ignore it.
- `semantos_tx_chain_create` must actually construct a valid BSV transaction with a CellToken PushDrop output, compute a real SIGHASH preimage, call `host_identity_sign`, and return a wire-format transaction parseable by `parseTxContext`.
- `semantos_tx_chain_verify` must actually walk the chain, recompute every preimage, and validate every signature. Not just check lengths.
- The SIGHASH policy engine must actually load rules from config JSON and apply them. No hardcoded flag values.

### 2. NO ZIG TYPES IN C HEADER
The header file (`semantos.h`) contains ONLY C types: `int32_t`, `uint8_t`, `size_t`, `const char*`, pointers to unsigned byte arrays.
- No `!u32`, no `error!T`, no custom Zig structs.
- Function signatures are callable from C; if a C compiler cannot parse it, you failed.

### 3. BOUNDS CHECK EVERYTHING
Every pointer and length parameter is validated.
- Null pointer input → return error, do not crash.
- Zero length on tx bytes → return error.
- Output buffer length too small → return SEMANTOS_ERR_BUFFER_TOO_SMALL and set required length.
- Transaction exceeding MAX_INPUTS (256) or MAX_OUTPUTS (256) → return SEMANTOS_ERR_INVALID_TX.
- No buffer overflows, no undefined behavior.

### 4. NO HOST REFERENCES HELD
Each FFI call is a self-contained transaction. The kernel does not hold pointers to host-provided buffers after the function returns.
- Copy all host-provided TX bytes into kernel-owned memory before processing.
- Any kernel-allocated buffers returned to host (serialised TXs) are owned by the host (host calls `semantos_free` to release).
- No dangling pointers, no use-after-free.

### 5. SIGHASH FLAGS COME FROM THE KERNEL
The host NEVER chooses SIGHASH flags. The kernel selects flags via the SIGHASH policy engine (30A.2) based on the FSM transition. If you find yourself accepting SIGHASH flags as a parameter from the host, you are violating the proof boundary. Stop.

### 6. OUTPUT MAP IS THE SOURCE OF TRUTH
Every primary CellToken output MUST have an output_map `[overflow_count:u8, proof_count:u8]` embedded in the PushDrop script. Every overflow output MUST be a PushDrop with a valid ContinuationHeader matching multicell.zig format. Every proof output MUST be OP_FALSE OP_RETURN with a proof_type byte. `walkPrimaryOutputs()` MUST skip exactly `overflow_count + proof_count` outputs per primary. If the output_map says 2 overflow and 1 proof, there MUST be exactly 2 PushDrop continuations followed by exactly 1 OP_RETURN at those positions. Mismatches are SEMANTOS_ERR_OUTPUT_MAP_INVALID — never silently ignored.

### 7. NO EASY TESTS
Tests verify actual behavior, not just "function exists" or "does not crash."
- Gate Test T12: Actually verify the signature in the output TX against the signer's public key by recomputing the SIGHASH preimage independently. Not just "no error returned."
- Gate Test T17: Build a real 3-TX chain with valid signatures and verify the whole chain end-to-end. Not "three empty TXs linked by txid."
- Gate Test T20: Attempt to consume a LINEAR cell twice through two different chain extensions. Verify the second one fails. Not "call verify with a flag set."
- Each test must have a clear failure case: what would cause this test to fail? If the answer is "nothing," rewrite the test.

### 8. NO TESTS THAT MATCH BROKEN CODE
Do not write tests that pass against buggy implementations.
- If `computePreimage` always returns zeros, and your test expects zeros, the test is useless.
- If `lookupSighash` hardcodes SIGHASH_ALL for all transitions, and your test only checks that result, the test is useless.
- Every test must exercise a code path that could realistically be wrong.

---

## PART 0: GIT HYGIENE

### 0.1 Assess
```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```
Verify that working directory is clean or contains only expected work-in-progress.

### 0.2 Commit or discard uncommitted work
If there are staged or unstaged changes not related to this patch, commit them explicitly by name or discard them.
```bash
git add <specific_files>
git commit -m "phase-xx/DXX.y: description"
```
Never use `git add -A` — be explicit about what you commit.

### 0.3 Verify prerequisites are complete
Phase 30A must be complete. Phases 30B and 30C are NOT prerequisites. Check that these files exist and contain real implementations:
```bash
ls -la src/ffi/semantos.h           # Phase 30A: C header with 8 function declarations
ls -la src/ffi/exports.zig          # Phase 30A: 8 exported FFI functions
ls -la packages/cell-engine/src/sighash.zig    # BIP143 preimage computation
ls -la packages/cell-engine/src/beef.zig       # BEEF envelope structure
ls -la packages/cell-engine/src/linearity.zig  # Internal linearity enforcement (Zig, not FFI)
ls -la packages/cell-engine/src/multicell.zig  # Continuation cell packing/unpacking
ls -la packages/protocol-types/src/cell-token.ts   # PushDrop output script layout
ls -la packages/protocol-types/src/cell-store.ts   # Version chaining via prevStateHash
```
All files must exist and contain real implementations (not stubs). If anything is missing, STOP and complete that prerequisite.
Note: there is NO callback registration infrastructure yet. This patch creates its own in sub-phase 30A.3.

### 0.4 Create patch branch
```bash
git checkout -b phase-30a-patch-tx-chain
```

---

## Step 1: Sub-Phase 30A.1 — TxBuilder (Zig)

**Objective**: Build the transaction template constructor that produces valid BSV wire-format transactions with multi-object output maps, overflow continuations, OP_RETURN proof carriage, and dual SIGHASH algorithm support.

**Instructions**:
1. Read `packages/cell-engine/src/sighash.zig` thoroughly. Understand TxContext, TxInput, TxOutput, parseTxContext, computeSigHash.
2. Read `packages/protocol-types/src/cell-token.ts` thoroughly. Understand the PushDrop output script layout.
3. Read `packages/cell-engine/src/multicell.zig` thoroughly. Understand ContinuationHeader (cell_type, cell_index, total_cells, payload_size, reserved), ContinuationInput, packMultiCell, unpackMultiCell. This is the format your overflow outputs must match.
4. Read `packages/cell-engine/src/constants.zig`. Note CELL_SIZE=1024, PAYLOAD_SIZE=768, CONTINUATION_PAYLOAD_SIZE=1016.
5. Create file `src/ffi/tx_builder.zig`.
6. Define `TxBuilder` struct:
   ```
   - inputs: array of TxBuildInput (prev_txid, prev_vout, script_sig placeholder, sequence)
   - outputs: array of TxBuildOutput (value, script_pubkey, output_type enum { primary, overflow, proof, payment })
   - version: u32 (default 1)
   - locktime: u32 (default 0)
   - input_count, output_count
   ```
7. Implement `addInput(prev_txid: [32]u8, prev_vout: u32, sequence: u32)`:
   - Appends to inputs array. Script_sig starts empty (filled after signing).
   - Returns input index.
8. Implement `addCellTokenOutput(cell_header: []const u8, cell_payload: []const u8, semantic_path: []const u8, content_hash: [32]u8, owner_pubkey: [33]u8, value: u64, overflow_count: u8, proof_count: u8)`:
   - Constructs PushDrop output script with embedded output_map.
   - Layout: OP_PUSH(cell_header) + OP_PUSH(cell_payload) + OP_PUSH(semantic_path) + OP_PUSH(content_hash) + OP_PUSH([overflow_count, proof_count]) + OP_DROP*5 + OP_PUSH(owner_pubkey) + OP_CHECKSIG.
   - Port the exact byte layout from cell-token.ts, adding the output_map push before the OP_DROP sequence.
   - Tags output as `output_type.primary`.
   - Returns output index.
9. Implement `addOverflowOutput(continuation_header: ContinuationHeader, continuation_payload: []const u8, owner_pubkey: [33]u8, value: u64)`:
   - Constructs PushDrop continuation output.
   - Layout: OP_PUSH(continuation_header as 8 bytes) + OP_PUSH(continuation_payload) + OP_DROP*2 + OP_PUSH(owner_pubkey) + OP_CHECKSIG.
   - ContinuationHeader matches multicell.zig format exactly: cell_type(1) + cell_index(2 LE) + total_cells(2 LE) + payload_size(2 LE) + reserved(1).
   - Tags output as `output_type.overflow`.
   - Returns output index.
10. Implement `addProofOutput(proof_type: u8, proof_payload: []const u8)`:
    - Constructs OP_RETURN output: OP_FALSE + OP_RETURN + OP_PUSH(proof_type) + OP_PUSH(proof_payload).
    - proof_type: BUMP=1, ATOMIC_BEEF=2, ENVELOPE=3.
    - No 1KB chunking — the full proof goes in one output. BSV OP_RETURN has no size limit post-Genesis.
    - Value is 0 (unspendable).
    - Tags output as `output_type.proof`.
    - Returns output index.
11. Implement `addPaymentOutput(value: u64, script_pubkey: []const u8)`:
    - Generic output for P2PKH or any other script.
    - Tags output as `output_type.payment`.
    - Returns output index.
12. Implement `serialize() → []u8`:
    - Wire format: version(4 LE) + varint(input_count) + inputs + varint(output_count) + outputs + locktime(4 LE).
    - Each input: prev_txid(32) + prev_vout(4 LE) + varint(script_sig_len) + script_sig + sequence(4 LE).
    - Each output: value(8 LE) + varint(script_pubkey_len) + script_pubkey.
13. Implement `walkPrimaryOutputs() → iterator`:
    - Yields indices of primary CellToken outputs by reading each output_map and skipping forward by overflow_count + proof_count.
    - Validates: the sum of all spans (1 + overflow_count + proof_count per primary) plus payment outputs equals total output count.
14. Implement `getObjectOutputSpan(primary_index) → { overflow_start, overflow_count, proof_start, proof_count }`:
    - Reads the output_map from the primary output at primary_index. Returns the range.
15. Implement `toTxContext(input_index: u32, input_value: u64) → TxContext`:
    - Converts the builder's state to a TxContext compatible with `computeSigHash`.
16. Implement `computePreimage(input_index: u32, subscript: []const u8, sighash_flags: u8, algorithm: SighashAlgorithm) → [32]u8`:
    - Delegates to `computeSigHash` if algorithm == .bip143, or `computeSigHashOriginal` if algorithm == .original.
17. Implement `insertSignature(input_index: u32, sig_der: []const u8, pubkey: [33]u8)`:
    - Constructs P2PKH script_sig: OP_PUSH(sig_der + sighash_byte) + OP_PUSH(pubkey).
    - Replaces the placeholder in the inputs array.
18. Implement `insertUnlockScript(input_index: u32, script_bytes: []const u8)`:
    - Places arbitrary unlock script bytes (Chronicle-era scripted unlocks).
    - The kernel constructs the script; the host does not influence it.
19. Also in sighash.zig, implement `computeSigHashOriginal(tx: *const TxContext, subscript: []const u8, sighash_type: u8) → [32]u8`:
    - Pre-BIP143 algorithm: serialise entire TX with modifications per SIGHASH type, then double-SHA256.
    - Original Bitcoin SIGHASH algorithm restored by Chronicle (mandatory April 7).
20. Verify round-trip: `builder.serialize()` → `parseTxContext()` → fields match builder state.
21. Verify output map consistency: walkPrimaryOutputs must navigate correctly across multi-object TXs.

**Tests** (inline or temporary — formal tests come in 30A.8):
- T1: Construct genesis TX with one CellToken PushDrop output with output_map [0,0]. Serialise. Deserialise. Fields match. Output_map bytes parseable.
- T2: Construct spending TX (one input ref genesis output, one new CellToken output). Wire format round-trips.
- T3: TX with MAX_INPUTS (256) inputs serialises without overflow.
- T4: Output script matches CellToken PushDrop layout with output_map.
- T30: TX with primary [overflow:2, proof:1] + 2 PushDrop continuations + 1 OP_RETURN. walkPrimaryOutputs yields correct indices.
- T31: TX with TWO primary outputs (A [overflow:1, proof:1] + B [overflow:0, proof:0]) + payment. Walk yields correct primary indices.
- T32: OP_RETURN proof output round-trips (OP_FALSE + OP_RETURN + type + payload).
- T33: PushDrop overflow output contains valid ContinuationHeader matching multicell.zig format.
- T34: State payload >768 bytes produces correct overflow_count and matching continuations.

**Commit**:
```bash
git add src/ffi/tx_builder.zig packages/cell-engine/src/sighash.zig
git commit -m "phase-30a-patch/D30A.1: TxBuilder with output map, overflow continuations, OP_RETURN proof carriage, and dual SIGHASH"
```

---

## Step 2: Sub-Phase 30A.2 — SIGHASH Policy Engine

**Objective**: Build the policy lookup table that maps FSM transitions to SIGHASH flags, loaded from vertical config JSON.

**Instructions**:
1. Create file `src/ffi/sighash_policy.zig`.
2. Define the vertical config schema extension. The vertical config JSON gains a new `sighashPolicy` block:
   ```json
   {
     "sighashPolicy": {
       "transitions": [
         {
           "from": "new",
           "to": "dispatched",
           "role": "pm",
           "sighash": "SINGLE|ACP|FORKID"
         },
         {
           "from": "dispatched",
           "to": "in_progress",
           "role": "executor",
           "sighash": "SINGLE|ACP|FORKID"
         },
         {
           "from": "in_progress",
           "to": "completed",
           "role": "executor",
           "sighash": "ALL|FORKID"
         },
         {
           "from": "completed",
           "to": "approved",
           "role": "approver",
           "sighash": "ALL|FORKID",
           "linear": true
         }
       ],
       "genesis": "ALL|FORKID"
     }
   }
   ```
3. Define `SighashAlgorithm` enum: `bip143`, `original`.
4. Define `SighashResult` struct: `{ flags: u8, algorithm: SighashAlgorithm }`.
5. Define `SighashPolicy` struct:
   - Array of `PolicyRule` (from_state, to_state, role, sighash_flags, algorithm, linear flag).
   - `genesis_sighash: SighashResult` — SIGHASH for genesis TX (usually ALL|FORKID, bip143).
   - Maximum 64 rules (more than enough for any vertical).
6. Implement `SighashPolicy.loadFromJson(json: []const u8) → !SighashPolicy`:
   - Parse JSON. Validate required fields.
   - Map string SIGHASH names to flag constants from sighash.zig.
   - String → flags mapping: "ALL" = 0x01, "NONE" = 0x02, "SINGLE" = 0x03, "ACP" = 0x80, "FORKID" = 0x40. Pipe-separated combinations.
   - Parse optional `"algorithm"` field: `"bip143"` (default) or `"original"` (Chronicle). Omitting defaults to bip143.
   - **Validate FORKID/algorithm consistency**: if algorithm is `"original"` and SIGHASH flags include FORKID, reject at load time. FORKID is BIP143-specific. This catches misconfiguration before any TX is built.
7. Implement `SighashPolicy.lookupSighash(from_state: []const u8, to_state: []const u8, role: []const u8) → ?SighashResult`:
   - Linear scan through rules. Match on (from, to, role).
   - Returns SighashResult (flags + algorithm) on match.
   - Returns null on no match. Caller treats null as SEMANTOS_ERR_FSM_VIOLATION.
   - Do NOT provide a default/fallback. Unknown transitions are rejected.
8. Implement `SighashPolicy.isLinear(from_state: []const u8, to_state: []const u8) → bool`:
   - Returns whether this transition consumes a LINEAR capability.

**Tests**:
- T5: Given (new → dispatched, pm) returns SighashResult { flags: 0xC3, algorithm: .bip143 }.
- T6: Given (completed → approved, approver) returns SighashResult { flags: 0x41, algorithm: .bip143 }.
- T7: Given (new → completed, pm) — undefined transition — returns null/error.
- T8: Load two different vertical configs. Same transition name produces different SIGHASH in each.
- T35: Rule with `"algorithm": "original"` returns SighashResult with algorithm=.original. Omitted field defaults to .bip143.

**Commit**:
```bash
git add src/ffi/sighash_policy.zig
git commit -m "phase-30a-patch/D30A.2: SIGHASH policy engine with JSON-loaded FSM transition rules"
```

---

## Step 3: Sub-Phase 30A.3 — FFI: tx_chain_create + tx_chain_extend

**Objective**: Wire TxBuilder + SIGHASH policy + host_identity_sign callback through the C ABI.

**Instructions**:
1. **Callback registration** — Phase 30B does not exist yet. Define callback registration inline in exports.zig:
   ```
   // Callback function pointer types
   const IdentitySignFn = *const fn(
       cert_id: [*]const u8, cert_len: u32,
       sighash_preimage: [*]const u8, preimage_len: u32,
       out_sig: *[*]u8, out_sig_len: *u32,
   ) callconv(.C) i32;

   const NetworkBroadcastFn = *const fn(
       raw_tx: [*]const u8, tx_len: u32,
       out_txid: [*]u8,
   ) callconv(.C) i32;

   // Thread-local callback storage
   var g_identity_sign: ?IdentitySignFn = null;
   var g_network_broadcast: ?NetworkBroadcastFn = null;
   ```
   Add a registration function:
   ```
   export fn semantos_register_tx_callbacks(
       identity_sign: IdentitySignFn,
       network_broadcast: ?NetworkBroadcastFn,
   ) callconv(.C) i32
   ```
   `identity_sign` is mandatory (returns error if null). `network_broadcast` is optional (only needed for tx_stream_queue drain — streaming works without it).
   Update semantos.h with the callback typedefs and registration function.
   When Phase 30B is eventually built, these callbacks should be absorbed into its unified callback table.

2. In `src/ffi/exports.zig`, add two new exported functions.
3. **`semantos_tx_chain_create`**:
   ```
   export fn semantos_tx_chain_create(
       path: [*]const u8, path_len: usize,
       state_json: [*]const u8, json_len: usize,
       signer_cert: [*]const u8, cert_len: usize,
       out_tx: *[*]u8, out_tx_len: *usize,
   ) callconv(.C) i32
   ```
   - Guard: not initialized → SEMANTOS_ERR_NOT_INIT.
   - Guard: host_identity_sign not registered → SEMANTOS_ERR_CALLBACK_NOT_REGISTERED.
   - Null checks on all input pointers.
   - Parse state_json to extract initial state name and cell payload.
   - Look up genesis SighashResult from policy engine (flags + algorithm).
   - Create TxBuilder.
   - If cell payload ≤ 768 bytes: add single CellToken output with output_map [0, 0].
   - If cell payload > 768 bytes: pack overflow via multicell logic. Add CellToken output with output_map [overflow_count, 0]. Add PushDrop continuation outputs with ContinuationHeader for each overflow chunk (cell_type DATA=4 or STATE=5).
   - Convert to TxContext. Compute SIGHASH preimage via computePreimage(algorithm).
   - Call host_identity_sign(signer_cert, preimage) → receive DER signature.
   - Insert signature into TX. Serialise.
   - Allocate output buffer (kernel-owned), copy serialised TX. Set out_tx and out_tx_len.
   - Return SEMANTOS_OK.
3. **`semantos_tx_chain_extend`**:
   ```
   export fn semantos_tx_chain_extend(
       prev_tx: [*]const u8, prev_tx_len: usize,
       prev_vout: u32,
       state_json: [*]const u8, json_len: usize,
       signer_cert: [*]const u8, cert_len: usize,
       beef: [*]const u8, beef_len: usize,
       out_tx: *[*]u8, out_tx_len: *usize,
   ) callconv(.C) i32
   ```
   - Guard: not initialized → SEMANTOS_ERR_NOT_INIT.
   - Guard: host_identity_sign not registered → SEMANTOS_ERR_CALLBACK_NOT_REGISTERED.
   - Parse prev_tx. Read output_map on primary outputs to identify object spans. Extract current FSM state from primary CellToken output at prev_vout.
   - Parse state_json to determine target state.
   - Look up SighashResult for (current_state → target_state, role).
   - If no policy match → SEMANTOS_ERR_FSM_VIOLATION.
   - Compute txid of prev_tx (double SHA256 of serialised TX).
   - Create TxBuilder. Add input spending prev_tx:prev_vout (the primary output only).
   - Determine output_map: overflow_count from payload size, proof_count = (beef_len > 0 ? 1 : 0).
   - Add CellToken primary output with output_map. Add overflow PushDrop outputs if needed.
   - If beef/beef_len non-null and non-zero: add OP_RETURN proof output (proof_type=ATOMIC_BEEF=2, payload=beef bytes).
   - Compute preimage (BIP143 or original per SighashResult.algorithm). Sign via callback. Insert signature. Serialise.
   - Return SEMANTOS_OK.
4. Update `src/ffi/semantos.h`:
   - Add function declarations for both new functions.
   - Add new error codes: SEMANTOS_ERR_INVALID_TX (-10), SEMANTOS_ERR_INVALID_SIGHASH (-11), SEMANTOS_ERR_CHAIN_BROKEN (-12), SEMANTOS_ERR_FSM_VIOLATION (-13), SEMANTOS_ERR_SIGNATURE_INVALID (-14), SEMANTOS_ERR_CALLBACK_NOT_REGISTERED (-15).
5. Set last_error_msg on every error path.

**Tests**:
- T9: semantos_tx_chain_create() returns serialised TX parseable by parseTxContext.
- T10: semantos_tx_chain_extend() produces TX whose input references prev TX's output (txid match).
- T11: Mock host_identity_sign receives correct SIGHASH preimage.
- T12: Signature in output TX validates against signer's public key.
- T13: SIGHASH flags in signed input match what the policy engine selected.

**Commit**:
```bash
git add src/ffi/exports.zig src/ffi/semantos.h
git commit -m "phase-30a-patch/D30A.3: tx_chain_create and tx_chain_extend FFI functions"
```

---

## Step 4: Sub-Phase 30A.4 — FFI: tx_chain_cosign

**Objective**: Add co-signature support for SINGLE|ANYONECANPAY collaborative workflows.

**Instructions**:
1. In `src/ffi/exports.zig`, add:
   ```
   export fn semantos_tx_chain_cosign(
       tx: [*]const u8, tx_len: usize,
       input_index: u32,
       signer_cert: [*]const u8, cert_len: usize,
       out_tx: *[*]u8, out_tx_len: *usize,
   ) callconv(.C) i32
   ```
2. Parse existing TX. Copy into kernel-owned TxBuilder representation.
3. Add a new input at `input_index` signed by `signer_cert`.
4. Compute SIGHASH preimage for the new input (using the SIGHASH flags from its subscript or policy).
5. Call host_identity_sign. Insert signature.
6. **CRITICAL**: Verify that existing signatures remain valid after the new input is added. This depends on SIGHASH flags — ANYONECANPAY signatures ARE stable when inputs are added; ALL-only signatures are NOT.
7. Re-serialise. Return updated TX.
8. Update semantos.h with function declaration.

**Tests**:
- T14: Add co-signature. Original SINGLE|ACP signature still valid.
- T15: Original signer's SINGLE|ACP signature validates independently after co-sign.
- T16: Co-signer's signature validates independently.

**Commit**:
```bash
git add src/ffi/exports.zig src/ffi/semantos.h
git commit -m "phase-30a-patch/D30A.4: tx_chain_cosign FFI function for collaborative signatures"
```

---

## Step 5: Sub-Phase 30A.5 — FFI: tx_chain_verify

**Objective**: Verify a complete transaction chain from genesis to tip. Pure computation — no callbacks, no network.

**Instructions**:
1. In `src/ffi/exports.zig`, add:
   ```
   export fn semantos_tx_chain_verify(
       chain_txs: [*]const u8, chain_len: usize,
       tx_count: u32,
   ) callconv(.C) i32
   ```
2. Wire format for chain_txs: 4-byte count (LE) + for each TX: [4-byte length (LE) + raw TX bytes].
3. Parse each TX in the chain via parseTxContext.
4. For each TX: read output_map on primary outputs. Use walkPrimaryOutputs logic to identify which outputs are primary, overflow, proof, or payment. Skip overflow and proof outputs when following the chain graph.
5. Validate output_map consistency: for each primary output, verify that overflow_count + proof_count matches the actual number and types of subsequent outputs. Mismatch → SEMANTOS_ERR_OUTPUT_MAP_INVALID.
6. For each TX after genesis:
   a. Verify its input(0) spends the previous TX's primary output. Compute txid of previous TX (double SHA256 of raw bytes), compare to input's prev_txid. The previous TX's primary output is identified by walking its output_map — NOT by assuming output index 0.
   b. Determine the SIGHASH algorithm from the SIGHASH type byte in the signature (FORKID flag present = BIP143, absent = original).
   c. Recompute the SIGHASH preimage using the correct algorithm.
   d. Verify the signature against the preimage and the signer's public key (extracted from previous TX's output script).
   e. Look up the FSM transition implied by the state change. Verify it's permitted by the policy engine.
   f. If the transition is LINEAR, verify no earlier TX in the chain consumed the same capability.
7. Return SEMANTOS_OK if the entire chain is valid.
8. Error returns:
   - SEMANTOS_ERR_CHAIN_BROKEN: TX doesn't spend expected previous output.
   - SEMANTOS_ERR_SIGNATURE_INVALID: signature doesn't match preimage.
   - SEMANTOS_ERR_FSM_VIOLATION: state transition not permitted.
   - SEMANTOS_ERR_ALREADY_CONSUMED (reuse existing linearity error): LINEAR double-consumption.
   - SEMANTOS_ERR_OUTPUT_MAP_INVALID: output_map span doesn't match actual outputs.
9. Update semantos.h.

**Tests**:
- T17: Valid 3-TX chain verifies successfully.
- T18: Tampered TX (modified output value) fails with SEMANTOS_ERR_SIGNATURE_INVALID.
- T19: Missing TX in chain (gap) fails with SEMANTOS_ERR_CHAIN_BROKEN.
- T20: LINEAR double-consumption returns appropriate error.
- T21: FSM violation (skip state) returns SEMANTOS_ERR_FSM_VIOLATION.
- T36: Chain where TX has overflow outputs: verify correctly follows primary output only.
- T37: Chain with mismatched output_map returns SEMANTOS_ERR_OUTPUT_MAP_INVALID.
- T38: Chain with TX0 using BIP143 and TX1 using original SIGHASH: both verify correctly.

**Commit**:
```bash
git add src/ffi/exports.zig src/ffi/semantos.h
git commit -m "phase-30a-patch/D30A.5: tx_chain_verify with FSM and linearity validation"
```

---

## Step 6: Sub-Phase 30A.6 — FFI: tx_verify_spv

**Objective**: SPV-verify a single transaction against a BEEF envelope. Offline, no callbacks.

**Instructions**:
1. Read `packages/cell-engine/src/beef.zig` thoroughly. Understand BEEF structure (Merkle proof + block headers).
2. In `src/ffi/exports.zig`, add:
   ```
   export fn semantos_tx_verify_spv(
       tx: [*]const u8, tx_len: usize,
       beef: [*]const u8, beef_len: usize,
   ) callconv(.C) i32
   ```
3. Parse BEEF envelope from beef bytes.
4. Compute txid of the raw TX (double SHA256).
5. Walk the Merkle path from the BEEF. Verify the txid hashes up to a known Merkle root.
6. Verify the block header contains that Merkle root.
7. Validate block header proof-of-work (hash meets difficulty target).
8. Return SEMANTOS_OK if valid.
9. Update semantos.h.

**Tests**:
- T22: Valid BEEF with correct Merkle proof returns 0.
- T23: Tampered BEEF (wrong Merkle path) returns SEMANTOS_ERR_INVALID_PROOF.
- T24: BEEF with invalid block header (bad PoW) returns error.

**Commit**:
```bash
git add src/ffi/exports.zig src/ffi/semantos.h
git commit -m "phase-30a-patch/D30A.6: tx_verify_spv with BEEF envelope Merkle verification"
```

---

## Step 7: Sub-Phase 30A.7 — FFI: tx_stream_accept + tx_stream_queue

**Objective**: Accept unconfirmed TXs from trusted counterparties and queue local TXs for network submission.

**Instructions**:
1. In `src/ffi/exports.zig`, add:
   ```
   export fn semantos_tx_stream_accept(
       tx: [*]const u8, tx_len: usize,
       expected_prev_txid: [*]const u8,
   ) callconv(.C) i32
   ```
   - Parse TX. Extract input(0) prev_txid.
   - Compare to expected_prev_txid (32 bytes). Mismatch → SEMANTOS_ERR_CHAIN_BROKEN.
   - Verify signature (recompute preimage, check sig).
   - Look up FSM transition from output state. Verify against policy.
   - If SIGHASH flags don't match policy → SEMANTOS_ERR_INVALID_SIGHASH.
   - Accept into local state (write via StorageAdapter under accepted TX prefix).
   - Return SEMANTOS_OK.

2. Add:
   ```
   export fn semantos_tx_stream_queue(
       tx: [*]const u8, tx_len: usize,
   ) callconv(.C) i32
   ```
   - Copy TX bytes into kernel-owned buffer.
   - Write to StorageAdapter under `_tx_queue/<txid_hex>` key.
   - Return SEMANTOS_OK.
   - The host's NetworkAdapter is responsible for draining the queue (calling `host_network_broadcast` for each entry).

3. Queue persistence: stored via StorageAdapter so it survives kernel shutdown/restart.
4. Update semantos.h with both function declarations.

**Tests**:
- T25: Accept valid unconfirmed TX referencing expected previous → returns 0.
- T26: TX referencing wrong previous output → SEMANTOS_ERR_CHAIN_BROKEN.
- T27: Invalid SIGHASH for FSM transition → SEMANTOS_ERR_INVALID_SIGHASH.
- T28: Queued TX retrievable via StorageAdapter under `_tx_queue/` prefix.
- T29: Queue survives kernel shutdown/restart cycle.

**Commit**:
```bash
git add src/ffi/exports.zig src/ffi/semantos.h
git commit -m "phase-30a-patch/D30A.7: tx_stream_accept and tx_stream_queue for trusted workflow streaming"
```

---

## Step 8: Sub-Phase 30A.8 — Integration Test Suite + Header Verification

**Objective**: Full integration tests, final header update, cross-sub-phase verification.

**Instructions**:
1. Create file `src/ffi/tests/tx_chain_test.zig`.
2. Implement a mock `host_identity_sign` callback:
   - Uses a hardcoded test keypair (secp256k1).
   - Signs the provided SIGHASH preimage.
   - Returns DER-encoded signature.
   - Tracks invocation count and last preimage for assertion.
3. Implement a mock `host_network_broadcast` callback:
   - Records submitted raw TX bytes.
   - Returns a deterministic txid (double SHA256 of raw TX).
4. Implement all 38 gate tests, grouped by sub-phase:
   ```
   test "30A.1 T1: genesis TX with output_map serialise/deserialise round-trip" { ... }
   test "30A.1 T2: spending TX wire format round-trip" { ... }
   test "30A.1 T3: MAX_INPUTS serialisation" { ... }
   test "30A.1 T4: PushDrop output script layout with output_map" { ... }
   test "30A.1 T30: multi-output TX with overflow and proof — walkPrimaryOutputs" { ... }
   test "30A.1 T31: two primary objects + payment — walk yields correct indices" { ... }
   test "30A.1 T32: OP_RETURN proof output round-trip" { ... }
   test "30A.1 T33: PushDrop overflow ContinuationHeader matches multicell.zig" { ... }
   test "30A.1 T34: state >768 bytes produces correct overflow" { ... }
   test "30A.2 T5: PM dispatch → SINGLE|ACP|FORKID bip143" { ... }
   test "30A.2 T6: approval → ALL|FORKID bip143" { ... }
   test "30A.2 T7: unknown transition → error" { ... }
   test "30A.2 T8: different vertical, different SIGHASH" { ... }
   test "30A.2 T35: original algorithm rule returns algorithm=original" { ... }
   test "30A.3 T9: tx_chain_create returns parseable TX with output_map" { ... }
   test "30A.3 T10: tx_chain_extend references prev TX primary output" { ... }
   test "30A.3 T11: host_identity_sign receives correct preimage" { ... }
   test "30A.3 T12: signature validates against pubkey" { ... }
   test "30A.3 T13: SIGHASH flags match policy selection" { ... }
   test "30A.4 T14: cosign preserves original signature" { ... }
   test "30A.4 T15: original SINGLE|ACP sig valid post-cosign" { ... }
   test "30A.4 T16: cosigner sig valid independently" { ... }
   test "30A.5 T17: valid 3-TX chain verifies" { ... }
   test "30A.5 T18: tampered TX fails verification" { ... }
   test "30A.5 T19: missing TX fails verification" { ... }
   test "30A.5 T20: LINEAR double-consumption rejected" { ... }
   test "30A.5 T21: FSM violation rejected" { ... }
   test "30A.5 T36: chain with overflow outputs — follows primary only" { ... }
   test "30A.5 T37: mismatched output_map → OUTPUT_MAP_INVALID" { ... }
   test "30A.5 T38: dual algorithm chain (BIP143 + original) verifies" { ... }
   test "30A.6 T22: valid BEEF SPV returns 0" { ... }
   test "30A.6 T23: tampered BEEF returns error" { ... }
   test "30A.6 T24: bad block header returns error" { ... }
   test "30A.7 T25: accept valid unconfirmed TX" { ... }
   test "30A.7 T26: wrong prev txid rejected" { ... }
   test "30A.7 T27: wrong SIGHASH rejected" { ... }
   test "30A.7 T28: queued TX stored under _tx_queue/" { ... }
   test "30A.7 T29: queue survives restart" { ... }
   ```
5. Each test initialises the kernel with `semantos_init`, registers the mock callbacks, exercises the function under test, and shuts down with `semantos_shutdown`.
6. Verify `src/ffi/semantos.h` contains all 8 new function declarations (7 tx_chain + 1 callback registration) and 7 new error codes. Verify it compiles:
   ```bash
   gcc -c src/ffi/semantos.h -o /dev/null
   ```
7. Run all tests:
   ```bash
   zig build test
   ```
   All 38 tests must pass. No skipped, no expected-failure.

**Commit**:
```bash
git add src/ffi/tests/tx_chain_test.zig src/ffi/semantos.h src/ffi/exports.zig
git commit -m "phase-30a-patch/D30A.8: integration test suite with 38 gate tests and updated C header"
```

---

## Post-Step: Verify Completion Criteria

Before merging, verify each criterion:

- [ ] `src/ffi/semantos.h` updated with all 8 new function declarations (7 tx_chain + 1 callback registration) and 7 new error codes. Compiles with `gcc -c`.
- [ ] `src/ffi/tx_builder.zig` constructs valid BSV transactions with output_map, overflow PushDrop outputs, and OP_RETURN proof outputs. Parseable by parseTxContext.
- [ ] `src/ffi/tx_builder.zig` supports multi-object transactions: walkPrimaryOutputs navigates correctly across multiple objects with different overflow/proof spans.
- [ ] `sighash.zig` has both `computeSigHash` (BIP143) and `computeSigHashOriginal` (pre-BIP143). Both return `[32]u8`.
- [ ] `src/ffi/sighash_policy.zig` loads rules from vertical config JSON. Returns SighashResult with flags + algorithm. Defaults to bip143.
- [ ] `src/ffi/exports.zig` implements all 8 new functions with `export fn` and `callconv(.C)`.
- [ ] `host_identity_sign` callback invoked correctly. Preimage matches independent recomputation.
- [ ] `host_network_broadcast` callback invoked correctly for queue drain.
- [ ] All 38 gate tests pass (original 29 + 9 new for overflow/Chronicle).
- [ ] Chain verification catches: tampered TX, missing TX, FSM violation, LINEAR double-consumption, output_map mismatch.
- [ ] SPV verification works offline with BEEF envelopes.
- [ ] Offline queue persists across kernel restart.
- [ ] No stubs, mocks, or hardcoded responses in production code (mocks exist ONLY in test files).
- [ ] `zig build test` runs successfully with no failures.
- [ ] All commits follow naming convention: `phase-30a-patch/D30A.N: description`.

---

## Merge & Tag

```bash
git log --oneline -8  # Verify all commits from 30A.1–30A.8
git checkout main
git merge --no-ff phase-30a-patch-tx-chain -m "Merge phase-30a-patch: Transaction chain FFI and SIGHASH state machine"
git tag v0.30a-patch
git push origin main v0.30a-patch
```

Mark `PHASE-30D-ANCHOR-FFI.md` as superseded:
```bash
# Add "SUPERSEDED by PHASE-30A-PATCH-TX-CHAIN.md" to line 6 of the file
```

---

## Post-Phase: Errata Sprint

In a fresh session, adversarially review the implementation:

1. Can you call `semantos_tx_chain_create` with zero-length state_json? Does it return an error or crash?
2. Can you call `semantos_tx_chain_extend` with a prev_tx that has no CellToken output at prev_vout? What happens?
3. If `host_identity_sign` returns an error, does the FFI function propagate it correctly? Or does it crash / return success?
4. If `host_identity_sign` returns a garbage signature (random bytes), does `semantos_tx_chain_verify` catch it?
5. Can you construct a chain where the same LINEAR cell is consumed in two different branches (fork attack)? Does the verifier catch it?
6. What happens if the vertical config JSON has no `sighashPolicy` block? Does `SighashPolicy.loadFromJson` return a clear error?
7. Can you call `semantos_tx_stream_accept` with a TX whose SIGHASH is valid for the FSM but the signature is invalid? Does it reject?
8. Is the `_tx_queue/` prefix collision-safe? What if two TXs have the same txid prefix? (They shouldn't — txids are unique, but verify the key format.)
9. Does `semantos_tx_chain_cosign` handle the case where the TX already has the maximum number of inputs?
10. What is the maximum chain length that `semantos_tx_chain_verify` can handle before stack overflow or timeout?
11. Can you construct a TX with output_map [255, 255] (max overflow + max proof)? Does the builder handle it or reject it?
12. What happens if an OP_RETURN proof output is placed BEFORE the overflow PushDrop outputs (violating the output_map ordering)? Does the verifier catch it?
13. Can you construct a multi-object TX where object A has overflow outputs and object B has proof outputs? Does walkPrimaryOutputs navigate correctly across the boundary?
14. What happens if `computeSigHashOriginal` is called with a FORKID flag? (FORKID is BIP143-specific — original algorithm doesn't use it.) Does it error or silently produce a wrong hash?
15. If a ContinuationHeader in an overflow output has cell_type=BUMP (1) instead of DATA (4), does the verifier reject it? Proof data should only appear in OP_RETURN outputs, not PushDrop overflow.

File any bugs as separate commits on main.
