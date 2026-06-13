---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/panels/ExtensionDetail.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.951611+00:00
---

# archive/apps-loom-react/src/panels/ExtensionDetail.tsx

```tsx
/**
 * ExtensionDetail — deep dive into a single extension.
 *
 * Inspector-style panel showing grammar, entity diagram, field mappings,
 * extraction history, evidence chain, version timeline, and contributors.
 *
 * Grammar is always rendered interactively (tables, diagrams). Never raw JSON.
 */

import { useState, useMemo } from 'react';
import type { ExtensionManifest } from '../../../protocol-types/src/extension-manifest';
import type { ExtensionGrammar, MigrationRule } from '../../../protocol-types/src/extension-grammar';
import type { GovernedConsumerBindingPayload } from '../../../protocol-types/src/governance';
import type { LoomObject } from '../types/loom';
import { useLoom } from '../state/LoomProvider';
import { GrammarInspector } from './GrammarInspector';
import { FieldMappingTable } from './FieldMappingTable';
import { EntityDiagram } from './EntityDiagram';
import { TrustSignalBar, DeprecationWarning } from './TrustSignals';

interface ExtensionDetailProps {
  manifest: ExtensionManifest;
  onClose: () => void;
}

type DetailTab = 'grammar' | 'diagram' | 'mappings' | 'history' | 'evidence' | 'versions' | 'contributors';

export function ExtensionDetail({ manifest, onClose }: ExtensionDetailProps) {
  const [activeTab, setActiveTab] = useState<DetailTab>('grammar');
  const { state } = useLoom();

  const grammar = manifest.grammar;

  const tabs: Array<{ id: DetailTab; label: string; visible: boolean }> = [
    { id: 'grammar', label: 'Grammar', visible: !!grammar },
    { id: 'diagram', label: 'Entity Diagram', visible: !!grammar && grammar.source.entities.length > 0 },
    { id: 'mappings', label: 'Field Mappings', visible: !!grammar && grammar.entityMappings.length > 0 },
    { id: 'history', label: 'Extraction History', visible: true },
    { id: 'evidence', label: 'Evidence Chain', visible: true },
    { id: 'versions', label: 'Versions', visible: true },
    { id: 'contributors', label: 'Contributors', visible: !!manifest.governanceConfig },
  ];

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-4 py-3 border-b border-gray-800">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-sm font-semibold text-gray-200">{manifest.name}</h2>
            <p className="text-xs text-gray-500">v{manifest.version} by {manifest.metadata?.author ?? 'Unknown'}</p>
          </div>
          <button
            onClick={onClose}
            className="text-gray-500 hover:text-white text-sm px-2"
          >
            &times;
          </button>
        </div>

        {manifest.metadata?.description && (
          <p className="text-xs text-gray-400 mt-1">{manifest.metadata.description}</p>
        )}

        {manifest.deprecationStatus?.isDeprecated && (
          <div className="mt-2">
            <DeprecationWarning
              sunsetDate={manifest.deprecationStatus.sunsetDate}
              replacementId={manifest.deprecationStatus.replacementExtensionId}
            />
          </div>
        )}

        <TrustSignalBar manifest={manifest} />

        <div className="flex items-center gap-1 mt-3 flex-wrap">
          {tabs.filter(t => t.visible).map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-2 py-0.5 text-xs rounded ${
                activeTab === tab.id
                  ? 'bg-blue-900/50 text-blue-300'
                  : 'text-gray-500 hover:text-gray-300 hover:bg-gray-800'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        {activeTab === 'grammar' && grammar && <GrammarInspector grammar={grammar} />}
        {activeTab === 'diagram' && grammar && (
          <EntityDiagram entities={grammar.source.entities} />
        )}
        {activeTab === 'mappings' && grammar && (
          <FieldMappingTable mappings={grammar.entityMappings} />
        )}
        {activeTab === 'history' && <ExtractionHistory manifestId={manifest.id} />}
        {activeTab === 'evidence' && <EvidenceChainView manifestId={manifest.id} />}
        {activeTab === 'versions' && <VersionTimeline manifest={manifest} />}
        {activeTab === 'contributors' && <ContributorList manifest={manifest} />}
        {!grammar && activeTab === 'grammar' && (
          <p className="text-xs text-gray-500">No grammar attached to this extension.</p>
        )}
      </div>
    </div>
  );
}

// ── Extraction History ──────────────────────────────────────────

function ExtractionHistory({ manifestId }: { manifestId: string }) {
  const { state } = useLoom();
  const [dateFilter, setDateFilter] = useState<'all' | '24h' | '7d' | '30d'>('all');

  // Extract extraction-related patches from objects created by this extension
  const runs = useMemo(() => {
    const result: Array<{
      timestamp: number;
      objectsCreated: number;
      objectsUpdated: number;
      errors: number;
      status: 'success' | 'partial' | 'failed';
    }> = [];

    // Group extraction patches by timestamp window
    const extractionPatches: Array<{ timestamp: number; kind: string; delta: Record<string, unknown> }> = [];
    for (const obj of state.objects.values()) {
      for (const patch of obj.patches) {
        if (patch.kind === 'extraction') {
          extractionPatches.push({ timestamp: patch.timestamp, kind: patch.kind, delta: patch.delta });
        }
      }
    }

    // Group by minute
    const groups = new Map<number, typeof extractionPatches>();
    for (const p of extractionPatches) {
      const minute = Math.floor(p.timestamp / 60000) * 60000;
      const group = groups.get(minute) ?? [];
      group.push(p);
      groups.set(minute, group);
    }

    for (const [ts, patches] of groups) {
      const errors = patches.filter(p => p.delta.error).length;
      result.push({
        timestamp: ts,
        objectsCreated: patches.length,
        objectsUpdated: 0,
        errors,
        status: errors === patches.length ? 'failed' : errors > 0 ? 'partial' : 'success',
      });
    }

    // Apply date filter
    const now = Date.now();
    const cutoffs = { all: 0, '24h': now - 86400000, '7d': now - 604800000, '30d': now - 2592000000 };
    const cutoff = cutoffs[dateFilter];
    return result.filter(r => r.timestamp >= cutoff).sort((a, b) => b.timestamp - a.timestamp);
  }, [state.objects, dateFilter]);

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-1">
        {(['all', '24h', '7d', '30d'] as const).map((filter) => (
          <button
            key={filter}
            onClick={() => setDateFilter(filter)}
            className={`px-2 py-0.5 text-xs rounded ${
              dateFilter === filter ? 'bg-blue-900/50 text-blue-300' : 'text-gray-500 hover:text-gray-300'
            }`}
          >
            {filter === 'all' ? 'All' : `Last ${filter}`}
          </button>
        ))}
      </div>

      {runs.length === 0 ? (
        <p className="text-xs text-gray-500">No extraction runs recorded.</p>
      ) : (
        <div className="space-y-2">
          {runs.map((run, i) => (
            <div key={i} className="bg-gray-800 border border-gray-700 rounded px-3 py-2 text-xs">
              <div className="flex items-center justify-between">
                <span className="text-gray-300">{new Date(run.timestamp).toLocaleString()}</span>
                <span className={`px-1.5 py-0.5 rounded ${
                  run.status === 'success' ? 'bg-green-900/40 text-green-400' :
                  run.status === 'partial' ? 'bg-yellow-900/40 text-yellow-400' :
                  'bg-red-900/40 text-red-400'
                }`}>
                  {run.status}
                </span>
              </div>
              <div className="flex gap-3 mt-1 text-gray-500">
                <span>{run.objectsCreated} created</span>
                <span>{run.objectsUpdated} updated</span>
                {run.errors > 0 && <span className="text-red-400">{run.errors} errors</span>}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Evidence Chain View ─────────────────────────────────────────

function EvidenceChainView({ manifestId }: { manifestId: string }) {
  const { state } = useLoom();
  const [typeFilter, setTypeFilter] = useState<string | null>(null);

  const entries = useMemo(() => {
    const result: Array<{
      objectId: string;
      objectType: string;
      patches: Array<{ id: string; kind: string; timestamp: number; delta: Record<string, unknown> }>;
    }> = [];

    for (const obj of state.objects.values()) {
      if (obj.patches.length > 0) {
        const typeName = obj.typeDefinition.name;
        if (typeFilter && typeName !== typeFilter) continue;

        result.push({
          objectId: obj.id,
          objectType: typeName,
          patches: obj.patches.map(p => ({
            id: p.id,
            kind: p.kind,
            timestamp: p.timestamp,
            delta: p.delta,
          })),
        });
      }
    }

    return result.slice(0, 50); // Limit display
  }, [state.objects, typeFilter]);

  const objectTypes = useMemo(() => {
    const types = new Set<string>();
    for (const obj of state.objects.values()) {
      types.add(obj.typeDefinition.name);
    }
    return [...types].sort();
  }, [state.objects]);

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2">
        <span className="text-xs text-gray-500">Filter by type:</span>
        <select
          className="px-2 py-0.5 text-xs bg-gray-800 border border-gray-700 rounded text-gray-300"
          value={typeFilter ?? ''}
          onChange={(e) => setTypeFilter(e.target.value || null)}
        >
          <option value="">All types</option>
          {objectTypes.map((t) => (
            <option key={t} value={t}>{t}</option>
          ))}
        </select>
      </div>

      {entries.length === 0 ? (
        <p className="text-xs text-gray-500">No evidence entries found.</p>
      ) : (
        <div className="space-y-2">
          {entries.map((entry) => (
            <div key={entry.objectId} className="bg-gray-800 border border-gray-700 rounded px-3 py-2 text-xs">
              <div className="flex items-center gap-2">
                <span className="text-gray-300 font-mono">{entry.objectId.slice(0, 12)}...</span>
                <span className="text-gray-500">{entry.objectType}</span>
                <span className="text-gray-600">{entry.patches.length} patches</span>
              </div>
              <div className="ml-3 mt-1 space-y-0.5">
                {entry.patches.slice(0, 3).map((p) => (
                  <div key={p.id} className="flex gap-2 text-gray-500">
                    <span>{p.kind}</span>
                    <span>{new Date(p.timestamp).toLocaleString()}</span>
                  </div>
                ))}
                {entry.patches.length > 3 && (
                  <span className="text-gray-600">+{entry.patches.length - 3} more</span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Version Timeline ────────────────────────────────────────────

function VersionTimeline({ manifest }: { manifest: ExtensionManifest }) {
  const migrations = manifest.grammar?.migrations ?? [];
  const [selectedVersion, setSelectedVersion] = useState<string | null>(null);

  // Build version history from migrations
  const versions = useMemo(() => {
    const versionSet = new Set<string>();
    versionSet.add(manifest.version);
    for (const m of migrations) {
      versionSet.add(m.fromVersion);
      versionSet.add(m.toVersion);
    }
    return [...versionSet].sort((a, b) => compareVersions(a, b));
  }, [manifest, migrations]);

  return (
    <div className="space-y-3">
      {versions.length <= 1 && migrations.length === 0 ? (
        <p className="text-xs text-gray-500">Only one version published (v{manifest.version}).</p>
      ) : (
        <div className="space-y-1">
          {versions.map((version) => {
            const migration = migrations.find(m => m.toVersion === version);
            const isCurrent = version === manifest.version;
            const isSelected = version === selectedVersion;

            return (
              <div
                key={version}
                className={`px-3 py-2 rounded border cursor-pointer ${
                  isSelected ? 'bg-gray-750 border-blue-700' :
                  isCurrent ? 'bg-gray-800 border-green-800/50' :
                  'bg-gray-800 border-gray-700 hover:border-gray-600'
                }`}
                onClick={() => setSelectedVersion(isSelected ? null : version)}
              >
                <div className="flex items-center justify-between text-xs">
                  <div className="flex items-center gap-2">
                    <span className="text-gray-200 font-medium">v{version}</span>
                    {isCurrent && (
                      <span className="px-1.5 py-0.5 bg-green-900/40 text-green-400 rounded">current</span>
                    )}
                  </div>
                  {migration?.breakingChanges && (
                    <span className="text-red-400">breaking</span>
                  )}
                </div>

                {isSelected && migration && (
                  <MigrationDetail migration={migration} />
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function MigrationDetail({ migration }: { migration: MigrationRule }) {
  return (
    <div className="mt-2 text-xs space-y-1 border-t border-gray-700 pt-2">
      <p className="text-gray-500">
        Migration from v{migration.fromVersion} to v{migration.toVersion}
      </p>

      {migration.fieldRenames && Object.keys(migration.fieldRenames).length > 0 && (
        <div>
          <span className="text-gray-400">Field renames: </span>
          {Object.entries(migration.fieldRenames).map(([from, to]) => (
            <span key={from} className="text-gray-300 font-mono">
              {from} \u2192 {to}{' '}
            </span>
          ))}
        </div>
      )}

      {migration.fieldsRemoved && migration.fieldsRemoved.length > 0 && (
        <div>
          <span className="text-red-400">Removed: </span>
          <span className="text-gray-300 font-mono">{migration.fieldsRemoved.join(', ')}</span>
        </div>
      )}

      {migration.fieldsAdded && Object.keys(migration.fieldsAdded).length > 0 && (
        <div>
          <span className="text-green-400">Added: </span>
          <span className="text-gray-300 font-mono">{Object.keys(migration.fieldsAdded).join(', ')}</span>
        </div>
      )}

      {migration.breakingChanges && (
        <p className="text-yellow-400">{migration.breakingChanges}</p>
      )}
    </div>
  );
}

// ── Contributor List ────────────────────────────────────────────

function ContributorList({ manifest }: { manifest: ExtensionManifest }) {
  const gov = manifest.governanceConfig;

  if (!gov) {
    return <p className="text-xs text-gray-500">No governance configuration.</p>;
  }

  return (
    <div className="space-y-3">
      <div className="text-xs text-gray-500">
        Patch acceptance: {gov.patchAcceptancePolicy.replace(/_/g, ' ')}
      </div>

      {gov.contributorHats.length === 0 ? (
        <p className="text-xs text-gray-500">No contributors. This extension is author-only.</p>
      ) : (
        <table className="w-full text-xs">
          <thead>
            <tr className="text-gray-500 border-b border-gray-800">
              <th className="py-1 text-left font-medium">Hat ID</th>
            </tr>
          </thead>
          <tbody>
            {gov.contributorHats.map((facetId) => (
              <tr key={facetId} className="border-b border-gray-800/50">
                <td className="py-1 text-gray-300 font-mono">{facetId}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

// ── Helpers ─────────────────────────────────────────────────────

function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    const diff = (pa[i] || 0) - (pb[i] || 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

```
