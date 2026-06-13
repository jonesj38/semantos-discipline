---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.990719+00:00
---

# platforms/flutter/semantos_core/pubspec.yaml

```yaml
name: semantos_core
description: >
  Interface-only Dart package for the Semantos platform.
  Defines WalletService, CellSigner, IntentGrammar, and the
  ConversationEngine extension point. Implementations live in
  semantos_ffi (offline FFI) and semantos_core itself
  (BrainWalletService HTTP client for online operators).
  Experience packages (oddjobz_experience, jam_experience) import
  only from this package — never from the shell or wallet impl.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.11.0

dependencies:
  http: ^1.2.0
  # SHA-256 for bundle digest computation in Brc42BundleVerifier.
  crypto: ^3.0.0
  # secp256k1 ECDSA verification for Brc42BundleVerifier. Pure Dart so
  # the same code path runs on native + PWA; pointycastle is already
  # a dep in oddjobz-mobile so the resolved artifact is shared across
  # the workspace.
  pointycastle: ^3.9.0
  # WSS transport for BrainVerbDispatchClient (JSON-RPC over
  # /api/v1/wallet). Already transitively present via shelf_web_socket;
  # making it a direct dep so the import surface is explicit.
  web_socket_channel: ^3.0.0

dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0

```
