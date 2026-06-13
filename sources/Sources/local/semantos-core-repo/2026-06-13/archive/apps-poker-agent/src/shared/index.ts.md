---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/shared/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.769946+00:00
---

# archive/apps-poker-agent/src/shared/index.ts

```ts
/**
 * Shared poker primitives — single source of truth for card types,
 * deterministic shuffle, hand evaluation, audit logs, and BEEF codec.
 *
 * Phase 7 (poker-stack) prompts 17–21 import from here instead of
 * reimplementing locally.
 */

export {
  cardLabel,
  createDeck,
  RANK_LABELS,
  SUITS,
  SUIT_CHAR,
  type Card,
  type Hand,
  type Rank,
  type Suit,
} from './card-types';

export {
  deterministicShuffle,
  randomShuffle,
  shuffleDeck,
} from './deterministic-shuffle';

export {
  comparePokerHands,
  evaluatePokerHand,
  pickWinner,
  rankPlayers,
  type EvaluatedHand,
  type HandRank,
  type PlayerHand,
  type ShowdownEntry,
} from './hand-evaluator';

export {
  AuditLogBuilder,
  renderAuditLog,
  type AuditEvent,
  type AuditLogOptions,
} from './audit-log-builder';

export {
  fromArray,
  isBeefArray,
  isHexBeef,
  toArray,
  type BeefInput,
} from './beef-codec';

```
