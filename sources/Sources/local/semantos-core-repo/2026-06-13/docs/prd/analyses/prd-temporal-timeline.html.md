---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/analyses/prd-temporal-timeline.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.763925+00:00
---

# docs/prd/analyses/prd-temporal-timeline.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Semantos Temporal Analysis — Concept Timeline</title>
<style>
:root {
  --bg:#0a0e17; --bg2:#111827; --bg3:#1f2937;
  --text:#e5e7eb; --text2:#9ca3af;
  --shomee:#f87171; --seed:#fbbf24; --core:#34d399;
  --accent:#60a5fa; --purple:#a78bfa; --pink:#f472b6; --cyan:#22d3ee;
}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'SF Mono','Fira Code',monospace;background:var(--bg);color:var(--text);overflow-x:hidden}

.header{padding:28px 40px 20px;border-bottom:1px solid var(--bg3)}
.header h1{font-size:22px;font-weight:700;margin-bottom:6px}
.header .sub{color:var(--text2);font-size:12px;line-height:1.5;max-width:900px}

nav{display:flex;gap:4px;padding:10px 40px;background:var(--bg2);border-bottom:1px solid var(--bg3)}
nav button{background:transparent;border:1px solid transparent;color:var(--text2);padding:7px 14px;border-radius:6px;cursor:pointer;font-family:inherit;font-size:12px;white-space:nowrap;transition:all .15s}
nav button:hover{color:var(--text);background:var(--bg3)}
nav button.active{color:var(--accent);background:rgba(96,165,250,.1);border-color:rgba(96,165,250,.3)}

.content{padding:20px 40px 60px}
.panel{display:none}.panel.active{display:block}
.section-title{font-size:15px;font-weight:600;margin:20px 0 6px}
.section-desc{font-size:12px;color:var(--text2);margin-bottom:14px;line-height:1.5;max-width:800px}

.chart-container{position:relative;width:100%;background:var(--bg2);border:1px solid var(--bg3);border-radius:8px;overflow:hidden;margin-bottom:20px}
.chart-container canvas{width:100%;display:block}

.controls{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px}
.controls button{background:var(--bg2);border:1px solid var(--bg3);color:var(--text2);padding:4px 10px;border-radius:4px;cursor:pointer;font-family:inherit;font-size:11px;transition:all .15s}
.controls button:hover{border-color:var(--accent);color:var(--text)}
.controls button.on{background:rgba(96,165,250,.15);border-color:var(--accent);color:var(--accent)}

.crossover-list{margin-bottom:20px}
.crossover{display:flex;align-items:center;gap:12px;padding:10px 16px;background:var(--bg2);border:1px solid var(--bg3);border-radius:6px;margin-bottom:5px;font-size:12px}
.crossover .date{min-width:90px;font-weight:600;color:var(--accent)}
.crossover .from{color:var(--shomee)}
.crossover .to{color:var(--core)}
.crossover .arrow{color:var(--text2)}

.burst-list{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:8px;margin-bottom:20px}
.burst{background:var(--bg2);border:1px solid var(--bg3);border-radius:6px;padding:10px 14px;font-size:12px}
.burst .concept{font-weight:600;color:var(--accent)}
.burst .factor{color:var(--shomee);font-weight:700}

.legend{position:absolute;top:10px;right:14px;background:rgba(10,14,23,.92);padding:8px 12px;border-radius:6px;font-size:10px;line-height:1.8;z-index:10}
.legend .swatch{display:inline-block;width:12px;height:3px;border-radius:1px;margin-right:6px;vertical-align:middle}

.tooltip{position:fixed;background:var(--bg3);border:1px solid var(--accent);border-radius:6px;padding:8px 12px;font-size:11px;max-width:300px;pointer-events:none;z-index:1000;display:none;line-height:1.5}
</style>
</head>
<body>

<div class="header">
  <h1>Temporal Concept Timeline — Git-Timestamped</h1>
  <div class="sub">
    Every markdown file placed on the calendar by its git commit date. Concept mentions aggregated weekly.
    The gap between June 2025 and March 2026 is the 9-month dark period between shomee-alpha and semantos-core.
    Crossover events mark the exact week when one concept overtook another.
  </div>
</div>

<nav id="nav"></nav>
<div class="content">
  <div id="panel-timeline" class="panel active"></div>
  <div id="panel-crossovers" class="panel"></div>
  <div id="panel-bursts" class="panel"></div>
  <div id="panel-peaks" class="panel"></div>
</div>
<div class="tooltip" id="tooltip"></div>

<script>
const D = {"timeline": {"start": "2025-04-21", "end": "2026-04-13", "weeks": 12, "dates": ["2025-04-21", "2025-04-28", "2025-05-05", "2025-05-12", "2025-05-19", "2025-05-26", "2025-06-02", "2025-06-09", "2026-03-23", "2026-03-30", "2026-04-06", "2026-04-13"]}, "concept_series": {"2pda": {"description": "dual-stack pushdown automaton", "total": 106, "first_seen": "2025-06-02", "last_seen": "2026-04-13", "peak_date": "2026-03-23", "peak_value": 48, "weekly_values": [0, 0, 0, 0, 0, 0, 1, 0, 48, 10, 2, 45]}, "6lowpan": {"description": "6LoWPAN IoT", "total": 45, "first_seen": "2025-05-12", "last_seen": "2026-04-13", "peak_date": "2026-04-06", "peak_value": 20, "weekly_values": [0, 0, 0, 9, 0, 0, 0, 0, 1, 1, 20, 14]}, "adapter": {"description": "adapter interface pattern", "total": 9152, "first_seen": "2025-04-28", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 4530, "weekly_values": [0, 21, 12, 331, 141, 194, 346, 25, 125, 885, 2542, 4530]}, "affine": {"description": "AFFINE substructural type", "total": 1641, "first_seen": "2025-05-12", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 840, "weekly_values": [0, 0, 0, 14, 0, 0, 0, 0, 303, 250, 234, 840]}, "anchor": {"description": "blockchain anchoring", "total": 3670, "first_seen": "2025-04-28", "last_seen": "2026-04-13", "peak_date": "2026-04-06", "peak_value": 1494, "weekly_values": [0, 8, 52, 111, 94, 255, 226, 12, 177, 88, 1494, 1153]}, "axiom": {"description": "axiom compilation", "total": 455, "first_seen": "2026-03-23", "last_seen": "2026-04-13", "peak_date": "2026-03-23", "peak_value": 179, "weekly_values": [0, 0, 0, 0, 0, 0, 0, 0, 179, 114, 27, 135]}, "bca": {"description": "Bitcoin-Certified Address", "total": 1966, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-03-23", "peak_value": 528, "weekly_values": [36, 7, 23, 22, 4, 500, 106, 0, 528, 137, 322, 281]}, "beef": {"description": "BEEF transaction format", "total": 7149, "first_seen": "2025-05-05", "last_seen": "2026-04-13", "peak_date": "2025-06-02", "peak_value": 2572, "weekly_values": [0, 0, 4, 1009, 22, 2471, 2572, 208, 651, 91, 65, 56]}, "bitcoin": {"description": "Bitcoin", "total": 3859, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2025-06-02", "peak_value": 1476, "weekly_values": [6, 5, 8, 293, 67, 1446, 1476, 58, 208, 97, 44, 151]}, "bsv": {"description": "Bitcoin SV", "total": 3890, "first_seen": "2025-04-28", "last_seen": "2026-04-13", "peak_date": "2026-03-23", "peak_value": 760, "weekly_values": [0, 3, 149, 383, 32, 572, 651, 107, 760, 145, 632, 456]}, "capability": {"description": "capability token", "total": 6373, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 3406, "weekly_values": [6, 6, 9, 110, 151, 352, 91, 58, 498, 1149, 537, 3406]}, "cell": {"description": "cell primitive", "total": 12645, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 4245, "weekly_values": [5, 0, 2, 1, 2, 45, 111, 13, 3680, 2033, 2508, 4245]}, "certgraph": {"description": "certificate graph", "total": 2054, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2025-05-12", "peak_value": 613, "weekly_values": [1, 24, 31, 613, 352, 463, 496, 16, 9, 13, 0, 36]}, "certificate": {"description": "identity certificate", "total": 12481, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2025-05-12", "peak_value": 4058, "weekly_values": [6, 14, 145, 4058, 747, 2745, 3456, 772, 55, 126, 77, 280]}, "civ-stack": {"description": "civ-stack prefix", "total": 19913, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2025-05-19", "peak_value": 8223, "weekly_values": [4, 0, 77, 6838, 8223, 3303, 796, 99, 106, 106, 14, 347]}, "compression": {"description": "compression concept", "total": 384, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2025-05-12", "peak_value": 139, "weekly_values": [2, 0, 0, 139, 5, 33, 5, 6, 7, 35, 26, 126]}, "consolidation": {"description": "consolidation process", "total": 437, "first_seen": "2025-04-21", "last_seen": "2025-06-02", "peak_date": "2025-06-02", "peak_value": 217, "weekly_values": [1, 0, 0, 122, 1, 96, 217, 0, 0, 0, 0, 0]}, "container": {"description": "container abstraction", "total": 24063, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2025-06-02", "peak_value": 11057, "weekly_values": [70, 46, 123, 1158, 3083, 7663, 11057, 520, 54, 56, 56, 177]}, "daemon": {"description": "daemon process", "total": 3168, "first_seen": "2025-05-05", "last_seen": "2026-04-13", "peak_date": "2025-05-26", "peak_value": 1979, "weekly_values": [0, 0, 4, 35, 63, 1979, 1080, 0, 0, 0, 2, 5]}, "dependency injection": {"description": "DI pattern", "total": 517, "first_seen": "2025-04-28", "last_seen": "2025-06-09", "peak_date": "2025-05-12", "peak_value": 168, "weekly_values": [0, 1, 2, 168, 147, 96, 102, 1, 0, 0, 0, 0]}, "docker": {"description": "Docker deployment", "total": 1093, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-06", "peak_value": 392, "weekly_values": [26, 1, 56, 9, 3, 68, 223, 2, 17, 48, 392, 248]}, "evidence": {"description": "evidence chain", "total": 2484, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 1493, "weekly_values": [1, 0, 0, 19, 5, 18, 41, 1, 306, 382, 218, 1493]}, "extension": {"description": "extension system", "total": 9460, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 5149, "weekly_values": [9, 21, 10, 191, 17, 593, 467, 16, 397, 864, 1726, 5149]}, "factory": {"description": "factory pattern", "total": 9343, "first_seen": "2025-05-05", "last_seen": "2026-04-13", "peak_date": "2025-06-02", "peak_value": 6982, "weekly_values": [0, 0, 7, 557, 497, 695, 6982, 299, 34, 41, 59, 172]}, "ffi": {"description": "foreign function interface", "total": 3109, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 1023, "weekly_values": [39, 1, 27, 98, 25, 217, 194, 10, 435, 296, 744, 1023]}, "flow": {"description": "conversation flow", "total": 8366, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 3598, "weekly_values": [74, 10, 199, 176, 201, 727, 714, 181, 640, 1416, 430, 3598]}, "forth": {"description": "Forth execution layer", "total": 1000, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-03-23", "peak_value": 386, "weekly_values": [1, 0, 18, 44, 0, 38, 0, 0, 386, 264, 40, 209]}, "gip": {"description": "identity model", "total": 2042, "first_seen": "2025-04-28", "last_seen": "2026-04-13", "peak_date": "2025-05-26", "peak_value": 636, "weekly_values": [0, 49, 190, 272, 71, 636, 342, 208, 48, 67, 4, 155]}, "governance": {"description": "governance system", "total": 6251, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 2424, "weekly_values": [4, 0, 22, 90, 459, 1473, 708, 34, 201, 489, 347, 2424]}, "grammar": {"description": "domain grammar", "total": 5121, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 3361, "weekly_values": [8, 16, 5, 61, 11, 225, 8, 0, 3, 43, 1380, 3361]}, "hypervisor": {"description": "hypervisor layer", "total": 866, "first_seen": "2025-05-19", "last_seen": "2026-04-13", "peak_date": "2025-05-26", "peak_value": 415, "weekly_values": [0, 0, 0, 0, 376, 415, 36, 15, 0, 8, 0, 16]}, "identity": {"description": "identity system", "total": 12254, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 4633, "weekly_values": [3, 43, 244, 2252, 485, 1065, 391, 258, 441, 1345, 1094, 4633]}, "intent": {"description": "intent classification", "total": 7063, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2025-05-26", "peak_value": 2544, "weekly_values": [4, 2, 32, 179, 218, 2544, 1379, 140, 233, 713, 85, 1534]}, "kernel": {"description": "kernel layer", "total": 5598, "first_seen": "2025-05-05", "last_seen": "2026-04-13", "peak_date": "2026-03-23", "peak_value": 1223, "weekly_values": [0, 0, 5, 157, 63, 1057, 714, 256, 1223, 303, 809, 1011]}, "linear": {"description": "LINEAR substructural type", "total": 6593, "first_seen": "2025-05-26", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 2504, "weekly_values": [0, 0, 0, 0, 0, 2, 22, 1, 2041, 979, 1044, 2504]}, "linearity": {"description": "linearity enforcement", "total": 3642, "first_seen": "2026-03-23", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 1330, "weekly_values": [0, 0, 0, 0, 0, 0, 0, 0, 1271, 539, 502, 1330]}, "lisp": {"description": "Lisp axiom layer", "total": 2026, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 952, "weekly_values": [10, 0, 32, 8, 13, 26, 1, 0, 31, 483, 470, 952]}, "mandala": {"description": "mandala architecture", "total": 942, "first_seen": "2025-05-19", "last_seen": "2025-06-02", "peak_date": "2025-06-02", "peak_value": 558, "weekly_values": [0, 0, 0, 0, 9, 375, 558, 0, 0, 0, 0, 0]}, "mesh": {"description": "mesh network", "total": 393, "first_seen": "2025-05-12", "last_seen": "2026-04-13", "peak_date": "2026-04-06", "peak_value": 149, "weekly_values": [0, 0, 0, 72, 61, 4, 4, 0, 12, 6, 149, 85]}, "migration": {"description": "migration process", "total": 2403, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2025-06-02", "peak_value": 707, "weekly_values": [14, 3, 166, 418, 170, 702, 707, 32, 9, 16, 55, 111]}, "node": {"description": "sovereign node", "total": 7491, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 2694, "weekly_values": [9, 6, 210, 415, 442, 430, 552, 38, 227, 657, 1811, 2694]}, "opcodes": {"description": "instruction set", "total": 1174, "first_seen": "2025-05-26", "last_seen": "2026-04-13", "peak_date": "2026-03-23", "peak_value": 532, "weekly_values": [0, 0, 0, 0, 0, 58, 6, 0, 532, 107, 174, 297]}, "paskian": {"description": "Paskian learning", "total": 279, "first_seen": "2026-04-06", "last_seen": "2026-04-13", "peak_date": "2026-04-06", "peak_value": 144, "weekly_values": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 144, 135]}, "patch": {"description": "state patch", "total": 8178, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 2646, "weekly_values": [59, 62, 478, 196, 602, 1397, 1043, 162, 276, 632, 625, 2646]}, "pike": {"description": "Pike protocol", "total": 1497, "first_seen": "2025-05-05", "last_seen": "2026-04-13", "peak_date": "2025-05-19", "peak_value": 651, "weekly_values": [0, 0, 9, 225, 651, 455, 85, 9, 11, 11, 5, 36]}, "plexus": {"description": "Plexus overlay", "total": 8520, "first_seen": "2026-03-23", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 5237, "weekly_values": [0, 0, 0, 0, 0, 0, 0, 0, 835, 2003, 445, 5237]}, "pubstream": {"description": "publication stream", "total": 702, "first_seen": "2025-04-28", "last_seen": "2025-05-26", "peak_date": "2025-05-12", "peak_value": 377, "weekly_values": [0, 13, 15, 377, 202, 95, 0, 0, 0, 0, 0, 0]}, "relevant": {"description": "RELEVANT substructural type", "total": 2402, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 1194, "weekly_values": [14, 6, 49, 32, 9, 30, 8, 0, 362, 307, 391, 1194]}, "reputation": {"description": "reputation system", "total": 541, "first_seen": "2025-05-05", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 307, "weekly_values": [0, 0, 1, 1, 0, 20, 4, 0, 78, 122, 8, 307]}, "semantic object": {"description": "semantic object", "total": 1222, "first_seen": "2025-05-26", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 675, "weekly_values": [0, 0, 0, 0, 0, 3, 1, 0, 151, 238, 154, 675]}, "semantic seed": {"description": "semantic seed core", "total": 216, "first_seen": "2025-05-12", "last_seen": "2025-06-09", "peak_date": "2025-06-02", "peak_value": 107, "weekly_values": [0, 0, 0, 10, 4, 94, 107, 1, 0, 0, 0, 0]}, "semantic shell": {"description": "semantic shell", "total": 292, "first_seen": "2025-05-05", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 134, "weekly_values": [0, 0, 1, 33, 6, 23, 2, 0, 13, 69, 11, 134]}, "shellbus": {"description": "shell bus", "total": 2811, "first_seen": "2025-04-21", "last_seen": "2025-06-02", "peak_date": "2025-05-12", "peak_value": 1192, "weekly_values": [44, 53, 136, 1192, 746, 600, 40, 0, 0, 0, 0, 0]}, "sosp": {"description": "SOSP protocol", "total": 1934, "first_seen": "2025-05-12", "last_seen": "2025-06-09", "peak_date": "2025-06-02", "peak_value": 1440, "weekly_values": [0, 0, 0, 10, 4, 440, 1440, 40, 0, 0, 0, 0]}, "sr6": {"description": "SR6 routing", "total": 335, "first_seen": "2025-05-12", "last_seen": "2026-04-13", "peak_date": "2025-05-12", "peak_value": 136, "weekly_values": [0, 0, 0, 136, 125, 34, 0, 0, 7, 7, 2, 24]}, "srv6": {"description": "SRv6 segment routing", "total": 819, "first_seen": "2025-05-12", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 274, "weekly_values": [0, 0, 0, 220, 12, 36, 0, 0, 11, 10, 256, 274]}, "tauri": {"description": "Tauri desktop", "total": 241, "first_seen": "2025-06-09", "last_seen": "2026-03-30", "peak_date": "2025-06-09", "peak_value": 226, "weekly_values": [0, 0, 0, 0, 0, 0, 0, 226, 10, 5, 0, 0]}, "taxonomy": {"description": "type taxonomy", "total": 4308, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 2592, "weekly_values": [1, 0, 8, 0, 0, 7, 0, 0, 235, 832, 633, 2592]}, "trades": {"description": "trades vertical", "total": 1808, "first_seen": "2025-05-05", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 1081, "weekly_values": [0, 0, 4, 0, 0, 0, 0, 0, 98, 435, 190, 1081]}, "transaction": {"description": "transaction", "total": 11294, "first_seen": "2025-04-21", "last_seen": "2026-04-13", "peak_date": "2025-06-02", "peak_value": 4465, "weekly_values": [1, 4, 49, 1977, 388, 3186, 4465, 307, 284, 171, 149, 313]}, "vertical": {"description": "vertical domain", "total": 4454, "first_seen": "2025-05-19", "last_seen": "2026-04-13", "peak_date": "2026-04-13", "peak_value": 2666, "weekly_values": [0, 0, 0, 0, 1, 0, 0, 0, 18, 8, 1761, 2666]}, "wallet": {"description": "wallet system", "total": 12787, "first_seen": "2025-04-28", "last_seen": "2026-04-13", "peak_date": "2025-06-02", "peak_value": 5205, "weekly_values": [0, 12, 279, 4560, 241, 1495, 5205, 438, 142, 127, 102, 186]}, "wasm": {"description": "WebAssembly", "total": 3096, "first_seen": "2025-05-05", "last_seen": "2026-04-13", "peak_date": "2026-03-23", "peak_value": 1636, "weekly_values": [0, 0, 3, 0, 0, 21, 2, 3, 1636, 416, 478, 537]}}, "crossovers": {"container vs cell": [{"date": "2026-03-23", "from_leader": "container", "to_leader": "cell", "val_a": 54, "val_b": 3680}], "container vs semantic object": [{"date": "2026-03-23", "from_leader": "container", "to_leader": "semantic object", "val_a": 54, "val_b": 151}], "factory vs adapter": [{"date": "2025-05-12", "from_leader": "adapter", "to_leader": "factory", "val_a": 557, "val_b": 331}, {"date": "2026-03-23", "from_leader": "factory", "to_leader": "adapter", "val_a": 34, "val_b": 125}], "dependency injection vs adapter": [{"date": "2025-05-19", "from_leader": "adapter", "to_leader": "dependency injection", "val_a": 147, "val_b": 141}, {"date": "2025-05-26", "from_leader": "dependency injection", "to_leader": "adapter", "val_a": 96, "val_b": 194}], "civ-stack vs extension": [{"date": "2025-05-05", "from_leader": "extension", "to_leader": "civ-stack", "val_a": 77, "val_b": 10}, {"date": "2026-03-23", "from_leader": "civ-stack", "to_leader": "extension", "val_a": 106, "val_b": 397}], "daemon vs kernel": [{"date": "2025-06-09", "from_leader": "daemon", "to_leader": "kernel", "val_a": 0, "val_b": 256}], "wallet vs anchor": [{"date": "2026-03-23", "from_leader": "wallet", "to_leader": "anchor", "val_a": 142, "val_b": 177}, {"date": "2026-03-30", "from_leader": "anchor", "to_leader": "wallet", "val_a": 127, "val_b": 88}, {"date": "2026-04-06", "from_leader": "wallet", "to_leader": "anchor", "val_a": 102, "val_b": 1494}], "certificate vs identity": [{"date": "2025-04-28", "from_leader": "certificate", "to_leader": "identity", "val_a": 14, "val_b": 43}, {"date": "2025-05-12", "from_leader": "identity", "to_leader": "certificate", "val_a": 4058, "val_b": 2252}, {"date": "2026-03-23", "from_leader": "certificate", "to_leader": "identity", "val_a": 55, "val_b": 441}], "sosp vs taxonomy": [{"date": "2025-05-12", "from_leader": "taxonomy", "to_leader": "sosp", "val_a": 10, "val_b": 0}, {"date": "2026-03-23", "from_leader": "sosp", "to_leader": "taxonomy", "val_a": 0, "val_b": 235}], "pike vs plexus": [{"date": "2026-03-23", "from_leader": "pike", "to_leader": "plexus", "val_a": 11, "val_b": 835}], "mandala vs cell": [{"date": "2025-05-19", "from_leader": "cell", "to_leader": "mandala", "val_a": 9, "val_b": 2}, {"date": "2025-06-09", "from_leader": "mandala", "to_leader": "cell", "val_a": 0, "val_b": 13}], "consolidation vs linear": [{"date": "2025-06-09", "from_leader": "consolidation", "to_leader": "linear", "val_a": 0, "val_b": 1}]}, "bursts": {"2pda": [{"date": "2026-03-23", "value": 48, "prev_avg": 0.2, "factor": 192.0}], "6lowpan": [{"date": "2025-05-12", "value": 9, "prev_avg": 0.0, "factor": 90.0}, {"date": "2026-04-06", "value": 20, "prev_avg": 0.5, "factor": 40.0}], "adapter": [{"date": "2025-05-12", "value": 331, "prev_avg": 11.0, "factor": 30.1}, {"date": "2026-03-30", "value": 885, "prev_avg": 172.5, "factor": 5.1}, {"date": "2026-04-06", "value": 2542, "prev_avg": 345.2, "factor": 7.4}, {"date": "2026-04-13", "value": 4530, "prev_avg": 894.2, "factor": 5.1}], "affine": [{"date": "2025-05-12", "value": 14, "prev_avg": 0.0, "factor": 140.0}, {"date": "2026-03-23", "value": 303, "prev_avg": 0.0, "factor": 3030.0}, {"date": "2026-03-30", "value": 250, "prev_avg": 75.8, "factor": 3.3}, {"date": "2026-04-13", "value": 840, "prev_avg": 196.8, "factor": 4.3}], "anchor": [{"date": "2025-05-05", "value": 52, "prev_avg": 4.0, "factor": 13.0}, {"date": "2025-05-12", "value": 111, "prev_avg": 20.0, "factor": 5.6}, {"date": "2025-05-26", "value": 255, "prev_avg": 66.2, "factor": 3.8}, {"date": "2026-04-06", "value": 1494, "prev_avg": 125.8, "factor": 11.9}], "axiom": [{"date": "2026-03-23", "value": 179, "prev_avg": 0.0, "factor": 1790.0}], "bca": [{"date": "2025-05-26", "value": 500, "prev_avg": 14.0, "factor": 35.7}, {"date": "2026-03-23", "value": 528, "prev_avg": 152.5, "factor": 3.5}], "beef": [{"date": "2025-05-12", "value": 1009, "prev_avg": 1.3, "factor": 756.8}, {"date": "2025-05-26", "value": 2471, "prev_avg": 258.8, "factor": 9.5}], "bitcoin": [{"date": "2025-05-12", "value": 293, "prev_avg": 6.3, "factor": 46.3}, {"date": "2025-05-26", "value": 1446, "prev_avg": 93.2, "factor": 15.5}, {"date": "2025-06-02", "value": 1476, "prev_avg": 453.5, "factor": 3.3}], "bsv": [{"date": "2025-05-05", "value": 149, "prev_avg": 1.5, "factor": 99.3}, {"date": "2025-05-12", "value": 383, "prev_avg": 50.7, "factor": 7.6}, {"date": "2025-05-26", "value": 572, "prev_avg": 141.8, "factor": 4.0}], "capability": [{"date": "2025-05-12", "value": 110, "prev_avg": 7.0, "factor": 15.7}, {"date": "2025-05-19", "value": 151, "prev_avg": 32.8, "factor": 4.6}, {"date": "2025-05-26", "value": 352, "prev_avg": 69.0, "factor": 5.1}, {"date": "2026-03-23", "value": 498, "prev_avg": 163.0, "factor": 3.1}, {"date": "2026-03-30", "value": 1149, "prev_avg": 249.8, "factor": 4.6}], "cell": [{"date": "2025-05-26", "value": 45, "prev_avg": 1.2, "factor": 36.0}, {"date": "2025-06-02", "value": 111, "prev_avg": 12.5, "factor": 8.9}, {"date": "2026-03-23", "value": 3680, "prev_avg": 42.8, "factor": 86.1}], "certgraph": [{"date": "2025-05-12", "value": 613, "prev_avg": 18.7, "factor": 32.8}, {"date": "2026-04-13", "value": 36, "prev_avg": 9.5, "factor": 3.8}], "certificate": [{"date": "2025-05-05", "value": 145, "prev_avg": 10.0, "factor": 14.5}, {"date": "2025-05-12", "value": 4058, "prev_avg": 55.0, "factor": 73.8}], "civ-stack": [{"date": "2025-05-05", "value": 77, "prev_avg": 2.0, "factor": 38.5}, {"date": "2025-05-12", "value": 6838, "prev_avg": 27.0, "factor": 253.3}, {"date": "2025-05-19", "value": 8223, "prev_avg": 1729.8, "factor": 4.8}, {"date": "2026-04-13", "value": 347, "prev_avg": 81.2, "factor": 4.3}], "compression": [{"date": "2025-05-12", "value": 139, "prev_avg": 0.7, "factor": 208.5}, {"date": "2026-04-13", "value": 126, "prev_avg": 18.5, "factor": 6.8}], "consolidation": [{"date": "2025-05-12", "value": 122, "prev_avg": 0.3, "factor": 366.0}, {"date": "2025-05-26", "value": 96, "prev_avg": 30.8, "factor": 3.1}, {"date": "2025-06-02", "value": 217, "prev_avg": 54.8, "factor": 4.0}], "container": [{"date": "2025-05-12", "value": 1158, "prev_avg": 79.7, "factor": 14.5}, {"date": "2025-05-19", "value": 3083, "prev_avg": 349.2, "factor": 8.8}, {"date": "2025-05-26", "value": 7663, "prev_avg": 1102.5, "factor": 7.0}, {"date": "2025-06-02", "value": 11057, "prev_avg": 3006.8, "factor": 3.7}], "daemon": [{"date": "2025-05-12", "value": 35, "prev_avg": 1.3, "factor": 26.2}, {"date": "2025-05-19", "value": 63, "prev_avg": 9.8, "factor": 6.5}, {"date": "2025-05-26", "value": 1979, "prev_avg": 25.5, "factor": 77.6}], "dependency injection": [{"date": "2025-05-12", "value": 168, "prev_avg": 1.0, "factor": 168.0}, {"date": "2025-05-19", "value": 147, "prev_avg": 42.8, "factor": 3.4}], "docker": [{"date": "2025-05-05", "value": 56, "prev_avg": 13.5, "factor": 4.1}, {"date": "2025-05-26", "value": 68, "prev_avg": 17.2, "factor": 3.9}, {"date": "2025-06-02", "value": 223, "prev_avg": 34.0, "factor": 6.6}, {"date": "2026-04-06", "value": 392, "prev_avg": 72.5, "factor": 5.4}], "evidence": [{"date": "2025-05-12", "value": 19, "prev_avg": 0.3, "factor": 57.0}, {"date": "2025-06-02", "value": 41, "prev_avg": 10.5, "factor": 3.9}, {"date": "2026-03-23", "value": 306, "prev_avg": 16.2, "factor": 18.8}, {"date": "2026-03-30", "value": 382, "prev_avg": 91.5, "factor": 4.2}, {"date": "2026-04-13", "value": 1493, "prev_avg": 226.8, "factor": 6.6}], "extension": [{"date": "2025-05-12", "value": 191, "prev_avg": 13.3, "factor": 14.3}, {"date": "2025-05-26", "value": 593, "prev_avg": 59.8, "factor": 9.9}, {"date": "2026-04-06", "value": 1726, "prev_avg": 436.0, "factor": 4.0}, {"date": "2026-04-13", "value": 5149, "prev_avg": 750.8, "factor": 6.9}], "factory": [{"date": "2025-05-05", "value": 7, "prev_avg": 0.0, "factor": 70.0}, {"date": "2025-05-12", "value": 557, "prev_avg": 2.3, "factor": 238.7}, {"date": "2025-05-19", "value": 497, "prev_avg": 141.0, "factor": 3.5}, {"date": "2025-06-02", "value": 6982, "prev_avg": 439.0, "factor": 15.9}], "ffi": [{"date": "2025-05-12", "value": 98, "prev_avg": 22.3, "factor": 4.4}, {"date": "2025-05-26", "value": 217, "prev_avg": 37.8, "factor": 5.7}, {"date": "2026-03-23", "value": 435, "prev_avg": 111.5, "factor": 3.9}, {"date": "2026-04-06", "value": 744, "prev_avg": 233.8, "factor": 3.2}], "flow": [{"date": "2025-05-05", "value": 199, "prev_avg": 42.0, "factor": 4.7}, {"date": "2025-05-26", "value": 727, "prev_avg": 146.5, "factor": 5.0}, {"date": "2026-04-13", "value": 3598, "prev_avg": 666.8, "factor": 5.4}], "forth": [{"date": "2025-05-05", "value": 18, "prev_avg": 0.5, "factor": 36.0}, {"date": "2025-05-12", "value": 44, "prev_avg": 6.3, "factor": 6.9}, {"date": "2026-03-23", "value": 386, "prev_avg": 9.5, "factor": 40.6}], "gip": [{"date": "2025-05-05", "value": 190, "prev_avg": 24.5, "factor": 7.8}, {"date": "2025-05-12", "value": 272, "prev_avg": 79.7, "factor": 3.4}, {"date": "2025-05-26", "value": 636, "prev_avg": 145.5, "factor": 4.4}], "governance": [{"date": "2025-05-05", "value": 22, "prev_avg": 2.0, "factor": 11.0}, {"date": "2025-05-12", "value": 90, "prev_avg": 8.7, "factor": 10.4}, {"date": "2025-05-19", "value": 459, "prev_avg": 29.0, "factor": 15.8}, {"date": "2025-05-26", "value": 1473, "prev_avg": 142.8, "factor": 10.3}, {"date": "2026-04-13", "value": 2424, "prev_avg": 267.8, "factor": 9.1}], "grammar": [{"date": "2025-05-12", "value": 61, "prev_avg": 9.7, "factor": 6.3}, {"date": "2025-05-26", "value": 225, "prev_avg": 23.2, "factor": 9.7}, {"date": "2026-04-06", "value": 1380, "prev_avg": 13.5, "factor": 102.2}, {"date": "2026-04-13", "value": 3361, "prev_avg": 356.5, "factor": 9.4}], "hypervisor": [{"date": "2025-05-19", "value": 376, "prev_avg": 0.0, "factor": 3760.0}, {"date": "2025-05-26", "value": 415, "prev_avg": 94.0, "factor": 4.4}], "identity": [{"date": "2025-05-05", "value": 244, "prev_avg": 23.0, "factor": 10.6}, {"date": "2025-05-12", "value": 2252, "prev_avg": 96.7, "factor": 23.3}, {"date": "2026-04-13", "value": 4633, "prev_avg": 784.5, "factor": 5.9}], "intent": [{"date": "2025-05-05", "value": 32, "prev_avg": 3.0, "factor": 10.7}, {"date": "2025-05-12", "value": 179, "prev_avg": 12.7, "factor": 14.1}, {"date": "2025-05-19", "value": 218, "prev_avg": 54.2, "factor": 4.0}, {"date": "2025-05-26", "value": 2544, "prev_avg": 107.8, "factor": 23.6}, {"date": "2026-04-13", "value": 1534, "prev_avg": 292.8, "factor": 5.2}], "kernel": [{"date": "2025-05-12", "value": 157, "prev_avg": 1.7, "factor": 94.2}, {"date": "2025-05-26", "value": 1057, "prev_avg": 56.2, "factor": 18.8}], "linear": [{"date": "2025-06-02", "value": 22, "prev_avg": 0.5, "factor": 44.0}, {"date": "2026-03-23", "value": 2041, "prev_avg": 6.2, "factor": 326.6}], "linearity": [{"date": "2026-03-23", "value": 1271, "prev_avg": 0.0, "factor": 12710.0}], "lisp": [{"date": "2025-05-05", "value": 32, "prev_avg": 5.0, "factor": 6.4}, {"date": "2026-03-23", "value": 31, "prev_avg": 10.0, "factor": 3.1}, {"date": "2026-03-30", "value": 483, "prev_avg": 14.5, "factor": 33.3}, {"date": "2026-04-06", "value": 470, "prev_avg": 128.8, "factor": 3.7}, {"date": "2026-04-13", "value": 952, "prev_avg": 246.0, "factor": 3.9}], "mandala": [{"date": "2025-05-19", "value": 9, "prev_avg": 0.0, "factor": 90.0}, {"date": "2025-05-26", "value": 375, "prev_avg": 2.2, "factor": 166.7}, {"date": "2025-06-02", "value": 558, "prev_avg": 96.0, "factor": 5.8}], "mesh": [{"date": "2025-05-12", "value": 72, "prev_avg": 0.0, "factor": 720.0}, {"date": "2025-05-19", "value": 61, "prev_avg": 18.0, "factor": 3.4}, {"date": "2026-04-06", "value": 149, "prev_avg": 5.5, "factor": 27.1}], "migration": [{"date": "2025-05-05", "value": 166, "prev_avg": 8.5, "factor": 19.5}, {"date": "2025-05-12", "value": 418, "prev_avg": 61.0, "factor": 6.9}, {"date": "2025-05-26", "value": 702, "prev_avg": 189.2, "factor": 3.7}, {"date": "2026-04-13", "value": 111, "prev_avg": 28.0, "factor": 4.0}], "node": [{"date": "2025-05-05", "value": 210, "prev_avg": 7.5, "factor": 28.0}, {"date": "2025-05-12", "value": 415, "prev_avg": 75.0, "factor": 5.5}, {"date": "2026-04-06", "value": 1811, "prev_avg": 368.5, "factor": 4.9}, {"date": "2026-04-13", "value": 2694, "prev_avg": 683.2, "factor": 3.9}], "opcodes": [{"date": "2025-05-26", "value": 58, "prev_avg": 0.0, "factor": 580.0}, {"date": "2026-03-23", "value": 532, "prev_avg": 16.0, "factor": 33.2}], "paskian": [{"date": "2026-04-06", "value": 144, "prev_avg": 0.0, "factor": 1440.0}, {"date": "2026-04-13", "value": 135, "prev_avg": 36.0, "factor": 3.8}], "patch": [{"date": "2025-05-05", "value": 478, "prev_avg": 60.5, "factor": 7.9}, {"date": "2025-05-19", "value": 602, "prev_avg": 198.8, "factor": 3.0}, {"date": "2025-05-26", "value": 1397, "prev_avg": 334.5, "factor": 4.2}, {"date": "2026-04-13", "value": 2646, "prev_avg": 423.8, "factor": 6.2}], "pike": [{"date": "2025-05-05", "value": 9, "prev_avg": 0.0, "factor": 90.0}, {"date": "2025-05-12", "value": 225, "prev_avg": 3.0, "factor": 75.0}, {"date": "2025-05-19", "value": 651, "prev_avg": 58.5, "factor": 11.1}, {"date": "2026-04-13", "value": 36, "prev_avg": 9.0, "factor": 4.0}], "plexus": [{"date": "2026-03-23", "value": 835, "prev_avg": 0.0, "factor": 8350.0}, {"date": "2026-03-30", "value": 2003, "prev_avg": 208.8, "factor": 9.6}, {"date": "2026-04-13", "value": 5237, "prev_avg": 820.8, "factor": 6.4}], "pubstream": [{"date": "2025-05-12", "value": 377, "prev_avg": 9.3, "factor": 40.4}], "relevant": [{"date": "2025-05-05", "value": 49, "prev_avg": 10.0, "factor": 4.9}, {"date": "2026-03-23", "value": 362, "prev_avg": 11.8, "factor": 30.8}, {"date": "2026-03-30", "value": 307, "prev_avg": 100.0, "factor": 3.1}, {"date": "2026-04-13", "value": 1194, "prev_avg": 265.0, "factor": 4.5}], "reputation": [{"date": "2025-05-26", "value": 20, "prev_avg": 0.5, "factor": 40.0}, {"date": "2026-03-23", "value": 78, "prev_avg": 6.0, "factor": 13.0}, {"date": "2026-03-30", "value": 122, "prev_avg": 25.5, "factor": 4.8}, {"date": "2026-04-13", "value": 307, "prev_avg": 52.0, "factor": 5.9}], "semantic object": [{"date": "2026-03-23", "value": 151, "prev_avg": 1.0, "factor": 151.0}, {"date": "2026-03-30", "value": 238, "prev_avg": 38.8, "factor": 6.1}, {"date": "2026-04-13", "value": 675, "prev_avg": 135.8, "factor": 5.0}], "semantic seed": [{"date": "2025-05-12", "value": 10, "prev_avg": 0.0, "factor": 100.0}, {"date": "2025-05-26", "value": 94, "prev_avg": 3.5, "factor": 26.9}, {"date": "2025-06-02", "value": 107, "prev_avg": 27.0, "factor": 4.0}], "semantic shell": [{"date": "2025-05-12", "value": 33, "prev_avg": 0.3, "factor": 99.0}, {"date": "2026-03-30", "value": 69, "prev_avg": 9.5, "factor": 7.3}, {"date": "2026-04-13", "value": 134, "prev_avg": 23.2, "factor": 5.8}], "shellbus": [{"date": "2025-05-12", "value": 1192, "prev_avg": 77.7, "factor": 15.3}], "sosp": [{"date": "2025-05-12", "value": 10, "prev_avg": 0.0, "factor": 100.0}, {"date": "2025-05-26", "value": 440, "prev_avg": 3.5, "factor": 125.7}, {"date": "2025-06-02", "value": 1440, "prev_avg": 113.5, "factor": 12.7}], "sr6": [{"date": "2025-05-12", "value": 136, "prev_avg": 0.0, "factor": 1360.0}, {"date": "2025-05-19", "value": 125, "prev_avg": 34.0, "factor": 3.7}, {"date": "2026-04-13", "value": 24, "prev_avg": 4.0, "factor": 6.0}], "srv6": [{"date": "2025-05-12", "value": 220, "prev_avg": 0.0, "factor": 2200.0}, {"date": "2026-04-06", "value": 256, "prev_avg": 5.2, "factor": 48.8}, {"date": "2026-04-13", "value": 274, "prev_avg": 69.2, "factor": 4.0}], "tauri": [{"date": "2025-06-09", "value": 226, "prev_avg": 0.0, "factor": 2260.0}], "taxonomy": [{"date": "2025-05-05", "value": 8, "prev_avg": 0.5, "factor": 16.0}, {"date": "2025-05-26", "value": 7, "prev_avg": 2.0, "factor": 3.5}, {"date": "2026-03-23", "value": 235, "prev_avg": 1.8, "factor": 134.3}, {"date": "2026-03-30", "value": 832, "prev_avg": 60.5, "factor": 13.8}, {"date": "2026-04-13", "value": 2592, "prev_avg": 425.0, "factor": 6.1}], "trades": [{"date": "2026-03-23", "value": 98, "prev_avg": 0.0, "factor": 980.0}, {"date": "2026-03-30", "value": 435, "prev_avg": 24.5, "factor": 17.8}, {"date": "2026-04-13", "value": 1081, "prev_avg": 180.8, "factor": 6.0}], "transaction": [{"date": "2025-05-05", "value": 49, "prev_avg": 2.5, "factor": 19.6}, {"date": "2025-05-12", "value": 1977, "prev_avg": 18.0, "factor": 109.8}, {"date": "2025-05-26", "value": 3186, "prev_avg": 604.5, "factor": 5.3}, {"date": "2025-06-02", "value": 4465, "prev_avg": 1400.0, "factor": 3.2}], "vertical": [{"date": "2026-03-23", "value": 18, "prev_avg": 0.2, "factor": 72.0}, {"date": "2026-04-06", "value": 1761, "prev_avg": 6.5, "factor": 270.9}, {"date": "2026-04-13", "value": 2666, "prev_avg": 446.8, "factor": 6.0}], "wallet": [{"date": "2025-05-05", "value": 279, "prev_avg": 6.0, "factor": 46.5}, {"date": "2025-05-12", "value": 4560, "prev_avg": 97.0, "factor": 47.0}, {"date": "2025-06-02", "value": 5205, "prev_avg": 1643.8, "factor": 3.2}], "wasm": [{"date": "2025-05-26", "value": 21, "prev_avg": 0.8, "factor": 28.0}, {"date": "2026-03-23", "value": 1636, "prev_avg": 6.5, "factor": 251.7}]}, "repo_activity": [{"date": "2025-04-21", "shomee": 20, "core": 0, "total_docs": 20}, {"date": "2025-04-28", "shomee": 20, "core": 0, "total_docs": 20}, {"date": "2025-05-05", "shomee": 122, "core": 0, "total_docs": 122}, {"date": "2025-05-12", "shomee": 314, "core": 0, "total_docs": 314}, {"date": "2025-05-19", "shomee": 283, "core": 0, "total_docs": 283}, {"date": "2025-05-26", "shomee": 341, "core": 0, "total_docs": 341}, {"date": "2025-06-02", "shomee": 395, "core": 0, "total_docs": 395}, {"date": "2025-06-09", "shomee": 42, "core": 0, "total_docs": 42}, {"date": "2026-03-23", "shomee": 0, "core": 98, "total_docs": 98}, {"date": "2026-03-30", "shomee": 0, "core": 105, "total_docs": 105}, {"date": "2026-04-06", "shomee": 0, "core": 114, "total_docs": 114}, {"date": "2026-04-13", "shomee": 0, "core": 314, "total_docs": 314}], "summary": {"total_entries": 2168, "shomee_date_range": "2025-04-22 to 2025-06-10", "core_date_range": "2026-03-27 to 2026-04-17"}};
const DATES = D.timeline.dates;

// Colors for concept lines
const PALETTE = [
  '#f87171','#fb923c','#fbbf24','#a3e635','#34d399','#22d3ee',
  '#60a5fa','#818cf8','#a78bfa','#f472b6','#e879f9','#38bdf8',
  '#4ade80','#facc15','#fb7185','#c084fc','#2dd4bf','#f59e0b',
];

// Nav
const tabs = [
  {id:'timeline',label:'Interactive Timeline'},
  {id:'crossovers',label:'Crossover Events'},
  {id:'bursts',label:'Concept Bursts'},
  {id:'peaks',label:'Peak Dates'},
];
const nav = document.getElementById('nav');
tabs.forEach(t => {
  const btn = document.createElement('button');
  btn.textContent = t.label;
  if(t.id==='timeline') btn.classList.add('active');
  btn.onclick = () => {
    nav.querySelectorAll('button').forEach(b=>b.classList.remove('active'));
    document.querySelectorAll('.panel').forEach(p=>p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById('panel-'+t.id).classList.add('active');
  };
  nav.appendChild(btn);
});

// ─── Timeline Panel ──────────────────────────────────────────────────────
function buildTimeline() {
  const panel = document.getElementById('panel-timeline');

  // Preset groups
  const presets = {
    'container vs cell': ['container','cell','semantic object','factory'],
    'type system': ['linear','affine','relevant','linearity','substructural'],
    'identity': ['identity','certificate','certgraph','gip','bca'],
    'network': ['plexus','srv6','sr6','mesh','6lowpan'],
    'shomee scaffolding': ['civ-stack','dependency injection','consolidation','mandala','sosp','hypervisor'],
    'compression gradient': ['semantic shell','lisp','forth','axiom','compression'],
    'economic': ['bsv','bitcoin','wallet','beef','transaction','anchor'],
    'architecture': ['kernel','adapter','extension','vertical','node','wasm','ffi'],
    'governance': ['governance','capability','flow','reputation','evidence'],
    'pruned vs born': ['shellbus','pubstream','daemon','paskian','plexus','trades'],
  };

  let html = `
    <div class="section-title">Interactive Concept Timeline</div>
    <div class="section-desc">
      Click presets to load concept groups, or click individual concept buttons to toggle them.
      The chart shows weekly mention counts across the full calendar timeline.
      The vertical gap is the 9-month dark period between repos.
    </div>
    <div style="margin-bottom:10px;font-size:11px;color:var(--text2)">Presets:</div>
    <div class="controls" id="presets">
  `;
  Object.keys(presets).forEach(name => {
    html += `<button data-preset="${name}">${name}</button>`;
  });
  html += `</div>
    <div style="margin-bottom:10px;font-size:11px;color:var(--text2)">Concepts (click to toggle):</div>
    <div class="controls" id="concept-buttons"></div>
    <div class="chart-container" style="height:420px">
      <canvas id="timeline-canvas"></canvas>
      <div class="legend" id="timeline-legend"></div>
    </div>

    <div class="section-title">Repo Activity</div>
    <div class="chart-container" style="height:120px">
      <canvas id="activity-canvas"></canvas>
    </div>
  `;
  panel.innerHTML = html;

  // Concept buttons
  const btnContainer = document.getElementById('concept-buttons');
  const allConcepts = Object.keys(D.concept_series).sort((a,b) => D.concept_series[b].total - D.concept_series[a].total);
  allConcepts.forEach((c, i) => {
    const btn = document.createElement('button');
    btn.textContent = c;
    btn.dataset.concept = c;
    btn.style.borderColor = PALETTE[i % PALETTE.length] + '66';
    btnContainer.appendChild(btn);
  });

  let activeConcepts = new Set(['container','cell','linear','adapter']);
  let colorMap = {};

  function updateColors() {
    colorMap = {};
    let i = 0;
    activeConcepts.forEach(c => { colorMap[c] = PALETTE[i++ % PALETTE.length]; });
  }

  function drawTimeline() {
    updateColors();
    const canvas = document.getElementById('timeline-canvas');
    const container = canvas.parentElement;
    const dpr = window.devicePixelRatio || 1;
    const W = container.clientWidth;
    const H = container.clientHeight;
    canvas.width = W * dpr; canvas.height = H * dpr;
    canvas.style.width = W+'px'; canvas.style.height = H+'px';
    const ctx = canvas.getContext('2d');
    ctx.scale(dpr, dpr);

    const PAD = {l:60,r:20,t:20,b:40};
    const cw = W-PAD.l-PAD.r, ch = H-PAD.t-PAD.b;

    // Find max value among active concepts
    let maxVal = 10;
    activeConcepts.forEach(c => {
      const s = D.concept_series[c];
      if(s) maxVal = Math.max(maxVal, ...s.weekly_values);
    });

    // Background
    ctx.fillStyle = '#111827';
    ctx.fillRect(0,0,W,H);

    // Grid
    ctx.strokeStyle = '#1f2937';
    ctx.lineWidth = 0.5;
    for(let i=0;i<=5;i++){
      const y = PAD.t + ch - (i/5)*ch;
      ctx.beginPath();ctx.moveTo(PAD.l,y);ctx.lineTo(W-PAD.r,y);ctx.stroke();
      ctx.fillStyle='#6b7280';ctx.font='10px monospace';ctx.textAlign='right';
      ctx.fillText(Math.round(maxVal*i/5), PAD.l-8, y+3);
    }

    // Date labels
    ctx.fillStyle='#6b7280';ctx.font='10px monospace';ctx.textAlign='center';
    const labelEvery = Math.max(1, Math.floor(DATES.length/10));
    DATES.forEach((d,i) => {
      if(i%labelEvery===0){
        const x = PAD.l + (i/(DATES.length-1))*cw;
        ctx.fillText(d.slice(0,7), x, H-PAD.b+16);
      }
    });

    // Draw repo boundary
    // Find the gap between repos
    const repoAct = D.repo_activity;
    let gapStart = -1, gapEnd = -1;
    for(let i=1;i<repoAct.length;i++){
      if(repoAct[i-1].shomee > 0 && repoAct[i].shomee === 0 && repoAct[i].core === 0){
        gapStart = i;
      }
      if(gapStart > 0 && repoAct[i].core > 0 && gapEnd < 0){
        gapEnd = i;
      }
    }
    if(gapStart > 0 && gapEnd > 0){
      const x1 = PAD.l + (gapStart/(DATES.length-1))*cw;
      const x2 = PAD.l + (gapEnd/(DATES.length-1))*cw;
      ctx.fillStyle='rgba(248,113,113,0.03)';
      ctx.fillRect(PAD.l, PAD.t, x1-PAD.l, ch);
      ctx.fillStyle='rgba(52,211,153,0.03)';
      ctx.fillRect(x2, PAD.t, W-PAD.r-x2, ch);
      ctx.fillStyle='rgba(156,163,175,0.05)';
      ctx.fillRect(x1, PAD.t, x2-x1, ch);

      // Labels
      ctx.fillStyle='#f8717166';ctx.font='bold 11px monospace';ctx.textAlign='center';
      ctx.fillText('shomee-alpha', (PAD.l+x1)/2, PAD.t+14);
      ctx.fillStyle='#9ca3af44';
      ctx.fillText('9-month gap', (x1+x2)/2, PAD.t+14);
      ctx.fillStyle='#34d39966';
      ctx.fillText('semantos-core', (x2+W-PAD.r)/2, PAD.t+14);
    }

    // Draw lines for each active concept
    activeConcepts.forEach(concept => {
      const s = D.concept_series[concept];
      if(!s) return;
      const color = colorMap[concept];
      const vals = s.weekly_values;

      ctx.beginPath();
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;

      let started = false;
      vals.forEach((v,i) => {
        const x = PAD.l + (i/(DATES.length-1))*cw;
        const y = PAD.t + ch - (v/maxVal)*ch;
        if(!started && v > 0){ctx.moveTo(x,y);started=true;}
        else if(started) ctx.lineTo(x,y);
      });
      ctx.stroke();

      // Dots at peaks
      const peakI = DATES.indexOf(s.peak_date);
      if(peakI >= 0){
        const px = PAD.l + (peakI/(DATES.length-1))*cw;
        const py = PAD.t + ch - (s.peak_value/maxVal)*ch;
        ctx.beginPath();ctx.arc(px,py,4,0,Math.PI*2);
        ctx.fillStyle=color;ctx.fill();
      }
    });

    // Legend
    const legend = document.getElementById('timeline-legend');
    legend.innerHTML = '';
    activeConcepts.forEach(c => {
      const color = colorMap[c];
      const s = D.concept_series[c];
      legend.innerHTML += `<div><span class="swatch" style="background:${color}"></span>${c} (peak: ${s?s.peak_value:0})</div>`;
    });

    // Update button states
    btnContainer.querySelectorAll('button').forEach(btn => {
      btn.classList.toggle('on', activeConcepts.has(btn.dataset.concept));
    });
  }

  // Concept button clicks
  btnContainer.addEventListener('click', e => {
    const concept = e.target.dataset.concept;
    if(!concept) return;
    if(activeConcepts.has(concept)) activeConcepts.delete(concept);
    else activeConcepts.add(concept);
    drawTimeline();
  });

  // Preset clicks
  document.getElementById('presets').addEventListener('click', e => {
    const preset = e.target.dataset.preset;
    if(!preset || !presets[preset]) return;
    activeConcepts = new Set(presets[preset].filter(c => D.concept_series[c]));
    drawTimeline();
  });

  // Draw activity chart
  function drawActivity() {
    const canvas = document.getElementById('activity-canvas');
    const container = canvas.parentElement;
    const dpr = window.devicePixelRatio || 1;
    const W = container.clientWidth;
    const H = container.clientHeight;
    canvas.width = W*dpr; canvas.height = H*dpr;
    canvas.style.width = W+'px'; canvas.style.height = H+'px';
    const ctx = canvas.getContext('2d');
    ctx.scale(dpr, dpr);

    const PAD = {l:60,r:20,t:10,b:20};
    const cw = W-PAD.l-PAD.r, ch = H-PAD.t-PAD.b;
    const maxDocs = Math.max(...D.repo_activity.map(r => r.total_docs), 1);
    const barW = cw / DATES.length - 1;

    ctx.fillStyle='#111827';ctx.fillRect(0,0,W,H);

    D.repo_activity.forEach((r, i) => {
      const x = PAD.l + (i/DATES.length)*cw;
      const hShomee = (r.shomee/maxDocs)*ch;
      const hCore = (r.core/maxDocs)*ch;
      ctx.fillStyle='#f8717188';
      ctx.fillRect(x, PAD.t+ch-hShomee, Math.max(barW,2), hShomee);
      ctx.fillStyle='#34d39988';
      ctx.fillRect(x, PAD.t+ch-hShomee-hCore, Math.max(barW,2), hCore);
    });

    ctx.fillStyle='#6b7280';ctx.font='10px monospace';ctx.textAlign='left';
    ctx.fillText('Weekly doc commits (red=shomee, green=core)', PAD.l, PAD.t+10);
  }

  drawTimeline();
  drawActivity();
}

// ─── Crossovers Panel ────────────────────────────────────────────────────
function buildCrossovers() {
  const panel = document.getElementById('panel-crossovers');
  let html = `
    <div class="section-title">Concept Crossover Events</div>
    <div class="section-desc">
      The exact week when one concept overtook another in weekly mention count.
      These are architectural phase transitions — the moment the system's vocabulary shifted.
    </div>
    <div class="crossover-list">
  `;

  // Sort all crossovers by date
  const allX = [];
  Object.entries(D.crossovers).forEach(([pair, events]) => {
    events.forEach(e => allX.push({pair, ...e}));
  });
  allX.sort((a,b) => a.date.localeCompare(b.date));

  allX.forEach(x => {
    html += `<div class="crossover">
      <div class="date">${x.date}</div>
      <div class="from">${x.from_leader} (${x.val_b})</div>
      <div class="arrow">→ overtaken by →</div>
      <div class="to">${x.to_leader} (${x.val_a})</div>
    </div>`;
  });

  html += '</div>';
  panel.innerHTML = html;
}

// ─── Bursts Panel ────────────────────────────────────────────────────────
function buildBursts() {
  const panel = document.getElementById('panel-bursts');
  let html = `
    <div class="section-title">Concept Burst Events</div>
    <div class="section-desc">
      Sudden spikes in concept mentions — 3x or more above the trailing 4-week average.
      These mark the moments when a concept exploded into the codebase.
      Sorted by amplification factor.
    </div>
    <div class="burst-list">
  `;

  // Collect all bursts, sort by factor
  const allBursts = [];
  Object.entries(D.bursts).forEach(([concept, events]) => {
    events.forEach(e => allBursts.push({concept, ...e}));
  });
  allBursts.sort((a,b) => b.factor - a.factor);

  allBursts.slice(0, 50).forEach(b => {
    html += `<div class="burst">
      <span class="concept">${b.concept}</span> on <strong>${b.date}</strong><br>
      <span class="factor">${b.factor}x</span> above avg
      (${b.value} mentions, avg was ${b.prev_avg})
    </div>`;
  });

  html += '</div>';
  panel.innerHTML = html;
}

// ─── Peaks Panel ─────────────────────────────────────────────────────────
function buildPeaks() {
  const panel = document.getElementById('panel-peaks');
  let html = `
    <div class="section-title">Concept Peak Dates</div>
    <div class="section-desc">
      When each concept hit its maximum weekly mention count.
      Concepts peaking in 2025 are shomee-era. Concepts peaking in 2026 are semantos-era.
      Concepts that peak in both may have undergone a phase transition.
    </div>
    <div style="background:var(--bg2);border:1px solid var(--bg3);border-radius:8px;overflow:hidden">
  `;

  const sorted = Object.entries(D.concept_series)
    .sort((a,b) => b[1].total - a[1].total);

  sorted.forEach(([concept, s]) => {
    const isCore = s.peak_date >= '2026';
    const color = isCore ? 'var(--core)' : 'var(--shomee)';
    const barW = Math.min(100, s.peak_value / 50);
    html += `<div style="display:flex;align-items:center;padding:5px 14px;border-bottom:1px solid var(--bg3);font-size:12px">
      <div style="min-width:150px">${concept}</div>
      <div style="min-width:90px;color:${color};font-weight:600">${s.peak_date}</div>
      <div style="min-width:60px;text-align:right">${s.peak_value}</div>
      <div style="flex:1;margin-left:12px;height:6px;background:var(--bg3);border-radius:3px">
        <div style="height:6px;width:${barW}%;background:${color};border-radius:3px"></div>
      </div>
      <div style="min-width:90px;text-align:right;color:var(--text2);font-size:11px">${s.first_seen} → ${s.last_seen}</div>
    </div>`;
  });

  html += '</div>';
  panel.innerHTML = html;
}

buildTimeline();
buildCrossovers();
buildBursts();
buildPeaks();
</script>
</body>
</html>
```
