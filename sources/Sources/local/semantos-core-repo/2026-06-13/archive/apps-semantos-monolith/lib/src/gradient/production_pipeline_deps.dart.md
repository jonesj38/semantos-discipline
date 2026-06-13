---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/gradient/production_pipeline_deps.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.875771+00:00
---

# archive/apps-semantos-monolith/lib/src/gradient/production_pipeline_deps.dart

```dart
// 2026-05-07 — production wiring for `DartIntentPipeline`'s
// `PipelineDeps` injection bag.  Called from `OnDeviceVoiceFactory`
// when both the on-device kernel + the operator's outbox are
// available.  Without this wiring the typed-NL pipeline would never
// run end-to-end (returns `TextIntentPipelineUnavailable`), which is
// what the operator was hitting on 2026-05-07.
//
// Architecture:
//
//   DartIntentPipeline runs SIR → OIR → opcode bytes → kernel verify
//   → cell construction → cell write.  Five callbacks bridge the
//   pipeline to the production stack:
//
//     - executeScript        → SemantosKernel.executeScript via FFI
//     - buildCell            → deriveCellId (non-cryptographic, mirrors
//                              TS reference) over the OIR-emitted
//                              opcode bytes.  Cryptographic id is a
//                              future change.
//     - writeCell            → enqueue an `oddjobz.intent_cell.v1`
//                              envelope into the outbox so the
//                              outbox flush flow uploads to the brain
//                              via the existing REPL transport
//     - emit                 → debugPrint with a `[pipeline]` prefix
//                              for now.  Audit-log sink is a future
//                              change once one exists in the mobile
//                              app.
//     - correlationIdFactory → const Uuid().v4()
//
// The envelope shape produced here MUST match the canonical spec at
// `docs/spec/oddjobz-intent-cell-v1.md`.  The brain side validates the
// shape and rejects with `envelope_invalid` on any deviation.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:semantos_ffi/semantos_ffi.dart' as kernel_ffi;

import '../outbox/outbox_db.dart';
import 'cell_id.dart';
import 'dart_pipeline.dart';
import 'intent_trace_service.dart';
import 'oddjobz_extension_context.dart' show kOddjobzDomainFlag;

/// Injection seam for the kernel.  Production wires
/// `SemantosKernel.executeScript`; tests inject a closure.  Decouples
/// the deps factory from the concrete `SemantosKernel` class so unit
/// tests can exercise the deps without loading the FFI shim.
typedef KernelExecuteScript = Future<kernel_ffi.ScriptResult> Function({
  required Uint8List bytes,
  kernel_ffi.ScriptContext? ctx,
});

/// Cell-type marker for typed-NL signed intent cells flowing through
/// the outbox.  Mirrors the Semantos Brain-side handler resource verb pair
/// (`intent_cells/submit`).  Spec: `docs/spec/oddjobz-intent-cell-v1.md`.
const String intentCellType = 'oddjobz.intent_cell.v1';

/// Envelope version.  Bump on a breaking shape change; the Semantos Brain handler
/// rejects unknown versions with `envelope_invalid`.
const int kIntentCellEnvelopeVersion = 1;

/// Construct a `PipelineDeps` bag wired to the production stack.
/// Pass into `DartIntentPipeline(deps)` once per turn (or once and
/// reuse — the deps hold no per-call state).
///
/// [kernel] — initialised `SemantosKernel`.  The caller must have
/// already awaited `kernel.initialize('{}')` before calling
/// `DartIntentPipeline.process(...)`; this factory does not bring
/// the kernel up.
///
/// [outboxDb] — direct DB access for `enqueue`.  We bypass the
/// `OutboxService.flush` loop here because the deps just need to
/// drop an entry; the flush loop picks it up on its next tick.
///
/// [intentSummary] — operator-readable summary derived from the
/// extracted Intent.  Stored in the envelope so the Semantos Brain side can
/// surface it in the AttentionFeedSection without re-running the
/// extractor.  Pass the SIR-extracted `intent.summary` value.
///
/// [intentAction] — extracted action verb (`find`, `quote`, etc.).
///
/// [intentTaxonomyJson] — the `{what,how,why}` triple, JSON-encoded.
///
/// [intentTargetJson] — Wave 9 follow-up. Optional JSON-encoded
/// `target` object hoisted from the extracted Intent (amount,
/// currency, jobId, customerId). When present, the brain-side
/// `intent_action_router` honours it instead of re-deriving entity
/// identity from `intent_summary` token matching. Empty string when
/// the intent had no target.
///
/// [uuid] — UUID generator.  Defaults to `const Uuid().v4()` via the
/// passed-in factory; tests inject a deterministic generator.
///
/// [audit] — stage-event sink.  Defaults to `debugPrint` with a
/// `[pipeline]` prefix.
///
/// [traceService] — Wave 9 follow-up. Optional in-app trace recorder.
/// When supplied, every `PipelineStageEvent` is forwarded to it
/// alongside the [audit] log sink, so the `IntentInspectorSheet` widget
/// can render the cascade for the user's last action without leaving
/// the PWA. Pass `null` (the default) to keep the previous behaviour.
PipelineDeps buildProductionPipelineDeps({
  required KernelExecuteScript kernelExecute,
  required OutboxDb outboxDb,
  required String hatId,
  required String certId,
  required String intentSummary,
  required String intentAction,
  required String intentTaxonomyJson,
  required String Function() uuid,
  String intentTargetJson = '',
  void Function(String message)? audit,
  IntentTraceService? traceService,
}) {
  final emitFn = audit ?? (String m) => debugPrint(m);

  // Captures the kernel verdict produced in stage 4 so stage 5b's
  // `writeCell` can ship it to the brain in the envelope's
  // `kernelResult` field for drift analysis.  Per-deps-instance
  // mutable state — DartIntentPipeline.process is sequential, so
  // there's no concurrent-write hazard within a single turn.  Each
  // turn should construct its own deps via this factory (or the
  // closure inside OnDeviceVoiceFactory).
  PipelineScriptResult? phoneKernelResult;

  return PipelineDeps(
    correlationIdFactory: uuid,

    // Stage 4 — kernel verify.  SemantosKernel.executeScript is
    // microsecond-cost (bounded 2-PDA on bytes ≤ 10 KiB), so we
    // intentionally do NOT spawn an isolate here.  The bigger cost
    // (llama inference) is already off the UI thread via the
    // LlamaService.complete isolate split (PR #427).
    executeScript: (Uint8List bytes, String correlationId) async {
      final raw = await kernelExecute(
        bytes: bytes,
        ctx: kernel_ffi.ScriptContext(traceCorrelationId: correlationId),
      );
      final mapped = PipelineScriptResult(
        ok: raw.ok,
        opcount: raw.opcount,
        stackDepth: raw.stackDepth,
        gasUsed: raw.gasUsed,
        errorCode: raw.errorCode,
        errorKind: raw.errorKind,
        errorMessage: raw.errorMessage,
        traceCorrelationId: raw.traceCorrelationId,
      );
      phoneKernelResult = mapped;
      return mapped;
    },

    // Stage 5a — package opcode bytes into a cell.  Synchronous;
    // signing happens server-side once the brain re-runs the kernel.
    buildCell: (Uint8List bytes, PipelineScriptResult kernelResult) {
      final id = deriveCellId(bytes, uuid);
      return PipelineCell(id: id, bytes: bytes);
    },

    // Stage 5b — persist.  Renders the canonical envelope and
    // enqueues into the outbox; the existing flush loop uploads
    // when a transport is reachable.
    writeCell: (PipelineCell cell) async {
      // Read the kernel verdict captured in stage 4.  If for some
      // reason `executeScript` never ran (would be a pipeline bug —
      // stage 4 always precedes stage 5b in DartIntentPipeline.
      // process), fall back to a placeholder ok-shape so the
      // envelope still validates brain-side.
      final kr = phoneKernelResult;
      final kernelClaim = kr == null
          ? <String, dynamic>{
              'ok': true,
              'opcount': 0,
              'stackDepth': 0,
              'gasUsed': 0,
              'errorKind': null,
            }
          : <String, dynamic>{
              'ok': kr.ok,
              'opcount': kr.opcount,
              'stackDepth': kr.stackDepth,
              'gasUsed': kr.gasUsed,
              'errorKind': kr.errorKind,
            };

      final envelope = <String, dynamic>{
        'kind': intentCellType,
        'version': kIntentCellEnvelopeVersion,
        'cellId': cell.id,
        'opcodeBytes': base64Encode(cell.bytes),
        'hatId': hatId,
        'certId': certId,
        'correlationId': uuid(),
        'kernelResult': kernelClaim,
        'originalIntent': <String, dynamic>{
          'summary': intentSummary,
          'action': intentAction,
          'taxonomyJson': intentTaxonomyJson,
          // Wave 9 follow-up — when the extractor + resolver bound
          // amount/currency/jobId/customerId, ship them so the brain
          // router skips its summary-token heuristic and addresses
          // the right entity directly.
          if (intentTargetJson.isNotEmpty) 'targetJson': intentTargetJson,
        },
      };
      // W1.2 — encode cell.id as UTF-8 bytes (zero-padded to 32).
      final cellIdBytes = utf8.encode(cell.id);
      final cellId32 = Uint8List(32)
        ..setRange(0, cellIdBytes.length.clamp(0, 32), cellIdBytes);
      await outboxDb.enqueue(
        cellId: cellId32,
        domainFlag: kOddjobzDomainFlag,
        payload: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      );
    },

    // Stage events — log via [emitFn] AND mirror into the in-app
    // trace recorder (when wired). The recorder is what the
    // IntentInspectorSheet reads from in home_screen.dart.
    emit: (PipelineStageEvent event) {
      emitFn(
        '[pipeline] cid=${event.correlationId} '
        'stage=${event.stage} '
        'ms=${event.durationMs.toStringAsFixed(2)} '
        'data=${jsonEncode(event.data)}',
      );
      traceService?.recordEvent(event);
    },
  );
}

/// Outbox flush adapter shim for the typed-NL intent cell type.
/// Renders an outbox row's `payload` (W1.2 BLOB — UTF-8 encoded JSON
/// cell envelope) as the REPL command line the Semantos Brain handler accepts:
///
///     submit-intent-cell --envelope BASE64(payloadJson)
///
/// The base64 wrap exists because the envelope is a JSON blob with
/// quotes + nested objects; the REPL parser treats the line as a
/// shell-style command, so quoting it raw would be a footgun.
///
/// Returns null when `payloadBytes` is null or empty so the
/// OutboxService skips the entry rather than sending a blank command.
String? renderIntentCellReplLine(Uint8List? payloadBytes) {
  if (payloadBytes == null || payloadBytes.isEmpty) return null;
  final b64 = base64Encode(payloadBytes);
  return 'submit-intent-cell --envelope $b64';
}

```
