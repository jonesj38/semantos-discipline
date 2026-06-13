---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/share-channel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.965270+00:00
---

# archive/apps-loom-react/src/helm/share-channel.ts

```ts
/**
 * ShareChannel — simulates hat-to-hat document transfer.
 *
 * In production this would be a Plexus edge with BRC-42 ECDH encryption.
 * For demo, we use an in-memory mailbox: sender drops a bundle,
 * recipient picks it up. Each hat has its own inbox.
 */

import type { DocumentBundle } from './document-bundle';

export interface ShareEnvelope {
  /** Unique envelope ID. */
  id: string;
  /** Sender hat ID. */
  from: string;
  /** Sender display name. */
  fromName: string;
  /** Recipient hat ID. */
  to: string;
  /** The document bundle. */
  bundle: DocumentBundle;
  /** When it was sent. */
  sentAt: number;
  /** Whether the recipient has opened it. */
  read: boolean;
}

const STORAGE_KEY = 'semantos-share-channel';

/** In-memory + localStorage backed mailbox. */
class ShareChannelStore {
  private envelopes: ShareEnvelope[] = [];
  private listeners: Set<() => void> = new Set();

  constructor() {
    this.load();
  }

  private load(): void {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) this.envelopes = JSON.parse(stored);
    } catch {
      this.envelopes = [];
    }
  }

  private save(): void {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.envelopes));
    } catch {
      // Storage full — envelopes are session-only
    }
    this.notify();
  }

  private notify(): void {
    for (const listener of this.listeners) listener();
  }

  /** Send a bundle from one hat to another. */
  send(from: string, fromName: string, to: string, bundle: DocumentBundle): ShareEnvelope {
    const envelope: ShareEnvelope = {
      id: `env-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      from,
      fromName,
      to,
      bundle,
      sentAt: Date.now(),
      read: false,
    };
    this.envelopes.push(envelope);
    this.save();
    return envelope;
  }

  /** Get all envelopes for a recipient hat. */
  getInbox(facetId: string): ShareEnvelope[] {
    return this.envelopes.filter(e => e.to === facetId);
  }

  /** Get unread count for a hat. */
  getUnreadCount(facetId: string): number {
    return this.envelopes.filter(e => e.to === facetId && !e.read).length;
  }

  /** Mark an envelope as read. */
  markRead(envelopeId: string): void {
    const env = this.envelopes.find(e => e.id === envelopeId);
    if (env) {
      env.read = true;
      this.save();
    }
  }

  /** Get all sent envelopes from a hat. */
  getSent(facetId: string): ShareEnvelope[] {
    return this.envelopes.filter(e => e.from === facetId);
  }

  /** Subscribe to changes. */
  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Clear all envelopes (for testing). */
  clear(): void {
    this.envelopes = [];
    this.save();
  }
}

/** Singleton share channel. */
export const shareChannel = new ShareChannelStore();

```
