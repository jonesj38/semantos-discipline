---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/android/CMakeLists.txt
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.994484+00:00
---

cmake_minimum_required(VERSION 3.16)
project(semantos_ffi)

# scripts/build-android-libs.sh stages libsemantos.a per ABI here:
#   build/android/${ANDROID_ABI}/libsemantos.a
#
# Layout:
#   1. Import the static lib produced by the Zig cross-compile.
#   2. Wrap it in a thin SHARED stub (`libsemantos.so`) that
#      whole-archive-links the static so all of its symbols are
#      preserved + re-exported.  Dart FFI's `DynamicLibrary.open(
#      'libsemantos.so')` (see platforms/flutter/semantos_ffi/lib/
#      src/bindings.dart) finds the bundled .so at runtime via the
#      Android JNI library loader.
#
# The static lib + shared shim split keeps the Zig kernel (and its
# whole-program optimisations) self-contained while Android's APK
# packaging only ever ships the shim .so.
add_library(semantos_static STATIC IMPORTED)
set_property(TARGET semantos_static PROPERTY IMPORTED_LOCATION
             "${CMAKE_CURRENT_SOURCE_DIR}/../build/android/${ANDROID_ABI}/libsemantos.a")

# D-OPS.mobile-smoke-test (2026-05-02): a small empty .c is the
# canonical "give me a SHARED target that exports the static's
# symbols" recipe.  CMake refuses to build a SHARED library with
# zero source files, so we ship a one-line stub.  --whole-archive
# pulls every symbol out of the static archive into the .so so
# Dart's dlsym() lookups against `libsemantos.so` succeed.
add_library(semantos SHARED stub.c)

target_include_directories(semantos PUBLIC
             "${CMAKE_CURRENT_SOURCE_DIR}/../include")

target_link_options(semantos PRIVATE
    "-Wl,--whole-archive"
    "$<TARGET_FILE:semantos_static>"
    "-Wl,--no-whole-archive")

# Re-introduce the dependency edge that target_link_options strips —
# without this CMake doesn't know `libsemantos.so` depends on the
# static archive's bytes and won't relink when it changes.
add_dependencies(semantos semantos_static)
