---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/overlays/IntentionOverlay.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.972711+00:00
---

# archive/apps-loom-react/src/navigator/overlays/IntentionOverlay.tsx

```tsx
import { useState, useEffect } from 'react';
import { useKernel } from '../../contexts/KernelProvider';
import { DIMENSIONS_ENUM } from '../../hooks/useDimensions';

interface IntentionOverlayProps {
  open: boolean;
  onClose: () => void;
}

const DIM_MAP: Record<string, string> = {
  mental: 'MENTAL', physical: 'PHYSICAL', spiritual: 'SPIRITUAL',
  social: 'SOCIAL', vocational: 'VOCATIONAL', financial: 'FINANCIAL', familial: 'FAMILIAL',
};

export function IntentionOverlay({ open, onClose }: IntentionOverlayProps) {
  const { kernel } = useKernel();
  const [step, setStep] = useState(0);
  const [dimension, setDimension] = useState<string | null>(null);
  const [intention, setIntention] = useState('');
  const [action, setAction] = useState('');

  useEffect(() => {
    if (!open) {
      setStep(0);
      setDimension(null);
      setIntention('');
      setAction('');
    }
  }, [open]);

  const save = () => {
    const fields = {
      date: new Date().toISOString().split('T')[0],
      todayIntention: intention,
      concreteAction: action,
      primaryDimension: dimension ? (DIM_MAP[dimension] || dimension) : undefined,
    };
    kernel?.createObject('MorningIntention', fields);
    onClose();
  };

  const selectedDim = DIMENSIONS_ENUM.find(d => d.id === dimension);

  return (
    <div className={`nav-overlay ${open ? 'open' : ''}`}>
      <div className="nav-overlay-header">
        <span className="nav-overlay-title">Morning Intention</span>
        <button className="nav-overlay-close" onClick={onClose}>×</button>
      </div>
      <div className="nav-overlay-body">
        {step === 0 && (
          <>
            <div className="nav-form-label">Pick your focus</div>
            <div className="nav-form-hint">Which dimension calls for attention today?</div>
            <div className="nav-dim-grid">
              {DIMENSIONS_ENUM.map(d => (
                <div
                  key={d.id}
                  className={`nav-dim-pick ${dimension === d.id ? 'selected' : ''}`}
                  onClick={() => setDimension(d.id)}
                >
                  <span style={{ fontSize: 20 }}>{d.emoji}</span>
                  <span>{d.label}</span>
                </div>
              ))}
            </div>
            <button
              className="nav-btn nav-btn-primary"
              style={{ marginTop: 16 }}
              disabled={!dimension}
              onClick={() => setStep(1)}
            >
              Next
            </button>
          </>
        )}

        {step === 1 && selectedDim && (
          <>
            <div
              style={{
                display: 'inline-flex', alignItems: 'center', gap: 6,
                padding: '6px 14px', borderRadius: 'var(--nav-radius-pill)',
                border: '1px solid var(--nav-blue)', color: 'var(--nav-blue)',
                fontSize: 13, marginBottom: 16,
              }}
            >
              {selectedDim.emoji} {selectedDim.label}
            </div>

            <div className="nav-form-label">Your intention</div>
            <div className="nav-form-hint">What do you intend to bring to {selectedDim.label.toLowerCase()} today?</div>
            <textarea
              className="nav-form-input"
              rows={3}
              placeholder="Today I intend to..."
              value={intention}
              onChange={e => setIntention(e.target.value)}
              autoFocus
            />

            <div className="nav-form-label" style={{ marginTop: 8 }}>Concrete action</div>
            <div className="nav-form-hint">One specific thing you'll do.</div>
            <textarea
              className="nav-form-input"
              rows={2}
              placeholder="I will..."
              value={action}
              onChange={e => setAction(e.target.value)}
            />

            <div style={{ display: 'flex', gap: 8 }}>
              <button className="nav-btn nav-btn-subtle" style={{ flex: 1 }} onClick={() => setStep(0)}>Back</button>
              <button className="nav-btn nav-btn-primary" style={{ flex: 2 }} onClick={save}>Set Intention</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

```
