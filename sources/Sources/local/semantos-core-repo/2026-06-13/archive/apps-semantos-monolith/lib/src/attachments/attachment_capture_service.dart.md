---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/attachments/attachment_capture_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.878180+00:00
---

# archive/apps-semantos-monolith/lib/src/attachments/attachment_capture_service.dart

```dart
// D-O5m.followup-8 capture+upload — Helm-side glue between the
// camera, the cell signer/builder, the outbox, and the upload
// transport.
//
// VisitDetailScreen calls `captureAndEnqueue(visitId)` when the
// operator taps the "Capture photo" CTA.  The service:
//
//   1. Drives `captureFromCamera` via the injected picker.
//   2. Reads the device's child-cert priv + cert id from
//      ChildCertStore.
//   3. Calls `attachment_builder.buildSignedAttachment` to mint the
//      signed cell.
//   4. Writes the blob to a stable disk location under
//      `<documents>/outbox-blobs/<sha>.bin`.
//   5. Enqueues an `oddjobz.attachment.v1` row in the outbox (with
//      `blob_path` pointing at the on-disk blob).
//   6. Triggers an immediate flush attempt; the helm UI surfaces the
//      summary as a snackbar ("Photo queued — uploading…" vs "Photo
//      queued (offline)").
//
// The service is tested via stub injections in
// `test/attachments/attachment_capture_service_test.dart`.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../gradient/oddjobz_extension_context.dart' show kOddjobzDomainFlag;
import '../identity/child_cert_store.dart';
import '../outbox/outbox_db.dart';
import '../outbox/outbox_service.dart';
import '../sensors/camera_capture.dart';
import '../sensors/gps_capture.dart';
import '../sensors/voice_memo_capture.dart';
import 'attachment_builder.dart';

/// Outcome of a capture attempt — surfaces the typed result to the
/// UI so the snackbar copy can adapt.
sealed class CaptureOutcome {
  const CaptureOutcome();
}

class CaptureCancelled extends CaptureOutcome {
  const CaptureCancelled();
}

class CaptureNotPaired extends CaptureOutcome {
  const CaptureNotPaired();
}

class CaptureQueuedAndSynced extends CaptureOutcome {
  final String attachmentId;
  const CaptureQueuedAndSynced(this.attachmentId);
}

class CaptureQueuedOffline extends CaptureOutcome {
  final String attachmentId;
  final String reason;
  const CaptureQueuedOffline(this.attachmentId, this.reason);
}

/// Owns the dependencies + the captureAndEnqueue flow.  Stateless
/// per-call — same instance can serve every visit detail screen.
class AttachmentCaptureService {
  final ChildCertStore certStore;
  final OutboxDb outboxDb;
  final OutboxService outboxService;
  final CameraPicker picker;
  final OutboxFlushAdapter flushAdapter;
  final Future<Directory> Function() blobsDirProvider;
  final DateTime Function() clock;

  AttachmentCaptureService({
    required this.certStore,
    required this.outboxDb,
    required this.outboxService,
    required this.picker,
    required this.flushAdapter,
    required this.blobsDirProvider,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Drive the camera, sign the cell, enqueue + best-effort flush.
  Future<CaptureOutcome> captureAndEnqueue(String visitId) async {
    final cert = await certStore.read();
    if (cert == null) return const CaptureNotPaired();

    final captured = await captureFromCamera(picker: picker, clock: clock);
    if (captured == null) return const CaptureCancelled();

    return _signEnqueueFlush(
      cert: cert,
      visitId: visitId,
      kind: 'photo',
      blobBytes: captured.bytes,
      mimeType: captured.mimeType,
      capturedAt: captured.capturedAt,
    );
  }

  /// Drive the geolocator, sign the gps_pin cell, enqueue + best-
  /// effort flush.  Same shape as [captureAndEnqueue] but for GPS
  /// pins; the only differences are the `kind`, the `mimeType`
  /// (`application/json`), and the blob source (canonical-JSON
  /// encoding of the pin via `gpsBlobBytes`).
  Future<CaptureOutcome> captureGpsAndEnqueue(
    String visitId, {
    required GeolocatorAdapter geolocator,
  }) async {
    final cert = await certStore.read();
    if (cert == null) return const CaptureNotPaired();

    final pin = await captureCurrentLocation(
      geolocator: geolocator,
      clock: clock,
    );
    if (pin == null) return const CaptureCancelled();

    return _signEnqueueFlush(
      cert: cert,
      visitId: visitId,
      kind: 'gps_pin',
      blobBytes: gpsBlobBytes(pin),
      mimeType: 'application/json',
      capturedAt: pin.capturedAt,
    );
  }

  /// Sign + enqueue a voice_memo cell from a [CapturedVoiceMemo] the
  /// helm has already produced via the `VoiceRecorderController`'s
  /// start/stop UI.  Unlike camera + GPS, voice memo capture is
  /// driven from a recording sheet inside the helm (so the operator
  /// can see the elapsed-time UI), so the service takes the already-
  /// captured memo rather than driving the recorder itself.
  Future<CaptureOutcome> enqueueVoiceMemo(
    String visitId, {
    required CapturedVoiceMemo memo,
  }) async {
    final cert = await certStore.read();
    if (cert == null) return const CaptureNotPaired();

    return _signEnqueueFlush(
      cert: cert,
      visitId: visitId,
      kind: 'voice_memo',
      blobBytes: memo.bytes,
      mimeType: memo.mimeType,
      capturedAt: memo.capturedAt,
    );
  }

  /// Shared sign-enqueue-flush body for the three sensor flows.  The
  /// substrate (cell signer + outbox + brain upload endpoint) is
  /// fully kind-agnostic so this body is identical for photo / gps /
  /// voice — only the inputs differ.
  Future<CaptureOutcome> _signEnqueueFlush({
    required ChildCertRecord cert,
    required String visitId,
    required String kind,
    required Uint8List blobBytes,
    required String mimeType,
    required String capturedAt,
  }) async {
    // Build the signed cell.
    final priv = _hexToBytes(cert.devicePrivHex);
    final certIdHex = cert.brainPinCertId; // 32 hex chars; the device-side cert id.
    final signed = buildSignedAttachment(
      visitId: visitId,
      kind: kind,
      blobBytes: blobBytes,
      mimeType: mimeType,
      capturedAt: capturedAt,
      capturedByCertId: _truncCertId(certIdHex),
      devicePrivBytes: priv,
    );

    // Persist the blob to a stable on-disk location keyed by
    // content_hash so the outbox row's blob_path is shareable across
    // app restarts.
    final dir = await blobsDirProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final blobFile = File('${dir.path}/${signed.contentHash}.bin');
    await blobFile.writeAsBytes(blobBytes, flush: true);

    final attachmentId = signed.payload['attachmentId'] as String;
    // W1.2 — encode the attachmentId string as a 32-byte cellId BLOB and
    // the upload-metadata JSON as the payload BLOB.
    final cellIdBytes = utf8.encode(attachmentId);
    final cellId32 = Uint8List(32)
      ..setRange(0, cellIdBytes.length.clamp(0, 32), cellIdBytes);
    await outboxDb.enqueue(
      cellId: cellId32,
      domainFlag: kOddjobzDomainFlag,
      payload: Uint8List.fromList(utf8.encode(signed.toUploadMetadataJson())),
    );

    // Best-effort immediate flush — the helm uses the summary to
    // pick the right snackbar copy.  Errors here are non-fatal; the
    // entry stays queued for the next flush pass.
    try {
      final summary = await outboxService.flush(flushAdapter);
      if (summary.succeeded > 0) {
        return CaptureQueuedAndSynced(attachmentId);
      }
      if (summary.unauthorised) {
        return CaptureQueuedOffline(attachmentId, 'bearer rejected');
      }
      return CaptureQueuedOffline(
        attachmentId,
        summary.retryable > 0 ? 'network unavailable' : 'queued for retry',
      );
    } catch (e) {
      return CaptureQueuedOffline(attachmentId, e.toString());
    }
  }
}

/// 32-hex-char form used as `capturedByCertId`.  The `brainPinCertId`
/// is already 32 hex chars in the post-pairing record; this helper is
/// defensive against future schema rotation that might pad/truncate.
String _truncCertId(String certIdHex) {
  if (certIdHex.length >= 32) return certIdHex.substring(0, 32);
  return certIdHex.padRight(32, '0');
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

```
