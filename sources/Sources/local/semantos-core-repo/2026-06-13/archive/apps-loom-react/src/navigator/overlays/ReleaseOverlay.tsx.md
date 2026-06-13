---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/overlays/ReleaseOverlay.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.972999+00:00
---

# archive/apps-loom-react/src/navigator/overlays/ReleaseOverlay.tsx

```tsx
import { useState, useRef, useEffect, useCallback } from 'react';
import { useKernel } from '../../contexts/KernelProvider';

interface ReleaseOverlayProps {
  open: boolean;
  onClose: () => void;
}

const PROMPTS = [
  'What am I holding onto?',
  'What am I afraid to say?',
  'What needs to come out?',
  'Where do I feel stuck?',
];

export function ReleaseOverlay({ open, onClose }: ReleaseOverlayProps) {
  const { kernel } = useKernel();
  const [text, setText] = useState('');
  const [seconds, setSeconds] = useState(0);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const startedRef = useRef(false);

  const wordCount = text.trim() ? text.trim().split(/\s+/).length : 0;
  const mm = String(Math.floor(seconds / 60)).padStart(2, '0');
  const ss = String(seconds % 60).padStart(2, '0');

  // Start timer on first keystroke
  useEffect(() => {
    if (text.length > 0 && !startedRef.current) {
      startedRef.current = true;
      timerRef.current = setInterval(() => setSeconds(s => s + 1), 1000);
    }
  }, [text]);

  // Cleanup timer
  useEffect(() => {
    if (!open) {
      if (timerRef.current) clearInterval(timerRef.current);
      timerRef.current = null;
      startedRef.current = false;
      setText('');
      setSeconds(0);
    }
  }, [open]);

  const insertPrompt = useCallback((prompt: string) => {
    setText(prev => (prev ? prev + '\n\n' : '') + prompt + ' ');
  }, []);

  const commit = useCallback(() => {
    if (!text.trim()) return;

    if (timerRef.current) clearInterval(timerRef.current);
    timerRef.current = null;

    const fields = { rawText: text, source: 'keyboard', prompt: 'freeform', valence: 0 };
    kernel?.createObject('Release', fields);

    setText('');
    setSeconds(0);
    startedRef.current = false;
    onClose();
  }, [text, kernel, onClose]);

  return (
    <div className={`nav-overlay ${open ? 'open' : ''}`}>
      <div className="nav-overlay-header">
        <span className="nav-overlay-title">Release</span>
        <button className="nav-overlay-close" onClick={onClose}>×</button>
      </div>
      <div className="nav-overlay-body">
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
          <span style={{ fontSize: 13, color: 'var(--nav-text-30)' }}>{wordCount} word{wordCount !== 1 ? 's' : ''}</span>
          <span style={{ fontSize: 13, color: 'var(--nav-text-30)' }}>{mm}:{ss}</span>
        </div>

        <textarea
          className="nav-form-input"
          rows={8}
          placeholder="Write freely. No one sees this but you..."
          value={text}
          onChange={e => setText(e.target.value)}
          autoFocus
        />

        <div className="nav-prompt-chips">
          {PROMPTS.map(p => (
            <button key={p} className="nav-prompt-chip" onClick={() => insertPrompt(p)}>
              {p}
            </button>
          ))}
        </div>

        <button
          className="nav-btn nav-btn-primary"
          onClick={commit}
          disabled={!text.trim()}
          style={{ marginTop: 16 }}
        >
          Release ↗
        </button>
      </div>
    </div>
  );
}

```
