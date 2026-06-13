---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-tessera_experience/lib/src/tessera_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.828760+00:00
---

# archive/packages-tessera_experience/lib/src/tessera_client.dart

```dart
import 'package:semantos_core/semantos_core.dart';

/// Typed Dart facade over [VerbDispatchClient] for the tessera extension's
/// 14 declared action verbs.
///
/// Composes on top of the generic primitive: callers say
/// `await client.harvest(lotId: "L1", grower: "alice", volumeMl: 1000)`
/// and the brain receives a
/// `verb.dispatch({extensionId: "tessera", verb: "tessera.harvest",
/// params: {lotId, grower, volumeMl}})` JSON-RPC call. The transport
/// binding (WSS / HTTP) is injected via [VerbDispatchClient]; this
/// class stays transport-agnostic.
///
/// Method names match the verbs declared in `cartridges/tessera/
/// cartridge.json`; payload shapes match the brain-side walker
/// contracts in `cartridges/tessera/brain/tessera_walkers.zig`.
///
/// Result shapes mirror the brain after the P3/P4 wave:
/// every mint-side verb returns either a [MintAck] (`{ok:true, id,
/// cellId, persisted}`) or a [MintRefusal] (`{ok:false, reason}`).
/// `bottle` returns a [MultiMintAck] (N successor cells) or refusal.
/// `ownerIdHex` (32-hex) is accepted on every method per P3e — when
/// omitted, the brain stamps a zero owner.
class TesseraClient {
  final VerbDispatchClient _dispatch;

  const TesseraClient(this._dispatch);

  /// Extension id this client targets. Matches cartridge.json.
  static const String extensionId = 'tessera';

  // ─── Producer surface ─────────────────────────────────────────────

  /// Record a harvest event — origin of the care chain. Mints an
  /// AFFINE `tessera.grape-lot` cell.
  Future<MintResult> harvest({
    required String lotId,
    required String grower,
    required int volumeMl,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.harvest',
      params: {
        'lotId': lotId,
        'grower': grower,
        'volumeMl': volumeMl,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  /// Rack a measured volume of a grape lot into a barrel. Mints a
  /// LINEAR `tessera.barrel`; consumes the grape-lot's cell.
  Future<MintResult> rack({
    required String lotId,
    required String barrelId,
    required int volumeMl,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.rack',
      params: {
        'lotId': lotId,
        'barrelId': barrelId,
        'volumeMl': volumeMl,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  /// Blend N input barrels into one out-barrel. Mints a LINEAR
  /// `tessera.barrel`; consumes each input barrel's cell.
  /// `declaredOutMl` is conservation-checked against the input volumes
  /// by the brain (K15 — `blend_not_conserved` refusal).
  Future<MintResult> blend({
    required String outBarrelId,
    required List<String> inBarrelIds,
    required int declaredOutMl,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.blend',
      params: {
        'outBarrelId': outBarrelId,
        'inBarrelIds': inBarrelIds,
        'declaredOutMl': declaredOutMl,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  /// Bottle a barrel — mints N LINEAR `tessera.bottle` cells (one per
  /// `bottleId`); consumes the source barrel.
  Future<MultiMintResult> bottle({
    required String barrelId,
    required List<String> bottleIds,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.bottle',
      params: {
        'barrelId': barrelId,
        'bottleIds': bottleIds,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MultiMintResult.fromJson(result);
  }

  /// Assemble a case from N bottles. Mints a LINEAR `tessera.case`;
  /// consumes each bottle.
  Future<MintResult> assembleCase({
    required String caseId,
    required String holder,
    required List<String> bottleIds,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.assemble-case',
      params: {
        'caseId': caseId,
        'holder': holder,
        'bottleIds': bottleIds,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  /// Open a custody container (pallet / shipment / case). Mints the
  /// initial container cell in the custody chain — no predecessor.
  /// `kind` ∈ {"pallet", "shipment", "case"} (unknown kinds map to case).
  Future<MintResult> openContainer({
    required String id,
    required String kind,
    required String holder,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.open-container',
      params: {
        'id': id,
        'kind': kind,
        'holder': holder,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  // ─── Custody surface ──────────────────────────────────────────────

  /// Open a custody hand-off. Mints a new container cell (same type as
  /// the original) carrying the in-flight state; consumes the prior
  /// container cell. The container's domain `id` stays constant; the
  /// substrate `cellId` advances.
  Future<MintResult> transferCustody({
    required String id,
    required String from,
    required String to,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.transfer-custody',
      params: {
        'id': id,
        'from': from,
        'to': to,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  /// Close a custody hand-off by confirming receipt. Mints a new
  /// container cell carrying the settled state; consumes the in-flight
  /// cell. The container's domain `id` stays constant.
  Future<MintResult> confirmReceipt({
    required String id,
    required String who,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.confirm-receipt',
      params: {
        'id': id,
        'who': who,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  // ─── Care-event family (AFFINE) ───────────────────────────────────

  /// Record an AFFINE care-event against a container (logger reading,
  /// inspection mark, …). The container is the parent; no new
  /// lookupable entity is created.
  Future<MintResult> recordCareEvent({
    required String containerId,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.record-care-event',
      params: {
        'containerId': containerId,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  /// Care-event family — operator-reported quality issue. Same brain
  /// path as [recordCareEvent].
  Future<MintResult> reportQualityIssue({
    required String containerId,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.report-quality-issue',
      params: {
        'containerId': containerId,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  /// Care-event family — manual log of a flipped thermochromic sticker.
  Future<MintResult> thermoFlag({
    required String containerId,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.thermo-flag',
      params: {
        'containerId': containerId,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  // ─── Bottle-state events ──────────────────────────────────────────

  /// Mark a bottle's tamper-loop seal broken. Terminal AFFINE one-shot
  /// per the V5.2 theorem — a second tamper on the same bottle refuses
  /// with `already_tampered`.
  Future<MintResult> tamper({
    required String bottleId,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.tamper',
      params: {
        'bottleId': bottleId,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  /// Anonymous-or-named consumer scan of a bottle. Produces a RELEVANT
  /// `tessera.scan-event` cell — must exist for the Care Score view
  /// to render (V5.6).
  Future<MintResult> consumerScan({
    required String bottleId,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.consumer-scan',
      params: {
        'bottleId': bottleId,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }

  /// Attach a DEBUG-class tasting note to a bottle. Inert: never gates
  /// any cap or transition.
  Future<MintResult> addTastingNote({
    required String bottleId,
    String? ownerIdHex,
  }) async {
    final result = await _dispatch.dispatch(
      extensionId: extensionId,
      verb: 'tessera.add-tasting-note',
      params: {
        'bottleId': bottleId,
        if (ownerIdHex != null) 'ownerIdHex': ownerIdHex,
      },
    );
    return MintResult.fromJson(result);
  }
}

// ─── Result types ─────────────────────────────────────────────────

/// Outcome of any single-cell mint-side verb.
///
/// Sealed: callers use a `switch (result)` or `if (result is MintAck)`
/// to discriminate success from refusal. A [MintRefusal] is a normal
/// domain outcome (`lot_not_found`, `blend_not_conserved`,
/// `already_tampered`, `unknown_predecessor`, `cell_already_consumed`,
/// …) — not an exception. Transport / protocol failures still throw
/// [VerbDispatchException].
sealed class MintResult {
  const MintResult();

  factory MintResult.fromJson(Map<String, dynamic> json) {
    if (json['ok'] == true) {
      return MintAck(
        id: (json['id'] as String?) ?? '',
        cellId: (json['cellId'] as String?) ?? '',
        persisted: (json['persisted'] as bool?) ?? false,
      );
    }
    return MintRefusal(reason: (json['reason'] as String?) ?? 'unknown');
  }
}

/// Successful single-cell mint. The brain has performed the FSM
/// transition AND minted the substrate cell (and, when bound, persisted
/// + spent any predecessor under the P4 protocol).
final class MintAck extends MintResult {
  /// Domain id of the entity this verb produced or affected
  /// (lotId / barrelId / bottleId / caseId / containerId / etc).
  final String id;

  /// 64-hex SHA-256 of the cell bytes. Stable per (cell type, owner,
  /// payload). Two harvests of the same lotId with the same owner
  /// yield the same cellId — explicit duplicates surface as
  /// `duplicate_id` refusals via the FSM rather than overlapping mints.
  final String cellId;

  /// `true` when the cell was written to the substrate CellStore (the
  /// brain was launched with the store wired in). `false` in dry-run
  /// / unit-test mode — the cellId is still authoritative but no
  /// persistence happened.
  final bool persisted;

  const MintAck({required this.id, required this.cellId, required this.persisted});
}

/// Domain refusal of a mint-side verb. Carries the kebab-case `reason`
/// from the brain — the same string the FSM produced (e.g.
/// `lot_not_found`, `bottle_tampered`) or the P4 consume protocol
/// (e.g. `unknown_predecessor`, `cell_already_consumed`). Treat as a
/// normal outcome, not an error.
final class MintRefusal extends MintResult {
  final String reason;
  const MintRefusal({required this.reason});
}

/// Outcome of `bottle` — the only N-successor verb. Same shape as
/// [MintResult] except `cellIds` is plural.
sealed class MultiMintResult {
  const MultiMintResult();

  factory MultiMintResult.fromJson(Map<String, dynamic> json) {
    if (json['ok'] == true) {
      final raw = json['cellIds'];
      final cellIds = raw is List
          ? raw.map((e) => e as String).toList(growable: false)
          : const <String>[];
      return MultiMintAck(
        id: (json['id'] as String?) ?? '',
        cellIds: cellIds,
        persisted: (json['persisted'] as bool?) ?? false,
      );
    }
    return MultiMintRefusal(reason: (json['reason'] as String?) ?? 'unknown');
  }
}

/// Successful multi-cell mint. Today only `bottle` produces this; one
/// `MintAck`-equivalent per bottle, all sharing the same source
/// barrel's `consumedCellIds` audit (P4d).
final class MultiMintAck extends MultiMintResult {
  final String id;
  final List<String> cellIds;
  final bool persisted;
  const MultiMintAck({
    required this.id,
    required this.cellIds,
    required this.persisted,
  });
}

/// Domain refusal of the multi-cell mint.
final class MultiMintRefusal extends MultiMintResult {
  final String reason;
  const MultiMintRefusal({required this.reason});
}

```
