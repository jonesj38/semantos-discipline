---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/inspector/HexView.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.945546+00:00
---

# archive/apps-loom-react/src/inspector/HexView.tsx

```tsx
interface HexViewProps {
  data: Uint8Array;
  maxRows?: number;
}

export function HexView({ data, maxRows = 16 }: HexViewProps) {
  const rows: { offset: number; hex: string[]; ascii: string }[] = [];
  const bytesPerRow = 16;
  const limit = Math.min(data.length, maxRows * bytesPerRow);

  for (let i = 0; i < limit; i += bytesPerRow) {
    const slice = data.subarray(i, Math.min(i + bytesPerRow, limit));
    const hex: string[] = [];
    let ascii = '';
    for (let j = 0; j < bytesPerRow; j++) {
      if (j < slice.length) {
        hex.push(slice[j].toString(16).padStart(2, '0'));
        ascii += slice[j] >= 32 && slice[j] < 127 ? String.fromCharCode(slice[j]) : '.';
      } else {
        hex.push('  ');
        ascii += ' ';
      }
    }
    rows.push({ offset: i, hex, ascii });
  }

  return (
    <div className="font-mono text-[10px] leading-4 overflow-x-auto">
      {rows.map(row => (
        <div key={row.offset} className="flex">
          <span className="text-gray-600 w-10 flex-shrink-0">{row.offset.toString(16).padStart(4, '0')}</span>
          <span className="text-gray-400 flex-shrink-0">
            {row.hex.slice(0, 8).join(' ')}
            <span className="text-gray-700"> | </span>
            {row.hex.slice(8).join(' ')}
          </span>
          <span className="text-gray-600 ml-2 flex-shrink-0">{row.ascii}</span>
        </div>
      ))}
      {data.length > limit && (
        <div className="text-gray-600">... {data.length - limit} more bytes</div>
      )}
    </div>
  );
}

```
