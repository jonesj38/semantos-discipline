---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/TerminalPanel.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.964988+00:00
---

# archive/apps-loom-react/src/helm/TerminalPanel.tsx

```tsx
/**
 * TerminalPanel — embedded shell REPL in the browser.
 *
 * Dispatches through the real shell parser/router pipeline via useShellDispatch().
 * Every command typed here goes through the same route() + capability gate as
 * the CLI, REPL, and agent modes. Shows output as JSON or text.
 * Supports command history (up/down arrows).
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import { useShellDispatch } from '../hooks/useShellDispatch';
import { useShellContext } from '../hooks/useShellContext';
import { KNOWN_VERBS } from '@semantos/shell';

interface TerminalEntry {
  id: number;
  input: string;
  output: string;
  isError: boolean;
  timestamp: number;
}

export interface TerminalPanelProps {
  isOpen: boolean;
  onClose: () => void;
}

export function TerminalPanel({ isOpen, onClose }: TerminalPanelProps) {
  const [entries, setEntries] = useState<TerminalEntry[]>([]);
  const [input, setInput] = useState('');
  const [historyIndex, setHistoryIndex] = useState(-1);
  const inputRef = useRef<HTMLInputElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const idCounter = useRef(0);
  const dispatch = useShellDispatch();
  const ctx = useShellContext();

  // Auto-scroll to bottom on new entries
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [entries]);

  // Focus input when panel opens
  useEffect(() => {
    if (isOpen) inputRef.current?.focus();
  }, [isOpen]);

  const history = entries.filter(e => e.input).map(e => e.input);

  // Derive prompt from active hat
  const facetName = ctx
    ? (ctx.identity.getActiveHat()?.name ?? 'anon')
    : '...';
  const extension = ctx?.activeExtension ?? 'core';

  const handleSubmit = useCallback(async () => {
    const trimmed = input.trim();
    if (!trimmed) return;

    const entryId = ++idCounter.current;

    // Local help command — shows all shell verbs
    if (trimmed === 'help') {
      const verbList = [...KNOWN_VERBS].sort().join(', ');
      setEntries(prev => [...prev, {
        id: entryId,
        input: trimmed,
        output: `Available verbs: ${verbList}\n\nUsage: <verb> [type-path | object-id] [--flags]\nExamples:\n  list --type Document\n  inspect <id>\n  new core.document --title "Meeting Notes"\n  publish <id>\n  whoami\n  game list`,
        isError: false,
        timestamp: Date.now(),
      }]);
      setInput('');
      setHistoryIndex(-1);
      return;
    }

    const result = await dispatch(trimmed);
    const output = result.ok
      ? (typeof result.data === 'string' ? result.data : JSON.stringify(result.data, null, 2))
      : `Error: ${result.error}`;

    setEntries(prev => [...prev, {
      id: entryId,
      input: trimmed,
      output,
      isError: !result.ok,
      timestamp: Date.now(),
    }]);

    setInput('');
    setHistoryIndex(-1);
  }, [input, dispatch]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleSubmit();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (history.length === 0) return;
      const newIndex = historyIndex < history.length - 1 ? historyIndex + 1 : historyIndex;
      setHistoryIndex(newIndex);
      setInput(history[history.length - 1 - newIndex] ?? '');
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (historyIndex <= 0) {
        setHistoryIndex(-1);
        setInput('');
      } else {
        const newIndex = historyIndex - 1;
        setHistoryIndex(newIndex);
        setInput(history[history.length - 1 - newIndex] ?? '');
      }
    } else if (e.key === 'Escape') {
      onClose();
    }
  }, [handleSubmit, history, historyIndex, onClose]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-x-0 bottom-[52px] h-[280px] bg-gray-950 border-t border-gray-700 flex flex-col z-40">
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-1.5 border-b border-gray-800 shrink-0">
        <span className="text-[10px] text-gray-500 font-mono uppercase tracking-wider">
          semantos shell
        </span>
        <button
          onClick={onClose}
          className="text-gray-500 hover:text-gray-300 text-xs transition-colors"
        >
          &times;
        </button>
      </div>

      {/* Output */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto px-3 py-2 font-mono text-xs">
        {entries.length === 0 && (
          <p className="text-gray-600">Type &apos;help&apos; for available commands.</p>
        )}
        {entries.map(entry => (
          <div key={entry.id} className="mb-2">
            <div className="text-gray-400">
              <span className="text-cyan-600">[{facetName}@{extension}]</span>{' '}
              <span className="text-green-600">$</span> {entry.input}
            </div>
            <pre className={`whitespace-pre-wrap mt-0.5 ${
              entry.isError ? 'text-red-400' : 'text-gray-300'
            }`}>
              {entry.output}
            </pre>
          </div>
        ))}
      </div>

      {/* Input */}
      <div className="flex items-center gap-2 px-3 py-2 border-t border-gray-800 shrink-0">
        <span className="text-cyan-600 font-mono text-xs">[{facetName}@{extension}]</span>
        <span className="text-green-600 font-mono text-xs">$</span>
        <input
          ref={inputRef}
          type="text"
          value={input}
          onChange={e => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="help"
          className="flex-1 bg-transparent text-gray-200 font-mono text-xs outline-none placeholder-gray-700"
          autoComplete="off"
          spellCheck={false}
        />
      </div>
    </div>
  );
}

```
