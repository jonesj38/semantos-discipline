---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/sidebar/TypeList.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.956569+00:00
---

# archive/apps-loom-react/src/sidebar/TypeList.tsx

```tsx
import { useMemo } from 'react';
import { useExtension } from '../config/ExtensionProvider';
import { useLoom } from '../state/LoomProvider';
import { LinearityBadge } from './LinearityBadge';
import type { Archetype, ObjectTypeDefinition } from '../config/extensionConfig';

const ICONS: Record<string, string> = {
  briefcase: '\u{1F4BC}', 'file-text': '\u{1F4C4}', 'map-pin': '\u{1F4CD}',
  receipt: '\u{1F9FE}', user: '\u{1F464}', home: '\u{1F3E0}', box: '\u{1F4E6}',
  zap: '\u{26A1}', shield: '\u{1F6E1}', key: '\u{1F511}', scroll: '\u{1F4DC}',
};

const ARCHETYPE_ORDER: Archetype[] = ['thing', 'action', 'instrument'];

const ARCHETYPE_LABELS: Record<string, string> = {
  identity: 'Identity',
  thing: 'Things',
  action: 'Actions',
  instrument: 'Instruments',
};

export function TypeList() {
  const { config } = useExtension();
  const { createObjectFromType } = useLoom();

  const grouped = useMemo(() => {
    if (!config) return new Map<Archetype, ObjectTypeDefinition[]>();
    const groups = new Map<Archetype, ObjectTypeDefinition[]>();
    for (const typeDef of config.objectTypes) {
      // Hide identity archetype types from the create list
      const archetype = typeDef.archetype ?? 'thing';
      if (archetype === 'identity') continue;
      if (!groups.has(archetype)) groups.set(archetype, []);
      groups.get(archetype)!.push(typeDef);
    }
    return groups;
  }, [config]);

  if (!config) return null;

  return (
    <div className="px-2 py-2">
      <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1 px-1">Create Object</div>
      {ARCHETYPE_ORDER.map(archetype => {
        const types = grouped.get(archetype);
        if (!types || types.length === 0) return null;
        return (
          <div key={archetype} className="mb-2">
            <div className="text-[10px] text-gray-600 uppercase tracking-wider px-2 py-0.5">
              {ARCHETYPE_LABELS[archetype]}
            </div>
            {types.map(typeDef => (
              <button
                key={typeDef.name}
                className="w-full flex items-center gap-2 px-2 py-1.5 rounded hover:bg-gray-800 text-left text-sm"
                onClick={() => createObjectFromType(typeDef)}
              >
                <span className="text-base">{ICONS[typeDef.icon] ?? '\u{1F4E6}'}</span>
                <span className="flex-1 text-gray-300">{typeDef.name}</span>
                <LinearityBadge linearity={typeDef.linearity} small />
              </button>
            ))}
          </div>
        );
      })}
    </div>
  );
}

```
