---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/panels/GrammarInspector.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.953103+00:00
---

# archive/apps-loom-react/src/panels/GrammarInspector.tsx

```tsx
/**
 * GrammarInspector — interactive structured view of an ExtensionGrammar.
 *
 * Renders grammar as tables, lists, and structured UI. NEVER raw JSON.
 * Shows object types, capabilities, source entities, and taxonomy namespace.
 */

import { useState } from 'react';
import type { ExtensionGrammar, ObjectTypeDeclaration, CapabilityRequirement, SourceEntity } from '../../../protocol-types/src/extension-grammar';

interface GrammarInspectorProps {
  grammar: ExtensionGrammar;
}

type Section = 'overview' | 'object-types' | 'capabilities' | 'source' | 'taxonomy';

export function GrammarInspector({ grammar }: GrammarInspectorProps) {
  const [activeSection, setActiveSection] = useState<Section>('overview');

  const sections: Array<{ id: Section; label: string }> = [
    { id: 'overview', label: 'Overview' },
    { id: 'object-types', label: 'Object Types' },
    { id: 'capabilities', label: 'Capabilities' },
    { id: 'source', label: 'Source System' },
    { id: 'taxonomy', label: 'Taxonomy' },
  ];

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-1 flex-wrap">
        {sections.map((s) => (
          <button
            key={s.id}
            onClick={() => setActiveSection(s.id)}
            className={`px-2 py-0.5 text-xs rounded ${
              activeSection === s.id
                ? 'bg-blue-900/50 text-blue-300'
                : 'text-gray-500 hover:text-gray-300 hover:bg-gray-800'
            }`}
          >
            {s.label}
          </button>
        ))}
      </div>

      {activeSection === 'overview' && <OverviewSection grammar={grammar} />}
      {activeSection === 'object-types' && <ObjectTypesSection types={grammar.objectTypes} />}
      {activeSection === 'capabilities' && <CapabilitiesSection capabilities={grammar.capabilities} />}
      {activeSection === 'source' && <SourceSection grammar={grammar} />}
      {activeSection === 'taxonomy' && <TaxonomySection grammar={grammar} />}
    </div>
  );
}

// ── Sections ────────────────────────────────────────────────────

function OverviewSection({ grammar }: { grammar: ExtensionGrammar }) {
  return (
    <div className="space-y-3">
      <table className="w-full text-xs">
        <tbody>
          <Row label="Grammar ID" value={grammar.grammarId} mono />
          <Row label="Version" value={grammar.grammarVersion} />
          <Row label="Display Name" value={grammar.displayName} />
          <Row label="Meta-schema" value={grammar.metaSchemaVersion} />
          <Row label="Author" value={`${grammar.author.name} (${grammar.author.certId})`} />
          <Row label="Protocol" value={grammar.source.protocol} />
          <Row label="Auth Type" value={grammar.source.auth.type} />
          <Row label="Namespace" value={grammar.taxonomyNamespace} />
          <Row label="Object Types" value={String(grammar.objectTypes.length)} />
          <Row label="Entity Mappings" value={String(grammar.entityMappings.length)} />
          <Row label="Source Entities" value={String(grammar.source.entities.length)} />
        </tbody>
      </table>

      {grammar.description && (
        <p className="text-xs text-gray-400">{grammar.description}</p>
      )}
    </div>
  );
}

function ObjectTypesSection({ types }: { types: ObjectTypeDeclaration[] }) {
  const [expandedType, setExpandedType] = useState<string | null>(null);

  return (
    <div className="space-y-2">
      {types.map((ot) => (
        <div key={ot.typePath} className="bg-gray-800 border border-gray-700 rounded">
          <div
            className="px-3 py-2 cursor-pointer hover:bg-gray-750 flex items-center justify-between"
            onClick={() => setExpandedType(expandedType === ot.typePath ? null : ot.typePath)}
          >
            <div>
              <span className="text-xs text-gray-200 font-medium">{ot.displayName}</span>
              <span className="text-xs text-gray-500 ml-2 font-mono">{ot.typePath}</span>
            </div>
            <div className="flex items-center gap-2 text-xs">
              <span className="text-gray-500">{ot.linearity}</span>
              <span className="text-gray-600">
                {Object.keys(ot.payloadSchema).length} fields
              </span>
            </div>
          </div>

          {expandedType === ot.typePath && (
            <div className="px-3 py-2 border-t border-gray-700 text-xs space-y-2">
              <p className="text-gray-400">{ot.description}</p>

              <div>
                <h5 className="text-gray-500 font-medium mb-1">Payload Schema</h5>
                <table className="w-full">
                  <thead>
                    <tr className="text-gray-600">
                      <th className="py-0.5 text-left font-medium">Field</th>
                      <th className="py-0.5 text-left font-medium">Type</th>
                      <th className="py-0.5 text-left font-medium">Description</th>
                    </tr>
                  </thead>
                  <tbody>
                    {Object.entries(ot.payloadSchema).map(([name, field]) => (
                      <tr key={name} className="border-t border-gray-800/50">
                        <td className="py-0.5 text-gray-300 font-mono">{name}</td>
                        <td className="py-0.5 text-gray-500">{field.type}</td>
                        <td className="py-0.5 text-gray-600">{field.description ?? ''}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div>
                <h5 className="text-gray-500 font-medium mb-1">Phases</h5>
                <div className="flex items-center gap-1">
                  {ot.phases.map((phase) => (
                    <span
                      key={phase}
                      className={`px-1.5 py-0.5 rounded ${
                        phase === ot.initialPhase ? 'bg-green-900/40 text-green-400' : 'bg-gray-700 text-gray-400'
                      }`}
                    >
                      {phase}{phase === ot.initialPhase ? ' (initial)' : ''}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

function CapabilitiesSection({ capabilities }: { capabilities: CapabilityRequirement[] }) {
  return (
    <div className="space-y-1">
      {capabilities.length === 0 ? (
        <p className="text-xs text-gray-500">No capabilities required.</p>
      ) : (
        capabilities.map((cap) => (
          <div
            key={cap.capability}
            className="flex items-center gap-2 px-3 py-1.5 bg-gray-800 rounded text-xs"
          >
            <span className={cap.required ? 'text-yellow-400' : 'text-gray-500'}>
              {cap.required ? '\u25CF' : '\u25CB'}
            </span>
            <span className="text-gray-300 font-mono">{cap.capability}</span>
            <span className="text-gray-500">{cap.reason}</span>
            {cap.required && <span className="text-yellow-400 text-xs">required</span>}
          </div>
        ))
      )}
    </div>
  );
}

function SourceSection({ grammar }: { grammar: ExtensionGrammar }) {
  const source = grammar.source;

  return (
    <div className="space-y-3">
      <table className="w-full text-xs">
        <tbody>
          <Row label="Protocol" value={source.protocol} />
          <Row label="Base URL" value={source.baseUrlTemplate} mono />
          <Row label="Auth Type" value={source.auth.type} />
          <Row
            label="Required Credentials"
            value={source.auth.requiredCredentials.join(', ') || 'None'}
          />
          {source.pagination && (
            <Row label="Pagination" value={`${source.pagination.type}, page size ${source.pagination.pageSize}`} />
          )}
          {source.rateLimits && (
            <Row
              label="Rate Limits"
              value={[
                source.rateLimits.requestsPerSecond && `${source.rateLimits.requestsPerSecond}/s`,
                source.rateLimits.requestsPerMinute && `${source.rateLimits.requestsPerMinute}/min`,
              ]
                .filter(Boolean)
                .join(', ') || 'None'}
            />
          )}
        </tbody>
      </table>

      <h4 className="text-xs text-gray-400 font-medium mt-2">Source Entities</h4>
      <div className="space-y-1">
        {source.entities.map((entity) => (
          <EntityRow key={entity.entityId} entity={entity} />
        ))}
      </div>
    </div>
  );
}

function EntityRow({ entity }: { entity: SourceEntity }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="bg-gray-800 border border-gray-700 rounded">
      <div
        className="px-3 py-1.5 cursor-pointer hover:bg-gray-750 flex items-center justify-between text-xs"
        onClick={() => setExpanded(!expanded)}
      >
        <span className="text-gray-200">{entity.displayName}</span>
        <span className="text-gray-500">{entity.fields.length} fields</span>
      </div>
      {expanded && (
        <div className="px-3 py-2 border-t border-gray-700 text-xs space-y-1">
          <div className="flex gap-2 text-gray-500">
            <span>List: {entity.endpoint.list}</span>
            <span>Get: {entity.endpoint.get}</span>
          </div>
          <table className="w-full mt-1">
            <tbody>
              {entity.fields.map((f) => (
                <tr key={f.sourceFieldName} className="border-t border-gray-800/50">
                  <td className="py-0.5 text-gray-300 font-mono">{f.sourceFieldName}</td>
                  <td className="py-0.5 text-gray-500">{f.sourceType}</td>
                  <td className="py-0.5">
                    {f.required && <span className="text-yellow-400">required</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function TaxonomySection({ grammar }: { grammar: ExtensionGrammar }) {
  return (
    <div className="space-y-3">
      <table className="w-full text-xs">
        <tbody>
          <Row label="Namespace" value={grammar.taxonomyNamespace} mono />
        </tbody>
      </table>

      {grammar.taxonomyExtensions && grammar.taxonomyExtensions.length > 0 && (
        <>
          <h4 className="text-xs text-gray-400 font-medium">Taxonomy Extensions</h4>
          {grammar.taxonomyExtensions.map((ext, i) => (
            <div key={i} className="text-xs space-y-0.5">
              <div className="flex gap-2">
                <span className="text-gray-500">Axis:</span>
                <span className="text-gray-300">{ext.axis}</span>
                <span className="text-gray-500">Parent:</span>
                <span className="text-gray-300 font-mono">{ext.parentPath}</span>
              </div>
              <div className="ml-4 space-y-0.5">
                {ext.nodes.map((node) => (
                  <div key={node.segment} className="flex gap-2">
                    <span className="text-gray-400 font-mono">{node.segment}</span>
                    <span className="text-gray-500">{node.displayName}</span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </>
      )}

      <h4 className="text-xs text-gray-400 font-medium">Entity Taxonomy Mappings</h4>
      <table className="w-full text-xs">
        <thead>
          <tr className="text-gray-600 border-b border-gray-800">
            <th className="py-1 text-left font-medium">Entity</th>
            <th className="py-1 text-left font-medium">What</th>
            <th className="py-1 text-left font-medium">How</th>
            <th className="py-1 text-left font-medium">Why</th>
          </tr>
        </thead>
        <tbody>
          {grammar.entityMappings.map((em) => (
            <tr key={`${em.sourceEntityId}-${em.targetObjectType}`} className="border-t border-gray-800/50">
              <td className="py-1 text-gray-300">{em.sourceEntityId}</td>
              <td className="py-1 text-gray-400 font-mono">{String(em.taxonomy.what)}</td>
              <td className="py-1 text-gray-400 font-mono">{String(em.taxonomy.how)}</td>
              <td className="py-1 text-gray-400 font-mono">{String(em.taxonomy.why)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── Shared ──────────────────────────────────────────────────────

function Row({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <tr className="border-b border-gray-800/50">
      <td className="py-1.5 pr-4 text-gray-500 whitespace-nowrap text-xs">{label}</td>
      <td className={`py-1.5 text-gray-300 text-xs ${mono ? 'font-mono' : ''}`}>{value}</td>
    </tr>
  );
}

```
