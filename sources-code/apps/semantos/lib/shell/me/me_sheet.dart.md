---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/me/me_sheet.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.120779+00:00
---

# apps/semantos/lib/shell/me/me_sheet.dart

```dart
// C11 PR-C11-1 — the "me" surface scaffold.
//
// Reference: docs/design/HELM-ME-SURFACE.md §3 (UX) + §4 (architecture seam).
// Track B per Todd's 2026-05-29 architecture call.
//
// First slice: the affordance + bottom sheet with four rows. Only the
// Identity row is live — it fetches /api/v1/info from the paired
// brain and renders cert + pubkey + hat + cartridges. The other three
// rows (Wallet, Recovery, Plexus RaaS) render as "not yet wired"
// placeholders so the user sees the full surface shape before each
// flow lands in its own PR (C11-2 through C11-5).
//
// Architectural note: the cert ALREADY exists on the brain after
// pairing (per D4 in the design doc). This widget does NOT mint a
// new cert — it surfaces what the brain reports. Per D4, the brain
// is the canonical identity store; the helm displays + acts through
// it.

import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:flutter/material.dart';
import 'package:semantos_core/semantos_core.dart'
    show NodeResolver, IdentityStore, HelmSurfacingMode;

import '../../src/brain/brain_http_client.dart';
import '../../src/plexus/challenge_bundle_store.dart';
import '../cartridge_hat_state.dart';
import '../semantos_platform.dart';
import '../shell_cartridge_host.dart'
    show kByokAnthropicKeySlot, kByokModelSlot;
import 'contacts_sheet.dart';
import 'recovery_envelope_flow.dart';
import 'wallet_launch.dart';

/// Show the "me" bottom sheet. The me-panel reads the brain's identity via
/// GET /api/v1/info — HTTP-only today (no `info` RPC method yet), so it builds
/// a short-lived [BrainHttpClient] from the saved connection rather than the
/// dispatcher's minter (M1.7b moved mints onto the WSS RPC client). Reads
/// ChallengeBundle state via the SemantosPlatform-provided IdentityStore.
Future<void> showMeSheet(BuildContext context) async {
  final platform = SemantosPlatform.of(context);
  // Capture the cartridge-switch state + the switchable cartridges from the
  // helm context (which is below CartridgeHatScope) BEFORE the modal opens.
  final cartridgeState = CartridgeHatScope.of(context);
  final cartridgeEntries =
      CartridgeRegistry.instance.entries
          .where((e) => e.role == 'experience')
          .where((e) {
            final mode =
                platform.grammarRegistry.byId(e.id)?.surfacingMode ??
                HelmSurfacingMode.defaultMode;
            return mode != HelmSurfacingMode.passive;
          })
          .toList()
        ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
  final url = await platform.identityStore.read(NodeResolver.brainUrlKey);
  final token = await platform.identityStore.read(NodeResolver.brainTokenKey);
  if (url == null || url.isEmpty || token == null || token.isEmpty) return;
  if (!context.mounted) return;
  final brain = BrainHttpClient(baseUrl: url, bearerToken: token);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => _MeSheet(
      brain: brain,
      bundleStore: ChallengeBundleStore(platform.identityStore),
      identityStore: platform.identityStore,
      cartridgeState: cartridgeState,
      cartridgeEntries: cartridgeEntries,
    ),
  );
}

class _MeSheet extends StatefulWidget {
  const _MeSheet({
    required this.brain,
    required this.bundleStore,
    required this.identityStore,
    required this.cartridgeState,
    required this.cartridgeEntries,
  });

  final BrainHttpClient brain;
  final ChallengeBundleStore bundleStore;
  final IdentityStore identityStore;
  final CartridgeHatState cartridgeState;
  final List<CartridgeEntry> cartridgeEntries;

  @override
  State<_MeSheet> createState() => _MeSheetState();
}

class _MeSheetState extends State<_MeSheet> {
  late Future<BrainInfo> _infoFuture;

  @override
  void initState() {
    super.initState();
    _infoFuture = widget.brain.getInfo();
  }

  void _reload() {
    setState(() {
      _infoFuture = widget.brain.getInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: Column(
            children: [
              // Grab handle
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
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Me',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh),
                      onPressed: _reload,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // Active-cartridge switcher — the shell is a dumb loader;
                    // this picks which cartridge's helm surface renders. Tap a
                    // cartridge → set active → close ME → helm re-renders it.
                    _CartridgeSection(
                      state: widget.cartridgeState,
                      entries: widget.cartridgeEntries,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _IdentitySection(infoFuture: _infoFuture),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    const _BrainManagementRow(),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    // C11 PR-C11-4a: Wallet row launches the bundled
                    // wallet-headers wallet.html in a native webview.
                    // 4b adds the Dart ↔ JS bridge that surfaces the
                    // BIP39 seed handle back to RecoveryRow.
                    _WalletRow(),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    // AI / BYOK — operator's own Anthropic key + model for OCR
                    // (and future LLM calls). Stored in the secure IdentityStore;
                    // sent per-request, never persisted on the brain.
                    _ByokSection(identityStore: widget.identityStore),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    // Contacts row — invite → bilateral edge → BRC-69
                    // backup flow (contacts-PKI). Tap opens the Contacts
                    // sheet over ContactsService.
                    const _ContactsRow(),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    // C11 PR-C11-2 + PR-C11-3: Recovery row reads
                    // ChallengeBundle storage on display. Generate
                    // button stays gated until the wallet seed lands
                    // (PR-C11-4).
                    FutureBuilder<BrainInfo>(
                      future: _infoFuture,
                      builder: (context, snap) => RecoveryRow(
                        brainInfo: snap.data,
                        bundleStore: widget.bundleStore,
                        hasSeed: false,
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _PlaceholderSection(
                      title: 'Plexus RaaS',
                      icon: Icons.cloud_outlined,
                      bodyLine: 'not enrolled (optional)',
                      placeholder: 'lands in PR-C11-5 (opt-in per D3)',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Identity row — live. Pulls from /api/v1/info.
class _IdentitySection extends StatelessWidget {
  const _IdentitySection({required this.infoFuture});

  final Future<BrainInfo> infoFuture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fingerprint, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                'Identity',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<BrainInfo>(
            future: infoFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Reading brain identity…',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Brain unreachable: ${snapshot.error}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                );
              }
              final info = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IdentityRow(
                    label: 'cert id',
                    value: _truncateHex(info.pinCertId),
                  ),
                  _IdentityRow(
                    label: 'pubkey',
                    value: _truncateHex(info.pinPubkey),
                  ),
                  if (!info.hat.isEmpty) ...[
                    _IdentityRow(
                      label: 'hat',
                      value: info.hat.name.isNotEmpty
                          ? info.hat.name
                          : info.hat.id,
                    ),
                  ],
                  _IdentityRow(label: 'brain', value: info.serverVersion),
                  _IdentityRow(
                    label: 'cartridges',
                    value: info.cartridges.isEmpty
                        ? 'none'
                        : info.cartridges.map((c) => c.id).join(', '),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// `a1b2c3d4…ef5678` — first 8 + last 4 hex chars. Returns the
  /// full string for short identifiers.
  static String _truncateHex(String s) {
    if (s.length <= 16) return s.isEmpty ? '—' : s;
    return '${s.substring(0, 8)}…${s.substring(s.length - 4)}';
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brain management row — operator/configuration surface entry point.
///
/// Per Todd 2026-06-12: the field PWA is primarily for using cartridges.
/// Cartridge policy/catalog management is more ergonomic from the brain/helm
/// side and must not surface as ordinary DO/TALK/FIND field verbs.
class _BrainManagementRow extends StatelessWidget {
  const _BrainManagementRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/me/brain-management'),
          builder: (_) => const _BrainManagementScreen(),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Brain management',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                'Manage cartridge policy, pricing/catalog configuration, '
                'and brain-side operator settings. Not field DO/TALK/FIND.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrainManagementScreen extends StatelessWidget {
  const _BrainManagementScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Brain management')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Cartridge management lives on the brain side',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The PWA stays optimised for using cartridges in the field. '
            'Policy, pricing catalog, and cartridge configuration are '
            'brain/helm management tasks exposed here from Me, rather than '
            'as ordinary DO/TALK/FIND actions.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _ManagementOptionCard(
            icon: Icons.extension_outlined,
            title: 'Cartridges',
            body:
                'Install, inspect, enable, disable, and configure cartridges.',
            status: 'brain management surface pending',
          ),
          _ManagementOptionCard(
            icon: Icons.price_change_outlined,
            title: 'Pricing & catalog policy',
            body:
                'Operator-owned service catalog and pricing policy for '
                'visit-based service businesses.',
            status: 'not surfaced in field verbs',
          ),
          _ManagementOptionCard(
            icon: Icons.rule_folder_outlined,
            title: 'Policy & permissions',
            body:
                'Capabilities, hats, workflow policy, and cartridge-level '
                'management controls.',
            status: 'brain-side controls pending',
          ),
        ],
      ),
    );
  }
}

class _ManagementOptionCard extends StatelessWidget {
  const _ManagementOptionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String body;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Text(
                    status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the "not yet wired" sections — Wallet, Recovery, Plexus RaaS.
/// Renders honest signal so the user sees the full surface shape
/// before each flow lands in its dedicated PR.
class _PlaceholderSection extends StatelessWidget {
  const _PlaceholderSection({
    required this.title,
    required this.icon,
    required this.bodyLine,
    required this.placeholder,
  });

  final String title;
  final IconData icon;
  final String bodyLine;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.outline),
              const SizedBox(width: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bodyLine,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  placeholder,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// C11 PR-C11-4 — Wallet row. Tap → `showWalletSheet()` opens a
/// full-screen sheet hosting the stripped renderer (PR-C11-4d) over
/// the loopback HTTP origin (PR-C11-4a) with the `SemantosWallet`
/// bridge (PR-C11-4e) talking to the shell-singleton key service
/// (PR-C11-4f).
///
/// Status info beneath the title reflects whether a cert_body is
/// bound. The "Generate dev cert" affordance writes a fresh random
/// cert_body to `me.cert_body.v1` so the wallet can be tested
/// end-to-end before Plexus RaaS / pairing flows land a real
/// writer. Dev-only — the button label flags that.
class _WalletRow extends StatefulWidget {
  const _WalletRow();

  @override
  State<_WalletRow> createState() => _WalletRowState();
}

class _WalletRowState extends State<_WalletRow> {
  bool _generatingCert = false;
  String? _lastBoundCertIdHex;

  Future<void> _generateDevCert() async {
    final keyService = SemantosPlatform.of(context).walletKeyService;
    setState(() => _generatingCert = true);
    try {
      final certIdHex = await keyService.writeDevRandomCertBody();
      if (!mounted) return;
      setState(() => _lastBoundCertIdHex = certIdHex);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dev cert generated · $certIdHex'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Generate dev cert failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    } finally {
      if (mounted) setState(() => _generatingCert = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyService = SemantosPlatform.of(context).walletKeyService;
    final bound = _lastBoundCertIdHex ?? keyService.certIdHex;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                "Wallet",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bound != null
                      ? "Identity bound · $bound"
                      : "No identity yet — generate a dev cert below.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: bound != null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Tier-0 vault + recipe store live in Dart "
                  "(see WALLET-RENDERER-CONTRACT.md §5)",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_full),
                      label: const Text("Open wallet"),
                      onPressed: () => showWalletSheet(context),
                    ),
                    OutlinedButton.icon(
                      icon: _generatingCert
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_fix_high),
                      label: const Text("Generate dev cert"),
                      onPressed: _generatingCert ? null : _generateDevCert,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Contacts row — entry point to the invite → bilateral edge → BRC-69
/// backup flow. Tap opens the Contacts sheet (`showContactsSheet`),
/// which drives `ContactsService` for invite generation, acceptance,
/// and the edge list.
class _ContactsRow extends StatelessWidget {
  const _ContactsRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => showContactsSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.people_alt_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Contacts',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                'Invite peers, accept invites, and view your edges '
                '(BRC-42 bilateral · BRC-69 backup).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// AI / BYOK section — operator sets their own Anthropic key + model for OCR
/// (and future LLM calls). The key is a secret: stored in the secure
/// IdentityStore, obscured in the field, sent per-request, never persisted on
/// the brain. Empty key → the brain falls back to its own env key.
class _ByokSection extends StatefulWidget {
  const _ByokSection({required this.identityStore});

  final IdentityStore identityStore;

  @override
  State<_ByokSection> createState() => _ByokSectionState();
}

class _ByokSectionState extends State<_ByokSection> {
  /// Curated model menu; the operator can also type a custom id.
  static const List<String> _models = [
    'claude-sonnet-4-6',
    'claude-haiku-4-5',
    'claude-opus-4-1',
  ];

  final _keyController = TextEditingController();
  String? _model;
  bool _obscure = true;
  bool _loading = true;
  bool _hasStoredKey = false;
  String? _savedNote;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = await widget.identityStore.read(kByokAnthropicKeySlot);
    final model = await widget.identityStore.read(kByokModelSlot);
    if (!mounted) return;
    setState(() {
      _hasStoredKey = key != null && key.isNotEmpty;
      _keyController.text = key ?? '';
      _model = (model != null && model.isNotEmpty) ? model : _models.first;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      await widget.identityStore.delete(kByokAnthropicKeySlot);
    } else {
      await widget.identityStore.write(kByokAnthropicKeySlot, key);
    }
    await widget.identityStore.write(kByokModelSlot, _model ?? _models.first);
    if (!mounted) return;
    setState(() {
      _hasStoredKey = key.isNotEmpty;
      _savedNote = key.isEmpty ? 'Saved · using brain key' : 'Saved';
    });
  }

  Future<void> _clearKey() async {
    await widget.identityStore.delete(kByokAnthropicKeySlot);
    if (!mounted) return;
    setState(() {
      _keyController.clear();
      _hasStoredKey = false;
      _savedNote = 'Key cleared · using brain key';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                'AI · bring your own key',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(left: 36, top: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _keyController,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Anthropic API key',
                      hintText: _hasStoredKey ? '•••• stored' : 'sk-ant-…',
                      helperText:
                          'Stored on this device only; sent per request, never saved on the brain. Empty = use the brain’s key.',
                      helperMaxLines: 3,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        tooltip: _obscure ? 'Show' : 'Hide',
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _models.contains(_model)
                        ? _model
                        : _models.first,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final m in _models)
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: (v) => setState(() => _model = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save'),
                      ),
                      const SizedBox(width: 8),
                      if (_hasStoredKey)
                        TextButton(
                          onPressed: _clearKey,
                          child: const Text('Clear key'),
                        ),
                      const Spacer(),
                      if (_savedNote != null)
                        Text(
                          _savedNote!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Active-cartridge switcher. The shell is a dumb loader: exactly one
/// cartridge is "active" at a time and its helm surface renders. Tapping a
/// cartridge sets [CartridgeHatState.activeCartridge] (the same hook the
/// AppBar apps-icon picker uses) and closes the ME sheet so the helm rebuilds
/// onto the chosen cartridge.
class _CartridgeSection extends StatelessWidget {
  const _CartridgeSection({required this.state, required this.entries});

  final CartridgeHatState state;
  final List<CartridgeEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.apps, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Active cartridge',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 36, top: 4),
                  child: Text(
                    'No switchable cartridges loaded.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final e in entries)
                  _CartridgeChoiceTile(
                    entry: e,
                    isActive: e.id == state.activeCartridge,
                    onTap: () {
                      state.activeCartridge = e.id;
                      Navigator.of(context).pop();
                    },
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _CartridgeChoiceTile extends StatelessWidget {
  const _CartridgeChoiceTile({
    required this.entry,
    required this.isActive,
    required this.onTap,
  });

  final CartridgeEntry entry;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 36, right: 0),
      dense: true,
      leading: Icon(
        entry.icon ?? Icons.extension,
        color: isActive
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        entry.title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          color: isActive ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        entry.id,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isActive
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : const Icon(Icons.radio_button_unchecked),
      onTap: isActive ? null : onTap,
    );
  }
}

```
