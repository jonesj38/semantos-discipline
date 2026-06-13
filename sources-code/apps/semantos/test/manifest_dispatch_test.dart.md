---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/manifest_dispatch_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.093039+00:00
---

# apps/semantos/test/manifest_dispatch_test.dart

```dart
// C9 PR-C9-7d — verifies that a manifest with `ui.verbs[].dispatch`
// blocks parses cleanly + that registering each verb's dispatch into
// IntentDispatcher.registerSpec produces working dispatchByName.
//
// This is the regression gate for the PR-C9-7d consolidation —
// catches drift between HelmUiVerbDispatch.fromJson and the shell
// boot loop in main.dart.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos_core/semantos_core.dart';
import 'package:semantos/src/brain/brain_http_client.dart';
import 'package:semantos/src/dispatch/intent_dispatcher.dart';

class _FixedMintAdapter implements HttpClientAdapter {
  final String cellType;
  final String cartridgeId;
  _FixedMintAdapter({required this.cellType, required this.cartridgeId});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"cellId":"abc","cartridgeId":"$cartridgeId","cellType":"$cellType","persistedAt":1}',
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('manifest ui.verbs[].dispatch → registerSpec', () {
    const manifestJson = '''
{
  "id": "betterment",
  "name": "Betterment",
  "version": "0.1.0",
  "domainFlag": "0x000201",
  "grammar": {
    "extensionId": "betterment",
    "lexicon": { "name": "betterment", "categories": [] },
    "defaultTaxonomyWhat": "betterment.practice",
    "objectTypes": [],
    "actions": []
  },
  "ui": {
    "surfacingMode": "default",
    "verbs": [
      {
        "modal": "do",
        "label": "Release",
        "intentType": "Release",
        "inputShape": {
          "kind": "multiline",
          "field": "rawText",
          "label": "What are you releasing?"
        },
        "dispatch": {
          "cellType": "betterment.practice.release",
          "triple": ["betterment", "practice", "release", ""],
          "defaultPayload": {
            "source": "keyboard",
            "prompt": "freeform",
            "elevation": 5
          }
        }
      },
      {
        "modal": "do",
        "label": "Set intention",
        "intentType": "SetIntention"
      }
    ]
  }
}
''';

    test('HelmUiVerb.fromJson parses dispatch block', () {
      final manifest = ExtensionManifest.fromJsonString(manifestJson);
      expect(manifest.uiVerbs, hasLength(2));

      final release = manifest.uiVerbs.first;
      expect(release.intentType, 'Release');
      expect(release.dispatch, isNotNull);
      expect(release.dispatch!.cellType, 'betterment.practice.release');
      expect(release.dispatch!.s1, 'betterment');
      expect(release.dispatch!.s2, 'practice');
      expect(release.dispatch!.s3, 'release');
      expect(release.dispatch!.s4, '');
      expect(release.dispatch!.defaultPayload['source'], 'keyboard');

      final setIntention = manifest.uiVerbs[1];
      expect(setIntention.intentType, 'SetIntention');
      expect(setIntention.dispatch, isNull,
          reason: 'verb without dispatch block surfaces as unwired');
    });

    test('main.dart-equivalent boot loop registers wired verbs only',
        () async {
      final manifest = ExtensionManifest.fromJsonString(manifestJson);
      final registry = GrammarRegistry.fromManifests([manifest]);

      final dispatcher = IntentDispatcher(
        brain: BrainHttpClient(
          baseUrl: 'https://example.brain',
          bearerToken: 't',
          dio: Dio()
            ..httpClientAdapter = _FixedMintAdapter(
              cellType: 'betterment.practice.release',
              cartridgeId: 'betterment',
            ),
        ),
      );

      // This loop MIRRORS the registration in apps/semantos/lib/main.dart
      // — keep this in sync if the boot loop changes.
      for (final m in registry.manifests) {
        for (final v in m.uiVerbs) {
          final d = v.dispatch;
          if (d == null) continue;
          dispatcher.registerSpec(
            intentTypeName: v.intentType,
            cartridgeId: m.id,
            cellType: d.cellType,
            s1: d.s1,
            s2: d.s2,
            s3: d.s3,
            s4: d.s4,
            defaultPayload: d.defaultPayload,
          );
        }
      }

      expect(dispatcher.hasBindingFor('Release'), isTrue);
      expect(dispatcher.hasBindingFor('SetIntention'), isFalse,
          reason: 'no dispatch block → no binding');

      final result = await dispatcher.dispatchByName(
        intentType: 'Release',
        payload: {'rawText': 'letting go'},
      );
      expect(result.mint.cellType, 'betterment.practice.release');
      expect(result.binding.defaultPayload['elevation'], 5,
          reason: 'cartridge default payload preserved in registered binding');
    });

    test('manifest with bad dispatch.triple shape throws FormatException', () {
      const bad = '''
{
  "id": "x",
  "name": "X",
  "version": "0.1.0",
  "domainFlag": 1,
  "grammar": {
    "extensionId": "x",
    "lexicon": { "name": "x", "categories": [] },
    "defaultTaxonomyWhat": "x",
    "objectTypes": [],
    "actions": []
  },
  "ui": {
    "verbs": [
      {
        "modal": "do",
        "label": "Bad",
        "intentType": "Bad",
        "dispatch": {
          "cellType": "x.y.z",
          "triple": []
        }
      }
    ]
  }
}
''';
      expect(
        () => ExtensionManifest.fromJsonString(bad),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

```
