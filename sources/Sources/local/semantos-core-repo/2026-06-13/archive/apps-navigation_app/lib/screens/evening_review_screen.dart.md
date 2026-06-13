---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/screens/evening_review_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.751365+00:00
---

# archive/apps-navigation_app/lib/screens/evening_review_screen.dart

```dart
import 'package:flutter/material.dart';
import '../models/semantic_types.dart';
import '../models/objects.dart';

/// Evening review flow — the most important daily touchpoint.
/// Voice-first, minimal taps. 3 wins, 3 improvements, tomorrow's intention.
///
/// Flow:
/// 1. "Tell me 3 things you did well today" (voice or text)
/// 2. "What 3 things could you improve?" (voice or text)
/// 3. Quick dimension scores (7 sliders, swipeable)
/// 4. "What's your intention for tomorrow?" (voice or text)
/// 5. Energy & mood check (2 sliders)
/// 6. Show Paskian insight if available
/// 7. Save → kernel consumes as LINEAR
class EveningReviewScreen extends StatefulWidget {
  const EveningReviewScreen({super.key});

  @override
  State<EveningReviewScreen> createState() => _EveningReviewScreenState();
}

class _EveningReviewScreenState extends State<EveningReviewScreen> {
  int _step = 0;
  final _pageController = PageController();

  // Step 1: Wins
  final List<String> _wins = ['', '', ''];
  final List<TextEditingController> _winControllers =
      List.generate(3, (_) => TextEditingController());

  // Step 2: Improvements
  final List<String> _improvements = ['', '', ''];
  final List<TextEditingController> _improvementControllers =
      List.generate(3, (_) => TextEditingController());

  // Step 3: Dimension scores
  final Map<Dimension, double> _dimensionScores = {
    for (final d in Dimension.values) d: 5.0,
  };

  // Step 4: Tomorrow's intention
  final _intentionController = TextEditingController();

  // Step 5: Energy & mood
  double _energy = 5;
  double _mood = 5;

  // Voice recording state
  bool _isListening = false;

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _winControllers) c.dispose();
    for (final c in _improvementControllers) c.dispose();
    _intentionController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_step < 4) {
      setState(() => _step++);
      _pageController.animateToPage(
        _step,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _saveReview();
    }
  }

  void _previousStep() {
    if (_step > 0) {
      setState(() => _step--);
      _pageController.animateToPage(
        _step,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _saveReview() async {
    final review = DailyReview(
      wins: _winControllers.map((c) => c.text).where((t) => t.isNotEmpty).toList(),
      improvements: _improvementControllers
          .map((c) => c.text)
          .where((t) => t.isNotEmpty)
          .toList(),
      tomorrowIntention: _intentionController.text,
      energyLevel: _energy.round(),
      moodLevel: _mood.round(),
      dimensionScores: _dimensionScores.map((k, v) => MapEntry(k, v.round())),
    );

    // 1. Local pre-validation
    // final validator = SessionValidator();
    // final validation = validator.validateDailyReview(
    //   wins: review.wins,
    //   improvements: review.improvements,
    //   intention: review.tomorrowIntention,
    //   durationSeconds: ...,
    // );
    // if (!validation.accepted) { show issues; return; }

    // 2. Save via kernel locally (LINEAR — consumed once)
    // await kernel.createObject(typeName: 'DailyReview', data: review.toJson());
    // await kernel.consumeLinear(review.id);

    // 3. Submit to node for authoritative validation + streak credit
    // final result = await nodeClient.submitDailyReview(
    //   reviewId: review.id,
    //   data: review.toJson(),
    // );
    // if (!result.accepted) { show result.reason; return; }

    // 4. Node's Paskian graph updates automatically from the submission

    if (mounted) {
      _showCompletionDialog();
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Review complete',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF4ade80), size: 48),
            const SizedBox(height: 16),
            // TODO: Show Paskian insight here
            Text(
              'Rest well. Tomorrow is a fresh start.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done', style: TextStyle(color: Color(0xFF60a5fa))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f23),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Evening Review',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white54),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Progress indicator
          _buildProgressBar(),

          // Swipeable pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildWinsStep(),
                _buildImprovementsStep(),
                _buildDimensionsStep(),
                _buildIntentionStep(),
                _buildEnergyMoodStep(),
              ],
            ),
          ),

          // Navigation buttons
          _buildNavButtons(),
        ],
      ),
      // Voice input FAB
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleVoice,
        backgroundColor:
            _isListening ? const Color(0xFFef4444) : const Color(0xFF3b82f6),
        child: Icon(_isListening ? Icons.stop : Icons.mic),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: List.generate(5, (i) {
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: i <= _step
                    ? const Color(0xFF3b82f6)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildWinsStep() {
    return _buildListStep(
      title: 'What went well today?',
      subtitle: '3 wins — big or small',
      controllers: _winControllers,
      hints: [
        'First win...',
        'Second win...',
        'Third win...',
      ],
    );
  }

  Widget _buildImprovementsStep() {
    return _buildListStep(
      title: 'What could improve?',
      subtitle: 'Not judgment — awareness',
      controllers: _improvementControllers,
      hints: [
        'First improvement...',
        'Second improvement...',
        'Third improvement...',
      ],
    );
  }

  Widget _buildListStep({
    required String title,
    required String subtitle,
    required List<TextEditingController> controllers,
    required List<String> hints,
  }) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
          ),
          const SizedBox(height: 24),
          ...List.generate(3, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: controllers[i],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: hints[i],
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 40, minHeight: 0),
                ),
                maxLines: 2,
                textInputAction:
                    i < 2 ? TextInputAction.next : TextInputAction.done,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDimensionsStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How did each dimension feel?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Quick gut feeling — don\'t overthink',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: Dimension.values.map((dim) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          dim.emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          dim.label,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: const Color(0xFF3b82f6),
                            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                            thumbColor: const Color(0xFF3b82f6),
                            overlayColor: const Color(0xFF3b82f6).withValues(alpha: 0.2),
                            trackHeight: 4,
                          ),
                          child: Slider(
                            value: _dimensionScores[dim]!,
                            min: 1,
                            max: 10,
                            divisions: 9,
                            onChanged: (v) =>
                                setState(() => _dimensionScores[dim] = v),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        child: Text(
                          _dimensionScores[dim]!.round().toString(),
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntentionStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tomorrow\'s intention',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'One clear focus for tomorrow',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _intentionController,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              hintText: 'Tomorrow I will...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            maxLines: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildEnergyMoodStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How are you feeling?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 32),
          _buildMoodSlider(
            label: 'Energy',
            value: _energy,
            lowEmoji: '😴',
            highEmoji: '⚡',
            onChanged: (v) => setState(() => _energy = v),
          ),
          const SizedBox(height: 32),
          _buildMoodSlider(
            label: 'Mood',
            value: _mood,
            lowEmoji: '😔',
            highEmoji: '😊',
            onChanged: (v) => setState(() => _mood = v),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodSlider({
    required String label,
    required double value,
    required String lowEmoji,
    required String highEmoji,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(lowEmoji, style: const TextStyle(fontSize: 24)),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: const Color(0xFF3b82f6),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                  thumbColor: const Color(0xFF3b82f6),
                  overlayColor: const Color(0xFF3b82f6).withValues(alpha: 0.2),
                  trackHeight: 6,
                ),
                child: Slider(
                  value: value,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: onChanged,
                ),
              ),
            ),
            Text(highEmoji, style: const TextStyle(fontSize: 24)),
          ],
        ),
        Center(
          child: Text(
            value.round().toString(),
            style: const TextStyle(color: Colors.white54, fontSize: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildNavButtons() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          if (_step > 0)
            TextButton(
              onPressed: _previousStep,
              child: const Text('Back', style: TextStyle(color: Colors.white54)),
            ),
          const Spacer(),
          ElevatedButton(
            onPressed: _nextStep,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3b82f6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_step < 4 ? 'Next' : 'Save'),
          ),
        ],
      ),
    );
  }

  void _toggleVoice() {
    setState(() => _isListening = !_isListening);
    // TODO: Integrate speech_to_text
    // if (_isListening) {
    //   _speechToText.listen(onResult: (result) {
    //     // Route recognized text to the current active field
    //   });
    // } else {
    //   _speechToText.stop();
    // }
  }
}

```
