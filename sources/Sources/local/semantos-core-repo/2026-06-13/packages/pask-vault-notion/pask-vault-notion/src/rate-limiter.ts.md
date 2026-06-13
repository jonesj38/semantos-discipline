---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-vault-notion/pask-vault-notion/src/rate-limiter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.443656+00:00
---

# packages/pask-vault-notion/pask-vault-notion/src/rate-limiter.ts

```ts
/**
 * Token-bucket rate limiter — DB4 §4.
 *
 * Fills at `fillRate` tokens/second up to `capacity`. Each API call
 * costs 1 token. If no token is available, `acquire()` resolves after
 * the necessary wait.
 */

export class TokenBucket {
  private tokens: number;
  private lastRefill: number;

  constructor(
    private readonly capacity: number,
    private readonly fillRate: number, // tokens per second
  ) {
    this.tokens = capacity;
    this.lastRefill = Date.now();
  }

  private refill(now = Date.now()): void {
    const elapsed = (now - this.lastRefill) / 1000;
    this.tokens = Math.min(this.capacity, this.tokens + elapsed * this.fillRate);
    this.lastRefill = now;
  }

  /** Resolves when a token is available, waiting if necessary. */
  async acquire(): Promise<void> {
    const now = Date.now();
    this.refill(now);
    if (this.tokens >= 1) {
      this.tokens -= 1;
      return;
    }
    const waitMs = ((1 - this.tokens) / this.fillRate) * 1000;
    await new Promise<void>((res) => setTimeout(res, waitMs));
    this.refill();
    this.tokens = Math.max(0, this.tokens - 1);
  }
}

```
