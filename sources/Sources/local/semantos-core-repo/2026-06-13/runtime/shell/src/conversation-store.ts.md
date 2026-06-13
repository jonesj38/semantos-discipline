---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/conversation-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.363817+00:00
---

# runtime/shell/src/conversation-store.ts

```ts
/**
 * ConversationStore — Multi-thread conversation state management.
 *
 * Phase 2: Replaces the single-thread ConversationState.history with
 * a thread-indexed model where each thread has its own context type,
 * encryption metadata, and participant list.
 *
 * Persistence: JSON file (matching existing loadState/saveState in chat.ts).
 * Hash chain: each message's prevMessageHash = SHA-256 of previous message.
 *
 * @module @semantos/shell/conversation-store
 */

import * as fs from 'node:fs';
import * as crypto from 'node:crypto';
import type {
  Thread, ConversationMessage, EncryptionMetadata,
  SerializedConversationStore,
} from '@semantos/protocol-types';
import { ConversationType } from '@semantos/protocol-types';

const CONVERSATIONS_FILE = '.semantos-conversations.json';

/** Generate a short UUID (collision-safe for demo). */
function uuid(): string {
  return crypto.randomUUID();
}

/** SHA-256 hash of a string, returned as hex. */
function sha256(data: string): string {
  return crypto.createHash('sha256').update(data).digest('hex');
}

/**
 * ConversationStore — manages threads and messages with JSON persistence.
 */
export class ConversationStore {
  private threads: Map<string, Thread> = new Map();
  private messages: Map<string, ConversationMessage> = new Map();
  private stateFile: string;

  constructor(stateFile?: string) {
    this.stateFile = stateFile ?? CONVERSATIONS_FILE;
    this.loadFromDisk();
    this.ensureSelfThread();
  }

  // ── Thread operations ──────────────────────────────────────

  /** Create a new conversation thread. */
  createThread(
    contextType: ConversationType,
    displayName: string,
    participants: string[],
    encryptionMetadata?: EncryptionMetadata,
  ): Thread {
    const now = new Date().toISOString();
    const thread: Thread = {
      conversationId: uuid(),
      contextType,
      displayName,
      participants,
      encryptionMetadata,
      messageIds: [],
      createdAt: now,
      lastActivity: now,
      unreadCount: 0,
      isPinned: false,
      isMuted: false,
    };
    this.threads.set(thread.conversationId, thread);
    this.saveToDisk();
    return thread;
  }

  /** Get a thread by ID. */
  getThread(conversationId: string): Thread | null {
    return this.threads.get(conversationId) ?? null;
  }

  /** List threads, optionally filtered by context type. */
  listThreads(filter?: { contextType?: ConversationType; participantCertId?: string }): Thread[] {
    let result = Array.from(this.threads.values());
    if (filter?.contextType) {
      result = result.filter(t => t.contextType === filter.contextType);
    }
    if (filter?.participantCertId) {
      result = result.filter(t => t.participants.includes(filter.participantCertId!));
    }
    return result.sort((a, b) => b.lastActivity.localeCompare(a.lastActivity));
  }

  /** Get the SELF thread (auto-created). */
  getSelfThread(): Thread {
    const self = this.listThreads({ contextType: ConversationType.SELF });
    return self[0];
  }

  /** Find an existing INDIVIDUAL thread with a specific contact. */
  findIndividualThread(localCertId: string, remoteCertId: string): Thread | null {
    return this.listThreads({ contextType: ConversationType.INDIVIDUAL })
      .find(t =>
        t.participants.includes(localCertId) &&
        t.participants.includes(remoteCertId),
      ) ?? null;
  }

  /** Update thread preferences (pin, mute). */
  updateThread(conversationId: string, updates: Partial<Pick<Thread, 'isPinned' | 'isMuted' | 'displayName'>>): void {
    const thread = this.threads.get(conversationId);
    if (!thread) return;
    Object.assign(thread, updates);
    this.saveToDisk();
  }

  // ── Message operations ─────────────────────────────────────

  /**
   * Add a message to a thread.
   * Computes prevMessageHash from the last message in the thread.
   * Returns the persisted message with computed fields.
   */
  addMessage(
    conversationId: string,
    role: 'user' | 'assistant',
    content: string,
    senderId: string,
    opts?: {
      dimensionTag?: string;
      encryptedContent?: string;
      signature?: string;
    },
  ): ConversationMessage | null {
    const thread = this.threads.get(conversationId);
    if (!thread) return null;

    // Compute hash chain
    const prevMessageId = thread.messageIds[thread.messageIds.length - 1];
    const prevMessage = prevMessageId ? this.messages.get(prevMessageId) : null;
    const prevMessageHash = prevMessage
      ? sha256(JSON.stringify({
          id: prevMessage.id,
          content: prevMessage.content,
          timestamp: prevMessage.timestamp,
        }))
      : sha256('genesis');

    // Sign message (stub signature if none provided)
    const signature = opts?.signature ?? sha256(`${senderId}:${content}:${Date.now()}`);

    const message: ConversationMessage = {
      id: uuid(),
      conversationId,
      contextType: thread.contextType,
      role,
      content,
      encryptedContent: opts?.encryptedContent,
      senderId,
      timestamp: new Date().toISOString(),
      prevMessageHash,
      signature,
      dimensionTag: opts?.dimensionTag,
    };

    this.messages.set(message.id, message);
    thread.messageIds.push(message.id);
    thread.lastActivity = message.timestamp;

    // Increment unread for non-sender participants (future: multi-device)
    if (role === 'assistant') {
      thread.unreadCount++;
    }

    this.saveToDisk();
    return message;
  }

  /** Get messages for a thread, most recent last. */
  getMessages(conversationId: string, limit?: number): ConversationMessage[] {
    const thread = this.threads.get(conversationId);
    if (!thread) return [];
    const ids = limit ? thread.messageIds.slice(-limit) : thread.messageIds;
    return ids
      .map(id => this.messages.get(id))
      .filter((m): m is ConversationMessage => m !== undefined);
  }

  /** Get the last N messages for LLM context window. */
  getRecentMessages(conversationId: string, count: number = 10): ConversationMessage[] {
    return this.getMessages(conversationId, count);
  }

  /** Verify the hash chain integrity of a thread. */
  verifyHashChain(conversationId: string): { valid: boolean; brokenAt?: string } {
    const messages = this.getMessages(conversationId);
    for (let i = 1; i < messages.length; i++) {
      const prev = messages[i - 1];
      const expectedHash = sha256(JSON.stringify({
        id: prev.id,
        content: prev.content,
        timestamp: prev.timestamp,
      }));
      if (messages[i].prevMessageHash !== expectedHash) {
        return { valid: false, brokenAt: messages[i].id };
      }
    }
    return { valid: true };
  }

  /** Mark all messages in a thread as read. */
  markRead(conversationId: string): void {
    const thread = this.threads.get(conversationId);
    if (thread) {
      thread.unreadCount = 0;
      this.saveToDisk();
    }
  }

  /** Get total message count across all threads. */
  get totalMessages(): number {
    return this.messages.size;
  }

  /** Get total thread count. */
  get totalThreads(): number {
    return this.threads.size;
  }

  // ── Persistence ────────────────────────────────────────────

  private loadFromDisk(): void {
    try {
      const raw = fs.readFileSync(this.stateFile, 'utf-8');
      const parsed: SerializedConversationStore = JSON.parse(raw);
      this.threads = new Map(parsed.threads);
      this.messages = new Map(parsed.messages);
    } catch {
      this.threads = new Map();
      this.messages = new Map();
    }
  }

  saveToDisk(): void {
    const serialized: SerializedConversationStore = {
      threads: Array.from(this.threads.entries()),
      messages: Array.from(this.messages.entries()),
    };
    fs.writeFileSync(this.stateFile, JSON.stringify(serialized, null, 2));
  }

  /** Ensure the SELF thread exists (auto-created on first use). */
  private ensureSelfThread(): void {
    const existing = this.listThreads({ contextType: ConversationType.SELF });
    if (existing.length === 0) {
      this.createThread(
        ConversationType.SELF,
        'Self',
        ['local'],
        { algorithm: 'AES-256-GCM', keyDerivation: 'LOCAL' },
      );
    }
  }
}

```
