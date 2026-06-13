---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/HatSwitcher.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.966375+00:00
---

# archive/apps-loom-react/src/helm/HatSwitcher.tsx

```tsx
/**
 * HatSwitcher — dropdown in the top bar to switch active hat.
 *
 * Shows current hat name, clicking opens a dropdown of all hats.
 * Switching hats changes the identity context for all operations.
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import { useIdentity } from '../identity/IdentityProvider';

export function HatSwitcher() {
  const { identity, activeHat, switchHat } = useIdentity();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  const handleSwitch = useCallback((hatId: string) => {
    switchHat(hatId);
    setOpen(false);
  }, [switchHat]);

  if (!identity || identity.hats.length <= 1) {
    // Single hat — just show the name, no dropdown
    return (
      <span className="text-[11px] text-gray-500 font-mono truncate max-w-[120px]">
        {activeHat?.name ?? 'Anonymous'}
      </span>
    );
  }

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-1 text-[11px] text-gray-400 hover:text-gray-200 font-mono transition-colors px-1.5 py-0.5 rounded hover:bg-gray-800"
      >
        <span className="w-1.5 h-1.5 rounded-full bg-green-500 shrink-0" />
        <span className="truncate max-w-[100px]">{activeHat?.name ?? 'Anonymous'}</span>
        <span className="text-gray-600 text-[9px]">&#9662;</span>
      </button>

      {open && (
        <div className="absolute top-full right-0 mt-1 bg-gray-800 border border-gray-700 rounded shadow-lg z-50 min-w-[180px]">
          <div className="px-3 py-1.5 border-b border-gray-700">
            <p className="text-[10px] text-gray-500">{identity.name}</p>
          </div>
          {identity.hats.map(f => (
            <button
              key={f.id}
              onClick={() => handleSwitch(f.id)}
              className={`w-full text-left px-3 py-1.5 text-xs transition-colors flex items-center gap-2 ${
                f.id === activeHat?.id
                  ? 'text-blue-400 bg-blue-950/30'
                  : 'text-gray-300 hover:bg-gray-700'
              }`}
            >
              <span className={`w-1.5 h-1.5 rounded-full shrink-0 ${
                f.id === activeHat?.id ? 'bg-green-500' : 'bg-gray-600'
              }`} />
              <span className="truncate">{f.name}</span>
              {f.capabilities && (
                <span className="text-[9px] text-gray-600 ml-auto">
                  {f.capabilities.length} caps
                </span>
              )}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

```
