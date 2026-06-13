---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/search_contacts_api.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.881807+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/search_contacts_api.dart

```dart
// Dio-backed client for POST /api/v1/search/contacts.
//
// W6 of CUSTOMER-CONV-LOOP-PLAN. Backed by the brain's
// runtime/semantos-brain/src/search_contacts_http.zig (W3.3-W3.5).
//
// Returns a list of ContactSearchHit — id + display name + phone
// + optional siteRef.  Used by the Talk|Direct search surface to
// surface contacts when the operator types a name OR a job address/
// suburb.

import 'package:dio/dio.dart';

class ContactSearchHit {
  /// Customer.v2 id (UUIDv4-ish). Use as conversationId on the
  /// ConversationSendApi.
  final String id;
  final String displayName;
  final String phone;
  final String? siteRef;

  const ContactSearchHit({
    required this.id,
    required this.displayName,
    required this.phone,
    this.siteRef,
  });

  factory ContactSearchHit.fromJson(Map<String, dynamic> json) {
    final raw = json['siteRef'];
    return ContactSearchHit(
      id: (json['id'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      siteRef: raw is String && raw.isNotEmpty ? raw : null,
    );
  }
}

class SearchContactsError implements Exception {
  /// Brain's `{"error":"<wire>"}` field. Known: unauthorised,
  /// malformed_body, empty_query, upstream_error.
  final String wire;
  final int httpStatus;
  const SearchContactsError({required this.wire, required this.httpStatus});

  @override
  String toString() => 'SearchContactsError(http=$httpStatus, wire="$wire")';

  String get userMessage {
    switch (wire) {
      case 'unauthorised':
        return 'Not authorised — please re-pair this device.';
      case 'empty_query':
        return 'Type something to search for.';
      case 'malformed_body':
        return 'Search request was rejected.';
      case 'upstream_error':
        return 'Search failed on the operator brain.';
      default:
        return 'Search failed ($httpStatus).';
    }
  }
}

class SearchContactsApi {
  final Dio _http;
  final String _baseUrl;
  final String Function() _bearer;

  SearchContactsApi({
    required Dio http,
    required String baseUrl,
    required String Function() bearer,
  })  : _http = http,
        _baseUrl = _stripTrailingSlash(baseUrl),
        _bearer = bearer;

  Future<List<ContactSearchHit>> search(String query) async {
    final resp = await _http.post<Map<String, dynamic>>(
      '$_baseUrl/api/v1/search/contacts',
      data: <String, dynamic>{'query': query},
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${_bearer()}',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );

    final status = resp.statusCode ?? 0;
    final data = resp.data ?? const <String, dynamic>{};

    if (status == 200 && data['matches'] is List) {
      final raw = data['matches'] as List;
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ContactSearchHit.fromJson)
          .toList(growable: false);
    }

    final wire = (data['error'] is String) ? data['error'] as String : '';
    throw SearchContactsError(wire: wire, httpStatus: status);
  }

  static String _stripTrailingSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}

```
