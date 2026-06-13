---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/brain_client_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.457641+00:00
---

# cartridges/oddjobz/experience/test/brain_client_test.dart

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oddjobz_experience/src/operator/brain_client.dart';
import 'package:oddjobz_experience/src/operator/quote_document.dart';
import 'package:oddjobz_experience/src/operator/quote_editor_screen.dart';

void main() {
  group('Oddjobz BrainClient', () {
    test(
      'findJobs parses the REPL JSON result used by the operator list',
      () async {
        final client = BrainClient(
          baseUrl: 'https://brain.example',
          bearer: 'token-123',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/repl');
            expect(
              request.headers['authorization'] ??
                  request.headers['Authorization'],
              'Bearer token-123',
            );
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['cmd'], 'find jobs');
            return http.Response(
              jsonEncode({
                'result': jsonEncode([
                  {
                    'id': 'job-1',
                    'customer_name': 'Hendry Street roof',
                    'state': 'qualified',
                    'cellId': 'a' * 64,
                    'propertyAddress': '42 Hendry Street',
                    'services': 'roof repair',
                  },
                ]),
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);

        final jobs = await client.findJobs();
        expect(jobs, hasLength(1));
        expect(jobs.single.id, 'job-1');
        expect(jobs.single.customerName, 'Hendry Street roof');
        expect(jobs.single.stateLabel, 'qualified');
        expect(jobs.single.cellId, 'a' * 64);
      },
    );

    test(
      'fetchTurns parses canonical oddjobz.conversation.turn payloads',
      () async {
        final client = BrainClient(
          baseUrl: 'https://brain.example',
          bearer: 'token-123',
          httpClient: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/api/v1/conversation/turns');
            expect(request.url.queryParameters['entityRef'], 'cell-abc');
            expect(request.url.queryParameters['limit'], '100');
            return http.Response(
              jsonEncode({
                'ok': true,
                'turns': [
                  {
                    'turnId': 'turn-1',
                    'conversationId': 'conv-1',
                    'participantRole': 'external',
                    'direction': 'inbound',
                    'surface': 'email',
                    'bodyText': 'Can you quote the roof repair?',
                    'timestamp': 1780911900000,
                    'entityRef': {'kind': 'job', 'cellHash': 'cell-abc'},
                    'identityHandle': {
                      'kind': 'email',
                      'value': 'pm@example.com',
                    },
                  },
                  {
                    'turnId': 'turn-2',
                    'conversationId': 'conv-1',
                    'participantRole': 'ai',
                    'direction': 'outbound',
                    'surface': 'email',
                    'bodyText': 'Draft reply',
                    'timestamp': 1780912000000,
                    'outboundState': 'proposed',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);

        final turns = await client.fetchTurns(entityRef: 'cell-abc');
        expect(turns, hasLength(2));
        expect(turns.first.isInbound, isTrue);
        expect(turns.first.identityValue, 'pm@example.com');
        expect(turns.first.entityCellHash, 'cell-abc');
        expect(turns.last.isProposed, isTrue);
      },
    );

    test(
      'submitJobNote posts typed notes to the voice-note endpoint',
      () async {
        final capturedAt = DateTime.utc(2026, 6, 12, 1, 2, 3);
        final client = BrainClient(
          baseUrl: 'https://brain.example',
          bearer: 'token-123',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/voice-note');
            expect(
              request.headers['authorization'] ??
                  request.headers['Authorization'],
              'Bearer token-123',
            );
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['transcript'], 'Customer confirmed roof access.');
            expect(body['entity_id'], 'cell-abc');
            expect(body['entity_kind'], 'job');
            expect(body['captured_at'], capturedAt.toIso8601String());
            return http.Response(
              jsonEncode({'turn_id': 'turn-note-1'}),
              201,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);

        final turnId = await client.submitJobNote(
          jobCellId: 'cell-abc',
          text: '  Customer confirmed roof access.  ',
          capturedAt: capturedAt,
        );

        expect(turnId, 'turn-note-1');
      },
    );

    test(
      'submitJobVoiceNote uploads audio multipart to the voice-note endpoint',
      () async {
        final capturedAt = DateTime.utc(2026, 6, 12, 4, 5, 6);
        final client = BrainClient(
          baseUrl: 'https://brain.example',
          bearer: 'token-123',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/voice-note');
            expect(
              request.headers['authorization'] ??
                  request.headers['Authorization'],
              'Bearer token-123',
            );
            expect(
              request.headers['content-type'],
              contains('multipart/form-data'),
            );
            expect(request, isA<http.Request>());
            final bodyText = latin1.decode((request as http.Request).bodyBytes);
            expect(bodyText, contains('name="entity_id"'));
            expect(bodyText, contains('cell-abc'));
            expect(bodyText, contains('name="entity_kind"'));
            expect(bodyText, contains('job'));
            expect(bodyText, contains('name="captured_at"'));
            expect(bodyText, contains(capturedAt.toIso8601String()));
            expect(bodyText, contains('name="transcript"'));
            expect(bodyText, contains('roof access memo'));
            expect(bodyText, contains('name="audio"'));
            expect(bodyText, contains('filename="note.webm"'));
            return http.Response(
              jsonEncode({'turn_id': 'voice-turn-1'}),
              201,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);

        final turnId = await client.submitJobVoiceNote(
          jobCellId: 'cell-abc',
          audioBytes: Uint8List.fromList([1, 2, 3, 4]),
          filename: 'note.webm',
          transcriptHint: ' roof access memo ',
          capturedAt: capturedAt,
        );

        expect(turnId, 'voice-turn-1');
      },
    );

    test(
      'uploadJobAttachment posts signed metadata and blob multipart',
      () async {
        final client = BrainClient(
          baseUrl: 'https://brain.example',
          bearer: 'token-123',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/attachments/upload');
            expect(
              request.headers['authorization'] ??
                  request.headers['Authorization'],
              'Bearer token-123',
            );
            expect(
              request.headers['content-type'],
              contains('multipart/form-data'),
            );
            final bodyText = latin1.decode((request as http.Request).bodyBytes);
            expect(bodyText, contains('name="metadata"'));
            expect(bodyText, contains('{"cell_payload"'));
            expect(bodyText, contains('name="blob"'));
            expect(bodyText, contains('filename="photo.jpg"'));
            return http.Response(
              jsonEncode({'id': 'att-1', 'status': 'created'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);

        final result = await client.uploadJobAttachment(
          metadataJson: '{"cell_payload":{"entity":"cell-abc"}}',
          blobBytes: Uint8List.fromList([1, 2, 3]),
          filename: 'photo.jpg',
        );

        expect(result.id, 'att-1');
        expect(result.status, 'created');
      },
    );

    test(
      'saveQuoteDraft folds editor document into canonical quote REPL command',
      () async {
        final now = DateTime.utc(2026, 6, 12);
        final client = BrainClient(
          baseUrl: 'https://brain.example',
          bearer: 'token-123',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/repl');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['cmd'], 'add quote job:job-1 min:34500 max:34500');
            return http.Response(
              jsonEncode({'result': 'quote q-1 created'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);

        final result = await client.saveQuoteDraft(
          QuoteDocument(
            id: 'draft-1',
            jobId: 'job-1',
            status: 'draft',
            lineItems: const [
              QuoteLineItem(
                description: 'Labour',
                quantity: 2,
                unitCents: 12500,
              ),
              QuoteLineItem(description: 'Parts', quantity: 1, unitCents: 9500),
            ],
            paymentTerms: 'Due on completion.',
            notes: 'Includes access constraints.',
            customerSummary: 'Repair quote.',
            createdAt: now,
            updatedAt: now,
          ),
        );

        expect(result, 'quote q-1 created');
      },
    );

    test(
      'extractQuoteFromSources uses canonical REPL extract quote first',
      () async {
        late Map<String, dynamic> replBody;
        final now = DateTime.utc(2026, 6, 13, 0, 0, 0);
        final client = BrainClient(
          baseUrl: 'https://brain.test',
          bearer: 'token',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/repl');
            replBody = jsonDecode(request.body) as Map<String, dynamic>;
            final cmd = replBody['cmd'] as String;
            expect(cmd, startsWith('extract quote '));
            final payload =
                jsonDecode(cmd.substring('extract quote '.length))
                    as Map<String, dynamic>;
            expect(payload['extractor'], 'scg.quote.import.v1');
            expect((payload['sourcePatches'] as List).single['ref'], 'turn:t1');
            return http.Response(
              jsonEncode({
                'result': jsonEncode({
                  'quoteDocument': {
                    'id': 'draft-repl',
                    'jobId': 'job-1',
                    'status': 'draft',
                    'lineItems': [
                      {
                        'description': 'REPL extracted access fee',
                        'quantity': 1,
                        'unitCents': 8000,
                        'provenanceRefs': ['turn:t1'],
                      },
                    ],
                    'paymentTerms': 'Due on completion.',
                    'notes': 'repl extracted',
                    'customerSummary': 'REPL quote',
                    'markdown': '- REPL extracted access fee',
                    'createdAt': now.toIso8601String(),
                    'updatedAt': now.toIso8601String(),
                  },
                }),
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final doc = await client.extractQuoteFromSources(
          current: QuoteDocument.newForJob('job-1', now: now),
          sourcePatches: const [
            QuoteSourcePatch(
              ref: 'turn:t1',
              title: 'sms · tenant',
              body: 'Please include the access fee.',
            ),
          ],
          catalogItems: const [],
        );

        expect(replBody['cmd'], isA<String>());
        expect(doc.lineItems.single.description, 'REPL extracted access fee');
        expect(doc.lineItems.single.provenanceRefs, ['turn:t1']);
      },
    );

    test(
      'extractQuoteFromSourcesViaHttp posts selected patches to quote-extract wrapper',
      () async {
        late Map<String, dynamic> posted;
        final now = DateTime.utc(2026, 6, 13, 0, 0, 0);
        final client = BrainClient(
          baseUrl: 'https://brain.test',
          bearer: 'token',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/quote-extract');
            expect(request.headers['authorization'], 'Bearer token');
            posted = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'quoteDocument': {
                  'id': 'draft-edge',
                  'jobId': 'job-1',
                  'status': 'draft',
                  'lineItems': [
                    {
                      'description': 'Edge extracted access fee',
                      'quantity': 1,
                      'unitCents': 8000,
                      'provenanceRefs': ['turn:t1'],
                    },
                  ],
                  'paymentTerms': 'Due on completion.',
                  'notes': 'edge extracted',
                  'customerSummary': 'Edge quote',
                  'markdown': '- Edge extracted access fee',
                  'createdAt': now.toIso8601String(),
                  'updatedAt': now.toIso8601String(),
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final doc = await client.extractQuoteFromSourcesViaHttp(
          current: QuoteDocument.newForJob('job-1', now: now),
          sourcePatches: const [
            QuoteSourcePatch(
              ref: 'turn:t1',
              title: 'sms · tenant',
              body: 'Please include the access fee.',
            ),
          ],
          catalogItems: const [],
        );

        expect(posted['extractor'], 'scg.quote.import.v1');
        expect(posted['sourcePatches'], isA<List<dynamic>>());
        expect((posted['sourcePatches'] as List).single['ref'], 'turn:t1');
        expect(doc.lineItems.single.description, 'Edge extracted access fee');
        expect(doc.lineItems.single.provenanceRefs, ['turn:t1']);
      },
    );

    test('approveTurn posts to the outbound approval endpoint', () async {
      final client = BrainClient(
        baseUrl: 'https://brain.example',
        bearer: 'token-123',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/conversation/turn/turn-2/approve');
          expect(jsonDecode(request.body), {'approved': true});
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.dispose);

      await client.approveTurn('turn-2');
    });
  });
}

```
