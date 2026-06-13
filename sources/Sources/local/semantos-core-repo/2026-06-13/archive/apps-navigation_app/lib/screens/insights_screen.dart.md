---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/screens/insights_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.750167+00:00
---

# archive/apps-navigation_app/lib/screens/insights_screen.dart

```dart
import 'package:flutter/material.dart';
import '../models/semantic_types.dart';

/// Insights screen — RELEVANT objects that persist and accumulate.
/// Shows: Paskian insights, extracted patterns, saved insights,
/// dimension trends, and the constraint graph visualization.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Mock data — will come from kernel/node
  final List<_InsightItem> _insights = [
    _InsightItem(
      content: 'When I release resistance to financial growth, vocational clarity follows.',
      source: 'writing',
      date: DateTime.now().subtract(const Duration(days: 1)),
      tags: ['financial', 'vocational', 'resistance'],
    ),
    _InsightItem(
      content: 'My morning runs are the anchor for everything else. Without them, attention scatters.',
      source: 'connection',
      date: DateTime.now().subtract(const Duration(days: 3)),
      tags: ['physical', 'attention', 'anchor'],
    ),
    _InsightItem(
      content: 'The fear isn\'t about money — it\'s about deserving.',
      source: 'writing',
      date: DateTime.now().subtract(const Duration(days: 5)),
      tags: ['financial', 'ego', 'belief'],
    ),
  ];

  final List<_PatternItem> _patterns = [
    _PatternItem(
      description: 'Resistance to financial topics appears every 3-4 days',
      strength: 0.8,
      occurrences: 12,
    ),
    _PatternItem(
      description: 'Writing sessions after exercise produce deeper insights',
      strength: 0.7,
      occurrences: 8,
    ),
    _PatternItem(
      description: 'Social dimension neglected when vocational is high-focus',
      strength: 0.6,
      occurrences: 6,
    ),
  ];

  final List<String> _paskianInsights = [
    'Physical and Mental are reinforcing each other. When you exercise, your focus score improves the next day.',
    'Social dimension hasn\'t had attention in 5 days. Even a small action here could shift things.',
    'Your writing depth has increased 40% over the past two weeks. The releases are getting more honest.',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                'Insights',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF3b82f6),
              unselectedLabelColor: Colors.white38,
              indicatorColor: const Color(0xFF3b82f6),
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.white.withValues(alpha: 0.05),
              tabs: const [
                Tab(text: 'Paskian'),
                Tab(text: 'Patterns'),
                Tab(text: 'Insights'),
              ],
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPaskianTab(),
                  _buildPatternsTab(),
                  _buildInsightsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaskianTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Paskian insights from the node
        ..._paskianInsights.map((insight) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1e1b4b), Color(0xFF172554)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome,
                            color: Color(0xFFa78bfa), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Graph insight',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      insight,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            )),

        const SizedBox(height: 24),

        // Reinforcing pairs
        _sectionHeader('REINFORCING'),
        const SizedBox(height: 8),
        _pairCard(
          from: 'Physical',
          to: 'Mental',
          strength: 0.72,
          color: const Color(0xFF4ade80),
          icon: Icons.link,
        ),
        _pairCard(
          from: 'Spiritual',
          to: 'Familial',
          strength: 0.58,
          color: const Color(0xFF4ade80),
          icon: Icons.link,
        ),

        const SizedBox(height: 20),

        // Competing pairs
        _sectionHeader('IN TENSION'),
        const SizedBox(height: 8),
        _pairCard(
          from: 'Vocational',
          to: 'Social',
          strength: 0.45,
          color: const Color(0xFFf59e0b),
          icon: Icons.compare_arrows,
        ),
      ],
    );
  }

  Widget _buildPatternsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: _patterns
          .map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.description,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // Strength bar
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: p.strength,
                                backgroundColor: Colors.white.withValues(alpha: 0.05),
                                valueColor: AlwaysStoppedAnimation(
                                  Color.lerp(
                                    const Color(0xFFfbbf24),
                                    const Color(0xFFef4444),
                                    p.strength,
                                  )!,
                                ),
                                minHeight: 4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${p.occurrences}x',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildInsightsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: _insights
          .map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.content,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _sourceChip(i.source),
                          const SizedBox(width: 8),
                          ...i.tags.take(2).map((t) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    t,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              )),
                          const Spacer(),
                          Text(
                            _timeAgo(i.date),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.25),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.4),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _pairCard({
    required String from,
    required String to,
    required double strength,
    required Color color,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Text(from,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(icon, color: color, size: 18),
            ),
            Text(to,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
            const Spacer(),
            Text(
              '${(strength * 100).round()}%',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceChip(String source) {
    final color = switch (source) {
      'writing' => const Color(0xFF3b82f6),
      'connection' => const Color(0xFF4ade80),
      'vacuum' => const Color(0xFF06b6d4),
      'meditation' => const Color(0xFF8b5cf6),
      _ => Colors.white38,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        source,
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return 'just now';
  }
}

class _InsightItem {
  final String content;
  final String source;
  final DateTime date;
  final List<String> tags;

  _InsightItem({
    required this.content,
    required this.source,
    required this.date,
    required this.tags,
  });
}

class _PatternItem {
  final String description;
  final double strength;
  final int occurrences;

  _PatternItem({
    required this.description,
    required this.strength,
    required this.occurrences,
  });
}

```
