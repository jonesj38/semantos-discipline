---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/android/app/google-services.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.856847+00:00
---

# archive/apps-semantos-monolith/android/app/google-services.json

```json
{
  "_comment_": "D-O5m.followup-9 Phase C — PLACEHOLDER google-services.json. The real per-tenant file is generated in the Firebase Console (Project settings → Your apps → Android app → Download google-services.json) and swapped in at deploy time per docs/operator-runbooks/push-notification-setup.md §FCM (Android). The placeholder values below are syntactically valid (the google-services Gradle plugin parses them) but the project_number / project_id / mobilesdk_app_id are nonsense fillers; pushing with this file in place will fail at the FCM dispatcher with a non-retryable auth error. The Gradle plugin REQUIRES this file to exist at apply time, even for Debug builds without push, so the placeholder ships in source control to keep `flutter build apk` working in CI without leaking real Firebase credentials.",
  "project_info": {
    "project_number": "000000000000",
    "project_id": "oddjobz-placeholder",
    "storage_bucket": "oddjobz-placeholder.appspot.com"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:000000000000:android:0000000000000000000000",
        "android_client_info": {
          "package_name": "info.oddjobtodd.oddjobz_mobile"
        }
      },
      "oauth_client": [],
      "api_key": [
        {
          "current_key": "AIzaSy-PLACEHOLDER-replace-via-runbook--00000000"
        }
      ],
      "services": {
        "appinvite_service": {
          "other_platform_oauth_client": []
        }
      }
    }
  ],
  "configuration_version": "1"
}

```
