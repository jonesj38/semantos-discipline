---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/views/HomeView.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.970799+00:00
---

# archive/apps-loom-react/src/navigator/views/HomeView.tsx

```tsx
import { useMemo } from 'react';
import { useKernel } from '../../contexts/KernelProvider';
import { useCardData } from '../../hooks/useCardData';
import { DIMENSION_IDS } from '../../hooks/useDimensions';
import { SpinningCard } from '../components/SpinningCard';
import { DimensionBar } from '../components/DimensionBar';
import { OBJECT_ICONS } from '../data/objectTypes';
import type { OverlayType } from '../NavigatorShell';
import type { TabId } from '../BottomNav';

interface HomeViewProps {
  onOpenOverlay: (type: OverlayType) => void;
  onSwitchTab: (tab: TabId) => void;
}

function timeAgo(ts: number): string {
  const diff = Date.now() - ts;
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}

function objectLabel(type: string, fields: Record<string, unknown>): string {
  if (type === 'Release') {
    const text = (fields.rawText as string) || '';
    return 'Released: ' + (text.length > 50 ? text.slice(0, 50) + '…' : text || 'written release');
  }
  if (type === 'Insight') return ((fields.content as string) || '').slice(0, 60) || 'New insight';
  if (type === 'Intention') return ((fields.statement as string) || '').slice(0, 60) || 'New intention';
  if (type === 'DailyReview') return 'Evening review completed';
  if (type === 'MorningIntention') return `Focus: ${fields.focusDimension || 'set'}`;
  return type;
}

export function HomeView({ onOpenOverlay, onSwitchTab }: HomeViewProps) {
  const { kernel } = useKernel();
  const { data, getGrouped } = useCardData();

  const greeting = useMemo(() => {
    const hour = new Date().getHours();
    return hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
  }, []);

  const objects = useMemo(() => kernel?.listObjects() ?? [], [kernel]);
  const recent = useMemo(() => objects.slice(-5).reverse(), [objects]);
  const grouped = getGrouped();
  const hasCardData = Object.values(data).some(d => d.recentEntries.length > 0 || d.score !== 50);

  return (
    <div style={{ padding: '0 16px 16px' }}>
      {/* Greeting */}
      <div className="nav-greeting">{greeting}</div>
      <div className="nav-greeting-sub">What would you like to focus on today?</div>
      <div style={{ marginTop: 12 }}>
        <span className="nav-streak">🔥 0 day streak</span>
      </div>

      {/* Quick Actions */}
      <div className="nav-quick-actions">
        <button className="nav-quick-btn" onClick={() => onOpenOverlay('release')}>
          <span>✍️</span> Release
        </button>
        <button className="nav-quick-btn" onClick={() => onOpenOverlay('intention')}>
          <span>🌅</span> Intention
        </button>
        <button className="nav-quick-btn" onClick={() => onOpenOverlay('review')}>
          <span>🌙</span> Review
        </button>
        <button className="nav-quick-btn" onClick={() => onSwitchTab('talk')}>
          <span>💬</span> Talk
        </button>
      </div>

      {/* Dimension Cards */}
      {hasCardData ? (
        <div>
          {Object.entries(grouped).map(([groupName, dims]) => (
            <div className="dimension-group" key={groupName}>
              <div className="group-label">{groupName}</div>
              <div className="card-grid">
                {dims.map(dim => (
                  <SpinningCard
                    key={dim.dimId}
                    dimensionId={dim.dimId}
                    score={dim.score}
                    recentEntries={dim.recentEntries}
                  />
                ))}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="nav-card" style={{ marginTop: 16 }}>
          <div className="nav-card-title">Life Dimensions</div>
          {DIMENSION_IDS.map(id => (
            <DimensionBar key={id} dimensionId={id} score={data[id]?.score ?? 50} />
          ))}
        </div>
      )}

      {/* Recent Activity */}
      {recent.length > 0 && (
        <div className="nav-card" style={{ marginTop: 4 }}>
          <div className="nav-card-title">Recent</div>
          {recent.map(obj => (
            <div key={obj.id} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 0' }}>
              <span style={{ fontSize: 16 }}>{OBJECT_ICONS[obj.type] || '•'}</span>
              <span style={{ flex: 1, fontSize: 13, color: 'var(--nav-text-70)' }}>
                {objectLabel(obj.type, obj.fields)}
              </span>
              <span className="nav-time-ago">{timeAgo(obj.createdAt)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

```
