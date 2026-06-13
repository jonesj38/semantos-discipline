---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/CHESS-DOUBLING-CUBE-TRACKING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.327908+00:00
---

# Chess + Doubling Cube — Implementation Phase Tracking

**Companion to:** `docs/design/CHESS-DOUBLING-CUBE.md` (v0.1 DRAFT)
**Doc owner:** Todd Price
**Repo scoped against:** `/Users/toddprice/projects/semantos-core` @ 2026-05-19
**Status:** Phase 0 complete (scope + design). Phase 1 not started.
**Branch caveat:** scoped against `main`. Do **not** build on
`chore/ext-dissolve-batch3` (28 behind main at scope time).

---

## 0. Decisions locked (2026-05-19)

| # | Decision | Locked value |
|---|---|---|
| D1 | Economic enforcement | Cell-engine LINEAR/RELEVANT types, **no sCrypt**. Replaces chessgammon `ChessGame` contract. |
| D2 | Doubled-claim coverage | Accept = anchor a `chess.stake_augment.v1` covering the new level, **or go all-in** (poker-style capped pot). Cube dies once anyone is all-in. |
| D3 | Chess engine | **Real engine, in the Zig walker cartridge.** Illegal moves never produce a cell. Engine emits terminal verdicts incl. draws. |
| D4 | Clock | Single per-player countdown. Offerer's clock **frozen** while a double is pending; only the responder's clock runs ⇒ "offerer wins on pending timeout" is fair. |
| D5 | Forfeit-on-no-accept | `chess.pending_double.v1` is LINEAR; decline / responder-flag both consume it into offerer-wins. No DROP path exists by type. |
| D6 | Cube start position | **Centered; either player may offer first** on their own turn (true backgammon). Not configurable. |
| D7 | Escrow custody (Phase 2) | **Path A** (design §12): 2-of-2 pot + Satoshi/Spilman **pre-signed settlement** refreshed per accepted double; **BSV tx-level locks only** (`nLockTime`/`nSequence`, no CSV/CLTV); enforced exit pays last mutually-agreed split, **no game result in script** (no sCrypt, no Rúnar). BEEF+BUMP/SPV exchange. Max griefer harm = bounded delay + fee; no theft/freeze. |

---

## Phase 1 status (2026-05-19)

**Code complete and fully tested standalone — 30 tests green** on branch
`feat/chess-doubling-cube` (off origin/main `3226424`):

| File | Tests | Validated against |
|---|---|---|
| `cartridges/chess/brain/chess_engine.zig` | 10 | perft (startpos d1–4, Kiwipete d1–3, ep pos) |
| `cartridges/chess/brain/chess_game_store.zig` | 10 | cube/clock/forfeit/draw state machine |
| `cartridges/chess/brain/chess_walkers.zig` | 5 | the **real** `verb_dispatcher.Registry` |
| `cartridges/chess/brain/chess_cells.zig` | 5 | the **real** kernel `linearity.zig`/`constants.zig` |
| `cartridges/chess/cartridge.json` | — | manifest (jambox-shape) |

**build.zig module wiring: DONE** — additive, jambox-pattern, `b.path` →
`../../cartridges/chess/brain/`; `zig build test-substrate` exits 0 with the
chess trio compiled inside the brain build.

**Boot wiring: DONE (landed in `origin/main` via PR #454, `b300d78`).**
The universal `runtime/semantos-brain/cartridge_boot.zig` constructs the chess
`Store` (`chess_game_store.Store.init`) and calls `chess_walkers.registerAll`
at brain boot, with a `.id="chess"` registry entry. `cartridge_boot` inline
tests assert `hasId(rt,"chess")` and `reg.hasExtension("chess")` (7 verbs);
`zig build test-substrate` on current `origin/main` (`61a2915`) exits 0. Chess
verbs register at boot — runnable end-to-end brain-side. (Supersedes the prior
"left for review" handoff: #454 generalised the deferred shared-boot-path into
a uniform multi-cartridge loader covering jambox+chess+tessera.)

**Remaining:**
- Capability mirror (`cap.chess.play` → `extensions.zig` §9 + `gen:cap-vectors`)
  — still deferred; P1 ships uncapped per jambox precedent. Natural to fold
  into Phase 2 (real money ⇒ real gate).

## 1. Phase plan

### Phase 1 — State machine, no money

Goal: two players, real chess, full cube/forfeit/clock state machine, anchors
stubbed. Mirrors the jambox P1 proof.

- [x] `cartridges/chess/cartridge.json` (manifest per `extension-manifest.ts`)
      — walkers surface, 7 verbs, money/caps deferral noted in `_notes`
- [x] `cartridges/chess/brain/chess_walkers.zig` — 7 verbs registered via
      `verb_dispatcher.Registry` (jambox pattern); domain refusals returned
      as `{ok:false,reason}` bodies, malformed params → invalid_params.
      5 tests green through the real dispatcher (incl. create→join→mate,
      offer→accept doubling)
- [x] build.zig module wiring: `chess_engine`/`chess_game_store`/
      `chess_walkers` modules + top-level imports + inline-test +
      `test-substrate` deps (jambox-pattern, `b.path` → `../../cartridges/
      chess/brain/`). Verified: `zig build test-substrate` exits 0 (chess
      trio compiles inside the brain build, inline tests green)
- [ ] Boot wiring: construct chess `Store` + call `registerAll` in the
      serve/cmdServe path + thread into `wss_wallet.Backend` — deeper than
      module wiring; needs user review (shared boot path)
- [ ] Capability mirror into `runtime/semantos-brain/src/extensions.zig`
      (`cap.chess.play`) — §9 gate; `bun run gen:cap-vectors` green
      *(deferred: P1 ships uncapped like jambox; dedicated iteration)*
- [x] Cell types: `chess.game.v1` (RELEVANT), `chess.move.v1` (RELEVANT,
      DAG-linked), `chess.stake.v1` / `chess.stake_augment.v1` / `chess.cube.v1`
      / `chess.pending_double.v1` (LINEAR) — `chess_cells.zig`, validated
      against the real kernel `linearity.zig`/`constants.zig` (header
      round-trip + marquee forfeit-guarantee proof). 5 tests green
- [x] Real chess engine in-cartridge: legality + terminal verdicts (mate,
      stalemate, 50-move, insufficient material). `chess_engine.zig`,
      perft-verified: startpos d1–4 (197281), Kiwipete d1–3 (97862),
      ep-discovered-check pos. 10/10 tests green. *(threefold = store-level)*
- [x] Cube state machine (§4): offer/accept/decline, centered-cube gating,
      cube ownership transfer on accept — in `chess_game_store.zig`
- [x] Clock model (§5): per-player ms countdown, offerer-frozen-while-pending,
      pending-flag ⇒ offerer wins (`timeout_pending`), normal flag ⇒ opponent
- [x] In-memory game store (jambox `jam_clip_state_store.zig` shape, swappable)
      — `chess_game_store.zig`, 10 tests green incl. fool's-mate, threefold,
      decline-forfeit, both timeout paths
- [ ] Unit tests: LINEAR DROP/DUP rejection on pending_double; forfeit paths;
      draw paths; engine legality suite (perft on a few positions)

### Phase 2 — Real escrow (Path A, design §12)

Goal: real BSV custody via the Satoshi/Spilman pre-signed-settlement
construction (D7); uncapped per-double funding (D2); resolution
conservation-checked; **no smart contract** (no sCrypt, no Rúnar).

**Progress (2026-05-19):** the *pure economic layer* is done and
brain-build-green. `chess_escrow.zig` — Path A state machine: D2
coverage (full-cover/all-in, cube-dead-on-all-in), poker cap +
unmatched refund-to-self, conservation asserted, nSequence ratchet
(stale never beats fresher, §12.5), resolve-consumes-each-anchor-once
(replay ⇒ `already_consumed`), all behind a `WalletPort` seam (8 tests).
Integrated into `chess_game_store` via an *optional* port — no wallet ⇒
byte-identical Phase-1 (verified); funded create→join→offer→accept→
move→decline→resolve conserves end-to-end (13 store tests). build.zig
wired; `zig build test-substrate` exits 0.

**Progress (2026-05-20):** native funding + port:
- `cartridges/wallet-headers/brain/src/test-chess-stake.ts` — wallet.html
  panel that mints two `chess.stake.v1` cell-anchors (white + black) in
  one tx; persists them in the `cell-anchors` basket tagged
  `['chess','stake',<color>,gameId]`. Mirrors test-deep-rotation's
  anchor-split. Bundle builds clean (197 KB).
- `cartridges/chess/brain/chess_wallet_port.zig` — native production
  `WalletPort` impl (4 tests). Pre-minted lookup model (Q1): `anchor_fn`
  binds an anchor from a manifest (Q2: JSON exported from wallet's
  outputStore). `consume_fn` calls the injected kernel `linear_consume`
  (stub in tests; production via the bridge). `pay_fn` writes a payout
  intent to a queue dir (Q3: detached submitter drains, no broadcast
  in the verb path) — verified end-to-end against a tmp dir.
- `cartridges/chess/brain/chess_native_bridge.zig` — production wrapper
  around `extern semantos_linear_consume`; rc → ConsumeError. Used at
  brain boot to build the `KernelConsumeFn` the port wants.

**Progress (2026-05-20, cont'd):** brain-side production wiring DONE.
- `cartridge_boot.zig`: 4 optional `BootDeps` fields
  (`chess_manifest_json` / `chess_queue_dir` / `chess_consumer_cert` /
  `chess_consume_fn`); ChessSpec.construct parses + attaches when all
  four are wired, else Phase-1 preserved. 2 new boot tests cover both
  paths.
- `cli/serve.zig`: reads `<data_dir>/chess/manifest.json` if present,
  ensures `<data_dir>/chess/intents/`, threads
  `chess_native_bridge.nativeConsumeFn()`. Missing manifest ⇒ chess
  stays Phase-1; full brain `zig build` exits 0.
- `chess_native_bridge.zig` is a **V1 stub** that returns OK: the
  brain's native binary doesn't link the cell-engine WASM exports
  directly; the kernel `linear_consume` runs in the submitter (which
  owns the WASM runtime). In-brain replay safety is already
  `escrow.resolved`; the submitter does the cross-process kernel
  guard against `source_outpoints` recorded in the payout intent.

**Progress (2026-05-20, cont'd):** `cap.chess.play` mirror landed.
- `runtime/semantos-brain/src/extensions.zig` — `CHESS_CAPS` (single
  cap) + `CHESS_MANIFEST` + added to `BUILTIN_MANIFESTS`. Domain flag
  `0x0001_0301` on the chess page (`0x000103xx` — distinct from
  oddjobz's `0x000101xx` and loom-shell's `0x000100xx`).
- `cartridges/chess/cartridge.json` — every verb declares
  `capability_required: "cap.chess.play"`. `_notes.caps` updated.
- DLO.1c test updated to reflect `BUILTIN_MANIFESTS.len == 2`.
- `zig build test` exits 0 across the full brain suite (1880+ tests).

**Progress (2026-05-20, cont'd):** submitter binary landed.
- `cartridges/wallet-headers/brain/src/chess-submitter.ts` — one-shot
  `bun` CLI: reads `<data_dir>/chess/manifest.json` +
  `<data_dir>/chess/intents/*.intent.json`, decodes
  `<data_dir>/chess/submitter.{sk.hex|wif}`, derives each anchor's
  spending sk via `deriveCellAnchorSk`, builds the multi-input spend
  tx (N anchors → 1 P2PKH out), chains BEEFs from each source's funding
  BEEF, and ARC-broadcasts. **Dry-run by default; `--broadcast` is the
  explicit on switch.** On success, moves intent to `intents/done/` and
  writes a `<id>.txid` sidecar.
- Intent schema bumped to `version: 1` with `sources: [{outpoint,
  cell_path}]` so the submitter knows the cell path for each anchor.
  `chess_wallet_port.Anchor` tracks the `bound_path` from `anchor_fn`.
- Manifest schema bumped to include `locking_script_hex` + `beef_hex`
  per anchor (in `chess-manifest-export.ts`) so the submitter has the
  full spend material with no IndexedDB / wallet-UI dependency.
- V1 scoped: the kernel `semantos_linear_consume` is NOT called from
  the submitter — V1 relies on on-chain double-spend rejection as the
  cross-process replay guard (the brain's in-process guard is already
  `escrow.resolved`). The WASM-mediated kernel call is a separate
  follow-up once the submitter embeds a cell-engine instance.
- Submitter bundle builds clean (52.56 KB, 15 modules). Brain
  `test-substrate` exits 0; wallet-page bundle exits 0.

**Phase-2 status: end-to-end pipeline implemented.** Remaining is the
operator-side integration run against real funded chess-stake anchors
(MD + ARC + real BSV) — the eyes-on smoke test we planned.

Custody / settlement:
- [ ] 2-of-2 pot funding output (both BCA-derived keys); cooperative-settle
      fast path (`nSequence=0xFFFFFFFF`, both sign final split)
- [ ] **Pre-signed enforced-exit settlement** exchanged *before* funding
      broadcast: both-signed, future `nLockTime`, non-final `nSequence`,
      pays last mutually-agreed split (Path A — no result in script)
- [x] (model) Per-double refresh: each accepted double adds funding **and** swaps in a
      new both-signed settlement, `nSequence` ratcheted up, `nLockTime`
      tightened; older states superseded
- [ ] BSV tx-level locks only — assert no CSV/CLTV anywhere; `nLockTime`
      /`nSequence` SIGHASH-committed so counterparty can't mutate
- [ ] BEEF (BRC-62) + BUMP exchange verified vs local headers (SPV) —
      instant, locally-verified acceptance (no confirmation wait)
- [ ] invite→accept→fund FSM adapted from cashlanes `ChannelFSM`

Stake cells / resolution (the LINEAR audit + payout layer):
- [ ] Wire `chess.stake.v1` / `chess.stake_augment.v1` to
      `semantos_wallet_anchor_transition()` (BRC-42 per-type domain flag,
      `cell-anchor.ts`)
- [ ] `chess.resolve` consumes all stake+augment cells →
      `semantos_linear_consume()`; replay returns `SEMANTOS_ERR_ALREADY_CONSUMED`
- [x] Coverage model D2: delta cover vs all-in cap; cube-dead-on-all-in
- [x] Resolution conservation test: `Σ consumed == payout + returned-unmatched`
      (asserted in escrow.resolve + tested pure & through the store)
- [x] Refund-to-self paths: draw + never-joined refund each side its own
      committed, no rake. `escrow.cancel` (pre-join only) + store
      `cancelGame` (creator-only, waiting-only) + Status/EndReason
      `cancelled`. 9 escrow + 16 store tests; `test-substrate` green.
- [ ] Broadcast via detached-grandchild submitter; SPV verify is local/sync,
      only the broadcast is detached (2026-05-18 outage class)
- [ ] Fold in `cap.chess.play` mirror here (real money ⇒ real gate)

Caveat carried from §12.5: nSequence-replacement has no consensus mempool-
eviction guarantee; the load-bearing guarantee is the `nLockTime`-dated refund
to last-agreed split → max griefer harm = bounded delay + on-chain fee, no
theft/freeze. Test the enforced-exit path explicitly (stale-state broadcast →
fresher state / lockTime refund wins).

### Phase 3 — Invite + world-app + hardening

- [x] `apps/world-apps/chess-game/` (jam-room template): relay connect,
      snapshot/commit, presence (RelayClient via `@semantos/world-sdk/relay`)
- [x] Invite flow §9: `chess.create_game` → room link (`?invite=<gameId>`);
      `chess.join_game`
- [x] `core/cube-object` mesh wired as the rendered doubling cube (linearity
      colour reflects live type via `multiplierToLinearity`)
- [x] Reconnection / snapshot replay; turn-clock authority hardening —
      `Store.getSettled` makes the world-app's every-tick `get_game` poll
      the authoritative clock heartbeat; a flagged-out side is observed
      on the opponent's screen even if no further verb runs. Snapshot
      replay = the relay's onPresence rejoin path already calls
      `refreshGame()` so a reconnecting peer pulls fresh state via
      `get_game` on the next tick.
- [x] `chess.get_game` read-only verb — `chess_walkers.zig::getGameWalker`
      registered as the 8th verb; world-app `refreshGame()` now calls it
      on every relay tick
- [x] `chess.list_legal_moves` 9th verb — returns UCI list from current
      FEN. World-app fetches on every FEN change, Board.svelte highlights
      legal destinations + suppresses illegal click round-trips (server
      stays single source of legality; client just renders the cache)

### Phase 4 — Brain-auth alignment (cross-cut, tracks T7)

- [ ] Replace bearer-token gating with BRC-52 cert + capability for chess verbs
      when the brain-auth alignment (T7) lands. Out of scope for P1–P3;
      P1 preserves existing bearer semantics.

---

## 2. Prior-art salvage from chessgammon

Reusable as reference (not as code — substrate differs entirely):

| chessgammon artefact | Use as |
|---|---|
| `backend/src/contracts/ChessGame.ts` `declineDouble` | Spec of the forfeit payout math; reimplemented as LINEAR consumption |
| `frontend/src/components/GameLobby.tsx` invite UX | UX reference for the relay-room invite |
| `backend/src/api/gameRouter.ts` `GameData` shape | Field reference for `chess.game.v1` payload |
| BRC-42 invoice key derivation | Conceptually superseded by `cell-anchor.ts` per-type domain flag |

Gaps chessgammon never closed, now in scope here: real move validation (D3),
draw handling (D3), immutable move history (`chess.move.v1` DAG),
persistence (P1 store → P2 anchored).
