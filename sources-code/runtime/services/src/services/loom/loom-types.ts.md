---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/loom-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.103010+00:00
---

# runtime/services/src/services/loom/loom-types.ts

```ts
/**
 * Loom state types — the canonical state shape and action union for the
 * renderer-agnostic LoomStore. Pure types only; no runtime imports beyond
 * the shared type module.
 */

import type {
  LoomObject,
  LoomCard,
  CardConnection,
  ObjectPatch,
} from '../../types/loom';

/** Overall loom state. */
export interface LoomState {
  objects: Map<string, LoomObject>;
  cards: Map<string, LoomCard>;
  selectedObjectId: string | null;
  selectedCardId: string | null;
  categoryFilter: string | null;
}

/** All actions the reducer understands. */
export type LoomAction =
  | { type: 'ADD_OBJECT'; object: LoomObject; openAsCard?: boolean }
  | { type: 'UPDATE_OBJECT'; id: string; updates: Partial<LoomObject> }
  | { type: 'DELETE_OBJECT'; id: string }
  | { type: 'SELECT_OBJECT'; id: string | null }
  | { type: 'ADD_CARD'; card: LoomCard }
  | { type: 'MOVE_CARD'; id: string; position: { x: number; y: number } }
  | { type: 'RESIZE_CARD'; id: string; size: { width: number; height: number } }
  | { type: 'CONNECT_CARDS'; connection: CardConnection }
  | { type: 'DISCONNECT_CARDS'; connectionId: string; cardId: string }
  | { type: 'UPDATE_CARD_STATE'; id: string; state: LoomCard['state'] }
  | { type: 'SET_CAPABILITY'; objectId: string; flagId: number; enabled: boolean }
  | { type: 'TRANSITION_LINEARITY'; objectId: string; newLinearity: number }
  | { type: 'ADD_PATCH'; objectId: string; patch: ObjectPatch }
  | { type: 'FILTER_BY_CATEGORY'; path: string | null }
  | { type: 'UPDATE_PAYLOAD'; objectId: string; field: string; value: unknown }
  | {
      type: 'TRANSITION_VISIBILITY';
      objectId: string;
      newVisibility: 'draft' | 'published' | 'revoked';
    };

/** The empty starting state used by every fresh LoomStore. */
export const initialState: LoomState = {
  objects: new Map(),
  cards: new Map(),
  selectedObjectId: null,
  selectedCardId: null,
  categoryFilter: null,
};

```
