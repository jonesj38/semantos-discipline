---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/betterment_experience/lib/src/release_capture_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.448342+00:00
---

# packages/betterment_experience/lib/src/release_capture_screen.dart

```dart
/// `do | betterment | release` — the cartridge-owned capture surface.
///
/// Presented by the shell's modal verb shelf when the Release verb's manifest
/// `inputShape.kind == "custom"` resolves to the registered key
/// `betterment.release` (see [registerBettermentCartridge]). The shell stays
/// cartridge-neutral: it pushes this screen by manifest key and never imports
/// betterment.
///
/// Three input modes, accumulated as chronological [CapturedTurn]s:
///   - Text  — typed entry → one turn.
///   - Photo — camera/gallery → brain OCR (Claude vision) → one turn per page
///             paragraph (host.ocr).
///   - Voice — disabled this pass (on-device STT not yet wired).
///
/// On "Release" it mints a betterment.practice.release cell via the neutral
/// [CartridgeHost] (CartridgeHostScope), building a schema-valid payload:
/// strictly-increasing turn indices, source ∈ {text,ocr}, local-day key,
/// joined rawText.

import 'dart:io';

import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum _Mode { text, photo, voice }

class _Turn {
  final String text;
  final String? sourcePageRef;
  final bool fromOcr;
  final bool fromVoice;
  const _Turn(this.text,
      {this.sourcePageRef, this.fromOcr = false, this.fromVoice = false});
}

class ReleaseCaptureScreen extends StatefulWidget {
  const ReleaseCaptureScreen({super.key, ImagePicker? picker})
      : _picker = picker;

  /// Injectable for tests; defaults to a real ImagePicker.
  final ImagePicker? _picker;

  @override
  State<ReleaseCaptureScreen> createState() => _ReleaseCaptureScreenState();
}

class _ReleaseCaptureScreenState extends State<ReleaseCaptureScreen> {
  final _textController = TextEditingController();
  final List<_Turn> _turns = [];
  final AudioRecorder _recorder = AudioRecorder();
  _Mode _mode = _Mode.text;
  bool _busy = false;
  bool _recording = false;
  String? _error;

  ImagePicker get _picker => widget._picker ?? ImagePicker();

  @override
  void dispose() {
    _textController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  String _todayLocalIso() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  void _addTypedTurn() {
    final t = _textController.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _turns.add(_Turn(t));
      _textController.clear();
    });
  }

  Future<void> _capture(ImageSource source) async {
    final host = CartridgeHostScope.maybeOf(context);
    if (host == null || !host.isConnected) {
      setState(() => _error = 'Not connected to a brain.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2200,
      );
      if (file == null) {
        setState(() => _busy = false);
        return;
      }
      final bytes = await file.readAsBytes();
      final outcome = await host.ocr(
        images: [CaptureImage(bytes: bytes, mimeType: file.mimeType ?? 'image/jpeg')],
        day: _todayLocalIso(),
      );
      if (!mounted) return;
      switch (outcome) {
        case OcrOk(:final turns, :final rawText):
          setState(() {
            if (turns.isNotEmpty) {
              for (final t in turns) {
                _turns.add(_Turn(t.text,
                    sourcePageRef: t.sourcePageRef, fromOcr: true));
              }
            } else if (rawText.trim().isNotEmpty) {
              _turns.add(_Turn(rawText.trim(), fromOcr: true));
            }
            _busy = false;
          });
        case OcrErr(:final reason, :final statusCode):
          setState(() {
            _busy = false;
            _error = 'OCR failed: $reason'
                '${statusCode != 0 ? ' ($statusCode)' : ''}';
          });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Capture failed: $e';
      });
    }
  }

  Future<void> _toggleRecording() async {
    final host = CartridgeHostScope.maybeOf(context);
    if (host == null || !host.canTranscribe) {
      setState(() => _error = 'Voice transcription unavailable on this device.');
      return;
    }
    if (_recording) {
      setState(() {
        _recording = false;
        _busy = true;
        _error = null;
      });
      try {
        final path = await _recorder.stop();
        if (path == null) {
          setState(() => _busy = false);
          return;
        }
        final bytes = await File(path).readAsBytes();
        try {
          await File(path).delete();
        } catch (_) {}
        final outcome = await host.transcribe(audioBytes: bytes);
        if (!mounted) return;
        switch (outcome) {
          case TranscribeOk(:final turns, :final transcript):
            setState(() {
              if (turns.isNotEmpty) {
                for (final t in turns) {
                  _turns.add(_Turn(t.text, fromVoice: true));
                }
              } else if (transcript.trim().isNotEmpty) {
                _turns.add(_Turn(transcript.trim(), fromVoice: true));
              }
              _busy = false;
            });
          case TranscribeErr(:final reason):
            setState(() {
              _busy = false;
              _error = 'Transcription failed: $reason';
            });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'Recording failed: $e';
        });
      }
    } else {
      if (!await _recorder.hasPermission()) {
        setState(() => _error = 'Microphone permission denied.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/release-${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _error = null;
      });
    }
  }

  Future<void> _release() async {
    final host = CartridgeHostScope.maybeOf(context);
    if (host == null || !host.isConnected) {
      setState(() => _error = 'Not connected to a brain.');
      return;
    }
    if (_turns.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    // Single source enum: voice wins, then OCR, else typed.
    final source = _turns.any((t) => t.fromVoice)
        ? 'voice_transcript'
        : _turns.any((t) => t.fromOcr)
            ? 'ocr'
            : 'text';
    final turnsPayload = <Map<String, dynamic>>[
      for (var i = 0; i < _turns.length; i++)
        {
          'index': i,
          'speaker': 'self',
          'text': _turns[i].text,
          if (_turns[i].sourcePageRef != null)
            'sourcePageRef': _turns[i].sourcePageRef,
        },
    ];
    final payload = <String, dynamic>{
      'source': source,
      'prompt': 'freeform',
      'day': _todayLocalIso(),
      'elevation': 5,
      'rawText': _turns.map((t) => t.text).join('\n\n'),
      'turns': turnsPayload,
    };

    final outcome = await host.mint(
      triple: const ['betterment', 'practice', 'release', ''],
      payload: payload,
    );
    if (!mounted) return;
    switch (outcome) {
      case MintOk(:final cellId):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Released · ${_short(cellId)}')),
        );
        Navigator.of(context).pop();
      case MintErr(:final message):
        setState(() {
          _busy = false;
          _error = 'Release failed: $message';
        });
    }
  }

  static String _short(String id) =>
      id.length > 12 ? '${id.substring(0, 12)}…' : id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Release')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_Mode>(
                segments: const [
                  ButtonSegment(
                      value: _Mode.text,
                      icon: Icon(Icons.keyboard),
                      label: Text('Text')),
                  ButtonSegment(
                      value: _Mode.photo,
                      icon: Icon(Icons.photo_camera),
                      label: Text('Photo')),
                  ButtonSegment(
                      value: _Mode.voice,
                      icon: Icon(Icons.mic),
                      label: Text('Voice')),
                ],
                selected: {_mode},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildModeBody(theme)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 8),
              _buildTurnSummary(theme),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: (_busy || _turns.isEmpty) ? null : _release,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.flash_on),
                label: Text(_turns.isEmpty
                    ? 'Release'
                    : 'Release (${_turns.length} ${_turns.length == 1 ? 'turn' : 'turns'})'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeBody(ThemeData theme) {
    switch (_mode) {
      case _Mode.text:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                enabled: !_busy,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "I'm letting go of…",
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _addTypedTurn,
              icon: const Icon(Icons.add),
              label: const Text('Add to release'),
            ),
          ],
        );
      case _Mode.photo:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Photograph a handwritten page — it’s transcribed for you.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : () => _capture(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed:
                        _busy ? null : () => _capture(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Transcribing…'),
              ],
            ],
          ),
        );
      case _Mode.voice:
        final host = CartridgeHostScope.maybeOf(context);
        final canVoice = host?.canTranscribe ?? false;
        if (!canVoice) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_off, color: theme.disabledColor, size: 40),
                const SizedBox(height: 8),
                Text('Voice transcription unavailable on this device',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.disabledColor)),
              ],
            ),
          );
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _recording
                    ? 'Recording… speak your release, then stop.'
                    : 'Record a voice note — it’s transcribed on-device.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (_busy && !_recording) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Transcribing…'),
              ] else
                FilledButton.icon(
                  onPressed: _busy ? null : _toggleRecording,
                  icon: Icon(_recording ? Icons.stop : Icons.mic),
                  style: _recording
                      ? FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error)
                      : null,
                  label: Text(_recording ? 'Stop' : 'Record'),
                ),
              const SizedBox(height: 8),
              Text('Transcribed on the brain (whisper).',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        );
    }
  }

  Widget _buildTurnSummary(ThemeData theme) {
    if (_turns.isEmpty) {
      return Text('No turns captured yet.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    }
    final ocrCount = _turns.where((t) => t.fromOcr).length;
    final voiceCount = _turns.where((t) => t.fromVoice).length;
    return Text(
      '${_turns.length} turn${_turns.length == 1 ? '' : 's'}'
      '${ocrCount > 0 ? ' · $ocrCount from OCR' : ''}'
      '${voiceCount > 0 ? ' · $voiceCount from voice' : ''}',
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

```
