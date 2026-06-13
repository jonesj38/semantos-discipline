---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/sidebar/CapabilityToggles.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.956021+00:00
---

# archive/apps-loom-react/src/sidebar/CapabilityToggles.tsx

```tsx
import { useExtension } from '../config/ExtensionProvider';
import { useLoom } from '../state/LoomProvider';

export function CapabilityToggles() {
  const { config } = useExtension();
  const { selectedObject, dispatch } = useLoom();

  if (!config || !selectedObject) return null;

  return (
    <div className="px-2 py-2 border-t border-gray-800">
      <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1 px-1">Capabilities</div>
      {config.capabilities.map(cap => {
        const isEnabled = (selectedObject.header.flags & (1 << cap.id)) !== 0;
        return (
          <label
            key={cap.id}
            className="flex items-center gap-2 px-2 py-1 rounded hover:bg-gray-800 cursor-pointer text-xs"
          >
            <input
              type="checkbox"
              checked={isEnabled}
              onChange={() => {
                dispatch({
                  type: 'SET_CAPABILITY',
                  objectId: selectedObject.id,
                  flagId: cap.id,
                  enabled: !isEnabled,
                });
              }}
              className="rounded border-gray-600"
            />
            <span className="text-gray-300">{cap.name}</span>
            <span className="text-gray-600 text-[10px]">({cap.id})</span>
          </label>
        );
      })}
    </div>
  );
}

```
