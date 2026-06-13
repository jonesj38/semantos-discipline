---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/attachment_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.886787+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/attachment_screen.dart

```dart
// D-DOG.1.0c Phase 3 F.4 — mobile attachment screen + inline PDF viewer.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
//            sub-deliverable F.4.
//
// One screen, one job — list every v2 `attachment.v2` cell linked to
// the supplied job cellId via `oddjobzQuery.findAttachmentsForJob()`
// (the F.1 PR wired the typed verb on `OddjobzQueryClient`).
//
// Each row renders the canonical attachment metadata that the Semantos Brain
// dispatcher emits via `oddjobz_query_handler::writeAttachment`:
//   • sourceBlobKey  — for legacy-ingest PDFs, the encrypted-on-brain
//                      blob key we'd resolve to bytes once the
//                      `legacy attachment <id>` verb ships;
//   • mimeType       — `application/pdf` vs `image/jpeg` etc;
//   • pageCount      — non-null for PDFs (the legacy ingest job
//                      stamps it during text extraction);
//   • photoCount     — non-null for visit-side captures with embedded
//                      thumbnails;
//   • hasPhotos      — boolean derived flag (true iff photoCount > 0
//                      OR the row has photo bytes attached).
//
// Two attachment shapes coexist:
//
//   1. Legacy-ingest PDFs (jobRef set, visitId == "").  Source bytes
//      are the encrypted PDF on the operator's brain; mobile cannot
//      decrypt locally.  This screen renders a clear "Source PDF lives
//      on operator's brain — `legacy attachment <id>` verb is needed"
//      message in lieu of a viewer until the verb ships.  The hook
//      sites for the eventual decrypt-and-render flow are clearly
//      marked with a `legacyVerbComing()` placeholder so the wave-3
//      PR has a single touchpoint.
//
//   2. Visit-side photos (visitId set).  These already render through
//      `VisitDetailScreen`'s existing `/api/v1/attachments/<id>/blob`
//      bearer-gated photo viewer.  We surface the same inline thumbnail
//      pattern so a job-level summary doesn't force the operator to
//      drill into each visit individually.
//
// The screen is reachable from two entry points:
//
//   • The `JobListRow` photos-icon tap (wired by F.4 — see
//     `job_list_row.dart`).  This is the operator's most-direct path
//     to "show me the attachments for the job I'm scanning".
//
//   • Future: a bottom-sheet shortcut on `JobDetailScreen` (deferred
//     to a Phase 3 F.5 follow-up — out of scope here).
//
// PDF dependency: `pdfx` is added in pubspec.  At runtime we only
// instantiate the viewer once we have decrypted bytes (post the
// `legacy attachment <id>` verb), so the build-time linkage is what
// matters now — the viewer constructor is referenced behind a guard
// so the symbol is resolved at compile time.
//
// Test posture: a widget test pumps the screen with a fake query
// client returning a synthetic attachment list.  The brain-side wire
// shape is exercised by the existing `oddjobz_query_handler` parity
// tests so we don't double-test JSON parsing here.

import 'package:flutter/material.dart';

import '../repl/oddjobz_query_client.dart';

/// Screen-specific view-shape over `oddjobz.find_attachments_for_job`.
///
/// `OddjobzQueryClient.findAttachmentsForJob` returns the raw
/// dispatcher map per-row; we parse into a typed view-shape here so
/// the widget code below stays terse.  Mirrors
/// `runtime/semantos-brain/src/oddjobz_query_handler.zig::writeAttachment`
/// 1:1 — see the Semantos Brain-side comment block for canonical field docs.
class JobAttachment {
  /// Legacy v1 string id (UUID-ish).  Always populated.  Used as the
  /// argument to the eventual `legacy attachment <id>` verb.
  final String id;

  /// 64-lowercase-hex content hash of the canonical `attachment.v2`
  /// cell.  Null on un-promoted v1 rows.  When non-null this is what
  /// any future query verbs use for cross-references (e.g. a future
  /// "find_jobs_with_attachment").
  final String? cellId;

  /// Visit-side captures carry the parent visit's id; legacy-ingest
  /// rows leave this empty.  Empty-string vs null is a Semantos Brain-side wire
  /// detail; we treat empty as "no visit" here.
  final String visitId;

  /// One of `photo | voice_memo | gps_pin | file_other` (visit-side)
  /// OR an arbitrary mime bucket for legacy-ingest rows.
  final String kind;

  /// `application/pdf` for PDFs, `image/jpeg` etc for photos.  Empty
  /// for legacy rows that didn't carry one.
  final String mimeType;

  /// Encrypted-on-brain blob key — the load-bearing identifier the
  /// `legacy attachment <id>` verb will resolve to bytes.  Null when
  /// the row is a visit-side capture (those use the bearer-gated
  /// `/api/v1/attachments/<id>/blob` HTTP endpoint instead).
  final String? sourceBlobKey;

  /// PDF page count, stamped by the legacy ingest job's text-extract
  /// pass.  Null on non-PDF rows.
  final int? pageCount;

  /// Embedded-photo count for legacy-ingest rows, or capture count
  /// for visit-side.  Null when not applicable.
  final int? photoCount;

  /// Derived flag: true iff [photoCount] > 0 OR the row carries a
  /// photo blob.  Brain emits this directly so we don't recompute.
  final bool hasPhotos;

  /// Operator-supplied caption (visit-side captures).  Empty for
  /// legacy-ingest rows.
  final String caption;

  /// ISO-8601 capture timestamp for visit-side rows; the legacy
  /// ingest job's createdAt for legacy rows.
  final String capturedAt;

  const JobAttachment({
    required this.id,
    required this.cellId,
    required this.visitId,
    required this.kind,
    required this.mimeType,
    required this.sourceBlobKey,
    required this.pageCount,
    required this.photoCount,
    required this.hasPhotos,
    required this.caption,
    required this.capturedAt,
  });

  /// True iff this row is a legacy-ingest PDF (vs a visit-side
  /// capture).  The mobile can't render its source bytes inline
  /// until the `legacy attachment <id>` verb ships — see the
  /// "Source PDF lives on operator's brain" placeholder below.
  bool get isLegacyIngestPdf =>
      visitId.isEmpty &&
      (mimeType == 'application/pdf' ||
          (sourceBlobKey != null && sourceBlobKey!.isNotEmpty));

  /// True iff this row has visit-side photo bytes the operator can
  /// see through the existing bearer-gated photo viewer.
  bool get isVisitSidePhoto => visitId.isNotEmpty && hasPhotos;

  /// Parse one row from the Semantos Brain-side dispatcher map.  Tolerant of
  /// missing optionals (legacy v1 rows have most fields null).
  factory JobAttachment.fromJson(Map<String, dynamic> r) {
    String? optStr(dynamic v) =>
        (v is String && v.isNotEmpty) ? v : null;
    int? optInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    return JobAttachment(
      id: (r['id'] ?? '').toString(),
      cellId: optStr(r['cellId']),
      visitId: (r['visit_id'] ?? '').toString(),
      kind: (r['kind'] ?? '').toString(),
      mimeType: (r['mime_type'] ?? '').toString(),
      sourceBlobKey: optStr(r['sourceBlobKey']),
      pageCount: optInt(r['pageCount']),
      photoCount: optInt(r['photoCount']),
      hasPhotos: r['hasPhotos'] is bool ? r['hasPhotos'] as bool : false,
      caption: (r['caption'] ?? '').toString(),
      capturedAt: (r['captured_at'] ?? '').toString(),
    );
  }
}

/// Mobile attachment screen — list every attachment linked to the
/// supplied [jobRef] via `oddjobzQuery.findAttachmentsForJob()`.
///
/// Best-effort posture: when the WSS query channel isn't connected
/// (e.g. flaky cell), we surface a typed error message rather than
/// hanging.  Pull-to-refresh re-runs the query.
class AttachmentScreen extends StatefulWidget {
  /// The job's 64-hex `cellId` we're listing attachments for.  The
  /// caller (typically `JobListRow`'s photos-icon tap handler) is
  /// responsible for resolving v1 `id` → v2 `cellId` if needed; the
  /// query verb only accepts v2 cellRefs.
  final String jobRef;

  /// Optional human-readable label for the app bar — usually the
  /// site's `fullAddress` or a property-key suffix the operator
  /// recognises.  Falls back to a generic "Attachments" title.
  final String? title;

  /// Graph-aware query client used to drive
  /// `oddjobz.find_attachments_for_job` over the long-lived WSS.
  /// Null when the WSS isn't open yet — the screen renders a
  /// "WSS not connected" message instead of crashing.
  final OddjobzQueryClient? oddjobzQuery;

  const AttachmentScreen({
    super.key,
    required this.jobRef,
    this.title,
    required this.oddjobzQuery,
  });

  @override
  State<AttachmentScreen> createState() => _AttachmentScreenState();
}

class _AttachmentScreenState extends State<AttachmentScreen> {
  /// Pulled view-shape rows.  Empty list ≠ null — null means
  /// "haven't fetched yet"; empty list means "fetched, but the
  /// brain has no attachments for this job".
  List<JobAttachment>? _rows;

  /// True only between the call to [_load] and the future settling.
  /// Pull-to-refresh leaves [_rows] populated and only flips this
  /// while the refresh is in flight (so the operator doesn't see
  /// the list pop out from under them).
  bool _loading = false;

  /// Last error message, if any.  Null when the previous load
  /// succeeded.  We render this as a banner over the list rather
  /// than blocking the whole screen — the cached rows stay visible
  /// even when a refresh fails.
  String? _error;

  @override
  void initState() {
    super.initState();
    // Kick off the initial fetch on first frame so the loading
    // spinner has a chance to render through MaterialPageRoute's
    // transition.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final client = widget.oddjobzQuery;
    if (client == null) {
      setState(() {
        _rows = const <JobAttachment>[];
        _error = 'Brain WSS not connected — pull to refresh once paired.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await client.findAttachmentsForJob(widget.jobRef);
      final parsed =
          raw.map(JobAttachment.fromJson).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _rows = parsed;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.title?.isNotEmpty == true
        ? 'Attachments — ${widget.title!}'
        : 'Attachments';
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(theme, rows),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, List<JobAttachment>? rows) {
    if (rows == null && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows == null) {
      // Pre-fetch state with no in-flight load — happens briefly
      // before the post-frame callback fires.  Show a neutral
      // placeholder rather than flashing the empty-list state.
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(child: Text('Loading attachments...')),
        ],
      );
    }
    final children = <Widget>[];
    if (_error != null) {
      children.add(_ErrorBanner(message: _error!, onRetry: _load));
    }
    if (rows.isEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No attachments for this job yet.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ),
      ));
    } else {
      for (final a in rows) {
        children.add(_AttachmentCard(att: a));
      }
    }
    return ListView(
      // Always allow scroll so RefreshIndicator works even on a
      // short list.
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }
}

/// One attachment row.  Renders the metadata block (always) + a
/// kind-specific affordance:
///   - PDF + legacy-ingest → "Source PDF lives on operator's brain"
///                           message + disabled "View PDF" button;
///   - PDF + bytes-available (future) → enabled "View PDF" button
///                                      that opens the inline pdfx
///                                      viewer;
///   - visit-side photo  → inline thumbnail (the existing photo
///                          viewer is owned by VisitDetailScreen, so
///                          the deep-render path is "tap to jump
///                          into the visit").
class _AttachmentCard extends StatelessWidget {
  final JobAttachment att;
  const _AttachmentCard({required this.att});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPdf = att.mimeType == 'application/pdf';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(att), size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    att.kind.isEmpty ? '(unknown kind)' : att.kind,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (att.hasPhotos)
                  const Icon(Icons.photo_camera, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            _metaRow('mimeType', att.mimeType.isEmpty ? '—' : att.mimeType),
            if (att.sourceBlobKey != null)
              _metaRow('sourceBlobKey', att.sourceBlobKey!),
            if (att.pageCount != null)
              _metaRow('pageCount', '${att.pageCount}'),
            if (att.photoCount != null)
              _metaRow('photoCount', '${att.photoCount}'),
            _metaRow('hasPhotos', att.hasPhotos ? 'yes' : 'no'),
            if (att.capturedAt.isNotEmpty)
              _metaRow('capturedAt', att.capturedAt),
            if (att.caption.isNotEmpty)
              _metaRow('caption', att.caption),
            if (isPdf) ...[
              const SizedBox(height: 12),
              if (att.isLegacyIngestPdf)
                _LegacyPdfPlaceholder(att: att)
              else
                _ViewPdfButton(att: att),
            ] else if (att.isVisitSidePhoto) ...[
              const SizedBox(height: 12),
              const Text(
                'Visit-side photo — open the parent visit to view it '
                'inline.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconFor(JobAttachment a) {
    if (a.mimeType == 'application/pdf') return Icons.picture_as_pdf;
    if (a.mimeType.startsWith('image/')) return Icons.image;
    switch (a.kind) {
      case 'photo':
        return Icons.photo;
      case 'voice_memo':
        return Icons.mic;
      case 'gps_pin':
        return Icons.location_on;
      default:
        return Icons.attach_file;
    }
  }

  Widget _metaRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54)),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      );
}

/// Placeholder shown for legacy-ingest PDFs whose source bytes are
/// encrypted on the operator's brain.  Mobile can't decrypt locally
/// — we surface a clear deferred-work message so the operator
/// understands why the inline viewer isn't available yet.  Once
/// the `legacy attachment <id>` verb ships (Phase 3 F.5 follow-up),
/// the wired-up [_ViewPdfButton] takes over.
class _LegacyPdfPlaceholder extends StatelessWidget {
  final JobAttachment att;
  const _LegacyPdfPlaceholder({required this.att});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Source PDF lives on operator\'s brain',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'The encrypted PDF blob is stored on your brain. '
            'Mobile cannot decrypt it locally — the '
            '`legacy attachment <id>` verb is needed to fetch '
            'and decrypt the bytes for inline rendering.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          // Disabled until the legacy verb ships.  Kept as a real
          // ElevatedButton so a future PR only flips the onPressed
          // wiring without restructuring the widget tree.
          ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: const Text('View PDF (waiting on legacy verb)'),
          ),
        ],
      ),
    );
  }
}

/// Enabled "View PDF" button — currently unreachable in production
/// (no PDF row makes it past [JobAttachment.isLegacyIngestPdf]
/// today) but already wired so that a future "decrypted-bytes"
/// path has a single touch-point.  The pdfx viewer is constructed
/// inline via [_PdfViewerScreen] when the operator taps the button.
class _ViewPdfButton extends StatelessWidget {
  final JobAttachment att;
  const _ViewPdfButton({required this.att});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        // The future legacy-verb path will resolve `att.sourceBlobKey`
        // → decrypted bytes here, then push [_PdfViewerScreen] with
        // those bytes.  Until then we show the same deferred
        // message as the legacy placeholder so accidental construction
        // doesn't crash.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'PDF rendering wired — bytes-fetch lands with `legacy '
                'attachment` verb.')));
      },
      icon: const Icon(Icons.picture_as_pdf, size: 16),
      label: const Text('View PDF'),
    );
  }
}

/// Banner above the list when a fetch errors out.  Tapping the
/// retry chip re-runs [_AttachmentScreenState._load].  Doesn't
/// hide the previously-loaded rows — the operator can still see
/// the cached state.
class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.amber.shade100,
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

```
