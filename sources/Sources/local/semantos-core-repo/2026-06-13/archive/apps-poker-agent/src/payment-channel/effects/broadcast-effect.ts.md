---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/broadcast-effect.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.792339+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/broadcast-effect.ts

```ts
/**
 * Broadcast effect — pumps `BroadcastCommand`s through `broadcasterPort`.
 *
 * The reducer never broadcasts (it's pure); the facade emits a
 * `BroadcastCommand` when it has a frozen rawTx ready to push out
 * (funding, settlement, close). This effect handles network errors and
 * surfaces them through the logger port — failures DO NOT throw out of
 * the bus subscriber, since other effects (persist, log) must still see
 * the command.
 */

import {
  broadcasterPort,
  loggerPort,
  type BroadcastResult,
  type Logger,
} from '@semantos/protocol-types/ports';
import type { Dispose } from '@semantos/state';

import { subscribeEffect } from './bus';

export interface BroadcastEffectOptions {
  logger?: Logger;
  /** Optional callback so tests can observe the result. */
  onResult?: (channelId: string, label: string, result: BroadcastResult) => void;
}

export interface BroadcastEffect {
  dispose: Dispose;
}

export function makeBroadcastEffect(opts: BroadcastEffectOptions = {}): BroadcastEffect {
  const log = opts.logger ?? safeGetLogger();

  const off = subscribeEffect('broadcast', (cmd) => {
    void runBroadcast(log, opts.onResult, cmd.channelId, cmd.label, cmd.rawTx);
  });

  return { dispose: off };
}

async function runBroadcast(
  log: Logger,
  onResult: BroadcastEffectOptions['onResult'],
  channelId: string,
  label: string,
  rawTx: string,
): Promise<void> {
  if (!broadcasterPort.isBound()) {
    log.error?.('broadcast skipped — broadcasterPort unbound', { channelId, label });
    return;
  }
  try {
    const result = await broadcasterPort.get().broadcast(rawTx);
    if (!result.ok) {
      log.error?.('broadcast failed', {
        channelId,
        label,
        error: result.error ?? result.status ?? 'unknown',
      });
    } else {
      log.info?.('broadcast ok', { channelId, label, txid: result.txid });
    }
    onResult?.(channelId, label, result);
  } catch (err) {
    log.error?.('broadcast threw', { channelId, label, err: String(err) });
  }
}

function safeGetLogger(): Logger {
  if (loggerPort.isBound()) return loggerPort.get();
  return { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} };
}

```
