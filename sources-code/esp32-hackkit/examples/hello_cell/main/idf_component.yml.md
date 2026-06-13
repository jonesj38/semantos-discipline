---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/esp32-hackkit/examples/hello_cell/main/idf_component.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.622407+00:00
---

# esp32-hackkit/examples/hello_cell/main/idf_component.yml

```yml
dependencies:
  # Runtime backend. wasm3 used to live at `espressif/wasm3` but is no
  # longer in the Espressif component registry (as of 2026-05). WAMR is
  # the current option: published as `espressif/wasm-micro-runtime`.
  # Switch CONFIG_SEMANTOS_RUNTIME_WAMR=y in sdkconfig to match.
  espressif/wasm-micro-runtime: "^2.4.0"
  idf: ">=5.0"

```
