---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/shell/Inspector.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.968374+00:00
---

# archive/apps-loom-react/src/shell/Inspector.tsx

```tsx
import type { ReactNode } from 'react';

interface InspectorProps {
  width: number;
  collapsed: boolean;
  onToggle: () => void;
  children?: ReactNode;
}

export function Inspector({ width, collapsed, onToggle, children }: InspectorProps) {
  if (collapsed) {
    return (
      <div className="flex-shrink-0 w-8 bg-gray-900 border-l border-gray-800 flex flex-col items-center pt-2">
        <button
          onClick={onToggle}
          className="text-gray-400 hover:text-white text-xs p-1"
          title="Expand inspector"
        >
          &#9664;
        </button>
      </div>
    );
  }

  return (
    <div
      className="flex-shrink-0 bg-gray-900 border-l border-gray-800 flex flex-col overflow-hidden"
      style={{ width }}
    >
      <div className="flex items-center justify-between px-3 py-2 border-b border-gray-800">
        <span className="text-xs font-semibold text-gray-400 uppercase tracking-wider">Inspector</span>
        <button
          onClick={onToggle}
          className="text-gray-500 hover:text-white text-xs"
          title="Collapse inspector"
        >
          &#9654;
        </button>
      </div>
      <div className="flex-1 overflow-y-auto">
        {children ?? (
          <div className="p-3 text-sm text-gray-500">Select an object to inspect</div>
        )}
      </div>
    </div>
  );
}

```
