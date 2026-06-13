---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/settings_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.897827+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/settings_screen.dart

```dart
// D-O5m — Settings screen.
//
// Shows the operator a summary of the persisted child cert + brain
// endpoints, surfaces an "Unpair this device" action that wipes the
// persisted record + transitions back to the pairing screen.
//
// D-O5m.followup-9 Phase C / Sovereign-push D.3 — also surfaces a
// "Notifications" card that shows the current registration state
// (registered / not registered, platform, registered_at) and exposes
// Re-register / Unregister / Open-Settings actions.  Sovereign-push
// D.3 adds a "Push backend" sub-section underneath where the
// Android operator can pick UnifiedPush (sovereign) vs Firebase
// Cloud Messaging.  iOS renders a read-only "Apple Push (APNs)"
// row with a tooltip explaining the sandbox limitation.  When push
// isn't wired in this build (no Firebase config / boot path failed),
// the card renders an info banner explaining how to enable push
// via the runbook.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../identity/child_cert_store.dart';
import '../identity/secure_signing_key.dart';
import '../mesh/mesh_transport.dart';
import '../push/push_platform.dart';
import '../push/push_registration_service.dart';

class SettingsScreen extends StatefulWidget {
  final ChildCertStore store;
  final ChildCertRecord record;
  final VoidCallback onUnpaired;
  final PushRegistrationService? pushService;

  /// D-O5m.followup-6 Phase 2 — initial mesh transport state.  When
  /// null the Mesh sync card renders a "Not configured" hint.
  final MeshTransportState? meshState;

  /// D-O5m.followup-6 Phase 2 — fired when the operator taps
  /// "Refresh transport" — re-runs the factory selection.  When null
  /// the button is hidden.  The future returns the new state which
  /// the screen swaps in.
  final Future<MeshTransportState> Function()? onRefreshMeshTransport;

  /// D-O5m.followup-2 — fired when the operator taps "Migrate now"
  /// in the Secure key card.  Generates a fresh key inside the
  /// platform secure store, atomically rewrites the persisted
  /// record with `secure_key_handle=<new>` + `device_priv_hex=''`,
  /// and returns the migrated record so the screen can refresh.
  /// When null the migration card renders a "Migration not
  /// available in this build" info banner.
  final Future<ChildCertRecord> Function()? onMigrateToSecureKey;

  /// Sovereign-push D.3 — fired when the operator taps "Apply" on
  /// the push-backend picker.  Implementation lives in main.dart
  /// (which constructs the appropriate adapters), persists the new
  /// preference, swaps the service's adapters, and re-runs
  /// registration.  When null the picker renders read-only.
  final Future<PushRegistrationResult> Function(PushBackendPreference pref)?
      onApplyBackendPreference;

  /// Sovereign-push D.3 — list of currently-installed UnifiedPush
  /// distributors (e.g. ["org.unifiedpush.distributor.ntfy",
  /// "org.unifiedpush.distributor.nextpush"]).  Empty when no UP
  /// distributor is installed.  Wired by main.dart through a thin
  /// shim around UnifiedPushAdapter.getDistributors().  When null
  /// the picker hides the distributor list (UP not built in).
  final Future<List<String>> Function()? onListUnifiedPushDistributors;

  /// Sovereign-push D.3 — persist the operator's chosen distributor
  /// inside the UP plugin.  Called after they pick from the
  /// distributor list.  When null the "Choose distributor" UI is
  /// hidden.
  final Future<void> Function(String distributorId)?
      onChooseUnifiedPushDistributor;

  const SettingsScreen({
    super.key,
    required this.store,
    required this.record,
    required this.onUnpaired,
    this.pushService,
    this.meshState,
    this.onRefreshMeshTransport,
    this.onMigrateToSecureKey,
    this.onApplyBackendPreference,
    this.onListUnifiedPushDistributors,
    this.onChooseUnifiedPushDistributor,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PushTokenRegistration _registration = PushTokenRegistration.empty;
  PushRegistrationResult? _lastResult;
  bool _busy = false;
  MeshTransportState? _meshState;
  bool _meshRefreshing = false;
  /// Sovereign-push D.3 — operator-staged backend preference (the
  /// dropdown selection BEFORE they hit Apply).  Initialised from
  /// the persisted preference on screen mount.
  PushBackendPreference _stagedBackend = PushBackendPreference.unifiedpush;
  /// True when the staged value differs from what's persisted —
  /// disables the Apply button until the operator changes their mind.
  PushBackendPreference _persistedBackend = PushBackendPreference.unifiedpush;
  /// List of installed UP distributors — refreshed on mount + after
  /// each Apply.  Empty when no distributor is installed (in which
  /// case the picker shows a "Install a distributor" hint).
  List<String> _upDistributors = const [];
  /// Did the most recent registration silently fall back from
  /// UnifiedPush → FCM?  Read from the service after each apply.
  bool _backendFellBack = false;

  /// D-O5m.followup-2 — local mirror of `widget.record` so the
  /// "Migrate now" button can refresh the screen state immediately
  /// after a successful migration without bouncing back through
  /// the parent widget tree.
  late ChildCertRecord _record;

  /// D-O5m.followup-2 — surfaces migration outcome (success, error)
  /// on the Secure key card.  Cleared when the operator dismisses
  /// the info banner via re-render.
  String? _migrationError;
  bool _migrating = false;

  @override
  void initState() {
    super.initState();
    _refreshRegistration();
    _refreshBackendPreference();
    _refreshUpDistributors();
    _meshState = widget.meshState;
    _record = widget.record;
  }

  Future<void> _refreshBackendPreference() async {
    final svc = widget.pushService;
    if (svc == null) return;
    final pref = await svc.readBackendPreference();
    if (!mounted) return;
    setState(() {
      _stagedBackend = pref;
      _persistedBackend = pref;
      _backendFellBack = svc.lastUsedFallback;
    });
  }

  Future<void> _refreshUpDistributors() async {
    final cb = widget.onListUnifiedPushDistributors;
    if (cb == null) return;
    try {
      final list = await cb();
      if (!mounted) return;
      setState(() => _upDistributors = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _upDistributors = const []);
    }
  }

  Future<void> _applyBackendPreference() async {
    final cb = widget.onApplyBackendPreference;
    if (cb == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await cb(_stagedBackend);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _persistedBackend = _stagedBackend;
        _lastResult = result;
        _backendFellBack = widget.pushService?.lastUsedFallback ?? false;
      });
      await _refreshRegistration();
      await _refreshUpDistributors();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastResult = PushRegistrationFailed(reason: 'apply failed: $e');
      });
    }
  }

  Future<void> _chooseUpDistributor(String distributor) async {
    final cb = widget.onChooseUnifiedPushDistributor;
    if (cb == null || _busy) return;
    setState(() => _busy = true);
    try {
      await cb(distributor);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refreshUpDistributors();
    }
  }

  Future<void> _refreshMeshTransport() async {
    final cb = widget.onRefreshMeshTransport;
    if (cb == null || _meshRefreshing) return;
    setState(() => _meshRefreshing = true);
    try {
      final newState = await cb();
      if (!mounted) return;
      setState(() {
        _meshState = newState;
        _meshRefreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _meshRefreshing = false);
    }
  }

  Future<void> _refreshRegistration() async {
    final svc = widget.pushService;
    if (svc == null) return;
    final reg = await svc.readPersisted();
    if (!mounted) return;
    setState(() => _registration = reg);
  }

  Future<void> _confirmUnpair(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair this device?'),
        content: const Text(
            'The child cert + brain endpoints will be removed from this '
            'device. To use the helm again you\'ll need to re-pair via QR.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Clear push registration alongside the cert.  Best-effort —
      // the brain DELETE call may fail (offline), but the local
      // record is wiped either way.
      await widget.pushService?.unregister();
      await widget.store.clear();
      widget.onUnpaired();
    }
  }

  Future<void> _reregister() async {
    final svc = widget.pushService;
    if (svc == null || _busy) return;
    setState(() => _busy = true);
    final result = await svc.registerOnPair();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastResult = result;
    });
    await _refreshRegistration();
  }

  Future<void> _unregister() async {
    final svc = widget.pushService;
    if (svc == null || _busy) return;
    setState(() => _busy = true);
    await svc.unregister();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastResult = null;
    });
    await _refreshRegistration();
  }

  Future<void> _openOsSettings() async {
    await openAppSettings();
  }

  /// D-O5m.followup-2 — drive the Settings → "Migrate now" flow.
  /// Calls the supplied callback (which routes through
  /// PairingService.migrateToSecureKey()), refreshes the local
  /// record on success, and surfaces typed errors via the
  /// `_migrationError` banner.
  Future<void> _migrateToSecureKey() async {
    final cb = widget.onMigrateToSecureKey;
    if (cb == null || _migrating) return;
    setState(() {
      _migrating = true;
      _migrationError = null;
    });
    try {
      final migrated = await cb();
      if (!mounted) return;
      setState(() {
        _record = migrated;
        _migrating = false;
        _migrationError = null;
      });
    } on SecureSigningKeyUnsupported catch (e) {
      if (!mounted) return;
      setState(() {
        _migrating = false;
        _migrationError =
            'This build does not support secure-key migration: ${e.message}. '
            'See docs/operator-runbooks/secure-signing-key-migration.md.';
      });
    } on SecureSigningKeyException catch (e) {
      if (!mounted) return;
      setState(() {
        _migrating = false;
        _migrationError = 'Migration failed: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _migrating = false;
        _migrationError = 'Migration failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Paired device',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _kv('Label', _record.label),
                _kv('Context tag', _record.contextTag.toString()),
                _kv('Child pubkey', _record.childPubHex),
                _kv('Operator cert', _record.operatorCertId),
                _kv('Brain (HTTPS)', _record.brainPairEndpoint),
                _kv('Brain (WSS)', _record.brainWssEndpoint),
                _kv('Capabilities', _record.capabilities.join(', ')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSecureKeyCard(context),
        const SizedBox(height: 16),
        _buildMeshSyncCard(context),
        const SizedBox(height: 16),
        _buildNotificationsCard(context),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _confirmUnpair(context),
          icon: const Icon(Icons.link_off),
          label: const Text('Unpair this device'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'D-O5m MVP. Voice, attention feed, full mesh sync are tracked '
          'as D-O5m.followup-1..N.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildNotificationsCard(BuildContext context) {
    final svc = widget.pushService;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notifications',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (svc == null)
              const Text(
                'Push notifications are not enabled in this build. See '
                'docs/operator-runbooks/push-architecture.md to '
                'configure Firebase + APNs + UnifiedPush at deploy time.',
                style: TextStyle(fontSize: 12),
              )
            else ...[
              _kv('Status',
                  _registration.isRegistered ? 'Registered' : 'Not registered'),
              if (_registration.isRegistered) ...[
                _kv('Backend', _registration.platform.toJson()),
                _kv('Registered at', _registration.registeredAt),
              ],
              if (_lastResult != null) ...[
                const SizedBox(height: 8),
                _resultBanner(_lastResult!),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!_registration.isRegistered)
                    FilledButton.icon(
                      onPressed: _busy ? null : _reregister,
                      icon: const Icon(Icons.notifications_active),
                      label: const Text('Enable notifications'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _reregister,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Re-register'),
                    ),
                  if (_registration.isRegistered)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _unregister,
                      icon: const Icon(Icons.notifications_off),
                      label: const Text('Unregister'),
                    ),
                  if (_lastResult is PushPermissionDenied)
                    FilledButton.icon(
                      onPressed: _busy ? null : _openOsSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Open Settings'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _buildBackendPicker(context),
            ],
          ],
        ),
      ),
    );
  }

  /// Sovereign-push D.3 — backend picker.  iOS renders read-only
  /// "Apple Push (APNs)"; Android renders a {UnifiedPush, FCM}
  /// dropdown plus the installed-distributor list when UP is
  /// chosen.  When the host didn't wire `onApplyBackendPreference`
  /// the picker is read-only (the build doesn't have UP support
  /// at all).
  Widget _buildBackendPicker(BuildContext context) {
    if (Platform.isIOS || Platform.isMacOS) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Push backend',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Tooltip(
            message:
                'iOS only permits Apple Push Notification service for '
                'wake notifications; the Apple sandbox bans alternative '
                'push transports (including UnifiedPush). Android '
                'operators can choose between UnifiedPush and Firebase.',
            child: Row(
              children: const [
                Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                SizedBox(width: 6),
                Text('Apple Push (APNs)',
                    style: TextStyle(fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      );
    }

    // Android.
    final apply = widget.onApplyBackendPreference;
    final dirty = _stagedBackend != _persistedBackend;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Push backend',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        if (apply == null)
          const Text(
            'This build does not include the UnifiedPush adapter; '
            'push wakes use Firebase Cloud Messaging.',
            style: TextStyle(fontSize: 12),
          )
        else ...[
          DropdownButton<PushBackendPreference>(
            value: _stagedBackend,
            isExpanded: true,
            onChanged: _busy
                ? null
                : (v) {
                    if (v != null) setState(() => _stagedBackend = v);
                  },
            items: const [
              DropdownMenuItem(
                value: PushBackendPreference.unifiedpush,
                child: Text('UnifiedPush (sovereign)'),
              ),
              DropdownMenuItem(
                value: PushBackendPreference.fcm,
                child: Text('Firebase Cloud Messaging'),
              ),
            ],
          ),
          if (_stagedBackend == PushBackendPreference.unifiedpush) ...[
            const SizedBox(height: 8),
            _buildUpDistributorList(context),
          ],
          if (_backendFellBack &&
              _persistedBackend == PushBackendPreference.unifiedpush) ...[
            const SizedBox(height: 8),
            _resultInfoBanner(
              'No UnifiedPush distributor installed — fell back to '
              'Firebase Cloud Messaging. Install ntfy, NextPush, or '
              'another distributor (https://unifiedpush.org/users/'
              'distributors/) to switch fully off Google services.',
              Colors.orange,
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (dirty && !_busy) ? _applyBackendPreference : null,
            icon: const Icon(Icons.check),
            label: const Text('Apply'),
          ),
        ],
      ],
    );
  }

  Widget _buildUpDistributorList(BuildContext context) {
    final cb = widget.onChooseUnifiedPushDistributor;
    if (_upDistributors.isEmpty) {
      return _resultInfoBanner(
        'No UnifiedPush distributor installed on this device. Pick one '
        'from https://unifiedpush.org/users/distributors/ — for example '
        'ntfy (open-source, public or self-hosted), NextPush '
        '(Nextcloud), or Conversations (XMPP). Install the app, then '
        'tap Apply to register through it.',
        Colors.blueGrey,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Installed distributors:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        for (final d in _upDistributors)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(d,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12)),
                ),
                if (cb != null)
                  TextButton(
                    onPressed: _busy ? null : () => _chooseUpDistributor(d),
                    child: const Text('Use'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _resultInfoBanner(String msg, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(msg, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Widget _resultBanner(PushRegistrationResult result) {
    final (msg, color) = switch (result) {
      PushRegistered(:final platform) => (
          'Registered for $platform push.',
          Colors.green
        ),
      PushPermissionDenied(:final reason) => (
          'Permission denied: $reason. Open Settings to enable '
          'notifications and try again.',
          Colors.orange,
        ),
      PushUnsupported(:final reason) => (
          'Push not supported on this device: $reason',
          Colors.grey,
        ),
      PushRegistrationFailed(:final reason, :final statusCode) => (
          'Registration failed (${statusCode ?? "?"}): $reason',
          Colors.red,
        ),
    };
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(msg, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  /// D-O5m.followup-2 — Secure-signing-key card.  Renders one of:
  ///   - "Migration not available in this build" (no callback wired)
  ///   - "Your signing key uses legacy storage" + Migrate button
  ///     (legacy raw-priv record, callback wired)
  ///   - "Secure key active" green-banner (record already migrated)
  Widget _buildSecureKeyCard(BuildContext context) {
    final cb = widget.onMigrateToSecureKey;
    final usesSecureKey = _record.usesSecureKeyHandle;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signing key',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (cb == null)
              const Text(
                'Secure-key migration is not available in this build. The '
                'signing priv is stored encrypted at rest in '
                'flutter_secure_storage (iOS Keychain / Android Keystore-'
                'derived encryption); a future build will add Keychain/'
                'Keystore-handle wrapping with biometric gating. See '
                'docs/operator-runbooks/secure-signing-key-migration.md.',
                style: TextStyle(fontSize: 12),
              )
            else if (usesSecureKey) ...[
              _kv('Status',
                  'Secure key active (biometric-gated, Keychain/Keystore-'
                      'backed)'),
              _kv('Key handle', _record.secureKeyHandle),
              const SizedBox(height: 8),
              _migrationStatusBanner(
                'Your signing key is stored in the platform secure store '
                'and gated by biometric authentication on every cell '
                'signature.',
                Colors.green,
              ),
            ] else ...[
              const Text(
                'Your signing key is using legacy storage (raw priv hex '
                'in flutter_secure_storage). Migrate to the secure-key '
                'path for biometric-gated signing + at-rest encryption.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _migrating ? null : _migrateToSecureKey,
                icon: _migrating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_outline),
                label: const Text('Migrate now'),
              ),
              if (_migrationError != null) ...[
                const SizedBox(height: 8),
                _migrationStatusBanner(_migrationError!, Colors.red),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _migrationStatusBanner(String msg, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(msg, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  /// D-O5m.followup-6 Phase 2 — Mesh sync status card.
  Widget _buildMeshSyncCard(BuildContext context) {
    final state = _meshState;
    final cb = widget.onRefreshMeshTransport;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mesh sync',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (state == null)
              const Text(
                'Mesh transport is not configured. The helm uses the '
                'HTTP-REPL fallback path for all writes. To enable mesh '
                'sync, set [mesh] shard_proxy_endpoint in the tenant '
                'manifest and re-pair this device.',
                style: TextStyle(fontSize: 12),
              )
            else ...[
              _kv('Status', _meshStatusLabel(state)),
              if (state.shardProxyEndpoint != null &&
                  state.shardProxyEndpoint!.isNotEmpty)
                _kv('Mesh endpoint', state.shardProxyEndpoint!),
              _kv('Last attempted',
                  _formatUnixSeconds(state.lastAttemptedUnix)),
            ],
            if (cb != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _meshRefreshing ? null : _refreshMeshTransport,
                icon: _meshRefreshing
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: const Text('Refresh transport'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _meshStatusLabel(MeshTransportState s) {
    if (s.meshActive) return 'Mesh active (${s.label})';
    return 'HTTP fallback (mesh unavailable)';
  }

  String _formatUnixSeconds(int unix) {
    if (unix <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    return dt.toIso8601String();
  }

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(key,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
            Text(value, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
      );
}

```
