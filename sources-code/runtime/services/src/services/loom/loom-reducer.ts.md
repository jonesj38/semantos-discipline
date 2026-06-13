---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/loom-reducer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.103642+00:00
---

# runtime/services/src/services/loom/loom-reducer.ts

```ts
/**
 * loomReducer — pure (state, action) → state for the loom workbench.
 *
 * Every transition is structural-share only: we copy the Map(s) we touch
 * and leave untouched fields aliasing the previous state. No `this`, no
 * async, no service calls — anything side-effectful belongs in the
 * LoomStore facade or in the handlers introduced in prompt 03.
 */

import type { LoomAction, LoomState } from './loom-types';

export function loomReducer(state: LoomState, action: LoomAction): LoomState {
  switch (action.type) {
    case 'ADD_OBJECT': {
      const objects = new Map(state.objects);
      objects.set(action.object.id, action.object);
      if (action.openAsCard) {
        const cards = new Map(state.cards);
        const cardId = `card-${action.object.id}`;
        const cardCount = cards.size;
        cards.set(cardId, {
          id: cardId,
          type: 'object' as const,
          objectId: action.object.id,
          position: { x: 100 + (cardCount % 5) * 40, y: 100 + (cardCount % 5) * 40 },
          size: { width: 320, height: 400 },
          state: 'expanded' as const,
          connections: [],
        });
        return { ...state, objects, cards, selectedObjectId: action.object.id };
      }
      return { ...state, objects };
    }
    case 'UPDATE_OBJECT': {
      const obj = state.objects.get(action.id);
      if (!obj) return state;
      const objects = new Map(state.objects);
      objects.set(action.id, { ...obj, ...action.updates, updatedAt: Date.now() });
      return { ...state, objects };
    }
    case 'DELETE_OBJECT': {
      const objects = new Map(state.objects);
      objects.delete(action.id);
      const cards = new Map(state.cards);
      for (const [cid, card] of cards) {
        if (card.objectId === action.id) cards.delete(cid);
      }
      return {
        ...state,
        objects,
        cards,
        selectedObjectId: state.selectedObjectId === action.id ? null : state.selectedObjectId,
      };
    }
    case 'SELECT_OBJECT': {
      return { ...state, selectedObjectId: action.id };
    }
    case 'ADD_CARD': {
      const cards = new Map(state.cards);
      cards.set(action.card.id, action.card);
      return { ...state, cards };
    }
    case 'MOVE_CARD': {
      const card = state.cards.get(action.id);
      if (!card) return state;
      const cards = new Map(state.cards);
      cards.set(action.id, { ...card, position: action.position });
      return { ...state, cards };
    }
    case 'RESIZE_CARD': {
      const card = state.cards.get(action.id);
      if (!card) return state;
      const cards = new Map(state.cards);
      cards.set(action.id, { ...card, size: action.size });
      return { ...state, cards };
    }
    case 'CONNECT_CARDS': {
      const fromCard = state.cards.get(action.connection.fromCardId);
      if (!fromCard) return state;
      const cards = new Map(state.cards);
      cards.set(fromCard.id, {
        ...fromCard,
        connections: [...fromCard.connections, action.connection],
      });
      return { ...state, cards };
    }
    case 'DISCONNECT_CARDS': {
      const card = state.cards.get(action.cardId);
      if (!card) return state;
      const cards = new Map(state.cards);
      cards.set(card.id, {
        ...card,
        connections: card.connections.filter(c => c.id !== action.connectionId),
      });
      return { ...state, cards };
    }
    case 'UPDATE_CARD_STATE': {
      const card = state.cards.get(action.id);
      if (!card) return state;
      const cards = new Map(state.cards);
      cards.set(action.id, { ...card, state: action.state });
      return { ...state, cards };
    }
    case 'SET_CAPABILITY': {
      const obj = state.objects.get(action.objectId);
      if (!obj) return state;
      const objects = new Map(state.objects);
      const flags = action.enabled
        ? obj.header.flags | (1 << action.flagId)
        : obj.header.flags & ~(1 << action.flagId);
      objects.set(action.objectId, {
        ...obj,
        header: { ...obj.header, flags },
        updatedAt: Date.now(),
      });
      return { ...state, objects };
    }
    case 'TRANSITION_LINEARITY': {
      const obj = state.objects.get(action.objectId);
      if (!obj) return state;
      const objects = new Map(state.objects);
      objects.set(action.objectId, {
        ...obj,
        header: { ...obj.header, linearity: action.newLinearity },
        updatedAt: Date.now(),
      });
      return { ...state, objects };
    }
    case 'ADD_PATCH': {
      const obj = state.objects.get(action.objectId);
      if (!obj) return state;
      const objects = new Map(state.objects);
      objects.set(action.objectId, {
        ...obj,
        patches: [...obj.patches, action.patch],
        updatedAt: Date.now(),
      });
      return { ...state, objects };
    }
    case 'FILTER_BY_CATEGORY': {
      return { ...state, categoryFilter: action.path };
    }
    case 'UPDATE_PAYLOAD': {
      const obj = state.objects.get(action.objectId);
      if (!obj) return state;
      const objects = new Map(state.objects);
      objects.set(action.objectId, {
        ...obj,
        payload: { ...obj.payload, [action.field]: action.value },
        updatedAt: Date.now(),
      });
      return { ...state, objects };
    }
    case 'TRANSITION_VISIBILITY': {
      const obj = state.objects.get(action.objectId);
      if (!obj) return state;
      const objects = new Map(state.objects);
      objects.set(action.objectId, {
        ...obj,
        visibility: action.newVisibility,
        updatedAt: Date.now(),
      });
      return { ...state, objects };
    }
    default:
      return state;
  }
}

```
