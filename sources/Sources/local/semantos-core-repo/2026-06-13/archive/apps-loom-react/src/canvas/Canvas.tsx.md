---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/canvas/Canvas.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.935381+00:00
---

# archive/apps-loom-react/src/canvas/Canvas.tsx

```tsx
import { useState, useCallback, useRef, type ReactNode } from 'react';
import { useLoom } from '../state/LoomProvider';
import { LoomCardView } from './LoomCard';
import { ConnectionLine } from './ConnectionLine';
import type { LoomCard } from '../types/loom';

interface Viewport {
  x: number;
  y: number;
  zoom: number;
}

export function Canvas() {
  const { state } = useLoom();
  const [viewport, setViewport] = useState<Viewport>({ x: 0, y: 0, zoom: 1 });
  const isPanning = useRef(false);
  const lastPos = useRef({ x: 0, y: 0 });

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    // Only pan on background click (not on cards)
    if (e.target === e.currentTarget || (e.target as HTMLElement).dataset.canvas) {
      isPanning.current = true;
      lastPos.current = { x: e.clientX, y: e.clientY };
      (e.currentTarget as HTMLElement).style.cursor = 'grabbing';
    }
  }, []);

  const onMouseMove = useCallback((e: React.MouseEvent) => {
    if (!isPanning.current) return;
    const dx = e.clientX - lastPos.current.x;
    const dy = e.clientY - lastPos.current.y;
    lastPos.current = { x: e.clientX, y: e.clientY };
    setViewport(v => ({ ...v, x: v.x + dx, y: v.y + dy }));
  }, []);

  const onMouseUp = useCallback((e: React.MouseEvent) => {
    isPanning.current = false;
    (e.currentTarget as HTMLElement).style.cursor = '';
  }, []);

  const onWheel = useCallback((e: React.WheelEvent) => {
    e.preventDefault();
    const delta = e.deltaY > 0 ? 0.9 : 1.1;
    setViewport(v => ({
      ...v,
      zoom: Math.max(0.25, Math.min(3, v.zoom * delta)),
    }));
  }, []);

  // Collect all connections for SVG rendering
  const connections: { fromCard: LoomCard; toCard: LoomCard; }[] = [];
  for (const card of state.cards.values()) {
    for (const conn of card.connections) {
      const toCard = state.cards.get(conn.toCardId);
      if (toCard) {
        connections.push({ fromCard: card, toCard });
      }
    }
  }

  return (
    <div
      className="flex-1 overflow-hidden relative"
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      onMouseUp={onMouseUp}
      onMouseLeave={onMouseUp}
      onWheel={onWheel}
    >
      {/* Grid background */}
      <div
        className="absolute inset-0"
        data-canvas="true"
        style={{
          backgroundImage: 'radial-gradient(circle, #1f2937 1px, transparent 1px)',
          backgroundSize: `${20 * viewport.zoom}px ${20 * viewport.zoom}px`,
          backgroundPosition: `${viewport.x}px ${viewport.y}px`,
        }}
      />

      {/* Transformed content layer */}
      <div
        className="absolute inset-0"
        style={{
          transform: `translate(${viewport.x}px, ${viewport.y}px) scale(${viewport.zoom})`,
          transformOrigin: '0 0',
        }}
      >
        {/* Connection SVG layer */}
        <svg className="absolute inset-0 w-full h-full pointer-events-none" style={{ overflow: 'visible' }}>
          {connections.map(({ fromCard, toCard }, i) => (
            <ConnectionLine
              key={i}
              fromX={fromCard.position.x + fromCard.size.width}
              fromY={fromCard.position.y + fromCard.size.height / 2}
              toX={toCard.position.x}
              toY={toCard.position.y + toCard.size.height / 2}
            />
          ))}
        </svg>

        {/* Cards */}
        {[...state.cards.values()].map(card => (
          <LoomCardView key={card.id} card={card} />
        ))}
      </div>

      {/* Zoom indicator */}
      <div className="absolute bottom-2 right-2 text-[10px] text-gray-600 font-mono">
        {Math.round(viewport.zoom * 100)}%
      </div>
    </div>
  );
}

```
