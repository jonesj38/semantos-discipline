---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/assets/wallet/wallet.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.121860+00:00
---

# apps/semantos/assets/wallet/wallet.html

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>Semantos Wallet</title>
    <!--
      C11 PR-C11-4d — Wallet renderer (stripped).

      This is NOT the legacy wallet-headers bundle. Per the renderer
      contract (docs/design/WALLET-RENDERER-CONTRACT.md §1), this page
      generates no seeds, derives no keys, signs no transactions, and
      broadcasts nothing. It is purely a display + intent-forwarding
      surface for the shell-side wallet stack.

      All cryptographic operations happen in Dart (cert custody +
      tier-0 + BRC-42 derivation landed in PR-C11-4c). Communication
      with Dart goes through the `SemantosWallet` JavaScriptChannel
      (wired up by `wallet_launch.dart` in PR-C11-4e).

      Until 4e ships the Dart-side channel, the renderer shows a
      "waiting for shell" state. That is the expected interim — see
      WALLET-RENDERER-CONTRACT.md §9.
    -->
    <style>
      :root {
        --bg: #0f1115;
        --fg: #e8eaed;
        --fg-muted: #9aa3b4;
        --accent: #4f8cff;
        --field-bg: #1a1d24;
        --field-border: #2a2f3a;
        --panel-bg: #14171d;
        --error: #ff6b6b;
      }
      html, body {
        margin: 0;
        padding: 0;
        background: var(--bg);
        color: var(--fg);
        font: 14px system-ui, sans-serif;
        min-height: 100vh;
      }
      body {
        padding: 1em;
        box-sizing: border-box;
      }
      .panel {
        border: 1px solid var(--field-border);
        border-radius: 6px;
        padding: 1em;
        margin: 1em 0;
        background: var(--panel-bg);
      }
      .panel h3 {
        margin: 0 0 0.5em 0;
        font-size: 15px;
      }
      .panel p.hint {
        color: var(--fg-muted);
        font-size: 13px;
        margin: 0 0 0.8em 0;
      }
      .panel .field {
        background: var(--field-bg);
        color: var(--fg);
        border: 1px solid var(--field-border);
        border-radius: 3px;
        padding: 0.4em 0.6em;
        margin: 0.3em 0;
        font: inherit;
        width: 100%;
        box-sizing: border-box;
      }
      .panel .field-row {
        display: flex;
        gap: 0.5em;
        align-items: center;
      }
      .panel button {
        background: var(--accent);
        color: white;
        border: none;
        border-radius: 4px;
        padding: 0.55em 1em;
        cursor: pointer;
        font: inherit;
      }
      .panel button:disabled {
        opacity: 0.5;
        cursor: not-allowed;
      }
      .panel button.secondary {
        background: var(--field-bg);
        color: var(--fg);
        border: 1px solid var(--field-border);
      }
      .panel .row {
        margin: 0.5em 0;
      }
      .mono {
        font: 12px ui-monospace, monospace;
        color: var(--fg-muted);
      }
      .badge-ok { color: #6ad28e; }
      .badge-pending { color: #d2b56a; }
      .badge-error { color: var(--error); }
      pre.log {
        background: #0a0c11;
        color: #c8cdd5;
        padding: 0.8em;
        margin: 0;
        font: 11px ui-monospace, monospace;
        white-space: pre-wrap;
        max-height: 12em;
        overflow-y: auto;
        border-radius: 4px;
      }
      .utxo-row {
        padding: 0.4em 0;
        border-bottom: 1px solid var(--field-border);
        font: 11px ui-monospace, monospace;
      }
      .utxo-row:last-child { border-bottom: none; }
      .utxo-empty {
        color: var(--fg-muted);
        font-style: italic;
      }
    </style>
  </head>
  <body>
    <div id="app"></div>
    <script src="./wallet-page.js"></script>
  </body>
</html>

```
