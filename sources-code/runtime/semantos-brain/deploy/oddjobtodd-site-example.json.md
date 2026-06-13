---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/oddjobtodd-site-example.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.168929+00:00
---

# runtime/semantos-brain/deploy/oddjobtodd-site-example.json

```json
{
  "_comment_": "D-O6a — example site.json for oddjobtodd.info enabling the public chat v0.5 widget. See docs/design/ODDJOBZ-EXTENSION-PLAN.md §O6. Copy this file to /var/lib/semantos/sites/oddjobtodd.info/site.json on the deployed server (or wherever the operator's BRAIN_DATA_DIR resolves), regenerate the signing_secret, and restart brain serve. Do NOT commit a real signing_secret — the value below is a placeholder.",

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
      "type": "static",
      "file": "index.html",
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
      "system_prompt": "You are a helpful assistant for a sole-trader carpenter named Todd. Visitors may ask about quotes, scheduling, services, or prices. Keep responses short and friendly. If a visitor seems to be inquiring about a real job, ask for their name, contact details, and a brief description of the work — but do not commit to specific prices or dates yourself; tell them Todd will follow up to confirm. Do not invent prices, availability, or guarantees.",
      "max_message_chars": 4000
    }
  }
}

```
