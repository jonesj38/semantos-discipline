---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/api/hooks.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.483475+00:00
---

# packages/calendar/src/api/hooks.ts

```ts
/**
 * Pluggable hook for conversation-patch integration.
 *
 * The calendar extension does not own any conversation-patch storage.
 * Consumers (bots) that want to see calendar events as typed patches
 * register a writer via `setConversationPatchWriter`. When API calls
 * (holdSlot/bookSlot/releaseSlot/cancelBooking) include a `conversationId`,
 * the writer is invoked.
 *
 * If no writer is registered, calendar API calls with a conversationId
 * are no-op (they don't fail).
 *
 * The expected writer shape matches `@semantos/intent`'s
 * `writeConversationPatch` — but we don't import from there (would create
 * a cycle since intent doesn't depend on calendar-ext).
 */
export interface CalendarPatchEvent {
  conversationId: string;
  lexicon: 'calendar';
  verb: 'propose' | 'hold' | 'book' | 'release' | 'reschedule' | 'cancel';
  objectKind: 'slot';
  objectId: string;
  delta: {
    hatId: string;
    startAt: string; // ISO
    endAt: string; // ISO
    subjectKind: string;
    subjectId: string;
    [key: string]: unknown;
  };
}

export type ConversationPatchWriter = (event: CalendarPatchEvent) => Promise<void> | void;

let writer: ConversationPatchWriter | null = null;

export function setConversationPatchWriter(fn: ConversationPatchWriter | null): void {
  writer = fn;
}

export function getConversationPatchWriter(): ConversationPatchWriter | null {
  return writer;
}

export async function emitPatch(event: CalendarPatchEvent): Promise<void> {
  if (!writer) return;
  try {
    await writer(event);
  } catch (err) {
    // Emit errors are logged but do not fail the calendar operation.
    // The booking/hold is already persisted; losing the patch is
    // recoverable (can be reconstructed from DB state).
    // eslint-disable-next-line no-console
    console.warn('[calendar] conversation patch writer failed:', err);
  }
}

```
