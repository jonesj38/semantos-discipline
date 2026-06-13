---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/shell/ResizeHandle.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.969185+00:00
---

# archive/apps-loom-react/src/shell/ResizeHandle.tsx

```tsx
import { useCallback, useRef } from 'react';

interface ResizeHandleProps {
  onResize: (delta: number) => void;
  direction: 'left' | 'right';
}

export function ResizeHandle({ onResize, direction }: ResizeHandleProps) {
  const dragging = useRef(false);
  const lastX = useRef(0);

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    dragging.current = true;
    lastX.current = e.clientX;

    const onMouseMove = (ev: MouseEvent) => {
      if (!dragging.current) return;
      const delta = ev.clientX - lastX.current;
      lastX.current = ev.clientX;
      onResize(direction === 'left' ? delta : -delta);
    };

    const onMouseUp = () => {
      dragging.current = false;
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    };

    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
  }, [onResize, direction]);

  return (
    <div
      className="w-1 cursor-col-resize bg-gray-800 hover:bg-blue-500 transition-colors flex-shrink-0"
      onMouseDown={onMouseDown}
    />
  );
}

```
