---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/android/stub.c
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.994206+00:00
---

# platforms/flutter/semantos_ffi/android/stub.c

```c
/*
 * D-OPS.mobile-smoke-test (2026-05-02): empty TU that gives CMake a
 * source file for the SHARED library target in CMakeLists.txt.
 *
 * The actual Semantos FFI symbols (semantos_init, semantos_version,
 * semantos_execute_script, …) come from the static archive
 * libsemantos.a, whole-archive-linked into this .so by the
 * target_link_options() block.
 *
 * Adding a real translation unit (vs. a CMake "INTERFACE" or empty
 * library) is required because Android's CMake/ninja toolchain
 * refuses to build a SHARED library with zero source files.
 */
static const char *_semantos_ffi_stub_marker =
    "semantos_ffi:android-shared-stub";

const char *semantos_ffi_stub_marker(void) {
    return _semantos_ffi_stub_marker;
}

```
