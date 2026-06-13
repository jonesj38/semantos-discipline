---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/SlotLauncher.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.966938+00:00
---

# archive/apps-loom-react/src/helm/SlotLauncher.tsx

```tsx
/**
 * SlotLauncher — 1-3-5 context shortlist panel.
 *
 * Renders the promoted objects + types for a given intent slot, with a
 * search input that narrows the list. Appears above the dock tier-2
 * when a context is selected. Selecting an item dispatches it.
 */

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  intentLauncher,
  loomStore,
  paskGraph,
  SLOT_LABEL,
  SLOT_MODE,
} from '../services/index';
import type { IntentContext, LauncherItem } from '../services/index';
import { useShellDispatch } from '../hooks/useShellDispatch';
import type { ShellDispatchResult } from '../hooks/useShellDispatch';

export interface SlotLauncherProps {
  slot: IntentContext;
  onInvoke: (command: string, result: ShellDispatchResult) => void;
  onClose: () => void;
}

export function SlotLauncher({ slot, onInvoke, onClose }: SlotLauncherProps) {
  const [query, setQuery] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);
  const dispatch = useShellDispatch();
  const mode = SLOT_MODE[slot];
  const label = SLOT_LABEL[slot];

  const result = useMemo(
    () => intentLauncher.resolve(slot, { loomStore, paskGraph }),
    [slot],
  );

  const items = useMemo(
    () => (query.trim() ? result.search(query) : result.promoted),
    [query, result],
  );

  useEffect(() => {
    inputRef.current?.focus();
  }, [slot]);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose]);

  const handleSelect = useCallback(
    async (item: LauncherItem) => {
      if (item.kind === 'type') {
        const command = `new ${item.id}`;
        const r = await dispatch(command);
        onInvoke(command, r);
      } else {
        // Select the object in the attention surface
        loomStore.dispatch({ type: 'SELECT_OBJECT', id: item.id });
        onClose();
      }
    },
    [dispatch, onInvoke, onClose],
  );

  const modeColour = mode === 'do'
    ? 'text-amber-400 border-amber-800'
    : mode === 'talk'
    ? 'text-blue-400 border-blue-800'
    : 'text-violet-400 border-violet-800';

  return (
    <div className="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-72 overflow-hidden">
      {/* Header */}
      <div className={`flex items-center gap-2 px-4 py-2.5 border-b ${modeColour}`}>
        <span className="text-xs font-semibold uppercase tracking-widest opacity-60">
          {mode}
        </span>
        <span className="text-sm font-semibold">{label}</span>
      </div>

      {/* Search input */}
      <div className="px-3 pt-3">
        <input
          ref={inputRef}
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search or type a command…"
          className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-sm text-gray-100 placeholder-gray-500 outline-none focus:border-gray-500 transition-colors"
        />
      </div>

      {/* Items */}
      <ul className="px-2 py-2 space-y-0.5 max-h-64 overflow-auto">
        {items.length === 0 && (
          <li className="px-3 py-2 text-xs text-gray-500 text-center">
            No results for &ldquo;{query}&rdquo;
          </li>
        )}
        {items.map((item) => (
          <LauncherRow key={`${item.kind}:${item.id}`} item={item} onSelect={handleSelect} />
        ))}
      </ul>

      {/* Footer hint */}
      <div className="px-4 py-1.5 border-t border-gray-800 text-[10px] text-gray-600">
        ↵ select · Esc close · ↑↓ navigate
      </div>
    </div>
  );
}

// ── Row ────────────────────────���───────────────────────────────────────────

interface LauncherRowProps {
  item: LauncherItem;
  onSelect: (item: LauncherItem) => void;
}

function LauncherRow({ item, onSelect }: LauncherRowProps) {
  const icon = item.kind === 'type' ? '⊕' : '▣';
  const dimScore = item.score < 0.01;

  return (
    <li>
      <button
        type="button"
        onClick={() => onSelect(item)}
        className="w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-left text-sm hover:bg-gray-800 transition-colors group"
      >
        <span className={`text-base shrink-0 ${item.kind === 'type' ? 'text-teal-500' : 'text-gray-400'}`}>
          {icon}
        </span>
        <span className={`flex-1 truncate ${dimScore ? 'text-gray-500' : 'text-gray-200'}`}>
          {item.label}
        </span>
        {item.kind === 'type' && (
          <span className="text-[10px] text-gray-600 shrink-0 group-hover:text-teal-500 transition-colors">
            new →
          </span>
        )}
        {item.score > 0 && (
          <span className="text-[9px] text-gray-700 shrink-0 tabular-nums">
            {(item.score * 100).toFixed(0)}
          </span>
        )}
      </button>
    </li>
  );
}

```
