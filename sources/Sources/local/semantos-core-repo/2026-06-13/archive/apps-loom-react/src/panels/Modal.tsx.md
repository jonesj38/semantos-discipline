---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/panels/Modal.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.951331+00:00
---

# archive/apps-loom-react/src/panels/Modal.tsx

```tsx
/**
 * Modal — generic overlay wrapper for panels and wizards.
 *
 * Renders a fixed overlay with backdrop, close on Escape, scrollable content.
 * Follows existing loom dark theme (bg-gray-900, border-gray-800).
 */

import { useEffect, useCallback, type ReactNode } from 'react';

interface ModalProps {
  open: boolean;
  onClose: () => void;
  title: string;
  width?: string;
  children: ReactNode;
}

export function Modal({ open, onClose, title, width = '640px', children }: ModalProps) {
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    },
    [onClose],
  );

  useEffect(() => {
    if (!open) return;
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [open, handleKeyDown]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className="bg-gray-900 border border-gray-700 rounded-lg shadow-2xl flex flex-col max-h-[90vh]"
        style={{ width, maxWidth: '95vw' }}
      >
        <div className="flex items-center justify-between px-4 py-3 border-b border-gray-800">
          <span className="text-sm font-semibold text-gray-200">{title}</span>
          <button
            onClick={onClose}
            className="text-gray-500 hover:text-white text-lg leading-none px-1"
            title="Close"
          >
            &times;
          </button>
        </div>
        <div className="flex-1 overflow-y-auto p-4">{children}</div>
      </div>
    </div>
  );
}

```
