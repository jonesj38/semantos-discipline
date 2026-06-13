---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/shell/Sidebar.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.968093+00:00
---

# archive/apps-loom-react/src/shell/Sidebar.tsx

```tsx
import type { ReactNode } from 'react';

interface SidebarProps {
  width: number;
  collapsed: boolean;
  onToggle: () => void;
  children?: ReactNode;
}

export function Sidebar({ width, collapsed, onToggle, children }: SidebarProps) {
  if (collapsed) {
    return (
      <div className="flex-shrink-0 w-8 bg-gray-900 border-r border-gray-800 flex flex-col items-center pt-2">
        <button
          onClick={onToggle}
          className="text-gray-400 hover:text-white text-xs p-1"
          title="Expand sidebar"
        >
          &#9654;
        </button>
      </div>
    );
  }

  return (
    <div
      className="flex-shrink-0 bg-gray-900 border-r border-gray-800 flex flex-col overflow-hidden"
      style={{ width }}
    >
      <div className="flex items-center justify-between px-3 py-2 border-b border-gray-800">
        <span className="text-xs font-semibold text-gray-400 uppercase tracking-wider">Objects</span>
        <button
          onClick={onToggle}
          className="text-gray-500 hover:text-white text-xs"
          title="Collapse sidebar"
        >
          &#9664;
        </button>
      </div>
      <div className="flex-1 overflow-y-auto">
        {children}
      </div>
    </div>
  );
}

```
