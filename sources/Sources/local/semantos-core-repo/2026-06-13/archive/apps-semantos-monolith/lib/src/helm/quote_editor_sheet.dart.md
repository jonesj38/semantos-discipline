---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/quote_editor_sheet.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.894105+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/quote_editor_sheet.dart

```dart
// Quote editor sheet.
//
// Full-screen modal bottom sheet for building a QuoteDocument.
// Two tabs: Edit (line items, payment terms, notes) and Preview
// (styled card rendering the quote as the customer would see it).
//
// Usage:
//   final saved = await showQuoteEditor(context, initial: doc);
//   if (saved != null) { /* persist + pass cost_min/max to add quote */ }

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../repl/conversation_turns_repository.dart';
import '../repl/jobs_repository.dart';
import 'quote_document.dart';
import 'quote_extractor.dart';
import 'receipt_ocr_service.dart';

Future<QuoteDocument?> showQuoteEditor(
  BuildContext context, {
  required QuoteDocument initial,
  String jobTitle = '',
  // AI extraction wiring — all optional; features hidden when absent.
  QuoteExtractorService? extractor,
  Job? job,
  ConversationTurnsRepository? turnsRepository,
  // P2b: receipt OCR — optional; scan button hidden when absent.
  ReceiptOcrService? receiptOcr,
}) {
  return showModalBottomSheet<QuoteDocument>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _QuoteEditorSheet(
      initial: initial,
      jobTitle: jobTitle,
      extractor: extractor,
      job: job,
      turnsRepository: turnsRepository,
      receiptOcr: receiptOcr,
    ),
  );
}

class _QuoteEditorSheet extends StatefulWidget {
  final QuoteDocument initial;
  final String jobTitle;
  final QuoteExtractorService? extractor;
  final Job? job;
  final ConversationTurnsRepository? turnsRepository;
  final ReceiptOcrService? receiptOcr;

  const _QuoteEditorSheet({
    required this.initial,
    required this.jobTitle,
    this.extractor,
    this.job,
    this.turnsRepository,
    this.receiptOcr,
  });

  @override
  State<_QuoteEditorSheet> createState() => _QuoteEditorSheetState();
}

class _QuoteEditorSheetState extends State<_QuoteEditorSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<QuoteLineItem> _items;
  late TextEditingController _paymentTerms;
  late TextEditingController _notes;
  late TextEditingController _nlInput;

  bool _extracting = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _items = List.of(widget.initial.lineItems);
    _paymentTerms = TextEditingController(text: widget.initial.paymentTerms);
    _notes = TextEditingController(text: widget.initial.notes);
    _nlInput = TextEditingController();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _paymentTerms.dispose();
    _notes.dispose();
    _nlInput.dispose();
    super.dispose();
  }

  int get _totalCents => _items.fold(0, (s, i) => s + i.totalCents);

  QuoteDocument _build() => widget.initial.copyWith(
        lineItems: _items,
        paymentTerms: _paymentTerms.text.trim(),
        notes: _notes.text.trim(),
        updatedAt: DateTime.now(),
      );

  void _addItem() {
    setState(() => _items.add(
          const QuoteLineItem(description: '', quantity: 1.0, unitCents: 0),
        ));
    WidgetsBinding.instance.addPostFrameCallback((_) => _tabs.animateTo(0));
  }

  void _removeItem(int i) => setState(() => _items.removeAt(i));

  void _updateItem(int i, QuoteLineItem item) =>
      setState(() => _items[i] = item);

  void _save() => Navigator.of(context).pop(_build());

  /// Generate line items from the job's conversation thread.
  Future<void> _generateFromConversation() async {
    final ex = widget.extractor;
    final job = widget.job;
    final turns = widget.turnsRepository;
    if (ex == null || job == null || turns == null) return;

    setState(() => _extracting = true);
    try {
      final result =
          await ex.fromConversation(job: job, turnsRepo: turns);
      if (!mounted) return;
      setState(() {
        _items = result.items;
        if (result.notes.isNotEmpty && _notes.text.trim().isEmpty) {
          _notes.text = result.notes;
        }
      });
      if (_items.isEmpty) {
        _showSnack(
            'No items extracted — try describing the work in the text field below.');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Extraction failed: $e');
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  /// Parse the operator's freehand text into line items and append them.
  Future<void> _parseNlInput() async {
    final ex = widget.extractor;
    final text = _nlInput.text.trim();
    if (ex == null || text.isEmpty) return;

    setState(() => _extracting = true);
    try {
      final result = await ex.fromText(text);
      if (!mounted) return;
      setState(() {
        // Append parsed items to anything already in the list
        _items = [..._items, ...result.items];
        if (result.notes.isNotEmpty && _notes.text.trim().isEmpty) {
          _notes.text = result.notes;
        }
        _nlInput.clear();
      });
      if (result.items.isEmpty) {
        _showSnack('Nothing parseable — try being more specific.');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Parse failed: $e');
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  /// P2b — scan a receipt photo and append OCR'd line items.
  Future<void> _scanReceipt() async {
    final ocr = widget.receiptOcr;
    if (ocr == null) return;

    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (!mounted || photo == null) return;

    setState(() => _extracting = true);
    try {
      final newItems = await ocr.fromPhoto(photo);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...newItems];
      });
      if (newItems.isEmpty) {
        _showSnack('No items found on receipt — try a clearer photo.');
      } else {
        _showSnack('Added ${newItems.length} item${newItems.length == 1 ? '' : 's'} from receipt.');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Receipt scan failed: $e');
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.jobTitle.isEmpty ? 'Quote' : 'Quote · ${widget.jobTitle}',
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Edit'),
            Tab(text: 'Preview'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _EditTab(
            items: _items,
            paymentTerms: _paymentTerms,
            notes: _notes,
            nlInput: _nlInput,
            totalCents: _totalCents,
            onAdd: _addItem,
            onRemove: _removeItem,
            onUpdate: _updateItem,
            extracting: _extracting,
            canGenerateFromConversation: widget.extractor != null &&
                widget.job != null &&
                widget.turnsRepository != null,
            canParseText: widget.extractor != null,
            onGenerateFromConversation: _generateFromConversation,
            onParseNlInput: _parseNlInput,
            canScanReceipt: widget.receiptOcr != null,
            onScanReceipt: _scanReceipt,
          ),
          _PreviewTab(
            jobTitle: widget.jobTitle,
            items: _items,
            paymentTerms: _paymentTerms.text,
            notes: _notes.text,
            totalCents: _totalCents,
            primaryColor: cs.primary,
          ),
        ],
      ),
    );
  }
}

// ── Edit tab ──────────────────────────────────────────────────────────────

class _EditTab extends StatelessWidget {
  final List<QuoteLineItem> items;
  final TextEditingController paymentTerms;
  final TextEditingController notes;
  final TextEditingController nlInput;
  final int totalCents;
  final VoidCallback onAdd;
  final void Function(int) onRemove;
  final void Function(int, QuoteLineItem) onUpdate;
  final bool extracting;
  final bool canGenerateFromConversation;
  final bool canParseText;
  final VoidCallback onGenerateFromConversation;
  final VoidCallback onParseNlInput;
  // P2b: receipt OCR
  final bool canScanReceipt;
  final VoidCallback onScanReceipt;

  const _EditTab({
    required this.items,
    required this.paymentTerms,
    required this.notes,
    required this.nlInput,
    required this.totalCents,
    required this.onAdd,
    required this.onRemove,
    required this.onUpdate,
    required this.extracting,
    required this.canGenerateFromConversation,
    required this.canParseText,
    required this.onGenerateFromConversation,
    required this.onParseNlInput,
    required this.canScanReceipt,
    required this.onScanReceipt,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── AI: generate from conversation ──────────────────────────
        if (canGenerateFromConversation) ...[
          _AiGenerateCard(
            extracting: extracting,
            onGenerate: onGenerateFromConversation,
          ),
          const SizedBox(height: 12),
        ],

        // ── AI: parse freehand text ──────────────────────────────────
        if (canParseText) ...[
          _NlInputRow(
            controller: nlInput,
            extracting: extracting,
            onParse: onParseNlInput,
          ),
          const SizedBox(height: 12),
        ],

        // ── P2b: Receipt scan ─────────────────────────────────────────
        if (canScanReceipt) ...[
          _ReceiptScanCard(
            extracting: extracting,
            onScan: onScanReceipt,
          ),
          const SizedBox(height: 16),
        ],

        // ── Line items ───────────────────────────────────────────────
        Row(
          children: [
            Text('Line items',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              onPressed: extracting ? null : onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),

        if (extracting)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Building your quote…',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              canGenerateFromConversation
                  ? 'Tap "Generate from conversation" or describe the work above.'
                  : 'No items yet. Tap Add to start.',
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
            ),
          )
        else
          ...items.asMap().entries.map((e) => _LineItemRow(
                index: e.key,
                item: e.value,
                onRemove: () => onRemove(e.key),
                onChanged: (updated) => onUpdate(e.key, updated),
              )),

        const Divider(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Total  ${_formatCents(totalCents)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        const SizedBox(height: 20),

        // ── Payment terms ────────────────────────────────────────────
        Text('Payment terms',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: paymentTerms,
          maxLines: 2,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'e.g. Payment due within 14 days of invoice.',
          ),
        ),
        const SizedBox(height: 20),

        // ── Notes / scope ────────────────────────────────────────────
        Text('Notes',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: notes,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Scope of work, inclusions, exclusions…',
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── AI generate card ──────────────────────────────────────────────────────

class _AiGenerateCard extends StatelessWidget {
  final bool extracting;
  final VoidCallback onGenerate;
  const _AiGenerateCard({required this.extracting, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: cs.secondary.withValues(alpha: 0.3), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: cs.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Generate from conversation',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSecondaryContainer),
            ),
          ),
          FilledButton.tonal(
            onPressed: extracting ? null : onGenerate,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            ),
            child: extracting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Generate'),
          ),
        ],
      ),
    );
  }
}

// ── NL input row ──────────────────────────────────────────────────────────

class _NlInputRow extends StatelessWidget {
  final TextEditingController controller;
  final bool extracting;
  final VoidCallback onParse;
  const _NlInputRow(
      {required this.controller,
      required this.extracting,
      required this.onParse});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 3,
            enabled: !extracting,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onParse(),
            decoration: const InputDecoration(
              hintText: 'Describe the work… e.g. "2hrs labour, fix leaking tap, replace washers x3"',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: extracting ? null : onParse,
          icon: extracting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send),
          tooltip: 'Parse into line items',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

// ── P2b: Receipt scan card ────────────────────────────────────────────────
//
// Amber-accented card shown below the NL input when ReceiptOcrService is
// wired.  One-tap camera launch → OCR → items appended.

class _ReceiptScanCard extends StatelessWidget {
  final bool extracting;
  final VoidCallback onScan;
  const _ReceiptScanCard({required this.extracting, required this.onScan});

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFF59E0B);
    const amberBg = Color(0xFFFFF8E1);
    const amberBorder = Color(0xFFFFCC02);
    return Container(
      decoration: BoxDecoration(
        color: amberBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amberBorder, width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 18, color: amber),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Scan receipt',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF78350F)),
            ),
          ),
          FilledButton.tonal(
            onPressed: extracting ? null : onScan,
            style: FilledButton.styleFrom(
              backgroundColor: amber,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            ),
            child: extracting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Scan'),
          ),
        ],
      ),
    );
  }
}

class _LineItemRow extends StatefulWidget {
  final int index;
  final QuoteLineItem item;
  final VoidCallback onRemove;
  final void Function(QuoteLineItem) onChanged;

  const _LineItemRow({
    required this.index,
    required this.item,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_LineItemRow> createState() => _LineItemRowState();
}

class _LineItemRowState extends State<_LineItemRow> {
  late final TextEditingController _desc;
  late final TextEditingController _qty;
  late final TextEditingController _unit;

  @override
  void initState() {
    super.initState();
    _desc = TextEditingController(text: widget.item.description);
    _qty  = TextEditingController(
        text: widget.item.quantity == widget.item.quantity.roundToDouble()
            ? widget.item.quantity.toInt().toString()
            : widget.item.quantity.toString());
    _unit = TextEditingController(
        text: (widget.item.unitCents / 100).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _desc.dispose();
    _qty.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _emit() {
    final qty  = double.tryParse(_qty.text.trim()) ?? 1.0;
    final unit = ((double.tryParse(_unit.text.trim()) ?? 0.0) * 100).round();
    widget.onChanged(QuoteLineItem(
      description: _desc.text.trim(),
      quantity:    qty,
      unitCents:   unit,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: _desc,
              onChanged: (_) => _emit(),
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: TextField(
              controller: _qty,
              onChanged: (_) => _emit(),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Qty',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _unit,
              onChanged: (_) => _emit(),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Unit \$',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: widget.onRemove,
            color: Colors.red,
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

// ── Preview tab ───────────────────────────────────────────────────────────

class _PreviewTab extends StatelessWidget {
  final String jobTitle;
  final List<QuoteLineItem> items;
  final String paymentTerms;
  final String notes;
  final int totalCents;
  final Color primaryColor;

  const _PreviewTab({
    required this.jobTitle,
    required this.items,
    required this.paymentTerms,
    required this.notes,
    required this.totalCents,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 2,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 36,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('QUOTE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                            letterSpacing: 1.2,
                          )),
                      if (jobTitle.isNotEmpty)
                        Text(jobTitle,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 16),
                _previewTableHeader(),
                const Divider(height: 8),
                ...items.map(_previewLine),
                const Divider(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total  ${_formatCents(totalCents)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: primaryColor,
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                const Text('No line items.',
                    style: TextStyle(color: Colors.grey)),
              ],
              if (paymentTerms.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Payment terms',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 4),
                Text(paymentTerms,
                    style: const TextStyle(fontSize: 13)),
              ],
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Notes',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 4),
                Text(notes, style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewTableHeader() => const Row(
        children: [
          Expanded(
              flex: 5,
              child: Text('Description',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12))),
          SizedBox(
              width: 36,
              child: Text('Qty',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
          SizedBox(width: 8),
          SizedBox(
              width: 72,
              child: Text('Unit', textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
          SizedBox(width: 8),
          SizedBox(
              width: 72,
              child: Text('Total', textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
        ],
      );

  Widget _previewLine(QuoteLineItem item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(flex: 5, child: Text(item.description, style: const TextStyle(fontSize: 13))),
            SizedBox(
                width: 36,
                child: Text(
                    item.quantity == item.quantity.roundToDouble()
                        ? item.quantity.toInt().toString()
                        : item.quantity.toStringAsFixed(1),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 8),
            SizedBox(
                width: 72,
                child: Text(_formatCents(item.unitCents),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 8),
            SizedBox(
                width: 72,
                child: Text(_formatCents(item.totalCents),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500))),
          ],
        ),
      );
}

String _formatCents(int cents) =>
    '\$${(cents / 100).toStringAsFixed(2)}';

```
