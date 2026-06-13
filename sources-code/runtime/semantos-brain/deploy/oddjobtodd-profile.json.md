---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/deploy/oddjobtodd-profile.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.167846+00:00
---

# runtime/semantos-brain/deploy/oddjobtodd-profile.json

```json
{
  "business_name":     "Oddjobz",
  "trade_label":       "Handyman",
  "geography":         "Sunshine Coast",
  "phone":             "0412 345 678",
  "abn":               "00 000 000 000",

  "problem":  "You need something fixed but can't find a reliable tradie who shows up and communicates.",
  "uvp":      "Get a rough quote in minutes",
  "hero_h1":  "Get a rough quote in minutes",
  "hero_lede": "Describe the job in the chat. We'll ask a couple of questions and give you a ballpark — no obligation.",

  "segment": "homeowners",
  "tone":    "friendly",

  "trust_signals": [
    "Sunshine Coast based — Noosa to Caloundra",
    "Free on-site quote for most jobs",
    "No call centre — you talk directly to the tradie",
    "Same-day response on urgent jobs"
  ],

  "services": [
    { "slug": "carpentry",  "label": "Carpentry",       "icon": "🔨", "description": "Decks, shelves, framing, cabinets, pergolas" },
    { "slug": "plumbing",   "label": "Plumbing",        "icon": "🚿", "description": "Taps, drains, hot water, pipes, toilets" },
    { "slug": "electrical", "label": "Electrical",      "icon": "⚡", "description": "Power points, switches, light fittings" },
    { "slug": "painting",   "label": "Painting",        "icon": "🎨", "description": "Interior, exterior, feature walls, patching" },
    { "slug": "fencing",    "label": "Fencing",         "icon": "🏚️", "description": "Palings, panels, posts, gates" },
    { "slug": "doors",      "label": "Doors & Windows", "icon": "🪟", "description": "Hanging, adjusting, locks, frames" },
    { "slug": "gardening",  "label": "Gardening",       "icon": "🪴", "description": "Mowing, hedging, mulch, retaining walls" },
    { "slug": "general",    "label": "General",         "icon": "🔧", "description": "Assembly, hanging, TV mounts, odd jobs" }
  ],

  "pricing": {
    "callout_fee":    { "label": "Service call", "amount": 120, "currency": "AUD" },
    "hourly_rate":    { "label": "Per hour",     "amount": 95,  "currency": "AUD" },
    "emergency_rate": { "label": "After hours",  "amount": 180, "currency": "AUD" },
    "minimum_charge": null,
    "quote_policy":   "free_onsite"
  },

  "widget_title":       "Get a rough quote",
  "widget_greeting":    "G'day! Tell me about the job and I'll give you a rough ballpark. What's going on?",
  "widget_placeholder": "Describe the job — e.g. 'dripping kitchen tap' or '3 fence panels need replacing'...",
  "widget_endpoint":    "/api/v1/chat"
}

```
