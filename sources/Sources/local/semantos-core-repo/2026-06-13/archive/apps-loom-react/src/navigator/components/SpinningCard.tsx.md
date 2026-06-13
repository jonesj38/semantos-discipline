---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/components/SpinningCard.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.969601+00:00
---

# archive/apps-loom-react/src/navigator/components/SpinningCard.tsx

```tsx
import { useState, useCallback } from 'react';
import { DIMENSION_META, type DimensionId } from '../../hooks/useDimensions';

interface SpinningCardProps {
  dimensionId: DimensionId;
  score: number;
  recentEntries: Array<{ id: string; type: string; fields: Record<string, unknown>; createdAt: number }>;
  faces?: string[];
}

const TAGS: Record<string, string> = {
  Release: '↗ Released', Insight: '✦ Insight', Intention: '🎯 Intention',
  DailyReview: '✓ Review', MorningIntention: '☀ Morning', Pattern: '🔄 Pattern',
  DimensionPulse: '📊 Pulse', Connection: '🔗 Connect', Session: '🧭 Session',
  VacuumSession: '🌀 Vacuum', GoldSeal: '✨ Sealed',
};

function timeAgo(ts: number): string {
  const diff = Date.now() - ts;
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

function truncate(str: string, len: number): string {
  return str.length > len ? str.slice(0, len) + '…' : str;
}

function ProfileFace({ meta, score, recentCount }: { meta: typeof DIMENSION_META['mind']; score: number; recentCount: number }) {
  return (
    <>
      <div className="card-header">
        <span className="card-emoji">{meta.emoji}</span>
        <span className="card-label">{meta.label}</span>
      </div>
      <div className="card-score-bar">
        <div className="card-score-fill" style={{ width: `${score}%`, background: meta.color }} />
      </div>
      <div className="card-score-text">{score}<span className="card-score-max">/100</span></div>
      <div className="card-stat">{recentCount} recent entries</div>
    </>
  );
}

function ReflectionFace({ meta, entries }: { meta: typeof DIMENSION_META['mind']; entries: SpinningCardProps['recentEntries'] }) {
  const shown = entries.slice(0, 3);
  return (
    <>
      <div className="card-header">
        <span className="card-emoji">{meta.emoji}</span>
        <span className="card-label">{meta.label} — Recent</span>
      </div>
      {shown.length > 0 ? (
        <div>
          {shown.map(e => (
            <div className="card-entry" key={e.id}>
              <span className="card-entry-tag">{TAGS[e.type] || e.type}</span>
              <span className="card-entry-text">
                {truncate(
                  (e.fields?.rawText || e.fields?.content || e.fields?.statement || '—') as string,
                  60,
                )}
              </span>
              <span className="card-entry-time">{timeAgo(e.createdAt)}</span>
            </div>
          ))}
        </div>
      ) : (
        <div className="card-empty">No entries yet. Start a conversation.</div>
      )}
    </>
  );
}

export function SpinningCard({ dimensionId, score, recentEntries, faces = ['profile', 'reflection'] }: SpinningCardProps) {
  const [currentFace, setCurrentFace] = useState(0);
  const [spinning, setSpinning] = useState(false);
  const meta = DIMENSION_META[dimensionId];

  const spin = useCallback(() => {
    setCurrentFace(prev => (prev + 1) % faces.length);
    setSpinning(true);
    setTimeout(() => setSpinning(false), 600);
  }, [faces.length]);

  const faceName = faces[currentFace];

  return (
    <div
      className={`spinning-card ${spinning ? 'spin' : ''}`}
      style={{ '--dim-color': meta.color } as React.CSSProperties}
      onClick={spin}
    >
      {faceName === 'profile' && <ProfileFace meta={meta} score={score} recentCount={recentEntries.length} />}
      {faceName === 'reflection' && <ReflectionFace meta={meta} entries={recentEntries} />}
      {faceName === 'analytics' && (
        <>
          <div className="card-header">
            <span className="card-emoji">{meta.emoji}</span>
            <span className="card-label">{meta.label} — Trends</span>
          </div>
          <div className="card-stat">7-day trend coming soon</div>
        </>
      )}
      {faceName === 'settings' && (
        <>
          <div className="card-header">
            <span className="card-emoji">⚙️</span>
            <span className="card-label">{meta.label} — Settings</span>
          </div>
          <div className="card-stat">Face customization — Phase 2</div>
        </>
      )}
    </div>
  );
}

```
