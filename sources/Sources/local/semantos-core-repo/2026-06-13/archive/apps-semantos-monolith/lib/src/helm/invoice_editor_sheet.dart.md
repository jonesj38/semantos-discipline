---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/invoice_editor_sheet.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.896327+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/invoice_editor_sheet.dart

```dart
// Invoice editor sheet.
//
// Full-screen modal bottom sheet for building an InvoiceDocument.
// Near-clone of QuoteEditorSheet with invoice-specific differences:
//
//   • Pre-populated from the approved QuoteDocument baseline (items tagged
//     source='quote').
//   • Source chips on each line item row show provenance (quote / manual /
//     receipt).
//   • Receipt OCR scan button (amber) to add materials/parts items.
//   • No approval state machine — operator edits then taps "Save"; the
//     caller drives the brain FSM transition.
//
// Usage:
//   final saved = await showInvoiceEditor(context,
//     initial: invoice, jobTitle: job.customerName,
//     receiptOcr: receiptOcrSvc,
//     extractor: extractor, job: job, turnsRepository: turns);
//   if (saved != null) { /* persist + send totalCents to brain */ }
//
// P3b of OJT-UNIFIED-QUOTE-INVOICE-PLAN.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../repl/conversation_turns_repository.dart';
import '../repl/jobs_repository.dart';
import 'invoice_document.dart';
import 'quote_extractor.dart';
import 'receipt_ocr_service.dart';

Future<InvoiceDocument?> showInvoiceEditor(
  BuildContext context, {
  required InvoiceDocument initial,
  String jobTitle = '',
  ReceiptOcrService? receiptOcr,
  // P3b AI generation — optional; hidden when absent.
  QuoteExtractorService? extractor,
  Job? job,
  ConversationTurnsRepository? turnsRepository,
}) {
  return showModalBottomSheet<InvoiceDocument>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _InvoiceEditorSheet(
      initial: initial,
      jobTitle: jobTitle,
      receiptOcr: receiptOcr,
      extractor: extractor,
      job: job,
      turnsRepository: turnsRepository,
    ),
  );
}

class _InvoiceEditorSheet extends StatefulWidget {
  final InvoiceDocument initial;
  final String jobTitle;
  final ReceiptOcrService? receiptOcr;
  final QuoteExtractorService? extractor;
  final Job? job;
  final ConversationTurnsRepository? turnsRepository;

  const _InvoiceEditorSheet({
    required this.initial,
    required this.jobTitle,
    this.receiptOcr,
    this.extractor,
    this.job,
    this.turnsRepository,
  });

  @override
  State<_InvoiceEditorSheet> createState() => _InvoiceEditorSheetState();
}

class _InvoiceEditorSheetState extends State<_InvoiceEditorSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late List<InvoiceLineItem> _items;
  late TextEditingController _paymentTerms;
  late TextEditingController _notes;

  bool _scanning = false;
  bool _extracting = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _items = List.of(widget.initial.lineItems);
    _paymentTerms =
        TextEditingController(text: widget.initial.paymentTerms);
    _notes = TextEditingController(text: widget.initial.notes);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _paymentTerms.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _totalCents => _items.fold(0, (s, i) => s + i.totalCents);

  InvoiceDocument _build() => widget.initial.copyWith(
        lineItems: _items,
        paymentTerms: _paymentTerms.text.trim(),
        notes: _notes.text.trim(),
        updatedAt: DateTime.now(),
      );

  void _addItem() {
    setState(() => _items.add(
          const InvoiceLineItem(
              description: '', quantity: 1.0, unitCents: 0,
              source: InvoiceLineSource.manual),
        ));
    WidgetsBinding.instance.addPostFrameCallback((_) => _tabs.animateTo(0));
  }

  void _removeItem(int i) => setState(() => _items.removeAt(i));

  void _updateItem(int i, InvoiceLineItem item) =>
      setState(() => _items[i] = item);

  void _save() => Navigator.of(context).pop(_build());

  /// Scan a receipt photo and append OCR'd items tagged source='receipt'.
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

    setState(() => _scanning = true);
    try {
      final quoteItems = await ocr.fromPhoto(photo);
      if (!mounted) return;
      final invoiceItems = quoteItems
          .map((q) => InvoiceLineItem(
                description: q.description,
                quantity: q.quantity,
                unitCents: q.unitCents,
                source: InvoiceLineSource.receipt,
              ))
          .toList();
      setState(() {
        _items = [..._items, ...invoiceItems];
      });
      if (invoiceItems.isEmpty) {
        _showSnack('No items found on receipt — try a clearer photo.');
      } else {
        _showSnack(
            'Added ${invoiceItems.length} item${invoiceItems.length == 1 ? '' : 's'} from receipt.');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Receipt scan failed: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// P3b — generate invoice items from the job's post-quote conversation turns.
  /// Appends to existing items so quote-sourced baseline is preserved.
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
      final newItems = result.items
          .map((q) => InvoiceLineItem(
                description: q.description,
                quantity: q.quantity,
                unitCents: q.unitCents,
                source: InvoiceLineSource.manual,
              ))
          .toList();
      setState(() {
        _items = [..._items, ...newItems];
        if (result.notes.isNotEmpty && _notes.text.trim().isEmpty) {
          _notes.text = result.notes;
        }
      });
      if (newItems.isEmpty) {
        _showSnack(
            'No additional items found — try adding a voice note first.');
      } else {
        _showSnack(
            'Added ${newItems.length} item${newItems.length == 1 ? '' : 's'} from conversation.');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Generation failed: $e');
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.jobTitle.isEmpty
              ? 'Invoice'
              : 'Invoice · ${widget.jobTitle}',
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
            totalCents: _totalCents,
            onAdd: _addItem,
            onRemove: _removeItem,
            onUpdate: _updateItem,
            scanning: _scanning,
            canScanReceipt: widget.receiptOcr != null,
            onScanReceipt: _scanReceipt,
            extracting: _extracting,
            canGenerateFromConversation: widget.extractor != null &&
                widget.job != null &&
                widget.turnsRepository != null,
            onGenerateFromConversation: _generateFromConversation,
          ),
          _PreviewTab(
            jobTitle: widget.jobTitle,
            items: _items,
            paymentTerms: _paymentTerms.text,
            notes: _notes.text,
            totalCents: _totalCents,
          ),
        ],
      ),
    );
  }
}

// ── Edit tab ──────────────────────────────────────────────────────────────

class _EditTab extends StatelessWidget {
  final List<InvoiceLineItem> items;
  final TextEditingController paymentTerms;
  final TextEditingController notes;
  final int totalCents;
  final VoidCallback onAdd;
  final void Function(int) onRemove;
  final void Function(int, InvoiceLineItem) onUpdate;
  final bool scanning;
  final bool canScanReceipt;
  final VoidCallback onScanReceipt;
  final bool extracting;
  final bool canGenerateFromConversation;
  final VoidCallback onGenerateFromConversation;

  const _EditTab({
    required this.items,
    required this.paymentTerms,
    required this.notes,
    required this.totalCents,
    required this.onAdd,
    required this.onRemove,
    required this.onUpdate,
    required this.scanning,
    required this.canScanReceipt,
    required this.onScanReceipt,
    required this.extracting,
    required this.canGenerateFromConversation,
    required this.onGenerateFromConversation,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── AI generate from conversation ─────────────────────────────
        if (canGenerateFromConversation) ...[
          _AiInvoiceGenerateCard(
            extracting: extracting,
            onGenerate: onGenerateFromConversation,
          ),
          const SizedBox(height: 12),
        ],

        // ── Receipt scan ──────────────────────────────────────────────
        if (canScanReceipt) ...[
          _ReceiptScanCard(scanning: scanning, onScan: onScanReceipt),
          const SizedBox(height: 16),
        ],

        // ── Line items ────────────────────────────────────────────────
        Row(
          children: [
            Text('Line items',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              onPressed: (scanning || extracting) ? null : onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),

        if (scanning)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Scanning receipt…',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No items yet. Tap Add or scan a receipt.',
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic),
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
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        const SizedBox(height: 20),

        // ── Payment terms ─────────────────────────────────────────────
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
            hintText: 'e.g. Payment due within 14 days.',
          ),
        ),
        const SizedBox(height: 20),

        // ── Notes ─────────────────────────────────────────────────────
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
            hintText: 'Invoice notes, inclusions, exclusions…',
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── AI invoice generate card ──────────────────────────────────────────────

class _AiInvoiceGenerateCard extends StatelessWidget {
  final bool extracting;
  final VoidCallback onGenerate;
  const _AiInvoiceGenerateCard(
      {required this.extracting, required this.onGenerate});

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
              'Generate from invoice context',
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

// ── Receipt scan card ─────────────────────────────────────────────────────

class _ReceiptScanCard extends StatelessWidget {
  final bool scanning;
  final VoidCallback onScan;
  const _ReceiptScanCard({required this.scanning, required this.onScan});

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
            onPressed: scanning ? null : onScan,
            style: FilledButton.styleFrom(
              backgroundColor: amber,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            ),
            child: scanning
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

// ── Line item row with source chip ────────────────────────────────────────

class _LineItemRow extends StatefulWidget {
  final int index;
  final InvoiceLineItem item;
  final VoidCallback onRemove;
  final void Function(InvoiceLineItem) onChanged;

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
    _qty = TextEditingController(
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
    final qty = double.tryParse(_qty.text.trim()) ?? 1.0;
    final unit =
        ((double.tryParse(_unit.text.trim()) ?? 0.0) * 100).round();
    widget.onChanged(widget.item.copyWith(
      description: _desc.text.trim(),
      quantity: qty,
      unitCents: unit,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Description + source chip ─────────────────────────
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _desc,
                  onChanged: (_) => _emit(),
                  decoration: const InputDecoration(
                    hintText: 'Item description',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(height: 4),
                _SourceChip(source: widget.item.source, cs: cs),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // ── Qty ───────────────────────────────────────────────
          SizedBox(
            width: 52,
            child: TextField(
              controller: _qty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d*$')),
              ],
              onChanged: (_) => _emit(),
              decoration: const InputDecoration(
                hintText: 'Qty',
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // ── Unit $ ────────────────────────────────────────────
          SizedBox(
            width: 72,
            child: TextField(
              controller: _unit,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'^\d*\.?\d{0,2}$')),
              ],
              onChanged: (_) => _emit(),
              decoration: const InputDecoration(
                hintText: '\$0.00',
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                prefixText: '\$',
              ),
            ),
          ),
          const SizedBox(width: 4),
          // ── Remove ────────────────────────────────────────────
          IconButton(
            onPressed: widget.onRemove,
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 28, minHeight: 28),
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

// ── Source chip ──────────────────────────────────────────────────────────

class _SourceChip extends StatelessWidget {
  final InvoiceLineSource source;
  final ColorScheme cs;
  const _SourceChip({required this.source, required this.cs});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (source) {
      InvoiceLineSource.quote => ('quote', cs.primary),
      InvoiceLineSource.receipt => ('receipt', const Color(0xFFF59E0B)),
      InvoiceLineSource.manual => ('manual', cs.onSurfaceVariant),
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.6),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Preview tab ──────────────────────────────────────────────────────────

class _PreviewTab extends StatelessWidget {
  final String jobTitle;
  final List<InvoiceLineItem> items;
  final String paymentTerms;
  final String notes;
  final int totalCents;

  const _PreviewTab({
    required this.jobTitle,
    required this.items,
    required this.paymentTerms,
    required this.notes,
    required this.totalCents,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TAX INVOICE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: cs.primary,
                  ),
                ),
                if (jobTitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(jobTitle,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 16),
                if (items.isEmpty)
                  Text('No items.',
                      style: TextStyle(color: cs.onSurfaceVariant))
                else
                  ...items.map((item) => Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item.quantity == item.quantity.roundToDouble() ? item.quantity.toInt() : item.quantity}'
                                ' × ${item.description}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              _formatCents(item.totalCents),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      )),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Total  ${_formatCents(totalCents)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ],
                ),
                if (paymentTerms.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(paymentTerms,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(notes,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────

String _formatCents(int cents) {
  final dollars = cents ~/ 100;
  final c = cents % 100;
  return '\$$dollars.${c.toString().padLeft(2, '0')}';
}

```
