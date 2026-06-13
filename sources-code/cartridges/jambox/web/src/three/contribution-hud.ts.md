---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/three/contribution-hud.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.616338+00:00
---

# cartridges/jambox/web/src/three/contribution-hud.ts

```ts
/**
 * D-E.8 — Contribution stream HUD.
 *
 * Left-edge DOM overlay; last 32 jam.contribution cells.
 * Each entry: player avatar (colour dot), action label, timestamp.
 * Click → camera dolly to the related object.
 *
 * Follows PodHUD pattern from pod-hud.ts.
 */

// ─── Types ────────────────────────────────────────────────────────────────────

export interface ContributionEntry {
  /** Stable id (jam.contribution semantic id). */
  id: string;
  playerIdentity: string;
  playerColor: string;
  /** Human-readable action label, e.g. "placed kick step at 1.3". */
  actionLabel: string;
  /** Wall-clock ms timestamp. */
  ts: number;
  /** Object ids related to this contribution (for camera dolly). */
  relatedObjectIds: string[];
}

export interface ContributionHUDCallbacks {
  /** Called when an entry is clicked — camera should dolly to the object. */
  onEntryClick: (entry: ContributionEntry) => void;
}

// ─── ContributionHUD ─────────────────────────────────────────────────────────

const MAX_ENTRIES = 32;

export class ContributionHUD {
  private el: HTMLDivElement;
  private entries: ContributionEntry[] = [];
  private cb: ContributionHUDCallbacks;

  constructor(cb: ContributionHUDCallbacks) {
    this.cb = cb;
    this.el = this.build();
    document.body.appendChild(this.el);
  }

  /** Push a new contribution to the top of the list. */
  push(entry: ContributionEntry): void {
    this.entries = [entry, ...this.entries].slice(0, MAX_ENTRIES);
    this.render();
  }

  /** Replace all entries (e.g. after a full state resync). */
  setEntries(entries: ContributionEntry[]): void {
    this.entries = entries.slice(0, MAX_ENTRIES);
    this.render();
  }

  show(): void { this.el.classList.add('visible'); }
  hide(): void { this.el.classList.remove('visible'); }

  dispose(): void { this.el.remove(); }

  // ── private ──────────────────────────────────────────────────────────────

  private build(): HTMLDivElement {
    const el = document.createElement('div');
    el.className = 'contribution-hud';
    el.setAttribute('aria-label', 'Contribution stream');
    return el;
  }

  private render(): void {
    this.el.innerHTML = '';

    const header = document.createElement('div');
    header.className = 'contribution-hud-header';
    header.textContent = 'Contributions';
    this.el.appendChild(header);

    for (const entry of this.entries) {
      const row = document.createElement('div');
      row.className = 'contribution-row';
      row.dataset.id = entry.id;

      const dot = document.createElement('span');
      dot.className = 'contribution-dot';
      dot.style.background = entry.playerColor;
      dot.setAttribute('aria-hidden', 'true');

      const label = document.createElement('span');
      label.className = 'contribution-label';
      label.textContent = entry.actionLabel;

      const time = document.createElement('span');
      time.className = 'contribution-time';
      time.textContent = formatAge(entry.ts);

      row.appendChild(dot);
      row.appendChild(label);
      row.appendChild(time);

      row.addEventListener('click', () => this.cb.onEntryClick(entry));
      this.el.appendChild(row);
    }
  }
}

function formatAge(ts: number): string {
  const delta = Math.floor((Date.now() - ts) / 1000);
  if (delta < 60) return `${delta}s`;
  if (delta < 3600) return `${Math.floor(delta / 60)}m`;
  return `${Math.floor(delta / 3600)}h`;
}

```
