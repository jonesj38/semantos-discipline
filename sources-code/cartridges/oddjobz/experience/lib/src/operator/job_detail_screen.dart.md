---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/job_detail_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.464703+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/job_detail_screen.dart

```dart
// JobDetailScreen — shows job metadata + full conversation thread.
// The conversation thread is fetched via the new
// GET /api/v1/conversation/turns?entityRef=<cellHash> endpoint.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'brain_client.dart';
import 'conversation_turn.dart';
import 'job.dart';
import 'quote_catalog.dart';
import 'quote_catalog_store.dart';
import 'quote_document.dart';
import 'quote_editor_screen.dart';
import 'quote_import_service.dart';
import 'quote_seed.dart';
import 'turn_bubble.dart';

class JobVoiceNoteCapture {
  final Uint8List audioBytes;
  final String filename;
  final String? transcriptHint;

  const JobVoiceNoteCapture({
    required this.audioBytes,
    this.filename = 'voice-note.webm',
    this.transcriptHint,
  });
}

typedef JobVoiceNoteCaptureProvider = Future<JobVoiceNoteCapture?> Function();

class JobAttachmentCapture {
  final Uint8List blobBytes;
  final String filename;
  final String metadataJson;

  const JobAttachmentCapture({
    required this.blobBytes,
    required this.metadataJson,
    this.filename = 'attachment.bin',
  });
}

typedef JobAttachmentCaptureProvider =
    Future<JobAttachmentCapture?> Function(Job job);

class JobDetailScreen extends StatefulWidget {
  final Job job;
  final BrainClient client;
  final JobVoiceNoteCaptureProvider? captureVoiceNote;
  final JobAttachmentCaptureProvider? captureAttachment;

  const JobDetailScreen({
    super.key,
    required this.job,
    required this.client,
    this.captureVoiceNote,
    this.captureAttachment,
  });

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  late Job _job;
  final _scrollController = ScrollController();
  final _turnKeys = <String, GlobalKey>{};
  Timer? _highlightTimer;
  List<ConversationTurn> _turns = const [];
  String? _highlightedTurnId;
  bool _loading = true;
  String? _error;
  String? _approving;
  bool _quoting = false;
  String? _quoteResult;
  final _noteController = TextEditingController();
  bool _sendingNote = false;
  bool _sendingVoiceNote = false;
  bool _uploadingAttachment = false;
  QuoteDocument? _draftQuote;
  bool _includeConversationContextInQuote = true;

  @override
  void initState() {
    super.initState();
    _job = widget.job;
    _loadTurns();
  }

  Future<void> _loadTurns() async {
    final cellId = _job.cellId;
    if (cellId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final turns = await widget.client.fetchTurns(entityRef: cellId);
      if (!mounted) return;
      setState(() => _turns = turns);
    } on BrainClientError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approveTurn(String turnId) async {
    setState(() => _approving = turnId);
    try {
      await widget.client.approveTurn(turnId);
      await _loadTurns();
    } on BrainClientError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Approve failed: ${e.message}')));
    } finally {
      if (mounted) setState(() => _approving = null);
    }
  }

  List<QuoteSourcePatch> get _quoteSourcePatches => [
    for (final turn in _turns)
      QuoteSourcePatch(
        ref: 'turn:${turn.turnId}',
        title: '${turn.surface} · ${turn.participantRole}',
        subtitle: DateTime.fromMillisecondsSinceEpoch(
          turn.timestamp,
        ).toLocal().toString(),
        body: turn.bodyText,
      ),
  ];

  ScgQuoteImportService get _quoteImportService =>
      FallbackScgQuoteImportService(
        primary: EdgeScgQuoteImportService(widget.client),
        fallback: DeterministicScgQuoteImportService(turns: _turns),
      );

  Future<void> _openQuoteEditor() async {
    setState(() {
      _quoting = true;
      _quoteResult = null;
    });
    try {
      final catalog = await QuoteCatalogStore().load();
      if (!mounted) return;
      final initialDraft =
          _draftQuote ??
          (_includeConversationContextInQuote
              ? quoteDraftSeededFromConversation(
                  jobId: _job.id,
                  turns: _turns,
                  catalogItems: catalog,
                )
              : QuoteDocument.newForJob(_job.id));
      final editorResult = await showQuoteEditor(
        context,
        initial: initialDraft,
        catalogItems: catalog,
        sourcePatches: _quoteSourcePatches,
        importFromSources: (current, selectedPatches) =>
            _quoteImportService.importFromSources(
              current: current,
              selectedPatches: selectedPatches,
              catalogItems: catalog,
            ),
        jobTitle: _job.customerName.isNotEmpty ? _job.customerName : _job.id,
      );
      if (!mounted || editorResult == null) return;
      final draft = editorResult.document;
      if (editorResult.shouldJumpToSource) {
        setState(() => _draftQuote = draft);
        await _jumpToProvenanceRef(editorResult.jumpToSourceRef!);
        return;
      }
      final result = await widget.client.saveQuoteDraft(draft);
      if (!mounted) return;
      setState(() {
        _draftQuote = draft;
        _quoteResult = result.isEmpty
            ? 'Saved quote draft · total ${formatCents(draft.totalCents)}'
            : result;
      });
      await _loadTurns();
    } catch (e) {
      if (!mounted) return;
      setState(() => _quoteResult = 'Error: $e');
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  GlobalKey _turnKey(String turnId) => _turnKeys.putIfAbsent(
    turnId,
    () => GlobalKey(debugLabel: 'turn:$turnId'),
  );

  Future<void> _jumpToProvenanceRef(String ref) async {
    if (!ref.startsWith('turn:')) return;
    final turnId = ref.substring('turn:'.length);
    setState(() => _highlightedTurnId = turnId);
    final key = _turnKeys[turnId];
    final context = key?.currentContext;
    if (context != null) {
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.25,
      );
    }
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _highlightedTurnId == turnId) {
        setState(() => _highlightedTurnId = null);
      }
    });
  }

  List<String> get _quoteProvenanceRefs {
    final refs = <String>{};
    for (final item in _draftQuote?.lineItems ?? const []) {
      refs.addAll(item.provenanceRefs);
    }
    return refs.toList(growable: false)..sort();
  }

  int get _proposedCount => _turns.where((t) => t.isProposed).length;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _noteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _uploadAttachment() async {
    if (_job.cellId == null || _uploadingAttachment) return;

    final captureProvider = widget.captureAttachment;
    if (captureProvider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attachment capture is not available.')),
      );
      return;
    }

    setState(() => _uploadingAttachment = true);
    try {
      final capture = await captureProvider(_job);
      if (!mounted || capture == null) return;
      await widget.client.uploadJobAttachment(
        metadataJson: capture.metadataJson,
        blobBytes: capture.blobBytes,
        filename: capture.filename,
      );
      final refreshed = await widget.client.findJob(_job.id);
      if (!mounted) return;
      if (refreshed != null) setState(() => _job = refreshed);
      await _loadTurns();
    } on BrainClientError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Attachment upload failed: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Attachment upload failed: $e')));
    } finally {
      if (mounted) setState(() => _uploadingAttachment = false);
    }
  }

  Future<void> _sendVoiceNote() async {
    final cellId = _job.cellId;
    if (cellId == null || _sendingVoiceNote) return;

    final captureProvider = widget.captureVoiceNote;
    if (captureProvider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice note capture is not available.')),
      );
      return;
    }

    setState(() => _sendingVoiceNote = true);
    try {
      final capture = await captureProvider();
      if (!mounted || capture == null) return;
      await widget.client.submitJobVoiceNote(
        jobCellId: cellId,
        audioBytes: capture.audioBytes,
        filename: capture.filename,
        transcriptHint: capture.transcriptHint,
      );
      await _loadTurns();
    } on BrainClientError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice note failed: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Voice note failed: $e')));
    } finally {
      if (mounted) setState(() => _sendingVoiceNote = false);
    }
  }

  Future<void> _sendNote() async {
    final cellId = _job.cellId;
    final text = _noteController.text.trim();
    if (cellId == null || text.isEmpty || _sendingNote) return;

    final now = DateTime.now();
    final pending = ConversationTurn(
      turnId: 'pending-${now.millisecondsSinceEpoch}',
      conversationId: 'pending',
      participantRole: 'operator',
      direction: 'outbound',
      surface: 'widget',
      bodyText: text,
      timestamp: now.millisecondsSinceEpoch,
      outboundState: 'pending',
      entityCellHash: cellId,
    );

    setState(() {
      _sendingNote = true;
      _turns = [..._turns, pending];
      _noteController.clear();
    });

    try {
      await widget.client.submitJobNote(jobCellId: cellId, text: text);
      await _loadTurns();
    } on BrainClientError catch (e) {
      if (!mounted) return;
      setState(() {
        _turns = [
          for (final turn in _turns)
            if (turn.turnId == pending.turnId)
              ConversationTurn(
                turnId: turn.turnId,
                conversationId: turn.conversationId,
                participantRole: turn.participantRole,
                direction: turn.direction,
                surface: turn.surface,
                bodyText: turn.bodyText,
                timestamp: turn.timestamp,
                outboundState: 'failed',
                identityValue: turn.identityValue,
                entityCellHash: turn.entityCellHash,
              )
            else
              turn,
        ];
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Note failed: ${e.message}')));
    } finally {
      if (mounted) setState(() => _sendingNote = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          job.customerName.isNotEmpty ? job.customerName : job.id,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              label: Text(
                job.stateLabel.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: job.isDone ? cs.onTertiaryContainer : cs.primary,
                ),
              ),
              backgroundColor: job.isDone
                  ? cs.tertiaryContainer
                  : cs.primaryContainer,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTurns,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            // ── Job metadata chips ──────────────────────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (job.workOrderNumber != null)
                  _MetaChip('WO ${job.workOrderNumber}'),
                if (job.propertyAddress != null)
                  _MetaChip('📍 ${job.propertyAddress}'),
                if (job.services != null) _MetaChip('🔧 ${job.services}'),
                if (job.scheduledAt != null && job.scheduledAt!.isNotEmpty)
                  _MetaChip('🗓 ${job.scheduledAt}'),
                if (job.cellId != null)
                  Tooltip(
                    message: job.cellId,
                    child: _MetaChip(
                      'cell ${job.cellId!.substring(0, 8)}…',
                      dim: true,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Quick actions ────────────────────────────────────────────
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (['lead', 'qualified'].contains(job.state))
                  FilledButton.tonalIcon(
                    onPressed: _quoting ? null : _openQuoteEditor,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(
                      _quoting ? 'Generating…' : 'Autogenerate quote',
                    ),
                  ),
                if (job.cellId != null) ...[
                  FilterChip(
                    label: const Text('Conversation patches feed quote'),
                    selected: _includeConversationContextInQuote,
                    onSelected: (value) => setState(
                      () => _includeConversationContextInQuote = value,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _sendingVoiceNote ? null : _sendVoiceNote,
                    icon: _sendingVoiceNote
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.mic, size: 18),
                    label: Text(
                      _sendingVoiceNote ? 'Uploading…' : 'Voice note',
                    ),
                  ),
                ],
                if (job.cellId != null) ...[
                  OutlinedButton.icon(
                    onPressed: _uploadingAttachment ? null : _uploadAttachment,
                    icon: _uploadingAttachment
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file, size: 18),
                    label: Text(
                      _uploadingAttachment ? 'Uploading…' : 'Add attachment',
                    ),
                  ),
                ],
                if (_proposedCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB24A).withOpacity(0.15),
                      border: Border.all(
                        color: const Color(0xFFFFB24A).withOpacity(0.4),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$_proposedCount pending approval',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFFE65100),
                      ),
                    ),
                  ),
                ],
              ],
            ),

            if (_quoteResult != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      _quoteResult!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                    if (_quoteProvenanceRefs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Quote sources',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final ref in _quoteProvenanceRefs)
                            ActionChip(
                              label: Text(ref),
                              avatar: Icon(
                                ref.startsWith('turn:')
                                    ? Icons.forum_outlined
                                    : Icons.sell_outlined,
                                size: 14,
                              ),
                              onPressed: ref.startsWith('turn:')
                                  ? () => _jumpToProvenanceRef(ref)
                                  : null,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            const SizedBox(height: 16),

            Text(
              'ATTACHMENTS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            if (job.attachmentRefs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'No attachments yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final ref in job.attachmentRefs)
                    Tooltip(
                      message: ref,
                      child: _MetaChip(
                        '📎 ${ref.length > 12 ? '${ref.substring(0, 12)}…' : ref}',
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 16),

            // ── Conversation thread header ───────────────────────────────
            Row(
              children: [
                Text(
                  'CONVERSATION',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: _loadTurns,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Turn list ─────────────────────────────────────────────────
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              )
            else if (job.cellId == null)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'No cellId — job not yet entity-anchored.',
                  style: TextStyle(color: Colors.orange),
                ),
              )
            else if (_turns.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'No conversation turns yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              for (final turn in _turns)
                TurnBubble(
                  key: _turnKey(turn.turnId),
                  turn: turn,
                  approving: _approving == turn.turnId,
                  highlighted: _highlightedTurnId == turn.turnId,
                  onApprove: turn.isProposed
                      ? () => _approveTurn(turn.turnId)
                      : null,
                ),

            const SizedBox(height: 12),
            if (job.cellId == null)
              const Text(
                'Add a cellId before writing job-scoped notes.',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              )
            else
              _NoteComposer(
                controller: _noteController,
                sending: _sendingNote,
                onSend: _sendNote,
              ),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final bool dim;
  const _MetaChip(this.label, {this.dim = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: dim
              ? cs.onSurfaceVariant.withOpacity(0.6)
              : cs.onSurfaceVariant,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _NoteComposer extends StatelessWidget {
  const _NoteComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !sending,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Add a note to this job conversation…',
                border: InputBorder.none,
                isDense: true,
              ),
              textInputAction: TextInputAction.newline,
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Send note',
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

```
