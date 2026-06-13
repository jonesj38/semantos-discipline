---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/ratification_card_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.898726+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/ratification_card_screen.dart

```dart
// D-O5m.followup-7 Phase B — RatificationCardScreen.
//
// The route at `/ratify`.  PushNotificationRouter (post-#328) already
// pushes this route with `arguments: {'lead_id': '<id>'}` when an
// operator taps a `lead.created` push notification; pre-this-PR the
// navigator's `onUnknownRoute` fired and the router logged a warning
// (intentional, the brief tracked it as a deferred wiring).  This PR
// closes the loop end-to-end.
//
// The screen displays:
//   - lead summary card (customer name, phone/email, summary, source)
//   - source attribution + correlation id (collapsible — operator taps
//     to see the full conversation thread when source == 'chat')
//   - sticky bottom action bar with Defer / Reject / Ratify
//
// The state machine + button-tap → client.{ratify, reject, defer}
// dispatch live in [RatificationCardController]
// (`lib/src/ratification/ratification_card_controller.dart`); this
// widget is a thin wrapper that delegates to the controller.

import 'package:flutter/material.dart';

import '../ratification/ratification_card_controller.dart';
import '../ratification/ratification_queue_client.dart';

// Re-export the controller's public types so callers that only need
// the screen don't have to import both files.
export '../ratification/ratification_card_controller.dart';

/// Full-screen ratification card.  Pushed by `Navigator.pushNamed(
/// '/ratify', arguments: {'lead_id': '...'})` from
/// PushNotificationRouter or by tapping a row in LeadsListScreen.
class RatificationCardScreen extends StatefulWidget {
  /// The queue client.  Wired through HomeScreen → MaterialApp
  /// `onGenerateRoute` so the screen can drive ratify/reject/defer
  /// without re-constructing one per route push.
  final RatificationQueueClient client;

  /// Lead id from the route arguments.  When null/empty the screen
  /// renders the noLeadId state.
  final String? leadId;

  const RatificationCardScreen({
    super.key,
    required this.client,
    required this.leadId,
  });

  @override
  State<RatificationCardScreen> createState() => _RatificationCardScreenState();
}

class _RatificationCardScreenState extends State<RatificationCardScreen> {
  late final RatificationCardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RatificationCardController(
      client: widget.client,
      leadId: widget.leadId,
      onCompleted: (outcome) {
        if (!mounted) return;
        Navigator.of(context).pop<RatificationCardOutcome>(outcome);
      },
    );
    _controller.addListener(_rebuild);
    Future.microtask(_controller.load);
  }

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final phase = _controller.phase;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ratify lead?'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context)
              .pop<RatificationCardOutcome>(const RatificationCardDismissed()),
        ),
      ),
      body: switch (phase) {
        RatificationCardPhase.loading =>
          const Center(child: CircularProgressIndicator()),
        RatificationCardPhase.noLeadId => const _NoLeadIdView(),
        RatificationCardPhase.loadError => _LoadErrorView(
            error: _controller.errorMessage ?? 'unknown error',
            onRetry: _controller.load,
          ),
        RatificationCardPhase.ready ||
        RatificationCardPhase.submitting ||
        RatificationCardPhase.actionError ||
        RatificationCardPhase.succeeded =>
          _LeadView(controller: _controller),
      },
    );
  }
}

class _NoLeadIdView extends StatelessWidget {
  const _NoLeadIdView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            SizedBox(height: 12),
            Text(
              'No lead id supplied to /ratify route.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadErrorView extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;
  const _LoadErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text('Failed to load lead:\n$error',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _LeadView extends StatelessWidget {
  final RatificationCardController controller;
  const _LeadView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final lead = controller.lead;
    if (lead == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final submitting = controller.phase == RatificationCardPhase.submitting;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(
              lead.customerName.isEmpty ? '(no customer)' : lead.customerName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            if (lead.phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Icon(Icons.phone, size: 16),
                  const SizedBox(width: 6),
                  Text(lead.phone),
                ]),
              ),
            if (lead.email.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Icon(Icons.email, size: 16),
                  const SizedBox(width: 6),
                  Text(lead.email),
                ]),
              ),
            const SizedBox(height: 16),
            if (lead.summary.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(lead.summary),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'From ${lead.source.isEmpty ? "(unknown)" : lead.source} on '
              '${lead.createdAt}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (lead.sourceCorrelationId.isNotEmpty)
              ExpansionTile(
                title: const Text('Conversation ID'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(lead.sourceCorrelationId),
                  ),
                ],
              ),
            if (controller.phase == RatificationCardPhase.actionError)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        controller.errorMessage ?? 'Action failed',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: submitting ? null : () => controller.defer(),
                    child: const Text('Defer'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: submitting
                        ? null
                        : () => _openRejectSheet(context, controller),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: submitting ? null : () => controller.ratify(),
                    child: submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Ratify'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _openRejectSheet(
  BuildContext context,
  RatificationCardController controller,
) async {
  final reason = await showModalBottomSheet<RejectionReason>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Reject reason',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final r in RejectionReason.values)
              ListTile(
                title: Text(r.label),
                onTap: () => Navigator.of(ctx).pop(r),
              ),
          ],
        ),
      );
    },
  );
  if (reason != null) {
    await controller.reject(reason);
  }
}

```
