---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/index.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.691252+00:00
---

# archive/apps-world-client/index.html

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>world-client · Semantos</title>
    <style>
      :root { color-scheme: dark; }
      * { box-sizing: border-box; }
      html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; }
      body {
        background: #0a0a0b;
        color: #c8c8cc;
        font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
      }
      #scene { position: absolute; inset: 0; }

      #hud {
        position: absolute; top: 12px; left: 12px;
        padding: 10px 12px;
        background: rgba(10, 10, 12, 0.78);
        border: 1px solid #2a2a30;
        border-radius: 6px;
        max-width: 380px;
        pointer-events: none;
      }
      #hud h1 {
        margin: 0 0 6px;
        font-size: 11px; font-weight: 600;
        letter-spacing: 0.04em; color: #8a9;
        text-transform: uppercase;
      }
      #hud .row { display: flex; gap: 8px; color: #999; }
      #hud .row b { color: #ccc; font-weight: 500; }
      #hud .hashrow { margin-top: 6px; padding-top: 6px; border-top: 1px dashed #2a2a30; }
      #hud .hashrow b { color: #5b9; }
      #hud .hashrow.diverged b { color: #f1c40f; }

      #help {
        position: absolute; bottom: 12px; left: 12px;
        padding: 10px 12px;
        background: rgba(10, 10, 12, 0.78);
        border: 1px solid #2a2a30;
        border-radius: 6px;
      }
      #help kbd {
        display: inline-block;
        padding: 1px 5px; margin: 0 1px;
        border: 1px solid #444; border-radius: 3px;
        background: #1a1a1e; color: #ddd;
        font-family: inherit;
      }
      #help button {
        margin-left: 12px;
        background: #1a1a1e; color: #c8c8cc;
        border: 1px solid #444; border-radius: 3px;
        padding: 3px 10px;
        font: inherit;
        cursor: pointer;
      }
      #help button.on {
        background: #5e2c2c; color: #ffeaea;
        border-color: #a44;
      }
      #help button:hover { border-color: #888; }

      #log {
        position: absolute; top: 12px; right: 12px; bottom: 220px;
        width: 360px;
        padding: 10px 12px;
        background: rgba(10, 10, 12, 0.72);
        border: 1px solid #2a2a30;
        border-radius: 6px;
        overflow: auto;
        font-size: 11px;
      }
      #log .line { padding: 1px 0; white-space: nowrap; text-overflow: ellipsis; overflow: hidden; }
      #log .line .t { color: #555; margin-right: 6px; }
      #log .line .k { color: #89a; margin-right: 6px; }
      #log .line.err .k { color: #e77; }
      #log .line.warn .k { color: #db5; }
      #log .line.ok .k { color: #5b9; }

      .annotation {
        position: absolute; right: 12px; bottom: 12px;
        width: 360px;
        padding: 14px 16px;
        background: rgba(15, 15, 18, 0.96);
        border-left: 4px solid #5b9;
        border-radius: 6px;
        opacity: 0;
        transform: translateY(8px);
        transition: opacity 220ms ease, transform 220ms ease;
        pointer-events: none;
      }
      .annotation.show { opacity: 1; transform: translateY(0); }
      .annotation[data-tone="ok"]      { border-left-color: #5b9; }
      .annotation[data-tone="info"]    { border-left-color: #6a9bd1; }
      .annotation[data-tone="reject"]  { border-left-color: #e74c3c; }
      .annotation[data-tone="diverge"] { border-left-color: #f1c40f; }

      .annotation .ann-title {
        font-size: 13px; font-weight: 600; color: #f0f0f3;
        margin-bottom: 4px;
      }
      .annotation .ann-source {
        font-size: 11px; color: #8aa;
        font-family: inherit;
        margin-bottom: 8px;
      }
      .annotation .ann-explainer {
        font-size: 12px; line-height: 1.55; color: #b8b8be;
      }

      .toast {
        position: absolute;
        top: 50%; left: 50%;
        transform: translate(-50%, -50%);
        padding: 10px 16px;
        background: rgba(220, 50, 50, 0.92);
        color: #fff;
        border-radius: 6px;
        font-weight: 600;
        opacity: 0;
        transition: opacity 0.25s ease;
        pointer-events: none;
      }
      .toast.show { opacity: 1; }
    </style>
  </head>
  <body>
    <canvas id="scene"></canvas>

    <div id="hud">
      <h1>world-client · Semantos</h1>
      <div class="row"><span>region <b id="hud-region">—</b></span></div>
      <div class="row"><span>tick <b id="hud-tick">—</b></span></div>
      <div class="row"><span>session <b id="hud-session">—</b></span></div>
      <div class="row"><span>selected <b id="hud-selected">—</b></span></div>
      <div class="row"><span>entities <b id="hud-count">0</b></span></div>
      <div class="row hashrow" id="hud-hashrow">
        <span>stateHash <b id="hud-hash">—</b></span>
      </div>
    </div>

    <div id="help">
      <b>Click</b> cube to select ·
      <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> / <kbd>↑</kbd><kbd>↓</kbd><kbd>←</kbd><kbd>→</kbd> move ·
      <kbd>X</kbd> attempt duplicate ·
      <kbd>R</kbd> drop
      <button id="cheat-toggle" type="button" title="Toggle predictor cheat — next DUP will lie locally">cheat: off</button>
    </div>

    <div id="log"></div>
    <div id="toast" class="toast">LINEAR cell cannot be duplicated</div>

    <script type="module" src="/src/main.ts"></script>
  </body>
</html>

```
