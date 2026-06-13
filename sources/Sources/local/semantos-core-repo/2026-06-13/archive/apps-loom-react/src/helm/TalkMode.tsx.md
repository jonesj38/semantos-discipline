---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/TalkMode.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.967221+00:00
---

# archive/apps-loom-react/src/helm/TalkMode.tsx

```tsx
/**
 * TalkMode — voice input surface for the Helm Talk intent.
 *
 * Phase 38G flow:
 *   1. VoiceInput captures utterance
 *   2. extractShellCommand() produces a grounded ExtractedCommand (or error)
 *   3. CommandApprovalCard renders pending command, expanded by default
 *   4. On Approve → useShellDispatch fires host.exec through the capability gate
 *   5. Receipt lands in Do/Transact via AttentionEngine routing
 *
 * No auto-dispatch: the approval card is mandatory at all confidences.
 */

import React, { useCallback, useState } from 'react';
import { VoiceInput } from './VoiceInput';
import { CommandApprovalCard } from './CommandApprovalCard';
import { useShellDispatch, type ShellDispatchResult } from '../hooks/useShellDispatch';
import { useShellContext } from '../hooks/useShellContext';
import {
  extractShellCommand,
  listHandlers,
  type ExtractedCommand,
  type ExtractError,
  type LlmClient,
} from '@semantos/shell';

export interface TalkModeProps {
  /** Optional LLM client. When null, the deterministic fallback handles extraction. */
  llm?: LlmClient | null;
}

/** Build `host.exec <handler> --arg k=v --arg k2=v2` from an ExtractedCommand. */
function buildDispatchCommand(extracted: ExtractedCommand): string {
  const parts = ['host.exec', extracted.handler];
  for (const [k, v] of Object.entries(extracted.args)) {
    parts.push('--arg', `${k}=${String(v)}`);
  }
  return parts.join(' ');
}

export function TalkMode({ llm = null }: TalkModeProps) {
  const dispatch = useShellDispatch();
  const shellCtx = useShellContext();

  const [pending, setPending] = useState<ExtractedCommand | null>(null);
  const [extractError, setExtractError] = useState<ExtractError | null>(null);
  const [lastResult, setLastResult] = useState<ShellDispatchResult | null>(null);
  const [busy, setBusy] = useState(false);

  const activeFacet = shellCtx?.identity.getActiveHat() ?? null;

  const handleUtterance = useCallback(async (text: string) => {
    setExtractError(null);
    setLastResult(null);

    const result = await extractShellCommand(text, {
      handlers: listHandlers(),
      llm,
    });

    if (!result.ok) {
      setExtractError(result);
      return;
    }
    setPending(result);
  }, [llm]);

  const handleApprove = useCallback(async () => {
    if (!pending || busy) return;
    setBusy(true);
    try {
      const cmd = buildDispatchCommand(pending);
      const res = await dispatch(cmd);
      setLastResult(res);
      setPending(null);
    } finally {
      setBusy(false);
    }
  }, [pending, busy, dispatch]);

  const handleCancel = useCallback(() => {
    setPending(null);
    setExtractError(null);
  }, []);

  return (
    <div className="p-4 flex flex-col gap-4">
      <div>
        <h2 className="text-sm font-medium text-gray-400 mb-3">Voice Input</h2>
        <VoiceInput onUtterance={handleUtterance} />
      </div>

      {/* Extract error — visible, not a toast */}
      {extractError && (
        <div className="rounded border border-red-500/40 bg-red-900/20 px-3 py-2 text-xs text-red-200">
          <div className="font-mono text-red-300 mb-1">{extractError.code}</div>
          <div>{extractError.message}</div>
          {extractError.suggestions && extractError.suggestions.length > 0 && (
            <div className="mt-1 text-[11px] text-red-300/80">
              Did you mean: {extractError.suggestions.join(', ')}?
            </div>
          )}
        </div>
      )}

      {/* Approval card */}
      {pending && activeFacet && (
        <CommandApprovalCard
          extracted={pending}
          activeHat={{ id: activeFacet.id, label: activeFacet.name }}
          onApprove={handleApprove}
          onCancel={handleCancel}
        />
      )}

      {/* Dispatch result — capability denial + success both visible */}
      {lastResult && (
        <div
          className={`rounded border px-3 py-2 text-xs ${
            lastResult.ok
              ? 'border-green-500/40 bg-green-900/20 text-green-200'
              : 'border-red-500/40 bg-red-900/20 text-red-200'
          }`}
        >
          <div className="font-mono mb-1">
            {lastResult.ok ? 'host.exec dispatched' : `Error: ${lastResult.error ?? 'unknown'}`}
          </div>
          {!lastResult.ok && lastResult.data && typeof lastResult.data === 'object' && 'code' in lastResult.data && (
            <div className="text-[11px] opacity-80 font-mono">
              code: {String((lastResult.data as Record<string, unknown>).code)}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

```
