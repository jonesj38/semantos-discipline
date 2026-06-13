---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/betterment_experience/test/release_capture_screen_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.447704+00:00
---

# packages/betterment_experience/test/release_capture_screen_test.dart

```dart
// Widget test for the betterment release capture screen (text mode).
//
// Drives the screen through a fake CartridgeHost and asserts the minted payload
// is schema-valid for betterment.practice.release: correct triple, source=text,
// strictly-indexed self-turns, joined rawText, and a YYYY-MM-DD day. The photo
// path needs ImagePicker (platform) and is exercised on the emulator, not here.

import 'package:betterment_experience/betterment_experience.dart';
import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHost implements CartridgeHost {
  List<String>? lastTriple;
  Map<String, dynamic>? lastPayload;

  @override
  bool get isConnected => true;

  @override
  Future<MintOutcome> mint({
    required List<String> triple,
    required Map<String, dynamic> payload,
  }) async {
    lastTriple = triple;
    lastPayload = payload;
    return const MintOk('abc123def456abc123def456abc123def456abc123def456abc123def456abcd');
  }

  @override
  Future<OcrOutcome> ocr({required List<CaptureImage> images, String? day}) async =>
      const OcrOk(turns: [], rawText: '');

  bool canTranscribeValue = false;

  @override
  bool get canTranscribe => canTranscribeValue;

  @override
  Future<TranscribeOutcome> transcribe({required List<int> audioBytes}) async =>
      const TranscribeOk(turns: [], transcript: '');
}

Future<void> _openScreen(WidgetTester tester, CartridgeHost host) async {
  await tester.pumpWidget(
    CartridgeHostScope(
      host: host,
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReleaseCaptureScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('text mode assembles a schema-valid release payload', (tester) async {
    final host = _FakeHost();
    await _openScreen(tester, host);

    await tester.enterText(find.byType(TextField), 'I release the tension');
    await tester.tap(find.text('Add to release'));
    await tester.pump();

    await tester.tap(find.text('Release (1 turn)'));
    await tester.pumpAndSettle();

    expect(host.lastTriple, ['betterment', 'practice', 'release', '']);
    final p = host.lastPayload!;
    expect(p['source'], 'text');
    expect(p['prompt'], 'freeform');
    expect(p['rawText'], 'I release the tension');
    expect(p['day'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    final turns = p['turns'] as List;
    expect(turns, hasLength(1));
    expect(turns.first['index'], 0);
    expect(turns.first['speaker'], 'self');
    expect(turns.first['text'], 'I release the tension');
  });

  testWidgets('Release is disabled until a turn is captured', (tester) async {
    final host = _FakeHost();
    await _openScreen(tester, host);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Release'),
    );
    expect(button.onPressed, isNull);
    expect(host.lastPayload, isNull);
  });

  testWidgets('Voice tab shows unavailable when the host cannot transcribe',
      (tester) async {
    final host = _FakeHost()..canTranscribeValue = false;
    await _openScreen(tester, host);
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    expect(find.textContaining('unavailable'), findsOneWidget);
  });

  testWidgets('Voice tab shows a Record button when transcription is available',
      (tester) async {
    final host = _FakeHost()..canTranscribeValue = true;
    await _openScreen(tester, host);
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Record'), findsOneWidget);
  });

  testWidgets('multiple typed turns get strictly increasing indices', (tester) async {
    final host = _FakeHost();
    await _openScreen(tester, host);

    await tester.enterText(find.byType(TextField), 'first');
    await tester.tap(find.text('Add to release'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'second');
    await tester.tap(find.text('Add to release'));
    await tester.pump();

    await tester.tap(find.text('Release (2 turns)'));
    await tester.pumpAndSettle();

    final turns = host.lastPayload!['turns'] as List;
    expect(turns.map((t) => t['index']).toList(), [0, 1]);
    expect(turns.map((t) => t['text']).toList(), ['first', 'second']);
    expect(host.lastPayload!['rawText'], 'first\n\nsecond');
  });
}

```
