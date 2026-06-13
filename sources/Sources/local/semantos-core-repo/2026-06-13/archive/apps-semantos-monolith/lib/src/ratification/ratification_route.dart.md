---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/ratification/ratification_route.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.874218+00:00
---

# archive/apps-semantos-monolith/lib/src/ratification/ratification_route.dart

```dart
// D-O5m.followup-7 Phase B — `/ratify` route registration.
//
// HomeScreen owns the bearer-gated RatificationQueueClient; the
// `/ratify` route is pushed by PushNotificationRouter (post-#328) from
// outside the HomeScreen widget tree (the navigator key is at the
// MaterialApp level).  We use a process-level holder to bridge: when
// HomeScreen mounts, it stores the active client in
// [RatificationClientHolder]; when the route is pushed, the
// onGenerateRoute factory below looks the client up.
//
// On unpair / disconnect HomeScreen clears the holder so a stale client
// can't satisfy a route push from a previous session.

import 'package:flutter/material.dart';

import '../helm/ratification_card_screen.dart';
import 'ratification_queue_client.dart';

/// Process-level holder for the active RatificationQueueClient.  Set
/// by HomeScreen on mount, cleared on dispose.  Pure-Dart so the unit
/// tests can drive the holder without instantiating Flutter.
class RatificationClientHolder {
  static RatificationQueueClient? _active;

  /// Set the active client.  Called from HomeScreen.initState once
  /// the bearer + ChildCertRecord have been resolved.
  static void set(RatificationQueueClient client) {
    _active = client;
  }

  /// Clear the active client.  Called from HomeScreen.dispose.
  static void clear() {
    _active = null;
  }

  /// Read the active client.  Returns null when no HomeScreen is
  /// currently mounted — the route renders an error in that case.
  static RatificationQueueClient? get active => _active;
}

/// Match a `/ratify` route push and build the screen.  Returns null
/// for any other route name so the host MaterialApp's other route-
/// resolution paths aren't shadowed.
///
/// The route arguments map carries `lead_id`; PushNotificationRouter
/// (post-#328) populates this exactly.
Route<RatificationCardOutcome>? buildRatificationRoute(RouteSettings settings) {
  if (settings.name != '/ratify') return null;
  final args = settings.arguments;
  String? leadId;
  if (args is Map) {
    final v = args['lead_id'];
    if (v is String) leadId = v;
  }
  return MaterialPageRoute<RatificationCardOutcome>(
    settings: settings,
    builder: (ctx) {
      final client = RatificationClientHolder.active;
      if (client == null) {
        // Stale push (operator was logged out between the push
        // arriving and the tap, or the helm tree hasn't mounted yet).
        // Render the same NoLeadId-shaped "missing client" surface
        // — the operator hits Close and is dropped back to wherever
        // the navigator was previously.
        return const _MissingClientView();
      }
      return RatificationCardScreen(client: client, leadId: leadId);
    },
  );
}

class _MissingClientView extends StatelessWidget {
  const _MissingClientView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ratify lead?'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red),
              SizedBox(height: 12),
              Text(
                'Sign in to ratify leads.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

```
