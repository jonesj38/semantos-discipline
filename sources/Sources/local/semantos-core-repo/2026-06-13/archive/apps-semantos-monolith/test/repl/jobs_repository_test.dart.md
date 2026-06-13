---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/jobs_repository_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.922363+00:00
---

# archive/apps-semantos-monolith/test/repl/jobs_repository_test.dart

```dart
// D-O5m — jobs_repository.dart parser test.
//
// Mirrors the test posture in `apps/loom-svelte` for the equivalent
// `parseJobs` function: assert each of the three best-effort parser
// branches (JSON, TSV, fallback-empty) produces the expected rows
// from a representative REPL response.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/repl/jobs_repository.dart';
import 'package:semantos/src/repl/repl_client.dart';

void main() {
  group('parseJobs', () {
    test('decodes a JSON-array response', () {
      final body = json.encode([
        {
          'id': 'job-001',
          'customer_name': 'Alice',
          'state': 'lead',
          'scheduled_at': '2026-05-03T09:00:00Z',
        },
        {
          'id': 'job-002',
          'customer': 'Bob',
          'state': 'scheduled',
          'scheduled_at': '2026-05-04T11:30:00Z',
        },
      ]);
      final rows = parseJobs(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('job-001'));
      expect(rows[0].customerName, equals('Alice'));
      expect(rows[0].state, equals('lead'));
      expect(rows[0].scheduledAt, equals('2026-05-03T09:00:00Z'));
      // Falls back to the `customer` key when `customer_name` is absent.
      expect(rows[1].customerName, equals('Bob'));
    });

    test('decodes a TSV response with header line', () {
      const body = '''
# id\tcustomer\tstate\tscheduled_at
job-001\tAlice\tlead\t2026-05-03
job-002\tBob\tscheduled\t2026-05-04
''';
      final rows = parseJobs(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('job-001'));
      expect(rows[0].customerName, equals('Alice'));
      expect(rows[1].state, equals('scheduled'));
    });

    test('returns empty list for an empty response', () {
      expect(parseJobs(''), isEmpty);
      expect(parseJobs('   \n   '), isEmpty);
    });

    test('skips malformed TSV lines', () {
      const body = '''
job-001\tAlice\tlead\t2026-05-03
malformed-line
job-002\tBob\tscheduled\t2026-05-04
''';
      final rows = parseJobs(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('job-001'));
      expect(rows[1].id, equals('job-002'));
    });

    // D-O5.followup-1 / D-O5m.followup-4 — integration with the typed
    // `find_jobs` dispatcher resource.  The brain-side resource handler
    // (runtime/semantos-brain/src/resources/jobs_handler.zig) emits a JSON array
    // where every row carries the canonical helm field set.  This test
    // asserts parseJobs consumes the exact bytes the dispatcher emits
    // — when a future churn drops a field on the Semantos Brain side, this test
    // breaks loud.
    test('decodes the D-O5.followup-1 dispatcher response shape', () {
      // Verbatim shape from `jobs_handler.zig::writeJobJson`.
      const body =
          '[{"id":"abc123","customer_name":"Acme Corp","state":"lead",'
          '"scheduled_at":"2026-05-15T09:00:00Z","created_at":"2026-05-02T10:00:00Z"},'
          '{"id":"def456","customer_name":"Globex","state":"scheduled",'
          '"scheduled_at":"","created_at":"2026-05-02T11:30:00Z"}]';
      final rows = parseJobs(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('abc123'));
      expect(rows[0].customerName, equals('Acme Corp'));
      expect(rows[0].state, equals('lead'));
      expect(rows[0].scheduledAt, equals('2026-05-15T09:00:00Z'));
      expect(rows[1].customerName, equals('Globex'));
      expect(rows[1].state, equals('scheduled'));
      expect(rows[1].scheduledAt, equals(''));
    });

    test('handles malformed JSON by falling through to TSV', () {
      // Starts with `[` so the JSON branch is attempted; on parse
      // failure the TSV branch should NOT pick it up (since the
      // first line starts with `[`). The desktop helm's parser has
      // the same shape: any unparseable input degrades to empty
      // gracefully rather than throwing.
      const body = '[not valid json';
      final rows = parseJobs(body);
      // The TSV fallback splits on tabs; this line has no tabs, so
      // it's filtered out as a malformed row.
      expect(rows, isEmpty);
    });
  });

  // D-O5.followup-3 (calendar + attention) — parser tests for the
  // two derived-query response shapes.  Mirrors the verbatim bytes
  // the Semantos Brain handler emits so a future churn that drops a field
  // breaks loud here.
  group('parseCalendar', () {
    test('decodes the dispatcher calendar shape', () {
      const body =
          '[{"date":"2026-05-04","jobs":[{"id":"job-001","customer_name":"Alice","state":"scheduled","scheduled_at":"2026-05-04T09:00:00Z"}]},'
          '{"date":"2026-05-05","jobs":[]},'
          '{"date":"2026-05-06","jobs":[{"id":"job-002","customer_name":"Bob","state":"in_progress","scheduled_at":"2026-05-06T10:00:00Z"}]}]';
      final days = parseCalendar(body);
      expect(days, hasLength(3));
      expect(days[0].date, equals('2026-05-04'));
      expect(days[0].jobs, hasLength(1));
      expect(days[0].jobs.first.customerName, equals('Alice'));
      // Empty-day buckets surface with `jobs: []` so the helm renders
      // the calendar grid without missing-key checks.
      expect(days[1].date, equals('2026-05-05'));
      expect(days[1].jobs, isEmpty);
      expect(days[2].jobs.first.scheduledAt, equals('2026-05-06T10:00:00Z'));
    });

    test('returns empty list on empty / non-JSON input', () {
      expect(parseCalendar(''), isEmpty);
      expect(parseCalendar('   '), isEmpty);
      expect(parseCalendar('not json'), isEmpty);
      // A malformed JSON envelope should also degrade to empty rather
      // than throw — same posture as parseJobs.
      expect(parseCalendar('[{"date":"2026-05-04",'), isEmpty);
    });
  });

  group('parseAttention', () {
    test('decodes the dispatcher attention shape', () {
      const body = '{"pending_quote":[{"id":"j-lead","customer_name":"Lead Co","state":"lead","scheduled_at":""}],'
          '"pending_schedule":[{"id":"j-quoted","customer_name":"Quoted Co","state":"quoted","scheduled_at":""}],'
          '"pending_invoice":[{"id":"j-completed","customer_name":"Done Co","state":"completed","scheduled_at":"2026-05-04T08:00:00Z"}],'
          '"total":3}';
      final feed = parseAttention(body);
      expect(feed.total, equals(3));
      expect(feed.isEmpty, isFalse);
      expect(feed.pendingQuote, hasLength(1));
      expect(feed.pendingQuote.first.customerName, equals('Lead Co'));
      expect(feed.pendingSchedule.first.state, equals('quoted'));
      expect(feed.pendingInvoice.first.scheduledAt,
          equals('2026-05-04T08:00:00Z'));
    });

    test('all-empty feed surfaces total=0 and isEmpty=true', () {
      const body =
          '{"pending_quote":[],"pending_schedule":[],"pending_invoice":[],"total":0}';
      final feed = parseAttention(body);
      expect(feed.total, equals(0));
      expect(feed.isEmpty, isTrue);
      expect(feed.pendingQuote, isEmpty);
    });

    test('returns empty feed on malformed input', () {
      expect(parseAttention('').isEmpty, isTrue);
      expect(parseAttention('not json').isEmpty, isTrue);
      expect(parseAttention('[]').isEmpty, isTrue);
    });
  });

  // D-O5.followup-3 polish — `parseJobOne` reads single-job
  // responses from the typed `jobs.find_by_id` dispatcher resource.
  // Pre-followup-3 the helm filtered findJobs() output by id; now
  // findJob() routes through `find job <id>` directly and parseJobOne
  // consumes the dispatcher's single-object shape.
  group('parseJobOne', () {
    test('decodes the dispatcher single-job response shape', () {
      const body =
          '{"id":"abc123","customer_name":"Acme Corp","state":"lead",'
          '"scheduled_at":"2026-05-15T09:00:00Z","created_at":"2026-05-02T10:00:00Z"}';
      final j = parseJobOne(body);
      expect(j, isNotNull);
      expect(j!.id, equals('abc123'));
      expect(j.customerName, equals('Acme Corp'));
      expect(j.state, equals('lead'));
      expect(j.scheduledAt, equals('2026-05-15T09:00:00Z'));
    });

    test('returns null for the typed not_found envelope', () {
      const body = '{"error":"not_found","id":"missing-id"}';
      expect(parseJobOne(body), isNull);
    });

    test('returns null for empty / malformed responses', () {
      expect(parseJobOne(''), isNull);
      expect(parseJobOne('not a json envelope'), isNull);
      expect(parseJobOne('{not valid json'), isNull);
    });
  });

  // D-O5 followup-1 — `parseJobTransitionResult` + the seven typed
  // repository wrappers (quoteJob / scheduleJob / startJob /
  // completeJob / invoiceJob / markJobPaid / closeJob).  Each test
  // pins the Semantos Brain REPL to a representative response shape via a stub
  // dio adapter and asserts the typed result the helm screen
  // consumes.
  group('parseJobTransitionResult', () {
    test('decodes a success body (bare Job shape)', () {
      const body =
          '{"id":"abc123","customer_name":"Acme","state":"quoted",'
          '"scheduled_at":"","created_at":"2026-05-02T10:00:00Z"}';
      final r = parseJobTransitionResult(body);
      expect(r, isA<JobTransitionSuccess>());
      final s = r as JobTransitionSuccess;
      expect(s.job.id, equals('abc123'));
      expect(s.job.state, equals('quoted'));
    });

    test('decodes already_in_state body', () {
      const body =
          '{"status":"already_in_state","job":{"id":"abc","customer_name":"X","state":"scheduled","scheduled_at":"","created_at":"2026-05-01T00:00:00Z"}}';
      final r = parseJobTransitionResult(body);
      expect(r, isA<JobTransitionAlreadyInState>());
      final a = r as JobTransitionAlreadyInState;
      expect(a.job.state, equals('scheduled'));
    });

    test('decodes typed error body (wrong_cap)', () {
      const body =
          '{"error":"wrong_cap","from":"lead","to":"quoted","cap_required":"cap.oddjobz.quote"}';
      final r = parseJobTransitionResult(body);
      expect(r, isA<JobTransitionError>());
      final e = r as JobTransitionError;
      expect(e.kind, equals('wrong_cap'));
      expect(e.from, equals('lead'));
      expect(e.to, equals('quoted'));
      expect(e.capRequired, equals('cap.oddjobz.quote'));
      expect(e.message, contains('cap.oddjobz.quote'));
    });

    test('decodes typed error body with null cap_required', () {
      const body =
          '{"error":"not_reachable","from":"lead","to":"invoiced","cap_required":null}';
      final r = parseJobTransitionResult(body);
      expect(r, isA<JobTransitionError>());
      final e = r as JobTransitionError;
      expect(e.kind, equals('not_reachable'));
      expect(e.capRequired, isNull);
    });

    test('decodes typed not_found error', () {
      const body = '{"error":"not_found","from":"","to":"quoted","cap_required":null}';
      final r = parseJobTransitionResult(body);
      expect(r, isA<JobTransitionError>());
      final e = r as JobTransitionError;
      expect(e.kind, equals('not_found'));
      expect(e.message, contains('no longer exists'));
    });

    test('returns parse_error on malformed JSON', () {
      final r = parseJobTransitionResult('not json');
      expect(r, isA<JobTransitionError>());
      expect((r as JobTransitionError).kind, equals('parse_error'));
    });
  });

  group('JobsRepository transition methods', () {
    // The mock adapter records every dispatched REPL command so we
    // can assert that each typed wrapper sends the operator-readable
    // verb the Semantos Brain side expects (`quote job <id>`, `schedule job <id>`
    // [--at X], etc.) — the Semantos Brain-side REPL parser is the canon.
    JobsRepository newRepo(_RecordingAdapter adapter) {
      final dio = Dio()..httpClientAdapter = adapter;
      final client = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'a' * 64,
      );
      return JobsRepository(client);
    }

    String successBody(String state) => json.encode({
          'result': json.encode({
            'id': 'abc',
            'customer_name': 'Acme',
            'state': state,
            'scheduled_at': '',
            'created_at': '2026-05-02T10:00:00Z',
          }),
          'exit': 'continue',
        });

    test('quoteJob sends `quote job <id>` and decodes success', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(successBody('quoted')),
      );
      final repo = newRepo(adapter);
      final r = await repo.quoteJob('abc');
      expect(r, isA<JobTransitionSuccess>());
      expect((r as JobTransitionSuccess).job.state, equals('quoted'));
      expect(adapter.lastBody!['cmd'], equals('quote job abc'));
    });

    test('scheduleJob sends `schedule job <id>` (no --at) and decodes', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(successBody('scheduled')),
      );
      final repo = newRepo(adapter);
      final r = await repo.scheduleJob('abc');
      expect(r, isA<JobTransitionSuccess>());
      expect(adapter.lastBody!['cmd'], equals('schedule job abc'));
    });

    test('scheduleJob with `at` includes --at <ISO timestamp>', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(successBody('scheduled')),
      );
      final repo = newRepo(adapter);
      final at = DateTime.utc(2026, 5, 15, 9, 0, 0);
      final r = await repo.scheduleJob('abc', at: at);
      expect(r, isA<JobTransitionSuccess>());
      expect(adapter.lastBody!['cmd'],
          equals('schedule job abc --at 2026-05-15T09:00:00Z'));
    });

    test('startJob sends `start job <id>`', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(successBody('in_progress')),
      );
      final repo = newRepo(adapter);
      final r = await repo.startJob('abc');
      expect((r as JobTransitionSuccess).job.state, equals('in_progress'));
      expect(adapter.lastBody!['cmd'], equals('start job abc'));
    });

    test('completeJob sends `complete job <id>`', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(successBody('completed')),
      );
      final repo = newRepo(adapter);
      final r = await repo.completeJob('abc');
      expect((r as JobTransitionSuccess).job.state, equals('completed'));
      expect(adapter.lastBody!['cmd'], equals('complete job abc'));
    });

    test('invoiceJob sends `invoice job <id>`', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(successBody('invoiced')),
      );
      final repo = newRepo(adapter);
      final r = await repo.invoiceJob('abc');
      expect((r as JobTransitionSuccess).job.state, equals('invoiced'));
      expect(adapter.lastBody!['cmd'], equals('invoice job abc'));
    });

    test('markJobPaid sends `mark job paid <id>`', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(successBody('paid')),
      );
      final repo = newRepo(adapter);
      final r = await repo.markJobPaid('abc');
      expect((r as JobTransitionSuccess).job.state, equals('paid'));
      expect(adapter.lastBody!['cmd'], equals('mark job paid abc'));
    });

    test('closeJob sends `close job <id>`', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(successBody('closed')),
      );
      final repo = newRepo(adapter);
      final r = await repo.closeJob('abc');
      expect((r as JobTransitionSuccess).job.state, equals('closed'));
      expect(adapter.lastBody!['cmd'], equals('close job abc'));
    });

    test('quoteJob surfaces typed wrong_cap error', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(json.encode({
          'result': json.encode({
            'error': 'wrong_cap',
            'from': 'lead',
            'to': 'quoted',
            'cap_required': 'cap.oddjobz.quote',
          }),
          'exit': 'continue',
        })),
      );
      final repo = newRepo(adapter);
      final r = await repo.quoteJob('abc');
      expect(r, isA<JobTransitionError>());
      expect((r as JobTransitionError).kind, equals('wrong_cap'));
      expect(r.capRequired, equals('cap.oddjobz.quote'));
    });

    test('quoteJob surfaces idempotent already_in_state', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(json.encode({
          'result': json.encode({
            'status': 'already_in_state',
            'job': {
              'id': 'abc',
              'customer_name': 'Acme',
              'state': 'quoted',
              'scheduled_at': '',
              'created_at': '2026-05-02T10:00:00Z',
            },
          }),
          'exit': 'continue',
        })),
      );
      final repo = newRepo(adapter);
      final r = await repo.quoteJob('abc');
      expect(r, isA<JobTransitionAlreadyInState>());
      expect((r as JobTransitionAlreadyInState).job.state, equals('quoted'));
    });

    test('transitionJob (generic) sends `transition job <id> <to> --principal X`',
        () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(successBody('quoted')),
      );
      final repo = newRepo(adapter);
      final r = await repo.transitionJob(
        id: 'abc',
        toState: 'quoted',
        principalKind: 'operator',
        presentedCap: 'cap.oddjobz.quote',
      );
      expect(r, isA<JobTransitionSuccess>());
      expect(
        adapter.lastBody!['cmd'],
        equals('transition job abc quoted --principal operator --cap cap.oddjobz.quote'),
      );
    });
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<int> body;
  Map<String, dynamic>? lastBody;
  _RecordingAdapter({required this.statusCode, required this.body});

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      final raw = await requestStream
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
      try {
        final decoded = json.decode(utf8.decode(raw));
        if (decoded is Map<String, dynamic>) lastBody = decoded;
      } catch (_) {
        // Ignore; non-JSON request body.
      }
    }
    return ResponseBody.fromBytes(body, statusCode, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

```
