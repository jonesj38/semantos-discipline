---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.522643+00:00
---

# packages/game-sdk/src/types.ts

```ts
/**
 * Game Engine SDK — Core Types
 *
 * Maps game concepts onto cell engine primitives:
 *   LINEAR  → unique items (legendary sword — one instance, no duplication)
 *   AFFINE  → consumables (health potion — use once, then gone)
 *   RELEVANT → quest markers (must keep, can inspect, cannot discard)
 *   FUNGIBLE → currency/ammo (freely copy, split, merge)
 *
 * Every GameEntity IS a cell. There is no shadow state.
 */

import type { Linearity } from '../../../core/protocol-types/src/constants';

// ── Entity Types ────────────────────────────────────────────────

export enum GameEntityType {
  CHARACTER = 0,
  ITEM = 1,
  CURRENCY = 2,
  STRUCTURE = 3,
  VEHICLE = 4,
  QUEST = 5,
  CUSTOM = 255,
}

// ── Game Entity ─────────────────────────────────────────────────

export interface GameEntity {
  /** Deterministic entity ID (hex of the cell's typeHash) */
  id: string;
  /** Entity classification */
  entityType: GameEntityType;
  /** 16-byte owner identifier */
  ownerId: Uint8Array;
  /** Linearity class (LINEAR=1, AFFINE=2, RELEVANT=3, DEBUG=4) */
  linearity: number;
  /** Current state label (for state machine transitions) */
  state: string;
  /** Arbitrary key-value metadata (serialized as JSON in payload) */
  metadata: Record<string, unknown>;
  /** Packed 1024-byte cell — the source of truth */
  cell: Uint8Array;
  /** Creation timestamp from cell header (ms since epoch) */
  timestamp: bigint;
}

// ── Inventory ───────────────────────────────────────────────────

export interface Inventory {
  /** Owner of this inventory */
  ownerId: Uint8Array;
  /** Slot name → packed 1024-byte cell buffer */
  slots: Map<string, Uint8Array>;
}

// ── Trade ───────────────────────────────────────────────────────

export interface TradeOffer {
  /** Slot names from the offeror's inventory */
  slots: string[];
}

export interface TradeProposal {
  /** Party A's inventory and offered items */
  partyA: { inventory: Inventory; offer: TradeOffer };
  /** Party B's inventory and offered items */
  partyB: { inventory: Inventory; offer: TradeOffer };
}

export interface TradeResult {
  success: boolean;
  /** Updated inventories (only set if success=true) */
  updatedA?: Inventory;
  updatedB?: Inventory;
  /** Error message if success=false */
  error?: string;
}

// ── State Machine ───────────────────────────────────────────────

export interface EntityState {
  name: string;
  /** Optional entry policy (Lisp s-expression, compiled and verified on entry) */
  entryPolicy?: string;
}

export interface EntityTransition {
  from: string;
  to: string;
  /** Policy expression that must evaluate to true for this transition */
  policy: string;
}

export interface EntityStateMachine {
  states: EntityState[];
  transitions: EntityTransition[];
  initialState: string;
}

// ── Policy ──────────────────────────────────────────────────────

export type LinearityMode = 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';

export interface GamePolicy {
  /** Lisp source expression */
  source: string;
  /** Compiled script bytes for the cell engine */
  scriptBytes: Uint8Array;
  /** Human-readable opcode mnemonics */
  scriptWords: string;
  /** Linearity mode */
  linearity: LinearityMode;
}

// ── Payload Codec Constants ─────────────────────────────────────

/** Binary prefix size in the entity payload */
export const ENTITY_PAYLOAD_HEADER_SIZE = 8;
/** Maximum metadata + script size in the payload region */
export const MAX_PAYLOAD_CONTENT_SIZE = 768 - ENTITY_PAYLOAD_HEADER_SIZE;

// ── Error Types ─────────────────────────────────────────────────

export class LinearityError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LinearityError';
  }
}

export class TradeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TradeError';
  }
}

export class TransitionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TransitionError';
  }
}

```
