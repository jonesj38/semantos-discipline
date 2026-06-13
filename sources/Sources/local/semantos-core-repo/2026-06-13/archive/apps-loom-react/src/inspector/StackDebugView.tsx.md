---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/inspector/StackDebugView.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.944180+00:00
---

# archive/apps-loom-react/src/inspector/StackDebugView.tsx

```tsx
import { useState, useCallback } from 'react';
import { useEngineContext } from '../engine/EngineProvider';

interface StackSlot {
  index: number;
  value: Uint8Array;
  length: number;
}

interface DebugSnapshot {
  pc: number;
  currentOp: number;
  mainStack: StackSlot[];
  altStack: StackSlot[];
}

function readStack(engine: any, isAlt: boolean): StackSlot[] {
  const slots: StackSlot[] = [];
  try {
    const depth = isAlt ? engine.altStackDepth() : engine.stackDepth();
    for (let i = 0; i < Math.min(depth, 16); i++) {
      const value = isAlt ? engine.altStackPeek(i) : engine.stackPeek(i);
      slots.push({ index: i, value, length: value.length });
    }
  } catch {}
  return slots;
}

function captureSnapshot(engine: any): DebugSnapshot {
  return {
    pc: engine.getPC(),
    currentOp: engine.getCurrentOp(),
    mainStack: readStack(engine, false),
    altStack: readStack(engine, true),
  };
}

function StackView({ label, slots }: { label: string; slots: StackSlot[] }) {
  if (slots.length === 0) {
    return (
      <div className="text-[10px] text-gray-600">{label}: empty</div>
    );
  }

  return (
    <div>
      <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-0.5">{label}</div>
      <div className="space-y-px">
        {slots.map(slot => (
          <div key={slot.index} className="flex items-center gap-2 font-mono text-[10px]">
            <span className="text-gray-600 w-4 text-right">{slot.index}</span>
            <span className="text-gray-400 truncate flex-1">
              {Array.from(slot.value).map(b => b.toString(16).padStart(2, '0')).join('') || '(empty)'}
            </span>
            <span className="text-gray-600">{slot.length}B</span>
          </div>
        ))}
      </div>
    </div>
  );
}

export function StackDebugView() {
  const { engine, isReady } = useEngineContext();
  const [snapshots, setSnapshots] = useState<DebugSnapshot[]>([]);
  const [currentIndex, setCurrentIndex] = useState(-1);

  const step = useCallback(() => {
    if (!engine) return;
    try {
      const result = engine.step();
      const snapshot = captureSnapshot(engine);
      setSnapshots(prev => [...prev, snapshot]);
      setCurrentIndex(prev => prev + 1);
    } catch (e) {
      console.error('Step failed:', e);
    }
  }, [engine]);

  const continueExec = useCallback(() => {
    if (!engine) return;
    let steps = 0;
    const maxSteps = 1000;
    try {
      while (steps < maxSteps) {
        const result = engine.step();
        const snapshot = captureSnapshot(engine);
        setSnapshots(prev => [...prev, snapshot]);
        if (result.status !== 0) break;
        steps++;
      }
      setCurrentIndex(snapshots.length + steps - 1);
    } catch {}
  }, [engine, snapshots.length]);

  const reset = useCallback(() => {
    if (!engine) return;
    engine.kernelReset();
    setSnapshots([]);
    setCurrentIndex(-1);
  }, [engine]);

  const current = currentIndex >= 0 ? snapshots[currentIndex] : null;

  if (!isReady) {
    return <div className="p-3 text-xs text-gray-600">Engine not ready</div>;
  }

  return (
    <div className="text-xs space-y-2 p-3">
      <div className="text-[10px] text-gray-500 uppercase tracking-wider">Debug</div>

      {/* Controls */}
      <div className="flex gap-1">
        <button onClick={step} className="px-2 py-0.5 bg-gray-800 hover:bg-gray-700 rounded text-[10px] text-gray-300">
          Step
        </button>
        <button onClick={continueExec} className="px-2 py-0.5 bg-gray-800 hover:bg-gray-700 rounded text-[10px] text-gray-300">
          Continue
        </button>
        <button onClick={reset} className="px-2 py-0.5 bg-gray-800 hover:bg-gray-700 rounded text-[10px] text-gray-300">
          Reset
        </button>
      </div>

      {/* PC / Opcode */}
      {current && (
        <div className="font-mono text-[10px]">
          <span className="text-gray-600">PC:</span>
          <span className="text-gray-300 ml-1">{current.pc}</span>
          <span className="text-gray-600 ml-3">OP:</span>
          <span className="text-gray-300 ml-1">0x{current.currentOp.toString(16).padStart(2, '0')}</span>
        </div>
      )}

      {/* Stacks */}
      <StackView label="Main Stack" slots={current?.mainStack ?? []} />
      <StackView label="Alt Stack" slots={current?.altStack ?? []} />

      {/* Timeline scrubber */}
      {snapshots.length > 0 && (
        <div>
          <div className="text-[10px] text-gray-500 mb-0.5">
            Timeline ({currentIndex + 1} / {snapshots.length})
          </div>
          <input
            type="range"
            min={0}
            max={snapshots.length - 1}
            value={currentIndex}
            onChange={e => setCurrentIndex(Number(e.target.value))}
            className="w-full h-1 accent-blue-500"
          />
        </div>
      )}
    </div>
  );
}

```
