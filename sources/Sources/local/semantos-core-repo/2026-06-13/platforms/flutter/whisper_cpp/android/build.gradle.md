---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/whisper_cpp/android/build.gradle
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.019210+00:00
---

# platforms/flutter/whisper_cpp/android/build.gradle

```gradle
// D-O5m.followup-3 Phase 1 — whisper.cpp Android Gradle module.
//
// Mirrors the semantos_ffi sibling plugin's layout. The native build is
// driven by `android/CMakeLists.txt` which uses FetchContent to pull
// whisper.cpp at the recorded commit. No native sources are vendored
// in this repo.

group 'io.semantos.whisper_cpp'
version '0.1.0'

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.1.0'
    }
}

apply plugin: 'com.android.library'

android {
    namespace 'io.semantos.whisper_cpp'
    compileSdk 34
    defaultConfig {
        minSdk 23
        externalNativeBuild {
            cmake {
                arguments "-DANDROID_STL=c++_shared"
                cppFlags "-std=c++17"
            }
        }
    }
    externalNativeBuild {
        cmake {
            path "CMakeLists.txt"
        }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}

```
