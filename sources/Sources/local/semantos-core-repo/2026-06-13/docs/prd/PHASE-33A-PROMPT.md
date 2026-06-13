---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-33A-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.696826+00:00
---

# Phase 33A Execution Prompt — DePIN Vertical Grammar + ESP32 Adapter Wiring

> Paste this prompt into a fresh Claude Code session to execute Phase 33A.

---

## Context

You are working in the `semantos-core` repo — the TypeScript application layer, React loom, and ESP32 hack-kit for Bitcoin-native semantic objects. The kernel (cell engine, 2-PDA, linearity enforcement) is Zig/WASM in the sibling `semantos` repo; this repo holds the type system, WASM bindings, loom UI, and `esp32-hackkit/` — an ESP-IDF component wrapping the 29 KB embedded WASM cell engine for ESP32 microcontrollers.

Phase 33A establishes the DePIN (Decentralised Physical Infrastructure Network) vertical on Semantos. This phase delivers three things:

1. **DePIN vertical grammar** — type definitions with linearity assignments (`depin.sensor.reading` → LINEAR, `depin.device.cert` → RELEVANT, etc.) following the `paskian/src/grammar.ts` pattern
2. **Three real ESP32 adapter implementations** — Storage (NVS + LittleFS), Identity (NVS cert store), and Anchor (CoAP POST to gateway) — replacing the no-op stubs in `adapters_noop.c`
3. **MFP payment channel state on ESP32** — C struct + tick proof computation matching the TypeScript `settlement.ts` TickProof format exactly

After this phase, an ESP32 can boot with real adapters, create DePIN-typed cells, compute payment tick proofs, and submit anchor hashes to a gateway. Phase 33B adds the OpenThread/6LoWPAN network adapter and mesh relay.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are building on top of. If you haven't read them, you will produce stubs, mocks, or code that doesn't integrate. That is not acceptable.

**Read first** (the PRDs — your requirements):
- `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-33-DEPIN-6LOWPAN-MASTER.md` — Master PRD: full architecture, deliverables D33.1–D33.9, hardware requirements, commercial context
- `/Users/toddprice/projects/semantos-core/docs/prd/COMMERCIAL-CONTEXT.md` — Business model → phase mapping. Understand where DePIN fits in the revenue picture.

**Read second** (the ESP32 hack-kit you are extending):
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/include/semantos.h` — Public API: `semantos_init()`, `semantos_kernel_*()` functions
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/include/semantos_adapters.h` — The four adapter callback signatures. These are your C function pointer contracts.
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/include/semantos_internal.h` — Internal types: `semantos_t`, `semantos_config_t`, `SEMANTOS_DEFAULT_CONFIG()`
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/src/semantos.c` — Kernel lifecycle: how adapters are registered and called
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/src/adapters_noop.c` — The no-op stubs you are replacing with real implementations
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/components/semantos/src/host_crypto_mbedtls.c` — Crypto host imports: `host_sha256`, `host_checksig`. You will use `host_sha256` for HMAC computation.
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/docs/ADAPTERS.md` — The four adapter patterns explained: callback signatures, error codes, ESP32-friendly bindings
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/docs/HOST_IMPORTS.md` — Ten host imports, especially `host_sha256` and `host_call_by_name`
- `/Users/toddprice/projects/semantos-core/esp32-hackkit/examples/hello_cell/main/main.c` — The existing example: shows how to boot, load script, execute. Your example extends this pattern.

**Read third** (the TypeScript implementations your C code must match):
- `/Users/toddprice/projects/semantos-core/packages/paskian/src/grammar.ts` — Paskian story grammar: the pattern you will follow for the DePIN grammar. Note `PASKIAN_GRAPH_TYPES`, `PASKIAN_STORY_TYPES`, `PaskianStoryGrammar` export structure.
- `/Users/toddprice/projects/semantos-core/packages/cell-ops/src/typeHashRegistry.ts` — Type hash computation: `computeTypeHash()`, `LINEARITY` constants, `buildCellHeader()`, `packCell()`. The DePIN grammar types must be computable by the same hash function.
- `/Users/toddprice/projects/semantos-core/packages/metering/src/channel-fsm.ts` — MFP channel FSM: 8 states, `createChannel()`, `tick()`, `requestClose()`, `settle()`. The ESP32 holds minimal state; the gateway runs the full FSM.
- `/Users/toddprice/projects/semantos-core/packages/metering/src/settlement.ts` — Tick proof format: `TickProof { channelId, tick, cumulativeSatoshis, hmac, timestamp }`. `computeTickProof()` uses `HMAC-SHA256(sharedSecret, "${channelId}:${tick}:${cumulativeSatoshis}")`. Your C implementation must produce identical HMACs.

**Read fourth** (the adapter interfaces your C code mirrors):
- `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/network.ts` — NetworkAdapter interface: `publish()`, `resolve()`, `subscribe()`. The C `network_publish_fn` is the embedded equivalent.
- `/Users/toddprice/projects/semantos-core/packages/protocol-types/src/adapters/stub-network-adapter.ts` — StubNetworkAdapter: in-memory reference. Understand the `PublishableObject` → `NetworkResult` flow.

**Read fifth** (branching policy):
- `/Users/toddprice/projects/semantos-core/docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-33a-depin-grammar-adapters`. Commits as `phase-33a/D33.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. NO STUBS IN ADAPTER IMPLEMENTATIONS

Every adapter function must do real I/O. `storage_read` must actually read from NVS or LittleFS. `identity_resolve` must actually return a cert from flash. `anchor_submit` must actually send a CoAP POST. If a transport dependency isn't available (no OpenThread yet), the function returns `SEMANTOS_ERR_DENIED` with a clear log message — it does not pretend to succeed.

### 2. HMAC MUST MATCH TYPESCRIPT

The C tick proof computation must produce byte-identical HMAC output to `settlement.ts`'s `computeTickProof()`. The message format is `"${channelId}:${tick}:${cumulativeSatoshis}"` encoded as UTF-8, keyed with the 32-byte shared secret. Use mbedTLS `mbedtls_md_hmac()` with `MBEDTLS_MD_SHA256`. Write a test that computes the same proof in both C and TypeScript and compares.

### 3. LINEARITY ASSIGNMENTS ARE SEMANTIC, NOT ARBITRARY

Every type in `DEPIN_TYPES` has a linearity class because of what the type *means*, not for convenience. `depin.sensor.reading` is LINEAR because a sensor reading must be consumed exactly once to prevent double-reporting. `depin.device.cert` is RELEVANT because a device identity is permanent and referenceable. If you can't explain *why* a type has its linearity, you've assigned it wrong.

### 4. TYPE HASHES MUST BE COMPUTABLE BY BOTH TYPESCRIPT AND C

The DePIN type hashes are `SHA256("what.depin.sensor.reading")` etc. The same string hashed with the same algorithm in TypeScript (`computeWhatHash()`) and C (`host_sha256()`) must produce the same 32 bytes. This is the entire bridge between the TypeScript layer and the embedded kernel.

### 5. CELL FORMAT IS 1024 BYTES, NON-NEGOTIABLE

Every cell is exactly 1024 bytes: 256-byte header + 768-byte payload. The header format matches `typeHashRegistry.ts`'s `buildCellHeader()`: magic at offset 0 (16 bytes), linearity at offset 16 (4 bytes LE), typeHash at offset 30 (32 bytes), ownerId at offset 62 (16 bytes), etc. Do not invent a different format for "embedded" cells.

### 6. NO ESP-IDF VERSION ASSUMPTIONS

Use only ESP-IDF v5.x stable APIs. No preview APIs, no deprecated APIs from v4.x. Check `idf_component.yml` for the minimum ESP-IDF version and respect it.

### 7. ADAPTERS ARE SYNCHRONOUS FROM KERNEL PERSPECTIVE

Every adapter callback blocks until it returns. The host can internally spin a FreeRTOS task or wait on an event group, but the callback must return before the kernel continues. This keeps kernel execution deterministic. Do not use `xTaskCreate()` inside an adapter callback without waiting for the result.

### 8. GRAMMAR FOLLOWS EXISTING PATTERN EXACTLY

The DePIN grammar file must follow the exact structure of `paskian/src/grammar.ts`: a `const` object with type paths as keys and `LINEARITY.*` as values, typed as `Record<string, Linearity>` with `as const satisfies`. An `AnchorPolicy` interface. A combined `DepinGrammar` export with `verticalId`, `types`, `anchorPolicy`. No improvisation on the structure.

### 9. TESTS USE REAL OPERATIONS

Gate tests are not mock assertions. T1 verifies the grammar types are registered and hashable. T2 verifies HMAC byte-equality between C and TypeScript. T3 verifies cell creation with DePIN type hashes. Tests that only check `expect().toBeDefined()` are not acceptable.

### 10. DO NOT ADJUST TESTS TO MATCH BROKEN CODE

If a test fails, fix the code, not the test. The test defines the contract.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify prerequisites are complete

```bash
# ESP32 hack-kit exists and has the WASM binary
ls esp32-hackkit/components/semantos/wasm/cell-engine-embedded.wasm
ls esp32-hackkit/components/semantos/include/semantos_adapters.h
ls esp32-hackkit/components/semantos/src/adapters_noop.c

# Paskian grammar exists (pattern reference)
ls packages/paskian/src/grammar.ts

# Metering exists (tick proof reference)
ls packages/metering/src/settlement.ts
ls packages/metering/src/channel-fsm.ts

# Type hash registry exists
ls packages/cell-ops/src/typeHashRegistry.ts

# Protocol-types adapters exist (Phase 26A-D complete)
ls packages/protocol-types/src/identity.ts
ls packages/protocol-types/src/network.ts
ls packages/protocol-types/src/storage.ts
```

All files must exist and not be stubbed. If anything is missing, STOP.

### 0.4 Create Phase 33A branch

```bash
git checkout -b phase-33a-depin-grammar-adapters
```

---

## Step 1: DePIN Vertical Grammar (D33.1)

Create `packages/paskian/src/depin-grammar.ts`.

Follow the exact structure of `grammar.ts`:

```typescript
/**
 * DePIN Vertical Grammar
 *
 * Defines the vertical grammar for DePIN (Decentralised Physical
 * Infrastructure Networks) over the cell model. Each device event
 * type maps to a linearity class; payment channels and provenance
 * records are RELEVANT references; sensor readings and compute
 * tasks are LINEAR (consumed once, paid once).
 *
 * Cross-references:
 *   cell-ops/typeHashRegistry.ts — LINEARITY constants, computeWhatHash()
 *   cell-engine/linearity.zig    — runtime enforcement
 *   metering/channel-fsm.ts      — MFP payment channel FSM
 *   metering/settlement.ts       — tick proof format
 */

import { LINEARITY, type Linearity } from '../../cell-ops/src/typeHashRegistry';
```

Define `DEPIN_SENSOR_TYPES`, `DEPIN_COMPUTE_TYPES`, `DEPIN_NETWORK_TYPES`, `DEPIN_PAYMENT_TYPES` as separate const objects (mirroring `PASKIAN_GRAPH_TYPES` + `PASKIAN_STORY_TYPES` pattern).

Type assignments:

| Type Path | Linearity | Why |
|-----------|-----------|-----|
| `depin.sensor.reading` | LINEAR | One reading, one payment. Consumed on report. Prevents double-counting. |
| `depin.sensor.telemetry` | RELEVANT | Ambient data (temp, humidity). Readable many times. Not payment-gated. |
| `depin.compute.task` | LINEAR | One task, one execution, one payment. |
| `depin.compute.result` | RELEVANT | Result is reference data. Accessible after task completes. |
| `depin.bandwidth.slot` | AFFINE | Use-or-discard. A bandwidth reservation expires if unused. |
| `depin.device.cert` | RELEVANT | Permanent device identity. Never consumed. |
| `depin.payment.channel` | RELEVANT | Open channel state. Referenced until closed. |
| `depin.payment.tick` | LINEAR | Individual tick proof. Consumed on settlement batch. |
| `depin.mesh.relay` | RELEVANT | Provenance record. Referenced for audit trail. |
| `depin.anchor.proof` | RELEVANT | BSV anchor receipt. Permanent reference. |

Define `DEPIN_ANCHOR_POLICY`:
- `requireAnchorOn`: `['linear_consume', 'channel_settle']`
- `complianceEvents`: `['reading_anchored', 'channel_closed', 'device_revoked']`
- `batchInterval`: `600_000` (10 minutes — gateway batches, not per-device)

Export `DepinGrammar` as a `PaskianGrammar`-compatible object with `verticalId: 'depin'`.

Also update `packages/paskian/src/index.ts` to re-export the DePIN grammar.

Verify:
```bash
# Type check passes
bun check
# Grammar types are importable
bun -e "import { DepinGrammar } from './packages/paskian/src/depin-grammar'; console.log(Object.keys(DepinGrammar.types).length)"
# Should print 10
```

Commit: `phase-33a/D33.1: DePIN vertical grammar with linearity assignments and anchor policy`

---

## Step 2: NVS + LittleFS Storage Adapter (D33.5)

Create `esp32-hackkit/components/semantos/src/adapter_storage_nvs.c`.

Implements `semantos_storage_read_fn` and `semantos_storage_write_fn`.

**Routing logic**:
- Keys starting with `ch_` (channel state) or `cert:` (certificates) → NVS namespace `semantos`
- All other keys → LittleFS partition `semantos_fs`

**NVS path**:
```c
#include "nvs_flash.h"
#include "nvs.h"

static nvs_handle_t s_nvs_handle;

int32_t adapter_storage_nvs_read(const char *key, size_t key_len,
                                  uint8_t *out_buf, size_t *inout_len) {
    // Open NVS namespace "semantos" if not already open
    // nvs_get_blob(s_nvs_handle, key, out_buf, inout_len)
    // Return SEMANTOS_OK or SEMANTOS_ERR_BADARG if buffer too small
}
```

**LittleFS path**:
```c
#include "esp_littlefs.h"

int32_t adapter_storage_littlefs_read(const char *key, size_t key_len,
                                       uint8_t *out_buf, size_t *inout_len) {
    // Open file at "/semantos_fs/{key}"
    // fread into out_buf, update *inout_len
    // Return SEMANTOS_OK or SEMANTOS_ERR_DENIED if not found
}
```

**Combined dispatcher**:
```c
int32_t depin_storage_read(const char *key, size_t key_len,
                            uint8_t *out_buf, size_t *inout_len) {
    if (strncmp(key, "ch_", 3) == 0 || strncmp(key, "cert:", 5) == 0) {
        return adapter_storage_nvs_read(key, key_len, out_buf, inout_len);
    }
    return adapter_storage_littlefs_read(key, key_len, out_buf, inout_len);
}
```

Write path follows same routing. Include `depin_storage_init()` that initialises NVS flash and mounts LittleFS.

Create header: `esp32-hackkit/components/semantos/include/depin_adapters.h` with:
```c
int32_t depin_storage_init(void);
int32_t depin_storage_read(const char *key, size_t key_len,
                            uint8_t *out_buf, size_t *inout_len);
int32_t depin_storage_write(const char *key, size_t key_len,
                             const uint8_t *data, size_t data_len);
```

Commit: `phase-33a/D33.5: NVS + LittleFS storage adapter with key-based routing`

---

## Step 3: NVS Identity Adapter (D33.3)

Create `esp32-hackkit/components/semantos/src/adapter_identity_nvs.c`.

Implements `semantos_identity_resolve_fn` and `semantos_identity_derive_fn`.

**Resolve**: reads cert JSON from NVS key `cert:{cert_id_hex}`.

```c
int32_t depin_identity_resolve(const uint8_t *cert_id, size_t cert_id_len,
                                uint8_t *out_json, size_t *inout_len) {
    // Convert cert_id bytes to hex string for NVS key
    // Read blob from NVS namespace "semantos" key "cert:{hex}"
    // Copy JSON into out_json, update *inout_len
    // Return SEMANTOS_ERR_DENIED if cert not found
}
```

**Derive**: uses HKDF-SHA256 (mbedTLS `mbedtls_hkdf()`) to derive a child key from parent cert + resource_id + domain_flag.

```c
int32_t depin_identity_derive(const char *parent_cert, size_t parent_cert_len,
                               const char *resource_id, size_t resource_id_len,
                               uint32_t domain_flag,
                               uint8_t *out_json, size_t *inout_len) {
    // Read parent cert from NVS
    // Extract parent public key from cert JSON
    // HKDF-SHA256(parent_key, resource_id || domain_flag_le32) → child_key
    // Build child cert JSON with derived key, parent reference, domain flag
    // Store child cert in NVS under "cert:{child_cert_id_hex}"
    // Copy child cert JSON into out_json
}
```

**First-boot provisioning**: register a `host_call_by_name` handler for `"cert.provision"` that accepts a cert JSON blob over serial/BLE and stores it in NVS. Document in the header that this must be called once before identity operations work.

Add to `depin_adapters.h`:
```c
int32_t depin_identity_resolve(const uint8_t *cert_id, size_t cert_id_len,
                                uint8_t *out_json, size_t *inout_len);
int32_t depin_identity_derive(const char *parent_cert, size_t parent_cert_len,
                               const char *resource_id, size_t resource_id_len,
                               uint32_t domain_flag,
                               uint8_t *out_json, size_t *inout_len);
int32_t depin_identity_init(void);
```

Commit: `phase-33a/D33.3: NVS identity adapter with HKDF-SHA256 child derivation`

---

## Step 4: CoAP Anchor Adapter (D33.4)

Create `esp32-hackkit/components/semantos/src/adapter_anchor_coap.c`.

Implements `semantos_anchor_submit_fn`.

**Design**: sensor nodes can't reach the internet. They send anchor requests to the border router over CoAP (which in Phase 33B will be OpenThread/6LoWPAN, but for now can be CoAP over WiFi or a loopback test).

```c
#include "coap3/coap.h"

// Border router address — configurable via menuconfig or runtime
static coap_address_t s_gateway_addr;
static coap_context_t *s_coap_ctx;

int32_t depin_anchor_submit(const uint8_t *state_hash, size_t state_hash_len,
                             const char *metadata_json, size_t metadata_len,
                             uint8_t *out_proof, size_t *inout_len) {
    // Build CoAP POST to coap://[gateway]/.well-known/semantos/anchor
    // Payload: CBOR { state_hash: bytes(32), metadata: text }
    // Wait for response (block on FreeRTOS event group, timeout 5s)
    // Response payload: gateway's signed receipt (provisional proof)
    // Copy receipt into out_proof, update *inout_len
    // Return SEMANTOS_OK on 2.01 Created, SEMANTOS_ERR_DENIED on timeout/error
}
```

If CoAP is not available (no network initialised yet), return `SEMANTOS_ERR_DENIED` with `ESP_LOGW("anchor", "no network — anchor deferred")`. The anchor scheduler on the gateway handles retry.

Add `depin_anchor_init(coap_address_t *gateway)` to `depin_adapters.h`.

Commit: `phase-33a/D33.4: CoAP anchor adapter — POST state hash to border router`

---

## Step 5: MFP Channel State on ESP32 (D33.6)

Create `esp32-hackkit/components/semantos/include/depin_channel.h`:

```c
#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char     channel_id[64];       // e.g. "ch_a1b2c3d4e"
    uint32_t current_tick;
    uint32_t cumulative_satoshis;
    uint8_t  shared_secret[32];    // ECDH shared secret with gateway
    char     provider_cert[96];    // device's cert ID string
    char     consumer_cert[96];    // gateway's cert ID string
    uint32_t created_at;           // unix epoch
    uint32_t updated_at;           // unix epoch
} depin_channel_state_t;

typedef struct {
    char     channel_id[64];
    uint32_t tick;
    uint32_t cumulative_satoshis;
    uint8_t  hmac[32];             // HMAC-SHA256 digest
    uint32_t timestamp;            // unix epoch
} depin_tick_proof_t;

/** Initialise a channel (NEGOTIATING state). */
int32_t depin_channel_init(depin_channel_state_t *ch,
                            const char *channel_id,
                            const char *provider_cert,
                            const char *consumer_cert,
                            const uint8_t *shared_secret);

/** Increment tick and compute HMAC proof. */
int32_t depin_channel_tick(depin_channel_state_t *ch,
                            uint32_t satoshis_this_tick,
                            depin_tick_proof_t *out_proof);

/** Serialise channel state to NVS-friendly blob. */
int32_t depin_channel_serialize(const depin_channel_state_t *ch,
                                 uint8_t *out_buf, size_t *inout_len);

/** Deserialise channel state from NVS blob. */
int32_t depin_channel_deserialize(const uint8_t *buf, size_t buf_len,
                                    depin_channel_state_t *out_ch);

#ifdef __cplusplus
}
#endif
```

Create `esp32-hackkit/components/semantos/src/depin_channel.c`:

**Critical**: `depin_channel_tick()` must compute the HMAC identically to `settlement.ts`:

```c
int32_t depin_channel_tick(depin_channel_state_t *ch,
                            uint32_t satoshis_this_tick,
                            depin_tick_proof_t *out_proof) {
    ch->current_tick++;
    ch->cumulative_satoshis += satoshis_this_tick;
    ch->updated_at = (uint32_t)(esp_timer_get_time() / 1000000ULL);

    // Build message: "${channel_id}:${tick}:${cumulative_satoshis}"
    char msg[192];
    int msg_len = snprintf(msg, sizeof(msg), "%s:%u:%u",
                           ch->channel_id, ch->current_tick, ch->cumulative_satoshis);

    // HMAC-SHA256(shared_secret, message)
    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), 1);
    mbedtls_md_hmac_starts(&ctx, ch->shared_secret, 32);
    mbedtls_md_hmac_update(&ctx, (const uint8_t *)msg, msg_len);
    mbedtls_md_hmac_finish(&ctx, out_proof->hmac);
    mbedtls_md_free(&ctx);

    // Fill proof fields
    strncpy(out_proof->channel_id, ch->channel_id, sizeof(out_proof->channel_id));
    out_proof->tick = ch->current_tick;
    out_proof->cumulative_satoshis = ch->cumulative_satoshis;
    out_proof->timestamp = ch->updated_at;

    return 0; // SEMANTOS_OK
}
```

**Serialise/Deserialise**: simple memcpy of the struct to/from a blob. The struct is fixed-size, no pointers. Add a 4-byte magic prefix (`0x4D465000` — "MFP\0") for validation on deserialise.

Commit: `phase-33a/D33.6: MFP channel state on ESP32 with HMAC-SHA256 tick proofs`

---

## Step 6: DePIN Adapter Table + Init (D33.5/D33.3/D33.4 integration)

Create `esp32-hackkit/components/semantos/src/depin_init.c` and `esp32-hackkit/components/semantos/include/depin_init.h`.

This file wires all three adapters into a `semantos_adapter_table_t`:

```c
#include "semantos_adapters.h"
#include "depin_adapters.h"
#include "depin_channel.h"

static const semantos_adapter_table_t depin_adapters = {
    .storage_read     = depin_storage_read,
    .storage_write    = depin_storage_write,
    .identity_resolve = depin_identity_resolve,
    .identity_derive  = depin_identity_derive,
    .anchor_submit    = depin_anchor_submit,
    .network_publish  = NULL,   // Phase 33B (OpenThread)
    .network_resolve  = NULL,   // Phase 33B (OpenThread)
};

/**
 * Initialise all DePIN adapters and return the adapter table.
 *
 * Call this before semantos_init(). It:
 * 1. Initialises NVS flash
 * 2. Mounts LittleFS partition
 * 3. Opens NVS namespace for certs
 * 4. (Optionally) initialises CoAP context for anchor
 *
 * Network adapters are NULL — Phase 33B wires OpenThread.
 */
int32_t depin_init(const semantos_adapter_table_t **out_adapters);
```

Commit: `phase-33a/D33.init: DePIN adapter table wiring storage + identity + anchor`

---

## Step 7: DePIN Hello Sensor Example (D33.9 partial)

Create `esp32-hackkit/examples/depin_sensor/main/main.c`:

This example:
1. Calls `depin_init()` to get the adapter table
2. Boots the cell engine with real adapters
3. Simulates a temperature sensor reading (or reads from GPIO if available)
4. Builds a LINEAR cell with type hash `SHA256("what.depin.sensor.reading")`
5. Packs the cell using the kernel
6. Computes an MFP tick proof via `depin_channel_tick()`
7. Submits the cell's state hash via the anchor adapter
8. Logs the tick proof HMAC over serial

Also create:
- `esp32-hackkit/examples/depin_sensor/CMakeLists.txt`
- `esp32-hackkit/examples/depin_sensor/main/CMakeLists.txt`
- `esp32-hackkit/examples/depin_sensor/main/idf_component.yml`
- `esp32-hackkit/examples/depin_sensor/sdkconfig.defaults`

The `sdkconfig.defaults` should enable:
- `CONFIG_PARTITION_TABLE_CUSTOM=y` (for LittleFS partition)
- `CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ_160=y`
- NVS encryption if targeting production

Follow the `hello_cell` example structure exactly.

Commit: `phase-33a/D33.9: DePIN sensor example — LINEAR reading + MFP tick proof`

---

## Step 8: Gate Tests (T1–T12)

Create `packages/__tests__/phase33a-gate.test.ts`.

### T1–T4: Grammar Tests

```typescript
import { describe, it, expect } from 'bun:test';
import { DepinGrammar, DEPIN_SENSOR_TYPES, DEPIN_PAYMENT_TYPES } from '@semantos/paskian';
import { LINEARITY, computeWhatHash } from '@semantos/cell-ops';

describe('DePIN Grammar (D33.1)', () => {
  it('T1: DepinGrammar exports with correct verticalId', () => {
    expect(DepinGrammar.verticalId).toBe('depin');
    expect(Object.keys(DepinGrammar.types).length).toBe(10);
  });

  it('T2: Sensor reading is LINEAR, device cert is RELEVANT', () => {
    expect(DepinGrammar.types['depin.sensor.reading']).toBe(LINEARITY.LINEAR);
    expect(DepinGrammar.types['depin.device.cert']).toBe(LINEARITY.RELEVANT);
    expect(DepinGrammar.types['depin.bandwidth.slot']).toBe(LINEARITY.AFFINE);
  });

  it('T3: All DePIN type paths produce valid SHA256 hashes', () => {
    for (const typePath of Object.keys(DepinGrammar.types)) {
      const hash = computeWhatHash(typePath);
      expect(hash.length).toBe(32);
      expect(hash).toBeInstanceOf(Buffer);
    }
  });

  it('T4: Anchor policy has gateway-batch interval', () => {
    expect(DepinGrammar.anchorPolicy.batchInterval).toBe(600_000);
    expect(DepinGrammar.anchorPolicy.requireAnchorOn).toContain('linear_consume');
    expect(DepinGrammar.anchorPolicy.requireAnchorOn).toContain('channel_settle');
  });
});
```

### T5–T8: Tick Proof Cross-Platform Parity

```typescript
import { computeTickProof } from '@semantos/metering';

describe('MFP Tick Proof Parity (D33.6)', () => {
  it('T5: TypeScript tick proof has expected HMAC format', async () => {
    const secret = new Uint8Array(32);
    secret.fill(0x42); // deterministic test key

    const proof = await computeTickProof('ch_test123', 1, 100, secret);
    expect(proof.channelId).toBe('ch_test123');
    expect(proof.tick).toBe(1);
    expect(proof.cumulativeSatoshis).toBe(100);
    expect(proof.hmac).toMatch(/^[0-9a-f]{64}$/);
  });

  it('T6: Tick proof HMAC is deterministic', async () => {
    const secret = new Uint8Array(32);
    secret.fill(0xAA);

    const proof1 = await computeTickProof('ch_abc', 5, 500, secret);
    const proof2 = await computeTickProof('ch_abc', 5, 500, secret);
    expect(proof1.hmac).toBe(proof2.hmac);
  });

  it('T7: Different secrets produce different HMACs', async () => {
    const secret1 = new Uint8Array(32).fill(0x01);
    const secret2 = new Uint8Array(32).fill(0x02);

    const proof1 = await computeTickProof('ch_abc', 1, 100, secret1);
    const proof2 = await computeTickProof('ch_abc', 1, 100, secret2);
    expect(proof1.hmac).not.toBe(proof2.hmac);
  });

  it('T8: Tick proof message format matches C implementation spec', async () => {
    // The C code builds: "${channel_id}:${tick}:${cumulative_satoshis}"
    // Verify TypeScript uses the same format
    const secret = new Uint8Array(32).fill(0x42);
    const proof = await computeTickProof('ch_test', 3, 750, secret);

    // Manually compute expected HMAC using the same message format
    const { createHmac } = await import('crypto');
    const hmac = createHmac('sha256', Buffer.from(secret))
      .update('ch_test:3:750')
      .digest('hex');

    expect(proof.hmac).toBe(hmac);
  });
});
```

### T9–T10: Cell Construction with DePIN Types

```typescript
import { buildCellHeader, packCell, computeWhatHash, LINEARITY } from '@semantos/cell-ops';

describe('DePIN Cell Construction (D33.1 + cell-ops)', () => {
  it('T9: Can build a LINEAR cell with depin.sensor.reading type hash', () => {
    const typeHash = computeWhatHash('depin.sensor.reading');
    const ownerId = Buffer.alloc(16, 0x01);

    const header = buildCellHeader({
      typeHash,
      linearity: LINEARITY.LINEAR,
      ownerId,
      phase: 'action',
      dimension: 'what',
      payloadSize: 64,
    });

    expect(header.length).toBe(256);
    // Verify linearity field at offset 16
    expect(header.readUInt32LE(16)).toBe(LINEARITY.LINEAR);
    // Verify type hash at offset 30
    expect(header.subarray(30, 62).equals(typeHash)).toBe(true);
  });

  it('T10: Packed cell is exactly 1024 bytes', () => {
    const typeHash = computeWhatHash('depin.sensor.reading');
    const ownerId = Buffer.alloc(16, 0x01);
    const payload = Buffer.from(JSON.stringify({
      temperature: 22.5,
      humidity: 65,
      timestamp: Date.now(),
      device: 'esp32-h2-001',
    }));

    const header = buildCellHeader({
      typeHash,
      linearity: LINEARITY.LINEAR,
      ownerId,
      phase: 'action',
      dimension: 'what',
      payloadSize: payload.length,
    });

    const cell = packCell(header, payload);
    expect(cell.length).toBe(1024);
  });
});
```

### T11–T12: File Structure Validation

```typescript
import { existsSync } from 'fs';
import { resolve } from 'path';

describe('Phase 33A file structure', () => {
  const root = '/Users/toddprice/projects/semantos-core';

  it('T11: All deliverable files exist', () => {
    const files = [
      'packages/paskian/src/depin-grammar.ts',
      'esp32-hackkit/components/semantos/src/adapter_storage_nvs.c',
      'esp32-hackkit/components/semantos/src/adapter_identity_nvs.c',
      'esp32-hackkit/components/semantos/src/adapter_anchor_coap.c',
      'esp32-hackkit/components/semantos/src/depin_channel.c',
      'esp32-hackkit/components/semantos/src/depin_init.c',
      'esp32-hackkit/components/semantos/include/depin_adapters.h',
      'esp32-hackkit/components/semantos/include/depin_channel.h',
      'esp32-hackkit/components/semantos/include/depin_init.h',
      'esp32-hackkit/examples/depin_sensor/main/main.c',
    ];

    for (const file of files) {
      expect(existsSync(resolve(root, file))).toBe(true);
    }
  });

  it('T12: No adapters_noop.c functions used in depin_init.c', async () => {
    const fs = await import('fs/promises');
    const content = await fs.readFile(
      resolve(root, 'esp32-hackkit/components/semantos/src/depin_init.c'),
      'utf8',
    );
    expect(content).not.toContain('noop');
    expect(content).not.toContain('NOOP');
    expect(content).toContain('depin_storage_read');
    expect(content).toContain('depin_identity_resolve');
    expect(content).toContain('depin_anchor_submit');
  });
});
```

Run all tests:
```bash
bun test packages/__tests__/phase33a-gate.test.ts
```

Commit: `phase-33a/T1-T12: full gate test suite — grammar, tick proof parity, cell construction, file structure`

---

## Step 9: Type Check and Build

```bash
bun check
bun run build
```

Fix any errors. Do NOT ignore type errors.

Commit (if changes needed): `phase-33a/fix: [description of fix]`

---

## Step 10: Errata Sprint

After all tests pass, review for mutations not caught by tests:

1. **HMAC byte order**: verify the C `snprintf` format string matches the TypeScript template literal exactly. Edge case: what happens when `cumulative_satoshis` exceeds `UINT32_MAX`? (Answer: it shouldn't in practice, but document the limit.)
2. **NVS key length limit**: ESP-IDF NVS keys are max 15 characters. Verify cert IDs are truncated or hashed to fit. If cert IDs exceed 15 chars, use `SHA256(cert_id)[0:15]` as the NVS key.
3. **LittleFS partition size**: verify the partition table allocates enough space for the cell buffer ring. Minimum 64 KB for a useful buffer.
4. **CoAP timeout**: verify the anchor adapter doesn't block the kernel for more than 5 seconds. Use `xEventGroupWaitBits()` with timeout.
5. **Grammar type hash collision**: verify no two DePIN type paths produce the same SHA256 hash (they won't, but test it explicitly).
6. **Linearity semantic review**: re-read each type's linearity assignment and verify the "why" column in the master PRD still holds. Flag any that feel wrong.
7. **Cell header ownerId**: verify the 16-byte ownerId in DePIN cells is derived from the device's Plexus cert, not hardcoded.

---

## Completion Criteria

- [ ] `packages/paskian/src/depin-grammar.ts` exists with 10 DePIN types, correct linearities, anchor policy
- [ ] `packages/paskian/src/index.ts` re-exports `DepinGrammar`
- [ ] `esp32-hackkit/components/semantos/src/adapter_storage_nvs.c` — real NVS + LittleFS storage
- [ ] `esp32-hackkit/components/semantos/src/adapter_identity_nvs.c` — real NVS cert store + HKDF derivation
- [ ] `esp32-hackkit/components/semantos/src/adapter_anchor_coap.c` — real CoAP POST to gateway
- [ ] `esp32-hackkit/components/semantos/src/depin_channel.c` — MFP channel state + HMAC tick proofs
- [ ] `esp32-hackkit/components/semantos/src/depin_init.c` — adapter table wiring
- [ ] `esp32-hackkit/components/semantos/include/depin_adapters.h` — all adapter function declarations
- [ ] `esp32-hackkit/components/semantos/include/depin_channel.h` — channel state + tick proof types
- [ ] `esp32-hackkit/components/semantos/include/depin_init.h` — init function declaration
- [ ] `esp32-hackkit/examples/depin_sensor/` — complete example with CMakeLists, main.c, sdkconfig.defaults
- [ ] Tests T1–T12 all pass
- [ ] `bun check` produces zero TypeScript errors
- [ ] `bun run build` succeeds
- [ ] HMAC parity verified: TypeScript `computeTickProof()` and C `depin_channel_tick()` produce identical output for same inputs
- [ ] All commits follow `phase-33a/D33.N:` naming convention
- [ ] Branch is `phase-33a-depin-grammar-adapters`

---

## Next Phase

**Phase 33B**: OpenThread/6LoWPAN Network Adapter + Mesh Relay. Implements `semantos_network_publish_fn` and `semantos_network_resolve_fn` using ESP-IDF's OpenThread component with CoAP over 6LoWPAN. Adds mesh relay provenance DAG (`depin_relay.c`). Adds border router gateway (TypeScript, `packages/depin-gateway/`). Requires ESP32-H2 or ESP32-C6 hardware with IEEE 802.15.4 radio.
