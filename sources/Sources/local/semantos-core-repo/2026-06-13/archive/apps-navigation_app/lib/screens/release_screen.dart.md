---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/screens/release_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.751076+00:00
---

# archive/apps-navigation_app/lib/screens/release_screen.dart

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/semantic_types.dart';

/// Stream-of-consciousness writing release.
/// Voice-first, timer running, prompts to get started.
/// The writing is LINEAR — once you release it, it's consumed.
class ReleaseScreen extends StatefulWidget {
  const ReleaseScreen({super.key});

  @override
  State<ReleaseScreen> createState() => _ReleaseScreenState();
}

class _ReleaseScreenState extends State<ReleaseScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  // Timer
  Timer? _timer;
  int _seconds = 0;
  bool _isRunning = false;

  // State
  bool _isListening = false;
  bool _released = false;
  int _wordCount = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateWordCount);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateWordCount() {
    final words = _controller.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    if (words != _wordCount) {
      setState(() => _wordCount = words);
    }

    // Auto-start timer on first keystroke
    if (!_isRunning && _controller.text.isNotEmpty) {
      _startTimer();
    }
  }

  void _startTimer() {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() => _isRunning = false);
  }

  String get _timerText {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _insertPrompt(String prompt) {
    final text = _controller.text;
    final selection = _controller.selection;
    final insertAt = selection.isValid ? selection.baseOffset : text.length;

    final prefix = text.isEmpty || text.endsWith('\n') ? '' : '\n';
    final newText = '$prefix$prompt ';

    _controller.text = text.substring(0, insertAt) +
        newText +
        text.substring(insertAt);
    _controller.selection = TextSelection.collapsed(
      offset: insertAt + newText.length,
    );
    _focusNode.requestFocus();
  }

  Future<void> _release() async {
    if (_controller.text.trim().isEmpty) return;

    _pauseTimer();

    // Show confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Release this writing?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Once released, it\'s consumed — gone. '
          'The kernel extracts insights and patterns, '
          'then the raw text is let go.\n\n'
          '$_wordCount words in $_timerText',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep writing',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFef4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('Release'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      if (_controller.text.isNotEmpty) _startTimer();
      return;
    }

    // TODO: Create Release object via kernel
    // TODO: Submit to node for pattern extraction
    // TODO: Kernel consumes (LINEAR — gone)

    setState(() => _released = true);

    // Show release animation then reset
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _controller.clear();
        _seconds = 0;
        _wordCount = 0;
        _released = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_released) return _buildReleaseAnimation();

    return Scaffold(
      backgroundColor: const Color(0xFF0f0f23),
      body: SafeArea(
        child: Column(
          children: [
            // Header with timer
            _buildHeader(),

            // Prompt chips
            _buildPrompts(),

            // Writing area
            Expanded(child: _buildWritingArea()),

            // Bottom bar
            _buildBottomBar(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _isListening = !_isListening),
        backgroundColor:
            _isListening ? const Color(0xFFef4444) : const Color(0xFF3b82f6),
        child: Icon(_isListening ? Icons.stop : Icons.mic, size: 28),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          const Text(
            'Release',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _isRunning
                  ? const Color(0xFF3b82f6).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(
                  _isRunning ? Icons.fiber_manual_record : Icons.timer_outlined,
                  size: 10,
                  color: _isRunning
                      ? const Color(0xFFef4444)
                      : Colors.white38,
                ),
                const SizedBox(width: 6),
                Text(
                  _timerText,
                  style: TextStyle(
                    color: _isRunning ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrompts() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _promptChip('I feel...'),
            _promptChip('I release...'),
            _promptChip('I am...'),
            _promptChip('I choose...'),
            _promptChip('I notice...'),
            _promptChip('What if...'),
          ],
        ),
      ),
    );
  }

  Widget _promptChip(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _insertPrompt(text),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Text(
            text,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildWritingArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          height: 1.7,
        ),
        decoration: InputDecoration(
          hintText: 'Let it flow...\n\nWrite without judgment. '
              'Keep the pen moving. '
              'Tap a prompt above if you need a starting point.',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.2),
            height: 1.7,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 80, 16), // 80 right for FAB
      child: Row(
        children: [
          Text(
            '$_wordCount words',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
          ),
          const Spacer(),
          if (_controller.text.trim().isNotEmpty)
            ElevatedButton.icon(
              onPressed: _release,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Release'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFef4444).withValues(alpha: 0.8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReleaseAnimation() {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f23),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.air,
              size: 64,
              color: Color(0xFF3b82f6),
            ),
            const SizedBox(height: 24),
            Text(
              'Released',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 24,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_wordCount words in $_timerText — let go',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

```
