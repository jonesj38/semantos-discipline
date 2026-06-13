---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/prototypes/multipane_viewer_testing/viewer.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.758917+00:00
---

# archive/prototypes/multipane_viewer_testing/viewer.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Semantos Console Viewer</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
:root {
    --bg: #0d1117; --card: #161b22; --border: #30363d;
    --fg: #c9d1d9; --dim: #8b949e; --green: #3fb950;
    --blue: #58a6ff; --purple: #d2a8ff; --red: #f85149;
    --orange: #f0883e;
}
body { background: var(--bg); color: var(--fg); font-family: 'JetBrains Mono', monospace; }

.header {
    display: flex; align-items: center; gap: 1rem;
    padding: 0.5rem 1rem; background: var(--card); border-bottom: 1px solid var(--border);
    height: 36px;
}
.header h1 { font-size: 0.9rem; color: var(--blue); font-weight: 600; }
.header .deploy-path { font-size: 0.7rem; color: var(--dim); }
.header .status { font-size: 0.75rem; margin-left: auto; }

.console-grid {
    display: grid;
    grid-template-columns: 20% 1fr 25%;
    grid-template-rows: 1fr 160px;
    height: calc(100vh - 36px);
    gap: 1px;
    background: var(--border);
}

.pane {
    background: var(--bg);
    position: relative;
    display: flex;
    flex-direction: column;
    overflow: hidden;
}
.pane-label {
    flex-shrink: 0;
    padding: 0.2rem 0.5rem;
    font-size: 0.65rem; color: var(--dim);
    background: var(--card); border-bottom: 1px solid var(--border);
    display: flex; align-items: center; gap: 0.4rem;
    height: 22px;
}
.pane-dot {
    width: 6px; height: 6px; border-radius: 50%;
    transition: background-color 0.3s;
}
.pane-dot.up { background: var(--green); }
.pane-dot.down { background: var(--red); }
.pane-dot.unknown { background: var(--dim); }

.pane iframe {
    flex: 1; width: 100%; border: none;
}

.pane-objects { grid-row: 1; grid-column: 1; }
.pane-shell  { grid-row: 1; grid-column: 2; }
.pane-inspector { grid-row: 1; grid-column: 3; }
.pane-events { grid-row: 2; grid-column: 1 / -1; }

.pane-placeholder {
    flex: 1;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    color: var(--dim); font-size: 0.8rem; gap: 0.5rem;
}
.pane-placeholder .retry-btn {
    padding: 0.2rem 0.6rem; font-size: 0.7rem;
    background: transparent; color: var(--blue); border: 1px solid var(--blue);
    border-radius: 3px; cursor: pointer; display: none;
}
</style>
</head>
<body>

<div class="header">
    <h1>Semantos Console Viewer</h1>
    <span id="deploy-path" class="deploy-path"></span>
    <span id="status" class="status" style="color:var(--dim)">connecting...</span>
</div>

<div class="console-grid">
    <div class="pane pane-objects" data-pane="objects">
        <div class="pane-label"><span class="pane-dot unknown" data-dot="objects"></span> OBJECT TREE</div>
        <div class="pane-placeholder" data-placeholder="objects">
            <span>connecting...</span>
            <button class="retry-btn" onclick="loadPane('objects')">retry</button>
        </div>
    </div>
    <div class="pane pane-shell" data-pane="shell">
        <div class="pane-label"><span class="pane-dot unknown" data-dot="shell"></span> SHELL (REPL)</div>
        <div class="pane-placeholder" data-placeholder="shell">
            <span>connecting...</span>
            <button class="retry-btn" onclick="loadPane('shell')">retry</button>
        </div>
    </div>
    <div class="pane pane-inspector" data-pane="inspector">
        <div class="pane-label"><span class="pane-dot unknown" data-dot="inspector"></span> INSPECTOR</div>
        <div class="pane-placeholder" data-placeholder="inspector">
            <span>connecting...</span>
            <button class="retry-btn" onclick="loadPane('inspector')">retry</button>
        </div>
    </div>
    <div class="pane pane-events" data-pane="events">
        <div class="pane-label"><span class="pane-dot unknown" data-dot="events"></span> EVENT LOG</div>
        <div class="pane-placeholder" data-placeholder="events">
            <span>connecting...</span>
            <button class="retry-btn" onclick="loadPane('events')">retry</button>
        </div>
    </div>
</div>

<script>
var CONFIG = null;
var PANE_LOADED = {};

async function loadConfig() {
    try {
        var r = await fetch('/api/config');
        CONFIG = await r.json();
        document.getElementById('deploy-path').textContent = CONFIG.deploy_dir || '';
        return true;
    } catch(e) {
        document.getElementById('status').textContent = 'viewer server unreachable';
        document.getElementById('status').style.color = 'var(--red)';
        return false;
    }
}

function loadPane(name) {
    if (!CONFIG || !CONFIG.ports[name]) return;
    var pane = document.querySelector('[data-pane="' + name + '"]');
    if (!pane) return;

    var placeholder = pane.querySelector('[data-placeholder]');
    var existing = pane.querySelector('iframe');
    if (existing) existing.remove();

    var host = window.location.hostname;
    var port = CONFIG.ports[name];
    var iframe = document.createElement('iframe');
    iframe.src = 'http://' + host + ':' + port + '/';

    iframe.onload = function() {
        PANE_LOADED[name] = true;
        if (placeholder) placeholder.style.display = 'none';
    };
    iframe.onerror = function() {
        PANE_LOADED[name] = false;
        if (placeholder) {
            placeholder.style.display = 'flex';
            placeholder.querySelector('span').textContent = 'failed to connect (port ' + port + ')';
            placeholder.querySelector('.retry-btn').style.display = 'inline-block';
        }
    };

    pane.appendChild(iframe);
}

function updateDot(name, isUp) {
    var dot = document.querySelector('[data-dot="' + name + '"]');
    if (!dot) return;
    dot.className = 'pane-dot ' + (isUp ? 'up' : 'down');
}

async function checkHealth() {
    try {
        var r = await fetch('/api/health');
        var data = await r.json();
        var el = document.getElementById('status');

        var allUp = true;
        var paneNames = ['objects', 'shell', 'inspector', 'events'];
        var downList = [];

        for (var i = 0; i < paneNames.length; i++) {
            var name = paneNames[i];
            var ttyd = data.ttyd && data.ttyd[name];
            var up = ttyd && ttyd.port_open && ttyd.pid_alive;
            updateDot(name, up);
            if (!up) {
                allUp = false;
                downList.push(name);
            }
        }

        if (allUp) {
            el.textContent = 'all panes connected';
            el.style.color = 'var(--green)';
        } else {
            el.textContent = downList.join(', ') + ' down';
            el.style.color = 'var(--orange)';
        }

        // Auto-retry panes that aren't loaded yet
        for (var j = 0; j < paneNames.length; j++) {
            var n = paneNames[j];
            var info = data.ttyd && data.ttyd[n];
            if (info && info.port_open && !PANE_LOADED[n]) {
                loadPane(n);
            }
        }
    } catch(e) {
        // viewer server went away
    }
}

async function init() {
    var ok = await loadConfig();
    if (!ok) return;

    // Attempt to load all panes
    var names = ['objects', 'shell', 'inspector', 'events'];
    for (var i = 0; i < names.length; i++) {
        loadPane(names[i]);
    }

    // Poll health and auto-retry
    checkHealth();
    setInterval(checkHealth, 5000);
}

init();
</script>
</body>
</html>

```
