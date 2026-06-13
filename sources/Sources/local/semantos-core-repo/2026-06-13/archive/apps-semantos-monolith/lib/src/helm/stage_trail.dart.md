---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/stage_trail.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.896919+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/stage_trail.dart

```dart
// Helm v7 — StageTrail widget.
//
// Renders the canonical §O4 Job FSM as a compact or labeled horizontal
// trail of dots + connecting lines.  Compact mode (dots only) is used
// on list-row cards; full mode (dots + labels) is used on header rows
// where there is more vertical space.

import 'package:flutter/material.dart';

/// Ordered stage labels — left to right.
const _kStageKeys = [
  'lead',
  'quoted',
  'scheduled',
  'in_progress',
  'completed',
  'invoiced',
  'paid',
];

/// Short display labels matching the stage order above.
const _kStageLabels = [
  'lead',
  'quote',
  'sched',
  'on-site',
  'done',
  'invoiced',
  'paid',
];

/// A horizontal stage trail for the §O4 job FSM.
///
/// [currentState] — the job's current FSM state string.  Unknown
/// states fall back to showing no dot highlighted.
///
/// [compact] — when true, renders dots + connectors without text
/// labels (fits in a single-row list tile).  When false, renders dots
/// + connectors + labels below each dot.
class StageTrail extends StatelessWidget {
  final String currentState;
  final bool compact;

  const StageTrail({
    super.key,
    required this.currentState,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentIdx = _kStageKeys.indexOf(currentState);

    if (compact) {
      return SizedBox(
        height: 12,
        child: _TrailPainter(
          currentIdx: currentIdx,
          primaryColor: cs.primary,
          outlineColor: cs.outline,
          compact: true,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 12,
          child: _TrailPainter(
            currentIdx: currentIdx,
            primaryColor: cs.primary,
            outlineColor: cs.outline,
            compact: false,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(_kStageKeys.length, (i) {
            final textColor = i == currentIdx
                ? cs.primary
                : i < currentIdx
                    ? cs.primary.withValues(alpha: 0.5)
                    : cs.outline.withValues(alpha: 0.4);
            return Expanded(
              child: Text(
                _kStageLabels[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  color: textColor,
                  fontWeight: i == currentIdx
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Custom painter that draws the trail purely in canvas so it scales to
/// any width without relying on Row/Expanded fractional-width math.
class _TrailPainter extends StatelessWidget {
  final int currentIdx;
  final Color primaryColor;
  final Color outlineColor;
  final bool compact;

  const _TrailPainter({
    required this.currentIdx,
    required this.primaryColor,
    required this.outlineColor,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StageTrailCustomPainter(
        currentIdx: currentIdx,
        primaryColor: primaryColor,
        outlineColor: outlineColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _StageTrailCustomPainter extends CustomPainter {
  final int currentIdx;
  final Color primaryColor;
  final Color outlineColor;

  const _StageTrailCustomPainter({
    required this.currentIdx,
    required this.primaryColor,
    required this.outlineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = _kStageKeys.length;
    final centerY = size.height / 2;
    final step = size.width / (n - 1);

    // Draw connectors first (behind dots).
    for (var i = 0; i < n - 1; i++) {
      final x1 = i * step;
      final x2 = (i + 1) * step;
      final isPast = i < currentIdx;
      final lineColor = isPast
          ? primaryColor.withValues(alpha: 0.35)
          : outlineColor.withValues(alpha: 0.18);
      canvas.drawLine(
        Offset(x1, centerY),
        Offset(x2, centerY),
        Paint()
          ..color = lineColor
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // Draw dots on top.
    for (var i = 0; i < n; i++) {
      final cx = i * step;
      if (i == currentIdx) {
        // Current — filled, larger, primary.
        canvas.drawCircle(
          Offset(cx, centerY),
          4.0,
          Paint()..color = primaryColor,
        );
      } else if (i < currentIdx) {
        // Past — filled, slightly smaller, dim primary.
        canvas.drawCircle(
          Offset(cx, centerY),
          3.0,
          Paint()..color = primaryColor.withValues(alpha: 0.4),
        );
      } else {
        // Future — hollow, very dim.
        final dimOutline = outlineColor.withValues(alpha: 0.25);
        canvas.drawCircle(
          Offset(cx, centerY),
          3.0,
          Paint()
            ..color = dimOutline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StageTrailCustomPainter old) =>
      old.currentIdx != currentIdx ||
      old.primaryColor != primaryColor ||
      old.outlineColor != outlineColor;
}

```
