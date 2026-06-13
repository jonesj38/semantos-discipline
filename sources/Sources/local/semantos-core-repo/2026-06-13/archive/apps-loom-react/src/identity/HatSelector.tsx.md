---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/identity/HatSelector.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.948070+00:00
---

# archive/apps-loom-react/src/identity/HatSelector.tsx

```tsx
import { useIdentity } from './IdentityProvider';

export function HatSelector() {
  const { identity, activeHat, switchHat } = useIdentity();

  if (!identity || identity.hats.length === 0) return null;

  return (
    <select
      value={identity.activeHatId}
      onChange={e => switchHat(e.target.value)}
      className="bg-transparent text-gray-400 text-xs border-none outline-none cursor-pointer hover:text-gray-200"
      title={activeHat ? `${activeHat.displayName} (${activeHat.capabilities.length} capabilities)` : ''}
    >
      {identity.hats.map(hat => (
        <option key={hat.id} value={hat.id} className="bg-gray-900">
          {hat.name} ({hat.capabilities.length})
        </option>
      ))}
    </select>
  );
}

```
