---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/demo/wine-card.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.640337+00:00
---

# cartridges/tessera/brain/demo/wine-card.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Tessera · the verifiable life of a wine</title>
<style>
  body { font-family: 'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, serif;
         max-width: 720px; margin: 3em auto; padding: 0 1.5em; color: #2a1810;
         line-height: 1.55; background: #faf6ef; }
  h1 { font-size: 1.8em; letter-spacing: 0.02em; margin-bottom: 0.2em; font-weight: 600; }
  h2 { font-size: 1.0em; font-weight: 400; font-style: italic; color: #7a5a40;
       margin: 0.2em 0 2em 0; border-bottom: 1px solid #d4c4a8; padding-bottom: 1em; }
  .chain { list-style: none; padding: 0; counter-reset: step; }
  .step { margin-bottom: 1.6em; padding-left: 3em; position: relative; counter-increment: step; }
  .step::before { content: counter(step, decimal); position: absolute; left: 0; top: 0;
                  width: 2em; height: 2em; border-radius: 50%; background: #fff;
                  border: 1px solid #d4c4a8; text-align: center; line-height: 2em;
                  font-family: Georgia, serif; color: #7a5a40; font-size: 0.9em; }
  .when { font-size: 0.85em; color: #7a5a40; text-transform: uppercase; letter-spacing: 0.1em; }
  .headline { font-size: 1.15em; font-weight: 600; margin: 0.15em 0; }
  .body { color: #4a3828; }
  .mint, .refusal { margin-top: 0.6em; padding: 0.8em 1em;
                    background: #fff; border-left: 3px solid #6a4a2a;
                    border-radius: 0 4px 4px 0; font-size: 0.92em; }
  .refusal { border-left-color: #a02020; background: #fff7f5; }
  .verb { font-weight: 600; color: #4a2a0a; }
  .verb.refused { color: #a02020; }
  .domain, .cellid { color: #7a5a40; font-size: 0.85em; }
  code { font-family: 'SF Mono', 'Consolas', monospace; font-size: 0.85em;
         background: #f0e7d4; padding: 0.1em 0.4em; border-radius: 3px; color: #4a2a0a; }
  .note { font-style: italic; color: #6a4a2a; margin-top: 0.4em; font-size: 0.95em; }
  .refusals { margin-top: 4em; padding-top: 1em; border-top: 1px dashed #c0a880; }
  .refusals h2 { font-style: normal; text-transform: uppercase;
                 letter-spacing: 0.15em; font-size: 0.9em; color: #a02020; }
  .cold-chain { margin-top: 3em; padding-top: 1em; border-top: 1px dashed #c0a880; }
  .cold-chain h2 { font-style: normal; text-transform: uppercase;
                   letter-spacing: 0.15em; font-size: 0.9em; color: #2a5a40; }
  .care-score { margin-top: 3em; padding: 1.5em 1.8em; border-radius: 8px;
                background: #fff; border: 1px solid #d4c4a8;
                box-shadow: 0 1px 6px rgba(80, 60, 30, 0.06); }
  .care-score h2 { font-size: 1.15em; text-transform: none; letter-spacing: 0;
                   border: none; padding: 0; margin: 0 0 0.4em 0; color: #2a1810;
                   font-weight: 600; }
  .care-score .score { color: #7a5a40; font-variant-numeric: tabular-nums; }
  .care-score .verdict { margin: 0 0 1.2em 0; font-style: italic; font-size: 0.95em; }
  .care-score .verdict.warn { color: #a02020; font-style: normal; font-weight: 500; }
  .care-score .verdict.ok   { color: #2a5a40; font-style: normal; font-weight: 500; }
  table.temp-log { width: 100%; border-collapse: collapse; font-size: 0.9em;
                   margin-bottom: 1.2em; }
  table.temp-log th, table.temp-log td { padding: 0.45em 0.6em; text-align: left;
                                          border-bottom: 1px solid #e7dcc4; }
  table.temp-log th { color: #7a5a40; text-transform: uppercase;
                      letter-spacing: 0.08em; font-size: 0.78em; font-weight: 600; }
  table.temp-log tr.excursion { background: #fff3ee; color: #8a2020; }
  table.temp-log tr.confirmed { background: #fff7ee; color: #8a4a20; }
  .care-score .conclusion { margin-top: 0.5em; color: #4a3828; font-size: 0.95em;
                            border-left: 3px solid #6a4a2a; padding-left: 1em; }
  footer { margin-top: 4em; padding-top: 2em; border-top: 1px solid #d4c4a8;
           font-size: 0.9em; color: #6a4a2a; }
  footer .brand { font-style: italic; text-align: center; margin-top: 1em; color: #7a5a40; }
</style>
</head>
<body>
<section class="vintage">
  <h1>Bottle #7 of Lot 2024-PINOT-1</h1>
  <h2>Alice's North Block · the verifiable life of a wine</h2>
  <ol class="chain">
    <li class="step">
      <div class="when">March 2024</div>
      <div class="headline">Alice harvests her north block</div>
      <div class="body">Lot 2024-PINOT-1 · 230 litres of Pinot Noir, hand-picked from a single block on Alice's small Mornington Peninsula vineyard.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> grape-lot · 230 L<br>
        <span class="domain">domain id:</span> <code>L2024-PINOT-1</code><br>
        <span class="cellid">substrate cell:</span> <code>85dc6f6de52e…</code>
      </div>
    </li>
    <li class="step">
      <div class="when">April 2024</div>
      <div class="headline">racked into two barriques</div>
      <div class="body">Alice splits the lot across two oak regimes — half French, half American — for the malolactic fermentation.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> barrel · 113 L · French oak (2nd-fill)<br>
        <span class="domain">domain id:</span> <code>Barrel-A</code><br>
        <span class="cellid">substrate cell:</span> <code>538539f45221…</code>
      </div>
      <div class="mint">
        <span class="verb">✓ minted</span> barrel · 112 L · American oak (new)<br>
        <span class="domain">domain id:</span> <code>Barrel-B</code><br>
        <span class="cellid">substrate cell:</span> <code>fafd1d6c1480…</code>
      </div>
      <div class="note">Five litres lost to pressings. The grape-lot is committed to oak.</div>
    </li>
    <li class="step">
      <div class="when">October 2024</div>
      <div class="headline">blended into the final cuvée</div>
      <div class="body">Six months in oak. Alice tastes both barrels, blends them into a single barrique to settle for bottling.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> cuvée barrique · 225 L = 113 + 112 ✓<br>
        <span class="domain">domain id:</span> <code>Barrel-C</code><br>
        <span class="cellid">substrate cell:</span> <code>f3ec6699633d…</code>
      </div>
      <div class="note">Barrels A and B are spent. The cuvée exists only in Barrel C.</div>
    </li>
    <li class="step">
      <div class="when">March 2025</div>
      <div class="headline">bottled · sealed with tamper-evident NFC chips</div>
      <div class="body">300 bottles of 750 ml from the 225 L barrique. We follow 12 of them (Bottle #7 is the one your sommelier friend will scan).</div>
      <div class="mint">
        <span class="verb">✓ minted</span> Bottle #7 · 750 ml · NFC-sealed<br>
        <span class="domain">domain id:</span> <code>B7</code><br>
        <span class="cellid">substrate cell:</span> <code>048e22b90836…</code>
      </div>
      <div class="note">Barrel C is now spent. Each bottle has a unique, unforgeable identity.</div>
    </li>
    <li class="step">
      <div class="when">March 2025</div>
      <div class="headline">assembled into a sample case for Dan Murphy's</div>
      <div class="body">Six bottles (B1..B6) go into Case-Alpha — destined for Dan Murphy's Cellar Reserve program, Perth.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> case · 6 bottles · holder=alice<br>
        <span class="domain">domain id:</span> <code>Case-Alpha</code><br>
        <span class="cellid">substrate cell:</span> <code>c80d23dac34d…</code>
      </div>
    </li>
    <li class="step">
      <div class="when">April 2025</div>
      <div class="headline">Alice transfers custody to Bob (Melbourne distributor)</div>
      <div class="body">The case leaves the vineyard. Bob's logistics chain will take it across the country to Perth.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> case · in-flight (alice → bob)<br>
        <span class="domain">domain id:</span> <code>Case-Alpha</code><br>
        <span class="cellid">substrate cell:</span> <code>bc128c8d6870…</code>
      </div>
    </li>
    <li class="step">
      <div class="when">April 2025</div>
      <div class="headline">Bob confirms receipt at his Melbourne climate-controlled warehouse</div>
      <div class="body">Bob's signature closes the first custody hop. From here, road haul: Melbourne → Adelaide → across the Nullarbor → Perth (~3,400 km).</div>
      <div class="mint">
        <span class="verb">✓ minted</span> case · holder=bob (settled)<br>
        <span class="domain">domain id:</span> <code>Case-Alpha</code><br>
        <span class="cellid">substrate cell:</span> <code>563615f4a1c8…</code>
      </div>
    </li>
  </ol>
</section>
<section class="cold-chain">
  <h2>the cold chain · every checkpoint logged</h2>
  <ol class="chain">
    <li class="step">
      <div class="when">Apr 14, 2025</div>
      <div class="headline">logger reading · Alice's cellar (pre-pickup)</div>
      <div class="body">Datalogger sealed inside Case-Alpha records ambient at Alice's underground cellar.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> care-event · 14 °C · normal<br>
        <span class="domain">domain id:</span> <code>Case-Alpha</code><br>
        <span class="cellid">substrate cell:</span> <code>d024c7afc29c…</code>
      </div>
    </li>
    <li class="step">
      <div class="when">Apr 18, 2025</div>
      <div class="headline">logger reading · Bob's Melbourne warehouse</div>
      <div class="body">Climate-controlled storage. Reading is stable.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> care-event · 16 °C · normal<br>
        <span class="domain">domain id:</span> <code>Case-Alpha</code><br>
        <span class="cellid">substrate cell:</span> <code>a231da3bb3bf…</code>
      </div>
    </li>
    <li class="step">
      <div class="when">Apr 21, 2025</div>
      <div class="headline">loaded onto the cross-country freight</div>
      <div class="body">Case-Alpha goes on a road train bound for Perth via the Nullarbor. Bob's last touchpoint until Perth receives.</div>
    </li>
    <li class="step">
      <div class="when">Apr 23, 2025</div>
      <div class="headline">logger reading · mid-Nullarbor truck stop</div>
      <div class="body">The trailer's refrigeration unit failed somewhere west of Eucla. By the time the next checkpoint reads, the case has been at peak afternoon temperatures.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> care-event · 33 °C · EXCURSION<br>
        <span class="domain">domain id:</span> <code>Case-Alpha</code><br>
        <span class="cellid">substrate cell:</span> <code>ff72c0a41d18…</code>
      </div>
    </li>
    <li class="step">
      <div class="when">Apr 24, 2025</div>
      <div class="headline">thermo-sticker flipped orange · dock-handler confirms by eye</div>
      <div class="body">Tessera ships every case with a heat-indicator dye sticker (irreversible above 28 °C). The driver notices it at the next stop and flags the load.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> care-event · sticker flipped · CONFIRMED<br>
        <span class="domain">domain id:</span> <code>Case-Alpha</code><br>
        <span class="cellid">substrate cell:</span> <code>cbc0b5162e87…</code>
      </div>
    </li>
    <li class="step">
      <div class="when">Apr 27, 2025</div>
      <div class="headline">logger reading · Dan Murphy's Perth DC</div>
      <div class="body">Back inside climate control. The case is in spec from here on — but the damage is recorded.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> care-event · 17 °C · normal<br>
        <span class="domain">domain id:</span> <code>Case-Alpha</code><br>
        <span class="cellid">substrate cell:</span> <code>f22cc86965a0…</code>
      </div>
    </li>
  </ol>
</section>
<section class="vintage">
  <h1>Bottle #7 of Lot 2024-PINOT-1</h1>
  <h2>Alice's North Block · the verifiable life of a wine</h2>
  <ol class="chain">
    <li class="step">
      <div class="when">May 2025</div>
      <div class="headline">the sommelier scans Bottle #7</div>
      <div class="body">At Dan Murphy's Perth, your friend taps her phone to the NFC seal. The full chain materialises — including every cold-chain reading.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> scan-event · sommelier viewed the chain<br>
        <span class="domain">domain id:</span> <code>B7</code><br>
        <span class="cellid">substrate cell:</span> <code>7d30cc9b44c2…</code>
      </div>
    </li>
  </ol>
</section>
<section class="care-score">
  <h2>Care Score · <span class="score">6 / 10</span></h2>
  <p class="verdict warn">One heat excursion detected · Mid-Nullarbor truck stop (Eucla, WA), Apr 23</p>
  <table class="temp-log">
    <thead><tr><th>date</th><th>temp</th><th>location</th><th></th></tr></thead>
    <tbody>
      <tr><td>Apr 14</td><td>14 °C</td><td>Alice's cellar, Mornington Peninsula</td><td>✓</td></tr>
      <tr><td>Apr 18</td><td>16 °C</td><td>Bob's Melbourne climate-controlled WH</td><td>✓</td></tr>
      <tr class="excursion"><td>Apr 23</td><td>33 °C</td><td>Mid-Nullarbor truck stop (Eucla, WA)</td><td>⚠ EXCURSION</td></tr>
      <tr class="confirmed"><td>Apr 24</td><td>—</td><td>thermo-sticker flipped orange</td><td>⚠ confirmed</td></tr>
      <tr><td>Apr 27</td><td>17 °C</td><td>Dan Murphy's Perth distribution centre</td><td>✓</td></tr>
    </tbody>
  </table>
  <p class="conclusion">If this bottle tastes oxidised, the chain proves WHERE. The damage happened at <strong>Mid-Nullarbor truck stop (Eucla, WA)</strong> on <strong>Apr 23</strong> — not at Alice's vineyard, not at Dan Murphy's. Carrier liability.</p>
</section>
<section class="refusals">
  <h2>what the substrate refuses</h2>
  <ol class="chain">
    <li class="step">
      <div class="when">Demonstration #1</div>
      <div class="headline">the tamper-loop is one-shot</div>
      <div class="body">Once a tamper-evident seal breaks, it cannot be 'un-broken' — and a second tamper claim is refused outright.</div>
      <div class="mint">
        <span class="verb">✓ minted</span> tamper-event · seal broken (one and only)<br>
        <span class="domain">domain id:</span> <code>B8</code><br>
        <span class="cellid">substrate cell:</span> <code>0241bb25590a…</code>
      </div>
      <div class="refusal">
        <span class="verb refused">✗ REFUSED</span> reason: <code>already_tampered</code><br>
        <div class="body">Already tampered. The substrate refuses to record a second break of the same seal.</div>
      </div>
    </li>
    <li class="step">
      <div class="when">Demonstration #2</div>
      <div class="headline">no phantom inventory</div>
      <div class="body">What if a fraudster tries to bottle Barrel-C a second time, conjuring 12 more bottles out of nothing?</div>
      <div class="refusal">
        <span class="verb refused">✗ REFUSED</span> reason: <code>already_consumed</code><br>
        <div class="body">Refused. Barrel-C's wine is already in the original 12 bottles. The substrate enforces single-use.</div>
      </div>
    </li>
    <li class="step">
      <div class="when">Demonstration #3</div>
      <div class="headline">blend conservation</div>
      <div class="body">What about declaring more wine than the inputs justify? Two 100ml barrels claiming 999ml of blended cuvée?</div>
      <div class="refusal">
        <span class="verb refused">✗ REFUSED</span> reason: <code>blend_not_conserved</code><br>
        <div class="body">Refused. Inputs total 200ml; a 999ml output cannot be conserved. The substrate refuses invented wine.</div>
      </div>
    </li>
  </ol>
</section>
<footer>
  <p>Every cell above was minted by the same code path that runs in
  production. The IDs are real SHA-256 hashes of the substrate cell
  bytes — verifiable, unforgeable.</p>
  <p class="brand">Tessera · care-chain provenance · grape to glass</p>
</footer>
</body>
</html>

```
