---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/gradient/oir_to_bytes_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.918089+00:00
---

# archive/apps-semantos-monolith/test/gradient/oir_to_bytes_test.dart

```dart
// D-O5m.followup-3 Phase 3 — oir_to_bytes unit + parity tests.
//
// Reference: apps/oddjobz-mobile/lib/src/gradient/oir_to_bytes.dart
//            (the unit under test, a verbatim port of
//            core/semantos-ir/src/emit.ts);
//            apps/oddjobz-mobile/test/fixtures/oir-to-bytes-fixture.json
//            (the cross-language fixture: the load-bearing
//            α-equivalence claim asserts the Dart oirToBytes()
//            produces byte-identical opcode streams to the TS emit()
//            for every well-formed OIR program).

import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:semantos/src/gradient/oir_to_bytes.dart';
import 'package:semantos/src/gradient/sir_to_oir.dart';
import 'package:test/test.dart';

void main() {
  group('oirToBytes — per-binding-kind emit', () {
    test('capability binding -> push + OP_CHECKCAPABILITY', () {
      final p = OirProgram(bindings: const [
        OirBinding(name: '\$0', kind: 'capability', capabilityNumber: 5),
      ], result: '\$0');
      final bytes = oirToBytes(p);
      // 0x01 push-len, 0x05 value, 0xC3 OP_CHECKCAPABILITY
      expect(bytes, equals([0x01, 0x05, 0xC3]));
    });

    test('domainCheck binding -> push + OP_CHECKDOMAINFLAG', () {
      final p = OirProgram(bindings: const [
        OirBinding(name: '\$0', kind: 'domainCheck', domainFlag: 5),
      ], result: '\$0');
      final bytes = oirToBytes(p);
      expect(bytes, equals([0x01, 0x05, 0xC6]));
    });

    test('comparison numeric > -> push + push+OP_LOADFIELD + OP_GREATERTHAN',
        () {
      final p = OirProgram(bindings: const [
        OirBinding(
          name: '\$0',
          kind: 'comparison',
          op: '>',
          field: 'amount',
          value: 500,
        ),
      ], result: '\$0');
      final bytes = oirToBytes(p);
      // The exact pattern: encode 500 (2 bytes), push 'amount' (string),
      // OP_LOADFIELD (0xB0), OP_GREATERTHAN (0xA0).
      expect(bytes.last, equals(0xA0));
      expect(bytes.contains(0xB0), isTrue);
    });

    test('logical_not -> single OP_NOT', () {
      final p = OirProgram(bindings: const [
        OirBinding(name: '\$0', kind: 'capability', capabilityNumber: 1),
        OirBinding(name: '\$1', kind: 'logical_not', operands: ['\$0']),
      ], result: '\$1');
      final bytes = oirToBytes(p);
      expect(bytes.last, equals(0x91)); // OP_NOT
    });

    test('logical_and(n) -> (n-1) OP_BOOLAND', () {
      final p = OirProgram(bindings: const [
        OirBinding(name: '\$0', kind: 'capability', capabilityNumber: 1),
        OirBinding(name: '\$1', kind: 'capability', capabilityNumber: 2),
        OirBinding(name: '\$2', kind: 'capability', capabilityNumber: 3),
        OirBinding(
          name: '\$3',
          kind: 'logical_and',
          operands: ['\$0', '\$1', '\$2'],
        ),
      ], result: '\$3');
      final bytes = oirToBytes(p);
      // Last 2 bytes are OP_BOOLAND (0x9A) — n=3 operands -> n-1=2 ANDs.
      expect(bytes[bytes.length - 1], equals(0x9A));
      expect(bytes[bytes.length - 2], equals(0x9A));
    });

    test('timeConstraint timeAfter -> push + OP_GREATERTHAN', () {
      final p = OirProgram(bindings: const [
        OirBinding(
          name: '\$0',
          kind: 'timeConstraint',
          timeOp: 'timeAfter',
          timestamp: 1000,
        ),
      ], result: '\$0');
      final bytes = oirToBytes(p);
      expect(bytes.last, equals(0xA0));
    });

    test('hostCall -> push functionName + OP_CALLHOST', () {
      final p = OirProgram(bindings: const [
        OirBinding(name: '\$0', kind: 'hostCall', functionName: 'fn:test'),
      ], result: '\$0');
      final bytes = oirToBytes(p);
      expect(bytes.last, equals(0xD0));
    });

    test('typeHashCheck -> push hash + OP_CHECKTYPEHASH', () {
      final hash = List.filled(32, 0).map((b) => '00').join();
      final p = OirProgram(bindings: [
        OirBinding(
          name: '\$0',
          kind: 'typeHashCheck',
          expectedHash: hash, // 32-byte zero hash
        ),
      ], result: '\$0');
      final bytes = oirToBytes(p);
      expect(bytes.last, equals(0xC7));
    });
  });

  group('oirToBytes — α-equivalence (the load-bearing property)', () {
    test('OIR programs produced from semantically-equivalent SIRs '
        'emit byte-identical bytes', () {
      // Two SIR programs with different surface shapes but
      // semantically-equivalent constraints -- both should lower to
      // the same OIR (a single capability binding) and therefore
      // produce identical opcode bytes. This is the byte-identical
      // α-equivalence property the paper §3, §4.4 commits to.
      Map<String, dynamic> mkProg(String category) => {
            'nodes': [
              {
                'id': '\$s0',
                'category': category,
                'taxonomy': const {
                  'what': 'demo',
                  'how': 'demo',
                  'why': 'demo',
                },
                'identity': const {
                  'subject': {'type': 'role', 'name': 'demo'},
                },
                'governance': const {
                  'trustClass': 'interpretive',
                  'proofRequirement': 'attestation',
                  'executionAuthority': 'hat_scoped',
                  'linearity': 'LINEAR',
                },
                'action': 'demo',
                'constraint': const {
                  'kind': 'capability',
                  'required': 7,
                  'name': 'X',
                },
                'provenance': const {
                  'source': 'voice',
                  'expressedAt': '2026-04-17T00:00:00Z',
                  'trustAtExpression': 'interpretive',
                },
              }
            ],
            'primaryNodeId': '\$s0',
            'programGovernance': const {
              'trustClass': 'interpretive',
              'proofRequirement': 'attestation',
              'executionAuthority': 'hat_scoped',
              'linearity': 'LINEAR',
            },
          };

      final p1 = sirToOir(mkProg('permission')) as SirToOirSuccess;
      final p2 = sirToOir(mkProg('declaration')) as SirToOirSuccess;
      // declaration + permission both fall through to a single
      // capability binding for this constraint shape.
      expect(p1.program.toJson(), equals(p2.program.toJson()));
      expect(oirToBytes(p1.program), equals(oirToBytes(p2.program)));
    });
  });

  group('oirToBytes — cross-language fixture parity', () {
    test('every fixture case produces byte-identical opcode bytes', () {
      final fixturePath = _findFixture('oir-to-bytes-fixture.json');
      final fixture = jsonDecode(File(fixturePath).readAsStringSync())
          as Map<String, dynamic>;
      final cases = fixture['cases'] as List;
      expect(cases, isNotEmpty);
      for (final raw in cases) {
        final c = raw as Map<String, dynamic>;
        final name = c['name'] as String;
        final oirJson = c['oirProgram'] as Map<String, dynamic>;
        final expectedHex = c['bytesHex'] as String;
        final program = OirProgram.fromJson(oirJson);
        final actual = oirToBytes(program);
        final actualHex = actual
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        expect(actualHex, equals(expectedHex),
            reason: 'opcode-byte parity for case $name');
      }
    });
  });
}

String _findFixture(String filename) {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final p =
        '${dir.path}/apps/oddjobz-mobile/test/fixtures/$filename';
    if (File(p).existsSync()) return p;
    final localP = '${dir.path}/test/fixtures/$filename';
    if (File(localP).existsSync()) return localP;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('fixture $filename not found from ${Directory.current.path}');
}

```
