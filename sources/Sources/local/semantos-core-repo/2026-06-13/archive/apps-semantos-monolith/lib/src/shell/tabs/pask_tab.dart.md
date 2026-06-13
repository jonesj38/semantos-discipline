---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/shell/tabs/pask_tab.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.904654+00:00
---

# archive/apps-semantos-monolith/lib/src/shell/tabs/pask_tab.dart

```dart
// Pask — shell-native Pask graph engine status tab.
//
// Surfaces the current state of the operator's Pask attention graph:
//   - Engine initialisation status (WASM loaded / snapshot restored)
//   - Snapshot age + size (from the SQLite snapshot store)
//   - Domain flag the graph is scoped to
//   - Whether pask interactions are being recorded (live session health)
//
// This tab is intentionally a STATUS VIEW, not an action surface.
// The Pask graph is a background substrate; operators don't "use" it
// directly — it influences attention scoring, FSM transition weighting,
// and music-pass proactive scheduling behind the scenes.  The tab makes
// that invisible substrate visible and debuggable.
//
// Future milestone: interactive pask graph explorer (nodes, edges, strength
// scores).  That's a separate follow-up; the graph model lives in
// `core/pask/` and the WASM exports are already stable.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../pask/pask_session_service.dart';

class PaskTab extends StatefulWidget {
  const PaskTab({super.key, required this.paskSession});

  final PaskSessionService? paskSession;

  @override
  State<PaskTab> createState() => _PaskTabState();
}

class _PaskTabState extends State<PaskTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final session = widget.paskSession;

    return Scaffold(
      appBar: AppBar(title: const Text('Pask Engine')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(session: session, cs: cs, tt: tt),
          const SizedBox(height: 12),
          if (session != null) _SnapshotCard(session: session, cs: cs, tt: tt),
          const SizedBox(height: 12),
          _AboutCard(cs: cs, tt: tt),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard(
      {required this.session, required this.cs, required this.tt});
  final PaskSessionService? session;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    final (icon, color, status, detail) = switch (session) {
      null => (
          Icons.hourglass_empty_outlined,
          cs.outlineVariant,
          'Initialising',
          'Pask DB is opening — usually ready within 500 ms of login.',
        ),
      final s when s.isRestored => (
          Icons.check_circle_outline,
          cs.primary,
          'Graph restored',
          'Pask WASM has loaded the last snapshot and is ready.',
        ),
      _ => (
          Icons.radio_button_unchecked,
          cs.tertiary,
          'Session open',
          'No prior snapshot found; graph starts fresh this session.',
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status,
                      style: tt.titleMedium?.copyWith(color: color)),
                  const SizedBox(height: 4),
                  Text(detail,
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard(
      {required this.session, required this.cs, required this.tt});
  final PaskSessionService session;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    final snapshot = session.cachedSnapshot;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Snapshot', style: tt.titleSmall),
            const SizedBox(height: 12),
            _Row(
              label: 'Status',
              value: snapshot != null ? 'Loaded' : 'No snapshot',
              cs: cs,
              tt: tt,
            ),
            if (snapshot != null)
              _Row(
                label: 'Size',
                value: _formatBytes(snapshot.length),
                cs: cs,
                tt: tt,
              ),
            _Row(
              label: 'Restored',
              value: session.isRestored ? 'Yes' : 'No',
              cs: cs,
              tt: tt,
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(2)} MB';
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.cs, required this.tt});
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('About Pask',
                  style: tt.titleSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(height: 8),
            Text(
              'Pask is the attention graph engine at the core of Semantos. '
              'It scores and schedules work items based on recency, '
              'interaction strength, and the operator\'s declared goals. '
              'The graph runs as a WASM module so it\'s portable to '
              'embedded hardware (ESP32-C6) and survives app restarts '
              'via SQLite snapshot/restore.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(
      {required this.label,
      required this.value,
      required this.cs,
      required this.tt});
  final String label;
  final String value;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          Text(value, style: tt.bodySmall),
        ],
      ),
    );
  }
}

```
