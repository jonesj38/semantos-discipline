---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/PIGGYBANK-BUILD-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.334397+00:00
---

# BitPiggy Build Plan — 3× XIAO ESP32-C6 + iPad (BSVA Browser)

Status: draft v2 — for Todd's review before any new code is written.
Last updated: 2026-04-20.

## 0. What we're building

Three XIAO ESP32-C6 boards become kid-sized chore-manager + piggy-bank
units. An iPad (or any device running the BSVA mobile browser) loads
**BitPiggy**, a PWA that the parents use to assign chores, approve/reject
claims, and release pocket-money payments in BSV from their existing BSVA
wallet.

Each kid has their own Plexus-recoverable identity. All day-to-day traffic
is LAN-only (mDNS + HTTP with BRC-100-signed payloads). A small local
header relay on an always-on box (Pi / Mac / NAS) fans out block headers
so the kid devices never touch the public internet.

## 1. What already exists — do not rewrite

The workspace already has the hard parts done:

| Package / file                                        | What it gives us                                                                                                                                         |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apps/piggybank/src/*.ts`                             | Every message type (`ChoreTemplate`, `ChoreClaim`, `BonusQuest`, `DeviceProfile`, `DeviceConfig`, `DeviceToAppSync`, `AppToDeviceSync`, `SpendRequest`, `PaymentQrData`, `SyncTransport`, `PiggyBankServiceRecord`). |
| `apps/piggybank/src/domain.ts`                        | Domain flags: `PIGGYBANK`, `CHORE_SIGNING`, `PAYMENT_RECEIPT`, `CHORE_DEFINITION`, `FAMILY_SYNC`, `SPENDING_AUTH`.                                        |
| `core/plexus-contracts`                               | `PlexusCert`, `CertificatePreimage`, `RecoverySession`, `ChallengeSpec`, BRC-100/BRC-52 header names.                                                     |
| `core/plexus-vendor-sdk`                              | `VendorSDK` — `registerIdentity`, `deriveChild` (BRC-42), `initiateRecovery`, `submitChallengeAnswers`, `createEdge`.                                     |
| `extensions/recovery`                                 | Challenge-set builder + export-payload assembly.                                                                                                          |
| `esp32-hackkit/examples/piggybank/main/piggybank.h`   | Full C-struct mirror of the TS types, domain-flag `#defines`, error codes, PIN-state layout, storage tuning.                                              |
| `esp32-hackkit/examples/piggybank/main/main.c`        | ESP32 firmware skeleton (boot → NVS init → provisioning wait → PIN entry → main menu). Targets **ESP32-S3** with **3 buttons (UP/DOWN/CONFIRM)**.         |
| `esp32-hackkit/components/semantos/*`                 | WASM cell-engine + mbedTLS crypto imports + adapter scaffolding (storage/identity/anchor/network).                                                        |

This is why I keep emphasising "don't rewrite it" — the chore protocol,
the sync transport contract, the Plexus recovery flow, and the firmware
boot sequence are already there. The new work is narrow.

## 2. Delta vs what exists

The existing firmware skeleton was written for **ESP32-S3 with 3 buttons**.
Todd has **XIAO ESP32-C6 × 3, no peripherals yet**. The two differences
that matter:

1. **Chip family change (S3 → C6).** Both are supported by ESP-IDF 5.x;
   `set-target esp32c6` should Just Work. The XIAO-C6 has no PSRAM, so we
   need to watch heap usage — the skeleton already uses stack buffers and
   short heap strings, so we're likely fine. The Semantos WASM blob runs
   in wasm3, which fits in ~64 KB code and doesn't need PSRAM.
2. **Button count 3 → 5.** The skeleton enumerates `BTN_EVT_UP`,
   `BTN_EVT_DOWN`, `BTN_EVT_CONFIRM`, `BTN_EVT_CONFIRM_LONG`. We need
   `BTN_EVT_MENU` and `BTN_EVT_BACK` as well, plus the GPIO constants
   below.

Everything else in the skeleton — NVS, provisioning state machine, UI
screen enum — stays as is.

## 3. Hardware spec (XIAO ESP32-C6 × 3)

### Per unit

- 1 × Seeed XIAO ESP32-C6 (you have these).
- 1 × 1.3" SH1106 I²C OLED (128 × 64, monochrome). Picked for:
  - Only 4 wires, leaves 9 GPIOs free.
  - Readable from across a kid's desk.
  - ~US$5.
  - If you want colour later, drop in a 0.96" ST7735 TFT (SPI) — footprint
    is the same on most breakout PCBs and the firmware driver swap is
    one `#ifdef`.
- 5 × tactile push-buttons (6 × 6 × 6 mm).
- 1 × small perfboard OR XIAO-shaped breakout (30 × 60 mm).
- Optional: 1 × 500 mAh 3.7 V LiPo + JST — makes the piggy bank portable.
- Optional: 1 × piezo buzzer for the "cha-ching!" reward sound.
- 1 × 3D-printed enclosure (I'll publish an STL).

### Button layout

```
  [ MENU ]   [ ▲ ]   [ ✓ DONE ]   [ ▼ ]   [ BACK ]
```

Navigation rules:
- `▲` / `▼` → cursor up/down in lists.
- `✓ DONE` → select / confirm / "I did this chore" on the chore row.
- `MENU` → from any screen, jump to main menu (Balance / Chores / Goals /
  Settings).
- `BACK` → up one level / cancel.
- `DONE held > 1 s` → already supported as `BTN_EVT_CONFIRM_LONG`; we'll
  use it for "I really mean it" confirmations (spend, unlock).

### XIAO-C6 pin map

| XIAO pin | Signal                | Notes                                  |
| -------- | --------------------- | -------------------------------------- |
| D0       | BUTTON_MENU           | INPUT_PULLUP, active-low               |
| D1       | BUTTON_UP             | INPUT_PULLUP, active-low               |
| D2       | BUTTON_SELECT (DONE)  | INPUT_PULLUP, active-low               |
| D3       | BUTTON_DOWN           | INPUT_PULLUP, active-low               |
| D4       | I²C SDA               | to OLED                                |
| D5       | I²C SCL               | to OLED                                |
| D6       | BUTTON_BACK           | INPUT_PULLUP, active-low               |
| D7       | BUZZER (optional)     | PWM                                    |
| D8–D10   | reserved              | future: LED, accelerometer, batt-mon   |

## 4. Plexus identity tree — one root per kid

Each kid gets their own root identity, so recovery is per-kid, not
per-family:

```
Parent root (Todd)
  ├─ family/PAYMENT_RECEIPT:*     ← parent's BSVA-browser wallet pays from here
  ├─ family/CHORE_DEFINITION:*    ← signs new ChoreTemplates
  └─ family/FAMILY_SYNC:*         ← signs AppToDeviceSync payloads

Kid root (e.g. mia@family.local)
  ├─ device/PIGGYBANK:0           ← device identity (DeviceProfile.deviceCertId)
  ├─ chores/CHORE_SIGNING:*       ← kid signs ChoreClaims
  ├─ receive/PAYMENT_RECEIPT:0..N ← P2PKH receive addrs for pocket money
  ├─ sync/FAMILY_SYNC:*           ← kid signs DeviceToAppSync payloads
  └─ spend/SPENDING_AUTH:*        ← kid signs outbound SpendRequests
```

No new crypto — just call `VendorSDK.registerIdentity(email)` then
`VendorSDK.deriveChild(parentCertId, resourceId, domainFlag)` with the
right flags.

### Recovery model

For each kid, the parent sets up (on the iPad, one time):

1. `VendorSDK.registerIdentity(kidEmail)` — mints the root.
2. `VendorSDK.initiateRecovery(kidEmail)` — returns a `RecoverySession`
   with 4 challenge questions. We'll override the stub's defaults with
   kid-appropriate questions: first teddy bear name, best friend at
   kindy, name of first pet, favourite colour.
3. The PWA then prints a "recovery card" with the email + the session-ID
   barcode. Seal in an envelope, put in the safe.

If an ESP32 is lost or wiped:
1. Parent scans the recovery card.
2. PWA calls `VendorSDK.submitChallengeAnswers(sessionId, answers)`.
3. On verified, the root key is re-derived from the same email + salt,
   so every domain-flagged child key comes back byte-for-byte identical.
4. Re-run the USB-C provisioning flow to push the re-derived keys into
   the replacement ESP32.

## 5. Parent app — "BitPiggy" PWA in the BSVA browser

Todd answered: "discover bitpiggy" — i.e. the PWA will be browsable in
whatever "installed apps" list the BSVA browser presents. That means
**the PWA is hosted at a stable HTTPS URL** (e.g. `https://bitpiggy.local`
with a local trust root, or a public URL like `https://bitpiggy.family`
that only serves the HTML/JS — all data traffic still goes to the LAN
ESP32s from the user's browser).

### Stack

- React + Vite + Tailwind, workspace package `apps/piggybank-parent`.
- Imports `@semantos/piggybank` types directly (no copy-paste between
  client and device).
- TanStack Query for sync polling.
- Uses `window.CWI` (BRC-100) inside the BSVA browser's WebView for:
  - Parent's identity + signing `AppToDeviceSync` payloads.
  - `createAction({ outputs: [...] })` to pay approved claims.
  - Broadcasting + receiving BEEF envelopes.

### Why PWA (not Flutter / Swift)

Todd mentioned having Flutter + Swift targets for the WASM kernel. Those
remain available if we later want a native version — the piggybank types
are already transport-agnostic JSON, so a Flutter or Swift front-end can
be added without touching the firmware or the protocol. For v1 we stick
with the PWA because:
- BSVA browser is the path of least friction for BSV payments.
- No App Store / TestFlight dance.
- Same codebase works on the iPad, a parent's phone, and a laptop.

### Device discovery

The PWA asks the BSVA browser for a list of `_bitpiggy._tcp` mDNS records
(if the browser exposes that API). Fallback: sequentially probe
`http://<kidname>-piggybank.local/whoami` for a small list of known
names. Whatever answers 200 with a valid `PiggyBankServiceRecord` is a
kid device.

### Main screens

1. **Kids** — list of devices, online/offline, balance, pending claims.
2. **Chore board** — per kid, drag-to-assign chore templates, with
   reward + schedule + streak rules.
3. **Claims inbox** — every `ChoreClaim` with `status=PENDING`. One tap
   approves + triggers a BSV payment, one tap rejects with reason.
4. **Payments** — ledger of sent rewards, pending broadcasts,
   confirmations.
5. **Bonus quests** — create/expire `BonusQuest`s.
6. **Recovery** — set up challenge questions, print recovery card.
7. **Settings** — per-device `DeviceConfig` (spending limits, WiFi,
   brightness, auto-lock).

## 6. LAN protocol (unchanged from sync.ts)

Every device exposes:

```
POST /sync/pull  → DeviceToAppSync          (requires parent BRC-100 sig)
POST /sync/push  ← AppToDeviceSync          (requires parent BRC-100 sig)
GET  /whoami     → PiggyBankServiceRecord
GET  /qr?sats=N  → SVG of a BIP21 URI (encodePaymentUri())
```

Auth: BRC-100 headers (`BRC100_HEADER_IDENTITY_KEY`, `_NONCE`,
`_TIMESTAMP`, `_SIGNATURE`). Device rejects anything not signed by a
`FAMILY_SYNC`-derived key under the parent cert it was provisioned with.

Reward-payment flow:

1. PWA approves a `ChoreClaim`.
2. PWA calls `window.CWI.createAction({ outputs: [{ satoshis: claim.effectiveRewardSats, lockingScript: p2pkh(kid.receiveAddressN) }] })`.
3. BSVA wallet signs + broadcasts; BEEF comes back.
4. PWA wraps it as `ApprovedClaim` inside an `AppToDeviceSync` → POSTs
   `/sync/push`.
5. Device verifies the BEEF against its local header chain, stores the
   UTXO, updates balance + streak.
6. Next `/sync/pull` returns `acknowledgedPayments: [claim.resourceId]`.

## 7. Local header relay

**Goal**: the three XIAO-C6s never touch the public internet. A tiny
relay on an always-on home box proxies block headers (and nothing else).

### Host options, cheapest → nicest

1. **Raspberry Pi Zero 2 W** (~US$15) — plenty for a header relay,
   fanless, 24/7. Recommended.
2. **A Mac mini / the iMac / whatever's always on** — runs the relay as
   a launchd service.
3. **Synology / TrueNAS Docker add-on** — if you already run a NAS.

### What the relay does

- New workspace package `apps/header-relay` (Bun / Node, tiny).
- On startup, fetches headers from WhatsOnChain (or your preferred
  source) and stores them in a flat file (80 bytes per header).
- Exposes:
  ```
  GET /headers?from=<height>&count=<N>  → concatenated 80-byte headers
  GET /tip                              → { height, hash }
  ```
- Advertises itself on mDNS as `_bitpiggy-headers._tcp`.
- Updates once per minute.

### What changes on the firmware side

`DeviceConfig.headerSyncUrl` (already defined) gets set during
provisioning to `http://bitpiggy-headers.local/headers`. The device
polls on its own schedule and appends new headers to `HeaderChainState`.

### What changes on the PWA side

Nothing required — the PWA still talks directly to each device. But the
PWA will also hit `/tip` so it can show the user a "fresh as of 2 min
ago" indicator.

## 8. Name: **BitPiggy**

Todd landed on this — applies to:
- PWA bundle ID / title.
- mDNS service type (`_bitpiggy._tcp`) — overrides the earlier
  `_piggybank._tcp` in sync.ts comments (but the types stay, they're
  just labels).
- The default `DeviceConfig.mdnsHostname` stays `piggybank` because each
  device prefixes with the kid name (`mia-piggybank.local`); we just
  change the service type.

## 9. New code to write (narrow scope)

### 9.1 Firmware (adapt existing skeleton, don't rewrite)

Work in `esp32-hackkit/examples/piggybank/`:

- Add XIAO-C6 `sdkconfig` defaults: `CONFIG_IDF_TARGET_ESP32C6=y`, WiFi
  station mode, no PSRAM.
- Add `BTN_MENU_GPIO = D0` and `BTN_BACK_GPIO = D6`; extend
  `button_event_t` with `BTN_EVT_MENU` and `BTN_EVT_BACK`.
- Swap the display driver stub for SH1106 over I²C using
  `espressif/ssd1306` (works on SH1106 in "reset column offset=2" mode).
- Fill in the four Semantos adapter callbacks:
  - **Storage** → NVS (encrypted partition).
  - **Identity** → read `pb_device_profile_t` from NVS, provide cert.
  - **Anchor** → append-only log in SPIFFS for claim hashes (stretch).
  - **Network** → HTTP client for `/sync/pull` against the PWA and for
    `/headers` against the local relay.
- Implement the two HTTP endpoints (`/sync/pull`, `/sync/push`,
  `/whoami`, `/qr`) using `esp_http_server`.
- Register the mDNS service.
- Pin-entry UI using the 5 buttons (▲/▼ pick digit, ✓ confirm digit,
  BACK to rub out last digit, MENU to give up).

### 9.2 PWA (new)

New workspace package `apps/piggybank-parent`:
- Scaffold Vite + React + Tailwind.
- Import `@semantos/piggybank` for types.
- One-screen "discovery" MVP first: list devices, show `/whoami`.
- Then add the screens in §5.

### 9.3 Provisioning CLI (new)

`scripts/piggybank-provision.ts` — a Bun script that:
- Opens the ESP32's USB CDC port.
- Runs the `ProvisioningHello → CHALLENGE → RESPONSE → PROVISION →
  ACK` flow already defined in `device.ts`.
- Uses `VendorSDK.deriveChild(kidRootCertId, 'device', PIGGYBANK)` to
  mint the device cert.
- Pushes `DeviceProfile` + initial `DeviceConfig` over the serial link.
- Prompts "Now set the 4-digit PIN on the device".

### 9.4 Header relay (new)

New workspace package `apps/header-relay`:
- Bun + Hono (or bare `Bun.serve`).
- One source (WhatsOnChain) → one flat file → two GET endpoints.
- Dockerfile for Pi deployment.
- mDNS advertisement via `mdns-server` or `avahi-publish-service`.

### 9.5 Shared C-header regeneration script (stretch)

`scripts/piggybank-header-gen.ts` — reads `apps/piggybank/src/*.ts`,
emits the C structs in `piggybank.h`. Keeps the two sides from drifting
as we add fields. Not critical for v1; the existing `piggybank.h` is
hand-written and still matches.

## 10. Milestones

Each milestone is a self-contained demo. You can stop at any one and
still have something usable.

1. **Serial provisioning dry-run** — `piggybank-provision.ts` +
   a mocked ESP32 (Bun TCP simulator). No BSV, no WiFi. Proves the
   handshake + key derivation.
2. **One XIAO-C6 online** — minimal firmware (WiFi join + mDNS +
   `/whoami`). Curl it from your laptop. Proves the transport.
3. **PWA shell** — `apps/piggybank-parent` discovers the one device and
   renders its `PiggyBankServiceRecord`. No wallet calls yet.
4. **Chore round-trip** — PWA pushes a `ChoreTemplate`, device renders
   it on the OLED, kid presses DONE, PWA sees the `ChoreClaim` in its
   inbox. Still no BSV.
5. **First real payment** — approve a claim, `window.CWI.createAction`
   signs + broadcasts, device verifies the BEEF against headers it
   fetched from the local relay, balance updates.
6. **Plexus per-kid wallets + recovery** — roll out the identity tree
   above, print the recovery cards, test the recovery flow end-to-end
   by wiping one device.
7. **UX polish + enclosure** — streak animations, buzzer, 3D-printed
   case, savings-goal screen.

## 11. Open questions

- **Header relay host**: which box will run it? (Pi Zero 2 W is my
  recommendation, US$15, fanless.)
- **PWA URL**: serve from `https://bitpiggy.family` (cloud) or
  `http://bitpiggy.local` (LAN-only, needs a simple HTTP server on the
  relay box)? Cloud hosting makes discovery inside the BSVA browser
  easier; LAN-only keeps everything offline.
- **Parent wallet link**: should BitPiggy use whatever identity the BSVA
  browser is currently unlocked with, or should it enforce a specific
  "family payer" identity derived under the parent root? Former is
  simpler, latter is cleaner long-term.
- **Kid count**: is it 3 kids (one board each) or fewer (with one board
  spare)? Affects whether one XIAO can double as a hub.

Once you confirm those, I'll start on milestone 1 (provisioning dry-run),
which is risk-free — no firmware flash, no BSV, just types and serial.
