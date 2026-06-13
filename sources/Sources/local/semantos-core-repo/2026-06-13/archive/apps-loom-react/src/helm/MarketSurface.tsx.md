---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/MarketSurface.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.967492+00:00
---

# archive/apps-loom-react/src/helm/MarketSurface.tsx

```tsx
/**
 * MarketSurface — Extension marketplace, management, and governance.
 *
 * Hosts the Phase 36E extension panels within the Phase 39 Support Drawer.
 * Replaces the old top-level tab bar (Canvas/Marketplace/My Extensions/Governance).
 */

import { useState } from 'react';
import { ExtensionMarketplace } from '../panels/ExtensionMarketplace';
import { MyExtensions } from '../panels/MyExtensions';
import { GovernanceDashboard } from '../panels/GovernanceDashboard';
import { ExtensionDetail } from '../panels/ExtensionDetail';
import { BindingWizard } from '../panels/BindingWizard';
import type { ExtensionManifest } from '@semantos/protocol-types';

type ActivePanel = 'marketplace' | 'my-extensions' | 'governance';

export function MarketSurface() {
  const [activePanel, setActivePanel] = useState<ActivePanel>('marketplace');
  const [selectedManifest, setSelectedManifest] = useState<ExtensionManifest | null>(null);
  const [wizardManifest, setWizardManifest] = useState<ExtensionManifest | null>(null);

  return (
    <div className="flex flex-col h-full">
      {/* Sub-tab bar */}
      <div className="flex items-center gap-1 px-3 py-1.5 border-b border-gray-800">
        <button
          onClick={() => { setActivePanel('marketplace'); setSelectedManifest(null); }}
          className={`px-2 py-0.5 text-xs rounded ${activePanel === 'marketplace' ? 'bg-blue-900/50 text-blue-300' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Marketplace
        </button>
        <button
          onClick={() => { setActivePanel('my-extensions'); setSelectedManifest(null); }}
          className={`px-2 py-0.5 text-xs rounded ${activePanel === 'my-extensions' ? 'bg-blue-900/50 text-blue-300' : 'text-gray-500 hover:text-gray-300'}`}
        >
          My Extensions
        </button>
        <button
          onClick={() => { setActivePanel('governance'); setSelectedManifest(null); }}
          className={`px-2 py-0.5 text-xs rounded ${activePanel === 'governance' ? 'bg-blue-900/50 text-blue-300' : 'text-gray-500 hover:text-gray-300'}`}
        >
          Governance
        </button>
      </div>

      {/* Panel content */}
      <div className="flex-1 overflow-y-auto">
        {activePanel === 'marketplace' && !selectedManifest && (
          <ExtensionMarketplace
            onInstall={(m) => setWizardManifest(m)}
            onSelect={(m) => setSelectedManifest(m)}
          />
        )}
        {activePanel === 'my-extensions' && !selectedManifest && (
          <MyExtensions
            onConfigure={() => {}}
            onSelectExtension={() => {}}
          />
        )}
        {activePanel === 'governance' && !selectedManifest && (
          <GovernanceDashboard />
        )}
        {selectedManifest && (
          <ExtensionDetail
            manifest={selectedManifest}
            onClose={() => setSelectedManifest(null)}
          />
        )}
      </div>

      {/* Binding Wizard Modal */}
      {wizardManifest && (
        <BindingWizard
          manifest={wizardManifest}
          open={true}
          onClose={() => setWizardManifest(null)}
          onComplete={() => {
            setWizardManifest(null);
            setActivePanel('my-extensions');
          }}
        />
      )}
    </div>
  );
}

```
