---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/attachments_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.880921+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/attachments_repository.dart

```dart
// D-O5m.followup-8 substrate — AttachmentList view-shape repository.
//
// Mirrors the parser shape in `visits_repository.dart`'s `parseVisits`
// and `parseVisitOne`.  Backed by the Semantos Brain dispatcher's typed
// `attachments` resource (runtime/semantos-brain/src/resources/
// attachments_handler.zig); `find attachments [--visit-id <id>]` /
// `find attachment <id>` route through that resource and emit
// canonical JSON.
//
// READ-ONLY: this repository ships only the read paths.  The producer
// side — mobile camera capture, binary blob upload, cell signing — is
// the load-bearing operator-visible work in the next PR.  When that
// lands the repository grows a `captureAttachment` method that
// drives the multipart HTTP endpoint + the `attachments.create_metadata`
// dispatcher cmd in lock-step.
//
// D-O5.followup-4 client hooks — when a [HelmEventStream] is supplied,
// the repo subscribes to `attachment.created` notifications and
// surfaces them as [AttachmentsCacheEvent]s on [cacheEvents].  The
// payload carries `visit_id` (not `id`) because the list view is
// scoped to a visit; subscribers filter by visit_id.  Mirrors the
// shape of `jobs_repository.dart` post-#318.

import 'dart:async';
import 'dart:convert';

import 'helm_event_stream.dart';
import 'repl_client.dart';

/// Single row of the helm Attachments list under VisitDetail.
class Attachment {
  final String id;
  final String visitId;

  /// One of: `photo | voice_memo | gps_pin | file_other`.
  final String kind;

  /// sha256 hex of the binary blob — 64 lowercase hex chars.
  final String contentHash;
  final int contentSize;
  final String mimeType;
  final String capturedAt;

  /// Device child-cert id that signed the cell — 32 lowercase hex chars.
  final String capturedByCertId;
  final String caption;
  final String createdAt;

  const Attachment({
    required this.id,
    required this.visitId,
    required this.kind,
    required this.contentHash,
    required this.contentSize,
    required this.mimeType,
    required this.capturedAt,
    required this.capturedByCertId,
    required this.caption,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'visit_id': visitId,
        'kind': kind,
        'content_hash': contentHash,
        'content_size': contentSize,
        'mime_type': mimeType,
        'captured_at': capturedAt,
        'captured_by_cert_id': capturedByCertId,
        'caption': caption,
        'created_at': createdAt,
      };
}

/// D-O5.followup-4 — cache-invalidation event surfaced by
/// [AttachmentsRepository] when the live stream delivers an
/// `attachment.created` notification.  Screens (`VisitDetailScreen`'s
/// attachments section, primarily) subscribe to
/// [AttachmentsRepository.cacheEvents] and refresh themselves on each
/// emission.  The list view is always visit-scoped, so the event
/// carries the parent `visitId` — subscribers filter by visit_id and
/// ignore events for other visits.  Mirrors `JobsCacheEvent`
/// post-#318.
class AttachmentsCacheEvent {
  /// The visit id whose attachment list changed.  Empty when the
  /// upstream payload didn't carry it (defensive).
  final String visitId;

  const AttachmentsCacheEvent({required this.visitId});
}

/// Repository over the REPL — the helm screens call this rather than
/// hand-parsing the REPL response themselves.  Mirrors
/// `VisitsRepository` minus the create + transition surface.
///
/// This is the READ-ONLY surface for the substrate PR.  When the
/// camera-capture PR lands the repository grows a `captureAttachment`
/// method that drives the multipart HTTP endpoint + the
/// `attachments.create_metadata` dispatcher cmd.
///
/// D-O5.followup-4 — when a [HelmEventStream] is supplied, the repo
/// subscribes to `attachment.created` notifications and surfaces them
/// as [AttachmentsCacheEvent]s on [cacheEvents].  Screens listen to
/// the cache-event stream and refresh themselves on each emission.
/// When the stream is null (tests, pull-only mode) the cacheEvents
/// stream is silent — no emissions, ever — and the repo behaves as it
/// did pre-followup-4.
class AttachmentsRepository {
  final ReplClient _repl;
  final StreamController<AttachmentsCacheEvent> _cacheCtl =
      StreamController<AttachmentsCacheEvent>.broadcast();
  StreamSubscription<HelmEvent>? _eventSub;

  AttachmentsRepository(this._repl, {HelmEventStream? eventStream}) {
    if (eventStream != null) {
      _eventSub = eventStream.events.listen(_onHelmEvent);
    }
  }

  /// Stream of cache-invalidation events the helm screens listen to.
  /// Broadcast — multiple screens can subscribe simultaneously.
  Stream<AttachmentsCacheEvent> get cacheEvents => _cacheCtl.stream;

  /// Release the event subscription + close the cache stream.  Call
  /// on logout / unpair so the next pairing starts with a clean
  /// repository.
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    if (!_cacheCtl.isClosed) await _cacheCtl.close();
  }

  void _onHelmEvent(HelmEvent event) {
    if (event.type != 'attachment.created') return;
    // The list view is visit-scoped; emit the parent visit_id so
    // VisitDetailScreen can ignore events for other visits.
    final vid = event.data['visit_id'];
    if (vid is! String || vid.isEmpty) return;
    _cacheCtl.add(AttachmentsCacheEvent(visitId: vid));
  }

  /// Fetch all attachments, optionally filtered by parent [visitId].
  /// Throws [ReplUnauthorisedError] on transport-level 401 (helm
  /// pivots to pairing).
  Future<List<Attachment>> findAttachments({String? visitId}) async {
    final cmd = visitId == null
        ? 'find attachments'
        : 'find attachments --visit-id $visitId';
    final resp = await _repl.send(cmd);
    return parseAttachments(resp.result);
  }

  /// Fetch a single attachment by id via the typed
  /// `attachments.find_by_id` resource.  Returns null on the typed
  /// `{error: "not_found", id}` envelope or any parse failure.
  Future<Attachment?> findAttachment(String id) async {
    final resp = await _repl.send('find attachment $id');
    return parseAttachmentOne(resp.result);
  }
}

/// Parse the REPL's `find attachments` output into [Attachment] rows.
/// JSON-only — attachments have no TSV legacy.
List<Attachment> parseAttachments(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  if (!(trimmed.startsWith('[') || trimmed.startsWith('{'))) return const [];
  try {
    final parsed = json.decode(trimmed);
    if (parsed is List) {
      return parsed.whereType<Map<String, dynamic>>().map(_attachmentFromJson).toList();
    }
  } catch (_) {
    // Fall through to empty.
  }
  return const [];
}

/// Parse a single-attachment response from `attachments.find_by_id`.
/// Returns null on the typed `{"error":"not_found", ...}` envelope or
/// any parse failure.
Attachment? parseAttachmentOne(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return null;
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      if (parsed['error'] == 'not_found') return null;
      if (parsed['id'] == null) return null;
      return _attachmentFromJson(parsed);
    }
    if (parsed is List && parsed.isNotEmpty) {
      final first = parsed.first;
      if (first is Map<String, dynamic>) return _attachmentFromJson(first);
    }
  } catch (_) {
    // Fall through to null.
  }
  return null;
}

Attachment _attachmentFromJson(Map<String, dynamic> row) => Attachment(
      id: (row['id'] ?? '').toString(),
      visitId: (row['visit_id'] ?? '').toString(),
      kind: (row['kind'] ?? '').toString(),
      contentHash: (row['content_hash'] ?? '').toString(),
      contentSize: (row['content_size'] is int)
          ? row['content_size'] as int
          : int.tryParse((row['content_size'] ?? '0').toString()) ?? 0,
      mimeType: (row['mime_type'] ?? '').toString(),
      capturedAt: (row['captured_at'] ?? '').toString(),
      capturedByCertId: (row['captured_by_cert_id'] ?? '').toString(),
      caption: (row['caption'] ?? '').toString(),
      createdAt: (row['created_at'] ?? '').toString(),
    );

/// Format bytes into a short human-readable label for the helm list
/// row ("2.5 MB", "180 KB", "64 B").  Mirrors the same posture as
/// other helm-side display helpers — keep the unit math local to the
/// repository so the screen doesn't bloat with view utilities.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

```
