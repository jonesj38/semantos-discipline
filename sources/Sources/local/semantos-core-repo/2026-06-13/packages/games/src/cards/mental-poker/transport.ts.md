---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/mental-poker/transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.434865+00:00
---

# packages/games/src/cards/mental-poker/transport.ts

```ts
/**
 * PokerTableTransport — shard multicast transport for trustless poker.
 *
 * Maps each poker table to a shard multicast group. Protocol steps
 * (shuffle proofs, decryption proofs, betting actions, community reveals,
 * key reveals) are packed into CellToken transactions and published via
 * ShardProxyClient UDP. Other players receive them via ShardSubscriptionManager.
 *
 * Wire format per message:
 *   1. Serialize protocol step to JSON
 *   2. Pack JSON into a valid 1024-byte cell (256-byte header + 768-byte payload)
 *   3. Wrap cell in a CellToken PushDrop output script
 *   4. Create a BSV transaction containing that output
 *   5. Encode as BRC-12 frame and publish via UDP
 *
 * Semantic path routing: `poker/{tableId}/{messageType}/{sequence}`
 *
 * Cross-references:
 *   protocol-types/src/overlay/shard-proxy-client.ts  → ShardProxyClient
 *   protocol-types/src/overlay/shard-subscription-manager.ts → ShardSubscriptionManager
 *   protocol-types/src/cell-token.ts → CellToken (BRC-48 PushDrop)
 *   protocol-types/src/cell-header.ts → serializeCellHeader
 */

import { createHash } from 'crypto';

import {
  ShardProxyClient,
  type ShardProxyConfig,
  type PublishResult,
  ShardSubscriptionManager,
  type ShardSubscriptionConfig,
  CellToken,
  serializeCellHeader,
  type CellHeader,
  CELL_SIZE,
  HEADER_SIZE,
  PAYLOAD_SIZE,
  HeaderOffsets,
  Linearity,
  MAGIC_1,
  MAGIC_2,
  MAGIC_3,
  MAGIC_4,
} from '@semantos/protocol-types';

import { Transaction, PublicKey, PrivateKey } from '@bsv/sdk';

import type {
  ShuffleProof,
  DecryptionProof,
  KeyRevealProof,
  VerificationResult,
} from './types';

// ── Message Types ─────────────────────────────────────────

export type PokerMessageType =
  | 'key-registration'
  | 'shuffle'
  | 'decryption'
  | 'action'
  | 'community-reveal'
  | 'key-reveal'
  | 'verification';

export interface PokerMessage {
  type: PokerMessageType;
  tableId: string;
  playerId: string;
  sequence: number;
  timestamp: number;
  handNumber: number;
  payload: Record<string, unknown>;
}

export interface KeyRegistrationPayload {
  keyCommitment: string;
}

export interface ShufflePayload {
  inputCommitment: string;
  outputCommitment: string;
}

export interface DecryptionPayload {
  cardPosition: number;
  encryptedBefore: string;
  decryptedAfter: string;
  commitment: string;
}

export interface ActionPayload {
  action: string;
  amount?: number;
}

export interface CommunityRevealPayload {
  phase: string;
  cards: { suit: string; rank: number }[];
}

export interface KeyRevealPayload {
  encryptKey: string;
  keyCommitment: string;
}

export interface VerificationPayload {
  valid: boolean;
  errors: string[];
  stepsVerified: number;
}

// ── Transport Config ──────────────────────────────────────

export interface PokerTransportConfig {
  tableId: string;
  playerId: string;
  /** ShardProxyClient config for publishing. */
  proxy: ShardProxyConfig;
  /** ShardSubscriptionManager config for receiving. */
  subscription: Omit<ShardSubscriptionConfig, 'onCellToken'>;
  /** Owner key pair for signing CellToken transactions. */
  ownerKey: PrivateKey;
}

// ── Transport ─────────────────────────────────────────────

export class PokerTableTransport {
  private publisher: ShardProxyClient;
  private subscriber: ShardSubscriptionManager;
  private tableId: string;
  private playerId: string;
  private ownerKey: PrivateKey;
  private ownerPubKey: PublicKey;
  private sequence = 0;
  private handlers: Map<PokerMessageType, ((msg: PokerMessage) => Promise<void>)[]> = new Map();
  private running = false;

  private constructor(
    publisher: ShardProxyClient,
    subscriber: ShardSubscriptionManager,
    tableId: string,
    playerId: string,
    ownerKey: PrivateKey,
  ) {
    this.publisher = publisher;
    this.subscriber = subscriber;
    this.tableId = tableId;
    this.playerId = playerId;
    this.ownerKey = ownerKey;
    this.ownerPubKey = ownerKey.toPublicKey();
  }

  /**
   * Create a transport for a poker table.
   *
   * Sets up ShardProxyClient for publishing and ShardSubscriptionManager
   * for receiving. The subscriber filters incoming cell-tokens by the
   * table's semantic path prefix.
   */
  static create(config: PokerTransportConfig): PokerTableTransport {
    const publisher = new ShardProxyClient(config.proxy);

    const subscriber = new ShardSubscriptionManager({
      ...config.subscription,
      onCellToken: async () => {
        // Will be replaced after construction
      },
    });

    const transport = new PokerTableTransport(
      publisher,
      subscriber,
      config.tableId,
      config.playerId,
      config.ownerKey,
    );

    // Wire up the subscriber callback
    (transport as any).subscriber = new ShardSubscriptionManager({
      ...config.subscription,
      onCellToken: async (result) => {
        await transport.handleIncoming(result);
      },
    });

    return transport;
  }

  /**
   * Start listening for incoming messages.
   */
  async start(): Promise<void> {
    if (this.running) return;
    await this.subscriber.start();
    this.running = true;
  }

  /**
   * Stop the transport and release resources.
   */
  async stop(): Promise<void> {
    if (!this.running) return;
    await this.subscriber.stop();
    this.publisher.close();
    this.running = false;
  }

  // ── Publishing ────────────────────────────────────────────

  /**
   * Publish a key registration to the table.
   */
  async publishKeyRegistration(
    keyCommitment: string,
    handNumber: number,
  ): Promise<PublishResult> {
    return this.publish('key-registration', handNumber, { keyCommitment });
  }

  /**
   * Publish a shuffle proof to the table.
   */
  async publishShuffle(
    proof: ShuffleProof,
    handNumber: number,
  ): Promise<PublishResult> {
    return this.publish('shuffle', handNumber, {
      inputCommitment: proof.inputCommitment,
      outputCommitment: proof.outputCommitment,
    });
  }

  /**
   * Publish a decryption proof (during card dealing).
   */
  async publishDecryption(
    proof: DecryptionProof,
    handNumber: number,
  ): Promise<PublishResult> {
    return this.publish('decryption', handNumber, {
      cardPosition: proof.cardPosition,
      encryptedBefore: proof.encryptedBefore,
      decryptedAfter: proof.decryptedAfter,
      commitment: proof.commitment,
    });
  }

  /**
   * Publish a betting action.
   */
  async publishAction(
    action: string,
    handNumber: number,
    amount?: number,
  ): Promise<PublishResult> {
    return this.publish('action', handNumber, { action, amount });
  }

  /**
   * Publish community card reveal.
   */
  async publishCommunityReveal(
    phase: string,
    cards: { suit: string; rank: number }[],
    handNumber: number,
  ): Promise<PublishResult> {
    return this.publish('community-reveal', handNumber, { phase, cards });
  }

  /**
   * Publish key reveal for showdown verification.
   */
  async publishKeyReveal(
    proof: KeyRevealProof,
    handNumber: number,
  ): Promise<PublishResult> {
    return this.publish('key-reveal', handNumber, {
      encryptKey: proof.encryptKey,
      keyCommitment: proof.keyCommitment,
    });
  }

  /**
   * Publish verification result.
   */
  async publishVerification(
    result: VerificationResult,
    handNumber: number,
  ): Promise<PublishResult> {
    return this.publish('verification', handNumber, {
      valid: result.valid,
      errors: result.errors,
      stepsVerified: result.stepsVerified,
    });
  }

  // ── Subscription ──────────────────────────────────────────

  /**
   * Register a handler for a specific message type.
   * Multiple handlers can be registered per type.
   */
  on(type: PokerMessageType, handler: (msg: PokerMessage) => Promise<void>): void {
    const existing = this.handlers.get(type) ?? [];
    existing.push(handler);
    this.handlers.set(type, existing);
  }

  /**
   * Register a handler for all message types.
   */
  onAny(handler: (msg: PokerMessage) => Promise<void>): void {
    const types: PokerMessageType[] = [
      'key-registration', 'shuffle', 'decryption',
      'action', 'community-reveal', 'key-reveal', 'verification',
    ];
    for (const t of types) {
      this.on(t, handler);
    }
  }

  /**
   * Get transport metrics from the subscription manager.
   */
  getMetrics() {
    return this.subscriber.getMetrics();
  }

  // ── Internal: Pack & Publish ──────────────────────────────

  private async publish(
    type: PokerMessageType,
    handNumber: number,
    payload: Record<string, unknown>,
  ): Promise<PublishResult> {
    const seq = this.sequence++;
    const message: PokerMessage = {
      type,
      tableId: this.tableId,
      playerId: this.playerId,
      sequence: seq,
      timestamp: Date.now(),
      handNumber,
      payload,
    };

    const semanticPath = `poker/${this.tableId}/${type}/${seq}`;
    const cellBytes = packMessageIntoCell(message);
    const contentHash = sha256Bytes(cellBytes);

    const lockingScript = CellToken.createOutputScript(
      cellBytes,
      semanticPath,
      contentHash,
      this.ownerPubKey,
    );

    const tx = new Transaction();
    tx.addOutput({ lockingScript, satoshis: 0 });

    return this.publisher.publish(tx);
  }

  // ── Internal: Receive & Dispatch ──────────────────────────

  private async handleIncoming(result: {
    txid: string;
    shardIndex: number;
    cellBytes: Uint8Array;
    semanticPath: string;
    contentHash: Uint8Array;
    ownerPubKey: Uint8Array;
  }): Promise<void> {
    // Filter by table prefix
    const prefix = `poker/${this.tableId}/`;
    if (!result.semanticPath.startsWith(prefix)) return;

    // Extract message from cell payload
    const message = unpackMessageFromCell(result.cellBytes);
    if (!message) return;

    // Skip own messages
    if (message.playerId === this.playerId) return;

    // Dispatch to handlers
    const handlers = this.handlers.get(message.type) ?? [];
    for (const handler of handlers) {
      await handler(message);
    }
  }
}

// ── Cell Packing ────────────────────────────────────────────

/** Type hash for poker protocol messages. */
const POKER_TYPE_HASH = new Uint8Array(32);
POKER_TYPE_HASH.set(
  new TextEncoder().encode('semantos.poker.protocol'),
  0,
);

/** Owner ID for poker protocol cells (shared table identity). */
const POKER_OWNER_ID = new Uint8Array(16);
POKER_OWNER_ID[0] = 0x90; // Distinguished prefix

/**
 * Pack a PokerMessage into a valid 1024-byte cell.
 *
 * Header (256 bytes): valid Semantos cell header with magic bytes,
 *   RELEVANT linearity, poker type hash.
 * Payload (768 bytes): JSON-encoded message, zero-padded.
 */
function packMessageIntoCell(message: PokerMessage): Uint8Array {
  const json = JSON.stringify(message);
  const jsonBytes = new TextEncoder().encode(json);

  if (jsonBytes.length > PAYLOAD_SIZE) {
    throw new Error(
      `Poker message too large: ${jsonBytes.length} bytes, max ${PAYLOAD_SIZE}`
    );
  }

  // Build cell header
  const header: CellHeader = {
    magic: new Uint8Array([
      ...le32(MAGIC_1), ...le32(MAGIC_2), ...le32(MAGIC_3), ...le32(MAGIC_4),
    ]),
    linearity: Linearity.RELEVANT,
    version: 1,
    flags: 0,
    refCount: 0,
    typeHash: POKER_TYPE_HASH,
    ownerId: POKER_OWNER_ID,
    timestamp: BigInt(message.timestamp),
    cellCount: 1,
    totalSize: jsonBytes.length,
    phase: 0,
    dimension: 0,
    parentHash: new Uint8Array(32),
    prevStateHash: new Uint8Array(32),
  };

  const headerBytes = serializeCellHeader(header);

  // Assemble full cell
  const cell = new Uint8Array(CELL_SIZE);
  cell.set(headerBytes, 0);
  cell.set(jsonBytes, HEADER_SIZE);
  // Remaining payload bytes are already zero

  return cell;
}

/**
 * Unpack a PokerMessage from a 1024-byte cell.
 * Returns null if the cell doesn't contain a valid poker message.
 */
function unpackMessageFromCell(cellBytes: Uint8Array): PokerMessage | null {
  if (cellBytes.length !== CELL_SIZE) return null;

  try {
    // Read totalSize from header to know JSON length
    const dv = new DataView(cellBytes.buffer, cellBytes.byteOffset, cellBytes.byteLength);
    const payloadLen = dv.getUint32(HeaderOffsets.payloadTotal, true);

    if (payloadLen === 0 || payloadLen > PAYLOAD_SIZE) return null;

    const jsonBytes = cellBytes.subarray(HEADER_SIZE, HEADER_SIZE + payloadLen);
    const json = new TextDecoder().decode(jsonBytes);
    const message = JSON.parse(json) as PokerMessage;

    // Basic validation
    if (!message.type || !message.tableId || !message.playerId) return null;

    return message;
  } catch {
    return null;
  }
}

// ── Helpers ─────────────────────────────────────────────────

function sha256Bytes(data: Uint8Array): Uint8Array {
  return new Uint8Array(createHash('sha256').update(data).digest());
}

function le32(n: number): Uint8Array {
  const buf = new Uint8Array(4);
  const dv = new DataView(buf.buffer);
  dv.setUint32(0, n, true);
  return buf;
}

```
