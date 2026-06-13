---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/sidebar/LinearityBadge.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.955749+00:00
---

# archive/apps-loom-react/src/sidebar/LinearityBadge.tsx

```tsx
const BADGE_STYLES: Record<string, string> = {
  LINEAR: 'bg-linear text-white',
  AFFINE: 'bg-affine text-white',
  RELEVANT: 'bg-relevant text-gray-900',
  DEBUG: 'bg-debug text-white',
};

interface LinearityBadgeProps {
  linearity: string;
  small?: boolean;
}

export function LinearityBadge({ linearity, small }: LinearityBadgeProps) {
  const style = BADGE_STYLES[linearity] ?? BADGE_STYLES.DEBUG;
  const size = small ? 'text-[9px] px-1 py-px' : 'text-[10px] px-1.5 py-0.5';
  return (
    <span className={`inline-block rounded font-mono font-semibold ${style} ${size}`}>
      {linearity[0]}
    </span>
  );
}

```
