---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/App.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.931973+00:00
---

# archive/apps-loom-react/src/App.tsx

```tsx
import { useState, useEffect, lazy, Suspense } from 'react';
import { ErrorBoundary } from './ErrorBoundary';

// Lazy-load both routes to avoid pulling in missing d3-force eagerly
const LoomApp = lazy(() => import('./LoomApp'));
const SwarmView = lazy(() => import('./swarm/SwarmDashboard').then(async (mod) => {
  const { SwarmDashboardProvider } = await import('./swarm/SwarmDashboardProvider');
  return {
    default: () => (
      <SwarmDashboardProvider>
        <mod.SwarmDashboard />
      </SwarmDashboardProvider>
    ),
  };
}));

const LOADING = <div className="h-screen bg-gray-950 flex items-center justify-center text-gray-400">Loading...</div>;

export function App() {
  const [isSwarmView, setIsSwarmView] = useState(() => window.location.hash === '#swarm');

  useEffect(() => {
    const handler = () => setIsSwarmView(window.location.hash === '#swarm');
    window.addEventListener('hashchange', handler);
    return () => window.removeEventListener('hashchange', handler);
  }, []);

  return (
    <ErrorBoundary>
      <Suspense fallback={LOADING}>
        {isSwarmView ? <SwarmView /> : <LoomApp />}
      </Suspense>
    </ErrorBoundary>
  );
}

```
