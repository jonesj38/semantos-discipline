---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/gradient/oddjobz_extension_context_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.917803+00:00
---

# archive/apps-semantos-monolith/test/gradient/oddjobz_extension_context_test.dart

```dart
// 2026-05-07 — pins the canonical oddjobz extension constants +
// `oddjobzPipelineHatContext` mapping.  Bumping these constants
// without bumping the canonical capability page in
// `extensions/oddjobz/src/capabilities.ts` will cause K3 domain
// rejections at the kernel — keep them in lock-step.

import 'package:semantos/src/gradient/oddjobz_extension_context.dart';
import 'package:semantos/src/identity/child_cert_store.dart';
import 'package:test/test.dart';

void main() {
  group('oddjobz extension constants', () {
    test('domain flag is 0x00010100 (oddjobz canonical page)', () {
      expect(kOddjobzDomainFlag, equals(0x00010100));
    });

    test('extension id is "oddjobz"', () {
      expect(kOddjobzExtensionId, equals('oddjobz'));
    });

    test('max trust class is "interpretive"', () {
      expect(kOddjobzMaxTrustClass, equals('interpretive'));
    });
  });

  group('oddjobzPipelineHatContext', () {
    test('threads operator + child cert ids through to PipelineHatContext',
        () {
      final record = ChildCertRecord(
        devicePrivHex: 'aa' * 32,
        secureKeyHandle: '',
        childPubHex: 'bb' * 33,
        operatorRootPub: 'cc' * 33,
        operatorCertId: 'dd' * 16,
        contextTag: 1,
        label: 'test',
        capabilities: const [],
        brainPairEndpoint: 'https://brain.example.invalid/api/v1/repl',
        brainWssEndpoint: 'wss://brain.example.invalid/api/v1/wss',
        brainPinCertId: 'dd' * 16,
        brainPinPubkey: 'cc' * 33,
        bearer: '00' * 32,
      );

      final ctx = oddjobzPipelineHatContext(record);
      expect(ctx.hatId, equals(record.operatorCertId));
      expect(ctx.certId, equals(record.childPubHex));
      expect(ctx.domainFlag, equals(kOddjobzDomainFlag));
      expect(ctx.maxTrustClass, equals(kOddjobzMaxTrustClass));
      expect(ctx.extensionId, equals(kOddjobzExtensionId));
    });
  });
}

```
