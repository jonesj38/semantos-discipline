---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/quote_document_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.458958+00:00
---

# cartridges/oddjobz/experience/test/quote_document_test.dart

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oddjobz_experience/src/operator/quote_document.dart';

void main() {
  test('QuoteLineItem calculates totals and round-trips JSON', () {
    const item = QuoteLineItem(
      description: 'Labour',
      quantity: 2.5,
      unitCents: 9500,
      unit: 'hr',
      category: 'labour',
      sourceCatalogItemId: 'labour_hr',
      provenanceRefs: ['catalog:labour_hr', 'turn:t-1'],
    );

    expect(item.totalCents, 23750);
    expect(QuoteLineItem.fromJson(item.toJson()).totalCents, 23750);
    final roundTrip = QuoteLineItem.fromJson(item.toJson());
    expect(roundTrip.sourceCatalogItemId, 'labour_hr');
    expect(roundTrip.provenanceRefs, ['catalog:labour_hr', 'turn:t-1']);
  });

  test(
    'QuoteDocument folds editable line items into canonical quote request',
    () {
      final now = DateTime.utc(2026, 6, 12, 1, 2, 3);
      final doc = QuoteDocument.newForJob('job-1', now: now).copyWith(
        customerSummary: 'Repair roof leak and clean gutters.',
        notes: 'Assumes safe roof access.',
        lineItems: const [
          QuoteLineItem(
            description: 'Roof inspection',
            quantity: 1,
            unitCents: 16500,
            provenanceRefs: ['catalog:roof_inspection', 'turn:roof-1'],
          ),
          QuoteLineItem(
            description: 'Clean gutters',
            quantity: 1,
            unitCents: 18000,
          ),
        ],
      );

      expect(doc.totalCents, 34500);

      final wire = doc.toQuoteRequestJson();
      expect(wire['jobId'], 'job-1');
      expect(wire['costMin'], 34500);
      expect(wire['costMax'], 34500);
      expect(wire['customerSummary'], 'Repair roof leak and clean gutters.');
      expect(wire['assumptionNotes'], contains('Assumes safe roof access.'));
      expect(wire['lineItems'], isA<List<dynamic>>());
      expect((wire['lineItems'] as List).first['provenanceRefs'], [
        'catalog:roof_inspection',
        'turn:roof-1',
      ]);

      final roundTrip = QuoteDocument.fromJson(doc.toJson());
      expect(roundTrip.jobId, 'job-1');
      expect(roundTrip.createdAt, now);
      expect(roundTrip.lineItems, hasLength(2));
    },
  );
}

```
