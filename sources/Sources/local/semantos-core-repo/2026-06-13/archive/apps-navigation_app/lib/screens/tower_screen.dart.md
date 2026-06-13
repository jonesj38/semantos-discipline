---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/screens/tower_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.750773+00:00
---

# archive/apps-navigation_app/lib/screens/tower_screen.dart

```dart
import 'package:flutter/material.dart';
import '../models/semantic_types.dart';

/// Process map — NOT a linear tower.
/// Shows nested cycles that build on each other,
/// with recursive release/receive patterns visible.
class TowerScreen extends StatefulWidget {
  const TowerScreen({super.key});

  @override
  State<TowerScreen> createState() => _TowerScreenState();
}

class _TowerScreenState extends State<TowerScreen> {
  ProcessCycle? _expandedCycle;
  ProcessStep? _selectedStep;

  // Colors for each cycle
  static const _cycleColors = {
    ProcessCycle.foundation: Color(0xFF3b82f6),      // Blue
    ProcessCycle.energeticRelease: Color(0xFFef4444), // Red
    ProcessCycle.consciousRelease: Color(0xFF8b5cf6), // Purple
    ProcessCycle.discernment: Color(0xFFf59e0b),      // Amber
    ProcessCycle.application: Color(0xFF4ade80),       // Green
  };

  List<ProcessStep> _stepsForCycle(ProcessCycle cycle) {
    return allProcessSteps.where((s) => s.cycle == cycle).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f23),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  const Text(
                    'Process',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_expandedCycle != null || _selectedStep != null)
                    GestureDetector(
                      onTap: () => setState(() {
                        if (_selectedStep != null) {
                          _selectedStep = null;
                        } else {
                          _expandedCycle = null;
                        }
                      }),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_back_ios,
                              color: Colors.white38, size: 14),
                          Text('Back',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4))),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _selectedStep != null
                  ? _buildStepDetail(_selectedStep!)
                  : _expandedCycle != null
                      ? _buildCycleDetail(_expandedCycle!)
                      : _buildProcessOverview(),
            ),
          ],
        ),
      ),
    );
  }

  /// Top-level: shows the five process cycles as cards
  Widget _buildProcessOverview() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Intro text
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(
            'Five processes that build on each other. '
            'Release and receive patterns repeat at every depth.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),

        ...ProcessCycle.values.map((cycle) => _buildCycleCard(cycle)),
      ],
    );
  }

  Widget _buildCycleCard(ProcessCycle cycle) {
    final color = _cycleColors[cycle]!;
    final steps = _stepsForCycle(cycle);
    final hasRelease = steps.any((s) => s.isRelease);
    final hasReceive = steps.any((s) => s.isReceive);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => setState(() => _expandedCycle = cycle),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Cycle indicator
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cycle.label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Release/receive indicators
                  if (hasRelease)
                    _tag('Release', const Color(0xFFef4444)),
                  if (hasReceive) ...[
                    const SizedBox(width: 6),
                    _tag('Receive', const Color(0xFF4ade80)),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                cycle.description,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),

              // Inquiry question
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  cycle.inquiry,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Step flow preview
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: steps.asMap().entries.map((entry) {
                    final i = entry.key;
                    final step = entry.value;
                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: step.isRelease
                                ? const Color(0xFFef4444).withValues(alpha: 0.15)
                                : step.isReceive
                                    ? const Color(0xFF4ade80).withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            step.label,
                            style: TextStyle(
                              color: step.isRelease
                                  ? const Color(0xFFef4444)
                                  : step.isReceive
                                      ? const Color(0xFF4ade80)
                                      : Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (i < steps.length - 1)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              Icons.arrow_forward,
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Expanded cycle view — shows steps with detail
  Widget _buildCycleDetail(ProcessCycle cycle) {
    final color = _cycleColors[cycle]!;
    final steps = _stepsForCycle(cycle);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Cycle header
        Text(
          cycle.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          cycle.inquiry,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          cycle.description,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),

        // Steps as a flow
        ...steps.asMap().entries.map((entry) {
          final i = entry.key;
          final step = entry.value;
          final stepColor = step.isRelease
              ? const Color(0xFFef4444)
              : step.isReceive
                  ? const Color(0xFF4ade80)
                  : color;

          return Column(
            children: [
              // Step card
              GestureDetector(
                onTap: () => setState(() => _selectedStep = step),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: stepColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: stepColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      // Step indicator
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: stepColor.withValues(alpha: 0.2),
                        ),
                        child: Icon(
                          step.isRelease
                              ? Icons.air
                              : step.isReceive
                                  ? Icons.download_rounded
                                  : Icons.circle,
                          color: stepColor,
                          size: step.isRelease || step.isReceive ? 20 : 10,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  step.label,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (step.isRelease || step.isReceive) ...[
                                  const SizedBox(width: 8),
                                  _tag(
                                    step.isRelease ? 'Release' : 'Receive',
                                    stepColor,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              step.description,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ],
                  ),
                ),
              ),

              // Arrow between steps
              if (i < steps.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white.withValues(alpha: 0.15),
                    size: 20,
                  ),
                ),
            ],
          );
        }),

        // Recursive indicator
        if (cycle == ProcessCycle.consciousRelease ||
            cycle == ProcessCycle.energeticRelease)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                  // dashed would be nice but Flutter doesn't have it natively
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.replay,
                      color: Colors.white.withValues(alpha: 0.3), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This cycle repeats. Each pass goes deeper. '
                      'The same release/receive pattern, new material.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Individual step detail with practice options
  Widget _buildStepDetail(ProcessStep step) {
    final stepColor = step.isRelease
        ? const Color(0xFFef4444)
        : step.isReceive
            ? const Color(0xFF4ade80)
            : _cycleColors[step.cycle]!;

    final practices = _practicesForStep(step);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Step type tag
        if (step.isRelease || step.isReceive)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _tag(
              step.isRelease ? 'Release phase' : 'Receive phase',
              stepColor,
            ),
          ),

        Text(
          step.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Part of: ${step.cycle.label}',
          style: TextStyle(
            color: _cycleColors[step.cycle]!.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          step.description,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 15,
            height: 1.6,
          ),
        ),

        const SizedBox(height: 28),

        // Practices
        Text(
          'PRACTICES',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),

        ...practices.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Starting ${p['name']}...'),
                      backgroundColor: const Color(0xFF1a1a2e),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (p['color'] as Color).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (p['color'] as Color).withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(p['icon'] as IconData,
                          color: p['color'] as Color, size: 22),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p['name'] as String,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              p['desc'] as String,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.play_circle_outline,
                          color: Colors.white.withValues(alpha: 0.25)),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }

  List<Map<String, dynamic>> _practicesForStep(ProcessStep step) {
    final base = <Map<String, dynamic>>[];

    // Release steps always get writing release
    if (step.isRelease) {
      base.add({
        'name': 'Writing Release',
        'desc': 'Stream of consciousness — let it flow',
        'icon': Icons.edit_note,
        'color': const Color(0xFF3b82f6),
      });
    }

    // Receive steps get connection
    if (step.isReceive) {
      base.add({
        'name': 'Receive & Document',
        'desc': 'What intelligence is available?',
        'icon': Icons.download_rounded,
        'color': const Color(0xFF4ade80),
      });
    }

    // Step-specific practices
    switch (step.id) {
      case 'attention':
        base.add({
          'name': 'Focus Timer',
          'desc': 'Sit with attention for 5-20 minutes',
          'icon': Icons.self_improvement,
          'color': const Color(0xFF8b5cf6),
        });
      case 'qse_vacuum':
        base.add({
          'name': 'Cosmic Vacuum',
          'desc': 'Guided QSE visualization',
          'icon': Icons.air,
          'color': const Color(0xFF06b6d4),
        });
      case 'gold':
        base.add({
          'name': 'Gold Seal',
          'desc': 'Seal with permanence and walk forward',
          'icon': Icons.auto_awesome,
          'color': const Color(0xFFf59e0b),
        });
      case 'connection':
        base.add({
          'name': 'Connection',
          'desc': 'Highest self, inner child, future self, ancestors',
          'icon': Icons.link,
          'color': const Color(0xFF4ade80),
        });
      case 'resistance':
        base.add({
          'name': 'Resistance Inquiry',
          'desc': 'What am I holding onto? What\'s the cost?',
          'icon': Icons.psychology,
          'color': const Color(0xFFf59e0b),
        });
      case 'degrees_authenticity':
      case 'ego_belief_knowledge':
      case 'soul_discernment_wisdom':
        base.add({
          'name': 'Discernment Check',
          'desc': 'Is this belief or knowledge? Ego or soul?',
          'icon': Icons.balance,
          'color': const Color(0xFFf59e0b),
        });
      case 'creation':
        base.add({
          'name': 'Dimension Focus',
          'desc': 'Pick a dimension and create within it',
          'icon': Icons.dashboard_customize,
          'color': const Color(0xFF4ade80),
        });
    }

    // Everything gets writing as a fallback
    if (base.isEmpty || (!step.isRelease && step.id != 'attention')) {
      base.add({
        'name': 'Journaling',
        'desc': 'Explore this step through writing',
        'icon': Icons.edit_note,
        'color': const Color(0xFF3b82f6),
      });
    }

    return base;
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }
}

```
