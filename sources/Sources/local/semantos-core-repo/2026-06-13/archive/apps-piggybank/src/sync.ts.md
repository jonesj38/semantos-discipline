---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-piggybank/src/sync.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.720026+00:00
---

# archive/apps-piggybank/src/sync.ts

```ts
/**
 * Sync Protocol
 *
 * Defines the messages exchanged between piggy bank devices (ESP32)
 * and the parent app (Flutter web / iPad / phone).
 *
 * Transport-agnostic: the same payloads work over WiFi (REST/WebSocket),
 * BLE GATT, ESP-NOW, or USB serial. Each transport just frames and
 * delivers these JSON messages.
 *
 * Both sides sign their sync payloads. Both sides verify. If the link
 * drops for a week, everything queues up and reconciles on next connect.
 * No data loss, no conflicts — linear types guarantee single consumption.
 */

import type { ChoreClaim, ChoreTemplate, BonusQuest, SavingsGoal } from './chores.js';
import type { DeviceConfig, HeaderChainState } from './device.js';

// ── Sync Direction ──────────────────────────────────────────────────────────

/**
 * Device → App: what the piggy bank tells the parent.
 *
 * Contains pending claims (chores the kid says they did), acks for
 * received payments, current balance, and streak states.
 */
export interface DeviceToAppSync {
  /** Protocol version for forwards compatibility */
  syncVersion: 1;

  /** Hex cert ID of the device sending this sync */
  deviceCertId: string;

  /** Hex cert ID of the kid who owns this device */
  kidCertId: string;

  /** Unix timestamp (ms) of this sync payload */
  timestamp: number;

  /** Monotonic sync counter (detects missed syncs) */
  syncSeq: number;

  // ── Chore claims ──

  /** Pending claims the parent hasn't seen yet */
  pendingClaims: ChoreClaim[];

  // ── Payment acks ──

  /** Resource IDs of BEEF envelopes successfully stored on device */
  acknowledgedPayments: string[];

  // ── State snapshot ──

  /** Total confirmed balance in satoshis (sum of stored unspent cells) */
  confirmedBalanceSats: number;

  /** Number of BEEF cells stored on device */
  storedCellCount: number;

  /** Current streak counts: choreTemplateId → consecutive completions */
  streakStates: Record<string, number>;

  /** Active savings goals */
  savingsGoals: SavingsGoal[];

  // ── Device health ──

  /** Header chain sync state */
  headerChain: HeaderChainState;

  /** Free flash space in bytes */
  freeFlashBytes: number;

  /** Firmware version */
  firmwareVersion: string;

  /** Hex signature over SHA-256(JSON.stringify(this without sig)) using FAMILY_SYNC key */
  signature: string;
}

/**
 * App → Device: what the parent app pushes to the piggy bank.
 *
 * Contains chore template updates, approved payment envelopes,
 * claim resolutions, and config changes.
 */
export interface AppToDeviceSync {
  /** Protocol version */
  syncVersion: 1;

  /** Hex cert ID of the parent app */
  parentCertId: string;

  /** Unix timestamp (ms) */
  timestamp: number;

  /** Monotonic sync counter */
  syncSeq: number;

  // ── Chore templates ──

  /** New or updated chore templates to store on device */
  choreTemplates: ChoreTemplate[];

  /** Resource IDs of chore templates to remove from device */
  revokedChoreIds: string[];

  // ── Claim resolutions ──

  /** Claims that were approved — each includes BEEF envelope bytes (hex) */
  approvedClaims: ApprovedClaim[];

  /** Claims that were rejected */
  rejectedClaims: RejectedClaim[];

  // ── Bonus quests ──

  /** New bonus quests to display on device */
  bonusQuests: BonusQuest[];

  // ── Configuration ──

  /** Updated device configuration (null = no changes) */
  configUpdate: Partial<DeviceConfig> | null;

  // ── Headers ──

  /** New block headers to append to the device's chain (hex, 80 bytes each) */
  newHeaders: string[];

  /** Starting height for the newHeaders batch */
  headersStartHeight: number;

  /** Hex signature over SHA-256(JSON.stringify(this without sig)) using FAMILY_SYNC key */
  signature: string;
}

// ── Claim Resolution Payloads ───────────────────────────────────────────────

export interface ApprovedClaim {
  /** Resource ID of the ChoreClaim being approved */
  claimResourceId: string;

  /** The BEEF envelope containing the payment transaction (hex) */
  beefEnvelopeHex: string;

  /** Satoshis paid (should match claim.effectiveRewardSats) */
  paidSats: number;

  /** Optional parent comment */
  comment: string;

  /** Unix timestamp (ms) of approval */
  approvedAt: number;
}

export interface RejectedClaim {
  /** Resource ID of the ChoreClaim being rejected */
  claimResourceId: string;

  /** Reason for rejection */
  reason: string;

  /** Unix timestamp (ms) of rejection */
  rejectedAt: number;
}

// ── Sync Transport Abstraction ──────────────────────────────────────────────

/**
 * Transport layer interface. Implement this for each physical link:
 * WiFi REST, BLE GATT, ESP-NOW, USB serial.
 *
 * The sync engine calls send() to push a payload and registers an
 * onReceive handler for incoming payloads from the other side.
 */
export interface SyncTransport {
  /** Human-readable transport name for logging */
  readonly name: string;

  /** Whether this transport is currently connected/available */
  isConnected(): boolean;

  /** Send a sync payload to the other side. Returns when acknowledged. */
  send(payload: DeviceToAppSync | AppToDeviceSync): Promise<void>;

  /** Register handler for incoming sync payloads */
  onReceive(handler: (payload: DeviceToAppSync | AppToDeviceSync) => void): void;

  /** Start the transport (connect, bind, etc.) */
  start(): Promise<void>;

  /** Stop the transport gracefully */
  stop(): Promise<void>;
}

// ── Discovery ───────────────────────────────────────────────────────────────

/**
 * mDNS service record for piggy bank discovery on the local network.
 * The Flutter app discovers these to find piggy banks to sync with.
 */
export interface PiggyBankServiceRecord {
  /** mDNS hostname ("mia-piggybank.local") */
  hostname: string;

  /** IP address on the local network */
  ipAddress: string;

  /** HTTP port for REST sync (default 80) */
  port: number;

  /** Kid name from device profile */
  kidName: string;

  /** Device cert ID for authentication */
  deviceCertId: string;

  /** Firmware version */
  firmwareVersion: string;
}

```
