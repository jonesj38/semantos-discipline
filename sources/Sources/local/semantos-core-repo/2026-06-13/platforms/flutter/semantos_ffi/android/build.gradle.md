---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/android/build.gradle
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.994752+00:00
---

# platforms/flutter/semantos_ffi/android/build.gradle

```gradle
group = 'io.semantos.ffi'
version = '1.0.0'

buildscript {
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.1.0")
    }
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply plugin: 'com.android.library'

android {
    namespace = "io.semantos.ffi"
    compileSdk = 34
    ndkVersion = "25.1.8937393"

    defaultConfig {
        minSdk = 21

        // D-OPS.mobile-smoke-test (2026-05-02): match the host app's
        // ABI matrix.  src/ffi/build.zig builds with single_threaded =
        // true on Android targets so all three ABIs link cleanly into
        // the SHARED .so wrapper this CMakeLists produces.  Drop x86
        // (32-bit) — Flutter doesn't ship a libflutter.so for it.
        ndk {
            // RM-122 — arm64-v8a only (mirrors the app module). The
            // armeabi-v7a Zig cross-compile of libsemantos.a currently
            // fails; x86_64 is emulator-only. Keeps the plugin's
            // externalNativeBuild to the one ABI that links cleanly.
            abiFilters "arm64-v8a"
        }
    }

    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
        }
    }
}

```
