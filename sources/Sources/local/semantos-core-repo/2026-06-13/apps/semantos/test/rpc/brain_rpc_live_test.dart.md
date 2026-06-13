---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/rpc/brain_rpc_live_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.128666+00:00
---

# apps/semantos/test/rpc/brain_rpc_live_test.dart

```dart
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/rpc/brain_rpc_client.dart';
import 'package:semantos/src/rpc/rpc_error.dart';

/// Live end-to-end test of BrainRpcClient against a running brain.
///
///   export BRAIN_DATA_DIR=$(mktemp -d /tmp/rpc.XXXXXX)
///   B=runtime/semantos-brain/zig-out/bin/brain
///   TOKEN=$($B bearer issue --label live | awk '/Token \(copy/{f=1;next} f&&/[0-9a-f]{64}/{print $1;exit}')
///   $B serve localhost --enable-repl --port 8810 &
///   RPC_PORT=8810 RPC_TOKEN=$TOKEN flutter test --tags live test/rpc/brain_rpc_live_test.dart
///
/// Skips when RPC_PORT / RPC_TOKEN are absent.
void main() {
  final port = Platform.environment['RPC_PORT'];
  final token = Platform.environment['RPC_TOKEN'];

  test('cell.query + repl.eval round-trip over the live channel', () async {
    if (port == null || token == null) {
      markTestSkipped('set RPC_PORT + RPC_TOKEN to run the live brain test');
      return;
    }
    final client = BrainRpcClient(baseUrl: 'http://127.0.0.1:$port', bearer: token);
    await client.connect();
    try {
      // repl.eval routes and returns real output.
      final status = await client.replEval('status');
      expect(status, contains('config:'));

      // cell.query routes to the live generic handler. A bare brain has no
      // oddjobz decoder registered, so it answers with a structured
      // not_found err — which still proves the method ROUTED (the whole point
      // vs the legacy wss_wallet path that dropped the branch entirely).
      await expectLater(
        client.cellQuery('oddjobz.job.v2'),
        throwsA(isA<RpcError>().having((e) => e.code, 'code', 'not_found')),
      );
    } finally {
      await client.close();
    }
  });
}

```
