---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/quote_import_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.456260+00:00
---

# cartridges/oddjobz/experience/test/quote_import_service_test.dart

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oddjobz_experience/src/operator/brain_client.dart';
import 'package:oddjobz_experience/src/operator/conversation_turn.dart';
import 'package:oddjobz_experience/src/operator/quote_catalog.dart';
import 'package:oddjobz_experience/src/operator/quote_document.dart';
import 'package:oddjobz_experience/src/operator/quote_editor_screen.dart';
import 'package:oddjobz_experience/src/operator/quote_import_service.dart';

void main() {
  test(
    'fallback service uses deterministic import when edge route is absent',
    () async {
      final current = QuoteDocument.newForJob(
        'job-1',
        now: DateTime.utc(2026, 6, 13),
      );
      final service = FallbackScgQuoteImportService(
        primary: _ThrowingImportService(const BrainClientError(404, 'missing')),
        fallback: const DeterministicScgQuoteImportService(
          turns: [
            ConversationTurn(
              turnId: 't-price',
              conversationId: 'c',
              participantRole: 'external',
              direction: 'inbound',
              surface: 'sms',
              bodyText: 'Please include the \$80 access fee.',
              timestamp: 1,
            ),
          ],
        ),
      );

      final imported = await service.importFromSources(
        current: current,
        selectedPatches: const [
          QuoteSourcePatch(
            ref: 'turn:t-price',
            title: 'sms · tenant',
            body: 'Please include the \$80 access fee.',
          ),
        ],
        catalogItems: const <QuoteCatalogItem>[],
      );

      expect(imported.lineItems, hasLength(1));
      expect(imported.lineItems.single.unitCents, 8000);
      expect(imported.lineItems.single.provenanceRefs, ['turn:t-price']);
      expect(imported.notes, contains('Imported via SCG source selection'));
    },
  );

  test('fallback service rethrows non-missing edge errors', () async {
    final service = FallbackScgQuoteImportService(
      primary: _ThrowingImportService(const BrainClientError(500, 'boom')),
      fallback: const DeterministicScgQuoteImportService(turns: []),
    );

    expect(
      () => service.importFromSources(
        current: QuoteDocument.newForJob('job-1'),
        selectedPatches: const [],
        catalogItems: const [],
      ),
      throwsA(isA<BrainClientError>()),
    );
  });
}

class _ThrowingImportService implements ScgQuoteImportService {
  const _ThrowingImportService(this.error);

  final BrainClientError error;

  @override
  Future<QuoteDocument> importFromSources({
    required QuoteDocument current,
    required List<QuoteSourcePatch> selectedPatches,
    required List<QuoteCatalogItem> catalogItems,
  }) async {
    throw error;
  }
}

```
