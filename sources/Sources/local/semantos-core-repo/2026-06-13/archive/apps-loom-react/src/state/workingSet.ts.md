---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/state/workingSet.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.957180+00:00
---

# archive/apps-loom-react/src/state/workingSet.ts

```ts
/**
 * Working-set store — the personal "what's in flight for me" layer.
 *
 * Combines two streams per docs/BRAINSTORM-DOCK-SHELL-SILOS.md §7:
 *   - auto-surfaced items (AttentionEngine output — lives elsewhere)
 *   - pinned items (user-explicit, persistent across sessions)
 *
 * v1 only implements the pinned side; the auto side is still served by the
 * existing `useAttention` hook on the AttentionEngine. Later we'll unify them
 * behind a single accessor with an auto/pinned splitter.
 *
 * Persistence: localStorage, keyed by `semantos.workingSet.pinned.v1`.
 */

import { useCallback, useEffect, useState } from 'react';

const STORAGE_KEY = 'semantos.workingSet.pinned.v1';

export interface PinnedItem {
  /** Object ID if this pin refers to a LoomStore object; otherwise synthetic. */
  objectId?: string;
  /** Human label shown on the canvas. */
  label: string;
  /** Optional icon. */
  icon?: string;
  /** Source command that produced the item (audit / re-run). */
  command?: string;
  /** Unix ms when pinned. */
  pinnedAt: number;
}

function readStorage(): PinnedItem[] {
  if (typeof window === 'undefined') return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeStorage(items: PinnedItem[]): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
  } catch {
    /* quota / private mode — ignore */
  }
}

export function useWorkingSet() {
  const [pinned, setPinned] = useState<PinnedItem[]>(() => readStorage());

  // Sync across tabs.
  useEffect(() => {
    const handler = (e: StorageEvent) => {
      if (e.key === STORAGE_KEY) setPinned(readStorage());
    };
    window.addEventListener('storage', handler);
    return () => window.removeEventListener('storage', handler);
  }, []);

  const pin = useCallback((item: Omit<PinnedItem, 'pinnedAt'>) => {
    setPinned(prev => {
      // De-dupe by objectId if present; otherwise by label.
      const key = item.objectId ?? item.label;
      const filtered = prev.filter(p => (p.objectId ?? p.label) !== key);
      const next = [{ ...item, pinnedAt: Date.now() }, ...filtered];
      writeStorage(next);
      return next;
    });
  }, []);

  const unpin = useCallback((key: string) => {
    setPinned(prev => {
      const next = prev.filter(p => (p.objectId ?? p.label) !== key);
      writeStorage(next);
      return next;
    });
  }, []);

  const clear = useCallback(() => {
    setPinned([]);
    writeStorage([]);
  }, []);

  return { pinned, pin, unpin, clear };
}

```
