---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/shell/StatusBar.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.968640+00:00
---

# archive/apps-loom-react/src/shell/StatusBar.tsx

```tsx
import { useMemo } from 'react';
import { useEngineContext } from '../engine/EngineProvider';
import { useExtension } from '../config/ExtensionProvider';
import { useIdentity } from '../identity/IdentityProvider';
import { useLoom } from '../state/LoomProvider';
import { FacetSelector } from '../identity/FacetSelector';
import { computeReputation, DEFAULT_REPUTATION_WEIGHTS } from '../services/ReputationComputer';

export function StatusBar() {
  const { isReady, profile, error } = useEngineContext();
  const { config, loading: extensionLoading, activeExtensionId } = useExtension();
  const { identity, activeHat } = useIdentity();
  const { state } = useLoom();

  const engineStatus = error
    ? 'Error'
    : isReady
      ? 'Ready'
      : 'Loading';

  const statusColor = error
    ? 'text-red-400'
    : isReady
      ? 'text-green-400'
      : 'text-yellow-400';

  const objectCount = config?.objectTypes.length ?? 0;

  // Compute reputation from identity's patches across all objects
  const reputation = useMemo(() => {
    if (!identity || !activeHat) return null;
    // Collect all patches authored by any of the identity's facets
    const facetIds = new Set(identity.hats.map(f => f.id));
    const identityPatches = [];
    for (const obj of state.objects.values()) {
      for (const p of obj.patches) {
        if (p.facetId && facetIds.has(p.facetId)) {
          identityPatches.push(p);
        }
      }
    }
    return computeReputation(identityPatches, state.objects, DEFAULT_REPUTATION_WEIGHTS);
  }, [identity, activeHat, state.objects]);

  const reputationColor = reputation
    ? reputation.total >= 70
      ? 'text-green-400'
      : reputation.total >= 40
        ? 'text-yellow-400'
        : 'text-red-400'
    : 'text-gray-500';

  return (
    <div className="h-6 bg-gray-900 border-t border-gray-800 flex items-center px-3 gap-4 text-xs flex-shrink-0">
      <span className={statusColor}>
        {engineStatus}
      </span>
      <span className="text-gray-500">|</span>
      <span className="text-gray-400">{profile}</span>
      <span className="text-gray-500">|</span>
      <FacetSelector />
      <span className="text-gray-500">|</span>
      <span className="text-gray-400">
        {extensionLoading ? 'loading...' : (config?.name ?? activeExtensionId)}
      </span>
      <span className="text-gray-500">|</span>
      <span className="text-gray-400">{objectCount} types</span>
      {reputation !== null && (
        <>
          <span className="text-gray-500">|</span>
          <span className={reputationColor} title={`Base: ${reputation.base} | Activity: ${reputation.activity} | Disputes: ${reputation.disputeOutcomes} | Contributions: ${reputation.contributions}`}>
            Rep: {reputation.total}
          </span>
        </>
      )}
      {error && (
        <>
          <span className="text-gray-500">|</span>
          <span className="text-red-400 truncate" title={error}>{error}</span>
        </>
      )}
    </div>
  );
}

```
