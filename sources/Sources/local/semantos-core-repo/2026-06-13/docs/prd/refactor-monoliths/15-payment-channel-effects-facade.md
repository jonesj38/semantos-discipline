---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/15-payment-channel-effects-facade.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.770589+00:00
---

# 15 — Payment-channel: effect atoms + shrink facade

**Phase:** 6 (Payment channel) · **Depends on:** 13, 14 · **Est. effort:** 1 day · **Branch:** `refactor/15-payment-channel-effects`

## Why

Final step to collapse the 1627 LOC monolith. Reducer is pure (13), external deps are portified (14). Now each emitted command/event from the reducer gets its own effect atom subscriber: one persists to CellStore, one broadcasts, one records fee credits, one logs. Facade shrinks to a thin orchestrator that `dispatch`es actions and exposes the atoms.

## Deliverables

Create under `apps/poker-agent/src/payment-channel/effects/`:

- `persist-effect.ts` — subscribes to emitted `PersistCommand`s; writes frozen artifacts to CellStore. Enforces byte-freeze guardrail from `CLAUDE.md`.
- `broadcast-effect.ts` — subscribes to emitted `BroadcastCommand`s; calls `broadcasterPort`.
- `spv-effect.ts` — subscribes to `AwaitSpvCommand`s; polls `spvPort`; emits `SpvConfirmed` or `SpvTimeout`.
- `fee-credit-effect.ts` — handles 1-sat UTXO generation commands per CashLanes fee-credits rules.
- `log-effect.ts` — subscribes to all events; writes structured log via `loggerPort`.

Create under `apps/poker-agent/src/payment-channel/`:

- `atoms.ts` — `channelStateAtom = atom<ChannelState>(UNFUNDED)`, `artifactsAtom = atom<ChannelArtifacts | null>(null)`, `channelEventsBus = eventBus<ChannelEvent>()`.
- `facade.ts` — `PaymentChannel` class (or functions): `fund`, `extract`, `bindConsumer`, `internalizeConsumer`, `internalizeProvider`, `settle`, `close`. Each dispatches one action; reading state goes through atoms.
- `boot.ts` — wires all effects at startup (idempotent).

Edit:

- `apps/poker-agent/src/payment-channel.ts` — reduces to a re-export of `facade.ts`. Add deprecation JSDoc pointing to the new module.

## Acceptance criteria

- [ ] Original `payment-channel.ts` file ≤ 80 LOC (facade re-export + docs only).
- [ ] No file in the new module over 250 LOC.
- [ ] Effects can be swapped/disabled individually in tests (verify with a test that swaps `persist-effect` for a no-op).
- [ ] Integration test: full channel lifecycle with test doubles passes in <1s.
- [ ] `pnpm -r check` passes.
- [ ] `bun test apps/poker-agent` passes.

## Out of scope

- Migrating poker-state-machine (prompt 17) or other poker files to use these atoms (happens in their own prompts).

## Test plan

End-to-end channel lifecycle with test doubles — happy path, settlement, close. Compare structured log output against golden fixture.
