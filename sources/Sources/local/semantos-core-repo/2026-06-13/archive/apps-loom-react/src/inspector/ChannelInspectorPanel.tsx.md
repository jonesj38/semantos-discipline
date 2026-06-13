---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/inspector/ChannelInspectorPanel.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.945274+00:00
---

# archive/apps-loom-react/src/inspector/ChannelInspectorPanel.tsx

```tsx
/**
 * ChannelInspectorPanel — channel-specific inspector panels for PaymentChannel objects.
 *
 * Displays channel status, funding, transaction history, policy rules, and dispute info.
 * Renders inside ObjectInspector when the selected object has category "metering.channel".
 */

import { useLoom } from '../state/LoomProvider';

const PHASE_COLORS: Record<string, string> = {
  prefunding: 'bg-gray-600',
  funding: 'bg-yellow-600',
  active: 'bg-green-600',
  settling: 'bg-blue-600',
  settled: 'bg-purple-600',
  disputed: 'bg-red-600',
  closed: 'bg-gray-500',
  cancelled: 'bg-gray-500',
  expired: 'bg-gray-500',
};

function truncateCertId(certId: string): string {
  if (!certId || certId.length < 20) return certId || '—';
  return certId.slice(0, 12) + '...' + certId.slice(-6);
}

export function ChannelInspectorPanel() {
  const { selectedObject, state } = useLoom();
  const objects = state.objects;

  if (!selectedObject) return null;
  if (selectedObject.typeDefinition.category !== 'metering.channel') return null;

  const p = selectedObject.payload;
  const status = (p.status as string) || 'prefunding';
  const channelCertId = (p.channelCertId as string) || '';
  const counterpartyCertId = (p.counterpartyCertId as string) || '';
  const fundingSatoshis = (p.fundingSatoshis as number) || 0;
  const fundingDeadline = (p.fundingDeadline as number) || 0;
  const cumulativeSatoshis = (p.cumulativeSatoshis as number) || 0;
  const currentTick = (p.currentTick as number) || 0;
  const meterUnit = (p.meterUnit as string) || '';
  const balanceTracking = (p.balanceTracking as Record<string, number>) || {};
  const policyObjectId = (p.policyObjectId as string) || '';
  const disputeId = (p.disputeId as string) || '';
  const ballotId = (p.ballotId as string) || '';
  const settlementTxId = (p.settlementTxId as string) || '';
  const settlementConfirmed = (p.settlementConfirmed as boolean) || false;

  // Get policy object if available
  const policyObj = policyObjectId ? objects.get(policyObjectId) : undefined;
  const policyPayload = policyObj?.payload;

  // Filter channel_transaction patches
  const txPatches = selectedObject.patches.filter(patch => patch.kind === 'channel_transaction');
  const settlementPatches = selectedObject.patches.filter(patch => patch.kind === 'channel_settlement');

  return (
    <div className="space-y-2">
      {/* Status Section */}
      <div>
        <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">Channel Status</div>
        <div className="space-y-0.5">
          <div className="flex items-center gap-2">
            <span className="text-gray-600 w-20 flex-shrink-0">Phase</span>
            <span className={`px-1.5 py-0.5 rounded text-[10px] text-white ${PHASE_COLORS[status] || 'bg-gray-600'}`}>
              {status.toUpperCase()}
            </span>
          </div>
          <Row label="Channel ID" value={truncateCertId(channelCertId)} />
          <Row label="Counterparty" value={truncateCertId(counterpartyCertId)} />
          <Row label="Meter Unit" value={meterUnit || '—'} />
          <Row label="Ticks" value={String(currentTick)} />
          <Row label="Cumulative" value={`${cumulativeSatoshis} sats`} />
        </div>
      </div>

      {/* Funding Section */}
      <div>
        <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">Funding</div>
        <div className="space-y-0.5">
          <Row label="Target" value={`${fundingSatoshis} sats`} />
          <Row label="Deadline" value={fundingDeadline ? new Date(fundingDeadline).toLocaleString() : '—'} />
        </div>
      </div>

      {/* Transaction History */}
      {txPatches.length > 0 && (
        <div>
          <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">
            Transactions ({txPatches.length})
          </div>
          <div className="space-y-0.5 max-h-32 overflow-y-auto">
            {txPatches.map(patch => {
              const d = patch.delta;
              return (
                <div key={patch.id} className="text-[10px] text-gray-400 flex gap-2">
                  <span className="text-gray-600 flex-shrink-0">
                    {new Date(patch.timestamp).toLocaleTimeString()}
                  </span>
                  <span className="text-emerald-400">{String(d.amount)} {String(d.meterUnit)}</span>
                  <span className="truncate">
                    {truncateCertId(String(d.from))} → {truncateCertId(String(d.to))}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Balance Tracking */}
      {Object.keys(balanceTracking).length > 0 && (
        <div>
          <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">Balances</div>
          <div className="space-y-0.5">
            {Object.entries(balanceTracking).map(([certId, amount]) => (
              <div key={certId} className="text-[10px] text-gray-400 flex gap-2">
                <span className="text-gray-300 font-mono">{truncateCertId(certId)}</span>
                <span className="text-green-400">{amount} sats</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Policy Rules */}
      {policyPayload && (
        <div>
          <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">Policy Rules</div>
          <div className="space-y-0.5">
            <Row label="Min Funding" value={`${policyPayload.minFundingSatoshis ?? '—'} sats`} />
            <Row label="Max Duration" value={`${policyPayload.maxChannelDurationSeconds ?? '—'}s`} />
            <Row label="Dispute Window" value={`${policyPayload.disputeWindowSeconds ?? '—'}s`} />
            <Row label="Settlement Fee" value={`${policyPayload.settlementFeePercent ?? '—'}%`} />
            <Row label="Meter Unit" value={String(policyPayload.meterUnit ?? '—')} />
            <Row label="Price/Unit" value={`${policyPayload.pricePerUnit ?? '—'} sats`} />
            <Row label="Auto-Settle" value={`${policyPayload.autoSettleThreshold ?? '—'}`} />
          </div>
        </div>
      )}

      {/* Settlement Section */}
      {settlementPatches.length > 0 && (
        <div>
          <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">Settlement</div>
          <div className="space-y-0.5">
            <Row label="Tx ID" value={truncateCertId(settlementTxId)} />
            <Row label="Confirmed" value={settlementConfirmed ? 'Yes' : 'No'} />
          </div>
        </div>
      )}

      {/* Dispute Section */}
      {status === 'disputed' && (disputeId || ballotId) && (
        <div>
          <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">Dispute</div>
          <div className="space-y-0.5">
            {disputeId && <Row label="Dispute" value={truncateCertId(disputeId)} />}
            {ballotId && <Row label="Ballot" value={truncateCertId(ballotId)} />}
          </div>
        </div>
      )}
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center gap-2 text-[11px]">
      <span className="text-gray-600 w-20 flex-shrink-0">{label}</span>
      <span className="text-gray-300 truncate font-mono text-[10px]">{value}</span>
    </div>
  );
}

```
