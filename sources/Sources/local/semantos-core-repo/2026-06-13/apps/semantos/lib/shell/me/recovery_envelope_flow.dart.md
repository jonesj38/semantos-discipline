---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/me/recovery_envelope_flow.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.120155+00:00
---

# apps/semantos/lib/shell/me/recovery_envelope_flow.dart

```dart
// C11 PR-C11-2 — Recovery row UI + envelope generation flow.
//
// Reference: docs/design/HELM-ME-SURFACE.md §3 (UX) + §5 row 3 (Recovery).
//
// The row has two sub-actions:
//   1. Set up secret questions  (lands in PR-C11-3)
//      Until PR-C11-3 wires the questions sheet, this opens a
//      "pending" snackbar so the operator sees what's coming.
//   2. Generate + download envelope
//      Enabled ONLY when both prereqs are satisfied:
//        - ChallengeBundle stored (PR-C11-3 ships the storage seam)
//        - 64-byte BIP39 seed available (PR-C11-4 wires wallet-headers)
//      Until then the button is disabled with an inline explainer.
//
// When both prereqs land, this widget will:
//   - read ChallengeBundle questions + answers (in-memory from a
//     just-collected sheet) and the wallet's BIP39 seed
//   - call `buildEnvelope(...)` from src/plexus/envelope.dart
//   - serialise the resulting envelope to JSON
//   - hand it to the platform via `share_plus` for the operator to
//     save (downloads/email/AirDrop/iCloud/etc.)
//
// PR-C11-2 lands the structure + state + button + the working
// `buildEnvelope` underneath. Wiring the prereqs into real state
// is PR-C11-3 (questions) + PR-C11-4 (wallet).

import 'package:flutter/material.dart';

import '../../src/brain/brain_http_client.dart';
import '../../src/plexus/challenge_bundle_store.dart';
import 'secret_questions_flow.dart';

/// Readiness gate for envelope generation. Each row knows which PR
/// will populate it; the UI surfaces an honest signal until then.
class EnvelopeReadiness {
  final bool hasQuestions;
  final bool hasSeed;
  const EnvelopeReadiness({
    required this.hasQuestions,
    required this.hasSeed,
  });

  bool get isReady => hasQuestions && hasSeed;

  /// Human-readable explainer for the disabled-button state.
  String get blockedReason {
    if (!hasQuestions && !hasSeed) {
      return 'needs secret questions (PR-C11-3) + wallet seed (PR-C11-4)';
    }
    if (!hasQuestions) return 'needs secret questions — PR-C11-3';
    return 'needs wallet seed — PR-C11-4';
  }
}

/// Recovery row body — two action tiles + state hints. Reads/writes
/// ChallengeBundle storage on demand (PR-C11-3); seed availability
/// arrives in PR-C11-4.
class RecoveryRow extends StatefulWidget {
  const RecoveryRow({
    super.key,
    required this.brainInfo,
    required this.bundleStore,
    this.hasSeed = false,
  });

  final BrainInfo? brainInfo;
  final ChallengeBundleStore bundleStore;

  /// Wallet seed availability — PR-C11-4 wires this true once wallet-
  /// headers exposes a BIP39 seed handle.
  final bool hasSeed;

  @override
  State<RecoveryRow> createState() => _RecoveryRowState();
}

class _RecoveryRowState extends State<RecoveryRow> {
  StoredChallengeBundle? _stored;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshBundle();
  }

  Future<void> _refreshBundle() async {
    final stored = await widget.bundleStore.read();
    if (!mounted) return;
    setState(() {
      _stored = stored;
      _loading = false;
    });
  }

  Future<void> _openQuestionsSheet() async {
    final saved = await showSecretQuestionsSheet(
      context,
      store: widget.bundleStore,
      existing: _stored,
    );
    if (saved) {
      await _refreshBundle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasQuestions = _stored != null;
    final readiness = EnvelopeReadiness(
      hasQuestions: hasQuestions,
      hasSeed: widget.hasSeed,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                'Recovery',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ] else ...[
            // Sub-action 1 — questions setup
            _SubAction(
              title: 'Secret questions',
              statusLine: hasQuestions
                  ? 'set · ${_stored!.bundle.questions.length} questions · created ${_relativeCreated(_stored!.createdAt)}'
                  : 'not set',
              statusOk: hasQuestions,
              buttonLabel: hasQuestions ? 'Update' : 'Set up secret questions',
              onPressed: _openQuestionsSheet,
            ),
            const SizedBox(height: 12),
            // Sub-action 2 — envelope generation + download
            _SubAction(
              title: 'Recovery envelope',
              statusLine: readiness.isReady
                  ? 'ready to generate'
                  : readiness.blockedReason,
              statusOk: readiness.isReady,
              buttonLabel: 'Generate + download',
              onPressed: readiness.isReady
                  ? () => _showPendingSnack(
                        context,
                        'Envelope generation needs the wallet seed (PR-C11-4). Crypto port + storage already in place.',
                      )
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  /// "today" / "yesterday" / "Apr 12" — best-effort, locale-agnostic.
  static String _relativeCreated(String iso) {
    DateTime when;
    try {
      when = DateTime.parse(iso).toLocal();
    } catch (_) {
      return iso;
    }
    final now = DateTime.now();
    final daysAgo = now.difference(when).inDays;
    if (daysAgo == 0) return 'today';
    if (daysAgo == 1) return 'yesterday';
    if (daysAgo < 30) return '$daysAgo days ago';
    return when.toIso8601String().substring(0, 10);
  }
}

class _SubAction extends StatelessWidget {
  const _SubAction({
    required this.title,
    required this.statusLine,
    required this.statusOk,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String statusLine;
  final bool statusOk;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = onPressed == null;
    return Padding(
      padding: const EdgeInsets.only(left: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                statusOk
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
                size: 16,
                color: statusOk
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 2),
            child: Text(
              statusLine,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDisabled
                    ? theme.colorScheme.outline
                    : theme.colorScheme.onSurfaceVariant,
                fontStyle: isDisabled ? FontStyle.italic : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 6),
            child: OutlinedButton(
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

void _showPendingSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
    ),
  );
}

```
