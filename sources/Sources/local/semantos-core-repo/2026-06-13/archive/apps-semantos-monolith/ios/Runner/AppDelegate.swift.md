---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/ios/Runner/AppDelegate.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.851991+00:00
---

# archive/apps-semantos-monolith/ios/Runner/AppDelegate.swift

```swift
// D-O5m.followup-9 Phase C — Firebase + APNs wiring on the iOS side.
//
// References:
//   - https://firebase.flutter.dev/docs/messaging/overview (Flutter
//     plugin canonical setup)
//   - Apple's UNUserNotificationCenter docs (request authorization +
//     foreground presentation options)
//
// What this file does (when Firebase is enabled):
//   1. Calls FirebaseApp.configure() at app launch so the
//      firebase_messaging plugin (loaded by GeneratedPluginRegistrant)
//      can talk to the native Firebase iOS SDK.
//   2. Wires UNUserNotificationCenter.delegate to the FlutterAppDelegate
//      so foreground notifications and tap callbacks reach the plugin.
//   3. Forwards the APNs device token to Messaging.messaging() so a
//      subsequent firebase_messaging.getAPNSToken() / getToken() call
//      resolves with the platform token the brain needs.
//
// 2026-05-07 — Firebase native bridge temporarily disabled
// =========================================================
// PR #392 commented out firebase_core + firebase_messaging from the
// Dart side (`apps/oddjobz-mobile/pubspec.yaml`) to unblock the iOS
// Simulator build for Bridget's pairing test. That PR missed the
// native iOS bridge here — without this fix the iOS Simulator build
// fails on `import FirebaseCore` / `import FirebaseMessaging` because
// the pods are no longer in the workspace.
//
// To restore Firebase later: revert this file alongside reinstating
// firebase_core + firebase_messaging in pubspec.yaml. The original
// Firebase-enabled code is preserved in git history at the previous
// HEAD (see PR #392 + this PR).
//
// Note (SecureSigningKey): the SecureSigningKeyChannel.register call
// is also commented out because SecureSigningKey.swift isn't in the
// Runner target's compile sources (project.pbxproj doesn't list it),
// so the channel symbol isn't reachable. SecureSigningKey.swift's
// gracefully-degraded `#if canImport(secp256k1)` path means the Dart
// side falls back to pointycastle when the channel returns
// UNSUPPORTED — and the channel returning UNSUPPORTED via "no
// registration" is functionally equivalent.

import Flutter
import UIKit
// 2026-05-07 — temporarily disabled (paired with PR #392 Dart-side stub):
// import FirebaseCore
// import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 2026-05-07 — temporarily disabled (paired with PR #392 Dart-side stub).
    // FirebaseApp.configure()

    // Forward UNUserNotificationCenter callbacks (foreground present
    // + tap) to the Flutter app delegate.  The firebase_messaging
    // plugin swizzles into this delegate to surface
    // onMessage/onMessageOpenedApp from the Dart side.
    //
    // Kept enabled so the local-notifications channel
    // (flutter_local_notifications, which IS still wired) can present.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // 2026-05-07 — APNs callback temporarily disabled (paired with PR #392).
  // APNs registration callback.  Forward the device token to the
  // Firebase Messaging native instance so getAPNSToken() resolves.
  // override func application(
  //   _ application: UIApplication,
  //   didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  // ) {
  //   Messaging.messaging().apnsToken = deviceToken
  //   super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  // }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 2026-05-07 — temporarily disabled.  D-O5m.followup-2 wired the
    // Keychain-backed secp256k1 signing key handle, but
    // SecureSigningKey.swift isn't in Runner's compile sources
    // (project.pbxproj doesn't list it) so the channel symbol isn't
    // reachable.  Dart-side falls back to pointycastle via
    // SecureSigningKey's `#if canImport(secp256k1)` graceful-degrade
    // path — same effective outcome as a registered channel returning
    // UNSUPPORTED.  Restoring requires either adding
    // SecureSigningKey.swift to the Runner target via Xcode project
    // settings (project.pbxproj entry) or wiring it in via a clean
    // PodFile-managed dependency on a forks-restored secp256k1 pod.
    // SecureSigningKeyChannel.register(with: engineBridge.pluginRegistry)
  }
}

```
