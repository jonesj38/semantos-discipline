---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/android/app/build.gradle.kts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.585410+00:00
---

# cartridges/jambox/mobile/android/app/build.gradle.kts

```kts
// D-G.2 — Android application build config for jam-room-mobile.

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.semantos.jam_room_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "io.semantos.jam_room_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Restrict ABI matrix to the three ABIs the FFI cross-compile produces.
        ndk {
            abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a", "x86_64"))
        }
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // BouncyCastle — secp256k1 primitives for BRC-42 key derivation.
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    // AndroidKeyStore-backed encrypted storage.
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    // BiometricPrompt for secure key access.
    implementation("androidx.biometric:biometric:1.2.0-alpha05")
    // Core library desugaring — java.time APIs on minSdk 21.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

```
