---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/job_list_row.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.890767+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/job_list_row.dart

```dart
// D-DOG.1.0c Phase 3 F.1 — graph-aware Job row.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
//            sub-deliverable F.1.c.
//
// Single Job row, shared between [JobListScreen] (the standalone
// route — kept around for navigation deep-links) and `_JobsTab`
// inside [FindNode] (the live operator-facing surface in the
// 5-tab Find node).  Pulled into its own file so widget tests can
// drive a single row through pump() without spinning up the whole
// screen state, and so the two callsites stay in lock-step.
//
// Layout (v2 rich row):
//
//   ┌─ ListTile ──────────────────────────────────────────────────┐
//   │ ┃ 47 Hygieta St, Doonside  [key #177]           [lane-chip] │ ← title
//   │ ┃ ● Sarah Liu (tenant)                                      │ ← line 2 (score dot + customer)
//   │ ┃ 💬 Hey can you come tomo…  3m                             │ ← line 3 (msg snippet, optional)
//   │ ┃ Due 24 Mar                       [icon]    [state-chip]   │ ← line 4
//   └─────────────────────────────────────────────────────────────┘
//
// Tier 2P Phase E.1 additions (all optional, backward-compat):
//   • Lane chip  — top-trailing area, near photos icon.
//   • Score dot  — 8dp circle next to job title.
//   • Last-message snippet — compact line below customer line.
// When no attention params are supplied the row renders exactly
// as before E.1 — no new vertical space, no new widgets.
//
// v1 fallback: title shows the customer name (existing v1 surface
// the operator already recognises), line 2 shows "—" (legacy job
// placeholder), line 3 shows "—" with no camera icon, state chip
// stays.  No v1 row is ever filtered out — the operator's existing
// 72 first-dogfood cells stay visible until Phase 5 migrates them.

import 'package:flutter/material.dart';

import '../repl/attention_service.dart';
import '../repl/jobs_repository.dart';
import '../repl/oddjobz_query_client.dart';
import 'stage_trail.dart';

/// Render a single Job row.  Used by both JobListScreen (route) and
/// FindNode._JobsTab (the live tab inside the Find pivot).
class JobListRow extends StatelessWidget {
  /// The job to render.  v1 vs v2 is detected via [Job.isV2].
  final Job job;

  /// Pre-resolved primary customer (looked up by the parent screen's
  /// bulk-fetch map).  Null in three cases:
  ///   1. v1 row (no customerRefs);
  ///   2. v2 row whose primary ref doesn't resolve in the map (the
  ///      bulk fetch missed it, e.g. WSS not connected);
  ///   3. v2 row with no primary entry in customerRefs[] yet.
  /// In every null case the renderer falls back to "—" or the v1
  /// customerName string per Phase 3 F.1.e backward-compat rules.
  final OddjobzCustomer? primaryCustomer;

  /// Tap handler — usually pushes [JobDetailScreen].
  final VoidCallback onTap;

  /// D-DOG.1.0c Phase 3 F.4 — tap handler for the photos camera icon.
  /// When non-null AND [Job.hasPhotos] is true, the icon becomes an
  /// independent tap target that pushes [AttachmentScreen] for the
  /// row's job cellId.  Falls through to [onTap] (the row tap) when
  /// null so existing call-sites that haven't wired the photos route
  /// keep their previous behaviour.  See `attachment_screen.dart` for
  /// the screen the parent wires up.
  final VoidCallback? onPhotosTap;

  /// D-DOG.1.0c Phase 3 F.3 — optional tap handler for the customer-
  /// name cell on line 2.  When non-null AND the row has a primary
  /// customerRef, the cell becomes its own InkWell that pushes the
  /// customer-pivot screen.  When null (legacy callsites that haven't
  /// wired the pivot, or v1 rows where the cell isn't a navigable
  /// customer ref), the cell stays a plain Text and the row's
  /// [onTap] is the only target — preserves the existing F.1
  /// behaviour for callsites that don't care about the pivot.
  final ValueChanged<String>? onCustomerTap;

  /// D-DOG.1.0c Phase 3 F.2 — optional tap handler for the property-
  /// address cell on line 1.  When non-null AND the row has a v2
  /// `propertyAddress`, the address Text becomes its own InkWell that
  /// pushes the site-pivot screen.  When null, the address stays a
  /// plain Text and the row's [onTap] handler is the only target —
  /// preserves the existing F.1 behaviour for callsites that don't
  /// care about the pivot (e.g. SiteScreen itself, where you're
  /// already AT the site so re-pivoting would be a no-op).
  ///
  /// The nested-InkWell pattern matches [onCustomerTap]: the address-
  /// cell InkWell absorbs the tap before it bubbles to the row's
  /// outer InkWell, so [onTap] does NOT fire when the address-cell
  /// version is tapped.
  final VoidCallback? onAddressTap;

  /// When true, render the [StageTrail] inline beneath the row.
  /// FindNode's _JobsTab opts in (the operator scans the full FSM
  /// position at a glance); the standalone JobListScreen route
  /// opts out (it's a denser scrolling list, the chip suffices).
  final bool showStageTrail;

  // ── Tier 2P Phase E.1 — optional attention augments ─────────────────

  /// Attention signal for this job.  When non-null, renders a coloured
  /// 8dp score dot next to the job title:
  ///   red   ≥ 0.8
  ///   amber ≥ 0.6
  ///   gray  < 0.6
  /// When null, no dot is rendered — existing rows are unchanged.
  final OddjobzAttentionSignal? attentionSignal;

  /// Most recent inbound message patch for this job's primary session.
  /// When non-null, renders a compact snippet line below the customer
  /// line: "💬 [first 60 chars]…  [relative time]" in bodySmall.
  /// When null, the line is omitted — no extra vertical space.
  final OddjobzMessagePatch? lastMessagePatch;

  /// Most recent dispatch decision whose primaryTarget is this job.
  /// When non-null, renders a small lane [Chip] in the top-trailing
  /// area (alongside the photos icon area):
  ///   direct    → blue
  ///   squad     → orange
  ///   broadcast → red
  ///   agent     → green
  ///   self      → gray
  /// When null, the chip is omitted.
  final OddjobzDispatchDecision? primaryDispatch;

  const JobListRow({
    super.key,
    required this.job,
    required this.primaryCustomer,
    required this.onTap,
    this.onPhotosTap,
    this.onCustomerTap,
    this.onAddressTap,
    this.showStageTrail = false,
    this.attentionSignal,
    this.lastMessagePatch,
    this.primaryDispatch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _titleRow(theme),
            const SizedBox(height: 4),
            _customerLine(theme),
            if (lastMessagePatch != null) ...[
              const SizedBox(height: 2),
              _messageSnippetLine(theme, lastMessagePatch!),
            ],
            const SizedBox(height: 2),
            _dueAndPhotosLine(theme),
            if (showStageTrail) ...[
              const SizedBox(height: 6),
              StageTrail(currentState: job.state, compact: true),
            ],
          ],
        ),
      ),
    );
  }

  /// Title line — property address (v2 with resolved site) OR
  /// customer name (v1 fallback) OR "—" (v2 with unresolved site).
  /// Trailing state chip lives on this line so the row tops are
  /// visually aligned regardless of v1 vs v2.
  ///
  /// Tier 2P Phase E.1 additions:
  ///   • Score dot (8dp coloured circle) prepended when [attentionSignal]
  ///     is non-null.
  ///   • Lane chip appended (trailing, before state chip) when
  ///     [primaryDispatch] is non-null.
  Widget _titleRow(ThemeData theme) {
    final Widget headlineText;
    if (job.isV2 && job.propertyAddress != null) {
      // Address cell — wrapped in InkWell when [onAddressTap] is wired
      // (F.2 site-pivot path).  When null, plain Text — the row's
      // outer InkWell handles taps via [onTap] (F.1 default behaviour).
      // The nested InkWell absorbs the tap so [onTap] does not also
      // fire — matches the [onCustomerTap] pattern below.
      final addressText = Text(
        job.propertyAddress!,
        style: theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      );
      final Widget addressWidget = onAddressTap != null
          ? InkWell(
              onTap: onAddressTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: addressText,
              ),
            )
          : addressText;
      headlineText = Row(
        children: [
          Expanded(child: addressWidget),
          if (job.propertyKey != null) ...[
            const SizedBox(width: 8),
            _KeyBadge(label: job.propertyKey!),
          ],
        ],
      );
    } else if (job.isV2 && job.propertyAddress == null) {
      // v2 row with un-enriched site — see the JobListRow doc for
      // why this can happen.  "—" is what the helm SPA shows in the
      // same scenario (file-disjoint parallel work in E.1).
      headlineText = Text(
        '—',
        style: theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      );
    } else {
      // v1: existing surface — customer name is the title.
      headlineText = Text(
        job.customerName.isEmpty ? '(no customer)' : job.customerName,
        style: theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      );
    }

    // Tier 2P Phase E.1 — score dot prefixed to the headline.
    final Widget headline;
    final signal = attentionSignal;
    if (signal != null) {
      headline = Row(
        children: [
          _ScoreDot(score: signal.score),
          const SizedBox(width: 6),
          Expanded(child: headlineText),
        ],
      );
    } else {
      headline = headlineText;
    }

    return Row(
      children: [
        Expanded(child: headline),
        // Tier 2P Phase E.1 — lane chip trailing (before state + legacy).
        if (primaryDispatch != null) ...[
          const SizedBox(width: 6),
          _LaneChip(lane: primaryDispatch!.lane),
        ],
        if (job.legacyUnsigned) ...[
          const SizedBox(width: 6),
          // D-DOG.1.0c Phase 5 G.2 — operator-visible signal that this
          // row is a pre-Layer-1 v1 cell that the `legacy migrate-to-
          // graph` verb couldn't promote.  Same Chip primitive as the
          // state chip so the row's chip-row stays visually balanced;
          // dashed border + warning tone keeps it scannable.
          const _LegacyPill(),
        ],
        const SizedBox(width: 8),
        Chip(
          label: Text(
            job.state.replaceAll('_', ' '),
            style: const TextStyle(fontSize: 11),
          ),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ],
    );
  }

  /// Tier 2P Phase E.1 — compact message snippet line.
  /// "💬 [first 60 chars]…  [relative time]" in bodySmall.
  Widget _messageSnippetLine(ThemeData theme, OddjobzMessagePatch patch) {
    final text = patch.text;
    final snippet = text.length > 60 ? '${text.substring(0, 60)}…' : text;
    final rel = _relativeTime(patch.timestamp);
    return Text(
      '💬 $snippet  $rel',
      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _customerLine(ThemeData theme) {
    final ref = job.primaryCustomerRef;
    if (ref == null) {
      return Text(
        '—',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      );
    }
    final c = primaryCustomer;
    final name =
        (c?.displayName.isNotEmpty == true) ? c!.displayName : ref.cellId;
    final label = '$name (${ref.role})';
    // D-DOG.1.0c Phase 3 F.3 — when the parent has wired a customer-
    // pivot tap handler, surface the cell as a tappable affordance
    // (link-style underline + InkWell hit area).  When not wired the
    // cell stays a plain Text so existing widget tests that don't
    // know about the pivot still match.  Stop the row's own onTap
    // from firing on the cell tap by tagging this with its own
    // GestureDetector / InkWell — the parent InkWell still wraps
    // the row, but Flutter's hit-testing gives the inner widget
    // priority.
    final onCustomerTap = this.onCustomerTap;
    if (onCustomerTap == null) {
      return Text(
        label,
        style: theme.textTheme.bodyMedium,
        overflow: TextOverflow.ellipsis,
      );
    }
    return InkWell(
      // semantics-friendly tap handler — VoiceOver/TalkBack reads it
      // as a button.
      onTap: () => onCustomerTap(ref.cellId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _dueAndPhotosLine(ThemeData theme) {
    final due = job.dueDate;
    final scheduled = job.scheduledAt.isNotEmpty ? job.scheduledAt : null;
    final hasPhotos = job.hasPhotos == true;
    final photoCount = job.photoCount;

    // Build the label: prefer dueDate; fall back to scheduledAt; else "—".
    final String dateLabel;
    final bool hasDate;
    if (due != null) {
      dateLabel = 'Due ${formatDueDate(due)}';
      hasDate = true;
    } else if (scheduled != null) {
      dateLabel = '📅 $scheduled';
      hasDate = true;
    } else {
      dateLabel = '—';
      hasDate = false;
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            dateLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: hasDate ? null : theme.hintColor,
            ),
          ),
        ),
        if (hasPhotos) ...[
          // D-DOG.1.0c Phase 3 F.4 — when [onPhotosTap] is wired,
          // the camera icon + count pair become a tappable target
          // routing to [AttachmentScreen] for the job.  When null
          // (older call-sites, widget tests pre-F.4) the icon stays
          // visual-only and a tap on the row falls through to the
          // standard [onTap] handler.  Wrapping in InkWell keeps the
          // ripple feedback consistent with the rest of the row.
          InkWell(
            onTap: onPhotosTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.photo_camera,
                    size: 16,
                    color: theme.colorScheme.primary,
                    // semanticLabel lets the widget test find the icon
                    // by its meaningful tag rather than by IconData
                    // equality (which is brittle if a future Material
                    // upgrade renames the codepoint).
                    semanticLabel: 'has photos',
                  ),
                  if (photoCount != null && photoCount > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$photoCount',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Tier 2P Phase E.1 — attention augment widgets ───────────────────

/// 8dp coloured dot indicating attention score.
///   red   ≥ 0.8
///   amber ≥ 0.6
///   gray  < 0.6
/// Rendered as a small Semantics-labelled container so screen readers
/// can surface the score level.
class _ScoreDot extends StatelessWidget {
  final double score;
  const _ScoreDot({required this.score});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (score >= 0.8) {
      color = Colors.red.shade600;
      label = 'high attention';
    } else if (score >= 0.6) {
      color = Colors.amber.shade700;
      label = 'medium attention';
    } else {
      color = Colors.grey.shade400;
      label = 'low attention';
    }
    return Semantics(
      label: label,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Small lane chip showing the dispatch routing lane with a colour
/// hint so the operator can scan at a glance.
///   direct    → blue   (Colors.blue.shade100 bg, blue.shade900 text)
///   squad     → orange
///   broadcast → red
///   agent     → green
///   self      → gray
class _LaneChip extends StatelessWidget {
  final OddjobzDispatchLane lane;
  const _LaneChip({required this.lane});

  @override
  Widget build(BuildContext context) {
    final (label, bgColor, fgColor) = _laneStyle(lane);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fgColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static (String, Color, Color) _laneStyle(OddjobzDispatchLane lane) {
    switch (lane) {
      case OddjobzDispatchLane.direct:
        return ('direct', Colors.blue.shade100, Colors.blue.shade900);
      case OddjobzDispatchLane.squad:
        return ('squad', Colors.orange.shade100, Colors.orange.shade900);
      case OddjobzDispatchLane.broadcast:
        return ('broadcast', Colors.red.shade100, Colors.red.shade900);
      case OddjobzDispatchLane.agent:
        return ('agent', Colors.green.shade100, Colors.green.shade900);
      case OddjobzDispatchLane.self:
        return ('self', Colors.grey.shade200, Colors.grey.shade800);
    }
  }
}

/// Relative timestamp helper for the message snippet.
/// Returns a short human-readable string like "3m", "2h", "yesterday".
String _relativeTime(int timestampMs) {
  final ts = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  final diff = DateTime.now().difference(ts);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays == 1) return 'yesterday';
  return '${diff.inDays}d';
}

// ── Existing private widgets (unchanged) ─────────────────────────────

/// Small inline badge for the property-key suffix (e.g. "key #177").
/// Lives next to the property-address title when set.  Visually
/// distinct from the state chip so the operator can scan a row
/// without confusing the two.
class _KeyBadge extends StatelessWidget {
  final String label;
  const _KeyBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// D-DOG.1.0c Phase 5 G.2 — small "legacy" pill rendered next to the
/// state chip when [Job.legacyUnsigned] is true.  Visually distinct
/// from the state chip + key badge so the operator can pick out
/// pre-Layer-1 v1 rows at a glance.  Dashed outline + warning tone
/// matches the helm SPA's `.legacy-pill` style.
class _LegacyPill extends StatelessWidget {
  const _LegacyPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message:
          'Pre-Layer-1 cell — not yet promoted to a signed graph row',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: theme.colorScheme.outline,
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Text(
          'legacy',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.error,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// Format a YYYY-MM-DD due date for the row.  "24 Mar" form when
/// it's in the current calendar year; "24 Mar 2027" when it crosses
/// over.  All input is UTC (the parser stamps T00:00:00Z); we render
/// in UTC too so the day-of-month doesn't drift across timezones.
/// Public so the unit tests can pin the format without spinning up
/// a full widget tree.
String formatDueDate(DateTime due) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final u = due.toUtc();
  final now = DateTime.now().toUtc();
  if (u.year == now.year) {
    return '${u.day} ${months[u.month - 1]}';
  }
  return '${u.day} ${months[u.month - 1]} ${u.year}';
}

```
