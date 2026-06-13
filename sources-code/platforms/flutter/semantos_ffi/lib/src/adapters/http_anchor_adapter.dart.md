---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/lib/src/adapters/http_anchor_adapter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.009302+00:00
---

# platforms/flutter/semantos_ffi/lib/src/adapters/http_anchor_adapter.dart

```dart
// HttpAnchorAdapter — Anchor service client with offline queue.
//
// Batches state hashes and submits them to an anchor service via HTTP.
// When offline, queues requests in SQLite and flushes when connectivity
// is restored.

import 'dart:convert' show json, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// HTTP-based anchor adapter with offline queue.
class HttpAnchorAdapter {
  final Dio _dio;
  final String _endpoint;
  Database? _queueDb;

  HttpAnchorAdapter({
    required String endpoint,
    Dio? dio,
  })  : _endpoint = endpoint,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
            ));

  /// Initialize the offline queue database.
  Future<void> open() async {
    if (_queueDb != null) return;

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/semantos_anchor_queue.db';

    _queueDb = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE anchor_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            state_hash BLOB NOT NULL,
            metadata_json TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending'
          )
        ''');
      },
    );
  }

  /// Submit a state hash for anchoring. Tries HTTP first; queues on failure.
  Future<Uint8List> submit(
    Uint8List stateHash,
    String metadataJson,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/anchor/batch',
        data: {
          'state_hash': _bytesToHex(stateHash),
          'metadata': json.decode(metadataJson),
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final proofJson = json.encode(response.data!);
        return Uint8List.fromList(utf8.encode(proofJson));
      }

      throw DioException(
        requestOptions: response.requestOptions,
        message: 'Anchor batch failed: ${response.statusCode}',
      );
    } on DioException {
      // Network failure — queue for later.
      await _enqueue(stateHash, metadataJson);
      // Return a pending proof placeholder.
      final pending = json.encode({
        'status': 'queued',
        'state_hash': _bytesToHex(stateHash),
        'queued_at': DateTime.now().toIso8601String(),
      });
      return Uint8List.fromList(utf8.encode(pending));
    }
  }

  /// Verify an anchor proof against the anchor service.
  Future<bool> verify(Uint8List proof, Uint8List stateHash) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/anchor/verify',
        data: {
          'proof': json.decode(utf8.decode(proof)),
          'state_hash': _bytesToHex(stateHash),
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data!['valid'] == true;
      }
      return false;
    } on DioException {
      return false;
    }
  }

  /// Flush the offline queue — resubmit all pending anchor requests.
  Future<int> flushQueue() async {
    final db = _queueDb;
    if (db == null) return 0;

    final pending = await db.query(
      'anchor_queue',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );

    var flushed = 0;
    for (final row in pending) {
      final id = row['id'] as int;
      final stateHash = row['state_hash'] as Uint8List;
      final metadataJson = row['metadata_json'] as String;

      try {
        await _dio.post(
          '$_endpoint/anchor/batch',
          data: {
            'state_hash': _bytesToHex(stateHash),
            'metadata': json.decode(metadataJson),
          },
        );
        await db.update(
          'anchor_queue',
          {'status': 'submitted'},
          where: 'id = ?',
          whereArgs: [id],
        );
        flushed++;
      } on DioException {
        // Still offline — stop flushing.
        break;
      }
    }
    return flushed;
  }

  /// Close the queue database.
  Future<void> close() async {
    await _queueDb?.close();
    _queueDb = null;
  }

  Future<void> _enqueue(Uint8List stateHash, String metadataJson) async {
    final db = _queueDb;
    if (db == null) return;
    await db.insert('anchor_queue', {
      'state_hash': stateHash,
      'metadata_json': metadataJson,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'status': 'pending',
    });
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

```
