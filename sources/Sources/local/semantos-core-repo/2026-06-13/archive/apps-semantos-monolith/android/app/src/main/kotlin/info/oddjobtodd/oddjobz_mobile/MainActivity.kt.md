---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/android/app/src/main/kotlin/info/oddjobtodd/oddjobz_mobile/MainActivity.kt
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.859015+00:00
---

# archive/apps-semantos-monolith/android/app/src/main/kotlin/info/oddjobtodd/oddjobz_mobile/MainActivity.kt

```kt
package info.oddjobtodd.oddjobz_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // D-O5m.followup-2 — wire the AndroidKeyStore-backed secp256k1
    // signing key handle.  See app/src/main/kotlin/.../
    // SecureSigningKey.kt for the honest scope analysis (priv enters
    // memory during sign because AndroidKeyStore EC keys are
    // restricted to NIST curves; secp256k1 isn't supported as a
    // native key algorithm).
    SecureSigningKeyChannel.register(
      flutterEngine.dartExecutor.binaryMessenger,
      applicationContext,
    )
  }
}

```
