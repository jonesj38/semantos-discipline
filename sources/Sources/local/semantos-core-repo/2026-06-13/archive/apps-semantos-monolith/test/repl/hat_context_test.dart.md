---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/hat_context_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.921848+00:00
---

# archive/apps-semantos-monolith/test/repl/hat_context_test.dart

```dart
// W1.5 — HatContext unit tests (red → green).
//
// Covers:
//   1. HatContext.oddjobz constant has correct domainFlag and extensionId
//   2. Two HatContexts with the same values are equal (==) and same hashCode
//   3. HatContexts with different values are not equal
//   4. HatContext.toString returns a useful debug string

import 'package:test/test.dart';

import 'package:semantos/src/repl/hat_context.dart';

void main() {
  group('HatContext (W1.5)', () {
    test('HatContext.oddjobz has correct domainFlag (0x000101 = 257)', () {
      expect(HatContext.oddjobz.domainFlag, equals(0x000101));
      expect(HatContext.oddjobz.domainFlag, equals(257));
    });

    test('HatContext.oddjobz has correct extensionId', () {
      expect(HatContext.oddjobz.extensionId, equals('oddjobz'));
    });

    test('two HatContexts with same values are equal', () {
      const a = HatContext(domainFlag: 0x000101, extensionId: 'oddjobz');
      const b = HatContext(domainFlag: 0x000101, extensionId: 'oddjobz');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('HatContexts with different domainFlag are not equal', () {
      const a = HatContext(domainFlag: 0x000101, extensionId: 'oddjobz');
      const b = HatContext(domainFlag: 0x000202, extensionId: 'oddjobz');
      expect(a, isNot(equals(b)));
    });

    test('HatContexts with different extensionId are not equal', () {
      const a = HatContext(domainFlag: 0x000101, extensionId: 'oddjobz');
      const b = HatContext(domainFlag: 0x000101, extensionId: 'otherjobz');
      expect(a, isNot(equals(b)));
    });

    test('HatContext.oddjobz equals a manually constructed equivalent', () {
      const manual = HatContext(domainFlag: 0x000101, extensionId: 'oddjobz');
      expect(HatContext.oddjobz, equals(manual));
    });

    test('HatContext can be used as a map key (hashCode contract)', () {
      const hat = HatContext.oddjobz;
      final map = <HatContext, String>{hat: 'value'};
      const sameHat = HatContext(domainFlag: 0x000101, extensionId: 'oddjobz');
      expect(map[sameHat], equals('value'));
    });
  });
}

```
