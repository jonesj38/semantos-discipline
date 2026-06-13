---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/components/DimensionBar.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.969892+00:00
---

# archive/apps-loom-react/src/navigator/components/DimensionBar.tsx

```tsx
import { DIMENSION_META, type DimensionId } from '../../hooks/useDimensions';

interface DimensionBarProps {
  dimensionId: DimensionId;
  score: number;
}

function scoreColor(score: number): string {
  if (score <= 30) return '#ef4444';
  if (score <= 50) return '#f59e0b';
  if (score <= 70) return '#3b82f6';
  return '#4ade80';
}

export function DimensionBar({ dimensionId, score }: DimensionBarProps) {
  const meta = DIMENSION_META[dimensionId];
  const color = scoreColor(score);

  return (
    <div className="nav-dim-row">
      <span className="nav-dim-emoji">{meta.emoji}</span>
      <span className="nav-dim-label">{meta.label}</span>
      <div className="nav-dim-bar-wrap">
        <div className="nav-dim-bar" style={{ width: `${score}%`, background: color }} />
      </div>
      <span className="nav-dim-score" style={{ color }}>{Math.round(score / 10)}</span>
    </div>
  );
}

```
