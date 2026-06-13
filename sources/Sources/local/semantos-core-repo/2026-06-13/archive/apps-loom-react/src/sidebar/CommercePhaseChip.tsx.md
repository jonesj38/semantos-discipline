---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/sidebar/CommercePhaseChip.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.954613+00:00
---

# archive/apps-loom-react/src/sidebar/CommercePhaseChip.tsx

```tsx
const PHASE_COLORS: Record<string, string> = {
  SOURCE: 'bg-purple-900 text-purple-300',
  PARSE: 'bg-blue-900 text-blue-300',
  AST: 'bg-cyan-900 text-cyan-300',
  TYPECHECK: 'bg-green-900 text-green-300',
  OPTIMISE: 'bg-lime-900 text-lime-300',
  CODEGEN: 'bg-yellow-900 text-yellow-300',
  ACTION: 'bg-orange-900 text-orange-300',
  OUTCOME: 'bg-red-900 text-red-300',
};

interface CommercePhaseChipProps {
  phase: string;
}

export function CommercePhaseChip({ phase }: CommercePhaseChipProps) {
  const color = PHASE_COLORS[phase] ?? 'bg-gray-800 text-gray-400';
  return (
    <span className={`inline-block rounded text-[9px] px-1 py-px font-mono ${color}`}>
      {phase}
    </span>
  );
}

```
