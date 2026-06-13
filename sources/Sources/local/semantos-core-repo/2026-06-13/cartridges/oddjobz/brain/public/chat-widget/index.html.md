---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/public/chat-widget/index.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.554632+00:00
---

# cartridges/oddjobz/brain/public/chat-widget/index.html

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Oddjobz public chat v0.5 — demo</title>
  <link rel="stylesheet" href="chat-widget.css">
  <style>
    /* Demo-page-only styles — not part of the widget. */
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                   "Helvetica Neue", Arial, sans-serif;
      max-width: 720px;
      margin: 40px auto;
      padding: 0 16px;
      color: #0f172a;
      background: #f7f8fa;
    }
    h1 {
      font-size: 24px;
      margin-bottom: 8px;
    }
    p.lede {
      color: #475569;
      margin-top: 0;
    }
    code {
      background: #eef0f3;
      padding: 1px 4px;
      border-radius: 4px;
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      font-size: 13px;
    }
    .demo-row {
      display: flex;
      gap: 24px;
      align-items: flex-start;
      flex-wrap: wrap;
      margin-top: 24px;
    }
    .notes {
      flex: 1 1 280px;
      min-width: 280px;
    }
    .notes h2 {
      font-size: 16px;
      margin-top: 0;
    }
    .notes ul {
      padding-left: 20px;
    }
  </style>
</head>
<body>
  <h1>Oddjobz public chat v0.5 — demo</h1>
  <p class="lede">
    Standalone demo page for the D-O6a chat widget.  Drives
    <code>POST /api/v1/chat</code> on the same origin via
    <code>fetch</code>; renders the back-and-forth as bubbles.
  </p>

  <div class="demo-row">
    <div id="oddjobz-chat-widget"
         data-title="Talk to oddjobtodd"
         data-placeholder="Quote, schedule, or just say hi..."></div>

    <div class="notes">
      <h2>How to embed</h2>
      <ol>
        <li>Copy <code>chat-widget.css</code> +
            <code>chat-widget.js</code> to your site's static dir.</li>
        <li>Add a <code>&lt;link&gt;</code> tag for the CSS in
            <code>&lt;head&gt;</code>.</li>
        <li>Drop a <code>&lt;div id="oddjobz-chat-widget"&gt;&lt;/div&gt;</code>
            where you want the widget mounted.</li>
        <li>Add a <code>&lt;script src=".../chat-widget.js" defer&gt;&lt;/script&gt;</code>
            tag at the end of <code>&lt;body&gt;</code>.</li>
      </ol>
      <p>
        The widget's mount div accepts data attributes for the title,
        placeholder, greeting, and endpoint — see
        <a href="README.md">README.md</a> for the full list.
      </p>
      <p>
        v0.5 is same-origin only (no CORS); embed the widget on the
        same domain that serves <code>/api/v1/chat</code>.  Cross-
        origin support lands with D-W1 Phase 3.
      </p>
    </div>
  </div>

  <script src="chat-widget.js" defer></script>
</body>
</html>

```
