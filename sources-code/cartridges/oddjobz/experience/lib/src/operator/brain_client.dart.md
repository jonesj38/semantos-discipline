---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/brain_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.461713+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/brain_client.dart

```dart
// BrainClient — bearer-gated HTTP client for the oddjobz operator PWA.
//
// Wraps:
//   POST /api/v1/repl              — typed REPL commands
//   GET  /api/v1/conversation/turns — conversation turns query
//   POST /api/v1/conversation/turn/:id/approve — approve proposed turn
//   POST /api/v1/voice-note         — add an operator note/voice transcript
//
// When deployed at the same origin as the brain (oddjobtodd.info),
// the baseUrl is derived from the current page origin.  Callers can
// override for testing.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'conversation_turn.dart';
import 'job.dart';
import 'quote_catalog.dart';
import 'quote_document.dart';
import 'quote_editor_screen.dart' show QuoteSourcePatch;

class AttachmentUploadResult {
  final String id;
  final String status;

  const AttachmentUploadResult({required this.id, required this.status});
}

class BrainClientError implements Exception {
  final int statusCode;
  final String message;
  const BrainClientError(this.statusCode, this.message);

  @override
  String toString() => 'BrainClientError($statusCode): $message';

  bool get isUnauthorised => statusCode == 401;
}

class BrainClient {
  final String baseUrl;
  final String bearer;
  final http.Client _http;

  BrainClient({
    required this.baseUrl,
    required this.bearer,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $bearer',
    'Content-Type': 'application/json',
  };

  // ── REPL ────────────────────────────────────────────────────────────────

  /// Send a REPL command; returns the raw result string.
  Future<String> repl(String cmd) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/api/v1/repl'),
      headers: _headers,
      body: jsonEncode({'cmd': cmd}),
    );
    _checkStatus(resp);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return (body['result'] as String? ?? '').trim();
  }

  // ── Jobs ────────────────────────────────────────────────────────────────

  Future<List<Job>> findJobs() async {
    final raw = await repl('find jobs');
    if (raw.isEmpty) return const [];
    final parsed = jsonDecode(raw);
    if (parsed is! List) return const [];
    return parsed.map((e) => Job.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Job?> findJob(String id) async {
    final raw = await repl('find job $id');
    if (raw.isEmpty) return null;
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) return null;
    return Job.fromJson(parsed);
  }

  Future<String> quoteJob(String id) => repl('quote job $id');

  /// Persist an operator-edited quote draft via the brain's canonical quote
  /// resource seam. Today that seam is exposed through REPL as
  /// `add quote job:<id> min:<cents> max:<cents>`; the editor still keeps the
  /// richer local line-item draft for preview and future cell-backed storage.
  Future<String> saveQuoteDraft(QuoteDocument document) {
    final wire = document.toQuoteRequestJson();
    final jobId = wire['jobId'] as String;
    final costMin = (wire['costMin'] as num).toInt();
    final costMax = (wire['costMax'] as num).toInt();
    return repl('add quote job:$jobId min:$costMin max:$costMax');
  }

  Map<String, dynamic> _quoteExtractPayload({
    required QuoteDocument current,
    required List<QuoteSourcePatch> sourcePatches,
    required List<QuoteCatalogItem> catalogItems,
  }) => {
    'jobId': current.jobId,
    'currentQuote': current.toJson(),
    'sourcePatches': [
      for (final patch in sourcePatches)
        {
          'ref': patch.ref,
          'title': patch.title,
          'subtitle': patch.subtitle,
          'body': patch.body,
        },
    ],
    'catalogItems': [for (final item in catalogItems) item.toJson()],
    'extractor': 'scg.quote.import.v1',
  };

  QuoteDocument _quoteDocumentFromExtractBody(Map<String, dynamic> body) {
    final docJson = body['quoteDocument'] ?? body['quote'];
    if (docJson is! Map<String, dynamic>) {
      throw const BrainClientError(500, 'quote extract missing quoteDocument');
    }
    return QuoteDocument.fromJson(docJson);
  }

  /// Canonical SCG+LLM quote extraction seam via REPL.
  ///
  /// HTTP `/api/v1/quote-extract` is only a PWA convenience wrapper. The
  /// operator-debuggable command surface remains REPL-first: `extract quote`
  /// receives a JSON payload containing selected source patches, current quote,
  /// and operator catalog policy, and returns `{ quoteDocument: ... }`.
  Future<QuoteDocument> extractQuoteFromSourcesViaRepl({
    required QuoteDocument current,
    required List<QuoteSourcePatch> sourcePatches,
    required List<QuoteCatalogItem> catalogItems,
  }) async {
    final payload = _quoteExtractPayload(
      current: current,
      sourcePatches: sourcePatches,
      catalogItems: catalogItems,
    );
    final raw = await repl('extract quote ${jsonEncode(payload)}');
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _quoteDocumentFromExtractBody(decoded);
      }
    } catch (_) {
      // Fall through to a typed disabled/missing error so callers can decide
      // whether to try a wrapper route or deterministic local extraction.
    }
    throw const BrainClientError(501, 'extract quote REPL verb unavailable');
  }

  /// Convenience HTTP wrapper for the same SCG+LLM quote extraction seam.
  ///
  /// This must not become the canonical operator surface; it exists for PWA
  /// transport ergonomics and should delegate to the same implementation as the
  /// REPL verb when deployed.
  Future<QuoteDocument> extractQuoteFromSourcesViaHttp({
    required QuoteDocument current,
    required List<QuoteSourcePatch> sourcePatches,
    required List<QuoteCatalogItem> catalogItems,
  }) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/api/v1/quote-extract'),
      headers: _headers,
      body: jsonEncode(
        _quoteExtractPayload(
          current: current,
          sourcePatches: sourcePatches,
          catalogItems: catalogItems,
        ),
      ),
    );
    _checkStatus(resp);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return _quoteDocumentFromExtractBody(body);
  }

  /// Preferred edge quote extraction: REPL canonical first, HTTP wrapper second.
  Future<QuoteDocument> extractQuoteFromSources({
    required QuoteDocument current,
    required List<QuoteSourcePatch> sourcePatches,
    required List<QuoteCatalogItem> catalogItems,
  }) async {
    try {
      return await extractQuoteFromSourcesViaRepl(
        current: current,
        sourcePatches: sourcePatches,
        catalogItems: catalogItems,
      );
    } on BrainClientError catch (e) {
      if (e.statusCode != 404 && e.statusCode != 501) rethrow;
      return extractQuoteFromSourcesViaHttp(
        current: current,
        sourcePatches: sourcePatches,
        catalogItems: catalogItems,
      );
    }
  }

  // ── Conversation turns ──────────────────────────────────────────────────

  Future<List<ConversationTurn>> fetchTurns({
    required String entityRef,
    int limit = 100,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/conversation/turns'
      '?entityRef=${Uri.encodeComponent(entityRef)}&limit=$limit',
    );
    final resp = await _http.get(uri, headers: _headers);
    _checkStatus(resp);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = body['turns'] as List<dynamic>? ?? const [];
    return list
        .map((e) => ConversationTurn.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Add an operator-authored note to a job conversation.
  ///
  /// The brain's historical endpoint is named `voice-note`, but it is
  /// intentionally transcript-first: archived OddJobz used the same path
  /// for typed operator notes by sending the text as `transcript`.
  ///
  /// Returns the canonical turn id created by the brain.
  Future<String> submitJobNote({
    required String jobCellId,
    required String text,
    DateTime? capturedAt,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const BrainClientError(400, 'note text is empty');
    }

    final resp = await _http.post(
      Uri.parse('$baseUrl/api/v1/voice-note'),
      headers: _headers,
      body: jsonEncode({
        'transcript': trimmed,
        'entity_id': jobCellId,
        'entity_kind': 'job',
        'captured_at': (capturedAt ?? DateTime.now().toUtc()).toIso8601String(),
      }),
    );
    _checkStatus(resp);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return body['turn_id'] as String? ?? '';
  }

  /// Upload a recorded operator voice note for a job conversation.
  ///
  /// The brain transcribes the audio server-side and stores the resulting
  /// transcript as an operator ConversationTurn anchored to [jobCellId].
  Future<String> submitJobVoiceNote({
    required String jobCellId,
    required Uint8List audioBytes,
    String filename = 'voice-note.webm',
    String? transcriptHint,
    DateTime? capturedAt,
  }) async {
    if (audioBytes.isEmpty) {
      throw const BrainClientError(400, 'voice note audio is empty');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/voice-note'),
    );
    request.headers['Authorization'] = 'Bearer $bearer';
    request.fields.addAll({
      'entity_id': jobCellId,
      'entity_kind': 'job',
      'captured_at': (capturedAt ?? DateTime.now().toUtc()).toIso8601String(),
      if (transcriptHint != null && transcriptHint.trim().isNotEmpty)
        'transcript': transcriptHint.trim(),
    });
    request.files.add(
      http.MultipartFile.fromBytes('audio', audioBytes, filename: filename),
    );

    final streamed = await _http.send(request);
    final resp = await http.Response.fromStream(streamed);
    _checkStatus(resp);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return body['turn_id'] as String? ?? '';
  }

  /// Upload a pre-signed attachment blob for a job.
  ///
  /// [metadataJson] is the signed metadata envelope expected by the brain's
  /// `/api/v1/attachments/upload` route. The cartridge package deliberately
  /// does not know how to sign cells; the shell/host capture layer supplies the
  /// signed metadata and bytes.
  Future<AttachmentUploadResult> uploadJobAttachment({
    required String metadataJson,
    required Uint8List blobBytes,
    String filename = 'attachment.bin',
  }) async {
    if (metadataJson.trim().isEmpty) {
      throw const BrainClientError(400, 'attachment metadata is empty');
    }
    if (blobBytes.isEmpty) {
      throw const BrainClientError(400, 'attachment blob is empty');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/attachments/upload'),
    );
    request.headers['Authorization'] = 'Bearer $bearer';
    request.fields['metadata'] = metadataJson;
    request.files.add(
      http.MultipartFile.fromBytes('blob', blobBytes, filename: filename),
    );

    final streamed = await _http.send(request);
    final resp = await http.Response.fromStream(streamed);
    _checkStatus(resp);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return AttachmentUploadResult(
      id: body['id'] as String? ?? '',
      status: body['status'] as String? ?? '',
    );
  }

  // ── Approve turn ────────────────────────────────────────────────────────

  Future<void> approveTurn(String turnId) async {
    final resp = await _http.post(
      Uri.parse(
        '$baseUrl/api/v1/conversation/turn/${Uri.encodeComponent(turnId)}/approve',
      ),
      headers: _headers,
      body: jsonEncode({'approved': true}),
    );
    _checkStatus(resp);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  void _checkStatus(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    throw BrainClientError(resp.statusCode, resp.body);
  }

  void dispose() => _http.close();
}

```
