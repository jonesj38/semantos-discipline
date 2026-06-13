---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/quote_seed_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.456532+00:00
---

# cartridges/oddjobz/experience/test/quote_seed_test.dart

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oddjobz_experience/src/operator/conversation_turn.dart';
import 'package:oddjobz_experience/src/operator/quote_catalog.dart';
import 'package:oddjobz_experience/src/operator/quote_document.dart';
import 'package:oddjobz_experience/src/operator/quote_seed.dart';

void main() {
  test('seeds editable quote line items from inbound money mentions only', () {
    final draft = quoteDraftSeededFromConversation(
      jobId: 'job-1',
      now: DateTime.utc(2026, 6, 12),
      turns: const [
        ConversationTurn(
          turnId: 'in-1',
          conversationId: 'c',
          participantRole: 'external',
          direction: 'inbound',
          surface: 'email',
          bodyText: 'Can you do the repair for \$125.50 this week?',
          timestamp: 1,
        ),
        ConversationTurn(
          turnId: 'out-1',
          conversationId: 'c',
          participantRole: 'operator',
          direction: 'outbound',
          surface: 'widget',
          bodyText: 'Internal note: \$999 should not seed.',
          timestamp: 2,
        ),
        ConversationTurn(
          turnId: 'in-2',
          conversationId: 'c',
          participantRole: 'external',
          direction: 'inbound',
          surface: 'sms',
          bodyText: 'No price in this one.',
          timestamp: 3,
        ),
      ],
    );

    expect(draft.jobId, 'job-1');
    expect(draft.lineItems, hasLength(1));
    expect(draft.lineItems.single.unitCents, 12550);
    expect(draft.lineItems.single.category, 'conversation');
    expect(draft.lineItems.single.sourceCatalogItemId, 'conversation:in-1');
    expect(draft.lineItems.single.provenanceRefs, ['turn:in-1']);
    expect(draft.lineItems.single.toJson()['provenanceRefs'], ['turn:in-1']);
    expect(draft.notes, contains('Conversation seed (email, turn:in-1)'));
    expect(draft.markdown, contains('source: turn:in-1'));
    expect(draft.customerSummary, contains('1 conversation money mention'));
  });

  test('infers relevant operator catalog prices from conversation text', () {
    final draft = quoteDraftSeededFromConversation(
      jobId: 'job-roof',
      now: DateTime.utc(2026, 6, 12),
      catalogItems: const [
        QuoteCatalogItem(
          id: 'roof_inspection',
          description: 'Roof inspection',
          defaultQty: 1,
          unitCents: 16500,
          unit: 'ea',
          category: 'roofing',
        ),
        QuoteCatalogItem(
          id: 'gutter_clean',
          description: 'Clean gutters',
          defaultQty: 1,
          unitCents: 18000,
          unit: 'job',
          category: 'roofing',
        ),
      ],
      turns: const [
        ConversationTurn(
          turnId: 'in-roof',
          conversationId: 'c',
          participantRole: 'external',
          direction: 'inbound',
          surface: 'sms',
          bodyText: 'Need someone to inspect the roof after the storm.',
          timestamp: 1,
        ),
      ],
    );

    expect(draft.lineItems, hasLength(1));
    expect(draft.lineItems.single.sourceCatalogItemId, 'roof_inspection');
    expect(draft.lineItems.single.unitCents, 16500);
    expect(draft.lineItems.single.provenanceRefs, [
      'catalog:roof_inspection',
      'turn:in-roof',
    ]);
    expect(draft.notes, contains('Catalog match: Roof inspection'));
    expect(draft.notes, contains('catalog:roof_inspection'));
    expect(draft.notes, contains('turn:in-roof'));
    expect(draft.markdown, contains('# Quote for job-roof'));
    expect(draft.markdown, contains('Roof inspection'));
    expect(draft.markdown, contains(r'$165.00'));
    expect(
      draft.markdown,
      contains('source: catalog:roof_inspection, turn:in-roof'),
    );
  });

  test('quote line item provenance survives json round trip', () {
    const item = QuoteLineItem(
      description: 'Roof inspection',
      quantity: 1,
      unitCents: 16500,
      provenanceRefs: ['catalog:roof_inspection', 'turn:in-roof'],
    );

    final decoded = QuoteLineItem.fromJson(item.toJson());

    expect(decoded.provenanceRefs, ['catalog:roof_inspection', 'turn:in-roof']);
  });
}

```
