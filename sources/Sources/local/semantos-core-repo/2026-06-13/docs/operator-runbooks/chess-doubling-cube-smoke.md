---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/chess-doubling-cube-smoke.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.636574+00:00
---

# Chess doubling-cube — Phase-2 end-to-end smoke test

**Status**: Operator runbook — first live run of the chess Phase-2
pipeline against real BSV.
**Audience**: Operator (you) running mint → game → submitter for the
first time end-to-end with a small Metanet Desktop stake.
**Time**: ~15 minutes (5 min wallet build + 5 min play + 5 min broadcast
verify).
**Safety**: Default is **DRY-RUN**. Real broadcast requires you to type
`--broadcast` explicitly on the submitter CLI.

## References
- `docs/design/CHESS-DOUBLING-CUBE.md` (§12 escrow construction)
- `docs/CHESS-DOUBLING-CUBE-TRACKING.md` (Phase-2 status)
- `cartridges/wallet-headers/brain/src/test-chess-stake.ts` (mint)
- `cartridges/wallet-headers/brain/src/chess-manifest-export.ts` (export)
- `cartridges/wallet-headers/brain/src/chess-submitter.ts` (drain)

---

## What this gets you

A round-trip proof on mainnet (small stake — single-digit cents):

1. Mint two `chess.stake.v1` cell-anchors funded from Metanet Desktop
   (one per "player"; in the single-wallet test setup both belong to
   your identity).
2. Brain ingests the manifest at boot, the chess store attaches its
   `WalletPort` to the live anchors.
3. Play a game to resolution. `chess.resolve` writes a payout intent
   to `<data_dir>/chess/intents/`.
4. **DRY-RUN the submitter** — inspects the planned spend tx with no
   network calls.
5. **Broadcast** — submitter signs each anchor input via its BRC-42-
   derived sk, ARC-broadcasts the chained BEEF, archives the intent.
6. Confirm on a block explorer.

---

## Prerequisites

| | |
|---|---|
| Metanet Desktop | installed at `localhost:3321`, identity unlocked, funded with **≥ 5,000 sats** (smoke uses 2,400; rest is fee/headroom) |
| `bun` | `bun --version` ≥ 1.3 |
| `zig` | `zig version` = 0.15.x (only needed to run the brain) |
| repo | This worktree at `/Users/toddprice/projects/chess-doubling-cube-wt-20260519`, on a tip at or after commit `46bfd5b` |
| `<data_dir>` | Pick one — e.g. `/tmp/chess-smoke-$(date +%s)`. Substituted as `$DATA_DIR` below |

```bash
export REPO=/Users/toddprice/projects/chess-doubling-cube-wt-20260519
export DATA_DIR=/tmp/chess-smoke-$(date +%s)
mkdir -p "$DATA_DIR/chess/intents"
```

---

## Step 1 — build the wallet UI

```bash
cd "$REPO/cartridges/wallet-headers/brain"
bun install                # if you haven't already
bun run build              # builds WASM + bundles + copies HTML to dist/
python3 -m http.server --directory dist 8088 &   # any static server works
```

Open <http://localhost:8088/index.html>. The wallet boots, talks to MD
at `localhost:3321`, derives identity from IndexedDB.

## Step 2 — fund the game from Metanet Desktop

In the wallet UI, find the **Chess stake — fund a game** panel
(fourth from the top):

| Field | Value |
|---|---|
| `gameId` | leave blank (auto: `chess-<base36 ts>`) — **note what it prints in the log** |
| `stake/side` | `1000` (sats per side) |

Click **Fund chess game**. MD will prompt — approve. The log shows:

```
identity: 0x02abcd…
gameId:   chess-abc123
fund tx:  <txid_be>
split tx: <txid_be>
  anchor[white] idx=… sats=1000 → <txid_be>:1
  anchor[black] idx=… sats=1000 → <txid_be>:2
domainFlag: 0x00010301 (typeHash chess.stake.v1)
✓ funded chess-…: white@…, black@…, 1000 sats each
```

If the ✓ doesn't appear, **stop here** and resolve the funding issue
(MD locked, insufficient sats, ARC reachability).

## Step 3 — export the manifest

In the same panel, leave `gameId` blank to export all, or type the
gameId from step 2 to scope. Click **Export anchors manifest**.
The browser downloads `chess-anchors-manifest-<filter>-<ts>.json`.

```bash
# Move the downloaded file into <data_dir>/chess/manifest.json
mv ~/Downloads/chess-anchors-manifest-*.json "$DATA_DIR/chess/manifest.json"
ls -la "$DATA_DIR/chess/manifest.json"
```

## Step 4 — drop the spending key

The submitter needs the SAME identity sk that minted the anchors. Get
the wallet's identity sk hex from the UI (the **Status** panel shows
the pubkey; for the V1 smoke we provide the sk directly).

> **For the smoke test:** the easiest path is to use a temporary throw-
> away identity — fund a fresh wallet just for this run, copy its
> sk-hex from the wallet's recovery export. **Never paste your main
> identity key into a file.**

```bash
# 64-hex (raw 32-byte sk), mode 0600.
printf '%s\n' "<paste-sk-hex>" > "$DATA_DIR/chess/submitter.sk.hex"
chmod 600 "$DATA_DIR/chess/submitter.sk.hex"
```

## Step 5 — start the brain

```bash
cd "$REPO"
DATA_DIR="$DATA_DIR" zig build run-brain   # or however you usually start it
# In another shell, sanity-check the chess cap registered:
#   curl ... or your usual verb.dispatch tool
```

At boot the brain reads `$DATA_DIR/chess/manifest.json`, ensures
`$DATA_DIR/chess/intents/`, threads `chess_native_bridge.nativeConsumeFn()`
into the cartridge boot path. Look for the chess store coming up with
`wallet_active=true`.

## Step 6 — play a game

Using your usual brain JSON-RPC client (or your dev-shell):

```
chess.create_game  { gameId, creator: "alice", color: "white",
                     stakeSats: 1000, clockMs: 600000 }
chess.join_game    { gameId, joiner: "bob" }
# … play a sequence of chess.submit_move until checkmate, OR
chess.offer_double { gameId, player: "alice" }
chess.decline_double { gameId, player: "bob" }       # alice wins
chess.resolve      { gameId }
```

After `chess.resolve`, you should see ONE new file:

```bash
ls -la "$DATA_DIR/chess/intents/"
# 0000000000000001-white-2000.intent.json   (or similar)
```

## Step 7 — DRY-RUN the submitter

**This is the button.** No money moves yet.

```bash
cd "$REPO/cartridges/wallet-headers/brain"
bun run src/chess-submitter.ts --data-dir "$DATA_DIR"
```

Expected output:

```
found 1 intent(s) in /tmp/chess-smoke-…/chess/intents
=== DRY-RUN (no broadcast) — pass --broadcast to commit ===
intent #1 (white, 2000 sats)
  txid_be:    <prospective txid>
  total_in:   2000 sats   fee: 200   payout: 1800
  recipient:  <your identity pk>
  inputs (2):
    <txid>:1  1000 sats  white  cell=…/stake/w/base
    <txid>:2  1000 sats  black  cell=…/stake/b/base
done: processed=1 dryRun=1 broadcast=0 failed=0
```

**Inspect the plan.** Verify:
- `recipient` is your identity pubkey.
- `inputs` are the two chess.stake.v1 anchors from step 2.
- `total_in - fee == payout`.
- `txid_be` is a fresh hex.

If anything looks wrong, **stop**. Don't go to step 8.

## Step 8 — BROADCAST

```bash
bun run src/chess-submitter.ts --data-dir "$DATA_DIR" --broadcast
```

Expected:
```
=== BROADCAST MODE ===
intent #1 (…)
  …
  ✓ broadcast txid <txid>
done: processed=1 dryRun=0 broadcast=1 failed=0
```

The intent file moves to `intents/done/<id>.intent.json` with a
sibling `<id>.txid`:

```bash
ls -la "$DATA_DIR/chess/intents/done/"
cat   "$DATA_DIR/chess/intents/done/"*.txid
```

## Step 9 — verify on chain

Use any block explorer (WhatsOnChain, etc.) with the txid:

```
https://whatsonchain.com/tx/<txid>
```

Confirm:
- Two inputs spending the two `chess.stake.v1` UTXOs you minted in step 2.
- One output paying `payout` sats to your identity's P2PKH.

If the tx appears (mempool or confirmed), **the round-trip is proven**.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `manifest not found` | step 3 didn't run / wrong `--data-dir` | re-export, check path |
| `WIF checksum failed` | mistyped sk in `submitter.sk.hex` | re-paste; trailing whitespace OK, embedded newlines bad |
| `ARC broadcast: ...` | network / ARC URL | re-run; default is `https://arc.taal.com`, override with `--arc-url` |
| `deriveCellAnchorSk null` | identity sk doesn't match the one that minted | step 4 is wrong — you provided a different key |
| `total_in < payout + fee` | manifest stale (anchors already spent) | re-export manifest, or these anchors are gone |

## After the smoke

- The intent's source anchors are now spent on-chain. The wallet's
  IndexedDB still shows them `status: 'unspent'` (V1 doesn't have a
  feedback loop). Don't try to spend them again — ARC will reject
  with double-spend. Next manifest export will re-list them but the
  submitter will fail at broadcast.
- Funds (minus the 200-sat fee) are back in your identity's P2PKH UTXO.
  Visible in MD as the recipient pubkey.
- The brain's chess store still has the game record with
  `status: 'white_won'`. Replaying `chess.resolve` returns the same
  result (idempotent — `escrow.resolved`).

## What this proves end-to-end

- The wallet's chess-stake panel produces real, BRC-42-derived
  chess-typed cell-anchors at the right paths.
- The manifest export contains everything the submitter needs (no IDB
  dependency).
- The brain's intent-queue writer produces the right shape, with the
  source outpoints + cell paths the submitter cross-references.
- The submitter's spend math is correct (conservation: total_in = fee
  + payout) and the multi-input SIGHASH signing per anchor works.
- Path A's "on-chain double-spend rejection IS the cross-process
  replay guard for V1" actually holds — the anchors became unspendable
  after broadcast.
