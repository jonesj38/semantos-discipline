---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/LocalIdentityAdapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.889432+00:00
---

# core/protocol-types/src/identity-adapters/LocalIdentityAdapter.ts

```ts
/**
 * @deprecated Use `@semantos/protocol-types/identity-adapters/local` (or
 * `@semantos/protocol-types/identity-adapters/local/local-identity-adapter`)
 * instead. This module is a one-release re-export shim for the new
 * home of the LocalIdentityAdapter under `local/`. It will be removed
 * once all consumers have migrated.
 *
 * The split lives in `core/protocol-types/src/identity-adapters/local/`:
 *   - `ports.ts`                  loggerPort + recoveryChallengesPort
 *   - `signing-key-deriver.ts`    sigKeyFromPem + sha256HexStr
 *   - `cert-chain-store-facade.ts` re-export of CertChainStore
 *   - `private-key-resolver.ts`   atom-backed key cache + resolver
 *   - `identity-registrar.ts`     registerRootIdentity + deriveChildIdentity
 *   - `recovery-share-manager.ts` initiateRecovery + submitChallengeAnswers
 *   - `subtree-querier.ts`        querySubtree
 *   - `local-identity-adapter.ts` public LocalIdentityAdapter class
 */

export {
  LocalIdentityAdapter,
  ALL_DOMAIN_FLAGS,
  DEFAULT_TOKEN_TTL,
  type LocalIdentityConfig,
} from './local/local-identity-adapter';

```
