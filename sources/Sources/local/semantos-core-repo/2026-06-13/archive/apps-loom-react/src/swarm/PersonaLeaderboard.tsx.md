---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/PersonaLeaderboard.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.959715+00:00
---

# archive/apps-loom-react/src/swarm/PersonaLeaderboard.tsx

```tsx
/**
 * DH5.3 — PersonaLeaderboard: Ranked table of persona stats with dominance indicator.
 */

import { useMemo } from 'react';
import { useSwarmDashboard } from './SwarmDashboardProvider';
import { PERSONA_COLORS, PERSONA_LABELS, type PersonaId, type PersonaStats } from './types';

interface RankedPersona {
  id: PersonaId;
  stats: PersonaStats;
  rank: number;
}

function MiniSparkline({ data, color, width = 80, height = 20 }: {
  data: number[];
  color: string;
  width?: number;
  height?: number;
}) {
  if (data.length < 2) return null;
  const max = Math.max(...data, 1);
  const min = Math.min(...data, 0);
  const range = max - min || 1;

  const points = data.map((v, i) => {
    const x = (i / (data.length - 1)) * width;
    const y = height - ((v - min) / range) * (height - 2) - 1;
    return `${x},${y}`;
  }).join(' ');

  return (
    <svg width={width} height={height} className="inline-block align-middle">
      <polyline points={points} fill="none" stroke={color} strokeWidth={1.5} />
    </svg>
  );
}

export function PersonaLeaderboard() {
  const { state } = useSwarmDashboard();
  const { personaStats } = state;

  const ranked = useMemo((): RankedPersona[] => {
    const ids: PersonaId[] = ['nit', 'maniac', 'calculator', 'apex'];
    const sorted = ids
      .map(id => ({ id, stats: personaStats.personas[id] }))
      .sort((a, b) => b.stats.balance - a.stats.balance);
    return sorted.map((item, i) => ({ ...item, rank: i + 1 }));
  }, [personaStats]);

  const avgWinRate = useMemo(() => {
    const ids: PersonaId[] = ['nit', 'maniac', 'calculator', 'apex'];
    const sum = ids.reduce((acc, id) => acc + personaStats.personas[id].winRate, 0);
    return sum / 4;
  }, [personaStats]);

  const apexStats = personaStats.personas.apex;
  const apexDominance = apexStats.winRate - avgWinRate;
  const showDominance = apexDominance > 0;

  return (
    <div className="p-4 flex flex-col gap-2">
      <div className="text-xs font-bold text-gray-400 tracking-wider">PERSONA LEADERBOARD</div>

      <table className="w-full text-xs font-mono">
        <thead>
          <tr className="text-gray-500 border-b border-swarm-border">
            <th className="text-left py-1 w-6">#</th>
            <th className="text-left py-1">Persona</th>
            <th className="text-right py-1">Balance</th>
            <th className="text-right py-1 hidden lg:table-cell">Hands</th>
            <th className="text-right py-1">Win%</th>
            <th className="text-right py-1 hidden lg:table-cell">Policy</th>
            <th className="text-right py-1 w-20"></th>
          </tr>
        </thead>
        <tbody>
          {ranked.map(({ id, stats, rank }) => {
            const isApex = id === 'apex';
            return (
              <tr
                key={id}
                className={`border-b border-gray-800 ${isApex ? 'bg-yellow-900/10' : ''}`}
              >
                <td className="py-1.5 text-gray-500">{rank}</td>
                <td className="py-1.5">
                  <span style={{ color: PERSONA_COLORS[id] }}>
                    {PERSONA_LABELS[id]}
                  </span>
                  {isApex && <span className="ml-1 text-swarm-apex">{'\u2605'}</span>}
                </td>
                <td className="py-1.5 text-right text-gray-200">{stats.balance} sats</td>
                <td className="py-1.5 text-right text-gray-400 hidden lg:table-cell">
                  {stats.handsPlayed}/{stats.handsWon}
                </td>
                <td className="py-1.5 text-right text-gray-200">
                  {(stats.winRate * 100).toFixed(1)}%
                </td>
                <td className="py-1.5 text-right text-gray-400 hidden lg:table-cell">
                  {isApex ? (
                    <span className="text-swarm-apex">v{stats.policyVersion}</span>
                  ) : (
                    <span className="text-gray-600">{'\u2013'}</span>
                  )}
                </td>
                <td className="py-1.5 text-right">
                  <MiniSparkline
                    data={stats.recentBalances}
                    color={PERSONA_COLORS[id]}
                  />
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>

      {/* Dominance indicator */}
      {showDominance && (
        <div className="mt-2 px-3 py-2 rounded border border-swarm-apex/30 bg-yellow-900/10 text-center animate-pulse">
          <span className="text-swarm-apex font-bold text-sm">
            APEX DOMINANCE: +{(apexDominance * 100).toFixed(1)}%
          </span>
        </div>
      )}

      {/* Swarm average */}
      <div className="text-xs text-gray-500 mt-1">
        Swarm avg win rate: <span className="text-gray-400 font-mono">{(avgWinRate * 100).toFixed(1)}%</span>
      </div>
    </div>
  );
}

```
