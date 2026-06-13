---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/canvas/LoomCard.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.934228+00:00
---

# archive/apps-loom-react/src/canvas/LoomCard.tsx

```tsx
import { useRef, useCallback } from 'react';
import { useLoom } from '../state/LoomProvider';
import { useIdentity } from '../identity/IdentityProvider';
import { LinearityBadge } from '../sidebar/LinearityBadge';
import { CommercePhaseChip } from '../sidebar/CommercePhaseChip';
import { linearityLabel } from '../state/objectFactory';
import { ConversationPanel } from './ConversationPanel';
import type { LoomCard } from '../types/loom';
import type { FieldDefinition } from '../config/extensionConfig';

const PHASE_NAMES: Record<number, string> = {
  0: 'SOURCE', 1: 'PARSE', 2: 'AST', 3: 'TYPECHECK',
  4: 'OPTIMISE', 5: 'CODEGEN', 6: 'ACTION', 7: 'OUTCOME',
};

function FieldRenderer({ field, value, onChange, locked }: {
  field: FieldDefinition;
  value: unknown;
  onChange: (v: unknown) => void;
  locked?: boolean;
}) {
  if (locked) {
    return (
      <div className="flex items-center gap-1 text-xs text-gray-600">
        <span className="text-[10px]">{'\u{1F512}'}</span>
        <span className="italic">Restricted</span>
      </div>
    );
  }

  switch (field.type) {
    case 'enum':
      return (
        <select
          className="w-full bg-gray-800 border border-gray-700 rounded px-1.5 py-0.5 text-xs text-gray-300"
          value={String(value ?? '')}
          onChange={e => onChange(e.target.value)}
        >
          {field.values?.map(v => <option key={v} value={v}>{v}</option>)}
        </select>
      );
    case 'number':
      return (
        <input
          type="number"
          className="w-full bg-gray-800 border border-gray-700 rounded px-1.5 py-0.5 text-xs text-gray-300"
          value={Number(value ?? 0)}
          min={field.min}
          max={field.max}
          onChange={e => onChange(Number(e.target.value))}
        />
      );
    case 'boolean':
      return (
        <input
          type="checkbox"
          checked={Boolean(value)}
          onChange={e => onChange(e.target.checked)}
          className="rounded border-gray-600"
        />
      );
    case 'datetime':
      return (
        <input
          type="datetime-local"
          className="w-full bg-gray-800 border border-gray-700 rounded px-1.5 py-0.5 text-xs text-gray-300"
          value={String(value ?? '')}
          onChange={e => onChange(e.target.value)}
        />
      );
    default:
      return (
        <input
          type="text"
          className="w-full bg-gray-800 border border-gray-700 rounded px-1.5 py-0.5 text-xs text-gray-300"
          value={String(value ?? '')}
          onChange={e => onChange(e.target.value)}
        />
      );
  }
}

/** Check if the active hat has all required capabilities for a field. */
function canAccessField(field: FieldDefinition, facetCapabilities: number[] | undefined): boolean {
  if (!field.requiredCapabilities?.length) return true;
  if (!facetCapabilities) return true; // no identity = debug mode
  return field.requiredCapabilities.every(c => facetCapabilities.includes(c));
}

export function LoomCardView({ card }: { card: LoomCard }) {
  const { state, dispatch } = useLoom();
  const { activeHat } = useIdentity();
  const object = state.objects.get(card.objectId);
  const dragRef = useRef({ isDragging: false, startX: 0, startY: 0 });

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    if ((e.target as HTMLElement).tagName === 'INPUT' || (e.target as HTMLElement).tagName === 'SELECT') return;
    e.stopPropagation();
    dragRef.current = { isDragging: true, startX: e.clientX - card.position.x, startY: e.clientY - card.position.y };

    const onMouseMove = (ev: MouseEvent) => {
      if (!dragRef.current.isDragging) return;
      dispatch({
        type: 'MOVE_CARD',
        id: card.id,
        position: { x: ev.clientX - dragRef.current.startX, y: ev.clientY - dragRef.current.startY },
      });
    };

    const onMouseUp = () => {
      dragRef.current.isDragging = false;
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
    };

    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
  }, [card.id, card.position, dispatch]);

  if (!object) return null;

  const isSelected = state.selectedObjectId === object.id;
  const linearity = linearityLabel(object.header.linearity);
  const phase = PHASE_NAMES[object.header.phase] ?? 'UNKNOWN';
  const useConversation = object.typeDefinition.conversationEnabled === true;

  return (
    <div
      className={`absolute bg-gray-900 border rounded-lg shadow-lg overflow-hidden ${
        isSelected ? 'border-blue-500 ring-1 ring-blue-500/50' : 'border-gray-700'
      }`}
      style={{
        left: card.position.x,
        top: card.position.y,
        width: card.size.width,
      }}
      onMouseDown={(e) => {
        dispatch({ type: 'SELECT_OBJECT', id: object.id });
        onMouseDown(e);
      }}
    >
      {/* Header */}
      <div className="flex items-center gap-2 px-3 py-2 bg-gray-800/50 border-b border-gray-700 cursor-grab">
        <LinearityBadge linearity={linearity} />
        <span className="flex-1 text-sm font-medium text-gray-200">{object.typeDefinition.name}</span>
        <CommercePhaseChip phase={phase} />
      </div>

      {/* Body — conversation or fields */}
      {card.state !== 'collapsed' && (
        useConversation ? (
          <ConversationPanel object={object} />
        ) : (
          <div className="px-3 py-2 space-y-1.5 max-h-[300px] overflow-y-auto">
            {object.typeDefinition.fields.map(field => {
              const locked = !canAccessField(field, activeHat?.capabilities);
              return (
                <div key={field.name}>
                  <label className="text-[10px] text-gray-500 block">
                    {field.name}
                    {locked && <span className="ml-1 text-gray-700">{'\u{1F512}'}</span>}
                  </label>
                  <FieldRenderer
                    field={field}
                    value={object.payload[field.name]}
                    onChange={v => dispatch({
                      type: 'UPDATE_PAYLOAD',
                      objectId: object.id,
                      field: field.name,
                      value: v,
                    })}
                    locked={locked}
                  />
                </div>
              );
            })}
          </div>
        )
      )}

      {/* Footer */}
      {card.state !== 'collapsed' && (
        <div className="flex gap-1 px-3 py-1.5 border-t border-gray-800 bg-gray-900/50">
          <span className="text-[10px] text-gray-600">#{object.id.split('-').pop()}</span>
        </div>
      )}
    </div>
  );
}

```
