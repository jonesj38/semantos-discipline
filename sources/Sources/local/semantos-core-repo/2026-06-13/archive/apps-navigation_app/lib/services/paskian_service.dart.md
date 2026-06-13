---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/services/paskian_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.748231+00:00
---

# archive/apps-navigation_app/lib/services/paskian_service.dart

```dart
import 'dart:math';
import '../models/semantic_types.dart';

/// A node in the Paskian constraint graph.
/// Each dimension and practice type is a node.
class PaskianNode {
  final String id;
  final String label;
  double activation; // Current activation level 0-1
  int interactionCount;
  DateTime lastInteraction;

  PaskianNode({
    required this.id,
    required this.label,
    this.activation = 0.5,
    this.interactionCount = 0,
    DateTime? lastInteraction,
  }) : lastInteraction = lastInteraction ?? DateTime.now();
}

/// An edge in the constraint graph.
/// Positive weight = reinforcing relationship.
/// Negative weight = competing relationship.
class PaskianEdge {
  final String fromId;
  final String toId;
  double weight; // -1.0 to 1.0
  int updateCount;

  PaskianEdge({
    required this.fromId,
    required this.toId,
    this.weight = 0.0,
    this.updateCount = 0,
  });
}

/// The Paskian conversation/learning engine.
///
/// This is the brain of the accountability system. It learns:
/// - Which dimensions reinforce each other (exercise → sleep → mental clarity)
/// - Which dimensions compete (vocational overtime → familial neglect)
/// - Which practices stabilise which dimensions
/// - When a dimension needs attention (activation decay)
///
/// Over time it teaches you back — surfacing insights about YOUR
/// personal growth dynamics, not generic advice.
class PaskianService {
  final Map<String, PaskianNode> _nodes = {};
  final Map<String, PaskianEdge> _edges = {};

  /// Learning rate — how fast edges update
  final double learningRate;

  /// Decay rate — how fast activation fades without interaction
  final double decayRate;

  PaskianService({
    this.learningRate = 0.1,
    this.decayRate = 0.02,
  }) {
    _initializeGraph();
  }

  void _initializeGraph() {
    // Create nodes for each dimension
    for (final dim in Dimension.values) {
      _nodes['dim_${dim.name}'] = PaskianNode(
        id: 'dim_${dim.name}',
        label: dim.label,
      );
    }

    // Create nodes for practice types
    final practices = [
      'writing_release',
      'meditation',
      'vacuum_session',
      'connection',
      'morning_intention',
      'evening_review',
      'midday_pulse',
    ];
    for (final p in practices) {
      _nodes['practice_$p'] = PaskianNode(
        id: 'practice_$p',
        label: p.replaceAll('_', ' '),
      );
    }

    // Create node for screen time / attention
    _nodes['attention_score'] = PaskianNode(
      id: 'attention_score',
      label: 'Attention Score',
    );

    // Initialize edges between all dimension pairs
    final dimNodes =
        _nodes.keys.where((k) => k.startsWith('dim_')).toList();
    for (int i = 0; i < dimNodes.length; i++) {
      for (int j = i + 1; j < dimNodes.length; j++) {
        final edgeId = '${dimNodes[i]}->${dimNodes[j]}';
        _edges[edgeId] = PaskianEdge(
          fromId: dimNodes[i],
          toId: dimNodes[j],
        );
      }
    }

    // Initialize edges from practices to dimensions
    for (final pId in _nodes.keys.where((k) => k.startsWith('practice_'))) {
      for (final dId in dimNodes) {
        final edgeId = '$pId->$dId';
        _edges[edgeId] = PaskianEdge(fromId: pId, toId: dId);
      }
    }

    // Attention score connects to all dimensions
    for (final dId in dimNodes) {
      final edgeId = 'attention_score->$dId';
      _edges[edgeId] = PaskianEdge(fromId: 'attention_score', toId: dId);
    }
  }

  /// Record an interaction — this is the core learning mechanism.
  /// Every check-in, practice, or measurement is an interaction.
  void interact({
    required String nodeId,
    required double signal, // -1.0 (negative) to 1.0 (positive)
    String? relatedNodeId,
  }) {
    final node = _nodes[nodeId];
    if (node == null) return;

    // Update node activation
    node.activation = (node.activation + signal * learningRate).clamp(0.0, 1.0);
    node.interactionCount++;
    node.lastInteraction = DateTime.now();

    // If there's a related node, strengthen/weaken the edge
    if (relatedNodeId != null) {
      _updateEdge(nodeId, relatedNodeId, signal);
    }

    // Propagate activation through strong edges
    _propagate(nodeId, signal * 0.5); // Attenuated propagation
  }

  /// Record a win (from daily review)
  void recordWin(Dimension dimension) {
    interact(
      nodeId: 'dim_${dimension.name}',
      signal: 0.3, // Gentle positive reinforcement
    );
  }

  /// Record an improvement area
  void recordImprovement(Dimension dimension) {
    interact(
      nodeId: 'dim_${dimension.name}',
      signal: -0.1, // Gentle negative signal — not punishment, awareness
    );
  }

  /// Record a practice completion
  void recordPractice(String practiceType, {Dimension? focusDimension}) {
    interact(
      nodeId: 'practice_$practiceType',
      signal: 0.5,
      relatedNodeId:
          focusDimension != null ? 'dim_${focusDimension.name}' : null,
    );
  }

  /// Record attention score from screen time
  void recordAttentionScore(int score) {
    interact(
      nodeId: 'attention_score',
      signal: (score - 50) / 50.0, // Normalise 0-100 to -1..1
    );
  }

  /// Record a fulfilled intention
  void recordIntentionFulfilled(Dimension dimension) {
    interact(
      nodeId: 'dim_${dimension.name}',
      signal: 0.5, // Stronger signal — you followed through
    );
  }

  /// Apply time decay — call daily
  void applyDecay() {
    final now = DateTime.now();
    for (final node in _nodes.values) {
      final hoursSince = now.difference(node.lastInteraction).inHours;
      if (hoursSince > 24) {
        // Activation decays toward 0.5 (neutral)
        final decay = decayRate * (hoursSince / 24).clamp(0, 7);
        if (node.activation > 0.5) {
          node.activation = max(0.5, node.activation - decay);
        } else {
          node.activation = min(0.5, node.activation + decay);
        }
      }
    }
  }

  /// Get the dimension that most needs attention right now.
  /// Based on lowest activation + decay + edge relationships.
  Dimension? getDimensionNeedingAttention() {
    Dimension? neediest;
    double lowestActivation = 1.0;

    for (final dim in Dimension.values) {
      final node = _nodes['dim_${dim.name}'];
      if (node != null && node.activation < lowestActivation) {
        lowestActivation = node.activation;
        neediest = dim;
      }
    }

    return neediest;
  }

  /// Get reinforcing pairs — "these dimensions support each other"
  List<Map<String, dynamic>> getReinforcingPairs() {
    return _edges.values
        .where((e) =>
            e.weight > 0.3 &&
            e.fromId.startsWith('dim_') &&
            e.toId.startsWith('dim_'))
        .map((e) => {
              'from': _nodes[e.fromId]!.label,
              'to': _nodes[e.toId]!.label,
              'strength': e.weight,
            })
        .toList()
      ..sort((a, b) =>
          (b['strength'] as double).compareTo(a['strength'] as double));
  }

  /// Get competing pairs — "these dimensions are in tension"
  List<Map<String, dynamic>> getCompetingPairs() {
    return _edges.values
        .where((e) =>
            e.weight < -0.2 &&
            e.fromId.startsWith('dim_') &&
            e.toId.startsWith('dim_'))
        .map((e) => {
              'from': _nodes[e.fromId]!.label,
              'to': _nodes[e.toId]!.label,
              'tension': e.weight.abs(),
            })
        .toList()
      ..sort(
          (a, b) => (b['tension'] as double).compareTo(a['tension'] as double));
  }

  /// Generate a Paskian insight — the graph teaching you back.
  /// Returns a natural language insight about your growth dynamics.
  String? generateInsight() {
    final reinforcing = getReinforcingPairs();
    final competing = getCompetingPairs();
    final neediest = getDimensionNeedingAttention();

    if (reinforcing.isNotEmpty && reinforcing.first['strength'] as double > 0.5) {
      final pair = reinforcing.first;
      return '${pair['from']} and ${pair['to']} are reinforcing each other. '
          'When you invest in one, the other strengthens too.';
    }

    if (competing.isNotEmpty && competing.first['tension'] as double > 0.4) {
      final pair = competing.first;
      return '${pair['from']} and ${pair['to']} seem to be in tension. '
          'Consider which deserves priority this week.';
    }

    if (neediest != null) {
      final node = _nodes['dim_${neediest.name}']!;
      final daysSince =
          DateTime.now().difference(node.lastInteraction).inDays;
      if (daysSince > 3) {
        return '${neediest.label} hasn\'t had attention in $daysSince days. '
            'Even a small action here could shift things.';
      }
    }

    return null;
  }

  /// Get full graph state for visualisation
  Map<String, dynamic> getGraphState() {
    return {
      'nodes': _nodes.map((k, v) => MapEntry(k, {
            'label': v.label,
            'activation': v.activation,
            'interactions': v.interactionCount,
            'lastInteraction': v.lastInteraction.toIso8601String(),
          })),
      'edges': _edges.map((k, v) => MapEntry(k, {
            'from': v.fromId,
            'to': v.toId,
            'weight': v.weight,
            'updates': v.updateCount,
          })),
    };
  }

  void _updateEdge(String fromId, String toId, double signal) {
    final edgeId1 = '$fromId->$toId';
    final edgeId2 = '$toId->$fromId';

    final edge = _edges[edgeId1] ?? _edges[edgeId2];
    if (edge != null) {
      // Hebbian-ish learning: co-activation strengthens, anti-correlation weakens
      edge.weight = (edge.weight + signal * learningRate).clamp(-1.0, 1.0);
      edge.updateCount++;
    }
  }

  void _propagate(String sourceId, double signal) {
    for (final edge in _edges.values) {
      if (edge.fromId == sourceId || edge.toId == sourceId) {
        final targetId =
            edge.fromId == sourceId ? edge.toId : edge.fromId;
        final target = _nodes[targetId];
        if (target != null) {
          // Propagate proportional to edge weight
          final propagatedSignal = signal * edge.weight;
          target.activation =
              (target.activation + propagatedSignal * 0.1).clamp(0.0, 1.0);
        }
      }
    }
  }

  void dispose() {}
}

```
