---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/CommandApprovalCard.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.963607+00:00
---

# archive/apps-loom-react/src/helm/CommandApprovalCard.tsx

```tsx
/**
 * CommandApprovalCard — expanded-by-default approval UI for voice-extracted host commands.
 *
 * Shows handler, every arg, active hat, required capability, timeout, and confidence
 * inline — no collapsed "details" drawer. The user taps Approve or Cancel; no
 * auto-dispatch even at confidence 1.0.
 *
 * Phase 38G.
 */

import React from 'react';
import type { ExtractedCommand } from '@semantos/shell';

export interface CommandApprovalCardProps {
  extracted: ExtractedCommand;
  activeHat: { id: string; label?: string };
  capabilityName?: string;
  timeoutMs?: number;
  onApprove: () => void;
  onCancel: () => void;
}

const LOW_CONFIDENCE_THRESHOLD = 0.6;

export function CommandApprovalCard({
  extracted,
  activeHat,
  capabilityName = 'HOST_EXEC',
  timeoutMs = 10_000,
  onApprove,
  onCancel,
}: CommandApprovalCardProps) {
  const confidencePercent = Math.round(extracted.confidence * 100);
  const lowConfidence = extracted.confidence < LOW_CONFIDENCE_THRESHOLD;
  const argEntries = Object.entries(extracted.args);

  return (
    <div
      role="dialog"
      aria-label="Approve host command"
      className="bg-gray-900 border border-gray-700 rounded-lg shadow-2xl p-4 min-w-[360px] max-w-[480px]"
    >
      <h3 className="text-sm font-semibold text-gray-100 mb-3">Approve host command</h3>

      {/* Always-expanded field list */}
      <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs mb-3">
        <dt className="text-gray-500">Handler:</dt>
        <dd className="text-gray-100 font-mono">{extracted.handler}</dd>

        <dt className="text-gray-500">Args:</dt>
        <dd className="text-gray-100 font-mono">
          {argEntries.length === 0
            ? <span className="text-gray-500 italic">(none)</span>
            : argEntries.map(([k, v]) => `${k}=${String(v)}`).join(', ')}
        </dd>

        <dt className="text-gray-500">Hat:</dt>
        <dd className="text-gray-100">
          {activeHat.label ? (
            <>
              <span className="font-mono">{activeHat.label}</span>
              <span className="text-gray-500 text-[10px] ml-1">(active)</span>
            </>
          ) : (
            <span className="font-mono">{activeHat.id}</span>
          )}
        </dd>

        <dt className="text-gray-500">Capability:</dt>
        <dd className="text-gray-100 font-mono">{capabilityName}</dd>

        <dt className="text-gray-500">Timeout:</dt>
        <dd className="text-gray-100">{Math.round(timeoutMs / 1000)}s</dd>

        <dt className="text-gray-500">Confidence:</dt>
        <dd className={lowConfidence ? 'text-amber-300' : 'text-gray-100'}>
          {confidencePercent}%
        </dd>
      </dl>

      {extracted.rationale && (
        <p className="text-[11px] text-gray-400 italic mb-3 px-1 border-l-2 border-gray-700 pl-2">
          {extracted.rationale}
        </p>
      )}

      {lowConfidence && (
        <div className="mb-3 rounded border border-amber-500/30 bg-amber-900/20 px-2 py-1.5 text-[11px] text-amber-200 flex items-start gap-1.5">
          <span className="text-amber-400 mt-[1px]">{'\u26A0'}</span>
          <span>Low confidence — review args carefully before approving.</span>
        </div>
      )}

      {/* Actions */}
      <div className="flex items-center justify-end gap-2 pt-1 border-t border-gray-800">
        <button
          type="button"
          onClick={onCancel}
          className="text-xs px-3 py-1 rounded bg-gray-800 text-gray-300 hover:bg-gray-700 hover:text-gray-100 transition-colors"
          aria-label="Cancel host command"
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={onApprove}
          className="text-xs px-3 py-1 rounded bg-blue-600 text-white hover:bg-blue-500 transition-colors"
          aria-label="Approve host command"
        >
          Approve
        </button>
      </div>
    </div>
  );
}

```
