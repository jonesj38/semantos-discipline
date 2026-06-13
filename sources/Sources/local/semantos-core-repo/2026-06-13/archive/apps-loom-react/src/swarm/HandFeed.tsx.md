---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/HandFeed.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.961150+00:00
---

# archive/apps-loom-react/src/swarm/HandFeed.tsx

```tsx
/**
 * DH5.4 — HandFeed: Scrolling feed of completed poker hands.
 */

import { useRef, useEffect } from 'react';
import { useSwarmDashboard } from './SwarmDashboardProvider';
import { PERSONA_LABELS, type HandCompletedEvent, type PersonaId } from './types';

function relativeTime(ts: number): string {
  const diff = Math.floor((Date.now() - ts) / 1000);
  if (diff < 1) return '<1s ago';
  if (diff < 60) return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  return `${Math.floor(diff / 3600)}h ago`;
}

function truncateTxid(txid: string): string {
  if (!txid || txid.length < 8) return txid || '--';
  return txid.slice(0, 6) + '...';
}

function handRowBg(hand: HandCompletedEvent): string {
  const hasApex = hand.players.some(p => p.persona === 'apex');
  if (!hasApex) return 'bg-gray-900/50';
  if (hand.winner.persona === 'apex') return 'bg-green-900/20';
  return 'bg-red-900/20';
}

function HandRow({ hand }: { hand: HandCompletedEvent }) {
  const hasViolation = !!hand.violation;
  const playerNames = hand.players
    .map(p => PERSONA_LABELS[p.persona as PersonaId] ?? p.persona)
    .join(' vs ');
  const winnerName = PERSONA_LABELS[hand.winner.persona as PersonaId] ?? hand.winner.persona;
  const whatsOnChainUrl = hand.bsvTxid
    ? `https://whatsonchain.com/tx/${hand.bsvTxid}`
    : null;

  return (
    <div
      className={`px-3 py-2 border-b border-gray-800 ${handRowBg(hand)} ${hasViolation ? 'border-l-2 border-l-swarm-error violation' : ''}`}
    >
      <div className="flex items-center justify-between text-xs font-mono">
        <div className="flex items-center gap-2">
          <span className={hasViolation ? 'text-swarm-error' : 'text-swarm-success'}>
            {hasViolation ? '\u2717' : '\u2713'}
          </span>
          <span className="text-gray-200">Hand #{hand.handId.replace(/^h/, '')}</span>
          <span className="text-gray-500">|</span>
          <span className="text-gray-400">{hand.tableId.slice(0, 8)}</span>
        </div>
        <span className="text-gray-200">pot:{hand.potSize} sats</span>
      </div>

      <div className="text-xs text-gray-500 mt-0.5">
        {playerNames} | {hand.actions} bet rnd
      </div>

      <div className="text-xs mt-0.5">
        <span className="text-gray-400">Winner: </span>
        <span className="text-gray-200">{winnerName}</span>
        <span className="text-gray-500"> | {hand.reason}</span>
      </div>

      {hasViolation && (
        <div className="text-xs text-swarm-error mt-0.5 font-bold">
          VIOLATION: {hand.violation!.details}
        </div>
      )}

      <div className="flex items-center justify-between text-xs mt-0.5">
        {whatsOnChainUrl ? (
          <a
            href={whatsOnChainUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="text-swarm-nit hover:underline"
          >
            BSV: {truncateTxid(hand.bsvTxid)}
          </a>
        ) : (
          <span className="text-gray-600">No anchor</span>
        )}
        <span className="text-gray-600">{relativeTime(hand.timestamp)}</span>
      </div>
    </div>
  );
}

export function HandFeed() {
  const { state } = useSwarmDashboard();
  const { hands } = state;
  const scrollRef = useRef<HTMLDivElement>(null);
  const wasAtTopRef = useRef(true);

  // Auto-scroll to top when new hands arrive (if already near top)
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    if (wasAtTopRef.current) {
      el.scrollTop = 0;
    }
  }, [hands.length]);

  const handleScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    wasAtTopRef.current = el.scrollTop < 40;
  };

  return (
    <div className="flex flex-col h-full">
      <div className="px-3 py-2 text-xs font-bold text-gray-400 tracking-wider border-b border-swarm-border">
        HAND FEED
      </div>
      <div
        ref={scrollRef}
        className="flex-1 overflow-y-auto"
        onScroll={handleScroll}
      >
        {hands.length === 0 ? (
          <div className="p-4 text-xs text-gray-600 text-center">
            Waiting for hands...
          </div>
        ) : (
          hands.map(hand => (
            <HandRow key={hand.handId} hand={hand} />
          ))
        )}
      </div>
    </div>
  );
}

```
