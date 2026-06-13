---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/inspector/AccumulatedStateView.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.944994+00:00
---

# archive/apps-loom-react/src/inspector/AccumulatedStateView.tsx

```tsx
import { useLoom } from '../state/LoomProvider';

const RECOMMENDATION_COLORS: Record<string, string> = {
  priority_lead: 'bg-green-600 text-white',
  worth_quoting: 'bg-green-800 text-green-200',
  probably_bookable: 'bg-blue-800 text-blue-200',
  needs_site_visit: 'bg-yellow-800 text-yellow-200',
  only_if_nearby: 'bg-orange-800 text-orange-200',
  ignore: 'bg-red-900 text-red-300',
};

function ScoreBar({ label, value, max = 100 }: { label: string; value: number; max?: number }) {
  const pct = Math.min(100, Math.max(0, (value / max) * 100));
  const color = pct >= 70 ? 'bg-green-500' : pct >= 40 ? 'bg-yellow-500' : 'bg-red-500';

  return (
    <div className="flex items-center gap-2">
      <span className="text-gray-500 w-28 flex-shrink-0 text-[10px]">{label}</span>
      <div className="flex-1 h-2 bg-gray-800 rounded overflow-hidden">
        <div className={`h-full ${color} rounded`} style={{ width: `${pct}%` }} />
      </div>
      <span className="text-gray-400 font-mono text-[10px] w-8 text-right">{value}</span>
    </div>
  );
}

export function AccumulatedStateView() {
  const { selectedObject } = useLoom();

  if (!selectedObject) return null;

  const p = selectedObject.payload;
  const hasScoring = p.customerFitScore != null || p.quoteWorthinessScore != null;
  if (!hasScoring) return null;

  const recommendation = String(p.recommendation ?? '');
  const recColor = RECOMMENDATION_COLORS[recommendation] ?? 'bg-gray-800 text-gray-400';

  return (
    <div>
      <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">Scoring Snapshot</div>
      <div className="space-y-1">
        <ScoreBar label="Customer Fit" value={Number(p.customerFitScore ?? 0)} />
        <ScoreBar label="Quote Worthiness" value={Number(p.quoteWorthinessScore ?? 0)} />
        <ScoreBar label="Confidence" value={Number(p.confidenceScore ?? 0)} />
        {recommendation && (
          <div className="flex items-center gap-2">
            <span className="text-gray-500 w-28 flex-shrink-0 text-[10px]">Recommendation</span>
            <span className={`inline-block rounded px-1.5 py-0.5 text-[10px] font-medium ${recColor}`}>
              {recommendation.replace(/_/g, ' ')}
            </span>
          </div>
        )}
      </div>
    </div>
  );
}

```
