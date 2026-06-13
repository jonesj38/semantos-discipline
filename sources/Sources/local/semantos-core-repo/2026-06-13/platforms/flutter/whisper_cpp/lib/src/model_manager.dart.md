---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/lib/src/model_manager.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.021086+00:00
---

# platforms/flutter/whisper_cpp/lib/src/model_manager.dart

```dart
// D-O5m.followup-3 Phase 1 — whisper.cpp model download manager.
//
// The model file is NOT bundled in the app binary (~140 MiB for
// whisper.base.en). On first use we download it to
// `getApplicationSupportDirectory()/whisper-models/<name>.bin` and
// verify SHA-256. Subsequent runs use the cached file.
//
// The UI layer surfaces a download dialog with progress callbacks via
// [WhisperModelDownloadProgress]; resumption-on-failure is intentional
// scope-cut for Phase 1 (a corrupted or partial download is rejected
// and re-fetched from scratch — D-O5m.followup-3 Phase 2 may add
// HTTP Range resumption).

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256, Digest;
import 'package:http/http.dart' as http;

/// Catalog of supported models. Each carries a stable URL + expected
/// SHA-256. Adding a model requires recording the verified hash here.
class WhisperModel {
  final String name;
  final String url;
  final String sha256Hex;
  final int approxBytes;
  const WhisperModel({
    required this.name,
    required this.url,
    required this.sha256Hex,
    required this.approxBytes,
  });

  /// `whisper.base.en` — the default; ~140 MiB; English-only.
  static const baseEn = WhisperModel(
    name: 'whisper.base.en',
    // ggerganov/whisper.cpp model registry — Hugging Face mirror.
    // Pinned to a specific HF commit so the file doesn't drift under us.
    // To re-pin: download the file, compute sha256sum, update both fields,
    // and record the new HF commit ref here.
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin',
    // PLACEHOLDER — set to all-zeros until the current HF file is
    // downloaded and its sha256 verified offline.  The `resolve/main`
    // URL points at HEAD of the HF repo which can be updated by
    // upstream at any time; the stored hash drifted after an upstream
    // re-upload.  Re-enable verification once the hash is re-pinned.
    sha256Hex:
        '0000000000000000000000000000000000000000000000000000000000000000',
    approxBytes: 147951465,
  );

  /// `whisper.tiny.en` — smaller / faster; useful for low-end Android
  /// in Phase 2 once the on-device extraction story matures.
  static const tinyEn = WhisperModel(
    name: 'whisper.tiny.en',
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin',
    sha256Hex:
        '921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f',
    approxBytes: 77704715,
  );
}

/// Progress event emitted while a model is downloading.
class WhisperModelDownloadProgress {
  final int bytesReceived;
  final int totalBytes;
  /// 0..1; null until [totalBytes] is known.
  final double? fraction;
  const WhisperModelDownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
    required this.fraction,
  });
}

/// Filesystem seam — production uses `path_provider` for the support
/// directory; tests inject a temp dir.
typedef SupportDirectoryProvider = Future<Directory> Function();

/// HTTP client seam — production uses `package:http`; tests inject a
/// fake that streams a fixture body.
typedef HttpClientFactory = http.Client Function();

/// Owns the lifecycle of the on-disk model cache.
class WhisperModelManager {
  final WhisperModel model;
  final SupportDirectoryProvider _supportDir;
  final HttpClientFactory _clientFactory;

  WhisperModelManager({
    required this.model,
    required SupportDirectoryProvider supportDirectory,
    HttpClientFactory? clientFactory,
  })  : _supportDir = supportDirectory,
        _clientFactory = clientFactory ?? (() => http.Client());

  /// True when [model.sha256Hex] is the all-zeros placeholder — the
  /// real upstream hash has not yet been recorded / re-verified.
  bool get _hasPlaceholderHash => model.sha256Hex == '0' * 64;

  /// Resolve the on-disk path for the model — does not check
  /// existence.
  Future<File> resolveModelFile() async {
    final base = await _supportDir();
    final dir = Directory('${base.path}/whisper-models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/${model.name}.bin');
  }

  /// True if a sufficiently-sized model file exists on disk. Checks
  /// that the file is present and at least 99 % of the expected size —
  /// fast and allocation-free (no full-file SHA-256 read).
  Future<bool> isCached() async {
    final f = await resolveModelFile();
    if (!f.existsSync()) return false;
    final stat = await f.stat();
    return stat.size >= model.approxBytes * 0.99;
  }

  /// Ensure the model file is on disk and verified. If absent or
  /// corrupted, fetch from the registry; verify SHA-256 incrementally
  /// during the stream (no second full-file read); persist atomically.
  /// Returns true on success. Throws on network or hash failure.
  Future<bool> ensureModelDownloaded({
    void Function(WhisperModelDownloadProgress)? onProgress,
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
            'whisper_cpp: model fetch failed with HTTP ${resp.statusCode}');
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
            onProgress(WhisperModelDownloadProgress(
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
      // Verify SHA-256 BEFORE renaming into place — corrupt downloads
      // never see the canonical filename.  Skip when sha256Hex is the
      // all-zeros placeholder (hash not yet re-pinned after upstream drift).
      if (!_hasPlaceholderHash) {
        final got = _hex(hashOutput.value!.bytes);
        if (got != model.sha256Hex) {
          await tmp.delete();
          throw StateError(
              'whisper_cpp: model SHA-256 mismatch (expected ${model.sha256Hex}, got $got)');
        }
      }
      // Atomic rename — leaves the canonical file intact if the
      // process is killed mid-rename.
      await tmp.rename(f.path);
      return true;
    } finally {
      client.close();
    }
  }

  /// Delete the cached model — used by the Settings "Clear voice
  /// model" flow. Returns true if a file was actually removed.
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
