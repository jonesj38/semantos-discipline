---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/gradient/oir_to_bytes.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.876398+00:00
---

# archive/apps-semantos-monolith/lib/src/gradient/oir_to_bytes.dart

```dart
// D-O5m.followup-3 Phase 3 — pure-Dart L2 (OIR) -> L3 (opcode bytes).
//
// Reference: core/semantos-ir/src/emit.ts (the canonical source of
//            truth -- this file is a verbatim port of the emit pass
//            that produces byte-identical opcode output for any
//            well-formed OIR program; the byte-identical
//            α-equivalence property from the paper §3, §4.4 is the
//            load-bearing claim the Dart port honours);
//            apps/oddjobz-mobile/test/fixtures/oir-to-bytes-fixture.json
//            (the cross-language fixture that pins the bytes the TS
//            emitter produces; oir_to_bytes_test.dart asserts byte
//            parity);
//            apps/oddjobz-mobile/lib/src/gradient/sir_to_oir.dart
//            (the L1->L2 lowering that produces the OIR programs this
//            emitter consumes).

import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'sir_to_oir.dart';

// ── Opcode constants ─────────────────────────────────────────────
// Sourced from packages/cell-engine/src/opcodes/standard.zig and
// plexus.zig; identical to core/semantos-ir/src/emit.ts.

const int _opPushdata1 = 0x4C;
const int _opEqual = 0x87;
const int _opNot = 0x91;
const int _opNumNotEqual = 0x9E;
const int _opBoolAnd = 0x9A;
const int _opBoolOr = 0x9B;
const int _opLessThan = 0x9F;
const int _opGreaterThan = 0xA0;
const int _opLessThanOrEqual = 0xA1;
const int _opGreaterThanOrEqual = 0xA2;
const int _op1 = 0x51; // BSV OP_1 / OP_TRUE — pushes 1 on the stack
const int _opCheckCapability = 0xC3;
const int _opCheckDomainFlag = 0xC6;
const int _opCheckTypeHash = 0xC7;
const int _opDerefPointer = 0xC8;
const int _opCallHost = 0xD0;
const int _opLoadField = 0xB0;

const Map<String, int> _comparisonOpcodes = {
  '>': _opGreaterThan,
  '<': _opLessThan,
  '>=': _opGreaterThanOrEqual,
  '<=': _opLessThanOrEqual,
  '=': _opEqual,
  '!=': _opNumNotEqual,
};

// ── Byte encoding ───────────────────────────────────────────────

Uint8List _encodeScriptNumber(int n) {
  if (n == 0) return Uint8List.fromList(const [0]);
  final negative = n < 0;
  var abs = n.abs();
  final bytes = <int>[];
  while (abs > 0) {
    bytes.add(abs & 0xFF);
    abs >>= 8;
  }
  if ((bytes.last & 0x80) != 0) {
    bytes.add(negative ? 0x80 : 0x00);
  } else if (negative) {
    bytes[bytes.length - 1] |= 0x80;
  }
  return Uint8List.fromList(bytes);
}

Uint8List _encodePushData(Uint8List data) {
  if (data.length <= 75) {
    final out = Uint8List(1 + data.length);
    out[0] = data.length;
    out.setRange(1, 1 + data.length, data);
    return out;
  }
  final out = Uint8List(2 + data.length);
  out[0] = _opPushdata1;
  out[1] = data.length;
  out.setRange(2, 2 + data.length, data);
  return out;
}

Uint8List _encodePushNumber(int n) => _encodePushData(_encodeScriptNumber(n));

Uint8List _encodePushString(String s) =>
    _encodePushData(Uint8List.fromList(utf8.encode(s)));

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

// ── Per-binding emit ────────────────────────────────────────────

List<int> _emitBinding(OirBinding b) {
  switch (b.kind) {
    case 'comparison':
      {
        final opcode = _comparisonOpcodes[b.op];
        if (opcode == null) {
          throw StateError('Unknown comparison op: ${b.op}');
        }
        final value = b.value;
        final pushBytes = value is num
            ? _encodePushNumber(value.toInt())
            : _encodePushString(value as String);
        final fieldBytes = <int>[
          ..._encodePushString(b.field!),
          _opLoadField,
        ];
        return [...pushBytes, ...fieldBytes, opcode];
      }
    case 'literal_true':
      // Pushes a truthy value on the stack. Used when the upstream
      // intent has no enforceable kernel constraints — the producer
      // is the gatekeeper, kernel script is vacuous. Without this
      // marker, scripts terminated with an empty stack and the
      // executor's terminal `top-of-stack must be truthy` check
      // rejected them.
      return const [_op1];
    case 'logical_not':
      return const [_opNot];
    case 'logical_and':
      {
        // BSV Script OP_BOOLAND consumes 2 stack items, pushes 1.
        // Folding N items down to 1 needs N-1 ANDs. For N < 2 there's
        // nothing to fold — emit no opcodes so the stack passes
        // through. Pre-fix this hit `List.filled(-1, …)` and crashed
        // the pipeline when the SIR producer emitted constraints=[]
        // (empty composite ⇒ logical_and with operands=[]).
        final n = b.operands?.length ?? 0;
        if (n < 2) return const <int>[];
        return List<int>.filled(n - 1, _opBoolAnd);
      }
    case 'logical_or':
      {
        final n = b.operands?.length ?? 0;
        if (n < 2) return const <int>[];
        return List<int>.filled(n - 1, _opBoolOr);
      }
    case 'capability':
      return [
        ..._encodePushNumber(b.capabilityNumber!),
        _opCheckCapability,
      ];
    case 'domainCheck':
      {
        final f = b.domainFlag;
        final flagInt = f is num
            ? f.toInt()
            : (int.tryParse((f as String), radix: 16) ?? 0);
        return [
          ..._encodePushNumber(flagInt),
          _opCheckDomainFlag,
        ];
      }
    case 'timeConstraint':
      {
        final opcode =
            b.timeOp == 'timeAfter' ? _opGreaterThan : _opLessThan;
        return [
          ..._encodePushNumber(b.timestamp!),
          opcode,
        ];
      }
    case 'hostCall':
      return [
        ..._encodePushString(b.functionName!),
        _opCallHost,
      ];
    case 'typeHashCheck':
      {
        final hashBytes = _hexToBytes(b.expectedHash!);
        return [
          ..._encodePushData(hashBytes),
          _opCheckTypeHash,
        ];
      }
    case 'deref':
      return const [_opDerefPointer];
  }
  throw StateError('unhandled OIR binding kind: ${b.kind}');
}

/// Emit an [OirProgram] as cell engine opcode bytes.
///
/// Walks bindings in order (topological -- operands before
/// combinators) and concatenates their opcode sequences.
///
/// The output is byte-for-byte identical to the TS
/// `core/semantos-ir/src/emit.ts:emit()` for the same input -- the
/// load-bearing α-equivalence property the cross-language fixture
/// `apps/oddjobz-mobile/test/fixtures/oir-to-bytes-fixture.json`
/// pins down.
Uint8List oirToBytes(OirProgram program) {
  final bytes = <int>[];
  for (final b in program.bindings) {
    bytes.addAll(_emitBinding(b));
  }
  return Uint8List.fromList(bytes);
}

```
