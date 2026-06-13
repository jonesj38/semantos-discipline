---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/push-notification-setup.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.640371+00:00
---

# Push notification setup — APNs (iOS) + FCM (Android)

> **Audience**: operator (sysadmin) provisioning push notifications
> for an oddjobz-mobile-equipped tenant brain.
>
> **Status**: D-O5m.followup-9 ships the full pipeline:
>  - Phase A (#326) — schema + `POST/DELETE /api/v1/push-register`
>    endpoint + `requires_operator_attention` event flag
>  - Phase B (#327) — real APNs (ES256 JWT) + FCM (OAuth2 RS256)
>    dispatchers
>  - Phase C (this PR) — Flutter Firebase wiring + iOS APNs
>    entitlement + Android google-services hookup +
>    PushRegistrationService
>
> **References**:
>  - [`docs/canon/deliverables.yml`](../canon/deliverables.yml) D-O5m.followup-9
>  - [`runtime/semantos-brain/src/push_register_http.zig`](../../runtime/semantos-brain/src/push_register_http.zig)
>  - [`runtime/semantos-brain/src/apns_dispatcher.zig`](../../runtime/semantos-brain/src/apns_dispatcher.zig)
>  - [`runtime/semantos-brain/src/fcm_dispatcher.zig`](../../runtime/semantos-brain/src/fcm_dispatcher.zig)
>  - [`apps/oddjobz-mobile/lib/src/push/push_registration_service.dart`](../../apps/oddjobz-mobile/lib/src/push/push_registration_service.dart)

## Overview

The push notification feature is end-to-end after this runbook is
followed:

1. The tradie pairs a phone via QR (D-O5p / D-O5m).
2. `PushRegistrationService.registerOnPair()` requests permission,
   captures the platform device token (APNs on iOS / FCM on
   Android), and POSTs it to `/api/v1/push-register`.
3. The brain persists the token onto the device's identity-cert
   record.
4. When a `lead.created` event (or any future event flagged
   `requires_operator_attention=true`) hits the helm event broker,
   `PushDispatcher` looks up the cert's `push_platform` and routes
   the payload through `ApnsDispatcher` or `FcmDispatcher`.
5. The device shows a system notification. Tap routes to the
   helm screen via `PushNotificationRouter` (deep-link by `screen`
   key on the data payload).

The credentials needed to run that pipeline are split across two
configuration files:

- `<data_dir>/push-config.json` — brain-side dispatcher config
  (APNs `.p8` path, FCM service-account JSON path, etc.). Read on
  brain boot; absent file = "push not configured".
- `apps/oddjobz-mobile/android/app/google-services.json` +
  `apps/oddjobz-mobile/ios/Runner/GoogleService-Info.plist` —
  device-side Firebase config. The repo ships placeholder
  `google-services.json` so `flutter build apk` works in CI; the
  real per-tenant files swap in at deploy time.

The two halves share a Firebase project (one project covers both
APNs and FCM; FCM is just a different transport on the same project).

## APNs (iOS)

### Prerequisites

- Apple Developer Program enrollment (USD 99/year).
- Access to the team's App Store Connect.
- The bundle ID configured in
  `apps/oddjobz-mobile/ios/Runner.xcodeproj` — currently
  `info.oddjobtodd.oddjobz_mobile`. Operators forking the codebase
  for a different tenant change this in Xcode → Runner target →
  Signing & Capabilities.

### One-time per Apple Developer team

1. Sign in to https://developer.apple.com/account/.
2. **Certificates, Identifiers & Profiles → Keys → "+"**.
3. Name the key (e.g. "oddjobz APNs"), tick **Apple Push
   Notifications service (APNs)**, click **Continue → Register**.
4. **Download** the `.p8` file. Apple only lets you download it
   once — store it in the operator's secrets vault. Note the **Key
   ID** (10 chars) shown on the same page.
5. Note the **Team ID** (10 chars) from Membership.

### Per-tenant deploy steps

1. Copy the `.p8` to the brain host at e.g.
   `/var/lib/semantos/<domain>/push/apns_authkey.p8` with mode 0600
   (owner-only readable).
2. Edit `<data_dir>/push-config.json`:
   ```json
   {
     "apns": {
       "team_id": "ABCD123456",
       "key_id": "EFGH789012",
       "p8_key_path": "/var/lib/semantos/<domain>/push/apns_authkey.p8",
       "bundle_id": "info.oddjobtodd.oddjobz_mobile",
       "environment": "production"
     }
   }
   ```
   `environment` must match the iOS build's `aps-environment`
   entitlement: `development` for `flutter run` against a Debug
   provisioning profile, `production` for App Store / TestFlight
   builds. **A token registered against the wrong environment fails
   on every send with `BadEnvironmentKeyInToken` and the brain
   clears the cert's `push_platform` automatically.**
3. Restart the Semantos Brain service. The boot line should report
   `[push] APNs configured`. Absent file logs
   `[push] not configured (no push-config.json)`.

### iOS app build (release flip)

The `aps-environment` entitlement at
`apps/oddjobz-mobile/ios/Runner/Runner.entitlements` ships set to
`development`. Before a TestFlight / App Store build, flip it to
`production`:

```xml
<key>aps-environment</key>
<string>production</string>
```

Apple recommends a separate Xcode build configuration for this
flip; the runbook keeps the simpler "edit before release" approach
to avoid Xcode-config sprawl.

## FCM (Android)

### One-time per Firebase project

1. Open https://console.firebase.google.com/ and create a new
   project (e.g. `oddjobz-<tenant>`). Disable Google Analytics
   unless the tenant explicitly opts in (Firebase Analytics
   collection is also disabled in `AndroidManifest.xml` via the
   `firebase_analytics_collection_enabled` meta-data).
2. **Add app → Android**. Package name must match
   `apps/oddjobz-mobile/android/app/build.gradle.kts`'s
   `applicationId` — currently `info.oddjobtodd.oddjobz_mobile`.
3. **Download `google-services.json`** and overwrite the placeholder
   at `apps/oddjobz-mobile/android/app/google-services.json`.
4. (Optional but recommended) **Add app → iOS** with the same
   bundle ID so APNs and FCM share a project. Download
   `GoogleService-Info.plist` and place it at
   `apps/oddjobz-mobile/ios/Runner/GoogleService-Info.plist`.
   Re-run `pod install` from `apps/oddjobz-mobile/ios/` once.

### Service-account key for the brain dispatcher

The brain side mints OAuth2 access tokens from a service-account
JWT (see `runtime/semantos-brain/src/fcm_dispatcher.zig`). To create the
service-account JSON:

1. In the Firebase Console: **Project settings → Service accounts
   tab → Manage service account permissions**.
2. The Google Cloud IAM page opens. **Create service account →
   name it `oddjobz-brain-fcm`**.
3. Grant the role `Firebase Cloud Messaging API Admin` (or
   narrower: `cloudmessaging.messages.create`).
4. Done → click the new account → **Keys → Add Key → Create new
   key → JSON → Create**. The browser downloads a JSON file. **This
   JSON cannot be re-downloaded — store it in the operator's
   secrets vault.**

### Per-tenant brain deploy steps

1. Copy the service-account JSON to e.g.
   `/var/lib/semantos/<domain>/push/fcm_service_account.json`,
   mode 0600.
2. Extend `<data_dir>/push-config.json`:
   ```json
   {
     "apns": {
       "team_id": "...",
       "key_id": "...",
       "p8_key_path": "...",
       "bundle_id": "...",
       "environment": "..."
     },
     "fcm": {
       "service_account_json_path": "/var/lib/semantos/<domain>/push/fcm_service_account.json"
     }
   }
   ```
3. Restart the Semantos Brain service. Boot line should now report both
   `[push] APNs configured` and `[push] FCM configured`.

## Verifying

After both halves are configured:

1. **Pair a device.** On a fresh phone, scan the operator's
   `brain device pair` QR. The pairing handshake completes; HomeScreen
   mounts; PushRegistrationService fires.
2. **Confirm the registration round-trip.** On the brain host:
   ```
   tail -f /var/log/semantos/<domain>.log | grep push-register
   ```
   You should see one POST entry with `platform=apns` (iOS) or
   `platform=fcm` (Android) and a 200 response.
3. **Confirm the local persisted record.** On the phone, Settings
   → Notifications card. The status should read "Registered" with
   a non-empty `Registered at` timestamp.
4. **Trigger a push end-to-end.** From the brain REPL, transition
   a job into the `lead` state:
   ```
   job <job-id> mark-lead
   ```
   The phone should receive a system notification within ~30
   seconds (longer on first send if Apple's APNs HTTP/2 connection
   is cold). Tap the notification — the helm should open to the
   ratification card (or fall through to home if D-O5m.followup-7
   hasn't shipped the `/ratify` route yet; see Phase C PR notes).

## Troubleshooting

### APNs

- **`BadDeviceToken`** — the token is malformed or registered against
  the wrong environment. The brain clears `push_platform` on the
  cert; re-pair the device or flip `aps-environment` /
  `push-config.json` `environment` to match.
- **`Unregistered`** — Apple has invalidated the token (app
  uninstalled / device wiped). Same recovery as `BadDeviceToken`:
  the brain clears the cert; the device re-registers on next launch.
- **`BadCertificateEnvironment`** — `aps-environment` and the
  brain config disagree. Same recovery.
- **No notifications, no error** — silent push? Check the iOS
  notification settings for the app (Settings → Notifications →
  Oddjobz Mobile → Allow Notifications). The Open-Settings CTA in
  the helm's Notifications card opens straight to that page.

### FCM

- **`UNREGISTERED`** — the FCM token has been invalidated. The brain
  clears `push_platform`; the device re-registers on next launch.
- **`SENDER_ID_MISMATCH`** — the device-side `google-services.json`
  was generated for a different Firebase project than the one the
  brain's service-account JSON authenticates against. Re-download
  the right `google-services.json` from the Firebase Console.
- **`UNAUTHENTICATED` / `403`** — service-account JSON path is
  wrong, or the service account is missing the
  `cloudmessaging.messages.create` permission. Check
  `<data_dir>/push-config.json` and IAM.

### Phase C `/ratify` deep-link not yet wired

D-O5m.followup-7 ships the voice/text input bar + the ratification
card. Until that PR lands, the `/ratify` route registered with the
helm's MaterialApp doesn't exist; PushNotificationRouter logs a
warning and the navigator falls through to home. The notification
itself is still delivered correctly — only the deep-link target is
deferred. Once followup-7 ships, no Phase C change is required: the
router already pushes `/ratify` with the `lead_id` argument.

## Token rotation

`PushRegistrationService.startTokenRefreshListener` listens to
`firebase_messaging.onTokenRefresh` and POSTs every rotated token
to `/api/v1/push-register`. The brain's `updatePushToken` is
idempotent — same cert, new token, same `push_platform`. No operator
intervention is required for routine rotations (OS updates, app
reinstalls).

## How `cert.push_platform = none` clearing works

When APNs returns `Unregistered` (or FCM returns `UNREGISTERED`),
the brain dispatcher calls `CertStore.updatePushToken(cert_id,
.none, "", "")`. The cert's `apns_token` / `fcm_token` /
`push_registered_at` fields are cleared. The next event flagged
`requires_operator_attention=true` finds `push_platform=none` on
the cert and routes nowhere (silent). When the device reopens the
app and HomeScreen mounts, `PushRegistrationService.registerOnPair`
fires again — getting the new token from the OS, POSTing it, and
restoring `push_platform` to the right transport. Push resumes
within one app launch of the rotation.
