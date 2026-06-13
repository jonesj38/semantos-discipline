---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/sidebar/ObjectTree.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.954881+00:00
---

# archive/apps-loom-react/src/sidebar/ObjectTree.tsx

```tsx
import { useMemo } from 'react';
import { useLoom } from '../state/LoomProvider';
import { useExtension } from '../config/ExtensionProvider';
import { LinearityBadge } from './LinearityBadge';
import { CommercePhaseChip } from './CommercePhaseChip';
import { linearityLabel } from '../state/objectFactory';
import type { Archetype } from '../config/extensionConfig';
import type { LoomObject } from '../types/loom';

const PHASE_NAMES: Record<number, string> = {
  0: 'SOURCE', 1: 'PARSE', 2: 'AST', 3: 'TYPECHECK',
  4: 'OPTIMISE', 5: 'CODEGEN', 6: 'ACTION', 7: 'OUTCOME',
};

const ARCHETYPE_ORDER: Archetype[] = ['identity', 'thing', 'action', 'instrument'];

const ARCHETYPE_LABELS: Record<string, string> = {
  identity: 'Identity',
  thing: 'Things',
  action: 'Actions',
  instrument: 'Instruments',
};

interface ArchetypeGroup {
  archetype: Archetype;
  typeGroups: Map<string, LoomObject[]>;
}

export function ObjectTree() {
  const { state, dispatch, openAsCard } = useLoom();
  const { config } = useExtension();

  const archetypeGroups = useMemo(() => {
    const objects = [...state.objects.values()];
    const filtered = state.categoryFilter
      ? objects.filter(o => o.typeDefinition.category?.startsWith(state.categoryFilter!))
      : objects;

    const groups = new Map<Archetype, Map<string, LoomObject[]>>();
    for (const obj of filtered) {
      const archetype = obj.typeDefinition.archetype ?? 'thing';
      if (!groups.has(archetype)) groups.set(archetype, new Map());
      const typeGroups = groups.get(archetype)!;
      const typeName = obj.typeDefinition.name;
      if (!typeGroups.has(typeName)) typeGroups.set(typeName, []);
      typeGroups.get(typeName)!.push(obj);
    }

    return ARCHETYPE_ORDER
      .filter(a => groups.has(a))
      .map(a => ({ archetype: a, typeGroups: groups.get(a)! }));
  }, [state.objects, state.categoryFilter]);

  if (archetypeGroups.length === 0) {
    return (
      <div className="px-3 py-2 text-xs text-gray-600">
        No objects yet. Create one from the type list below.
      </div>
    );
  }

  return (
    <div className="px-1 py-1">
      {archetypeGroups.map(({ archetype, typeGroups }) => (
        <div key={archetype} className="mb-2">
          <div className="text-[10px] text-gray-600 uppercase tracking-wider font-semibold px-2 py-0.5">
            {ARCHETYPE_LABELS[archetype]}
          </div>
          {[...typeGroups.entries()].map(([typeName, objects]) => (
            <div key={typeName} className="mb-1">
              <div className="text-[10px] text-gray-500 px-2 py-0.5">
                {typeName} ({objects.length})
              </div>
              {objects.map(obj => {
                const isSelected = state.selectedObjectId === obj.id;
                return (
                  <div
                    key={obj.id}
                    className={`flex items-center gap-1.5 px-2 py-1 rounded cursor-pointer text-xs ${
                      isSelected ? 'bg-gray-700' : 'hover:bg-gray-800'
                    }`}
                    onClick={() => dispatch({ type: 'SELECT_OBJECT', id: obj.id })}
                    onDoubleClick={() => openAsCard(obj.id)}
                  >
                    <LinearityBadge linearity={linearityLabel(obj.header.linearity)} small />
                    <span className="flex-1 text-gray-300 truncate">
                      {obj.typeDefinition.name} #{obj.id.split('-').pop()}
                    </span>
                    <CommercePhaseChip phase={PHASE_NAMES[obj.header.phase] ?? 'UNKNOWN'} />
                  </div>
                );
              })}
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

```
