---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/canvas/ConnectionLine.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.935107+00:00
---

# archive/apps-loom-react/src/canvas/ConnectionLine.tsx

```tsx
interface ConnectionLineProps {
  fromX: number;
  fromY: number;
  toX: number;
  toY: number;
}

export function ConnectionLine({ fromX, fromY, toX, toY }: ConnectionLineProps) {
  const midX = (fromX + toX) / 2;
  const d = `M ${fromX} ${fromY} C ${midX} ${fromY}, ${midX} ${toY}, ${toX} ${toY}`;

  return (
    <g>
      <path d={d} fill="none" stroke="#374151" strokeWidth={2} />
      <path d={d} fill="none" stroke="#3b82f6" strokeWidth={1} strokeDasharray="4 4">
        <animate attributeName="stroke-dashoffset" from="8" to="0" dur="1s" repeatCount="indefinite" />
      </path>
    </g>
  );
}

```
