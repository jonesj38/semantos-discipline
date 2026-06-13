---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/esp32-hackkit/components/semantos/idf_component.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.596232+00:00
---

# esp32-hackkit/components/semantos/idf_component.yml

```yml
description: "Semantos cell-engine embedded WASM kernel for ESP32 — hack-kit distribution"
version: "0.0.1-hackkit"
url: "https://github.com/toddprice/semantos-core"
issues: "https://github.com/toddprice/semantos-core/issues"
maintainers:
  - "Todd Price <todd.price.aus@gmail.com>"
license: "UNLICENSED"
tags:
  - wasm
  - cell-engine
  - semantos
  - experimental

dependencies:
  idf: ">=5.0"
  # WAMR is the active runtime on the Espressif component registry. The
  # `espressif/wasm3` and `espressif/wamr` names referenced in older
  # versions of this manifest were not registered or have been retired
  # (as of 2026-05). The semantos component itself doesn't pin a runtime —
  # the app picks one in its own idf_component.yml and enables the matching
  # Kconfig switch (CONFIG_SEMANTOS_RUNTIME_WAMR=y).
  espressif/wasm-micro-runtime:
    version: "^2.4.0"
    require: "no"

```
