---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/audit-log-renderer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.789902+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/audit-log-renderer.ts

```ts
/**
 * Pure renderer for the P2P runner's on-chain transaction audit log.
 *
 * Extracted from `printAuditLog()` so the output can be tested
 * against a golden fixture and called from non-CLI consumers
 * (the arena dashboard, the JSON API).
 */

import type { AuditLogEntry, P2PHandResult } from './types';

export interface RenderAuditOptions {
  /** ANSI colour mode. Default: true. Tests pass `false` for plain. */
  ansi?: boolean;
}

export function renderAuditLog(
  myName: string,
  handResults: readonly P2PHandResult[],
  txids: readonly AuditLogEntry[],
  opts: RenderAuditOptions = {},
): string {
  const ansi = opts.ansi ?? true;
  const cyan = (s: string) => (ansi ? `\x1b[36m${s}\x1b[0m` : s);
  const green = (s: string) => (ansi ? `\x1b[32m${s}\x1b[0m` : s);
  const yellow = (s: string) => (ansi ? `\x1b[33m${s}\x1b[0m` : s);

  const out: string[] = [];
  out.push('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  out.push(`  ${myName} — On-Chain Transaction Audit Log`);
  out.push('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  out.push('');

  let currentHand = 0;
  let txNum = 0;
  for (const entry of txids) {
    if (entry.hand !== currentHand) {
      currentHand = entry.hand;
      const result = handResults.find((r) => r.handNumber === currentHand);
      out.push(
        `${cyan(`── Hand #${currentHand} ──`)}  Winner: ${result?.winner ?? '?'} | Pot: ${result?.potSize ?? '?'}`,
      );
    }
    txNum++;
    const colorize = entry.type === 'CellToken' ? green : yellow;
    out.push(`  ${colorize(`${String(txNum).padStart(3)}. [${entry.type}]`)} ${entry.txid}`);
    if (entry.type === 'CellToken') {
      out.push(`       https://whatsonchain.com/tx/${entry.txid}`);
    }
    out.push(`       ${entry.detail}`);
  }
  out.push('');
  out.push(cyan(`Total: ${txNum} transactions on BSV mainnet`));
  out.push('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  return out.join('\n');
}

```
