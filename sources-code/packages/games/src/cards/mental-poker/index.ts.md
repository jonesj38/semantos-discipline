---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/mental-poker/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.434287+00:00
---

# packages/games/src/cards/mental-poker/index.ts

```ts
/**
 * Mental Poker — trustless card game protocol using SRA commutative encryption.
 *
 * No single party can see any card until legitimately revealed.
 * Every protocol step produces a cryptographic proof stored in the cell DAG.
 * The full game can be verified post-hoc by replaying all steps.
 */

// Protocol
export { MentalPokerProtocol } from './protocol';
export { TrustlessPokerEngine } from './trustless-engine';

// Crypto
export {
  generateKeyPair,
  sraEncrypt,
  sraDecrypt,
  modPow,
  modInverse,
  commitDeck,
  commitKey,
  SRA_PRIME,
} from './crypto';

// Transport (shard multicast)
export { PokerTableTransport } from './transport';
export type {
  PokerMessage,
  PokerMessageType,
  PokerTransportConfig,
  KeyRegistrationPayload,
  ShufflePayload,
  DecryptionPayload,
  ActionPayload,
  CommunityRevealPayload,
  KeyRevealPayload,
  VerificationPayload,
} from './transport';

// Types
export type {
  PlayerKeyPair,
  MentalCard,
  MentalDeck,
  ShuffleProof,
  DecryptionProof,
  KeyRevealProof,
  ProtocolState,
  VerificationResult,
  CardIdentity,
  DeckPhase,
} from './types';

```
