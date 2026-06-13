---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/state/LoomProvider.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.956888+00:00
---

# archive/apps-loom-react/src/state/LoomProvider.tsx

```tsx
/**
 * LoomProvider — thin React wrapper over LoomStore.
 * All business logic lives in LoomStore (services/).
 */

import { createContext, useContext, useCallback, useSyncExternalStore, type ReactNode } from 'react';
import type { LoomState, LoomAction } from './loomReducer';
import type { ObjectTypeDefinition } from '../config/extensionConfig';
import type { LoomObject } from '../types/loom';
import { useIdentity } from '../identity/IdentityProvider';
import { loomStore } from '../services/index';

/** Convert first 32 hex chars (16 bytes) of a hex string to Uint8Array(16). */
function hexToBytes16(hex: string): Uint8Array {
  const bytes = new Uint8Array(16);
  const clean = hex.slice(0, 32);
  for (let i = 0; i < 16 && i * 2 < clean.length; i++) {
    bytes[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

interface LoomContextValue {
  state: LoomState;
  dispatch: (action: LoomAction) => void;
  createObjectFromType: (typeDef: ObjectTypeDefinition) => string;
  openAsCard: (objectId: string) => void;
  selectedObject: LoomObject | null;
}

const LoomContext = createContext<LoomContextValue | null>(null);

export function LoomProvider({ children }: { children: ReactNode }) {
  const state = useSyncExternalStore(
    loomStore.stableSubscribe,
    loomStore.getSnapshot,
  );
  const { activeHat } = useIdentity();

  const dispatch = useCallback((action: LoomAction) => {
    loomStore.dispatch(action);
  }, []);

  const createObjectFromType = useCallback((typeDef: ObjectTypeDefinition): string => {
    let ownerIdBytes: Uint8Array | undefined;
    if (activeHat?.certId) {
      // Use Plexus-derived certId hex as ownerIdBytes (first 16 bytes)
      const hex = activeHat.certId.replace(/^cert:/, '');
      ownerIdBytes = hexToBytes16(hex);
    } else if (activeHat) {
      // Fallback for pre-plexus facets
      ownerIdBytes = new TextEncoder().encode(activeHat.id.slice(0, 16).padEnd(16, '\0'));
    }
    return loomStore.createObjectFromType(
      typeDef,
      ownerIdBytes,
      activeHat?.id,
      activeHat?.capabilities,
    );
  }, [activeHat]);

  const openAsCard = useCallback((objectId: string) => {
    loomStore.openAsCard(objectId);
  }, []);

  const selectedObject = loomStore.getSelectedObject();

  return (
    <LoomContext.Provider value={{ state, dispatch, createObjectFromType, openAsCard, selectedObject }}>
      {children}
    </LoomContext.Provider>
  );
}

export function useLoom(): LoomContextValue {
  const ctx = useContext(LoomContext);
  if (!ctx) throw new Error('useLoom must be used within LoomProvider');
  return ctx;
}

```
