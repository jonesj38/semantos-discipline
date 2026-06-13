---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/src/__tests__/pipeline.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.009613+00:00
---

# core/conversation-graph/src/__tests__/pipeline.test.ts

```ts
/**
 * RM-031b — generic `runConversationTurn` with stub ports.
 *
 * Exercises the full extractor → merger → reducer composition plus
 * the optional auto-emit hook. The stub ports are intentionally tiny
 * so the test exercises the WIRING, not any domain semantics.
 */
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { createObject, type Database } from '@semantos/semantic-objects';
import { RELATION_OBJECT_KIND } from '@semantos/scg-relations';
import { makeTestDb } from './setup.js';
import { runConversationTurn } from '../pipeline.js';
import type {
  ConversationExtractor,
  ConversationStateMerger,
  ConversationReducer,
} from '../pipeline.js';

interface DemoState {
  readonly messages: ReadonlyArray<string>;
  readonly tags: ReadonlyArray<string>;
}
interface DemoExtraction {
  readonly text: string;
  readonly tag: string;
}
interface DemoReducerResult {
  readonly intent: string;
  readonly confidence: number;
}

const extractor: ConversationExtractor<DemoState, DemoExtraction> = {
  async extract(input) {
    return {
      text: input.latestMessage,
      tag: input.latestMessage.startsWith('+1') ? 'support' : 'declaration',
    };
  },
};

const merger: ConversationStateMerger<DemoState, DemoExtraction> = {
  merge(state, extraction) {
    return {
      messages: [...state.messages, extraction.text],
      tags: [...state.tags, extraction.tag],
    };
  },
};

const reducer: ConversationReducer<DemoState, DemoExtraction, DemoReducerResult> = {
  async reduce(input) {
    return {
      intent: `${input.extraction.tag}:${input.extraction.text.slice(0, 8)}`,
      confidence: input.extraction.tag === 'support' ? 0.95 : 0.7,
    };
  },
};

describe('runConversationTurn (RM-031b)', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => {
    ({ db, close } = await makeTestDb());
  });
  afterEach(async () => {
    await close();
  });

  test('P1 composes extract → merge → reduce in order', async () => {
    const result = await runConversationTurn(
      { extractor, merger, reducer },
      {
        currentState: { messages: [], tags: [] },
        latestMessage: 'hello world',
      },
    );
    expect(result.extraction.text).toBe('hello world');
    expect(result.extraction.tag).toBe('declaration');
    expect(result.state.messages).toEqual(['hello world']);
    expect(result.state.tags).toEqual(['declaration']);
    expect(result.reducer.intent).toBe('declaration:hello wo');
    expect(result.reducer.confidence).toBe(0.7);
    expect(result.autoEmittedRelation).toBeNull();
  });

  test('P2 +1 message routes to a "support" tag', async () => {
    const result = await runConversationTurn(
      { extractor, merger, reducer },
      {
        currentState: { messages: [], tags: [] },
        latestMessage: '+1 to the proposal',
      },
    );
    expect(result.extraction.tag).toBe('support');
    expect(result.reducer.confidence).toBe(0.95);
  });

  test('P3 quoted turn + db emits REPLIES_TO via auto-emit hook', async () => {
    const conv = await createObject(db, { objectKind: 'conversation', payload: {} });
    const original = await createObject(db, { id: 't1', objectKind: 'conversation.turn', payload: {} });
    const reply = await createObject(db, { id: 't2', objectKind: 'conversation.turn', payload: {} });

    const result = await runConversationTurn(
      { db, extractor, merger, reducer },
      {
        currentState: { messages: [], tags: [] },
        latestMessage: 'reply to the previous',
        turn: {
          conversationId: conv.id,
          turnId: reply.id,
          quotedTurnId: original.id,
          authorCertId: 'cert-x',
        },
      },
    );
    expect(result.autoEmittedRelation).not.toBeNull();
    if (!result.autoEmittedRelation) return;
    expect(result.autoEmittedRelation.objectKind).toBe(RELATION_OBJECT_KIND);
    expect(result.autoEmittedRelation.payload.kind).toBe('REPLIES_TO');
    expect(result.autoEmittedRelation.payload.sourceId).toBe(reply.id);
    expect(result.autoEmittedRelation.payload.targetId).toBe(original.id);
  });

  test('P4 no db = no auto-emit (preview/read-only callers)', async () => {
    const result = await runConversationTurn(
      { extractor, merger, reducer },
      {
        currentState: { messages: [], tags: [] },
        latestMessage: 'reply to that',
        turn: {
          conversationId: 'c1',
          turnId: 't2',
          quotedTurnId: 't1',
        },
      },
    );
    expect(result.autoEmittedRelation).toBeNull();
  });

  test('P5 capability-check denial propagates from auto-emit', async () => {
    const conv = await createObject(db, { objectKind: 'conversation', payload: {} });
    const a = await createObject(db, { objectKind: 'conversation.turn', payload: {} });
    const b = await createObject(db, { objectKind: 'conversation.turn', payload: {} });
    await expect(
      runConversationTurn(
        { db, extractor, merger, reducer },
        {
          currentState: { messages: [], tags: [] },
          latestMessage: 'reply',
          turn: {
            conversationId: conv.id,
            turnId: b.id,
            quotedTurnId: a.id,
          },
          capabilityCheck: async () => {
            throw new Error('RELATION_MINT denied');
          },
        },
      ),
    ).rejects.toThrow('RELATION_MINT denied');
  });

  test('P6 extractor failures propagate; merge + reduce do not run', async () => {
    let mergeCalls = 0;
    let reduceCalls = 0;
    const throwingExtractor: ConversationExtractor<DemoState, DemoExtraction> = {
      async extract() {
        throw new Error('LLM upstream down');
      },
    };
    const trackedMerger: ConversationStateMerger<DemoState, DemoExtraction> = {
      merge(state, extraction) {
        mergeCalls += 1;
        return merger.merge(state, extraction);
      },
    };
    const trackedReducer: ConversationReducer<DemoState, DemoExtraction, DemoReducerResult> = {
      async reduce(input) {
        reduceCalls += 1;
        return reducer.reduce(input);
      },
    };
    await expect(
      runConversationTurn(
        { extractor: throwingExtractor, merger: trackedMerger, reducer: trackedReducer },
        { currentState: { messages: [], tags: [] }, latestMessage: 'x' },
      ),
    ).rejects.toThrow('LLM upstream down');
    expect(mergeCalls).toBe(0);
    expect(reduceCalls).toBe(0);
  });
});

```
