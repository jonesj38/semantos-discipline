---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/panels/FieldMappingTable.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.952216+00:00
---

# archive/apps-loom-react/src/panels/FieldMappingTable.tsx

```tsx
/**
 * FieldMappingTable — sortable table showing source-to-target field mappings.
 *
 * Renders entity mappings as an interactive table with sort, click-to-focus,
 * and transform detail display. Never shows raw JSON.
 */

import { useState, useMemo } from 'react';
import type { EntityMapping, FieldMapping, FieldTransform } from '../../../protocol-types/src/extension-grammar';

interface FieldMappingTableProps {
  mappings: EntityMapping[];
}

type SortField = 'source' | 'target' | 'sourceType' | 'required';
type SortDir = 'asc' | 'desc';

export function FieldMappingTable({ mappings }: FieldMappingTableProps) {
  const [sortField, setSortField] = useState<SortField>('source');
  const [sortDir, setSortDir] = useState<SortDir>('asc');
  const [expandedRow, setExpandedRow] = useState<string | null>(null);

  // Flatten all field mappings with their parent entity context
  const rows = useMemo(() => {
    const flat: Array<{
      key: string;
      sourceEntityId: string;
      targetObjectType: string;
      mapping: FieldMapping;
    }> = [];

    for (const em of mappings) {
      for (const fm of em.fieldMappings) {
        flat.push({
          key: `${em.sourceEntityId}.${fm.sourceField}->${fm.targetField}`,
          sourceEntityId: em.sourceEntityId,
          targetObjectType: em.targetObjectType,
          mapping: fm,
        });
      }
    }

    // Sort
    flat.sort((a, b) => {
      let cmp = 0;
      switch (sortField) {
        case 'source':
          cmp = a.mapping.sourceField.localeCompare(b.mapping.sourceField);
          break;
        case 'target':
          cmp = a.mapping.targetField.localeCompare(b.mapping.targetField);
          break;
        case 'required':
          cmp = (a.mapping.required ? 1 : 0) - (b.mapping.required ? 1 : 0);
          break;
        default:
          cmp = a.mapping.sourceField.localeCompare(b.mapping.sourceField);
      }
      return sortDir === 'desc' ? -cmp : cmp;
    });

    return flat;
  }, [mappings, sortField, sortDir]);

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDir('asc');
    }
  };

  if (mappings.length === 0) {
    return <p className="text-xs text-gray-500">No field mappings defined.</p>;
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-xs">
        <thead>
          <tr className="text-gray-500 border-b border-gray-800">
            <SortHeader field="source" current={sortField} dir={sortDir} onClick={handleSort}>
              Source Field
            </SortHeader>
            <SortHeader field="target" current={sortField} dir={sortDir} onClick={handleSort}>
              Target Field
            </SortHeader>
            <th className="py-2 px-2 text-left font-medium">Entity</th>
            <th className="py-2 px-2 text-left font-medium">Transform</th>
            <SortHeader field="required" current={sortField} dir={sortDir} onClick={handleSort}>
              Required
            </SortHeader>
            <th className="py-2 px-2 text-left font-medium">Visibility</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <>
              <tr
                key={row.key}
                className="border-b border-gray-800/50 hover:bg-gray-800/30 cursor-pointer"
                onClick={() => setExpandedRow(expandedRow === row.key ? null : row.key)}
              >
                <td className="py-1.5 px-2 text-gray-300 font-mono">{row.mapping.sourceField}</td>
                <td className="py-1.5 px-2 text-gray-300 font-mono">{row.mapping.targetField}</td>
                <td className="py-1.5 px-2 text-gray-500">{row.sourceEntityId}</td>
                <td className="py-1.5 px-2 text-gray-400">
                  {row.mapping.transform ? formatTransformBrief(row.mapping.transform) : '-'}
                </td>
                <td className="py-1.5 px-2">
                  {row.mapping.required ? (
                    <span className="text-yellow-400">Yes</span>
                  ) : (
                    <span className="text-gray-600">No</span>
                  )}
                </td>
                <td className="py-1.5 px-2 text-gray-500">
                  {row.mapping.visibility ?? 'visible'}
                </td>
              </tr>
              {expandedRow === row.key && (
                <tr key={`${row.key}-detail`}>
                  <td colSpan={6} className="px-4 py-2 bg-gray-850 border-b border-gray-800/50">
                    <FieldMappingDetail mapping={row.mapping} objectType={row.targetObjectType} />
                  </td>
                </tr>
              )}
            </>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── Sub-components ──────────────────────────────────────────────

function SortHeader({
  field,
  current,
  dir,
  onClick,
  children,
}: {
  field: SortField;
  current: SortField;
  dir: SortDir;
  onClick: (f: SortField) => void;
  children: React.ReactNode;
}) {
  const isActive = field === current;
  return (
    <th
      className="py-2 px-2 text-left font-medium cursor-pointer hover:text-gray-300"
      onClick={() => onClick(field)}
    >
      {children}
      {isActive && <span className="ml-1">{dir === 'asc' ? '\u25B4' : '\u25BE'}</span>}
    </th>
  );
}

function FieldMappingDetail({ mapping, objectType }: { mapping: FieldMapping; objectType: string }) {
  return (
    <div className="space-y-1 text-xs">
      <div className="flex gap-2">
        <span className="text-gray-500">Object type:</span>
        <span className="text-gray-300">{objectType}</span>
      </div>
      {mapping.coerce && (
        <div className="flex gap-2">
          <span className="text-gray-500">Coercion:</span>
          <span className="text-gray-300">{mapping.coerce.from} \u2192 {mapping.coerce.to}</span>
          {mapping.coerce.format && <span className="text-gray-500">(format: {mapping.coerce.format})</span>}
        </div>
      )}
      {mapping.transform && (
        <div className="flex gap-2">
          <span className="text-gray-500">Transform:</span>
          <span className="text-gray-300">{formatTransformFull(mapping.transform)}</span>
        </div>
      )}
      {mapping.default !== undefined && (
        <div className="flex gap-2">
          <span className="text-gray-500">Default:</span>
          <span className="text-gray-300">{String(mapping.default)}</span>
        </div>
      )}
    </div>
  );
}

// ── Helpers ─────────────────────────────────────────────────────

function formatTransformBrief(t: FieldTransform): string {
  switch (t.type) {
    case 'concat': return `concat(${t.parts?.length ?? 0} parts)`;
    case 'split': return `split("${t.delimiter ?? ','}")`;
    case 'lookup': return 'lookup table';
    case 'template': return 'template';
    case 'lowercase': return 'lowercase';
    case 'uppercase': return 'uppercase';
    case 'trim': return 'trim';
    case 'map_enum': return `map_enum(${Object.keys(t.enumMap ?? {}).length} values)`;
    case 'compute': return t.expression ?? 'compute';
    default: return t.type;
  }
}

function formatTransformFull(t: FieldTransform): string {
  switch (t.type) {
    case 'concat':
      return `Concatenate: ${(t.parts ?? []).map(p => typeof p === 'string' ? p : `"${p.literal}"`).join(' + ')}`;
    case 'split':
      return `Split by "${t.delimiter}"`;
    case 'lookup':
      return `Lookup: ${Object.entries(t.lookupTable ?? {}).map(([k, v]) => `${k}\u2192${v}`).join(', ')}`;
    case 'template':
      return `Template: ${t.template}`;
    case 'map_enum':
      return `Map enum: ${Object.entries(t.enumMap ?? {}).map(([k, v]) => `${k}\u2192${v}`).join(', ')}`;
    case 'compute':
      return `Compute: ${t.expression}`;
    default:
      return t.type;
  }
}

```
