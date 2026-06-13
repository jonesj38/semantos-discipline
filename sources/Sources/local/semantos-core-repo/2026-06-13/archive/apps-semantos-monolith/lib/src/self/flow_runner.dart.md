---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/self/flow_runner.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.868686+00:00
---

# archive/apps-semantos-monolith/lib/src/self/flow_runner.dart

```dart
// T7.b — FlowRunner: templated widget that drives any FlowDef.
//
// Per Q17 resolution: one widget renders all 12 self-practice flows
// (currently 3 shipped in v0.1.0).  Adding a flow = constants edit
// in flow_def.dart, no new screen.
//
// UX: a conversation-style stack of cards.  Each step prompts, captures
// input via an appropriate widget (TextField for longText/shortText,
// ChoiceChips for enumChoice — photo capture is a TODO), and advances
// on submit.  Optional steps show a "Skip" button.  At the final step,
// `onSubmit` fires with the collected field map; the caller mints the
// resulting self.* cell via the brain.
//
// Theme integration deferred to the parent (SelfNode passes a Theme
// scoped to the self cartridge's palette per cartridge.json
// `theme.colors`).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'flow_def.dart';

/// Callback fired when the flow completes — caller mints the cell.
typedef FlowSubmit = void Function(FlowDef flow, Map<String, String> fields);

class FlowRunner extends StatefulWidget {
  final FlowDef flow;
  final FlowSubmit onSubmit;

  /// Optional cancel callback — if provided, an X button appears in the
  /// app bar.  Caller decides what to do (typically pop back to chooser).
  final VoidCallback? onCancel;

  const FlowRunner({
    super.key,
    required this.flow,
    required this.onSubmit,
    this.onCancel,
  });

  @override
  State<FlowRunner> createState() => _FlowRunnerState();
}

class _FlowRunnerState extends State<FlowRunner> {
  /// Current step index (0..steps.length).  When equal to steps.length,
  /// the flow is complete and we render a confirmation.
  int _index = 0;

  /// Collected field values, keyed by step.field.
  final Map<String, String> _fields = {};

  /// Per-step text controller (for longText / shortText).  Created
  /// lazily on first build of each step.
  final Map<int, TextEditingController> _controllers = {};

  /// Per-step enum selection (for enumChoice).
  final Map<int, String> _enumSelections = {};

  /// Per-step image picker result (path or URI).  Held separately
  /// from `_fields` so we can preview it before advancing.
  final Map<int, String> _photoPaths = {};

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  FlowStep get _currentStep => widget.flow.steps[_index];
  bool get _isLastStep => _index == widget.flow.steps.length - 1;
  bool get _isComplete => _index >= widget.flow.steps.length;

  TextEditingController _controllerFor(int index) {
    return _controllers.putIfAbsent(index, () => TextEditingController());
  }

  bool _stepHasValue(int index) {
    final step = widget.flow.steps[index];
    switch (step.kind) {
      case FlowFieldKind.longText:
      case FlowFieldKind.shortText:
        return _controllers[index]?.text.trim().isNotEmpty ?? false;
      case FlowFieldKind.enumChoice:
        return _enumSelections[index] != null;
      case FlowFieldKind.photo:
        return _photoPaths[index]?.isNotEmpty ?? false;
    }
  }

  void _captureCurrentStep() {
    final step = _currentStep;
    switch (step.kind) {
      case FlowFieldKind.longText:
      case FlowFieldKind.shortText:
        final text = _controllers[_index]?.text.trim() ?? '';
        if (text.isNotEmpty) {
          _fields[step.field] = text;
        }
        break;
      case FlowFieldKind.enumChoice:
        final sel = _enumSelections[_index];
        if (sel != null) {
          _fields[step.field] = sel;
        }
        break;
      case FlowFieldKind.photo:
        final path = _photoPaths[_index];
        if (path != null && path.isNotEmpty) {
          _fields[step.field] = path;
        }
        break;
    }
  }

  Future<void> _capturePhoto(int index, ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 88,
      );
      if (picked == null) return; // user cancelled
      if (!mounted) return;
      setState(() {
        _photoPaths[index] = picked.path;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not capture photo: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _advance() {
    _captureCurrentStep();
    setState(() {
      _index += 1;
    });
    if (_isComplete) {
      widget.onSubmit(widget.flow, Map.unmodifiable(_fields));
    }
  }

  void _skip() {
    if (_currentStep.required) return;
    setState(() {
      _index += 1;
    });
    if (_isComplete) {
      widget.onSubmit(widget.flow, Map.unmodifiable(_fields));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.flow.name),
        leading: widget.onCancel != null
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onCancel,
              )
            : null,
      ),
      body: SafeArea(
        child: _isComplete
            ? _buildCompleteBanner(theme)
            : _buildStep(theme, _index, _currentStep),
      ),
    );
  }

  Widget _buildCompleteBanner(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Sealed.',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Minting ${widget.flow.onComplete.cellTypeName}…',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(ThemeData theme, int index, FlowStep step) {
    final progress = (index + 1) / widget.flow.steps.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: progress),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Step ${index + 1} of ${widget.flow.steps.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  step.prompt,
                  style: theme.textTheme.titleMedium,
                ),
                if (!step.required) ...[
                  const SizedBox(height: 4),
                  Text(
                    '(optional)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _buildInput(theme, index, step),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!step.required)
                TextButton(
                  onPressed: _skip,
                  child: const Text('Skip'),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: (_stepHasValue(index) || !step.required) ? _advance : null,
                icon: Icon(_isLastStep ? Icons.check : Icons.arrow_forward),
                label: Text(_isLastStep ? 'Complete' : 'Next'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInput(ThemeData theme, int index, FlowStep step) {
    switch (step.kind) {
      case FlowFieldKind.longText:
        return TextField(
          controller: _controllerFor(index),
          autofocus: true,
          maxLines: 8,
          minLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Write here…',
          ),
          onChanged: (_) => setState(() {}),
        );
      case FlowFieldKind.shortText:
        return TextField(
          controller: _controllerFor(index),
          autofocus: true,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _stepHasValue(index) ? _advance() : null,
        );
      case FlowFieldKind.enumChoice:
        final choices = step.enumChoices ?? [];
        final selected = _enumSelections[index];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: choices.map((c) {
            return ChoiceChip(
              label: Text(c),
              selected: selected == c,
              onSelected: (v) {
                setState(() {
                  _enumSelections[index] = v ? c : (selected ?? '');
                  if (!v && selected == c) _enumSelections.remove(index);
                });
              },
            );
          }).toList(),
        );
      case FlowFieldKind.photo:
        final path = _photoPaths[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (path != null) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not preview image at $path',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(path == null ? 'Take photo' : 'Retake'),
                    onPressed: () => _capturePhoto(index, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose'),
                    onPressed: () => _capturePhoto(index, ImageSource.gallery),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }
}

```
