---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/plexus/envelope.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.113273+00:00
---

# apps/semantos/lib/src/plexus/envelope.dart

```dart
/// envelope.dart — Pure-Dart port of the Plexus recovery envelope (W7).
///
/// Mirror of `cartridges/wallet-headers/brain/src/plexus/envelope.ts`.
/// Identical wire format + identical normalization rule so an envelope
/// built by the canonical PWA decrypts under the same answers that the
/// wallet-headers TS implementation expects, and vice versa.
///
/// What gets built:
///   - challengeBundle: questions, 32-byte salt, sha256(salt || normalize(answer))
///     per question, PBKDF2 cost factor (pinned at 100k)
///   - encryptedRecoverySeed: AES-256-GCM(seed, KEK, nonce, AAD)
///     where KEK = PBKDF2-SHA256(concat(normalized answers), salt, 100k, 32 bytes)
///     and AAD = identityKey(33) || envelopeVersion(=1)
///   - identityKey, certId, contactEmail, version markers
///
/// Out of scope for PR-C11-2:
///   - derivationContexts / edgeRecipes / derivationStateSnapshot
///     (these come from wallet-headers' DerivationState; PR-C11-4 wires
///     wallet-headers and they flow in automatically)
///   - BRC-100 signature (PR-C11-5 needs it for Plexus dispatch; local
///     file download in this PR does not)
///
/// Round-trip tested against fixed test vectors so the wire shape stays
/// pinned.
library;

import 'dart:convert' show jsonEncode, utf8;
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:pointycastle/block/aes.dart' show AESEngine;
import 'package:pointycastle/block/modes/gcm.dart' show GCMBlockCipher;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart' show Pbkdf2Parameters;
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/paddings/pkcs7.dart' show PKCS7Padding;
import 'package:pointycastle/api.dart' show AEADParameters, KeyParameter;

// ─────────────────────────────────────────────────────────────────────
// Constants — pinned to match TS envelope.ts
// ─────────────────────────────────────────────────────────────────────

/// PBKDF2 cost factor for the KEK. Pinned at 100_000 per W7 spec.
const int kPbkdf2Iterations = 100000;

/// Schema major version. Bump on any wire-incompatible change.
const int kEnvelopeVersion = 1;

/// Envelope KDF-era counter. Independent of [kEnvelopeVersion] (the wire
/// FORMAT / AAD version, unchanged at 1).
///   1 — pre-L11: recipes carry no per-domain kdfVersion; all derivation
///       implicitly BRC-42.
///   2 — L11 / L11.5: recovery recipes carry a per-domain `kdfVersion`
///       (`recipe_store.dart`) that self-describes the derivation algorithm.
///       Unilateral domains derive via EP3259724B1 `deriveSegment` (kdf-v2)
///       or, since L11.5, the domain-separated `deriveDomainSegment` (kdf-v3,
///       change/anchor). The era stays 2: per recovery model 2b the v3 cutover
///       rides the existing format via the per-recipe `kdfVersion`, NOT an era
///       bump — mirroring the brain, whose ALGORITHM_VERSION also stays 2 and
///       whose operator validates `algorithmVersion ∈ [1, 2]`. Bumping to 3
///       would be rejected by that operator. Legacy `1` stays readable.
const int kAlgorithmVersion = 2;

/// 64-byte BIP39 PBKDF2 seed length.
const int kSeedBytes = 64;

/// 32-byte salt for the challenge hashes + KEK derivation.
const int kSaltBytes = 32;

/// 12-byte nonce for AES-256-GCM.
const int kGcmNonceBytes = 12;

/// 16-byte authentication tag for AES-256-GCM (128-bit).
const int kGcmTagBytes = 16;

// ─────────────────────────────────────────────────────────────────────
// Schema types (mirrors TS interfaces)
// ─────────────────────────────────────────────────────────────────────

/// The salted-hash challenge bundle Plexus stores. Plexus never sees raw
/// answers — only sha256(salt || normalize(answer)).
class ChallengeBundle {
  final List<String> questions;

  /// 32-byte salt as 64-char hex.
  final String saltHex;

  /// sha256(salt || normalize(answer_i)) per question, as 64-char hex.
  final List<String> answerHashes;

  /// PBKDF2 cost factor. Always [kPbkdf2Iterations] in v1.
  final int kdfIterations;

  const ChallengeBundle({
    required this.questions,
    required this.saltHex,
    required this.answerHashes,
    this.kdfIterations = kPbkdf2Iterations,
  });

  Map<String, dynamic> toJson() => {
        'questions': questions,
        'salt': saltHex,
        'answerHashes': answerHashes,
        'kdfIterations': kdfIterations,
      };
}

/// AES-256-GCM ciphertext envelope around the BIP39 seed.
class EncryptedRecoverySeed {
  /// Hex-encoded ciphertext (variable length).
  final String ciphertextHex;

  /// 12-byte GCM nonce, as 24-char hex.
  final String nonceHex;

  /// 16-byte GCM auth tag, as 32-char hex.
  final String tagHex;

  /// Additional Authenticated Data committed in the GCM tag.
  /// AAD = identityKey(33) || envelopeVersion(1), as 68-char hex.
  final String aadHex;

  const EncryptedRecoverySeed({
    required this.ciphertextHex,
    required this.nonceHex,
    required this.tagHex,
    required this.aadHex,
  });

  Map<String, dynamic> toJson() => {
        'ciphertext': ciphertextHex,
        'nonce': nonceHex,
        'tag': tagHex,
        'aad': aadHex,
      };
}

/// Complete v1 PlexusRecoveryEnvelope. JSON-serialisable; never carries
/// plaintext key material, mnemonic, or plaintext answers.
class PlexusRecoveryEnvelope {
  final int envelopeVersion;
  final String identityKeyHex;
  final String certIdHex;
  final String contactEmail;
  final ChallengeBundle challengeBundle;
  final EncryptedRecoverySeed encryptedRecoverySeed;
  final int algorithmVersion;

  const PlexusRecoveryEnvelope({
    required this.identityKeyHex,
    required this.certIdHex,
    required this.contactEmail,
    required this.challengeBundle,
    required this.encryptedRecoverySeed,
    this.envelopeVersion = kEnvelopeVersion,
    this.algorithmVersion = kAlgorithmVersion,
  });

  Map<String, dynamic> toJson() => {
        'envelopeVersion': envelopeVersion,
        'identityKey': identityKeyHex,
        'certId': certIdHex,
        'contactEmail': contactEmail,
        'challengeBundle': challengeBundle.toJson(),
        'encryptedRecoverySeed': encryptedRecoverySeed.toJson(),
        'algorithmVersion': algorithmVersion,
        // derivationContexts / edgeRecipes / derivationStateSnapshot
        // populate when wallet-headers is wired in PR-C11-4. Sent as
        // empty in PR-C11-2's local-only download path.
        'derivationContexts': const [],
        'edgeRecipes': const [],
        'derivationStateSnapshot': {
          'records': const [],
          'snapshotTimestamp': '',
        },
      };

  /// Canonical JSON serialisation. Matches what TS
  /// `JSON.stringify(envelope)` produces for the same payload.
  String toJsonString() => jsonEncode(toJson());
}

// ─────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────

/// Build inputs the wallet collects locally before envelope generation.
/// All sensitive buffers ([identityKey] is public-only here, the
/// caller's [recoverySeed] + [answers] should be wiped by the caller
/// after build returns).
class BuildEnvelopeInput {
  /// 33-byte compressed secp256k1 identity public key.
  final Uint8List identityKey;

  /// 32-byte (or 16-byte — brain currently uses 16) cert id.
  /// Stored as hex in the envelope; we accept any length here so the
  /// envelope mirrors what the brain reports.
  final Uint8List certId;

  final String contactEmail;
  final List<String> questions;

  /// Raw answers, same order as [questions]. Caller wipes after build.
  final List<String> answers;

  /// The 64-byte BIP39 seed to encrypt. Caller wipes after build.
  final Uint8List recoverySeed;

  /// Override salt + nonce for deterministic tests. Production callers
  /// pass null → cryptographically random bytes.
  final Uint8List? saltOverride;
  final Uint8List? nonceOverride;

  const BuildEnvelopeInput({
    required this.identityKey,
    required this.certId,
    required this.contactEmail,
    required this.questions,
    required this.answers,
    required this.recoverySeed,
    this.saltOverride,
    this.nonceOverride,
  });
}

/// What [buildEnvelope] returns. Sum type: ok | invalid input | invariant fail.
sealed class BuildResult {
  const BuildResult();
}

class BuildOk extends BuildResult {
  final PlexusRecoveryEnvelope envelope;
  const BuildOk(this.envelope);
}

class BuildInvalidInput extends BuildResult {
  final String reason;
  const BuildInvalidInput(this.reason);
}

class BuildInvariantFailed extends BuildResult {
  /// Which §8.2 invariant failed (1..5).
  final int check;
  final String detail;
  const BuildInvariantFailed(this.check, this.detail);
}

/// Build the v1 PlexusRecoveryEnvelope. Runs §8.2 invariant checks
/// against the built envelope before returning so the caller never
/// emits a malformed envelope. Mirrors `buildEnvelope` in the TS
/// reference at `cartridges/wallet-headers/brain/src/plexus/envelope.ts`.
BuildResult buildEnvelope(BuildEnvelopeInput input, {Random? random}) {
  if (input.identityKey.length != 33) {
    return const BuildInvalidInput('identityKey must be 33 bytes (compressed)');
  }
  if (input.contactEmail.isEmpty || !input.contactEmail.contains('@')) {
    return const BuildInvalidInput('contactEmail must contain @');
  }
  if (input.questions.isEmpty) {
    return const BuildInvalidInput('questions must not be empty');
  }
  if (input.questions.length != input.answers.length) {
    return const BuildInvalidInput(
        'answers length must match questions length');
  }
  if (input.recoverySeed.length != kSeedBytes) {
    return const BuildInvalidInput('recoverySeed must be $kSeedBytes bytes');
  }

  // Resolve salt + nonce (overrides for tests, otherwise random).
  final rng = random ?? Random.secure();
  final salt = input.saltOverride ?? _randomBytes(rng, kSaltBytes);
  if (salt.length != kSaltBytes) {
    return const BuildInvalidInput('salt must be $kSaltBytes bytes');
  }
  final nonce = input.nonceOverride ?? _randomBytes(rng, kGcmNonceBytes);
  if (nonce.length != kGcmNonceBytes) {
    return const BuildInvalidInput('nonce must be $kGcmNonceBytes bytes');
  }

  // Normalize answers — same rule as TS normalizeAnswer (NFKC + lowercase
  // + collapse whitespace + trim).
  final normalized =
      input.answers.map(normalizeAnswer).toList(growable: false);

  // Hash each answer: sha256(salt || utf8(normalized_answer)).
  final answerHashes = normalized
      .map((a) => _bytesToHex(_hashAnswer(salt, a)))
      .toList(growable: false);

  // KEK = PBKDF2-SHA256(concat(normalized), salt, 100k, 32 bytes).
  final concatBytes = utf8.encode(normalized.join());
  final kek = _pbkdf2Sha256(
      Uint8List.fromList(concatBytes), salt, kPbkdf2Iterations, 32);

  // AAD = identityKey(33) || envelopeVersion(1).
  final aad = Uint8List(34)
    ..setRange(0, 33, input.identityKey)
    ..[33] = kEnvelopeVersion;

  // AES-256-GCM encrypt seed → ciphertext + 16-byte tag.
  final ciphertextWithTag =
      _aesGcmEncrypt(key: kek, nonce: nonce, aad: aad, plaintext: input.recoverySeed);
  final ciphertext = ciphertextWithTag.sublist(
      0, ciphertextWithTag.length - kGcmTagBytes);
  final tag = ciphertextWithTag.sublist(
      ciphertextWithTag.length - kGcmTagBytes);

  // Best-effort wipe of derived KEK + the concat buffer.
  for (var i = 0; i < kek.length; i++) {
    kek[i] = 0;
  }
  for (var i = 0; i < concatBytes.length; i++) {
    concatBytes[i] = 0;
  }

  final envelope = PlexusRecoveryEnvelope(
    identityKeyHex: _bytesToHex(input.identityKey),
    certIdHex: _bytesToHex(input.certId),
    contactEmail: input.contactEmail,
    challengeBundle: ChallengeBundle(
      questions: List<String>.from(input.questions),
      saltHex: _bytesToHex(salt),
      answerHashes: answerHashes,
    ),
    encryptedRecoverySeed: EncryptedRecoverySeed(
      ciphertextHex: _bytesToHex(ciphertext),
      nonceHex: _bytesToHex(nonce),
      tagHex: _bytesToHex(tag),
      aadHex: _bytesToHex(aad),
    ),
  );

  // Invariant checks per §8.2:
  //   1. No plaintext sk/seed/answer appears in the JSON.
  //   2. answerHashes[i] == sha256(salt || normalize(answer_i)).
  //   3. Ciphertext decrypts under re-derived KEK to the original seed.
  //   (4/5 are caller-side — we don't have identitySk here, and certId
  //    shape was validated at input.)
  final invariantErr = _runInvariantChecks(
      envelope, salt, normalized, input.recoverySeed);
  if (invariantErr != null) return invariantErr;

  // Wipe normalized answers held during invariant checking.
  for (var i = 0; i < normalized.length; i++) {
    normalized[i] = '';
  }

  return BuildOk(envelope);
}

/// Decrypt the recovery seed locally using the same answers as enrollment.
/// Returns null on any failure (wrong answers, tampered ciphertext, malformed
/// hex). Mirrors `decryptRecoverySeed` in the TS reference.
Uint8List? decryptRecoverySeed(
  PlexusRecoveryEnvelope envelope,
  List<String> answers,
) {
  if (answers.length != envelope.challengeBundle.questions.length) return null;
  late Uint8List salt;
  late Uint8List nonce;
  late Uint8List tag;
  late Uint8List ciphertext;
  late Uint8List aad;
  try {
    salt = _hexToBytes(envelope.challengeBundle.saltHex);
    nonce = _hexToBytes(envelope.encryptedRecoverySeed.nonceHex);
    tag = _hexToBytes(envelope.encryptedRecoverySeed.tagHex);
    ciphertext = _hexToBytes(envelope.encryptedRecoverySeed.ciphertextHex);
    aad = _hexToBytes(envelope.encryptedRecoverySeed.aadHex);
  } catch (_) {
    return null;
  }

  final normalized = answers.map(normalizeAnswer).toList(growable: false);
  final concatBytes = utf8.encode(normalized.join());
  final kek = _pbkdf2Sha256(Uint8List.fromList(concatBytes), salt,
      envelope.challengeBundle.kdfIterations, 32);
  for (var i = 0; i < concatBytes.length; i++) {
    concatBytes[i] = 0;
  }

  final ctWithTag = Uint8List(ciphertext.length + tag.length)
    ..setRange(0, ciphertext.length, ciphertext)
    ..setRange(ciphertext.length, ciphertext.length + tag.length, tag);

  try {
    final pt = _aesGcmDecrypt(
        key: kek, nonce: nonce, aad: aad, ciphertextWithTag: ctWithTag);
    return pt;
  } catch (_) {
    return null;
  } finally {
    for (var i = 0; i < kek.length; i++) {
      kek[i] = 0;
    }
  }
}

/// Normalize one challenge answer. **MUST match TS `normalizeAnswer`:**
/// Unicode NFKC + lowercase + collapse internal whitespace + trim.
///
/// Dart's `String` is UTF-16; there's no NFKC primitive in dart:core but
/// for the V1 question set ("mother's maiden name", etc.) the answers
/// are ASCII / common Latin chars where NFKC is a no-op. We document the
/// limitation: operators answering with emoji or composing-codepoints
/// could see a mismatch with the TS reference. PR-C11-3 surfaces this
/// via the retype-confirm UX.
String normalizeAnswer(String raw) {
  // Lowercase, collapse all whitespace runs to a single space, trim.
  final lower = raw.toLowerCase();
  final collapsed = lower.replaceAll(RegExp(r'\s+'), ' ');
  return collapsed.trim();
}

// ─────────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────────

Uint8List _randomBytes(Random rng, int len) {
  final out = Uint8List(len);
  for (var i = 0; i < len; i++) {
    out[i] = rng.nextInt(256);
  }
  return out;
}

Uint8List _hashAnswer(Uint8List salt, String normalizedAnswer) {
  final ans = utf8.encode(normalizedAnswer);
  final buf = Uint8List(salt.length + ans.length)
    ..setRange(0, salt.length, salt)
    ..setRange(salt.length, salt.length + ans.length, ans);
  return SHA256Digest().process(buf);
}

Uint8List _pbkdf2Sha256(
    Uint8List password, Uint8List salt, int iterations, int dkLen) {
  final params = Pbkdf2Parameters(salt, iterations, dkLen);
  final hmac = HMac(SHA256Digest(), 64);
  final kdf = PBKDF2KeyDerivator(hmac);
  kdf.init(params);
  return kdf.process(password);
}

Uint8List _aesGcmEncrypt({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List aad,
  required Uint8List plaintext,
}) {
  final cipher = GCMBlockCipher(AESEngine());
  final params = AEADParameters(
      KeyParameter(key), kGcmTagBytes * 8, nonce, aad);
  cipher.init(true, params);
  return cipher.process(plaintext);
}

Uint8List _aesGcmDecrypt({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List aad,
  required Uint8List ciphertextWithTag,
}) {
  final cipher = GCMBlockCipher(AESEngine());
  final params = AEADParameters(
      KeyParameter(key), kGcmTagBytes * 8, nonce, aad);
  cipher.init(false, params);
  return cipher.process(ciphertextWithTag);
}

String _bytesToHex(Uint8List bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

Uint8List _hexToBytes(String hex) {
  if (hex.length.isOdd) throw FormatException('hex length odd');
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

BuildResult? _runInvariantChecks(
  PlexusRecoveryEnvelope envelope,
  Uint8List salt,
  List<String> normalizedAnswers,
  Uint8List plaintextSeed,
) {
  // Check 1 — no plaintext seed or plaintext answer in the JSON.
  // (We don't have identitySk here; that's the caller's responsibility.)
  final json = envelope.toJsonString();
  final seedHex = _bytesToHex(plaintextSeed);
  if (json.contains(seedHex)) {
    return const BuildInvariantFailed(
        1, 'plaintext recovery seed found in envelope');
  }
  if (json.contains(seedHex.toUpperCase())) {
    return const BuildInvariantFailed(
        1, 'plaintext recovery seed (UPPER) found in envelope');
  }
  for (final ans in normalizedAnswers) {
    if (ans.isEmpty) continue;
    if (json.contains(ans)) {
      return const BuildInvariantFailed(
          1, 'plaintext challenge answer found in envelope');
    }
  }

  // Check 2 — answerHashes[i] == sha256(salt || normalize(answer_i)).
  if (envelope.challengeBundle.answerHashes.length !=
      normalizedAnswers.length) {
    return const BuildInvariantFailed(2, 'answerHashes length mismatch');
  }
  if (envelope.challengeBundle.saltHex != _bytesToHex(salt)) {
    return const BuildInvariantFailed(
        2, 'salt in envelope does not match input salt');
  }
  for (var i = 0; i < normalizedAnswers.length; i++) {
    final expected = _bytesToHex(_hashAnswer(salt, normalizedAnswers[i]));
    if (envelope.challengeBundle.answerHashes[i] != expected) {
      return BuildInvariantFailed(2, 'answerHashes[$i] mismatch');
    }
  }

  // Check 3 — ciphertext decrypts to the original seed under a re-derived KEK.
  final roundTrip = decryptRecoverySeed(envelope, normalizedAnswers);
  if (roundTrip == null) {
    return const BuildInvariantFailed(
        3, 'round-trip decrypt returned null (ciphertext+answers do not round-trip)');
  }
  if (roundTrip.length != plaintextSeed.length) {
    return BuildInvariantFailed(
        3, 'round-trip length mismatch (${roundTrip.length} vs ${plaintextSeed.length})');
  }
  var diff = 0;
  for (var i = 0; i < plaintextSeed.length; i++) {
    diff |= plaintextSeed[i] ^ roundTrip[i];
  }
  if (diff != 0) {
    return const BuildInvariantFailed(
        3, 'round-trip plaintext bytes differ');
  }

  return null;
}

// PKCS7Padding referenced only to keep the AES import surface stable
// across pointycastle versions — the GCM mode itself does not pad.
// ignore: unused_element
PKCS7Padding _unused = PKCS7Padding();

```
