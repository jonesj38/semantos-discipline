---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/voice/voice_command_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.910135+00:00
---

# archive/apps-semantos-monolith/test/voice/voice_command_service_test.dart

```dart
// D-O5m.followup-3 Phase 1 — voice_command_service unit tests.
//
// Asserts the orchestrator wires record → transcribe → sign correctly
// when all three pieces are mocked at their seams.  Specifically:
//   - happy path returns a VoiceCommandReady carrying a signed
//     Transcript whose `keyId` equals the cert binding,
//   - empty transcript surfaces VoiceCommandTranscriptionFailed,
//   - missing cert (no pairing) surfaces VoiceCommandNotPaired,
//   - transcriber exception surfaces VoiceCommandTranscriptionFailed.

import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:semantos/src/identity/child_cert_store.dart';
import 'package:semantos/src/voice/sir_extractor.dart';
import 'package:semantos/src/voice/voice_command_service.dart';
import 'package:semantos/src/voice/voice_session_service.dart';

class _FakeTranscriber implements VoiceTranscriber {
  String returns;
  bool throws;
  _FakeTranscriber({this.returns = 'job 12345 is invoiced', this.throws = false});

  @override
  Future<String> transcribe(Uint8List bytes, {String language = 'en'}) async {
    if (throws) throw StateError('forced failure');
    return returns;
  }
}

const _validIntentJson = '''
{
  "id": "i-001",
  "summary": "job 12345 is invoiced",
  "category": {"lexicon": "trades", "category": "invoice"},
  "taxonomy": {"what": "jobs", "how": "transition", "why": "close-out"},
  "action": "invoice",
  "constraints": [],
  "confidence": 0.85,
  "source": "voice"
}
''';

class _FakeCompleter implements LlmCompleter {
  final String returns;
  bool throws;
  _FakeCompleter({this.returns = _validIntentJson, this.throws = false});

  @override
  Future<String> complete({
    required String prompt,
    String? grammarBNF,
    int maxTokens = 512,
    double temperature = 0.0,
  }) async {
    if (throws) throw StateError('forced failure');
    return returns;
  }
}

final _hat = HatContext(
  hatId: 'operator',
  certId: 'a' * 64,
  extensionId: 'oddjobz',
  capabilities: const [0x00010101],
);

const _privHex =
    '5ad0e1ff96b4ef3df1ad34e5b97c4c1d8a5fe24ed18793e89d96d4d2e1abf001';
const _childPubHex =
    '03311ca3e2bacb244e50339b61d4652bba16d55fccf2fe33af73827b3745b17098';

Future<ChildCertStore> _makePairedStore() async {
  final store = ChildCertStore(InMemorySecureStore());
  await store.write(ChildCertRecord(
    devicePrivHex: _privHex,
    childPubHex: _childPubHex,
    operatorRootPub: _childPubHex,
    operatorCertId: 'a' * 32,
    contextTag: 1,
    label: 'test',
    capabilities: const ['cap.voice.command'],
    brainPairEndpoint: 'https://brain.local',
    brainWssEndpoint: 'wss://brain.local',
    brainPinCertId: 'a' * 32,
    brainPinPubkey: _childPubHex,
    bearer: 'b' * 64,
  ));
  return store;
}

void main() {
  group('VoiceCommandService.processRecording', () {
    test('happy path returns a signed Transcript', () async {
      final store = await _makePairedStore();
      final svc = VoiceCommandService(
        certStore: store,
        transcriber: _FakeTranscriber(),
      );
      final outcome = await svc.processRecording(
        recordedBytes: Uint8List.fromList(List.filled(64000, 0)),
        mimeType: 'audio/wav',
        durationMs: 2000,
      );
      expect(outcome, isA<VoiceCommandReady>());
      final ready = outcome as VoiceCommandReady;
      expect(ready.recording.transcript.text,
          equals('job 12345 is invoiced'));
      expect(ready.recording.transcript.signature.bytes.length, equals(64));
      expect(ready.recording.transcript.signature.keyId,
          equals(ready.recording.transcript.certId));
    });

    test('empty transcript text surfaces transcription failed', () async {
      final store = await _makePairedStore();
      final svc = VoiceCommandService(
        certStore: store,
        transcriber: _FakeTranscriber(returns: '   '),
      );
      final outcome = await svc.processRecording(
        recordedBytes: Uint8List.fromList(List.filled(32000, 0)),
        mimeType: 'audio/wav',
        durationMs: 1000,
      );
      expect(outcome, isA<VoiceCommandFailed>());
      final f = (outcome as VoiceCommandFailed).failure;
      expect(f, isA<VoiceCommandTranscriptionFailed>());
    });

    test('missing pairing record surfaces not paired', () async {
      final store = ChildCertStore(InMemorySecureStore());
      final svc = VoiceCommandService(
        certStore: store,
        transcriber: _FakeTranscriber(),
      );
      final outcome = await svc.processRecording(
        recordedBytes: Uint8List.fromList(List.filled(32000, 0)),
        mimeType: 'audio/wav',
        durationMs: 1000,
      );
      expect(outcome, isA<VoiceCommandFailed>());
      expect((outcome as VoiceCommandFailed).failure,
          isA<VoiceCommandNotPaired>());
    });

    test('transcriber exception surfaces typed failure', () async {
      final store = await _makePairedStore();
      final svc = VoiceCommandService(
        certStore: store,
        transcriber: _FakeTranscriber(throws: true),
      );
      final outcome = await svc.processRecording(
        recordedBytes: Uint8List.fromList(List.filled(32000, 0)),
        mimeType: 'audio/wav',
        durationMs: 1000,
      );
      expect(outcome, isA<VoiceCommandFailed>());
      final f = (outcome as VoiceCommandFailed).failure;
      expect(f, isA<VoiceCommandTranscriptionFailed>());
    });

    test('signed transcript verifies under verifyTranscript', () async {
      final store = await _makePairedStore();
      final svc = VoiceCommandService(
        certStore: store,
        transcriber: _FakeTranscriber(),
      );
      final outcome = await svc.processRecording(
        recordedBytes: Uint8List.fromList(List.filled(32000, 0)),
        mimeType: 'audio/wav',
        durationMs: 1000,
      ) as VoiceCommandReady;
      // Pull the device pubkey from the cert binding.
      final pub = Uint8List.fromList(List<int>.generate(33, (i) {
        final s = _childPubHex.substring(i * 2, i * 2 + 2);
        return int.parse(s, radix: 16);
      }));
      expect(verifyTranscript(outcome.recording.transcript, pub), isTrue);
    });

    // ── Phase 2 — on-device L1 SIR extraction ─────────────────────────

    test('Phase 2: on-device extraction success surfaces sir candidate',
        () async {
      final store = await _makePairedStore();
      final extractor = SirExtractor(
        completer: _FakeCompleter(),
        intentGrammarBNF: 'root ::= "{" .* "}"',
      );
      final svc = VoiceCommandService(
        certStore: store,
        transcriber: _FakeTranscriber(),
        sirExtractor: extractor,
        hatContext: _hat,
      );
      final outcome = await svc.processRecording(
        recordedBytes: Uint8List.fromList(List.filled(32000, 0)),
        mimeType: 'audio/wav',
        durationMs: 1000,
      ) as VoiceCommandReady;
      expect(outcome.recording.sirExtractionResult,
          isA<SirExtractionSuccess>());
      expect(outcome.recording.sirCandidate, isNotNull);
      expect(outcome.recording.sirCandidate!['action'], equals('invoice'));
    });

    test('Phase 2: on-device extractor refusal -> sir candidate null',
        () async {
      final store = await _makePairedStore();
      // Output a malformed Intent so the extractor refuses.
      final extractor = SirExtractor(
        completer: _FakeCompleter(returns: '{"id": "x"}'),
        intentGrammarBNF: 'root ::= .*',
      );
      final svc = VoiceCommandService(
        certStore: store,
        transcriber: _FakeTranscriber(),
        sirExtractor: extractor,
        hatContext: _hat,
      );
      final outcome = await svc.processRecording(
        recordedBytes: Uint8List.fromList(List.filled(32000, 0)),
        mimeType: 'audio/wav',
        durationMs: 1000,
      ) as VoiceCommandReady;
      expect(outcome.recording.sirExtractionResult,
          isA<SirExtractionRefused>());
      expect(outcome.recording.sirCandidate, isNull);
    });

    test('Phase 2: extractor exception falls back to brain-side',
        () async {
      final store = await _makePairedStore();
      final extractor = SirExtractor(
        completer: _FakeCompleter(throws: true),
        intentGrammarBNF: 'root ::= .*',
      );
      final svc = VoiceCommandService(
        certStore: store,
        transcriber: _FakeTranscriber(),
        sirExtractor: extractor,
        hatContext: _hat,
      );
      final outcome = await svc.processRecording(
        recordedBytes: Uint8List.fromList(List.filled(32000, 0)),
        mimeType: 'audio/wav',
        durationMs: 1000,
      ) as VoiceCommandReady;
      expect(outcome.recording.sirExtractionResult,
          isA<SirExtractionRefused>());
      expect(outcome.recording.sirCandidate, isNull);
    });

    test('Phase 2: null extractor preserves Phase 1 fallback path',
        () async {
      // No sirExtractor configured -> sir candidate is always null
      // and the brain runs the full Phase 1 pipeline.
      final store = await _makePairedStore();
      final svc = VoiceCommandService(
        certStore: store,
        transcriber: _FakeTranscriber(),
        // sirExtractor: null intentionally
      );
      final outcome = await svc.processRecording(
        recordedBytes: Uint8List.fromList(List.filled(32000, 0)),
        mimeType: 'audio/wav',
        durationMs: 1000,
      ) as VoiceCommandReady;
      expect(outcome.recording.sirExtractionResult, isNull);
      expect(outcome.recording.sirCandidate, isNull);
    });
  });
}

```
