---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/bearer_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.466879+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/bearer_store.dart

```dart
// BearerStore — persists the operator bearer token across sessions.
// Uses shared_preferences (localStorage on web, NSUserDefaults on iOS,
// SharedPreferences on Android).

import 'package:shared_preferences/shared_preferences.dart';

class BearerStore {
  static const _key = 'oddjobz_bearer';

  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> save(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, token.trim());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

```
