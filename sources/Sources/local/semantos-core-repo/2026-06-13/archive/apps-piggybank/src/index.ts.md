---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-piggybank/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.719192+00:00
---

# archive/apps-piggybank/src/index.ts

```ts
/**
 * @semantos/piggybank
 *
 * BSV piggy bank protocol for kids: chore/reward system with offline SPV,
 * Plexus identity, and multi-device sync.
 *
 * Three targets consume these types:
 *   1. ESP32 firmware  — C structs mirror these interfaces (see piggybank.h)
 *   2. Flutter app     — Dart classes generated or hand-ported from these types
 *   3. Web dashboard   — imports directly from this package
 *
 * The protocol is transport-agnostic: WiFi, BLE, ESP-NOW, USB serial.
 */

// Domain flags (client-sovereign range)
export {
  PIGGYBANK,
  CHORE_SIGNING,
  PAYMENT_RECEIPT,
  CHORE_DEFINITION,
  FAMILY_SYNC,
  SPENDING_AUTH,
} from './domain.js';

// Chore & reward system
export {
  ChoreFrequency,
  ClaimStatus,
  type ChoreSchedule,
  type StreakBonus,
  type SpendingLimits,
  type ChoreTemplate,
  type ChoreClaim,
  type ClaimResolutionProof,
  type BonusQuest,
  type BonusQuestMeta,
  type SavingsGoal,
  createChoreTemplate,
  createChoreClaim,
  createBonusQuest,
} from './chores.js';

// Device identity & provisioning
export {
  ProvisioningStep,
  DEFAULT_PIN_STATE,
  DEFAULT_DEVICE_CONFIG,
  type DeviceProfile,
  type PinState,
  type ProvisioningHello,
  type ProvisioningChallenge,
  type ProvisioningResponse,
  type ProvisioningPayload,
  type ProvisioningAck,
  type ProvisioningNack,
  type ProvisioningMessage,
  type HeaderChainState,
  type DeviceConfig,
} from './device.js';

// Sync protocol
export {
  type DeviceToAppSync,
  type AppToDeviceSync,
  type ApprovedClaim,
  type RejectedClaim,
  type SyncTransport,
  type PiggyBankServiceRecord,
} from './sync.js';

// Wallet
export {
  SpendStatus,
  type StoredUtxo,
  type WalletState,
  type SpendRequest,
  type PaymentQrData,
  encodePaymentUri,
} from './wallet.js';

```
