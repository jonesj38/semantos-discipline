---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/bsv-app/spinning-card.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.725158+00:00
---

# archive/apps-navigation_app/bsv-app/spinning-card.js

```js
/**
 * SpinningCard — vanilla JS card component with CSS 3D spin gesture.
 *
 * 2–3 faces: swipe/click to spin (rotateY transition < 200ms).
 * 4+ faces: tabs below card header.
 *
 * Face types:
 *   - profile: dimension stats (score bar, recent count)
 *   - reflection: recent entries with timestamps
 *   - analytics: placeholder trend indicator
 *   - settings: face customization (Phase 2)
 */

// ── Dimension metadata ──────────────────────────────────────────

const DIMENSION_META = {
  mind:   { emoji: '🧠', label: 'Mind',   color: '#818cf8', group: 'Self' },
  body:   { emoji: '💪', label: 'Body',   color: '#f472b6', group: 'Self' },
  spirit: { emoji: '✨', label: 'Spirit', color: '#c084fc', group: 'Self' },
  tribe:  { emoji: '👥', label: 'Tribe',  color: '#fb923c', group: 'Connection' },
  home:   { emoji: '🏠', label: 'Home',   color: '#4ade80', group: 'Connection' },
  craft:  { emoji: '🎨', label: 'Craft',  color: '#facc15', group: 'Creation' },
  wealth: { emoji: '💎', label: 'Wealth', color: '#38bdf8', group: 'Creation' },
};

// ── SpinningCard class ──────────────────────────────────────────

class SpinningCard {
  /**
   * @param {HTMLElement} container - Parent element to render into
   * @param {string} dimensionId - One of: mind, body, spirit, tribe, home, craft, wealth
   * @param {object} options
   * @param {number} options.score - Current dimension score (0–100)
   * @param {Array} options.recentEntries - Recent kernel objects for this dimension
   * @param {Array} options.faces - Face names to render (default: ['profile', 'reflection'])
   */
  constructor(container, dimensionId, options = {}) {
    this.container = container;
    this.dimensionId = dimensionId;
    this.meta = DIMENSION_META[dimensionId] || { emoji: '❓', label: dimensionId, color: '#666', group: 'Unknown' };
    this.score = options.score || 0;
    this.recentEntries = options.recentEntries || [];
    this.faces = options.faces || ['profile', 'reflection'];
    this.currentFaceIndex = 0;
    this.useTabs = this.faces.length >= 4;

    this.el = null;
    this.render();
  }

  render() {
    if (this.el) this.el.remove();

    this.el = document.createElement('div');
    this.el.className = 'spinning-card-wrapper';
    this.el.dataset.dimension = this.dimensionId;

    if (this.useTabs) {
      this.renderTabbed();
    } else {
      this.renderSpinnable();
    }

    this.container.appendChild(this.el);
  }

  renderSpinnable() {
    const card = document.createElement('div');
    card.className = 'spinning-card';
    card.style.setProperty('--dim-color', this.meta.color);

    // Render faces
    this.faces.forEach((faceName, i) => {
      const face = this.createFace(faceName);
      face.style.transform = `rotateY(${i * (360 / this.faces.length)}deg) translateZ(100px)`;
      face.style.display = i === 0 ? 'flex' : 'none';
      face.dataset.faceIndex = i;
      card.appendChild(face);
    });

    // Click/tap to spin
    card.addEventListener('click', (e) => {
      if (e.target.closest('.card-action-btn')) return; // Don't spin on button clicks
      this.spin();
    });

    this.cardEl = card;
    this.el.appendChild(card);
  }

  renderTabbed() {
    // Card body
    const card = document.createElement('div');
    card.className = 'spinning-card tabbed';
    card.style.setProperty('--dim-color', this.meta.color);

    // Tab bar
    const tabBar = document.createElement('div');
    tabBar.className = 'card-tab-bar';
    this.faces.forEach((faceName, i) => {
      const tab = document.createElement('button');
      tab.className = 'card-tab' + (i === 0 ? ' active' : '');
      tab.textContent = faceName.charAt(0).toUpperCase() + faceName.slice(1);
      tab.addEventListener('click', () => this.switchTab(i));
      tabBar.appendChild(tab);
    });

    // Face container
    const faceContainer = document.createElement('div');
    faceContainer.className = 'card-face-container';
    this.faces.forEach((faceName, i) => {
      const face = this.createFace(faceName);
      face.style.display = i === 0 ? 'flex' : 'none';
      face.dataset.faceIndex = i;
      faceContainer.appendChild(face);
    });

    card.appendChild(tabBar);
    card.appendChild(faceContainer);
    this.cardEl = card;
    this.el.appendChild(card);
  }

  createFace(faceName) {
    const face = document.createElement('div');
    face.className = 'card-face card-face-' + faceName;

    switch (faceName) {
      case 'profile':
        face.innerHTML = `
          <div class="card-header">
            <span class="card-emoji">${this.meta.emoji}</span>
            <span class="card-label">${this.meta.label}</span>
          </div>
          <div class="card-score-bar">
            <div class="card-score-fill" style="width: ${this.score}%; background: ${this.meta.color}"></div>
          </div>
          <div class="card-score-text">${this.score}<span class="card-score-max">/100</span></div>
          <div class="card-stat">${this.recentEntries.length} recent entries</div>
        `;
        break;

      case 'reflection':
        const entries = this.recentEntries.slice(0, 3);
        const entriesHtml = entries.length > 0
          ? entries.map(e => `
            <div class="card-entry">
              <span class="card-entry-tag">${this.getTag(e.type)}</span>
              <span class="card-entry-text">${this.truncate(e.fields?.rawText || e.fields?.content || e.fields?.statement || '—', 60)}</span>
              <span class="card-entry-time">${this.timeAgo(e.createdAt)}</span>
            </div>
          `).join('')
          : '<div class="card-empty">No entries yet. Start a conversation.</div>';

        face.innerHTML = `
          <div class="card-header">
            <span class="card-emoji">${this.meta.emoji}</span>
            <span class="card-label">${this.meta.label} — Recent</span>
          </div>
          <div class="card-entries">${entriesHtml}</div>
        `;
        break;

      case 'analytics':
        face.innerHTML = `
          <div class="card-header">
            <span class="card-emoji">${this.meta.emoji}</span>
            <span class="card-label">${this.meta.label} — Trends</span>
          </div>
          <div class="card-analytics-placeholder">
            <div class="card-trend-line" style="border-color: ${this.meta.color}"></div>
            <div class="card-stat">7-day trend coming soon</div>
          </div>
        `;
        break;

      case 'settings':
        face.innerHTML = `
          <div class="card-header">
            <span class="card-emoji">⚙️</span>
            <span class="card-label">${this.meta.label} — Settings</span>
          </div>
          <div class="card-settings-placeholder">
            <div class="card-stat">Face customization — Phase 2</div>
          </div>
        `;
        break;
    }

    return face;
  }

  spin() {
    if (this.useTabs) return;
    const faces = this.cardEl.querySelectorAll('.card-face');
    faces[this.currentFaceIndex].style.display = 'none';
    this.currentFaceIndex = (this.currentFaceIndex + 1) % this.faces.length;
    faces[this.currentFaceIndex].style.display = 'flex';

    // Spin animation
    this.cardEl.classList.add('spin');
    setTimeout(() => this.cardEl.classList.remove('spin'), 600);
  }

  switchTab(index) {
    const faces = this.cardEl.querySelectorAll('.card-face');
    const tabs = this.cardEl.querySelectorAll('.card-tab');
    faces[this.currentFaceIndex].style.display = 'none';
    tabs[this.currentFaceIndex].classList.remove('active');
    this.currentFaceIndex = index;
    faces[this.currentFaceIndex].style.display = 'flex';
    tabs[this.currentFaceIndex].classList.add('active');
  }

  update(options) {
    if (options.score !== undefined) this.score = options.score;
    if (options.recentEntries) this.recentEntries = options.recentEntries;
    if (options.faces) {
      this.faces = options.faces;
      this.useTabs = this.faces.length >= 4;
    }
    this.render();
  }

  // ── Helpers ──

  getTag(type) {
    const tags = {
      Release: '↗ Released',
      Insight: '✦ Insight',
      Intention: '🎯 Intention',
      DailyReview: '✓ Review',
      MorningIntention: '☀ Morning',
      Pattern: '🔄 Pattern',
      DimensionPulse: '📊 Pulse',
      Connection: '🔗 Connect',
      Session: '🧭 Session',
      VacuumSession: '🌀 Vacuum',
      GoldSeal: '✨ Sealed',
    };
    return tags[type] || type;
  }

  truncate(str, len) {
    return str.length > len ? str.slice(0, len) + '…' : str;
  }

  timeAgo(ts) {
    const diff = Date.now() - ts;
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins}m ago`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
  }
}

// Expose globally
window.SpinningCard = SpinningCard;
window.DIMENSION_META = DIMENSION_META;

```
