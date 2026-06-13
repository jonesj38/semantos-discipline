---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/headers_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.104980+00:00
---

# apps/semantos/lib/src/wallet/headers_client.dart

```dart
// C11 PR-C11-7b — BSV chain headers client.
//
// References:
//   - cartridges/bsv-anchor-bundle/brain/zig/src/headers_http.zig
//     — the brain-side `headers serve` HTTP implementation.
//   - Renderer contract: docs/design/WALLET-RENDERER-CONTRACT.md §5
//     (Dart-side SPV / BEEF validation).
//
// What this owns:
//   The wallet's read-only view of the local SPV header chain. The
//   brain runs `brain headers serve --http-port <port>` which exposes
//   four routes; this client wraps them so the wallet (and PR-C11-7c's
//   BEEF validator, when it lands) can fetch the data it needs for
//   merkle-proof verification.
//
// Brain HTTP routes (per headers_http.zig):
//   - GET /api/v1/chain/header/byHeight/tip
//   - GET /api/v1/chain/header/byHeight/{h}
//   - GET /api/v1/chain/header/byHash/{hashHex}
//   - GET /api/v1/chain/header/range?from=N&to=M       (range — unused here)
//
// Response shape (80-byte serialized header, raw bytes — the routes
// return `application/octet-stream`):
//
//     version (4 LE) || prevBlockHash (32) || merkleRoot (32) ||
//     timestamp (4 LE) || bits (4 LE) || nonce (4 LE)         = 80 bytes
//
// The tip route also returns the height as the `X-Header-Height`
// response header.
//
// What this does NOT own:
//   - BEEF parsing / validation. That lands in 7c — it needs to
//     iterate the BUMP merkle path against the headers this client
//     fetches.
//   - Header sync. The brain does that; the wallet just reads.
//
// Testing seam:
//   `HeadersClient` is abstract. `HttpHeadersClient` is the
//   production impl. `InMemoryHeadersClient` is a test fixture that
//   holds a fixed map of (height ↔ header) and (hash ↔ header) plus
//   a tip. The downstream BEEF validator can be exercised end-to-end
//   against the in-memory variant without an actual brain running.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/sha256.dart';

/// 80-byte serialized BSV block header.
const int kBlockHeaderLength = 80;

/// One header row: the 80 raw bytes plus its block hash and height.
/// The hash is `sha256(sha256(bytes))` reversed (BSV display order).
class BlockHeader {
  const BlockHeader({
    required this.bytes,
    required this.blockHashHex,
    required this.height,
  });

  /// 80-byte serialized header.
  final Uint8List bytes;

  /// 32-byte block hash, display-hex (big-endian — explorer order).
  final String blockHashHex;

  /// Height in the chain. `0` for genesis.
  final int height;
}

/// Read-only view of the chain headers a SPV proof needs.
abstract class HeadersClient {
  Future<BlockHeader> getTip();
  Future<BlockHeader> getByHeight(int height);

  /// Returns null if the hash isn't known to the local chain — a
  /// legitimate "fork or pending sync" answer, not an error.
  Future<BlockHeader?> getByHash(String blockHashHex);
}

/// Production impl: talks to `brain headers serve` over HTTP.
class HttpHeadersClient implements HeadersClient {
  HttpHeadersClient({
    required Uri baseUrl,
    http.Client? httpClient,
  })  : _baseUrl = baseUrl,
        _http = httpClient ?? http.Client();

  final Uri _baseUrl;
  final http.Client _http;

  @override
  Future<BlockHeader> getTip() async {
    final uri = _baseUrl.resolve('/api/v1/chain/header/byHeight/tip');
    final resp = await _http.get(uri);
    if (resp.statusCode != 200) {
      throw HeadersClientException(
          'getTip → HTTP ${resp.statusCode}: ${resp.body}');
    }
    final bytes = _bytes(resp);
    return BlockHeader(
      bytes: bytes,
      blockHashHex: displayHashOf(bytes),
      height: _heightHeader(resp),
    );
  }

  @override
  Future<BlockHeader> getByHeight(int height) async {
    if (height < 0) {
      throw ArgumentError.value(height, 'height', 'must be non-negative');
    }
    final uri =
        _baseUrl.resolve('/api/v1/chain/header/byHeight/$height');
    final resp = await _http.get(uri);
    if (resp.statusCode == 404) {
      throw HeadersClientException(
          'getByHeight($height) → 404 (height not in local chain)');
    }
    if (resp.statusCode != 200) {
      throw HeadersClientException(
          'getByHeight($height) → HTTP ${resp.statusCode}: ${resp.body}');
    }
    final bytes = _bytes(resp);
    return BlockHeader(
      bytes: bytes,
      blockHashHex: displayHashOf(bytes),
      height: height,
    );
  }

  @override
  Future<BlockHeader?> getByHash(String blockHashHex) async {
    _assertHex32(blockHashHex);
    final uri = _baseUrl.resolve(
        '/api/v1/chain/header/byHash/${blockHashHex.toLowerCase()}');
    final resp = await _http.get(uri);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw HeadersClientException(
          'getByHash → HTTP ${resp.statusCode}: ${resp.body}');
    }
    final bytes = _bytes(resp);
    return BlockHeader(
      bytes: bytes,
      blockHashHex: blockHashHex.toLowerCase(),
      height: _heightHeader(resp),
    );
  }

  Uint8List _bytes(http.Response resp) {
    final b = resp.bodyBytes;
    if (b.length != kBlockHeaderLength) {
      debugPrint('[wallet] [WARN] [headers-client] unexpected body length '
          '${b.length} (expected $kBlockHeaderLength)');
    }
    return Uint8List.fromList(b);
  }

  int _heightHeader(http.Response resp) {
    final raw = resp.headers['x-header-height'];
    if (raw == null) {
      throw HeadersClientException(
          'response missing X-Header-Height (brain headers HTTP contract)');
    }
    final h = int.tryParse(raw);
    if (h == null || h < 0) {
      throw HeadersClientException('invalid X-Header-Height "$raw"');
    }
    return h;
  }
}

/// Test fixture: in-memory header set. Used by 7c's BEEF validator
/// tests + 7b's own unit tests.
class InMemoryHeadersClient implements HeadersClient {
  InMemoryHeadersClient({BlockHeader? tip}) : _tip = tip;

  final Map<int, BlockHeader> _byHeight = {};
  final Map<String, BlockHeader> _byHash = {};
  BlockHeader? _tip;

  /// Insert a header. Indexes by both height and hash. Promotes to
  /// tip if it's the highest height seen.
  void put(BlockHeader header) {
    _byHeight[header.height] = header;
    _byHash[header.blockHashHex.toLowerCase()] = header;
    if (_tip == null || header.height > _tip!.height) {
      _tip = header;
    }
  }

  /// Override the tip explicitly. Used for "tip ahead of index" tests.
  void setTip(BlockHeader header) {
    _tip = header;
  }

  @override
  Future<BlockHeader> getTip() async {
    final t = _tip;
    if (t == null) {
      throw HeadersClientException('InMemoryHeadersClient: tip not set');
    }
    return t;
  }

  @override
  Future<BlockHeader> getByHeight(int height) async {
    final h = _byHeight[height];
    if (h == null) {
      throw HeadersClientException(
          'InMemoryHeadersClient: no header at height $height');
    }
    return h;
  }

  @override
  Future<BlockHeader?> getByHash(String blockHashHex) async {
    _assertHex32(blockHashHex);
    return _byHash[blockHashHex.toLowerCase()];
  }
}

/// Common error for headers-client failures.
class HeadersClientException implements Exception {
  HeadersClientException(this.message);
  final String message;
  @override
  String toString() => 'HeadersClientException: $message';
}

/// Compute the display-hex block hash for an 80-byte header:
/// `sha256(sha256(bytes))` reversed (big-endian display order).
/// Exposed so callers that already have the raw header bytes can
/// derive the hash without round-tripping through HTTP.
String displayHashOf(Uint8List headerBytes) {
  final inner = SHA256Digest().process(headerBytes);
  final outer = SHA256Digest().process(inner);
  final sb = StringBuffer();
  for (var i = outer.length - 1; i >= 0; i--) {
    sb.write(outer[i].toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

void _assertHex32(String hex) {
  if (hex.length != 64) {
    throw ArgumentError.value(
        hex.length, 'blockHashHex.length', 'must be 64 (32 bytes hex)');
  }
  for (var i = 0; i < hex.length; i++) {
    final c = hex.codeUnitAt(i);
    final ok = (c >= 0x30 && c <= 0x39) ||
        (c >= 0x61 && c <= 0x66) ||
        (c >= 0x41 && c <= 0x46);
    if (!ok) {
      throw ArgumentError.value(
          hex, 'blockHashHex', 'non-hex char at index $i');
    }
  }
}

```
