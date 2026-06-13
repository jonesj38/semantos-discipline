---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/quote_catalog_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.456804+00:00
---

# cartridges/oddjobz/experience/test/quote_catalog_test.dart

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oddjobz_experience/src/operator/quote_catalog.dart';

void main() {
  test('example catalog contains optional service-business seed items', () {
    final ids = oddjobzExampleServiceCatalogItems
        .map((item) => item.id)
        .toSet();
    expect(ids, containsAll(<String>['labour_hr', 'callout', 'tap_washer']));
  });

  test('catalog items convert to quote line items', () {
    const item = QuoteCatalogItem(
      id: 'tap_washer',
      description: 'Replace tap washer',
      defaultQty: 2,
      unitCents: 3500,
      unit: 'ea',
      category: 'plumbing',
    );

    final line = item.toLineItem();
    expect(line.description, 'Replace tap washer');
    expect(line.totalCents, 7000);
    expect(line.sourceCatalogItemId, 'tap_washer');
    expect(item.priceLabel, r'$35.00 / ea');
  });

  test('catalog JSON helpers round trip lists', () {
    final encoded = encodeQuoteCatalogItems(
      oddjobzExampleServiceCatalogItems.take(2).toList(),
    );
    final decoded = parseQuoteCatalogItems(encoded);

    expect(decoded, hasLength(2));
    expect(decoded.first.id, oddjobzExampleServiceCatalogItems.first.id);
    expect(parseQuoteCatalogItems({'not': 'a list'}), isEmpty);
  });
}

```
