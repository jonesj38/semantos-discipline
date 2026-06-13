---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/06-wallet-client-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.777337+00:00
---

# 06 — Split `core/protocol-types/src/wallet-client.ts`

**Phase:** 3 (Core protocol-types) · **Depends on:** 01 · **Est. effort:** 0.5 day · **Branch:** `refactor/06-wallet-client-split`

## Why

535 LOC BRC-100 wallet abstraction mixing HTTP transport, request building, error handling, path fallback, response parsing, and BRC-100 spec details. Every runtime that talks to metanet-desktop reaches into this.

The CashLanes guardrails in `CLAUDE.md` require role-scoped wallet instances (provider vs consumer) with distinct Origin forwarding and cookie jars. The current monolith makes role isolation awkward; splitting into transport + request-builder + method files removes the friction.

## Deliverables

Create under `core/protocol-types/src/wallet-client/`:

- `wallet-http-transport.ts` — `httpTransportPort = port<HttpTransport>('wallet-http')`. Default impl uses `fetch` with origin forwarding, cookie jar, timeout.
- `wallet-path-resolver.ts` — `tryPaths(method, paths, body, transport): Response` — generic fallback.
- `wallet-request-builder.ts` — pure per-method builders: `buildCreateAction`, `buildGetPublicKey`, `buildListOutputs`, `buildSignAction`, `buildInternalizeAction`, `buildGetHeight`, `buildGetNetwork`.
- `wallet-response-parser.ts` — pure parsers mirroring the builders.
- `wallet-error-handler.ts` — `toWalletClientError(response): WalletClientError`.
- `methods/` — one file per BRC-100 method, each ~40 LOC: compose builder + transport + parser.
- `wallet-client-facade.ts` — the class, thin, delegates to `methods/`.
- `__tests__/*.test.ts`.

Edit:

- `core/protocol-types/src/wallet-client.ts` → re-export facade.

## Acceptance criteria

- [ ] Each `methods/*.ts` ≤ 60 LOC.
- [ ] `WalletClientError` single source of truth, no duplicate string literals.
- [ ] Transport is pluggable via port.
- [ ] All existing tests pass.
- [ ] New per-method unit tests with stubbed transport.
- [ ] `pnpm -r check` passes.

## Out of scope

- Adding role-scoped wallet instances (that's a CashLanes prompt, tracked separately in `HANDOFF.md`).
- Changing BRC-100 method signatures.

## Test plan

Contract test: stub transport returns canned responses from recorded metanet-desktop interactions. Assert every method decodes and propagates identically to pre-refactor.
