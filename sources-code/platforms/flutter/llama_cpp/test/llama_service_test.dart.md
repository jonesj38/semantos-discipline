---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/llama_cpp/test/llama_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.023963+00:00
---

# platforms/flutter/llama_cpp/test/llama_service_test.dart

```dart
// D-O5m.followup-3 Phase 2 — LlamaService + ModelManager tests.
//
// Reference: platforms/flutter/whisper_cpp/test/whisper_service_test.dart
//            (the Phase 1 sibling -- same structure, same fake-HTTP +
//            stub-bindings injection seams).
//
// Pure-Dart tests (no Flutter SDK required at unit-test time).  The
// bindings are stubbed via [LlamaBindingsBase] injection; the model
// manager's HTTP client is stubbed to stream a fixture body.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;
import 'package:llama_cpp/llama_cpp.dart';
import 'package:test/test.dart';

class _StubBindings extends LlamaBindingsBase {
  final List<String> calls = [];
  String? lastModelPath;
  String? lastPrompt;
  String? lastGrammar;
  int? lastMaxTokens;
  double? lastTemperature;
  String returnText;
  int openReturn;

  _StubBindings({
    this.returnText =
        '{"id":"i1","summary":"job 12345 invoiced","category":{"lexicon":"trades","category":"invoice"},"taxonomy":{"what":"jobs","how":"transition","why":"close-out"},"action":"transition","constraints":[],"confidence":0.92,"source":"voice"}',
    this.openReturn = 1,
  });

  @override
  int open(String modelPath) {
    calls.add('open:$modelPath');
    lastModelPath = modelPath;
    return openReturn;
  }

  @override
  String complete({
    required int handle,
    required String prompt,
    String? grammarBNF,
    int maxTokens = 512,
    double temperature = 0.0,
  }) {
    calls.add('complete:$handle:${prompt.length}:${grammarBNF?.length ?? 0}');
    lastPrompt = prompt;
    lastGrammar = grammarBNF;
    lastMaxTokens = maxTokens;
    lastTemperature = temperature;
    return returnText;
  }

  @override
  void close(int handle) {
    calls.add('close:$handle');
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

LlamaModelManager _mgrWithCachedFixture(Directory tmp, Uint8List body) {
  final hash = sha256
      .convert(body)
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final model = LlamaModel(
    name: 'test-stub',
    url: 'about:blank',
    sha256Hex: hash,
    approxBytes: body.length,
  );
  return LlamaModelManager(
    model: model,
    supportDirectory: () async => tmp,
  );
}

void main() {
  group('LlamaService.complete', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('llama-test-');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('completes happy path through stubbed bindings + grammar', () async {
      final fakeBytes =
          Uint8List.fromList(List<int>.generate(1024, (i) => i & 0xff));
      final mgr = _mgrWithCachedFixture(tmp, fakeBytes);
      final f = await mgr.resolveModelFile();
      f.writeAsBytesSync(fakeBytes);
      expect(await mgr.isCached(), isTrue);

      final stub = _StubBindings();
      final svc = LlamaService(modelManager: mgr, bindings: stub);

      final out = await svc.complete(
        prompt: 'extract intent: "job 12345 done invoiced"',
        grammarBNF: 'root ::= "{" .* "}"',
        maxTokens: 256,
        temperature: 0.0,
      );

      expect(out.startsWith('{'), isTrue);
      expect(stub.lastPrompt, contains('job 12345'));
      expect(stub.lastGrammar, contains('root'));
      expect(stub.lastMaxTokens, equals(256));
      expect(stub.lastTemperature, equals(0.0));
      // Calls happened in the right order.
      expect(stub.calls.first.startsWith('open:'), isTrue);
      expect(stub.calls.last.startsWith('close:'), isTrue);
    });

    test('rejects when model not cached', () async {
      final model = LlamaModel(
        name: 'test-stub-uncached',
        url: 'about:blank',
        sha256Hex: 'deadbeef' * 8,
        approxBytes: 1024,
      );
      final mgr = LlamaModelManager(
        model: model,
        supportDirectory: () async => tmp,
      );
      final svc = LlamaService(modelManager: mgr, bindings: _StubBindings());
      expect(
        () => svc.complete(prompt: 'hello'),
        throwsA(isA<LlamaCompletionError>()),
      );
    });

    test('null handle from bindings surfaces typed inferenceFailed', () async {
      final fakeBytes =
          Uint8List.fromList(List<int>.generate(64, (i) => i & 0xff));
      final mgr = _mgrWithCachedFixture(tmp, fakeBytes);
      final f = await mgr.resolveModelFile();
      f.writeAsBytesSync(fakeBytes);
      final svc = LlamaService(
        modelManager: mgr,
        bindings: _StubBindings(openReturn: 0),
      );
      expect(
        () => svc.complete(prompt: 'hi'),
        throwsA(isA<LlamaCompletionError>()),
      );
    });

    // 2026-05-07 — pins that injecting bindings keeps the call on the
    // current isolate (test stubs aren't sendable across isolates).
    // Production omits the bindings arg, which routes through
    // `Isolate.run` so multi-second llama.cpp inference doesn't
    // freeze the UI thread; the integration check for that path is
    // device-only because llama_open requires a real model + lib.
    test(
        'injected bindings stay on the current isolate (synchronous test path)',
        () async {
      final fakeBytes =
          Uint8List.fromList(List<int>.generate(64, (i) => i & 0xff));
      final mgr = _mgrWithCachedFixture(tmp, fakeBytes);
      final f = await mgr.resolveModelFile();
      f.writeAsBytesSync(fakeBytes);
      final stub = _StubBindings();
      final svc = LlamaService(modelManager: mgr, bindings: stub);
      await svc.complete(prompt: 'hi');
      // Stub state would be empty if the call had crossed an isolate
      // boundary (the new isolate would get a fresh LlamaBindings.open()
      // not our stub).
      expect(stub.calls, isNotEmpty);
      expect(stub.lastPrompt, equals('hi'));
    });
  });

  group('LlamaModelManager', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('llama-mm-'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('downloads and verifies a model on first use', () async {
      final body =
          Uint8List.fromList(List<int>.generate(2048, (i) => i & 0xff));
      final hash = sha256
          .convert(body)
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final model = LlamaModel(
        name: 'test-download',
        url: 'https://example.invalid/model.gguf',
        sha256Hex: hash,
        approxBytes: body.length,
      );
      final mgr = LlamaModelManager(
        model: model,
        supportDirectory: () async => tmp,
        clientFactory: () => _FakeHttpClient(body),
      );
      expect(await mgr.isCached(), isFalse);
      final progress = <LlamaModelDownloadProgress>[];
      final ok =
          await mgr.ensureModelDownloaded(onProgress: progress.add);
      expect(ok, isTrue);
      expect(await mgr.isCached(), isTrue);
      expect(progress, isNotEmpty);
      expect(progress.last.bytesReceived, equals(body.length));
    });

    test('rejects a corrupted download by SHA-256 mismatch', () async {
      final body =
          Uint8List.fromList(List<int>.generate(2048, (i) => i & 0xff));
      final model = LlamaModel(
        name: 'test-corrupt',
        url: 'https://example.invalid/model.gguf',
        sha256Hex: 'a' * 64,
        approxBytes: body.length,
      );
      final mgr = LlamaModelManager(
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
      final hash = sha256
          .convert(body)
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final model = LlamaModel(
        name: 'test-cached',
        url: 'about:blank',
        sha256Hex: hash,
        approxBytes: body.length,
      );
      final mgr = LlamaModelManager(
        model: model,
        supportDirectory: () async => tmp,
      );
      final f = await mgr.resolveModelFile();
      f.writeAsBytesSync(body);
      expect(await mgr.isCached(), isTrue);
    });

    test('clearCache removes the cached file', () async {
      final body = Uint8List.fromList([9, 9, 9]);
      final hash = sha256
          .convert(body)
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final model = LlamaModel(
        name: 'test-clear',
        url: 'about:blank',
        sha256Hex: hash,
        approxBytes: body.length,
      );
      final mgr = LlamaModelManager(
        model: model,
        supportDirectory: () async => tmp,
      );
      final f = await mgr.resolveModelFile();
      f.writeAsBytesSync(body);
      expect(await mgr.isCached(), isTrue);
      expect(await mgr.clearCache(), isTrue);
      expect(f.existsSync(), isFalse);
    });

    test('modelAvailable returns true for files at least half size', () async {
      // approxBytes 1000, file 600 bytes -- counts as available
      // (cheap check used to gate UI without paying SHA-256 cost).
      final body =
          Uint8List.fromList(List<int>.generate(600, (i) => i & 0xff));
      final model = LlamaModel(
        name: 'test-available',
        url: 'about:blank',
        sha256Hex: 'b' * 64,
        approxBytes: 1000,
      );
      final mgr = LlamaModelManager(
        model: model,
        supportDirectory: () async => tmp,
      );
      final f = await mgr.resolveModelFile();
      f.writeAsBytesSync(body);
      expect(await mgr.modelAvailable(), isTrue);
    });

    test('modelAvailable returns false for partial files', () async {
      // 100 bytes vs 1000 expected -- below the 50% threshold,
      // counts as a partial / corrupted download.
      final body =
          Uint8List.fromList(List<int>.generate(100, (i) => i & 0xff));
      final model = LlamaModel(
        name: 'test-partial',
        url: 'about:blank',
        sha256Hex: 'b' * 64,
        approxBytes: 1000,
      );
      final mgr = LlamaModelManager(
        model: model,
        supportDirectory: () async => tmp,
      );
      final f = await mgr.resolveModelFile();
      f.writeAsBytesSync(body);
      expect(await mgr.modelAvailable(), isFalse);
    });
  });
}

```
