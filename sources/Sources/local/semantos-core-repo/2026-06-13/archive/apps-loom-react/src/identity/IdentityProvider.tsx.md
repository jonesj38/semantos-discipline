---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/identity/IdentityProvider.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.947527+00:00
---

# archive/apps-loom-react/src/identity/IdentityProvider.tsx

```tsx
/**
 * IdentityProvider — thin React wrapper over IdentityStore.
 * All business logic lives in IdentityStore (services/).
 */

import { createContext, useContext, useCallback, useSyncExternalStore, type ReactNode } from 'react';
import type { Identity, Hat, IdentityPolicy } from '../types/loom';
import { identityStore } from '../services/index';

interface IdentityContextValue {
  identity: Identity | null;
  activeHat: Hat | null;
  isSetupComplete: boolean;
  createIdentity: (name: string) => void;
  addHat: (name: string, displayName: string, capabilities: number[], derivationPath: string) => void;
  switchHat: (facetId: string) => void;
  addPolicy: (policy: Omit<IdentityPolicy, 'object'>) => void;
  togglePolicy: (policyId: string) => void;
}

const IdentityContext = createContext<IdentityContextValue | null>(null);

export function IdentityProvider({ children }: { children: ReactNode }) {
  // Subscribe to store changes — re-renders when identity changes
  useSyncExternalStore(
    identityStore.stableSubscribe,
    identityStore.getSnapshot,
  );

  const identity = identityStore.getIdentity();
  const activeFacet = identityStore.getActiveHat();
  const isSetupComplete = identityStore.isSetupComplete();

  const createIdentity = useCallback((name: string) => {
    identityStore.createIdentity(name);
  }, []);

  const addFacet = useCallback((name: string, displayName: string, capabilities: number[], derivationPath: string) => {
    identityStore.addHat(name, displayName, capabilities, derivationPath);
  }, []);

  const switchFacet = useCallback((facetId: string) => {
    identityStore.switchHat(facetId);
  }, []);

  const addPolicy = useCallback((policy: Omit<IdentityPolicy, 'object'>) => {
    identityStore.addPolicy(policy);
  }, []);

  const togglePolicy = useCallback((policyId: string) => {
    identityStore.togglePolicy(policyId);
  }, []);

  return (
    <IdentityContext.Provider value={{
      identity,
      activeHat,
      isSetupComplete,
      createIdentity,
      addHat,
      switchHat,
      addPolicy,
      togglePolicy,
    }}>
      {children}
    </IdentityContext.Provider>
  );
}

export function useIdentity(): IdentityContextValue {
  const ctx = useContext(IdentityContext);
  if (!ctx) throw new Error('useIdentity must be used within IdentityProvider');
  return ctx;
}

```
