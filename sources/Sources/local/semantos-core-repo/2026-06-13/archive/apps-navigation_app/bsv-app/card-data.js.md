---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/bsv-app/card-data.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.726107+00:00
---

# archive/apps-navigation_app/bsv-app/card-data.js

```js
/**
 * CardData — adapter that reads from SemantosKernel and maintains
 * sorted card data for the dashboard's seven dimension cards.
 *
 * Groups objects by dimension, computes scores, and provides
 * the data shape SpinningCard expects.
 */

// ── Dimension-to-enum mapping (consciousness-specific, TODO: make config-driven) ──

const DIMENSION_IDS = ['mind', 'body', 'spirit', 'tribe', 'home', 'craft', 'wealth'];

const DIMENSION_ENUM_MAP = {
  'MENTAL': 'mind',
  'PHYSICAL': 'body',
  'SPIRITUAL': 'spirit',
  'SOCIAL': 'tribe',
  'VOCATIONAL': 'craft',
  'FINANCIAL': 'wealth',
  'FAMILIAL': 'home',
};

const GROUPS = {
  Self: ['mind', 'body', 'spirit'],
  Connection: ['tribe', 'home'],
  Creation: ['craft', 'wealth'],
};

// ── CardDataManager ─────────────────────────────────────────────

class CardDataManager {
  constructor() {
    this.dimensionData = {};
    this.listeners = new Set();

    // Initialize all dimensions
    for (const id of DIMENSION_IDS) {
      this.dimensionData[id] = {
        score: 50, // Default starting score
        recentEntries: [],
      };
    }
  }

  /**
   * Connect to SemantosKernel and subscribe to changes.
   * Call this after kernel-bridge.js has loaded.
   */
  connect() {
    if (!window.SemantosKernel) {
      console.warn('[CardData] SemantosKernel not available');
      return;
    }

    // Initial sync
    this.sync();

    // Subscribe to changes
    window.SemantosKernel.subscribe(() => this.sync());
  }

  /**
   * Sync dimension data from kernel objects.
   */
  sync() {
    const kernel = window.SemantosKernel;
    if (!kernel) return;

    const allObjects = kernel.listObjects();
    const now = Date.now();
    const weekAgo = now - 7 * 24 * 60 * 60 * 1000;

    // Reset recent entries
    for (const id of DIMENSION_IDS) {
      this.dimensionData[id].recentEntries = [];
    }

    // Bucket objects by dimension
    for (const obj of allObjects) {
      const dimId = this.resolveDimension(obj);
      if (dimId && this.dimensionData[dimId]) {
        if (obj.createdAt >= weekAgo) {
          this.dimensionData[dimId].recentEntries.push(obj);
        }
      }

      // Update scores from DimensionPulse objects
      if (obj.type === 'DimensionPulse' && obj.fields.dimension) {
        const pulseDimId = DIMENSION_ENUM_MAP[obj.fields.dimension];
        if (pulseDimId && this.dimensionData[pulseDimId]) {
          // Scale 1-10 score to 0-100
          const score = typeof obj.fields.score === 'number' ? obj.fields.score * 10 : 50;
          this.dimensionData[pulseDimId].score = Math.min(100, Math.max(0, score));
        }
      }

      // Update scores from DimensionState objects
      if (obj.type === 'DimensionState' && obj.fields.dimension) {
        const stateDimId = DIMENSION_ENUM_MAP[obj.fields.dimension];
        if (stateDimId && this.dimensionData[stateDimId]) {
          const score = typeof obj.fields.currentLevel === 'number' ? obj.fields.currentLevel : 50;
          this.dimensionData[stateDimId].score = Math.min(100, Math.max(0, score));
        }
      }
    }

    // Sort recent entries by creation time (newest first)
    for (const id of DIMENSION_IDS) {
      this.dimensionData[id].recentEntries.sort((a, b) => b.createdAt - a.createdAt);
    }

    this.notify();
  }

  /**
   * Get data for a single dimension.
   */
  getDimension(dimId) {
    return this.dimensionData[dimId] || { score: 50, recentEntries: [] };
  }

  /**
   * Get all dimensions grouped by meta-category.
   * Returns: { Self: [{dimId, ...data}], Connection: [...], Creation: [...] }
   */
  getGrouped() {
    const result = {};
    for (const [groupName, dimIds] of Object.entries(GROUPS)) {
      result[groupName] = dimIds.map(id => ({
        dimId: id,
        ...this.dimensionData[id],
      }));
    }
    return result;
  }

  /**
   * Subscribe to data changes.
   */
  subscribe(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  // ── Internal ──

  resolveDimension(obj) {
    // Check explicit dimension fields
    const dimField = obj.fields.dimension || obj.fields.primaryDimension;
    if (dimField && DIMENSION_ENUM_MAP[dimField]) {
      return DIMENSION_ENUM_MAP[dimField];
    }

    // Check dimensions field (comma-separated or single)
    if (obj.fields.dimensions) {
      const first = String(obj.fields.dimensions).split(',')[0].trim();
      if (DIMENSION_ENUM_MAP[first]) return DIMENSION_ENUM_MAP[first];
    }

    // Default assignment by object type
    const typeDefaults = {
      Release: 'spirit',
      Insight: 'mind',
      Pattern: 'mind',
      Intention: 'craft',
      DailyReview: 'mind',
      MorningIntention: 'mind',
      Connection: 'tribe',
      Session: 'spirit',
      VacuumSession: 'spirit',
      GoldSeal: 'spirit',
    };
    return typeDefaults[obj.type] || null;
  }

  notify() {
    for (const fn of this.listeners) fn(this.dimensionData);
  }
}

// Expose globally
window.CardDataManager = CardDataManager;
window.DIMENSION_IDS = DIMENSION_IDS;
window.DIMENSION_GROUPS = GROUPS;

```
