---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/test/kernel_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.996306+00:00
---

# platforms/flutter/semantos_ffi/test/kernel_test.dart

```dart
// Phase 30G/D30G.7 — Kernel wrapper tests.
//
// Validates the SemantosKernel Dart wrapper against the real native library.
// Tests init/shutdown lifecycle, cell write/read round-trip, error handling,
// and buffer management.

import 'dart:convert' show utf8;
import 'dart:io' show Directory, Platform;
import 'dart:typed_data' show BytesBuilder, Endian, Uint8List;

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos_ffi/semantos_ffi.dart';

String _testLibPath() {
  var root = Directory.current.path;
  for (var i = 0; i < 6; i++) {
    final candidate = '$root/src/ffi/zig-out/lib';
    if (Directory(candidate).existsSync()) {
      if (Platform.isMacOS) return '$candidate/libsemantos.dylib';
      if (Platform.isLinux) return '$candidate/libsemantos.so';
    }
    root = Directory(root).parent.path;
  }
  throw StateError(
    'Could not find libsemantos in zig-out. '
    'Run `zig build dylib` in src/ffi/ first. CWD: ${Directory.current.path}',
  );
}

void main() {
  late SemantosKernel kernel;

  setUp(() {
    final bindings = SemantosBindings.fromPath(_testLibPath());
    kernel = SemantosKernel.withBindings(bindings);
  });

  tearDown(() async {
    if (kernel.isInitialized) {
      await kernel.shutdown();
    }
  });

  group('Lifecycle', () {
    test('initialize with valid JSON config succeeds', () async {
      await kernel.initialize('{}');
      expect(kernel.isInitialized, isTrue);
    });

    test('double init throws ALREADY_INIT', () async {
      await kernel.initialize('{}');
      expect(
        () => kernel.initialize('{}'),
        throwsA(isA<SemantosException>()),
      );
    });

    test('shutdown after init succeeds', () async {
      await kernel.initialize('{}');
      await kernel.shutdown();
      expect(kernel.isInitialized, isFalse);
    });

    test('shutdown without init throws NOT_INIT', () async {
      expect(
        () => kernel.shutdown(),
        throwsA(isA<SemantosException>()),
      );
    });

    test('initialize with invalid JSON throws INVALID_JSON', () async {
      expect(
        () => kernel.initialize('not json'),
        throwsA(isA<SemantosException>()),
      );
    });
  });

  group('Cell operations', () {
    setUp(() async {
      await kernel.initialize('{}');
    });

    test('cellWrite and cellRead return identical bytes', () async {
      final originalData = Uint8List.fromList(
        utf8.encode('Hello, Semantos!'),
      );
      await kernel.cellWrite('/test/path', originalData);
      final readData = await kernel.cellRead('/test/path');

      expect(readData, isNotNull);
      expect(readData, equals(originalData));
    });

    test('cellRead on non-existent path returns null', () async {
      final result = await kernel.cellRead('/nonexistent');
      expect(result, isNull);
    });

    test('cellWrite overwrites existing data', () async {
      final data1 = Uint8List.fromList(utf8.encode('first'));
      final data2 = Uint8List.fromList(utf8.encode('second'));

      await kernel.cellWrite('/overwrite', data1);
      await kernel.cellWrite('/overwrite', data2);

      final result = await kernel.cellRead('/overwrite');
      expect(result, equals(data2));
    });

    test('cellWrite with empty data is rejected', () async {
      final empty = Uint8List(0);
      // Kernel rejects zero-length writes (DENIED).
      expect(
        () => kernel.cellWrite('/empty', empty),
        throwsA(isA<SemantosException>()),
      );
    });

    test('cellWrite and cellRead with binary data', () async {
      final binary = Uint8List.fromList(
        List.generate(256, (i) => i),
      );
      await kernel.cellWrite('/binary', binary);
      final result = await kernel.cellRead('/binary');
      expect(result, equals(binary));
    });

    test('cellWrite and cellRead with large data (64KB)', () async {
      final large = Uint8List.fromList(
        List.generate(65536, (i) => i % 256),
      );
      await kernel.cellWrite('/large', large);
      final result = await kernel.cellRead('/large');
      expect(result, equals(large));
    });
  });

  group('Metadata', () {
    test('version returns a non-empty string', () async {
      final version = kernel.version();
      expect(version, isNotEmpty);
      expect(version, matches(RegExp(r'\d+\.\d+\.\d+')));
    });
  });

  group('Memory safety', () {
    test('100 write/read cycles without leak', () async {
      await kernel.initialize('{}');
      for (var i = 0; i < 100; i++) {
        final data = Uint8List.fromList(utf8.encode('cycle-$i'));
        await kernel.cellWrite('/cycle/$i', data);
        final result = await kernel.cellRead('/cycle/$i');
        expect(result, equals(data));
      }
      // If we get here without crashing, memory management is working.
    });
  });

  // D-O5m.followup-3 Phase 3 + D-O5m.followup-1 — script execution surface.
  // The Dart-side gradient pipeline
  // (apps/oddjobz-mobile/lib/src/gradient/dart_pipeline.dart) produces
  // opcode bytes via the pure-Dart oirToBytes() port; this group exercises
  // the FFI path that runs them through the real cell-engine 2-PDA on
  // device, and verifies K1-K4 substructural enforcement is local.
  group('executeScript (Phase 3 + K1-K4)', () {
    setUp(() async {
      await kernel.initialize('{}');
    });

    // ── Cell-construction helper ─────────────────────────────────────
    // Mirrors src/ffi/tests/execute_script_test.zig:buildCell. Produces
    // a 1024-byte cell with the requested linearity / domain_flag /
    // capability_type fields the executor reads.
    Uint8List buildCell({
      required int linearity,
      required int domainFlag,
      required int capabilityType,
    }) {
      final cell = Uint8List(1024);
      // linearity at offset 16, u32 LE
      cell.buffer.asByteData().setUint32(16, linearity, Endian.little);
      // domain_flag at offset 24, u32 LE
      cell.buffer.asByteData().setUint32(24, domainFlag, Endian.little);
      // capability_type at offset 256 (payload byte 0)
      cell[256] = capabilityType;
      return cell;
    }

    /// Build an opcode stream that PUSHDATA2-pushes the given cell.
    Uint8List pushCell(Uint8List cell) {
      final out = BytesBuilder();
      out.addByte(0x4D); // OP_PUSHDATA2
      out.addByte(cell.length & 0xFF);
      out.addByte((cell.length >> 8) & 0xFF);
      out.add(cell);
      return out.toBytes();
    }

    test('well-formed equality script returns ok=true', () async {
      // Push 5, push 5, OP_EQUAL → truthy 1.
      final bytes = Uint8List.fromList([0x01, 0x05, 0x01, 0x05, 0x87]);
      final result = await kernel.executeScript(bytes: bytes);
      expect(result.ok, isTrue);
      expect(result.opcount, equals(3));
      expect(result.stackDepth, equals(1));
      expect(result.errorCode, isNull);
      expect(result.errorKind, isNull);
      expect(result.toOutcome(), isA<ScriptOk>());
    });

    test('truncated pushdata maps to script_invalid', () async {
      // OP_PUSHDATA1 announces 5 bytes but only 2 follow.
      final bytes = Uint8List.fromList([0x4C, 0x05, 0xAA, 0xBB]);
      final result = await kernel.executeScript(bytes: bytes);
      expect(result.ok, isFalse);
      expect(result.errorCode, isNotNull);
      expect(result.errorKind, equals('script_invalid'));
      final outcome = result.toOutcome();
      expect(outcome, isA<ScriptViolation>());
      expect(
        (outcome as ScriptViolation).kind,
        equals(ScriptViolationKind.scriptInvalid),
      );
    });

    test('traceCorrelationId echoes through the result', () async {
      final bytes = Uint8List.fromList([0x51]); // OP_1
      final result = await kernel.executeScript(
        bytes: bytes,
        ctx: const ScriptContext(traceCorrelationId: 'unit-test-1'),
      );
      expect(result.ok, isTrue);
      expect(result.traceCorrelationId, equals('unit-test-1'));
    });

    test('empty bytes return ok=true with opcount=0', () async {
      final result = await kernel.executeScript(bytes: Uint8List(0));
      expect(result.ok, isTrue);
      expect(result.opcount, equals(0));
    });

    test('long trace id survives BUFFER_TOO_SMALL retry', () async {
      // OP_1 — simplest happy path; the load-bearing assertion is that
      // a long traceCorrelationId pushes the result JSON past the
      // wrapper's initial 1024-byte buffer and the retry path lifts
      // capacity to fit. The K1 enforcement path on the real 2-PDA
      // means OP_1 + OP_DROP loops trip cell_too_short, so we keep
      // the script minimal and let the trace id do the size lift.
      final bytes = Uint8List.fromList([0x51]);
      final longId = 'x' * 1100;
      final result = await kernel.executeScript(
        bytes: bytes,
        ctx: ScriptContext(traceCorrelationId: longId),
      );
      expect(result.ok, isTrue);
      expect(result.opcount, equals(1));
      expect(result.traceCorrelationId, equals(longId));
    });

    // ── D-O5m.followup-1 — K1-K4 substructural enforcement ───────────

    test('K1 — duplicating a LINEAR cell yields ScriptViolation(k1Linearity)',
        () async {
      // Push LINEAR cell, OP_DUP — the PDA's enforced-DUP path raises
      // cannot_duplicate_linear which the FFI maps to k1_linearity_violation.
      final cell = buildCell(linearity: 1, domainFlag: 0x100, capabilityType: 5);
      final builder = BytesBuilder();
      builder.add(pushCell(cell));
      builder.addByte(0x76); // OP_DUP

      final result = await kernel.executeScript(bytes: builder.toBytes());
      expect(result.ok, isFalse);
      expect(result.errorKind, equals('k1_linearity_violation'));
      final outcome = result.toOutcome();
      expect(outcome, isA<ScriptViolation>());
      expect(
        (outcome as ScriptViolation).kind,
        equals(ScriptViolationKind.k1Linearity),
      );
    });

    test('K2 — wrong capability type yields ScriptViolation(k2Auth)',
        () async {
      // Push LINEAR cell with cap=5, push expected cap=6, OP_CHECKCAPABILITY.
      final cell = buildCell(linearity: 1, domainFlag: 0x100, capabilityType: 5);
      final builder = BytesBuilder();
      builder.add(pushCell(cell));
      builder.addByte(0x01); // direct push 1 byte
      builder.addByte(0x06); // expected cap = 6 (mismatch)
      builder.addByte(0xC3); // OP_CHECKCAPABILITY

      final result = await kernel.executeScript(bytes: builder.toBytes());
      expect(result.ok, isFalse);
      expect(result.errorKind, equals('k2_auth_failed'));
      expect(
        (result.toOutcome() as ScriptViolation).kind,
        equals(ScriptViolationKind.k2Auth),
      );
    });

    test('K3 — wrong domain flag yields ScriptViolation(k3Domain)', () async {
      // Push LINEAR cell with flag=0x100, push expected flag=0x200, OP_CHECKDOMAINFLAG.
      final cell = buildCell(linearity: 1, domainFlag: 0x100, capabilityType: 5);
      final builder = BytesBuilder();
      builder.add(pushCell(cell));
      builder.addByte(0x02); // direct push 2 bytes
      builder.addByte(0x00); // expected flag low
      builder.addByte(0x02); // expected flag high (= 0x200)
      builder.addByte(0xC6); // OP_CHECKDOMAINFLAG

      final result = await kernel.executeScript(bytes: builder.toBytes());
      expect(result.ok, isFalse);
      expect(result.errorKind, equals('k3_domain_mismatch'));
      expect(
        (result.toOutcome() as ScriptViolation).kind,
        equals(ScriptViolationKind.k3Domain),
      );
    });

    test('K4 — OP_VERIFY on falsy top yields ScriptViolation(k4Atomicity)',
        () async {
      // OP_0 OP_VERIFY → verify_failed → k4_atomicity_violation.
      final bytes = Uint8List.fromList([0x00, 0x69]);
      final result = await kernel.executeScript(bytes: bytes);
      expect(result.ok, isFalse);
      expect(result.errorKind, equals('k4_atomicity_violation'));
      expect(
        (result.toOutcome() as ScriptViolation).kind,
        equals(ScriptViolationKind.k4Atomicity),
      );
    });
  });
}

```
