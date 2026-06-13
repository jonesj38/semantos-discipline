---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/android/app/build.gradle.kts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.856548+00:00
---

# archive/apps-semantos-monolith/android/app/build.gradle.kts

```kts
plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // D-O5m.followup-9 Phase C — apply the google-services plugin
    // contributed by android/build.gradle.kts.  This parses
    // app/google-services.json and emits the resource entries that
    // firebase_core consumes at runtime.
    id("com.google.gms.google-services")
}

android {
    namespace = "info.oddjobtodd.oddjobz_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // D-OPS.mobile-smoke-test (2026-05-02): `flutter_local_notifications`
        // (pulled in via D-O5m.followup-9 Phase C) requires Java 8+ APIs
        // (java.time.*) on minSdk 21, which Android Gradle Plugin only
        // provides via core library desugaring.  Without this flag the
        // build fails at :app:checkDebugAarMetadata.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "info.oddjobtodd.oddjobz_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // D-OPS.mobile-smoke-test (2026-05-02): restrict ABI matrix
        // to the three ABIs the FFI cross-compile produces:
        //   * arm64-v8a    — every modern Android phone (2018+).
        //   * armeabi-v7a  — legacy phones (Android < 8 era).
        //   * x86_64       — Android Studio emulator.
        // src/ffi/build.zig builds the FFI under `single_threaded =
        // true` for Android so all three ABIs link cleanly.  Drop x86
        // (32-bit) — it's not a target Flutter or any current Android
        // device runs.
        ndk {
            // RM-122 — arm64-v8a only. All modern target devices (incl.
            // the operator's Galaxy S20 FE) are arm64; armeabi-v7a
            // (32-bit ARM) currently fails the semantos_ffi Zig cross-
            // compile and x86_64 is emulator-only. Restricting here
            // gates externalNativeBuild so the APK builds + stays lean
            // for sideload. Re-add ABIs once the 32-bit ffi build is
            // fixed (separate from RM-121/RM-122).
            abiFilters.addAll(listOf("arm64-v8a"))
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // D-OPS.mobile-smoke-test (2026-05-02): bouncycastle (D-O5m.followup-2)
    // and jspecify (transitive via firebase) both ship a
    // META-INF/versions/9/OSGI-INF/MANIFEST.MF resource with identical
    // path but different bytes.  Both are pure metadata that the
    // Android runtime never consults, so the safe resolution is "pick
    // first" via packagingOptions.resources.pickFirsts.
    packaging {
        resources {
            pickFirsts.add("META-INF/versions/9/OSGI-INF/MANIFEST.MF")
        }
    }
}

flutter {
    source = "../.."
}

// Sovereign-push D.3 — the `unifiedpush_android` plugin pulls in
// `webpush_encryption` which depends on `com.google.crypto.tink:tink`
// (the JVM/desktop variant).  `firebase_messaging` already pulls in
// `com.google.crypto.tink:tink-android` (the Android variant — same
// classes, native-Android-friendly packaging).  Both shipping side-
// by-side trips :app:checkDebugDuplicateClasses with hundreds of
// `Duplicate class com.google.crypto.tink.*` errors.  The Android
// variant is the right one for an APK build, so we exclude the JVM
// flavour transitively.  When/if firebase_messaging gets dropped
// (operator goes UP-only and removes Firebase) this exclude becomes
// inverted — drop tink-android, keep tink — which we'll handle then.
configurations.all {
    exclude(group = "com.google.crypto.tink", module = "tink")
}

dependencies {
    // D-O5m.followup-2 — Keychain/AndroidKeyStore-backed secp256k1
    // signing key handle.
    //
    // BouncyCastle (`bcprov-jdk18on`) — secp256k1 primitives for
    // generating + signing in userspace.  AndroidKeyStore's native EC
    // support only covers NIST P-256/P-384/P-521, so secp256k1 has to
    // be done in userspace.  MIT-licensed; latest stable as of 2024.
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    // androidx.security.crypto — EncryptedSharedPreferences with an
    // AndroidKeyStore-backed master key.  This is what the priv blob
    // gets wrapped by at rest.
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    // androidx.biometric — BiometricPrompt API used by the master key
    // (auth-per-use) and by the Settings migration UI (explicit
    // prompt before generating a new key).
    implementation("androidx.biometric:biometric:1.2.0-alpha05")
    // D-OPS.mobile-smoke-test (2026-05-02): core library desugaring
    // runtime — pairs with `isCoreLibraryDesugaringEnabled = true`
    // above.  Lets `flutter_local_notifications` (and any other plugin
    // that targets Java 8 java.time APIs) run on minSdk 21.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

```
