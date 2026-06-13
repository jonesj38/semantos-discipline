---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/NavigatorShell.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.943013+00:00
---

# archive/apps-loom-react/src/navigator/NavigatorShell.tsx

```tsx
import { useState, lazy, Suspense } from 'react';
import { TopStatusBar } from './TopStatusBar';
import { BottomNav, type TabId } from './BottomNav';
import { HomeView } from './views/HomeView';
import { TalkView } from './views/TalkView';
import { ProcessView } from './views/ProcessView';
import { InsightsView } from './views/InsightsView';
import { ReleaseOverlay } from './overlays/ReleaseOverlay';
import { ReviewOverlay } from './overlays/ReviewOverlay';
import { IntentionOverlay } from './overlays/IntentionOverlay';
import { useKernel } from '../contexts/KernelProvider';
import './navigator.css';

// Lazy-load the loom tab since it's heavy
const WorkbenchTab = lazy(() => import('./WorkbenchTab'));

export type OverlayType = 'release' | 'review' | 'intention' | null;

export function NavigatorShell() {
  const [activeTab, setActiveTab] = useState<TabId>('home');
  const [overlay, setOverlay] = useState<OverlayType>(null);
  const { isBooting } = useKernel();

  if (isBooting) {
    return (
      <div className="h-full flex flex-col" style={{ background: 'var(--nav-bg)' }}>
        <div className="nav-loading">Booting kernel...</div>
      </div>
    );
  }

  const isWorkbench = activeTab === 'workbench';

  return (
    <div className="h-full flex flex-col" style={{ background: 'var(--nav-bg)', color: 'var(--nav-text)' }}>
      <TopStatusBar />

      <div className="flex-1 overflow-hidden">
        <div
          className={isWorkbench ? 'h-full' : 'h-full mx-auto'}
          style={isWorkbench ? undefined : { maxWidth: 480 }}
        >
          <div className="h-full overflow-y-auto" style={{ display: activeTab === 'home' ? 'flex' : 'none', flexDirection: 'column' }}>
            <HomeView onOpenOverlay={setOverlay} onSwitchTab={setActiveTab} />
          </div>
          <div className="h-full overflow-y-auto" style={{ display: activeTab === 'talk' ? 'flex' : 'none', flexDirection: 'column' }}>
            <TalkView />
          </div>
          <div className="h-full overflow-y-auto" style={{ display: activeTab === 'process' ? 'flex' : 'none', flexDirection: 'column' }}>
            <ProcessView onSwitchToTalk={(text) => { setActiveTab('talk'); /* TalkView handles pre-fill via ref */ }} />
          </div>
          <div className="h-full overflow-y-auto" style={{ display: activeTab === 'insights' ? 'flex' : 'none', flexDirection: 'column' }}>
            <InsightsView />
          </div>
          {activeTab === 'workbench' && (
            <Suspense fallback={<div className="nav-loading">Loading loom...</div>}>
              <WorkbenchTab />
            </Suspense>
          )}
        </div>
      </div>

      <BottomNav activeTab={activeTab} onTabChange={setActiveTab} />

      {/* Overlays */}
      <ReleaseOverlay open={overlay === 'release'} onClose={() => setOverlay(null)} />
      <ReviewOverlay open={overlay === 'review'} onClose={() => setOverlay(null)} />
      <IntentionOverlay open={overlay === 'intention'} onClose={() => setOverlay(null)} />
    </div>
  );
}

```
