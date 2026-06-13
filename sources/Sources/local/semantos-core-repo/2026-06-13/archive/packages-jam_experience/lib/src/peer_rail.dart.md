---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/src/peer_rail.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.815486+00:00
---

# archive/packages-jam_experience/lib/src/peer_rail.dart

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// PeerRail — vertical strip of peer avatars with phase-locked pulse
/// rings. Migrated from
/// `apps/world-apps/jam-room-mobile/lib/src/jam/peer_rail.dart`.
class PeerRail extends StatelessWidget {
  final List<PeerInfo> peers;
  final double bpm;

  const PeerRail({super.key, required this.peers, required this.bpm});

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: peers
            .map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PeerAvatar(peer: p, bpm: bpm),
                ))
            .toList(),
      ),
    );
  }
}

class PeerInfo {
  final String id;
  final String initials;
  final Color color;
  final double drift; // -0.5..0.5 relative phase offset

  const PeerInfo({
    required this.id,
    required this.initials,
    required this.color,
    this.drift = 0,
  });
}

class _PeerAvatar extends StatefulWidget {
  final PeerInfo peer;
  final double bpm;

  const _PeerAvatar({required this.peer, required this.bpm});

  @override
  State<_PeerAvatar> createState() => _PeerAvatarState();
}

class _PeerAvatarState extends State<_PeerAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    final beatMs = (60000 / widget.bpm).round();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: beatMs),
    )..repeat();
    // Offset by drift
    _ctrl.value = (widget.peer.drift + 0.5) % 1.0;
  }

  @override
  void didUpdateWidget(_PeerAvatar old) {
    super.didUpdateWidget(old);
    if (old.bpm != widget.bpm) {
      final beatMs = (60000 / widget.bpm).round();
      _ctrl.duration = Duration(milliseconds: beatMs);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final pulse = math.sin(_ctrl.value * math.pi * 2) * 0.5 + 0.5;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulse ring
            Container(
              width: 40 + pulse * 6,
              height: 40 + pulse * 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.peer.color.withValues(alpha: 0.2 + pulse * 0.2),
                  width: 1,
                ),
              ),
            ),
            // Avatar circle
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.peer.color.withValues(alpha: 0.18),
                border: Border.all(
                  color: widget.peer.color.withValues(alpha: 0.5),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.peer.initials,
                style: TextStyle(
                  fontFamily: 'GeistMono',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: widget.peer.color,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}


```
