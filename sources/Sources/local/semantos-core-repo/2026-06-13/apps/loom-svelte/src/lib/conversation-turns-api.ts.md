---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/conversation-turns-api.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.082743+00:00
---

# apps/loom-svelte/src/lib/conversation-turns-api.ts

```ts
/**
 * conversation-turns-api.ts — typed client for
 * GET  /api/v1/conversation/turns?entityRef=<jobId>
 * POST /api/v1/voice-note  { transcript, entity_cell_hash }
 *
 * Wire shape mirrors ConversationTurn.fromJson in
 * apps/oddjobz-mobile/lib/src/repl/conversation_turn.dart verbatim.
 */

export interface ConversationTurn {
  /** UUID turn id from Postgres. */
  turnId: string;
  /** UUID conversation id. */
  conversationId: string;
  /** 'customer' | 'operator' | 'assistant' */
  participantRole: string;
  /** 'inbound' | 'outbound' */
  direction: string;
  /** Surface: 'gmail' | 'email' | 'sms' | 'widget' | 'voice_note' | 'repl' | ... */
  surface: string;
  /** Human-readable message body. */
  bodyText: string;
  /** Unix epoch milliseconds. */
  timestamp: number;
  /** For outbound turns: 'proposed' | 'approved' | 'sent' | 'delivered' | 'failed' | null */
  outboundState: string | null;
  /** Sender display name (email address, phone, contact name). */
  identityValue: string | null;
}

/**
 * Fetch turns for a job via GET /api/v1/conversation/turns?entityRef=<jobId>.
 * Returns empty array on error — callers show an empty state rather than crashing.
 */
export async function fetchTurns(
  jobId: string,
  bearer: string,
): Promise<ConversationTurn[]> {
  if (!jobId || !bearer) return [];
  try {
    const res = await fetch(
      `/api/v1/conversation/turns?entityRef=${encodeURIComponent(jobId)}`,
      { headers: { Authorization: `Bearer ${bearer}` } },
    );
    if (!res.ok) return [];
    const data = (await res.json()) as { ok?: boolean; turns?: unknown[] };
    return (data.turns ?? []) as ConversationTurn[];
  } catch {
    return [];
  }
}

/**
 * Add an operator note to a job's conversation thread via
 * POST /api/v1/voice-note (reuses the voice-note endpoint which
 * writes an operator-role ConversationTurn when entity_cell_hash is present).
 *
 * Returns true on success, false on error.
 */
export async function sendOperatorNote(
  jobId: string,
  text: string,
  bearer: string,
): Promise<boolean> {
  if (!jobId || !text.trim() || !bearer) return false;
  try {
    const res = await fetch('/api/v1/voice-note', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${bearer}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ transcript: text.trim(), entity_cell_hash: jobId }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

```
