---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/identity/auth_state.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.594532+00:00
---

# cartridges/jambox/mobile/lib/src/identity/auth_state.dart

```dart
// D-O5m — Mobile auth state machine.
//
// Mirrors the model in `apps/loom-svelte/src/lib/auth.ts` (the desktop
// helm SPA's auth state) but with FlutterSecureStorage-backed
// persistence instead of localStorage. The same three states carry
// over:
//
//   - authenticated : ChildCertStore has a full record, bearer is
//                     populated. The helm UI is available.
//   - unauthenticated : no record persisted. The pairing screen is
//                       the only available route.
//   - pending : transient — the pairing service is mid-flight, or the
//               REPL client just got a 401 and we need to clear and
//               redirect to pairing.

import 'child_cert_store.dart';

/// Tagged union of the three auth states. Pattern-match by `kind` in
/// the helm router.
sealed class AuthState {
  const AuthState();
}

class AuthAuthenticated extends AuthState {
  final ChildCertRecord record;
  const AuthAuthenticated(this.record);
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthPending extends AuthState {
  const AuthPending();
}

/// Snapshot the current auth state by reading the cert store. Async
/// because the underlying secure storage is platform-channel-backed.
Future<AuthState> currentAuthState(ChildCertStore store) async {
  final record = await store.read();
  if (record == null) return const AuthUnauthenticated();
  if (record.bearer.isEmpty) return const AuthUnauthenticated();
  return AuthAuthenticated(record);
}

/// Clear persisted auth — called on REPL 401 (the brain rejected our
/// bearer) or on an operator-initiated unpair.
Future<void> clearAuth(ChildCertStore store) => store.clear();

```
