---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/shell/MainCanvas.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.968904+00:00
---

# archive/apps-loom-react/src/shell/MainCanvas.tsx

```tsx
import type { ReactNode } from 'react';

interface MainCanvasProps {
  children?: ReactNode;
}

export function MainCanvas({ children }: MainCanvasProps) {
  return (
    <div className="flex-1 bg-gray-950 flex flex-col overflow-hidden relative min-w-0">
      <div className="flex-1 overflow-hidden relative flex flex-col">
        {children ?? (
          <div className="flex items-center justify-center h-full text-gray-600">
            <div className="text-center">
              <p className="text-lg">Semantic Object Loom</p>
              <p className="text-sm mt-1">Create objects from the sidebar to get started</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

```
