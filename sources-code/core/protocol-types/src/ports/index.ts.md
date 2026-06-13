---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/ports/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.901544+00:00
---

# core/protocol-types/src/ports/index.ts

```ts
/**
 * Cross-package ports barrel — payment-channel + every other package
 * imports the port symbols + interfaces from here.
 */

export {
  walletPort,
  createWalletPort,
  type WalletPortClient,
  type WalletRole,
} from './wallet-port';
export {
  utxoProviderPort,
  type Utxo,
  type UtxoProvider,
  type UtxoWatchCallback,
  type Dispose,
} from './utxo-provider-port';
export {
  broadcasterPort,
  type Broadcaster,
  type BroadcastResult,
} from './broadcaster-port';
export {
  signerPort,
  type Signer,
  type Signature,
} from './signer-port';
export {
  spvPort,
  type SpvVerifier,
} from './spv-port';
export {
  loggerPort,
  consoleLogger,
  silentLogger,
  getLogger,
  type Logger,
} from './logger-port';

```
