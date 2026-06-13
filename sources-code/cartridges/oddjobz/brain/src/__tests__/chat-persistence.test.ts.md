---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/chat-persistence.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.513754+00:00
---

# cartridges/oddjobz/brain/src/__tests__/chat-persistence.test.ts

```ts
/**
 * D-O6b — Deliverable 1 — chat persistence tests.
 *
 * Acceptance:
 *  - Each visitor turn yields TWO `oddjobz.message.v1` cells (visitor +
 *    ai).
 *  - Both carry the same channelId derived from the chatSessionId.
 *  - messageIds are deterministic — same input bytes always produce
 *    the same cell hashes.
 *  - The cells round-trip through `messageCellType.pack/unpack`
 *    byte-identically.
 *  - The reconstructChatThread helper sorts and filters correctly.
 */

import { describe, expect, test } from 'bun:test';
import {
  buildVisitorMessageCell,
  buildAiMessageCell,
  buildChatTurn,
  chatSessionToChannelId,
  chatMessageId,
  reconstructChatThread,
  type ChatPersistenceInput,
} from '../chat-persistence.js';
import { messageCellType } from '../cell-types/message.js';

const TURN: ChatPersistenceInput = {
  chatSessionId: 'session-deck-repair-abc-123',
  visitorText: 'Hi, I need a quote for a deck repair, urgent, ~$3000 budget.',
  aiText:
    'Sure — can do tomorrow morning between 9 and 11. What suburb are you in?',
  turnIndex: 0,
  nowIso: '2026-05-01T09:00:00Z',
};

describe('§O6b — chat persistence — channelId derivation', () => {
  test('chatSessionToChannelId is deterministic + UUID-v4 shape', () => {
    const a = chatSessionToChannelId('sess-abc');
    const b = chatSessionToChannelId('sess-abc');
    expect(a).toBe(b);
    expect(a).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  test('different chatSessionIds yield different channelIds', () => {
    const a = chatSessionToChannelId('sess-a');
    const b = chatSessionToChannelId('sess-b');
    expect(a).not.toBe(b);
  });

  test('empty chatSessionId yields the all-zeros UUID', () => {
    expect(chatSessionToChannelId('')).toBe(
      '00000000-0000-4000-8000-000000000000',
    );
  });
});

describe('§O6b — chat persistence — messageId derivation', () => {
  test('chatMessageId is deterministic per (session, kind, sequence)', () => {
    const a = chatMessageId('s', 'visitor', 0);
    const b = chatMessageId('s', 'visitor', 0);
    expect(a).toBe(b);
  });

  test('visitor and ai messageIds for the same turn differ', () => {
    expect(chatMessageId('s', 'visitor', 0)).not.toBe(
      chatMessageId('s', 'ai', 0),
    );
  });

  test('different turn indices yield different messageIds', () => {
    expect(chatMessageId('s', 'visitor', 0)).not.toBe(
      chatMessageId('s', 'visitor', 1),
    );
  });
});

describe('§O6b — chat persistence — cell construction', () => {
  test('buildVisitorMessageCell emits a senderType=customer / channel=webchat cell', () => {
    const c = buildVisitorMessageCell(TURN);
    expect(c.senderType).toBe('customer');
    expect(c.channel).toBe('webchat');
    expect(c.messageType).toBe('text');
    expect(c.rawContent).toBe(TURN.visitorText);
    expect(c.createdAt).toBe(TURN.nowIso);
    expect(c.channelId).toBe(chatSessionToChannelId(TURN.chatSessionId));
    expect(c.customerId).toBe(chatSessionToChannelId(TURN.chatSessionId));
  });

  test('buildAiMessageCell emits a senderType=ai cell', () => {
    const c = buildAiMessageCell(TURN);
    expect(c.senderType).toBe('ai');
    expect(c.channel).toBe('webchat');
    expect(c.messageType).toBe('text');
    expect(c.rawContent).toBe(TURN.aiText);
    expect(c.createdAt).toBe(TURN.nowIso);
    expect(c.channelId).toBe(chatSessionToChannelId(TURN.chatSessionId));
  });

  test('visitor + ai cells share a channelId — thread reconstruction works', () => {
    const v = buildVisitorMessageCell(TURN);
    const a = buildAiMessageCell(TURN);
    expect(v.channelId).toBe(a.channelId);
  });

  test('visitor + ai cells have different messageIds', () => {
    const v = buildVisitorMessageCell(TURN);
    const a = buildAiMessageCell(TURN);
    expect(v.messageId).not.toBe(a.messageId);
  });

  test('rejects empty visitorText', () => {
    expect(() =>
      buildVisitorMessageCell({ ...TURN, visitorText: '' }),
    ).toThrow(/visitorText/);
  });

  test('rejects empty aiText', () => {
    expect(() => buildAiMessageCell({ ...TURN, aiText: '' })).toThrow(/aiText/);
  });
});

describe('§O6b — chat persistence — cells pack through oddjobz.message.v1', () => {
  test('buildChatTurn packed bytes round-trip via messageCellType.unpack', () => {
    const turn = buildChatTurn(TURN);
    const v = messageCellType.unpack(turn.visitorBytes);
    const a = messageCellType.unpack(turn.aiBytes);
    expect(v.messageId).toBe(turn.visitorCell.messageId);
    expect(a.messageId).toBe(turn.aiCell.messageId);
    expect(v.senderType).toBe('customer');
    expect(a.senderType).toBe('ai');
  });

  test('buildChatTurn produces deterministic bytes', () => {
    const a = buildChatTurn(TURN);
    const b = buildChatTurn(TURN);
    expect(a.visitorBytes.length).toBe(b.visitorBytes.length);
    for (let i = 0; i < a.visitorBytes.length; i++) {
      expect(a.visitorBytes[i]).toBe(b.visitorBytes[i] as number);
    }
    expect(a.aiBytes.length).toBe(b.aiBytes.length);
    for (let i = 0; i < a.aiBytes.length; i++) {
      expect(a.aiBytes[i]).toBe(b.aiBytes[i] as number);
    }
  });
});

describe('§O6b — chat persistence — reconstructChatThread', () => {
  test('filters cells by channelId derived from chatSessionId', () => {
    const t1 = buildChatTurn(TURN);
    const t2 = buildChatTurn({
      ...TURN,
      chatSessionId: 'other-session',
      visitorText: 'unrelated',
      aiText: 'unrelated reply',
      turnIndex: 0,
    });
    const all = [t1.visitorCell, t1.aiCell, t2.visitorCell, t2.aiCell];
    const reconstructed = reconstructChatThread(all, TURN.chatSessionId);
    expect(reconstructed).toHaveLength(2);
    for (const c of reconstructed) {
      expect(c.channelId).toBe(
        chatSessionToChannelId(TURN.chatSessionId),
      );
    }
  });

  test('sorts by createdAt then messageId', () => {
    const t0 = buildChatTurn({ ...TURN, turnIndex: 0, nowIso: '2026-05-01T09:00:00Z' });
    const t1 = buildChatTurn({
      ...TURN,
      turnIndex: 1,
      nowIso: '2026-05-01T09:01:00Z',
      visitorText: 'follow-up',
      aiText: 'follow-up reply',
    });
    const all = [t1.aiCell, t0.aiCell, t1.visitorCell, t0.visitorCell];
    const sorted = reconstructChatThread(all, TURN.chatSessionId);
    expect(sorted).toHaveLength(4);
    // First two from turn 0, then turn 1.
    expect(sorted[0]!.createdAt).toBe('2026-05-01T09:00:00Z');
    expect(sorted[1]!.createdAt).toBe('2026-05-01T09:00:00Z');
    expect(sorted[2]!.createdAt).toBe('2026-05-01T09:01:00Z');
    expect(sorted[3]!.createdAt).toBe('2026-05-01T09:01:00Z');
  });
});

```
