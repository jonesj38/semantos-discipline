---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/contexts/KernelProvider.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.954296+00:00
---

# archive/apps-loom-react/src/contexts/KernelProvider.tsx

```tsx
import { createContext, useContext, useState, useEffect, useRef, type ReactNode } from 'react';
import { initKernel, type SemantosKernel } from './kernel-bridge';

interface KernelContextValue {
  kernel: SemantosKernel | null;
  isBooting: boolean;
  error: string | null;
}

const KernelContext = createContext<KernelContextValue>({
  kernel: null,
  isBooting: true,
  error: null,
});

export function KernelProvider({ children }: { children: ReactNode }) {
  const [kernel, setKernel] = useState<SemantosKernel | null>(null);
  const [isBooting, setIsBooting] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const initRef = useRef(false);

  useEffect(() => {
    if (initRef.current) return;
    initRef.current = true;

    try {
      const k = initKernel();
      setKernel(k);
      setIsBooting(false);
    } catch (err: any) {
      console.error('[KernelProvider] Boot failed:', err);
      setError(err.message || 'Kernel boot failed');
      setIsBooting(false);
    }
  }, []);

  return (
    <KernelContext.Provider value={{ kernel, isBooting, error }}>
      {children}
    </KernelContext.Provider>
  );
}

export function useKernel() {
  return useContext(KernelContext);
}

```
