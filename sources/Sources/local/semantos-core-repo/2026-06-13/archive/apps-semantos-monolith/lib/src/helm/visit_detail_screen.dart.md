---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/visit_detail_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.899684+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/visit_detail_screen.dart

```dart
// D-O4.followup-2 — Visit detail screen (mobile).
//
// MVP slice: read-only view of a single visit, fetched via
// `visits.find_by_id`.  D-O4.followup-2 (Visit FSM cutover) adds
// state-aware action buttons that drive `visits.transition` through
// the dispatcher — `scheduled` shows "Start" + "Cancel", `in_progress`
// shows "Complete" + "Cancel", terminal states (completed/cancelled)
// show no actions.  Mirrors job_detail_screen.dart's shape.
//
// D-O5m.followup-8 substrate adds a read-only "Attachments" section
// when an [AttachmentsRepository] is wired in.  The section lists
// metadata rows (kind, captured_at, caption, content_size); the
// camera-capture flow + binary blob preview ship in the subsequent
// PR.  When `attachments` is null the section is hidden — callers
// that haven't wired the repo still see a working VisitDetail.
//
// D-O5m.followup-8 GPS + voice memo adapters extend the screen with
// two more sensor CTAs alongside "Capture photo" — "Drop GPS pin"
// and "Record voice memo" — and kind-specific attachment row
// rendering (map-pin icon + lat/lng caption for gps_pin; speaker icon
// + tap-to-play modal for voice_memo).  All three CTAs route through
// the same AttachmentCaptureService → outbox → brain upload pipeline
// shipped by #316; only the cell `kind` + `mimeType` differ.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../attachments/attachment_capture_service.dart';
import '../outbox/outbox_db.dart';
import '../repl/attachments_repository.dart';
import '../repl/repl_errors.dart';
import '../repl/visits_repository.dart';
import '../sensors/gps_capture.dart';
import '../sensors/voice_memo_capture.dart';
import '../voice/voice_command_service.dart';
import '../voice/voice_extract_uploader.dart';
import 'voice_command_sheet.dart';
import 'voice_memo_player_screen.dart';

class VisitDetailScreen extends StatefulWidget {
  final VisitsRepository visits;

  /// Optional — when wired, the screen renders an "Attachments"
  /// section listing metadata rows for this visit.
  final AttachmentsRepository? attachments;

  /// D-O5m.followup-8 capture+upload — when wired (alongside
  /// [attachments]), the screen renders a "Capture photo" CTA when
  /// the visit is `in_progress`.  Tapping it drives the camera +
  /// signs the cell + enqueues the upload.
  final AttachmentCaptureService? captureService;

  /// D-O5m.followup-8 GPS + voice memo adapters — production wiring
  /// for the geolocator (drives the "Drop GPS pin" CTA).  When null
  /// the GPS CTA is hidden; the photo + voice CTAs still render.
  final GeolocatorAdapter? geolocator;

  /// D-O5m.followup-8 GPS + voice memo adapters — factory that mints
  /// a fresh VoiceRecorderAdapter per recording session.  When null
  /// the voice memo CTA is hidden.  A factory rather than a single
  /// instance because the adapter is single-use (one recording per
  /// instance) — re-using one across two recordings has caused
  /// platform-side state-leak bugs in past iterations.
  final VoiceRecorderAdapter Function()? voiceRecorderFactory;

  /// D-O5m.followup-8 GPS + voice memo adapters — factory that mints
  /// a fresh VoicePlaybackAdapter per playback session.  When null
  /// the voice memo player falls back to a no-op adapter so the
  /// modal still opens but reports "Playback unavailable".
  final VoicePlaybackAdapter Function()? voicePlaybackFactory;

  /// Bearer-providing function used by the photo viewer's
  /// authenticated blob fetch.  Production wiring threads this from
  /// ChildCertStore via the helm app shell; tests can pass a stub.
  final String? Function()? bearerProvider;

  /// Brain HTTPS base — same value the REPL client + uploader use.
  /// Together with [bearerProvider] enables thumbnail fetching of
  /// previously uploaded photos.
  final String? brainHttpsBase;

  /// D-O5m.followup-3 Phase 1 voice — voice command orchestration
  /// service.  When wired (alongside [voiceUploader] + [outboxDb] +
  /// [voiceRecorderFactory]), the screen renders a "Voice command"
  /// CTA on `scheduled` + `in_progress` visits.
  final VoiceCommandService? voiceCommandService;

  /// D-O5m.followup-3 Phase 1 voice — multipart uploader for the
  /// /api/v1/voice-extract endpoint.  When the device is offline the
  /// recording is enqueued via [outboxDb] for offline flush.
  final VoiceExtractUploader? voiceUploader;

  /// D-O5m.followup-3 Phase 1 voice — outbox shared with the rest of
  /// the helm.  The voice flow enqueues `oddjobz.voice_extract.v1`
  /// rows here when offline.
  final OutboxDb? outboxDb;

  /// D-O5m.followup-3 Phase 1 voice — current hat label for the
  /// /api/v1/voice-extract metadata.  When null, defaults to
  /// "operator".
  final String? hatContext;

  /// D-O5m.followup-3 Phase 1 voice — UUID-v7-or-similar generator
  /// for client_correlation_id stamping.  When null, falls back to
  /// `DateTime.now().millisecondsSinceEpoch.toString()`.
  final String Function()? voiceCorrelationIdFactory;
  final String visitId;
  final Visit initial;
  final Future<void> Function() onUnauthorised;
  const VisitDetailScreen({
    super.key,
    required this.visits,
    this.attachments,
    this.captureService,
    this.geolocator,
    this.voiceRecorderFactory,
    this.voicePlaybackFactory,
    this.bearerProvider,
    this.brainHttpsBase,
    this.voiceCommandService,
    this.voiceUploader,
    this.outboxDb,
    this.hatContext,
    this.voiceCorrelationIdFactory,
    required this.visitId,
    required this.initial,
    required this.onUnauthorised,
  });

  @override
  State<VisitDetailScreen> createState() => _VisitDetailScreenState();
}

class _VisitDetailScreenState extends State<VisitDetailScreen> {
  late Visit _visit = widget.initial;
  bool _loading = false;
  bool _transitioning = false;
  String? _error;

  /// D-O5m.followup-8 substrate — attachments cache for the section
  /// at the bottom of the screen.  Populated lazily on first build
  /// when the repository is wired; refreshed alongside _refresh().
  List<Attachment>? _attachments;
  bool _attachmentsLoading = false;
  String? _attachmentsError;
  bool _attachmentsFetched = false;

  /// D-O5.followup-4 — live cache invalidation subscriptions.  When
  /// operator A transitions THIS visit on another device, the brain
  /// emits `visit.transitioned` and we refetch here.  Same for the
  /// attachments slice when an `attachment.created` lands for THIS
  /// visit_id.
  StreamSubscription<VisitsCacheEvent>? _visitsCacheSub;
  StreamSubscription<AttachmentsCacheEvent>? _attachmentsCacheSub;

  @override
  void initState() {
    super.initState();
    if (widget.attachments != null) {
      // Fire-and-forget; the section renders a loading placeholder
      // until this resolves.
      _refreshAttachments();
    }
    // D-O5.followup-4 — re-fetch this specific visit when the brain
    // emits a `visit.*` event matching our id.
    _visitsCacheSub = widget.visits.cacheEvents.listen((evt) {
      if (!mounted) return;
      if (evt.visitId != widget.visitId) return;
      _refresh();
    });
    final attRepo = widget.attachments;
    if (attRepo != null) {
      // D-O5.followup-4 — refresh the attachments section when a new
      // attachment lands for THIS visit (events for other visits are
      // ignored — the AttachmentsCacheEvent.visitId carries the
      // parent).
      _attachmentsCacheSub = attRepo.cacheEvents.listen((evt) {
        if (!mounted) return;
        if (evt.visitId != widget.visitId) return;
        _refreshAttachments();
      });
    }
  }

  @override
  void dispose() {
    _visitsCacheSub?.cancel();
    _attachmentsCacheSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await widget.visits.findVisit(widget.visitId);
      if (!mounted) return;
      if (fresh != null) setState(() => _visit = fresh);
      // Refresh attachments alongside the visit metadata.  No-op when
      // the repository wasn't wired.
      if (widget.attachments != null) {
        await _refreshAttachments();
      }
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshAttachments() async {
    final repo = widget.attachments;
    if (repo == null) return;
    setState(() {
      _attachmentsLoading = true;
      _attachmentsError = null;
    });
    try {
      final rows = await repo.findAttachments(visitId: widget.visitId);
      if (!mounted) return;
      setState(() {
        _attachments = rows;
        _attachmentsFetched = true;
      });
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _attachmentsError = e.toString());
    } finally {
      if (mounted) setState(() => _attachmentsLoading = false);
    }
  }

  Future<void> _runTransition(
    String label,
    Future<VisitTransitionResult> Function() runner,
  ) async {
    setState(() {
      _transitioning = true;
      _error = null;
    });
    try {
      final result = await runner();
      if (!mounted) return;
      if (result is VisitTransitionSuccess) {
        setState(() => _visit = result.visit);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: ${result.visit.status}')),
        );
      } else if (result is VisitTransitionAlreadyInState) {
        setState(() => _visit = result.visit);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: already ${result.visit.status}')),
        );
      } else if (result is VisitTransitionError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label failed: ${result.message}')),
        );
      }
    } on ReplUnauthorisedError {
      await widget.onUnauthorised();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  /// State-keyed action buttons.  Pulls the operator-readable verb
  /// directly off the §O4 Visit FSM table:
  ///
  ///   scheduled     → Start (service)   |  Cancel (operator) | Voice command
  ///   in_progress   → Complete (operator) |  Cancel (operator) | Capture photo
  ///                   | Drop GPS pin | Record voice memo | Voice command
  ///   completed     → (no actions — terminal)
  ///   cancelled     → (no actions — terminal)
  ///
  /// D-O5m.followup-3 Phase 1 voice — "Voice command" routes through
  /// the [VoiceCommandSheet] modal; the recording is signed via the
  /// [VoiceCommandService] and POSTed via the [VoiceExtractUploader].
  /// Visible only when `voiceCommandService`, `voiceUploader`, and
  /// `outboxDb` are all wired (production wiring lives in helm_app).
  List<Widget> _actionsForState(BuildContext context) {
    final disabled = _transitioning;
    final voiceWired = widget.voiceCommandService != null &&
        widget.voiceUploader != null &&
        widget.outboxDb != null &&
        widget.voiceRecorderFactory != null;
    switch (_visit.status) {
      case 'scheduled':
        return [
          ElevatedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Start',
                      () => widget.visits.startVisit(widget.visitId),
                    ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Cancel',
                      () => widget.visits.cancelVisit(widget.visitId),
                    ),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel'),
          ),
          if (voiceWired)
            OutlinedButton.icon(
              onPressed: disabled ? null : _openVoiceCommand,
              icon: const Icon(Icons.record_voice_over),
              label: const Text('Voice command'),
            ),
        ];
      case 'in_progress':
        return [
          ElevatedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Complete',
                      () => widget.visits.completeVisit(widget.visitId),
                    ),
            icon: const Icon(Icons.check_circle),
            label: const Text('Complete'),
          ),
          OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _runTransition(
                      'Cancel',
                      () => widget.visits.cancelVisit(widget.visitId),
                    ),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel'),
          ),
          if (widget.captureService != null)
            OutlinedButton.icon(
              onPressed: disabled ? null : _captureAttachment,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Capture photo'),
            ),
          if (widget.captureService != null && widget.geolocator != null)
            OutlinedButton.icon(
              onPressed: disabled ? null : _captureGpsPin,
              icon: const Icon(Icons.location_on),
              label: const Text('Drop GPS pin'),
            ),
          if (widget.captureService != null &&
              widget.voiceRecorderFactory != null)
            OutlinedButton.icon(
              onPressed: disabled ? null : _recordVoiceMemo,
              icon: const Icon(Icons.mic),
              label: const Text('Record voice memo'),
            ),
          if (voiceWired)
            OutlinedButton.icon(
              onPressed: disabled ? null : _openVoiceCommand,
              icon: const Icon(Icons.record_voice_over),
              label: const Text('Voice command'),
            ),
        ];
      case 'completed':
      case 'cancelled':
        return const [];
      default:
        return const [];
    }
  }

  Future<void> _captureAttachment() async {
    final svc = widget.captureService;
    if (svc == null) return;
    setState(() => _transitioning = true);
    try {
      final outcome = await svc.captureAndEnqueue(widget.visitId);
      if (!mounted) return;
      _surfaceCaptureOutcome(outcome, kindLabel: 'Photo');
      if (widget.attachments != null) {
        await _refreshAttachments();
      }
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  Future<void> _captureGpsPin() async {
    final svc = widget.captureService;
    final geo = widget.geolocator;
    if (svc == null || geo == null) return;
    setState(() => _transitioning = true);
    try {
      final outcome =
          await svc.captureGpsAndEnqueue(widget.visitId, geolocator: geo);
      if (!mounted) return;
      _surfaceCaptureOutcome(outcome,
          kindLabel: 'GPS pin',
          cancelMessage:
              'Could not read location — check permissions / signal.');
      if (widget.attachments != null) {
        await _refreshAttachments();
      }
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  /// D-O5m.followup-3 Phase 1 voice — open the voice-command modal.
  /// All four wires (service / uploader / outbox / recorder factory)
  /// are required; the CTA is hidden when any is missing.
  Future<void> _openVoiceCommand() async {
    final svc = widget.voiceCommandService;
    final uploader = widget.voiceUploader;
    final outbox = widget.outboxDb;
    final factory = widget.voiceRecorderFactory;
    if (svc == null || uploader == null || outbox == null || factory == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (ctx) => VoiceCommandSheet(
        recorderFactory: factory,
        commandService: svc,
        uploader: uploader,
        outboxDb: outbox,
        visitId: widget.visitId,
        hatContext: widget.hatContext ?? 'operator',
        correlationIdFactory: widget.voiceCorrelationIdFactory ??
            (() => 'voice-${DateTime.now().millisecondsSinceEpoch}'),
      ),
    );
  }

  Future<void> _recordVoiceMemo() async {
    final svc = widget.captureService;
    final factory = widget.voiceRecorderFactory;
    if (svc == null || factory == null) return;

    final memo = await showModalBottomSheet<CapturedVoiceMemo?>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => _VoiceRecorderSheet(adapter: factory()),
    );
    if (memo == null) return;
    if (!mounted) return;

    setState(() => _transitioning = true);
    try {
      final outcome =
          await svc.enqueueVoiceMemo(widget.visitId, memo: memo);
      if (!mounted) return;
      _surfaceCaptureOutcome(outcome, kindLabel: 'Voice memo');
      if (widget.attachments != null) {
        await _refreshAttachments();
      }
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  /// Shared snackbar copy for the three sensor flows.  Keeps the
  /// kind-specific verb in one place rather than smeared across each
  /// CTA handler.
  void _surfaceCaptureOutcome(
    CaptureOutcome outcome, {
    required String kindLabel,
    String? cancelMessage,
  }) {
    String msg;
    switch (outcome) {
      case CaptureCancelled():
        msg = cancelMessage ?? '$kindLabel capture cancelled.';
      case CaptureNotPaired():
        msg = 'Device not paired — re-pair to capture attachments.';
      case CaptureQueuedAndSynced():
        msg = '$kindLabel queued — uploaded.';
      case CaptureQueuedOffline(reason: final r):
        msg = '$kindLabel queued (offline: $r).';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actionsForState(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Visit ${_visit.id}'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // RM-124 — resolved parent-job context first (who/where/
          // what) so a scheduled visit isn't just hex strings.
          if (_visit.jobCustomerName.isNotEmpty)
            _row('Customer', _visit.jobCustomerName),
          if (_visit.jobPropertyAddress.isNotEmpty)
            _row('Address', _visit.jobPropertyAddress),
          if (_visit.jobDescription.isNotEmpty)
            _row('Work', _visit.jobDescription),
          _row('Type', _visit.visitType),
          _row('Status', _visit.status),
          _row('Visit ID', _visit.id),
          _row('Job ID', _visit.jobId),
          if (_visit.actualStart.isNotEmpty) _row('Started', _visit.actualStart),
          if (_visit.outcome.isNotEmpty) _row('Outcome', _visit.outcome),
          if (_visit.notes.isNotEmpty) _row('Notes', _visit.notes),
          _row('Created', _visit.createdAt),
          _row('Updated', _visit.updatedAt),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text('Refresh failed: $_error',
                style: const TextStyle(color: Colors.red)),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 24),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
          if (widget.attachments != null) ..._attachmentsSection(),
        ],
      ),
    );
  }

  /// D-O5m.followup-8 substrate — attachments section shown at the
  /// bottom of VisitDetail when an AttachmentsRepository is wired.
  /// Read-only metadata list today; the camera-capture FAB ships in
  /// the next PR.
  List<Widget> _attachmentsSection() {
    final headerRow = Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          const Text('Attachments',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const Spacer(),
          if (_attachmentsLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );

    if (_attachmentsError != null) {
      return [
        headerRow,
        Text('Failed to load: $_attachmentsError',
            style: const TextStyle(color: Colors.red)),
      ];
    }

    if (!_attachmentsFetched && _attachmentsLoading) {
      return [headerRow, const Text('Loading…')];
    }

    final rows = _attachments ?? const <Attachment>[];
    if (rows.isEmpty) {
      return [
        headerRow,
        const Text(
          'No attachments yet — capture from this site coming soon.',
          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.black54),
        ),
      ];
    }

    return [
      headerRow,
      ...rows.map(_attachmentRow),
    ];
  }

  Widget _attachmentRow(Attachment a) {
    final hasBearer = widget.brainHttpsBase != null &&
        widget.brainHttpsBase!.isNotEmpty &&
        widget.bearerProvider != null &&
        (widget.bearerProvider!() ?? '').isNotEmpty;
    final blobUrl = hasBearer
        ? '${widget.brainHttpsBase}/api/v1/attachments/${a.id}/blob'
        : null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => _onAttachmentTap(a, blobUrl),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _attachmentLeading(a, blobUrl),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(a.kind,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            const Spacer(),
                            Text(formatBytes(a.contentSize),
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(a.capturedAt,
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 12)),
                        if (a.kind == 'gps_pin' && blobUrl != null) ...[
                          const SizedBox(height: 4),
                          _GpsCaption(
                            blobUrl: blobUrl,
                            bearer: widget.bearerProvider?.call() ?? '',
                          ),
                        ],
                        if (a.caption.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(a.caption),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kind-aware leading widget: thumbnail for photo, large icon for
  /// gps_pin / voice_memo / file_other.  Photo is the only kind whose
  /// blob renders inline; the others surface their bytes via the
  /// fullscreen viewer (audio player, etc.) the row tap routes into.
  Widget _attachmentLeading(Attachment a, String? blobUrl) {
    if (a.kind == 'photo' && blobUrl != null) {
      return Image.network(
        blobUrl,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        headers: {
          'Authorization': 'Bearer ${widget.bearerProvider!()!}',
        },
        errorBuilder: (context, error, stackTrace) => const SizedBox(
          width: 100,
          height: 100,
          child: Icon(Icons.broken_image),
        ),
      );
    }
    return Container(
      width: 100,
      height: 100,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(_iconForKind(a.kind), size: 36, color: Colors.black54),
    );
  }

  void _onAttachmentTap(Attachment a, String? blobUrl) {
    if (blobUrl == null) return;
    switch (a.kind) {
      case 'photo':
        _openPhotoViewer(blobUrl);
        break;
      case 'voice_memo':
        _openVoicePlayer(a, blobUrl);
        break;
      case 'gps_pin':
        // GPS pin tap is reserved for a future "open in map" flow;
        // the inline caption already shows lat/lng.  Surfacing a
        // snackbar acknowledges the tap so the row doesn't feel
        // dead.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Map preview ships in a follow-up.')));
        break;
      case 'file_other':
      default:
        // No inline viewer for arbitrary files yet.  Future PR:
        // surface a "save" affordance.
        break;
    }
  }

  void _openVoicePlayer(Attachment a, String blobUrl) {
    final factory = widget.voicePlaybackFactory;
    if (factory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Voice playback not configured.')));
      return;
    }
    final bearer = widget.bearerProvider?.call() ?? '';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VoiceMemoPlayerScreen(
        blobUrl: blobUrl,
        bearer: bearer,
        caption: a.caption.isEmpty ? null : a.caption,
        adapter: factory(),
      ),
    ));
  }

  void _openPhotoViewer(String blobUrl) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Photo')),
        body: Center(
          child: Image.network(
            blobUrl,
            headers: {
              'Authorization': 'Bearer ${widget.bearerProvider!()!}',
            },
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const Padding(padding: EdgeInsets.all(24), child: Icon(Icons.broken_image, size: 48)),
          ),
        ),
      ),
    ));
  }

  IconData _iconForKind(String kind) {
    switch (kind) {
      case 'photo':
        return Icons.photo;
      case 'voice_memo':
        return Icons.mic;
      case 'gps_pin':
        return Icons.location_on;
      case 'file_other':
      default:
        return Icons.attach_file;
    }
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

/// D-O5m.followup-8 GPS + voice memo adapters — modal sheet driving
/// the recording UI.  Owns a [VoiceRecorderController] for its
/// lifetime, surfaces a single Stop button, and pops with the
/// captured memo (or null on cancel / error).
class _VoiceRecorderSheet extends StatefulWidget {
  final VoiceRecorderAdapter adapter;
  const _VoiceRecorderSheet({required this.adapter});

  @override
  State<_VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<_VoiceRecorderSheet> {
  late final VoiceRecorderController _controller;
  StreamSubscription<RecordingState>? _stateSub;
  RecordingState _state = RecordingState.idle;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _controller = VoiceRecorderController(recorder: widget.adapter);
    _stateSub = _controller.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    // Fire-and-forget the start.  When start fails the state stream
    // already reports `error`; the UI surfaces a fallback message
    // and the user can dismiss.
    _controller.start().then((ok) {
      if (ok) {
        _startedAt = DateTime.now();
        _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
          if (!mounted) return;
          if (_startedAt == null) return;
          setState(() {
            _elapsed = DateTime.now().difference(_startedAt!);
          });
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stateSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onStop() async {
    final memo = await _controller.stop();
    if (!mounted) return;
    Navigator.of(context).pop<CapturedVoiceMemo?>(memo);
  }

  Future<void> _onCancel() async {
    await _controller.cancel();
    if (!mounted) return;
    Navigator.of(context).pop<CapturedVoiceMemo?>(null);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic, size: 64, color: Colors.red),
          const SizedBox(height: 12),
          Text(
            _state == RecordingState.recording
                ? 'Recording — ${_fmt(_elapsed)}'
                : _state == RecordingState.error
                    ? 'Recording failed.'
                    : _state == RecordingState.stopped
                        ? 'Stopping…'
                        : 'Starting…',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                onPressed: _onCancel,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: _state == RecordingState.recording ? _onStop : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// D-O5m.followup-8 GPS + voice memo adapters — caption widget that
/// fetches a gps_pin's blob bytes once + decodes them to render a
/// "Lat: X.XXX, Lng: Y.YYY, ±Z m" subtitle.  The fetch is bearer-
/// gated through the same `/api/v1/attachments/<id>/blob` endpoint
/// the photo viewer uses, but unlike the photo viewer the GPS row
/// renders the decoded text inline rather than the raw bytes.
class _GpsCaption extends StatefulWidget {
  final String blobUrl;
  final String bearer;

  const _GpsCaption({required this.blobUrl, required this.bearer});

  @override
  State<_GpsCaption> createState() => _GpsCaptionState();
}

class _GpsCaptionState extends State<_GpsCaption> {
  CapturedGpsPin? _pin;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final uri = Uri.parse(widget.blobUrl);
      final client = HttpClient();
      final req = await client.getUrl(uri);
      if (widget.bearer.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer ${widget.bearer}');
      }
      final resp = await req.close();
      final bytes = await consolidateHttpClientResponseBytes(resp);
      if (!mounted) return;
      setState(() {
        _pin = decodeGpsBlob(bytes);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Text('Loading location…',
          style: TextStyle(fontSize: 12, color: Colors.black54));
    }
    final pin = _pin;
    if (pin == null) {
      return const Text('Location unavailable.',
          style: TextStyle(fontSize: 12, color: Colors.black54));
    }
    final acc = pin.accuracyMeters == null
        ? ''
        : ', ±${pin.accuracyMeters!.toStringAsFixed(0)} m';
    return Text(
      'Lat: ${pin.latitude.toStringAsFixed(4)}, '
      'Lng: ${pin.longitude.toStringAsFixed(4)}$acc',
      style: const TextStyle(fontSize: 12, color: Colors.black54),
    );
  }
}

```
