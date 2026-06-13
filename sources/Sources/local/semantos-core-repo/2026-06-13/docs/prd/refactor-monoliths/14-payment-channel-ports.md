---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/14-payment-channel-ports.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.771846+00:00
---

# 14 — Payment-channel: define and wire ports

**Phase:** 6 (Payment channel) · **Depends on:** 06, 13 · **Est. effort:** 1 day · **Branch:** `refactor/14-payment-channel-ports`

## Why

Today `payment-channel.ts` instantiates wallets, broadcasters, and signers inline, which (a) makes testing require a live wallet, (b) violates the CashLanes role-isolation rule, and (c) couples the FSM to concrete implementations. Split every external dependency into a port declared in `core/protocol-types`.

## Deliverables

Create under `core/protocol-types/src/ports/`:

- `wallet-port.ts` — `walletPort = port<WalletClient>('wallet')` plus role-scoped factory `createWalletPort(role: 'provider' | 'consumer')`.
- `utxo-provider-port.ts` — `utxoProviderPort = port<UtxoProvider>('utxo-provider')` with `listUtxos(address): Utxo[]`, `watch(address, cb): Dispose`.
- `broadcaster-port.ts` — `broadcasterPort = port<Broadcaster>('broadcaster')` with `broadcast(rawTx): Promise<{ txid, ok }>`.
- `signer-port.ts` — `signerPort = port<Signer>('signer')` with `sign(message, keyId): Signature`, `derivePublicKey(keyId): string`.
- `spv-port.ts` — `spvPort = port<SpvVerifier>('spv')` with `verifyBeef(beef, txid): Promise<boolean>`, `verifyBump(bump, txid): Promise<boolean>`.
- `logger-port.ts` — `loggerPort = port<Logger>('logger')`.

Create under `apps/poker-agent/src/payment-channel/ports/`:

- `index.ts` — re-exports the core ports above plus any poker-specific ports (e.g. `channelIdGeneratorPort`).
- `default-bindings.ts` — factory that binds concrete impls at app boot (wraps existing metanet-desktop client, existing ARC wrapper, etc).
- `test-doubles.ts` — in-memory fakes usable from tests; exported so other packages can reuse.

Edit:

- `apps/poker-agent/src/payment-channel.ts` — replace every `new WalletClient(...)`, `new ARC(...)`, etc. with `walletPort.get()`, etc. Pass the role tag at instantiation.

## Acceptance criteria

- [ ] Every external dependency accessed only through a port.
- [ ] Provider-role and consumer-role wallets bound to separate ports per CashLanes role-isolation.
- [ ] Tests updated to bind `test-doubles` instead of live impls — no network calls in the test suite.
- [ ] `pnpm -r check` passes.
- [ ] `grep -rn "new WalletClient\|new ARC" apps/poker-agent/src/payment-channel` returns 0 matches.

## Out of scope

- Effect atoms (prompt 15).
- Other poker files — this PR is scoped to payment-channel only.

## Test plan

Bind `test-doubles` throughout test suite; ensure channel flows complete without any network access. Snapshot tests from prompt 13 still pass.
