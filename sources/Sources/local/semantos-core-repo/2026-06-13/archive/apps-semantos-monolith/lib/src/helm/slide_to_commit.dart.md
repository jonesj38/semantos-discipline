---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/slide_to_commit.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.899018+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/slide_to_commit.dart

```dart
// Helm v7 — SlideToCommit widget.
//
// A slide-to-commit gesture track that replaces simple taps for
// irreversible REPL transitions.  The operator drags a thumb rightward;
// when it crosses 75% of the track width the async [onCommit] fires.
//
// Spring animation snaps the thumb back when the gesture is released
// below threshold.  After a successful commit the thumb shows a
// checkmark briefly then resets.  Errors surface as red inline text.

import 'package:flutter/material.dart';

/// A slide-to-commit gesture widget.
///
/// [label]    — text rendered on the left side of the track.
/// [onCommit] — async callback fired when the threshold is crossed.
/// [enabled]  — when false the widget is greyed out and non-interactive.
class SlideToCommit extends StatefulWidget {
  final String label;
  final Future<void> Function() onCommit;
  final bool enabled;

  const SlideToCommit({
    super.key,
    required this.label,
    required this.onCommit,
    this.enabled = true,
  });

  @override
  State<SlideToCommit> createState() => _SlideToCommitState();
}

enum _CommitPhase { idle, dragging, committing, success, error }

class _SlideToCommitState extends State<SlideToCommit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _springCtl;

  double _dragFraction = 0.0;
  _CommitPhase _phase = _CommitPhase.idle;
  String? _errorText;

  static const _kThreshold = 0.75;
  static const _kThumbWidth = 48.0;
  static const _kTrackHeight = 48.0;

  @override
  void initState() {
    super.initState();
    _springCtl = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _springCtl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double trackWidth) {
    if (!widget.enabled) return;
    if (_phase == _CommitPhase.committing || _phase == _CommitPhase.success) {
      return;
    }
    setState(() {
      _phase = _CommitPhase.dragging;
      _errorText = null;
      final maxDx = trackWidth - _kThumbWidth;
      final newFrac =
          (_dragFraction + details.delta.dx / maxDx).clamp(0.0, 1.0);
      _dragFraction = newFrac;
    });
  }

  void _onDragEnd(DragEndDetails details, double trackWidth) {
    if (!widget.enabled) return;
    if (_phase == _CommitPhase.committing || _phase == _CommitPhase.success) {
      return;
    }

    if (_dragFraction >= _kThreshold) {
      _commit();
    } else {
      _snapBack();
    }
  }

  void _snapBack() {
    final startFraction = _dragFraction;
    _springCtl
      ..value = 0.0
      ..animateTo(1.0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut)
      ..addListener(() {
        if (!mounted) return;
        setState(() {
          _dragFraction = Tween<double>(begin: startFraction, end: 0.0)
              .transform(Curves.elasticOut.transform(_springCtl.value));
        });
      });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _phase = _CommitPhase.idle;
        _dragFraction = 0.0;
      });
      _springCtl.removeListener(() {});
    });
  }

  Future<void> _commit() async {
    setState(() {
      _phase = _CommitPhase.committing;
      _dragFraction = 1.0;
    });
    try {
      await widget.onCommit();
      if (!mounted) return;
      setState(() => _phase = _CommitPhase.success);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() {
        _phase = _CommitPhase.idle;
        _dragFraction = 0.0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _CommitPhase.error;
        _errorText = e.toString();
        _dragFraction = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = !widget.enabled ||
        _phase == _CommitPhase.committing ||
        _phase == _CommitPhase.success;
    final trackColor = disabled
        ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
        : cs.surfaceContainerHighest;
    final thumbColor = disabled
        ? cs.onSurface.withValues(alpha: 0.3)
        : cs.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 300.0;
        final maxDx = (trackWidth - _kThumbWidth).clamp(0.0, double.infinity);
        final thumbDx = _dragFraction * maxDx;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onHorizontalDragUpdate:
                  disabled ? null : (d) => _onDragUpdate(d, trackWidth),
              onHorizontalDragEnd:
                  disabled ? null : (d) => _onDragEnd(d, trackWidth),
              child: Container(
                height: _kTrackHeight,
                width: trackWidth,
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(_kTrackHeight / 2),
                ),
                child: Stack(
                  children: [
                    // Fill progress behind thumb.
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: thumbDx + _kThumbWidth / 2,
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(_kTrackHeight / 2),
                        ),
                      ),
                    ),
                    // Label.
                    Positioned(
                      left: _kThumbWidth + 8,
                      top: 0,
                      bottom: 0,
                      right: 8,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: disabled
                                ? cs.onSurface.withValues(alpha: 0.4)
                                : cs.onSurface,
                          ),
                        ),
                      ),
                    ),
                    // Thumb.
                    Positioned(
                      left: thumbDx,
                      top: 0,
                      bottom: 0,
                      child: SizedBox(
                        width: _kThumbWidth,
                        child: Center(
                          child: Container(
                            width: _kThumbWidth - 8,
                            height: _kTrackHeight - 8,
                            decoration: BoxDecoration(
                              color: thumbColor,
                              borderRadius:
                                  BorderRadius.circular((_kTrackHeight - 8) / 2),
                            ),
                            child: Center(
                              child: _thumbIcon(cs),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_phase == _CommitPhase.error && _errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _errorText!,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _thumbIcon(ColorScheme cs) {
    switch (_phase) {
      case _CommitPhase.committing:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
          ),
        );
      case _CommitPhase.success:
        return Icon(Icons.check, color: cs.onPrimary, size: 20);
      case _CommitPhase.error:
        return Icon(Icons.chevron_right, color: cs.onPrimary, size: 20);
      case _CommitPhase.idle:
      case _CommitPhase.dragging:
        return Icon(Icons.chevron_right, color: cs.onPrimary, size: 20);
    }
  }
}

```
