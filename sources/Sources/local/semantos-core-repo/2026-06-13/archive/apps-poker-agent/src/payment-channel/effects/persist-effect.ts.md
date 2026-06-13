---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/persist-effect.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.790635+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/persist-effect.ts

```ts
/**
 * Persist effect — durable storage for funding artifacts + SPV proofs.
 *
 * Subscribes to:
 *   - `persist-artifacts` (emitted by reducer on FUND)
 *   - `persist-spv`       (emitted on attach-spv + settle-begin)
 *
 * Enforces the byte-freeze guardrail from `CLAUDE.md` §"Payment-channel
 * invariants": once `persist-artifacts` is written for a channel, any
 * follow-up persist with different bytes is rejected. This catches
 * accidental re-funding races at the IO boundary even if the reducer
 * (which has its own guard) is bypassed.
 */

import { loggerPort, type Logger } from '@semantos/protocol-types/ports';
import type { Dispose } from '@semantos/state';

import type { ChannelArtifacts, SpvProof } from '../fsm';
import { subscribeEffect } from './bus';

export interface PersistStore {
  putArtifacts(channelId: string, artifacts: ChannelArtifacts): Promise<void>;
  putSpv(channelId: string, proof: SpvProof): Promise<void>;
  getArtifacts(channelId: string): Promise<ChannelArtifacts | null>;
}

export interface PersistEffectOptions {
  store: PersistStore;
  logger?: Logger;
}

export interface PersistEffect {
  /** Tear down both subscriptions. */
  dispose: Dispose;
}

export function makePersistEffect(opts: PersistEffectOptions): PersistEffect {
  const { store } = opts;
  const log = opts.logger ?? safeGetLogger();

  const offArtifacts = subscribeEffect('persist-artifacts', (cmd) => {
    void persistArtifacts(store, log, cmd.channelId, cmd.artifacts);
  });
  const offSpv = subscribeEffect('persist-spv', (cmd) => {
    void store.putSpv(cmd.channelId, cmd.proof).catch((err: unknown) => {
      log.error?.('persist-spv failed', { channelId: cmd.channelId, err: String(err) });
    });
  });

  return {
    dispose: () => {
      offArtifacts();
      offSpv();
    },
  };
}

async function persistArtifacts(
  store: PersistStore,
  log: Logger,
  channelId: string,
  artifacts: ChannelArtifacts,
): Promise<void> {
  try {
    const existing = await store.getArtifacts(channelId);
    if (existing) {
      // Byte-freeze check — invariant 1.
      if (
        existing.envelopeHex !== artifacts.envelopeHex ||
        existing.simpleRawTx !== artifacts.simpleRawTx
      ) {
        log.error?.('persist-artifacts byte-freeze violated', {
          channelId,
          existingTxid: existing.txid,
          incomingTxid: artifacts.txid,
        });
        return;
      }
      // Idempotent — same bytes, drop.
      return;
    }
    await store.putArtifacts(channelId, artifacts);
  } catch (err) {
    log.error?.('persist-artifacts failed', {
      channelId,
      err: String(err),
    });
  }
}

function safeGetLogger(): Logger {
  if (loggerPort.isBound()) return loggerPort.get();
  // Fallback no-op so a test that forgot to bind still runs.
  return { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} };
}

```
