---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/engine/useEngine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.936563+00:00
---

# archive/apps-loom-react/src/engine/useEngine.ts

```ts
import { useState, useEffect, useRef } from 'react';
import type { CellEngine } from '@semantos/cell-engine/browser';

type Profile = 'full' | 'embedded';

interface UseEngineResult {
  engine: CellEngine | null;
  isReady: boolean;
  profile: Profile;
  error: string | null;
}

/**
 * React hook: loads the CellEngine WASM binary and returns a typed engine instance.
 * Uses the browser loader from @semantos/cell-engine/browser.
 */
export function useEngine(): UseEngineResult {
  const [engine, setEngine] = useState<CellEngine | null>(null);
  const [isReady, setIsReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const loadingRef = useRef(false);

  // Determine profile from URL param or default to embedded
  const params = new URLSearchParams(window.location.search);
  const profile: Profile = params.get('profile') === 'full' ? 'full' : 'embedded';

  useEffect(() => {
    if (loadingRef.current) return;
    loadingRef.current = true;

    async function load() {
      try {
        // Dynamic import to avoid bundling issues with WASM loader
        const { loadCellEngine } = await import('@semantos/cell-engine/browser');
        const wasmUrl = profile === 'full'
          ? '/wasm/cell-engine.wasm'
          : '/wasm/cell-engine-embedded.wasm';
        const eng = await loadCellEngine({ wasmUrl, profile });
        setEngine(eng);
        setIsReady(true);
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error('CellEngine load failed:', msg);
        setError(msg);
      }
    }

    load();
  }, [profile]);

  return { engine, isReady, profile, error };
}

```
