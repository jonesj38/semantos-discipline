---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/intents.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.460473+00:00
---

# cartridges/oddjobz/experience/lib/src/intents.dart

```dart
import 'package:semantos_core/semantos_core.dart';

/// Pay a job milestone to a recipient.
class PayMilestone extends StructuredIntent {
  final String recipientPubkeyHex;
  final int amountSats;
  final String jobId;
  final String? milestoneId;
  const PayMilestone({
    required this.recipientPubkeyHex,
    required this.amountSats,
    required this.jobId,
    this.milestoneId,
  });
}

/// Transition a job to a new state.
class TransitionJob extends StructuredIntent {
  final String jobId;
  final String toState;
  const TransitionJob({required this.jobId, required this.toState});
}

/// Assign a worker to a job.
class AssignWorker extends StructuredIntent {
  final String jobId;
  final String workerPubkeyHex;
  const AssignWorker({required this.jobId, required this.workerPubkeyHex});
}

/// Request a quote for a job.
class RequestQuote extends StructuredIntent {
  final String jobId;
  final String? description;
  const RequestQuote({required this.jobId, this.description});
}

```
