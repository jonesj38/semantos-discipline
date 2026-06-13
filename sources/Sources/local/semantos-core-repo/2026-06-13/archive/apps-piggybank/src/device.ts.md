---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-piggybank/src/device.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.719468+00:00
---

# archive/apps-piggybank/src/device.ts

```ts
/**
 * Device Identity & Provisioning
 *
 * Types for the ESP32 piggy bank device lifecycle:
 *   1. USB-C provisioning (serial handshake → cert + key push)
 *   2. PIN setup and key wrapping
 *   3. Device profile storage
 *   4. Header chain sync state
 */

import type { DomainFlag } from '@semantos/core/types/domain-flags.js';
import type { SpendingLimits } from './chores.js';

// ── Device Identity ─────────────────────────────────────────────────────────

/**
 * A provisioned piggy bank device.
 *
 * Created during USB-C provisioning and stored in NVS (encrypted partition).
 * The private key material is wrapped with a PIN-derived AES key.
 */
export interface DeviceProfile {
  /** Hex cert ID of this device's Plexus identity */
  deviceCertId: string;

  /** Hex compressed public key (33 bytes) */
  publicKey: string;

  /**
   * Encrypted private key blob (AES-256-GCM).
   * Key = PBKDF2(PIN, salt, 10000 iterations, 32 bytes)
   * Decrypted only when PIN is entered; zeroed after use.
   */
  encryptedPrivateKey: string;

  /** Salt for PBKDF2 PIN derivation (hex, 16 bytes) */
  pinSalt: string;

  /** AES-GCM nonce used for key encryption (hex, 12 bytes) */
  pinNonce: string;

  /** AES-GCM auth tag (hex, 16 bytes) */
  pinAuthTag: string;

  /** Human-readable kid name ("Mia", "Liam") */
  kidName: string;

  /** Hex cert ID of the parent who provisioned this device */
  parentCertId: string;

  /** Unix timestamp (ms) when device was provisioned */
  provisionedAt: number;

  /** Firmware version at provisioning time */
  firmwareVersion: string;

  /** ESP32 chip ID (for device identification over USB) */
  chipId: string;
}

// ── PIN Management ──────────────────────────────────────────────────────────

export interface PinState {
  /** Number of consecutive failed PIN attempts */
  failedAttempts: number;

  /** Unix timestamp (ms) of last failed attempt */
  lastFailedAt: number | null;

  /** Unix timestamp (ms) when lockout expires (null = not locked) */
  lockedUntil: number | null;

  /** Maximum allowed attempts before lockout */
  maxAttempts: number;

  /** Lockout duration in ms. Doubles after each lockout cycle. */
  lockoutDurationMs: number;
}

/** Default PIN policy: 3 attempts, 60s initial lockout, escalating */
export const DEFAULT_PIN_STATE: PinState = {
  failedAttempts: 0,
  lastFailedAt: null,
  lockedUntil: null,
  maxAttempts: 3,
  lockoutDurationMs: 60_000,
};

// ── Provisioning Protocol ───────────────────────────────────────────────────

/**
 * Messages exchanged during USB-C provisioning.
 *
 * The provisioning flow is:
 *   1. Device → Host: HELLO (chip ID, firmware version)
 *   2. Host → Device: CHALLENGE (random nonce for DH key exchange)
 *   3. Device → Host: RESPONSE (device ephemeral pubkey + signed nonce)
 *   4. Host → Device: PROVISION (encrypted cert + wrapped privkey + kid name)
 *   5. Device → Host: ACK (success) or NACK (failure reason)
 *   6. Device prompts kid to set 4-digit PIN via buttons
 *   7. Device wraps privkey with PIN-derived AES key, stores in NVS
 */
export enum ProvisioningStep {
  HELLO = 'HELLO',
  CHALLENGE = 'CHALLENGE',
  RESPONSE = 'RESPONSE',
  PROVISION = 'PROVISION',
  ACK = 'ACK',
  NACK = 'NACK',
  PIN_SET = 'PIN_SET',
}

export interface ProvisioningHello {
  step: ProvisioningStep.HELLO;
  chipId: string;
  firmwareVersion: string;
  hasExistingIdentity: boolean;
}

export interface ProvisioningChallenge {
  step: ProvisioningStep.CHALLENGE;
  nonce: string;             // hex, 32 bytes
  hostEphemeralPubKey: string; // hex, 33 bytes compressed
}

export interface ProvisioningResponse {
  step: ProvisioningStep.RESPONSE;
  deviceEphemeralPubKey: string; // hex, 33 bytes compressed
  signedNonce: string;           // hex, DER-encoded ECDSA sig
}

export interface ProvisioningPayload {
  step: ProvisioningStep.PROVISION;
  /** Encrypted with shared ECDH secret (AES-256-GCM) */
  encryptedPayload: string;  // hex: { certJson, privateKeyHex, kidName, parentCertId }
  nonce: string;             // hex, 12 bytes GCM nonce
  authTag: string;           // hex, 16 bytes GCM tag
}

export interface ProvisioningAck {
  step: ProvisioningStep.ACK;
  deviceCertId: string;
  publicKey: string;
}

export interface ProvisioningNack {
  step: ProvisioningStep.NACK;
  reason: string;
}

export type ProvisioningMessage =
  | ProvisioningHello
  | ProvisioningChallenge
  | ProvisioningResponse
  | ProvisioningPayload
  | ProvisioningAck
  | ProvisioningNack;

// ── Header Chain ────────────────────────────────────────────────────────────

/**
 * State of the device's local header chain for SPV verification.
 *
 * The device stores a contiguous range of block headers (80 bytes each)
 * and validates BEEF envelopes against them locally.
 */
export interface HeaderChainState {
  /** Lowest block height stored */
  startHeight: number;

  /** Highest block height stored */
  tipHeight: number;

  /** Hash of the tip header (hex, 32 bytes, double-SHA256 LE) */
  tipHash: string;

  /** Unix timestamp (ms) of last sync with a header source */
  lastSyncAt: number;

  /** Total headers stored (tipHeight - startHeight + 1) */
  headerCount: number;

  /** Approximate flash usage in bytes (headerCount × 80) */
  flashUsageBytes: number;
}

// ── Device Configuration ────────────────────────────────────────────────────

/**
 * Runtime configuration pushed from the parent app.
 * Stored in NVS, applied on next boot or sync.
 */
export interface DeviceConfig {
  /** Kid's spending limits */
  spendingLimits: SpendingLimits;

  /** WiFi SSID for header sync + API fallback (null = offline only) */
  wifiSsid: string | null;

  /** WiFi password (encrypted in transit, cleartext in NVS) */
  wifiPassword: string | null;

  /** mDNS hostname for local network discovery ("mia-piggybank") */
  mdnsHostname: string;

  /** Display brightness (0-255) */
  displayBrightness: number;

  /** Sound effects enabled */
  soundEnabled: boolean;

  /** Which header sync endpoint to use (null = WhatsOnChain default) */
  headerSyncUrl: string | null;

  /** Auto-lock timeout in seconds (0 = never) */
  autoLockSeconds: number;

  /** Timezone offset in minutes from UTC (for schedule window evaluation) */
  timezoneOffsetMinutes: number;
}

export const DEFAULT_DEVICE_CONFIG: DeviceConfig = {
  spendingLimits: {
    dailyMaxSats: 10_000,
    perTxMaxSats: 5_000,
    requireParentApproval: false,
  },
  wifiSsid: null,
  wifiPassword: null,
  mdnsHostname: 'piggybank',
  displayBrightness: 128,
  soundEnabled: true,
  headerSyncUrl: null,
  autoLockSeconds: 300,
  timezoneOffsetMinutes: 0,
};

```
