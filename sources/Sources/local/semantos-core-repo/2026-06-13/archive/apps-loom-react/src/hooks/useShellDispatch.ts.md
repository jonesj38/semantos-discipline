---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/hooks/useShellDispatch.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.961480+00:00
---

# archive/apps-loom-react/src/hooks/useShellDispatch.ts

```ts
/**
 * useShellDispatch — fire shell commands from React components.
 *
 * Every UI action (button click, form submit) that mutates state should
 * dispatch through the shell pipeline rather than calling LoomStore directly.
 * This ensures capability gating, audit trails, and consistency with the
 * CLI/REPL/agent paths.
 *
 * Usage:
 *   const dispatch = useShellDispatch();
 *   await dispatch('publish invoice-123');
 *   await dispatch('new core.document --title "Meeting Notes"');
 */

import { useCallback } from 'react';
import { parseCommand, route } from '@semantos/shell';
import { useShellContext } from './useShellContext';

export interface ShellDispatchResult {
  ok: boolean;
  data: unknown;
  error?: string;
}

/**
 * Simple shell-aware tokenizer for the dispatch hook.
 * Handles double-quoted strings so flags like --title "My Doc" work.
 */
function tokenize(input: string): string[] {
  const tokens: string[] = [];
  let current = '';
  let inQuote = false;
  for (const ch of input) {
    if (ch === '"') {
      inQuote = !inQuote;
    } else if (ch === ' ' && !inQuote) {
      if (current) tokens.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  if (current) tokens.push(current);
  return tokens;
}

export function useShellDispatch(): (command: string) => Promise<ShellDispatchResult> {
  const ctx = useShellContext();

  return useCallback(async (command: string): Promise<ShellDispatchResult> => {
    if (!ctx) {
      return { ok: false, data: null, error: 'Shell context not initialized yet.' };
    }

    try {
      const args = tokenize(command.trim());
      const cmd = parseCommand(args);
      const data = await route(cmd, ctx);

      // Shell route() returns error objects with an `error` field on failure
      if (data && typeof data === 'object' && 'error' in data) {
        return { ok: false, data, error: String((data as Record<string, unknown>).error) };
      }

      return { ok: true, data };
    } catch (err) {
      return { ok: false, data: null, error: (err as Error).message };
    }
  }, [ctx]);
}

```
