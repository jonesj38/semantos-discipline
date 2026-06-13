---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/spv-effect.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.790329+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/spv-effect.ts

```ts
/**
 * SPV effect — polls `spvPort` until the requested txid reaches the
 * required confirmation depth.
 *
 * Subscribes to `await-spv`. On success it pushes nothing back through
 * the bus (the facade is responsible for dispatching the `attach-spv`
 * reducer event after this resolves) — instead it returns a Promise via
 * the optional `onResolved` callback so the facade can chain on it.
 *
 * Polling cadence is configurable; defaults are the smallest values
 * that keep tests fast. `verifyBeef` / `verifyBump` semantics are left
 * to the bound `SpvVerifier` impl.
 */

import {
  loggerPort,
  spvPort,
  type Logger,
  type SpvVerifier,
} from '@semantos/protocol-types/ports';
import type { Dispose } from '@semantos/state';

import { subscribeEffect } from './bus';
import type { AwaitSpvCommand } from './types';

export interface SpvEffectOptions {
  /** ms between polls when proof not yet available. Default: 50. */
  pollMs?: number;
  /** Max polls before timing out. Default: 20. */
  maxPolls?: number;
  /** Optional source of pre-fetched proofs keyed by txid (test helper). */
  proofSource?: (txid: string) => Promise<{ beef: string; depth: number } | null>;
  logger?: Logger;
  /** Test hook fired after each await-spv resolves or times out. */
  onResolved?: (cmd: AwaitSpvCommand, ok: boolean) => void;
}

export interface SpvEffect {
  dispose: Dispose;
}

export function makeSpvEffect(opts: SpvEffectOptions = {}): SpvEffect {
  const log = opts.logger ?? safeGetLogger();
  const pollMs = opts.pollMs ?? 50;
  const maxPolls = opts.maxPolls ?? 20;

  const off = subscribeEffect('await-spv', (cmd) => {
    void awaitSpv(cmd, opts, log, pollMs, maxPolls);
  });
  return { dispose: off };
}

async function awaitSpv(
  cmd: AwaitSpvCommand,
  opts: SpvEffectOptions,
  log: Logger,
  pollMs: number,
  maxPolls: number,
): Promise<void> {
  const verifier = spvPort.isBound() ? spvPort.get() : null;
  if (!verifier && !opts.proofSource) {
    log.warn?.('await-spv skipped — spvPort unbound', { channelId: cmd.channelId });
    opts.onResolved?.(cmd, false);
    return;
  }

  for (let i = 0; i < maxPolls; i++) {
    try {
      const ok = await tryVerify(verifier, opts.proofSource, cmd.txid, cmd.minConfirmations);
      if (ok) {
        log.info?.('await-spv confirmed', { channelId: cmd.channelId, txid: cmd.txid });
        opts.onResolved?.(cmd, true);
        return;
      }
    } catch (err) {
      log.warn?.('await-spv attempt errored', {
        channelId: cmd.channelId,
        txid: cmd.txid,
        attempt: i,
        err: String(err),
      });
    }
    if (i < maxPolls - 1) await sleep(pollMs);
  }
  log.error?.('await-spv timed out', {
    channelId: cmd.channelId,
    txid: cmd.txid,
    polls: maxPolls,
  });
  opts.onResolved?.(cmd, false);
}

async function tryVerify(
  verifier: SpvVerifier | null,
  proofSource: SpvEffectOptions['proofSource'],
  txid: string,
  minConfirmations: number,
): Promise<boolean> {
  if (proofSource) {
    const proof = await proofSource(txid);
    if (!proof) return false;
    if (proof.depth < minConfirmations) return false;
    if (verifier) return verifier.verifyBeef(proof.beef, txid);
    return true;
  }
  // No proof source — assume the verifier itself can answer.
  if (!verifier) return false;
  return verifier.verifyBeef('', txid);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function safeGetLogger(): Logger {
  if (loggerPort.isBound()) return loggerPort.get();
  return { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} };
}

```
