---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/SwarmDashboard.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.958865+00:00
---

# archive/apps-loom-react/src/swarm/SwarmDashboard.tsx

```tsx
/**
 * DH5.6 — SwarmDashboard: Top-level shell assembling all five panels.
 *
 * Layout: CSS Grid, 2 columns x 3 rows.
 * Dark theme: #0a0a0a background, Courier New monospace.
 */

import { useState, useCallback } from 'react';
import { useSwarmDashboard } from './SwarmDashboardProvider';
import { SwarmTopology } from './SwarmTopology';
import { TPSCounter } from './TPSCounter';
import { PersonaLeaderboard } from './PersonaLeaderboard';
import { HandFeed } from './HandFeed';
import { AnchorChain } from './AnchorChain';

function ConnectionBar() {
  const { state, connect, disconnect } = useSwarmDashboard();
  const [urlInput, setUrlInput] = useState(state.wsUrl);

  const handleConnect = useCallback(() => {
    if (state.connection === 'connected') {
      disconnect();
    } else {
      connect(urlInput);
    }
  }, [state.connection, urlInput, connect, disconnect]);

  const statusColor = {
    connected: 'bg-swarm-success',
    connecting: 'bg-swarm-warning',
    disconnected: 'bg-swarm-error',
    error: 'bg-swarm-error',
  }[state.connection];

  return (
    <div className="flex items-center gap-3 px-4 py-2 bg-gray-900 border-b border-swarm-border">
      <div className={`w-2 h-2 rounded-full ${statusColor}`} />
      <span className="text-xs text-gray-400 font-mono uppercase">
        {state.connection}
      </span>
      <input
        type="text"
        value={urlInput}
        onChange={(e) => setUrlInput(e.target.value)}
        className="flex-1 max-w-md px-2 py-1 text-xs font-mono bg-gray-800 border border-gray-700 rounded text-gray-200 focus:outline-none focus:border-swarm-nit"
        placeholder="ws://localhost:8081"
      />
      <button
        onClick={handleConnect}
        className={`px-3 py-1 text-xs font-mono rounded ${
          state.connection === 'connected'
            ? 'bg-gray-700 text-gray-300 hover:bg-gray-600'
            : 'bg-swarm-nit text-white hover:bg-blue-600'
        }`}
      >
        {state.connection === 'connected' ? 'Disconnect' : 'Connect'}
      </button>
      <div className="text-xs text-gray-600 font-mono">
        SEMANTOS SWARM GOD VIEW
      </div>
    </div>
  );
}

function DisconnectedBanner() {
  const { state } = useSwarmDashboard();
  if (state.connection === 'connected' || state.connection === 'connecting') return null;

  return (
    <div className="absolute top-12 left-1/2 -translate-x-1/2 z-50 px-6 py-2 bg-swarm-error/90 text-white text-sm font-mono rounded shadow-lg">
      DISCONNECTED — auto-reconnecting...
    </div>
  );
}

export function SwarmDashboard() {
  return (
    <div className="h-screen w-screen flex flex-col bg-swarm-bg text-gray-200 font-mono relative">
      <ConnectionBar />
      <DisconnectedBanner />

      {/* Main grid */}
      <div
        className="flex-1 grid gap-px overflow-hidden"
        style={{
          gridTemplateColumns: '1fr 1fr',
          gridTemplateRows: '2fr 1fr 1fr',
        }}
      >
        {/* Row 1, Col 1: Topology (spans 2 rows) */}
        <div
          className="bg-swarm-panel border border-swarm-border overflow-hidden"
          style={{ gridRow: '1 / 3' }}
        >
          <SwarmTopology />
        </div>

        {/* Row 1, Col 2: TPS Counter */}
        <div className="bg-swarm-panel border border-swarm-border overflow-hidden">
          <TPSCounter />
        </div>

        {/* Row 2, Col 2: Persona Leaderboard */}
        <div className="bg-swarm-panel border border-swarm-border overflow-auto">
          <PersonaLeaderboard />
        </div>

        {/* Row 3, Col 1: Hand Feed */}
        <div className="bg-swarm-panel border border-swarm-border overflow-hidden">
          <HandFeed />
        </div>

        {/* Row 3, Col 2: Anchor Chain */}
        <div className="bg-swarm-panel border border-swarm-border overflow-hidden">
          <AnchorChain />
        </div>
      </div>
    </div>
  );
}

```
