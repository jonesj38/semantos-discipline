---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/InboxIndicator.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.962904+00:00
---

# archive/apps-loom-react/src/helm/InboxIndicator.tsx

```tsx
/**
 * InboxIndicator — shows unread shared document count in the top bar.
 *
 * Clicking opens a dropdown of pending shared bundles.
 * Selecting one navigates to the Do mode and triggers import/merge.
 */

import { useState, useCallback, useRef, useEffect, useMemo } from 'react';
import { useIdentity } from '../identity/IdentityProvider';
import { shareChannel, type ShareEnvelope } from './share-channel';

export interface InboxIndicatorProps {
  onOpenEnvelope: (envelope: ShareEnvelope) => void;
}

export function InboxIndicator({ onOpenEnvelope }: InboxIndicatorProps) {
  const { activeHat } = useIdentity();
  const [open, setOpen] = useState(false);
  const [version, setVersion] = useState(0);
  const ref = useRef<HTMLDivElement>(null);

  // Subscribe to share channel
  useState(() => {
    const unsub = shareChannel.subscribe(() => setVersion(v => v + 1));
    return unsub;
  });

  const facetId = activeHat?.id ?? '';
  const inbox = useMemo(() => shareChannel.getInbox(facetId), [facetId, version]);
  const unreadCount = useMemo(() => shareChannel.getUnreadCount(facetId), [facetId, version]);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  const handleOpen = useCallback((env: ShareEnvelope) => {
    shareChannel.markRead(env.id);
    setOpen(false);
    onOpenEnvelope(env);
  }, [onOpenEnvelope]);

  if (inbox.length === 0) return null;

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="relative text-gray-400 hover:text-gray-200 transition-colors text-sm px-1.5 py-0.5 rounded hover:bg-gray-800"
        aria-label="Inbox"
      >
        &#9993;
        {unreadCount > 0 && (
          <span className="absolute -top-1 -right-1 text-[9px] bg-blue-600 text-white w-3.5 h-3.5 rounded-full flex items-center justify-center">
            {unreadCount}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute top-full right-0 mt-1 bg-gray-800 border border-gray-700 rounded shadow-lg z-50 min-w-[220px] max-h-[300px] overflow-y-auto">
          <div className="px-3 py-1.5 border-b border-gray-700">
            <p className="text-[10px] text-gray-500 uppercase tracking-wider">
              Shared with you
            </p>
          </div>
          {inbox.map(env => (
            <button
              key={env.id}
              onClick={() => handleOpen(env)}
              className={`w-full text-left px-3 py-2 text-xs transition-colors border-b border-gray-700/50 last:border-0 ${
                !env.read ? 'bg-blue-950/20 hover:bg-blue-950/40' : 'hover:bg-gray-700'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="text-gray-200 truncate">
                  {!env.read && <span className="text-blue-400 mr-1">&bull;</span>}
                  {(env.bundle.payload.title as string) || 'Untitled'}
                </span>
              </div>
              <p className="text-[10px] text-gray-500 mt-0.5">
                from {env.fromName} &middot; {env.bundle.patches.length} patches &middot;{' '}
                {new Date(env.sentAt).toLocaleTimeString()}
              </p>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

```
