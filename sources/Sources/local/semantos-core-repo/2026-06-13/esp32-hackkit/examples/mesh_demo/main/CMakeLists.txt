---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/esp32-hackkit/examples/mesh_demo/main/CMakeLists.txt
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.621871+00:00
---

idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "."
    REQUIRES cell-mesh semantos
    PRIV_REQUIRES esp_timer driver mbedtls esp_driver_usb_serial_jtag
    EMBED_FILES "embed/cell_deck.bin"
)
