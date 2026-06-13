---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/ios/Runner/Info.plist
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.851708+00:00
---

# archive/apps-semantos-monolith/ios/Runner/Info.plist

```plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
	<key>NSCameraUsageDescription</key>
	<string>Used to scan the operator-issued pairing QR for D-O5p / D-O5m device pairing.</string>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Drops a GPS pin at your current job site to attach to a Visit.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Records voice memos to attach to a Visit.</string>
	<!-- D-O5m.followup-9 Phase C — push notifications.
	     Operator-readable copy is shown in the iOS authorization prompt
	     the first time PushRegistrationService asks for permission. -->
	<key>NSUserNotificationsUsageDescription</key>
	<string>We send you push notifications when new leads arrive while the app is closed.</string>
	<!-- Background remote notification + content fetch — required so
	     APNs silent pushes reach the firebase_messaging plugin's
	     background handler when the app is suspended. -->
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
		<string>remote-notification</string>
	</array>
	<!-- Suppress Firebase auto-init data-collection consent toast.
	     The mobile shell already gates push behind explicit
	     PushRegistrationService.registerOnPair(), so the auto-init is
	     redundant.  Operators can flip this to true at deploy time
	     when telemetry is opted-in via the tenant manifest. -->
	<key>FirebaseAppDelegateProxyEnabled</key>
	<true/>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>Oddjobz Mobile</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>oddjobz_mobile</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<false/>
		<key>UISceneConfigurations</key>
		<dict>
			<key>UIWindowSceneSessionRoleApplication</key>
			<array>
				<dict>
					<key>UISceneClassName</key>
					<string>UIWindowScene</string>
					<key>UISceneConfigurationName</key>
					<string>flutter</string>
					<key>UISceneDelegateClassName</key>
					<string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
					<key>UISceneStoryboardFile</key>
					<string>Main</string>
				</dict>
			</array>
		</dict>
	</dict>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
	<key>UILaunchStoryboardName</key>
	<string>LaunchScreen</string>
	<key>UIMainStoryboardFile</key>
	<string>Main</string>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>

```
