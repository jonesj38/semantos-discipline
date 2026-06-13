---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/mesh/mesh_transport.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.903112+00:00
---

# archive/apps-semantos-monolith/lib/src/mesh/mesh_transport.dart

```dart
// D-O5m.followup-6 Phase 2 — Top-level MeshTransport abstraction.
//
// Reference: this brief.  The outbox consumes `MeshTransport.send`;
// incoming bundles flow through `MeshTransport.incoming()`.  The
// factory selects between two backends at app startup:
//
//   • ShardProxyMeshTransport — phone+brain are structurally peers,
//     bundles flow through a shard-proxy relay (phone publishes,
//     brain subscribes; brain publishes back, phone subscribes).
//   • HttpReplFallbackTransport — backward-compat path for environments
//     without shard-proxy reachability.  Routes by payload_type to the
//     existing per-kind uploaders (DioAttachmentUploader,
//     VoiceExtractFlushUploader, ReplClient.send for cell.create).
//     Receive is a no-op stream (incoming live-updates ride the
//     existing WSS path).
//
// The HTTP-REPL fallback preserves backward compat — the brief is
// explicit that we don't break it.  Phase 2's contribution is the
// seam that makes the mesh path real when the operator has wired a
// shard-proxy.

import 'dart:async';
import 'dart:io';

import '../repl/repl_client.dart';
import '../repl/repl_errors.dart';
import '../outbox/outbox_service.dart';
import 'shard_proxy_client.dart';
import 'signed_bundle.dart';

/// Abstract over the wire layer the outbox uses to send + receive
/// SignedBundles.
abstract class MeshTransport {
  /// Send a bundle.  Returns when the transport accepts the bundle
  /// (NOT when the recipient processes it).  Failures are typed
  /// [MeshSendResult]s rather than throws so the outbox's flush loop
  /// has a single result-mapping site.
  Future<MeshSendResult> send(SignedBundle bundle);

  /// Stream of bundles addressed to this device.  Hot stream — caller
  /// listens once and forwards events to the outbox or live-tick
  /// handlers.  Backends that don't have a native receive path return
  /// `Stream<SignedBundle>.empty()` (the existing WSS path covers
  /// live-updates for fallback environments).
  Stream<SignedBundle> incoming();

  /// Human-readable label for the surface bar / UI (returned via
  /// [MeshTransportFactory.currentState]).
  String get label;

  Future<void> close();
}

/// Result of a [MeshTransport.send] call.  Sealed so the outbox's
/// switch covers every case.
sealed class MeshSendResult {
  const MeshSendResult();
}

/// Successful publish — the relay accepted the bundle.
class MeshSent extends MeshSendResult {
  /// Optional bundle id the relay returned (sha256 of the wire bytes,
  /// or whatever the relay assigns).  Empty when the relay doesn't
  /// echo an id.
  final String bundleId;
  const MeshSent({this.bundleId = ''});
}

/// The transport itself isn't reachable (offline, shard-proxy down,
/// repl backend not configured).  Distinct from a real backend
/// failure — the outbox can leave the entry queued and retry later.
class MeshTransportUnavailable extends MeshSendResult {
  final String reason;
  const MeshTransportUnavailable({required this.reason});
}

/// The transport is reachable but reported a failure (404 from the
/// relay, validation error from the brain, etc.).  Carries optional
/// HTTP status when relevant.
class MeshSendFailed extends MeshSendResult {
  final String reason;
  final int? statusCode;
  const MeshSendFailed({required this.reason, this.statusCode});
}

// ─────────────────────────────────────────────────────────────────────
// ShardProxyMeshTransport — the post-shard-proxy peer-mesh path.
// ─────────────────────────────────────────────────────────────────────

/// Wraps a [ShardProxyClient] (publish + subscribe) into the
/// MeshTransport contract.
class ShardProxyMeshTransport implements MeshTransport {
  final ShardProxyClient _client;
  final String _myCertId;
  Stream<SignedBundle>? _incoming;

  ShardProxyMeshTransport({
    required ShardProxyClient client,
    required String myCertId,
  })  : _client = client,
        _myCertId = myCertId;

  @override
  String get label => 'shard-proxy';

  @override
  Future<MeshSendResult> send(SignedBundle bundle) async {
    try {
      await _client.publish(bundle: bundle);
      return const MeshSent();
    } on ShardProxyError catch (e) {
      if (e.reason == 'network_error' || e.reason == 'closed') {
        return MeshTransportUnavailable(reason: e.reason);
      }
      return MeshSendFailed(reason: e.reason, statusCode: e.statusCode);
    } catch (e) {
      return MeshSendFailed(reason: 'unknown_error: $e');
    }
  }

  @override
  Stream<SignedBundle> incoming() {
    _incoming ??= _client.subscribe(myCertId: _myCertId).asBroadcastStream();
    return _incoming!;
  }

  @override
  Future<void> close() async {
    _client.close();
  }
}

// ─────────────────────────────────────────────────────────────────────
// HttpReplFallbackTransport — backward-compat path.  Routes by
// payload_type to the existing per-kind uploaders.  No native receive
// stream; incoming live-updates ride the existing WSS path.
// ─────────────────────────────────────────────────────────────────────

/// Payload-type tag for attachment-create bundles.  Mirrors the cell-
/// type discriminator the outbox uses.
const String payloadTypeAttachmentCreate = 'oddjobz.attachment.create';

/// Payload-type tag for voice-extract bundles.
const String payloadTypeVoiceExtract = 'oddjobz.voice-extract';

/// Payload-type tag for generic signed-cell bundles (the default case;
/// the brain dispatches via the inner request envelope).
const String payloadTypeCellCreate = 'oddjobz.cell.create';

/// Adapter the fallback transport uses to dispatch by payload_type.
/// Tests inject a stub; production wiring threads the existing
/// uploaders + REPL client through.
class HttpReplFallbackAdapters {
  final AttachmentUploader? attachmentUploader;
  final VoiceExtractFlushUploader? voiceUploader;
  final ReplClient? replClient;

  /// Optional mapping from a SignedBundle attachment payload to the
  /// disk file the uploader should consume.  In production this is
  /// supplied by the outbox layer (it owns the blob_path).  For tests
  /// the stub uploader doesn't need a real File.
  final File Function(SignedBundle bundle)? resolveAttachmentBlob;
  final File Function(SignedBundle bundle)? resolveVoiceBlob;

  /// Optional extractor for the metadata JSON the legacy uploaders
  /// expect.  The bundle's payload bytes ARE the JSON the brain
  /// dispatches against — for the legacy multipart shape we extract
  /// the metadata field from inside it.
  final String Function(SignedBundle bundle)? extractMetadataJson;

  /// Optional extractor for the REPL command that bundle.payload
  /// represents.  The default falls back to dispatching the bundle's
  /// payload bytes verbatim as a JSON-encoded REPL line.
  final String Function(SignedBundle bundle)? extractReplCommand;

  const HttpReplFallbackAdapters({
    this.attachmentUploader,
    this.voiceUploader,
    this.replClient,
    this.resolveAttachmentBlob,
    this.resolveVoiceBlob,
    this.extractMetadataJson,
    this.extractReplCommand,
  });
}

/// Backward-compat transport.  Routes [SignedBundle.payloadType] to
/// the existing uploader / REPL surfaces.  This is the path used when
/// no shard-proxy is configured (or it's unreachable at startup).
class HttpReplFallbackTransport implements MeshTransport {
  final HttpReplFallbackAdapters _adapters;

  HttpReplFallbackTransport({
    required HttpReplFallbackAdapters adapters,
  }) : _adapters = adapters;

  @override
  String get label => 'http-repl-fallback';

  @override
  Future<MeshSendResult> send(SignedBundle bundle) async {
    try {
      switch (bundle.payloadType) {
        case payloadTypeAttachmentCreate:
          final uploader = _adapters.attachmentUploader;
          final resolveBlob = _adapters.resolveAttachmentBlob;
          final extractMeta = _adapters.extractMetadataJson;
          if (uploader == null || resolveBlob == null || extractMeta == null) {
            return const MeshTransportUnavailable(
                reason: 'attachment_uploader_not_configured');
          }
          await uploader.upload(
            blobFile: resolveBlob(bundle),
            metadataJson: extractMeta(bundle),
          );
          return const MeshSent();
        case payloadTypeVoiceExtract:
          final uploader = _adapters.voiceUploader;
          final resolveBlob = _adapters.resolveVoiceBlob;
          final extractMeta = _adapters.extractMetadataJson;
          if (uploader == null || resolveBlob == null || extractMeta == null) {
            return const MeshTransportUnavailable(
                reason: 'voice_uploader_not_configured');
          }
          await uploader.upload(
            audioFile: resolveBlob(bundle),
            envelopeJson: extractMeta(bundle),
          );
          return const MeshSent();
        case payloadTypeCellCreate:
        default:
          final repl = _adapters.replClient;
          final extractCmd = _adapters.extractReplCommand;
          if (repl == null || extractCmd == null) {
            return const MeshTransportUnavailable(
                reason: 'repl_client_not_configured');
          }
          await repl.send(extractCmd(bundle));
          return const MeshSent();
      }
    } on ReplUnauthorisedError catch (e) {
      return MeshSendFailed(reason: 'unauthorised: ${e.reason}', statusCode: 401);
    } on ReplValidationError catch (e) {
      return MeshSendFailed(reason: 'validation_failed: ${e.message}', statusCode: 400);
    } on ReplBackendUnavailable catch (e) {
      return MeshTransportUnavailable(reason: 'backend_unavailable: ${e.message}');
    } on ReplError catch (e) {
      return MeshSendFailed(reason: 'repl_error: ${e.message}');
    } catch (e) {
      return MeshSendFailed(reason: 'unknown_error: $e');
    }
  }

  /// HTTP-REPL doesn't have a native receive stream — incoming live-
  /// updates are handled by the existing WSS path on `helm_event_stream`.
  @override
  Stream<SignedBundle> incoming() => const Stream<SignedBundle>.empty();

  @override
  Future<void> close() async {}
}

// ─────────────────────────────────────────────────────────────────────
// Factory — selects the transport at app startup.
// ─────────────────────────────────────────────────────────────────────

/// Snapshot of the current transport state — used by the settings UI.
class MeshTransportState {
  /// Which backend is live: 'shard-proxy' / 'http-repl-fallback' /
  /// 'unconfigured'.
  final String label;

  /// True iff a shard-proxy is configured AND reachable at the last
  /// reachability probe.
  final bool meshActive;

  /// The configured shard-proxy endpoint, or null if not configured.
  final String? shardProxyEndpoint;

  /// Unix-seconds timestamp of the last factory selection attempt.
  final int lastAttemptedUnix;

  const MeshTransportState({
    required this.label,
    required this.meshActive,
    required this.shardProxyEndpoint,
    required this.lastAttemptedUnix,
  });
}

/// Inputs the factory needs to construct + reachability-probe the
/// shard-proxy backend.
class MeshTransportFactoryInputs {
  /// The shard-proxy endpoint (from /api/v1/info).  null → not
  /// configured; factory returns the fallback transport without
  /// probing.
  final String? shardProxyEndpoint;

  /// The shard group id (from tenant manifest [mesh] / /api/v1/info).
  final String shardGroupId;

  /// This device's leaf cert id (32 hex chars) — used by the
  /// subscribe filter.
  final String myCertId;

  /// Adapter set for the fallback transport.  Always required (the
  /// factory may fall back at any time).
  final HttpReplFallbackAdapters fallbackAdapters;

  /// Pre-built ShardProxyClient.  Tests inject a mock; production
  /// wiring constructs one with the real Dio.  When null, the factory
  /// behaves as if no shard-proxy is configured (returns fallback).
  final ShardProxyClient? shardProxyClient;

  const MeshTransportFactoryInputs({
    required this.shardProxyEndpoint,
    required this.shardGroupId,
    required this.myCertId,
    required this.fallbackAdapters,
    this.shardProxyClient,
  });
}

/// Factory that constructs a MeshTransport at app startup.  Probes
/// the shard-proxy for reachability; falls back to HTTP-REPL when the
/// probe fails.  Exposes a state snapshot for the settings UI.
class MeshTransportFactory {
  /// Build a [MeshTransport] from `inputs`.  Returns the live
  /// transport + a [MeshTransportState] snapshot.  The state lets the
  /// settings UI render the current backend label without re-probing.
  static Future<({MeshTransport transport, MeshTransportState state})>
      select(MeshTransportFactoryInputs inputs) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final shardProxyConfigured = inputs.shardProxyEndpoint != null &&
        inputs.shardProxyEndpoint!.isNotEmpty &&
        inputs.shardProxyClient != null;

    if (!shardProxyConfigured) {
      return (
        transport: HttpReplFallbackTransport(adapters: inputs.fallbackAdapters),
        state: MeshTransportState(
          label: 'http-repl-fallback',
          meshActive: false,
          shardProxyEndpoint: inputs.shardProxyEndpoint,
          lastAttemptedUnix: now,
        ),
      );
    }

    final client = inputs.shardProxyClient!;
    final reachable = await client.healthCheck();
    if (!reachable) {
      // Don't dispose the client — a future "Refresh transport" tap
      // can re-probe.  We just don't return it as the live transport.
      return (
        transport: HttpReplFallbackTransport(adapters: inputs.fallbackAdapters),
        state: MeshTransportState(
          label: 'http-repl-fallback',
          meshActive: false,
          shardProxyEndpoint: inputs.shardProxyEndpoint,
          lastAttemptedUnix: now,
        ),
      );
    }

    return (
      transport: ShardProxyMeshTransport(
        client: client,
        myCertId: inputs.myCertId,
      ),
      state: MeshTransportState(
        label: 'shard-proxy',
        meshActive: true,
        shardProxyEndpoint: inputs.shardProxyEndpoint,
        lastAttemptedUnix: now,
      ),
    );
  }
}

```
