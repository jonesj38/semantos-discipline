---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/esp32-hackkit/examples/piggybank/main/CMakeLists.txt
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.623662+00:00
---

idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "."
    REQUIRES semantos nvs_flash driver
)
