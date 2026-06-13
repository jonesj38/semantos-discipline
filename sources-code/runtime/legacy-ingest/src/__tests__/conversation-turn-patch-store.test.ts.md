---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/conversation-turn-patch-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.140782+00:00
---

# runtime/legacy-ingest/src/__tests__/conversation-turn-patch-store.test.ts

```ts
import { describe, expect, it } from 'bun:test';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import type { ConversationTurnEvent } from '../conversation/types';
import {
  JsonlConversationTurnPatchSink,
  conversationTurnToOddjobzMessagePatch,
  rawItemToOddjobzMessagePatch,
} from '../conversation/turn-patch-store';
import type { RawItem } from '../types';

function makeEvent(overrides: Partial<ConversationTurnEvent> = {}): ConversationTurnEvent {
  return {
    providerId: 'meta',
    sessionId: 'meta:USER_001',
    channel: 'meta_messenger',
    recipientId: 'USER_001',
    role: 'customer',
    text: 'Need the tap fixed',
    timestamp: 1_700_000_000_000,
    ...overrides,
  };
}

function makeEmailItem(overrides: Partial<RawItem> = {}): RawItem {
  const raw = [
    'Message-ID: <msg-1@example.com>',
    'From: Sarah Tenant <sarah@example.com>',
    'To: Todd <todd@oddjobtodd.com.au>',
    'Subject: Leaking tap',
    'Date: Tue, 5 May 2026 10:00:00 +1000',
    '',
    'Hi Todd, the kitchen tap is leaking again.',
  ].join('\r\n');
  return {
    providerId: 'gmail',
    providerItemId: 'gmail-1',
    fetchedAt: 1_700_000_000_000,
    contentType: 'email/rfc822',
    bytes: new TextEncoder().encode(raw),
    metadata: {
      threadId: 'thread-1',
      snippet: 'kitchen tap is leaking',
      internalDate: '1777939200000',
    },
    ...overrides,
  };
}

describe('conversation turn patch store', () => {
  it('maps a turn to an oddjobz.message.v1 patch row', () => {
    const patch = conversationTurnToOddjobzMessagePatch(makeEvent(), 1_700_000_000_123);

    expect(patch.schema).toBe('oddjobz.message.v1');
    expect(patch.op).toBe('oddjobz.message.v1');
    expect(patch.patchId).toMatch(/^msg_[0-9a-f]{16}$/);
    expect(patch.sessionId).toBe('meta:USER_001');
    expect(patch.target).toEqual({
      type: 'conversation-session',
      ref: 'meta:USER_001',
    });
    expect(patch.writtenAt).toBe(1_700_000_000_123);
  });

  it('appends each turn to messages.jsonl under the oddjobz data dir', () => {
    const root = mkdtempSync(join(tmpdir(), 'semantos-turns-'));
    try {
      const sink = new JsonlConversationTurnPatchSink({
        root,
        now: () => 1_700_000_000_456,
      });

      sink.append(makeEvent({ text: 'First message' }));
      sink.append(makeEvent({ role: 'assistant', text: 'Where is it?' }));

      const path = join(root, 'data', 'oddjobz', 'messages.jsonl');
      const lines = readFileSync(path, 'utf8').trim().split('\n');
      const rows = lines.map((line) => JSON.parse(line) as Record<string, unknown>);

      expect(rows).toHaveLength(2);
      expect(rows[0]?.schema).toBe('oddjobz.message.v1');
      expect(rows[0]?.text).toBe('First message');
      expect(rows[1]?.role).toBe('assistant');
      expect(rows[1]?.writtenAt).toBe(1_700_000_000_456);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('maps a Gmail raw email to the same oddjobz.message.v1 patch schema', () => {
    const patch = rawItemToOddjobzMessagePatch(makeEmailItem(), 1_700_000_000_789);

    expect(patch?.schema).toBe('oddjobz.message.v1');
    expect(patch?.providerId).toBe('gmail');
    expect(patch?.channel).toBe('email');
    expect(patch?.sessionId).toBe('email:thread-1');
    expect(patch?.recipientId).toBe('sarah@example.com');
    expect(patch?.role).toBe('customer');
    expect(patch?.text).toContain('Subject: Leaking tap');
    expect(patch?.text).toContain('kitchen tap is leaking');
    expect(patch?.source?.sourceBlobKey).toBe('legacy-ingest/gmail/gmail-1');
    expect(patch?.target).toEqual({
      type: 'conversation-session',
      ref: 'email:thread-1',
    });
  });

  it('deduplicates patch ids across repeated appends', () => {
    const root = mkdtempSync(join(tmpdir(), 'semantos-turns-'));
    try {
      const sink = new JsonlConversationTurnPatchSink({ root });
      const item = makeEmailItem();

      sink.appendRawItem(item);
      sink.appendRawItem(item);

      const path = join(root, 'data', 'oddjobz', 'messages.jsonl');
      const lines = readFileSync(path, 'utf8').trim().split('\n');

      expect(lines).toHaveLength(1);
      expect(JSON.parse(lines[0]!).providerId).toBe('gmail');
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  it('notifies an observer only when a new patch row is written', () => {
    const root = mkdtempSync(join(tmpdir(), 'semantos-turns-'));
    try {
      const observed: string[] = [];
      const sink = new JsonlConversationTurnPatchSink({
        root,
        onPatch: (patch) => {
          observed.push(patch.patchId);
        },
      });
      const item = makeEmailItem();

      sink.appendRawItem(item);
      sink.appendRawItem(item);

      expect(observed).toHaveLength(1);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});

```
