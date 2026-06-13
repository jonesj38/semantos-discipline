---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/views/ProcessView.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.971092+00:00
---

# archive/apps-loom-react/src/navigator/views/ProcessView.tsx

```tsx
import { useCallback } from 'react';
import { PROCESS_CYCLES } from '../data/processCycles';

interface ProcessViewProps {
  onSwitchToTalk: (prefill: string) => void;
}

export function ProcessView({ onSwitchToTalk }: ProcessViewProps) {
  const startCycleChat = useCallback(
    (cycleId: string) => {
      const cycle = PROCESS_CYCLES.find(c => c.id === cycleId);
      if (cycle) onSwitchToTalk(`I want to work on the ${cycle.label} process`);
    },
    [onSwitchToTalk],
  );

  return (
    <div style={{ padding: 16 }}>
      <div style={{ fontSize: 20, fontWeight: 700, color: 'var(--nav-text)', marginBottom: 4 }}>
        The Process
      </div>
      <div style={{ fontSize: 14, color: 'var(--nav-text-50)', marginBottom: 16, lineHeight: 1.5 }}>
        Five cycles that build on each other. Release and receive at every depth.
      </div>

      {PROCESS_CYCLES.map(cycle => (
        <div
          key={cycle.id}
          className="cycle-card"
          style={{ background: `${cycle.color}08`, borderLeftColor: cycle.color }}
          onClick={() => startCycleChat(cycle.id)}
        >
          <div className="cycle-title" style={{ color: cycle.color }}>{cycle.label}</div>
          <div className="cycle-inquiry">{cycle.inquiry}</div>
          <div className="cycle-desc">{cycle.description}</div>
          <div className="cycle-flow">
            {cycle.steps.map((s, i) => {
              const cls = s.release ? 'release' : s.receive ? 'receive' : 'neutral';
              return (
                <span key={s.id}>
                  <span className={`step-chip ${cls}`}>{s.label}</span>
                  {i < cycle.steps.length - 1 && <span className="flow-arrow"> → </span>}
                </span>
              );
            })}
            {cycle.recursive && <span className="flow-arrow"> ↻</span>}
          </div>
        </div>
      ))}
    </div>
  );
}

```
