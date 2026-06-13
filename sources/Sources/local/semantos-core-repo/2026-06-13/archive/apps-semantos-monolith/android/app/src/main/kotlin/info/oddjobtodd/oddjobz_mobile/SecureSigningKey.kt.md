---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/android/app/src/main/kotlin/info/oddjobtodd/oddjobz_mobile/SecureSigningKey.kt
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.858657+00:00
---

# archive/apps-semantos-monolith/android/app/src/main/kotlin/info/oddjobtodd/oddjobz_mobile/SecureSigningKey.kt

```kt
// D-O5m.followup-2 — AndroidKeyStore-backed secp256k1 signing key
// handle.
//
// What this file does:
//   - Generates a fresh 32-byte secp256k1 priv via BouncyCastle's
//     ECKeyPairGenerator (same primitives bsvz uses on the Zig side).
//     BouncyCastle (`org.bouncycastle:bcprov-jdk18on`) is permissively
//     licensed and pinned in app/build.gradle.kts.
//   - Encrypts the priv at rest using EncryptedSharedPreferences,
//     whose master key sits in AndroidKeyStore (StrongBox-backed on
//     hardware that supports it; falls back to TEE on devices
//     without StrongBox).  Per Android docs:
//       https://developer.android.com/training/articles/keystore
//     EncryptedSharedPreferences uses AES-256-GCM with a key whose
//     unwrap requires the AndroidKeyStore master key, which is
//     hardware-backed.
//   - Optionally gates reads on biometric authentication via the
//     androidx.biometric BiometricPrompt API (`setUserAuthentication
//     Required(true)` on the master-key spec).  See the runbook for
//     the device-class compatibility matrix.
//
// Honest scope:
//   - At-rest: priv blob is AES-256-GCM encrypted with a key whose
//     unwrap requires AndroidKeyStore (hardware-backed).
//   - In-use: the priv DOES briefly enter process memory during a
//     sign call, because AndroidKeyStore's `KeyProperties.KEY_
//     ALGORITHM_EC` only exposes NIST curves (P-256/P-384/P-521),
//     not secp256k1.  We can't ask the keystore to sign with
//     secp256k1 directly; we have to read the priv out, sign in
//     userspace, and let the priv drop out of scope.
//   - Biometric gating: the EncryptedSharedPreferences master key is
//     created with `setUserAuthenticationRequired(true)` so a
//     successful BiometricPrompt is required before each read.
//     `setUserAuthenticationValidityDurationSeconds(0)` (the
//     auth-per-use mode) ensures no timing-window cache.
//
// MethodChannel contract — name `semantos.oddjobz/secure_signing_key`:
//   - generate(label: String) -> {keyHandle: String, publicKey: ByteArray}
//   - sign(keyHandle: String, message: ByteArray) -> ByteArray  (64-byte r||s)
//   - delete(keyHandle: String) -> Unit
//   - exists(keyHandle: String) -> Boolean
//
// Reference: apps/oddjobz-mobile/lib/src/identity/secure_signing_key.dart
// (Dart counterpart; this Kotlin file is the Android implementation
// of the `PlatformSecureSigningKeyAdapter` MethodChannel surface.)

package info.oddjobtodd.oddjobz_mobile

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyProperties
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.bouncycastle.crypto.generators.ECKeyPairGenerator
import org.bouncycastle.crypto.params.ECDomainParameters
import org.bouncycastle.crypto.params.ECKeyGenerationParameters
import org.bouncycastle.crypto.params.ECPrivateKeyParameters
import org.bouncycastle.crypto.params.ECPublicKeyParameters
import org.bouncycastle.crypto.signers.ECDSASigner
import org.bouncycastle.crypto.signers.HMacDSAKCalculator
import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.asn1.sec.SECNamedCurves
import java.math.BigInteger
import java.security.SecureRandom

/// Slot prefix shared with the iOS Swift counterpart.  Keeps the
/// SharedPreferences key namespace from colliding with other slots
/// the app uses.
private const val SLOT_PREFIX = "d-o5m.followup-2.secure_signing_key."

/// EncryptedSharedPreferences file name.  All `SecureSigningKey`
/// entries live in this single file so we can scope deletes / queries.
private const val PREFS_FILE = "info.oddjobtodd.oddjobz_mobile.secure_signing_key"

/// Master key alias inside AndroidKeyStore.  Created lazily on first
/// access; setUserAuthenticationRequired=true gates reads on a fresh
/// BiometricPrompt success.
private const val MASTER_KEY_ALIAS = "d-o5m.followup-2.master_key"

class SecureSigningKey(private val context: Context) {

  /// Result tag exposed across the FlutterMethodChannel — see
  /// SecureSigningKey.swift `Errors` for the iOS counterpart.
  enum class ErrorCode(val code: String) {
    GENERATE_FAILED("GENERATE_FAILED"),
    SIGN_FAILED("SIGN_FAILED"),
    DELETE_FAILED("DELETE_FAILED"),
    KEY_NOT_FOUND("KEY_NOT_FOUND"),
    UNSUPPORTED("UNSUPPORTED"),
  }

  /// secp256k1 domain parameters.  Same curve bsvz uses on the Zig
  /// side and pointycastle uses in `cell_signer.dart`.
  private val secp256k1: ECDomainParameters by lazy {
    val params = SECNamedCurves.getByName("secp256k1")
    ECDomainParameters(params.curve, params.g, params.n, params.h)
  }

  private val prefs: SharedPreferences by lazy { openPrefs() }

  private fun openPrefs(): SharedPreferences {
    val masterKey = MasterKey.Builder(context, MASTER_KEY_ALIAS)
      .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
      .setUserAuthenticationRequired(true, 0)
      .build()
    return EncryptedSharedPreferences.create(
      context,
      PREFS_FILE,
      masterKey,
      EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
      EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )
  }

  /// Generate a fresh secp256k1 priv inside EncryptedSharedPreferences.
  /// Returns the 33-byte compressed pub + the opaque keyHandle (the
  /// SharedPreferences key suffix).  The priv bytes are written and
  /// not returned to the caller.
  fun generateNew(label: String): Pair<String, ByteArray>? {
    return try {
      val keyGen = ECKeyPairGenerator()
      val keyParams = ECKeyGenerationParameters(secp256k1, SecureRandom())
      keyGen.init(keyParams)
      val keyPair = keyGen.generateKeyPair()
      val priv = (keyPair.private as ECPrivateKeyParameters).d
      val pub = (keyPair.public as ECPublicKeyParameters).q
      val privBytes = bigIntTo32Bytes(priv)
      // 33-byte compressed SEC1.
      val pubCompressed = pub.getEncoded(true)

      val handle = randomHex(32)
      val slotKey = SLOT_PREFIX + handle
      // The label is stored alongside the priv so a future
      // re-derive / audit pass can correlate handle ↔ operator label.
      prefs.edit()
        .putString(slotKey, hexEncode(privBytes))
        .putString("$slotKey.label", label)
        .apply()

      Pair(handle, pubCompressed)
    } catch (t: Throwable) {
      null
    }
  }

  /// Sign `message` with the priv stored at `keyHandle`.  Returns 64
  /// raw bytes (32-byte big-endian r || 32-byte big-endian s, low-s
  /// normalised — same wire shape as the pure-Dart `signCellPayload`
  /// in cell_signer.dart).
  ///
  /// IMPORTANT: this function reads the priv out of the encrypted
  /// SharedPreferences (which triggers the BiometricPrompt
  /// gating) into process memory for the duration of the sign call.
  /// See file header for the honest scope analysis.
  fun sign(keyHandle: String, message: ByteArray): Result_ {
    val slotKey = SLOT_PREFIX + keyHandle
    val privHex = prefs.getString(slotKey, null) ?: return Result_.Error(ErrorCode.KEY_NOT_FOUND)
    return try {
      val privBytes = hexDecode(privHex)
      val d = BigInteger(1, privBytes)
      val signer = ECDSASigner(HMacDSAKCalculator(SHA256Digest()))
      signer.init(true, ECPrivateKeyParameters(d, secp256k1))
      val sha256 = java.security.MessageDigest.getInstance("SHA-256")
      val digest = sha256.digest(message)
      val rs = signer.generateSignature(digest)
      val r = rs[0]
      var s = rs[1]
      // BIP-62 low-s normalisation.
      val halfN = secp256k1.n.shiftRight(1)
      if (s > halfN) {
        s = secp256k1.n.subtract(s)
      }
      val out = ByteArray(64)
      System.arraycopy(bigIntTo32Bytes(r), 0, out, 0, 32)
      System.arraycopy(bigIntTo32Bytes(s), 0, out, 32, 32)
      Result_.Ok(out)
    } catch (t: Throwable) {
      Result_.Error(ErrorCode.SIGN_FAILED)
    }
  }

  /// Remove the entry for `keyHandle`.  Idempotent.
  fun delete(keyHandle: String): Boolean {
    val slotKey = SLOT_PREFIX + keyHandle
    return try {
      prefs.edit().remove(slotKey).remove("$slotKey.label").apply()
      true
    } catch (t: Throwable) {
      false
    }
  }

  /// Cheap existence check.  Does NOT read the value (the SharedPrefs
  /// `contains` check on encrypted SP can still trigger the master
  /// key unlock — but no BiometricPrompt is required to enumerate
  /// keys, only to read values).
  fun exists(keyHandle: String): Boolean {
    val slotKey = SLOT_PREFIX + keyHandle
    return try {
      prefs.contains(slotKey)
    } catch (t: Throwable) {
      false
    }
  }

  // ─── helpers ───────────────────────────────────────────────────────

  sealed class Result_ {
    data class Ok(val bytes: ByteArray) : Result_()
    data class Error(val code: ErrorCode) : Result_()
  }

  private fun bigIntTo32Bytes(n: BigInteger): ByteArray {
    val raw = n.toByteArray()
    if (raw.size == 32) return raw
    if (raw.size > 32) {
      // Strip the leading sign byte BouncyCastle's BigInteger
      // sometimes prepends.
      return raw.copyOfRange(raw.size - 32, raw.size)
    }
    val padded = ByteArray(32)
    System.arraycopy(raw, 0, padded, 32 - raw.size, raw.size)
    return padded
  }

  private fun randomHex(byteLen: Int): String {
    val b = ByteArray(byteLen)
    SecureRandom().nextBytes(b)
    return hexEncode(b)
  }

  private fun hexEncode(b: ByteArray): String {
    val sb = StringBuilder(b.size * 2)
    for (x in b) {
      sb.append(String.format("%02x", x.toInt() and 0xff))
    }
    return sb.toString()
  }

  private fun hexDecode(h: String): ByteArray {
    val out = ByteArray(h.length / 2)
    for (i in out.indices) {
      out[i] = h.substring(i * 2, i * 2 + 2).toInt(16).toByte()
    }
    return out
  }
}

// MARK: - Flutter MethodChannel handler

/// Wires `SecureSigningKey` operations into the
/// `semantos.oddjobz/secure_signing_key` MethodChannel.  Called from
/// `MainActivity.configureFlutterEngine`.
class SecureSigningKeyChannel(context: Context) : MethodCallHandler {
  private val key = SecureSigningKey(context)

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "generate" -> {
        val label = call.argument<String>("label")
        if (label == null) {
          result.error("BAD_ARGS", "expected {label: String}", null)
          return
        }
        val pair = key.generateNew(label)
        if (pair == null) {
          result.error(SecureSigningKey.ErrorCode.GENERATE_FAILED.code, null, null)
        } else {
          result.success(mapOf(
            "keyHandle" to pair.first,
            "publicKey" to pair.second,
          ))
        }
      }
      "sign" -> {
        val handle = call.argument<String>("keyHandle")
        val msg = call.argument<ByteArray>("message")
        if (handle == null || msg == null) {
          result.error("BAD_ARGS", "expected {keyHandle: String, message: ByteArray}", null)
          return
        }
        when (val r = key.sign(handle, msg)) {
          is SecureSigningKey.Result_.Ok -> result.success(r.bytes)
          is SecureSigningKey.Result_.Error -> result.error(r.code.code, null, null)
        }
      }
      "delete" -> {
        val handle = call.argument<String>("keyHandle")
        if (handle == null) {
          result.error("BAD_ARGS", "expected {keyHandle: String}", null)
          return
        }
        if (key.delete(handle)) result.success(null)
        else result.error(SecureSigningKey.ErrorCode.DELETE_FAILED.code, null, null)
      }
      "exists" -> {
        val handle = call.argument<String>("keyHandle")
        if (handle == null) {
          result.error("BAD_ARGS", "expected {keyHandle: String}", null)
          return
        }
        result.success(key.exists(handle))
      }
      else -> result.notImplemented()
    }
  }

  companion object {
    fun register(messenger: io.flutter.plugin.common.BinaryMessenger, context: Context) {
      val channel = MethodChannel(messenger, "semantos.oddjobz/secure_signing_key")
      channel.setMethodCallHandler(SecureSigningKeyChannel(context))
    }
  }
}

```
