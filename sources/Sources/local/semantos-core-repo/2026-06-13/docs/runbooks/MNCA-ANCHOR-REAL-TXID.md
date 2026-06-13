---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/runbooks/MNCA-ANCHOR-REAL-TXID.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.755273+00:00
---

# MNCA anchor — real mainnet txid via the cleavage apparatus

This runbook walks through producing a real BSV mainnet transaction id
through the cleavage apparatus that landed across PR-3d → PR-8b-ix.

The goal: a single HTTP mint of an `mnca.anchor.transition.intent` cell
turns into a real on-chain BSV tx, with the brain pre-computing the
sighash + the wallet (Metanet Desktop) signing + the broker broadcasting
via ARC.

## Proven recipe (executed end-to-end on mainnet 2026-06-01)

PR-8b-x — proof-of-execution: the apparatus produced two real mainnet
txids in sequence:

| Phase | mainnet txid | role |
|---|---|---|
| 3 (funding) | [`5ab00c6580d8e73788700ce091188effd721bb75d9795e45f73a7bfd834f088d:0`](https://whatsonchain.com/tx/5ab00c6580d8e73788700ce091188effd721bb75d9795e45f73a7bfd834f088d) | seeds the anchor lineage — 1 sat PushDrop committing to initial snapshot `45e0d0c8…b8ecb7fc96e` |
| 8 (transition) | [`5d592c2647fc96cbeddb37aff43daa9406efb43e1879b4ece3a4aa61d0b8589a:0`](https://whatsonchain.com/tx/5d592c2647fc96cbeddb37aff43daa9406efb43e1879b4ece3a4aa61d0b8589a) | spends the funding UTXO with the brain-computed BIP-143 sighash; outputs 1 sat to next-anchor PushDrop committing to `ff82b17b…0b268b2` |

Invariants the recipe depends on (anything outside the same shape
will produce a different sighash than the brain emits, breaking
OP_CHECKSIG):

- **Cell wire format** must be binary at fixed offsets — POST mints
  with `payloadBytesHex` (PR-8b-viii), not `payload`. The MNCA
  Context builder reads `payload[1..33]` etc.; JSON-stringified
  payloads break it.
- **Tx version** = 1, **locktime** = 0.
- **Input sequence** = `0xFFFFFFFE` (= `feffffff` LE). Matches
  `ANCHOR_UTXO_SEQUENCE` in `cells_mint_mnca_context.zig`.
- **Input value** = 1 satoshi. Matches `ANCHOR_UTXO_VALUE_SATS`.
- **Sighash flag** = `0x41` = `SIGHASH_ALL | FORKID`.
- **Output 0** = 1 sat to `buildPushDropScript(next_snapshot_hash,
  owner_pubkey)` = 69 bytes exactly.
- **Wallet call shape** (Metanet Desktop / any BRC-100 wallet):
  - `protocolID: [2, "mnca anchor"]` — letters/numbers/space-only
    per BRC-43; **don't** use `mnca.anchor` (dots rejected).
  - `keyID: "0"` matches the leaf derivation index.
  - `counterparty: "self"` — **critical**: the `@bsv/sdk`
    `ProtoWallet` default counterparty for `createSignature` is
    `"anyone"`, but for `getPublicKey` it's `"self"`. Letting the
    default ride derives a different key for sign vs. verify;
    OP_CHECKSIG fails with "Signature must be zero for failed
    CHECK(MULTI)SIG operation".
  - `hashToDirectlySign: <32 bytes>` (byte array) — **critical**:
    the BIP-143 sighash is already double-SHA256; passing it via
    `data:` re-hashes once more inside the wallet and ECDSA-signs a
    triple-hash that won't validate. The
    `hashToDirectlySign` parameter skips the wallet's internal
    SHA256 so the resulting signature commits to the raw sighash
    OP_CHECKSIG actually verifies.
- **Unlock script** = `PUSH 72 <der_sig || 0x41>`. For a 71-byte DER
  signature plus the 1-byte sighash flag, `der_sig.len + 1 = 72`,
  pushed via opcode `0x48`.
- **Broadcast** = `POST https://api.whatsonchain.com/v1/bsv/main/tx/raw`
  with `{"txhex":"<hex>"}` — WhatsOnChain accepts 1-sat-in/1-sat-out
  zero-fee txs at this endpoint; ARC endpoints (taal /
  gorillapool) reject for fee. Future fee-paying composition is
  PR-8b-xii-b (kernel seam shipped in PR-8b-xii-a / PR #800): the
  primary input must use `SIGHASH_SINGLE|FORKID|ANYONECANPAY` (0xC3)
  so it doesn't commit to other inputs (BIP-143 hashPrevouts = 0
  under ANYONECANPAY) AND only commits to output[input_index]
  (= output 0, the successor PushDrop). The fee-paying secondary
  input uses `SIGHASH_NONE|FORKID|ANYONECANPAY` (0xC2). A naïve
  "leave primary as SIGHASH_ALL + add a SIGHASH_NONE fee input"
  composition does NOT work — the primary's hashPrevouts changes
  the moment any input is added.

## Grind surface taxonomy

PR-8b-xi added a brain-side sighash grind loop so the apparatus can
pre-satisfy structural predicates on the sighash before emitting
the sign.request. The grind surface is the set of preimage-
committed fields the cartridge's semantic commitment doesn't pin —
the brain may freely nudge these to satisfy a predicate. Three
options identified during the 2026-06-02 Brendan Lee
conversation:

| Surface | BIP-143 impact | Cartridge cost |
|---|---|---|
| `nLockTime` | direct preimage byte | free (default; what PR-8b-xi uses) |
| Successor-PushDrop grind nonce | output 0 bytes → changes `hashOutputs` | adds a few bytes to the successor cell's lock script (e.g. `PUSH <nonce> OP_DROP` prepended) |
| Input sequence | direct preimage byte | NONE — `0xFFFFFFFE` is the cartridge-pinned value (see invariants above) |
| Output ordering | changes `hashOutputs` | breaks the cell-graph convention that output 0 is the successor anchor; **don't use** |

**The unlock script is NOT a grind surface.** BIP-143 commits to
`scriptCode` (the script being SPENT, not the spending input's
unlock script), the outpoint, input value, sequence, and the
output set. The unlock script comes AFTER the signature is
constructed; the wallet appends arbitrary bytes there without
disturbing the preimage. (Common misconception; the PR-8b-vii
runbook walk briefly entertained it before the math was clarified.)

**Recipe-predicate cost profile.** Different OP_PUSH_TX
constructions impose different per-sighash success rates, which the
brain trades off against on-chain byte count + ~2^d security
degradation per the article-referenced PUSHTX_BIT_SHIFT analysis:

| Construction | Lock script | Per-sighash success | Mean grind | Source |
|---|---|---|---|---|
| Original PUSHTX | 376 B | 1/1 | 0 | endianness-reversal version (Brendan, 440 B with full preimage) |
| Brendan 136-byte tail | 136 B | ~1 − 2⁻³² | ~1 | `z[28..32] != 0xFFFFFFFF` |
| Brendan 110-byte | 110 B | 255/256 | ~1 | predicate shape TBC |
| PUSHTX_BIT_SHIFT d=3 | 82 B | 1/8 | 8 | `HASH256(preimage) mod 8 == 1` |

Cartridge authors pick based on their per-anchor byte budget +
acceptable expected grind cost. The PR-8b-xi grind loop has a
1024-attempt budget that covers every published construction.
PR-9's `bsv.tx.lock.recipe` substrate cell will dispatch the
predicate via a fn-pointer per recipe; PR-8b-xi's seam is the
mechanism.

## Topology

All-local (per the topology decision in PR-8b-vii):

```
┌──────────────┐    POST /api/v1/cells
│ Test harness │ ─────────────────────────► ┌──────────────────────┐
└──────┬───────┘                            │ brain (local Mac)    │
       │ GET /api/v1/cell/<hash>            │   - cells_mint_http  │
       │ ◄──────────────────────────────────│   - MNCA Context     │
       │                                    │     (PR-8b-iv/v/vi)  │
       │ POST sign request                  │   - dispatcher       │
       ▼                                    │   - cell_store (lmdb)│
┌──────────────┐                            └──────────────────────┘
│ Metanet      │
│ Desktop :3321│
└──────┬───────┘
       │ signed digest
       ▼
┌──────────────┐    POST /v1/tx
│ Test harness │ ─────────────────────────► ┌──────────────────────┐
│ (assembles   │ ◄────────────────── txid ──│ ARC                   │
│  tx + posts) │                            │ (mainnet)             │
└──────────────┘                            └──────────────────────┘
```

The headers store stays empty — anchor transitions don't need SPV verify
(only `bsv.spv.verify.intent` does). The `FsHeaderStore` exists so the
brain's `dynamic_setup` brings up the MNCA Context builder via the
composite wiring landed in PR-3e + PR-8b-iv.

## Prerequisites

- `zig 0.15.x` toolchain
- Metanet Desktop running on `:3321` (see `mnca_anchor_onchain_mainnet`
  memory for the proven recipe)
- ARC mainnet endpoint + token (same one the existing
  `mnca_anchor_onchain_mainnet` path uses)
- A small (~10 sat) BSV mainnet wallet balance for the anchor + fees

## Phase 0 — build the brain binary

```bash
cd runtime/semantos-brain
zig build                       # Debug optimize; binary is ~16 MB
# (ReleaseFast works too but takes 5–10× longer to build; for smoke
#  walks Debug compiles in ~30s and runs more than fast enough.)
ls -lh zig-out/bin/brain
```

## Phase 1 — initialize a local data dir + site

`brain init` writes a JSON config file (not a TOML); pass the desired
config path via `--config-path`. The data dir is read from the config
or the `BRAIN_DATA_DIR` env var (see Phase 2), not from the CLI flag.

```bash
mkdir -p ~/.semantos-mnca-smoke
./zig-out/bin/brain init --config-path ~/.semantos-mnca-smoke/brain.json
```

Edit `~/.semantos-mnca-smoke/brain.json` so `shell.data_dir` points at
the smoke data dir (the init default lives at `~/.semantos`; we want
isolation):

```json
{
  "shell": {
    "data_dir":    "~/.semantos-mnca-smoke/data",
    "modules_dir": "~/.semantos-mnca-smoke/wasm"
  },
  "modules": {}
}
```

Then scaffold the `smoke.local` site directory (`brain serve` requires
a `site.json` for the domain — without it, boot fails with
`FileNotFound` on `~/.semantos/sites/smoke.local/site.json`):

```bash
./zig-out/bin/brain site init smoke.local
```

The generated `site.json` is fine as-is for the MNCA recipe — no
dynamic-route workaround is required as of PR #803 (unblocker #40
decouples the MNCA `ScriptContextBuilder` wiring from `has_dynamic`).
The MNCA composite child fires unconditionally; only the SPV
ScriptContextBuilder still needs the dynamic runtime (because it
depends on `FsHeaderStore`). If you ARE following the runbook for
an SPV cartridge, then add a stub `dynamic` route to flip
`has_dynamic = true`:

```json
"routes": {
  "/": {
    "type": "static",
    "file": "index.html",
    "public": true
  },
  "/_dynamic_stub": {
    "type": "dynamic",
    "handler": "stub.wasm"
  }
}
```

(Even with the stub, the SPV builder needs more wiring than this
runbook covers — see `bsv-anchor-bundle/cartridge.json` + PR-3e for
the full SPV path. The MNCA recipe doesn't need any of it.)

Deploy the substrate cartridges to `<data_dir>/extensions/`:

```bash
mkdir -p ~/.semantos-mnca-smoke/data/extensions
cp -r cartridges/mnca               ~/.semantos-mnca-smoke/data/extensions/
cp -r cartridges/bsv-anchor-bundle  ~/.semantos-mnca-smoke/data/extensions/
```

Both cartridges are required: `mnca` provides the transition handler
+ cellTypes; `bsv-anchor-bundle` provides `bsv.tx.sign.request` which
the MNCA handler's `emits[]` allowlist references (cross-cartridge
resolution lands in PR-8b-ix; without bsv-anchor-bundle the emit
walker rejects the sign.request push as `emit_outside_allowlist`).

## Phase 2 — start the brain

In one terminal:

```bash
BRAIN_DATA_DIR=~/.semantos-mnca-smoke/data \
./zig-out/bin/brain serve smoke.local \
  --config-path ~/.semantos-mnca-smoke/brain.json \
  --repl-config-path ~/.semantos-mnca-smoke/brain.json \
  --enable-repl \
  --port 8443
```

Three things to note about the flags:

- `--port N` (not `--bind host:port`) — `brain serve --help` is
  authoritative; the brain listens dual-stack `[::]:N`.
- `--config-path` sets the boot config but the runtime reads
  `data_dir` from `~/.semantos/config.json` or `$BRAIN_DATA_DIR`
  (see `cli/common.zig::resolveDataDir`). Export `BRAIN_DATA_DIR`
  to point everything at the smoke dir; without it the brain
  writes to `~/.semantos` even though we passed `--config-path`.
- `--repl-config-path` is independent — the REPL session resolves
  its own config (defaults to `~/.semantos/config.json`). Point
  this at the smoke config too so the REPL session sees the same
  cell_store + cartridges.

Brain logs should show:

- `cells_mint: cellType registry populated — 24 cellTypes from 2/2
  cartridges (0 skipped)` (9 mnca + 15 bsv-anchor-bundle = 24 total)
- `dynamic handlers: 0 of 1 loaded` (we declared the stub route but
  ship no WASM — that's fine, the runtime is up which is the gate
  the composite Context builder cares about)
- NO `cells mint handler running without ScriptContextBuilder`
  warning. That warning means `dynamic_setup` is null and the MNCA
  + SPV builders aren't wired; re-check the site.json dynamic route.

Issue a bearer token (the HTTP API requires one):

```bash
BRAIN_DATA_DIR=~/.semantos-mnca-smoke/data \
./zig-out/bin/brain bearer issue --label mnca-smoke
# Copy the printed token into BRAIN_BEARER for later phases.
```

## Phase 3 — fund an initial anchor UTXO

> **BRC-43 / BRC-100 protocolID gotcha:** Metanet Desktop's
> `getPublicKey` (and `createSignature`, see Phase 7) accept letters,
> numbers, and spaces only in the protocol name. **Don't** use
> `mnca.anchor` (dots are rejected) — use `mnca anchor`.

1. Mint the initial `mnca.snapshot` cell so its cell-hash is bound to
   the funding output:
   ```bash
   SNAP_TYPE=$(bun run scripts/mnca-smoke/typehash.ts mnca standalone snapshot "")
   curl -s -X POST http://127.0.0.1:8443/api/v1/cells \
     -H "Authorization: Bearer $BRAIN_BEARER" \
     -H "Content-Type: application/json" \
     -d "{\"typeHashHex\":\"$SNAP_TYPE\",\"payload\":{}}"
   # → {"cellId":"<initial_snapshot_cell_hash>",...}
   ```
   For the smoke an empty payload (`{}`) is fine — the brain
   constructs a well-formed 1024-byte cell. The MNCA Context builder
   takes `cell[256..1024]` as the predecessor tile payload regardless
   of the JSON payload's actual length; stepTilePayload runs over
   `{` `}` followed by 766 zero bytes and produces a deterministic
   successor. Real production smokes use payloadBytesHex with a
   proper 768-byte tile.

2. Derive the BRC-42 leaf pubkey via Metanet Desktop:
   ```bash
   curl -s -X POST http://127.0.0.1:3321/getPublicKey \
     -H "Content-Type: application/json" \
     -H "Origin: http://localhost" \
     -d '{"protocolID":[2,"mnca anchor"],"keyID":"0","counterparty":"self"}'
   # → {"publicKey":"<33-byte compressed hex>"}
   ```
   Approve the prompt the first time. Record as `LEAF_PK`.

3. Build the 1-sat PushDrop locking script (69 bytes, hex):
   `20 || <snapshot_hash> || 75 || 21 || <LEAF_PK> || ac`
   - `0x20` PUSH 32  ← initial_snapshot_cell_hash
   - `0x75` OP_DROP
   - `0x21` PUSH 33  ← LEAF_PK
   - `0xac` OP_CHECKSIG

4. Broadcast via Metanet Desktop's `createAction` (it adds fee
   inputs + change automatically):
   ```bash
   curl -s -X POST http://127.0.0.1:3321/createAction \
     -H "Content-Type: application/json" \
     -H "Origin: http://localhost" \
     -d '{
       "description":"MNCA anchor seed",
       "outputs":[{
         "lockingScript":"<69-byte PushDrop hex>",
         "satoshis":1,
         "outputDescription":"mnca anchor leaf utxo"
       }]
     }'
   # → {"txid":"<funding_txid>","tx":[...BEEF bytes...]}
   ```
   Record `funding_txid` + `funding_vout = 0` (createAction places
   operator outputs first).

## Phase 4 — insert the predecessor mnca.anchor cell

Phase 3 already minted the snapshot via the HTTP path. The predecessor
`mnca.anchor` cell must be inserted with the funding txid + vout baked
into its binary payload — only then will the brain's MNCA Context
builder pre-compute the BIP-143 sighash in Phase 5.

Use `payloadBytesHex` (PR-8b-viii) to insert the 139-byte binary
payload directly — the standard `payload:{...}` path JSON-stringifies
the object into the cell payload section, which breaks the handler
scripts' fixed-offset reads.

Wire layout (139 bytes) per `core/protocol-types/src/mnca/anchor.ts::encodeMncaAnchor`:

```
  0   1   VERSION = 1
  1  32   current_snapshot_hash    (initial_snapshot_cell_hash)
 33  32   prev_anchor_hash         (32 zero bytes for the initial anchor)
 65   4   generation (LE u32)      0
 69  33   owner_pubkey             LEAF_PK (33 bytes compressed)
102   1   status                   0 (Active)
103  32   anchor_txid              funding_txid in BSV INTERNAL byte order
                                    (= display txid REVERSED)
135   4   anchor_vout (LE u32)     funding_vout (= 0)
```

Bun helper:

```bash
ANCHOR_TYPE=$(bun run scripts/mnca-smoke/typehash.ts mnca anchor "" "")

PAYLOAD_HEX=$(bun -e '
  const txid    = "5ab00c6580d8e73788700ce091188effd721bb75d9795e45f73a7bfd834f088d";
  const snap    = "<initial_snapshot_cell_hash>";
  const leafPk  = "<LEAF_PK hex>";
  const txidInt = txid.match(/../g).reverse().join("");
  process.stdout.write([
    "01", snap, "00".repeat(32), "00000000",
    leafPk, "00", txidInt, "00000000",
  ].join(""));
')

curl -s -X POST http://127.0.0.1:8443/api/v1/cells \
  -H "Authorization: Bearer $BRAIN_BEARER" \
  -H "Content-Type: application/json" \
  -d "{\"typeHashHex\":\"$ANCHOR_TYPE\",\"payloadBytesHex\":\"$PAYLOAD_HEX\"}"
# → {"cellId":"<predecessor_anchor_hash>",...}
```

Record `predecessor_anchor_hash` for Phase 5.

## Phase 5 — mint the transition intent

The transition intent's 73-byte prefix (no computationProof):

```
  0   1   VERSION = 1
  1  32   predecessor_anchor_hash
 33  32   next_snapshot_hash       SHA256(stepTilePayload(predecessor_tile))
 65   4   next_generation (LE u32) predecessor.generation + 1
 69   4   proof_len (LE u32)       0 for inline-verify
```

Compute `next_snapshot_hash` by running the MNCA rule on the
predecessor tile bytes. For the smoke-mode snapshot whose payload was
`{}` + 766 zeros, `stepTilePayload` returns early (width=height=0 from
the JSON bytes) and writes `tick+1` at offset 4 — so:

```bash
NEXT_SNAP=$(bun -e '
  import {createHash} from "crypto";
  const pred = new Uint8Array(768);
  pred[0] = 0x7B; pred[1] = 0x7D;   // {}
  const out = new Uint8Array(pred); // memcpy
  out[4] = 0x01;                    // tick + 1
  console.log(createHash("sha256").update(out).digest("hex"));
')
```

For a real 768-byte tile, replace the inner with
`stepTile(decodeTilePayload(tile))` then SHA256 the result (the TS
oracle in `core/protocol-types/src/mnca/tile.ts` is byte-equivalent
to the Zig `mnca_tile.stepTilePayload` the brain runs).

POST the intent (binary payload via PR-8b-viii):

```bash
INTENT_TYPE=$(bun run scripts/mnca-smoke/typehash.ts mnca anchor transition intent)
INTENT_HEX="01<predecessor_anchor_hash><NEXT_SNAP>0100000000000000"
curl -s -X POST http://127.0.0.1:8443/api/v1/cells \
  -H "Authorization: Bearer $BRAIN_BEARER" \
  -H "Content-Type: application/json" \
  -d "{\"typeHashHex\":\"$INTENT_TYPE\",\"payloadBytesHex\":\"$INTENT_HEX\"}"
# → 201 {"cellId":"<intent_hash>","cellType":"mnca.anchor.transition.intent",...}
```

A 201 means the brain ran the full pipeline (PR-8b-ix wires the
handler dispatch into the reactor): MNCA Context builder fired, the
host_mnca_verify_transition hostcall produced a Valid verdict, the
brain pushed pre-built successor `mnca.anchor` + `bsv.tx.sign.request`
extra cells, the handler script `OP_CELLCREATE`'d the
`transition.result`, and the stack walker persisted all three.

## Phase 6 — read back the emitted cells

Enumerate cells whose `prev_state_hash` is all zeros (root cells in
the smoke setup) and identify them by the typeHash at bytes 30..62:

```bash
curl -s -H "Authorization: Bearer $BRAIN_BEARER" \
  "http://127.0.0.1:8443/api/v1/cell/since/$(printf '%.0s0' {1..64})" \
  -o /tmp/since_root.bin
# Each cell is 1024 bytes; iterate slots offset 0, 1024, 2048, ...
# bsv.tx.sign.request typeHash: 136523b9fea2b7321b5b9ccb3e8d006a...
```

Grab the sign.request cell and parse the digest:

```bash
curl -s -H "Authorization: Bearer $BRAIN_BEARER" \
  http://127.0.0.1:8443/api/v1/cell/<sign_request_hash> \
  -o sign_request.bin
xxd -s 256 -l 80 sign_request.bin
#   payload bytes:
#     [0]      VERSION = 1
#     [1..33]  digest (BIP-143 sighash, BSV double-SHA256)
#     [33..65] recipe_id (zeros in v1)
#     [65..69] input_index (LE u32, = 0)
#     [69]     sighash_flags = 0x41
```

## Phase 7 — wallet signs the digest

Two BRC-100 / `@bsv/sdk` gotchas the runbook trapped against — both
caught from `node_modules/@bsv/sdk/dist/esm/src/wallet/ProtoWallet.js`:

1. **`data` is auto-SHA256'd; `hashToDirectlySign` is not.** A
   BIP-143 sighash is already a double-SHA256; passing it as `data`
   makes the wallet sign `SHA256(sighash)`, and OP_CHECKSIG
   (which verifies against the raw sighash) fails with `Signature
   must be zero for failed CHECK(MULTI)SIG operation`. Use
   `hashToDirectlySign` so the wallet signs the sighash verbatim.

2. **`createSignature` default counterparty is `"anyone"`, but
   `getPublicKey` defaults to `"self"`.** Letting the default ride
   derives a DIFFERENT key for sign vs. verify — same symptom as
   (1) above. Pass `counterparty: "self"` explicitly to match the
   leaf pubkey derived in Phase 3.

3. **`protocolID` name validator rejects dots** — `"mnca anchor"`
   (with a space), not `"mnca.anchor"`.

Wire format for `hashToDirectlySign` is a JSON array of bytes (not
base64). For the sighash hex `0421f85b9d...0846`:

```bash
HASH_BYTES=$(bun -e '
  process.stdout.write(JSON.stringify(Array.from(
    Buffer.from("<32-byte sighash hex>", "hex")
  )));
')

curl -s -X POST http://127.0.0.1:3321/createSignature \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost" \
  -d "{
    \"protocolID\":[2,\"mnca anchor\"],
    \"keyID\":\"0\",
    \"counterparty\":\"self\",
    \"hashToDirectlySign\":$HASH_BYTES
  }"
# → {"signature":[48,69,2,...]}   (DER bytes as JSON array)
```

Verify before assembling — saves a round-trip to the BSV node when
the signature is wrong:

```bash
bun -e '
  import { PublicKey, ECDSA, BigNumber, Signature } from "@bsv/sdk";
  const leafPk = PublicKey.fromString("<LEAF_PK hex>");
  const sigBytes = [/* paste from response */];
  const sig = Signature.fromDER(Buffer.from(sigBytes).toString("hex"), "hex");
  const sighash = new BigNumber("<sighash hex>", 16);
  console.log("OP_CHECKSIG verify:", ECDSA.verify(sighash, sig, leafPk));
'
# → "OP_CHECKSIG verify: true"
```

Once true, append `0x41` to the DER bytes to make the BSV unlock
signature.

## Phase 8 — assemble + broadcast the tx

The spending tx structure must match the brain's BIP-143 sighash
exactly — see the invariants in the "Proven recipe" block at the top.

```bash
bun -e '
import { createHash } from "crypto";

const sigBytes = [/* DER bytes from Phase 7 */];
const sigHex   = Buffer.from(sigBytes).toString("hex");
const sigWithFlag = sigHex + "41";              // append SIGHASH_ALL|FORKID
const unlockLen = sigBytes.length + 1;          // sig + flag
const unlockScript = unlockLen.toString(16).padStart(2,"0") + sigWithFlag;
const unlockScriptLen = (unlockScript.length/2).toString(16).padStart(2,"0");

const fundingTxidInternal = "<funding_txid display>"
  .match(/../g).reverse().join("");
const succPushDrop = "20" + "<next_snapshot_hash>" + "75"
                   + "21" + "<LEAF_PK hex>"        + "ac";

const rawTx =
  "01000000"                + // version 1 LE
  "01"                      + // input count
  fundingTxidInternal       + // prev_txid (32 bytes, internal byte order)
  "00000000"                + // prev_vout = 0
  unlockScriptLen           + // unlock script length (varint)
  unlockScript              + // unlock script bytes
  "feffffff"                + // sequence 0xFFFFFFFE
  "01"                      + // output count
  "0100000000000000"        + // value 1 sat
  "45"                      + // pushdrop length = 69
  succPushDrop              +
  "00000000";                 // nLockTime

import { writeFileSync } from "fs";
writeFileSync("/tmp/spending_tx.bin", Buffer.from(rawTx, "hex"));

const h1 = createHash("sha256").update(Buffer.from(rawTx, "hex")).digest();
const h2 = createHash("sha256").update(h1).digest();
console.log("expected txid:", h2.reverse().toString("hex"));
'

curl -s -X POST https://api.whatsonchain.com/v1/bsv/main/tx/raw \
  -H "Content-Type: application/json" \
  -d "{\"txhex\":\"$(xxd -p -c 1000 /tmp/spending_tx.bin)\"}"
# → "<txid>"
```

**Broadcast endpoint choice:** WhatsOnChain accepts 1-sat-in /
1-sat-out zero-fee txs at the `/v1/bsv/main/tx/raw` route; ARC nodes
(taal.com, gorillapool.io) reject for `minimum expected fee: 21,
actual fee: 0`. Future work to bring fee-paying composition lands in
PR-8c+ — the design is to add a second input signed with
SIGHASH_NONE|ANYONECANPAY so the brain-issued primary signature stays
valid while the second input pays fee from operator change.

## Phase 9 — verify

```bash
sleep 5
curl -s "https://api.whatsonchain.com/v1/bsv/main/tx/hash/<spend_txid>" | jq .
```

You should see:
- 1 input consuming the funding `txid:vout` (Phase 3)
- 1 output (1 sat) `nonstandard` with the PushDrop committing to
  `next_snapshot_hash`
- Input scriptSig.hex carries your `<sig + 0x41>` exactly
- Input scriptSig.asm shows `[ALL|FORKID]`

That's the real-txid demo end-to-end through the cleavage apparatus.

## Closing the loop (post-broadcast)

After broadcast, the broker would normally write the new txid back into
the successor anchor cell's `anchor_txid` / `anchor_vout` fields (the
PR-8b-vi-1 wire format slots that stay zero until commit). Subsequent
transitions then see a committed predecessor and the brain pre-builds
the next sign.request automatically.

For this v1 smoke, you can do this manually via `admin update-cell`
(once that REPL command exists) or by reading the new anchor, patching
the bytes, and inserting the patched version under a new hash.

## Troubleshooting

### MNCA Context builder doesn't fire

Symptoms: `host_mnca_verify_transition` returns no-context sentinel
(`0xFFFFFFFE`) at script time; transition.result has `outcome = Error`.

Causes:
- `dynamic_setup` not up — re-check `--enable-repl` flag
- Composite builder not wired — check serve.zig boot log for
  `cells mint handler running without ScriptContextBuilder`
- typeHash mismatch — verify the intent's typeHash matches
  `INTENT_TYPE_HASH` (= sha256("mnca")[0:8] ++ … of "transition" /
  "intent" / etc.)

### sign.request not emitted

Symptoms: only 2 cells emitted (successor + result), no sign.request.

Cause: predecessor anchor's `anchor_txid` is all zeros (uncommitted).
Re-check Phase 4 — the anchor cell must carry the funding txid +
vout in bytes 103..135 + 135..139 of its payload.

### ARC rejects the tx

- Check input value: the predecessor anchor UTXO must be exactly 1 sat
  (matches `ANCHOR_UTXO_VALUE_SATS` in `cells_mint_mnca_context.zig`)
- Check sequence: must be `0xFFFFFFFE` (matches Context builder)
- Check sighash type: `0x41` (SIGHASH_ALL | FORKID)
- Check the PushDrop layout: 69 bytes exactly, per `buildPushDropScript`
