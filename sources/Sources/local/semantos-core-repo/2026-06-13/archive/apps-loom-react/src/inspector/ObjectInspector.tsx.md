---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/inspector/ObjectInspector.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.944725+00:00
---

# archive/apps-loom-react/src/inspector/ObjectInspector.tsx

```tsx
import { useLoom } from '../state/LoomProvider';
import { useExtension } from '../config/ExtensionProvider';
import { LinearityBadge } from '../sidebar/LinearityBadge';
import { CommercePhaseChip } from '../sidebar/CommercePhaseChip';
import { linearityLabel } from '../state/objectFactory';
import { serializeCellHeader } from '@semantos/protocol-types/browser';
import { HexView } from './HexView';
import { AccumulatedStateView } from './AccumulatedStateView';
import { EvidenceChain } from './EvidenceChain';
import { ChannelInspectorPanel } from './ChannelInspectorPanel';

const PHASE_NAMES: Record<number, string> = {
  0: 'SOURCE', 1: 'PARSE', 2: 'AST', 3: 'TYPECHECK',
  4: 'OPTIMISE', 5: 'CODEGEN', 6: 'ACTION', 7: 'OUTCOME',
};

function toHex(arr: Uint8Array, max = 16): string {
  const hex = Array.from(arr.subarray(0, max)).map(b => b.toString(16).padStart(2, '0')).join('');
  return arr.length > max ? hex + '...' : hex;
}

export function ObjectInspector() {
  const { selectedObject } = useLoom();
  const { config } = useExtension();

  if (!selectedObject) return null;

  const h = selectedObject.header;
  const linearity = linearityLabel(h.linearity);
  const phase = PHASE_NAMES[h.phase] ?? 'UNKNOWN';
  const typeDef = selectedObject.typeDefinition;

  // Find matching capability names from config
  const flagNames: string[] = [];
  if (config) {
    for (const cap of config.capabilities) {
      if ((h.flags & (1 << cap.id)) !== 0) {
        flagNames.push(cap.name);
      }
    }
  }

  // Serialize header to bytes for hex view
  let headerBytes: Uint8Array | null = null;
  try {
    headerBytes = serializeCellHeader(h);
  } catch {}

  return (
    <div className="text-xs space-y-3 p-3">
      {/* Header */}
      <div>
        <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">Cell Header</div>
        <div className="space-y-0.5">
          <Row label="Type" value={typeDef.name} />
          <Row label="Linearity">
            <LinearityBadge linearity={linearity} />
            <span className="text-gray-400 ml-1">{linearity}</span>
          </Row>
          <Row label="Version" value={String(h.version)} />
          <Row label="Flags" value={`0x${h.flags.toString(16)} (${flagNames.join(', ') || 'none'})`} />
          <Row label="Ref Count" value={String(h.refCount)} />
          <Row label="Type Hash" value={toHex(h.typeHash)} mono />
          <Row label="Owner ID" value={toHex(h.ownerId)} mono />
          <Row label="Timestamp" value={new Date(Number(h.timestamp)).toLocaleString()} />
          <Row label="Cell Count" value={String(h.cellCount)} />
          <Row label="Total Size" value={`${h.totalSize} bytes`} />
          <Row label="Phase">
            <CommercePhaseChip phase={phase} />
          </Row>
        </div>
      </div>

      {/* Linearity transitions */}
      {typeDef.linearityTransitions && typeDef.linearityTransitions.length > 0 && (
        <div>
          <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">Linearity Transitions</div>
          {typeDef.linearityTransitions.map((t, i) => (
            <div key={i} className="text-gray-400 flex items-center gap-1">
              <LinearityBadge linearity={t.from} small />
              <span>\u2192</span>
              <LinearityBadge linearity={t.to} small />
              <span className="text-gray-600">when {t.trigger}</span>
            </div>
          ))}
        </div>
      )}

      {/* Channel-specific panels for metering.channel objects */}
      {typeDef?.category === 'metering.channel' && <ChannelInspectorPanel />}

      {/* Accumulated State (scoring view for relevant types) */}
      <AccumulatedStateView />

      {/* Evidence Chain */}
      <EvidenceChain />

      {/* Raw header hex */}
      {headerBytes && (
        <div>
          <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">Raw Header (256 bytes)</div>
          <HexView data={headerBytes} maxRows={8} />
        </div>
      )}
    </div>
  );
}

function Row({ label, value, mono, children }: {
  label: string;
  value?: string;
  mono?: boolean;
  children?: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-gray-600 w-20 flex-shrink-0">{label}</span>
      {children ?? (
        <span className={`text-gray-300 truncate ${mono ? 'font-mono text-[10px]' : ''}`}>
          {value}
        </span>
      )}
    </div>
  );
}

```
