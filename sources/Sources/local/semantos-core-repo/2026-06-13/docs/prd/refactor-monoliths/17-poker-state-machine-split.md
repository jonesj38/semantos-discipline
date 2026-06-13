---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/17-poker-state-machine-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.771600+00:00
---

# 17 — Split `apps/poker-agent/src/poker-state-machine.ts`

**Phase:** 7 (Poker stack) · **Depends on:** 14, 16 · **Est. effort:** 1 day · **Branch:** `refactor/17-poker-state-machine`

## Why

742 LOC managing LINEAR CellToken transitions via 2PDA with P2P key alternation, cell construction, deferred signing, UTXO tracking, and OP_RETURN anchoring.

## Deliverables

Create under `apps/poker-agent/src/poker-state-machine/`:

- `cell-builder.ts` — pure: `buildCell(stateHash, prevStateHash, metadata)` using the `CellStore` facade from prompt 04.
- `celltoken-signer.ts` — UTXO discovery, preimage creation, deferred signature, unlock script assembly. Uses `walletPort`, `signerPort`, `utxoProviderPort`.
- `p2p-key-manager.ts` — key derivation + alternating pubkey tracking. Atoms: `myPubKeyAtom`, `opponentPubKeyAtom`, `keyIdAtom`.
- `event-anchor.ts` — `anchorEvent()`, `anchorEventBatch()`. OP_RETURN batch builder.
- `utxo-tracker.ts` — `LiveUtxo` cache as atom: `liveUtxoAtom = atom<LiveUtxo | null>(null)`.
- `state-machine-facade.ts` — thin `PokerStateMachine` class orchestrating the modules.
- `__tests__/*.test.ts`.

Edit:

- `apps/poker-agent/src/poker-state-machine.ts` → re-export facade.

## Acceptance criteria

- [ ] No file over 250 LOC.
- [ ] BEEF conversion uses `shared/beef-codec.ts` (prompt 16).
- [ ] Wallet/UTXO access via ports only.
- [ ] All existing state-machine tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing the CellToken protocol or 2PDA logic.

## Test plan

Record 5 full hands pre-refactor; replay transitions through new facade; cell byte outputs identical.
