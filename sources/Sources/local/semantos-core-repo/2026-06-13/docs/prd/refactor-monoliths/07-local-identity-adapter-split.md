---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/07-local-identity-adapter-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.775072+00:00
---

# 07 — Split `core/protocol-types/src/identity-adapters/LocalIdentityAdapter.ts`

**Phase:** 3 (Core protocol-types) · **Depends on:** 01 · **Est. effort:** 0.5 day · **Branch:** `refactor/07-local-identity-split`

## Why

529 LOC offline identity adapter conflating key derivation, capability token validation, cert storage, private-key cache, recovery challenges, subtree queries, and edge management. Has module-level `setCertChainStore`/`setKeyCache` setters — the anti-pattern to fix via ports.

## Deliverables

Create under `core/protocol-types/src/identity-adapters/local/`:

- `cert-chain-store-facade.ts` — wraps `CertChainStore`; exposes a clean interface.
- `private-key-resolver.ts` — `resolvePrivateKey(certId)` with atom-backed cache: `privateKeyCacheAtom = atom(new Map<CertId, Uint8Array>())`.
- `identity-registrar.ts` — `registerRootIdentity(email)` and `deriveChildIdentity(...)`.
- `recovery-share-manager.ts` — challenge/answer/session flow.
- `subtree-querier.ts` — pure recursive walk: `querySubtree(rootCertId, depth, store)`.
- `signing-key-deriver.ts` — `fromPublicKey(pem)` isolation.
- `ports.ts` — `certChainStorePort`, `keyCachePort`, `loggerPort`, `recoveryChallengesPort`.
- `local-identity-adapter.ts` — the facade class, thin.
- `__tests__/*.test.ts`.

Edit:

- `core/protocol-types/src/identity-adapters/LocalIdentityAdapter.ts` → re-export facade, add deprecation JSDoc. Remove module-level setters — replace with port bindings.

## Acceptance criteria

- [ ] Module-level mutable state removed; all config via ports.
- [ ] `debugLogging` flag replaced by `loggerPort`.
- [ ] Hardcoded `RECOVERY_CHALLENGES` array moved to injectable config.
- [ ] All existing tests pass after updating to bind ports in test setup.
- [ ] `pnpm -r check` passes.

## Out of scope

- Protocol-level changes to identity derivation (deterministic derivation must remain identical).

## Test plan

Deterministic derivation snapshot: seed with a fixed email, derive 10 generations of child identities, compare public keys against golden values.
