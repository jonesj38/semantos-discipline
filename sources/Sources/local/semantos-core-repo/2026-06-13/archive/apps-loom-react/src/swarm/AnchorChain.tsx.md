---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/AnchorChain.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.960569+00:00
---

# archive/apps-loom-react/src/swarm/AnchorChain.tsx

```tsx
/**
 * DH5.5 — AnchorChain: Horizontal chain of Merkle-rooted BSV anchor batches.
 */

import { useSwarmDashboard } from './SwarmDashboardProvider';
import type { BatchAnchoredEvent } from './types';

function truncate(hex: string, len = 6): string {
  if (!hex || hex.length < len) return hex || '--';
  return hex.slice(0, len) + '...';
}

function relativeTime(ts: number): string {
  const diff = Math.floor((Date.now() - ts) / 1000);
  if (diff < 1) return '<1s ago';
  if (diff < 60) return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  return `${Math.floor(diff / 3600)}h ago`;
}

function BatchBlock({ batch, isNewest }: { batch: BatchAnchoredEvent; isNewest: boolean }) {
  const whatsOnChainUrl = batch.bsvTxid
    ? `https://whatsonchain.com/tx/${batch.bsvTxid}`
    : null;

  return (
    <div
      className={`
        flex-shrink-0 w-36 p-2 rounded border font-mono text-xs
        ${isNewest
          ? 'border-swarm-apex/50 bg-yellow-900/15 new-batch'
          : 'border-swarm-border bg-swarm-panel'
        }
      `}
    >
      <div className="text-gray-200 font-bold mb-1">
        Batch {batch.batchNumber}
        {isNewest && <span className="ml-1 text-swarm-apex text-[10px]">NEW</span>}
      </div>
      <div className="text-gray-400">{batch.cellCount} cells</div>
      <div className="text-gray-500 mt-1">
        Root: <span className="text-gray-300">{truncate(batch.merkleRoot)}</span>
      </div>
      {batch.bsvTxid ? (
        <div className="mt-0.5">
          TxID:{' '}
          <a
            href={whatsOnChainUrl!}
            target="_blank"
            rel="noopener noreferrer"
            className="text-swarm-nit hover:underline"
          >
            {truncate(batch.bsvTxid)}
          </a>
        </div>
      ) : (
        <div className="text-gray-600 mt-0.5">Pending anchor</div>
      )}
      <div className="text-gray-600 mt-1">{relativeTime(batch.timestamp)}</div>
    </div>
  );
}

export function AnchorChain() {
  const { state } = useSwarmDashboard();
  // Display chronologically: oldest on left, newest on right
  const batches = [...state.batches].reverse();

  return (
    <div className="flex flex-col h-full">
      <div className="px-3 py-2 text-xs font-bold text-gray-400 tracking-wider border-b border-swarm-border">
        ANCHOR CHAIN (BSV Settlement)
      </div>
      <div className="flex-1 overflow-x-auto p-3">
        {batches.length === 0 ? (
          <div className="text-xs text-gray-600 text-center py-4">
            Waiting for batches...
          </div>
        ) : (
          <div className="flex items-center gap-2 min-w-min">
            {batches.map((batch, i) => (
              <div key={batch.batchNumber} className="flex items-center">
                <BatchBlock
                  batch={batch}
                  isNewest={i === batches.length - 1}
                />
                {i < batches.length - 1 && (
                  <div className="flex-shrink-0 w-6 flex items-center justify-center">
                    <span className="text-gray-500 text-lg">{'\u2192'}</span>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

```
