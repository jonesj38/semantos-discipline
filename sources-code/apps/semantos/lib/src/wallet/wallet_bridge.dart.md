---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/wallet_bridge.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.108707+00:00
---

# apps/semantos/lib/src/wallet/wallet_bridge.dart

```dart
// C11 PR-C11-4e/f — `SemantosWallet` bridge message router.
//
// References:
//   - docs/design/WALLET-RENDERER-CONTRACT.md §3 (bridge protocol)
//   - apps/semantos/lib/src/wallet/wallet_key_service.dart — the
//     shell-singleton key service this bridge delegates to (PR-C11-4f)
//   - apps/semantos/assets/wallet/wallet-page.js (renderer side)
//
// The bridge is the renderer's UX adapter over `WalletKeyService`. It:
//   - Decodes envelopes from the JavaScriptChannel and dispatches them.
//   - Asks the key service for derivations (address.request →
//     `WalletKeyService.deriveReceive`).
//   - Reports identity state pushed from the service.
//   - Returns `error.show` for not-yet-implemented kinds (`tx.request`
//     lands in PR-C11-7).
//
// The bridge does NOT own keys. The service does. Other consumers
// (REPL, intent dispatch, cell anchoring) can call the same service
// directly without crossing the bridge.

import 'dart:async';
import 'dart:convert';

import 'package:semantos_core/semantos_core.dart' show IdentityStore;

import '../plexus/challenge_bundle_store.dart';
import 'derivation_domain.dart';
import 'recipe_store.dart';
import 'wallet_key_service.dart';

/// Wire-format envelope per contract §3.
class WalletEnvelope {
  WalletEnvelope({required this.id, required this.kind, required this.payload});
  final String id;
  final String kind;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'payload': payload,
      };

  static WalletEnvelope? tryDecode(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return null;
      final id = m['id'];
      final kind = m['kind'];
      if (id is! String || kind is! String) return null;
      final payload = m['payload'];
      return WalletEnvelope(
        id: id,
        kind: kind,
        payload: payload is Map<String, dynamic>
            ? payload
            : payload is Map
                ? Map<String, dynamic>.from(payload)
                : <String, dynamic>{},
      );
    } catch (_) {
      return null;
    }
  }
}

/// Router for `SemantosWallet` bridge messages. One instance per
/// wallet sheet; disposed when the sheet closes. Delegates to a
/// shared [WalletKeyService] for everything cryptographic — multiple
/// bridges (across consecutive sheet opens) share the same service
/// and recipe store via the `SemantosPlatform` singleton.
class WalletBridge {
  WalletBridge({
    required WalletKeyService service,
    required IdentityStore identityStore,
  })  : _service = service,
        _challengeStore = ChallengeBundleStore(identityStore);

  final WalletKeyService _service;
  final ChallengeBundleStore _challengeStore;

  bool _disposed = false;
  int _idCounter = 0;

  /// Process an envelope received from the renderer. Returns the
  /// envelopes the sheet should dispatch back. May be empty.
  Future<List<WalletEnvelope>> handle(String raw) async {
    if (_disposed) return const [];
    final env = WalletEnvelope.tryDecode(raw);
    if (env == null) {
      return [
        _envelope('error.show', {
          'message': 'Malformed inbound envelope',
        }),
      ];
    }
    switch (env.kind) {
      case 'ready':
        // Refresh identity from the store on every `ready` — covers
        // the case where the operator generated / imported a cert
        // between sheet opens. Identity goes out first, then the
        // UTXO snapshot so the renderer's panels paint in order.
        await _service.loadIdentity();
        final identityEnv = await _buildIdentitySet();
        if (!_service.hasIdentity) return [identityEnv];
        return [identityEnv, await _buildUtxosList()];
      case 'address.request':
        // Returns [address.reply, utxos.list]: the address reply
        // updates the receive panel; the utxos.list refresh shows
        // the new watching row right away.
        final reply = await _handleAddressRequest(env.payload);
        if (reply.kind != 'address.reply') return [reply];
        return [reply, await _buildUtxosList()];
      case 'tx.request':
        return [
          _envelope('error.show', {
            'message': 'Tx building lands in PR-C11-7 '
                '(UTXO store + tx builder). The bridge accepted your '
                'request but cannot fulfill it yet.',
          }),
        ];
      case 'tx.confirm':
      case 'tx.cancel':
        // No active preview at the bridge layer until tx.request lands.
        return const [];
      case 'derivation.request':
        return [await _handleDerivationRequest(env.payload)];
      default:
        return [
          _envelope('error.show', {
            'message': 'Unknown inbound kind: ${env.kind}',
          }),
        ];
    }
  }

  Future<WalletEnvelope> _buildIdentitySet() async {
    if (!_service.hasIdentity) {
      return _envelope('identity.set', {
        'certIdHex': '',
        'tier0Pub': '',
        'displayName': '',
        'recoverable': false,
      });
    }
    final tier0Pub = _service.tier0Pub!;
    final hasBundle = (await _challengeStore.read()) != null;
    return _envelope('identity.set', {
      'certIdHex': _service.certIdHex!,
      'tier0Pub': _hex(tier0Pub),
      'displayName': '',
      'recoverable': hasBundle,
    });
  }

  Future<WalletEnvelope> _handleAddressRequest(
      Map<String, dynamic> payload) async {
    if (!_service.hasIdentity) {
      return _envelope('error.show', {
        'message':
            'No identity bound — set up the operator identity first.',
      });
    }
    final ctx = (payload['contextLabel'] as String?)?.trim() ?? '';
    if (ctx.isEmpty) {
      return _envelope('error.show', {
        'message': 'address.request requires a non-empty contextLabel',
      });
    }
    final result = await _service.deriveReceive(ctx);
    return _envelope('address.reply', {
      // PR-C11-7a: real BSV P2PKH address (base58check). `pubHex` is
      // kept as a separate field for diagnostics / signing reference.
      'address': result.address,
      'pubHex': result.pubHex,
      'recipeId': result.recipeId,
      'index': result.index,
      'contextLabel': result.contextLabel,
    });
  }

  /// Build a `utxos.list` envelope from the current UTXO store. Per
  /// contract §3.1 the payload is the array directly (not wrapped).
  Future<WalletEnvelope> _buildUtxosList() async {
    final rows = await _service.utxos.readAll();
    final payload = rows
        .map((r) => <String, dynamic>{
              'txid': r.txid,
              'vout': r.vout,
              'value': r.value,
              'scriptHex': r.scriptHex,
              'address': r.address,
              'recipeId': r.recipeId,
              'index': r.index,
              'status': r.status.name,
            })
        .toList();
    return WalletEnvelope(
      id: _newId(),
      kind: 'utxos.list',
      payload: <String, dynamic>{'rows': payload},
    );
  }

  Future<WalletEnvelope> _handleDerivationRequest(
      Map<String, dynamic> payload) async {
    if (!_service.hasIdentity) {
      return _envelope('error.show', {
        'message':
            'No identity bound — set up the operator identity first.',
      });
    }
    final recipeId = (payload['recipeId'] as String?) ?? '';
    final fromIndex = (payload['fromIndex'] as int?) ?? 0;
    final count = (payload['count'] as int?) ?? 1;
    if (recipeId.isEmpty || count <= 0 || fromIndex < 0) {
      return _envelope('error.show', {
        'message':
            'derivation.request requires recipeId, fromIndex>=0, count>0',
      });
    }
    final rules = await _service.recipes.readAll();
    final ruleMatches = rules.where((r) => r.id == recipeId);
    if (ruleMatches.isEmpty) {
      return _envelope('error.show', {
        'message': 'derivation.request: unknown recipeId "$recipeId"',
      });
    }
    final rule = ruleMatches.first;
    final domain = _domainFromRule(rule);
    if (domain == null) {
      return _envelope('error.show', {
        'message':
            'derivation.request: cannot rebuild domain for scope ${rule.scope}',
      });
    }
    final pubs = <Map<String, dynamic>>[];
    for (var i = fromIndex; i < fromIndex + count; i++) {
      pubs.add({
        'index': i,
        'pub': _hex(await _service.deriveAt(domain, i)),
      });
    }
    return _envelope('derivation.reply', {
      'recipeId': recipeId,
      'pubs': pubs,
    });
  }

  /// Rebuild a [DerivationDomain] from a stored [DerivationRule].
  /// Returns null for counterparty-scoped rules (deferred to PR-C11-7).
  DerivationDomain? _domainFromRule(DerivationRule rule) {
    switch (rule.scope) {
      case DerivationScope.tier0:
        return DerivationDomain.tier0;
      case DerivationScope.change:
        return DerivationDomain.change;
      case DerivationScope.context:
        final ctx = rule.contextLabel;
        if (ctx == null) return null;
        return DerivationDomain.spend(ctx);
      case DerivationScope.anchor:
        final typeHash = rule.typeHash;
        if (typeHash == null) return null;
        return DerivationDomain.anchorFromTypeHashHex(typeHash);
      case DerivationScope.counterparty:
        return null; // PR-C11-7
    }
  }

  String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  WalletEnvelope _envelope(String kind, Map<String, dynamic> payload) {
    return WalletEnvelope(
      id: _newId(),
      kind: kind,
      payload: payload,
    );
  }

  String _newId() {
    final ms = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    _idCounter = (_idCounter + 1) & 0xffff;
    return '$ms-${_idCounter.toRadixString(16).padLeft(4, '0')}';
  }

  /// Per-sheet teardown. Does NOT dispose the underlying service —
  /// that's owned by `SemantosPlatform` and lives across sheet opens.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
  }
}

```
