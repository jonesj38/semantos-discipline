---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/test/whisper_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.019855+00:00
---

# platforms/flutter/whisper_cpp/test/whisper_service_test.dart

```dart
// D-O5m.followup-3 Phase 1 — WhisperService + ModelManager tests.
//
// Pure-Dart tests (no Flutter SDK required at unit-test time). The
// bindings are stubbed via [WhisperBindingsBase] injection; the model
// manager's HTTP client is stubbed to stream a fixture body.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:whisper_cpp/whisper_cpp.dart';

class _StubBindings extends WhisperBindingsBase {
  final List<String> calls = [];
  String? lastModelPath;
  List<double>? lastSamples;
  String? lastLanguage;
  String returnText;
  int initReturn;

  _StubBindings({this.returnText = 'job 12345 is invoiced', this.initReturn = 1});

  @override
  int initFromFile(String modelPath) {
    calls.add('init:$modelPath');
    lastModelPath = modelPath;
    return initReturn;
  }

  @override
  String runFull({
    required int ctxHandle,
    required List<double> samples,
    required String language,
  }) {
    calls.add('run:$ctxHandle:${samples.length}:$language');
    lastSamples = samples;
    lastLanguage = language;
    return returnText;
  }

  @override
  void free(int ctxHandle) {
    calls.add('free:$ctxHandle');
  }
}

class _FakeStreamedResponse extends http.BaseResponse
    implements http.StreamedResponse {
  @override
  final http.ByteStream stream;
  _FakeStreamedResponse(this.stream, int statusCode, int? contentLength)
      : super(statusCode, contentLength: contentLength);
}

class _FakeHttpClient extends http.BaseClient {
  final List<int> body;
  _FakeHttpClient(this.body);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = http.ByteStream.fromBytes(body);
    return _FakeStreamedResponse(stream, 200, body.length);
  }
}

void main() {
  group('WhisperService.transcribe', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('whisper-test-');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('transcribes happy path through stubbed bindings', () async {
      // Pre-populate the cache with a fake model file. The hash on
      // the WhisperModel doesn't matter for this test because we
      // bypass `isCached` by writing bytes that hash to a value we
      // record on a custom WhisperModel.
      final fakeBytes = Uint8List.fromList(List<int>.generate(1024, (i) => i & 0xff));
      final hash = sha256.convert(fakeBytes).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final model = WhisperModel(
        name: 'test-stub',
        url: 'about:blank',
        sha256Hex: hash,
        approxBytes: fakeBytes.length,
      );
      final mgr = WhisperModelManager(
        model: model,
        supportDirectory: () async => tmp,
      );
      final f = await mgr.resolveModelFile();
      f.writeAsBytesSync(fakeBytes);
      expect(await mgr.isCached(), isTrue);

      final stub = _StubBindings(returnText: 'job 12345 is invoiced');
      final svc = WhisperService(modelManager: mgr, bindings: stub);

      // Build 2 seconds of silent 16kHz 16-bit PCM (32000 samples * 2 bytes).
      final pcm = Uint8List(2 * 16000 * 2);
      final text = await svc.transcribe(pcm, language: 'en');

      expect(text, equals('job 12345 is invoiced'));
      expect(stub.lastLanguage, equals('en'));
      expect(stub.lastSamples!.length, equals(32000));
      // Calls happened in the right order.
      expect(stub.calls.first.startsWith('init:'), isTrue);
      expect(stub.calls.last.startsWith('free:'), isTrue);
    });

    test('rejects audio shorter than 1 second', () async {
      final fakeBytes = Uint8List.fromList(List<int>.generate(1024, (i) => i & 0xff));
      final hash = sha256.convert(fakeBytes).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final model = WhisperModel(
        name: 'test-stub',
        url: 'about:blank',
        sha256Hex: hash,
        approxBytes: fakeBytes.length,
      );
      final mgr = WhisperModelManager(
        model: model,
        supportDirectory: () async => tmp,
      );
      final f = await mgr.resolveModelFile();
      f.writeAsBytesSync(fakeBytes);
      final svc = WhisperService(modelManager: mgr, bindings: _StubBindings());
      expect(
        () => svc.transcribe(Uint8List(100)),
        throwsA(isA<WhisperTranscriptionError>()),
      );
    });

    test('rejects when model not cached', () async {
      // Use a model whose hash won't match anything we have on disk
      // (intentionally dud).
      final model = WhisperModel(
        name: 'test-stub-uncached',
        url: 'about:blank',
        sha256Hex: 'deadbeef' * 8,
        approxBytes: 1024,
      );
      final mgr = WhisperModelManager(
        model: model,
        supportDirectory: () async => tmp,
      );
      final svc = WhisperService(modelManager: mgr, bindings: _StubBindings());
      final pcm = Uint8List(2 * 16000 * 2);
      expect(
        () => svc.transcribe(pcm),
        throwsA(isA<WhisperTranscriptionError>()),
      );
    });
  });

  group('WhisperModelManager', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('whisper-mm-'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('downloads and verifies a model on first use', () async {
      final body = Uint8List.fromList(List<int>.generate(2048, (i) => i & 0xff));
      final hash = sha256.convert(body).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final model = WhisperModel(
        name: 'test-download',
        url: 'https://example.invalid/model.bin',
        sha256Hex: hash,
        approxBytes: body.length,
      );
      final mgr = WhisperModelManager(
        model: model,
        supportDirectory: () async => tmp,
        clientFactory: () => _FakeHttpClient(body),
      );
      expect(await mgr.isCached(), isFalse);
      final progressEvents = <WhisperModelDownloadProgress>[];
      final ok =
          await mgr.ensureModelDownloaded(onProgress: progressEvents.add);
      expect(ok, isTrue);
      expect(await mgr.isCached(), isTrue);
      expect(progressEvents, isNotEmpty);
      expect(progressEvents.last.bytesReceived, equals(body.length));
    });

    test('rejects a corrupted download by SHA-256 mismatch', () async {
      final body = Uint8List.fromList(List<int>.generate(2048, (i) => i & 0xff));
      final model = WhisperModel(
        name: 'test-corrupt',
        url: 'https://example.invalid/model.bin',
        // Deliberately wrong hash.
        sha256Hex: 'a' * 64,
        approxBytes: body.length,
      );
      final mgr = WhisperModelManager(
        model: model,
        supportDirectory: () async => tmp,
        clientFactory: () => _FakeHttpClient(body),
      );
      expect(
        () => mgr.ensureModelDownloaded(),
        throwsA(isA<StateError>()),
      );
      expect(await mgr.isCached(), isFalse);
    });

    test('isCached returns true when file is on disk and hash matches',
        () async {
      final body = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = sha256.convert(body).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final model = WhisperModel(
        name: 'test-cached',
        url: 'about:blank',
        sha256Hex: hash,
        approxBytes: body.length,
      );
      final mgr = WhisperModelManager(
        model: model,
        supportDirectory: () async => tmp,
      );
      final f = await mgr.resolveModelFile();
      f.writeAsBytesSync(body);
      expect(await mgr.isCached(), isTrue);
    });

    test('clearCache removes the cached file', () async {
      final body = Uint8List.fromList([9, 9, 9]);
      final hash = sha256.convert(body).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final model = WhisperModel(
        name: 'test-clear',
        url: 'about:blank',
        sha256Hex: hash,
        approxBytes: body.length,
      );
      final mgr = WhisperModelManager(
        model: model,
        supportDirectory: () async => tmp,
      );
      final f = await mgr.resolveModelFile();
      f.writeAsBytesSync(body);
      expect(await mgr.isCached(), isTrue);
      expect(await mgr.clearCache(), isTrue);
      expect(f.existsSync(), isFalse);
    });
  });
}

```
