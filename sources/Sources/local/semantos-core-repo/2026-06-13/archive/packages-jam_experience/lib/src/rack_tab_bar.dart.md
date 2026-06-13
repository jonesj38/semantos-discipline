---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/src/rack_tab_bar.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.813815+00:00
---

# archive/packages-jam_experience/lib/src/rack_tab_bar.dart

```dart
import 'package:flutter/material.dart';

import 'jam_colours.dart';

/// RackTabBar — three-tab bottom bar (RHYTHM / MELODY / BASS) with
/// live 16-step density indicators. Migrated from
/// `apps/world-apps/jam-room-mobile/lib/src/jam/rack_tab_bar.dart`.
class RackTabBar extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onTabSelected;

  /// 3 × 16 step indicators per rack. Inner list is 16 ints; 0 = off,
  /// nonzero = on.
  final List<List<int>> liveSteps;

  const RackTabBar({
    super.key,
    required this.activeIndex,
    required this.onTabSelected,
    this.liveSteps = const [[], [], []],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: JamColours.ink1,
        border: Border(top: BorderSide(color: JamColours.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (int i = 0; i < _racks.length; i++)
                Expanded(
                  child: _RackTab(
                    spec: _racks[i],
                    active: i == activeIndex,
                    steps: i < liveSteps.length ? liveSteps[i] : const [],
                    onTap: () => onTabSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _racks = [
  _RackSpec(
    id: 'rhythm',
    label: 'RHYTHM',
    icon: Icons.graphic_eq,
    tone: JamColours.toneRhythm,
  ),
  _RackSpec(
    id: 'melody',
    label: 'MELODY',
    icon: Icons.piano,
    tone: JamColours.toneMelody,
  ),
  _RackSpec(
    id: 'bass',
    label: 'BASS',
    icon: Icons.waves_outlined,
    tone: JamColours.toneBass,
  ),
];

class _RackSpec {
  final String id;
  final String label;
  final IconData icon;
  final Color tone;
  const _RackSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.tone,
  });
}

class _RackTab extends StatelessWidget {
  final _RackSpec spec;
  final bool active;
  final List<int> steps;
  final VoidCallback onTap;

  const _RackTab({
    required this.spec,
    required this.active,
    required this.steps,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? spec.tone : JamColours.muted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(spec.icon, color: color, size: 20),
            const SizedBox(height: 2),
            Text(
              spec.label,
              style: TextStyle(
                fontFamily: 'GeistMono',
                fontSize: 9,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: color,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(16, (i) {
                  final on = i < steps.length && steps[i] != 0;
                  return Container(
                    width: 3,
                    height: on ? 4 : 2,
                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                    decoration: BoxDecoration(
                      color: on
                          ? spec.tone.withValues(alpha: active ? 0.9 : 0.5)
                          : JamColours.line2,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

```
