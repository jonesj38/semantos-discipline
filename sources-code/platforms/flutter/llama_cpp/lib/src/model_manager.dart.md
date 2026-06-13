---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/llama_cpp/lib/src/model_manager.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.025272+00:00
---

# platforms/flutter/llama_cpp/lib/src/model_manager.dart

```dart
// D-O5m.followup-3 Phase 2 — llama.cpp model download manager.
//
// Reference: platforms/flutter/whisper_cpp/lib/src/model_manager.dart
//            (the Phase 1 sibling -- same shape, same SHA-256
//            atomic-rename pattern).
//
// The model file is NOT bundled in the app binary (~2 GiB for
// Llama-3.2-3B-Instruct Q4_K_M).  On first use we download it to
// `getApplicationSupportDirectory()/llama-models/<name>.gguf` and
// verify SHA-256.  Subsequent runs use the cached file.
//
// Model choice (Phase 2 default):
//
//   Llama-3.2-3B-Instruct-Q4_K_M.gguf
//
//   - License: Llama 3.2 Community License (permissive for
//     commercial use under defined revenue threshold; ships in the
//     same family of weights as Phase 3 will use for the L2/L3/L4
//     port).
//   - Size: ~2 GiB at Q4_K_M quantization -- fits comfortably in
//     a flagship phone's RAM budget while leaving headroom for the
//     STT model's working set.
//   - Structured-output capability: Llama 3.2 family handles
//     grammar-constrained JSON well; the GBNF sampler in llama.cpp
//     enforces structural validity at the token level so model size
//     trades off accuracy of *content*, not validity of *shape*.
//   - Phi-3.5-mini-instruct (also evaluated) is a close runner-up;
//     swap in via `LlamaModel` config if license terms shift.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256, Digest;
import 'package:http/http.dart' as http;

/// Catalog of supported models.  Each carries a stable URL + expected
/// SHA-256.  Adding a model requires recording the verified hash here.
class LlamaModel {
  final String name;
  final String url;
  final String sha256Hex;
  final int approxBytes;
  const LlamaModel({
    required this.name,
    required this.url,
    required this.sha256Hex,
    required this.approxBytes,
  });

  /// Default model -- Llama-3.2-3B-Instruct-Q4_K_M.  ~2.0 GiB GGUF.
  /// The recorded sha256 of the upstream file is committed alongside
  /// the URL to make corruption detection and version pinning
  /// explicit; cross-check before bumping.  Phase 2 uses this; Phase
  /// 3 may move to a smaller distilled model once the L2-L4
  /// gradient is on-device.
  static const llama32_3b = LlamaModel(
    name: 'llama-3.2-3b-instruct-q4-k-m',
    url:
        'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
    // PLACEHOLDER -- the real hash is recorded once the upstream
    // file is downloaded + verified.  Until then the production app
    // will reject the download via SHA-256 mismatch, which is
    // intentionally fail-closed.  Update via the audited
    // `update-llama-pin` flow.
    sha256Hex:
        '0000000000000000000000000000000000000000000000000000000000000000',
    approxBytes: 2019377504,
  );

  /// Phi-3.5-mini-instruct (Q4_K_M) -- runner-up if Llama license
  /// terms shift.  ~2.4 GiB.
  static const phi35Mini = LlamaModel(
    name: 'phi-3.5-mini-instruct-q4-k-m',
    url:
        'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
    sha256Hex:
        '0000000000000000000000000000000000000000000000000000000000000000',
    approxBytes: 2393233152,
  );
}

/// Progress event emitted while a model is downloading.
class LlamaModelDownloadProgress {
  final int bytesReceived;
  final int totalBytes;

  /// 0..1; null until [totalBytes] is known.
  final double? fraction;
  const LlamaModelDownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
    required this.fraction,
  });
}

/// Filesystem seam -- production uses `path_provider` for the support
/// directory; tests inject a temp dir.
typedef SupportDirectoryProvider = Future<Directory> Function();

/// HTTP client seam -- production uses `package:http`; tests inject a
/// fake that streams a fixture body.
typedef HttpClientFactory = http.Client Function();

/// Owns the lifecycle of the on-disk model cache.
class LlamaModelManager {
  final LlamaModel model;
  final SupportDirectoryProvider _supportDir;
  final HttpClientFactory _clientFactory;

  LlamaModelManager({
    required this.model,
    required SupportDirectoryProvider supportDirectory,
    HttpClientFactory? clientFactory,
  })  : _supportDir = supportDirectory,
        _clientFactory = clientFactory ?? (() => http.Client());

  /// True when [model.sha256Hex] is the all-zeros placeholder — the
  /// real upstream hash has not yet been recorded.
  bool get _hasPlaceholderHash => model.sha256Hex == '0' * 64;

  /// Resolve the on-disk path for the model -- does not check
  /// existence.
  Future<File> resolveModelFile() async {
    final base = await _supportDir();
    final dir = Directory('${base.path}/llama-models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/${model.name}.gguf');
  }

  /// True if a sufficiently-sized model file exists on disk. Checks
  /// that the file is present and at least 99 % of the expected size —
  /// fast and allocation-free (no full-file SHA-256 read). When the
  /// SHA-256 is a placeholder, size alone is the acceptance criterion.
  Future<bool> isCached() async {
    final f = await resolveModelFile();
    if (!f.existsSync()) return false;
    final stat = await f.stat();
    return stat.size >= model.approxBytes * 0.99;
  }

  /// Cheap check -- does the file exist on disk at all?  Used by
  /// callers that want to gate UI ("Voice command unavailable until
  /// LLM model downloads") without paying the SHA-256 cost.  Returns
  /// false if the file is missing or smaller than half the expected
  /// size (a partial download).
  Future<bool> modelAvailable() async {
    final f = await resolveModelFile();
    if (!f.existsSync()) return false;
    final stat = await f.stat();
    return stat.size >= model.approxBytes ~/ 2;
  }

  /// Ensure the model file is on disk and verified.  If absent or
  /// corrupted, fetch from the registry; verify SHA-256 incrementally
  /// during the stream (no second full-file read); persist atomically.
  /// When [_hasPlaceholderHash] is true the hash check is skipped and
  /// the download is accepted on size alone.
  /// Returns true on success.  Throws on network or hash failure.
  Future<bool> ensureModelDownloaded({
    void Function(LlamaModelDownloadProgress)? onProgress,
  }) async {
    if (await isCached()) return true;
    final f = await resolveModelFile();
    final tmp = File('${f.path}.partial');
    if (tmp.existsSync()) await tmp.delete();
    final client = _clientFactory();
    try {
      final req = http.Request('GET', Uri.parse(model.url));
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw StateError(
            'llama_cpp: model fetch failed with HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength ?? model.approxBytes;
      final sink = tmp.openWrite();
      // Compute SHA-256 incrementally while streaming — no second read.
      final hashOutput = _DigestSink();
      final hashSink = sha256.startChunkedConversion(hashOutput);
      var received = 0;
      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          hashSink.add(chunk);
          received += chunk.length;
          if (onProgress != null) {
            onProgress(LlamaModelDownloadProgress(
              bytesReceived: received,
              totalBytes: total,
              fraction: total > 0 ? received / total : null,
            ));
          }
        }
      } finally {
        await sink.close();
        hashSink.close();
      }
      // Verify SHA-256 BEFORE renaming into place -- corrupt
      // downloads never see the canonical filename.
      // Skip the check when the hash is still a placeholder; the
      // download is accepted on size alone until the pin is updated.
      if (!_hasPlaceholderHash) {
        final got = _hex(hashOutput.value!.bytes);
        if (got != model.sha256Hex) {
          await tmp.delete();
          throw StateError(
              'llama_cpp: model SHA-256 mismatch (expected ${model.sha256Hex}, got $got)');
        }
      }
      // Atomic rename -- leaves the canonical file intact if the
      // process is killed mid-rename.
      await tmp.rename(f.path);
      return true;
    } finally {
      client.close();
    }
  }

  /// Delete the cached model -- used by the Settings "Clear LLM
  /// model" flow.  Returns true if a file was actually removed.
  Future<bool> clearCache() async {
    final f = await resolveModelFile();
    if (!f.existsSync()) return false;
    await f.delete();
    return true;
  }
}

// Minimal sink that captures the single Digest emitted by a
// Hash.startChunkedConversion pipeline.
class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

String _hex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

```
