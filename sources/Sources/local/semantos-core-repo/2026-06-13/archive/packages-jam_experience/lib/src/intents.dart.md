---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/src/intents.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.814936+00:00
---

# archive/packages-jam_experience/lib/src/intents.dart

```dart
import 'package:semantos_core/semantos_core.dart';

/// Launch a clip on the next beat boundary. Maps onto the `launch_clip`
/// verb in the jambox manifest.
class LaunchClip extends StructuredIntent {
  final String clipId;
  final String? launchedByPlayer;
  const LaunchClip({required this.clipId, this.launchedByPlayer});
}

/// Stop a clip on the next beat boundary.
class StopClip extends StructuredIntent {
  final String clipId;
  const StopClip({required this.clipId});
}

/// Launch every clip in a scene together. Maps to `launch_scene`.
class LaunchScene extends StructuredIntent {
  final String sceneId;
  const LaunchScene({required this.sceneId});
}

/// Capture the current performance as a take. Maps to `record_take`.
class RecordTake extends StructuredIntent {
  final String? trackId;
  const RecordTake({this.trackId});
}

/// Promote a captured take onto the arrangement timeline.
/// Host-only (matches manifest action's `authoredBy: ["host"]`).
class PromoteTake extends StructuredIntent {
  final String takeId;
  final String? arrangementSlot;
  const PromoteTake({required this.takeId, this.arrangementSlot});
}

/// Move a macro parameter live. Maps to `twist_macro`.
class TwistMacro extends StructuredIntent {
  final String macroId;
  final double value; // 0..1
  const TwistMacro({required this.macroId, required this.value});
}

/// Change the session tempo. Host-only.
class SetTempo extends StructuredIntent {
  final double bpm;
  const SetTempo({required this.bpm});
}

/// Mute a track's audio output.
class MuteTrack extends StructuredIntent {
  final String trackId;
  const MuteTrack({required this.trackId});
}

/// Unmute a previously-muted track.
class UnmuteTrack extends StructuredIntent {
  final String trackId;
  const UnmuteTrack({required this.trackId});
}

```
