---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/customers_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.879427+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/customers_repository.dart

```dart
// D-O5.followup-3 — CustomerList view-shape repository.
//
// Mirrors the parser in `apps/loom-svelte/src/views/CustomerList.svelte`'s
// `parseCustomers` and the shape of `jobs_repository.dart`'s
// `parseJobs`.  Backed by the Semantos Brain dispatcher's typed `customers`
// resource (runtime/semantos-brain/src/resources/customers_handler.zig); both the
// `find customers` and `find customer <id>` REPL verbs route through
// that resource and emit canonical JSON.  The TSV fallback stays in
// place for backwards-compat with any operator wiring a different
// upstream — same hedge as `parseJobs` post-D-O5.followup-1.
//
// Field shape mirrors a SUBSET of the canonical `oddjobz.customer.v1`
// cell payload — enough for the helm CustomerList table + drill-down
// detail view.  Notes are populated only for the find-by-id detail
// path; the list view omits them to keep payloads compact.
//
// D-O5.followup-4 client hooks — when a [HelmEventStream] is supplied,
// the repo subscribes to `customer.created` notifications and surfaces
// them as [CustomersCacheEvent]s on [cacheEvents].  Mirrors the shape
// of `jobs_repository.dart` post-#318.

import 'dart:async';
import 'dart:convert';

import 'helm_event_stream.dart';
import 'repl_client.dart';

/// Single row of the helm Customers view.
class Customer {
  final String id;
  final String displayName;
  final String phone;
  final String email;
  final String address;
  final String notes;
  final String createdAt;

  const Customer({
    required this.id,
    required this.displayName,
    required this.phone,
    required this.email,
    required this.address,
    required this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'phone': phone,
        'email': email,
        'address': address,
        'notes': notes,
        'created_at': createdAt,
      };
}

/// D-O5.followup-4 — cache-invalidation event surfaced by
/// [CustomersRepository] when the live stream delivers a
/// `customer.created` notification.  Screens (`CustomerListScreen`,
/// `CustomerDetailScreen`) subscribe to
/// [CustomersRepository.cacheEvents] and refresh themselves on each
/// emission.  Mirrors `JobsCacheEvent` post-#318.
class CustomersCacheEvent {
  /// The customer id that changed.  Empty when the upstream payload
  /// didn't carry an id (defensive; the Semantos Brain emit always populates it).
  final String customerId;

  const CustomersCacheEvent({required this.customerId});
}

/// Repository over the REPL — the helm screens call this rather than
/// hand-parsing the REPL response themselves.
///
/// D-O5.followup-4 — when a [HelmEventStream] is supplied, the repo
/// subscribes to `customer.created` notifications and surfaces them as
/// [CustomersCacheEvent]s on [cacheEvents].  Screens listen to the
/// cache-event stream and refresh themselves on each emission.  When
/// the stream is null (tests, pull-only mode) the cacheEvents stream
/// is silent — no emissions, ever — and the repo behaves as it did
/// pre-followup-4.
class CustomersRepository {
  final ReplClient _repl;
  final StreamController<CustomersCacheEvent> _cacheCtl =
      StreamController<CustomersCacheEvent>.broadcast();
  StreamSubscription<HelmEvent>? _eventSub;

  CustomersRepository(this._repl, {HelmEventStream? eventStream}) {
    if (eventStream != null) {
      _eventSub = eventStream.events.listen(_onHelmEvent);
    }
  }

  /// Stream of cache-invalidation events the helm screens listen to.
  /// Broadcast — multiple screens can subscribe simultaneously.
  Stream<CustomersCacheEvent> get cacheEvents => _cacheCtl.stream;

  /// Release the event subscription + close the cache stream.  Call
  /// on logout / unpair so the next pairing starts with a clean
  /// repository.
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    if (!_cacheCtl.isClosed) await _cacheCtl.close();
  }

  void _onHelmEvent(HelmEvent event) {
    if (event.type != 'customer.created') return;
    final id = event.data['id'];
    if (id is! String || id.isEmpty) return;
    _cacheCtl.add(CustomersCacheEvent(customerId: id));
  }

  /// Fetch the operator's customers. Throws ReplUnauthorisedError on
  /// 401 (the helm screen catches that and transitions to the pairing
  /// screen); other typed exceptions propagate verbatim so the helm
  /// screen can surface them in-line.
  Future<List<Customer>> findCustomers() async {
    final resp = await _repl.send('find customers');
    return parseCustomers(resp.result);
  }

  /// Fetch a single customer by id via the typed `customers.find_by_id`
  /// resource command.  The brain dispatcher emits a single-object body
  /// (or a `{error: "not_found", id}` envelope when missing); we parse
  /// either shape and return null on miss / parse failure.
  Future<Customer?> findCustomer(String id) async {
    // The REPL verb `find customer <id>` emits a single JSON object
    // straight from the dispatcher (notes included).  Same parser
    // posture as parseCustomers but consumes a single object.
    final resp = await _repl.send('find customer $id');
    return parseCustomerOne(resp.result);
  }
}

/// Parse the REPL's `find customers` output into [Customer] rows.
///
/// Mirrors the desktop helm's parser in
/// `apps/loom-svelte/src/views/CustomerList.svelte` exactly:
///   1. JSON if the trimmed result starts with `[` or `{` — return
///      typed rows;
///   2. otherwise, tab-separated lines (`# id\tdisplay_name\tphone\temail\taddress\tcreated_at`,
///      header line skipped);
///   3. otherwise, the empty list.
List<Customer> parseCustomers(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];

  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    try {
      final parsed = json.decode(trimmed);
      if (parsed is List) {
        return parsed
            .whereType<Map<String, dynamic>>()
            .map(_customerFromJson)
            .toList();
      }
    } catch (_) {
      // Fall through to TSV.
    }
  }

  // TSV / line fallback — REPL's text emit is line-based.
  final lines = trimmed
      .split('\n')
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  return lines
      .map((line) {
        final cols = line.split('\t');
        if (cols.length < 2) return null;
        return Customer(
          id: cols[0],
          displayName: cols[1],
          phone: cols.length > 2 ? cols[2] : '',
          email: cols.length > 3 ? cols[3] : '',
          address: cols.length > 4 ? cols[4] : '',
          notes: '',
          createdAt: cols.length > 5 ? cols[5] : '',
        );
      })
      .whereType<Customer>()
      .toList();
}

/// Parse a single-customer response (from `customers.find_by_id`).
/// Returns null on a `{"error":"not_found", ...}` envelope or any
/// parse failure — the caller surfaces a "no longer exists" message.
Customer? parseCustomerOne(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return null;
  try {
    final parsed = json.decode(trimmed);
    if (parsed is Map<String, dynamic>) {
      // Typed not_found envelope — handler returns this when the id
      // doesn't exist (200 with the typed body).
      if (parsed['error'] == 'not_found') return null;
      if (parsed['display_name'] == null) return null;
      return _customerFromJson(parsed);
    }
    if (parsed is List && parsed.isNotEmpty) {
      // Defensive: if the upstream emits a single-element array, peel
      // it.  parseCustomers handles this branch too; mirror here so
      // drill-down keeps working.
      final first = parsed.first;
      if (first is Map<String, dynamic>) return _customerFromJson(first);
    }
  } catch (_) {
    // Fall through to null.
  }
  return null;
}

Customer _customerFromJson(Map<String, dynamic> row) => Customer(
      id: (row['id'] ?? '').toString(),
      displayName: (row['display_name'] ?? row['name'] ?? '').toString(),
      phone: (row['phone'] ?? '').toString(),
      email: (row['email'] ?? '').toString(),
      address: (row['address'] ?? '').toString(),
      notes: (row['notes'] ?? '').toString(),
      createdAt: (row['created_at'] ?? '').toString(),
    );

```
