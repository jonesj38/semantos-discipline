---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/overlays/ReviewOverlay.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.972398+00:00
---

# archive/apps-loom-react/src/navigator/overlays/ReviewOverlay.tsx

```tsx
import { useState, useEffect } from 'react';
import { useKernel } from '../../contexts/KernelProvider';
import { DIMENSIONS_ENUM } from '../../hooks/useDimensions';

interface ReviewOverlayProps {
  open: boolean;
  onClose: () => void;
}

interface ReviewData {
  wins: [string, string, string];
  improvements: [string, string, string];
  intention: string;
  energy: number;
  mood: number;
  dimensions: Record<string, number>;
}

const INITIAL: ReviewData = {
  wins: ['', '', ''],
  improvements: ['', '', ''],
  intention: '',
  energy: 5,
  mood: 5,
  dimensions: {},
};

export function ReviewOverlay({ open, onClose }: ReviewOverlayProps) {
  const { kernel } = useKernel();
  const [step, setStep] = useState(0);
  const [data, setData] = useState<ReviewData>({ ...INITIAL, wins: ['', '', ''], improvements: ['', '', ''] });

  useEffect(() => {
    if (!open) {
      setStep(0);
      setData({ ...INITIAL, wins: ['', '', ''], improvements: ['', '', ''] });
    }
  }, [open]);

  const setWin = (i: number, v: string) => {
    const wins = [...data.wins] as [string, string, string];
    wins[i] = v;
    setData(d => ({ ...d, wins }));
  };

  const setImprovement = (i: number, v: string) => {
    const improvements = [...data.improvements] as [string, string, string];
    improvements[i] = v;
    setData(d => ({ ...d, improvements }));
  };

  const setDimension = (id: string, v: number) => {
    setData(d => ({ ...d, dimensions: { ...d.dimensions, [id]: v } }));
  };

  const save = () => {
    const fields = {
      date: new Date().toISOString().split('T')[0],
      win1: data.wins[0].trim(),
      win2: data.wins[1].trim(),
      win3: data.wins[2].trim(),
      improve1: data.improvements[0].trim(),
      improve2: data.improvements[1].trim(),
      improve3: data.improvements[2].trim(),
      tomorrowIntention: data.intention,
      energyLevel: data.energy,
      moodLevel: data.mood,
    };
    kernel?.createObject('DailyReview', fields);
    onClose();
  };

  const totalSteps = 5;

  return (
    <div className={`nav-overlay ${open ? 'open' : ''}`}>
      <div className="nav-overlay-header">
        <span className="nav-overlay-title">Evening Review</span>
        <button className="nav-overlay-close" onClick={onClose}>×</button>
      </div>
      <div className="nav-overlay-body">
        {/* Progress */}
        <div className="nav-progress">
          {Array.from({ length: totalSteps }, (_, i) => (
            <div key={i} className={`nav-progress-seg ${i <= step ? 'done' : ''}`} />
          ))}
        </div>

        {/* Step 0: Wins */}
        {step === 0 && (
          <>
            <div className="nav-form-label">What went well today?</div>
            <div className="nav-form-hint">Three things you did well, no matter how small.</div>
            {[0, 1, 2].map(i => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ fontSize: 12, color: 'var(--nav-text-30)', width: 16 }}>{i + 1}</span>
                <textarea
                  className="nav-form-input"
                  rows={2}
                  placeholder="Something that went well..."
                  value={data.wins[i]}
                  onChange={e => setWin(i, e.target.value)}
                />
              </div>
            ))}
            <button className="nav-btn nav-btn-primary" onClick={() => setStep(1)}>Next</button>
          </>
        )}

        {/* Step 1: Improvements */}
        {step === 1 && (
          <>
            <div className="nav-form-label">What could be better?</div>
            <div className="nav-form-hint">Three things to improve — honest, not harsh.</div>
            {[0, 1, 2].map(i => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ fontSize: 12, color: 'var(--nav-text-30)', width: 16 }}>{i + 1}</span>
                <textarea
                  className="nav-form-input"
                  rows={2}
                  placeholder="Something to improve..."
                  value={data.improvements[i]}
                  onChange={e => setImprovement(i, e.target.value)}
                />
              </div>
            ))}
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="nav-btn nav-btn-subtle" style={{ flex: 1 }} onClick={() => setStep(0)}>Back</button>
              <button className="nav-btn nav-btn-primary" style={{ flex: 2 }} onClick={() => setStep(2)}>Next</button>
            </div>
          </>
        )}

        {/* Step 2: Energy + Mood */}
        {step === 2 && (
          <>
            <div className="nav-form-label">How are you feeling?</div>
            <div className="nav-form-hint">Check in with your body and mind.</div>

            <div style={{ margin: '16px 0' }}>
              <div style={{ fontSize: 13, color: 'var(--nav-text-50)', marginBottom: 8 }}>Energy</div>
              <div className="nav-slider-row">
                <span>😴</span>
                <div className="nav-slider-wrap">
                  <input
                    type="range" min="1" max="10" value={data.energy}
                    onChange={e => setData(d => ({ ...d, energy: +e.target.value }))}
                  />
                </div>
                <span className="nav-slider-val">{data.energy}</span>
                <span>⚡</span>
              </div>
            </div>

            <div style={{ margin: '16px 0' }}>
              <div style={{ fontSize: 13, color: 'var(--nav-text-50)', marginBottom: 8 }}>Mood</div>
              <div className="nav-slider-row">
                <span>😔</span>
                <div className="nav-slider-wrap">
                  <input
                    type="range" min="1" max="10" value={data.mood}
                    onChange={e => setData(d => ({ ...d, mood: +e.target.value }))}
                  />
                </div>
                <span className="nav-slider-val">{data.mood}</span>
                <span>😊</span>
              </div>
            </div>

            <div style={{ display: 'flex', gap: 8 }}>
              <button className="nav-btn nav-btn-subtle" style={{ flex: 1 }} onClick={() => setStep(1)}>Back</button>
              <button className="nav-btn nav-btn-primary" style={{ flex: 2 }} onClick={() => setStep(3)}>Next</button>
            </div>
          </>
        )}

        {/* Step 3: Dimensions */}
        {step === 3 && (
          <>
            <div className="nav-form-label">Rate your dimensions</div>
            <div className="nav-form-hint">How did each area of life go today?</div>
            {DIMENSIONS_ENUM.map(d => {
              const val = data.dimensions[d.id] ?? 5;
              return (
                <div key={d.id} style={{ marginBottom: 12 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                    <span style={{ fontSize: 16 }}>{d.emoji}</span>
                    <span style={{ fontSize: 13, color: 'var(--nav-text-70)' }}>{d.label}</span>
                  </div>
                  <div className="nav-slider-row">
                    <div className="nav-slider-wrap">
                      <input
                        type="range" min="1" max="10" value={val}
                        onChange={e => setDimension(d.id, +e.target.value)}
                      />
                    </div>
                    <span className="nav-slider-val">{val}</span>
                  </div>
                </div>
              );
            })}
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="nav-btn nav-btn-subtle" style={{ flex: 1 }} onClick={() => setStep(2)}>Back</button>
              <button className="nav-btn nav-btn-primary" style={{ flex: 2 }} onClick={() => setStep(4)}>Next</button>
            </div>
          </>
        )}

        {/* Step 4: Tomorrow */}
        {step === 4 && (
          <>
            <div className="nav-form-label">What about tomorrow?</div>
            <div className="nav-form-hint">One intention to carry forward.</div>
            <textarea
              className="nav-form-input"
              rows={3}
              placeholder="Tomorrow I will..."
              value={data.intention}
              onChange={e => setData(d => ({ ...d, intention: e.target.value }))}
            />
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="nav-btn nav-btn-subtle" style={{ flex: 1 }} onClick={() => setStep(3)}>Back</button>
              <button className="nav-btn nav-btn-primary" style={{ flex: 2 }} onClick={save}>Save Review</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

```
