---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/field_job_detail_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.465353+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/field_job_detail_screen.dart

```dart
import 'package:flutter/material.dart';

import 'field_job_detail_repository.dart';
import 'oddjobz_rpc.dart';
import 'package:oddjobz_experience/src/operator/oddjobz_visuals.dart';

/// Job detail — the operator's per-job surface: metadata, the FSM StageTrail
/// (pipeline with the current state + a one-tap advance), and the per-job
/// conversation thread. Everything reads/writes via `repl.eval` over the
/// unified channel (find job / advance verbs / find turns).
class FieldJobDetailScreen extends StatefulWidget {
  const FieldJobDetailScreen({
    super.key,
    required this.rpc,
    required this.jobId,
    this.initialTitle,
  });

  final OddjobzRpc rpc;
  final String jobId;

  /// Customer name to show in the AppBar before the load completes.
  final String? initialTitle;

  @override
  State<FieldJobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<FieldJobDetailScreen> {
  late final JobDetailRepository _repo = JobDetailRepository(widget.rpc);
  late Future<JobDetail> _jobFuture;
  late Future<TurnsResult> _turnsFuture;
  bool _transitioning = false;

  @override
  void initState() {
    super.initState();
    _jobFuture = _repo.load(widget.jobId);
    _turnsFuture = _repo.turns(widget.jobId);
  }

  void _reload() {
    setState(() {
      _jobFuture = _repo.load(widget.jobId);
      _turnsFuture = _repo.turns(widget.jobId);
    });
  }

  Future<void> _advance(JobFsmAction action, JobDetail job) async {
    final command = await _commandFromActionSheet(action, job);
    if (command == null || !mounted) return;
    setState(() => _transitioning = true);
    String msg;
    try {
      msg = await _repo.transitionCommand(command);
    } catch (e) {
      msg = 'Failed: $e';
    }
    if (!mounted) return;
    setState(() => _transitioning = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
    _reload();
  }

  Future<String?> _commandFromActionSheet(
    JobFsmAction action,
    JobDetail job,
  ) async {
    switch (action.sheet) {
      case JobActionSheetKind.none:
        return action.commandFor(job.id);
      case JobActionSheetKind.visitScheduler:
        final values = await _showTemplateSheet(
          title: action.toState == 'scheduled'
              ? 'Schedule work'
              : 'Visit scheduler',
          icon: Icons.event_outlined,
          intro:
              'Pick or confirm the visit slot before `${action.commandFor(job.id)}`.',
          fields: const [
            ('Date / time', 'Today 2:00 PM'),
            ('Duration', '60–90 min'),
            ('Crew / hat', 'operator / service'),
          ],
          confirm: action.label,
        );
        if (values == null) return null;
        if (action.toState == 'scheduled') {
          final when = values.first.trim();
          return when.isEmpty
              ? action.commandFor(job.id)
              : 'schedule job ${job.id} $when';
        }
        return action.commandFor(job.id);
      case JobActionSheetKind.quoteTemplate:
        final values = await _showTemplateSheet(
          title: 'Quote template',
          icon: Icons.request_quote_outlined,
          intro:
              'Review the quote draft before `${action.commandFor(job.id)}`.',
          fields: const [
            ('Scope', 'Seed from ROM / visit notes'),
            ('Line items', 'Materials + labour + variance'),
            ('Customer message', 'Ready to present'),
          ],
          confirm: action.label,
        );
        return values == null ? null : action.commandFor(job.id);
      case JobActionSheetKind.invoiceTemplate:
        final values = await _showTemplateSheet(
          title: 'Invoice template',
          icon: Icons.receipt_long_outlined,
          intro:
              'Review invoice details before `${action.commandFor(job.id)}`.',
          fields: const [
            ('Total cents', '0'),
            ('Attachments', 'Photos / completion notes'),
            ('Payment terms', 'Due on receipt'),
          ],
          confirm: action.label,
        );
        if (values == null) return null;
        final cents = int.tryParse(values.first.trim());
        return cents == null || cents <= 0
            ? action.commandFor(job.id)
            : 'invoice job ${job.id} total_cents $cents';
    }
  }

  Future<List<String>?> _showTemplateSheet({
    required String title,
    required IconData icon,
    required String intro,
    required List<(String, String)> fields,
    required String confirm,
  }) async {
    final controllers = [
      for (final field in fields) TextEditingController(text: field.$2),
    ];
    try {
      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          final theme = Theme.of(context);
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: OddjobzVisuals.rule,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(icon, color: OddjobzVisuals.activation),
                      const SizedBox(width: 10),
                      Text(title, style: theme.textTheme.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(intro, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 14),
                  for (var i = 0; i < fields.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: controllers[i],
                        decoration: InputDecoration(
                          labelText: fields[i].$1,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(confirm),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (result != true) return null;
      return [for (final controller in controllers) controller.text];
    } finally {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OddjobzPaper(
      child: Scaffold(
        appBar: AppBar(title: Text(widget.initialTitle ?? 'Job')),
        body: FutureBuilder<JobDetail>(
          future: _jobFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Error(error: snap.error.toString(), onRetry: _reload);
            }
            final job = snap.data!;
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _MetaCard(job: job),
                _StageTrail(state: job.state),
                _AdvanceBar(
                  state: job.state,
                  busy: _transitioning,
                  job: job,
                  onAdvance: _advance,
                ),
                const Divider(height: 1),
                const OddjobzSectionLabel(
                  label: 'Conversation',
                  icon: Icons.forum_outlined,
                ),
                _Conversation(future: _turnsFuture),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.job});
  final JobDetail job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(IconData, String)>[
      if (job.propertyAddress.isNotEmpty &&
          job.propertyAddress != job.customerName)
        (Icons.place_outlined, job.propertyAddress),
      if (job.services != null && job.services!.isNotEmpty)
        (Icons.build_outlined, job.services!),
      if (job.workOrderNumber != null && job.workOrderNumber!.isNotEmpty)
        (Icons.tag, 'WO ${job.workOrderNumber}'),
      if (job.scheduledAt.isNotEmpty) (Icons.event_outlined, job.scheduledAt),
    ];
    return OddjobzCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            job.customerName.isEmpty ? '(no customer)' : job.customerName,
            style: theme.textTheme.titleLarge,
          ),
          if (job.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(job.description, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 10),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    r.$1,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal pipeline trail; the current stage is filled, prior stages ticked.
class _StageTrail extends StatelessWidget {
  const _StageTrail({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = JobFsm.indexOf(state);
    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: JobFsm.stages.length,
        itemBuilder: (context, i) {
          final stage = JobFsm.stages[i];
          final done = current >= 0 && i < current;
          final isCurrent = i == current;
          final color = isCurrent
              ? theme.colorScheme.primary
              : done
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant;
          return Row(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isCurrent || done ? color : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: done
                        ? const Icon(Icons.check, size: 13, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    JobFsm.labelFor(stage),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isCurrent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isCurrent ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
              if (i < JobFsm.stages.length - 1)
                Container(
                  width: 24,
                  height: 2,
                  color: theme.colorScheme.outlineVariant,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AdvanceBar extends StatelessWidget {
  const _AdvanceBar({
    required this.state,
    required this.job,
    required this.busy,
    required this.onAdvance,
  });
  final String state;
  final JobDetail job;
  final bool busy;
  final Future<void> Function(JobFsmAction action, JobDetail job) onAdvance;

  IconData _iconFor(JobActionSheetKind kind) => switch (kind) {
    JobActionSheetKind.visitScheduler => Icons.event_outlined,
    JobActionSheetKind.quoteTemplate => Icons.request_quote_outlined,
    JobActionSheetKind.invoiceTemplate => Icons.receipt_long_outlined,
    JobActionSheetKind.none => Icons.arrow_forward,
  };

  @override
  Widget build(BuildContext context) {
    final actions = JobFsm.actionsFrom(state);
    if (actions.isEmpty) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in actions)
              FilledButton.icon(
                onPressed: busy ? null : () => onAdvance(action, job),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_iconFor(action.sheet), size: 18),
                label: Text(action.label),
              ),
          ],
        ),
      ),
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({required this.future});
  final Future<TurnsResult> future;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<TurnsResult>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final result = snap.data;
        if (snap.hasError || result == null) {
          return _hint(theme, 'Couldn’t load conversation.');
        }
        if (!result.available) {
          return _hint(
            theme,
            result.unavailableReason ?? 'No conversation linked to this job.',
          );
        }
        if (result.turns.isEmpty) {
          return _hint(theme, 'No messages yet.');
        }
        return Column(
          children: [for (final t in result.turns) _TurnBubble(turn: t)],
        );
      },
    );
  }

  Widget _hint(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}

class _TurnBubble extends StatelessWidget {
  const _TurnBubble({required this.turn});
  final ConvTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outbound = turn.direction == 'outbound';
    return Align(
      alignment: outbound ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: outbound
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: outbound
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              [
                turn.surface,
                turn.role,
                if (turn.outboundState.isNotEmpty) turn.outboundState,
              ].where((s) => s.isNotEmpty).join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(turn.body),
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Couldn’t load job', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

```
