---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/identity/HatManager.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.946975+00:00
---

# archive/apps-loom-react/src/identity/HatManager.tsx

```tsx
import { useState } from 'react';
import { useIdentity } from './IdentityProvider';
import { useExtension } from '../config/ExtensionProvider';

const CAPABILITY_LABELS: Record<number, string> = {
  1: 'EDGE', 2: 'SIGN', 3: 'ENCRYPT', 4: 'MSG',
  5: 'ATTEST', 6: 'CHILD', 7: 'PERM', 8: 'DATA',
  9: 'SCHEMA', 10: 'METER',
};

export function HatManager() {
  const { identity, addHat, switchHat } = useIdentity();
  const { config } = useExtension();
  const [isAdding, setIsAdding] = useState(false);
  const [name, setName] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [selectedCaps, setSelectedCaps] = useState<number[]>([]);

  if (!identity) return null;

  const capabilities = config?.capabilities ?? [];

  const handleAdd = () => {
    if (!name.trim()) return;
    addHat(
      name.trim(),
      displayName.trim() || name.trim(),
      selectedCaps,
      `m/brc52/${name.trim().toLowerCase().replace(/\s+/g, '-')}/0`,
    );
    setName('');
    setDisplayName('');
    setSelectedCaps([]);
    setIsAdding(false);
  };

  const toggleCap = (capId: number) => {
    setSelectedCaps(prev =>
      prev.includes(capId)
        ? prev.filter(c => c !== capId)
        : [...prev, capId]
    );
  };

  return (
    <div className="border-t border-gray-800 px-2 py-2">
      <div className="flex items-center justify-between mb-1">
        <span className="text-xs font-medium text-gray-400">Hats</span>
        <button
          onClick={() => setIsAdding(!isAdding)}
          className="text-xs text-blue-400 hover:text-blue-300"
        >
          {isAdding ? 'Cancel' : '+ Add'}
        </button>
      </div>

      {identity.hats.map(hat => (
        <button
          key={hat.id}
          onClick={() => switchHat(hat.id)}
          className={`w-full text-left px-2 py-1 rounded text-xs flex items-center gap-2 ${
            hat.id === identity.activeHatId
              ? 'bg-blue-900/30 text-blue-300'
              : 'text-gray-400 hover:bg-gray-800'
          }`}
        >
          <span className="truncate flex-1">{hat.name}</span>
          <span className="text-gray-600 flex-shrink-0">
            {hat.capabilities.length} caps
          </span>
        </button>
      ))}

      {isAdding && (
        <div className="mt-2 space-y-2 bg-gray-800/50 rounded p-2">
          <input
            type="text"
            value={name}
            onChange={e => setName(e.target.value)}
            placeholder="Hat name"
            className="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-xs text-gray-100 focus:outline-none focus:border-blue-500"
            autoFocus
          />
          <input
            type="text"
            value={displayName}
            onChange={e => setDisplayName(e.target.value)}
            placeholder="Display name (optional)"
            className="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-xs text-gray-100 focus:outline-none focus:border-blue-500"
          />
          <div className="flex flex-wrap gap-1">
            {capabilities.map(cap => (
              <button
                key={cap.id}
                onClick={() => toggleCap(cap.id)}
                title={cap.description}
                className={`text-[10px] px-1.5 py-0.5 rounded ${
                  selectedCaps.includes(cap.id)
                    ? 'bg-blue-700 text-blue-100'
                    : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
                }`}
              >
                {CAPABILITY_LABELS[cap.id] ?? cap.name}
              </button>
            ))}
          </div>
          <button
            onClick={handleAdd}
            disabled={!name.trim()}
            className="w-full bg-blue-600 hover:bg-blue-500 disabled:bg-gray-700 disabled:text-gray-500 text-white text-xs rounded px-2 py-1 transition-colors"
          >
            Create Hat
          </button>
        </div>
      )}
    </div>
  );
}

```
