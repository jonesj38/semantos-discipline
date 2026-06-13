---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/quote_catalog_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.463215+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/quote_catalog_store.dart

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'quote_catalog.dart';

/// Local editable quote-catalog draft for the operator.
///
/// A fresh OddJobz operator is intentionally unconfigured.  OddJobz is a
/// visit-based service-business cartridge, not a fixed trade template; hosts
/// may offer seed examples, but the operator's catalog/policy is the source
/// of truth.
class QuoteCatalogStore {
  QuoteCatalogStore({this.prefsKey = _defaultPrefsKey});

  static const _defaultPrefsKey = 'oddjobz.quote_catalog.v1';
  final String prefsKey;

  Future<List<QuoteCatalogItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return parseQuoteCatalogItems(decoded);
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<QuoteCatalogItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(encodeQuoteCatalogItems(items)));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }

  Future<void> importExampleSeed() => save(oddjobzExampleServiceCatalogItems);
}

```
