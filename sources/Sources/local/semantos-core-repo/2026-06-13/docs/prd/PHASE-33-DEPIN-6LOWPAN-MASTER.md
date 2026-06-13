---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-33-DEPIN-6LOWPAN-MASTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.700925+00:00
---

# Phase 33 — DePIN 6LoWPAN Mesh on ESP32

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 2–3 days (concentrated sprint)
**Prerequisites**: Phase 26A–26D complete (four adapter interfaces), esp32-hackkit functional
**Branch**: `phase-33-depin-6lowpan`

---

## Context

The ESP32 hack-kit (`esp32-hackkit/`) ships a 29 KB WASM cell engine with the full 2-PDA, linearity enforcement, Plexus opcodes, and four adapter callbacks (Storage, Identity, Anchor, Network) — all stubbed with no-ops. The `hello_cell` example proves the engine boots and executes Bitcoin Script on-device.

Phase 33 wires these adapters to real hardware for a DePIN (Decentralised Physical Infrastructure Network) use case: ESP32-H2 or ESP32-C6 devices with native IEEE 802.15.4 forming a 6LoWPAN mesh via OpenThread. Each device is a Semantos cell engine that creates LINEAR sensor readings, gets paid via MFP micropayment channels, and routes cells through the mesh to a border-router gateway that settles to BSV mainnet.

### The DePIN Problem (What This Solves)

Existing DePIN protocols (Helium, Hivemapper, DIMO) rely on device-signed assertions: the device says "I did X" and the network trusts it. There's no cryptographic proof that X happened once, no prevention of double-reporting, and no trustless payment without an inflationary reward token.

Semantos solves all four:

| Problem | Semantos Mechanism |
|---------|-------------------|
| Proof it happened | BSV anchor, permanent txid |
| No double-reporting | LINEAR cell, consumed exactly once |
| Trustless payment | MFP payment channel per service unit |
| Device identity | Plexus cert on the ESP32 |

### Architecture

```
ESP32-H2 mesh (6LoWPAN / OpenThread)
  — compressed IPv6 over IEEE 802.15.4
  — devices 10-100 meters apart
  — each node runs 29 KB cell engine WASM
  — Plexus cert in flash (NVS)
  — MFP channel state in SRAM

Each service event:
  sensor reading → LINEAR cell created
  → cell published to mesh via CoAP
  → relay nodes append RELEVANT provenance refs
  → border router receives cell
  → MFP tick increments cumulative satoshis
  → BSV settles when channel closes

                    ┌──────────────────┐
                    │  BSV Mainnet     │
                    │  (settlement)    │
                    └────────▲─────────┘
                             │ anchor + settle
                    ┌────────┴─────────┐
                    │  Border Router   │
                    │  (gateway node)  │
                    │  WiFi + 802.15.4 │
                    └────────▲─────────┘
                             │ 6LoWPAN mesh
              ┌──────────────┼──────────────┐
              │              │              │
        ┌─────┴─────┐ ┌─────┴─────┐ ┌─────┴─────┐
        │ ESP32-H2  │ │ ESP32-H2  │ │ ESP32-H2  │
        │ sensor    │ │ relay     │ │ sensor    │
        │ + cell    │ │ node      │ │ + cell    │
        │ engine    │ │           │ │ engine    │
        └───────────┘ └───────────┘ └───────────┘
```

---

## The Four Adapter Implementations

### 1. Storage → NVS + LittleFS

- **NVS**: Plexus cert root, MFP channel state (small, hot-path)
- **LittleFS**: Cell buffer ring (pending cells awaiting mesh relay), anchor proof cache

### 2. Identity → Flash Cert Store

- Device cert provisioned at first boot via BLE or serial
- Stored in encrypted NVS partition
- `identity_resolve()` returns cert JSON from NVS
- `identity_derive()` derives child cert for resource-specific signing (sensor-class keys)
- Uses ESP32 eFuse key as hardware root of trust

### 3. Anchor → CoAP POST to Border Router

- Sensor nodes don't anchor directly to BSV — they can't reach the internet
- `anchor_submit()` sends a CoAP POST carrying the 32-byte state hash to the border router's well-known URI
- Border router batches anchors using `anchor-scheduler.ts` logic (10-min interval)
- Returns a provisional proof (border router's signed receipt) immediately
- Final BSV merkle proof backfills when the border router settles

### 4. Network → OpenThread CoAP over 6LoWPAN

- `network_publish()` serialises cell as CBOR, sends CoAP POST to mesh multicast group `ff03::1` (realm-local)
- `network_resolve()` sends CoAP GET to border router's lookup URI with semantic path as query
- Relay nodes: receive published cells, append RELEVANT provenance reference (own cert + timestamp), re-publish
- Border router subscribes to the multicast group, accumulates cells, forwards to BSV overlay

---

## DePIN Vertical Grammar

New vertical grammar following the `paskian/src/grammar.ts` pattern:

```typescript
export const DEPIN_TYPES = {
  // Sensor readings — consumed once, one payment per reading
  'depin.sensor.reading':         LINEARITY.LINEAR,
  // Temperature/humidity/pressure — reference data, read many times
  'depin.sensor.telemetry':       LINEARITY.RELEVANT,
  // Compute task — done once, paid once
  'depin.compute.task':           LINEARITY.LINEAR,
  // Compute result — reference data
  'depin.compute.result':         LINEARITY.RELEVANT,
  // Bandwidth slot — used up, not repeatable
  'depin.bandwidth.slot':         LINEARITY.AFFINE,
  // Device certificate — permanent identity
  'depin.device.cert':            LINEARITY.RELEVANT,
  // Payment channel — open until closed
  'depin.payment.channel':        LINEARITY.RELEVANT,
  // Payment tick — consumed on settlement
  'depin.payment.tick':           LINEARITY.LINEAR,
  // Mesh relay event — provenance record, referenceable
  'depin.mesh.relay':             LINEARITY.RELEVANT,
  // Anchor proof — permanent, referenceable
  'depin.anchor.proof':           LINEARITY.RELEVANT,
} as const;
```

### Anchor Policy

```typescript
export const DEPIN_ANCHOR_POLICY: AnchorPolicy = {
  requireAnchorOn: ['linear_consume', 'channel_settle'],
  complianceEvents: ['reading_anchored', 'channel_closed', 'device_revoked'],
  batchInterval: 600_000, // 10 minutes — gateway batches
};
```

---

## MFP Payment on ESP32

The MFP payment channel FSM (`metering/src/channel-fsm.ts`) runs on the border router (TypeScript). The ESP32 device holds minimal channel state:

```c
typedef struct {
    char     channel_id[64];
    uint32_t current_tick;
    uint32_t cumulative_satoshis;
    uint8_t  shared_secret[32];   // ECDH shared secret with gateway
    uint8_t  provider_cert[64];   // device's cert ID
    uint8_t  consumer_cert[64];   // gateway's cert ID
} depin_channel_state_t;
```

On each sensor reading:
1. Device creates LINEAR cell with reading payload
2. Device increments `current_tick` and `cumulative_satoshis`
3. Device computes HMAC-SHA256 tick proof: `HMAC(shared_secret, channel_id:tick:cumulative)`
4. Tick proof attached to cell metadata
5. Cell published to mesh via CoAP
6. Gateway receives cell, validates tick proof, updates its FSM state
7. Gateway closes channel and settles to BSV at configured interval

---

## Mesh Provenance DAG

The novel contribution: relay nodes in the mesh append RELEVANT cells to the routing path. When a reading reaches the gateway, the DAG contains:

```
sensor_reading (LINEAR, device A cert)
  ├─ relay_event (RELEVANT, device B cert, timestamp T1)
  │   └─ relay_event (RELEVANT, device C cert, timestamp T2)
  │       └─ gateway_receipt (RELEVANT, gateway cert, timestamp T3)
  └─ anchor_proof (RELEVANT, BSV txid, block height)
```

Each relay event references the cell it relayed (by content hash) and the relaying device's cert. This gives cryptographic provenance for the physical path a reading took through the mesh.

Use case: pharmaceutical cold chain — a temperature reading has a verifiable chain from the sensor on the pallet, through the warehouse relay nodes, to the logistics gateway, to the BSV ledger.

---

## Deliverables

### D33.1 — DePIN Vertical Grammar (TypeScript)

New file: `packages/paskian/src/depin-grammar.ts`

- `DEPIN_TYPES` with linearity assignments
- `DEPIN_ANCHOR_POLICY` with gateway-batch semantics
- `DepinGrammar` exported following `PaskianStoryGrammar` pattern
- Type hashes registered in `cell-ops/src/typeHashRegistry.ts`

### D33.2 — OpenThread Network Adapter (C, ESP32)

New file: `esp32-hackkit/components/semantos/src/adapter_network_openthread.c`

- Implements `semantos_network_publish_fn` and `semantos_network_resolve_fn`
- CoAP POST to realm-local multicast for publish
- CoAP GET to border router for resolve
- CBOR serialisation of cell JSON (compact, <256 bytes per message)
- Depends on ESP-IDF `openthread` and `coap` components

### D33.3 — NVS Identity Adapter (C, ESP32)

New file: `esp32-hackkit/components/semantos/src/adapter_identity_nvs.c`

- Implements `semantos_identity_resolve_fn` and `semantos_identity_derive_fn`
- Reads device cert from encrypted NVS partition `plexus_certs`
- Derives child certs using HKDF-SHA256 (from mbedTLS, already linked)
- First-boot provisioning via `host_call_by_name("cert.provision")`

### D33.4 — CoAP Anchor Adapter (C, ESP32)

New file: `esp32-hackkit/components/semantos/src/adapter_anchor_coap.c`

- Implements `semantos_anchor_submit_fn`
- CoAP POST to border router's `/.well-known/semantos/anchor` URI
- Carries 32-byte state hash + metadata JSON
- Returns gateway's signed receipt as provisional proof
- Non-blocking: uses FreeRTOS event group to wait on CoAP response

### D33.5 — NVS + LittleFS Storage Adapter (C, ESP32)

New file: `esp32-hackkit/components/semantos/src/adapter_storage_nvs.c`

- Implements `semantos_storage_read_fn` and `semantos_storage_write_fn`
- Keys starting with `ch_` or `cert:` → NVS (small, fast)
- Everything else → LittleFS partition (cell buffer ring)
- Buffer ring: circular overwrite of oldest cells when partition full

### D33.6 — MFP Channel State (C, ESP32)

New file: `esp32-hackkit/components/semantos/src/depin_channel.c`
New header: `esp32-hackkit/components/semantos/include/depin_channel.h`

- `depin_channel_state_t` struct with tick, cumulative, shared secret
- `depin_channel_init()` — negotiate with gateway over CoAP
- `depin_channel_tick()` — increment + HMAC computation using `host_sha256`
- `depin_channel_serialize()` / `depin_channel_deserialize()` — NVS persistence
- Tick proof format matches `settlement.ts` TickProof exactly

### D33.7 — Mesh Relay + Provenance DAG (C, ESP32)

New file: `esp32-hackkit/components/semantos/src/depin_relay.c`
New header: `esp32-hackkit/components/semantos/include/depin_relay.h`

- `depin_relay_handler()` — callback for received CoAP multicast cells
- On receive: validate cell magic, check not own cert, append RELEVANT relay cell
- Relay cell payload: `{ relayer_cert, relayed_content_hash, timestamp, hop_count }`
- Re-publish to mesh with relay cell appended to provenance chain
- Max hop count (configurable, default 8) prevents infinite relay

### D33.8 — Border Router Gateway (TypeScript)

New file: `packages/depin-gateway/src/gateway.ts`

- CoAP server receiving cells from mesh
- Validates LINEAR cell consumption (cell not already consumed)
- Validates MFP tick proofs against shared secret
- Updates MFP channel FSM (reuses `metering/src/channel-fsm.ts`)
- Batches anchor submissions (reuses `protocol-types/src/anchor-scheduler.ts`)
- Settles channels at configurable interval
- Stores provenance DAG for audit

### D33.9 — DePIN Hello World Example

New directory: `esp32-hackkit/examples/depin_sensor/`

- Boots cell engine with all four real adapters wired
- Reads temperature from GPIO (or simulated)
- Creates LINEAR `depin.sensor.reading` cell
- Publishes to mesh via OpenThread CoAP
- Computes MFP tick proof
- Logs result over serial
- Pairs with a border router example (TypeScript, runs on Pi or laptop)

---

## Phase Decomposition (Optional)

If you prefer sub-phases instead of one sprint:

```
Phase 33A: D33.1 + D33.5 + D33.3          (grammar + storage + identity)
Phase 33B: D33.2 + D33.4                   (network + anchor — needs OpenThread)
Phase 33C: D33.6 + D33.7                   (payment + relay)
Phase 33D: D33.8 + D33.9                   (gateway + example)
```

33A and 33B can run in parallel. 33C needs 33B (CoAP transport). 33D needs all three.

---

## Hardware Requirements

| Board | Why |
|-------|-----|
| **ESP32-H2** (preferred) | Native IEEE 802.15.4, Thread-certified, RISC-V, 320 KB SRAM |
| **ESP32-C6** (alternative) | WiFi + 802.15.4 combo, can serve as border router |
| **ESP32-S3** (gateway only) | WiFi + BLE, more RAM, no 802.15.4 — needs C6/H2 for mesh |

Minimum mesh: 2× ESP32-H2 (sensor nodes) + 1× ESP32-C6 (border router with WiFi uplink).

---

## Commercial Context

No Helium-style token. No inflationary reward mechanism. Device owners earn BSV micropayments for every verified service event. The LINEAR cell is the receipt. The MFP channel is the running tab. The gateway closes and settles.

Revenue model:
- **Device owners**: earn BSV per verified reading
- **Gateway operators**: earn margin on settlement batches (same model as Plexus Node)
- **Platform**: extension marketplace — DePIN vertical grammar ($29-$79), cold chain compliance module, agricultural sensor pack

This directly extends the commercial model in `COMMERCIAL-CONTEXT.md`: the DePIN vertical is an extension that loads via `semantos install extension depin`, uses the same kernel, same adapters, same MFP channels.

---

## Next Phase

Phase 33E (future): DePIN vertical extensions — cold chain compliance (pharmaceutical), agricultural sensor network, smart city infrastructure. Each is a grammar extension + sensor-specific `host_call_by_name` entries + industry-specific anchor policies.
