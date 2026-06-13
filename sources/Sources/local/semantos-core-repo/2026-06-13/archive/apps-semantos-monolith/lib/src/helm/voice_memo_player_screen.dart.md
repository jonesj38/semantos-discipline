---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/voice_memo_player_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.890466+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/voice_memo_player_screen.dart

```dart
// D-O5m.followup-8 GPS + voice memo adapters — Voice memo player.
//
// Fullscreen modal used by VisitDetailScreen when the operator taps
// a `voice_memo` attachment row.  Streams the bearer-gated blob bytes
// from the brain via the same `/api/v1/attachments/<id>/blob`
// endpoint photos use, and plays them back via a tiny audio player
// surface (play / pause + a scrub bar).
//
// The actual platform audio engine is dependency-injected via the
// [VoicePlaybackAdapter] interface — production wiring uses the
// `audioplayers` package; tests inject a stub.  The adapter is kept
// behind an interface for the same reason the recording adapter is:
// keeps `dart test` runs unblocked + isolates the UI surface from
// the platform plugin.

import 'dart:async';

import 'package:flutter/material.dart';

/// Playback lifecycle states.  The player UI binds to a stream of
/// these to drive the play/pause icon + the scrub bar position.
enum VoicePlaybackState {
  loading,
  playing,
  paused,
  stopped,
  error,
}

/// Position update emitted by [VoicePlaybackAdapter.positionStream].
class VoicePlaybackPosition {
  final Duration position;
  final Duration duration;

  const VoicePlaybackPosition({
    required this.position,
    required this.duration,
  });
}

/// Lightweight abstraction over the platform audio player
/// (`audioplayers` on iOS + Android).  Production wiring adapts the
/// package's `AudioPlayer().setSourceUrl + play + pause + seek` calls
/// into this surface; tests inject a stub.
abstract class VoicePlaybackAdapter {
  Stream<VoicePlaybackState> get stateStream;
  Stream<VoicePlaybackPosition> get positionStream;

  /// Begin playback from the bearer-gated blob URL.  The adapter
  /// fetches the bytes (with the supplied bearer header) and plays
  /// them inline.
  Future<void> play(String blobUrl, {required String bearer});
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}

/// Fullscreen player modal pushed onto the navigator from
/// VisitDetailScreen.  Owns the adapter for its lifetime, plays on
/// mount, disposes on pop.
class VoiceMemoPlayerScreen extends StatefulWidget {
  final String blobUrl;
  final String bearer;
  final String? caption;
  final VoicePlaybackAdapter adapter;

  const VoiceMemoPlayerScreen({
    super.key,
    required this.blobUrl,
    required this.bearer,
    required this.adapter,
    this.caption,
  });

  @override
  State<VoiceMemoPlayerScreen> createState() => _VoiceMemoPlayerScreenState();
}

class _VoiceMemoPlayerScreenState extends State<VoiceMemoPlayerScreen> {
  VoicePlaybackState _state = VoicePlaybackState.loading;
  VoicePlaybackPosition _pos =
      const VoicePlaybackPosition(position: Duration.zero, duration: Duration.zero);
  StreamSubscription<VoicePlaybackState>? _stateSub;
  StreamSubscription<VoicePlaybackPosition>? _posSub;

  @override
  void initState() {
    super.initState();
    _stateSub = widget.adapter.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _posSub = widget.adapter.positionStream.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    // Fire-and-forget the play call; errors surface via the state
    // stream as VoicePlaybackState.error.
    widget.adapter.play(widget.blobUrl, bearer: widget.bearer);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    widget.adapter.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    switch (_state) {
      case VoicePlaybackState.playing:
        await widget.adapter.pause();
        break;
      case VoicePlaybackState.paused:
        await widget.adapter.resume();
        break;
      case VoicePlaybackState.stopped:
      case VoicePlaybackState.error:
        await widget.adapter.play(widget.blobUrl, bearer: widget.bearer);
        break;
      case VoicePlaybackState.loading:
        break;
    }
  }

  IconData get _playIcon {
    switch (_state) {
      case VoicePlaybackState.playing:
        return Icons.pause_circle_filled;
      case VoicePlaybackState.loading:
        return Icons.hourglass_empty;
      case VoicePlaybackState.error:
        return Icons.error_outline;
      case VoicePlaybackState.paused:
      case VoicePlaybackState.stopped:
        return Icons.play_circle_filled;
    }
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total = _pos.duration.inMilliseconds.toDouble();
    final at = _pos.position.inMilliseconds.toDouble().clamp(0.0, total);
    return Scaffold(
      appBar: AppBar(title: const Text('Voice memo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic, size: 96, color: Colors.black54),
            const SizedBox(height: 24),
            if (widget.caption != null && widget.caption!.isNotEmpty) ...[
              Text(widget.caption!,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
            ],
            Slider(
              value: total <= 0 ? 0 : at,
              min: 0,
              max: total <= 0 ? 1 : total,
              onChanged: total <= 0
                  ? null
                  : (v) => widget.adapter
                      .seek(Duration(milliseconds: v.toInt())),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmtDuration(_pos.position)),
                Text(_fmtDuration(_pos.duration)),
              ],
            ),
            const SizedBox(height: 16),
            IconButton(
              icon: Icon(_playIcon, size: 64),
              onPressed: _state == VoicePlaybackState.loading
                  ? null
                  : _togglePlay,
            ),
            if (_state == VoicePlaybackState.error)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Playback failed.',
                    style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}

```
