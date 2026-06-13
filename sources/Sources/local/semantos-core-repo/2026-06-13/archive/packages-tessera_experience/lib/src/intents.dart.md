---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-tessera_experience/lib/src/intents.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.829338+00:00
---

# archive/packages-tessera_experience/lib/src/intents.dart

```dart
import 'package:semantos_core/semantos_core.dart';

/// Record a harvest event — origin of the care chain. Produces an
/// AFFINE `tessera.grape-lot` (or analogue) cell.
class Harvest extends StructuredIntent {
  final String lotId;
  final String? block;
  final int? brixAtPick;
  final int? tonnage;
  const Harvest({
    required this.lotId,
    this.block,
    this.brixAtPick,
    this.tonnage,
  });
}

/// Bottle a barrel — produce N LINEAR `tessera.bottle` cells from one
/// barrel cell.
class Bottle extends StructuredIntent {
  final String barrelId;
  final int count;
  const Bottle({required this.barrelId, required this.count});
}

/// Transfer custody of a case / pallet / shipment to another operator.
class TransferCustody extends StructuredIntent {
  final String cellId;
  final String toOperatorCertId;
  const TransferCustody({
    required this.cellId,
    required this.toOperatorCertId,
  });
}

/// Record an AFFINE care-event (temp-logger reading, thermo flag) on a
/// shipment chain.
class RecordCareEvent extends StructuredIntent {
  final String shipmentId;
  final int severity;
  final String? note;
  const RecordCareEvent({
    required this.shipmentId,
    required this.severity,
    this.note,
  });
}

/// Anonymous consumer scan — produces a RELEVANT `tessera.scan-event`
/// cell on the bottle chain. (Driven from the field-app for the
/// club-member hat; the anonymous PWA path is a separate codebase.)
class ConsumerScan extends StructuredIntent {
  final String bottleId;
  const ConsumerScan({required this.bottleId});
}

/// Mark a bottle's tamper-loop seal broken. Self-authorising — the
/// tamper-loop break is its own evidence (no capability required).
/// Single LINEAR transition `intact → broken` per the V5.2 theorem.
class MarkTamper extends StructuredIntent {
  final String bottleId;
  const MarkTamper({required this.bottleId});
}

```
