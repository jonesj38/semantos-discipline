---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/screens/dashboard_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.750471+00:00
---

# archive/apps-navigation_app/lib/screens/dashboard_screen.dart

```dart
import 'package:flutter/material.dart';
import '../models/semantic_types.dart';
import '../main.dart';
import 'evening_review_screen.dart';
import 'morning_intention_screen.dart';

/// Main dashboard — the home screen.
/// Shows: streak, dimension radar, today's intention, vesting balance,
/// attention score, next action, and Paskian insight.
///
/// Design: dark theme, minimal, voice-first affordances.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Mock data — will come from providers
  int _streak = 12;
  int _attentionScore = 72;
  double _vestedBsv = 0.0847;
  double _unvestedBsv = 0.2341;
  String? _todayIntention = 'Focus on physical health — morning run';
  String? _paskianInsight =
      'Physical and Mental are reinforcing each other. '
      'When you exercise, your focus score improves the next day.';

  final Map<Dimension, double> _dimensionScores = {
    Dimension.mental: 7.0,
    Dimension.physical: 6.0,
    Dimension.spiritual: 8.0,
    Dimension.social: 5.0,
    Dimension.vocational: 6.5,
    Dimension.financial: 4.0,
    Dimension.familial: 7.5,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f23),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header with streak and balance
            SliverToBoxAdapter(child: _buildHeader()),

            // Today's intention card
            if (_todayIntention != null)
              SliverToBoxAdapter(child: _buildIntentionCard()),

            // Attention score
            SliverToBoxAdapter(child: _buildAttentionCard()),

            // Dimension scores
            SliverToBoxAdapter(child: _buildDimensionsCard()),

            // Vesting / financial card
            SliverToBoxAdapter(child: _buildVestingCard()),

            // Paskian insight
            if (_paskianInsight != null)
              SliverToBoxAdapter(child: _buildInsightCard()),

            // Quick actions
            SliverToBoxAdapter(child: _buildQuickActions()),

            // Bottom padding for nav bar
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Day $_streak',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getGreeting(),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ],
          ),
          const Spacer(),
          // Streak fire
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFf97316).withValues(alpha: 0.2),
                  const Color(0xFFef4444).withValues(alpha: 0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 4),
                Text(
                  '$_streak',
                  style: const TextStyle(
                    color: Color(0xFFf97316),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntentionCard() {
    return GestureDetector(
      onTap: () {
        final shell = context.findAncestorStateOfType<AppShellState>();
        shell?.openMorningIntention();
      },
      child: _card(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: Color(0xFF3b82f6), size: 18),
              const SizedBox(width: 8),
              Text(
                'Today\'s intention',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _todayIntention!,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildAttentionCard() {
    final color = _attentionScore > 70
        ? const Color(0xFF4ade80)
        : _attentionScore > 40
            ? const Color(0xFFfbbf24)
            : const Color(0xFFef4444);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.remove_red_eye_outlined,
                  color: Color(0xFF8b5cf6), size: 18),
              const SizedBox(width: 8),
              Text(
                'Attention score',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '$_attentionScore',
                style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Simple bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _attentionScore / 100,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Based on screen time analysis',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Life dimensions',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          ...Dimension.values.map((dim) {
            final score = _dimensionScores[dim] ?? 5.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(dim.emoji, style: const TextStyle(fontSize: 16)),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      dim.label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: score / 10,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation(
                          Color.lerp(
                            const Color(0xFFef4444),
                            const Color(0xFF4ade80),
                            score / 10,
                          )!,
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 20,
                    child: Text(
                      score.round().toString(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildVestingCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: Color(0xFFf59e0b), size: 18),
              const SizedBox(width: 8),
              Text(
                'Balance',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_vestedBsv.toStringAsFixed(4)} BSV',
                      style: const TextStyle(
                        color: Color(0xFF4ade80),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Vested — yours to claim',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_unvestedBsv.toStringAsFixed(4)} BSV',
                      style: const TextStyle(
                        color: Color(0xFFfbbf24),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Unvested — keep your streak',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard() {
    return _card(
      gradient: const LinearGradient(
        colors: [Color(0xFF1e1b4b), Color(0xFF172554)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFFa78bfa), size: 18),
              const SizedBox(width: 8),
              Text(
                'Paskian insight',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _paskianInsight!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          _actionButton(
            icon: Icons.edit_note,
            label: 'Release',
            color: const Color(0xFF3b82f6),
            onTap: () {
              final shell = context.findAncestorStateOfType<AppShellState>();
              shell?.switchToTab(1); // Release tab
            },
          ),
          const SizedBox(width: 12),
          _actionButton(
            icon: Icons.self_improvement,
            label: 'Meditate',
            color: const Color(0xFF8b5cf6),
            onTap: () {
              // Opens evening review as a modal for now
              // TODO: Dedicated meditation timer screen
              final shell = context.findAncestorStateOfType<AppShellState>();
              shell?.openEveningReview();
            },
          ),
          const SizedBox(width: 12),
          _actionButton(
            icon: Icons.camera_alt_outlined,
            label: 'Capture',
            color: const Color(0xFFf59e0b),
            onTap: () {
              // TODO: Open camera via image_picker to photograph journal
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Camera capture — coming soon'),
                  backgroundColor: Color(0xFF1a1a2e),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({
    required Widget child,
    Gradient? gradient,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: gradient,
          color: gradient == null ? Colors.white.withValues(alpha: 0.05) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

```
