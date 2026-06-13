---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/SwarmDashboardProvider.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.960867+00:00
---

# archive/apps-loom-react/src/swarm/SwarmDashboardProvider.tsx

```tsx
/**
 * SwarmDashboardProvider — thin React wrapper over SwarmDashboardStore.
 * Follows the same pattern as LoomProvider.
 */

import { createContext, useContext, useEffect, useSyncExternalStore, type ReactNode } from 'react';
import type { SwarmDashboardState } from './types';
import { swarmDashboardStore } from './index';

interface SwarmDashboardContextValue {
  state: SwarmDashboardState;
  connect: (url?: string) => void;
  disconnect: () => void;
  selectNode: (id: string | null) => void;
}

const SwarmDashboardContext = createContext<SwarmDashboardContextValue | null>(null);

export function SwarmDashboardProvider({ children }: { children: ReactNode }) {
  const state = useSyncExternalStore(
    swarmDashboardStore.stableSubscribe,
    swarmDashboardStore.getSnapshot,
  );

  useEffect(() => {
    swarmDashboardStore.connect();
    return () => swarmDashboardStore.disconnect();
  }, []);

  return (
    <SwarmDashboardContext.Provider
      value={{
        state,
        connect: (url) => swarmDashboardStore.connect(url),
        disconnect: () => swarmDashboardStore.disconnect(),
        selectNode: (id) => swarmDashboardStore.selectNode(id),
      }}
    >
      {children}
    </SwarmDashboardContext.Provider>
  );
}

export function useSwarmDashboard(): SwarmDashboardContextValue {
  const ctx = useContext(SwarmDashboardContext);
  if (!ctx) throw new Error('useSwarmDashboard must be used within SwarmDashboardProvider');
  return ctx;
}

```
