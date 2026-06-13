---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.914274+00:00
---

# core/protocol-types/src/identity-adapters/local/index.ts

```ts
/**
 * Local-identity barrel — re-exports the public class plus the
 * helpers most consumers of the splits will want directly.
 */

export {
  LocalIdentityAdapter,
  ALL_DOMAIN_FLAGS,
  DEFAULT_TOKEN_TTL,
  type LocalIdentityConfig,
} from './local-identity-adapter';
export {
  bindDefaultLocalIdentityPorts,
  consoleDebugLogger,
  silentLogger,
  loggerPort,
  recoveryChallengesPort,
  getLogger,
  getRecoveryChallenges,
  DEFAULT_RECOVERY_CHALLENGES,
  type IdentityLogger,
  type RecoveryChallenge,
} from './ports';
export {
  privateKeyCacheAtom,
  resolvePrivateKey,
  cacheKey,
  getKey,
  clearKeyCache,
} from './private-key-resolver';
export { CertChainStore, type CertData } from './cert-chain-store-facade';
export {
  registerRootIdentity,
  deriveChildIdentity,
} from './identity-registrar';
export {
  initiateRecovery,
  submitChallengeAnswers,
} from './recovery-share-manager';
export { querySubtree, type SubtreeResult, type SubtreeChild } from './subtree-querier';
export { sigKeyFromPem, sha256HexStr } from './signing-key-deriver';

```
