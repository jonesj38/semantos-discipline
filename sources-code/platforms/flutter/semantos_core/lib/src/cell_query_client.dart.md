---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/cell_query_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.017274+00:00
---

# platforms/flutter/semantos_core/lib/src/cell_query_client.dart

```dart
import 'dart:async';
import 'dart:convert';

/// Brain-side cell.query primitive — generic projection over the cell DAG
/// by typeHash + filter expression.
///
/// Wraps the JSON-RPC method `cell.query(typeHash, filter, limit?, cursor?)`
/// exposed by the brain's WSS dispatcher.
///
/// Experiences compose this client-side via typed wrappers in their own
/// packages (e.g. JobsRepository in oddjobz_experience builds on
/// CellQueryClient.query(typeHash: jobTypeHash, ...) rather than calling
/// hardcoded oddjobz.find_jobs_at_site). New extensions get reads for
/// free — no brain code change needed.
///
/// This complements (not replaces) the existing typed oddjobz.* verbs
/// during the migration. Old call sites continue to work; new ones use
/// this primitive.
abstract class CellQueryClient {
  /// Query cells by [typeHash] (32-byte hex) with an optional [filter]
  /// expression. Returns a list of cells as JSON-encoded maps.
  ///
  /// [filter] is a brain-interpreted predicate map; the exact shape is
  /// extension-defined but typically: { "fieldName": value } for equality,
  /// or { "fieldName": { "$gt": v } } for ordered ops.
  ///
  /// [limit] caps results; [cursor] resumes a previous page.
  Future<CellQueryPage> query({
    required String typeHash,
    Map<String, dynamic>? filter,
    int? limit,
    String? cursor,
  });

  /// Single-cell getter shortcut. Returns null if not found.
  Future<Map<String, dynamic>?> getById({
    required String typeHash,
    required String cellRef,
  });
}

/// A page of cell.query results.
class CellQueryPage {
  /// The cell rows. Each is the cell's JSON payload as decoded by the
  /// brain's typed view-store — fields per the cell type's schema.
  final List<Map<String, dynamic>> cells;

  /// Opaque continuation token if more results are available, else null.
  final String? nextCursor;

  /// Total count reported by the brain (may be approximate for large sets).
  final int? totalCount;

  const CellQueryPage({
    required this.cells,
    this.nextCursor,
    this.totalCount,
  });

  factory CellQueryPage.fromJson(Map<String, dynamic> json) {
    final cellsRaw = json['cells'];
    final cells = (cellsRaw is List)
        ? cellsRaw
            .whereType<Map<String, dynamic>>()
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    return CellQueryPage(
      cells: cells,
      nextCursor: json['nextCursor'] as String?,
      totalCount: json['totalCount'] as int?,
    );
  }
}

/// Errors thrown by CellQueryClient implementations.
class CellQueryException implements Exception {
  final String message;
  final int? code;
  const CellQueryException(this.message, {this.code});

  @override
  String toString() =>
      code != null ? 'CellQueryException($code): $message' : 'CellQueryException: $message';
}

/// JSON-RPC request envelope helper. Exposed for transport implementations
/// (the actual WSS / HTTP send is platform code).
class CellQueryRpc {
  /// Build the `cell.query` JSON-RPC params object.
  static Map<String, dynamic> queryParams({
    required String typeHash,
    Map<String, dynamic>? filter,
    int? limit,
    String? cursor,
  }) {
    return {
      'typeHash': typeHash,
      if (filter != null) 'filter': filter,
      if (limit != null) 'limit': limit,
      if (cursor != null) 'cursor': cursor,
    };
  }

  /// Build the `cell.get` JSON-RPC params object.
  static Map<String, dynamic> getParams({
    required String typeHash,
    required String cellRef,
  }) {
    return {'typeHash': typeHash, 'cellRef': cellRef};
  }

  /// Decode a brain JSON-RPC response body into a [CellQueryPage].
  /// Throws [CellQueryException] on error responses.
  static CellQueryPage decodePage(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const CellQueryException('cell.query response not a JSON object');
    }
    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      throw CellQueryException(
        (error['message'] as String?) ?? 'unknown error',
        code: error['code'] as int?,
      );
    }
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) {
      throw const CellQueryException('cell.query result missing or not an object');
    }
    return CellQueryPage.fromJson(result);
  }
}

```
