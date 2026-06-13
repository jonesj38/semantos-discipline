---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/android/CMakeLists.txt
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.018928+00:00
---

# D-O5m.followup-3 Phase 1 — whisper.cpp Android build wiring.
#
# We DO NOT vendor whisper.cpp source in this repo (~30k lines of
# C++). FetchContent pulls the upstream repo at configure time and
# pins to a specific commit recorded in `WHISPER_CPP_PIN` so a clean
# build is reproducible. Bumping the pin requires an audit pass — the
# C ABI surface covered by `lib/src/bindings.dart` must match.
#
# This file is invoked by the Flutter Android Gradle plugin as part of
# `flutter build apk` / `flutter build appbundle`.

cmake_minimum_required(VERSION 3.18)
project(whisper_cpp LANGUAGES C CXX)

set(WHISPER_CPP_PIN "v1.6.0" CACHE STRING "Pinned upstream whisper.cpp tag/commit")

include(FetchContent)
FetchContent_Declare(
  whisper_upstream
  GIT_REPOSITORY https://github.com/ggerganov/whisper.cpp.git
  GIT_TAG        ${WHISPER_CPP_PIN}
  GIT_SHALLOW    TRUE
)
# Disable upstream tests / examples to keep the build slim.
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)

# Disable host-native arch tuning — we cross-compile for a specific
# ABI via the Android toolchain file.
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)

# AArch64: pre-seed the FP16 format check to empty so whisper.cpp's
# ggml doesn't try to add -mfp16-format=ieee (ARM32-only flag).
set(COMPILER_SUPPORTS_FP16_FORMAT_I3E "" CACHE STRING "" FORCE)

# Android bionic does not have a separate libpthread — pthread symbols
# live in libc.  Pre-declare the cmake results so FindThreads doesn't
# try -lpthread / -lpthreads (which don't exist) and abort configure.
set(CMAKE_HAVE_LIBC_PTHREAD TRUE CACHE BOOL "" FORCE)
set(THREADS_HAVE_PTHREAD_ARG FALSE CACHE BOOL "" FORCE)
set(CMAKE_THREAD_LIBS_INIT "" CACHE STRING "" FORCE)

# OpenMP is unavailable in the Android NDK.
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

# Force upstream whisper + ggml to build as STATIC libraries so they
# don't collide with libwhisper.so produced by our whisper_plugin shim.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(whisper_upstream)

# The shared library Flutter loads via DynamicLibrary.open("libwhisper.so").
# A thin shim (whisper_cpp_shim.cpp) re-exports the ABI we use.
#
# Target is named "whisper_plugin" (not "whisper") to avoid conflicting
# with the upstream "whisper" static-library target.  OUTPUT_NAME keeps
# the on-disk filename as "libwhisper.so".
add_library(whisper_plugin SHARED src/main/cpp/whisper_cpp_shim.cpp)
target_link_libraries(whisper_plugin PRIVATE whisper)
target_include_directories(whisper_plugin PRIVATE
  ${whisper_upstream_SOURCE_DIR}
  ${whisper_upstream_SOURCE_DIR}/include
)
set_target_properties(whisper_plugin PROPERTIES
  OUTPUT_NAME "whisper"
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
)
