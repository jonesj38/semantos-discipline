---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/conversation-patch.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.353524+00:00
---

# runtime/intent/src/__tests__/conversation-patch.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { writeConversationPatch } from '../conversation-patch';
import type {
  ConversationPatchDeps,
  ConversationPatchShape,
} from '../conversation-patch';
import { createInMemoryLogger } from '../logger';
import type { CorrelationId, PatchId } from '../types';

const mkDeps = (
  over: Partial<ConversationPatchDeps> = {},
): ConversationPatchDeps & {
  writes: Array<{ objectId: string; patch: ConversationPatchShape }>;
} => {
  const writes: Array<{ objectId: string; patch: ConversationPatchShape }> = [];
  return {
    write: (objectId, patch) => {
      writes.push({ objectId, patch });
    },
    logger: createInMemoryLogger(),
    generatePatchId: () => 'patch-gen-1',
    generateCorrelationId: () => 'corr-gen-1',
    now: () => 1_700_000_000_000,
    writes,
    ...over,
  };
};

describe('writeConversationPatch', () => {
  test('writes a well-formed ObjectPatch with kind=conversation', async () => {
    const deps = mkDeps();
    await writeConversationPatch(
      {
        objectId: 'obj-1',
        hatId: 'hat-tenant',
        body: 'the kitchen tap is dripping',
        hatCapabilities: [1, 2],
        source: 'nl',
      },
      deps,
    );

    expect(deps.writes).toHaveLength(1);
    const { objectId, patch } = deps.writes[0]!;
    expect(objectId).toBe('obj-1');
    expect(patch.kind).toBe('conversation');
    expect(patch.id).toBe('patch-gen-1');
    expect(patch.timestamp).toBe(1_700_000_000_000);
    expect(patch.hatId).toBe('hat-tenant');
    expect(patch.hatCapabilities).toEqual([1, 2]);
    expect(patch.delta).toEqual({
      body: 'the kitchen tap is dripping',
      hatId: 'hat-tenant',
      source: 'nl',
    });
  });

  test('emits exactly one conversation_patch_written stage event', async () => {
    const logger = createInMemoryLogger();
    const deps = mkDeps({ logger });

    await writeConversationPatch(
      { objectId: 'obj-1', hatId: 'hat-1', body: 'hi', source: 'voice' },
      deps,
    );

    expect(logger.events).toHaveLength(1);
    const ev = logger.events[0]!;
    expect(ev.stage).toBe('conversation_patch_written');
    expect(ev.intentId).toBeNull(); // no Intent on the cheap path
    expect(ev.hatId).toBe('hat-1');
    expect(ev.source).toBe('voice');
    expect(ev.data).toEqual({ objectId: 'obj-1', patchId: 'patch-gen-1' });
  });

  test('generated correlationId propagates into the event', async () => {
    const logger = createInMemoryLogger();
    const deps = mkDeps({ logger });

    const result = await writeConversationPatch(
      { objectId: 'obj-1', hatId: 'hat-1', body: 'hi', source: 'nl' },
      deps,
    );

    expect(result.correlationId).toBe('corr-gen-1' as CorrelationId);
    expect(logger.events[0]!.correlationId).toBe('corr-gen-1' as CorrelationId);
  });

  test('caller-supplied correlationId is threaded through unchanged', async () => {
    const logger = createInMemoryLogger();
    const deps = mkDeps({ logger });

    const given = 'corr-turn-42' as CorrelationId;
    const result = await writeConversationPatch(
      {
        objectId: 'obj-1',
        hatId: 'hat-1',
        body: 'hi',
        source: 'nl',
        correlationId: given,
      },
      deps,
    );

    expect(result.correlationId).toBe(given);
    expect(logger.events[0]!.correlationId).toBe(given);
  });

  test('caller-supplied patchId wins over generator', async () => {
    const deps = mkDeps();
    const pid = 'patch-specific' as PatchId;
    const result = await writeConversationPatch(
      {
        objectId: 'obj-1',
        hatId: 'hat-1',
        body: 'hi',
        source: 'ui',
        patchId: pid,
      },
      deps,
    );
    expect(result.patchId).toBe(pid);
    expect(deps.writes[0]!.patch.id).toBe(pid);
  });

  test('write() happens before the stage event fires (event reflects persisted state)', async () => {
    const order: string[] = [];
    const logger = createInMemoryLogger();
    const deps: ConversationPatchDeps = {
      ...mkDeps({ logger }),
      write: async () => {
        order.push('write');
      },
      logger: {
        emit: ev => {
          order.push('emit');
          logger.emit(ev);
        },
      },
    };

    await writeConversationPatch(
      { objectId: 'obj-1', hatId: 'hat-1', body: 'hi', source: 'nl' },
      deps,
    );

    expect(order).toEqual(['write', 'emit']);
  });

  test('async write is awaited before event', async () => {
    let writeResolved = false;
    const logger = createInMemoryLogger();
    const deps: ConversationPatchDeps = {
      ...mkDeps({ logger }),
      write: () =>
        new Promise(r =>
          setTimeout(() => {
            writeResolved = true;
            r();
          }, 10),
        ),
      logger: {
        emit: ev => {
          // When event fires, write must have resolved already.
          expect(writeResolved).toBe(true);
          logger.emit(ev);
        },
      },
    };

    await writeConversationPatch(
      { objectId: 'obj-1', hatId: 'hat-1', body: 'hi', source: 'nl' },
      deps,
    );
    expect(logger.events).toHaveLength(1);
  });
});

```
