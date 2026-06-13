---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/shared/audit-log-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.771199+00:00
---

# archive/apps-poker-agent/src/shared/audit-log-builder.ts

```ts
/**
 * Audit-log builder — pure builder for poker hand transcripts.
 *
 * Takes a chronological event stream and renders a fixed,
 * human-readable string. The builder is pure — no I/O, no clocks —
 * so the same event stream always produces the same string. This
 * keeps it suitable for golden tests + on-chain audit anchoring.
 *
 * Event shape is intentionally minimal so legacy call sites
 * (`game-loop.ts`, `p2p-agent-runner.ts`) can feed straight in
 * without refactoring their internal data model.
 */

import type { Card } from './card-types';
import { cardLabel } from './card-types';

export type AuditEvent =
  | { kind: 'hand-start'; handNumber: number; dealer: string; smallBlind: number; bigBlind: number }
  | { kind: 'deal-hole'; player: string; cards: Card[] }
  | { kind: 'community'; phase: 'flop' | 'turn' | 'river'; cards: Card[] }
  | { kind: 'action'; player: string; action: string; amount?: number; phase: string }
  | { kind: 'pot-update'; pot: number }
  | { kind: 'showdown'; winner: string; description?: string; pot: number }
  | { kind: 'hand-end'; handNumber: number; winner: string; pot: number };

export interface AuditLogOptions {
  /** Include hole cards in the rendered log. Default: false (private). */
  includeHole?: boolean;
  /** Prefix for every line. Default: empty. */
  prefix?: string;
}

/**
 * Render a stream of events as a multi-line audit log. Lines are
 * `\n`-separated; trailing newline is omitted.
 */
export function renderAuditLog(
  events: readonly AuditEvent[],
  opts: AuditLogOptions = {},
): string {
  const prefix = opts.prefix ?? '';
  const lines: string[] = [];
  for (const e of events) {
    lines.push(prefix + renderEvent(e, opts));
  }
  return lines.join('\n');
}

function renderEvent(e: AuditEvent, opts: AuditLogOptions): string {
  switch (e.kind) {
    case 'hand-start':
      return `[hand ${e.handNumber}] start · dealer=${e.dealer} · sb=${e.smallBlind} bb=${e.bigBlind}`;
    case 'deal-hole':
      return opts.includeHole
        ? `  deal ${e.player}: ${e.cards.map(cardLabel).join(' ')}`
        : `  deal ${e.player}: 2 cards`;
    case 'community':
      return `  ${e.phase}: ${e.cards.map(cardLabel).join(' ')}`;
    case 'action': {
      const amt = e.amount === undefined ? '' : ` ${e.amount}`;
      return `  ${e.phase} · ${e.player} → ${e.action}${amt}`;
    }
    case 'pot-update':
      return `  pot=${e.pot}`;
    case 'showdown':
      return e.description
        ? `  showdown · ${e.winner} wins ${e.pot} (${e.description})`
        : `  showdown · ${e.winner} wins ${e.pot}`;
    case 'hand-end':
      return `[hand ${e.handNumber}] end · winner=${e.winner} · pot=${e.pot}`;
  }
}

/**
 * Mutable builder helper for call sites that accumulate events
 * incrementally instead of constructing a full array up-front.
 */
export class AuditLogBuilder {
  private readonly events: AuditEvent[] = [];

  push(event: AuditEvent): this {
    this.events.push(event);
    return this;
  }

  /** Snapshot of events captured so far (defensive copy). */
  snapshot(): AuditEvent[] {
    return [...this.events];
  }

  render(opts?: AuditLogOptions): string {
    return renderAuditLog(this.events, opts);
  }

  clear(): void {
    this.events.length = 0;
  }
}

```
