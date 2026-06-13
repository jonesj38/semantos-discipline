---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/ports/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.795220+00:00
---

# archive/apps-poker-agent/src/payment-channel/ports/index.ts

```ts
/**
 * Payment-channel port surface.
 *
 * Re-exports the cross-package ports from `@semantos/protocol-types`
 * and adds poker-specific ports (channelIdGeneratorPort).
 */

import { port, type Port } from '@semantos/state';

export {
  walletPort,
  createWalletPort,
  utxoProviderPort,
  broadcasterPort,
  signerPort,
  spvPort,
  loggerPort,
  consoleLogger,
  silentLogger,
  getLogger,
  type WalletPortClient,
  type WalletRole,
  type Utxo,
  type UtxoProvider,
  type UtxoWatchCallback,
  type Dispose,
  type Broadcaster,
  type BroadcastResult,
  type Signer,
  type Signature,
  type SpvVerifier,
  type Logger,
} from '@semantos/protocol-types/ports';

/** Generate a fresh channel id. Stubbed in tests for determinism. */
export interface ChannelIdGenerator {
  next(): string;
}

export const channelIdGeneratorPort: Port<ChannelIdGenerator> = port<ChannelIdGenerator>(
  'poker-channel-id-generator',
);

export function getChannelIdGenerator(): ChannelIdGenerator | null {
  return channelIdGeneratorPort.isBound() ? channelIdGeneratorPort.get() : null;
}

```
