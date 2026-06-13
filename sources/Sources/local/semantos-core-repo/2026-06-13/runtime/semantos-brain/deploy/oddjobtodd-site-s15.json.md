---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/oddjobtodd-site-s15.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.169745+00:00
---

# runtime/semantos-brain/deploy/oddjobtodd-site-s15.json

```json
{
  "_comment_": "S15 — oddjobtodd.info site.json with operator_home route replacing the hand-coded static HTML. Copy to /var/lib/semantos/sites/oddjobtodd.info/site.json on the deployed server, then run: brain site-publish oddjobtodd.info --data-dir /var/lib/semantos --from deploy/oddjobtodd-profile.json. Restart brain serve to pick up the new routes.",

  "site": {
    "domain": "oddjobtodd.info",
    "content_root": "./public",
    "listen_port": 8080,
    "session_ttl_seconds": 86400,
    "signing_secret": "0000000000000000000000000000000000000000000000000000000000000000",
    "anonymous_caps": [
      "cap.llm.complete:anonymous-oddjobz"
    ]
  },
  "routes": {
    "/": {
      "type": "operator_home",
      "public": true
    },
    "/index.html": {
      "type": "operator_home",
      "public": true
    },
    "/chat-widget/chat-widget.js": {
      "type": "static",
      "file": "chat-widget/chat-widget.js",
      "public": true
    },
    "/chat-widget/chat-widget.css": {
      "type": "static",
      "file": "chat-widget/chat-widget.css",
      "public": true
    },
    "/api/v1/chat": {
      "type": "chat",
      "scope": "anonymous-oddjobz",
      "system_prompt": "You are a helpful intake assistant for Oddjobz, a Sunshine Coast handyman service run by Todd. Your job is to get enough information to give the visitor a rough ballpark price and book a follow-up. Ask about: what needs doing, rough size/scope, any photos they can share, and their contact details. Keep it conversational. Do not commit to exact prices or dates — tell them Todd will confirm. Typical rates: $120 service call, $95/hr labour, after-hours $180/hr.",
      "max_message_chars": 4000
    },
    "/api/v1/analytics": {
      "type": "analytics",
      "public": true
    }
  }
}

```
