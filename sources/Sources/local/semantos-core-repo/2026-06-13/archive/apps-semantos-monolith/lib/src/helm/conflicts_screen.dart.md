---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/conflicts_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.889561+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/conflicts_screen.dart

```dart
// D-O5m.followup-5 K1 conflict UI — Conflicts screen.
//
// Surfaces failed outbox entries with operator-actionable rows.  The
// AppBar status indicator on HomeScreen routes here when the operator
// taps the red "failed entries" dot.
//
// Each row carries:
//   - cell-id hex prefix + domain flag (from summariseEntry)
//   - the operator-facing failure message (from failure_messages.dart)
//   - the prev_state_hash hex for state_moved_on conflicts (W1.2)
//   - actions: Retry / Discard, plus "View conflict" for state_moved_on
//
// The screen subscribes to OutboxService.failedEntries so the surface
// updates live as flushes complete + the operator drains the queue.

import 'package:flutter/material.dart';

import '../outbox/conflict_summary.dart';
import '../outbox/failure_messages.dart';
import '../outbox/outbox_db.dart';
import '../outbox/outbox_service.dart';

/// Public widget for the conflicts surface.  Pass the same
/// [OutboxService] the home screen + flush loop use.
class ConflictsScreen extends StatelessWidget {
  final OutboxService outbox;
  const ConflictsScreen({super.key, required this.outbox});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Outbox conflicts')),
      body: StreamBuilder<List<OutboxFailedEntry>>(
        stream: outbox.failedEntries,
        builder: (context, snap) {
          final failed = snap.data ?? const <OutboxFailedEntry>[];
          if (failed.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            itemCount: failed.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _ConflictRow(
              failed: failed[i],
              outbox: outbox,
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
            SizedBox(height: 12),
            Text(
              'No conflicts.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              'Every queued change has either been accepted by the brain or is waiting to retry.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  final OutboxFailedEntry failed;
  final OutboxService outbox;
  const _ConflictRow({required this.failed, required this.outbox});

  @override
  Widget build(BuildContext context) {
    final summary = summariseEntry(failed.entry);
    final message = readableMessage(failed.kind, failed.message);
    final canViewConflict = failed.kind == OutboxFailureKind.stateMovedOn;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(summary,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 4),
          Text(message),
          // W1.2 — prev_state_hash is a 32-byte BLOB; display as hex prefix.
          if (failed.entry.prevStateHash != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "Brain's prior hash: ${_hexPrefix(failed.entry.prevStateHash!)}",
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (canViewConflict)
                TextButton.icon(
                  onPressed: () => _showConflictDialog(context, failed),
                  icon: const Icon(Icons.compare_arrows, size: 18),
                  label: const Text('View conflict'),
                ),
              TextButton.icon(
                onPressed: () => outbox.discard(failed.entry.id),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Discard'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => outbox.retry(failed.entry.id),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

/// Show a simple side-by-side dialog: "Your offline change → Brain's
/// prior state hash".  This is intentionally lightweight for the MVP —
/// future iterations can surface a structured diff per cell-type.
///
/// W1.2 — the old `payloadJson` / `lastBrainState` text fields are gone.
/// Displays the cell-id + payload hex prefix and the prev_state_hash.
void _showConflictDialog(BuildContext context, OutboxFailedEntry failed) {
  final prevHash = failed.entry.prevStateHash != null
      ? _hexPrefix(failed.entry.prevStateHash!)
      : '(unknown)';
  final payloadSummary = failed.entry.payload != null
      ? _hexPrefix(failed.entry.payload!)
      : '(no payload)';
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('State conflict'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Your offline change (payload prefix)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SelectableText(
              payloadSummary,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const Divider(height: 24),
            const Text("Brain's prior state hash",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SelectableText(
              prevHash,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Hex-encode up to 16 bytes from [bytes] as a display prefix.
String _hexPrefix(List<int> bytes) {
  final n = bytes.length < 16 ? bytes.length : 16;
  final sb = StringBuffer();
  for (var i = 0; i < n; i++) {
    sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  if (bytes.length > 16) sb.write('…');
  return sb.toString();
}

```
