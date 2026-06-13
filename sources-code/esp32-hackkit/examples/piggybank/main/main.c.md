---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/esp32-hackkit/examples/piggybank/main/main.c
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.623345+00:00
---

# esp32-hackkit/examples/piggybank/main/main.c

```c
// piggybank — BSV piggy bank for kids on ESP32-S3.
//
// Hardware:
//   - ESP32-S3-DevKitC (native USB-C, 8MB flash, PSRAM)
//   - SSD1306 128×64 OLED (I2C) or ST7735 160×128 TFT (SPI)
//   - 3× tactile buttons: UP (GPIO 4), DOWN (GPIO 5), CONFIRM (GPIO 6)
//   - Piezo buzzer (GPIO 7)
//   - Optional: PN532 NFC (I2C), MPU6050 accelerometer (I2C)
//
// Boot sequence:
//   1. Init NVS, load profile + config
//   2. If not provisioned → show "Plug me in!" on display, wait for USB
//   3. If provisioned → show PIN entry screen
//   4. After unlock → main menu (Balance / Chores / Goals / Settings)
//   5. Background: WiFi connect → header sync → mDNS announce
//
// The Semantos cell engine runs BEEF/SPV verification. The four adapters
// are wired to NVS (storage), Plexus cert (identity), header chain
// (anchor), and WiFi/BLE/ESP-NOW (network).

#include <stdio.h>
#include <string.h>
#include "esp_log.h"
#include "esp_system.h"
#include "nvs_flash.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "driver/gpio.h"

#include "semantos.h"
#include "piggybank.h"

static const char *TAG = "piggybank";

// ── GPIO Pins ───────────────────────────────────────────────────────────

#define BTN_UP_GPIO       4
#define BTN_DOWN_GPIO     5
#define BTN_CONFIRM_GPIO  6
#define BUZZER_GPIO       7

// ── Button Events ───────────────────────────────────────────────────────

typedef enum {
    BTN_EVT_NONE = 0,
    BTN_EVT_UP,
    BTN_EVT_DOWN,
    BTN_EVT_CONFIRM,
    BTN_EVT_CONFIRM_LONG,  // held > 1 second
} button_event_t;

static QueueHandle_t s_button_queue;

// ── UI Screens ──────────────────────────────────────────────────────────

typedef enum {
    SCREEN_BOOT,
    SCREEN_NOT_PROVISIONED,
    SCREEN_PIN_ENTRY,
    SCREEN_MAIN_MENU,
    SCREEN_BALANCE,
    SCREEN_CHORE_LIST,
    SCREEN_CHORE_CONFIRM,
    SCREEN_CHORE_DONE,
    SCREEN_SAVINGS_GOALS,
    SCREEN_QR_RECEIVE,
    SCREEN_QR_SPEND,
    SCREEN_SETTINGS,
    SCREEN_SYNCING,
} screen_t;

// ── Application State ───────────────────────────────────────────────────

static pb_state_t s_state;
static semantos_t *s_sem = NULL;
static screen_t s_current_screen = SCREEN_BOOT;
static uint8_t s_menu_index = 0;
static char s_pin_buffer[PB_PIN_LENGTH + 1] = {0};
static uint8_t s_pin_pos = 0;

// ── Display Abstraction ─────────────────────────────────────────────────
// TODO: implement for SSD1306 or ST7735. For now, log to serial.

static void display_clear(void) {
    // TODO: clear OLED/TFT
}

static void display_text(uint8_t row, const char *text) {
    ESP_LOGI(TAG, "[display row %d] %s", row, text);
}

static void display_large_number(uint64_t sats) {
    // Show balance in a large font. BSV = sats / 100_000_000
    uint32_t bsv_whole = (uint32_t)(sats / 100000000ULL);
    uint32_t bsv_frac  = (uint32_t)(sats % 100000000ULL);
    char buf[32];
    snprintf(buf, sizeof(buf), "%u.%08u BSV", bsv_whole, bsv_frac);
    ESP_LOGI(TAG, "[display BALANCE] %s", buf);
}

// ── Buzzer ──────────────────────────────────────────────────────────────

static void buzzer_coin_sound(void) {
    if (!s_state.config.sound_enabled) return;
    // TODO: PWM tone sequence (Mario coin: 988Hz 80ms → 1319Hz 400ms)
    ESP_LOGI(TAG, "[buzzer] coin!");
}

static void buzzer_error_sound(void) {
    if (!s_state.config.sound_enabled) return;
    // TODO: low buzz
    ESP_LOGI(TAG, "[buzzer] error");
}

static void buzzer_streak_sound(void) {
    if (!s_state.config.sound_enabled) return;
    // TODO: ascending arpeggio
    ESP_LOGI(TAG, "[buzzer] streak!");
}

// ── Button ISR ──────────────────────────────────────────────────────────

static void IRAM_ATTR button_isr_handler(void *arg) {
    button_event_t evt = (button_event_t)(uintptr_t)arg;
    xQueueSendFromISR(s_button_queue, &evt, NULL);
}

static void buttons_init(void) {
    s_button_queue = xQueueCreate(10, sizeof(button_event_t));

    gpio_config_t io_conf = {
        .intr_type = GPIO_INTR_NEGEDGE,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
    };

    io_conf.pin_bit_mask = (1ULL << BTN_UP_GPIO);
    gpio_config(&io_conf);
    gpio_isr_handler_add(BTN_UP_GPIO, button_isr_handler, (void *)BTN_EVT_UP);

    io_conf.pin_bit_mask = (1ULL << BTN_DOWN_GPIO);
    gpio_config(&io_conf);
    gpio_isr_handler_add(BTN_DOWN_GPIO, button_isr_handler, (void *)BTN_EVT_DOWN);

    io_conf.pin_bit_mask = (1ULL << BTN_CONFIRM_GPIO);
    gpio_config(&io_conf);
    gpio_isr_handler_add(BTN_CONFIRM_GPIO, button_isr_handler, (void *)BTN_EVT_CONFIRM);
}

// ── Screen Handlers ─────────────────────────────────────────────────────

static void render_screen(void) {
    display_clear();

    switch (s_current_screen) {
        case SCREEN_BOOT:
            display_text(0, "Piggy Bank");
            display_text(1, "booting...");
            break;

        case SCREEN_NOT_PROVISIONED:
            display_text(0, "== Setup ==");
            display_text(1, "Plug USB-C into");
            display_text(2, "parent's computer");
            display_text(3, "to get started!");
            break;

        case SCREEN_PIN_ENTRY: {
            display_text(0, "Enter PIN:");
            char dots[PB_PIN_LENGTH + 1] = {0};
            for (int i = 0; i < PB_PIN_LENGTH; i++) {
                dots[i] = (i < s_pin_pos) ? '*' : '_';
            }
            display_text(1, dots);
            if (s_state.pin_state.failed_attempts > 0) {
                char warn[32];
                snprintf(warn, sizeof(warn), "%d attempts left",
                         s_state.pin_state.max_attempts - s_state.pin_state.failed_attempts);
                display_text(3, warn);
            }
            break;
        }

        case SCREEN_MAIN_MENU: {
            display_text(0, s_state.profile->kid_name);
            const char *items[] = {"Balance", "Chores", "Goals", "Receive", "Settings"};
            for (int i = 0; i < 5; i++) {
                char line[48];
                snprintf(line, sizeof(line), "%s %s", (i == s_menu_index) ? ">" : " ", items[i]);
                display_text(i + 1, line);
            }
            break;
        }

        case SCREEN_BALANCE:
            display_text(0, "== Balance ==");
            display_large_number(s_state.wallet.confirmed_balance_sats);
            {
                char info[48];
                snprintf(info, sizeof(info), "%u UTXOs  %u received",
                         s_state.wallet.utxo_count, s_state.wallet.total_received);
                display_text(3, info);
            }
            break;

        case SCREEN_CHORE_LIST:
            display_text(0, "== Chores ==");
            if (s_state.chore_count == 0) {
                display_text(1, "No chores yet!");
                display_text(2, "Ask parent to");
                display_text(3, "add some :)");
            } else {
                for (int i = 0; i < s_state.chore_count && i < 4; i++) {
                    char line[64];
                    uint8_t display_idx = (s_menu_index + i) % s_state.chore_count;
                    snprintf(line, sizeof(line), "%s %s (%u sats)",
                             (i == 0) ? ">" : " ",
                             s_state.chores[display_idx].name,
                             s_state.chores[display_idx].reward_sats);
                    display_text(i + 1, line);
                }
            }
            break;

        case SCREEN_CHORE_CONFIRM: {
            pb_chore_template_t *chore = &s_state.chores[s_menu_index];
            display_text(0, "Done this?");
            display_text(1, chore->name);
            char reward[32];
            uint16_t streak = s_state.streaks[s_menu_index];
            snprintf(reward, sizeof(reward), "%u sats (streak: %u)",
                     chore->reward_sats, streak);
            display_text(2, reward);
            display_text(3, "[OK] Claim  [DOWN] Back");
            break;
        }

        case SCREEN_CHORE_DONE:
            display_text(0, "== Claimed! ==");
            display_text(1, "Waiting for");
            display_text(2, "parent approval");
            display_text(3, ":)");
            break;

        case SCREEN_SAVINGS_GOALS:
            display_text(0, "== Goals ==");
            if (s_state.goal_count == 0) {
                display_text(1, "No goals set");
            } else {
                for (int i = 0; i < s_state.goal_count && i < 3; i++) {
                    char line[64];
                    uint32_t pct = (uint32_t)(s_state.goals[i].saved_sats * 100 /
                                   (s_state.goals[i].target_sats ? s_state.goals[i].target_sats : 1));
                    snprintf(line, sizeof(line), "%s %u%%",
                             s_state.goals[i].name, pct);
                    display_text(i + 1, line);
                }
            }
            break;

        case SCREEN_QR_RECEIVE:
            display_text(0, "== Receive ==");
            // TODO: render QR code bitmap from current receiving address
            display_text(1, "QR code here");
            display_text(3, "[HOLD] New address");
            break;

        case SCREEN_SYNCING:
            display_text(0, "== Syncing ==");
            display_text(1, "...");
            break;

        default:
            display_text(0, "TODO");
            break;
    }
}

static void handle_button(button_event_t evt) {
    switch (s_current_screen) {
        case SCREEN_PIN_ENTRY:
            if (evt == BTN_UP) {
                // Cycle digit up: 0-9
                s_pin_buffer[s_pin_pos] = (s_pin_buffer[s_pin_pos] == 0)
                    ? '0'
                    : (s_pin_buffer[s_pin_pos] == '9' ? '0' : s_pin_buffer[s_pin_pos] + 1);
            } else if (evt == BTN_DOWN) {
                s_pin_buffer[s_pin_pos] = (s_pin_buffer[s_pin_pos] == 0 || s_pin_buffer[s_pin_pos] == '0')
                    ? '9'
                    : s_pin_buffer[s_pin_pos] - 1;
            } else if (evt == BTN_EVT_CONFIRM) {
                s_pin_pos++;
                if (s_pin_pos >= PB_PIN_LENGTH) {
                    // Attempt unlock
                    int rc = pb_unlock(&s_state, s_pin_buffer);
                    if (rc == PB_OK) {
                        buzzer_coin_sound();
                        s_current_screen = SCREEN_MAIN_MENU;
                        s_menu_index = 0;
                    } else if (rc == PB_ERR_PIN_LOCKED) {
                        buzzer_error_sound();
                        display_text(3, "LOCKED! Wait...");
                    } else {
                        buzzer_error_sound();
                    }
                    // Reset PIN buffer
                    memset(s_pin_buffer, 0, sizeof(s_pin_buffer));
                    s_pin_pos = 0;
                }
            }
            break;

        case SCREEN_MAIN_MENU:
            if (evt == BTN_EVT_UP && s_menu_index > 0) s_menu_index--;
            else if (evt == BTN_EVT_DOWN && s_menu_index < 4) s_menu_index++;
            else if (evt == BTN_EVT_CONFIRM) {
                switch (s_menu_index) {
                    case 0: s_current_screen = SCREEN_BALANCE; break;
                    case 1: s_current_screen = SCREEN_CHORE_LIST; s_menu_index = 0; break;
                    case 2: s_current_screen = SCREEN_SAVINGS_GOALS; break;
                    case 3: s_current_screen = SCREEN_QR_RECEIVE; break;
                    case 4: s_current_screen = SCREEN_SETTINGS; break;
                }
            }
            break;

        case SCREEN_BALANCE:
        case SCREEN_SAVINGS_GOALS:
        case SCREEN_SETTINGS:
            // Any button returns to main menu
            if (evt == BTN_EVT_DOWN || evt == BTN_EVT_CONFIRM) {
                s_current_screen = SCREEN_MAIN_MENU;
                s_menu_index = 0;
            }
            break;

        case SCREEN_CHORE_LIST:
            if (evt == BTN_EVT_UP && s_menu_index > 0) s_menu_index--;
            else if (evt == BTN_EVT_DOWN && s_menu_index < s_state.chore_count - 1) s_menu_index++;
            else if (evt == BTN_EVT_CONFIRM) {
                s_current_screen = SCREEN_CHORE_CONFIRM;
            } else if (evt == BTN_EVT_CONFIRM_LONG) {
                s_current_screen = SCREEN_MAIN_MENU;
                s_menu_index = 0;
            }
            break;

        case SCREEN_CHORE_CONFIRM:
            if (evt == BTN_EVT_CONFIRM) {
                int rc = pb_claim_chore(&s_state, s_menu_index);
                if (rc == PB_OK) {
                    buzzer_coin_sound();
                    s_current_screen = SCREEN_CHORE_DONE;
                } else {
                    buzzer_error_sound();
                }
            } else if (evt == BTN_EVT_DOWN) {
                s_current_screen = SCREEN_CHORE_LIST;
            }
            break;

        case SCREEN_CHORE_DONE:
            if (evt == BTN_EVT_CONFIRM || evt == BTN_EVT_DOWN) {
                s_current_screen = SCREEN_CHORE_LIST;
            }
            break;

        case SCREEN_QR_RECEIVE:
            if (evt == BTN_EVT_DOWN || evt == BTN_EVT_CONFIRM) {
                s_current_screen = SCREEN_MAIN_MENU;
                s_menu_index = 0;
            }
            // TODO: long press = generate new address
            break;

        default:
            break;
    }

    render_screen();
}

// ── Adapter Implementations ─────────────────────────────────────────────
// Wire the Semantos kernel to the piggy bank's NVS storage.

static int32_t pb_storage_read(const char *key, size_t key_len,
                                uint8_t *out_buf, size_t *inout_len) {
    // TODO: NVS read. Key format: "pb:<namespace>:<id>"
    return SEMANTOS_ERR_DENIED;
}

static int32_t pb_storage_write(const char *key, size_t key_len,
                                 const uint8_t *data, size_t data_len) {
    // TODO: NVS write
    return SEMANTOS_ERR_DENIED;
}

static int32_t pb_identity_resolve(const uint8_t *cert_id, size_t cert_id_len,
                                    uint8_t *out_json, size_t *inout_len) {
    // TODO: resolve from NVS-stored certs
    return SEMANTOS_ERR_DENIED;
}

static int32_t pb_identity_derive(const char *parent_cert, size_t parent_cert_len,
                                   const char *resource_id, size_t resource_id_len,
                                   uint32_t domain_flag,
                                   uint8_t *out_json, size_t *inout_len) {
    // TODO: BRC-42 key derivation using mbedTLS
    return SEMANTOS_ERR_DENIED;
}

static int32_t pb_anchor_submit(const uint8_t *state_hash, size_t state_hash_len,
                                 const char *metadata_json, size_t metadata_len,
                                 uint8_t *out_proof, size_t *inout_len) {
    // TODO: verify against local header chain
    return SEMANTOS_ERR_DENIED;
}

static int32_t pb_network_publish(const char *object_json, size_t object_len) {
    // TODO: mDNS / BLE / ESP-NOW
    return SEMANTOS_ERR_DENIED;
}

static int32_t pb_network_resolve(const char *query_json, size_t query_len,
                                   uint8_t *out_results, size_t *inout_len) {
    // TODO: mDNS / BLE / ESP-NOW
    return SEMANTOS_ERR_DENIED;
}

static const semantos_adapter_table_t s_pb_adapters = {
    .storage_read     = pb_storage_read,
    .storage_write    = pb_storage_write,
    .identity_resolve = pb_identity_resolve,
    .identity_derive  = pb_identity_derive,
    .anchor_submit    = pb_anchor_submit,
    .network_publish  = pb_network_publish,
    .network_resolve  = pb_network_resolve,
};

// ── Lifecycle Stubs ─────────────────────────────────────────────────────

int pb_init(pb_state_t *state) {
    memset(state, 0, sizeof(pb_state_t));
    state->pin_state.max_attempts = PB_PIN_MAX_ATTEMPTS;
    state->pin_state.lockout_duration_ms = PB_PIN_LOCKOUT_MS;

    // TODO: load profile from NVS encrypted partition
    // If no profile found, state->profile remains NULL → not provisioned

    // TODO: load chore templates, wallet state, config from NVS

    return PB_OK;
}

int pb_unlock(pb_state_t *state, const char pin[PB_PIN_LENGTH]) {
    // Check lockout
    if (state->pin_state.locked_until > 0) {
        // TODO: check against current time
        // If still locked, return PB_ERR_PIN_LOCKED
    }

    // TODO: derive AES key from PIN + salt via PBKDF2
    // TODO: attempt AES-GCM decrypt of encrypted_private_key
    // TODO: if auth tag matches → success, zero plaintext after use
    // TODO: if mismatch → increment failed_attempts, check lockout

    return PB_ERR_PIN_WRONG; // stub
}

void pb_lock(pb_state_t *state) {
    state->unlocked = false;
    // TODO: zero any decrypted key material in memory
}

int pb_claim_chore(pb_state_t *state, uint8_t chore_index) {
    if (chore_index >= state->chore_count) return PB_ERR_BAD_BEEF;
    if (!state->unlocked) return PB_ERR_PIN_LOCKED;
    if (state->pending_claim_count >= PB_MAX_PENDING_CLAIMS) return PB_ERR_FLASH_FULL;

    pb_chore_template_t *chore = &state->chores[chore_index];
    pb_chore_claim_t *claim = &state->pending_claims[state->pending_claim_count];

    memset(claim, 0, sizeof(pb_chore_claim_t));
    memcpy(claim->chore_template_id, chore->resource_id, PB_RESOURCE_ID_LEN);
    memcpy(claim->kid_cert_id, state->profile->device_cert_id, PB_CERT_ID_LEN);
    memcpy(claim->device_cert_id, state->profile->device_cert_id, PB_CERT_ID_LEN);
    // TODO: claim->claimed_at = get_current_time_ms();
    claim->status = PB_CLAIM_PENDING;
    claim->current_streak = state->streaks[chore_index] + 1;
    claim->effective_reward_sats = chore->reward_sats;

    // TODO: apply streak multiplier if applicable
    // TODO: sign claim with CHORE_SIGNING domain key
    // TODO: generate resource_id

    // Auto-approve if chore doesn't require it
    if (!chore->requires_approval) {
        claim->status = PB_CLAIM_AUTO_APPROVED;
    }

    state->streaks[chore_index]++;
    state->pending_claim_count++;

    ESP_LOGI(TAG, "chore claimed: %s (streak %u, %u sats)",
             chore->name, claim->current_streak, claim->effective_reward_sats);

    return PB_OK;
}

int pb_receive_payment(pb_state_t *state, const uint8_t *beef, size_t beef_len) {
    // TODO:
    // 1. Parse BEEF envelope prefix (0x01010101 + subject TXID)
    // 2. Run beef.zig SPV verification via semantos_kernel
    // 3. Extract output value and locking script
    // 4. Verify locking script matches our key
    // 5. Store cell in flash (SPIFFS/LittleFS)
    // 6. Add to utxo list
    // 7. Update balance

    ESP_LOGI(TAG, "receive_payment: %zu bytes BEEF", beef_len);
    return PB_ERR_BAD_BEEF; // stub
}

uint64_t pb_get_balance(const pb_state_t *state) {
    return state->wallet.confirmed_balance_sats;
}

uint8_t pb_get_pending_claim_count(const pb_state_t *state) {
    return state->pending_claim_count;
}

// ── Main ────────────────────────────────────────────────────────────────

void app_main(void) {
    ESP_LOGI(TAG, "=== Piggy Bank v0.1.0 ===");

    // Init NVS
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Init GPIO ISR service
    gpio_install_isr_service(0);

    // Init buttons
    buttons_init();

    // Init piggy bank state
    int rc = pb_init(&s_state);
    if (rc != PB_OK) {
        ESP_LOGE(TAG, "pb_init failed: %d", rc);
        return;
    }

    // Init Semantos cell engine with piggybank adapters
    semantos_config_t sem_cfg = SEMANTOS_DEFAULT_CONFIG();
    sem_cfg.adapters = &s_pb_adapters;
    if (semantos_init(&sem_cfg, &s_sem) != ESP_OK) {
        ESP_LOGE(TAG, "semantos_init failed");
        return;
    }
    rc = semantos_kernel_init(s_sem);
    ESP_LOGI(TAG, "cell engine ready (rc=%d)", rc);

    // Decide initial screen
    if (s_state.profile == NULL) {
        s_current_screen = SCREEN_NOT_PROVISIONED;
    } else {
        s_current_screen = SCREEN_PIN_ENTRY;
    }
    render_screen();

    // Main loop: process button events
    button_event_t evt;
    for (;;) {
        if (xQueueReceive(s_button_queue, &evt, pdMS_TO_TICKS(100))) {
            handle_button(evt);
        }

        // TODO: periodic tasks
        // - WiFi reconnect check
        // - Header sync (if connected)
        // - mDNS announce
        // - Auto-lock timer
        // - BLE advertising for nearby parent app
    }
}

```
