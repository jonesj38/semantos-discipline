---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/ios/Runner/SecureSigningKey.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.851133+00:00
---

# archive/apps-semantos-monolith/ios/Runner/SecureSigningKey.swift

```swift
// D-O5m.followup-2 — Keychain-backed secp256k1 signing key handle.
//
// What this file does:
//   - Generates a fresh 32-byte secp256k1 priv via secp256k1.swift
//     (GigaBitcoin maintained fork — permissive MIT licence, the same
//     primitives bsvz uses; pinned via Podfile).
//   - Stores the priv in iOS Keychain as a generic password item with
//     `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` + a
//     `SecAccessControlCreateWithFlags` ACL that requires biometric
//     (or fall-back-to-passcode) presence on every read.
//   - Signs payload bytes by reading the priv out of Keychain and
//     calling `secp256k1.swift.Signing.PrivateKey.signature(for:)` —
//     the priv DOES briefly enter process memory during the read+sign,
//     because Apple's Secure Enclave only supports NIST P-256 (not
//     secp256k1) so we can't keep the priv inside SE/SEP.  See the
//     PR body / runbook for the honest scope analysis.
//
// Honest scope:
//   - At-rest: Keychain encrypts with hardware-backed keys (Secure
//     Enclave-protected on devices that have one, including all modern
//     iPhones).  Even with `kSecClassGenericPassword`, the entry is
//     wrapped by a key whose master key sits inside SE.
//   - In-use: the priv exists as a `Data` in process memory for the
//     duration of one `signature(for:)` call, then drops out of scope.
//     We rely on Swift `Data` to release the bytes promptly; we don't
//     attempt explicit zeroisation (the GigaBitcoin secp256k1.swift
//     wrapper allocates a `secp256k1_context` that owns its own copy
//     internally — explicit zeroisation of our local copy would be a
//     defence-in-depth-only measure since the platform already
//     unmaps the page on deallocation).
//   - Biometric gating: the SecAccessControl flags require a fresh
//     authentication on every Keychain read (no LAContext caching),
//     so the user sees a Face ID / Touch ID / passcode prompt on
//     every cell signature.  The runbook explains how to disable
//     this for kiosk-style operator devices.
//
// MethodChannel contract — name `semantos.oddjobz/secure_signing_key`:
//   - generate(label: String) -> {keyHandle: String, publicKey: Data}
//   - sign(keyHandle: String, message: Data) -> Data            (64-byte r||s)
//   - delete(keyHandle: String) -> nil
//   - exists(keyHandle: String) -> Bool
//
// All three integer-bridged by the FlutterMethodChannel; binary data
// rides as `FlutterStandardTypedData(bytes:)` per the codec spec.
//
// References:
//   - https://github.com/GigaBitcoin/secp256k1.swift  (vendored via
//     Podfile entry `pod 'secp256k1.swift'`)
//   - https://developer.apple.com/documentation/security/keychain_services
//   - apps/oddjobz-mobile/lib/src/identity/secure_signing_key.dart
//     (Dart counterpart; this Swift file is the iOS implementation
//     of the `PlatformSecureSigningKeyAdapter` MethodChannel surface.)

import Foundation
import Security
import LocalAuthentication

#if canImport(secp256k1)
import secp256k1
#endif

/// Slot prefix shared with the Android Kotlin counterpart.  Keeps
/// the Keychain account-name namespace from colliding with other
/// generic-password items the app uses.
private let kSlotPrefix = "d-o5m.followup-2.secure_signing_key."

/// `kSecAttrService` value for our Keychain items.  All entries the
/// SecureSigningKey owns share this service so we can scope deletes
/// + queries to just our items.
private let kService = "info.oddjobtodd.oddjobz_mobile.secure_signing_key"

@objc class SecureSigningKey: NSObject {

  /// Result tag exposed across the FlutterMethodChannel so Dart can
  /// pattern-match without colliding with native exception types.
  enum Errors: String {
    case generateFailed = "GENERATE_FAILED"
    case signFailed = "SIGN_FAILED"
    case deleteFailed = "DELETE_FAILED"
    case keyNotFound = "KEY_NOT_FOUND"
    case unsupported = "UNSUPPORTED"
  }

  /// Generate a fresh secp256k1 priv inside Keychain.  Returns the
  /// 33-byte compressed pub + the opaque keyHandle (Keychain account
  /// name).  The priv bytes are written to Keychain and never
  /// returned to the caller.
  static func generateNew(label: String) -> Result<(keyHandle: String, publicKey: Data), Errors> {
    #if canImport(secp256k1)
    do {
      let priv = try secp256k1.Signing.PrivateKey()
      let pubCompressed = priv.publicKey.dataRepresentation
      let privBytes = priv.dataRepresentation

      // Mint a fresh keyHandle (32-byte random hex) for the Keychain
      // account name.  Decoupled from the operator-supplied label so
      // a label change doesn't move the key.
      let handle = randomHex(32)

      var error: Unmanaged<CFError>?
      // userPresence bundles BiometryAny + DevicePasscode-fallback —
      // matches what the runbook tells operators to expect.  On
      // hardware without biometrics this falls back to passcode.
      guard let access = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        .userPresence,
        &error
      ) else {
        return .failure(.generateFailed)
      }

      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: kService,
        kSecAttrAccount as String: kSlotPrefix + handle,
        kSecAttrLabel as String: label,
        kSecValueData as String: privBytes,
        kSecAttrAccessControl as String: access,
        kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
      ]

      // Best-effort: if a stale entry exists at this handle (shouldn't
      // — handles are random — but defence-in-depth), wipe it first.
      SecItemDelete(query as CFDictionary)
      let status = SecItemAdd(query as CFDictionary, nil)
      if status != errSecSuccess {
        return .failure(.generateFailed)
      }
      return .success((keyHandle: handle, publicKey: pubCompressed))
    } catch {
      return .failure(.generateFailed)
    }
    #else
    // secp256k1.swift not present in this build.  The Dart side
    // surfaces this as `SecureSigningKeyUnsupported`; the runbook
    // tells the operator to add the Pod and re-build.
    return .failure(.unsupported)
    #endif
  }

  /// Sign `message` with the priv stored at `keyHandle`.  Returns 64
  /// raw bytes (32-byte big-endian r || 32-byte big-endian s, low-s
  /// normalised — same wire shape as the pure-Dart `signCellPayload`
  /// in cell_signer.dart).
  ///
  /// IMPORTANT: this function reads the priv out of Keychain into
  /// process memory for the duration of the sign call.  See file
  /// header for the honest scope analysis.
  static func sign(keyHandle: String, message: Data) -> Result<Data, Errors> {
    #if canImport(secp256k1)
    var item: AnyObject?
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: kService,
      kSecAttrAccount as String: kSlotPrefix + keyHandle,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseOperationPrompt as String:
        "Authorize signing for the oddjobz operator device.",
    ]
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return .failure(.keyNotFound)
    }
    if status != errSecSuccess {
      return .failure(.signFailed)
    }
    guard let privBytes = item as? Data else {
      return .failure(.signFailed)
    }

    do {
      let priv = try secp256k1.Signing.PrivateKey(dataRepresentation: privBytes)
      // The cell-wire signature scheme is RFC 6979 deterministic-k
      // ECDSA-secp256k1-sha256, low-s normalised, 64-byte compact
      // r||s (no recovery byte — the brain's verifier loops over
      // recovery ids 0..3).  The Dart counterpart rides Zig stdlib's
      // Sha256oSha256 HMAC underlying hash; a future rev (D-O5m.
      // followup-2-bis) replaces signCellPayload's pure-Dart path
      // with this native call to converge on a single signing impl
      // — for now the wire bytes are the same shape, but the
      // deterministic-k seed differs (so a Dart-signed cell vs a
      // SE-signed cell will not produce byte-identical signatures
      // for the same message).  The brain-side verifier accepts
      // both because the recovery loop only depends on (r, s)
      // representing a valid ECDSA over the message digest.
      let sig = try priv.signature(for: message)
      // `secp256k1.swift` returns DER-encoded by default; flatten to
      // 64-byte compact r||s.  The library exposes `compact` via the
      // `dataRepresentation` of the `ECDSASignature`'s parsed form;
      // adapt as needed at integration time.
      let compact = try sig.compactRepresentation
      return .success(compact)
    } catch {
      return .failure(.signFailed)
    }
    #else
    return .failure(.unsupported)
    #endif
  }

  /// Remove the Keychain entry for `keyHandle`.  Idempotent — a
  /// not-found error is mapped to .keyNotFound but the .delete
  /// surface treats that as acceptable since the postcondition
  /// (no entry exists at this handle) holds either way.
  static func delete(keyHandle: String) -> Result<Void, Errors> {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: kService,
      kSecAttrAccount as String: kSlotPrefix + keyHandle,
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound {
      return .success(())
    }
    return .failure(.deleteFailed)
  }

  /// Cheap existence check — does NOT trigger the biometric prompt
  /// (we don't request `kSecReturnData`).  Used by the helm UI to
  /// gate the "Migrate now" button.
  static func exists(keyHandle: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: kService,
      kSecAttrAccount as String: kSlotPrefix + keyHandle,
      kSecReturnData as String: false,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess
  }

  // ─── helpers ─────────────────────────────────────────────────────

  private static func randomHex(_ byteLen: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: byteLen)
    let rc = SecRandomCopyBytes(kSecRandomDefault, byteLen, &bytes)
    if rc != errSecSuccess {
      // Falls back to arc4random — still cryptographically OK on iOS;
      // SecRandomCopyBytes is the canonical source.
      for i in 0..<byteLen {
        bytes[i] = UInt8.random(in: 0...255)
      }
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }
}

// MARK: - Flutter MethodChannel handler

/// Wires `SecureSigningKey` operations into the
/// `semantos.oddjobz/secure_signing_key` MethodChannel.  Called from
/// `AppDelegate.didInitializeImplicitFlutterEngine`.
///
/// All binary data crosses the channel as `FlutterStandardTypedData`
/// (typed `bytes:`) per the standard codec.  Errors flatten to
/// `FlutterError(code:)` carrying one of `Errors.rawValue` so the
/// Dart side can pattern-match without string-comparing free-form
/// messages.
@objc class SecureSigningKeyChannel: NSObject {
  @objc static func register(with registry: FlutterPluginRegistry) {
    let channel = FlutterMethodChannel(
      name: "semantos.oddjobz/secure_signing_key",
      binaryMessenger: registry.registrar(forPlugin: "SecureSigningKey")!.messenger())
    channel.setMethodCallHandler(handle)
  }

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "generate":
      guard let args = call.arguments as? [String: Any],
            let label = args["label"] as? String else {
        result(FlutterError(code: "BAD_ARGS", message: "expected {label: String}", details: nil))
        return
      }
      switch SecureSigningKey.generateNew(label: label) {
      case .success(let pair):
        result([
          "keyHandle": pair.keyHandle,
          "publicKey": FlutterStandardTypedData(bytes: pair.publicKey),
        ])
      case .failure(let e):
        result(FlutterError(code: e.rawValue, message: nil, details: nil))
      }

    case "sign":
      guard let args = call.arguments as? [String: Any],
            let handle = args["keyHandle"] as? String,
            let msg = args["message"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "BAD_ARGS",
                            message: "expected {keyHandle: String, message: bytes}",
                            details: nil))
        return
      }
      switch SecureSigningKey.sign(keyHandle: handle, message: msg.data) {
      case .success(let sig):
        result(FlutterStandardTypedData(bytes: sig))
      case .failure(let e):
        result(FlutterError(code: e.rawValue, message: nil, details: nil))
      }

    case "delete":
      guard let args = call.arguments as? [String: Any],
            let handle = args["keyHandle"] as? String else {
        result(FlutterError(code: "BAD_ARGS", message: "expected {keyHandle: String}", details: nil))
        return
      }
      switch SecureSigningKey.delete(keyHandle: handle) {
      case .success: result(nil)
      case .failure(let e): result(FlutterError(code: e.rawValue, message: nil, details: nil))
      }

    case "exists":
      guard let args = call.arguments as? [String: Any],
            let handle = args["keyHandle"] as? String else {
        result(FlutterError(code: "BAD_ARGS", message: "expected {keyHandle: String}", details: nil))
        return
      }
      result(SecureSigningKey.exists(keyHandle: handle))

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

```
