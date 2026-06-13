---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cartridge_sdk/lib/src/cartridge_host.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.509978+00:00
---

# packages/cartridge_sdk/lib/src/cartridge_host.dart

```dart
/// Neutral capability seam between a cartridge-owned screen and the shell.
///
/// Cartridge `*_experience` screens are built with only a [BuildContext]
/// ([CartridgeEntry.buildScreen]) and MUST NOT import the app shell. When such
/// a screen needs to act on the brain — mint a cell, run OCR — it reads
/// [CartridgeHost] from the widget tree via [CartridgeHostScope]. The shell
/// provides the concrete implementation (wrapping its dispatcher / brain RPC
/// client / OCR uploader) and installs the scope near the app root.
///
/// Dependency direction stays shell -> *_experience -> cartridge_sdk: the
/// interface + neutral data types live here; the shell depends on cartridge_sdk
/// to implement them; cartridges depend on cartridge_sdk to consume them.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// One page image to OCR.
class CaptureImage {
  final Uint8List bytes;
  final String mimeType;
  const CaptureImage({required this.bytes, required this.mimeType});
}

/// One chronological turn returned by OCR (parallels the brain's ReleaseTurn).
class CapturedTurn {
  final int index;
  final String text;
  final String speaker;
  final String? sourcePageRef;
  final double? confidence;
  const CapturedTurn({
    required this.index,
    required this.text,
    this.speaker = 'self',
    this.sourcePageRef,
    this.confidence,
  });
}

/// Outcome of an OCR request.
sealed class OcrOutcome {
  const OcrOutcome();
}

class OcrOk extends OcrOutcome {
  final List<CapturedTurn> turns;
  final String rawText;
  const OcrOk({required this.turns, required this.rawText});
}

class OcrErr extends OcrOutcome {
  final String reason;
  final int statusCode;
  const OcrErr({required this.reason, this.statusCode = 0});
}

/// Outcome of a voice-transcription request.
sealed class TranscribeOutcome {
  const TranscribeOutcome();
}

class TranscribeOk extends TranscribeOutcome {
  final List<CapturedTurn> turns;
  final String transcript;
  const TranscribeOk({required this.turns, required this.transcript});
}

class TranscribeErr extends TranscribeOutcome {
  final String reason;
  const TranscribeErr(this.reason);
}

/// Outcome of a mint request.
sealed class MintOutcome {
  const MintOutcome();
}

class MintOk extends MintOutcome {
  final String cellId;
  const MintOk(this.cellId);
}

class MintErr extends MintOutcome {
  final String message;
  const MintErr(this.message);
}

/// The shell-provided capabilities a cartridge screen may use. Kept tiny and
/// brain-shaped; grows only as cartridge surfaces genuinely need more.
abstract class CartridgeHost {
  /// Mint a cell of the given triple `[s1,s2,s3,s4]` with [payload].
  Future<MintOutcome> mint({
    required List<String> triple,
    required Map<String, dynamic> payload,
  });

  /// Run handwriting OCR over [images] via the brain's image-extract endpoint.
  Future<OcrOutcome> ocr({
    required List<CaptureImage> images,
    String? day,
  });

  /// Transcribe recorded audio (WAV or raw 16kHz mono PCM16) to text + turns
  /// via on-device whisper. Returns a TranscribeErr when no transcriber is
  /// available on this platform/build.
  Future<TranscribeOutcome> transcribe({
    required List<int> audioBytes,
  });

  /// Whether on-device voice transcription is available (whisper wired).
  bool get canTranscribe;

  /// Whether a brain connection is available (mint/ocr will otherwise fail).
  bool get isConnected;
}

/// InheritedWidget exposing the [CartridgeHost] to cartridge screens.
class CartridgeHostScope extends InheritedWidget {
  const CartridgeHostScope({
    super.key,
    required this.host,
    required super.child,
  });

  final CartridgeHost host;

  /// Read the host. Returns null when no scope is installed (e.g. a cartridge
  /// screen previewed outside the shell) so screens can degrade gracefully.
  static CartridgeHost? maybeOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<CartridgeHostScope>();
    return scope?.host;
  }

  /// Read the host or throw — use when the screen cannot function without it.
  static CartridgeHost of(BuildContext context) {
    final host = maybeOf(context);
    if (host == null) {
      throw StateError(
        'CartridgeHostScope.of: no CartridgeHost in the tree. The shell must '
        'install CartridgeHostScope above cartridge screens.',
      );
    }
    return host;
  }

  @override
  bool updateShouldNotify(CartridgeHostScope oldWidget) =>
      host != oldWidget.host;
}

/// Registry of cartridge-owned "custom" verb surfaces.
///
/// A manifest verb whose `inputShape.kind == "custom"` carries a `customKey`;
/// the shell looks the key up here and pushes the registered screen instead of
/// the generic input sheet. Cartridges register their builders at boot
/// (alongside their [CartridgeEntry]). The shell never imports the cartridge.
class CustomVerbSurfaceRegistry {
  CustomVerbSurfaceRegistry._();
  static final CustomVerbSurfaceRegistry instance =
      CustomVerbSurfaceRegistry._();

  final Map<String, WidgetBuilder> _byKey = <String, WidgetBuilder>{};

  /// Register (or replace) a custom-surface builder for [key]
  /// (e.g. "betterment.release"). The built screen reads [CartridgeHostScope].
  void register(String key, WidgetBuilder builder) => _byKey[key] = builder;

  WidgetBuilder? builderFor(String key) => _byKey[key];

  bool has(String key) => _byKey.containsKey(key);

  /// Test/host hook — clear all registrations.
  void resetForTest() => _byKey.clear();
}

```
