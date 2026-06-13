---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/index.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.688205+00:00
---

# archive/apps-demo-wasm-threejs/index.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Semantos — substructural linearity in Three.js</title>
  <link rel="stylesheet" href="./src/style.css" />
</head>
<body>
  <div id="hud">
    <div id="title">substructural typing, animated</div>
    <div id="hint">click a cube — the kernel's K1 linearity gate decides legal / illegal · shatter = rejection</div>
    <div id="readout"></div>
  </div>

  <div id="legend">
    <div class="lrow"><span class="dot linear"></span>LINEAR<span class="rule">no DUP · no DROP</span></div>
    <div class="lrow"><span class="dot affine"></span>AFFINE<span class="rule">no DUP</span></div>
    <div class="lrow"><span class="dot relevant"></span>RELEVANT<span class="rule">no DROP</span></div>
  </div>

  <div id="controls">
    <label class="toggle"><input id="enforce-toggle" type="checkbox" checked /> K1 enforcement</label>
    <button id="reset-btn">reset scene</button>
  </div>

  <aside id="identity-panel"></aside>

  <canvas id="scene"></canvas>
  <script type="module" src="./src/main.ts"></script>
</body>
</html>

```
