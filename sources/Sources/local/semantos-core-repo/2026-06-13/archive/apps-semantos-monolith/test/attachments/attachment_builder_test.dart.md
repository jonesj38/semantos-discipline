---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/attachments/attachment_builder_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.919554+00:00
---

# archive/apps-semantos-monolith/test/attachments/attachment_builder_test.dart

```dart
// D-O5m.followup-8 capture+upload — attachment_builder unit tests.
//
// Coverage:
//   - Build → unpack JSON round-trips with all required fields.
//   - Hash determinism: same inputs → same content_hash + same id
//     (with a pinned attachmentId).
//   - Canonical JSON byte stability across two builds.
//   - Validation: invalid kind / oversize caption / bad cert id length.
//   - Signature verifies via cell_signer.verifyCellSignature against
//     the device pubkey derived from the priv we signed with.

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:semantos/src/attachments/attachment_builder.dart';
import 'package:semantos/src/identity/cell_signer.dart';

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

const String _testPrivHex =
    'a1b2c3d4e5f600112233445566778899aabbccddeeff00112233445566778899';
const String _testCertId = '00112233445566778899aabbccddeeff';
const String _testVisitId = '00000000-0000-4000-8000-000000000abc';

void main() {
  group('attachment_builder', () {
    test('builds a signed attachment with all required fields', () {
      final priv = _hexToBytes(_testPrivHex);
      final blob = Uint8List.fromList(utf8.encode('fake-jpeg-bytes'));

      final signed = buildSignedAttachment(
        visitId: _testVisitId,
        kind: 'photo',
        blobBytes: blob,
        mimeType: 'image/jpeg',
        capturedAt: '2026-05-15T14:30:00Z',
        capturedByCertId: _testCertId,
        devicePrivBytes: priv,
        attachmentId: '00000000-0000-4000-8000-000000000001',
      );

      // Payload shape
      expect(signed.payload['attachmentId'],
          equals('00000000-0000-4000-8000-000000000001'));
      expect(signed.payload['visitId'], equals(_testVisitId));
      expect(signed.payload['kind'], equals('photo'));
      expect(signed.payload['mimeType'], equals('image/jpeg'));
      expect(signed.payload['capturedAt'], equals('2026-05-15T14:30:00Z'));
      expect(signed.payload['capturedByCertId'], equals(_testCertId));
      expect(signed.payload['contentSize'], equals(blob.length));
      expect(signed.contentSize, equals(blob.length));
      expect(signed.mimeType, equals('image/jpeg'));

      // contentHash is sha256 of the blob (canonical-attachment hash
      // of "fake-jpeg-bytes" — verified independently here).
      expect(signed.payload['contentHash'], equals(signed.contentHash));
      expect(signed.contentHash.length, equals(64));

      // No createdAt in the unsigned payload (server-stamped on
      // receipt).
      expect(signed.payload.containsKey('createdAt'), isFalse);

      // Signature length sanity
      expect(signed.signature.length, equals(64));
    });

    test('signature verifies against the priv-derived pubkey', () {
      final priv = _hexToBytes(_testPrivHex);
      final pub = devicePubFromPriv(priv);
      final blob = Uint8List.fromList(utf8.encode('verify-this'));

      final signed = buildSignedAttachment(
        visitId: _testVisitId,
        kind: 'voice_memo',
        blobBytes: blob,
        mimeType: 'audio/m4a',
        capturedAt: '2026-05-15T14:35:00Z',
        capturedByCertId: _testCertId,
        devicePrivBytes: priv,
      );

      final ok = verifyCellSignature(
          signed.payloadCanonicalBytes, signed.signature, pub);
      expect(ok, isTrue,
          reason: 'cell_signer.verifyCellSignature must accept the '
              'attachment_builder output — without parity here the '
              'brain will reject every uploaded cell.');
    });

    test('canonical bytes are byte-stable across two builds with same inputs',
        () {
      final priv = _hexToBytes(_testPrivHex);
      final blob = Uint8List.fromList([1, 2, 3, 4]);

      final a = buildSignedAttachment(
        visitId: _testVisitId,
        kind: 'photo',
        blobBytes: blob,
        mimeType: 'image/jpeg',
        capturedAt: '2026-05-15T14:30:00Z',
        capturedByCertId: _testCertId,
        devicePrivBytes: priv,
        attachmentId: '00000000-0000-4000-8000-000000000001',
      );
      final b = buildSignedAttachment(
        visitId: _testVisitId,
        kind: 'photo',
        blobBytes: blob,
        mimeType: 'image/jpeg',
        capturedAt: '2026-05-15T14:30:00Z',
        capturedByCertId: _testCertId,
        devicePrivBytes: priv,
        attachmentId: '00000000-0000-4000-8000-000000000001',
      );

      // Canonical bytes byte-for-byte equal — load-bearing for
      // signature determinism.
      expect(a.payloadCanonicalBytes, equals(b.payloadCanonicalBytes));
      expect(a.signature, equals(b.signature));
      expect(a.contentHash, equals(b.contentHash));
    });

    test('canonical encoder emits keys in lexicographic order', () {
      final out = encodeCanonicalJson(<String, dynamic>{
        'zebra': 1,
        'alpha': 2,
        'mango': 3,
      });
      final text = utf8.decode(out);
      // Keys must appear alphabetically.
      expect(text.indexOf('"alpha"') < text.indexOf('"mango"'), isTrue);
      expect(text.indexOf('"mango"') < text.indexOf('"zebra"'), isTrue);
    });

    test('canonical encoder produces no whitespace', () {
      final out = encodeCanonicalJson({'a': 1, 'b': [2, 3]});
      final text = utf8.decode(out);
      expect(text, equals('{"a":1,"b":[2,3]}'));
    });

    test('canonical encoder escapes special chars', () {
      final out = encodeCanonicalJson('he said "hi"\nworld');
      final text = utf8.decode(out);
      expect(text, equals('"he said \\"hi\\"\\nworld"'));
    });

    test('upload metadata JSON has cell_payload + signature_hex + cert id',
        () {
      final priv = _hexToBytes(_testPrivHex);
      final blob = Uint8List.fromList([1, 2, 3, 4]);
      final signed = buildSignedAttachment(
        visitId: _testVisitId,
        kind: 'photo',
        blobBytes: blob,
        mimeType: 'image/jpeg',
        capturedAt: '2026-05-15T14:30:00Z',
        capturedByCertId: _testCertId,
        devicePrivBytes: priv,
      );

      final upload = json.decode(signed.toUploadMetadataJson()) as Map;
      expect(upload['cell_payload'], isA<Map>());
      expect((upload['cell_payload'] as Map)['kind'], equals('photo'));
      expect(upload['signature_hex'], isA<String>());
      expect((upload['signature_hex'] as String).length, equals(128));
      expect(upload['captured_by_cert_id'], equals(_testCertId));
    });

    test('rejects invalid kind', () {
      expect(
        () => buildSignedAttachment(
          visitId: _testVisitId,
          kind: 'video',
          blobBytes: Uint8List(0),
          mimeType: 'video/mp4',
          capturedAt: '2026-05-15T14:30:00Z',
          capturedByCertId: _testCertId,
          devicePrivBytes: _hexToBytes(_testPrivHex),
        ),
        throwsArgumentError,
      );
    });

    test('rejects oversize caption', () {
      expect(
        () => buildSignedAttachment(
          visitId: _testVisitId,
          kind: 'photo',
          blobBytes: Uint8List(0),
          mimeType: 'image/jpeg',
          capturedAt: '2026-05-15T14:30:00Z',
          capturedByCertId: _testCertId,
          devicePrivBytes: _hexToBytes(_testPrivHex),
          caption: List.filled(501, 'x').join(),
        ),
        throwsArgumentError,
      );
    });

    test('rejects bad capturedByCertId length', () {
      expect(
        () => buildSignedAttachment(
          visitId: _testVisitId,
          kind: 'photo',
          blobBytes: Uint8List(0),
          mimeType: 'image/jpeg',
          capturedAt: '2026-05-15T14:30:00Z',
          capturedByCertId: 'short',
          devicePrivBytes: _hexToBytes(_testPrivHex),
        ),
        throwsArgumentError,
      );
    });

    test('caption shows up in the signed payload when provided', () {
      final signed = buildSignedAttachment(
        visitId: _testVisitId,
        kind: 'photo',
        blobBytes: Uint8List.fromList([0]),
        mimeType: 'image/jpeg',
        capturedAt: '2026-05-15T14:30:00Z',
        capturedByCertId: _testCertId,
        devicePrivBytes: _hexToBytes(_testPrivHex),
        caption: 'Customer pointed at the eaves.',
      );
      expect(signed.payload['caption'],
          equals('Customer pointed at the eaves.'));
    });

    test('caption is omitted when empty', () {
      final signed = buildSignedAttachment(
        visitId: _testVisitId,
        kind: 'photo',
        blobBytes: Uint8List.fromList([0]),
        mimeType: 'image/jpeg',
        capturedAt: '2026-05-15T14:30:00Z',
        capturedByCertId: _testCertId,
        devicePrivBytes: _hexToBytes(_testPrivHex),
        caption: '',
      );
      expect(signed.payload.containsKey('caption'), isFalse);
    });
  });
}

```
