---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/SupportDrawer.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.967759+00:00
---

# archive/apps-loom-react/src/helm/SupportDrawer.tsx

```tsx
import React, { lazy, Suspense, useState } from 'react';

const PageSurface = lazy(() =>
  import('./PageSurface').then((m) => ({ default: m.PageSurface }))
);
const MarketSurface = lazy(() =>
  import('./MarketSurface').then((m) => ({ default: m.MarketSurface }))
);

type SupportTab = 'page' | 'settings' | 'insights' | 'library' | 'market';

interface TabDef {
  id: SupportTab;
  label: string;
}

const SUPPORT_TABS: TabDef[] = [
  { id: 'page',     label: 'Page' },
  { id: 'settings', label: 'Settings' },
  { id: 'insights', label: 'Insights' },
  { id: 'library',  label: 'Library' },
  { id: 'market',   label: 'Market' },
];

export interface SupportDrawerProps {
  isOpen: boolean;
  onClose: () => void;
}

function PlaceholderSurface({ name }: { name: string }) {
  return (
    <div className="p-4 text-center text-gray-500 py-12">
      <p className="text-sm font-medium">{name}</p>
      <p className="text-xs mt-1 text-gray-600">This surface is not yet implemented.</p>
    </div>
  );
}

function SurfaceContent({ tab }: { tab: SupportTab }) {
  switch (tab) {
    case 'page':
      return (
        <Suspense fallback={<div className="p-4 text-gray-500 text-sm">Loading...</div>}>
          <PageSurface />
        </Suspense>
      );
    case 'settings':
      return <PlaceholderSurface name="Settings" />;
    case 'insights':
      return <PlaceholderSurface name="Insights" />;
    case 'library':
      return <PlaceholderSurface name="Library" />;
    case 'market':
      return (
        <Suspense fallback={<div className="p-4 text-gray-500 text-sm">Loading...</div>}>
          <MarketSurface />
        </Suspense>
      );
  }
}

export function SupportDrawer({ isOpen, onClose }: SupportDrawerProps) {
  const [activeTab, setActiveTab] = useState<SupportTab>('page');

  if (!isOpen) return null;

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/40 z-40"
        onClick={onClose}
        aria-hidden="true"
      />

      {/* Drawer panel */}
      <div className="fixed inset-y-0 right-0 w-80 max-w-full bg-gray-900 border-l border-gray-700 z-50 flex flex-col shadow-xl">
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-gray-700">
          <h2 className="text-sm font-semibold text-gray-200">Support</h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-200 transition-colors text-lg leading-none"
            aria-label="Close drawer"
          >
            {'\u2715'}
          </button>
        </div>

        {/* Tab bar */}
        <div className="flex border-b border-gray-700 overflow-x-auto shrink-0">
          {SUPPORT_TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`
                px-3 py-2 text-xs font-medium whitespace-nowrap transition-colors
                ${activeTab === tab.id
                  ? 'text-blue-400 border-b-2 border-blue-400'
                  : 'text-gray-400 hover:text-gray-200'}
              `}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto">
          <SurfaceContent tab={activeTab} />
        </div>
      </div>
    </>
  );
}

```
