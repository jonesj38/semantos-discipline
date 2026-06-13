---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/gradient/dart_pipeline.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.115402+00:00
---

# apps/semantos/lib/src/gradient/dart_pipeline.dart

```dart
// D-O5m.followup-3 Phase 3 — pure-Dart intent pipeline orchestrator.
//
// Reference: runtime/intent/src/pipeline.ts:processIntent (the
//            canonical TS orchestrator -- this file mirrors its
//            stage-event flow exactly so the same correlationId tag
//            travels through every stage and a failed turn is a
//            single grep);
//            apps/oddjobz-mobile/lib/src/gradient/sir_to_oir.dart
//            (the L1->L2 lowering pass);
//            apps/oddjobz-mobile/lib/src/gradient/oir_to_bytes.dart
//            (the L2->L3 emit pass);
//            platforms/flutter/semantos_ffi/lib/src/kernel.dart
//            (the FFI surface the L3->L4 stage calls into).
//
// The pipeline runs in five stages:
//
//   1. sirBuilt     -- given the Phase-2 Intent + hat, build the SIR
//                      program (mirrors sir-builder.ts:buildSIR)
//   2. sirLowered   -- SIR -> OIR (sir_to_oir.dart); rejection routes
//                      through `IntentRejection{stage: sir}`
//   3. irEmitted    -- OIR -> opcode bytes (oir_to_bytes.dart)
//   4. scriptExecuted -- bytes -> kernel ScriptResult (deps.executeScript);
//                        rejection routes through
//                        `IntentRejection{stage: kernel}`
//   5. cellWritten  -- bytes packaged into a Cell + persisted via
//                      deps.writeCell
//
// Every stage emits a `PipelineStageEvent` carrying the correlationId
// + durationMs, mirroring `StageEvent` in runtime/intent/src/types.ts.

import 'dart:typed_data';

import 'oir_to_bytes.dart';
import 'sir_to_oir.dart';

/// Hat-context fields the pipeline consumes. Loose Map-based shape
/// keeps Dart-side consumers free to construct on the fly.
class PipelineHatContext {
  final String hatId;
  final String? certId;
  final int domainFlag;
  final String maxTrustClass;
  final String? extensionId;

  const PipelineHatContext({
    required this.hatId,
    this.certId,
    required this.domainFlag,
    required this.maxTrustClass,
    this.extensionId,
  });
}

/// Cell shape -- mirrors @semantos/intent Cell. The id derivation is
/// up to deps.buildCell; the bytes are the kernel-emitted opcode
/// stream.
class PipelineCell {
  final String id;
  final Uint8List bytes;
  const PipelineCell({required this.id, required this.bytes});
}

/// Kernel result -- shape-compatible with
/// platforms/flutter/semantos_ffi/lib/src/kernel.dart:ScriptResult so
/// the FFI return type drops in unchanged.
///
/// D-O5m.followup-1 — extended with [errorKind] now that the on-device
/// 2-PDA reports K1-K4 substructural violations directly.
class PipelineScriptResult {
  final bool ok;
  final int opcount;
  final int stackDepth;
  final int gasUsed;
  final int? errorCode;

  /// One of "k1_linearity_violation", "k2_auth_failed",
  /// "k3_domain_mismatch", "k4_atomicity_violation", "script_invalid"
  /// when [ok] is false; null on success. Matches the `errorKind` JSON
  /// field produced by `src/ffi/exports.zig:semantos_execute_script`.
  final String? errorKind;
  final String? errorMessage;
  final String? traceCorrelationId;

  const PipelineScriptResult({
    required this.ok,
    required this.opcount,
    required this.stackDepth,
    required this.gasUsed,
    this.errorCode,
    this.errorKind,
    this.errorMessage,
    this.traceCorrelationId,
  });
}

/// D-O5m.followup-1 — typed kernel rejection kinds. The string values
/// match the FFI `errorKind` field so the pipeline can lift the kernel
/// verdict into a typed enum without re-parsing.
enum PipelineKernelViolation {
  k1Linearity('k1_linearity_violation'),
  k2Auth('k2_auth_failed'),
  k3Domain('k3_domain_mismatch'),
  k4Atomicity('k4_atomicity_violation'),
  scriptInvalid('script_invalid'),
  unknown('unknown');

  final String wireValue;
  const PipelineKernelViolation(this.wireValue);

  static PipelineKernelViolation fromString(String? s) {
    if (s == null) return PipelineKernelViolation.unknown;
    for (final v in PipelineKernelViolation.values) {
      if (v.wireValue == s) return v;
    }
    return PipelineKernelViolation.unknown;
  }
}

/// Structured rejection -- mirrors @semantos/intent IntentRejection.
///
/// D-O5m.followup-1 — when `stage == 'kernel'`, [kernelViolation] carries
/// the typed K1-K4 / script_invalid taxonomy so the helm UI can render
/// operator-specific messages. For `stage == 'sir'`, [kernelViolation]
/// is null (the violation was a lowering refusal, not a 2-PDA verdict).
class IntentRejection {
  final String stage; // 'sir' | 'kernel'
  final String code;
  final String message;
  final PipelineKernelViolation? kernelViolation;
  const IntentRejection({
    required this.stage,
    required this.code,
    required this.message,
    this.kernelViolation,
  });
}

/// Stage event -- mirrors @semantos/intent StageEvent.
class PipelineStageEvent {
  final String correlationId;
  final String stage;
  final double durationMs;
  final Map<String, dynamic> data;
  PipelineStageEvent({
    required this.correlationId,
    required this.stage,
    required this.durationMs,
    required this.data,
  });
}

/// Outcome of running the Dart pipeline -- success carries a signed
/// + persisted Cell + the kernel result; rejection carries the
/// structured IntentRejection so the UI can render a typed reason.
sealed class IntentResult {
  const IntentResult();
}

class IntentSuccess extends IntentResult {
  final String correlationId;
  final PipelineCell cell;
  final PipelineScriptResult kernelResult;
  const IntentSuccess({
    required this.correlationId,
    required this.cell,
    required this.kernelResult,
  });
}

class IntentRejected extends IntentResult {
  final String correlationId;
  final IntentRejection rejection;
  // Bytes / kernel result available when the rejection happened at
  // the kernel stage, so the UI can render the partial trace.
  final Uint8List? bytes;
  final PipelineScriptResult? kernelResult;
  const IntentRejected({
    required this.correlationId,
    required this.rejection,
    this.bytes,
    this.kernelResult,
  });
}

/// Injection seam for the kernel surface -- production wires
/// `SemantosKernel.executeScript()` from semantos_ffi; tests inject a
/// fake.
typedef ExecuteScript = Future<PipelineScriptResult> Function(
  Uint8List bytes,
  String correlationId,
);

/// Injection seam for the cell-construction surface -- given the
/// emitted bytes + kernel result, produce a typed Cell. Production
/// wires the existing `cell_signer.dart`-driven signing path.
typedef BuildCell = PipelineCell Function(
  Uint8List bytes,
  PipelineScriptResult kernelResult,
);

/// Injection seam for cell persistence -- production wires the
/// outbox / storage adapter; tests inject a recorder.
typedef WriteCell = Future<void> Function(PipelineCell cell);

/// Injection seam for stage events -- production wires the existing
/// audit log; tests inject a list-collector.
typedef EmitStageEvent = void Function(PipelineStageEvent event);

/// Injection seam for correlation ids -- production threads through
/// crypto.randomUUID; tests inject a deterministic generator.
typedef CorrelationIdFactory = String Function();

class PipelineDeps {
  final ExecuteScript executeScript;
  final BuildCell buildCell;
  final WriteCell writeCell;
  final EmitStageEvent emit;
  final CorrelationIdFactory correlationIdFactory;

  const PipelineDeps({
    required this.executeScript,
    required this.buildCell,
    required this.writeCell,
    required this.emit,
    required this.correlationIdFactory,
  });
}

class DartIntentPipeline {
  final PipelineDeps deps;
  const DartIntentPipeline(this.deps);

  /// Run the L1->L2->L3->L4 pipeline locally for the given Intent +
  /// hat context. Returns a typed [IntentResult] -- never throws on
  /// an expected rejection (only on infrastructure failure inside
  /// deps.writeCell or deps.executeScript).
  Future<IntentResult> process({
    required Map<String, dynamic> intent,
    required PipelineHatContext hatContext,
    String? correlationId,
  }) async {
    final cid = correlationId ??
        (intent['correlationId'] as String?) ??
        deps.correlationIdFactory();

    // Stage 1: build SIR.
    final sirStart = DateTime.now();
    final sirProgram = buildSir(
      intent: intent,
      hatId: hatContext.hatId,
      certId: hatContext.certId,
      domainFlag: hatContext.domainFlag,
      maxTrustClass: hatContext.maxTrustClass,
      extensionId: hatContext.extensionId,
    );
    deps.emit(PipelineStageEvent(
      correlationId: cid,
      stage: 'sir_built',
      durationMs:
          DateTime.now().difference(sirStart).inMicroseconds / 1000.0,
      data: {
        'trustClass':
            (sirProgram['programGovernance'] as Map)['trustClass'],
        'constraintCount':
            (intent['constraints'] as List? ?? const []).length,
      },
    ));

    // Stage 2: SIR -> OIR.
    final lowerStart = DateTime.now();
    final lowered = sirToOir(sirProgram);
    final lowerMs =
        DateTime.now().difference(lowerStart).inMicroseconds / 1000.0;
    if (lowered is SirToOirRejected) {
      final rejection = IntentRejection(
        stage: 'sir',
        code: lowered.rejection.code,
        message: lowered.rejection.message,
      );
      deps.emit(PipelineStageEvent(
        correlationId: cid,
        stage: 'intent_rejected',
        durationMs: lowerMs,
        data: {
          'stage': 'sir',
          'code': rejection.code,
          'message': rejection.message,
        },
      ));
      return IntentRejected(correlationId: cid, rejection: rejection);
    }
    final oirProgram = (lowered as SirToOirSuccess).program;
    deps.emit(PipelineStageEvent(
      correlationId: cid,
      stage: 'sir_lowered',
      durationMs: lowerMs,
      data: {
        'bindingCount': oirProgram.bindings.length,
        'result': oirProgram.result,
      },
    ));

    // Stage 3: OIR -> bytes.
    final emitStart = DateTime.now();
    final bytes = oirToBytes(oirProgram);
    final emitMs =
        DateTime.now().difference(emitStart).inMicroseconds / 1000.0;
    deps.emit(PipelineStageEvent(
      correlationId: cid,
      stage: 'ir_emitted',
      durationMs: emitMs,
      data: {'byteLength': bytes.length},
    ));

    // Stage 4: kernel.
    final execStart = DateTime.now();
    final kernelResult = await deps.executeScript(bytes, cid);
    final execMs =
        DateTime.now().difference(execStart).inMicroseconds / 1000.0;
    deps.emit(PipelineStageEvent(
      correlationId: cid,
      stage: 'script_executed',
      durationMs: execMs,
      data: {
        'kernelOk': kernelResult.ok,
        'opcount': kernelResult.opcount,
        'stackDepth': kernelResult.stackDepth,
        'gasUsed': kernelResult.gasUsed,
      },
    ));
    if (!kernelResult.ok) {
      // D-O5m.followup-1 — lift the FFI's `errorKind` string into a
      // typed [PipelineKernelViolation] so downstream consumers (helm
      // UI, audit log) can switch on it without re-parsing.
      final violation =
          PipelineKernelViolation.fromString(kernelResult.errorKind);
      final rejection = IntentRejection(
        stage: 'kernel',
        // Prefer the typed violation kind as the rejection `code` so a
        // single grep finds every K1/K2/K3/K4 surface across logs +
        // audit + helm. Fall back to the numeric errorCode when the
        // kernel failed without a kind string (legacy WASM path).
        code: violation != PipelineKernelViolation.unknown
            ? violation.wireValue
            : (kernelResult.errorCode != null
                ? '${kernelResult.errorCode}'
                : 'kernel_error'),
        message: kernelResult.errorMessage ?? 'kernel rejected script',
        kernelViolation: violation,
      );
      deps.emit(PipelineStageEvent(
        correlationId: cid,
        stage: 'intent_rejected',
        durationMs: execMs,
        data: {
          'stage': 'kernel',
          'code': rejection.code,
          'message': rejection.message,
        },
      ));
      return IntentRejected(
        correlationId: cid,
        rejection: rejection,
        bytes: bytes,
        kernelResult: kernelResult,
      );
    }

    // Stage 5: write cell.
    final writeStart = DateTime.now();
    final cell = deps.buildCell(bytes, kernelResult);
    await deps.writeCell(cell);
    final writeMs =
        DateTime.now().difference(writeStart).inMicroseconds / 1000.0;
    deps.emit(PipelineStageEvent(
      correlationId: cid,
      stage: 'cell_written',
      durationMs: writeMs,
      data: {'cellId': cell.id, 'bytes': cell.bytes.length},
    ));

    deps.emit(PipelineStageEvent(
      correlationId: cid,
      stage: 'intent_completed',
      durationMs: 0,
      data: {'ok': true, 'cellId': cell.id},
    ));

    return IntentSuccess(
      correlationId: cid,
      cell: cell,
      kernelResult: kernelResult,
    );
  }
}

```
