---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/LINEAR-CELL-SPV-STATE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.729187+00:00
---

# Linear Cells as SPV State Machines

**Status:** design locked 2026-05-30; **revised 2026-05-31** to drop the
WASM-handler framing in favor of cell-engine scripts dispatched through
the C10 PolicyRuntime adapter. PR-C11-7c ships this doc only;
PR-C11-7d through 7k implement against it.

**Owner:** the C11 ("me" surface + wallet) track.

**Companions:**
- `docs/design/REAL-EXECUTOR-WIRE.md` — C10 PolicyRuntime adapter (the substrate scripts run on)
- `docs/design/BRAIN-GENERIC-MINT-VERB.md` — manifest-driven typeHash dispatch (the mint shape)
- `docs/design/WALLET-RENDERER-CONTRACT.md` — the Dart-shell wallet contract
- `docs/design/PLEXUS-ALIGNMENT.md` — Plexus recovery + edge derivation alignment
- `docs/design/CANONICAL-CARTRIDGE-MODEL.md` — cartridge / cell-type relationship
- `docs/design/PLATFORM-WALLET-ARCHITECTURE.md` — broader wallet architecture
- `docs/textbook/11-2pda-cell-engine.md` — the cell-engine 2PDA (the execution substrate)
- `memory/mnca_anchor_onchain_mainnet.md` — proven MNCA anchor path on mainnet
- `memory/cell_engine_static_5mb_unfit_for_mcu.md` — embedded build constraints
- `memory/cell_wire_format_location.md` — 1024-byte cell layout authority

**Existing code this composes:**
- `core/cell-engine/src/pda.zig` + `executor.zig` — the cell-engine 2PDA
- `core/cell-engine/src/opcodes/{standard,plexus,routing,macro,hostcall}.zig` — ~108 opcodes including OP_CALLHOST (0xD0), OP_CHECKCAPABILITY (0xC3), OP_CHECKIDENTITY (0xC4), OP_CELLCREATE (0xCA)
- `core/cell-engine/src/beef.zig::verifyBeefSpv` — the BEEF SPV primitive
- `runtime/semantos-brain/src/policy_runtime.zig::evaluateReal` — PolicyRuntime adapter wrapping the cell-engine 2PDA
- `runtime/semantos-brain/src/spv_cap_verifier.zig` — Zig wrapper of verifyBeefSpv
- `runtime/semantos-brain/src/broker.zig::host_verify_beef_root` — capability-gated hostcall
- `runtime/semantos-brain/src/host_capability_table.zig` — hostcall name → capability registry
- `core/protocol-types/src/ports/spv-port.ts::SpvVerifier` — the TS port
- `cartridges/wallet-headers/brain/src/beef-codec.ts` — TS BEEF/BUMP codec (reference)
- `cartridges/wallet-headers/brain/src/spv-verifier.ts` — TS reference verifier

---

## §0 TL;DR

A **linear cell** is the canonical Semantos primitive that binds a
piece of state to a single 1-sat BSV UTXO. Its full identity is the
tuple

```
(anchor UTXO, cell payload, BEEF carriage chain)
```

— inseparable. The on-chain UTXO commits (via OP_PUSHDROP) to the
payload hash; the BEEF is the SPV proof the UTXO exists; the payload
is the application-level state.

State transitions are **atomic** from the operator's perspective:
the cell-engine consumes the old anchor + verifies its BEEF, computes
the new payload deterministically, builds and signs the spending tx,
appends it to the BEEF, persists the new linear cell, and broadcasts
to ARC — all as one transactional unit. Failure at any step rolls back
the local cell store. SPV reconciliation (pending → confirmed) is an
explicit follow-on cell.

The shape covers every wallet operation we care about:

- **Receive** (BRC-29 incoming): the inbound payment becomes a fresh
  linear cell whose anchor is the sender's funding output and whose
  BEEF is whatever the sender handed over.
- **Send** (BRC-29 outbound, MNCA anchor transition, cell anchor mint):
  consumes one or more linear cells, mints fresh ones, emits the
  outbound BEEF to the peer.
- **Validate** (standalone SPV check): wraps `host_verify_beef_spv`
  as a single-shot verify cell with no state change.

Dart's role shrinks to identity custody + sign-digest + a thin cell
dispatcher transport. **The cell-engine owns BEEF, tx, broadcast.**
Each cell type's handler is a small cell-engine script (cell-engine
bytecode declared in the cartridge manifest, dispatched through
PolicyRuntime); the new substrate work is the host-call registration
set, which carves cleanly on embedded targets.

---

## §1 The model: linear cells as SPV state machines

### §1.1 What a linear cell is

```
struct LinearCell {
  anchor:    AnchorRef,       // (txid, vout, satoshis=1, scriptPubKey)
  payload:   Bytes,           // application-defined state (≤1KB in
                              // the cell itself; carriage extension
                              // for larger payloads)
  beefHead:  CellHash,        // head of the BEEF carriage chain
  status:    Status,          // pending | confirmed | spent | failed
  leafPk:    CompressedPub,   // the spending key
  cellType:  TypeHash,        // 32-byte cell-type id
}

struct AnchorRef {
  txid:          Bytes32,
  vout:          uint32,
  satoshis:      uint64,      // always 1 for linear cells
  scriptPubKey:  Bytes,       // OP_PUSHDROP { payloadHash leafPk OP_CHECKSIG }
                              // — committed to the payload
}
```

The `scriptPubKey` MUST commit to `sha256(payload)` via the PushDrop
data field — the verifier recomputes and rejects mismatches. This
binds the on-chain anchor to the off-chain payload immutably.

### §1.2 The transition contract

A linear cell at state `S` mutates to state `S'` via a
**transition intent cell** that names the cell type's transition
function and the inputs it needs. The cell-engine runs:

```
1. SPV-verify the current anchor's BEEF
   (host_verify_beef_spv against trusted roots).
2. Verify the PushDrop commitment matches the stored payload
   (recompute sha256(payload), compare to script's pushdata).
3. Apply the cell type's deterministic transition fn:
     S' = T(S, intent.inputs)
   The transition fn is the cell-engine script declared in the cell
   type's manifest entry, executed on the 2PDA. Total + bounded by
   the executor's opcount + script-size + nesting caps.
4. Build the spending tx:
     input  = current anchor UTXO
     output = new 1-sat output with PushDrop committing to sha256(S')
   Optionally additional outputs for change / counterparties.
5. Request a signature for the input from Dart
   (sign-digest request cell — priv never crosses FFI; §3.6).
6. Assemble the signed tx + extend the BEEF chain.
7. Persist the new linear cell (status = pending) + new carriage
   chain. Mark old cell's status = spent.
8. Broadcast via host_broadcast_arc.
9. Watch for confirmation; on first sufficient-work merkle proof,
   flip status pending → confirmed.
10. On reorg: emit a status-change cell flipping confirmed → pending
    (or pending → failed if the spend reorgs out and the input still
    has spendability).
```

Steps 1–8 are atomic in the cell-engine's local store. Step 9–10 are
async; they cause additional status-change cells to land.

### §1.3 Why this is the right abstraction

- **One primitive covers BRC-29 receive, BRC-29 send, MNCA anchor
  transition, multi-party covenants, and recovery.** They differ only
  in their cell-engine script — the substrate is the same.
- **SPV is structural, not bolted on.** Every linear cell carries its
  own proof. There's no "this UTXO is funded, trust us" — the BEEF is
  always there.
- **State is auditable.** A future operator can be handed the cell +
  its BEEF chain and SPV-verify the entire history back to coinbase
  without any side channel. This is the BRC-29 §Recipient Validation
  property generalised.
- **Composability.** Carriage cells are already how the cell-DAG
  handles >1KB payloads. BEEFs naturally chunk into them.
- **Determinism.** The transition fn has no side effects; every
  cell-engine instance reaches the same `S'` from the same `(S,
  inputs)` tuple. Reproducible across operator devices.

---

## §2 Cell types catalog

All cell types in this doc live under the `bsv.spv.*` and
`bsv.linear.*` namespaces. They land as part of PR-C11-7e.

### §2.1 Substrate types

| Type | Purpose | Persistent? | Carriage chain? |
|---|---|---|---|
| `bsv.linear.anchor` | The linear-cell state record itself. | Yes | Points at `bsv.beef.carriage.head` |
| `bsv.beef.carriage.head` | First chunk of a BEEF, carries length + chain head. | Yes | Points at next `bsv.beef.carriage.body` |
| `bsv.beef.carriage.body` | Subsequent BEEF chunks. | Yes | Chains predecessor → successor by hash |
| `bsv.linear.status` | Status-change notice (pending → confirmed, reorgs). | Yes | None |

### §2.2 Operation intent / result types

| Type | Direction | Purpose |
|---|---|---|
| `bsv.spv.verify.intent` | Dart → engine | Standalone BEEF check (no state change). Carries beefHead. |
| `bsv.spv.verify.result` | engine → Dart | `{ valid: bool, txid, error? }` |
| `bsv.linear.transition.intent` | Dart → engine | Consume old anchor + mint new. Carries oldAnchorRef, cellType, transitionInputs. |
| `bsv.linear.transition.result` | engine → Dart | `{ newAnchor, newBeefHead, broadcastTxid, error? }` |
| `bsv.brc29.internalize.intent` | Dart → engine | Internalize an incoming BRC-29 payment. Carries beefHead, outputIndex, remittance. |
| `bsv.brc29.internalize.result` | engine → Dart | New `bsv.linear.anchor` cell + carriage chain. |
| `bsv.tx.sign.request` | engine → Dart | "Sign this digest for input N under recipeId+index." |
| `bsv.tx.sign.response` | Dart → engine | The 64-byte (r,s) signature. |
| `bsv.tx.broadcast.intent` | Dart → engine | Standalone broadcast (when not bundled into a linear transition). |
| `bsv.tx.broadcast.result` | engine → Dart | `{ txid, accepted, arcStatus, error? }` |

### §2.3 Discovery + recovery types

| Type | Purpose |
|---|---|
| `bsv.recovery.scan.intent` | Walk recipes, regenerate addresses, fetch BEEFs, materialise linear cells. Big batched op. |
| `bsv.recovery.scan.progress` | Stream-of-progress cells the engine emits during a long scan. |
| `bsv.recovery.scan.result` | Final summary: cells discovered, value found, gaps. |

### §2.4 Wire shapes

Each intent/result type is one cell (≤1024 bytes) carrying:

```
struct CellHeader {
  cellType:   TypeHash,
  payloadLen: uint16,
  ownerId:    Bytes16,     // identifies the requesting operator
  flags:      uint8,
  // ...per core/protocol-types/src/constants.ts
}
```

Payloads bind to the type by manifest. For intent/result cells with
data > 1024 bytes (BEEFs, tx hexes, etc.), the cell body carries a
**reference to a carriage-chain head**, not the bytes themselves —
the chain is rebuilt before the cell-engine consumes the operation.

---

## §3 Hostcall ABI

Hostcalls are Zig functions registered in
`runtime/semantos-brain/src/host_capability_table.zig`. Scripts
invoke them via `OP_CALLHOST` (opcode 0xD0). Each registration carries
a capability tag; the cell-engine refuses dispatch if the executing
cell-type's manifest doesn't declare the capability, and the broker
re-checks at call time.

### §3.1 The OP_CALLHOST dispatch

A cell-engine script invokes a hostcall by pushing the function name
onto the main stack (as UTF-8 bytes), then executing `OP_CALLHOST`
(0xD0). The opcode:

1. Pops the function name from the main stack.
2. Looks up the entry in `host_capability_table`.
3. Verifies the entry's capability tag is declared in the executing
   cell type's `handler.capabilities` manifest field.
4. Invokes the registered Zig function. The function reads its
   inputs from a pre-set `ExecutionContext` (not from the stack —
   the stack only carries the function name). Some hostcalls read
   additional inputs from cells previously pushed onto the stack
   via OP_DEREF_POINTER (0xC8) + OP_READPAYLOAD (0xCC).
5. Pushes the result onto the main stack (typically `0`/`1` for
   booleans, or a Bytes32 for hashes).

Structurally simpler than the previous WASM-imports model: no linear
memory, no per-module import table, just a global capability table
the cell-engine references by string at runtime. The hostcall surface
is a thin Zig API; no marshaling.

### §3.2 Core hostcalls (always present, no capability required)

These ship in every cell-engine build target including embedded:

```
host_sha256        — SHA-256(data) → Bytes32
host_sha256d       — double SHA-256(data) → Bytes32
host_ripemd160     — RIPEMD-160(data) → Bytes20
host_hash160       — RIPEMD-160(SHA-256(data)) → Bytes20
host_hash256       — double SHA-256(data) → Bytes32
host_checksig      — secp256k1 ECDSA verify
host_checkmultisig — m-of-n multisig verify
host_log           — structured log (debug only; audit-truncated)
host_load_cell     — read a cell by content hash
host_persist_cell  — write a cell to the cell store
host_fetch_cell    — octave-addressed cell read
```

**No `host_alloc`**: the cell-engine is stack-based. Working memory
is the main stack (1024×1KB at full build, 16×1KB at embedded) plus
the aux stack (256×1KB / 2×1KB). Larger working sets span multiple
cells via OP_CELLCREATE + host_persist_cell.

**No `host_now_ms`** in deterministic execution paths: the cell-engine
is deterministic by construction; clock reads break that property.
Where wall time is needed (e.g., audit timestamps), the brain stamps
it at emit, not the script.

### §3.3 SPV hostcall (capability: `cap.spv.verify`)

```
host_verify_beef_spv — pop beef-cell-hash, return 0=valid / non-zero=error
```

This is the existing `core/cell-engine/src/beef.zig::verifyBeefSpv`
bound via `broker.zig`. PR-C11-7d landed this binding and lifted the
broker capability gate from "wallet-engine-only" to `cap.spv.verify`.

Trusted roots are the brain's local-chain roots; the broker wraps the
existing `LocalChainTracker` so the verifier composes against
PoW-verified headers automatically.

### §3.4 Tx-builder hostcalls (capability: `cap.tx.build`)

```
host_build_tx   — pop input/output cell hashes + nLockTime,
                  push tx-cell hash (BSVZ tx builder under the hood)
host_build_beef — pop base-beef cell hash + spend-tx cell hash,
                  push extended beef-cell hash
```

Wrappers around BSVZ's tx + BEEF builders. Stateless; no priv touches
this layer. Inputs and outputs are referenced by cell hash, the
builder reads payloads via `host_load_cell`.

### §3.5 Sign-digest request (capability: `cap.tx.sign`)

Signing is **not** a synchronous hostcall — the cell-engine is
loop-free, scripts run to completion. The signing protocol is **two
cells**:

1. The script emits a `bsv.tx.sign.request` cell carrying the digest
   + derivation context, then returns.
2. The brain's mint pipeline forwards the request cell to Dart via
   the CellDispatcher.
3. Dart's `WalletKeyService` derives the key, signs the digest,
   returns a `bsv.tx.sign.response` cell.
4. The brain dispatches the response cell as input to a follow-on
   script (typically the next state-transition of the same linear
   cell). That script reads the signature off the response cell and
   completes the transition.

This is the cell-engine-native pattern: each step is a cell;
transitions chain via cell emission. No script-side suspension
required, and the priv never enters Zig memory because signing
happens in Dart's process.

`cap.tx.sign` therefore gates the right to *emit* a
`bsv.tx.sign.request` cell — enforced by the cell-engine's emit
allowlist on the cell type's manifest entry.

### §3.6 Broadcast hostcall (capability: `cap.tx.broadcast`)

```
host_broadcast_arc — pop beef-cell hash, push (status, txid) cell hash
```

Wraps the brain's existing ARC client. For embedded targets that
can't reach ARC, the hostcall is simply not registered — scripts
that need it fail at OP_CHECKCAPABILITY before they reach the
hostcall site.

### §3.7 Why the sign step is two cells, not a callback

Two reasons:
- **Security**: priv stays in Dart's `SecureStore`-backed memory.
  The Zig host process is treated as semi-trusted; sufficient for tx
  building + broadcast, but not custody.
- **Hardware-key compatibility**: when the operator's identity is
  backed by a secure-enclave key handle (PR-D-O5m.followup-2),
  signing goes through a platform MethodChannel that Zig can't
  reach. The two-cell pattern composes naturally — Dart owns the
  signing turn.

---

## §4 Atomicity contract

### §4.1 The unit of atomicity

A linear-cell transition is atomic over:

- the **local cell-store delta** (old cell's status flip to spent +
  new cell + carriage chain insert), AND
- the **broadcast outcome** (ARC accepts the tx).

If broadcast fails, the local delta rolls back. If broadcast succeeds
but the engine crashes before committing the local delta, on restart
the engine re-broadcasts (idempotent — ARC dedupes by txid) and
re-attempts the commit.

### §4.2 What atomicity does NOT cover

- **On-chain confirmation.** The tx may sit in ARC's mempool for an
  unbounded time, get reorged out, be RBF'd by a fee-bump (BSV
  doesn't RBF in practice but the cell-engine doesn't assume),
  etc. SPV reconciliation lives in §4.4.

- **Side-channel delivery.** If the new BEEF carries an output for a
  counterparty (BRC-29 outbound), getting that BEEF + remittance to
  the counterparty is the caller's job — it happens via a separate
  cell (`bsv.brc29.outbound.send`) post-broadcast. If that fails the
  payment is still on-chain; the counterparty just doesn't know yet.
  Retryable.

- **External invariants.** A transition fn can't reach outside the
  cell — no DNS, no HTTP, no clock that matters for consensus. The
  only world it talks to is its host calls, which are deterministic
  modulo the SPV + tx-broadcast results.

### §4.3 Failure model + rollback

Any non-zero return from any host call in steps 1–8 aborts the
transition. The cell-engine emits a `bsv.linear.transition.result`
cell with `{ status: "failed", reason }`, and the local store is
left exactly as it was before the intent landed.

For brand-new mints (no input cell yet — e.g., genesis of a new
linear cell), step 4's "old anchor" is null; the transition becomes
"build + sign + broadcast + persist" with no spend input. Failure
modes collapse symmetrically.

### §4.4 SPV reconciliation (status flips)

After a successful broadcast, the new cell is `status = pending`.
The cell-engine subscribes (internally, no new Dart code) to header
events. On each new header that lands on the brain's chain tracker,
the engine re-checks: does the BEEF I built for this cell now SPV?
If yes (a sufficient merkle proof reaches a header in the trusted
chain), emit `bsv.linear.status { from: pending, to: confirmed }`
and flip the cell's status field.

On reorg: emit `bsv.linear.status { from: confirmed, to: pending }`
(or `from: pending, to: failed` if the spent input UTXO was
double-spent in the reorg-winning branch). The renderer's UTXOs panel
reflects this via `utxos.list` push.

### §4.5 Failure of the brain itself

If the brain hosting cell-engine crashes mid-step-8, on restart it
replays the WAL (cell-engine already has WAL via cell_handler.zig per
the C10 work). Idempotent broadcast handles the case where the tx
already reached ARC.

---

## §5 Carriage-cell chunking

BEEFs routinely exceed 1024 bytes — a single mainnet tx with a
moderate ancestor set is 4–20 KB; deeper provenance can hit hundreds
of KB. Carriage cells chain them.

### §5.1 The chunking algorithm

```
input:  beef_bytes: []u8
output: cells: []Cell where cells[0].cellType = bsv.beef.carriage.head
                  and cells[1..].cellType = bsv.beef.carriage.body
                  and each cells[i].payload is a 960-byte slice of
                      beef_bytes (the 64-byte budget left over is
                      header + predecessor-hash + length fields)
                  and cells[i].payload[0..32] = hash(cells[i+1])
                      for the chain link, or zeros for the terminal.

chunk_size  = 960
n           = ceil(len(beef_bytes) / chunk_size)
cells       = new Cell[n]
for i in n-1 down to 0:
  succ_hash = if i == n-1 then zeros(32) else hash(cells[i+1])
  payload   = beef_bytes[i*chunk_size .. (i+1)*chunk_size]
  cells[i].cellType    = if i == 0 then HEAD else BODY
  cells[i].payload     = succ_hash || varint(total_len) || payload
  cells[i].header.size = header_overhead + len(cells[i].payload)
end
return cells   // cells[0] is the head; its hash is the BEEF's
               // carriage-chain identity.
```

The 960-byte chunk size leaves room for the cell header (62 bytes
per `core/protocol-types/src/constants.ts`) + the 32-byte successor
hash + a 2-byte length field, all within the 1024-byte cell.

### §5.2 Reassembly

The engine walks `head → body → body → ... → terminal` accumulating
`payload[32+varint_len..]` slices. Total length is recorded in the
head cell for a fast preflight check.

Reassembly is bounded by `total_len` from the head — a malicious
chain claiming a 10 GB BEEF gets rejected before the walk starts.

### §5.3 Garbage collection

A linear cell's BEEF carriage chain is referenced by exactly one
linear cell. When that linear cell's status flips to `spent` AND
exceeds the operator's GC retention window (default: keep 6 months
of spent cells for recovery rebuild), the chain becomes unreferenced
and may be GC'd. Recovery scanner depends on this retention window —
shorter windows lose history.

### §5.4 Sharing chains between cells

When two linear cells share the same funding ancestry (e.g., two
outputs from the same incoming BRC-29 payment), they share the
**root** of the BEEF chain — each cell references the head; the
underlying body cells are deduplicated by hash. The cell store is
content-addressed so dedup is automatic.

---

## §6 Dart cell dispatcher

### §6.1 What it is

A new Dart module at `apps/semantos/lib/src/cells/` exposing:

```dart
abstract class CellDispatcher {
  /// Send a cell to the cell-engine and await a result cell. May
  /// emit progress cells while running (delivered via [onProgress]).
  Future<Cell> dispatch(
    Cell input, {
    void Function(Cell progress)? onProgress,
    Duration? timeout,
  });

  /// Subscribe to engine-emitted cells targeting this operator that
  /// weren't responses to a dispatch (status flips, recovery
  /// progress, etc.). Returns until disposed.
  Stream<Cell> subscribe({String? cellType});
}
```

Two implementations:

- **`HttpCellDispatcher`** — talks to brain over HTTP (cells-over-HTTP
  transport; see §6.2). Production default.
- **`InMemoryCellDispatcher`** — for tests, runs an in-process
  cell-engine stub that handles a fixed set of cell types.

### §6.2 Cells-over-HTTP transport (v1)

Each `dispatch` call is a `POST /api/v1/cells` with body:

```
Content-Type: application/x-semantos-cell-chain
Authorization: Bearer <token>
X-Cells-Count: <N>

<cell_0_bytes> <cell_1_bytes> ... <cell_N-1_bytes>
```

Where the body is the concatenation of N cells in dispatch order
(carriage chain bodies first, then the intent head). Cells are
length-delimited by their `payloadLen` header field; the receiver
parses sequentially.

Response is the same shape — a chain of cells, terminating in the
result cell. Progress cells are streamed via SSE if the engine emits
them mid-execution.

For long-running ops (recovery scan), the dispatcher upgrades to WSS
on the brain's existing WSS endpoint; cells stream over the same
subprotocol the federation work in C2c uses.

### §6.3 Why HTTP first (not a fresh cell-protocol port)

- The brain already serves bearer-gated HTTP on the operator's
  domain; adding `/api/v1/cells` reuses existing transport, auth,
  TLS, rate-limiting.
- Same-origin / mobile-friendly. The Dart wallet sheet already does
  HTTP over the loopback `wallet_asset_server`.
- A native cell-passing protocol (the obvious long-term answer for
  federation + offline mesh) doesn't block this work. It can come in
  a later wave; the `CellDispatcher` abstraction lets us swap
  transports without changing call sites.

### §6.4 Authentication

The bearer-gated HTTP transport already authenticates the operator
to their brain. Cells inside the request carry the same `ownerIdHex`
field they always do; the brain cross-checks the bearer's
operator-cert-id matches every cell's owner before passing them into
the engine. This prevents a stolen bearer from injecting cells for a
different operator.

---

## §7 Capability gating

Each hostcall is registered in
`runtime/semantos-brain/src/host_capability_table.zig` with a name
string and a capability tag:

| Capability | Hostcalls gated |
|---|---|
| `cap.spv.verify` | `host_verify_beef_spv` |
| `cap.tx.build` | `host_build_tx`, `host_build_beef` |
| `cap.tx.sign` | (no hostcall — the right to emit `bsv.tx.sign.request`) |
| `cap.tx.broadcast` | `host_broadcast_arc` |

Every cell-type handler declares its required capabilities in its
manifest entry under `cellTypes[i].handler.capabilities` (matching
the existing `extensions/<id>/cartridge.json` capability field
shape). The cell-engine refuses to load the handler script if the
operator hasn't granted the capabilities; the broker re-checks at
hostcall time.

Granted capabilities live in the operator's identity cert's
`capabilities` field (already present on
`apps/semantos/lib/src/identity/child_cert_store.dart::
ChildCertRecord.capabilities`). Plexus envelope persists them.

A `bsv.linear.anchor` cell type's handler declares all four. A
`bsv.spv.verify.intent` cell type's handler declares only
`cap.spv.verify`. An embedded sensor cell type's handler declares
none and never sees BSV-related hostcalls.

**Two-layer gating:**
1. **Script-side** — `OP_CHECKCAPABILITY` (0xC3) reads a capability
   byte off a cell payload and pushes TRUE if it matches. Used
   inside scripts to gate behavior based on a presented capability
   from an input cell.
2. **Broker-side** — `broker.checkInvocationCapabilities` (the typed
   gate preserved through the 2PDA-WASM excise) is the authorization
   check the dispatcher calls before invoking the handler script.
   Currently fail-closed for `require_cert == true`; un-parks with
   the Phase-1b BCA cert verifier.

---

## §8 UTXO store as projection

PR-C11-7a's `UtxoStore` becomes a **read-only projection** of the
cell-store. The cell-store is the source of truth; the UtxoStore is a
flat, fast-to-query view the renderer needs.

### §8.1 The projection

```
cell-store row                              UtxoRow projection
─────────────                              ──────────────────
bsv.linear.anchor {                         {
  anchor: {txid, vout, sats, script}   →     txid, vout, value=sats, scriptHex,
  payload: {...},                            address: addressFromScript(script),
  beefHead: ...,                             beefHex: reassembled(beefHead),
  status,                                    status,
  leafPk,                                    derivationModel: from payload,
  cellType,                                  recipeId, index: from payload,
  derivation: from payload                   senderIdentityKey, derivationPrefix,
}                                            derivationSuffix: from payload
                                             addedAtMs, updatedAtMs, spvVerifiedAtMs
                                           }
```

The renderer reads the projection; writes go to the cell store via
the dispatcher.

### §8.2 The deletion / wipe path

Operator-initiated wipe (`clearIdentity`) drops the cell store + the
UtxoStore in lockstep. No partial states.

### §8.3 Bypass-cell payments (future)

Some inbound paths don't need linear-cell ceremony — a faucet send to
a plain receive address still produces a confirmed UTXO Bridget can
spend, but doesn't naturally come with BEEF + remittance. For those:

```
UtxoRow with derivationModel = self, status = confirmed,
                beefHex empty, no carriage-chain link.
```

These rows sit in the projection without a cell-store backing. The
projection layer reads them from a separate `me.utxos.bypass.v1`
slot. Spending such a UTXO is the only operation that can't be
expressed as a linear-cell transition — it becomes a one-shot
`bsv.tx.broadcast.intent` cell with the funding UTXO supplied
explicitly.

This is the "easy add later" Todd noted; the doc reserves the slot.

---

## §9 Deployment matrix

Compile-time feature flags carve the host_capability_table for each
target; the cell-engine 2PDA stays the same across all builds. Sizes
are the proven cell-engine carve plus the registered hostcalls'
implementations.

| Target | `cap.spv.verify` | `cap.tx.build` | `cap.tx.sign` | `cap.tx.broadcast` | Substrate size estimate |
|---|---|---|---|---|---|
| `embedded-sensor` (ESP32-C6 sensor) | – | – | – | – | 29 KB (proven; per `cell_engine_static_5mb_unfit_for_mcu`) |
| `embedded-pi-mesh` (Orange Pi federation node) | ✓ | – | – | – | ~50 KB (add SPV) |
| `mobile` (Semantos Flutter shell) | ✓ | ✓ | ✓ | – (brain proxies) | ~80 KB (add tx-build + sign request emit) |
| `desktop` (PWA wasm) | ✓ | ✓ | ✓ | ✓ | ~120 KB (full) |
| `brain-full` (rbs / oddjobtodd.info) | ✓ | ✓ | ✓ | ✓ | ~150 KB (full + broker integration) |

`mobile` doesn't register `host_broadcast_arc` because the brain
proxies broadcasts — the operator's phone never POSTs to ARC
directly. The Dart wallet sends a `bsv.tx.broadcast.intent` cell to
the brain, which broadcasts and returns the result cell.

`cap.tx.sign` doesn't gate a hostcall (sign is the two-cell pattern
per §3.5) — it gates the right to *emit* a `bsv.tx.sign.request`
cell. Embedded targets that don't sign omit `cap.tx.sign` from the
operator's cert.

**The C6 sensor target stays at 29 KB** per the proven embedded carve.
Cell-engine + linearity opcodes + the core hostcalls is the entire
substrate; no wasmtime, no per-cell-type runtime overhead.

---

## §10 Migration from REST to cells

### §10.1 What retires

- `POST /api/v1/wallet-op` (legacy): replaced by cell-engine intents.
- The planned-but-not-shipped `POST /api/v1/spv/verify-beef`:
  replaced by `bsv.spv.verify.intent`.
- The wallet-headers TS verifier (`spv-verifier.ts`): retired once
  the cell-engine path is canonical; kept as a reference impl during
  the transition.

### §10.2 What stays REST

- Bearer-gated control plane: pairing, `/api/v1/bearer issue`,
  `/api/v1/contacts`, `/api/v1/cartridges`. These are operator-level
  administration, not wallet operations.
- `/api/v1/chain/header/...`: the brain's headers HTTP. Wallet only
  needs it for the rare case where it bypasses cell-engine (offline
  recovery, header sync diagnostic).
- `/api/v1/info`: operator profile, unchanged.

### §10.3 Interim coexistence

During PR-C11-7d through 7k, the old paths remain functional. The
Dart wallet uses cell dispatch for new code paths; the legacy code
paths stay until the equivalent cell path is proven. PR-C11-7m
deletes the legacy fallbacks once we're confident.

---

## §11 Test posture

### §11.1 Pure-Dart tests

- `CellDispatcher` tests against `InMemoryCellDispatcher` with
  hand-built result cells per intent type.
- `WalletKeyService.internalizeIncoming` tests dispatch a fixture
  intent, the in-memory dispatcher returns a pre-computed result, the
  service persists + asserts the UtxoRow projection.
- Carriage-chain encode/decode tests against fixed BEEF byte fixtures.

### §11.2 Zig-side tests

- Cell-engine script conformance tests for each cell type — pull from
  existing `runtime/semantos-brain/tests/` patterns. Each handler
  script runs through `PolicyRuntime.evaluateReal` against a fixture
  input cell; emitted cells get hash-compared against expectations.
- Hostcall tests with hand-built BEEF fixtures (reusing the ones from
  `cartridges/wallet-headers/brain/test/spv-verifier.conformance.spec.ts`).
- Capability-gating tests: a handler script that emits an
  `OP_CALLHOST "host_verify_beef_spv"` without declaring
  `cap.spv.verify` in its manifest must fail at dispatch time. A
  script that attempts to emit a cell type outside its declared
  `handler.emits` allowlist must fail at OP_CELLCREATE time.

### §11.3 End-to-end

- A "fake brain" test harness running cell-engine inline + a stub ARC
  + a stub headers tracker. The Dart wallet drives BRC-29 receive +
  later spend, asserts the on-chain state matches the cell-engine's
  projection.

### §11.4 Adversarial fixtures

- Tampered BEEF (wrong merkle path) → `bsv.spv.verify.intent` returns
  invalid; `bsv.brc29.internalize.intent` refuses.
- Mismatched scriptPubKey (sender derived from wrong invoice) →
  internalize refuses.
- Reorg fixture: header set rolls back; status-change cells emit;
  UtxoRow projection updates.

---

## §12 PR sequence

Updated after the 2026-05-31 2PDA-WASM excise. 7d already landed; the
WASM-handler PR stack (originally 7e-2a–7e-2g, merged then excised at
commit `edf91c1`) is replaced by a much smaller script-dispatcher
sequence.

| PR | Scope | Depends on | Status |
|---|---|---|---|
| **7c** | This doc. | — | landed (revised 2026-05-31) |
| **7d** | Bind `host_verify_beef_spv` in broker.zig. Lift broker capability gate from "wallet-engine-only" to `cap.spv.verify`. Zig-only. Conformance tests. | 7c | landed |
| **7e** | Define `bsv.spv.verify.intent`/`result`, `bsv.linear.anchor`, `bsv.beef.carriage.head`/`body`, `bsv.linear.status` cell types in `core/protocol-types/`. Manifest schema for `cellTypes[i].handler.script` + `handler.scriptHash` + `handler.capabilities` + `handler.opcountBudget` + `handler.emits`. | 7d | pending |
| **7f** | typeHash → script-bytecode dispatcher in `cells_mint_handler` via `PolicyRuntime.evaluateReal`. Dart `CellDispatcher` (`HttpCellDispatcher` + `InMemoryCellDispatcher`) + cells-over-HTTP transport on brain. | 7e | pending |
| **7g** | First script handler: `bsv.spv.verify.intent` as a small cell-engine script (~10 opcodes — load intent → OP_CALLHOST `"host_verify_beef_spv"` → OP_CELLCREATE result → persist). Adversarial: tampered BEEF, missing capability. | 7f | pending |
| **7h** | `bsv.brc29.internalize.intent` cell type + script handler. `WalletKeyService.internalizeIncoming` dispatches it. End-to-end BRC-29 receive flow. | 7g | pending |
| **7i** | Register `host_build_tx`/`host_build_beef`/`host_broadcast_arc` hostcalls. `bsv.linear.transition.intent` cell type + script. Two-cell sign request/response flow. The full atomic transition fires. | 7g | pending |
| **7j** | `bsv.brc29.outbound.send` cell type. Dart-side "Send" panel actually sends. | 7i | pending |
| **7k** | Recovery scanner — `bsv.recovery.scan.intent`. | 7i | pending |
| **7m** | Retire legacy REST fallbacks for wallet ops. | 7k | pending |

**C10 finish-the-flips** (per `docs/design/REAL-EXECUTOR-WIRE.md`)
runs in parallel — flipping `cell_handler` + `cells_mint_handler` to
`.real_executor` mode and switching the `policy_runtime.init()` default.
The PolicyRuntime adapter is the substrate the script-handler
dispatcher sits on; the flips activate it everywhere.

8a/8b (contacts + edge store) and 9a–f (challenge handshake) run in
parallel with 7d–7k; they don't depend on cell-engine wiring.

---

## §13 Out of scope (deferred / explicit non-goals)

- **In-process cell-engine on the Dart device.** Cell-engine runs on
  the brain in v1. A future PR (likely C12 territory) brings
  cell-engine in-process to the Dart shell for offline-first /
  operator-sovereignty cases. The `CellDispatcher` abstraction means
  the swap is local to one file.
- **Cell-passing federation protocol.** Cells over WSS / UDP
  multicast / IPv6 multicast in the mesh path is the federation
  track's concern (C2c). The wallet uses HTTP first; the dispatcher
  abstraction lets federation plug in later.
- **Recovery of bypass-cell UTXOs (the future "easy add" path).**
  When we open Pandora's box of non-cell-backed UTXOs, the recovery
  scanner needs a parallel bypass scan. That's a future PR; the
  schema reserves the slot.
- **MNCA cell-type catalog beyond `bsv.linear.anchor`.** The full
  MNCA cell-type set (covenants, multi-input, etc.) is its own track
  (C6 / MNCA arc); this doc only specifies the cell types the wallet
  itself needs.

---

## §14 Open questions

- **Reorg policy details.** What depth does the cell-engine consider
  "deep enough" before it stops listening for reorgs on a given
  cell? Default = 6 blocks (Bitcoin convention); operator-configurable.
- **Long-running scan resumability.** A recovery scan may take minutes
  on a large operator history. Should `bsv.recovery.scan.intent` be
  pause/resumable, or is it ok to re-run from scratch on interruption?
  Lean toward resumable: emit progress cells with a resumeCursor field
  the next intent can carry.
- **Carriage chain compression.** 960-byte slices is the simplest
  scheme. We could LZ4-compress BEEFs before chunking (BEEFs have
  tons of repeated tx prefixes) to roughly halve the chain length.
  Probably a 7m-era optimisation.
- **Capability revocation.** What happens to in-flight handler
  scripts when the operator revokes a capability mid-execution? The
  cell-engine is loop-free (scripts run to completion in a single
  opcount budget) so mid-script revocation is structurally
  ungetable — the script either completes its current invocation or
  doesn't start. Revocation takes effect at the *next* dispatch.
  Whether the broker should also abort an in-flight transaction
  (mid-step-8 broadcast) is the actual question; v1 default is
  let-it-finish since the tx is already signed and re-broadcast is
  idempotent.
