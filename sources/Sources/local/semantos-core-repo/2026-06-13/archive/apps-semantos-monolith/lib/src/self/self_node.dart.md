---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/self/self_node.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.869577+00:00
---

# archive/apps-semantos-monolith/lib/src/self/self_node.dart

```dart
// T7.b — SelfNode: shell tab/node entry for the self cartridge.
//
// Mirrors the helm node pattern (home_node, find_node, do_node) but
// simpler.  Lists the available self-practice flows as cards.  Tapping
// a card pushes into FlowRunner; on completion, the collected fields
// are handed to the caller-supplied minter for ratification (the
// brain's ratification endpoint mints the self.* cell — see T7.a
// `@semantos/self` cell-type validators).
//
// Per Q15 resolution: self ships as a tab inside the existing
// oddjobz-mobile Flutter shell for v0.1.0.  Full rename of
// oddjobz-mobile → "Semantos Shell" is a separate ~87-file PR.
//
// Per Q16 resolution: brain integration is light.  This widget holds
// in-app draft state; only complete-and-mint goes to the brain.
//
// Theme: cartridge.json `theme.colors` (17 colors) should drive the
// surrounding ThemeData when this tab is active.  v0.1.0 uses
// inherited theme; v0.2.0 wraps the body in a Theme override built
// from a SelfTheme service that loads the manifest colors.

import 'package:flutter/material.dart';

import 'flow_def.dart';
import 'flow_runner.dart';
import 'self_theme.dart';
import 'session_view.dart';
// SelfFlowMinter typedef lives in flow_def.dart and is exported from there.

class SelfNode extends StatelessWidget {
  /// All flows to offer in the chooser.  Defaults to the v0.1.0
  /// shipped set (`selfFlows` from flow_def.dart).  Tests can inject
  /// a different list.
  final List<FlowDef> flows;

  /// Caller-supplied minter — invoked when a flow completes.
  final SelfFlowMinter onMint;

  /// Optional callback that fetches the pask sweep result from the brain
  /// before opening the guided session.  When null (or on fetch failure)
  /// the SCAN screen falls back to empty themes ("field is clear").
  final SelfSweepFetcher? sweepFetcher;

  const SelfNode({
    super.key,
    this.flows = selfFlows,
    required this.onMint,
    this.sweepFetcher,
  });

  Future<void> _openSession(BuildContext context) async {
    SelfSweepResult? sweep;
    if (sweepFetcher != null) {
      try {
        sweep = await sweepFetcher!();
      } catch (_) {
        // sweep failure must never block session start
      }
    }
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (ctx) => SelfSessionView(
        onMint: onMint,
        primedThemes: sweep?.primedThemes ?? const [],
        overallElevationEstimate: sweep?.overallElevationEstimate ?? 5.0,
      ),
    ));
  }

  void _openFlow(BuildContext context, FlowDef flow) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) {
        return SelfThemeScope(
          child: FlowRunner(
            flow: flow,
            onSubmit: (completed, fields) async {
            // Pop the FlowRunner back to the chooser first so the
            // user sees the success indicator briefly then returns
            // to a list with the new entry reflected.
            Navigator.of(ctx).pop();
            try {
              await onMint(completed.onComplete.cellTypeName, fields);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Sealed: ${completed.name}'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not seal: $e'),
                    backgroundColor: Colors.red.shade700,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
            onCancel: () => Navigator.of(ctx).pop(),
          ),
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SelfThemeScope(child: _buildBody(context));
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Self'),
      ),
      body: CustomScrollView(
        slivers: [
          // ── Primary: Begin Practice session ──────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _BeginPracticeCard(
                onTap: () => _openSession(context),
              ),
            ),
          ),

          // ── Secondary: Quick-access individual flows ──────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Quick access',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.separated(
              itemCount: flows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final flow = flows[i];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(flow.name, style: theme.textTheme.titleMedium),
                    subtitle: flow.description != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              flow.description!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openFlow(context, flow),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Begin Practice card ──────────────────────────────────────────────────────

/// Primary entry point — tapping begins a guided session driven by the
/// SelfSessionConductor FSM (arriving → grounding → scan → practice → close).
class _BeginPracticeCard extends StatelessWidget {
  final VoidCallback onTap;
  const _BeginPracticeCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              SelfPalette.release,
              SelfPalette.growth,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: SelfPalette.release.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Begin Practice',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Guided session — arrive, scan, release, seal.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

```
