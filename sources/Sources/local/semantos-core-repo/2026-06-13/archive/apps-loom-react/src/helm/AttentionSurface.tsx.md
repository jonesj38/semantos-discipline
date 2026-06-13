---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/AttentionSurface.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.965810+00:00
---

# archive/apps-loom-react/src/helm/AttentionSurface.tsx

```tsx
import React, { useEffect, useRef, useState, useCallback } from 'react';
import type { AttentionItem, AttentionReason } from '../types/loom';
import type {
  AttentionTelemetry,
  AttentionRules,
} from '../services/index';

export interface AttentionSurfaceProps {
  items: AttentionItem[];
  onItemTap: (item: AttentionItem) => void;
  /** Optional telemetry sink — when present, every interaction is recorded. */
  telemetry?: AttentionTelemetry;
  /** Optional rules service — enables pin/suppress/must-show context menu. */
  rules?: AttentionRules;
}

interface MenuState {
  itemId: string;
  x: number;
  y: number;
}

function linearityLabel(linearity: number): string {
  switch (linearity) {
    case 1: return 'LINEAR';
    case 2: return 'AFFINE';
    case 3: return 'RELEVANT';
    case 4: return 'DEBUG';
    default: return `L${linearity}`;
  }
}

function linearityColor(linearity: number): string {
  switch (linearity) {
    case 1: return 'bg-purple-600/30 text-purple-300';
    case 2: return 'bg-blue-600/30 text-blue-300';
    case 3: return 'bg-green-600/30 text-green-300';
    default: return 'bg-gray-600/30 text-gray-300';
  }
}

function urgencyAccent(urgency: 'immediate' | 'soon' | 'background'): string {
  switch (urgency) {
    case 'immediate': return 'border-l-red-500';
    case 'soon':      return 'border-l-amber-500';
    case 'background': return 'border-l-transparent';
  }
}

function formatTimeSince(ms: number): string {
  const seconds = Math.floor(ms / 1000);
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

function reasonText(reason: AttentionReason): string {
  switch (reason.type) {
    case 'active_work':
      return `Active work \u2014 ${formatTimeSince(reason.lastTouchedAgo)}`;
    case 'deadline_approaching':
      return `Deadline: ${reason.field} in ${formatTimeSince(reason.remainingMs).replace(' ago', '')}`;
    case 'goal_misalignment':
      return `Goal misalignment: ${reason.description}`;
    case 'pending_action':
      return `Pending: ${reason.action}`;
    case 'new_update':
      return `${reason.patchCount} new update${reason.patchCount === 1 ? '' : 's'}`;
    case 'streak_continuation':
      return `${reason.streakDays}-day streak`;
    case 'scheduled':
      return `Scheduled: ${new Date(reason.scheduledTime).toLocaleTimeString()}`;
    case 'extension_signal':
      return `Signal from ${reason.extensionId}: ${reason.signal}`;
  }
}

export function AttentionSurface({ items, onItemTap, telemetry, rules }: AttentionSurfaceProps) {
  const [menu, setMenu] = useState<MenuState | null>(null);
  const cardRefs = useRef<Map<string, HTMLButtonElement>>(new Map());
  const visibleSince = useRef<Map<string, number>>(new Map());
  const surfacedSince = useRef<Map<string, number>>(new Map());

  // Track when items first surface. Emit push-delivered on first appearance
  // (Tier 1 of the TALK notification loop). Emit ignored when items leave
  // without any interaction.
  useEffect(() => {
    const now = Date.now();
    const presentIds = new Set<string>();
    for (const item of items) {
      const id = item.object.id;
      presentIds.add(id);
      if (!surfacedSince.current.has(id)) {
        surfacedSince.current.set(id, now);
        void telemetry?.record({ kind: 'push-delivered', itemId: id, channel: 'push' });
      }
    }
    // For items that scroll out without interaction → emit `ignored`.
    for (const [id, since] of surfacedSince.current.entries()) {
      if (!presentIds.has(id)) {
        const surfaceForMs = now - since;
        if (surfaceForMs > 30_000) {
          void telemetry?.record({ kind: 'ignored', itemId: id, surfaceForMs });
        }
        surfacedSince.current.delete(id);
        visibleSince.current.delete(id);
      }
    }
  }, [items, telemetry]);

  // IntersectionObserver — emit `opened` when a card is visible \u2265 500ms.
  useEffect(() => {
    if (!telemetry) return;
    const observer = new IntersectionObserver((entries) => {
      const now = Date.now();
      for (const entry of entries) {
        const id = entry.target.getAttribute('data-item-id');
        if (!id) continue;
        if (entry.isIntersecting) {
          visibleSince.current.set(id, now);
        } else {
          const since = visibleSince.current.get(id);
          if (since && now - since >= 500) {
            void telemetry.record({
              kind: 'opened',
              itemId: id,
              secondsViewed: Math.floor((now - since) / 1000),
            });
          }
          visibleSince.current.delete(id);
        }
      }
    }, { threshold: 0.5 });
    for (const [, el] of cardRefs.current) observer.observe(el);
    return () => observer.disconnect();
  }, [items, telemetry]);

  // Close context menu on outside click / Escape.
  useEffect(() => {
    if (!menu) return;
    const close = () => setMenu(null);
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') close(); };
    document.addEventListener('click', close);
    document.addEventListener('keydown', esc);
    return () => {
      document.removeEventListener('click', close);
      document.removeEventListener('keydown', esc);
    };
  }, [menu]);

  const handleTap = useCallback((item: AttentionItem, rank: number) => {
    void telemetry?.record({
      kind: 'tapped',
      itemId: item.object.id,
      rank,
      relevance: item.relevance,
      primaryReason: item.reason.type,
    });
    onItemTap(item);
  }, [onItemTap, telemetry]);

  const handleContextMenu = useCallback((e: React.MouseEvent, item: AttentionItem) => {
    if (!rules) return;
    e.preventDefault();
    setMenu({ itemId: item.object.id, x: e.clientX, y: e.clientY });
  }, [rules]);

  const handlePin = useCallback(async (item: AttentionItem) => {
    await rules?.pin(item.object.id);
    await telemetry?.record({ kind: 'pinned', itemId: item.object.id });
    setMenu(null);
  }, [rules, telemetry]);

  const handleSuppressClass = useCallback(async (item: AttentionItem) => {
    const pattern = item.object.typeDefinition?.name ?? item.object.id;
    await rules?.suppress(pattern);
    await telemetry?.record({ kind: 'suppressed', itemId: item.object.id, pattern });
    setMenu(null);
  }, [rules, telemetry]);

  const handleSuppressUntilTomorrow = useCallback(async (item: AttentionItem) => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    await rules?.suppress(item.object.id, { until: tomorrow.toISOString() });
    await telemetry?.record({
      kind: 'suppressed',
      itemId: item.object.id,
      pattern: item.object.id,
    });
    setMenu(null);
  }, [rules, telemetry]);

  const handleAlwaysShow = useCallback(async (item: AttentionItem) => {
    const pattern = item.object.typeDefinition?.name ?? item.object.id;
    await rules?.mustShow(pattern, 0.30);
    setMenu(null);
  }, [rules]);

  const handleDismiss = useCallback(async (item: AttentionItem, e: React.MouseEvent) => {
    e.stopPropagation();
    await telemetry?.record({
      kind: 'dismissed',
      itemId: item.object.id,
      explicit: true,
    });
  }, [telemetry]);

  if (items.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-gray-500 px-6 py-12">
        <span className="text-4xl mb-3">{'\u2693'}</span>
        <p className="text-sm font-medium">Nothing needs your attention right now.</p>
        <p className="text-xs mt-1 text-gray-600">
          Objects will surface here as they become relevant.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-1 p-2 overflow-y-auto">
      {items.map((item, index) => {
        const obj = item.object;
        const name = (obj.payload.name as string)
          || (obj.payload.title as string)
          || obj.typeDefinition?.name
          || obj.id;
        const now = Date.now();
        const timeSince = now - obj.updatedAt;

        return (
          <button
            key={obj.id}
            data-item-id={obj.id}
            ref={(el) => {
              if (el) cardRefs.current.set(obj.id, el);
              else cardRefs.current.delete(obj.id);
            }}
            onClick={() => handleTap(item, index)}
            onContextMenu={(e) => handleContextMenu(e, item)}
            className={`
              w-full text-left border-l-4 ${urgencyAccent(item.urgency)}
              bg-gray-800/60 hover:bg-gray-800 rounded-r-lg px-3 py-2.5
              transition-colors cursor-pointer relative group
            `}
          >
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-gray-100 truncate">
                    {name}
                  </span>
                  <span className={`text-[10px] font-mono px-1.5 py-0.5 rounded ${linearityColor(obj.header.linearity)}`}>
                    {linearityLabel(obj.header.linearity)}
                  </span>
                </div>

                <p className="text-xs text-gray-400 mt-0.5">
                  {reasonText(item.reason)}
                </p>
              </div>

              <div className="flex flex-col items-end gap-1 shrink-0">
                <span className="text-[10px] text-gray-500">
                  {formatTimeSince(timeSince)}
                </span>
                {obj.patches.length > 0 && (
                  <span className="text-[10px] text-gray-500">
                    {obj.patches.length} patch{obj.patches.length === 1 ? '' : 'es'}
                  </span>
                )}
              </div>
            </div>

            <div className="flex items-center gap-2 mt-1">
              <span className="text-[10px] text-gray-500 font-mono">
                {(item.relevance * 100).toFixed(0)}%
              </span>
              <span className="text-[10px] text-gray-600">
                {item.primaryMode}
              </span>
            </div>

            {telemetry && (
              <span
                role="button"
                aria-label="Dismiss"
                title="Dismiss"
                onClick={(e) => void handleDismiss(item, e)}
                className="absolute top-1.5 right-1.5 text-[10px] text-gray-600 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity px-1.5 py-0.5"
              >
                {'\u2715'}
              </span>
            )}
          </button>
        );
      })}

      {menu && rules && (
        <div
          className="fixed z-50 bg-gray-900 border border-gray-700 rounded shadow-lg py-1 text-sm min-w-[180px]"
          style={{ top: menu.y, left: menu.x }}
          onClick={(e) => e.stopPropagation()}
        >
          {(() => {
            const item = items.find(i => i.object.id === menu.itemId);
            if (!item) return null;
            return (
              <>
                <button
                  onClick={() => void handlePin(item)}
                  className="w-full text-left px-3 py-1.5 hover:bg-gray-800 text-gray-200"
                >
                  {'\u2691'} Pin
                </button>
                <button
                  onClick={() => void handleSuppressClass(item)}
                  className="w-full text-left px-3 py-1.5 hover:bg-gray-800 text-gray-200"
                >
                  Suppress class
                </button>
                <button
                  onClick={() => void handleSuppressUntilTomorrow(item)}
                  className="w-full text-left px-3 py-1.5 hover:bg-gray-800 text-gray-200"
                >
                  Suppress until tomorrow
                </button>
                <button
                  onClick={() => void handleAlwaysShow(item)}
                  className="w-full text-left px-3 py-1.5 hover:bg-gray-800 text-gray-200"
                >
                  Always show class
                </button>
              </>
            );
          })()}
        </div>
      )}
    </div>
  );
}

```
