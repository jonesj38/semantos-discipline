---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/ratify_tray_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.886164+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/ratify_tray_screen.dart

```dart
// Tier 2P Phase E.4 — RatifyTrayScreen.
//
// Reference: docs/prd/TIER-2P-PHASE-E-AND-F-BRIEFS.md §Phase E.4.
//
// A dedicated screen surfacing all dispatch decisions where
// `requiresRatification == true`, so the operator can see and clear
// pending broadcast/squad approvals in one place.
//
// Reached by tapping the [_RatifyBadge] in the HomeScreen AppBar.
//
// v1 Ratify/Decline buttons are intentionally stubs — the real
// wallet-side ratify flow is a separate post-Tier-2P phase.

import 'dart:async';

import 'package:flutter/material.dart';

import '../repl/attention_service.dart';

/// Dedicated tray screen for all pending dispatch ratifications.
///
/// Subscribes to [AttentionService.pendingRatifications] and renders
/// one card per decision in descending-confidence order.  Pull-to-
/// refresh calls [AttentionService.refresh].
class RatifyTrayScreen extends StatefulWidget {
  final AttentionService attention;

  const RatifyTrayScreen({super.key, required this.attention});

  @override
  State<RatifyTrayScreen> createState() => _RatifyTrayScreenState();
}

class _RatifyTrayScreenState extends State<RatifyTrayScreen> {
  List<OddjobzDispatchDecision> _pending = const [];
  StreamSubscription<List<OddjobzDispatchDecision>>? _sub;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.attention.pendingRatifications.listen((decisions) {
      if (!mounted) return;
      // Sort descending by confidence so the highest-confidence decisions
      // are easiest to scan / act on first.
      final sorted = List<OddjobzDispatchDecision>.from(decisions)
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      setState(() {
        _pending = sorted;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.attention.refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return Scaffold(
      appBar: AppBar(
        title: Text('Ratify Tray — ${pending.length} pending'),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: pending.isEmpty
            ? _EmptyState(refreshing: _refreshing)
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: pending.length,
                itemBuilder: (context, i) =>
                    _PendingDecisionCard(decision: pending[i]),
              ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool refreshing;
  const _EmptyState({required this.refreshing});

  @override
  Widget build(BuildContext context) {
    // Must be scrollable for RefreshIndicator to work even when empty.
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          child: Center(
            child: refreshing
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 56,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nothing waiting — surface is clean.',
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

// ── Decision card ──────────────────────────────────────────────────────────

class _PendingDecisionCard extends StatelessWidget {
  final OddjobzDispatchDecision decision;
  const _PendingDecisionCard({required this.decision});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ref = decision.primaryTarget.ref;
    final refShort = ref.length > 8 ? '${ref.substring(0, 8)}…' : ref;
    final targetSummary =
        '${_targetTypeLabel(decision.primaryTarget.type)} · $refShort';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: lane chip + target summary ──────────────────────
            Row(
              children: [
                _LaneChip(lane: decision.lane),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    targetSummary,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Row 2: confidence bar ───────────────────────────────────
            _ConfidenceBar(confidence: decision.confidence),
            const SizedBox(height: 10),
            // ── Row 3: action buttons ───────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _onDecline(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _onRatify(context),
                  child: const Text('Ratify'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onRatify(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ratify flow coming soon')),
    );
  }

  void _onDecline(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ratify flow coming soon')),
    );
  }
}

// ── Lane chip ─────────────────────────────────────────────────────────────

/// Small Material Chip displaying the dispatch lane with a colour code
/// matching the design in E.1.
///
///   direct    → blue
///   squad     → orange
///   broadcast → red
///   agent     → green
///   self      → grey
class _LaneChip extends StatelessWidget {
  final OddjobzDispatchLane lane;
  const _LaneChip({required this.lane});

  static const Map<OddjobzDispatchLane, ({Color bg, Color fg})> _colors = {
    OddjobzDispatchLane.direct: (
      bg: Color(0xFFBBDEFB),
      fg: Color(0xFF0D47A1),
    ),
    OddjobzDispatchLane.squad: (
      bg: Color(0xFFFFE0B2),
      fg: Color(0xFFE65100),
    ),
    OddjobzDispatchLane.broadcast: (
      bg: Color(0xFFFFCDD2),
      fg: Color(0xFFB71C1C),
    ),
    OddjobzDispatchLane.agent: (
      bg: Color(0xFFC8E6C9),
      fg: Color(0xFF1B5E20),
    ),
    OddjobzDispatchLane.self: (
      bg: Color(0xFFEEEEEE),
      fg: Color(0xFF424242),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final colors = _colors[lane] ??
        (bg: const Color(0xFFEEEEEE), fg: const Color(0xFF424242));
    return Chip(
      label: Text(
        _laneLabel(lane),
        style: TextStyle(fontSize: 11, color: colors.fg),
      ),
      backgroundColor: colors.bg,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      side: BorderSide.none,
    );
  }
}

// ── Confidence bar ────────────────────────────────────────────────────────

/// Linear progress bar coloured by confidence level:
///   < 0.5  → red
///   0.5–0.7 → amber
///   >= 0.7 → green
class _ConfidenceBar extends StatelessWidget {
  final double confidence;
  const _ConfidenceBar({required this.confidence});

  Color _barColor() {
    if (confidence < 0.5) return Colors.red;
    if (confidence < 0.7) return Colors.amber;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final color = _barColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Confidence',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const Spacer(),
            Text(
              '${(confidence * 100).round()}%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: confidence.clamp(0.0, 1.0),
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

String _laneLabel(OddjobzDispatchLane lane) {
  switch (lane) {
    case OddjobzDispatchLane.direct:
      return 'Direct';
    case OddjobzDispatchLane.squad:
      return 'Squad';
    case OddjobzDispatchLane.broadcast:
      return 'Broadcast';
    case OddjobzDispatchLane.agent:
      return 'Agent';
    case OddjobzDispatchLane.self:
      return 'Self';
  }
}

String _targetTypeLabel(OddjobzDispatchTargetType type) {
  switch (type) {
    case OddjobzDispatchTargetType.job:
      return 'Job';
    case OddjobzDispatchTargetType.customer:
      return 'Customer';
    case OddjobzDispatchTargetType.site:
      return 'Site';
    case OddjobzDispatchTargetType.squad:
      return 'Squad';
    case OddjobzDispatchTargetType.agent:
      return 'Agent';
    case OddjobzDispatchTargetType.broadcastChannel:
      return 'Broadcast Channel';
    case OddjobzDispatchTargetType.conversationSession:
      return 'Conversation';
  }
}

```
