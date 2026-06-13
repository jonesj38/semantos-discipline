---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/secure-signing-key-migration.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.636874+00:00
---

# Secure-signing-key migration

D-O5m.followup-2 — Keychain (iOS) / EncryptedSharedPreferences (Android)
backed signing key for the oddjobz mobile shell.

## What changed

Before this PR: the device's BRC-42 derived signing priv was persisted
as raw 64-hex bytes inside `flutter_secure_storage`. The bytes were
read out into Dart memory whenever a cell needed signing.

After this PR: new pairings generate the priv inside the platform
secure store. iOS uses Keychain (with `SecAccessControl` requiring
biometric or passcode presence on every read) and the
`secp256k1.swift` library for the actual signing primitives. Android
uses `EncryptedSharedPreferences` (with an AndroidKeyStore-backed
master key, `setUserAuthenticationRequired(true)`) and BouncyCastle
for the secp256k1 primitives.

The persisted record gains a `secure_key_handle` slot. The legacy
`device_priv_hex` slot stays in place for backward compatibility:
records that have one or the other (but not both) are valid; the
operator-initiated migration in Settings rewrites a legacy record
into a secure-key record.

## Honest scope: what this is NOT

iOS Secure Enclave only supports NIST P-256. Our cell signer uses
secp256k1 (Bitcoin curve). The SE itself cannot host the priv — and
neither can AndroidKeyStore as a native EC key (its EC key support is
restricted to NIST curves P-256 / P-384 / P-521).

Consequence: the priv DOES briefly enter process memory during signing
on both platforms. Specifically:

- **iOS**: the Keychain entry is read into a `Data` blob, passed to
  `secp256k1.swift.Signing.PrivateKey(dataRepresentation:)`, and the
  `signature(for:)` call runs in userspace. Swift's `Data` releases
  the bytes when the local goes out of scope; we don't do explicit
  zeroisation since the underlying page is unmapped on dealloc.
- **Android**: the priv blob (AES-256-GCM encrypted at rest with an
  AndroidKeyStore-derived master key) is decrypted into a Kotlin
  `String`, hex-decoded into a `ByteArray`, and signed via
  BouncyCastle's `ECDSASigner`. The `ByteArray` is GC-eligible after
  the sign call returns.

What the migration DOES add:

1. **At-rest encryption** — Keychain (iOS) / AES-256-GCM master key
   (Android) hardware-backed (Secure Enclave / StrongBox or TEE).
2. **Biometric gating** — every sign call triggers a Face ID / Touch
   ID / passcode prompt (or BiometricPrompt on Android).
3. **Key revocation via handle delete** — the Settings → Unpair flow
   wipes the platform secure-store entry alongside the local record.
4. **Local-side migration** — operators can rotate their signing key
   without re-pairing the device (well, except for the bearer
   re-issuance; see "After the migration" below).

What the migration does NOT add:

- **Priv never leaving the enclave** — the priv enters process memory
  during sign. A future revision (D-O5m.followup-2-bis) would require
  either a curve change (Plexus would have to ship a P-256 cell
  signer alongside the secp256k1 one) or a JNI/CMake-built libsecp256k1
  running inside an iOS cryptokit extension or Android Keystore custom
  plugin, neither of which are zero-effort changes.

## Before you migrate

- Confirm your device has biometrics enrolled (Face ID / Touch ID on
  iOS, fingerprint or face on Android). If not, the migration falls
  through to the device passcode on every sign.
- Ensure your operator has not revoked your existing pairing — the
  migration is local-side only; the brain still recognises your
  current bearer.
- Back up your existing pairing context (the operator can re-issue a
  fresh QR via `brain device pair`). The migration mints a fresh
  signing pub, so the brain will need to re-issue the bearer against
  the new pub before the device can post cells again.

## How to migrate (operator-side)

1. Open the oddjobz mobile shell on the device.
2. Tap the Settings tab in the bottom navigation bar.
3. In the "Signing key" card you should see:
   _"Your signing key is using legacy storage (raw priv hex in
   flutter_secure_storage). Migrate to the secure-key path for
   biometric-gated signing + at-rest encryption."_
4. Tap **Migrate now**.
5. Approve the biometric prompt when it appears. (On iOS the prompt
   text reads "Authorize signing for the oddjobz operator device.")
6. The card flips to a green "Secure key active" banner showing the
   new key handle.

After the migration the persisted record holds:
- `device_priv_hex` = `""`
- `secure_key_handle` = `<opaque platform reference>`
- `child_pub_hex` = `<33-byte SEC1 compressed pub of the new key>`

## After the migration: re-pair to refresh the brain bearer

The migration mints a NEW signing pub. The brain's bearer is bound to
the original signing pub, so the next cell flush will fail with a
401. The operator must:

1. Run `brain device pair --label "<existing label>"` on the desktop
   helm to mint a fresh QR.
2. On the mobile shell, tap Settings → Unpair this device.
3. Scan the new QR. The fresh pairing automatically generates the
   priv inside the secure store (since the platform adapter is wired
   in) — no second migration needed.

A future revision (D-O5m.followup-2-bis) folds the migration + bearer
re-issuance into a single ceremony.

## Verifying the migration succeeded

Method 1 — Settings card:
- Open Settings, look at the "Signing key" card. The green "Secure
  key active" banner indicates a successful migration.

Method 2 — log scrub (dev-only):
- The Dart side prints `PairingService: secure adapter rejected
  generate (...)` if the platform handler is not wired in. Absence
  of this line on first pair (or after migrate) confirms the secure
  path was taken.

Method 3 — secure-key card details:
- The green banner shows the `secureKeyHandle` value. On iOS this
  matches a Keychain account name with `kSecAttrService =
  info.oddjobtodd.oddjobz_mobile.secure_signing_key`. On Android it
  matches a SharedPreferences key in
  `info.oddjobtodd.oddjobz_mobile.secure_signing_key`. Inspect via
  Xcode → Product → Show Build Settings → Keychain Access (sim only)
  or `adb shell run-as <pkg> ls files/`.

## Troubleshooting

### "Secure-key migration is not available in this build"

The platform adapter isn't wired in. Common causes:

- iOS: the `pod 'secp256k1.swift'` line in `Podfile` was not picked
  up. Run `flutter pub get` then `cd ios && pod install`. Confirm
  `Pods/secp256k1.swift` is listed in the Pods project.
- Android: the BouncyCastle / security-crypto / biometric Gradle deps
  weren't included. Confirm `app/build.gradle.kts` lists
  `org.bouncycastle:bcprov-jdk18on`, `androidx.security:security-crypto`,
  and `androidx.biometric:biometric` under `dependencies { ... }`.
- Both: the `MethodChannel('semantos.oddjobz/secure_signing_key')`
  isn't being registered at engine init. iOS: verify
  `SecureSigningKeyChannel.register(with:)` is called in
  `AppDelegate.didInitializeImplicitFlutterEngine`. Android: verify
  `SecureSigningKeyChannel.register(...)` is called in
  `MainActivity.configureFlutterEngine`.

### Biometric prompt failing

- iOS: enroll Face ID / Touch ID via Settings → Face ID & Passcode.
  If the user has no biometrics enrolled, the SecAccessControl
  `userPresence` flag falls back to the device passcode — this is
  the documented behaviour.
- Android: the `MasterKey.Builder.setUserAuthenticationRequired(true,
  0)` mode requires either a fingerprint, face, or device-credential
  setup. If none are available, the migration's `generateNew` call
  will throw `KeyPermanentlyInvalidatedException`; the dart side
  surfaces this as `SecureSigningKeyError("GENERATE_FAILED", ...)`.
  Resolve by setting up a screen lock (PIN / pattern / password) on
  the device, then retry.

### "Migration failed: SecureSigningKeyError(SIGN_FAILED, ...)"

The native handler couldn't sign. Common causes:

- iOS: the Keychain entry was wiped by the OS (e.g. a factory restore
  or a Settings → General → Transfer or Reset iPhone → Reset Network
  Settings — yes, that wipes Keychain too). The handle is now
  orphaned. Fix: tap Unpair, then re-pair via QR.
- Android: same — the EncryptedSharedPreferences master key is
  invalidated when the user changes their primary biometric (e.g.
  enrolls a different fingerprint). Fix: tap Unpair, then re-pair.

### How re-pairing works

After Unpair → Re-pair:
- The fresh pairing always uses the secure-key path (because the
  PlatformSecureSigningKeyAdapter is wired in at app boot).
- The brain issues a fresh bearer bound to the new signing pub.
- The Mesh sync card refreshes the transport state.
- The Settings → Signing key card immediately renders the green
  "Secure key active" banner.

## Reference

- `apps/oddjobz-mobile/ios/Runner/SecureSigningKey.swift`
- `apps/oddjobz-mobile/android/app/src/main/kotlin/info/oddjobtodd/oddjobz_mobile/SecureSigningKey.kt`
- `apps/oddjobz-mobile/lib/src/identity/secure_signing_key.dart`
- `apps/oddjobz-mobile/lib/src/identity/platform_secure_signing_key_adapter.dart`
- `apps/oddjobz-mobile/lib/src/pairing/pairing_service.dart` (search
  for `migrateToSecureKey`)
- `apps/oddjobz-mobile/lib/src/helm/settings_screen.dart` (search for
  `_buildSecureKeyCard`)
- `docs/canon/glossary.yml` — entries `secure-signing-key-mobile`,
  `keychain-backed-priv`, `androidkeystore-backed-priv`,
  `biometric-gated-signing`.
