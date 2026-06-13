---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/modal_verb_shelf.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.101928+00:00
---

# apps/semantos/lib/shell/modal_verb_shelf.dart

```dart
// C9 PR-C9-7c — modal verb shelf (DO | TALK | FIND), cartridge-neutral.
//
// Reference: docs/design/HELM-CANONICAL-SURFACE.md §3 (modal verb shelf)
//            + §5 (cartridge contribution model)
//            + canonicalization-matrix.yml C13 (verb-shelf inversion).
//
// Architecture lock (Todd 2026-05-29 "IDIOT" pushback):
//   - Shell is a neutral cartridge loader. Zero imports from any
//     cartridge package live in this file (or anywhere in the helm
//     chrome). The previous PR-C9-4 implementation imported Release
//     from betterment_experience and hardcoded a Self/betterment
//     tile — that's the leak this PR closes.
//   - Verbs come from the cartridge manifest's `ui.verbs[]`,
//     filtered by (active cartridge, active hat).
//   - Dispatch goes through IntentDispatcher.dispatchByName(name,
//     payload), which uses the dispatch metadata declared in the
//     cartridge manifest's ui.verbs[].dispatch block to mint without
//     the shell needing the typed intent class.
//   - Input collection uses a generic input sheet driven by
//     ui.verbs[].inputShape — no cartridge-specific input widget
//     code in the shell.
//
// History:
//   PR-C9-4 (#717): initial shelf with hardcoded Release tile +
//                   shell→cartridge import. Surfaced the architectural
//                   leak.
//   PR-C9-6 (#719): manifest ui.verbs[] schema + GrammarRegistry
//                   .verbsForModal() aggregator.
//   PR-C9-7c (this PR): drops shell→cartridge import + hardcoded tile
//                       + hardcoded _ReleaseSheet. Generic input sheet
//                       + active-cartridge scoping + dispatchByName.

import 'package:flutter/material.dart';
import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:semantos_core/semantos_core.dart';

import '../src/dispatch/intent_dispatcher.dart';
import 'cartridge_hat_state.dart';
import 'cell_list_screen.dart';
import 'semantos_platform.dart';

/// The three modal verbs from WALLET-VOICE-SHELL-GRAMMAR.md, surfaced
/// as a bottom-of-helm tri-button row. Cartridges contribute sub-
/// verbs INTO each modal via manifest `ui.verbs[]`.
///
/// This wraps the canonical [HelmVerbModal] from semantos_core with
/// shell-side label + icon presentation. Use [HelmVerbModal] as the
/// canonical enum; this helper just maps to UI affordances.
enum HelmModal { do_, talk, find }

extension HelmModalLabel on HelmModal {
  String get label => switch (this) {
        HelmModal.do_ => 'DO',
        HelmModal.talk => 'TALK',
        HelmModal.find => 'FIND',
      };

  IconData get icon => switch (this) {
        HelmModal.do_ => Icons.flash_on,
        HelmModal.talk => Icons.chat_bubble_outline,
        HelmModal.find => Icons.search,
      };

  HelmVerbModal get coreModal => switch (this) {
        HelmModal.do_ => HelmVerbModal.do_,
        HelmModal.talk => HelmVerbModal.talk,
        HelmModal.find => HelmVerbModal.find,
      };
}

/// Bottom-of-helm modal-verb-shelf widget.
///
/// Renders DO | TALK | FIND as three equal-weight buttons. Tap opens
/// the modal's sub-verb picker. The picker reads verbs from the active
/// cartridge's manifest (when one is active) or from all default-mode
/// cartridges (when none is — helm is in unscoped view).
class ModalVerbShelf extends StatelessWidget {
  const ModalVerbShelf({
    super.key,
    required this.dispatcher,
    required this.onMinted,
  });

  /// IntentDispatcher the sheet flows dispatch through.
  final IntentDispatcher dispatcher;

  /// Callback fired when a sub-verb successfully mints a cell.
  /// HelmHomeScreen uses this to update its recent-mints list.
  final void Function(IntentDispatchResult result, String payloadPreview)
      onMinted;

  void _open(BuildContext context, HelmModal modal) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => _ModalVerbSheet(
        modal: modal,
        dispatcher: dispatcher,
        onMinted: onMinted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final modal in HelmModal.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _ModalButton(
                    modal: modal,
                    onTap: () => _open(context, modal),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModalButton extends StatelessWidget {
  const _ModalButton({required this.modal, required this.onTap});

  final HelmModal modal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(modal.icon, color: theme.colorScheme.primary, size: 22),
              const SizedBox(height: 4),
              Text(
                modal.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet shown when a modal verb button is tapped. Reads the
/// active cartridge from [CartridgeHatScope] and the verbs for the
/// modal from [GrammarRegistry] — no cartridge-specific code lives
/// in this widget.
class _ModalVerbSheet extends StatelessWidget {
  const _ModalVerbSheet({
    required this.modal,
    required this.dispatcher,
    required this.onMinted,
  });

  final HelmModal modal;
  final IntentDispatcher dispatcher;
  final void Function(IntentDispatchResult result, String payloadPreview)
      onMinted;

  @override
  Widget build(BuildContext context) {
    final platform = SemantosPlatform.of(context);
    final hatState = CartridgeHatScope.of(context);
    final activeCartridge = hatState.activeCartridge;

    // Scope: if a cartridge is active, only its verbs show. If none,
    // show verbs across all default-mode cartridges (helm's unscoped
    // mode). This is the architectural lock per Todd 2026-05-29 —
    // selecting oddjobz must NOT show betterment.Release.
    final verbs = activeCartridge != null
        ? platform.grammarRegistry
            .verbsForModalAndExtension(modal.coreModal, activeCartridge)
        : platform.grammarRegistry.verbsForModal(modal.coreModal);

    final insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: insets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader(label: modal.label, activeCartridge: activeCartridge),
          const SizedBox(height: 12),
          if (verbs.isEmpty)
            _EmptyVerbsHint(modal: modal, activeCartridge: activeCartridge)
          else
            ...verbs.map((binding) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SubVerbTile(
                    // Wired = mints (dispatch) OR reads (M1.8 query block).
                    binding: binding,
                    hasDispatch:
                        dispatcher.hasBindingFor(binding.verb.intentType) ||
                            binding.verb.query != null,
                    onTap: () => _openVerb(context, binding),
                  ),
                )),
        ],
      ),
    );
  }

  void _openVerb(BuildContext context, HelmVerbBinding binding) {
    // M1.8 — a FIND verb with a `query` block is a READ: run cell.query over
    // the unified channel and render the rows generically. No dispatch needed.
    final query = binding.verb.query;
    if (query != null) {
      final rpc = SemantosPlatform.of(context).rpcClient;
      Navigator.of(context).pop(); // close the modal picker
      if (rpc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not connected to a brain.')),
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CellListScreen(rpc: rpc, query: query),
        ),
      );
      return;
    }

    final shape = binding.verb.inputShape;

    // A cartridge-owned custom capture surface (e.g. betterment's release
    // screen): push the registered builder instead of the generic sheet. The
    // screen does its own mint/OCR via CartridgeHostScope — no dispatch binding
    // needed, and the shell stays cartridge-neutral (lookup by manifest key).
    if (shape != null && shape.kind == HelmInputShapeKind.custom) {
      Navigator.of(context).pop();
      final key = shape.customKey ?? '';
      final builder = CustomVerbSurfaceRegistry.instance.builderFor(key);
      if (builder == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${binding.verb.label}: custom surface "$key" not registered. '
              'The cartridge must register it via CustomVerbSurfaceRegistry at boot.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
      Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
      return;
    }

    final hasDispatch = dispatcher.hasBindingFor(binding.verb.intentType);

    if (!hasDispatch) {
      // Declared in manifest but no `dispatch` block populated yet.
      // Honest signal — not a crash.
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${binding.extensionName} · ${binding.verb.label}: not yet wired. '
            'Add a `dispatch` block (cellType + triple + defaultPayload) '
            'to this verb in the cartridge manifest to enable it.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (shape == null) {
      // No input UI — dispatch immediately with empty payload (binding's
      // defaultPayload covers any required fields). Useful for "click
      // and go" verbs.
      Navigator.of(context).pop();
      _dispatchAndReport(context, binding, const {});
      return;
    }

    // Generic input sheet driven by ui.verbs[].inputShape.
    Navigator.of(context).pop(); // close the modal picker
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => _GenericInputSheet(
        binding: binding,
        shape: shape,
        onSubmit: (payload, preview) async {
          await _dispatchAndReport(sheetCtx, binding, payload, preview: preview);
        },
      ),
    );
  }

  Future<void> _dispatchAndReport(
    BuildContext context,
    HelmVerbBinding binding,
    Map<String, dynamic> payload, {
    String? preview,
  }) async {
    try {
      final result = await dispatcher.dispatchByName(
        intentType: binding.verb.intentType,
        payload: payload,
      );
      onMinted(result, preview ?? binding.verb.label);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${binding.verb.label} failed: $e')),
        );
      }
    }
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.label, this.activeCartridge});
  final String label;
  final String? activeCartridge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        if (activeCartridge != null) ...[
          const SizedBox(width: 8),
          Text(
            '· $activeCartridge',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyVerbsHint extends StatelessWidget {
  const _EmptyVerbsHint({required this.modal, this.activeCartridge});
  final HelmModal modal;
  final String? activeCartridge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = activeCartridge == null
        ? 'any active cartridge'
        : '$activeCartridge';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      child: Text(
        'No ${modal.label} verbs declared by $scope. Cartridges declare '
        'verbs in their manifest.json ui.verbs[] block.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _SubVerbTile extends StatelessWidget {
  const _SubVerbTile({
    required this.binding,
    required this.hasDispatch,
    required this.onTap,
  });

  final HelmVerbBinding binding;
  final bool hasDispatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _resolveIcon(binding.verb.iconName);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                color: hasDispatch
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          binding.extensionName,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('·',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            )),
                        const SizedBox(width: 6),
                        Text(
                          binding.verb.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: hasDispatch
                                ? null
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (!hasDispatch) ...[
                          const SizedBox(width: 6),
                          Text(
                            '(unwired)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (binding.verb.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          binding.verb.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _resolveIcon(String? name) {
    // Tiny name→IconData map. Unknown names fall back to a generic
    // verb icon. Cartridges using unfamiliar icon names should add
    // them here (one-line entry).
    switch (name) {
      case 'flash_on':
        return Icons.flash_on;
      case 'flag':
        return Icons.flag;
      case 'nights_stay':
        return Icons.nights_stay;
      case 'search':
        return Icons.search;
      case 'build':
        return Icons.build;
      case 'request_quote':
        return Icons.request_quote;
      case 'location_on':
        return Icons.location_on;
      case 'receipt_long':
        return Icons.receipt_long;
      case 'person_search':
        return Icons.person_search;
      default:
        return Icons.play_circle_outline;
    }
  }
}

/// Generic input sheet driven by [HelmInputShape] from the verb's
/// manifest declaration. Replaces the hardcoded _ReleaseSheet from
/// PR-C9-4 — now ANY cartridge verb that declares `inputShape.kind:
/// text|multiline` gets the same sheet, no shell code per verb.
class _GenericInputSheet extends StatefulWidget {
  const _GenericInputSheet({
    required this.binding,
    required this.shape,
    required this.onSubmit,
  });

  final HelmVerbBinding binding;
  final HelmInputShape shape;
  final Future<void> Function(Map<String, dynamic> payload, String preview)
      onSubmit;

  @override
  State<_GenericInputSheet> createState() => _GenericInputSheetState();
}

class _GenericInputSheetState extends State<_GenericInputSheet> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final preview =
          text.length > 80 ? '${text.substring(0, 77)}…' : text;
      await widget.onSubmit({widget.shape.field: text}, preview);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    final theme = Theme.of(context);
    final isMultiline = widget.shape.kind == HelmInputShapeKind.multiline;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: insets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.binding.extensionName} · ${widget.binding.verb.label}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.shape.label.isEmpty
                ? widget.binding.verb.label
                : widget.shape.label,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: isMultiline ? (widget.shape.maxLines ?? 6) : 1,
            minLines: isMultiline ? (widget.shape.minLines ?? 4) : 1,
            enabled: !_sending,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: widget.shape.hint,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(widget.binding.verb.label),
          ),
        ],
      ),
    );
  }
}

```
