---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/android/app/src/main/AndroidManifest.xml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.857318+00:00
---

# archive/apps-semantos-monolith/android/app/src/main/AndroidManifest.xml

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required for all HTTP/HTTPS network access including model
         downloads, /api/v1/repl, WebSocket /api/v1/wallet, and Firebase. -->
    <uses-permission android:name="android.permission.INTERNET" />
    <!-- D-O5m: camera is required for the pairing-QR scanner. -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <!-- D-O5m.followup-8 GPS + voice memo adapters: location + mic
         permissions for the §O5m-f sensor trio.  ACCESS_COARSE_LOCATION
         is the fallback path for devices without fine-grained GPS or
         when the operator has only granted coarse access; the helm
         renders the same lat/lng caption either way. -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <!-- D-O5m.followup-9 Phase C — push notifications.
         Android 13 (API 33) and above require an explicit runtime
         permission for posting notifications.  Older Android versions
         silently grant the permission at install time; the manifest
         entry is harmless on older devices and load-bearing on newer
         ones (the firebase_messaging plugin will silently drop
         notifications without it).  PushRegistrationService prompts
         via permission_handler before calling getDeviceToken(). -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <!-- Wake the device on incoming high-priority FCM messages so
         the operator hears the system notification sound when a lead
         arrives outside business hours (the brain-side push payload
         marks lead.created as high priority). -->
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <application
        android:label="oddjobz_mobile"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
        <!-- D-O5m.followup-9 Phase C — FCM default notification
             channel.  When a payload arrives without an explicit
             channel_id (the brain-side dispatcher omits it for
             portability), Android 8+ routes it through this channel.
             The channel itself is created at runtime by
             flutter_local_notifications when push_handlers.dart
             initialises (see _ensureDefaultChannel). -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="oddjobz_default_channel" />
        <!-- Disable Firebase Analytics auto-collection — the helm
             doesn't ship analytics and the operator's data plane
             stays inside their tenant.  Operators can flip this to
             true via the tenant manifest at deploy time. -->
        <meta-data
            android:name="firebase_messaging_auto_init_enabled"
            android:value="true" />
        <meta-data
            android:name="firebase_analytics_collection_enabled"
            android:value="false" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>

```
