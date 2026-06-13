---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/llama_cpp/android/CMakeLists.txt
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.023028+00:00
---

# D-O5m.followup-3 Phase 2 — llama.cpp Android build wiring.
#
# Reference: platforms/flutter/whisper_cpp/android/CMakeLists.txt
#            (the Phase 1 sibling -- same FetchContent pattern, same
#            shim layout).
#
# We DO NOT vendor llama.cpp source in this repo (~120k lines of
# C++).  FetchContent pulls the upstream repo at configure time and
# pins to a specific commit recorded in `LLAMA_CPP_PIN` so a clean
# build is reproducible.  Bumping the pin requires an audit pass --
# the C ABI surface covered by `lib/src/bindings.dart` (and the
# `llama_cpp_shim.cpp` that re-exports it) must match.
#
# This file is invoked by the Flutter Android Gradle plugin as part of
# `flutter build apk` / `flutter build appbundle`.

cmake_minimum_required(VERSION 3.18)
project(llama_cpp LANGUAGES C CXX)

set(LLAMA_CPP_PIN "b3500" CACHE STRING "Pinned upstream llama.cpp tag/commit")

include(FetchContent)
FetchContent_Declare(
  llama_upstream
  GIT_REPOSITORY https://github.com/ggerganov/llama.cpp.git
  GIT_TAG        ${LLAMA_CPP_PIN}
  GIT_SHALLOW    TRUE
)
# Disable upstream tests / examples / server to keep the build slim.
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)

# AArch64 clang does not accept -mfp16-format=ieee (that flag only
# exists for ARM 32-bit targets; on arm64 IEEE FP16 is the only
# format and the flag is not recognised).  ggml's cmake probes this
# flag via check_cxx_compiler_flag and, if the result is non-empty,
# appends -mfp16-format=ieee to ARCH_FLAGS — causing a compile-time
# "unknown argument" error.
#
# Pre-seeding the cache variable to "" (empty string) tells
# check_cxx_compiler_flag the test already ran and failed, so the
# flag is never appended.  We use CACHE STRING (not BOOL) to preserve
# the empty-string semantics; BOOL would coerce "" to FALSE which is
# also non-empty and would still trigger the append.
set(COMPILER_SUPPORTS_FP16_FORMAT_I3E "" CACHE STRING "" FORCE)

# Disable host-native arch tuning — we cross-compile for a specific
# ABI via the Android toolchain file and don't want the build system
# second-guessing the target CPU.
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)

# Android bionic does not implement pthread_cancel, so CMake's
# FindThreads / CheckLibraryExists probe that calls pthread_cancel
# fails with "call to undeclared function" under strict C99/C++17.
# Pre-declaring the result as TRUE tells CMake that pthreads are
# available (they are — just without pthread_cancel) and skips the
# broken probe entirely.
set(CMAKE_HAVE_LIBC_PTHREAD TRUE CACHE BOOL "" FORCE)
# THREADS_HAVE_PTHREAD_ARG must also be set so find_package(Threads)
# doesn't re-run the broken detection path.
set(THREADS_HAVE_PTHREAD_ARG FALSE CACHE BOOL "" FORCE)
set(CMAKE_THREAD_LIBS_INIT "" CACHE STRING "" FORCE)

# OpenMP is not available in the Android NDK and its detection path
# exercises the same pthread_cancel probe; disable it outright.
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENMP OFF CACHE BOOL "" FORCE)

# Force upstream llama + ggml to build as STATIC libraries.  If we let
# them build as SHARED they would also emit libllama.so, which would
# collide with the libllama.so produced by our llama_plugin shim target
# (OUTPUT_NAME = "llama").  With STATIC upstreams Flutter loads exactly
# one libllama.so — the shim — and the upstream symbols are inlined into
# it at link time.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(llama_upstream)

# The shared library Flutter loads via DynamicLibrary.open("libllama.so").
# A thin shim (llama_cpp_shim.cpp) re-exports the ABI we use; this is
# where any future custom wrappers (e.g. llama_shim_complete with
# grammar-constrained sampling) live.
#
# We name the CMake target "llama_plugin" to avoid conflicting with the
# "llama" static-library target that llama.cpp's own CMakeLists.txt
# defines.  OUTPUT_NAME ensures the on-disk file is still "libllama.so"
# so DynamicLibrary.open("libllama.so") in Dart resolves correctly.
add_library(llama_plugin SHARED
  src/main/cpp/llama_cpp_shim.cpp
  # grammar-parser.cpp is part of llama.cpp's common/ directory.
  # It is NOT compiled into the upstream 'llama' static library, so
  # we add it directly here so llama_cpp_shim.cpp can call
  # grammar_parser::parse() for BNF-constrained sampling.
  ${llama_upstream_SOURCE_DIR}/common/grammar-parser.cpp
)
target_link_libraries(llama_plugin PRIVATE llama log)
target_include_directories(llama_plugin PRIVATE
  ${llama_upstream_SOURCE_DIR}
  ${llama_upstream_SOURCE_DIR}/include
  ${llama_upstream_SOURCE_DIR}/common
)
set_target_properties(llama_plugin PROPERTIES
  OUTPUT_NAME "llama"
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
)
