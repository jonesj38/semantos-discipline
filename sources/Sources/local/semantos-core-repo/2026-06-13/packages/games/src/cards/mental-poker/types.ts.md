---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/mental-poker/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.434575+00:00
---

# packages/games/src/cards/mental-poker/types.ts

```ts
/**
 * Mental Poker Types
 *
 * SRA (Shamir-Rivest-Adleman) commutative encryption protocol for
 * trustless card games. No single party can see any card until it's
 * legitimately revealed.
 *
 * Key property: E_a(E_b(m)) = E_b(E_a(m)) — encryption commutes,
 * so players can encrypt in any order and decrypt in any order.
 *
 * Each protocol step produces a commitment stored as a cell in the DAG.
 */

// ── Key Material ────────────────────────────────────────────

export interface PlayerKeyPair {
  /** Player identifier. */
  playerId: string;
  /** Secret encryption exponent. */
  encryptKey: bigint;
  /** Secret decryption exponent (modular inverse of encryptKey). */
  decryptKey: bigint;
  /** Public commitment: H(encryptKey) — proves key wasn't changed mid-game. */
  keyCommitment: string;
}

// ── Encrypted Cards ─────────────────────────────────────────

export interface MentalCard {
  /** Card index in the canonical deck (0-51). */
  index: number;
  /** Current encrypted value (BigInt as hex string for serialization). */
  encryptedValue: string;
  /** Which players have encrypted this card (in order). */
  encryptedBy: string[];
}

export interface MentalDeck {
  /** All 52 cards in their current (possibly encrypted, shuffled) state. */
  cards: MentalCard[];
  /** Protocol phase this deck is in. */
  phase: DeckPhase;
}

export type DeckPhase =
  | 'initial'           // Cards mapped to canonical values, unencrypted
  | 'encrypting'        // Players are encrypting and shuffling in turn
  | 'locked'            // All players have encrypted — deck is locked
  | 'dealing'           // Cards being dealt (selective decryption)
  | 'complete';         // Hand is over

// ── Protocol Proofs ─────────────────────────────────────────

/** Proof that a shuffle was performed honestly. */
export interface ShuffleProof {
  /** Who performed this shuffle step. */
  playerId: string;
  /** SHA-256 of the deck state BEFORE this shuffle. */
  inputCommitment: string;
  /** SHA-256 of the deck state AFTER this shuffle. */
  outputCommitment: string;
  /** Timestamp. */
  timestamp: number;
}

/** Proof that a card was decrypted honestly. */
export interface DecryptionProof {
  /** Who decrypted. */
  playerId: string;
  /** Card position in the shuffled deck. */
  cardPosition: number;
  /** Encrypted value before decryption. */
  encryptedBefore: string;
  /** Value after this player's decryption layer removed. */
  decryptedAfter: string;
  /** SHA-256 commitment of the decryption. */
  commitment: string;
  /** Timestamp. */
  timestamp: number;
}

/** Proof of key reveal (at showdown or for verification). */
export interface KeyRevealProof {
  playerId: string;
  /** The encryption key (revealed). */
  encryptKey: string;
  /** Must match the keyCommitment from setup. */
  keyCommitment: string;
  /** Timestamp. */
  timestamp: number;
}

// ── Protocol State ──────────────────────────────────────────

export interface ProtocolState {
  /** All player key commitments (established at game start). */
  keyCommitments: Map<string, string>;
  /** Canonical card mapping: index → large random value. Public. */
  cardMapping: string[];
  /** Current deck state. */
  deck: MentalDeck;
  /** All shuffle proofs in order. */
  shuffleProofs: ShuffleProof[];
  /** All decryption proofs in order. */
  decryptionProofs: DecryptionProof[];
  /** Key reveal proofs (populated at showdown). */
  keyRevealProofs: KeyRevealProof[];
  /** The prime modulus used for SRA encryption. */
  prime: string;
  /** Player order for shuffle/encryption. */
  playerOrder: string[];
}

// ── Card Canonical Mapping ──────────────────────────────────

export interface CardIdentity {
  index: number;
  suit: string;
  rank: number;
}

/** Full verification result. */
export interface VerificationResult {
  valid: boolean;
  errors: string[];
  /** Number of protocol steps verified. */
  stepsVerified: number;
}

```
