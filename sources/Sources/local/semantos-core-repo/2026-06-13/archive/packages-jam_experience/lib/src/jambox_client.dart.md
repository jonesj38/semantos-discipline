---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/src/jambox_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.812967+00:00
---

# archive/packages-jam_experience/lib/src/jambox_client.dart

```dart
import 'package:semantos_core/semantos_core.dart';

/// Typed Dart facade over [VerbDispatchClient] for the jambox extension's
/// declared action verbs.
///
/// Composes on top of the generic primitive: callers say
/// `await client.launchClip("clip-42")` and the brain receives a
/// `verb.dispatch({extensionId: "jambox", verb: "launch_clip", params:
/// {clipId: "clip-42"}})` JSON-RPC call. The transport binding (WSS
/// today, HTTP later) is injected — this class itself stays transport-
/// agnostic.
///
/// Method names match the verbs declared in `assets/manifest.json` and
/// the action verb wrappers in `intents.dart`; payload shapes match the
/// brain-side walker contracts in `runtime/semantos-brain/src/jambox_walkers.zig`.
class JamboxClient {
  final VerbDispatchClient _dispatch;

  const JamboxClient(this._dispatch);

  /// Extension id this client targets. Matches the manifest.
  static const String extensionId = 'jambox';

  /// Queue a clip to launch on the next beat boundary.
  ///
  /// Brain walker today: validates `clipId`, returns
  /// `{status: "queued", clipId, queuedAt, ...}`. Phase 2: mints
  /// a `jam.intent.launch_clip.v1` cell + bumps the jam.clip cell state.
  Future<LaunchClipAck> launchClip(
    String clipId, {
    String? launchedByPlayer,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'launch_clip',
      params: {
        'clipId': clipId,
        if (launchedByPlayer != null) 'launchedByPlayer': launchedByPlayer,
      },
    );
    return LaunchClipAck.fromJson(result);
  }

  /// Capture the current performance as a take.
  ///
  /// [trackId] null = capture all tracks; matches the walker's default.
  Future<RecordTakeAck> recordTake({String? trackId}) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'record_take',
      params: trackId != null ? {'trackId': trackId} : null,
    );
    return RecordTakeAck.fromJson(result);
  }

  // Convenience wrappers for the remaining manifest verbs land as their
  // walkers come online on the brain. Until then they would 404
  // (walker_not_found) — preferable to expose them once they have a
  // server-side handler rather than ship typed Dart wrappers that all
  // failure.
}

/// Result of [JamboxClient.launchClip]. Mirrors the walker's return JSON.
class LaunchClipAck {
  final String status;
  final String clipId;
  final String? launchedByPlayer;
  final int queuedAt;
  final String note;

  const LaunchClipAck({
    required this.status,
    required this.clipId,
    required this.queuedAt,
    required this.note,
    this.launchedByPlayer,
  });

  factory LaunchClipAck.fromJson(Map<String, dynamic> json) {
    return LaunchClipAck(
      status: (json['status'] as String?) ?? 'unknown',
      clipId: (json['clipId'] as String?) ?? '',
      launchedByPlayer: json['launchedByPlayer'] as String?,
      queuedAt: (json['queuedAt'] as int?) ?? 0,
      note: (json['note'] as String?) ?? '',
    );
  }
}

/// Result of [JamboxClient.recordTake]. Mirrors the walker's return JSON.
class RecordTakeAck {
  final String status;
  final String? trackId;
  final int capturedAt;
  final String note;

  const RecordTakeAck({
    required this.status,
    required this.capturedAt,
    required this.note,
    this.trackId,
  });

  factory RecordTakeAck.fromJson(Map<String, dynamic> json) {
    return RecordTakeAck(
      status: (json['status'] as String?) ?? 'unknown',
      trackId: json['trackId'] as String?,
      capturedAt: (json['capturedAt'] as int?) ?? 0,
      note: (json['note'] as String?) ?? '',
    );
  }
}

```
