---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/jam-room-mobile-build-and-pair.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.639027+00:00
---

# Jam Room Mobile — build + pair runbook

D-G.10 — end-to-end walkthrough for building `jam-room-mobile`, pairing it
with a running `brain` node, and verifying the full jam session flow on an
Android or iOS device.

This runbook mirrors `mobile-build-and-pair.md` but covers the Jam Room
Flutter shell instead of Oddjobz.  Pre-requisite for shipping Phase G work.

> **Pair tokens expire in 5 minutes.**  Build and install the APK/IPA first,
> launch the app and confirm the Pair screen is visible, THEN mint the pair
> token.  The first `flutter build apk --debug` takes 10+ minutes on a fresh
> checkout — longer than the token TTL.

---

## Sections

- R1. Prerequisites
- R2. One-time device setup
- R3. Start brain with the jam-room world app
- R4. Build + install the APK (Android) or run on iOS simulator
- R5. Generate a pair token
- R6. Pair the device
- R7. Smoke test: L1 anchor card + scene launch
- R8. Smoke test: L2 rack tab bar
- R9. Smoke test: phone-as-controller (sensor inputs)
- R10. Smoke test: USB MIDI controller
- R11. Troubleshooting

---

## R1. Prerequisites

| Tool | Version | Verify |
|------|---------|--------|
| Flutter | ≥ 3.22 | `flutter --version` |
| Dart | ≥ 3.4 | `dart --version` |
| Android Studio / SDK | API 34+ | `flutter doctor` |
| Xcode (macOS, iOS only) | ≥ 15 | `xcode-select --version` |
| bun | ≥ 1.1 | `bun --version` |
| brain binary | current | `brain version` |

**brain must be running with the jam-room world app loaded** (see R3).

---

## R2. One-time device setup

### Android

1. Enable Developer Options on the phone (tap Build Number 7 times).
2. Enable USB Debugging.
3. Run `flutter devices` and confirm the device appears.

### iOS (Simulator)

1. `open -a Simulator` or use Xcode.
2. Run `flutter devices` and confirm the simulator appears.

### iOS (physical device)

1. Xcode → Devices and Simulators → trust the connected device.
2. Add provisioning profile (or use Personal Team for local testing).

---

## R3. Start brain with the jam-room world app

```bash
# From repo root
bun install
pnpm -C apps/world-apps/jam-room build:bundle

# Start brain (replace with your config path)
brain start --config config/dev.yaml --world apps/world-apps/jam-room
```

Confirm brain is reachable:
```bash
curl -k https://localhost:3443/api/v1/info
```

---

## R4. Build + install

### Android APK (debug, fastest for dev)

```bash
cd apps/world-apps/jam-room-mobile
flutter build apk --debug
flutter install
```

### Android release split APK

```bash
flutter build apk --release --split-per-abi
# Install arm64 variant:
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### iOS simulator

```bash
flutter run -d "iPhone 15"  # or the device name from `flutter devices`
```

---

## R5. Generate a pair token

From the Semantos Brain CLI on the server:

```bash
brain device pair --room lobby --ttl 300
# Outputs:
#   Token:  eyJ...
#   QR URL: https://localhost:3443/pair?token=eyJ...
```

Keep this terminal open — the QR URL is valid for 5 minutes.

---

## R6. Pair the device

1. Open Jam Room on the device — the Pair Screen appears.
2. Tap **Scan QR** and point the camera at the QR code from R5.
   - Or tap **Paste Token** and paste the token string.
3. The app pairs and navigates to the Home Screen (L1 anchor card visible).

Verify in brain logs:
```
INFO  device pair: accepted  device=jam-room-mobile-XXXX
INFO  jam.subscribe: room:lobby:state  device=jam-room-mobile-XXXX
```

---

## R7. Smoke test: L1 anchor card + scene launch

1. On the Semantos Brain REPL or another connected client, launch a scene:
   ```
   jam.scene.launch scene-A
   ```
2. Verify the phone shows "Main Loop" (or the scene's name) in the anchor card.
3. The BPM counter should tick and the clock dial should animate.

---

## R8. Smoke test: L2 rack tab bar

1. The bottom tab bar should show **Rhythm**, **Melody**, **Bass**.
2. Tap **Melody** — the note pad grid should appear (4×8 pads coloured by scale).
3. Tap a pad — verify `jam.note.on` is dispatched (visible in brain REPL):
   ```
   brain repl
   > watch jam.note.*
   ```

---

## R9. Smoke test: phone-as-controller (sensor inputs)

Requires iOS 13+ or Android with DeviceMotion permission.

1. With the Melody tab active, tilt the phone forward/backward — the brightness
   macro (macro 4) should change.
2. Shake the phone — chaos macro (macro 7) should spike.
3. Three-finger-tap the screen — `jam.gesture{propose}` should appear in brain REPL.

On iOS: the app will request DeviceMotion permission on first activation.
Tap **Allow**.

---

## R10. Smoke test: USB MIDI controller

1. Connect a USB MIDI controller via OTG adapter (Android) or USB-C (iOS).
2. The controller should be detected: a banner appears with the detected profile
   (e.g. "MPK49 detected — mpk49 profile loaded").
3. Play notes on the controller — they should appear in the Melody pad grid.
4. Check brain REPL for `jam.note.*` events.

---

## R11. Troubleshooting

### "Pair screen loops" / token rejected

- Check token TTL: tokens expire in 5 minutes.
- Confirm the `wss://` URL in the token matches the running brain host.
- Verify brain is using HTTPS (the Flutter HTTP client rejects plain HTTP by default).

### Scene name doesn't update

- Check brain logs for `jam.subscribe` acceptance.
- Verify `room:lobby:state` channel is active: `brain channels --list`.

### MIDI device not detected

- Android: confirm USB OTG is enabled and `android.hardware.usb.host` permission
  is granted (appears in AndroidManifest.xml).
- iOS: confirm the device has CoreMIDI-compatible USB interface.

### Sensor inputs not working

- iOS: confirm DeviceMotion permission was granted.
- Android: no permission required, but some emulators don't emulate sensors.

### Build failures

```bash
flutter clean
flutter pub get
flutter build apk --debug
```

Run the full audit:
```bash
bash scripts/audit-flutter-build.sh SKIP_BUILD=1
```
