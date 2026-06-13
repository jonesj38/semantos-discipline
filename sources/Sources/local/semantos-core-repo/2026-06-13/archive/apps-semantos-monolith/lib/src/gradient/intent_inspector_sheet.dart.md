---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/gradient/intent_inspector_sheet.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.875464+00:00
---

# archive/apps-semantos-monolith/lib/src/gradient/intent_inspector_sheet.dart

```dart
// Wave 9 PWA surface — modal that renders the most recent intent
// cascade. Mirrors `tools/intent-trace/src/render.ts::renderCascade`
// but in Flutter so the user sees it WITHOUT leaving the PWA.
//
// Triggered from `home_screen.dart`'s AppBar (a small "inspect" icon).
// Pull this sheet open after any action — chat send, quote approve,
// invoice issue — and you see exactly which stages fired, in what
// order, with timings and the rejection reason when the kernel said
// no. Round-trip inspectability at the user surface.

import 'dart:async';

import 'package:flutter/material.dart';

import 'dart_pipeline.dart';
import 'intent_trace_service.dart';

class IntentInspectorSheet extends StatefulWidget {
  const IntentInspectorSheet({super.key, required this.trace});

  final IntentTraceService trace;

  static Future<void> show(BuildContext context, IntentTraceService trace) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtl) => IntentInspectorSheet(trace: trace),
      ),
    );
  }

  @override
  State<IntentInspectorSheet> createState() => _IntentInspectorSheetState();
}

class _IntentInspectorSheetState extends State<IntentInspectorSheet> {
  String? _selectedCorrelationId;

  @override
  void initState() {
    super.initState();
    _selectedCorrelationId = widget.trace.latest?.correlationId;
    widget.trace.addListener(_onTraceUpdate);
  }

  @override
  void dispose() {
    widget.trace.removeListener(_onTraceUpdate);
    super.dispose();
  }

  void _onTraceUpdate() {
    if (!mounted) return;
    setState(() {
      // Auto-follow when no group has been pinned yet, or when the
      // selected group has been evicted.
      final groups = widget.trace.groups;
      _selectedCorrelationId ??= groups.isEmpty
          ? null
          : groups.first.correlationId;
      if (_selectedCorrelationId != null &&
          widget.trace.groupFor(_selectedCorrelationId!) == null) {
        _selectedCorrelationId = groups.isEmpty
            ? null
            : groups.first.correlationId;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = widget.trace.groups;
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: cs.outline, size: 48),
            const SizedBox(height: 12),
            Text(
              'No intent traces yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Take an action — send a chat message, approve a quote, or '
              'issue an invoice — and the cascade appears here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    final selected = _selectedCorrelationId != null
        ? widget.trace.groupFor(_selectedCorrelationId!)
        : groups.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                'Intent inspector',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Clear trace history',
                onPressed: () {
                  widget.trace.clear();
                  setState(() => _selectedCorrelationId = null);
                },
              ),
            ],
          ),
        ),
        // Group picker — chip row for the last few turns.
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final g = groups[i];
              final isSel = g.correlationId == selected?.correlationId;
              return ChoiceChip(
                label: Text(_chipLabel(g)),
                selected: isSel,
                onSelected: (_) =>
                    setState(() => _selectedCorrelationId = g.correlationId),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: selected == null
              ? const SizedBox.shrink()
              : _CascadeView(group: selected),
        ),
      ],
    );
  }

  String _chipLabel(TraceGroup g) {
    final stub = g.correlationId.length > 8
        ? g.correlationId.substring(0, 8)
        : g.correlationId;
    final marker = g.isRejected
        ? '⨯'
        : g.isCompleted
            ? '✓'
            : '…';
    return '$marker $stub';
  }
}

class _CascadeView extends StatelessWidget {
  const _CascadeView({required this.group});

  final TraceGroup group;

  /// A group is "in-flight" when its tail event is a marker we expect
  /// to be followed by another event (e.g. `sir_extracting`, `intent_produced`
  /// while we're still inside processText). Used to drive the live
  /// elapsed-time ticker on the tail row.
  bool get _isInFlight {
    if (group.isCompleted || group.isRejected) return false;
    if (group.events.isEmpty) return false;
    const inFlightStages = <String>{
      'intent_produced',
      'sir_extracting',
      'sir_built',
      'sir_lowered',
      'ir_emitted',
      'script_executed',
      'cell_written',
    };
    return inFlightStages.contains(group.events.last.stage);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tailIndex = group.events.length - 1;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _Header(group: group),
        const SizedBox(height: 12),
        for (int i = 0; i < group.events.length; i++)
          _StageRow(
            event: group.events[i],
            // Live-tick the tail row when the cascade hasn't terminated.
            liveSince: (i == tailIndex && _isInFlight)
                ? group.lastEventAt
                : null,
          ),
        if (group.cellId != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('cell',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.outline,
                        )),
                const SizedBox(height: 4),
                SelectableText(
                  group.cellId!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.group});

  final TraceGroup group;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = group.isRejected
        ? cs.error
        : group.isCompleted
            ? cs.primary
            : cs.outline;
    final marker = group.isRejected
        ? Icons.cancel_outlined
        : group.isCompleted
            ? Icons.check_circle_outline
            : Icons.hourglass_empty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(marker, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            group.correlationId,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          '${group.events.length} stages · '
          '${group.totalDurationMs.toStringAsFixed(1)} ms',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _StageRow extends StatefulWidget {
  const _StageRow({required this.event, this.liveSince});

  final PipelineStageEvent event;

  /// When non-null, the row is the *tail* of an in-flight group; the
  /// duration column ticks up from this timestamp instead of rendering
  /// the captured (and frozen-at-zero) `event.durationMs`. The ticker
  /// stops when this widget rebuilds with `liveSince = null` (a new
  /// event has landed and this row is no longer the tail).
  final DateTime? liveSince;

  @override
  State<_StageRow> createState() => _StageRowState();
}

class _StageRowState extends State<_StageRow> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _restartTicker();
  }

  @override
  void didUpdateWidget(covariant _StageRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveSince != widget.liveSince) _restartTicker();
  }

  void _restartTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (widget.liveSince == null) return;
    // 500ms granularity is enough for "is it still ticking?" without
    // wasting frames.
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _renderedDuration() {
    final live = widget.liveSince;
    if (live != null) {
      final elapsed = DateTime.now().difference(live).inMilliseconds;
      return '${elapsed.toStringAsFixed(0)} ms · live';
    }
    return '${widget.event.durationMs.toStringAsFixed(1)} ms';
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final cs = Theme.of(context).colorScheme;
    final isReject = event.stage == 'intent_rejected';
    final color = isReject ? cs.error : cs.onSurface;
    final summary = _summary(event);
    final detail = _detailLines(event);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: 10),
                decoration: BoxDecoration(
                  color: widget.liveSince != null ? cs.primary : color,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  event.stage,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
              Text(
                _renderedDuration(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: widget.liveSince != null
                          ? cs.primary
                          : cs.outline,
                    ),
              ),
            ],
          ),
          if (summary != null)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 2),
              child: Text(
                summary,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in detail)
                    Text(
                      line,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            color: cs.outline,
                          ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// One-line headline for the row — the stage's most-asked-about field.
  String? _summary(PipelineStageEvent event) {
    switch (event.stage) {
      case 'sir_built':
        final tc = event.data['trustClass'];
        final cc = event.data['constraintCount'];
        return 'trustClass=$tc · constraints=$cc';
      case 'sir_lowered':
        final bc = event.data['bindingCount'];
        return 'bindings=$bc';
      case 'ir_emitted':
        final bl = event.data['byteLength'];
        return 'byteLength=$bl';
      case 'script_executed':
        final ok = event.data['kernelOk'];
        final op = event.data['opcount'];
        final gas = event.data['gasUsed'];
        return 'ok=$ok · opcount=$op · gas=$gas';
      case 'cell_written':
        final cid = event.data['cellId'];
        return 'cell=$cid';
      case 'intent_rejected':
        final stage = event.data['stage'];
        final code = event.data['code'];
        if (stage == 'producer') {
          // Wave 9 PWA — TextIntentService synthesises producer-stage
          // rejections (extractor_unavailable, sir_refused, etc.) so
          // the user sees WHY their typed input never reached the
          // kernel.
          return 'rejected before pipeline · $code';
        }
        return 'rejected at $stage · $code';
      case 'intent_completed':
        return 'ok';
      case 'reducer_pass_completed':
        final pass = event.data['pass'];
        final conf = event.data['confidence'];
        return 'pass=$pass · conf=${(conf is num) ? conf.toStringAsFixed(2) : conf}';
      case 'intent_produced':
        final digest = event.data['rawInputDigest'];
        return 'digest=$digest';
      case 'sir_extracting':
        final n = event.data['transcriptLength'];
        return 'extractor awaiting Anthropic · transcript=$n chars';
      case 'sir_extracted':
        final outcome = event.data['outcome'];
        return 'outcome=$outcome';
      case 'entity_resolved':
        // Wave 9 follow-up — producer-side resolver bound the intent
        // to a specific job/customer before cell mint.
        final jobId = event.data['jobId'];
        final score = event.data['score'];
        final runner = event.data['runnerUpScore'];
        return 'job=$jobId · score=$score (runner=$runner)';
      case 'entity_unresolved':
        final code = event.data['code'];
        return 'no entity bound · $code';
    }
    return null;
  }

  /// Extra lines surfaced only for events that warrant a second look —
  /// alternative candidates from RM-092, kernel error message, etc.
  List<String> _detailLines(PipelineStageEvent event) {
    final out = <String>[];
    if (event.stage == 'intent_rejected') {
      final msg = event.data['message'];
      if (msg is String && msg.isNotEmpty) {
        // Multi-line messages (e.g. pipeline stack traces from
        // TextIntentService.pipeline_threw) get split so each frame
        // renders on its own line. First line is prefixed `reason:`
        // for grep continuity with the single-line case.
        final lines = msg.split('\n');
        out.add('reason: ${lines.first}');
        for (final line in lines.skip(1)) {
          if (line.trim().isEmpty) continue;
          out.add('  $line');
        }
      }
    }
    if (event.stage == 'entity_resolved' ||
        event.stage == 'entity_unresolved') {
      final reason = event.data['reason'];
      if (reason is String && reason.isNotEmpty) {
        out.add('reason: $reason');
      }
      if (event.stage == 'entity_resolved') {
        final cust = event.data['customerId'];
        if (cust is String && cust.isNotEmpty) {
          out.add('customerId=$cust');
        }
      }
    }
    if (event.stage == 'reducer_pass_completed') {
      final alt = event.data['alternativesCount'];
      if (alt is num && alt > 0) {
        out.add('+ $alt alternative${alt == 1 ? '' : 's'} considered');
      }
      final flags = event.data['flags'];
      if (flags is List && flags.isNotEmpty) {
        for (final f in flags) {
          out.add('⚑ $f');
        }
      }
    }
    return out;
  }
}

```
