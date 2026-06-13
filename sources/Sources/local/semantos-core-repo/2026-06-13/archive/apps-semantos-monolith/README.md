---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.693901+00:00
---

# oddjobz-mobile (D-O5m, Phase 1 MVP)

Flutter mobile shell for the oddjobz operator. The mobile shell pairs
into the operator's brain via the D-O5p QR-pairing flow and runs a
helm UI on top of the same bearer-gated `POST /api/v1/repl` endpoint
that the desktop helm SPA (`apps/loom-svelte`) consumes.

> **Want to run this on a physical phone?** See the operator runbook
> at [`docs/operator-runbooks/mobile-build-and-pair.md`](../../docs/operator-runbooks/mobile-build-and-pair.md)
> for the end-to-end smoke-test walkthrough — build the native libs
> via `scripts/build-android-libs.sh`, install the APK, pair via QR,
> and exercise the voice → cell → outbox loop.  Run
> [`scripts/smoke-test-mobile.sh`](../../scripts/smoke-test-mobile.sh)
> to automate the predictable build + tunnel + token-mint steps.

## Scope

This package ships the **D-O5m Phase 1 MVP** slice — the device-side
production binary for the §3 Phase O5m sub-deliverables `O5m-a`,
`O5m-b`, the `O5m-h` helm subset, and the `O5m-i` outbox skeleton.
The full Phase O5m scope (voice shell, sensors, push notifications,
real mesh sync, full K1 conflict resolution surface) is tracked as
follow-ups `D-O5m.followup-1..N` in `docs/canon/deliverables.yml`.

| Sub-deliverable | Status   | Note                                                                          |
| --------------- | -------- | ----------------------------------------------------------------------------- |
| O5m-a           | shipped  | Flutter scaffolding at `apps/oddjobz-mobile/`                                 |
| O5m-b           | shipped  | QR pairing + BRC-42 child derivation + child-cert custody                     |
| O5m-c           | deferred | Local cell engine — D-O5m.followup-1                                          |
| O5m-d           | deferred | Voice-shell pipeline — D-O5m.followup-3                                       |
| O5m-e           | deferred | SignedBundle mesh sync — D-O5m.followup-6                                     |
| O5m-f           | deferred | Camera/GPS/microphone sensors — D-O5m.followup-8                              |
| O5m-g           | deferred | APNs/FCM push subscriptions — D-O5m.followup-9                                |
| O5m-h           | partial  | Pairing, paired state, JobList, JobDetail, settings/unpair (read-only helm)   |
| O5m-i           | partial  | Outbox queue skeleton (sqflite enqueue/dequeue/flush; no K1 resolution UI)    |

See `docs/design/ODDJOBZ-EXTENSION-PLAN.md` §Phase O5m for the full
design.

## Architecture

```
apps/oddjobz-mobile/lib/src/
├── pairing/         Decode brain-device-pair-v2 token → BRC-42 derive →
│                    POST /api/v1/device-pair → persist child cert
├── identity/        SecureStore abstraction + flutter_secure_storage
│                    adapter + auth state machine
├── repl/            Bearer-gated POST /api/v1/repl client + jobs
│                    repository (REPL `find jobs`)
├── helm/            Pairing screen + Home/JobList/JobDetail/Settings
└── outbox/          sqflite-backed FIFO queue for offline cell
                     transitions + flush-on-reconnect skeleton
```

The pairing path mirrors `extensions/oddjobz/src/device-pair-client.ts`
(the TS reference implementation) byte-for-byte. The cross-language
parity test at `test/pairing/brc42_derive_test.dart` asserts that the
Dart port produces the same `childPubKeyHex` as the TS reference for
the canonical fixture in
`extensions/oddjobz/tests/vectors/device-pair/v2-fixture.json`.

## Tests

Pure-Dart unit tests (no Flutter SDK gate):

```bash
cd apps/oddjobz-mobile
dart test                   # 33 tests across pairing, repl, outbox
```

Flutter-gated tests (require the Flutter SDK + a target device or
emulator):

```bash
flutter test integration_test/
```

The pure-Dart suite is the gate — every PR must pass it. The Flutter
SDK suite is informational (it tests the screen widgets via
`flutter_test`'s widget harness, but those tests are not load-bearing
for the MVP correctness story).

## Crypto

BRC-42 child derivation uses [pointycastle](https://pub.dev/packages/pointycastle)
(pure-Dart secp256k1 + HMAC-SHA-256 + ECDH). The derivation must be
byte-identical to the TS reference (which uses `@bsv/sdk`); the
parity test at `test/pairing/brc42_derive_test.dart` is the
authoritative correctness proof.

The HMAC key is the **compressed-SEC1 33-byte form** of the ECDH
shared point — NOT the raw X coordinate. pointycastle's
`ECDHBasicAgreement` returns just the X scalar, which is wrong; the
derivation explicitly computes `Q = priv * pub` and then encodes Q
compressed. See `lib/src/pairing/brc42_derive.dart` for the full
flow.

## Wire format

All pairing tokens are `brain-device-pair-v2` — see
`runtime/semantos-brain/src/device_pair.zig`. The on-device REPL client is
bearer-gated; the bearer is issued by the brain on successful
pairing and persisted in `flutter_secure_storage`.

## Permissions

- iOS: `NSCameraUsageDescription` in `ios/Runner/Info.plist` (camera
  for QR scan).
- Android: `android.permission.CAMERA` in
  `android/app/src/main/AndroidManifest.xml`.
