---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/job_thread_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.888903+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/job_thread_screen.dart

```dart
// JobThreadScreen — canonical conversation thread for a single job.
//
// Data source:
//   GET /api/v1/conversation/turns?entityRef=<jobCellId>
//   via ConversationTurnsRepository (Dio + bearer token).
//
// The screen replaces the old AttentionService-backed patch/dispatch
// merge with the canonical `oddjobz.conversation.turn` rows that the
// brain stores in Postgres.  Same endpoint as the operator web PWA's
// JobDetailScreen, so both surfaces show the same data.
//
// Layout:
//   • Inbound  (customer)  — left-aligned blue bubble.
//   • Outbound (operator)  — right-aligned green bubble.
//   • Outbound (assistant) — full-width gray italic note.
//   • Proposed outbound   — amber border + ✓ Approve & send button.
//
// Pull-to-refresh reloads via the same fetchTurns() call.

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../repl/conversation_turns_repository.dart';
import '../repl/repl_client.dart';

// Surface icon map — mirrors the operator PWA's TurnBubble.
const _surfaceIcon = <String, String>{
  'email': '✉',
  'gmail': '✉',
  'sms': '💬',
  'meta-inbox': '📩',
  'widget': '🌐',
};

class JobThreadScreen extends StatefulWidget {
  /// 64-hex LMDB cell hash of the job.  Passed as `entityRef` to the
  /// conversation turns endpoint.
  final String entityRef;

  /// Job title shown in the AppBar — typically the customer name.
  /// Falls back to the first 8 chars of [entityRef] when empty.
  final String jobTitle;

  /// Conversation turns repository backed by the brain's HTTP endpoint.
  final ConversationTurnsRepository turnsRepository;

  /// When supplied, a send bar appears at the bottom of the thread so
  /// the operator can type notes directly from the thread view.  Notes
  /// are posted to POST /api/v1/repl with a job-scoped prefix so the
  /// brain's entity resolver knows which job the note belongs to.
  final ReplClient? replClient;

  /// When supplied, the thread's composer becomes a single big mic
  /// button that opens VoiceCommandSheet anchored to this job.  The
  /// sheet's transcript is submitted as a ConversationTurn anchored
  /// to [entityRef] (see HomeScreen._openJobVoiceNote).  Null = the
  /// thread renders without a composer (read-only view).
  final Future<void> Function(
    BuildContext context,
    String jobCellId,
    ConversationTurnsRepository turns,
  )? openVoiceNote;

  const JobThreadScreen({
    super.key,
    required this.entityRef,
    required this.jobTitle,
    required this.turnsRepository,
    this.replClient,
    this.openVoiceNote,
  });

  @override
  State<JobThreadScreen> createState() => _JobThreadScreenState();
}

class _JobThreadScreenState extends State<JobThreadScreen> {
  List<ConversationTurn> _turns = const [];
  bool _loading = true;
  String? _error;
  String? _approving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final turns = await widget.turnsRepository.fetchTurns(
        entityRef: widget.entityRef,
        limit: 200,
      );
      if (!mounted) return;
      setState(() => _turns = turns);
    } on ConversationTurnsError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.isUnauthorised
          ? 'Not authorised — please re-pair this device.'
          : 'Failed to load thread: ${e.wire} (${e.httpStatus})');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load thread: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendNote(String text) async {
    if (text.trim().isEmpty) return;

    // Local-first: append the operator's note to the visible thread
    // *immediately* and let the brain round-trip happen in the
    // background.  Pre-refactor we awaited a 60-second receive-timeout
    // POST before showing anything; if the brain was slow (Postgres
    // connectivity, bun child cold-start) the operator got a "Note not
    // saved" snackbar after a minute of staring at a frozen composer.
    //
    // Now: the optimistic turn carries `outboundState: 'pending'` so it
    // renders with the pending badge; the background task updates the
    // badge to 'sent' on success (and a reload swaps in the canonical
    // turn id) or 'failed' on error.  The composer is free instantly.
    final now = DateTime.now().millisecondsSinceEpoch;
    final pendingId = 'pending-$now';
    final trimmed = text.trim();
    setState(() => _turns = [
          ..._turns,
          ConversationTurn(
            turnId: pendingId,
            conversationId: '',
            participantRole: 'operator',
            direction: 'outbound',
            surface: 'widget',
            bodyText: trimmed,
            timestamp: now,
            outboundState: 'pending',
          ),
        ]);

    // Fire-and-forget the POST.  Capture `widget.turnsRepository` +
    // `widget.entityRef` before scheduling so the future doesn't reach
    // back into the widget after dispose.
    final repo = widget.turnsRepository;
    final entityId = widget.entityRef;
    unawaited(() async {
      try {
        await repo.submitVoiceNote(
          transcript: trimmed,
          entityId: entityId,
          entityKind: 'job',
          capturedAt: DateTime.now().toUtc().toIso8601String(),
        );
        // Reload swaps the optimistic pending turn for the canonical
        // server-side version (which has the real turn_id).
        if (mounted) await _load();
      } on ConversationTurnsError catch (e) {
        if (!mounted) return;
        _markPendingFailed(pendingId, e.isUnauthorised
            ? 'Not authorised — please re-pair.'
            : 'Note not saved: ${e.wire}');
      } catch (e) {
        if (!mounted) return;
        _markPendingFailed(pendingId, 'Note not saved: $e');
      }
    }());
  }

  /// Flip a still-pending optimistic turn to the `failed` state so the
  /// red badge surfaces inline on that turn, then show a non-blocking
  /// snackbar.  The operator can re-send by typing the same text again
  /// or (future work) tapping the failed turn to retry.
  void _markPendingFailed(String pendingTurnId, String message) {
    setState(() {
      _turns = [
        for (final t in _turns)
          if (t.turnId == pendingTurnId)
            ConversationTurn(
              turnId: t.turnId,
              conversationId: t.conversationId,
              participantRole: t.participantRole,
              direction: t.direction,
              surface: t.surface,
              bodyText: t.bodyText,
              timestamp: t.timestamp,
              outboundState: 'failed',
            )
          else
            t,
      ];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _approveTurn(String turnId) async {
    setState(() => _approving = turnId);
    try {
      await widget.turnsRepository.approveTurn(turnId);
      await _load();
    } on ConversationTurnsError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approve failed: ${e.wire}')),
      );
    } finally {
      if (mounted) setState(() => _approving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.jobTitle.isNotEmpty
        ? widget.jobTitle
        : widget.entityRef.substring(0, 8);

    return Scaffold(
      appBar: AppBar(
        title: Text('Thread — $title'),
        actions: [
          // Voice-note affordance.  Same VoiceCommandSheet pipeline as
          // JobDetailScreen's AppBar mic — the transcript lands in this
          // thread's ConversationTurn history alongside any typed notes.
          if (widget.openVoiceNote != null)
            IconButton(
              icon: const Icon(Icons.mic_none),
              onPressed: () => widget.openVoiceNote!(
                context,
                widget.entityRef,
                widget.turnsRepository,
              ),
              tooltip: 'Record voice note',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _buildBody(context),
            ),
          ),
          // Footer composer = text input + send (for typing notes).
          // Voice notes are recorded from the AppBar mic — both flow
          // into the same ConversationTurn history above.
          _ThreadSendBar(
            jobTitle: title,
            onSend: _sendNote,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _turns.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _turns.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 64),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_turns.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 64),
          Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No conversation history yet.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: _turns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, i) => _TurnBubble(
        key: ValueKey(_turns[i].turnId),
        turn: _turns[i],
        approving: _approving == _turns[i].turnId,
        onApprove: _turns[i].isProposed
            ? () => _approveTurn(_turns[i].turnId)
            : null,
      ),
    );
  }
}

// ── Turn bubble ────────────────────────────────────────────────────────

class _TurnBubble extends StatelessWidget {
  final ConversationTurn turn;
  final bool approving;
  final VoidCallback? onApprove;

  const _TurnBubble({
    super.key,
    required this.turn,
    this.approving = false,
    this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // assistant outbound → centred italic note.
    if (!turn.isInbound && turn.participantRole == 'assistant') {
      return _assistantNote(context, theme, cs);
    }

    // inbound = customer (left), outbound = operator (right).
    if (turn.isInbound) {
      return _customerBubble(context, theme, cs);
    }
    return _operatorBubble(context, theme, cs);
  }

  Widget _assistantNote(
      BuildContext context, ThemeData theme, ColorScheme cs) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: turn.isProposed
              ? const Color(0xFFFFB24A).withOpacity(0.08)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
          border: turn.isProposed
              ? Border.all(color: const Color(0xFFFFB24A))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _metaRow(context, theme, cs),
            const SizedBox(height: 4),
            Text(
              turn.bodyText,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (turn.isProposed && onApprove != null)
              _approveButton(theme),
          ],
        ),
      ),
    );
  }

  Widget _customerBubble(
      BuildContext context, ThemeData theme, ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 280),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
              bottomLeft: Radius.circular(12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _metaRow(context, theme, cs),
              const SizedBox(height: 4),
              SelectableText(turn.bodyText,
                  style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  Widget _operatorBubble(
      BuildContext context, ThemeData theme, ColorScheme cs) {
    final isProposed = turn.isProposed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 280),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isProposed
                    ? const Color(0xFFFFB24A).withOpacity(0.08)
                    : Colors.green.shade100,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                border: isProposed
                    ? Border.all(color: const Color(0xFFFFB24A))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _metaRow(context, theme, cs),
                  const SizedBox(height: 4),
                  SelectableText(turn.bodyText,
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
        if (isProposed && onApprove != null)
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 4),
            child: _approveButton(theme),
          ),
      ],
    );
  }

  Widget _metaRow(
      BuildContext context, ThemeData theme, ColorScheme cs) {
    final tsLabel = _tsLabel(turn.timestamp);
    final surfaceIcon =
        _surfaceIcon[turn.surface] ?? '·';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$surfaceIcon ${turn.surface}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          tsLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant.withOpacity(0.6),
          ),
        ),
        if (turn.outboundState != null && !turn.isInbound) ...[
          const SizedBox(width: 6),
          _StateBadge(state: turn.outboundState!),
        ],
      ],
    );
  }

  Widget _approveButton(ThemeData theme) {
    return SizedBox(
      child: FilledButton.tonal(
        onPressed: approving ? null : onApprove,
        style: FilledButton.styleFrom(
          backgroundColor:
              const Color(0xFF4CAF50).withOpacity(0.15),
          foregroundColor: const Color(0xFF2E7D32),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        ),
        child: Text(
          approving ? 'Sending…' : '✓ Approve & send',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  String _tsLabel(int ms) {
    if (ms == 0) return '';
    final ts = DateTime.fromMillisecondsSinceEpoch(ms);
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays}d ago';
  }
}

// ── Thread send bar ────────────────────────────────────────────────────

class _ThreadSendBar extends StatefulWidget {
  final String jobTitle;
  final Future<void> Function(String) onSend;

  const _ThreadSendBar({required this.jobTitle, required this.onSend});

  @override
  State<_ThreadSendBar> createState() => _ThreadSendBarState();
}

class _ThreadSendBarState extends State<_ThreadSendBar> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Add a note…',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

// ── State badge ────────────────────────────────────────────────────────

class _StateBadge extends StatelessWidget {
  final String state;
  const _StateBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (state) {
      case 'proposed':
        color = const Color(0xFFFFB24A);
        break;
      case 'sent':
      case 'delivered':
        color = const Color(0xFF4CAF50);
        break;
      case 'failed':
      case 'rejected':
        color = const Color(0xFFE53935);
        break;
      case 'approved':
        color = Theme.of(context).colorScheme.primary;
        break;
      default:
        color = Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        state.toUpperCase(),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 9,
          letterSpacing: 0.8,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

```
