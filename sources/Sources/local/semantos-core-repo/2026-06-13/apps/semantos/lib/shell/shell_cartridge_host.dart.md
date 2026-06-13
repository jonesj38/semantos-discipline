---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/shell_cartridge_host.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.103091+00:00
---

# apps/semantos/lib/shell/shell_cartridge_host.dart

```dart
// Shell implementation of the neutral [CartridgeHost] capability seam.
//
// Lets cartridge-owned screens (presented via CustomVerbSurfaceRegistry) mint
// cells + run OCR without importing the shell. Wraps the boot-wired CellMinter
// (BrainRpcClient → cells.mint over WSS) and the OCR uploader. Installed near
// the app root via CartridgeHostScope (see main.dart).

import 'dart:typed_data';

import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:semantos_core/semantos_core.dart' show IdentityStore;

import '../src/dispatch/cell_minter.dart';
import '../src/gradient/type_hash.dart';
import '../src/ocr/image_extract_uploader.dart';

/// Transcribe recorded audio (WAV/PCM16 mono 16kHz) → plain text. Wired in the
/// shell to on-device whisper; null on platforms/builds without it.
typedef VoiceTranscriber = Future<String> Function(Uint8List audioBytes);

/// IdentityStore slot for the operator's BYOK Anthropic key (secret).
const String kByokAnthropicKeySlot = 'me.llm.anthropic_key.v1';

/// IdentityStore slot for the operator's selected LLM model.
const String kByokModelSlot = 'me.llm.model.v1';

class ShellCartridgeHost implements CartridgeHost {
  final CellMinter? _minter;
  final ImageExtractUploader? _ocr;
  final IdentityStore? _identity;
  final VoiceTranscriber? _transcriber;

  const ShellCartridgeHost({
    CellMinter? minter,
    ImageExtractUploader? ocr,
    IdentityStore? identity,
    VoiceTranscriber? transcriber,
  })  : _minter = minter,
        _ocr = ocr,
        _identity = identity,
        _transcriber = transcriber;

  @override
  bool get isConnected => _minter != null;

  @override
  bool get canTranscribe => _transcriber != null;

  @override
  Future<TranscribeOutcome> transcribe({required List<int> audioBytes}) async {
    final t = _transcriber;
    if (t == null) return const TranscribeErr('not_available');
    try {
      final text = (await t(Uint8List.fromList(audioBytes))).trim();
      if (text.isEmpty) return const TranscribeErr('empty_transcript');
      // A voice note is one self-turn; split only on explicit blank-line breaks.
      final paras = text
          .replaceAll('\r\n', '\n')
          .split(RegExp(r'\n[ \t]*\n+'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      final segs = paras.isEmpty ? [text] : paras;
      final turns = [
        for (var i = 0; i < segs.length; i++)
          CapturedTurn(index: i, text: segs[i], speaker: 'self'),
      ];
      return TranscribeOk(turns: turns, transcript: text);
    } catch (e) {
      return TranscribeErr(e.toString());
    }
  }

  @override
  Future<MintOutcome> mint({
    required List<String> triple,
    required Map<String, dynamic> payload,
  }) async {
    final minter = _minter;
    if (minter == null) return const MintErr('not connected to a brain');
    String seg(int i) => i < triple.length ? triple[i] : '';
    final thh = typeHashHex(buildTypeHash(seg(0), seg(1), seg(2), seg(3)));
    try {
      final r = await minter.mintCell(typeHashHex: thh, payload: payload);
      return MintOk(r.cellId);
    } catch (e) {
      return MintErr(e.toString());
    }
  }

  @override
  Future<OcrOutcome> ocr({
    required List<CaptureImage> images,
    String? day,
  }) async {
    final uploader = _ocr;
    if (uploader == null) {
      return const OcrErr(reason: 'not_connected');
    }
    // BYOK: read the operator's own key + model (if set) from secure storage and
    // pass them per-request. Empty/absent → the brain uses its own env key/default.
    final apiKey = await _identity?.read(kByokAnthropicKeySlot);
    final model = await _identity?.read(kByokModelSlot);
    final res = await uploader.upload(
      images: images
          .map((c) => OcrImage(bytes: c.bytes, mimeType: c.mimeType))
          .toList(),
      metadata: day != null ? ImageExtractMetadata(day: day) : null,
      apiKey: (apiKey != null && apiKey.isNotEmpty) ? apiKey : null,
      model: (model != null && model.isNotEmpty) ? model : null,
    );
    return switch (res) {
      ImageExtractSuccess s => OcrOk(
          turns: s.turns
              .map((t) => CapturedTurn(
                    index: t.index,
                    text: t.text,
                    speaker: t.speaker,
                    sourcePageRef: t.sourcePageRef,
                    confidence: t.confidence,
                  ))
              .toList(),
          rawText: s.rawText,
        ),
      ImageExtractFailed f =>
        OcrErr(reason: f.reason, statusCode: f.statusCode),
      ImageExtractNetworkError n => OcrErr(reason: n.message),
    };
  }
}

```
