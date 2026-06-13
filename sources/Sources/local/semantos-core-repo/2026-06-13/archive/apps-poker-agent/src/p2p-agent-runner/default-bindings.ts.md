---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/default-bindings.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.788707+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/default-bindings.ts

```ts
/**
 * Default boot wiring — binds `transportPort` to the real
 * `PokerMessageTransport` factory.
 *
 * Idempotent. Tests bind their own factory via `transportPort.bind`
 * before constructing the facade, in which case this is a no-op.
 */

import type { WalletClient } from '../../../../core/protocol-types/src/wallet-client';

import { PokerMessageTransport } from '../poker-message-transport';

import {
  transportPort,
  type Transport,
  type TransportFactory,
} from './transport-port';

export interface DefaultTransportBindingOptions {
  wallet: WalletClient;
}

/** Bind the production MessageBox transport factory. Idempotent. */
export function bindDefaultP2PTransport(opts: DefaultTransportBindingOptions): void {
  if (transportPort.isBound()) return;
  const factory: TransportFactory = ({ gameId, opponentIdentityKey, verbose }): Transport => {
    return new PokerMessageTransport(opts.wallet, {
      gameId,
      opponentIdentityKey,
      verbose: verbose ?? false,
    });
  };
  transportPort.bind(factory);
}

```
