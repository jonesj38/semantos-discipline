---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/quote_import_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.462919+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/quote_import_service.dart

```dart
import 'brain_client.dart';
import 'conversation_turn.dart';
import 'quote_catalog.dart';
import 'quote_document.dart';
import 'quote_editor_screen.dart' show QuoteSourcePatch;
import 'quote_seed.dart';

/// Edge/SCG quote import boundary.
///
/// The UI selects conversation/source patches. This service is responsible for
/// turning those selected sources into a richer quote draft. The preferred path
/// is an edge SCG+LLM extractor (not substrate/brain-side AI). Until that route
/// is deployed, callers can use [FallbackScgQuoteImportService] to preserve the
/// UX with deterministic local extraction.
abstract interface class ScgQuoteImportService {
  Future<QuoteDocument> importFromSources({
    required QuoteDocument current,
    required List<QuoteSourcePatch> selectedPatches,
    required List<QuoteCatalogItem> catalogItems,
  });
}

class EdgeScgQuoteImportService implements ScgQuoteImportService {
  const EdgeScgQuoteImportService(this.client);

  final BrainClient client;

  @override
  Future<QuoteDocument> importFromSources({
    required QuoteDocument current,
    required List<QuoteSourcePatch> selectedPatches,
    required List<QuoteCatalogItem> catalogItems,
  }) {
    return client.extractQuoteFromSources(
      current: current,
      sourcePatches: selectedPatches,
      catalogItems: catalogItems,
    );
  }
}

class DeterministicScgQuoteImportService implements ScgQuoteImportService {
  const DeterministicScgQuoteImportService({required this.turns});

  final List<ConversationTurn> turns;

  @override
  Future<QuoteDocument> importFromSources({
    required QuoteDocument current,
    required List<QuoteSourcePatch> selectedPatches,
    required List<QuoteCatalogItem> catalogItems,
  }) async {
    final selectedTurnIds = {
      for (final patch in selectedPatches)
        if (patch.ref.startsWith('turn:')) patch.ref.substring('turn:'.length),
    };
    final selectedTurns = turns
        .where((turn) => selectedTurnIds.contains(turn.turnId))
        .toList(growable: false);
    final imported = quoteDraftSeededFromConversation(
      jobId: current.jobId,
      turns: selectedTurns,
      catalogItems: catalogItems,
    );
    final refs = selectedPatches.map((patch) => patch.ref).join(', ');
    return imported.copyWith(
      id: current.id,
      quoteId: current.quoteId,
      status: current.status,
      notes: [
        if (current.notes.trim().isNotEmpty) current.notes.trim(),
        if (imported.notes.trim().isNotEmpty) imported.notes.trim(),
        if (refs.isNotEmpty) 'Imported via SCG source selection: $refs',
      ].join('\n'),
      createdAt: current.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}

class FallbackScgQuoteImportService implements ScgQuoteImportService {
  const FallbackScgQuoteImportService({
    required this.primary,
    required this.fallback,
  });

  final ScgQuoteImportService primary;
  final ScgQuoteImportService fallback;

  @override
  Future<QuoteDocument> importFromSources({
    required QuoteDocument current,
    required List<QuoteSourcePatch> selectedPatches,
    required List<QuoteCatalogItem> catalogItems,
  }) async {
    try {
      return await primary.importFromSources(
        current: current,
        selectedPatches: selectedPatches,
        catalogItems: catalogItems,
      );
    } on BrainClientError catch (e) {
      // Route not deployed yet / intentionally disabled: keep operator UX live
      // with deterministic local import until the edge SCG+LLM service exists.
      if (e.statusCode != 404 && e.statusCode != 501) rethrow;
      return fallback.importFromSources(
        current: current,
        selectedPatches: selectedPatches,
        catalogItems: catalogItems,
      );
    }
  }
}

```
