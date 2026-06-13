---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/ports/utxo-provider-port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.901270+00:00
---

# core/protocol-types/src/ports/utxo-provider-port.ts

```ts
/**
 * UTXO provider port — exposes the minimum surface payment-channel
 * callers need to discover and watch funding UTXOs without coupling
 * to a specific tx index or wallet implementation.
 */

import { port, type Port } from '@semantos/state';

export interface Utxo {
  txid: string;
  vout: number;
  satoshis: number;
  lockingScriptHex: string;
}

export type UtxoWatchCallback = (utxos: Utxo[]) => void;

export type Dispose = () => void;

export interface UtxoProvider {
  /** List unspent outputs for a given Bitcoin address. */
  listUtxos(address: string): Promise<Utxo[]>;
  /**
   * Subscribe to UTXO-set changes for an address. Implementations may
   * batch deliveries; the callback fires with the current set.
   * Returns a `Dispose` to unsubscribe.
   */
  watch(address: string, cb: UtxoWatchCallback): Dispose;
}

export const utxoProviderPort: Port<UtxoProvider> = port<UtxoProvider>('utxo-provider');

```
