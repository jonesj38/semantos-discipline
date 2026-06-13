---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/esp32-hackkit/examples/piggybank/main/piggybank.h
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.623937+00:00
---

# esp32-hackkit/examples/piggybank/main/piggybank.h

```h
// piggybank.h — C structs and constants for the Piggy Bank firmware.
//
// These mirror the TypeScript types in @semantos/piggybank. The parent
// Flutter app and this firmware speak the same protocol — sync messages
// are JSON-serialized from these structs on the ESP32 side and parsed
// from the TS types on the app side.
//
// Memory budget: ESP32-S3 with PSRAM is generous. Without PSRAM,
// keep heap-allocated strings short and prefer stack-local buffers.

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── Domain Flags (client-sovereign range) ───────────────────────────────
// Must match packages/piggybank/src/domain.ts

#define PB_DOMAIN_PIGGYBANK        0x00010001
#define PB_DOMAIN_CHORE_SIGNING    0x00010002
#define PB_DOMAIN_PAYMENT_RECEIPT  0x00010003
#define PB_DOMAIN_CHORE_DEFINITION 0x00010004
#define PB_DOMAIN_FAMILY_SYNC      0x00010005
#define PB_DOMAIN_SPENDING_AUTH    0x00010006

// ── Error Codes ─────────────────────────────────────────────────────────

#define PB_OK                  0
#define PB_ERR_PIN_LOCKED     -10
#define PB_ERR_PIN_WRONG      -11
#define PB_ERR_NOT_PROVISIONED -12
#define PB_ERR_FLASH_FULL     -13
#define PB_ERR_BAD_BEEF       -14
#define PB_ERR_BAD_SIGNATURE  -15
#define PB_ERR_SYNC_VERSION   -16
#define PB_ERR_NO_WIFI        -17

// ── PIN Management ──────────────────────────────────────────────────────

#define PB_PIN_LENGTH          4
#define PB_PIN_MAX_ATTEMPTS    3
#define PB_PIN_LOCKOUT_MS      60000   // 60 seconds, doubles each cycle
#define PB_PIN_SALT_LEN        16
#define PB_PIN_NONCE_LEN       12
#define PB_PIN_AUTH_TAG_LEN    16

typedef struct {
    uint8_t  failed_attempts;
    int64_t  last_failed_at;      // unix ms, 0 = never
    int64_t  locked_until;        // unix ms, 0 = not locked
    uint8_t  max_attempts;
    uint32_t lockout_duration_ms;
} pb_pin_state_t;

// ── Device Profile ──────────────────────────────────────────────────────
// Stored in NVS encrypted partition after provisioning.

#define PB_CERT_ID_LEN         32   // hex bytes
#define PB_PUBKEY_LEN          33   // compressed SEC1
#define PB_KID_NAME_MAX        32   // UTF-8 bytes
#define PB_CHIP_ID_LEN         8

typedef struct {
    uint8_t  device_cert_id[PB_CERT_ID_LEN];
    uint8_t  public_key[PB_PUBKEY_LEN];
    uint8_t  encrypted_private_key[48];     // AES-256-GCM wrapped
    uint8_t  pin_salt[PB_PIN_SALT_LEN];
    uint8_t  pin_nonce[PB_PIN_NONCE_LEN];
    uint8_t  pin_auth_tag[PB_PIN_AUTH_TAG_LEN];
    char     kid_name[PB_KID_NAME_MAX];
    uint8_t  parent_cert_id[PB_CERT_ID_LEN];
    int64_t  provisioned_at;                // unix ms
    uint8_t  chip_id[PB_CHIP_ID_LEN];
} pb_device_profile_t;

// ── Chore Schedule ──────────────────────────────────────────────────────

typedef enum {
    PB_FREQ_ONCE    = 0,
    PB_FREQ_DAILY   = 1,
    PB_FREQ_WEEKLY  = 2,
    PB_FREQ_MONTHLY = 3,
} pb_chore_frequency_t;

typedef struct {
    pb_chore_frequency_t frequency;
    int8_t   day_of_week;       // 0-6, -1 = N/A
    int8_t   window_open_hour;  // 0-23, -1 = N/A
    int8_t   window_close_hour; // 0-23, -1 = N/A
} pb_chore_schedule_t;

// ── Streak Bonus ────────────────────────────────────────────────────────

typedef struct {
    uint16_t threshold;       // consecutive completions needed
    uint16_t multiplier_x100; // 150 = 1.5x
    uint16_t duration_days;
} pb_streak_bonus_t;

// ── Chore Template ──────────────────────────────────────────────────────
// Synced from parent app. Stored in NVS.
// Max 16 chores per device (kid doesn't need 50 things to do).

#define PB_MAX_CHORES          16
#define PB_CHORE_NAME_MAX      48
#define PB_CHORE_DESC_MAX      128
#define PB_CHORE_ICON_MAX      16
#define PB_CHORE_CATEGORY_MAX  16
#define PB_MAX_STREAK_BONUSES  3
#define PB_RESOURCE_ID_LEN     24

typedef struct {
    uint8_t  resource_id[PB_RESOURCE_ID_LEN];
    char     name[PB_CHORE_NAME_MAX];
    char     description[PB_CHORE_DESC_MAX];
    char     icon[PB_CHORE_ICON_MAX];
    uint32_t reward_sats;
    uint8_t  issuer_cert_id[PB_CERT_ID_LEN];
    pb_chore_schedule_t schedule;
    pb_streak_bonus_t streak_bonuses[PB_MAX_STREAK_BONUSES];
    uint8_t  streak_bonus_count;
    bool     requires_approval;
    char     category[PB_CHORE_CATEGORY_MAX];
    bool     active;  // false = revoked/deleted
} pb_chore_template_t;

// ── Chore Claim ─────────────────────────────────────────────────────────
// Minted on-device when kid presses "done". Queued for sync.

typedef enum {
    PB_CLAIM_PENDING       = 0,
    PB_CLAIM_APPROVED      = 1,
    PB_CLAIM_REJECTED      = 2,
    PB_CLAIM_AUTO_APPROVED = 3,
} pb_claim_status_t;

#define PB_MAX_PENDING_CLAIMS  32
#define PB_SIGNATURE_MAX       72   // DER-encoded ECDSA

typedef struct {
    uint8_t  resource_id[PB_RESOURCE_ID_LEN];
    uint8_t  chore_template_id[PB_RESOURCE_ID_LEN];
    uint8_t  kid_cert_id[PB_CERT_ID_LEN];
    uint8_t  device_cert_id[PB_CERT_ID_LEN];
    int64_t  claimed_at;         // unix ms
    pb_claim_status_t status;
    uint8_t  kid_signature[PB_SIGNATURE_MAX];
    uint8_t  kid_signature_len;
    uint16_t current_streak;
    uint32_t effective_reward_sats;
} pb_chore_claim_t;

// ── Stored UTXO ─────────────────────────────────────────────────────────
// Backed by a BEEF cell in flash.

#define PB_MAX_UTXOS           64
#define PB_TXID_LEN            32

typedef struct {
    uint8_t  txid[PB_TXID_LEN];
    uint32_t vout;
    uint64_t satoshis;
    uint32_t block_height;
    int64_t  received_at;        // unix ms
    char     cell_storage_key[32];
    bool     spent;
} pb_stored_utxo_t;

// ── Wallet State ────────────────────────────────────────────────────────

typedef struct {
    pb_stored_utxo_t utxos[PB_MAX_UTXOS];
    uint16_t utxo_count;
    uint64_t confirmed_balance_sats;
    uint32_t total_received;
    uint32_t total_sent;
    uint64_t lifetime_received_sats;
    uint64_t lifetime_spent_sats;
    uint32_t current_address_index;
} pb_wallet_state_t;

// ── Header Chain ────────────────────────────────────────────────────────

#define PB_BLOCK_HEADER_SIZE   80

typedef struct {
    uint32_t start_height;
    uint32_t tip_height;
    uint8_t  tip_hash[32];
    int64_t  last_sync_at;       // unix ms
    uint32_t header_count;
} pb_header_chain_state_t;

// ── Savings Goal ────────────────────────────────────────────────────────

#define PB_MAX_SAVINGS_GOALS   8
#define PB_GOAL_NAME_MAX       48

typedef struct {
    char     goal_id[16];
    char     name[PB_GOAL_NAME_MAX];
    uint64_t target_sats;
    uint64_t saved_sats;
    int64_t  created_at;        // unix ms
    int64_t  reached_at;        // unix ms, 0 = not reached
    char     icon[PB_CHORE_ICON_MAX];
} pb_savings_goal_t;

// ── Device Configuration ────────────────────────────────────────────────

#define PB_WIFI_SSID_MAX       32
#define PB_WIFI_PASS_MAX       64
#define PB_MDNS_HOST_MAX       32
#define PB_URL_MAX             128

typedef struct {
    // Spending limits
    uint32_t daily_max_sats;
    uint32_t per_tx_max_sats;
    bool     require_parent_approval;

    // WiFi
    char     wifi_ssid[PB_WIFI_SSID_MAX];
    char     wifi_password[PB_WIFI_PASS_MAX];
    bool     wifi_configured;

    // Network
    char     mdns_hostname[PB_MDNS_HOST_MAX];
    char     header_sync_url[PB_URL_MAX];

    // Display / UX
    uint8_t  display_brightness;
    bool     sound_enabled;
    uint16_t auto_lock_seconds;
    int16_t  timezone_offset_minutes;
} pb_device_config_t;

// ── Aggregate Device State ──────────────────────────────────────────────
// Top-level struct holding everything the firmware needs at runtime.

typedef struct {
    // Identity (loaded from NVS on boot, NULL if not provisioned)
    pb_device_profile_t   *profile;
    pb_pin_state_t         pin_state;
    bool                   unlocked;      // true after correct PIN entry

    // Chores
    pb_chore_template_t    chores[PB_MAX_CHORES];
    uint8_t                chore_count;
    pb_chore_claim_t       pending_claims[PB_MAX_PENDING_CLAIMS];
    uint8_t                pending_claim_count;
    uint16_t               streaks[PB_MAX_CHORES]; // parallel to chores[]

    // Wallet
    pb_wallet_state_t      wallet;

    // Headers
    pb_header_chain_state_t header_chain;

    // Savings
    pb_savings_goal_t      goals[PB_MAX_SAVINGS_GOALS];
    uint8_t                goal_count;

    // Config
    pb_device_config_t     config;

    // Sync
    uint32_t               sync_seq;      // monotonic counter
    int64_t                last_sync_at;   // unix ms
} pb_state_t;

// ── Lifecycle ───────────────────────────────────────────────────────────

/** Initialize piggy bank state. Loads profile + config from NVS. */
int pb_init(pb_state_t *state);

/** Enter PIN. Returns PB_OK, PB_ERR_PIN_WRONG, or PB_ERR_PIN_LOCKED. */
int pb_unlock(pb_state_t *state, const char pin[PB_PIN_LENGTH]);

/** Lock the device (zero the decrypted key from memory). */
void pb_lock(pb_state_t *state);

/** Mint a chore claim (kid pressed "done"). Returns PB_OK or error. */
int pb_claim_chore(pb_state_t *state, uint8_t chore_index);

/** Receive a BEEF envelope, verify SPV, store cell. Returns PB_OK or error. */
int pb_receive_payment(pb_state_t *state, const uint8_t *beef, size_t beef_len);

/** Get the current balance in satoshis. */
uint64_t pb_get_balance(const pb_state_t *state);

/** Get the number of pending (unsynced) claims. */
uint8_t pb_get_pending_claim_count(const pb_state_t *state);

#ifdef __cplusplus
}
#endif

```
