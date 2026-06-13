---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/stage_trail.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.465667+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/stage_trail.dart

```dart
import 'package:flutter/material.dart';

import 'field_job_detail_repository.dart' show JobFsm;

/// Compact dots-only FSM trail for a job row (no labels) — the current state
/// filled, prior states dimmed, upcoming hollow. Mirrors the monolith's
/// JobListRow StageTrail.
class MiniStageTrail extends StatelessWidget {
  const MiniStageTrail({super.key, required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = JobFsm.indexOf(state);
    return Row(
      children: [
        for (int i = 0; i < JobFsm.stages.length; i++) ...[
          _dot(theme, i, current),
          if (i < JobFsm.stages.length - 1)
            Container(
              width: 10,
              height: 2,
              color: theme.colorScheme.outlineVariant,
            ),
        ],
        const SizedBox(width: 8),
        Text(
          state.replaceAll('_', ' '),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _dot(ThemeData theme, int i, int current) {
    final done = current >= 0 && i < current;
    final isCurrent = i == current;
    final color = isCurrent
        ? theme.colorScheme.primary
        : done
        ? theme.colorScheme.primary.withValues(alpha: 0.4)
        : theme.colorScheme.outlineVariant;
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: isCurrent || done ? color : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
    );
  }
}

```
