---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CHESS-DOUBLING-CUBE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.727823+00:00
---

# Semantos — Chess Invite + Doubling Cube on Linear/Affine Objects

**Version**: 0.1 DRAFT
**Status**: Design (pre-implementation)
**Date**: 2026-05-19
**Authors**: Todd
**Replaces**: `chessgammon` sCrypt `ChessGame` contract (live as doublemate.app) — the economic invariants move from Bitcoin Script to cell-engine substructural types.
**Related**:
  - `core/cell-engine/src/linearity.zig` (`LinearityType`, `checkLinearity`)
  - `core/cell-engine/src/constants.zig` (`HEADER_OFFSET_LINEARITY=16`, `HEADER_OFFSET_DOMAIN_FLAG=24`, `HEADER_OFFSET_TYPE_HASH=30`, `HEADER_OFFSET_OWNER_ID=62`)
  - `core/cube-object/` (renderable linearity-typed cube — the literal doubling cube)
  - `cartridges/jambox/cartridge.json`, `cartridges/jambox/brain/jambox_walkers.zig` (walker-cartridge template)
  - `runtime/semantos-brain/src/verb_dispatcher.zig` (`Registry`, `WalkerFn`, `DispatchError`)
  - `core/protocol-types/src/extension-manifest.ts` (`cartridge.json` schema)
  - `src/ffi/wallet_exports.zig` (`semantos_wallet_anchor_transition`, `semantos_wallet_pay`, `semantos_wallet_identity_pubkey`)
  - `src/ffi/exports.zig` (`semantos_linear_consume`, `semantos_capability_check`), `src/ffi/semantos.h` (`SEMANTOS_ERR_ALREADY_CONSUMED`)
  - `cartridges/wallet-headers/brain/src/cell-anchor.ts` (BRC-42 anchor derivation, per-type domain flag)
  - `runtime/world-beam/apps/cell_relay/lib/cell_relay/ws_handler.ex`, `packages/world-sdk/src/relay/{types,client}.ts` (invite/session transport)
  - `apps/world-apps/jam-room/` (world-app integration template)
  - Tracker: `docs/CHESS-DOUBLING-CUBE-TRACKING.md`

---

## 1. Goal and the one-sentence thesis

Let one player invite another to a staked game of chess with a backgammon-style
doubling cube, where **declining the cube — or letting it stand unanswered until
the clock runs out — forfeits the game automatically**, and where every economic
invariant that `chessgammon`'s sCrypt contract enforced is instead enforced by
the cell-engine's linear/affine type discipline. No sCrypt.

The thesis: **the doubling cube is not application state with rules bolted on; it
is a LINEAR cube-object whose type makes "don't accept ⇒ you forfeit"
unrepresentable as anything else.**

---

## 2. What chessgammon's sCrypt contract guaranteed, and the replacement

`chessgammon/my-bsv-app/backend/src/contracts/ChessGame.ts` enforced four
economic invariants in Bitcoin Script. Each maps to a cell linearity type
(`core/cell-engine/src/linearity.zig`):

| sCrypt invariant (ChessGame.ts) | Linear/affine replacement |
|---|---|
| Stake escrow `betAmount·2·multiplier`, cannot vanish, cannot double-pay (`hashOutputs` check) | **`chess.stake.v1` = LINEAR.** Anchored on-chain via `semantos_wallet_anchor_transition()`. LINEAR forbids DUP (pot can't be paid twice) and DROP (a stake can't be made to vanish). Consumed exactly once, at resolution. |
| Doubling cube ownership: one cube, transfers on accept, not offerable by both (`doublingCubeOwner` prop) | **`chess.cube.v1` = LINEAR cube-object** bound to owner identity (`HEADER_OFFSET_OWNER_ID`). Exactly one exists. Transfer = consume owner's cube cell, emit a new one bound to the accepter. |
| Decline ⇒ game ends, cube owner wins all (`declineDouble`) | **`chess.pending_double.v1` = LINEAR obligation** directed at the responder. LINEAR ⇒ must be consumed exactly once. The *only* game-continuing consumption is `accept_double`; every other path (decline, clock expiry) consumes it into the forfeit resolution. The forfeit rule *is the type*, not a branch. |
| Single winner, atomic payout | `chess.resolve` consumes **both players' LINEAR stake + augment cells** into one winner anchor transition (`semantos_linear_consume` → `SEMANTOS_ERR_ALREADY_CONSUMED` on any replay). Linearity is the atomicity sCrypt got from `SIGHASH_ALL`. |

The substructural enforcement runs in the 2-PDA executor's K1–K4 invariants;
there is no script to audit and no on-chain contract to deploy.

---

## 3. Object model

All cells carry the standard header (`core/cell-engine/src/constants.zig`):
linearity at byte 16, domain flag at 24, type-hash at 30, owner-id at 62. Domain
flags derive per cell-type as in `cartridges/wallet-headers/brain/src/cell-anchor.ts`
(`0x00010000 | typeHash[0..3]`), so each chess cell type's anchors are
cryptographically isolated.

| Cell type | Linearity | Role |
|---|---|---|
| `chess.game.v1` | RELEVANT | The game record (players, clock config, board FEN pointer, status). Retained, may be referenced many times; never duplicated as authority. |
| `chess.move.v1` | RELEVANT | One ply. DAG-linked: `parentHashes = [prior position state hash]`. Gives the immutable move history chessgammon never had (it stubbed move validation). |
| `chess.stake.v1` | **LINEAR** | A player's base escrow. Anchored on-chain. One per player. |
| `chess.stake_augment.v1` | **LINEAR** | Incremental cover posted when a double is accepted (or an all-in marker). Anchored. Never dropped/duped ⇒ pot integrity across escalations. |
| `chess.cube.v1` | **LINEAR** | The doubling cube — a `core/cube-object` instance. Bound to the current owner via `HEADER_OFFSET_OWNER_ID`. Exactly one in existence at any time. |
| `chess.pending_double.v1` | **LINEAR** | The unanswered-offer obligation. Directed at the responder. Carries `offered_at_clock`, `level_before`, `level_after`, `offerer_id`. Must be consumed exactly once. |

Why these linearity choices, precisely (`checkLinearity` semantics):

- **LINEAR stake/cube/pending**: `cannot_duplicate` + `cannot_discard`. You cannot
  fork the pot, mint a second cube, or *walk away from a pending double*. The
  forbidden DROP is the entire forfeit mechanic.
- **Not AFFINE**: AFFINE permits DROP. An AFFINE pending-double would let the
  responder ignore the offer with no consequence — exactly the behaviour we must
  make impossible. The choice of LINEAR over AFFINE here *is* the rule.
- **RELEVANT moves/game**: `cannot_discard`, DUP allowed. History must be
  retained and is freely referenced by later cells; it is never an
  authority token, so duplication is harmless.

The `core/cube-object` mesh renders the cube coloured by its live linearity
class, so the UI shows a LINEAR (teal) cube the players literally cannot discard.

---

## 4. The doubling cube state machine

Backgammon semantics: on your turn you **either** make a move **or** offer the
cube (offering is not a move). The cube starts **centered** — either player may
offer on their own turn (recommended default; see §8 Q-cube). Initial multiplier
`m = 1`. Define base stake `S` per player; pot `= 2·m·S`.

```
                     ┌─────────────────────────────────────────┐
                     │ ACTIVE (m, cube centered or owned)        │
                     │ player-to-move clock running              │
                     └───────────────┬───────────────┬──────────┘
                       legal move     │               │ offer cube (instead of move)
                  (engine-validated)  │               │
                                      ▼               ▼
                          switch clock to     emit chess.pending_double.v1 (LINEAR)
                          opponent, continue   FREEZE offerer clock
                                               START/continue responder clock
                                                       │
                          ┌────────────────────────────┼───────────────────────────┐
              accept_double│                  decline   │                responder   │
                           ▼                  ▼          clock hits 0 while pending  ▼
              responder posts cover or    consume pending  ───────────────────────► consume pending
              all-in augment; consume      → RESOLVE:                                 → RESOLVE:
              pending; emit new            offerer wins pot                           offerer wins pot
              chess.cube.v1 bound to       at level m                                 at level m
              responder; m ← 2m;
              control returns to offerer
              to make a move; offerer
              clock resumes
```

There is no transition that leaves `chess.pending_double.v1` un-consumed,
because LINEAR forbids it. "Don't accept ⇒ you forfeit" has no code path of its
own — it is the absence of any legal DROP.

---

## 5. The clock and the fairness question

You asked: *"If the cube was offered but wasn't accepted and either party's
timer runs down then the offerer wins the game — that should be fair?"*

**Yes — with one guard, which this design bakes in.** Naively, if *both* clocks
keep running during a pending double, a player who is losing and about to flag
could spam-offer the cube on the last tick to convert a time-loss into a win —
the opponent may not physically have time to click *accept*. That is not fair.

The fix that makes "offerer wins on a pending-double timeout" unambiguously
fair: **while a double is pending, the offerer's clock is frozen and only the
responder's clock runs.** Consequences:

- The only clock that can expire during a pending double is the **responder's**.
- A responder sitting on a forced accept/decline decision until their own clock
  expires is *exactly* the forfeit condition — they declined by inaction.
- So your "either party's timer" collapses, in practice, to "the responder's
  timer," which is the fair reading of the intent. The offerer cannot lose on
  time while waiting, and cannot weaponise their own near-flag.

Clock rules (single per-player countdown, standard chess-clock — only the
player-to-act's clock decrements):

1. **Normal flag, no pending double**: the player whose clock hits 0 loses;
   opponent wins the pot at the current multiplier `m`.
2. **Offer the cube**: offerer's clock freezes; responder's clock runs.
3. **Pending double, responder flags**: forfeit ⇒ offerer wins pot at `m`.
4. **Accept**: cover/all-in posted, cube re-binds to responder, `m ← 2m`,
   control returns to the offerer to make an actual move, offerer's clock
   resumes.
5. **Decline**: immediate ⇒ offerer wins pot at `m`.

Draw detection (stalemate, threefold, 50-move, insufficient material) is now
possible because the chess engine is real and in-cartridge (§6): a draw consumes
each player's stake/augment cells back to their own owner (refund of matched
amounts; unmatched all-in remainder returned to its poster). chessgammon could
not do this — it had no draw path.

---

## 6. Coverage model — commit-more-or-go-all-in (locked)

Doubling escalates the *claim*; on-chain the anchored stake is fixed sats, so
the doubled level must be **re-escrowed**, not promised:

- To **accept** a double taking the level `m → 2m`, the responder must anchor a
  `chess.stake_augment.v1` LINEAR cell bringing their total committed from `m·S`
  to `2m·S` (delta `= m·S`).
- If the responder cannot fully cover the delta, they may **go all-in**: anchor
  an augment for whatever balance `b` they have. The contested pot is then
  **capped poker-style** at `2·(committed_responder + b)`; the offerer's stake
  above the matched amount is not at risk and is returned to the offerer at
  resolution.
- **Symmetric obligation**: a player may only offer a double they can themselves
  back to `2m·S` — or they offer all-in (their own cap). The offer carries the
  offerer's augment (or all-in marker) atomically; you cannot offer a double you
  cannot at least all-in cover.
- **Once any player is all-in, the cube is dead** — it cannot be re-offered,
  because there is nothing left to escalate. This is a clean terminal and is
  fair to both sides.

Every augment is a LINEAR anchored cell. Resolution (`chess.resolve`) consumes
the full set — both base stakes plus every augment from both players — into a
single winner anchor transition. Linearity guarantees no augment can be dropped
(stake can't vanish) or duplicated (no double payout). This is precisely the
`betAmount·2·multiplier` arithmetic chessgammon's contract did, but the
arithmetic is now a conservation law of the type system rather than a script
assertion.

---

## 7. The chess engine (locked: real, in-cartridge)

chessgammon never validated chess moves — `submitMove` was a frontend TODO and
the contract only checked state transitions. Here, **move legality is enforced
by a real chess engine inside the Zig walker cartridge**:

- `chess.submit_move` parses the move, runs full legality (checks, pins, en
  passant, castling rights, promotion), and only then emits a `chess.move.v1`
  cell DAG-linked to the prior position. An illegal move returns
  `DispatchError.invalid_params` and never produces a cell — the relay never
  broadcasts an illegal position.
- The engine also produces terminal verdicts (checkmate, stalemate, threefold,
  50-move, insufficient material) which drive `chess.resolve` without requiring
  both players to co-sign an outcome (chessgammon's `resolveGame` needed both
  signatures and still had no draw path).

This is a self-contained engine in the cartridge, consistent with the
"intelligence at the edges, none in the kernel/substrate" rule — the chess
engine is cartridge logic, not a kernel opcode and not an AI call.

---

## 8. Cartridge + world-app shape

Two artefacts (the two-cartridge-kinds model — a brain walker cartridge **and**
a world-app):

**`cartridges/chess/`** — walker-surface cartridge, `jambox` as the template.

```jsonc
// cartridges/chess/cartridge.json  (schema: core/protocol-types/src/extension-manifest.ts)
{
  "id": "chess",
  "name": "Chess (Doubling Cube)",
  "version": "0.1.0",
  "role": "experience",
  "experience": { "flutterPackage": "apps/world-apps/chess-game" },
  "brain": { "surface": "walkers", "verbsModule": "chess_walkers" },
  "verbs": [
    { "name": "chess.create_game",  "capability_required": "cap.chess.play" },
    { "name": "chess.join_game",    "capability_required": "cap.chess.play" },
    { "name": "chess.submit_move",  "capability_required": "cap.chess.play" },
    { "name": "chess.offer_double", "capability_required": "cap.chess.play" },
    { "name": "chess.accept_double","capability_required": "cap.chess.play" },
    { "name": "chess.decline_double","capability_required": "cap.chess.play" },
    { "name": "chess.resolve",      "capability_required": "cap.chess.play" }
  ]
}
```

`brain/chess_walkers.zig` registers each verb via the `verb_dispatcher.Registry`
(`WalkerFn = fn(allocator, ctx:*anyopaque, params_json) DispatchError![]u8`),
exactly as `jambox_walkers.zig` does. Capability names must be mirrored into the
Zig cap list (`runtime/semantos-brain/src/extensions.zig`, §9 acceptance gate)
until the manifest-loader (DLO.1c) lands. **Auth note**: gating is BRC-52 cert +
capability per the intended brain-auth model; current brain code is bearer-token
only. V1 preserves existing semantics — full cert/capability binding tracks with
the brain-auth alignment item (T7), not this doc.

**`apps/world-apps/chess-game/`** — UI + cell-relay integration, `jam-room` as
the template. The doubling cube renders via `core/cube-object`'s mesh, coloured
by linearity class.

---

## 9. Invite flow (replaces HTTP invite-code + 2s REST polling)

chessgammon used an 8-char invite code, REST endpoints, and 2-second polling
against an in-memory map. Replace with the BEAM cell-relay room
(`runtime/world-beam/apps/cell_relay`, `packages/world-sdk/src/relay`):

1. `chess.create_game` → emits `chess.game.v1` + the inviter's `chess.stake.v1`
   anchor; returns a room link `?room=chess-<gameId>&as=<identity>`.
2. Opponent opens the link → joins the relay room → receives the `snapshot` of
   game + stake cells, presence event fires.
3. `chess.join_game` → opponent's `chess.stake.v1` anchor. Both stakes present
   ⇒ `chess.game.v1` transitions to active; cube minted centered.
4. Moves and cube actions broadcast as cells over the relay (`commit`); the
   `parentHashes` DAG gives the audit trail chessgammon lacked. No polling.

---

## 10. Risks / constraints to respect

- **Single-threaded brain reactor**: a verb that triggers an on-chain anchor
  broadcast must **not** synchronously call back into the brain (self-call
  deadlock — see the 2026-05-18 outage). `chess.resolve`'s anchor submission
  uses the detached-grandchild submitter pattern, not an in-reactor sync call.
- **No hardcoded shortcuts**: stake amounts, clock config, and cube cap are
  game-creation parameters on `chess.game.v1`, not constants.
- **Anchor liveness**: `semantos_wallet_anchor_transition()` is native-target
  only; the P1 build stubs the anchor and exercises the full LINEAR state
  machine without money (mirrors jambox P1).
- **All-in cap accounting** must be unit-tested against the resolution
  conservation law: `Σ consumed stake/augment cells == winner payout +
  returned-unmatched`, with `SEMANTOS_ERR_ALREADY_CONSUMED` proving no replay.

---

## 11. Decisions — all locked

No open items. Per the 2026-05-19 decision: coverage model (commit-more-or-
all-in), real in-cartridge chess engine, single game clock with the offerer's
clock frozen while a double is pending, and — confirmed — **the cube starts
centered and either player may offer first on their own turn** (true
backgammon; not chessgammon's player-1-owns-first). §4 and §5 already assume
this; it is no longer configurable at game creation. Escrow custody is locked
to **Path A** — see §12.

---

## 12. Phase-2 escrow custody — pre-signed settlement (locked: Path A)

This section specifies *how the pot is actually held and released on BSV*. It
supersedes any "a bare 2-of-2 holds the pot" reading: a bare 2-of-2 is
**hostage-able** (if the loser never co-signs, the funds freeze forever), so
custody is 2-of-2 **plus a pre-signed exit refreshed at every state**.

### 12.1 Why not a smart contract (no sCrypt, no Rúnar)

The enforced exit could instead be a *result-conditioned* spend — the winner
claims by proving the game outcome in the locking script (sCrypt, or a
Rúnar-compiled Zig predicate; runar.build is a multi-language→Bitcoin-Script
compiler, i.e. the same class of tool as sCrypt). **Rejected (Path B).** It
re-introduces the on-chain contract the linear-object thesis deletes, and
"prove a chess result in a spend condition" is exactly the hard problem we
removed sCrypt to avoid. The LINEAR resolution cell stays the off-chain audit
layer; the script never learns the game result.

### 12.2 BSV reality — tx-level locks only

BSV has **no `OP_CHECKSEQUENCEVERIFY` / `OP_CHECKLOCKTIMEVERIFY`**. You cannot
put a timelocked branch *inside* a script. Timelocks are transaction-level
only: **`nLockTime`** (absolute) and **`nSequence`** (relative, BIP-68
semantics enforced at consensus), made tamper-proof because the counterparty's
signature commits to them via SIGHASH. So the anti-hostage mechanism is a
**pre-signed transaction**, not a script clause. This is the original
Satoshi/Spilman channel construction, *not* Poon-Dryja (which needs CSV).

### 12.3 The construction

- **Pot** = a 2-of-2 multisig funding output (both players' BCA-derived keys).
- **Cooperative path (fast)**: both sign the final settlement, `nSequence =
  0xFFFFFFFF` (immediately final). Used whenever both are honest — one
  settlement tx, done.
- **Enforced exit**: *before the funding tx is broadcast*, the parties exchange
  a fully both-signed settlement tx spending the 2-of-2, dated with a future
  `nLockTime` and a non-final `nSequence`. Either party can broadcast it
  unilaterally once the lock matures — no counterparty cooperation needed at
  settlement. *That* is "get your loot if they dig in."
- **Per-double refresh**: §6/D2 is uncapped per-double funding (locked — the
  psychology: players won't pre-fund the cube's cap; the live, pressured
  funding decision *is* the product). So each accepted double adds its funding
  to the pot **and** the parties exchange a **new** both-signed settlement
  reflecting the new at-stake split, with a **higher `nSequence`** (ratchet)
  and tightened `nLockTime`. The newest mutually-signed state supersedes older
  ones.
- **Path A exit semantics**: the enforced settlement pays the **last
  mutually-agreed split**. By construction that is the correct result — you
  only ever co-sign a split you accepted (accept-double, decline→offerer,
  game-end→winner are each a co-signed state; a player who won't co-sign the
  new state simply leaves the *prior* co-signed state as the enforced exit,
  which is still correct for them).

### 12.4 Exchange transport

Settlement/funding packages are exchanged as **BEEF (BRC-62) + BUMP merkle
paths verified against a local headers chain (SPV)** — acceptance is an
instant, locally-verifiable exchange, *not* a wait on network confirmation.
This removes the "fund under a ticking clock" race entirely. The
invite→accept→fund handshake reuses the cashlanes `ChannelFSM` pattern
(`UNFUNDED→FUNDING_PENDING→FUNDED→…`), adapted to game states.

### 12.5 Honest caveat — the guarantee, precisely

The pure nSequence-replacement model has a known fragility: BSV gives no
consensus guarantee that a higher-`nSequence` tx evicts a lower one from every
mempool, so a griefer can *attempt* to get a stale state mined. The real
backstop is therefore the **`nLockTime`-dated pre-signed refund to the last
mutually-agreed split**. Maximum harm a digging-in counterparty can impose:
**bounded delay (until `nLockTime`) + the on-chain fee**. They **cannot steal
and cannot freeze funds permanently**. That is the strongest property BSV
script affords without an arbiter — and it is exactly what chessgammon's sCrypt
was buying, reconstructed in pre-signed txs + LINEAR-cell bookkeeping.

### 12.6 Reactor safety (reaffirms §10)

Funding and settlement broadcasts must not synchronously call back into the
single-threaded brain reactor (2026-05-18 self-call outage class). Use the
detached-grandchild submitter; SPV/BEEF verification is local and synchronous,
the *broadcast* is detached.
