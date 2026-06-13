---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/turn_bubble.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.462341+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/turn_bubble.dart

```dart
// TurnBubble — renders a single ConversationTurn in the job thread.

import 'package:flutter/material.dart';

import 'brain_client.dart';
import 'conversation_turn.dart';

const _surfaceIcon = {
  'email': '✉',
  'gmail': '✉',
  'sms': '💬',
  'meta-inbox': '📩',
  'widget': '🌐',
};

class TurnBubble extends StatelessWidget {
  final ConversationTurn turn;
  final bool approving;
  final bool highlighted;
  final VoidCallback? onApprove;

  const TurnBubble({
    super.key,
    required this.turn,
    this.approving = false,
    this.highlighted = false,
    this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isIn = turn.isInbound;
    final isProposed = turn.isProposed;

    final ts = DateTime.fromMillisecondsSinceEpoch(turn.timestamp);
    final tsLabel =
        '${ts.day} ${_monthAbbr(ts.month)}, ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    final borderColor = highlighted
        ? cs.primary
        : isProposed
        ? const Color(0xFFFFB24A)
        : isIn
        ? cs.outlineVariant
        : cs.primary.withOpacity(0.4);

    final bgColor = highlighted
        ? cs.primaryContainer.withOpacity(0.28)
        : isProposed
        ? const Color(0xFFFFB24A).withOpacity(0.06)
        : isIn
        ? cs.surfaceContainerHighest
        : cs.surface;

    final accentColor = highlighted
        ? cs.primary
        : isProposed
        ? const Color(0xFFFFB24A)
        : isIn
        ? cs.outlineVariant
        : cs.primary;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
          bottomLeft: Radius.circular(6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Meta row ────────────────────────────────────────
                    Row(
                      children: [
                        Text(
                          '${_surfaceIcon[turn.surface] ?? '·'} ${turn.surface}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.8,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          tsLabel,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: cs.onSurfaceVariant.withOpacity(0.6),
                              ),
                        ),
                        if (turn.outboundState != null && !turn.isInbound) ...[
                          const SizedBox(width: 6),
                          _StateBadge(state: turn.outboundState!),
                        ],
                      ],
                    ),
                    if (turn.identityValue != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        turn.identityValue!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // ── Body ──────────────────────────────────────────────
                    SelectableText(
                      turn.bodyText,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    // ── Approve button (proposed only) ───────────────────
                    if (turn.isProposed && onApprove != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonal(
                          onPressed: approving ? null : onApprove,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(
                              0xFF4CAF50,
                            ).withOpacity(0.15),
                            foregroundColor: const Color(0xFF2E7D32),
                          ),
                          child: Text(
                            approving ? 'Sending…' : '✓ Approve & send',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthAbbr(int m) => const [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m];
}

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

class BrainClientErrorBanner extends StatelessWidget {
  final BrainClientError error;
  final VoidCallback? onLogout;

  const BrainClientErrorBanner({super.key, required this.error, this.onLogout});

  @override
  Widget build(BuildContext context) {
    if (error.isUnauthorised) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            const Text('Bearer token rejected. Please log in again.'),
            const SizedBox(height: 12),
            if (onLogout != null)
              FilledButton(onPressed: onLogout, child: const Text('Log out')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(error.message, style: const TextStyle(color: Colors.red)),
    );
  }
}

```
