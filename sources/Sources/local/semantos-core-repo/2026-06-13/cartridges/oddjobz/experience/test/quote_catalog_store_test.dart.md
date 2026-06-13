---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/quote_catalog_store_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.457080+00:00
---

# cartridges/oddjobz/experience/test/quote_catalog_store_test.dart

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oddjobz_experience/src/operator/quote_catalog.dart';
import 'package:oddjobz_experience/src/operator/quote_catalog_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'fresh operator catalog is unconfigured until explicitly saved',
    () async {
      final store = QuoteCatalogStore();

      expect(await store.load(), isEmpty);
    },
  );

  test('operator can save and reload a custom service catalog', () async {
    final store = QuoteCatalogStore();
    const custom = [
      QuoteCatalogItem(
        id: 'consulting_hour',
        description: 'Consulting',
        defaultQty: 1,
        unitCents: 22000,
        unit: 'hr',
        category: 'professional-services',
      ),
    ];

    await store.save(custom);
    final loaded = await store.load();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'consulting_hour');
    expect(loaded.single.unitCents, 22000);
  });

  test('example seed is opt-in, not an implicit default', () async {
    final store = QuoteCatalogStore();

    expect(await store.load(), isEmpty);

    await store.importExampleSeed();
    final loaded = await store.load();

    expect(loaded.map((item) => item.id), contains('callout'));
  });
}

```
