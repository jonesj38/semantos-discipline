---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/transport-port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.785236+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/transport-port.ts

```ts
/**
 * Transport port — abstracts the BRC-103 MessageBox channel the
 * P2P agents use to exchange moves + control messages.
 *
 * Per the prompt-20 acceptance criterion: "Transport is a port
 * (`transportPort`)." Production binds `PokerMessageTransport`;
 * tests bind an in-memory double.
 *
 * Per-game scope: distinct games hold distinct transport instances
 * (two MessageBox channels each), so the port is really a factory.
 * The runtime binds a factory that returns a transport per gameId.
 */

import { port, type Port } from '@semantos/state';

import type {
  PokerControlMessage,
  PokerMoveMessage,
} from '../poker-message-transport';

export type OnMoveCallback = (move: PokerMoveMessage) => void | Promise<void>;
export type OnControlCallback = (
  msg: PokerControlMessage,
) => void | Promise<void>;

export interface Transport {
  init(): Promise<void>;
  sendMove(move: PokerMoveMessage): Promise<void>;
  sendControl(type: string, payload: Record<string, unknown>): Promise<void>;
  startListening(onMove: OnMoveCallback, onControl: OnControlCallback): Promise<void>;
  stopListening(): Promise<void>;
  drainPending(): Promise<void>;
}

export interface TransportFactoryArgs {
  gameId: string;
  opponentIdentityKey: string;
  verbose?: boolean;
}

export type TransportFactory = (args: TransportFactoryArgs) => Transport;

export const transportPort: Port<TransportFactory> = port<TransportFactory>(
  'p2p-poker-transport',
);

export type { PokerControlMessage, PokerMoveMessage };

```
