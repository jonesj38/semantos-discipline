---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/app.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.608576+00:00
---

# cartridges/jambox/web/src/svelte/app.css

```css
/* ============================================================
   jam-room — studio-warm meets hardware
   ============================================================ */

@import url('https://fonts.googleapis.com/css2?family=Geist:wght@300;400;500;600;700;800&family=Geist+Mono:wght@400;500;600;700&family=Instrument+Serif:ital@0;1&display=swap');

:root {
  /* Base palette — deep space-ink, warm paper */
  --ink-0: #08090c;
  --ink-1: #0d0f14;
  --ink-2: #14171f;
  --ink-3: #1c2029;
  --ink-4: #262b37;
  --line:  #2a2f3c;
  --line-2:#3a4051;
  --paper: #efead8;
  --paper-2:#cdc8b8;
  --muted: #8a8676;
  --muted-2:#5e5b50;

  /* Brass / brand accent */
  --brass: #d4a655;
  --brass-bright: #f1c876;
  --brass-deep: #8a6b2e;

  /* Functional */
  --record: #ef4d6a;
  --live:   #6cdc9a;
  --warn:   #ffb347;

  /* Theme accent (tweakable) */
  --accent: var(--brass);
  --accent-bright: var(--brass-bright);

  /* Boomwhacker scale palette (12 hues, hsl) */
  --pc-0:  hsl(  0 78% 56%);
  --pc-1:  hsl( 14 75% 56%);
  --pc-2:  hsl( 30 82% 56%);
  --pc-3:  hsl( 44 78% 56%);
  --pc-4:  hsl( 56 80% 56%);
  --pc-5:  hsl(132 60% 50%);
  --pc-6:  hsl(168 60% 48%);
  --pc-7:  hsl(190 70% 52%);
  --pc-8:  hsl(208 65% 55%);
  --pc-9:  hsl(228 60% 60%);
  --pc-10: hsl(258 50% 60%);
  --pc-11: hsl(282 55% 58%);

  /* Density */
  --d-pad: 56px;
  --d-gap: 6px;
  --d-radius: 10px;

  /* Typography */
  --f-display: 'Instrument Serif', 'Times New Roman', serif;
  --f-ui: 'Geist', system-ui, sans-serif;
  --f-mono: 'Geist Mono', ui-monospace, Menlo, monospace;
}

[data-density="cosy"]    { --d-pad: 64px; --d-gap: 8px; }
[data-density="standard"]{ --d-pad: 56px; --d-gap: 6px; }
[data-density="compact"] { --d-pad: 44px; --d-gap: 4px; }

[data-accent="cyan"]    { --accent: hsl(190 80% 60%); --accent-bright: hsl(190 95% 72%); }
[data-accent="amber"]   { --accent: var(--brass); --accent-bright: var(--brass-bright); }
[data-accent="magenta"] { --accent: hsl(330 75% 62%); --accent-bright: hsl(330 90% 75%); }
[data-accent="lime"]    { --accent: hsl(80 65% 56%); --accent-bright: hsl(80 80% 70%); }

[data-aesthetic="hardware"] {
  --ink-0: #050608; --ink-1: #0a0b0f; --ink-2: #11131a;
  --paper: #e8e2d0;
  --d-radius: 6px;
}
[data-aesthetic="studio-warm"] {
  --ink-0: #0e0c08; --ink-1: #15120c; --ink-2: #1d1810;
  --line: #2a2418; --paper: #f5efe0;
}
[data-aesthetic="playful"] {
  --ink-0: #0c0a14; --ink-1: #131124; --ink-2: #1d1a30;
  --paper: #fff8e7;
  --d-radius: 16px;
}

* { box-sizing: border-box; }
html, body {
  margin: 0; padding: 0;
  background: var(--ink-0);
  color: var(--paper);
  font-family: var(--f-ui);
  font-size: 13px;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

body {
  min-height: 100vh;
  background:
    radial-gradient(ellipse 1200px 600px at 50% -10%, rgba(212,166,85,0.06), transparent 60%),
    radial-gradient(ellipse 800px 400px at 80% 110%, rgba(108,220,154,0.03), transparent 60%),
    var(--ink-0);
}

button { font-family: inherit; color: inherit; cursor: pointer; }

::-webkit-scrollbar { width: 10px; height: 10px; }
::-webkit-scrollbar-track { background: var(--ink-1); }
::-webkit-scrollbar-thumb { background: var(--line-2); border-radius: 4px; }
::-webkit-scrollbar-thumb:hover { background: var(--muted-2); }

```
