---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/engine/EngineProvider.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.936290+00:00
---

# archive/apps-loom-react/src/engine/EngineProvider.tsx

```tsx
import { createContext, useContext, type ReactNode } from 'react';
import { useEngine } from './useEngine';
import type { CellEngine } from '@semantos/cell-engine/browser';

interface EngineContextValue {
  engine: CellEngine | null;
  isReady: boolean;
  profile: 'full' | 'embedded';
  error: string | null;
}

const EngineContext = createContext<EngineContextValue | null>(null);

export function EngineProvider({ children }: { children: ReactNode }) {
  const value = useEngine();
  return (
    <EngineContext.Provider value={value}>
      {children}
    </EngineContext.Provider>
  );
}

export function useEngineContext(): EngineContextValue {
  const ctx = useContext(EngineContext);
  if (!ctx) throw new Error('useEngineContext must be used within EngineProvider');
  return ctx;
}

```
