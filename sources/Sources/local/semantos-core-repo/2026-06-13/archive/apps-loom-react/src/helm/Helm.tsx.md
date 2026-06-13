---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/Helm.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.966657+00:00
---

# archive/apps-loom-react/src/helm/Helm.tsx

```tsx
/**
 * Helm — the attention surface + 1-3-5 dock.
 *
 * Layout (per docs/EXTENSIONS-VS-TYPES.md + docs/BRAINSTORM-DOCK-SHELL-SILOS.md):
 *
 *   [ hat ▾ ]  Semantos  [ workspace ▾ ]   >_   ≡
 *   ────────────────────────────────────────────────
 *   pinned strip (when any)
 *   ─────
 *   AttentionSurface (auto-surfaced items)
 *
 *   ┌─ DetailPane (overlay when a dock action fires) ─┐
 *
 *   TerminalPanel (toggle via `)
 *
 *   Dock — tier 1 (3 intents + Home) / tier 2 (5 contexts) / tier 3 (favs + text + mic)
 */

import React, { useState, useEffect, useMemo, useCallback } from 'react';
import type { AttentionItem } from '../types/loom';
import type { LoomStore } from '../services/LoomStore';
import { AttentionEngine } from '../services/AttentionEngine';
import {
  configStore as singletonConfigStore,
  loomStore as singletonLoomStore,
  attentionTelemetry,
  attentionWeightLearner,
  attentionRules,
  attentionSignals,
  paskGraph,
} from '../services/index';
import type { ConfigStore } from '../services/ConfigStore';
import { useAttention } from '../hooks/useAttention';
import { AttentionSurface } from './AttentionSurface';
import { SupportDrawer } from './SupportDrawer';
import { HatSwitcher } from './HatSwitcher';
import { ExtensionSwitcher } from './ExtensionSwitcher';
import { InboxIndicator } from './InboxIndicator';
import { TerminalPanel } from './TerminalPanel';
import type { ShareEnvelope } from './share-channel';
import { Dock } from './dock/Dock';
import { DetailPane } from './dock/DetailPane';
import { DocumentEditor } from './dock/DocumentEditor';
import { TalkMode } from './TalkMode';
import { StableThreads } from './StableThreads';
import { useWorkingSet, type PinnedItem } from '../state/workingSet';
import { useIdentity } from '../identity/IdentityProvider';
import type { IntentId } from './dock/context-weights';
import type { ShellDispatchResult } from '../hooks/useShellDispatch';

export interface HelmProps {
  store?: LoomStore;
  config?: ConfigStore;
}

interface DockInvocation {
  command: string;
  result: ShellDispatchResult;
  at: number;
}

export function Helm({ store: externalStore, config: externalConfig }: HelmProps) {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [terminalOpen, setTerminalOpen] = useState(false);
  const [dockIntent, setDockIntent] = useState<IntentId | null>(null);
  const [detail, setDetail] = useState<DockInvocation | null>(null);
  const [activeContextCellId, setActiveContextCellId] = useState<string | null>(null);

  // Unified store: default to the singleton loomStore that useShellContext
  // also binds to, so shell-dispatched `new <Type>` writes show up in Helm's
  // attention engine, handleItemTap, pinned strip, and detail panes. Tests
  // or other shells can still override via the `store` prop.
  const store = useMemo(() => externalStore ?? singletonLoomStore, [externalStore]);
  const configStoreInstance = externalConfig ?? singletonConfigStore;
  // Reserve for future: extension weights from configStore manifests.
  void configStoreInstance;

  // Active hat (for authoring patches from the dock).
  const { activeHat } = useIdentity();
  const activeHatId = activeHat?.id;

  // Create and manage AttentionEngine lifecycle. AS2 wires the weight
  // learner; AS3 the override rules; AS4 the external signal registry.
  const engine = useMemo(() => new AttentionEngine(store, {
    weightLearner: attentionWeightLearner,
    rules: attentionRules,
    signals: attentionSignals,
    telemetry: attentionTelemetry,
    paskGraph,
    contextProvider: () => {
      const isMobile = typeof navigator !== 'undefined' && /Mobi|Android/i.test(navigator.userAgent);
      const hour = new Date().getHours();
      if (hour < 7 || hour >= 22) return 'night';
      return isMobile ? 'field' : 'desk';
    },
  }), [store]);

  useEffect(() => {
    engine.start();
    return () => engine.stop();
  }, [engine]);

  // Subscribe to attention updates
  const attention = useAttention(engine);

  // Working set (pinned items)
  const { pinned, pin, unpin } = useWorkingSet();

  const homeBadge = useMemo(
    () => attention.items.filter((item) => item.urgency === 'immediate').length,
    [attention.items],
  );

  const [editingDocumentId, setEditingDocumentId] = useState<string | null>(null);

  const handleItemTap = useCallback((item: AttentionItem) => {
    store.dispatch({ type: 'SELECT_OBJECT', id: item.object.id });
    // Documents get the full editor pane; other types still flow through
    // DetailPane when the user triggers them from the dock.
    if (item.object.typeDefinition?.name === 'Document') {
      setEditingDocumentId(item.object.id);
    }
  }, [store]);

  const handleOpenDrawer = useCallback(() => setDrawerOpen(true), []);
  const handleCloseDrawer = useCallback(() => setDrawerOpen(false), []);

  const handleOpenEnvelope = useCallback((_envelope: ShareEnvelope) => {
    // Inbox envelopes fall into attention; dock handles creation of new docs.
  }, []);

  // Keyboard shortcut: backtick to toggle terminal
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === '`' && !e.ctrlKey && !e.metaKey) {
        const tag = (e.target as HTMLElement)?.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA') return;
        if ((e.target as HTMLElement)?.closest('.cm-editor')) return;
        e.preventDefault();
        setTerminalOpen(prev => !prev);
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, []);

  const handleInvoke = useCallback((command: string, result: ShellDispatchResult) => {
    // Dock just created a Document → jump straight into the editor pane.
    if (result.ok) {
      const data = result.data as { id?: string; type?: string } | null;
      if (data?.type === 'Document' && typeof data.id === 'string') {
        setEditingDocumentId(data.id);
        setDetail(null);
        return;
      }
    }
    setDetail({ command, result, at: Date.now() });
  }, []);

  const handleGoHome = useCallback(() => {
    setDetail(null);
    setEditingDocumentId(null);
    setDockIntent(null);
    setActiveContextCellId(null);
    paskGraph.setActiveContext(null);
    engine.setActiveContext(null);
  }, [engine]);

  const handleThreadSelect = useCallback((cellId: string | null) => {
    setActiveContextCellId(cellId);
    paskGraph.setActiveContext(cellId);
    engine.setActiveContext(cellId);
  }, [engine]);

  const handleCloseEditor = useCallback(() => {
    setEditingDocumentId(null);
  }, []);

  const handlePinEditor = useCallback(() => {
    if (!editingDocumentId) return;
    const obj = store.getState().objects.get(editingDocumentId);
    const title = (obj?.payload.title as string) || 'Untitled';
    pin({
      objectId: editingDocumentId,
      label: title,
      command: `edit ${editingDocumentId}`,
    });
  }, [editingDocumentId, pin, store]);

  const handlePinFromDetail = useCallback(() => {
    if (!detail || !detail.result.ok) return;
    const data = detail.result.data as { id?: string; type?: string; title?: string } | null;
    const label =
      data?.title ??
      (data?.type && data?.id ? `${data.type} ${data.id.slice(0, 8)}` : detail.command);
    pin({ objectId: data?.id, label, command: detail.command });
  }, [detail, pin]);

  return (
    <div className="flex flex-col h-screen bg-gray-950 text-gray-100">
      {/* Top bar: two switchers (identity + workspace) */}
      <header className="flex items-center justify-between px-4 py-2 border-b border-gray-800 shrink-0">
        <div className="flex items-center gap-3">
          <span className="text-sm font-semibold text-gray-300">Semantos</span>
          <ExtensionSwitcher />
        </div>

        <div className="flex items-center gap-3">
          <HatSwitcher />
          <InboxIndicator onOpenEnvelope={handleOpenEnvelope} />
          <button
            onClick={() => setTerminalOpen(!terminalOpen)}
            className={`text-sm px-2 py-0.5 rounded transition-colors font-mono ${
              terminalOpen
                ? 'text-green-400 bg-gray-800'
                : 'text-gray-500 hover:text-gray-300 hover:bg-gray-800'
            }`}
            aria-label="Toggle terminal"
            title="Toggle terminal (`)"
          >
            &gt;_
          </button>
          <button
            onClick={handleOpenDrawer}
            className="text-gray-400 hover:text-gray-200 transition-colors text-sm px-2 py-1 rounded hover:bg-gray-800"
            aria-label="Open support drawer"
          >
            {'\u2261'}
          </button>
        </div>
      </header>

      {/* Attention surface canvas */}
      <main className="flex-1 relative overflow-hidden">
        <div className="h-full overflow-auto">
          <StableThreads
            paskGraph={paskGraph}
            activeContextCellId={activeContextCellId}
            onThreadSelect={handleThreadSelect}
          />
          {pinned.length > 0 && (
            <PinnedStrip items={pinned} onUnpin={unpin} />
          )}
          <AttentionSurface
            items={attention.items}
            onItemTap={handleItemTap}
            telemetry={attentionTelemetry}
            rules={attentionRules}
          />
        </div>

        {/* Detail pane overlay (non-Document results) */}
        {detail && !editingDocumentId && (
          <DetailPane
            command={detail.command}
            result={detail.result}
            onClose={() => setDetail(null)}
            onPin={detail.result.ok ? handlePinFromDetail : undefined}
          />
        )}

        {/* Document editor overlay (GitBook-style markdown pane). */}
        {editingDocumentId && (
          <DocumentEditor
            store={store}
            objectId={editingDocumentId}
            hatId={activeHatId}
            onClose={handleCloseEditor}
            onPin={handlePinEditor}
          />
        )}
      </main>

      {/* Terminal panel */}
      <TerminalPanel isOpen={terminalOpen} onClose={() => setTerminalOpen(false)} />

      {/* Talk mode — voice → NL extract → approval → host.exec (Phase 38G).
          Appears above the dock when the Talk intent is active. */}
      {dockIntent === 'talk' && (
        <div className="border-t border-gray-800 bg-gray-950/95 shrink-0 max-h-[50vh] overflow-auto">
          <TalkMode />
        </div>
      )}

      {/* Dock — tier 1/2/3 progressive disclosure */}
      <Dock
        onInvoke={handleInvoke}
        onGoHome={handleGoHome}
        homeBadge={homeBadge}
        activeIntent={dockIntent}
        setActiveIntent={setDockIntent}
      />

      {/* Support drawer */}
      <SupportDrawer isOpen={drawerOpen} onClose={handleCloseDrawer} />
    </div>
  );
}

// ── Pinned strip ────────────────────────────────────────────────

interface PinnedStripProps {
  items: PinnedItem[];
  onUnpin: (key: string) => void;
}

function PinnedStrip({ items, onUnpin }: PinnedStripProps) {
  return (
    <section className="border-b border-gray-800 bg-gray-900/50 px-4 py-2">
      <div className="text-[10px] uppercase tracking-wide text-gray-500 mb-2">
        Pinned
      </div>
      <div className="flex flex-wrap gap-2">
        {items.map(item => {
          const key = item.objectId ?? item.label;
          return (
            <div
              key={key}
              className="group flex items-center gap-2 bg-gray-800 hover:bg-gray-750 rounded-md px-3 py-1.5 text-xs"
              title={item.command ?? ''}
            >
              <span className="text-yellow-500">{'\u2691'}</span>
              <span className="text-gray-200 max-w-[220px] truncate">{item.label}</span>
              <button
                onClick={() => onUnpin(key)}
                className="text-gray-500 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
                aria-label={`Unpin ${item.label}`}
                title="Unpin"
              >
                {'\u2715'}
              </button>
            </div>
          );
        })}
      </div>
    </section>
  );
}

```
