---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/action-queue.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.834003+00:00
---

# archive/apps-mud/src/action-queue.ts

```ts
/**
 * ActionQueue -- async iterable queue for room actor action serialization.
 *
 * Each room actor has exactly one ActionQueue. Player actions enter the queue
 * and the actor drains them sequentially. This eliminates all concurrency
 * issues within a room: two players attacking the same goblin never race.
 *
 * The queue is unbounded — backpressure is not needed because human input
 * rates are orders of magnitude below the processing rate.
 */

export class ActionQueue<T> {
  private queue: T[] = [];
  private resolveWait: ((value: void) => void) | null = null;
  private closed = false;

  /** Enqueue an action. Returns immediately. */
  push(action: T): void {
    if (this.closed) throw new Error('ActionQueue is closed');
    this.queue.push(action);
    if (this.resolveWait) {
      this.resolveWait();
      this.resolveWait = null;
    }
  }

  /** Number of pending actions. */
  get length(): number {
    return this.queue.length;
  }

  /** Close the queue. No more actions can be pushed. */
  close(): void {
    this.closed = true;
    if (this.resolveWait) {
      this.resolveWait();
      this.resolveWait = null;
    }
  }

  /** Whether the queue has been closed. */
  get isClosed(): boolean {
    return this.closed;
  }

  /**
   * Drain the queue: yields actions one at a time, in order.
   * Awaits when empty. Stops when closed and drained.
   */
  async *drain(): AsyncGenerator<T> {
    while (true) {
      if (this.queue.length > 0) {
        yield this.queue.shift()!;
      } else if (this.closed) {
        return;
      } else {
        await new Promise<void>(resolve => {
          this.resolveWait = resolve;
        });
      }
    }
  }

  /**
   * Take the next action, or null if closed and empty.
   * Blocks until an action is available.
   */
  async take(): Promise<T | null> {
    if (this.queue.length > 0) {
      return this.queue.shift()!;
    }
    if (this.closed) return null;
    await new Promise<void>(resolve => {
      this.resolveWait = resolve;
    });
    return this.queue.length > 0 ? this.queue.shift()! : null;
  }
}

```
