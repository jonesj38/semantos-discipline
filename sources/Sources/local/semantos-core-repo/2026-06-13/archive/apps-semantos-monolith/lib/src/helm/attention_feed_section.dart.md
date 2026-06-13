---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/attention_feed_section.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.899361+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/attention_feed_section.dart

```dart
// Tier 2P Phase D.3 — AttentionFeedSection.
//
// A compact "Surface" section that renders the top-10 Pask attention signals
// at the top of HomeNode, above the existing stage-grouped job sections.
//
// Signal kinds:
//   dispatch — lane chip + confidence bar + optional "Pending ratification" tag
//   message  — channel icon + customer name + relative timestamp + text snippet
//   job      — site address + customer name + due date with urgency colour
//
// Tapping any card navigates to JobDetailScreen for the underlying job via the
// signal's `ref` field (which holds the job id for all three kinds when
// derivable — dispatch and message signals carry the job cellId in their
// primaryTarget.ref / raw map; job signals use ref directly).
//
// Pull-to-refresh on the section calls AttentionService.refresh().
// "See all" link at the bottom is a v1 no-op (Coming soon).
// Empty stream → section hides entirely (SizedBox.shrink).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../repl/attention_service.dart';
import '../repl/conversation_turns_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/repl_client.dart';
import 'job_detail_screen.dart';

// ── Constants ────────────────────────────────────────────────────────────────

/// Maximum signals to display in the surface section.
const int _kMaxSignals = 10;

/// Approximate card height in logical pixels; keeps the section compact.
const double _kCardHeight = 80.0;

// ── Lane colours ─────────────────────────────────────────────────────────────

Color _laneBg(OddjobzDispatchLane lane) {
  switch (lane) {
    case OddjobzDispatchLane.direct:
      return Colors.blue.shade100;
    case OddjobzDispatchLane.squad:
      return Colors.orange.shade100;
    case OddjobzDispatchLane.broadcast:
      return Colors.red.shade100;
    case OddjobzDispatchLane.agent:
      return Colors.green.shade100;
    case OddjobzDispatchLane.self:
      return Colors.grey.shade200;
  }
}

Color _laneFg(OddjobzDispatchLane lane) {
  switch (lane) {
    case OddjobzDispatchLane.direct:
      return Colors.blue.shade900;
    case OddjobzDispatchLane.squad:
      return Colors.orange.shade900;
    case OddjobzDispatchLane.broadcast:
      return Colors.red.shade900;
    case OddjobzDispatchLane.agent:
      return Colors.green.shade900;
    case OddjobzDispatchLane.self:
      return Colors.grey.shade800;
  }
}

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

// ── Channel icons ─────────────────────────────────────────────────────────────

IconData _channelIcon(String channel) {
  final c = channel.toLowerCase();
  if (c.contains('gmail') || c.contains('email')) {
    return Icons.email_outlined;
  }
  if (c.contains('meta') || c.contains('messenger') || c.contains('instagram')) {
    return Icons.chat_bubble_outline;
  }
  if (c.contains('voice')) {
    return Icons.mic_outlined;
  }
  return Icons.message_outlined;
}

// ── Relative timestamp ────────────────────────────────────────────────────────

String _relativeTime(int timestampMs) {
  if (timestampMs == 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 60) return '${math.max(0, diff.inMinutes)}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays}d';
}

// ── Urgency colour for job due-date ──────────────────────────────────────────

Color _urgencyColour(String? dueDateRaw) {
  if (dueDateRaw == null || dueDateRaw.isEmpty) return Colors.grey;
  try {
    final due = DateTime.parse(dueDateRaw);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final dueDate = DateTime(due.year, due.month, due.day);
    final diff = dueDate.difference(todayDate).inDays;
    if (diff <= 0) return Colors.red;
    if (diff <= 1) return Colors.amber;
    return Colors.grey;
  } catch (_) {
    return Colors.grey;
  }
}

// ── Public widget ─────────────────────────────────────────────────────────────

/// Top section of HomeNode surfacing the Pask attention pipeline signals.
///
/// Subscribe to [attention.signals]; renders top-[_kMaxSignals] by score desc.
/// Returns [SizedBox.shrink] when the stream has never emitted or emits empty.
class AttentionFeedSection extends StatefulWidget {
  final AttentionService attention;
  final JobsRepository jobs;

  /// Optional — when supplied, the Thread button appears in JobDetailScreen
  /// so the operator can see the canonical conversation from the DO tab.
  final ConversationTurnsRepository? turnsRepository;
  final ReplClient? replClient;

  const AttentionFeedSection({
    super.key,
    required this.attention,
    required this.jobs,
    this.turnsRepository,
    this.replClient,
  });

  @override
  State<AttentionFeedSection> createState() => _AttentionFeedSectionState();
}

class _AttentionFeedSectionState extends State<AttentionFeedSection> {
  StreamSubscription<List<OddjobzAttentionSignal>>? _sub;
  List<OddjobzAttentionSignal> _signals = const [];
  bool _everReceived = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.attention.signals.listen(_onSignals);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onSignals(List<OddjobzAttentionSignal> signals) {
    if (!mounted) return;
    final sorted = [...signals]..sort((a, b) => b.score.compareTo(a.score));
    setState(() {
      _everReceived = true;
      _signals =
          sorted.length > _kMaxSignals ? sorted.sublist(0, _kMaxSignals) : sorted;
    });
  }

  Future<void> _onRefresh() => widget.attention.refresh();

  void _onCardTap(OddjobzAttentionSignal signal) {
    // Resolve job id from the signal.  For job-kind signals ref IS the job id.
    // For dispatch/message kinds the raw map may carry primaryTarget.ref.
    String jobId = signal.ref;
    if (signal.kind != OddjobzAttentionKind.job) {
      final pt = signal.raw['primaryTarget'];
      if (pt is Map && pt['ref'] is String && (pt['ref'] as String).isNotEmpty) {
        jobId = pt['ref'] as String;
      }
    }
    if (jobId.isEmpty) return;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobDetailScreen(
        jobs: widget.jobs,
        jobId: jobId,
        initial: _syntheticJob(signal, jobId),
        onUnauthorised: () async {},
        turnsRepository: widget.turnsRepository,
        replClient: widget.replClient,
      ),
    ));
  }

  /// Build a minimal synthetic Job so JobDetailScreen doesn't need a
  /// network round-trip to render while it fetches the real record.
  Job _syntheticJob(OddjobzAttentionSignal signal, String jobId) {
    return Job(
      id: jobId,
      customerName: signal.summary,
      state: 'lead',
      scheduledAt: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_everReceived || _signals.isEmpty) return const SizedBox.shrink();

    // ListView makes the section independently pull-to-refresh-able
    // when rendered in isolation (test context); when embedded inside
    // HomeNode's parent ListView the NeverScrollableScrollPhysics passed
    // by the parent ensures it doesn't fight for gesture ownership.
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView(
        // Shrink-wrap so the section takes only the space its cards need
        // when embedded in HomeNode's outer ListView.
        shrinkWrap: true,
        // Do not intercept the outer ListView's scroll events.
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _SurfaceHeader(count: _signals.length),
          ..._signals.map(
            (s) => _SignalCard(
              signal: s,
              onTap: () => _onCardTap(s),
            ),
          ),
          _SeeAllLink(total: _signals.length),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SurfaceHeader extends StatelessWidget {
  final int count;
  const _SurfaceHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          // Attention indicator dot
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Surface',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ── "See all" link ────────────────────────────────────────────────────────────

class _SeeAllLink extends StatelessWidget {
  final int total;
  const _SeeAllLink({required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GestureDetector(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Full surface feed — coming soon.')),
          );
        },
        child: Text(
          'See all ($total)',
          style: TextStyle(
            fontSize: 12,
            color: cs.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Signal card dispatcher ────────────────────────────────────────────────────

class _SignalCard extends StatelessWidget {
  final OddjobzAttentionSignal signal;
  final VoidCallback onTap;
  const _SignalCard({required this.signal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    switch (signal.kind) {
      case OddjobzAttentionKind.dispatch:
        return _DispatchCard(signal: signal, onTap: onTap);
      case OddjobzAttentionKind.message:
        return _MessageCard(signal: signal, onTap: onTap);
      case OddjobzAttentionKind.job:
        return _JobCard(signal: signal, onTap: onTap);
    }
  }
}

// ── Dispatch card ─────────────────────────────────────────────────────────────

class _DispatchCard extends StatelessWidget {
  final OddjobzAttentionSignal signal;
  final VoidCallback onTap;
  const _DispatchCard({required this.signal, required this.onTap});

  OddjobzDispatchDecision? _decode() {
    try {
      return OddjobzDispatchDecision.fromJson(
          Map<String, dynamic>.from(signal.raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dispatch = _decode();
    final lane = dispatch?.lane ?? OddjobzDispatchLane.self;
    final confidence = dispatch?.confidence ?? signal.score;
    final requiresRatification = dispatch?.requiresRatification ?? false;

    // Confidence bar colour
    Color barColour;
    if (confidence >= 0.7) {
      barColour = Colors.green;
    } else if (confidence >= 0.5) {
      barColour = Colors.amber;
    } else {
      barColour = Colors.red;
    }

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _kCardHeight,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Lane chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _laneBg(lane),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _laneLabel(lane),
                          style: TextStyle(
                            fontSize: 10,
                            color: _laneFg(lane),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (requiresRatification) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Pending ratification',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    signal.summary.isNotEmpty
                        ? signal.summary
                        : 'Dispatch signal',
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Confidence bar at bottom edge
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  value: confidence.clamp(0.0, 1.0),
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(barColour),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Message card ──────────────────────────────────────────────────────────────

class _MessageCard extends StatelessWidget {
  final OddjobzAttentionSignal signal;
  final VoidCallback onTap;
  const _MessageCard({required this.signal, required this.onTap});

  OddjobzMessagePatch? _decode() {
    try {
      return OddjobzMessagePatch.fromJson(
          Map<String, dynamic>.from(signal.raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final msg = _decode();
    final channel = msg?.channel ?? '';
    final timestamp = msg?.timestamp ?? 0;
    final text = msg?.text ?? signal.summary;
    final snippet = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    final rel = _relativeTime(timestamp);

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _kCardHeight,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _channelIcon(channel),
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      signal.summary.isNotEmpty
                          ? signal.summary
                          : 'Message',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (rel.isNotEmpty)
                    Text(
                      rel,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                snippet,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Job card ──────────────────────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  final OddjobzAttentionSignal signal;
  final VoidCallback onTap;
  const _JobCard({required this.signal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Try to pull structured fields from raw if present.
    final raw = signal.raw;
    final customerName = raw['customer_name'] is String
        ? raw['customer_name'] as String
        : '';
    final dueDateRaw = raw['dueDate'] is String ? raw['dueDate'] as String : null;
    final urgency = _urgencyColour(dueDateRaw);

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _kCardHeight,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      // Site address from summary; fall back to customer name.
                      signal.summary.isNotEmpty
                          ? signal.summary
                          : customerName.isNotEmpty
                              ? customerName
                              : 'Job',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Urgency dot
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: urgency,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (customerName.isNotEmpty) ...[
                    Icon(Icons.person_outline,
                        size: 12, color: cs.onSurfaceVariant),
                    const SizedBox(width: 2),
                    Text(
                      customerName,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (dueDateRaw != null) ...[
                    Icon(Icons.calendar_today_outlined,
                        size: 12, color: urgency),
                    const SizedBox(width: 2),
                    Text(
                      dueDateRaw,
                      style: TextStyle(fontSize: 12, color: urgency),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

```
