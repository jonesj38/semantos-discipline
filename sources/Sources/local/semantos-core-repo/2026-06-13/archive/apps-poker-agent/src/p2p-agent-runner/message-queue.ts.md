---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/message-queue.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.788144+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/message-queue.ts

```ts
/**
 * Per-game move queue — atom-backed FIFO of `PokerMoveMessage`s
 * received from the transport, with `waitForMove(gameId)` exposed
 * as an async effect.
 *
 * The legacy runner kept this as a closure local to `run()`; the
 * extraction lets tests inject moves without touching the
 * transport, and lets dashboards subscribe to the queue depth.
 */

import { atom, get, set, type Atom } from '@semantos/state';

import type { PokerMoveMessage } from './transport-port';

export interface MessageQueueAtoms {
  gameId: string;
  /** Snapshot of pending moves. Re-set via `set` so subscribers fire. */
  messageQueueAtom: Atom<PokerMoveMessage[]>;
}

const registry = new Map<string, MessageQueueAtoms>();
const resolverRegistry = new Map<string, ((m: PokerMoveMessage) => void) | null>();

export function getMessageQueueAtoms(gameId: string): MessageQueueAtoms {
  const existing = registry.get(gameId);
  if (existing) return existing;
  const bundle: MessageQueueAtoms = {
    gameId,
    messageQueueAtom: atom<PokerMoveMessage[]>([]),
  };
  registry.set(gameId, bundle);
  return bundle;
}

export function resetMessageQueueAtoms(): void {
  registry.clear();
  resolverRegistry.clear();
}

/**
 * Push a move onto the queue. If a `waitForMove` consumer is
 * pending, it resolves immediately and the move bypasses the
 * queue (matches the legacy `moveResolver` semantics).
 */
export function enqueueMove(gameId: string, move: PokerMoveMessage): void {
  const resolver = resolverRegistry.get(gameId);
  if (resolver) {
    resolverRegistry.set(gameId, null);
    resolver(move);
    return;
  }
  const a = getMessageQueueAtoms(gameId).messageQueueAtom;
  set(a, [...get(a), move]);
}

/**
 * Pop the head of the queue. If empty, returns a promise that
 * resolves the next time `enqueueMove` is called for this gameId.
 */
export function waitForMove(gameId: string): Promise<PokerMoveMessage> {
  const a = getMessageQueueAtoms(gameId).messageQueueAtom;
  const queue = get(a);
  if (queue.length > 0) {
    const [head, ...rest] = queue;
    set(a, rest);
    return Promise.resolve(head);
  }
  return new Promise<PokerMoveMessage>((resolve) => {
    resolverRegistry.set(gameId, resolve);
  });
}

/** Snapshot of the current queue depth (for dashboards/tests). */
export function queueDepth(gameId: string): number {
  return get(getMessageQueueAtoms(gameId).messageQueueAtom).length;
}

```
