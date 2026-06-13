---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/WorkbenchTab.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.943294+00:00
---

# archive/apps-loom-react/src/navigator/WorkbenchTab.tsx

```tsx
/**
 * WorkbenchTab — wraps the existing loom Shell inside the navigator's workbench tab.
 * This is lazy-loaded by NavigatorShell to keep the initial bundle small.
 */

import { useState, useCallback } from 'react';
import { LoomProvider } from '../state/LoomProvider';
import { Sidebar } from '../shell/Sidebar';
import { MainCanvas } from '../shell/MainCanvas';
import { StatusBar } from '../shell/StatusBar';
import { ResizeHandle } from '../shell/ResizeHandle';
import { FacetManager } from '../identity/FacetManager';
import { ObjectTree } from '../sidebar/ObjectTree';
import { TypeList } from '../sidebar/TypeList';
import { CapabilityToggles } from '../sidebar/CapabilityToggles';
import { TaxonomyBrowser } from '../sidebar/TaxonomyBrowser';
import { PolicyViewer } from '../sidebar/PolicyViewer';
import { CommercePipeline } from '../canvas/CommercePipeline';
import { ChatView } from '../canvas/ChatView';
import { ExtensionMarketplace } from '../panels/ExtensionMarketplace';
import { MyExtensions } from '../panels/MyExtensions';
import { GovernanceDashboard } from '../panels/GovernanceDashboard';
import { ExtensionDetail } from '../panels/ExtensionDetail';
import { BindingWizard } from '../panels/BindingWizard';
import type { ExtensionManifest } from '../../../protocol-types/src/extension-manifest';

const STORAGE_KEY = 'workbench-layout';

function getInitialLayout() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) return JSON.parse(saved);
  } catch {}
  return { sidebarWidth: 280, inspectorWidth: 320, sidebarCollapsed: false, inspectorCollapsed: false };
}

type ActivePanel = 'marketplace' | 'my-extensions' | 'governance' | null;

function Shell() {
  const [layout, setLayout] = useState(getInitialLayout);
  const [activePanel, setActivePanel] = useState<ActivePanel>(null);
  const [selectedManifest, setSelectedManifest] = useState<ExtensionManifest | null>(null);
  const [wizardManifest, setWizardManifest] = useState<ExtensionManifest | null>(null);

  const persistLayout = useCallback((next: typeof layout) => {
    setLayout(next);
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(next)); } catch {}
  }, []);

  const resizeSidebar = useCallback((delta: number) => {
    persistLayout({
      ...layout,
      sidebarWidth: Math.max(180, Math.min(500, layout.sidebarWidth + delta)),
    });
  }, [layout, persistLayout]);

  const toggleSidebar = useCallback(() => {
    persistLayout({ ...layout, sidebarCollapsed: !layout.sidebarCollapsed });
  }, [layout, persistLayout]);

  return (
    <div className="h-full flex flex-col">
      <div className="flex items-center gap-1 px-3 py-1.5 bg-gray-900 border-b border-gray-800">
        <button
          onClick={() => { setActivePanel(null); setSelectedManifest(null); }}
          className={`px-2 py-0.5 text-xs rounded ${!activePanel ? 'bg-gray-700 text-gray-200' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Canvas
        </button>
        <button
          onClick={() => setActivePanel('marketplace')}
          className={`px-2 py-0.5 text-xs rounded ${activePanel === 'marketplace' ? 'bg-blue-900/50 text-blue-300' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Marketplace
        </button>
        <button
          onClick={() => setActivePanel('my-extensions')}
          className={`px-2 py-0.5 text-xs rounded ${activePanel === 'my-extensions' ? 'bg-blue-900/50 text-blue-300' : 'text-gray-500 hover:text-gray-300'}`}
        >
          My Extensions
        </button>
        <button
          onClick={() => setActivePanel('governance')}
          className={`px-2 py-0.5 text-xs rounded ${activePanel === 'governance' ? 'bg-blue-900/50 text-blue-300' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Governance
        </button>
      </div>

      <div className="flex-1 flex overflow-hidden">
        <Sidebar width={layout.sidebarWidth} collapsed={layout.sidebarCollapsed} onToggle={toggleSidebar}>
          <FacetManager />
          <ObjectTree />
          <TypeList />
          <CapabilityToggles />
          <TaxonomyBrowser />
          <PolicyViewer />
        </Sidebar>
        {!layout.sidebarCollapsed && <ResizeHandle onResize={resizeSidebar} direction="left" />}
        <MainCanvas>
          {!activePanel && !selectedManifest && (
            <>
              <CommercePipeline />
              <ChatView />
            </>
          )}
          {activePanel === 'marketplace' && !selectedManifest && (
            <ExtensionMarketplace onInstall={(m) => setWizardManifest(m)} onSelect={(m) => setSelectedManifest(m)} />
          )}
          {activePanel === 'my-extensions' && !selectedManifest && (
            <MyExtensions onConfigure={() => {}} onSelectExtension={() => {}} />
          )}
          {activePanel === 'governance' && !selectedManifest && <GovernanceDashboard />}
          {selectedManifest && <ExtensionDetail manifest={selectedManifest} onClose={() => setSelectedManifest(null)} />}
        </MainCanvas>
      </div>
      <StatusBar />

      {wizardManifest && (
        <BindingWizard
          manifest={wizardManifest}
          open={true}
          onClose={() => setWizardManifest(null)}
          onComplete={() => { setWizardManifest(null); setActivePanel('my-extensions'); }}
        />
      )}
    </div>
  );
}

export default function WorkbenchTab() {
  return (
    <LoomProvider>
      <Shell />
    </LoomProvider>
  );
}

```
