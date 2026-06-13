---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/shell/shell_cartridge_host_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.132822+00:00
---

# apps/semantos/test/shell/shell_cartridge_host_test.dart

```dart
// Tests the BYOK read→send path of ShellCartridgeHost.ocr: it reads the
// operator's stored Anthropic key + model from the IdentityStore and passes
// them to the uploader per request (empty/absent → null, brain uses its key).

import 'dart:typed_data';

import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/shell/shell_cartridge_host.dart';
import 'package:semantos/src/ocr/image_extract_uploader.dart';
import 'package:semantos_core/semantos_core.dart' show IdentityStore;

class _MemIdentityStore implements IdentityStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
  @override
  bool get isHardwareBacked => false;
}

class _CapturingUploader implements ImageExtractUploader {
  String? lastApiKey;
  String? lastModel;
  bool called = false;

  @override
  Future<ImageExtractResult> upload({
    required List<OcrImage> images,
    ImageExtractMetadata? metadata,
    String? apiKey,
    String? model,
  }) async {
    called = true;
    lastApiKey = apiKey;
    lastModel = model;
    return const ImageExtractSuccess(turns: [], rawText: '', pageCount: 1);
  }
}

CaptureImage _img() =>
    CaptureImage(bytes: Uint8List(8), mimeType: 'image/jpeg');

void main() {
  test('passes stored BYOK key + model to the uploader', () async {
    final store = _MemIdentityStore();
    await store.write(kByokAnthropicKeySlot, 'sk-byok-abc');
    await store.write(kByokModelSlot, 'claude-opus-4-1');
    final up = _CapturingUploader();
    final host = ShellCartridgeHost(ocr: up, identity: store);

    await host.ocr(images: [_img()], day: '2026-06-11');

    expect(up.called, isTrue);
    expect(up.lastApiKey, 'sk-byok-abc');
    expect(up.lastModel, 'claude-opus-4-1');
  });

  test('passes null when no BYOK key is stored', () async {
    final store = _MemIdentityStore();
    final up = _CapturingUploader();
    final host = ShellCartridgeHost(ocr: up, identity: store);

    await host.ocr(images: [_img()]);

    expect(up.lastApiKey, isNull);
    expect(up.lastModel, isNull);
  });

  test('treats an empty stored key as null', () async {
    final store = _MemIdentityStore();
    await store.write(kByokAnthropicKeySlot, '');
    final up = _CapturingUploader();
    final host = ShellCartridgeHost(ocr: up, identity: store);

    await host.ocr(images: [_img()]);

    expect(up.lastApiKey, isNull);
  });

  group('transcribe', () {
    test('no transcriber → not available + TranscribeErr', () async {
      const host = ShellCartridgeHost();
      expect(host.canTranscribe, isFalse);
      final out = await host.transcribe(audioBytes: [1, 2, 3]);
      expect(out, isA<TranscribeErr>());
    });

    test('segments transcript into self-turns on blank lines', () async {
      final host = ShellCartridgeHost(
        transcriber: (bytes) async => 'first thought\n\nsecond thought',
      );
      expect(host.canTranscribe, isTrue);
      final out = await host.transcribe(audioBytes: [0, 0]);
      expect(out, isA<TranscribeOk>());
      final ok = out as TranscribeOk;
      expect(ok.transcript, 'first thought\n\nsecond thought');
      expect(ok.turns.map((t) => t.text).toList(),
          ['first thought', 'second thought']);
      expect(ok.turns.every((t) => t.speaker == 'self'), isTrue);
      expect(ok.turns.map((t) => t.index).toList(), [0, 1]);
    });

    test('a single-paragraph note is one turn', () async {
      final host = ShellCartridgeHost(
        transcriber: (bytes) async => 'one continuous spoken release',
      );
      final ok = await host.transcribe(audioBytes: [0]) as TranscribeOk;
      expect(ok.turns, hasLength(1));
      expect(ok.turns.first.text, 'one continuous spoken release');
    });

    test('empty transcript → TranscribeErr', () async {
      final host = ShellCartridgeHost(transcriber: (bytes) async => '   ');
      final out = await host.transcribe(audioBytes: [0]);
      expect(out, isA<TranscribeErr>());
    });

    test('transcriber throwing → TranscribeErr', () async {
      final host = ShellCartridgeHost(
        transcriber: (bytes) async => throw StateError('whisper boom'),
      );
      final out = await host.transcribe(audioBytes: [0]);
      expect(out, isA<TranscribeErr>());
    });
  });
}

```
