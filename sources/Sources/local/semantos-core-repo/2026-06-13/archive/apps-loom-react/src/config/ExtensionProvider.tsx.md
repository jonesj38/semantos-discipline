---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/config/ExtensionProvider.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.935696+00:00
---

# archive/apps-loom-react/src/config/ExtensionProvider.tsx

```tsx
/**
 * ExtensionProvider — thin React wrapper over ConfigStore.
 * All config loading and merging logic lives in ConfigStore (services/).
 */

import { createContext, useContext, useCallback, useEffect, useSyncExternalStore, type ReactNode } from 'react';
import type { ExtensionConfig } from './extensionConfig';
import { configStore } from '../services/index';

interface ExtensionContextValue {
  config: ExtensionConfig | null;
  loading: boolean;
  error: string | null;
  switchExtension: (id: string) => void;
  activeExtensionId: string;
}

const ExtensionContext = createContext<ExtensionContextValue | null>(null);

export function ExtensionProvider({ children }: { children: ReactNode }) {
  const snapshot = useSyncExternalStore(
    configStore.stableSubscribe,
    configStore.getSnapshot,
  );

  // Initialize on mount
  useEffect(() => {
    configStore.initialize();
  }, []);

  const switchExtension = useCallback((id: string) => {
    configStore.switchExtension(id);
  }, []);

  return (
    <ExtensionContext.Provider value={{
      config: snapshot.config,
      loading: snapshot.loading,
      error: snapshot.error,
      switchExtension,
      activeExtensionId: snapshot.activeExtensionId,
    }}>
      {children}
    </ExtensionContext.Provider>
  );
}

export function useExtension(): ExtensionContextValue {
  const ctx = useContext(ExtensionContext);
  if (!ctx) throw new Error('useExtension must be used within ExtensionProvider');
  return ctx;
}

```
