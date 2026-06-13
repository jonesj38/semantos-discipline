---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/ports/default-bindings.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.795837+00:00
---

# archive/apps-poker-agent/src/payment-channel/ports/default-bindings.ts

```ts
/**
 * Default boot wiring — binds production implementations of every
 * payment-channel port. Called once at app boot; idempotent.
 *
 * Each binding is opt-in: callers pass in the concrete dependencies
 * they want to wire (ARC URL, wallet client, etc.). Anything left
 * out stays unbound, in which case ports report unbound errors at
 * the call site so callers know to provide a stub.
 */

import { makeArcBroadcaster } from '../../broadcasters/arc-broadcaster';

import {
  broadcasterPort,
  channelIdGeneratorPort,
  consoleLogger,
  createWalletPort,
  loggerPort,
  walletPort,
  type ChannelIdGenerator,
  type Logger,
  type WalletPortClient,
  type WalletRole,
} from './index';

export { makeArcBroadcaster };

export interface DefaultBindingsOptions {
  /** ARC endpoint to broadcast through. Default: GorillaPool. */
  arcUrl?: string;
  /**
   * Wallet client(s). Pass a single client to bind the role-agnostic
   * `walletPort`, or an object to bind both role-scoped ports.
   */
  wallet?:
    | WalletPortClient
    | { provider: WalletPortClient; consumer: WalletPortClient };
  /** Channel ID generator. Production typically uses a UUID. */
  channelIdGenerator?: ChannelIdGenerator;
  /** Logger. Defaults to a console-backed logger. */
  logger?: Logger;
}

/** Bind the production defaults. Idempotent. */
export function bindDefaultPaymentChannelPorts(
  opts: DefaultBindingsOptions = {},
): void {
  if (!broadcasterPort.isBound()) {
    broadcasterPort.bind(makeArcBroadcaster(opts.arcUrl));
  }
  if (opts.wallet) {
    if ('provider' in opts.wallet && 'consumer' in opts.wallet) {
      const providerPort = createWalletPort('provider' as WalletRole);
      const consumerPort = createWalletPort('consumer' as WalletRole);
      if (!providerPort.isBound()) providerPort.bind(opts.wallet.provider);
      if (!consumerPort.isBound()) consumerPort.bind(opts.wallet.consumer);
    } else if (!walletPort.isBound()) {
      walletPort.bind(opts.wallet as WalletPortClient);
    }
  }
  if (opts.channelIdGenerator && !channelIdGeneratorPort.isBound()) {
    channelIdGeneratorPort.bind(opts.channelIdGenerator);
  }
  if (!loggerPort.isBound()) {
    loggerPort.bind(opts.logger ?? consoleLogger);
  }
}

```
