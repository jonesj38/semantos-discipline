---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.050665+00:00
---

# apps/semantos/pubspec.yaml

```yaml
name: semantos
description: >
  The unified Semantos shell app. Boots operator identity once, then
  routes to experience packages (oddjobz_experience, jam_experience).
  Owns the conversation engine (whisper_cpp STT + llama_cpp extraction
  + GrammarRegistry), wallet lifecycle (FFI or brain HTTP), and the
  device pairing handshake.

  See docs/design/PLATFORM-WALLET-ARCHITECTURE.md §5 for the full
  architecture and §8 for the delivery order (P4 = this scaffold).
publish_to: none
version: 0.1.0+1

environment:
  sdk: ^3.11.0
  flutter: ^3.41.0

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

  # secp256k1 + SHA-256 for the identity primitive (cell signing,
  # BRC-42 child derivation, BCA computation). Pure Dart — no native
  # FFI, no web build complications. Forklifted from the monolith
  # under C1 (identity substrate). See lib/src/identity/.
  pointycastle: ^3.9.1

  # HTTP client for the voice primitive's brain-upload path
  # (POST /api/v1/voice-extract per Q1 decision). Also used by other
  # forklifted brain-HTTP consumers (repl, theme, etc.) in later C1
  # ticks. See lib/src/voice/.
  dio: ^5.7.0

  # Semantos platform interfaces (WalletService, CellSigner, IntentGrammar).
  semantos_core:
    path: ../../platforms/flutter/semantos_core
  cartridge_sdk:
    path: ../../packages/cartridge_sdk

  # Offline FFI wallet + cell-engine bridge.
  semantos_ffi:
    path: ../../platforms/flutter/semantos_ffi

  # Experience packages — the cartridges the canonical PWA loads.
  # Per C8 archival decision (canonicalization-brief.md §3), jam_experience
  # and tessera_experience are archived dead-end cartridges and NOT loaded
  # by the canonical shell. The two live cartridges on the slice path are:
  #   - oddjobz_experience    (trades — Todd's primary cartridge)
  #   - betterment_experience (personal practice + Paskian narrative for
  #                            self-development — the C7 V1 golden slice's
  #                            cartridge. Renamed from self_experience
  #                            2026-05-29 to free "self" for the shell
  #                            identity primitive.)
  oddjobz_experience:
    path: ../../cartridges/oddjobz/experience
  betterment_experience:
    path: ../../packages/betterment_experience

  # STT + LLM inference for the ConversationEngine.
  whisper_cpp:
    path: ../../platforms/flutter/whisper_cpp
  llama_cpp:
    path: ../../platforms/flutter/llama_cpp
  # Whisper model cache directory (getApplicationSupportDirectory).
  path_provider: ^2.1.4

  # HTTP for BrainWalletService + device pairing.
  http: ^1.2.0

  # Identity + bearer-token storage.
  #   - Native targets: semantos_shell_native_identity wraps
  #     flutter_secure_storage (iOS Keychain / Android Keystore /
  #     macOS Keychain / Linux libsecret / Windows DPAPI). The sub-
  #     package isolates the flutter_secure_storage dep so Flutter's
  #     web plugin registrant doesn't pull `flutter_secure_storage_web`
  #     (which imports `dart:html`) into the wasm build graph.
  #   - PWA target: idb_shim backs IdentityStore with IndexedDB. Selected
  #     via conditional import on `dart.library.html`.
  semantos_shell_native_identity:
    path: ../../platforms/flutter/semantos_shell_native_identity
  idb_shim: ^2.6.0

  # WSS wallet endpoint (BRC-100 JSON-RPC).
  web_socket_channel: ^3.0.0

  # C11 PR-C11-4a — native webview for the helm "me" surface's Wallet
  # row (per docs/design/HELM-ME-SURFACE.md D2 + PLEXUS-ALIGNMENT §10.C).
  # Hosts the bundled wallet-headers wallet.html in-app so the operator
  # never leaves the canonical shell to mint a wallet. webview_flutter
  # is the official Flutter team package; provides JavaScriptChannel
  # for the Dart ↔ wallet.html bridge that PR-C11-4b adds.
  webview_flutter: ^4.10.0

# record 5.x pulls record_platform_interface 1.6.0 (added startStream), but the
# endorsed record_linux 0.7.2 never implemented it — and `flutter build` compiles
# every federated platform impl's Dart into the kernel, breaking the Android build
# on the Linux impl. record_android 1.5.2 only needs ^1.5.0, so pinning the
# interface to 1.5.0 keeps Android working and lets record_linux 0.7.2 compile.
dependency_overrides:
  record_platform_interface: 1.5.0
  # record 5.0.5 caps record_linux <1.0.0 → pub grabs the ancient 0.7.2 which
  # predates startStream and breaks the kernel build. record_linux 1.3.1 needs
  # platform_interface ^1.5.0 and implements the modern interface; override past
  # the cap so the Linux impl compiles cleanly.
  record_linux: 1.3.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true

  # C11 PR-C11-4a — bundled wallet-headers artifacts. Sourced from
  # cartridges/wallet-headers/brain/dist/ (built via
  # `cd cartridges/wallet-headers/brain && bun run build`). Re-bundle
  # the dist artifacts under apps/semantos/assets/wallet/ when the
  # wallet-headers code changes; webview loads from the asset bundle.
  assets:
    - assets/wallet/

```
