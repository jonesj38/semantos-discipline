---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/dock/DetailPane.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.974176+00:00
---

# archive/apps-loom-react/src/helm/dock/DetailPane.tsx

```tsx
/**
 * DetailPane — overlay shown on the attention surface after a dock invocation.
 *
 * v1 responsibility: show the shell command that ran + the result (success or
 * error) in a readable card. Later passes will replace this with typed
 * per-object views (Document editor, Event form, etc.) based on what `result`
 * refers to.
 */

import React from 'react';
import type { ShellDispatchResult } from '../../hooks/useShellDispatch';

export interface DetailPaneProps {
  command: string;
  result: ShellDispatchResult;
  onClose: () => void;
  onPin?: () => void;
}

export function DetailPane({ command, result, onClose, onPin }: DetailPaneProps) {
  const body = (() => {
    if (!result.ok) {
      return (
        <div className="text-sm text-red-300">
          <div className="font-medium mb-1">Shell error</div>
          <div className="font-mono text-xs whitespace-pre-wrap">
            {result.error ?? 'unknown error'}
          </div>
        </div>
      );
    }
    return (
      <pre className="text-xs font-mono text-gray-300 whitespace-pre-wrap max-h-[50vh] overflow-auto">
        {JSON.stringify(result.data, null, 2)}
      </pre>
    );
  })();

  return (
    <div
      className="absolute inset-0 z-10 flex items-start justify-center pt-12 px-4 pb-4 pointer-events-none"
      onClick={onClose}
    >
      <div
        className="pointer-events-auto w-full max-w-2xl bg-gray-900/98 border border-gray-700 rounded-lg shadow-2xl p-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-4 mb-3 pb-3 border-b border-gray-800">
          <div className="min-w-0">
            <div className="text-[10px] text-gray-500 uppercase tracking-wide mb-0.5">
              {result.ok ? 'Result' : 'Error'}
            </div>
            <div className="font-mono text-sm text-gray-200 truncate">{command}</div>
          </div>
          <div className="flex items-center gap-1 shrink-0">
            {onPin && result.ok && (
              <button
                onClick={onPin}
                className="text-xs px-2 py-1 rounded bg-gray-800 hover:bg-gray-700 text-gray-300"
                title="Pin to attention surface"
              >
                {'\u2691'} Pin
              </button>
            )}
            <button
              onClick={onClose}
              className="text-gray-500 hover:text-gray-200 px-2"
              aria-label="Close detail pane"
            >
              {'\u2715'}
            </button>
          </div>
        </div>
        {body}
      </div>
    </div>
  );
}

```
