---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/components/HelmPrimitives.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.051646+00:00
---

# apps/oddjobtodd/src/components/HelmPrimitives.tsx

```tsx
import { useState, useRef, type ReactNode } from 'react';

// ── 4-node dock ──────────────────────────────────────────────────────
export function Dock({ active = 'home', activated = [] }: { active?: string; activated?: string[] }) {
  const nodes = [
    { id: 'home', glyph: '⚓', label: 'home' },
    { id: 'do',   glyph: '⚡', label: 'do' },
    { id: 'talk', glyph: '◌', label: 'talk' },
    { id: 'find', glyph: '○', label: 'find' },
  ];
  return (
    <div className="dock">
      {nodes.map(n => (
        <div key={n.id}
          className={`node ${active === n.id ? 'active' : ''} ${activated.includes(n.id) ? 'activated' : ''}`}>
          <div className="glyph">{n.glyph}</div>
          <div className="label">{n.label}</div>
        </div>
      ))}
    </div>
  );
}

// ── Ribbon top bar ───────────────────────────────────────────────────
export function Ribbon({ hat = 'Worker', signal = '' }: { hat?: string; signal?: string }) {
  return (
    <div className="ribbon">
      <div className="hat"><span className="dot" />{hat}</div>
      <div className="signal-state">{signal}</div>
    </div>
  );
}

// ── Capture FAB (triple-click for camera mode) ───────────────────────
function CaptureFab({ live }: { live?: boolean }) {
  const [mode, setMode] = useState<'voice' | 'camera'>('voice');
  const [shot, setShot] = useState<'photo' | 'video'>('photo');
  const clicks = useRef<number[]>([]);
  const idleTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const armIdleTimer = () => {
    if (idleTimer.current) clearTimeout(idleTimer.current);
    idleTimer.current = setTimeout(() => setMode('voice'), 6000);
  };
  const dismiss = () => {
    if (idleTimer.current) clearTimeout(idleTimer.current);
    setMode('voice');
  };

  const onClick = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (mode === 'camera') return;
    const now = Date.now();
    clicks.current = [...clicks.current, now].filter(t => now - t < 600);
    if (clicks.current.length >= 3) {
      clicks.current = [];
      setMode('camera');
      armIdleTimer();
    }
  };

  if (mode === 'voice') {
    return (
      <div className={`mic-fab ${live ? 'live' : ''}`} onClick={onClick} title="triple-click for camera">◉</div>
    );
  }
  return (
    <>
      <div className="capture-switch" onClick={armIdleTimer}>
        <button className={shot === 'photo' ? 'on' : ''}
          onClick={e => { e.stopPropagation(); setShot('photo'); armIdleTimer(); }}>▣ photo</button>
        <button className={shot === 'video' ? 'on' : ''}
          onClick={e => { e.stopPropagation(); setShot('video'); armIdleTimer(); }}>● video</button>
        <button className="dismiss" onClick={e => { e.stopPropagation(); dismiss(); }} title="back to voice">✕</button>
      </div>
      <div className={`mic-fab camera ${shot}`}
        onClick={e => { e.stopPropagation(); armIdleTimer(); }}
        title={shot === 'photo' ? 'tap to capture' : 'tap to start recording'}>
        {shot === 'photo' ? '▣' : '●'}
      </div>
    </>
  );
}

export function Mic({ variant = 'fab', live = false }: { variant?: string; live?: boolean }) {
  if (variant === 'hidden') return null;
  if (variant === 'edge') return <div className="mic-fab edge">swipe ↑ to speak</div>;
  if (variant === 'bar')  return <div className="mic-fab bar">tap or hold to speak</div>;
  return <CaptureFab live={live} />;
}

// ── Stage trail ──────────────────────────────────────────────────────
const STAGES = [
  { id: 'lead',     lbl: 'lead' },
  { id: 'quote',    lbl: 'quoted' },
  { id: 'sched',    lbl: 'scheduled' },
  { id: 'onsite',   lbl: 'on-site' },
  { id: 'done',     lbl: 'done' },
  { id: 'invoiced', lbl: 'invoiced' },
  { id: 'paid',     lbl: 'paid' },
];

export function StageTrail({ at, compact = false, withWhen = {} }: {
  at: string;
  compact?: boolean;
  withWhen?: Record<string, string>;
}) {
  const idx = STAGES.findIndex(s => s.id === at);
  if (compact) {
    return (
      <div className="stage-trail">
        {STAGES.map((s, i) => {
          const cls = i < idx ? 'done' : i === idx ? 'now' : '';
          return (
            <>
              <div key={s.id} className={`stage ${cls}`}>
                <div className="pip" />
                {i === idx && <span className="lbl">{s.lbl}</span>}
              </div>
              {i < STAGES.length - 1 && <div key={`c${i}`} className={`conn ${i < idx ? 'done' : ''}`} />}
            </>
          );
        })}
      </div>
    );
  }
  return (
    <div className="stage-trail-v">
      {STAGES.map((s, i) => {
        const cls = i < idx ? 'done' : i === idx ? 'now' : '';
        return (
          <div key={s.id} className={`stage ${cls}`}>
            <div className="pip" />
            <div className="lbl">{s.lbl}</div>
            {withWhen[s.id] && <div className="when">{withWhen[s.id]}</div>}
          </div>
        );
      })}
    </div>
  );
}

// ── Sentence grammar ─────────────────────────────────────────────────
export function Sentence({ filled = {}, live = null }: {
  filled?: Record<string, string>;
  live?: string | null;
}) {
  const slots = [
    { id: 'what',  prefix: 'I need ',     fallback: '_______' },
    { id: 'where', prefix: ' at ',        fallback: '_______' },
    { id: 'when',  prefix: ' by ',        fallback: '_______' },
    { id: 'who',   prefix: ' — someone ', fallback: '_______' },
    { id: 'worth', prefix: ' for ',       fallback: '_______' },
  ];
  return (
    <div className="sentence">
      {slots.map(s => {
        const isLive = live === s.id;
        const val = filled[s.id];
        const cls = val ? 'slot filled' : isLive ? 'slot live' : 'slot';
        return (
          <>
            <span key={`p${s.id}`} style={{ color: 'var(--ink)' }}>{s.prefix}</span>
            <span key={s.id} className={cls}>
              {val || (isLive ? '…listening' : s.fallback)}
              <span className="tag">{s.id}</span>
            </span>
          </>
        );
      })}
      <span style={{ color: 'var(--ink)' }}>.</span>
    </div>
  );
}

// ── Frame card (device mockup) ───────────────────────────────────────
export function Frame({ label, sub, topoTag, children, annotation }: {
  label: string;
  sub?: string;
  topoTag?: string;
  children: ReactNode;
  annotation?: string;
}) {
  return (
    <div className="frame-card" data-screen-label={label}>
      <div>
        <div className="frame-label">{label}</div>
        {sub && <div className="frame-sub">{sub}</div>}
      </div>
      <div className="device" style={{ position: 'relative' }}>
        {topoTag && <div className="topo-tag">{topoTag}</div>}
        <div className="status">
          <span>09:41 · helm</span>
          <span className="right">
            <span className="bar" /><span className="bar" /><span className="bar" /><span className="bar" />
          </span>
        </div>
        {children}
      </div>
      {annotation && (
        <div className="annot">
          <div className="arrow">↑ note</div>
          <div>{annotation}</div>
        </div>
      )}
    </div>
  );
}

```
