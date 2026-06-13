---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/test-oddjobz-parity.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.321067+00:00
---

# scripts/test-oddjobz-parity.sh

```sh
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf '\n== OddJobz package parity tests ==\n'
(
  cd "$ROOT/cartridges/oddjobz/experience"
  flutter test
)

printf '\n== Betterment package smoke tests ==\n'
(
  cd "$ROOT/packages/betterment_experience"
  flutter test
)

printf '\n== Semantos shell parity tests ==\n'
(
  cd "$ROOT/apps/semantos"
  flutter test -r compact \
    test/shell/cartridge_picker_navigation_test.dart \
    test/shell/cartridge_parity_wiring_test.dart \
    test/shell/helm_home_attention_scope_test.dart \
    test/shell/surfacing_mode_policy_test.dart \
    test/shell/no_cert_banner_test.dart
)

printf '\nOddJobz/Semantos parity test checklist passed.\n'

```
