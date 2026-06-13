---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/dock/DocumentEditor.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.975652+00:00
---

# archive/apps-loom-react/src/helm/dock/DocumentEditor.tsx

```tsx
/**
 * DocumentEditor — overlay pane for editing a Document object.
 *
 * Opened when the dock creates a Document (Do → Create → New Document) or
 * when an existing Document is selected. Replaces the raw-JSON DetailPane
 * for this type, per user direction: "launch a markdown editor… with some
 * simple buttons for manipulating the md (like gitbooks edit pane)."
 *
 * Layout:
 *   ┌────────────────────────────────────────────────────────┐
 *   │ [title input]                  [publish] [pin] [×]      │
 *   ├────────────────────────────────────────────────────────┤
 *   │ [H1] [H2] [B] [I] [link] [list] [quote] [code]          │
 *   ├────────────────────────────────────────────────────────┤
 *   │ CodeMirror markdown editor…                             │
 *   └────────────────────────────────────────────────────────┘
 *
 * Save semantics: every keystroke → UPDATE_PAYLOAD + ADD_PATCH, so the
 * evidence chain matches what the shell `patch` verb would produce.
 */

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { LoomStore } from '../../services/LoomStore';
import type { ObjectPatch } from '@semantos/runtime-services';
import { MarkdownEditor, type MarkdownEditorHandle } from '../MarkdownEditor';
import { useShellDispatch } from '../../hooks/useShellDispatch';

export interface DocumentEditorProps {
  store: LoomStore;
  objectId: string;
  facetId?: string;
  onClose: () => void;
  onPin?: () => void;
}

export function DocumentEditor({
  store,
  objectId,
  facetId,
  onClose,
  onPin,
}: DocumentEditorProps) {
  const editorRef = useRef<MarkdownEditorHandle>(null);
  const dispatch = useShellDispatch();
  const [busy, setBusy] = useState<'publish' | null>(null);
  const [publishError, setPublishError] = useState<string | null>(null);

  // Snapshot the object once — subsequent edits are driven by the editor.
  // For live re-render on external changes we subscribe below.
  const [snapshot, setSnapshot] = useState(() => {
    const obj = store.getState().objects.get(objectId);
    return {
      title: (obj?.payload.title as string) ?? '',
      content: (obj?.payload.content as string) ?? '',
      visibility: obj?.visibility ?? 'draft',
      exists: !!obj,
    };
  });

  // Subscribe so external transitions (publish) reflect in the pane.
  // LoomStore is a TypedEventEmitter; use `stableSubscribe` (which returns
  // an unsubscribe fn suitable for useSyncExternalStore / useEffect cleanup).
  useEffect(() => {
    const unsubscribe = store.stableSubscribe(() => {
      const obj = store.getState().objects.get(objectId);
      if (!obj) {
        setSnapshot(s => ({ ...s, exists: false }));
        return;
      }
      setSnapshot(prev => ({
        title: (obj.payload.title as string) ?? prev.title,
        content: (obj.payload.content as string) ?? prev.content,
        visibility: obj.visibility,
        exists: true,
      }));
    });
    return unsubscribe;
  }, [store, objectId]);

  const handleTitleChange = useCallback((title: string) => {
    store.dispatch({ type: 'UPDATE_PAYLOAD', objectId, field: 'title', value: title });
    setSnapshot(s => ({ ...s, title }));
  }, [store, objectId]);

  const handleContentChange = useCallback((content: string) => {
    store.dispatch({ type: 'UPDATE_PAYLOAD', objectId, field: 'content', value: content });
    const patch: ObjectPatch = {
      id: `patch-${Date.now()}-edit`,
      kind: 'manual_override',
      timestamp: Date.now(),
      delta: { field: 'content', length: content.length },
      hatId,
    };
    store.dispatch({ type: 'ADD_PATCH', objectId, patch });
  }, [store, objectId, facetId]);

  const handlePublish = useCallback(async () => {
    setBusy('publish');
    setPublishError(null);
    try {
      const result = await dispatch(`publish ${objectId}`);
      if (!result.ok) {
        setPublishError(result.error ?? 'Publish failed');
      }
    } finally {
      setBusy(null);
    }
  }, [dispatch, objectId]);

  // Toolbar handlers — dispatch through the imperative ref on the editor.
  const tool = useMemo(() => ({
    h1: () => editorRef.current?.prefixLines('# '),
    h2: () => editorRef.current?.prefixLines('## '),
    h3: () => editorRef.current?.prefixLines('### '),
    bold: () => editorRef.current?.wrapSelection('**', '**', 'bold text'),
    italic: () => editorRef.current?.wrapSelection('_', '_', 'italic text'),
    code: () => editorRef.current?.wrapSelection('`', '`', 'code'),
    codeblock: () => editorRef.current?.wrapSelection('\n```\n', '\n```\n', 'code'),
    link: () => editorRef.current?.wrapSelection('[', '](url)', 'link text'),
    list: () => editorRef.current?.prefixLines('- '),
    numberList: () => editorRef.current?.prefixLines('1. '),
    quote: () => editorRef.current?.prefixLines('> '),
    hr: () => editorRef.current?.insertAtCursor('\n\n---\n\n'),
  }), []);

  // Esc closes.
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !(e.target as HTMLElement)?.closest('.cm-editor')) {
        onClose();
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose]);

  if (!snapshot.exists) {
    return (
      <div className="absolute inset-0 z-10 flex items-start justify-center pt-12 px-4 pb-4 pointer-events-none">
        <div className="pointer-events-auto w-full max-w-3xl bg-gray-900/98 border border-gray-700 rounded-lg shadow-2xl p-6 text-center text-gray-400">
          Document {objectId.slice(0, 12)}… not found.
          <button onClick={onClose} className="ml-2 text-blue-400 hover:text-blue-300">close</button>
        </div>
      </div>
    );
  }

  const published = snapshot.visibility === 'published';

  return (
    <div
      className="absolute inset-0 z-10 flex items-start justify-center pt-6 px-4 pb-4 pointer-events-none"
      onClick={onClose}
    >
      <div
        className="pointer-events-auto w-full max-w-3xl h-[calc(100vh-140px)] bg-gray-900/98 border border-gray-700 rounded-lg shadow-2xl flex flex-col overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header: title + actions */}
        <div className="flex items-center gap-2 px-3 py-2 border-b border-gray-800 shrink-0">
          <span className="text-gray-500 text-lg shrink-0">{'\uD83D\uDCC4'}</span>
          <input
            type="text"
            value={snapshot.title}
            onChange={(e) => handleTitleChange(e.target.value)}
            placeholder="Untitled"
            className="flex-1 bg-transparent text-base font-medium text-gray-100 placeholder-gray-600 focus:outline-none"
            autoComplete="off"
            spellCheck={false}
            aria-label="Document title"
          />
          <span
            className={`text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded border shrink-0 ${
              published
                ? 'text-emerald-300 border-emerald-500/40 bg-emerald-900/20'
                : 'text-amber-300 border-amber-500/30 bg-amber-900/20'
            }`}
            title={`Visibility: ${snapshot.visibility}`}
          >
            {snapshot.visibility}
          </span>
          {!published && (
            <button
              onClick={handlePublish}
              disabled={busy === 'publish'}
              className="text-xs px-2 py-1 rounded bg-blue-600 hover:bg-blue-500 text-white disabled:opacity-50 shrink-0"
              title="Publish (draft → published, AFFINE → RELEVANT)"
            >
              {busy === 'publish' ? 'Publishing…' : 'Publish'}
            </button>
          )}
          {onPin && (
            <button
              onClick={onPin}
              className="text-xs px-2 py-1 rounded bg-gray-800 hover:bg-gray-700 text-gray-300 shrink-0"
              title="Pin to attention surface"
            >
              {'\u2691'} Pin
            </button>
          )}
          <button
            onClick={onClose}
            className="text-gray-500 hover:text-gray-200 px-2 shrink-0"
            aria-label="Close editor"
          >
            {'\u2715'}
          </button>
        </div>

        {publishError && (
          <div className="px-3 py-1.5 text-[11px] text-red-300 bg-red-900/20 border-b border-red-900/40 shrink-0">
            {publishError}
          </div>
        )}

        {/* Toolbar: markdown formatting buttons */}
        <div className="flex items-center gap-0.5 px-2 py-1 border-b border-gray-800 bg-gray-900/50 shrink-0 overflow-x-auto">
          <TB onClick={tool.h1} title="Heading 1" kbd="#">H1</TB>
          <TB onClick={tool.h2} title="Heading 2" kbd="##">H2</TB>
          <TB onClick={tool.h3} title="Heading 3" kbd="###">H3</TB>
          <Sep />
          <TB onClick={tool.bold} title="Bold (wrap **)" kbd="**"><span className="font-bold">B</span></TB>
          <TB onClick={tool.italic} title="Italic (wrap _)" kbd="_"><span className="italic">I</span></TB>
          <TB onClick={tool.code} title="Inline code (wrap `)" kbd="`">
            <span className="font-mono">{'</>'}</span>
          </TB>
          <Sep />
          <TB onClick={tool.link} title="Link" kbd="[]()">{'\uD83D\uDD17'}</TB>
          <TB onClick={tool.list} title="Bulleted list" kbd="-">{'\u2022'}</TB>
          <TB onClick={tool.numberList} title="Numbered list" kbd="1.">1.</TB>
          <TB onClick={tool.quote} title="Blockquote" kbd=">">{'\u201C'}</TB>
          <TB onClick={tool.codeblock} title="Code block" kbd="```">{'{ }'}</TB>
          <TB onClick={tool.hr} title="Horizontal rule" kbd="---">{'\u2014'}</TB>
        </div>

        {/* Editor body */}
        <div className="flex-1 min-h-0 flex flex-col">
          <MarkdownEditor
            ref={editorRef}
            value={snapshot.content}
            onChange={handleContentChange}
            placeholder="Start writing in markdown…"
            autoFocus
          />
        </div>

        {/* Footer: id + hint */}
        <div className="flex items-center justify-between gap-2 px-3 py-1.5 border-t border-gray-800 text-[10px] text-gray-500 bg-gray-950/50 shrink-0">
          <span className="font-mono truncate">{objectId}</span>
          <span className="shrink-0">Saves auto-patch · Esc to close</span>
        </div>
      </div>
    </div>
  );
}

// ── Toolbar helpers ────────────────────────────────────────────

interface TBProps {
  onClick: () => void;
  title: string;
  kbd?: string;
  children: React.ReactNode;
}

function TB({ onClick, title, kbd, children }: TBProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      title={kbd ? `${title} — ${kbd}` : title}
      className="w-7 h-7 flex items-center justify-center rounded text-gray-400 hover:text-gray-100 hover:bg-gray-800 text-sm transition-colors shrink-0"
    >
      {children}
    </button>
  );
}

function Sep() {
  return <span className="w-px h-4 bg-gray-800 mx-1 shrink-0" aria-hidden="true" />;
}

```
