---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/quote_editor_screen_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.458681+00:00
---

# cartridges/oddjobz/experience/test/quote_editor_screen_test.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oddjobz_experience/src/operator/quote_catalog.dart';
import 'package:oddjobz_experience/src/operator/quote_document.dart';
import 'package:oddjobz_experience/src/operator/quote_editor_screen.dart';

void main() {
  testWidgets('quote editor adds configured catalog item and previews total', (
    tester,
  ) async {
    QuoteEditorResult? result;
    final initial = QuoteDocument.newForJob(
      'job-1',
      now: DateTime.utc(2026, 6, 12),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showQuoteEditor(
                  context,
                  initial: initial,
                  catalogItems: const [
                    QuoteCatalogItem(
                      id: 'consulting_hour',
                      description: 'Consulting',
                      defaultQty: 2,
                      unitCents: 22000,
                      unit: 'hr',
                      category: 'professional-services',
                    ),
                  ],
                );
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Consulting'), findsOneWidget);

    await tester.tap(find.textContaining('Consulting'));
    await tester.pump();

    expect(find.text(r'Total $440.00'), findsOneWidget);

    await tester.tap(find.text('Preview'));
    await tester.pump();
    expect(find.text('Quote preview'), findsOneWidget);
    expect(find.text('Consulting'), findsWidgets);
    expect(find.textContaining(r'$440.00'), findsWidgets);

    await tester.tap(find.text('Use draft'));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.document.lineItems, hasLength(1));
    expect(result!.document.totalCents, 44000);
  });

  testWidgets('quote editor shows unconfigured catalog hint', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuoteEditorSheet(
            initial: QuoteDocument.newForJob('job-1'),
            catalogItems: const [],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('No operator catalog configured'),
      findsOneWidget,
    );
    expect(find.textContaining('Me → Brain management'), findsOneWidget);
  });

  testWidgets('quote editor exposes generated Markdown as editable text', (
    tester,
  ) async {
    final initial = QuoteDocument.newForJob(
      'job-md',
      now: DateTime.utc(2026, 6, 12),
    ).copyWith(markdown: '# Quote for job-md\n\n- Existing generated line');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuoteEditorSheet(initial: initial, catalogItems: const []),
        ),
      ),
    );

    expect(find.text('Editable Markdown quote'), findsOneWidget);
    expect(find.textContaining('Existing generated line'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Editable Markdown quote',
      ),
      '# Edited quote\n\nCustomer approved scope.',
    );
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Editable Markdown quote',
      ),
    );
    expect(field.controller?.text, contains('Customer approved scope.'));
  });

  testWidgets('quote editor source chip returns jump-to-source result', (
    tester,
  ) async {
    QuoteEditorResult? result;
    final initial =
        QuoteDocument.newForJob(
          'job-source',
          now: DateTime.utc(2026, 6, 12),
        ).copyWith(
          lineItems: const [
            QuoteLineItem(
              description: 'Access fee',
              quantity: 1,
              unitCents: 8000,
              provenanceRefs: ['turn:turn-price'],
            ),
          ],
          markdown: '- Access fee _(source: turn:turn-price)_',
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showQuoteEditor(
                  context,
                  initial: initial,
                  catalogItems: const [],
                );
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final chip = find.widgetWithText(ActionChip, 'turn:turn-price').first;
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.shouldJumpToSource, isTrue);
    expect(result!.jumpToSourceRef, 'turn:turn-price');
    expect(result!.document.lineItems.single.description, 'Access fee');
  });

  testWidgets('dog-ear source side selects patches and imports to quote', (
    tester,
  ) async {
    final initial = QuoteDocument.newForJob(
      'job-flip',
      now: DateTime.utc(2026, 6, 12),
    );
    var importedRefs = const <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuoteEditorSheet(
            initial: initial,
            catalogItems: const [],
            sourcePatches: const [
              QuoteSourcePatch(
                ref: 'turn:t1',
                title: 'sms · tenant',
                body: r'Please include the $80 access fee.',
              ),
            ],
            importFromSources: (current, selected) async {
              importedRefs = [for (final patch in selected) patch.ref];
              return current.copyWith(
                customerSummary: 'Imported from SCG source selection.',
                lineItems: const [
                  QuoteLineItem(
                    description: 'Access fee',
                    quantity: 1,
                    unitCents: 8000,
                    provenanceRefs: ['turn:t1'],
                  ),
                ],
                markdown:
                    r'- Access fee — 1 × $80.00 = $80.00 _(source: turn:t1)_',
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Flip to conversation sources'));
    await tester.pumpAndSettle();

    expect(find.text('Conversation sources'), findsOneWidget);
    expect(find.text('sms · tenant'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Import to quote'));
    await tester.pumpAndSettle();

    expect(importedRefs, ['turn:t1']);
    expect(find.text('Editable Markdown quote'), findsOneWidget);
    expect(find.textContaining('Access fee'), findsWidgets);
    expect(find.text('turn:t1'), findsWidgets);
  });
}

```
