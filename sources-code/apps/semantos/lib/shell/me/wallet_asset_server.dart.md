---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/me/wallet_asset_server.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.121409+00:00
---

# apps/semantos/lib/shell/me/wallet_asset_server.dart

```dart
// C11 PR-C11-4a — Loopback HTTP server for the wallet webview.
//
// Why this exists:
//   `WebViewController.loadFlutterAsset()` on Android calls
//   `loadUrl("file:///android_asset/flutter_assets/<path>")`, putting the
//   wallet at the `file://` origin — which the browser security model
//   reports as the "null" origin. ES module loads
//   (`<script type="module">`) and `fetch()` from null origins are
//   blocked by CORS:
//
//       Access to script at 'file:///.../wallet-page.js' from origin
//       'null' has been blocked by CORS policy: Cross origin requests
//       are only supported for protocol schemes: http, data, chrome,
//       chrome-untrusted, https.
//
//   wallet.html uses `<script type="module" src="./wallet-page.js">`
//   and wallet-page.js does `fetch('./cell-engine-embedded.wasm')`, so
//   both load steps hit the null-origin wall. The webview rendered
//   only the empty `<div id="app"></div>` and dom-len stayed at 89.
//
// Fix:
//   Bind a tiny in-process HTTP server to `127.0.0.1` on a kernel-
//   chosen port, serve any file under `assets/wallet/` from
//   `rootBundle.load()`, and point the webview at
//   `http://127.0.0.1:<port>/wallet.html`. The origin is now a real
//   `http` scheme, CORS is satisfied, modules + fetch + wasm all work.
//
// Scope of this server:
//   - 127.0.0.1 only — never binds to a routable interface, so the
//     wallet UI is reachable only from inside this app process. The
//     emulator's NAT does not expose loopback to the host or LAN.
//   - Lifetime is the wallet sheet — `start()` in `initState`, `stop()`
//     in `dispose`. Each sheet open gets a fresh port; no shared state.
//   - Read-only — no POST/PUT/DELETE handling. Asset misses 404.
//   - No directory traversal — requests must resolve to a path inside
//     `assets/wallet/` after normalisation.
//
// This is intentionally not a long-lived shell-wide service. PR-C11-4b
// adds the JavaScriptChannel bridge for Dart ↔ JS messaging; the server
// here just satisfies the origin requirement so the bridge can layer on
// top of a working page.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError, debugPrint;
import 'package:flutter/services.dart' show rootBundle;

/// Root of the bundled wallet asset tree. All requests on the loopback
/// server resolve relative to this prefix (so `GET /wallet.html` reads
/// `assets/wallet/wallet.html` from `rootBundle`).
const String _kAssetRoot = 'assets/wallet';

/// MIME types we care about. The CORS-sensitive ones (`text/html`,
/// `application/javascript`, `application/wasm`) are explicit so the
/// browser uses the right loader. Anything else falls back to
/// `application/octet-stream`.
const Map<String, String> _kMimeByExtension = <String, String>{
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.map': 'application/json; charset=utf-8',
};

/// Per-sheet loopback server hosting `assets/wallet/` from `rootBundle`.
class WalletAssetServer {
  WalletAssetServer();

  HttpServer? _server;

  /// Resolved base URL (`http://127.0.0.1:<port>/`) once `start()` has
  /// completed. Null before start or after stop.
  Uri? get baseUrl {
    final s = _server;
    if (s == null) return null;
    return Uri(scheme: 'http', host: '127.0.0.1', port: s.port, path: '/');
  }

  /// Bind the server, start accepting requests, and return its base
  /// URL. Idempotent — a second call without `stop()` between them
  /// returns the existing base URL.
  Future<Uri> start() async {
    if (_server != null) return baseUrl!;
    // Port 0 → kernel picks a free port. shared:false keeps the socket
    // bound to this isolate; no cross-isolate accept races.
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    _server = server;
    debugPrint('[wallet] [INFO] [wallet-asset-server] '
        'listening at http://127.0.0.1:${server.port}/');
    // Fire-and-forget request loop. Errors are logged but don't kill
    // the server — a bad request must not take down the wallet sheet.
    unawaited(_serve(server));
    return baseUrl!;
  }

  /// Close the listening socket. Safe to call multiple times.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
      debugPrint('[wallet] [INFO] [wallet-asset-server] stopped');
    }
  }

  Future<void> _serve(HttpServer server) async {
    await for (final HttpRequest request in server) {
      // Each request is independent; failures here must not stop the
      // accept loop.
      unawaited(_handle(request).catchError((Object e, StackTrace s) {
        debugPrint('[wallet] [ERROR] [wallet-asset-server] '
            'handler crashed: $e');
      }));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    // Strip leading slash; map "/" to wallet.html.
    var path = request.uri.path;
    if (path.startsWith('/')) path = path.substring(1);
    if (path.isEmpty) path = 'wallet.html';

    // Defensive — refuse anything that looks like an escape attempt.
    // The asset bundle is read-only so the worst case is a 404, but
    // we don't want `..` or absolute paths reaching `rootBundle.load`.
    if (path.contains('..') || path.startsWith('/')) {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }

    final assetKey = '$_kAssetRoot/$path';
    Uint8List bytes;
    try {
      final data = await rootBundle.load(assetKey);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on FlutterError {
      // rootBundle.load throws FlutterError on a missing asset.
      debugPrint('[wallet] [WARN] [wallet-asset-server] '
          '404 $assetKey');
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final mime = _mimeFor(path);
    response.statusCode = HttpStatus.ok;
    response.headers.set(HttpHeaders.contentTypeHeader, mime);
    response.headers.set(HttpHeaders.contentLengthHeader, bytes.length);
    // Same-origin assets, no caching needed for an in-app server.
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    response.add(bytes);
    await response.close();
  }

  String _mimeFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return 'application/octet-stream';
    final ext = path.substring(dot).toLowerCase();
    return _kMimeByExtension[ext] ?? 'application/octet-stream';
  }
}

```
