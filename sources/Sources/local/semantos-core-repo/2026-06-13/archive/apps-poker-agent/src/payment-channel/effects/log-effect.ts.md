---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/log-effect.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.791769+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/log-effect.ts

```ts
/**
 * Log effect — emits a structured log line for every effect command.
 *
 * Subscribes to the entire bus (no filter). Output goes through
 * `loggerPort.info()` with a fixed shape so the lifecycle integration
 * test can pin it against a golden fixture.
 *
 * Each line is `{ tag: 'channel-effect', cmd: <type>, … }` plus the
 * command-specific fields (channelId, txid, label, reason, etc.). Bytes
 * are NEVER inlined — only hashes/txids/labels — so logs stay small.
 */

import { loggerPort, type Logger } from '@semantos/protocol-types/ports';
import type { Dispose } from '@semantos/state';

import { effectBus } from './bus';
import type { EffectCommand } from './types';

export interface LogEffectOptions {
  logger?: Logger;
  /** Test hook fired with the structured payload before logging. */
  onEntry?: (entry: Record<string, unknown>) => void;
}

export interface LogEffect {
  dispose: Dispose;
}

export function makeLogEffect(opts: LogEffectOptions = {}): LogEffect {
  const log = opts.logger ?? safeGetLogger();
  const off = effectBus.on((cmd) => {
    const entry = formatEntry(cmd);
    opts.onEntry?.(entry);
    log.info?.('channel-effect', entry);
  });
  return { dispose: off };
}

function formatEntry(cmd: EffectCommand): Record<string, unknown> {
  switch (cmd.type) {
    case 'persist-artifacts':
      return {
        cmd: cmd.type,
        channelId: cmd.channelId,
        txid: cmd.artifacts.txid,
        envelopeHash: cmd.artifacts.envelopeHash,
        simpleHash: cmd.artifacts.simpleHash,
        vout: cmd.artifacts.vout,
      };
    case 'persist-spv':
      return {
        cmd: cmd.type,
        channelId: cmd.channelId,
        bumpHash: cmd.proof.bumpHash,
        confirmations: cmd.proof.confirmations,
      };
    case 'broadcast':
      return {
        cmd: cmd.type,
        channelId: cmd.channelId,
        label: cmd.label,
        rawTxBytes: Math.floor(cmd.rawTx.length / 2),
      };
    case 'await-spv':
      return {
        cmd: cmd.type,
        channelId: cmd.channelId,
        txid: cmd.txid,
        minConfirmations: cmd.minConfirmations,
      };
    case 'fee-credit':
      return {
        cmd: cmd.type,
        channelId: cmd.channelId,
        reason: cmd.reason,
        sats: cmd.sats,
      };
    case 'mark-state':
      return {
        cmd: cmd.type,
        channelId: cmd.channelId,
        state: cmd.state,
      };
    case 'emit-event':
      return {
        cmd: cmd.type,
        channelId: cmd.channelId,
        event: cmd.event.type,
      };
  }
}

function safeGetLogger(): Logger {
  if (loggerPort.isBound()) return loggerPort.get();
  return { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} };
}

```
