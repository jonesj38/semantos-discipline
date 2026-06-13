---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/panels/ExtensionMarketplace.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.953391+00:00
---

# archive/apps-loom-react/src/panels/ExtensionMarketplace.tsx

```tsx
/**
 * ExtensionMarketplace — browse and install extensions from the registry.
 *
 * Consumer entry point for discovering extensions. Reads available manifests
 * from ConfigStore, renders trust signals, and opens BindingWizard for install.
 *
 * State: useExtension() for config, local useState for search/filter.
 * No separate state management.
 */

import { useState, useMemo, useCallback } from 'react';
import { useExtension } from '../config/ExtensionProvider';
import { useLoom } from '../state/LoomProvider';
import type { ExtensionManifest } from '../../../protocol-types/src/extension-manifest';
import { TrustSignalBar, DeprecationWarning } from './TrustSignals';

interface ExtensionMarketplaceProps {
  onInstall: (manifest: ExtensionManifest) => void;
  onSelect: (manifest: ExtensionManifest) => void;
}

/** Available extensions sourced from ConfigStore's known extension list. */
function useAvailableExtensions(): { extensions: ExtensionManifest[]; loading: boolean; error: string | null } {
  const { config, loading, error } = useExtension();

  const extensions = useMemo(() => {
    if (!config) return [];
    // Build manifest stubs from known bundled extensions.
    // In production, this would be overlay queries for all published manifests.
    const manifests: ExtensionManifest[] = [];

    // The config itself represents the active extension; build a manifest for it
    const activeManifest: ExtensionManifest = {
      id: config.id ?? 'core',
      name: config.name ?? 'Core',
      version: config.version ?? '1.0.0',
      taxonomyPath: 'taxonomy/core.json',
      flowsDir: 'flows',
      promptsDir: 'prompts',
      metadata: {
        description: config.description ?? 'Core extension',
        author: 'Semantos',
      },
    };
    manifests.push(activeManifest);

    return manifests;
  }, [config]);

  return { extensions, loading, error };
}

export function ExtensionMarketplace({ onInstall, onSelect }: ExtensionMarketplaceProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<string | null>(null);
  const { extensions, loading, error } = useAvailableExtensions();
  const { state } = useLoom();

  const filtered = useMemo(() => {
    let result = extensions;
    if (searchQuery) {
      const q = searchQuery.toLowerCase();
      result = result.filter(
        (m) =>
          m.name.toLowerCase().includes(q) ||
          m.id.toLowerCase().includes(q) ||
          m.metadata?.author?.toLowerCase().includes(q) ||
          m.metadata?.description?.toLowerCase().includes(q),
      );
    }
    if (categoryFilter) {
      result = result.filter((m) => m.taxonomyPath.includes(categoryFilter));
    }
    return result;
  }, [extensions, searchQuery, categoryFilter]);

  const categories = useMemo(() => {
    const cats = new Set<string>();
    for (const m of extensions) {
      if (m.grammar?.taxonomyNamespace) cats.add(m.grammar.taxonomyNamespace);
      else cats.add(m.taxonomyPath.split('/').slice(-1)[0]?.replace('.json', '') ?? 'other');
    }
    return [...cats].sort();
  }, [extensions]);

  const handleRetry = useCallback(() => {
    window.location.reload();
  }, []);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full text-gray-500 text-sm">
        Loading marketplace...
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-3 text-gray-500">
        <p className="text-sm">Unable to load marketplace</p>
        <p className="text-xs text-gray-600">{error}</p>
        <button
          onClick={handleRetry}
          className="px-3 py-1.5 text-xs bg-gray-800 hover:bg-gray-700 text-gray-300 rounded border border-gray-700"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-4 py-3 border-b border-gray-800">
        <h2 className="text-sm font-semibold text-gray-200 mb-2">Extension Marketplace</h2>
        <div className="flex items-center gap-2">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search extensions..."
            className="flex-1 px-3 py-1.5 text-xs bg-gray-800 border border-gray-700 rounded text-gray-300 placeholder-gray-600 focus:outline-none focus:border-gray-500"
          />
        </div>
        {categories.length > 1 && (
          <div className="flex items-center gap-1 mt-2 flex-wrap">
            <button
              onClick={() => setCategoryFilter(null)}
              className={`px-2 py-0.5 text-xs rounded ${!categoryFilter ? 'bg-blue-900/50 text-blue-300' : 'bg-gray-800 text-gray-500 hover:text-gray-300'}`}
            >
              All
            </button>
            {categories.map((cat) => (
              <button
                key={cat}
                onClick={() => setCategoryFilter(cat === categoryFilter ? null : cat)}
                className={`px-2 py-0.5 text-xs rounded ${cat === categoryFilter ? 'bg-blue-900/50 text-blue-300' : 'bg-gray-800 text-gray-500 hover:text-gray-300'}`}
              >
                {cat}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Extension Grid */}
      <div className="flex-1 overflow-y-auto p-4">
        {filtered.length === 0 ? (
          <div className="text-center text-sm text-gray-600 mt-8">
            {searchQuery ? 'No extensions match your search.' : 'No extensions available.'}
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3">
            {filtered.map((manifest) => (
              <ExtensionCard
                key={manifest.id}
                manifest={manifest}
                objectCount={state.objects.size}
                onInstall={() => onInstall(manifest)}
                onSelect={() => onSelect(manifest)}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Extension Card ──────────────────────────────────────────────

interface ExtensionCardProps {
  manifest: ExtensionManifest;
  objectCount: number;
  onInstall: () => void;
  onSelect: () => void;
}

function ExtensionCard({ manifest, objectCount, onInstall, onSelect }: ExtensionCardProps) {
  const isDeprecated = manifest.deprecationStatus?.isDeprecated;

  return (
    <div
      className="bg-gray-800 border border-gray-700 rounded-lg p-4 hover:border-gray-600 cursor-pointer transition-colors"
      onClick={onSelect}
    >
      <div className="flex items-start justify-between">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <h3 className="text-sm font-medium text-gray-200 truncate">{manifest.name}</h3>
            <span className="text-xs text-gray-500">v{manifest.version}</span>
          </div>
          {manifest.metadata?.author && (
            <p className="text-xs text-gray-500 mt-0.5">by {manifest.metadata.author}</p>
          )}
          {manifest.metadata?.description && (
            <p className="text-xs text-gray-400 mt-1 line-clamp-2">{manifest.metadata.description}</p>
          )}
        </div>
        <button
          onClick={(e) => {
            e.stopPropagation();
            onInstall();
          }}
          className={`ml-3 px-3 py-1.5 text-xs rounded font-medium ${
            isDeprecated
              ? 'bg-gray-700 text-gray-500 cursor-not-allowed'
              : 'bg-blue-800 hover:bg-blue-700 text-blue-200'
          }`}
          disabled={isDeprecated}
        >
          Install
        </button>
      </div>

      {isDeprecated && (
        <div className="mt-2">
          <DeprecationWarning
            sunsetDate={manifest.deprecationStatus?.sunsetDate}
            replacementId={manifest.deprecationStatus?.replacementExtensionId}
          />
        </div>
      )}

      <TrustSignalBar
        manifest={manifest}
        reputationScore={manifest.grammar?.author?.certId ? 50 : 25}
        objectCount={objectCount}
      />

      {manifest.grammar && (
        <div className="flex items-center gap-3 mt-2 text-xs text-gray-500">
          <span>{manifest.grammar.objectTypes.length} object types</span>
          <span>{manifest.grammar.source.entities.length} entities</span>
          <span>{manifest.grammar.capabilities.length} capabilities</span>
        </div>
      )}
    </div>
  );
}

```
