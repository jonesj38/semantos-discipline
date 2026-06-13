---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/esp32-hackkit/examples/hello_cell/CMakeLists.txt
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.620234+00:00
---

cmake_minimum_required(VERSION 3.16)

# Point ESP-IDF at our component directory so it picks up the semantos
# component alongside any managed components you install.
set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_LIST_DIR}/../../components")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(hello_cell)
