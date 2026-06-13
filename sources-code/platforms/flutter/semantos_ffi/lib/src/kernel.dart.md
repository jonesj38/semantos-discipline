---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/lib/src/kernel.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.008309+00:00
---

# platforms/flutter/semantos_ffi/lib/src/kernel.dart

```dart
// Semantos FFI — Idiomatic Dart wrapper around the C ABI.
//
// All pointer allocations use try/finally to guarantee cleanup.
// All C calls check the return code and throw SemantosException on failure.

import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:ffi' as ffi;
import 'dart:typed_data' show Uint8List;

import 'package:ffi/ffi.dart';

import 'bindings.dart';

String _encodeJson(Map<String, dynamic> m) => jsonEncode(m);

/// Exception thrown when a Semantos kernel call fails.
class SemantosException implements Exception {
  final int code;
  final String message;

  SemantosException(this.code, this.message);

  @override
  String toString() => 'SemantosException($code): $message';
}

/// D-O5m.followup-3 Phase 3 — kernel script-execution context.
///
/// Carries the trace correlation id alongside the bytes so the
/// returned [ScriptResult] echoes it back into log streams. Future
/// fields (capabilities, identity, time) can be added without breaking
/// the Phase 3 wire shape.
class ScriptContext {
  final String? traceCorrelationId;

  const ScriptContext({this.traceCorrelationId});

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{};
    if (traceCorrelationId != null) {
      out['traceCorrelationId'] = traceCorrelationId;
    }
    return out;
  }
}

/// D-O5m.followup-3 Phase 3 — kernel script-execution result.
///
/// Mirrors the TS-side `@semantos/intent` `ScriptResult` shape so a
/// Dart pipeline can route rejections through the same
/// `intent_rejected{kernel}` stage event the brain pipeline emits.
///
/// D-O5m.followup-1 — extended with `errorKind`. Now that the on-device
/// 2-PDA enforces K1-K4, the kernel's typed verdict carries a stable
/// kind string that maps to the [ScriptViolationKind] enum. Callers
/// that want a typed switch should use [toOutcome] which produces a
/// sealed [ScriptOutcome].
class ScriptResult {
  final bool ok;
  final int opcount;
  final int stackDepth;
  final int gasUsed;
  final int? errorCode;

  /// Stable failure kind from the Zig FFI:
  ///   "k1_linearity_violation", "k2_auth_failed",
  ///   "k3_domain_mismatch",     "k4_atomicity_violation",
  ///   "script_invalid"
  /// Always present in the JSON when [ok] is false; null on success.
  final String? errorKind;
  final String? errorMessage;
  final String? traceCorrelationId;

  const ScriptResult({
    required this.ok,
    required this.opcount,
    required this.stackDepth,
    required this.gasUsed,
    this.errorCode,
    this.errorKind,
    this.errorMessage,
    this.traceCorrelationId,
  });

  factory ScriptResult.fromJson(Map<String, dynamic> json) {
    return ScriptResult(
      ok: json['ok'] == true,
      opcount: (json['opcount'] as num?)?.toInt() ?? 0,
      stackDepth: (json['stackDepth'] as num?)?.toInt() ?? 0,
      gasUsed: (json['gasUsed'] as num?)?.toInt() ?? 0,
      errorCode: (json['errorCode'] as num?)?.toInt(),
      errorKind: json['errorKind'] as String?,
      errorMessage: json['errorMessage'] as String?,
      traceCorrelationId: json['traceCorrelationId'] as String?,
    );
  }

  /// Map this raw result into a sealed [ScriptOutcome] for typed
  /// pattern-matching. The helm UI / dart_pipeline routes against
  /// [ScriptViolationKind] so each K1-K4 / script_invalid / generic
  /// rejection can show its own operator message.
  ScriptOutcome toOutcome() {
    if (ok) {
      return ScriptOk(
        opcount: opcount,
        stackDepth: stackDepth,
        gasUsed: gasUsed,
        traceCorrelationId: traceCorrelationId,
      );
    }
    final kind = _kindFromString(errorKind);
    return ScriptViolation(
      kind: kind,
      message: errorMessage ?? 'kernel rejected script',
      errorCode: errorCode ?? 0,
      opcount: opcount,
      traceCorrelationId: traceCorrelationId,
    );
  }
}

/// D-O5m.followup-1 — typed K-invariant violation kinds.
///
/// String values match the FFI's `errorKind` JSON field (see
/// `src/ffi/exports.zig:classifyExecuteError`). The Dart pipeline
/// switches on these to render operator-specific messages in the
/// helm UI ("K1 violation: cell already used. Refresh and retry.",
/// "K3 violation: hat doesn't have access. Switch to the right hat.",
/// etc.).
enum ScriptViolationKind {
  /// K1 — substructural linearity violation. A LINEAR cell was
  /// duplicated or discarded, an AFFINE was duplicated, or a
  /// RELEVANT was discarded. Operationally: "the cell was already
  /// used (or shouldn't be reused)".
  k1Linearity('k1_linearity_violation'),

  /// K2 — authentication failure. Capability mismatch, signature
  /// invalid, owner identity mismatch, type-hash mismatch.
  /// Operationally: "the device's signature didn't pass — re-pair
  /// or refresh the cap".
  k2Auth('k2_auth_failed'),

  /// K3 — domain-flag scope mismatch. The hat the operator is
  /// wearing doesn't grant access to the requested domain.
  k3Domain('k3_domain_mismatch'),

  /// K4 — atomicity violation. The transaction aborted mid-step
  /// (verify failed, budget insufficient, host fetch failed under
  /// partial commit). Operationally: "we rolled back; nothing
  /// changed".
  k4Atomicity('k4_atomicity_violation'),

  /// Malformed bytes / unknown opcode / disabled opcode / nesting
  /// overflow. Operationally: "the gradient produced something
  /// the kernel doesn't understand — file a bug".
  scriptInvalid('script_invalid'),

  /// Fallback — kernel reported a failure but the `errorKind`
  /// string was missing or unrecognised. Operationally identical
  /// to scriptInvalid for the UI but distinct so we can spot
  /// schema drift in the audit log.
  unknown('unknown');

  final String wireValue;
  const ScriptViolationKind(this.wireValue);
}

ScriptViolationKind _kindFromString(String? s) {
  if (s == null) return ScriptViolationKind.unknown;
  for (final k in ScriptViolationKind.values) {
    if (k.wireValue == s) return k;
  }
  return ScriptViolationKind.unknown;
}

/// D-O5m.followup-1 — sealed outcome of a kernel script execution.
/// One of [ScriptOk] or [ScriptViolation]. Use a Dart 3 switch
/// expression to pattern-match the K1-K4 routing.
sealed class ScriptOutcome {
  const ScriptOutcome();
}

class ScriptOk extends ScriptOutcome {
  final int opcount;
  final int stackDepth;
  final int gasUsed;
  final String? traceCorrelationId;
  const ScriptOk({
    required this.opcount,
    required this.stackDepth,
    required this.gasUsed,
    this.traceCorrelationId,
  });
}

class ScriptViolation extends ScriptOutcome {
  final ScriptViolationKind kind;
  final String message;
  final int errorCode;
  final int opcount;
  final String? traceCorrelationId;
  const ScriptViolation({
    required this.kind,
    required this.message,
    required this.errorCode,
    required this.opcount,
    this.traceCorrelationId,
  });
}

/// Idiomatic Dart wrapper for the Semantos kernel.
///
/// Usage:
/// ```dart
/// final kernel = SemantosKernel();
/// await kernel.initialize('{}');
/// await kernel.cellWrite('/path', data);
/// final result = await kernel.cellRead('/path');
/// await kernel.shutdown();
/// ```
class SemantosKernel {
  final SemantosBindings _bindings;
  bool _initialized = false;

  SemantosKernel() : _bindings = SemantosBindings();

  /// For testing: inject bindings loaded from an explicit library path.
  SemantosKernel.withBindings(this._bindings);

  /// Whether the kernel has been initialized.
  bool get isInitialized => _initialized;

  /// The underlying bindings, for advanced use (e.g., callback registration).
  SemantosBindings get bindings => _bindings;

  // ── Lifecycle ──

  /// Initialize the kernel with a JSON configuration string.
  /// Pass `'{}'` for default configuration.
  Future<void> initialize(String configJson) async {
    final configBytes = utf8.encode(configJson);
    final configPtr = calloc<ffi.Uint8>(configBytes.length);
    try {
      configPtr.asTypedList(configBytes.length).setAll(0, configBytes);
      final result = _bindings.semantosInit(configPtr, configBytes.length);
      _checkResult(result, 'initialize');
      _initialized = true;
    } finally {
      calloc.free(configPtr);
    }
  }

  /// Shut down the kernel and release all resources.
  Future<void> shutdown() async {
    final result = _bindings.semantosShutdown();
    _checkResult(result, 'shutdown');
    _initialized = false;
  }

  // ── Cell operations ──

  /// Write data to a cell at the given path.
  Future<void> cellWrite(String path, Uint8List data) async {
    final pathBytes = utf8.encode(path);
    final pathPtr = calloc<ffi.Uint8>(pathBytes.length);
    final dataPtr = calloc<ffi.Uint8>(data.length);
    try {
      pathPtr.asTypedList(pathBytes.length).setAll(0, pathBytes);
      dataPtr.asTypedList(data.length).setAll(0, data);
      final result = _bindings.semantosCellWrite(
        pathPtr,
        pathBytes.length,
        dataPtr,
        data.length,
      );
      _checkResult(result, 'cellWrite');
    } finally {
      calloc.free(dataPtr);
      calloc.free(pathPtr);
    }
  }

  /// Read data from a cell at the given path.
  /// Returns null if the cell does not exist.
  Future<Uint8List?> cellRead(String path) async {
    final pathBytes = utf8.encode(path);
    final pathPtr = calloc<ffi.Uint8>(pathBytes.length);
    // Start with a reasonable buffer; retry with larger if needed.
    var bufSize = 4096;
    var outPtr = calloc<ffi.Uint8>(bufSize);
    final lenPtr = calloc<ffi.Size>();
    try {
      pathPtr.asTypedList(pathBytes.length).setAll(0, pathBytes);
      lenPtr.value = bufSize;

      var result = _bindings.semantosCellRead(
        pathPtr,
        pathBytes.length,
        outPtr,
        lenPtr,
      );

      // If buffer too small, retry with the size the kernel told us.
      if (result == semantosErrBufferTooSmall) {
        final needed = lenPtr.value;
        calloc.free(outPtr);
        bufSize = needed;
        outPtr = calloc<ffi.Uint8>(bufSize);
        lenPtr.value = bufSize;
        result = _bindings.semantosCellRead(
          pathPtr,
          pathBytes.length,
          outPtr,
          lenPtr,
        );
      }

      if (result == semantosErrNotFound) return null;
      _checkResult(result, 'cellRead');

      final actualLen = lenPtr.value;
      return Uint8List.fromList(outPtr.asTypedList(actualLen));
    } finally {
      calloc.free(lenPtr);
      calloc.free(outPtr);
      calloc.free(pathPtr);
    }
  }

  /// Verify a proof against the cell at the given path.
  Future<bool> cellVerify(String path, Uint8List proof) async {
    final pathBytes = utf8.encode(path);
    final pathPtr = calloc<ffi.Uint8>(pathBytes.length);
    final proofPtr = calloc<ffi.Uint8>(proof.length);
    try {
      pathPtr.asTypedList(pathBytes.length).setAll(0, pathBytes);
      proofPtr.asTypedList(proof.length).setAll(0, proof);
      final result = _bindings.semantosCellVerify(
        pathPtr,
        pathBytes.length,
        proofPtr,
        proof.length,
      );
      if (result == semantosErrInvalidProof) return false;
      if (result == semantosErrNotFound) return false;
      _checkResult(result, 'cellVerify');
      return true;
    } finally {
      calloc.free(proofPtr);
      calloc.free(pathPtr);
    }
  }

  // ── Capability (Phase 30C) ──

  /// Check if a certificate grants the required flags for a resource.
  Future<bool> capabilityCheck(
    Uint8List certJson,
    String resourceId,
    int requiredFlags,
  ) async {
    final ridBytes = utf8.encode(resourceId);
    final certPtr = calloc<ffi.Uint8>(certJson.length);
    final ridPtr = calloc<ffi.Uint8>(ridBytes.length);
    try {
      certPtr.asTypedList(certJson.length).setAll(0, certJson);
      ridPtr.asTypedList(ridBytes.length).setAll(0, ridBytes);
      final result = _bindings.semantosCapabilityCheck(
        certPtr,
        certJson.length,
        ridPtr,
        ridBytes.length,
        requiredFlags,
      );
      if (result == semantosErrDenied) return false;
      _checkResult(result, 'capabilityCheck');
      return true;
    } finally {
      calloc.free(ridPtr);
      calloc.free(certPtr);
    }
  }

  /// Present (derive) a new capability certificate.
  Future<Uint8List> capabilityPresent(
    Uint8List parentCert,
    String resourceId,
    int grantedFlags,
  ) async {
    final ridBytes = utf8.encode(resourceId);
    final parentPtr = calloc<ffi.Uint8>(parentCert.length);
    final ridPtr = calloc<ffi.Uint8>(ridBytes.length);
    var bufSize = 4096;
    var outPtr = calloc<ffi.Uint8>(bufSize);
    final lenPtr = calloc<ffi.Size>();
    try {
      parentPtr.asTypedList(parentCert.length).setAll(0, parentCert);
      ridPtr.asTypedList(ridBytes.length).setAll(0, ridBytes);
      lenPtr.value = bufSize;

      var result = _bindings.semantosCapabilityPresent(
        parentPtr,
        parentCert.length,
        ridPtr,
        ridBytes.length,
        grantedFlags,
        outPtr,
        lenPtr,
      );

      if (result == semantosErrBufferTooSmall) {
        final needed = lenPtr.value;
        calloc.free(outPtr);
        bufSize = needed;
        outPtr = calloc<ffi.Uint8>(bufSize);
        lenPtr.value = bufSize;
        result = _bindings.semantosCapabilityPresent(
          parentPtr,
          parentCert.length,
          ridPtr,
          ridBytes.length,
          grantedFlags,
          outPtr,
          lenPtr,
        );
      }

      _checkResult(result, 'capabilityPresent');
      return Uint8List.fromList(outPtr.asTypedList(lenPtr.value));
    } finally {
      calloc.free(lenPtr);
      calloc.free(outPtr);
      calloc.free(ridPtr);
      calloc.free(parentPtr);
    }
  }

  // ── Anchor (Phase 30D) ──

  /// Submit a state hash for anchoring, returns the anchor proof.
  Future<Uint8List> anchorBatch(
    Uint8List stateHash,
    String metadataJson,
  ) async {
    final metaBytes = utf8.encode(metadataJson);
    final hashPtr = calloc<ffi.Uint8>(stateHash.length);
    final metaPtr = calloc<ffi.Uint8>(metaBytes.length);
    var bufSize = 4096;
    var outPtr = calloc<ffi.Uint8>(bufSize);
    final lenPtr = calloc<ffi.Size>();
    try {
      hashPtr.asTypedList(stateHash.length).setAll(0, stateHash);
      metaPtr.asTypedList(metaBytes.length).setAll(0, metaBytes);
      lenPtr.value = bufSize;

      var result = _bindings.semantosAnchorBatch(
        hashPtr,
        stateHash.length,
        metaPtr,
        metaBytes.length,
        outPtr,
        lenPtr,
      );

      if (result == semantosErrBufferTooSmall) {
        final needed = lenPtr.value;
        calloc.free(outPtr);
        bufSize = needed;
        outPtr = calloc<ffi.Uint8>(bufSize);
        lenPtr.value = bufSize;
        result = _bindings.semantosAnchorBatch(
          hashPtr,
          stateHash.length,
          metaPtr,
          metaBytes.length,
          outPtr,
          lenPtr,
        );
      }

      _checkResult(result, 'anchorBatch');
      return Uint8List.fromList(outPtr.asTypedList(lenPtr.value));
    } finally {
      calloc.free(lenPtr);
      calloc.free(outPtr);
      calloc.free(metaPtr);
      calloc.free(hashPtr);
    }
  }

  /// Verify an anchor proof against a state hash.
  Future<bool> anchorVerify(Uint8List proof, Uint8List stateHash) async {
    final proofPtr = calloc<ffi.Uint8>(proof.length);
    final hashPtr = calloc<ffi.Uint8>(stateHash.length);
    try {
      proofPtr.asTypedList(proof.length).setAll(0, proof);
      hashPtr.asTypedList(stateHash.length).setAll(0, stateHash);
      final result = _bindings.semantosAnchorVerify(
        proofPtr,
        proof.length,
        hashPtr,
        stateHash.length,
      );
      if (result == semantosErrInvalidProof) return false;
      _checkResult(result, 'anchorVerify');
      return true;
    } finally {
      calloc.free(hashPtr);
      calloc.free(proofPtr);
    }
  }

  // ── Linearity (Phase 30C) ──

  /// Mark a cell as consumed (linear resource).
  Future<void> linearConsume(String path) async {
    final pathBytes = utf8.encode(path);
    final pathPtr = calloc<ffi.Uint8>(pathBytes.length);
    try {
      pathPtr.asTypedList(pathBytes.length).setAll(0, pathBytes);
      final result = _bindings.semantosLinearConsume(
        pathPtr,
        pathBytes.length,
      );
      _checkResult(result, 'linearConsume');
    } finally {
      calloc.free(pathPtr);
    }
  }

  // ── Script execution (D-O5m.followup-3 Phase 3) ──

  /// Execute an opcode byte stream through the kernel and return a
  /// typed [ScriptResult]. Mirrors the brain-side authoring contract:
  /// the bytes are validated as a well-formed opcode stream and the
  /// opcount is returned alongside `ok=true`. Malformed streams yield
  /// `ok=false` with a structured `errorCode` + `errorMessage` so the
  /// Dart-side pipeline can route the failure through
  /// `intent_rejected{kernel}` exactly the way the TS pipeline does
  /// (`runtime/intent/src/pipeline.ts` step 5).
  ///
  /// Honours the BUFFER_TOO_SMALL retry pattern — the Zig export
  /// reports the required size when our initial buffer is too small;
  /// we re-allocate and retry once.
  Future<ScriptResult> executeScript({
    required Uint8List bytes,
    ScriptContext? ctx,
  }) async {
    final ctxJson = ctx == null ? '{}' : _encodeJson(ctx.toJson());
    final ctxBytes = utf8.encode(ctxJson);

    final bytesPtr = calloc<ffi.Uint8>(bytes.length == 0 ? 1 : bytes.length);
    final ctxPtr = calloc<ffi.Uint8>(ctxBytes.length == 0 ? 1 : ctxBytes.length);
    var bufSize = 1024;
    var outPtr = calloc<ffi.Uint8>(bufSize);
    final lenPtr = calloc<ffi.Size>();
    try {
      if (bytes.isNotEmpty) {
        bytesPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      if (ctxBytes.isNotEmpty) {
        ctxPtr.asTypedList(ctxBytes.length).setAll(0, ctxBytes);
      }
      lenPtr.value = bufSize;

      var result = _bindings.semantosExecuteScript(
        bytesPtr,
        bytes.length,
        ctxPtr,
        ctxBytes.length,
        outPtr,
        bufSize,
        lenPtr,
      );

      if (result == semantosErrBufferTooSmall) {
        final needed = lenPtr.value;
        calloc.free(outPtr);
        bufSize = needed;
        outPtr = calloc<ffi.Uint8>(bufSize);
        lenPtr.value = bufSize;
        result = _bindings.semantosExecuteScript(
          bytesPtr,
          bytes.length,
          ctxPtr,
          ctxBytes.length,
          outPtr,
          bufSize,
          lenPtr,
        );
      }

      _checkResult(result, 'executeScript');
      final actualLen = lenPtr.value;
      final json = utf8.decode(outPtr.asTypedList(actualLen));
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) {
        throw SemantosException(
          result,
          'executeScript returned non-object JSON: $decoded',
        );
      }
      return ScriptResult.fromJson(decoded);
    } finally {
      calloc.free(lenPtr);
      calloc.free(outPtr);
      calloc.free(ctxPtr);
      calloc.free(bytesPtr);
    }
  }

  // ── Metadata ──

  /// Return the kernel version string.
  String version() {
    final ptr = _bindings.semantosVersion();
    return ptr.toDartString();
  }

  /// Return the last error message from the kernel.
  String? lastError() {
    final bufSize = 256;
    final outPtr = calloc<ffi.Uint8>(bufSize);
    final lenPtr = calloc<ffi.Size>();
    try {
      lenPtr.value = bufSize;
      final result = _bindings.semantosLastError(
        outPtr,
        lenPtr,
      );
      if (result != semantosOk) return null;
      final actualLen = lenPtr.value;
      if (actualLen == 0) return null;
      return utf8.decode(outPtr.asTypedList(actualLen));
    } finally {
      calloc.free(lenPtr);
      calloc.free(outPtr);
    }
  }

  // ── Internal ──

  void _checkResult(int result, String operation) {
    if (result == semantosOk) return;
    final errorMsg = lastError();
    final msg = errorMsg ?? _errorCodeToString(result);
    throw SemantosException(result, '$operation failed: $msg');
  }

  static String _errorCodeToString(int code) {
    switch (code) {
      case semantosErrNotFound:
        return 'NOT_FOUND';
      case semantosErrInvalidJson:
        return 'INVALID_JSON';
      case semantosErrAlreadyConsumed:
        return 'ALREADY_CONSUMED';
      case semantosErrAlreadyInit:
        return 'ALREADY_INIT';
      case semantosErrNotInit:
        return 'NOT_INIT';
      case semantosErrBufferTooSmall:
        return 'BUFFER_TOO_SMALL';
      case semantosErrInvalidProof:
        return 'INVALID_PROOF';
      case semantosErrDenied:
        return 'DENIED';
      case semantosErrExpired:
        return 'EXPIRED';
      default:
        return 'UNKNOWN_ERROR($code)';
    }
  }
}

```
