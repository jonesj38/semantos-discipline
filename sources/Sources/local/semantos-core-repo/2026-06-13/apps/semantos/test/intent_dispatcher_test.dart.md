---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/intent_dispatcher_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.093323+00:00
---

# apps/semantos/test/intent_dispatcher_test.dart

```dart
// Unit tests for IntentDispatcher. Uses a stub StructuredIntent (no
// dep on betterment_experience to keep this test in the shell tree) and a
// mock BrainHttpClient via Dio's MockAdapter.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos_core/semantos_core.dart' show StructuredIntent;
import 'package:semantos/src/brain/brain_http_client.dart';
import 'package:semantos/src/dispatch/intent_dispatcher.dart';

class _StubReleaseIntent extends StructuredIntent {
  final String rawText;
  const _StubReleaseIntent(this.rawText);
}

class _OtherIntent extends StructuredIntent {
  const _OtherIntent();
}

/// Minimal Dio adapter that returns a fixed JSON response for any request.
class _StubMintAdapter implements HttpClientAdapter {
  final Map<String, dynamic> response;
  _StubMintAdapter(this.response);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final body =
        '{"cellId":"${response['cellId']}",'
        '"cartridgeId":"${response['cartridgeId']}",'
        '"cellType":"${response['cellType']}",'
        '"persistedAt":${response['persistedAt']}}';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Captures the outgoing request body so signed-path tests can assert the
/// wire shape, then returns a fixed mint response.
class _CapturingMintAdapter implements HttpClientAdapter {
  Object? lastBody;
  final Map<String, dynamic> response;
  _CapturingMintAdapter(this.response);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    lastBody = options.data;
    final body =
        '{"cellId":"${response['cellId']}",'
        '"cartridgeId":"${response['cartridgeId']}",'
        '"cellType":"${response['cellType']}",'
        '"persistedAt":${response['persistedAt']}}';
    return ResponseBody.fromString(
      body,
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
  group('IntentDispatcher', () {
    late BrainHttpClient brain;
    late IntentDispatcher dispatcher;

    setUp(() {
      final dio = Dio()
        ..httpClientAdapter = _StubMintAdapter({
          'cellId':
              '2002206665f7e6f4cdc6c90b7b425fc4fba53b0589aa2ffd7560e923834f504a',
          'cartridgeId': 'betterment',
          'cellType': 'betterment.practice.release',
          'persistedAt': 1779920150423,
        });
      brain = BrainHttpClient(
        baseUrl: 'https://oddjobtodd.info',
        bearerToken: 'fake-token',
        dio: dio,
      );
      dispatcher = IntentDispatcher(brain: brain);
    });

    test(
      'dispatch with registered binding returns IntentDispatchResult',
      () async {
        dispatcher.register<_StubReleaseIntent>(
          IntentBinding<_StubReleaseIntent>(
            intentType: _StubReleaseIntent,
            cartridgeId: 'betterment',
            cellType: 'betterment.practice.release',
            s1: 'betterment',
            s2: 'practice',
            s3: 'release',
            s4: '',
            payloadBuilder: (i) => {
              'rawText': i.rawText,
              'source': 'keyboard',
              'prompt': 'freeform',
              'elevation': 5,
            },
          ),
        );

        final result = await dispatcher.dispatch(
          const _StubReleaseIntent('I am letting go.'),
        );

        expect(
          result.mint.cellId,
          '2002206665f7e6f4cdc6c90b7b425fc4fba53b0589aa2ffd7560e923834f504a',
        );
        expect(result.mint.cartridgeId, 'betterment');
        expect(result.mint.cellType, 'betterment.practice.release');
        expect(result.binding.cellType, 'betterment.practice.release');
      },
    );

    test(
      'dispatch WITH a signer routes through the signed-mint wire',
      () async {
        final adapter = _CapturingMintAdapter({
          'cellId': 'abc',
          'cartridgeId': 'betterment',
          'cellType': 'betterment.practice.release',
          'persistedAt': 1,
        });
        final signedDispatcher =
            IntentDispatcher(
              brain: BrainHttpClient(
                baseUrl: 'https://oddjobtodd.info',
                bearerToken: 'fake-token',
                dio: Dio()..httpClientAdapter = adapter,
              ),
              signer: (payload) =>
                  (signatureHex: '11' * 64, signerCertIdHex: 'deadbeef'),
            )..registerSpec(
              intentTypeName: 'Release',
              cartridgeId: 'betterment',
              cellType: 'betterment.practice.release',
              s1: 'betterment',
              s2: 'practice',
              s3: 'release',
            );

        await signedDispatcher.dispatchByName(
          intentType: 'Release',
          payload: {'rawText': 'x'},
        );

        final body = adapter.lastBody as Map<String, dynamic>;
        expect(body['signatureHex'], equals('11' * 64));
        expect(body['signerCertIdHex'], equals('deadbeef'));
        expect(body.containsKey('payload'), isTrue);
      },
    );

    test('dispatch WITHOUT a signer uses the unsigned-mint wire', () async {
      final adapter = _CapturingMintAdapter({
        'cellId': 'abc',
        'cartridgeId': 'betterment',
        'cellType': 'betterment.practice.release',
        'persistedAt': 1,
      });
      final plainDispatcher =
          IntentDispatcher(
            brain: BrainHttpClient(
              baseUrl: 'https://oddjobtodd.info',
              bearerToken: 'fake-token',
              dio: Dio()..httpClientAdapter = adapter,
            ),
          )..registerSpec(
            intentTypeName: 'Release',
            cartridgeId: 'betterment',
            cellType: 'betterment.practice.release',
            s1: 'betterment',
            s2: 'practice',
            s3: 'release',
          );

      await plainDispatcher.dispatchByName(
        intentType: 'Release',
        payload: {'rawText': 'x'},
      );

      final body = adapter.lastBody as Map<String, dynamic>;
      expect(body.containsKey('signatureHex'), isFalse);
      expect(body.containsKey('signerCertIdHex'), isFalse);
    });

    test(
      'dispatch without registered binding throws UnboundIntentError',
      () async {
        await expectLater(
          dispatcher.dispatch(const _OtherIntent()),
          throwsA(isA<UnboundIntentError>()),
        );
      },
    );

    test('registeredIntentTypes lists registered intent types', () {
      expect(dispatcher.registeredIntentTypes, isEmpty);
      dispatcher.register<_StubReleaseIntent>(
        IntentBinding<_StubReleaseIntent>(
          intentType: _StubReleaseIntent,
          cartridgeId: 'betterment',
          cellType: 'betterment.practice.release',
          s1: 'betterment',
          s2: 'practice',
          s3: 'release',
          payloadBuilder: (i) => {'rawText': i.rawText},
        ),
      );
      expect(dispatcher.registeredIntentTypes, [_StubReleaseIntent]);
    });

    test('double-registering same intentType throws StateError', () {
      final binding1 = IntentBinding<_StubReleaseIntent>(
        intentType: _StubReleaseIntent,
        cartridgeId: 'betterment',
        cellType: 'betterment.practice.release',
        s1: 'betterment',
        s2: 'practice',
        s3: 'release',
        payloadBuilder: (i) => {'rawText': i.rawText},
      );
      dispatcher.register<_StubReleaseIntent>(binding1);

      expect(
        () => dispatcher.register<_StubReleaseIntent>(binding1),
        throwsA(isA<StateError>()),
      );
    });

    // C9 PR-C9-7c — spec registration + name-keyed dispatch
    test(
      'registerSpec + dispatchByName round-trips through the brain',
      () async {
        dispatcher.registerSpec(
          intentTypeName: 'Release',
          cartridgeId: 'betterment',
          cellType: 'betterment.practice.release',
          s1: 'betterment',
          s2: 'practice',
          s3: 'release',
          defaultPayload: {
            'source': 'keyboard',
            'prompt': 'freeform',
            'elevation': 5,
          },
        );

        final result = await dispatcher.dispatchByName(
          intentType: 'Release',
          payload: {'rawText': 'I am letting go.'},
        );

        expect(result.mint.cellType, 'betterment.practice.release');
        expect(result.binding.intentTypeName, 'Release');
        expect(result.binding.defaultPayload, contains('source'));
      },
    );

    test(
      'dispatchByName with unregistered name throws UnboundIntentError',
      () async {
        await expectLater(
          dispatcher.dispatchByName(intentType: 'Unknown', payload: const {}),
          throwsA(isA<UnboundIntentError>()),
        );
      },
    );

    test(
      'duplicate manifest intent names are rejected to prevent cross-cartridge dispatch bleed',
      () {
        dispatcher.registerSpec(
          intentTypeName: 'Release',
          cartridgeId: 'betterment',
          cellType: 'betterment.practice.release',
          s1: 'betterment',
          s2: 'practice',
          s3: 'release',
        );

        expect(
          () => dispatcher.registerSpec(
            intentTypeName: 'Release',
            cartridgeId: 'oddjobz',
            cellType: 'oddjobz.release',
            s1: 'oddjobz',
            s2: 'release',
            s3: 'write',
          ),
          throwsStateError,
          reason:
              'Name-keyed dispatch is global; duplicate names must fail loudly rather than bleed across cartridges.',
        );
      },
    );

    test('hasBindingFor reflects name-keyed registrations', () {
      expect(dispatcher.hasBindingFor('Release'), isFalse);
      dispatcher.registerSpec(
        intentTypeName: 'Release',
        cartridgeId: 'betterment',
        cellType: 'betterment.practice.release',
        s1: 'betterment',
        s2: 'practice',
        s3: 'release',
      );
      expect(dispatcher.hasBindingFor('Release'), isTrue);
      expect(dispatcher.hasBindingFor('SetIntention'), isFalse);
    });
  });
}

```
