---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/pairing/decode_token.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.589190+00:00
---

# cartridges/jambox/mobile/lib/src/pairing/decode_token.dart

```dart
// D-O5m — Decode a base64url-encoded pairing token into PairPayload.
//
// Port of `decodePairingToken` in
// `extensions/oddjobz/src/device-pair-client.ts`. Does NOT verify the
// operator signature — the brain re-verifies on accept. Throws
// `PairPayloadFormatException` for malformed tokens (with operator-
// readable messages so the pairing screen can surface them directly).

import 'dart:convert';

import 'pair_payload.dart';

/// Strip a URL wrapper if present, returning the bare base64url token.
///
/// Smoke-test pass #1, fix #16 — pre-fix this only handled the exact
/// `?token=` substring case; if the operator pasted a `semantos-pair://`
/// URL with a `&` parameter ordering or any other shape Dart's `Uri`
/// recognised but the substring search didn't, the bare URL ran
/// through base64 decode + failed with "invalid character at index 6"
/// (the `:` of `semantos-pair://`).
///
/// The pair token URLs that brain + the helm CLI emit have the shape
/// `semantos-pair://<brain-domain>/pair?token=<base64url>`.  Accept
/// either the full URL OR the bare `<base64url>` token.
String _stripPairUrlScheme(String raw) {
  // Trim leading/trailing whitespace and a one-shot trailing newline —
  // operators copy-paste from terminal output where wrapping is common.
  var s = raw.trim();
  if (s.isEmpty) return s;

  // Try strict URI parsing first.  If it parses AND has a `token`
  // query parameter, return that.  This handles every well-formed
  // shape (semantos-pair://, https://, brain-pair://, or any future
  // scheme that follows the same `?token=` query convention).
  try {
    final uri = Uri.parse(s);
    if (uri.queryParameters.containsKey('token')) {
      return uri.queryParameters['token']!;
    }
  } catch (_) {
    // Fall through to substring search.
  }

  // Fallback: legacy substring shape (kept for back-compat with any
  // QR encoders that emit something Dart's URI parser rejects, e.g.
  // unencoded `+` characters).  Use lastIndexOf so `?token=foo&...`
  // and any pre-?token chars don't trip the search.
  const marker = '?token=';
  final idx = s.indexOf(marker);
  if (idx >= 0) {
    var tail = s.substring(idx + marker.length);
    // Strip any trailing &param=value the operator's clipboard added.
    final amp = tail.indexOf('&');
    if (amp >= 0) tail = tail.substring(0, amp);
    return tail;
  }

  // No URL wrapper — assume it's a bare base64url token.
  return s;
}

/// Decode base64url -> bytes (with padding tolerance, since the Semantos Brain
/// emitter strips `=` padding per RFC 4648 §5).
List<int> _base64UrlDecode(String b64) {
  // Normalise base64url -> base64 + add padding.
  final pad = (4 - b64.length % 4) % 4;
  final padded = b64 + ('=' * pad);
  final std = padded.replaceAll('-', '+').replaceAll('_', '/');
  return base64.decode(std);
}

/// Decode a base64url-encoded pairing token into a typed `PairPayload`.
///
/// Throws `PairPayloadFormatException` if:
///   - the token is not valid base64url-encoded JSON,
///   - the version is not [wireVersion] (currently 2),
///   - the domain is not [wireDomain],
///   - a required field is missing or has the wrong type,
///   - operator_root_pub is not 66 hex chars,
///   - context_tag is outside 0..255.
PairPayload decodePairingToken(String tokenBase64Url) {
  final bare = _stripPairUrlScheme(tokenBase64Url);
  late final List<int> bytes;
  try {
    bytes = _base64UrlDecode(bare);
  } catch (e) {
    throw PairPayloadFormatException('token is not valid base64url: $e');
  }
  late final dynamic parsed;
  try {
    parsed = json.decode(utf8.decode(bytes));
  } catch (e) {
    throw PairPayloadFormatException('token JSON parse failed: $e');
  }
  if (parsed is! Map<String, dynamic>) {
    throw const PairPayloadFormatException(
        'token must decode to a JSON object');
  }
  final obj = parsed;

  int asInt(String key) {
    final v = obj[key];
    if (v is! int) {
      throw PairPayloadFormatException(
          'device-pair payload: $key must be a number');
    }
    return v;
  }

  String asStr(String key) {
    final v = obj[key];
    if (v is! String) {
      throw PairPayloadFormatException(
          'device-pair payload: $key must be a string');
    }
    return v;
  }

  List<String> asStrArray(String key) {
    final v = obj[key];
    if (v is! List) {
      throw PairPayloadFormatException(
          'device-pair payload: $key must be an array');
    }
    final out = <String>[];
    for (var i = 0; i < v.length; i++) {
      final el = v[i];
      if (el is! String) {
        throw PairPayloadFormatException(
            'device-pair payload: $key[$i] must be a string');
      }
      out.add(el);
    }
    return out;
  }

  // Check version + domain BEFORE pulling other fields so a v1 (or
  // v3+) payload surfaces a clean error at the version level instead
  // of a downstream missing-field complaint. Mirrors the TS reference.
  final v = asInt('v');
  if (v != wireVersion) {
    throw PairPayloadFormatException(
        'device-pair payload: unknown version $v; expected $wireVersion');
  }
  final domain = asStr('domain');
  if (domain != wireDomain) {
    throw PairPayloadFormatException(
        'device-pair payload: unknown domain $domain; expected $wireDomain');
  }

  final decoded = PairPayload(
    v: v,
    domain: domain,
    operatorRootCertId: asStr('operator_root_cert_id'),
    operatorRootPub: asStr('operator_root_pub'),
    contextTag: asInt('context_tag'),
    label: asStr('label'),
    capabilities: asStrArray('capabilities'),
    expiresAt: asInt('expires_at'),
    nonce: asStr('nonce'),
    brainPairEndpoint: asStr('brain_pair_endpoint'),
    brainWssEndpoint: asStr('brain_wss_endpoint'),
    brainPinCertId: asStr('brain_pin_cert_id'),
    brainPinPubkey: asStr('brain_pin_pubkey'),
    signature: asStr('signature'),
  );
  if (decoded.operatorRootPub.length != 66) {
    throw const PairPayloadFormatException(
        'device-pair payload: operator_root_pub must be 66 hex chars');
  }
  if (decoded.contextTag < 0 || decoded.contextTag > 255) {
    throw const PairPayloadFormatException(
        'device-pair payload: context_tag must be u8');
  }
  return decoded;
}

```
