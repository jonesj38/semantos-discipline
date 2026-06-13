---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/screens/morning_intention_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.749855+00:00
---

# archive/apps-navigation_app/lib/screens/morning_intention_screen.dart

```dart
import 'package:flutter/material.dart';
import '../models/semantic_types.dart';
import '../models/objects.dart';

/// Morning intention flow — set focus for the day.
/// Voice-first, 60 seconds max.
///
/// Flow:
/// 1. Show yesterday's intention + whether it was fulfilled
/// 2. "Which dimension are you focusing on today?" (tap or voice)
/// 3. "What's your intention?" (voice or text)
/// 4. "One concrete action?" (voice or text)
/// 5. Save → kernel creates as LINEAR
class MorningIntentionScreen extends StatefulWidget {
  const MorningIntentionScreen({super.key});

  @override
  State<MorningIntentionScreen> createState() => _MorningIntentionScreenState();
}

class _MorningIntentionScreenState extends State<MorningIntentionScreen> {
  int _step = 0;
  Dimension? _selectedDimension;
  final _intentionController = TextEditingController();
  final _actionController = TextEditingController();
  bool _yesterdayFulfilled = false;

  @override
  void dispose() {
    _intentionController.dispose();
    _actionController.dispose();
    super.dispose();
  }

  void _selectDimension(Dimension dim) {
    setState(() {
      _selectedDimension = dim;
      _step = 1;
    });
  }

  Future<void> _save() async {
    if (_selectedDimension == null) return;

    final intention = MorningIntention(
      focusDimension: _selectedDimension!.name,
      intention: _intentionController.text,
      concreteAction: _actionController.text,
      yesterdayReflection: _yesterdayFulfilled ? 'fulfilled' : 'not fulfilled',
    );

    // TODO: Save via kernel
    // TODO: Feed Paskian graph

    if (mounted) Navigator.of(context).pop(intention);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f23),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Good morning',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _step == 0 ? _buildDimensionPicker() : _buildIntentionForm(),
      ),
    );
  }

  Widget _buildDimensionPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Yesterday's review
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                _yesterdayFulfilled ? Icons.check_circle : Icons.circle_outlined,
                color: _yesterdayFulfilled
                    ? const Color(0xFF4ade80)
                    : Colors.white24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Yesterday: "Focus on physical health"',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _yesterdayFulfilled = !_yesterdayFulfilled),
                child: Text(
                  _yesterdayFulfilled ? 'Done' : 'Tap if done',
                  style: TextStyle(
                    color: _yesterdayFulfilled
                        ? const Color(0xFF4ade80)
                        : const Color(0xFF3b82f6),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        const Text(
          'What dimension today?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap the one calling you',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: 24),

        // Dimension grid
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: Dimension.values.map((dim) {
              final isSelected = _selectedDimension == dim;
              return GestureDetector(
                onTap: () => _selectDimension(dim),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF3b82f6).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF3b82f6)
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(dim.emoji, style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 4),
                      Text(
                        dim.label,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildIntentionForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected dimension chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF3b82f6).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_selectedDimension!.emoji} ${_selectedDimension!.label}',
            style: const TextStyle(color: Color(0xFF60a5fa)),
          ),
        ),
        const SizedBox(height: 24),

        const Text(
          'Your intention',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _intentionController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Today I will...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        const SizedBox(height: 24),

        const Text(
          'One concrete action',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _actionController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Specifically, I will...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          maxLines: 2,
        ),

        const Spacer(),

        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _step = 0),
              child: const Text('Back', style: TextStyle(color: Colors.white54)),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3b82f6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Set intention'),
            ),
          ],
        ),
      ],
    );
  }
}

```
