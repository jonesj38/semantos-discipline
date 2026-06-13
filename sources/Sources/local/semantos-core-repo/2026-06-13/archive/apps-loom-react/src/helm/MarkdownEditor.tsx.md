---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/MarkdownEditor.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.964437+00:00
---

# archive/apps-loom-react/src/helm/MarkdownEditor.tsx

```tsx
/**
 * MarkdownEditor — CodeMirror 6 wrapper for editing markdown content.
 *
 * Controlled component: receives value + onChange, manages CM state internally.
 * Debounces onChange to avoid thrashing the store on every keystroke.
 *
 * Exposes an imperative handle so toolbar components can wrap/prefix the
 * current selection (bold, italic, heading, list, etc). The ref API is the
 * simplest way to keep CodeMirror internal while still letting a sibling
 * toolbar drive edits.
 */

import { useRef, useEffect, useCallback, forwardRef, useImperativeHandle } from 'react';
import { EditorState } from '@codemirror/state';
import { EditorView, keymap, placeholder as cmPlaceholder } from '@codemirror/view';
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands';
import { markdown } from '@codemirror/lang-markdown';
import { oneDark } from '@codemirror/theme-one-dark';

export interface MarkdownEditorProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  autoFocus?: boolean;
}

export interface MarkdownEditorHandle {
  /** Wrap current selection with `before`…`after`. Inserts placeholder if empty. */
  wrapSelection: (before: string, after?: string, placeholder?: string) => void;
  /** Prefix each selected line with `prefix` (for lists, quotes, headings). */
  prefixLines: (prefix: string) => void;
  /** Insert text at the cursor. */
  insertAtCursor: (text: string) => void;
  /** Focus the editor. */
  focus: () => void;
}

const theme = EditorView.theme({
  '&': {
    height: '100%',
    fontSize: '14px',
  },
  '.cm-scroller': {
    overflow: 'auto',
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
  },
  '.cm-content': {
    padding: '12px 16px',
    minHeight: '200px',
  },
  '&.cm-focused': {
    outline: 'none',
  },
});

export const MarkdownEditor = forwardRef<MarkdownEditorHandle, MarkdownEditorProps>(
  function MarkdownEditor({ value, onChange, placeholder, autoFocus }, ref) {
    const containerRef = useRef<HTMLDivElement>(null);
    const viewRef = useRef<EditorView | null>(null);
    const onChangeRef = useRef(onChange);
    onChangeRef.current = onChange;

    // Debounce timer
    const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

    const handleUpdate = useCallback((doc: string) => {
      if (timerRef.current) clearTimeout(timerRef.current);
      timerRef.current = setTimeout(() => {
        onChangeRef.current(doc);
      }, 300);
    }, []);

    useEffect(() => {
      if (!containerRef.current) return;

      const state = EditorState.create({
        doc: value,
        extensions: [
          keymap.of([...defaultKeymap, ...historyKeymap]),
          history(),
          markdown(),
          oneDark,
          theme,
          placeholder ? cmPlaceholder(placeholder) : [],
          EditorView.updateListener.of((update) => {
            if (update.docChanged) {
              handleUpdate(update.state.doc.toString());
            }
          }),
        ],
      });

      const view = new EditorView({
        state,
        parent: containerRef.current,
      });

      viewRef.current = view;

      if (autoFocus) {
        requestAnimationFrame(() => view.focus());
      }

      return () => {
        if (timerRef.current) clearTimeout(timerRef.current);
        view.destroy();
        viewRef.current = null;
      };
    }, []); // eslint-disable-line react-hooks/exhaustive-deps — intentionally init once

    // Sync external value changes (e.g. switching documents)
    useEffect(() => {
      const view = viewRef.current;
      if (!view) return;
      const current = view.state.doc.toString();
      if (current !== value) {
        view.dispatch({
          changes: { from: 0, to: current.length, insert: value },
        });
      }
    }, [value]);

    useImperativeHandle(ref, () => ({
      wrapSelection(before, after = before, placeholderText = '') {
        const view = viewRef.current;
        if (!view) return;
        const { from, to } = view.state.selection.main;
        const selected = view.state.sliceDoc(from, to);
        const body = selected.length > 0 ? selected : placeholderText;
        const insert = `${before}${body}${after}`;
        view.dispatch({
          changes: { from, to, insert },
          selection: {
            anchor: from + before.length,
            head: from + before.length + body.length,
          },
        });
        view.focus();
      },
      prefixLines(prefix) {
        const view = viewRef.current;
        if (!view) return;
        const { from, to } = view.state.selection.main;
        const startLine = view.state.doc.lineAt(from);
        const endLine = view.state.doc.lineAt(to);
        const changes = [] as { from: number; to: number; insert: string }[];
        for (let n = startLine.number; n <= endLine.number; n++) {
          const line = view.state.doc.line(n);
          changes.push({ from: line.from, to: line.from, insert: prefix });
        }
        view.dispatch({ changes });
        view.focus();
      },
      insertAtCursor(text) {
        const view = viewRef.current;
        if (!view) return;
        view.dispatch(view.state.replaceSelection(text));
        view.focus();
      },
      focus() {
        viewRef.current?.focus();
      },
    }), []);

    return (
      <div
        ref={containerRef}
        className="flex-1 overflow-hidden"
      />
    );
  },
);

```
