---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/app.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.068503+00:00
---

# apps/loom-svelte/src/app.css

```css
* { box-sizing: border-box; }

/* Helm v7 cockpit palette — all load-bearing surfaces reference these vars.
   applyThemeToDocument overwrites --color-primary / --color-accent /
   --color-linear / --theme-font-family at runtime per tenant manifest. */
:root {
  color-scheme: dark;
  --void: #0d1014;
  --shell: #14181e;
  --shell-2: #1a1f27;
  --shell-3: #232932;
  --rule: #2a3340;
  --rule-bright: #3a4555;
  --ink: #e7eef5;
  --ink-soft: #aab6c4;
  --ink-faint: #6b7889;
  --activation: #7fd9ff;
  --activation-soft: rgba(127,217,255,0.16);
  --activation-glow: rgba(127,217,255,0.45);
  --hold: #6fd6b5;
  --hold-soft: rgba(111,214,181,0.14);
  --linear: #ffb24a;
  --linear-soft: rgba(255,178,74,0.14);
  --display: "Inter", system-ui, sans-serif;
  --mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  /* tenant-overridable — applyThemeToDocument writes these */
  --color-primary: var(--activation);
  --color-accent: var(--linear);
  --color-linear: var(--linear);
  --theme-font-family: var(--display);
}

/* Light-mode override — applies when applyThemeToDocument resolves
   the operator's `mode` to `light`. */
html[data-mode="light"] {
  color-scheme: light;
  --void: #f0f2f5;
  --shell: #ffffff;
  --shell-2: #f4f6f8;
  --shell-3: #e8ecf0;
  --rule: #d4dae2;
  --rule-bright: #b8c2ce;
  --ink: #18181f;
  --ink-soft: #4a5568;
  --ink-faint: #8896a8;
}
html[data-mode="light"] body {
  background: #f0f2f5;
  color: #18181f;
}
html[data-mode="light"] header {
  border-bottom-color: rgba(0, 0, 0, 0.08);
}

html, body, #app {
  margin: 0;
  padding: 0;
  min-height: 100vh;
}

body {
  background: var(--void);
  color: var(--ink);
  font: 14px/1.6 var(--theme-font-family);
  -webkit-font-smoothing: antialiased;
}

main {
  max-width: 800px;
  margin: 0 auto;
  padding: 0 24px 64px;
}

/* ── Header ───────────────────────────────────────────────── */
header {
  padding: 20px 0 0;
  margin-bottom: 28px;
}

h1 {
  margin: 0 0 4px;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--ink-faint);
  font-family: var(--mono);
}

h2 {
  margin: 0 0 12px;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--ink-faint);
}

/* ── Nav ──────────────────────────────────────────────────── */
nav {
  display: flex;
  gap: 0;
  margin-top: 12px;
  border-bottom: 1px solid var(--rule);
}

nav button {
  background: none;
  border: none;
  border-bottom: 2px solid transparent;
  padding: 8px 14px;
  color: var(--ink-soft);
  font: inherit;
  font-size: 12px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  cursor: pointer;
  transition: color 0.15s, border-color 0.15s;
  margin-bottom: -1px;
}

nav button:hover { color: var(--ink); }

nav button.active {
  color: var(--activation);
  border-bottom-color: var(--activation);
}

/* ── Brand logo ───────────────────────────────────────────── */
/* D-O5.followup-6 — operator-supplied logo from /api/v1/info's
   theme.logo_url. Sits inline alongside the wordmark. */
.brand-logo {
  display: inline-block;
  height: 28px;
  width: auto;
  vertical-align: middle;
  margin-right: 12px;
}

/* ── Hat strip + nav trailing ─────────────────────────────── */
/* D-O5.followup-8 — per-hat indicator strip. */
.hat-strip {
  position: sticky;
  top: 0;
  z-index: 10;
  height: 3px;
  width: 100%;
}

/* D-O5.followup-8 — top-right hat switcher. */
.nav-trailing {
  float: right;
  margin-top: -2.4em;
  display: inline-flex;
  align-items: center;
}

/* ── Tables ───────────────────────────────────────────────── */
table {
  border-collapse: collapse;
  width: 100%;
  font-size: 13px;
}

th {
  text-align: left;
  padding: 6px 10px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--ink-faint);
  border-bottom: 1px solid var(--rule);
  font-family: var(--mono);
}

td {
  padding: 10px 10px;
  border-bottom: 1px solid var(--rule);
  font-family: var(--mono);
  font-size: 12px;
  color: var(--ink-soft);
}

tr:last-child td { border-bottom: none; }
tr:hover td { background: var(--shell-2); color: var(--ink); }
td:first-child { color: var(--activation); }
td:last-child { text-align: right; }

/* ── Cards / panels ───────────────────────────────────────── */
.panel {
  background: var(--shell);
  border: 1px solid var(--rule);
  border-radius: 6px;
  padding: 16px;
  margin-bottom: 16px;
}

.panel + .panel { margin-top: 8px; }

/* ── State chips ──────────────────────────────────────────── */
.state-chip {
  display: inline-block;
  font-family: var(--mono);
  font-size: 10px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  padding: 2px 7px;
  border-radius: 3px;
  border: 1px solid var(--rule);
  background: var(--shell-2);
  color: var(--ink-soft);
}

.state-chip.lead      { border-color: var(--ink-faint); color: var(--ink-soft); }
.state-chip.quoted    { border-color: var(--activation); color: var(--activation); background: var(--activation-soft); }
.state-chip.scheduled { border-color: var(--hold); color: var(--hold); background: var(--hold-soft); }
.state-chip.in_progress { border-color: var(--hold); color: var(--hold); background: var(--hold-soft); }
.state-chip.completed { border-color: var(--linear); color: var(--linear); background: var(--linear-soft); }
.state-chip.invoiced  { border-color: var(--linear); color: var(--linear); background: var(--linear-soft); }
.state-chip.paid      { border-color: var(--hold); color: var(--hold); }
.state-chip.closed    { border-color: var(--rule); color: var(--ink-faint); }

/* ── Live indicator ───────────────────────────────────────── */
/* D-O5.followup-4 — live-tick indicator dot. */
.live-indicator {
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  margin-left: 12px;
  vertical-align: middle;
  background: var(--ink-faint);
}

.live-indicator.live        { background: var(--hold); box-shadow: 0 0 6px var(--hold); }
.live-indicator.reconnecting { background: var(--linear); }
.live-indicator.offline     { background: var(--ink-faint); }

/* ── Links, code, misc ────────────────────────────────────── */
a { color: var(--activation); text-decoration: none; }
a:hover { text-decoration: underline; }

code {
  background: var(--shell-2);
  border: 1px solid var(--rule);
  padding: 1px 5px;
  border-radius: 3px;
  font-family: var(--mono);
  font-size: 11px;
  color: var(--ink-soft);
}

.muted { color: var(--ink-faint); font-size: 12px; }

.sub {
  margin: 0;
  color: var(--ink-faint);
}

.empty {
  padding: 24px;
  background: var(--shell);
  border: 1px solid var(--rule);
  border-radius: 6px;
  color: var(--ink-faint);
  font-size: 13px;
  font-family: var(--mono);
  text-align: center;
}

footer {
  margin-top: 48px;
  padding-top: 16px;
  border-top: 1px solid var(--rule);
  color: var(--ink-faint);
  font-size: 12px;
  font-family: var(--mono);
}

footer a { color: var(--activation); }

section { margin-bottom: 32px; }

dl {
  display: grid;
  grid-template-columns: max-content 1fr;
  gap: 6px 16px;
  margin: 0;
}

dt { color: var(--ink-soft); font-family: var(--mono); font-size: 12px; }
dd { margin: 0; font-family: var(--mono); font-size: 12px; color: var(--ink); }

ul.tree {
  list-style: none;
  padding-left: 0;
  margin: 0;
}

ul.tree > li {
  padding: 8px 0;
  border-bottom: 1px solid var(--rule);
}

ul.tree ul {
  margin: 8px 0 0 16px;
  padding-left: 16px;
  border-left: 1px solid var(--rule-bright);
  list-style: none;
}

```
