---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.686423+00:00
---

# archive/apps-navigation_app/pubspec.yaml

```yaml
name: navigation_app
description: Semantos Navigation - Consciousness development with micropayments
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: '>=3.2.0 <4.0.0'
  flutter: '>=3.16.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  # State management
  flutter_riverpod: ^2.4.9

  # Local storage
  hive: ^2.2.3
  hive_flutter: ^1.1.0

  # Notifications & scheduling
  flutter_local_notifications: ^17.0.0
  workmanager: ^0.5.2

  # Screen time (Android UsageStats)
  usage_stats: ^1.3.1
  app_usage: ^4.0.0

  # Node sync (BSV incentives run on the node, app is a client)
  http: ^1.2.0
  web_socket_channel: ^2.4.0

  # Voice & camera
  speech_to_text: ^6.6.0
  image_picker: ^1.0.7

  # UI
  flutter_animate: ^4.5.2
  fl_chart: ^1.2.0

  # Utilities
  uuid: ^4.2.2
  intl: ^0.20.2
  path_provider: ^2.1.2
  json_annotation: ^4.8.1
  crypto: ^3.0.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1
  build_runner: ^2.4.7
  json_serializable: ^6.7.1

flutter:
  uses-material-design: true

```
