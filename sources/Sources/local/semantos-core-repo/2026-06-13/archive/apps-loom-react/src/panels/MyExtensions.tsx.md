---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/panels/MyExtensions.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.952506+00:00
---

# archive/apps-loom-react/src/panels/MyExtensions.tsx

```tsx
/**
 * MyExtensions — installed extensions and their status.
 *
 * Lists ConsumerBindings from LoomStore, shows extraction metrics,
 * status badges, and provides update/remove/run actions.
 *
 * State: useLoom() for bindings, useExtension() for config.
 */

import { useState, useMemo, useCallback } from 'react';
import { useLoom } from '../state/LoomProvider';
import { useExtension } from '../config/ExtensionProvider';
import type { GovernedConsumerBinding, GovernedConsumerBindingPayload, CompatibilityResult } from '../../../protocol-types/src/governance';
import type { ExtensionManifest } from '../../../protocol-types/src/extension-manifest';
import type { LoomObject } from '../types/loom';
import { checkCompatibility } from '../../../extraction/src/governance/version-compat';
import { TrustSignalBar, CompatibilityBadge } from './TrustSignals';

interface MyExtensionsProps {
  onConfigure: (bindingId: string) => void;
  onSelectExtension: (manifestId: string) => void;
}

/** Extract ConsumerBinding objects from loom state. */
function useBindings(): { bindings: Array<{ object: LoomObject; payload: GovernedConsumerBindingPayload }>; manifests: Map<string, ExtensionManifest> } {
  const { state } = useLoom();
  const { config } = useExtension();

  return useMemo(() => {
    const bindings: Array<{ object: LoomObject; payload: GovernedConsumerBindingPayload }> = [];
    const manifests = new Map<string, ExtensionManifest>();

    for (const obj of state.objects.values()) {
      if (obj.typeDefinition.name === 'ConsumerBinding' ||
          obj.typeDefinition.category === 'extension' ||
          (obj.payload as Record<string, unknown>)?.extensionManifestId) {
        const payload = obj.payload as unknown as GovernedConsumerBindingPayload;
        if (payload.extensionManifestId) {
          bindings.push({ object: obj, payload });
        }
      }
    }

    // Build manifest lookup from config
    if (config) {
      const manifest: ExtensionManifest = {
        id: config.id ?? 'core',
        name: config.name ?? 'Core',
        version: config.version ?? '1.0.0',
        taxonomyPath: 'taxonomy/core.json',
        flowsDir: 'flows',
        promptsDir: 'prompts',
        metadata: { author: 'Semantos', description: config.description },
      };
      manifests.set(manifest.id, manifest);
    }

    return { bindings, manifests };
  }, [state.objects, config]);
}

export function MyExtensions({ onConfigure, onSelectExtension }: MyExtensionsProps) {
  const { bindings, manifests } = useBindings();
  const { dispatch } = useLoom();
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [runningExtraction, setRunningExtraction] = useState<string | null>(null);

  const handleRemove = useCallback(
    (bindingId: string) => {
      if (confirm('Remove this binding? Objects created by this extension will remain.')) {
        dispatch({ type: 'DELETE_OBJECT', id: bindingId });
      }
    },
    [dispatch],
  );

  const handleRunExtraction = useCallback(
    (bindingId: string) => {
      setRunningExtraction(bindingId);
      // Extraction runs via the pipeline — stub progress here
      setTimeout(() => setRunningExtraction(null), 2000);
    },
    [],
  );

  if (bindings.length === 0) {
    return (
      <div className="flex flex-col h-full">
        <div className="px-4 py-3 border-b border-gray-800">
          <h2 className="text-sm font-semibold text-gray-200">My Extensions</h2>
        </div>
        <div className="flex-1 flex items-center justify-center text-gray-500 text-sm">
          No extensions installed. Visit the Marketplace to install one.
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      <div className="px-4 py-3 border-b border-gray-800">
        <h2 className="text-sm font-semibold text-gray-200">My Extensions</h2>
        <p className="text-xs text-gray-500 mt-0.5">{bindings.length} installed</p>
      </div>

      <div className="flex-1 overflow-y-auto">
        {bindings.map(({ object, payload }) => {
          const manifest = manifests.get(payload.extensionManifestId);
          const isExpanded = expandedId === object.id;
          const isRunning = runningExtraction === object.id;

          return (
            <div key={object.id} className="border-b border-gray-800">
              {/* Row */}
              <div
                className="px-4 py-3 hover:bg-gray-800/50 cursor-pointer flex items-center gap-3"
                onClick={() => setExpandedId(isExpanded ? null : object.id)}
              >
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-gray-200 font-medium truncate">
                      {manifest?.name ?? payload.extensionManifestId}
                    </span>
                    <span className="text-xs text-gray-500">
                      {payload.grammarVersionPinned}
                    </span>
                    <StatusBadge status={payload.status} />
                  </div>
                  <div className="flex items-center gap-3 mt-1 text-xs text-gray-500">
                    {payload.lastExtractionTimestamp && (
                      <span>Last run: {formatRelativeTime(payload.lastExtractionTimestamp)}</span>
                    )}
                    <span>
                      {payload.autoUpdateGrammar ? 'Auto-update' : `Pinned: ${payload.grammarVersionPinned}`}
                    </span>
                    {payload.credentialsEncrypted && (
                      <span>{payload.credentialsEncrypted.credentialFieldNames.length} credentials</span>
                    )}
                  </div>
                </div>

                {/* Actions */}
                <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
                  <button
                    onClick={() => handleRunExtraction(object.id)}
                    className="px-2 py-1 text-xs bg-gray-800 hover:bg-gray-700 text-gray-400 rounded border border-gray-700"
                    disabled={isRunning}
                  >
                    {isRunning ? 'Running...' : 'Run'}
                  </button>
                  <button
                    onClick={() => onConfigure(object.id)}
                    className="px-2 py-1 text-xs bg-gray-800 hover:bg-gray-700 text-gray-400 rounded border border-gray-700"
                  >
                    Configure
                  </button>
                  <button
                    onClick={() => handleRemove(object.id)}
                    className="px-2 py-1 text-xs bg-gray-800 hover:bg-red-900/50 text-gray-400 hover:text-red-300 rounded border border-gray-700"
                  >
                    Remove
                  </button>
                </div>
              </div>

              {/* Expanded Detail */}
              {isExpanded && (
                <BindingDetail
                  payload={payload}
                  manifest={manifest}
                  onViewDetail={() => onSelectExtension(payload.extensionManifestId)}
                />
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ── Sub-components ──────────────────────────────────────────────

function StatusBadge({ status }: { status: GovernedConsumerBindingPayload['status'] }) {
  const styles = {
    active: 'bg-green-900/40 text-green-400',
    paused: 'bg-yellow-900/40 text-yellow-400',
    deprecated: 'bg-red-900/40 text-red-400',
  };

  return (
    <span className={`px-1.5 py-0.5 text-xs rounded ${styles[status]}`}>
      {status}
    </span>
  );
}

interface BindingDetailProps {
  payload: GovernedConsumerBindingPayload;
  manifest?: ExtensionManifest;
  onViewDetail: () => void;
}

function BindingDetail({ payload, manifest, onViewDetail }: BindingDetailProps) {
  return (
    <div className="px-4 py-3 bg-gray-850 border-t border-gray-800/50">
      <div className="grid grid-cols-2 gap-4 text-xs">
        <div>
          <h4 className="text-gray-400 font-medium mb-1">Binding Configuration</h4>
          <dl className="space-y-1">
            <div className="flex gap-2">
              <dt className="text-gray-500">Version pin:</dt>
              <dd className="text-gray-300">{payload.grammarVersionPinned}</dd>
            </div>
            <div className="flex gap-2">
              <dt className="text-gray-500">Auto-update:</dt>
              <dd className="text-gray-300">{payload.autoUpdateGrammar ? 'Yes' : 'No'}</dd>
            </div>
            <div className="flex gap-2">
              <dt className="text-gray-500">Credentials:</dt>
              <dd className="text-gray-300">
                {payload.credentialsEncrypted?.credentialFieldNames.join(', ') ?? 'None'}
              </dd>
            </div>
            {payload.fieldOverrides && payload.fieldOverrides.length > 0 && (
              <div className="flex gap-2">
                <dt className="text-gray-500">Field overrides:</dt>
                <dd className="text-gray-300">{payload.fieldOverrides.length} override(s)</dd>
              </div>
            )}
            {payload.taxonomyOverrides && payload.taxonomyOverrides.length > 0 && (
              <div className="flex gap-2">
                <dt className="text-gray-500">Taxonomy overrides:</dt>
                <dd className="text-gray-300">{payload.taxonomyOverrides.length} override(s)</dd>
              </div>
            )}
          </dl>
        </div>

        <div>
          <h4 className="text-gray-400 font-medium mb-1">Grammar Summary</h4>
          {manifest?.grammar ? (
            <dl className="space-y-1">
              <div className="flex gap-2">
                <dt className="text-gray-500">Object types:</dt>
                <dd className="text-gray-300">{manifest.grammar.objectTypes.length}</dd>
              </div>
              <div className="flex gap-2">
                <dt className="text-gray-500">Source entities:</dt>
                <dd className="text-gray-300">{manifest.grammar.source.entities.length}</dd>
              </div>
              <div className="flex gap-2">
                <dt className="text-gray-500">Capabilities:</dt>
                <dd className="text-gray-300">{manifest.grammar.capabilities.length}</dd>
              </div>
              <div className="flex gap-2">
                <dt className="text-gray-500">Namespace:</dt>
                <dd className="text-gray-300">{manifest.grammar.taxonomyNamespace}</dd>
              </div>
            </dl>
          ) : (
            <p className="text-gray-500">No grammar attached</p>
          )}
        </div>
      </div>

      {manifest && (
        <div className="mt-3">
          <TrustSignalBar manifest={manifest} />
        </div>
      )}

      <button
        onClick={onViewDetail}
        className="mt-3 px-3 py-1.5 text-xs bg-gray-800 hover:bg-gray-700 text-gray-400 rounded border border-gray-700"
      >
        View Extension Detail
      </button>
    </div>
  );
}

// ── Helpers ─────────────────────────────────────────────────────

function formatRelativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diff / 60_000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

```
