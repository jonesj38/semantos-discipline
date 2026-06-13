---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/job_detail_screen_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.458370+00:00
---

# cartridges/oddjobz/experience/test/job_detail_screen_test.dart

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oddjobz_experience/src/operator/brain_client.dart';
import 'package:oddjobz_experience/src/operator/job.dart';
import 'package:oddjobz_experience/src/operator/job_detail_screen.dart';
import 'package:oddjobz_experience/src/operator/turn_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness({
    required Job job,
    required BrainClient client,
    JobVoiceNoteCaptureProvider? captureVoiceNote,
    JobAttachmentCaptureProvider? captureAttachment,
  }) {
    return MaterialApp(
      home: JobDetailScreen(
        job: job,
        client: client,
        captureVoiceNote: captureVoiceNote,
        captureAttachment: captureAttachment,
      ),
    );
  }

  BrainClient clientFor(MockClient mock) => BrainClient(
    baseUrl: 'https://brain.example',
    bearer: 'test-token',
    httpClient: mock,
  );

  testWidgets('blocks job-scoped note compose until a job has a cellId', (
    tester,
  ) async {
    final client = clientFor(
      MockClient((request) async {
        fail('no-cell jobs must not fetch turns or submit notes');
      }),
    );

    await tester.pumpWidget(
      harness(
        job: const Job(
          id: 'job-1',
          customerName: 'No Cell Customer',
          state: 'lead',
        ),
        client: client,
      ),
    );
    await tester.pump();

    expect(
      find.text('No cellId — job not yet entity-anchored.'),
      findsOneWidget,
    );
    expect(
      find.text('Add a cellId before writing job-scoped notes.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Send note'), findsNothing);
  });

  testWidgets(
    'submitting a job note posts to brain and refreshes the turn list',
    (tester) async {
      var fetchCount = 0;
      http.Request? submitted;
      final client = clientFor(
        MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/conversation/turns') {
            fetchCount += 1;
            final turns = fetchCount == 1
                ? const <Map<String, dynamic>>[]
                : <Map<String, dynamic>>[
                    {
                      'turnId': 'turn-1',
                      'conversationId': 'conv-1',
                      'participantRole': 'operator',
                      'direction': 'outbound',
                      'surface': 'widget',
                      'bodyText': 'Customer prefers Tuesday morning.',
                      'timestamp': 1718150400000,
                      'outboundState': 'sent',
                      'entityRef': {'cellHash': 'cell-abc'},
                    },
                  ];
            return http.Response(jsonEncode({'ok': true, 'turns': turns}), 200);
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/voice-note') {
            submitted = request;
            return http.Response(
              jsonEncode({'ok': true, 'turn_id': 'turn-1'}),
              200,
            );
          }
          return http.Response(
            'unexpected ${request.method} ${request.url}',
            500,
          );
        }),
      );

      await tester.pumpWidget(
        harness(
          job: const Job(
            id: 'job-1',
            customerName: 'Refresh Customer',
            state: 'lead',
            cellId: 'cell-abc',
          ),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No conversation turns yet.'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        '  Customer prefers Tuesday morning.  ',
      );
      await tester.tap(find.byTooltip('Send note'));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.headers['authorization'], 'Bearer test-token');
      final body = jsonDecode(submitted!.body) as Map<String, dynamic>;
      expect(body['transcript'], 'Customer prefers Tuesday morning.');
      expect(body['entity_id'], 'cell-abc');
      expect(body['entity_kind'], 'job');
      expect(fetchCount, 2, reason: 'successful submit should refresh turns');
      expect(find.text('Customer prefers Tuesday morning.'), findsOneWidget);
      expect(find.text('SENT'), findsOneWidget);
    },
  );

  testWidgets(
    'quote editor saves canonical quote draft through brain and refreshes turns',
    (tester) async {
      final commands = <String>[];
      var turnFetches = 0;
      final client = clientFor(
        MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/conversation/turns') {
            turnFetches += 1;
            return http.Response(
              jsonEncode({
                'ok': true,
                'turns': [
                  {
                    'turnId': 'turn-price',
                    'conversationId': 'conv-1',
                    'participantRole': 'external',
                    'direction': 'inbound',
                    'surface': 'email',
                    'bodyText': 'Could you include the \$80 access fee?',
                    'timestamp': 1718150400000,
                  },
                ],
              }),
              200,
            );
          }
          if (request.method == 'POST' && request.url.path == '/api/v1/repl') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            commands.add(body['cmd'] as String);
            return http.Response(
              jsonEncode({'result': 'quote q-1 created'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            'unexpected ${request.method} ${request.url}',
            500,
          );
        }),
      );

      SharedPreferences.setMockInitialValues({
        'oddjobz.quote_catalog.v1': jsonEncode([
          {
            'id': 'repair_labour',
            'description': 'Repair labour',
            'defaultQty': 1,
            'unitCents': 12500,
            'unit': 'ea',
            'category': 'labour',
          },
        ]),
      });

      await tester.pumpWidget(
        harness(
          job: const Job(
            id: 'job-1',
            customerName: 'Quote Customer',
            state: 'lead',
            cellId: 'cell-abc',
          ),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Autogenerate quote'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Repair labour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use draft'));
      await tester.pumpAndSettle();

      expect(commands, ['add quote job:job-1 min:20500 max:20500']);
      expect(turnFetches, 2, reason: 'save should refresh conversation turns');
      expect(find.text('quote q-1 created'), findsOneWidget);
      expect(find.text('Quote sources'), findsOneWidget);
      expect(find.text('turn:turn-price'), findsOneWidget);

      await tester.tap(find.text('turn:turn-price'));
      await tester.pump();
      final highlightedTurn = tester.widget<TurnBubble>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TurnBubble &&
              widget.turn.turnId == 'turn-price' &&
              widget.highlighted,
        ),
      );
      expect(highlightedTurn.turn.turnId, 'turn-price');
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets('quote editor can exclude conversation context before seeding', (
    tester,
  ) async {
    final commands = <String>[];
    final client = clientFor(
      MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/v1/conversation/turns') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'turns': [
                {
                  'turnId': 'turn-price',
                  'conversationId': 'conv-1',
                  'participantRole': 'external',
                  'direction': 'inbound',
                  'surface': 'sms',
                  'bodyText': 'Please include \$80 access fee.',
                  'timestamp': 1718150400000,
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST' && request.url.path == '/api/v1/repl') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          commands.add(body['cmd'] as String);
          return http.Response(
            jsonEncode({'result': 'quote q-2 created'}),
            200,
          );
        }
        return http.Response(
          'unexpected ${request.method} ${request.url}',
          500,
        );
      }),
    );

    SharedPreferences.setMockInitialValues({
      'oddjobz.quote_catalog.v1': jsonEncode([
        {
          'id': 'repair_labour',
          'description': 'Repair labour',
          'defaultQty': 1,
          'unitCents': 12500,
          'unit': 'ea',
          'category': 'labour',
        },
      ]),
    });

    await tester.pumpWidget(
      harness(
        job: const Job(
          id: 'job-1',
          customerName: 'Quote Customer',
          state: 'lead',
          cellId: 'cell-abc',
        ),
        client: client,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conversation patches feed quote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autogenerate quote'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Repair labour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use draft'));
    await tester.pumpAndSettle();

    expect(commands, ['add quote job:job-1 min:12500 max:12500']);
  });

  testWidgets('shows existing job attachment refs', (tester) async {
    final client = clientFor(
      MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/v1/conversation/turns') {
          return http.Response(
            jsonEncode({'ok': true, 'turns': const []}),
            200,
          );
        }
        return http.Response(
          'unexpected ${request.method} ${request.url}',
          500,
        );
      }),
    );

    await tester.pumpWidget(
      harness(
        job: const Job(
          id: 'job-1',
          customerName: 'Attached Customer',
          state: 'lead',
          cellId: 'cell-abc',
          attachmentRefs: ['attachment-photo-001'],
        ),
        client: client,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ATTACHMENTS'), findsOneWidget);
    expect(find.text('📎 attachment-p…'), findsOneWidget);
    expect(find.text('No attachments yet.'), findsNothing);
  });

  testWidgets(
    'attachment upload posts blob and refreshes job attachment list',
    (tester) async {
      var findJobCalls = 0;
      http.BaseRequest? submitted;
      final client = clientFor(
        MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/conversation/turns') {
            return http.Response(
              jsonEncode({'ok': true, 'turns': const []}),
              200,
            );
          }
          if (request.method == 'POST' && request.url.path == '/api/v1/repl') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body['cmd'] == 'find job job-1') {
              findJobCalls += 1;
              return http.Response(
                jsonEncode({
                  'result': jsonEncode({
                    'id': 'job-1',
                    'customer_name': 'Attachment Customer',
                    'state': 'lead',
                    'cellId': 'cell-abc',
                    'attachmentRefs': ['att-new'],
                  }),
                }),
                200,
              );
            }
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/attachments/upload') {
            submitted = request;
            return http.Response(
              jsonEncode({'id': 'att-new', 'status': 'created'}),
              200,
            );
          }
          return http.Response(
            'unexpected ${request.method} ${request.url}',
            500,
          );
        }),
      );

      await tester.pumpWidget(
        harness(
          job: const Job(
            id: 'job-1',
            customerName: 'Attachment Customer',
            state: 'lead',
            cellId: 'cell-abc',
          ),
          client: client,
          captureAttachment: (job) async {
            expect(job.cellId, 'cell-abc');
            return JobAttachmentCapture(
              blobBytes: Uint8List.fromList([4, 5, 6]),
              filename: 'site-photo.jpg',
              metadataJson: '{"cell_payload":{"entityRef":"cell-abc"}}',
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No attachments yet.'), findsOneWidget);
      await tester.tap(find.text('Add attachment'));
      await tester.pumpAndSettle();

      expect(submitted, isA<http.Request>());
      final bodyText = latin1.decode((submitted! as http.Request).bodyBytes);
      expect(bodyText, contains('name="metadata"'));
      expect(bodyText, contains('cell-abc'));
      expect(bodyText, contains('filename="site-photo.jpg"'));
      expect(
        findJobCalls,
        1,
        reason: 'upload success should refresh the job row',
      );
      expect(find.text('📎 att-new'), findsOneWidget);
    },
  );

  testWidgets(
    'attachment upload failure shows error and keeps actions usable',
    (tester) async {
      final client = clientFor(
        MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/conversation/turns') {
            return http.Response(
              jsonEncode({'ok': true, 'turns': const []}),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/attachments/upload') {
            return http.Response('hash_mismatch', 400);
          }
          return http.Response(
            'unexpected ${request.method} ${request.url}',
            500,
          );
        }),
      );

      await tester.pumpWidget(
        harness(
          job: const Job(
            id: 'job-1',
            customerName: 'Attachment Failure Customer',
            state: 'lead',
            cellId: 'cell-abc',
          ),
          client: client,
          captureAttachment: (_) async => JobAttachmentCapture(
            blobBytes: Uint8List.fromList([9]),
            filename: 'bad.jpg',
            metadataJson: '{"cell_payload":{}}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add attachment'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Attachment upload failed: hash_mismatch'),
        findsOneWidget,
      );
      expect(find.text('Add attachment'), findsOneWidget);
    },
  );

  testWidgets('voice note action uploads audio and refreshes the turn list', (
    tester,
  ) async {
    var fetchCount = 0;
    http.BaseRequest? submitted;
    final client = clientFor(
      MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/api/v1/conversation/turns') {
          fetchCount += 1;
          final turns = fetchCount == 1
              ? const <Map<String, dynamic>>[]
              : <Map<String, dynamic>>[
                  {
                    'turnId': 'voice-turn-1',
                    'conversationId': 'conv-1',
                    'participantRole': 'operator',
                    'direction': 'outbound',
                    'surface': 'voice',
                    'bodyText': 'Voice memo transcript',
                    'timestamp': 1718150400000,
                    'outboundState': 'sent',
                    'entityRef': {'cellHash': 'cell-abc'},
                  },
                ];
          return http.Response(jsonEncode({'ok': true, 'turns': turns}), 200);
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/voice-note') {
          submitted = request;
          return http.Response(
            jsonEncode({'ok': true, 'turn_id': 'voice-turn-1'}),
            200,
          );
        }
        return http.Response(
          'unexpected ${request.method} ${request.url}',
          500,
        );
      }),
    );

    await tester.pumpWidget(
      harness(
        job: const Job(
          id: 'job-1',
          customerName: 'Voice Customer',
          state: 'lead',
          cellId: 'cell-abc',
        ),
        client: client,
        captureVoiceNote: () async => JobVoiceNoteCapture(
          audioBytes: Uint8List.fromList([9, 8, 7]),
          filename: 'field-note.webm',
          transcriptHint: 'Voice memo transcript',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Voice note'));
    await tester.pumpAndSettle();

    expect(submitted, isA<http.Request>());
    final bodyText = latin1.decode((submitted! as http.Request).bodyBytes);
    expect(bodyText, contains('name="entity_id"'));
    expect(bodyText, contains('cell-abc'));
    expect(bodyText, contains('name="entity_kind"'));
    expect(bodyText, contains('job'));
    expect(bodyText, contains('name="transcript"'));
    expect(bodyText, contains('Voice memo transcript'));
    expect(bodyText, contains('filename="field-note.webm"'));
    expect(
      fetchCount,
      2,
      reason: 'successful voice upload should refresh turns',
    );
    expect(find.text('Voice memo transcript'), findsOneWidget);
    expect(find.text('SENT'), findsOneWidget);
  });

  testWidgets(
    'failed voice note upload shows error and keeps composer usable',
    (tester) async {
      final client = clientFor(
        MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/conversation/turns') {
            return http.Response(
              jsonEncode({'ok': true, 'turns': const []}),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/voice-note') {
            return http.Response('transcription failed', 502);
          }
          return http.Response(
            'unexpected ${request.method} ${request.url}',
            500,
          );
        }),
      );

      await tester.pumpWidget(
        harness(
          job: const Job(
            id: 'job-1',
            customerName: 'Voice Failure Customer',
            state: 'lead',
            cellId: 'cell-abc',
          ),
          client: client,
          captureVoiceNote: () async => JobVoiceNoteCapture(
            audioBytes: Uint8List.fromList([1]),
            filename: 'bad.webm',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Voice note'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Voice note failed: transcription failed'),
        findsOneWidget,
      );
      expect(find.byTooltip('Send note'), findsOneWidget);
    },
  );

  testWidgets(
    'failed note submit leaves a failed pending turn and shows error',
    (tester) async {
      final client = clientFor(
        MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/conversation/turns') {
            return http.Response(
              jsonEncode({'ok': true, 'turns': const []}),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/voice-note') {
            return http.Response('token rejected', 401);
          }
          return http.Response(
            'unexpected ${request.method} ${request.url}',
            500,
          );
        }),
      );

      await tester.pumpWidget(
        harness(
          job: const Job(
            id: 'job-1',
            customerName: 'Failure Customer',
            state: 'lead',
            cellId: 'cell-abc',
          ),
          client: client,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'This should fail');
      await tester.tap(find.byTooltip('Send note'));
      await tester.pumpAndSettle();

      expect(find.text('This should fail'), findsOneWidget);
      expect(find.text('FAILED'), findsOneWidget);
      expect(
        find.textContaining('Note failed: token rejected'),
        findsOneWidget,
      );
    },
  );
}

```
