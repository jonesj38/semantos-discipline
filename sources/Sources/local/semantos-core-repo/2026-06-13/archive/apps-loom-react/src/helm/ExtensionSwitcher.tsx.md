---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/ExtensionSwitcher.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.966108+00:00
---

# archive/apps-loom-react/src/helm/ExtensionSwitcher.tsx

```tsx
/**
 * ExtensionSwitcher — "what am I doing?" (workspace selector).
 *
 * Distinct from the HatSwitcher (which is "who am I being?") per
 * docs/EXTENSIONS-VS-TYPES.md §Two Switchers. An extension re-weights which
 * types populate tier-3 popovers — it does NOT change the 15-context grammar.
 *
 * v1 stub: only shows "core" as active. Real manifest loading + multi-select
 * + tier-3 weight composition arrive in a follow-up pass.
 */

import React, { useState } from 'react';

interface ExtensionOption {
  id: string;
  label: string;
  description: string;
}

const EXTENSIONS: ExtensionOption[] = [
  { id: 'core', label: 'core', description: 'Kernel types only' },
  // Future entries will come from manifest scan.
];

export function ExtensionSwitcher() {
  const [open, setOpen] = useState(false);
  const active = EXTENSIONS[0];

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="text-xs text-gray-400 hover:text-gray-200 bg-gray-800 hover:bg-gray-700 px-2 py-1 rounded flex items-center gap-1"
        title="Workspace (extension)"
        aria-label="Extension switcher"
      >
        <span className="text-gray-500">{'\u25A1'}</span>
        <span>{active.label}</span>
        <span className="text-gray-500">{'\u25BE'}</span>
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-10" onClick={() => setOpen(false)} />
          <div className="absolute right-0 top-full mt-1 z-20 min-w-[220px] bg-gray-900 border border-gray-700 rounded-lg shadow-xl p-1">
            <div className="px-3 py-2 text-[10px] text-gray-500 uppercase tracking-wide border-b border-gray-800 mb-1">
              Workspace
            </div>
            {EXTENSIONS.map(ext => (
              <div
                key={ext.id}
                className={`flex flex-col gap-0.5 px-3 py-2 rounded ${
                  ext.id === active.id ? 'bg-gray-800' : 'text-gray-400'
                }`}
              >
                <div className="text-sm text-gray-200">{ext.label}</div>
                <div className="text-[11px] text-gray-500">{ext.description}</div>
              </div>
            ))}
            <div className="px-3 py-2 text-[10px] text-gray-600 italic border-t border-gray-800 mt-1">
              More workspaces land with the extension-manifest pass.
            </div>
          </div>
        </>
      )}
    </div>
  );
}

```
