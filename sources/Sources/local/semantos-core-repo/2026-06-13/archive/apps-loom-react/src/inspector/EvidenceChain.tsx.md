---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/inspector/EvidenceChain.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.943895+00:00
---

# archive/apps-loom-react/src/inspector/EvidenceChain.tsx

```tsx
import { useLoom } from '../state/LoomProvider';
import { useIdentity } from '../identity/IdentityProvider';

const KIND_COLORS: Record<string, string> = {
  extraction: 'text-blue-400',
  rescore: 'text-green-400',
  manual_override: 'text-yellow-400',
  state_transition: 'text-purple-400',
  evidence_merge: 'text-cyan-400',
  instrument_emit: 'text-orange-400',
  action: 'text-red-400',
  conversation: 'text-indigo-400',
  channel_transaction: 'text-emerald-400',
  channel_settlement: 'text-lime-400',
};

/** Consistent color for a hat based on its name. */
const HAT_BORDER_COLORS = [
  'border-l-blue-400',
  'border-l-green-400',
  'border-l-amber-400',
  'border-l-purple-400',
  'border-l-cyan-400',
  'border-l-rose-400',
  'border-l-teal-400',
  'border-l-orange-400',
];

function hatBorderColor(hatId: string): string {
  let hash = 0;
  for (let i = 0; i < hatId.length; i++) {
    hash = ((hash << 5) - hash + hatId.charCodeAt(i)) | 0;
  }
  return HAT_BORDER_COLORS[Math.abs(hash) % HAT_BORDER_COLORS.length];
}

export function EvidenceChain() {
  const { selectedObject } = useLoom();
  const { identity } = useIdentity();

  if (!selectedObject || selectedObject.patches.length === 0) return null;

  const hatNameMap = new Map<string, string>();
  if (identity) {
    for (const hat of identity.hats) {
      hatNameMap.set(hat.id, hat.name);
    }
  }

  return (
    <div>
      <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">
        Evidence Chain ({selectedObject.patches.length})
      </div>
      <div className="space-y-1">
        {selectedObject.patches.map(patch => {
          const hasHat = !!patch.hatId;
          const hatName = patch.hatId ? hatNameMap.get(patch.hatId) : undefined;
          const borderClass = patch.hatId ? hatBorderColor(patch.hatId) : 'border-l-gray-700';

          return (
            <div
              key={patch.id}
              className={`flex items-start gap-2 text-[11px] border-l-2 pl-2 ${borderClass}`}
            >
              <span className="text-gray-600 flex-shrink-0 font-mono">
                {new Date(patch.timestamp).toLocaleTimeString()}
              </span>
              <span className={`flex-shrink-0 ${KIND_COLORS[patch.kind] ?? 'text-gray-400'}`}>
                {patch.kind}
              </span>
              {hasHat && hatName && (
                <span className="text-gray-600 flex-shrink-0 text-[10px]">
                  [{hatName}]
                </span>
              )}
              <span className="text-gray-500 truncate">
                {patch.kind === 'conversation'
                  ? String(patch.delta.text ?? '').slice(0, 40)
                  : Object.keys(patch.delta).join(', ')}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

```
