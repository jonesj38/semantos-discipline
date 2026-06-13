---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/oddjobz_query_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.881515+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/oddjobz_query_client.dart

```dart
// D-DOG.1.0c Phase 3 F.1 — graph-aware query RPC client.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
//            sub-deliverable F.1.b;
//            runtime/semantos-brain/src/oddjobz_query_handler.zig — server side;
//            runtime/semantos-brain/src/wss_wallet.zig — JSON-RPC dispatch.
//
// Wraps the brain's eight `oddjobz.*` query verbs that landed in
// PR #375 (Phase 2B.3).  These are JSON-RPC over WSS — same socket
// HelmEventStream uses for `helm.subscribe` / `helm.fetch_since` —
// not REPL commands.  The mobile app already maintains a long-lived
// WSS via HelmEventStream; this client rides that same channel via
// HelmEventStream's `callOddjobzQuery` helper.
//
// Why a dedicated client (rather than another method on
// JobsRepository): the eight verbs span four resources (sites,
// customers, jobs, attachments) and include cross-store queries
// (find_jobs_at_site, find_jobs_for_customer) that don't belong to
// any single repository.  A single OddjobzQueryClient with typed
// methods + Dart models keeps the call-sites readable and lets the
// wave-2 site-pivot / customer-pivot screens (F.2 / F.3) reuse it.
//
// Scope for F.1: the JobList screen calls `listSites()` +
// `listCustomers()` for the bulk-fetch enrichment pattern.  The
// other six verbs are wired here for wave-2 (F.2 / F.3 / F.4) so
// those don't need to touch this file.

import 'dart:async';

import 'helm_event_stream.dart';

// [OddjobzQueryError] is defined in helm_event_stream.dart (the
// reply-routing logic there synthesises it from JSON-RPC error
// envelopes; we'd otherwise have a circular import).  Re-export
// from this file so the JobList screen can `catch` it without
// importing helm_event_stream directly.
export 'helm_event_stream.dart' show OddjobzQueryError;

/// One row of the `oddjobz.list_sites` / `oddjobz.get_site` response.
///
/// Mirrors the Semantos Brain-side `oddjobz_query_handler.writeSite` wire shape
/// 1:1.  All v2-required fields are non-null; the few legacy-shape
/// optional fields (suburb, postcode, state, keyNumber) carry through
/// nullable.  v1 site rows aren't reachable through these verbs (the
/// brain sites store only persists v2 cells), so every Site value here
/// is graph-aware.
class OddjobzSite {
  /// 64-lowercase-hex content hash of the canonical `site.v2` cell —
  /// the cell-DAG primary key.  This is what `Job.siteRef` points at.
  final String cellId;

  /// 64-lowercase-hex `oddjobz.site.v2` typeHash; same value across
  /// every v2 site row.  Carried so a future v3 type can coexist in
  /// the same store without breaking the helm's index.
  final String typeHash;

  /// Canonical lowercase-and-collapsed-whitespace form of the full
  /// address — THE dedupe key for site lookup-or-mint.  Mirrors
  /// `oddjobz.site.v2.normalisedAddress`.
  final String normalisedAddress;

  /// Optional "key #N" suffix parsed out separately so two units in
  /// the same building don't collapse during lookup.  Null when the
  /// source PDF didn't disclose one.
  final String? keyNumber;

  /// Derived `<normalisedAddress>|<keyNumber-or-empty>` — what
  /// Phase 2's lookup-or-mint hashes on.
  final String lookupKey;

  /// Operator-friendly full address (re-cased, with unit number etc.)
  /// — what the JobList renders as the row's "property" line.  This
  /// is the Semantos Brain-side `Site.fullAddress`, not normalisedAddress.
  final String fullAddress;

  /// Optional locality fields surfaced for the F.2 site-pivot screen;
  /// F.1 doesn't render them but parses for completeness.
  final String? suburb;
  final String? postcode;
  final String? state;

  /// Unix-seconds creation timestamp — the Semantos Brain side emits as i64.
  final int createdAt;

  const OddjobzSite({
    required this.cellId,
    required this.typeHash,
    required this.normalisedAddress,
    required this.keyNumber,
    required this.lookupKey,
    required this.fullAddress,
    required this.suburb,
    required this.postcode,
    required this.state,
    required this.createdAt,
  });

  /// Parse a single Site row from the wire shape (the JSON-RPC
  /// dispatcher emits it via `oddjobz_query_handler::writeSite`).
  /// Tolerates missing optional fields by defaulting them to null /
  /// empty / 0 — the helm renders "—" for the missing ones rather
  /// than crashing.
  factory OddjobzSite.fromJson(Map<String, dynamic> r) => OddjobzSite(
        cellId: (r['cellId'] ?? '').toString(),
        typeHash: (r['typeHash'] ?? '').toString(),
        normalisedAddress: (r['normalisedAddress'] ?? '').toString(),
        keyNumber: r['keyNumber'] is String && (r['keyNumber'] as String).isNotEmpty
            ? r['keyNumber'] as String
            : null,
        lookupKey: (r['lookupKey'] ?? '').toString(),
        fullAddress: (r['fullAddress'] ?? '').toString(),
        suburb: r['suburb'] is String && (r['suburb'] as String).isNotEmpty
            ? r['suburb'] as String
            : null,
        postcode:
            r['postcode'] is String && (r['postcode'] as String).isNotEmpty
                ? r['postcode'] as String
                : null,
        state: r['state'] is String && (r['state'] as String).isNotEmpty
            ? r['state'] as String
            : null,
        createdAt: r['createdAt'] is int
            ? r['createdAt'] as int
            : (r['createdAt'] is num ? (r['createdAt'] as num).toInt() : 0),
      );
}

/// One row of the `oddjobz.list_customers` / `oddjobz.get_customer`
/// response.
///
/// The brain-side handler emits both v1 and v2 customer rows through
/// the same wire shape — v1 rows have `cellId`, `typeHash`, `role`,
/// `normalisedPhone`, `sourceProvenance`, `siteRef` all null.  v2
/// rows populate them.  Distinguish via [isV2] (true when cellId is
/// non-null).  The JobList screen's enrichment map keys on EITHER
/// the v2 cellId (when present) OR the legacy v1 string id (when
/// not) so v1 rows still resolve when a job's customerRefs[].cellId
/// somehow points at a v1 row's id.
class OddjobzCustomer {
  /// Legacy v1 string id (UUID-ish).  Always populated.
  final String id;

  /// Operator-supplied display name — what the JobList renders as
  /// the "primary customer" field.  Mirrors v1's behaviour for
  /// backward-compat.
  final String displayName;

  final String phone;
  final String email;
  final String address;

  /// 64-lowercase-hex content hash of the canonical `customer.v2`
  /// cell.  Null on v1 rows.  This is what `JobCustomerRef.cellId`
  /// points at.
  final String? cellId;

  /// 64-lowercase-hex `oddjobz.customer.v2` typeHash.  Null on v1.
  final String? typeHash;

  /// One of `tenant | agent | owner | pm | sub-tradie | other`.
  /// Free-form so a future role addition doesn't bump the model.
  /// Null on v1 rows.
  final String? role;

  /// 64-lowercase-hex cellId of the customer's `site.v2` cell, when
  /// the brain has linked them (it does so on lookup-or-mint).  Null
  /// on v1.  Used by the F.3 customer-pivot screen.
  final String? siteRef;

  /// True iff this is a v2 (graph-aware) row, i.e. has a cellId.
  bool get isV2 => cellId != null;

  const OddjobzCustomer({
    required this.id,
    required this.displayName,
    required this.phone,
    required this.email,
    required this.address,
    required this.cellId,
    required this.typeHash,
    required this.role,
    required this.siteRef,
  });

  /// Parse one Customer row.  Mirrors `writeCustomer` from the Semantos Brain
  /// query handler.  v1 rows: every v2 field becomes null.
  factory OddjobzCustomer.fromJson(Map<String, dynamic> r) {
    String? optStr(dynamic v) =>
        (v is String && v.isNotEmpty) ? v : null;
    return OddjobzCustomer(
      id: (r['id'] ?? '').toString(),
      displayName: (r['display_name'] ?? r['displayName'] ?? '').toString(),
      phone: (r['phone'] ?? '').toString(),
      email: (r['email'] ?? '').toString(),
      address: (r['address'] ?? '').toString(),
      cellId: optStr(r['cellId']),
      typeHash: optStr(r['typeHash']),
      role: optStr(r['role']),
      siteRef: optStr(r['siteRef']),
    );
  }
}


/// Typed client over the brain's `oddjobz.*` query verbs.  Stateless
/// apart from the [HelmEventStream] reference it dispatches through;
/// the long-lived WSS lifecycle is owned by HelmEventStream itself.
///
/// All methods throw:
///   - [StateError] — when the underlying WSS isn't open (the caller
///     must `connect()` first; HomeScreen does this at boot).
///   - [OddjobzQueryError] — on a JSON-RPC error reply from the brain.
///   - [TimeoutException] — when the brain doesn't reply within the
///     supplied timeout (defaults to 10s, plenty for these queries).
class OddjobzQueryClient {
  final HelmEventStream _stream;

  /// Default timeout for any single RPC.  Operators on flaky cell
  /// connections still see a useful error rather than a hung list
  /// screen if the WSS is alive but the brain process is wedged.
  final Duration timeout;

  OddjobzQueryClient(
    this._stream, {
    // 2026-05-07: bumped default from 10s → 30s — same rationale as
    // OddjobzAttentionClient (operator-realistic data volumes were
    // tripping the 10s budget over Caddy → brain reactor on residential
    // bandwidth; Bridget flagged this on ngrok demo too).  Most
    // calls still complete in <500ms.
    this.timeout = const Duration(seconds: 30),
  });

  /// `oddjobz.list_sites()` — every persisted `site.v2` cell.  Used
  /// by JobList's bulk-fetch enrichment to resolve siteRef →
  /// fullAddress in O(1) per row instead of N round-trips.
  Future<List<OddjobzSite>> listSites() async {
    final result = await _stream.callOddjobzQuery(
      'oddjobz.list_sites',
      const <String, dynamic>{},
      timeout: timeout,
    );
    final raw = result['sites'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(OddjobzSite.fromJson)
        .toList();
  }

  /// `oddjobz.list_customers()` — every customer row, both v1 and
  /// v2.  Used by JobList's bulk-fetch enrichment to resolve
  /// `JobCustomerRef.cellId` → `displayName`.  v1 rows are returned
  /// too so a job whose primary customer never got upgraded to v2
  /// still resolves.
  Future<List<OddjobzCustomer>> listCustomers() async {
    final result = await _stream.callOddjobzQuery(
      'oddjobz.list_customers',
      const <String, dynamic>{},
      timeout: timeout,
    );
    final raw = result['customers'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(OddjobzCustomer.fromJson)
        .toList();
  }

  /// `oddjobz.get_site(siteRef)` — single Site lookup.  Returns null
  /// when the brain returns the typed `{site: null}` miss envelope
  /// (the cellRef doesn't match any persisted cell).  Reserved for
  /// wave-2 (F.2 site-pivot screen); F.1 uses [listSites] instead.
  Future<OddjobzSite?> getSite(String siteRef) async {
    final result = await _stream.callOddjobzQuery(
      'oddjobz.get_site',
      {'siteRef': siteRef},
      timeout: timeout,
    );
    final raw = result['site'];
    if (raw is! Map<String, dynamic>) return null;
    return OddjobzSite.fromJson(raw);
  }

  /// `oddjobz.get_customer(customerRef)` — single Customer lookup.
  /// Wave-2 (F.3 customer-pivot screen).
  Future<OddjobzCustomer?> getCustomer(String customerRef) async {
    final result = await _stream.callOddjobzQuery(
      'oddjobz.get_customer',
      {'customerRef': customerRef},
      timeout: timeout,
    );
    final raw = result['customer'];
    if (raw is! Map<String, dynamic>) return null;
    return OddjobzCustomer.fromJson(raw);
  }

  /// `oddjobz.get_job(jobRef)` — single Job lookup by 64-hex cellRef.
  /// Returns the raw map; the caller (typically `JobsRepository`)
  /// re-shapes through `parseJobOne` for parser unification.  Wave-2
  /// users (F.2 / F.3 / F.4) consume this directly.
  Future<Map<String, dynamic>?> getJob(String jobRef) async {
    final result = await _stream.callOddjobzQuery(
      'oddjobz.get_job',
      {'jobRef': jobRef},
      timeout: timeout,
    );
    final raw = result['job'];
    if (raw is! Map<String, dynamic>) return null;
    return raw;
  }

  /// `oddjobz.find_jobs_at_site(siteRef)` — every v2 job whose
  /// `siteRef == argument`.  Wave-2 (F.2).  Returns raw maps so the
  /// caller can route through `parseJobs` for the same shape as
  /// findJobs() / find_calendar() / find_attention().
  Future<List<Map<String, dynamic>>> findJobsAtSite(String siteRef) async {
    final result = await _stream.callOddjobzQuery(
      'oddjobz.find_jobs_at_site',
      {'siteRef': siteRef},
      timeout: timeout,
    );
    final raw = result['jobs'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  /// `oddjobz.find_jobs_for_customer(customerRef)` — every v2 job
  /// whose customerRefs contains the argument.  Wave-2 (F.3).
  Future<List<Map<String, dynamic>>> findJobsForCustomer(
    String customerRef,
  ) async {
    final result = await _stream.callOddjobzQuery(
      'oddjobz.find_jobs_for_customer',
      {'customerRef': customerRef},
      timeout: timeout,
    );
    final raw = result['jobs'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  /// `oddjobz.find_attachments_for_job(jobRef)` — every v2 PDF /
  /// photo attachment linked to the given job.  Wave-2 (F.4).
  Future<List<Map<String, dynamic>>> findAttachmentsForJob(
    String jobRef,
  ) async {
    final result = await _stream.callOddjobzQuery(
      'oddjobz.find_attachments_for_job',
      {'jobRef': jobRef},
      timeout: timeout,
    );
    final raw = result['attachments'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }
}

```
