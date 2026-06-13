---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/HelmNav.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.964714+00:00
---

# archive/apps-loom-react/src/helm/HelmNav.tsx

```tsx
import React from 'react';

export type NavTab = 'home' | 'do' | 'talk' | 'find';

export interface HelmNavProps {
  activeTab: NavTab;
  onTabChange: (tab: NavTab) => void;
  /** Badge count for the home/anchor tab (immediate attention items). */
  homeBadge: number;
  /** Per-mode badge counts. */
  modeBadges: Record<'do' | 'talk' | 'find', number>;
}

interface TabDef {
  id: NavTab;
  label: string;
  icon: string;
}

const TABS: TabDef[] = [
  { id: 'home', label: 'Home', icon: '\u2693' },   // anchor
  { id: 'do',   label: 'Do',   icon: '\u26A1' },   // lightning
  { id: 'talk', label: 'Talk', icon: '\uD83D\uDCAC' }, // speech bubble
  { id: 'find', label: 'Find', icon: '\uD83D\uDD0D' }, // magnifier
];

function Badge({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <span className="absolute -top-1 -right-2 min-w-[18px] h-[18px] flex items-center justify-center rounded-full bg-red-500 text-white text-[10px] font-semibold px-1">
      {count > 99 ? '99+' : count}
    </span>
  );
}

export function HelmNav({ activeTab, onTabChange, homeBadge, modeBadges }: HelmNavProps) {
  function badgeFor(tab: NavTab): number {
    if (tab === 'home') return homeBadge;
    return modeBadges[tab as 'do' | 'talk' | 'find'] ?? 0;
  }

  return (
    <nav className="flex items-center justify-around border-t border-gray-700 bg-gray-900 px-2 py-1 shrink-0">
      {TABS.map((tab) => {
        const isActive = activeTab === tab.id;
        const badge = badgeFor(tab.id);
        return (
          <button
            key={tab.id}
            onClick={() => onTabChange(tab.id)}
            className={`
              relative flex flex-col items-center gap-0.5 px-4 py-1.5 rounded-lg transition-colors
              ${isActive
                ? 'text-blue-400 bg-gray-800'
                : 'text-gray-400 hover:text-gray-200 hover:bg-gray-800/50'}
            `}
            aria-current={isActive ? 'page' : undefined}
            aria-label={tab.label}
          >
            <span className="relative text-lg leading-none">
              {tab.icon}
              <Badge count={badge} />
            </span>
            <span className="text-[11px] font-medium">{tab.label}</span>
          </button>
        );
      })}
    </nav>
  );
}

```
