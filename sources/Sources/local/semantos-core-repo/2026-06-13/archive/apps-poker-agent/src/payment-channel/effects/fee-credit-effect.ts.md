---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/fee-credit-effect.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.791208+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/fee-credit-effect.ts

```ts
/**
 * Fee-credit effect — accumulates 1-sat UTXOs per the CashLanes
 * fee-credits accounting rule.
 *
 * Subscribes to `fee-credit`. Maintains an in-memory ledger keyed by
 * `(channelId, reason)`. The ledger is observable via `getLedger()` so
 * tests + dashboards can assert on it without poking at the bus.
 *
 * The CashLanes spec credits 1 sat per:
 *   - funding open (reason='funding')
 *   - each recorded tick (reason='tick')
 *   - settlement close (reason='settlement')
 *
 * The actual UTXO building lives downstream; this effect is just the
 * accounting layer.
 */

import { loggerPort, type Logger } from '@semantos/protocol-types/ports';
import type { Dispose } from '@semantos/state';

import { subscribeEffect } from './bus';
import type { FeeCreditCommand } from './types';

export interface FeeCreditLedgerEntry {
  channelId: string;
  reason: FeeCreditCommand['reason'];
  sats: number;
}

export interface FeeCreditEffect {
  dispose: Dispose;
  /** Total accumulated sats across all channels + reasons. */
  total(): number;
  /** Sats accumulated for a specific channel. */
  totalForChannel(channelId: string): number;
  /** Flat list of every credit accepted, in arrival order. */
  ledger(): readonly FeeCreditLedgerEntry[];
}

export interface FeeCreditEffectOptions {
  logger?: Logger;
}

export function makeFeeCreditEffect(opts: FeeCreditEffectOptions = {}): FeeCreditEffect {
  const log = opts.logger ?? safeGetLogger();
  const ledger: FeeCreditLedgerEntry[] = [];

  const off = subscribeEffect('fee-credit', (cmd) => {
    if (!Number.isInteger(cmd.sats) || cmd.sats <= 0) {
      log.warn?.('fee-credit ignored — non-positive sats', {
        channelId: cmd.channelId,
        sats: cmd.sats,
      });
      return;
    }
    ledger.push({ channelId: cmd.channelId, reason: cmd.reason, sats: cmd.sats });
    log.debug?.('fee-credit', {
      channelId: cmd.channelId,
      reason: cmd.reason,
      sats: cmd.sats,
    });
  });

  return {
    dispose: off,
    total: () => ledger.reduce((acc, e) => acc + e.sats, 0),
    totalForChannel: (channelId) =>
      ledger.filter((e) => e.channelId === channelId).reduce((acc, e) => acc + e.sats, 0),
    ledger: () => ledger,
  };
}

function safeGetLogger(): Logger {
  if (loggerPort.isBound()) return loggerPort.get();
  return { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} };
}

```
