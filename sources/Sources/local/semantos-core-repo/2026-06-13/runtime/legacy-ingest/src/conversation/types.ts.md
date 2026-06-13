---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/conversation/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.161121+00:00
---

# runtime/legacy-ingest/src/conversation/types.ts

```ts
/**
 * Conversation engine types.
 *
 * Channel-agnostic multi-turn intake conversation. The same ConversationEngine
 * runs regardless of whether the customer is on Meta DM or the website widget.
 * The only difference is the ConversationTransport, which delivers messages to
 * the right channel.
 *
 * Flow:
 *   1. Inbound message arrives (webhook or HTTP POST).
 *   2. Transport wraps it as a ConversationTurn and calls engine.handleTurn().
 *   3. Engine decides what to ask next (or signals extraction complete).
 *   4. Engine calls transport.send() with the reply text.
 *   5. On completion, engine produces a Proposal for the ratification queue.
 *
 * Session state is held in memory and persisted as JSON blobs so it can
 * survive restarts. The session id maps to a thread id on the transport side.
 */

/** Which channel this session came through. */
export type ConversationChannel = 'meta_messenger' | 'meta_instagram' | 'widget';

/** A single turn in the conversation. */
export interface ConversationTurn {
  /** Direction from the perspective of the intake system. */
  role: 'customer' | 'assistant';
  text: string;
  /** Unix ms when this turn was recorded. */
  timestamp: number;
}

/**
 * Channel-neutral audit event for a single conversation turn. Webhook/widget
 * adapters can expose this to their host so every turn can be persisted as an
 * oddjobz.message.v1 cell or intent conversation patch without baking Oddjobz
 * storage into the conversation engine.
 */
export interface ConversationTurnEvent {
  providerId: 'meta' | 'widget';
  sessionId: string;
  channel: ConversationChannel;
  recipientId: string;
  role: ConversationTurn['role'];
  text: string;
  timestamp: number;
}

export type ConversationTurnSink = (event: ConversationTurnEvent) => Promise<void> | void;

/** Persisted state for an ongoing intake conversation. */
export interface ConversationSession {
  /** Stable session id, e.g. `meta:USER_PSID` or `widget:<uuid>`. */
  readonly sessionId: string;
  readonly channel: ConversationChannel;
  /** Channel-specific recipient id for transport replies. */
  readonly recipientId: string;
  /** All turns so far, oldest first. */
  turns: ConversationTurn[];
  /** Partially-gathered job facts. Populated incrementally across turns. */
  facts: ConversationFacts;
  /** Current state of the intake FSM. */
  state: ConversationState;
  /** Unix ms when the session was created. */
  readonly createdAt: number;
  /** Unix ms when the session was last updated. */
  updatedAt: number;
}

/** Facts we're trying to gather. All optional until extraction is signalled. */
export interface ConversationFacts {
  customerName?: string;
  customerPhone?: string;
  jobDescription?: string;
  jobLocation?: string;
  desiredDate?: string;
  referenceNumber?: string;
}

export type ConversationState =
  | 'greeting'         // session just started, first reply not yet sent
  | 'gathering'        // asking clarifying questions
  | 'confirming'       // summarising and asking for confirmation
  | 'complete'         // enough info, extraction ready
  | 'abandoned';       // no response for too long

/**
 * Channel-agnostic transport port.
 * The engine calls `send()` to deliver a reply. The transport handles the
 * actual HTTP call (Meta Send API, WebSocket push, SSE, etc.).
 */
export interface ConversationTransport {
  send(recipientId: string, text: string): Promise<void>;
}

/** Result of processing a single turn. */
export interface TurnResult {
  /** Reply text sent back to the customer (or null if session is now complete). */
  replySent: string | null;
  /** Set when the engine has gathered enough info and closed the session. */
  completed: boolean;
  /** Populated when completed = true. Passed to the extraction pipeline. */
  extractedText?: string;
}

```
