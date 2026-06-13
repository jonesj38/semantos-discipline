---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/rpc/brain_rpc_client_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.128942+00:00
---

# apps/semantos/test/rpc/brain_rpc_client_test.dart

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/rpc/brain_rpc_client.dart';
import 'package:semantos/src/rpc/rpc_error.dart';

void main() {
  BrainRpcClient newClient() =>
      BrainRpcClient(baseUrl: 'https://brain.example.com', bearer: 'a' * 64);

  group('rpcUri', () {
    test('https → wss with /api/v1/rpc + bearer query', () {
      final uri = newClient().rpcUri;
      expect(uri.scheme, 'wss');
      expect(uri.path, '/api/v1/rpc');
      expect(uri.queryParameters['bearer'], 'a' * 64);
      expect(uri.host, 'brain.example.com');
    });

    test('port-less https resolves to :443, never :0 (regression)', () {
      // Dart's Uri has no default port for wss, so a port-less https base URL
      // used to render as wss://host:0/... and the WSS upgrade always failed.
      final uri = newClient().rpcUri;
      expect(uri.port, 443);
      expect(uri.toString(), isNot(contains(':0/')));
    });

    test('explicit https port is preserved', () {
      final uri = BrainRpcClient(baseUrl: 'https://brain.example.com:8443', bearer: 'a' * 64).rpcUri;
      expect(uri.port, 8443);
    });

    test('http → ws', () {
      final uri = BrainRpcClient(baseUrl: 'http://127.0.0.1:8799', bearer: 'b' * 64).rpcUri;
      expect(uri.scheme, 'ws');
      expect(uri.port, 8799);
    });
  });

  group('frame dispatch', () {
    test('res frame completes the pending call with its result object', () async {
      final c = newClient();
      final fut = c.awaitPendingForTest('c1');
      c.handleRawFrame('{"t":"res","id":"c1","result":{"jobs":[{"id":"j1"}]}}');
      final result = await fut;
      expect(result['jobs'], isA<List>());
      expect((result['jobs'] as List).length, 1);
    });

    test('err frame surfaces a typed RpcError', () async {
      final c = newClient();
      final fut = c.awaitPendingForTest('c2');
      c.handleRawFrame('{"t":"err","id":"c2","code":"forbidden","message":"need cap"}');
      await expectLater(
        fut,
        throwsA(isA<RpcError>()
            .having((e) => e.code, 'code', 'forbidden')
            .having((e) => e.isForbidden, 'isForbidden', true)
            .having((e) => e.id, 'id', 'c2')),
      );
    });

    test('unknown id is ignored (no crash, no completion)', () {
      final c = newClient();
      // No pending registered for "ghost" — must not throw.
      expect(
        () => c.handleRawFrame('{"t":"res","id":"ghost","result":{}}'),
        returnsNormally,
      );
    });

    test('push frame is emitted on the pushes stream', () async {
      final c = newClient();
      final got = expectLater(
        c.pushes,
        emits(isA<RpcPush>()
            .having((p) => p.channel, 'channel', 'hat.events')
            .having((p) => p.payload['job_id'], 'payload.job_id', 'x')),
      );
      c.handleRawFrame(
          '{"t":"push","sub":"s1","channel":"hat.events","payload":{"job_id":"x"}}');
      await got;
    });

    test('malformed frame is ignored', () {
      final c = newClient();
      expect(() => c.handleRawFrame('not json'), returnsNormally);
      expect(() => c.handleRawFrame('[1,2,3]'), returnsNormally);
    });
  });
}

```
