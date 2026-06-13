---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/quote_editor_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.466566+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/quote_editor_screen.dart

```dart
import 'package:flutter/material.dart';

import 'quote_catalog.dart';
import 'quote_document.dart';

class QuoteSourcePatch {
  const QuoteSourcePatch({
    required this.ref,
    required this.title,
    required this.body,
    this.subtitle = '',
  });

  final String ref;
  final String title;
  final String subtitle;
  final String body;
}

typedef ScgQuoteImporter =
    Future<QuoteDocument> Function(
      QuoteDocument current,
      List<QuoteSourcePatch> selectedPatches,
    );

class QuoteEditorResult {
  const QuoteEditorResult.useDraft(this.document) : jumpToSourceRef = null;
  const QuoteEditorResult.jumpToSource(this.jumpToSourceRef, this.document);

  final QuoteDocument document;
  final String? jumpToSourceRef;

  bool get shouldJumpToSource => jumpToSourceRef != null;
}

Future<QuoteEditorResult?> showQuoteEditor(
  BuildContext context, {
  required QuoteDocument initial,
  required List<QuoteCatalogItem> catalogItems,
  List<QuoteSourcePatch> sourcePatches = const [],
  ScgQuoteImporter? importFromSources,
  String jobTitle = '',
}) {
  return showModalBottomSheet<QuoteEditorResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => QuoteEditorSheet(
      initial: initial,
      catalogItems: catalogItems,
      sourcePatches: sourcePatches,
      importFromSources: importFromSources,
      jobTitle: jobTitle,
    ),
  );
}

class QuoteEditorSheet extends StatefulWidget {
  const QuoteEditorSheet({
    super.key,
    required this.initial,
    required this.catalogItems,
    this.sourcePatches = const [],
    this.importFromSources,
    this.jobTitle = '',
  });

  final QuoteDocument initial;
  final List<QuoteCatalogItem> catalogItems;
  final List<QuoteSourcePatch> sourcePatches;
  final ScgQuoteImporter? importFromSources;
  final String jobTitle;

  @override
  State<QuoteEditorSheet> createState() => _QuoteEditorSheetState();
}

class _QuoteEditorSheetState extends State<QuoteEditorSheet> {
  late List<QuoteLineItem> _items;
  late final TextEditingController _summary;
  late final TextEditingController _terms;
  late final TextEditingController _notes;
  late final TextEditingController _markdown;
  final _selectedSourceRefs = <String>{};
  bool _preview = false;
  bool _sourceSide = false;
  bool _importingSources = false;

  @override
  void initState() {
    super.initState();
    _items = [...widget.initial.lineItems];
    _summary = TextEditingController(text: widget.initial.customerSummary);
    _terms = TextEditingController(text: widget.initial.paymentTerms);
    _notes = TextEditingController(text: widget.initial.notes);
    _markdown = TextEditingController(text: widget.initial.markdown);
  }

  @override
  void dispose() {
    _summary.dispose();
    _terms.dispose();
    _notes.dispose();
    _markdown.dispose();
    super.dispose();
  }

  QuoteDocument _document() => widget.initial.copyWith(
    lineItems: _items,
    customerSummary: _summary.text.trim(),
    paymentTerms: _terms.text.trim(),
    notes: _notes.text.trim(),
    markdown: _markdown.text.trim(),
    updatedAt: DateTime.now().toUtc(),
  );

  void _addBlankLine() {
    setState(() {
      _items = [
        ..._items,
        const QuoteLineItem(description: '', quantity: 1, unitCents: 0),
      ];
    });
  }

  void _addCatalogItem(QuoteCatalogItem item) {
    setState(() => _items = [..._items, item.toLineItem()]);
  }

  void _updateItem(int index, QuoteLineItem item) {
    setState(() {
      _items = [
        for (var i = 0; i < _items.length; i++)
          if (i == index) item else _items[i],
      ];
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items = [
        for (var i = 0; i < _items.length; i++)
          if (i != index) _items[i],
      ];
    });
  }

  void _jumpToSource(String ref) {
    Navigator.of(context).pop(QuoteEditorResult.jumpToSource(ref, _document()));
  }

  void _toggleSourcePatch(String ref, bool selected) {
    setState(() {
      if (selected) {
        _selectedSourceRefs.add(ref);
      } else {
        _selectedSourceRefs.remove(ref);
      }
    });
  }

  Future<void> _importSelectedSources() async {
    final importer = widget.importFromSources;
    if (importer == null || _selectedSourceRefs.isEmpty) return;
    setState(() => _importingSources = true);
    try {
      final patches = widget.sourcePatches
          .where((patch) => _selectedSourceRefs.contains(patch.ref))
          .toList(growable: false);
      final imported = await importer(_document(), patches);
      if (!mounted) return;
      setState(() {
        _items = [...imported.lineItems];
        _summary.text = imported.customerSummary;
        _terms.text = imported.paymentTerms;
        _notes.text = imported.notes;
        _markdown.text = imported.markdown;
        _sourceSide = false;
      });
    } finally {
      if (mounted) setState(() => _importingSources = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _document();
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.98,
      minChildSize: 0.5,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quote draft',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (widget.jobTitle.isNotEmpty)
                        Text(
                          widget.jobTitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton.filledTonal(
                      tooltip: _sourceSide
                          ? 'Flip back to quote'
                          : 'Flip to conversation sources',
                      icon: Icon(
                        _sourceSide
                            ? Icons.description_outlined
                            : Icons.flip_to_back_outlined,
                      ),
                      onPressed: widget.sourcePatches.isEmpty
                          ? null
                          : () => setState(() => _sourceSide = !_sourceSide),
                    ),
                    _CompactQuoteSourceChips(
                      doc: doc,
                      onSourceTap: _jumpToSource,
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Edit')),
                        ButtonSegment(value: true, label: Text('Preview')),
                      ],
                      selected: {_preview},
                      onSelectionChanged: (v) =>
                          setState(() => _preview = v.first),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _sourceSide
                ? _QuoteSourceBack(
                    scrollController: scrollController,
                    sourcePatches: widget.sourcePatches,
                    selectedRefs: _selectedSourceRefs,
                    importing: _importingSources,
                    canImport: widget.importFromSources != null,
                    onToggle: _toggleSourcePatch,
                    onJump: _jumpToSource,
                    onImport: _importSelectedSources,
                  )
                : _preview
                ? _QuotePreview(
                    scrollController: scrollController,
                    doc: doc,
                    onSourceTap: _jumpToSource,
                  )
                : _QuoteEdit(
                    scrollController: scrollController,
                    doc: doc,
                    catalogItems: widget.catalogItems,
                    summary: _summary,
                    terms: _terms,
                    notes: _notes,
                    markdown: _markdown,
                    onAddBlankLine: _addBlankLine,
                    onAddCatalogItem: _addCatalogItem,
                    onUpdateItem: _updateItem,
                    onRemoveItem: _removeItem,
                    onSourceTap: _jumpToSource,
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total ${formatCents(doc.totalCents)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(QuoteEditorResult.useDraft(doc)),
                    icon: const Icon(Icons.check),
                    label: const Text('Use draft'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteSourceBack extends StatelessWidget {
  const _QuoteSourceBack({
    required this.scrollController,
    required this.sourcePatches,
    required this.selectedRefs,
    required this.importing,
    required this.canImport,
    required this.onToggle,
    required this.onJump,
    required this.onImport,
  });

  final ScrollController scrollController;
  final List<QuoteSourcePatch> sourcePatches;
  final Set<String> selectedRefs;
  final bool importing;
  final bool canImport;
  final void Function(String ref, bool selected) onToggle;
  final ValueChanged<String> onJump;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (sourcePatches.isEmpty) {
      return const Center(child: Text('No conversation sources available.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Conversation sources',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: canImport && selectedRefs.isNotEmpty && !importing
                    ? onImport
                    : null,
                icon: importing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(importing ? 'Importing…' : 'Import to quote'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: sourcePatches.length,
            itemBuilder: (context, index) {
              final patch = sourcePatches[index];
              final selected = selectedRefs.contains(patch.ref);
              return Card(
                child: CheckboxListTile(
                  value: selected,
                  onChanged: (value) => onToggle(patch.ref, value ?? false),
                  title: Text(patch.title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (patch.subtitle.isNotEmpty) Text(patch.subtitle),
                      const SizedBox(height: 4),
                      Text(
                        patch.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: patch.ref.startsWith('turn:')
                              ? () => onJump(patch.ref)
                              : null,
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: Text(patch.ref),
                        ),
                      ),
                    ],
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CompactQuoteSourceChips extends StatelessWidget {
  const _CompactQuoteSourceChips({
    required this.doc,
    required this.onSourceTap,
  });

  final QuoteDocument doc;
  final ValueChanged<String> onSourceTap;

  @override
  Widget build(BuildContext context) {
    final refs = <String>{};
    for (final item in doc.lineItems) {
      refs.addAll(item.provenanceRefs.where((ref) => ref.startsWith('turn:')));
    }
    final sorted = refs.toList(growable: false)..sort();
    if (sorted.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final ref in sorted.take(2))
          ActionChip(
            visualDensity: VisualDensity.compact,
            label: Text(ref),
            avatar: const Icon(Icons.forum_outlined, size: 14),
            onPressed: () => onSourceTap(ref),
          ),
      ],
    );
  }
}

class _QuoteEdit extends StatelessWidget {
  const _QuoteEdit({
    required this.scrollController,
    required this.doc,
    required this.catalogItems,
    required this.summary,
    required this.terms,
    required this.notes,
    required this.markdown,
    required this.onAddBlankLine,
    required this.onAddCatalogItem,
    required this.onUpdateItem,
    required this.onRemoveItem,
    required this.onSourceTap,
  });

  final ScrollController scrollController;
  final QuoteDocument doc;
  final List<QuoteCatalogItem> catalogItems;
  final TextEditingController summary;
  final TextEditingController terms;
  final TextEditingController notes;
  final TextEditingController markdown;
  final VoidCallback onAddBlankLine;
  final void Function(QuoteCatalogItem item) onAddCatalogItem;
  final void Function(int index, QuoteLineItem item) onUpdateItem;
  final void Function(int index) onRemoveItem;
  final ValueChanged<String> onSourceTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        if (catalogItems.isEmpty)
          _HintBox(
            icon: Icons.price_change_outlined,
            text:
                'No operator catalog configured yet. Add manual line items '
                'here; manage reusable catalog/policy from Me → Brain management.',
          )
        else ...[
          Text('Operator catalog', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in catalogItems)
                ActionChip(
                  label: Text('${item.description} · ${item.priceLabel}'),
                  onPressed: () => onAddCatalogItem(item),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),

        TextField(
          controller: markdown,
          decoration: const InputDecoration(
            labelText: 'Editable Markdown quote',
            helperText:
                'Autogenerated from conversation/catalog; edit before sending.',
            border: OutlineInputBorder(),
          ),
          minLines: 8,
          maxLines: 18,
        ),
        const SizedBox(height: 16),
        _QuoteSourceChips(doc: doc, onSourceTap: onSourceTap),
        const SizedBox(height: 16),
        TextField(
          controller: summary,
          decoration: const InputDecoration(
            labelText: 'Customer summary',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Line items', style: theme.textTheme.titleSmall),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onAddBlankLine,
              icon: const Icon(Icons.add),
              label: const Text('Manual line'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (doc.lineItems.isEmpty)
          const _HintBox(
            icon: Icons.format_list_bulleted,
            text: 'No line items yet.',
          )
        else
          for (var i = 0; i < doc.lineItems.length; i++)
            _LineItemEditor(
              key: ValueKey(
                'line-$i-${doc.lineItems[i].sourceCatalogItemId ?? ''}',
              ),
              item: doc.lineItems[i],
              onChanged: (item) => onUpdateItem(i, item),
              onRemove: () => onRemoveItem(i),
            ),
        const SizedBox(height: 16),
        TextField(
          controller: terms,
          decoration: const InputDecoration(
            labelText: 'Payment terms',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notes,
          decoration: const InputDecoration(
            labelText: 'Assumptions / notes',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
      ],
    );
  }
}

class _LineItemEditor extends StatefulWidget {
  const _LineItemEditor({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  final QuoteLineItem item;
  final void Function(QuoteLineItem item) onChanged;
  final VoidCallback onRemove;

  @override
  State<_LineItemEditor> createState() => _LineItemEditorState();
}

class _LineItemEditorState extends State<_LineItemEditor> {
  late final TextEditingController _description;
  late final TextEditingController _quantity;
  late final TextEditingController _unitCents;

  @override
  void initState() {
    super.initState();
    _description = TextEditingController(text: widget.item.description);
    _quantity = TextEditingController(text: _formatQty(widget.item.quantity));
    _unitCents = TextEditingController(
      text: (widget.item.unitCents / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _unitCents.dispose();
    super.dispose();
  }

  void _emit() {
    final qty = double.tryParse(_quantity.text.trim()) ?? widget.item.quantity;
    final dollars =
        double.tryParse(_unitCents.text.trim()) ??
        (widget.item.unitCents / 100);
    widget.onChanged(
      widget.item.copyWith(
        description: _description.text.trim(),
        quantity: qty,
        unitCents: (dollars * 100).round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              onChanged: (_) => _emit(),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Qty'),
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _unitCents,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Unit price'),
                    onChanged: (_) => _emit(),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove line',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text('Line total ${formatCents(widget.item.totalCents)}'),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatQty(double qty) =>
      qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
}

class _QuotePreview extends StatelessWidget {
  const _QuotePreview({
    required this.scrollController,
    required this.doc,
    required this.onSourceTap,
  });

  final ScrollController scrollController;
  final QuoteDocument doc;
  final ValueChanged<String> onSourceTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quote preview', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _QuoteSourceChips(doc: doc, onSourceTap: onSourceTap),
                if (doc.markdown.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(doc.markdown.trim()),
                  const Divider(height: 24),
                ],
                const SizedBox(height: 8),
                Text(
                  doc.customerSummary.isEmpty
                      ? 'Quote for job ${doc.jobId}'
                      : doc.customerSummary,
                ),
                const Divider(height: 24),
                if (doc.lineItems.isEmpty)
                  const Text('No line items.')
                else
                  for (final item in doc.lineItems)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.description.isEmpty
                                  ? '(untitled)'
                                  : item.description,
                            ),
                          ),
                          Text(
                            '${_LineItemEditorState._formatQty(item.quantity)} × ${formatCents(item.unitCents)}',
                          ),
                          const SizedBox(width: 12),
                          Text(formatCents(item.totalCents)),
                        ],
                      ),
                    ),
                const Divider(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total ${formatCents(doc.totalCents)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (doc.paymentTerms.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Payment terms', style: theme.textTheme.titleSmall),
                  Text(doc.paymentTerms),
                ],
                if (doc.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Notes', style: theme.textTheme.titleSmall),
                  Text(doc.notes),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuoteSourceChips extends StatelessWidget {
  const _QuoteSourceChips({required this.doc, required this.onSourceTap});

  final QuoteDocument doc;
  final ValueChanged<String> onSourceTap;

  @override
  Widget build(BuildContext context) {
    final refs = <String>{};
    for (final item in doc.lineItems) {
      refs.addAll(item.provenanceRefs);
    }
    final sorted = refs.toList(growable: false)..sort();
    if (sorted.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quote sources', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final ref in sorted)
              ActionChip(
                label: Text(ref),
                avatar: Icon(
                  ref.startsWith('turn:')
                      ? Icons.forum_outlined
                      : Icons.sell_outlined,
                  size: 14,
                ),
                onPressed: ref.startsWith('turn:')
                    ? () => onSourceTap(ref)
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _HintBox extends StatelessWidget {
  const _HintBox({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

```
