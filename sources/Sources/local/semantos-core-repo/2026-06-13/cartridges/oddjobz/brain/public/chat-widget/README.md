---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/public/chat-widget/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.554344+00:00
---

# Oddjobz public chat widget — v0.5 (D-O6a)

A drop-in chat widget that POSTs visitor messages to a Semantos Brain-served
`/api/v1/chat` endpoint, which dispatches into
`dispatcher.dispatch(llm.complete, ...)` against the operator's
LLM backend.

References:
- `docs/design/ODDJOBZ-EXTENSION-PLAN.md` §O6 (D-O6a entry).
- `docs/design/BRAIN-DISPATCHER-UNIFICATION.md` §3 line 182, §11 line ~428.

No build step.  Plain HTML / CSS / JS that ships verbatim alongside
your site's static content.

## Embedding

```html
<link rel="stylesheet" href="/chat-widget/chat-widget.css">
<div id="oddjobz-chat-widget"></div>
<script src="/chat-widget/chat-widget.js" defer></script>
```

The widget auto-mounts into `#oddjobz-chat-widget` on
`DOMContentLoaded`.  All four files (`chat-widget.js`,
`chat-widget.css`, `index.html`, this README) are deploy-ready as-is —
copy them into the operator's `content_root` (per
`site_config.zig`).

## Customisation via data attributes

| Attribute          | Default                                         | Purpose                                  |
|--------------------|-------------------------------------------------|------------------------------------------|
| `data-endpoint`    | `/api/v1/chat`                                  | Chat endpoint URL.                       |
| `data-title`       | `Chat with us`                                  | Header text.                             |
| `data-placeholder` | `Ask a question, or describe a job...`          | Input placeholder.                       |
| `data-greeting`    | `Hi! I'm here to help. What can I do for you?`  | First bot bubble (rendered locally).     |

The widget exposes `window.OddjobzChatWidget.mount(el, opts)` for
programmatic mounts when the auto-mount path isn't a fit.

## Wire shape

Request:

```json
POST /api/v1/chat
Content-Type: application/json

{ "message": "<visitor text>", "session_id": "<opaque>" }
```

Response (200):

```json
{ "reply": "<text>", "model": "<model-id>", "tokens_used": 17 }
```

Errors map to HTTP status:

| Status | Trigger                              |
|--------|--------------------------------------|
| 400    | Missing `message` field.             |
| 401    | `anonymous_caps` lacks scope's cap.  |
| 413    | Message exceeds `max_message_chars`. |
| 429    | Per-scope rate limit / day-budget.   |
| 503    | LLM backend unreachable.             |
| 500    | Other unexpected handler error.      |

## Same-origin only on v0.5

Cross-origin (CORS preflight) lands with D-W1 Phase 3 + brain issue
\#273.  Embed the widget on the same domain that serves the chat
endpoint.

## Persistence

D-O6a is **passthrough only** — visitor messages do **not** become
canon cells.  D-O6b (depends on D-O2 + D-W1 Phase 2) layers
`oddjobz.message.v1` cells + the lead-extraction + ratification flow.

## Accessibility

- Messages live region: `aria-live="polite"`.
- Input is auto-focused on mount + after each round-trip.
- Enter sends; Shift+Enter inserts a newline.
- Visible focus styles (no aggressive outline reset).
- Mobile: viewport-relative sizing under `max-width: 480px`.

## Browser-side tests

D-O6a leans on the Semantos Brain-side `chat_http_conformance.zig` Zig tests for
end-to-end coverage of the wire shape.  A browser-driven smoke test
(jsdom / happy-dom) is a TODO — `bun test` does not currently include
the widget; D-O6b will add it once the cell-write path is in scope.
