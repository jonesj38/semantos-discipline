---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/outbox/outbox_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.863557+00:00
---

# archive/apps-semantos-monolith/lib/src/outbox/outbox_service.dart

```dart
// D-O5m-i (skeleton) — Outbox flush-on-reconnect service.
//
// MVP slice: when the device transitions from offline → online, the
// service walks the FIFO outbox and pushes each entry through the
// REPL client. On success: dequeue. On a typed REPL error: record
// the failure + leave the entry queued (for the UI to surface or for
// a future retry).
//
// D-O5m.followup-5 K1 conflict UI — flush now maps the brain's typed
// error JSON bodies to typed [OutboxFailureKind]s.  It records each
// failure via [OutboxDb.recordTypedFailure] so the conflicts screen
// can render an actionable surface.  A `failedEntries` stream
// re-emits the failed-set on every flush + every retry/discard the
// conflicts screen issues, so the AppBar status indicator updates
// without manual refresh wiring.
//
// The MVP simply re-emits the cell payload as a REPL line and lets
// the brain process it. The cell-type → REPL-line mapping is a
// caller concern; the outbox is shape-agnostic.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../mesh/mesh_transport.dart';
import '../mesh/signed_bundle.dart';
import '../repl/repl_client.dart';
import '../repl/repl_errors.dart';
import 'mesh_outbox_builder.dart';
import 'outbox_db.dart';

/// D-O5m.followup-8 capture+upload — cell-type discriminator that the
/// flush handler reads to decide between the REPL path (default) and
/// the multipart-upload path (attachments).  Stored verbatim in the
/// `cell_type` column.
const String attachmentCellType = 'oddjobz.attachment.v1';

/// D-O5m.followup-3 Phase 1 voice — cell-type discriminator for
/// voice-extract rows.  When the device is offline at the time the
/// operator hits "Send" in the voice command sheet, the recording is
/// enqueued under this cell_type.  The flush handler routes those rows
/// through the [VoiceExtractFlushUploader] (which POSTs the same
/// multipart body the production [DioVoiceExtractUploader] uses).
const String voiceExtractCellType = 'oddjobz.voice_extract.v1';

/// Maps an OutboxEntry to the REPL line that flushes it. Caller
/// supplies this so the outbox stays decoupled from the cell-type
/// surface. Returns null to skip flushing (entry stays queued).
typedef OutboxFlushAdapter = String? Function(OutboxEntry entry);

/// Result of a flush pass — the helm settings screen surfaces these
/// counts to the operator.
class FlushSummary {
  /// Entries successfully pushed + dequeued in this pass.
  final int succeeded;

  /// Entries that the brain accepted but reported a validation
  /// error for (caller decides whether to dequeue or leave queued).
  final int validationFailed;

  /// Entries that hit a network or 503 error (left queued).
  final int retryable;

  /// Entries that hit a 401 — the bearer was rejected. Flush halts
  /// at this point; the helm screen transitions to pairing.
  final bool unauthorised;

  /// D-O5m.followup-5 — entries that hit a K1 state_moved_on
  /// conflict.  Surfaced in the conflicts screen with a side-by-
  /// side reconciliation view.
  final int stateMovedOn;

  const FlushSummary({
    required this.succeeded,
    required this.validationFailed,
    required this.retryable,
    required this.unauthorised,
    this.stateMovedOn = 0,
  });

  @override
  String toString() =>
      'FlushSummary(succeeded=$succeeded, validationFailed=$validationFailed, '
      'retryable=$retryable, unauthorised=$unauthorised, '
      'stateMovedOn=$stateMovedOn)';
}

/// Result of an attachment upload — the brain returns
/// `{id, status: "created" | "already_exists"}` on 200.  Surface both
/// to the caller so the helm UI can distinguish a fresh upload from
/// an idempotent retry.
class AttachmentUploadResult {
  final String id;
  final String status;
  const AttachmentUploadResult({required this.id, required this.status});
}

/// Attachment uploader — abstracts the multipart POST so tests can
/// swap in a stub.  Production wiring uses [DioAttachmentUploader]
/// which posts to `<brainHttpsEndpoint>/api/v1/attachments/upload`
/// with the bearer in the Authorization header.
abstract class AttachmentUploader {
  Future<AttachmentUploadResult> upload({
    required File blobFile,
    required String metadataJson,
  });
}

/// D-O5m.followup-3 Phase 1 voice — outbox-side voice-extract uploader
/// seam.  Mirrors [AttachmentUploader] in shape: takes the audio blob
/// path on disk + the JSON-encoded {transcript, metadata} envelope
/// stored in `payload_json`, POSTs the multipart body to
/// /api/v1/voice-extract.  Tests inject a stub.
abstract class VoiceExtractFlushUploader {
  Future<void> upload({
    required File audioFile,
    required String envelopeJson,
  });
}

/// Production attachment uploader — Dio-backed multipart POST.
class DioAttachmentUploader implements AttachmentUploader {
  final Dio _http;
  final String _baseUrl;
  final String Function() _bearer;

  DioAttachmentUploader({
    required Dio http,
    required String baseUrl,
    required String Function() bearer,
  })  : _http = http,
        _baseUrl = baseUrl,
        _bearer = bearer;

  @override
  Future<AttachmentUploadResult> upload({
    required File blobFile,
    required String metadataJson,
  }) async {
    final formData = FormData();
    formData.fields.add(MapEntry('metadata', metadataJson));
    formData.files.add(MapEntry(
      'blob',
      await MultipartFile.fromFile(
        blobFile.path,
        filename: blobFile.path.split('/').last,
      ),
    ));
    final resp = await _http.post<Map<String, dynamic>>(
      '$_baseUrl/api/v1/attachments/upload',
      data: formData,
      options: Options(
        headers: {'Authorization': 'Bearer ${_bearer()}'},
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );
    if (resp.statusCode == 401) throw const ReplUnauthorisedError('upload bearer rejected');
    if (resp.statusCode == 200) {
      final body = resp.data ?? const {};
      return AttachmentUploadResult(
        id: (body['id'] ?? '').toString(),
        status: (body['status'] ?? 'created').toString(),
      );
    }
    final body = resp.data ?? const {};
    throw ReplValidationError((body['error'] ?? 'upload_failed').toString());
  }
}

/// D-O5m.followup-5 — parse a brain-side error string (the value of
/// the `error` field in a typed JSON body) into a typed
/// [OutboxFailureKind].  Returns null when the wire string isn't a
/// recognised K1-conflict surface — callers fall back to the generic
/// `validationFailed` kind in that case.
///
/// The mapping reflects the brain's typed error vocabulary surfaced
/// in `runtime/semantos-brain/src/attachments_upload_http.zig` + the cell-type
/// dispatch handlers.  When the brain grows new typed kinds, extend
/// this map (and `failure_messages.dart`) in lockstep.
OutboxFailureKind? parseBrainError(String? wire) {
  if (wire == null) return null;
  final w = wire.trim();
  if (w.isEmpty) return null;
  switch (w) {
    case 'hash_mismatch':
      return OutboxFailureKind.hashMismatch;
    case 'signature_invalid':
      return OutboxFailureKind.signatureInvalid;
    case 'cert_unknown':
      return OutboxFailureKind.certUnknown;
    case 'visit_not_found':
    case 'not_found':
      return OutboxFailureKind.visitNotFound;
    case 'state_moved_on':
    case 'not_reachable':
    case 'wrong_principal':
    case 'wrong_cap':
      // The K1 conflict surfaces under a few brain-side names
      // depending on the FSM path that rejected the transition.
      // All three reduce to "the brain isn't where you thought it
      // was" from the operator's perspective.
      return OutboxFailureKind.stateMovedOn;
    case 'attachment_id_in_use_with_different_contents':
      return OutboxFailureKind.replay;
    case 'bearer_invalid':
      return OutboxFailureKind.unauthorised;
    case 'payload_invalid_format':
    case 'invalid_args':
    case 'too_large':
      return OutboxFailureKind.validationFailed;
    default:
      return null;
  }
}

/// D-O5m.followup-5 — best-effort extractor for the brain's current
/// canonical state on a state_moved_on conflict.  The brain emits
/// `{"error":"not_reachable","from":"<state>",...}`-shaped bodies on
/// FSM rejection; this pulls the `from` (or `current_state`) field
/// when present.
String? extractBrainState(Map<String, Object?> body) {
  final from = body['from'];
  if (from is String && from.isNotEmpty) return from;
  final current = body['current_state'];
  if (current is String && current.isNotEmpty) return current;
  final state = body['state'];
  if (state is String && state.isNotEmpty) return state;
  return null;
}

class OutboxService {
  final OutboxDb _db;
  final ReplClient _repl;

  /// D-O5m.followup-6 Phase 2 — optional mesh transport seam.  When
  /// set, [flushViaMesh] wraps each entry as a [SignedBundle] and
  /// pushes through this transport instead of the legacy per-kind
  /// uploaders.  Absent → callers stick with [flush] (legacy path).
  /// Both paths coexist; the factory in mesh_transport.dart decides
  /// at app startup which transport is live.
  final MeshTransport? _meshTransport;

  /// D-O5m.followup-6 Phase 2 — identity context for mesh-bundle
  /// signing.  Required iff [_meshTransport] is set.
  final MeshIdentityContext? _meshIdentity;

  /// D-O5m.followup-6 Phase 2 — incoming bundle handler.  When the
  /// mesh transport delivers a bundle addressed to this device, the
  /// outbox dispatches by payload_type.  helm.event bundles flow
  /// into the live-update layer; other types are logged + dropped
  /// (Phase 3 will handle peer-cell-incoming).
  StreamSubscription<SignedBundle>? _incomingSub;

  /// D-O5m.followup-5 — broadcasts the failed-entry set on every
  /// flush + every external mutation (retry / discard).  The
  /// conflicts screen + AppBar indicator subscribe to this.
  final StreamController<List<OutboxFailedEntry>> _failedCtl =
      StreamController<List<OutboxFailedEntry>>.broadcast();

  /// D-O5m.followup-5 — broadcasts the count of non-failed pending
  /// entries on every flush + retry/discard.  The AppBar indicator
  /// uses this to distinguish "outbox empty" (green) from "outbox
  /// has pending entries" (yellow).
  final StreamController<int> _pendingCtl =
      StreamController<int>.broadcast();

  /// Exposes the underlying [OutboxDb] so callers that need direct
  /// DB access (e.g. VoiceCommandSheet) can enqueue entries without
  /// going through the service flush loop.
  OutboxDb get db => _db;

  OutboxService({
    required OutboxDb db,
    required ReplClient repl,
    MeshTransport? meshTransport,
    MeshIdentityContext? meshIdentity,
    void Function(SignedBundle bundle)? onIncomingBundle,
  })  : _db = db,
        _repl = repl,
        _meshTransport = meshTransport,
        _meshIdentity = meshIdentity {
    if (_meshTransport != null && _meshIdentity == null) {
      throw ArgumentError(
          'OutboxService: meshTransport requires meshIdentity');
    }
    // Prime subscribers with the current state asynchronously so a
    // subscriber that attaches before the first flush still gets a
    // snapshot.
    scheduleMicrotask(_emitFailed);
    // Wire incoming bundles when the mesh transport supports a
    // receive stream.  HttpReplFallbackTransport.incoming() is empty,
    // so the stream-empty case is a no-op.
    final mesh = _meshTransport;
    if (mesh != null) {
      _incomingSub = mesh.incoming().listen((bundle) {
        if (onIncomingBundle != null) {
          onIncomingBundle(bundle);
        }
      });
    }
  }

  /// D-O5m.followup-5 — subscribe to changes in the failed-entry
  /// set.  Replays the most recent emission on subscription.  Stable
  /// across the lifetime of the service.
  Stream<List<OutboxFailedEntry>> get failedEntries => _failedCtl.stream;

  /// D-O5m.followup-5 — subscribe to the count of non-failed pending
  /// entries.  Used by the AppBar status indicator's green-vs-yellow
  /// distinction.
  Stream<int> get pendingCount => _pendingCtl.stream;

  /// Best-effort emit of the current failed-entry list + pending
  /// count.
  Future<void> _emitFailed() async {
    if (_failedCtl.isClosed) return;
    try {
      final failed = await _db.peekFailed();
      if (!_failedCtl.isClosed) _failedCtl.add(failed);
      // Pending count == total queue depth − failed count.  We don't
      // need cryptographic precision here — the indicator just wants
      // a "is there anything in flight" signal.
      final total = await _db.count();
      final pending = total - failed.length;
      if (!_pendingCtl.isClosed) _pendingCtl.add(pending < 0 ? 0 : pending);
    } catch (_) {
      // Non-fatal — the next emit cycle will retry.
    }
  }

  /// Walk the FIFO outbox and push each entry through the adapter.
  ///
  /// W1.2 — With the cell-envelope schema all entries carry a 1024-byte
  /// `payload` BLOB.  The caller-supplied [adapter] renders each entry
  /// as a REPL command string (or returns null to skip).  The old
  /// cellType-based attachment/voice-extract routing is superseded by
  /// the payload envelope; those paths are removed.
  Future<FlushSummary> flush(OutboxFlushAdapter adapter,
      {int batchLimit = 100}) async {
    var succeeded = 0;
    var validationFailed = 0;
    var retryable = 0;
    var stateMovedOn = 0;

    final batch = await _db.peek(limit: batchLimit);
    for (final entry in batch) {
      try {
        final cmd = adapter(entry);
        if (cmd == null) continue;
        await _repl.send(cmd);
        await _db.dequeue(entry.id);
        succeeded += 1;
      } on ReplUnauthorisedError catch (e) {
        // Bearer rejected — record the typed failure on this entry
        // (so the conflicts screen surfaces it) AND abort the flush
        // — the helm screen will transition to pairing.
        await _db.recordTypedFailure(
          id: entry.id,
          kind: OutboxFailureKind.unauthorised,
          message: e.reason,
        );
        await _emitFailed();
        return FlushSummary(
          succeeded: succeeded,
          validationFailed: validationFailed,
          retryable: retryable,
          unauthorised: true,
          stateMovedOn: stateMovedOn,
        );
      } on ReplValidationError catch (e) {
        final mapped = e.body != null
            ? _mapErrorBody(e.body!)
            : _mapErrorMessage(e.message);
        await _db.recordTypedFailure(
          id: entry.id,
          kind: mapped.kind,
          message: mapped.detail ?? e.message,
          // W1.2: prevStateHash replaces lastBrainState TEXT.
          // brainState is a human-readable string from the REPL error
          // body; until the brain ships a 32-byte hash we pass null.
        );
        if (mapped.kind == OutboxFailureKind.stateMovedOn) {
          stateMovedOn += 1;
        } else {
          validationFailed += 1;
        }
      } on ReplBackendUnavailable catch (e) {
        await _db.recordTypedFailure(
          id: entry.id,
          kind: OutboxFailureKind.networkError,
          message: e.message,
        );
        retryable += 1;
      } on ReplError catch (e) {
        await _db.recordTypedFailure(
          id: entry.id,
          kind: OutboxFailureKind.networkError,
          message: e.message,
        );
        retryable += 1;
      } catch (e) {
        // Network errors (connection refused, timeout, etc.) — leave
        // queued for retry.
        await _db.recordTypedFailure(
          id: entry.id,
          kind: OutboxFailureKind.networkError,
          message: e.toString(),
        );
        retryable += 1;
      }
    }

    await _emitFailed();
    return FlushSummary(
      succeeded: succeeded,
      validationFailed: validationFailed,
      retryable: retryable,
      unauthorised: false,
      stateMovedOn: stateMovedOn,
    );
  }

  // W1.2 — _flushAttachment and _flushVoiceExtract removed.
  // With the cell-envelope schema the payload BLOB carries the full
  // cell envelope; routing by cell_type is handled by the caller's
  // OutboxFlushAdapter rather than a special-case branch here.

  /// D-O5m.followup-5 — the conflicts screen's "Retry" button calls
  /// this to clear the typed-failure metadata on a single entry so
  /// the next flush sees a clean entry.  Re-emits the failed-entry
  /// set on completion so the AppBar indicator updates.
  Future<void> retry(int id) async {
    await _db.clearFailure(id);
    await _emitFailed();
  }

  /// D-O5m.followup-5 — the conflicts screen's "Discard" button
  /// calls this to remove the entry from the outbox entirely
  /// (operator accepts data loss).  Re-emits the failed-entry set.
  Future<void> discard(int id) async {
    await _db.dequeue(id);
    await _emitFailed();
  }

  /// D-O5m.followup-6 Phase 2 — mesh-transport flush variant.
  ///
  /// Walks the FIFO outbox; for each entry, builds a [SignedBundle]
  /// from `entry.payloadJson` and pushes through [_meshTransport].
  /// Maps the [MeshSendResult] to the same [FlushSummary] shape the
  /// legacy [flush] returns so callers can swap paths without
  /// downstream surface changes.
  ///
  /// Caller must have configured a mesh transport at construction
  /// time; otherwise this throws [StateError].  The legacy [flush]
  /// remains the default path; callers opt into the mesh flush when
  /// [MeshTransportFactory] returned a [ShardProxyMeshTransport].
  Future<FlushSummary> flushViaMesh({int batchLimit = 100}) async {
    final transport = _meshTransport;
    final identity = _meshIdentity;
    if (transport == null || identity == null) {
      throw StateError('flushViaMesh: mesh transport not configured');
    }
    var succeeded = 0;
    var validationFailed = 0;
    var retryable = 0;
    var unauthorised = false;

    final batch = await _db.peek(limit: batchLimit);
    for (final entry in batch) {
      final bundle = buildBundleFromOutboxEntry(
        entry: entry,
        identity: identity,
      );
      final result = await transport.send(bundle);
      switch (result) {
        case MeshSent():
          await _db.dequeue(entry.id);
          succeeded += 1;
        case MeshTransportUnavailable(:final reason):
          await _db.recordTypedFailure(
            id: entry.id,
            kind: OutboxFailureKind.networkError,
            message: reason,
          );
          retryable += 1;
        case MeshSendFailed(:final reason, :final statusCode):
          if (statusCode == 401) {
            await _db.recordTypedFailure(
              id: entry.id,
              kind: OutboxFailureKind.unauthorised,
              message: reason,
            );
            unauthorised = true;
            await _emitFailed();
            return FlushSummary(
              succeeded: succeeded,
              validationFailed: validationFailed,
              retryable: retryable,
              unauthorised: true,
            );
          }
          await _db.recordTypedFailure(
            id: entry.id,
            kind: OutboxFailureKind.validationFailed,
            message: reason,
          );
          validationFailed += 1;
      }
    }
    await _emitFailed();
    return FlushSummary(
      succeeded: succeeded,
      validationFailed: validationFailed,
      retryable: retryable,
      unauthorised: unauthorised,
    );
  }

  /// Free resources — call this on logout / unpair.
  Future<void> dispose() async {
    await _incomingSub?.cancel();
    await _failedCtl.close();
    await _pendingCtl.close();
  }

  /// Internal: map a brain error message (typically the value of
  /// the JSON `error` field) to a typed kind + detail + optional
  /// brain state.  The mapper handles two common shapes:
  ///   - bare string ("hash_mismatch")
  ///   - JSON object body (the brain's typed-body shape)
  /// — falling back to validationFailed when neither matches.
  _MappedError _mapErrorMessage(String message) {
    // Try to interpret the message as a JSON body — covers callers
    // that stuff the body text into the message.
    Map<String, Object?>? body;
    try {
      final parsed = jsonDecode(message);
      if (parsed is Map<String, Object?>) body = parsed;
    } catch (_) {
      // Plain string — fall through.
    }
    if (body != null) return _mapErrorBody(body);
    final kind = parseBrainError(message) ?? OutboxFailureKind.validationFailed;
    return _MappedError(kind: kind, detail: message);
  }

  /// Internal: map a parsed brain error body (the JSON object the
  /// brain returned with the typed-error wire shape) to a typed kind
  /// + detail + optional brain state.
  _MappedError _mapErrorBody(Map<String, Object?> body) {
    final wire = body['error'];
    if (wire is String) {
      final kind = parseBrainError(wire) ?? OutboxFailureKind.validationFailed;
      final detail =
          body['hint'] is String ? body['hint'] as String : wire;
      return _MappedError(
        kind: kind,
        detail: detail,
        brainState: extractBrainState(body),
      );
    }
    return const _MappedError(kind: OutboxFailureKind.validationFailed);
  }
}

class _MappedError {
  final OutboxFailureKind kind;
  final String? detail;
  final String? brainState;
  const _MappedError({required this.kind, this.detail, this.brainState});
}

```
