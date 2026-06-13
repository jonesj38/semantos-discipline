---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/dock/Dock.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.974773+00:00
---

# archive/apps-loom-react/src/helm/dock/Dock.tsx

```tsx
/**
 * Dock — the 1-3-5 bottom dock (macOS-style stacks).
 *
 * Tier 1: 3 intent icons (Do / Talk / Find) + Home anchor — always visible.
 * Tier 2: 5 context icons for the active intent — pops up above tier 1.
 * Tier 3: favourites + text + mic for the active context — pops up above tier 2.
 *
 * Progressive disclosure: click intent → tier 2; click context → tier 3.
 * Click anywhere else or press Esc → collapse to tier 1.
 *
 * Keyboard path mirrors mouse (per docs/BRAINSTORM-DOCK-SHELL-SILOS.md §9):
 *   D → Do, T → Talk, F → Find
 *   Then C / M / T / P / O … (first letter of a visible context)
 *   1–5: invoke the Nth favourite once tier 3 is open.
 */

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Tier3Popover } from './Tier3Popover';
import { SlotLauncher } from '../SlotLauncher';
import {
  KERNEL_CONTEXT_WEIGHTS,
  resolveFavourites,
  DO_CONTEXTS,
  TALK_CONTEXTS,
  FIND_CONTEXTS,
  type ContextPath,
  type IntentId,
} from './context-weights';
import type { IntentContext } from '../../services/index';
import type { ShellDispatchResult } from '../../hooks/useShellDispatch';

export interface DockProps {
  /** Called when a shell command completes (for detail pane / canvas refresh). */
  onInvoke: (command: string, result: ShellDispatchResult) => void;
  /** Called when the Home anchor is clicked — return to attention surface. */
  onGoHome: () => void;
  /** Home anchor badge (immediate attention count). */
  homeBadge?: number;
  /** Which intent is visually "active" — i.e. which has its tier-2 open. */
  activeIntent: IntentId | null;
  /** Setter for activeIntent. */
  setActiveIntent: (intent: IntentId | null) => void;
}

interface IntentDef {
  id: IntentId;
  label: string;
  icon: string;
  key: string; // keyboard trigger
}

const INTENTS: IntentDef[] = [
  { id: 'do', label: 'Do', icon: '\u26A1', key: 'd' },
  { id: 'talk', label: 'Talk', icon: '\uD83D\uDCAC', key: 't' },
  { id: 'find', label: 'Find', icon: '\uD83D\uDD0D', key: 'f' },
];

function contextsFor(intent: IntentId) {
  if (intent === 'do') return DO_CONTEXTS;
  if (intent === 'talk') return TALK_CONTEXTS;
  return FIND_CONTEXTS;
}

export function Dock({ onInvoke, onGoHome, homeBadge = 0, activeIntent, setActiveIntent }: DockProps) {
  const [activeContext, setActiveContext] = useState<string | null>(null);

  // Close tier 2/3 when clicking outside the dock.
  useEffect(() => {
    if (!activeIntent) return;
    const handler = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      if (target.closest('[data-dock-root]')) return;
      setActiveIntent(null);
      setActiveContext(null);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [activeIntent, setActiveIntent]);

  // Keyboard shortcuts: d / t / f open tier 2; Esc closes.
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      // Skip when typing in an input/textarea/cm-editor.
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      if ((e.target as HTMLElement)?.closest('.cm-editor')) return;
      if (e.ctrlKey || e.metaKey || e.altKey) return;

      if (e.key === 'Escape') {
        setActiveContext(null);
        setActiveIntent(null);
        return;
      }

      const intent = INTENTS.find(i => i.key === e.key.toLowerCase());
      if (intent) {
        e.preventDefault();
        if (activeIntent === intent.id) {
          setActiveIntent(null);
          setActiveContext(null);
        } else {
          setActiveIntent(intent.id);
          setActiveContext(null);
        }
        return;
      }

      // Number keys 1–5: invoke Nth favourite when tier 3 is open.
      if (activeIntent && activeContext && /^[1-5]$/.test(e.key)) {
        const idx = parseInt(e.key, 10) - 1;
        const path = `${activeIntent}.${activeContext}` as ContextPath;
        const favs = resolveFavourites(path, KERNEL_CONTEXT_WEIGHTS);
        const fav = favs[idx];
        if (fav) {
          e.preventDefault();
          // Synthesize the same invoke path as a click.
          void (async () => {
            // dispatch via the parent — no useShellDispatch needed here
            // because Tier3Popover owns it; just simulate a click by
            // opening context then letting user press Enter.
            // Simplest: delegate to the popover's button by data-fav-idx.
            const btn = document.querySelector<HTMLButtonElement>(
              `[data-dock-root] [data-fav-idx="${idx}"]`,
            );
            btn?.click();
          })();
        }
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [activeIntent, activeContext, setActiveIntent]);

  const tier3 = useMemo(() => {
    if (!activeIntent || !activeContext) return null;
    const path = `${activeIntent}.${activeContext}` as ContextPath;
    const favourites = resolveFavourites(path, KERNEL_CONTEXT_WEIGHTS);
    const ctxDef = contextsFor(activeIntent).find(c => c.id === activeContext);
    if (!ctxDef) return null;
    return { path, favourites, ctxDef };
  }, [activeIntent, activeContext]);

  const handleIntentClick = useCallback((intent: IntentId) => {
    if (activeIntent === intent) {
      setActiveIntent(null);
      setActiveContext(null);
    } else {
      setActiveIntent(intent);
      setActiveContext(null);
    }
  }, [activeIntent, setActiveIntent]);

  const handleContextClick = useCallback((contextId: string) => {
    setActiveContext(prev => (prev === contextId ? null : contextId));
  }, []);

  const handleInvoke = useCallback((command: string, result: ShellDispatchResult) => {
    onInvoke(command, result);
    // Close dock after a successful invocation.
    if (result.ok) {
      setActiveContext(null);
      setActiveIntent(null);
    }
  }, [onInvoke, setActiveIntent]);

  const handleTier3Close = useCallback(() => {
    setActiveContext(null);
  }, []);

  const activeSlot = useMemo((): IntentContext | null => {
    if (!activeIntent || !activeContext) return null;
    return `${activeIntent}.${activeContext}` as IntentContext;
  }, [activeIntent, activeContext]);

  return (
    <div data-dock-root className="relative shrink-0">
      {/* Tier 3 popover — sits above tier-2 strip (tier-2 is ~72px tall starting at bottom-64) */}
      {tier3 && (
        <div className="absolute bottom-[148px] left-1/2 -translate-x-1/2 z-30 flex gap-2 items-end">
          <Tier3Popover
            contextPath={tier3.path}
            contextLabel={tier3.ctxDef.label}
            contextIcon={tier3.ctxDef.icon}
            favourites={tier3.favourites}
            onInvoke={handleInvoke}
            onClose={handleTier3Close}
          />
          {/* SlotLauncher panel — Pask-ranked shortlist for this context */}
          {activeSlot && (
            <SlotLauncher
              slot={activeSlot}
              onInvoke={handleInvoke}
              onClose={handleTier3Close}
            />
          )}
        </div>
      )}

      {/* Tier 2 context strip */}
      {activeIntent && (
        <div className="absolute bottom-[64px] left-1/2 -translate-x-1/2 z-20">
          <div className="flex items-center gap-1 bg-gray-900/95 border border-gray-700 rounded-lg shadow-xl px-2 py-1">
            {contextsFor(activeIntent).map(ctx => {
              const isActive = activeContext === ctx.id;
              return (
                <button
                  key={ctx.id}
                  onClick={() => handleContextClick(ctx.id)}
                  className={`flex flex-col items-center justify-center w-14 h-14 rounded transition-colors ${
                    isActive
                      ? 'bg-gray-700 text-gray-100'
                      : 'text-gray-400 hover:text-gray-100 hover:bg-gray-800'
                  }`}
                  title={ctx.description}
                  aria-label={ctx.label}
                >
                  <span className="text-xl leading-none mb-0.5">{ctx.icon}</span>
                  <span className="text-[10px] font-medium">{ctx.label}</span>
                </button>
              );
            })}
          </div>
        </div>
      )}

      {/* Tier 1: intents + home */}
      <nav className="flex items-center justify-around border-t border-gray-700 bg-gray-900 px-2 py-1 h-[64px]">
        <DockBtn
          icon={'\u2693'}
          label="Home"
          active={false}
          onClick={onGoHome}
          badge={homeBadge}
        />
        {INTENTS.map(intent => (
          <DockBtn
            key={intent.id}
            icon={intent.icon}
            label={intent.label}
            active={activeIntent === intent.id}
            onClick={() => handleIntentClick(intent.id)}
            hotkey={intent.key.toUpperCase()}
          />
        ))}
      </nav>
    </div>
  );
}

interface DockBtnProps {
  icon: string;
  label: string;
  active: boolean;
  onClick: () => void;
  badge?: number;
  hotkey?: string;
}

function DockBtn({ icon, label, active, onClick, badge = 0, hotkey }: DockBtnProps) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      className={`relative flex flex-col items-center gap-0.5 px-6 py-1.5 rounded-lg transition-colors ${
        active
          ? 'text-blue-400 bg-gray-800'
          : 'text-gray-400 hover:text-gray-200 hover:bg-gray-800/50'
      }`}
    >
      <span className="relative text-lg leading-none">
        {icon}
        {badge > 0 && (
          <span className="absolute -top-1 -right-2 min-w-[18px] h-[18px] flex items-center justify-center rounded-full bg-red-500 text-white text-[10px] font-semibold px-1">
            {badge > 99 ? '99+' : badge}
          </span>
        )}
      </span>
      <span className="text-[11px] font-medium flex items-center gap-1">
        {label}
        {hotkey && (
          <kbd className="text-[9px] font-mono text-gray-600 border border-gray-700 rounded px-1 leading-none py-[1px]">
            {hotkey}
          </kbd>
        )}
      </span>
    </button>
  );
}

```
