---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/plexus/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.676494+00:00
---

# cartridges/wallet-headers/brain/src/plexus/index.ts

```ts
// Plexus dispatch module — public API barrel (W7).
//
// Per `docs/design/WALLET-TIER-CUSTODY.md` §8.1 the wallet bundle includes
// a small Plexus Dispatch Module that builds the dispatch envelope, signs
// it, and walks the OTP loop on enrollment / recovery. Everything in this
// barrel is the *public* surface the rest of the wallet (popup UI, bridge,
// future wallet-UI in W9) calls into.

export {
  buildEnvelope,
  decryptRecoverySeed,
  hashAnswerHex,
  normalizeAnswer,
  PBKDF2_ITERATIONS,
  ENVELOPE_VERSION,
  ALGORITHM_VERSION,
  type PlexusRecoveryEnvelope,
  type DerivationContext,
  type DerivationStateRecord,
  type DerivationStateSnapshot,
  type ChallengeBundle,
  type EncryptedRecoverySeed,
  type RecoveryPolicy,
  type BuildEnvelopeInput,
  type BuildResult,
  type BuildError,
} from './envelope';

export {
  enroll,
  enrollCachedEnvelope,
  recover,
  type EnrollParams,
  type EnrollCachedParams,
  type EnrollResult,
  type EnrollError,
  type RecoverParams,
  type RecoverResult,
  type RecoverError,
  type Result,
  type OtpPromptFn,
  type AnswerPromptFn,
} from './dispatch';

export {
  MockPlexusOperator,
  HttpPlexusOperator,
  DEFAULT_MOCK_POLICY,
  sha256FingerprintHex,
  type PlexusOperator,
  type PlexusOperatorConfig,
  type Brc100Wire,
  type OperatorResponse,
  type OperatorInfo,
  type MockOperatorPolicy,
} from './operator';

```
