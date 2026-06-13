---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/lib/src/bindings.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.021688+00:00
---

# platforms/flutter/whisper_cpp/lib/src/bindings.dart

```dart
// D-O5m.followup-3 Phase 1 — dart:ffi bindings to whisper.cpp.
//
// Reference: upstream whisper.cpp public headers — `whisper.h`. The
// bindings here cover the four entry points the high-level
// [WhisperService] uses:
//
//   - whisper_init_from_file(model_path: char*) → whisper_context*
//   - whisper_full(ctx, params, samples, n_samples) → int (0 on success)
//   - whisper_full_get_segment_text(ctx, i_segment) → char*
//   - whisper_free(ctx)
//
// We DO NOT vendor whisper.cpp source in the repo (~30k lines). Instead
// the platform-side build wiring (android/CMakeLists.txt and the iOS/
// macOS podspec) fetches the upstream repo at build time and pins to
// the recorded commit. See `WHISPER_CPP_PIN` in [WhisperBindings].
//
// The base class [WhisperBindingsBase] is the seam tests inject — a
// stub impl asserts the right calls happen on transcribe() without
// loading the real model.

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Pinned upstream whisper.cpp commit. CMake / CocoaPods FetchContent
/// stanzas reference this exact rev so a clean build is reproducible.
/// Update via the audited `update-whisper-pin` flow only — bumping
/// this changes the C ABI shape covered by [WhisperBindings].
const String kWhisperCppPin = 'v1.6.0';

/// Default model — best speed/accuracy tradeoff for English-only
/// site-tradies use case. Multilingual models (whisper.base, etc.)
/// can be selected via [WhisperModel] in `model_manager.dart`.
const String kDefaultModelName = 'whisper.base.en';

/// Abstract base — the seam tests inject. Production wires
/// [WhisperBindings] which loads the real dynamic library.
abstract class WhisperBindingsBase {
  /// Initialise a whisper context from a .bin model file at [modelPath].
  /// Returns an opaque handle; null/0 on failure.
  int initFromFile(String modelPath);

  /// Run inference on [samples] (16 kHz mono float32) and return the
  /// concatenated text of all segments. Throws on inference failure.
  String runFull({
    required int ctxHandle,
    required List<double> samples,
    required String language,
  });

  /// Release the context. Safe to call with 0/null.
  void free(int ctxHandle);
}

/// Production bindings — load the dynamic library produced by the
/// platform-side build (CMake on Android, podspec on iOS/macOS).
///
/// On Android: libwhisper.so in the APK's lib/<abi>/ directory.
/// On iOS / macOS: linked via the podspec's vendored framework.
class WhisperBindings extends WhisperBindingsBase {
  static const _libName = 'whisper';

  late final DynamicLibrary _dylib;

  // C ABI typedefs — match whisper.h.
  late final Pointer<Void> Function(Pointer<Utf8>) _initFromFile;
  late final int Function(Pointer<Void>, Pointer<Float>, int, Pointer<Utf8>)
      _runFull;
  late final Pointer<Utf8> Function(Pointer<Void>, int)
      _getSegmentText;
  late final void Function(Pointer<Void>) _free;

  WhisperBindings._(this._dylib) {
    _initFromFile = _dylib
        .lookup<NativeFunction<Pointer<Void> Function(Pointer<Utf8>)>>(
            'whisper_init_from_file')
        .asFunction();
    _runFull = _dylib
        .lookup<
                NativeFunction<
                    Int32 Function(Pointer<Void>, Pointer<Float>, Int32,
                        Pointer<Utf8>)>>('whisper_full_simple')
        .asFunction();
    _getSegmentText = _dylib
        .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Void>, Int32)>>(
            'whisper_full_get_segment_text')
        .asFunction();
    _free = _dylib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('whisper_free')
        .asFunction();
  }

  /// Open the platform's whisper dynamic library. Throws if the
  /// library could not be loaded — usually a misconfigured podspec or
  /// missing CMake target.
  factory WhisperBindings.open() {
    DynamicLibrary lib;
    if (Platform.isIOS || Platform.isMacOS) {
      lib = DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      lib = DynamicLibrary.open('lib$_libName.so');
    } else {
      throw UnsupportedError(
          'whisper_cpp does not support ${Platform.operatingSystem}');
    }
    return WhisperBindings._(lib);
  }

  @override
  int initFromFile(String modelPath) {
    final cStr = modelPath.toNativeUtf8();
    try {
      final ptr = _initFromFile(cStr);
      return ptr.address;
    } finally {
      calloc.free(cStr);
    }
  }

  @override
  String runFull({
    required int ctxHandle,
    required List<double> samples,
    required String language,
  }) {
    if (ctxHandle == 0) {
      throw StateError('whisper_cpp: cannot run on a null context handle');
    }
    final ctx = Pointer<Void>.fromAddress(ctxHandle);
    final n = samples.length;
    final buf = calloc<Float>(n);
    final lang = language.toNativeUtf8();
    try {
      for (var i = 0; i < n; i++) {
        buf[i] = samples[i];
      }
      final rc = _runFull(ctx, buf, n, lang);
      if (rc != 0) {
        throw StateError('whisper_cpp: whisper_full_simple returned $rc');
      }
      // Concatenate all segments. We stop at the first null pointer.
      //
      // Each segment pointer is decoded as UTF-8. If `toDartString()`
      // throws FormatException ("Unexpected extension byte (at offset N)")
      // it almost always means whisper.cpp returned a pointer to
      // uninitialised / partially-overwritten memory — e.g. inference
      // ran but produced no usable text, leaving prior-run buffer junk
      // in place.  The old code propagated that FormatException up
      // through whisper_service.dart's catch-all and surfaced the
      // useless message "inference failed: FormatException: Unexpected
      // extension byte (at offset 0)" to the operator.  Now we skip
      // the bad segment and return whatever clean segments we did get;
      // if every segment is bad we return empty so the caller can
      // treat it as "no speech detected" rather than a hard crash.
      final sb = StringBuffer();
      var i = 0;
      var skippedBadSegments = 0;
      while (true) {
        final p = _getSegmentText(ctx, i);
        if (p.address == 0) break;
        try {
          sb.write(p.toDartString());
        } on FormatException catch (_) {
          // Garbage UTF-8 — skip this segment and keep going.
          skippedBadSegments++;
        }
        i++;
        if (i > 10000) break; // belt-and-braces guard
      }
      if (sb.isEmpty && skippedBadSegments > 0) {
        // All segments were garbage — treat as inference failure with a
        // meaningful message rather than letting an empty string look
        // like a successful "" transcription.
        throw StateError(
            'whisper_cpp: all $skippedBadSegments segment(s) returned '
            'invalid UTF-8 (whisper.cpp output buffer corruption — '
            'usually no speech detected or model mismatch)');
      }
      return sb.toString();
    } finally {
      calloc.free(buf);
      calloc.free(lang);
    }
  }

  @override
  void free(int ctxHandle) {
    if (ctxHandle == 0) return;
    _free(Pointer<Void>.fromAddress(ctxHandle));
  }
}

```
