---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/lib/corpus.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.555568+00:00
---

# tools/crystallization/lib/corpus.ts

```ts
import { execSync } from 'child_process';
import { readFileSync, readdirSync, statSync } from 'fs';
import { join, relative } from 'path';
import type { AnalysisConfig, ConceptDef, CorpusDoc } from '../types';
import { buildMatchers, countMentions } from './corpus-internal';
export { buildMatchers, countMentions } from './corpus-internal';

// ── ISO week helper ───────────────────────────────────────────────────────────

function isoWeek(ts: number): string {
  const d = new Date(ts * 1000);
  const jan4 = new Date(d.getFullYear(), 0, 4);
  const startOfWeek1 = new Date(jan4);
  startOfWeek1.setDate(jan4.getDate() - ((jan4.getDay() + 6) % 7));
  const diff = d.getTime() - startOfWeek1.getTime();
  const week = Math.floor(diff / (7 * 86400000)) + 1;
  return `${d.getFullYear()}-W${String(week).padStart(2, '0')}`;
}

// ── Git timestamp for a file ──────────────────────────────────────────────────

function gitTimestamp(repoPath: string, filePath: string): number {
  try {
    const rel = relative(repoPath, filePath);
    const out = execSync(`git -C "${repoPath}" log --follow --format="%at" -1 -- "${rel}"`, {
      encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'],
    }).trim();
    const n = parseInt(out, 10);
    return isNaN(n) ? 0 : n;
  } catch {
    return 0;
  }
}

// ── Markdown files ────────────────────────────────────────────────────────────

function findMarkdown(dir: string): string[] {
  const results: string[] = [];
  try {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name.startsWith('.') || entry.name === 'node_modules') continue;
      const full = join(dir, entry.name);
      if (entry.isDirectory()) results.push(...findMarkdown(full));
      else if (entry.isFile() && entry.name.endsWith('.md')) results.push(full);
    }
  } catch { /* permission errors */ }
  return results;
}

// ── Auto-vocab extraction ─────────────────────────────────────────────────────

const STOP = new Set([
  'the','a','an','and','or','but','in','on','at','to','for','of','with','by',
  'from','up','about','into','through','during','is','are','was','were','be',
  'been','being','have','has','had','do','does','did','will','would','could',
  'should','may','might','shall','can','this','that','these','those','it','its',
  'we','they','them','their','our','your','he','she','his','her','you','i','me',
  'not','as','if','so','then','than','when','where','which','who','what','how',
  'all','each','some','any','more','also','new','used','use','using','based',
  'between','after','before','within','without','per','via','over','under',
]);

export function extractAutoVocab(texts: string[], topN: number): ConceptDef[] {
  const df = new Map<string, number>(); // doc frequency
  const tf = new Map<string, number>(); // total frequency
  for (const text of texts) {
    const words = text.toLowerCase().match(/\b[a-z][a-z0-9_-]{2,}\b/g) ?? [];
    const seen = new Set<string>();
    for (const w of words) {
      if (STOP.has(w)) continue;
      tf.set(w, (tf.get(w) ?? 0) + 1);
      if (!seen.has(w)) { seen.add(w); df.set(w, (df.get(w) ?? 0) + 1); }
    }
  }
  const N = texts.length;
  const scores = [...tf.entries()]
    .map(([w, freq]) => {
      const d = df.get(w) ?? 1;
      const tfidf = freq * Math.log(N / d);
      return { w, score: tfidf * Math.sqrt(d) }; // boost widespread terms
    })
    .filter(x => (df.get(x.w) ?? 0) >= 3)        // must appear in 3+ docs
    .sort((a, b) => b.score - a.score)
    .slice(0, topN);
  return scores.map(({ w }) => ({ name: w, aliases: [w], description: '' }));
}

// ── Main corpus loader ────────────────────────────────────────────────────────

export function loadCorpus(config: AnalysisConfig, concepts: ConceptDef[]): CorpusDoc[] {
  const matchers = buildMatchers(concepts);
  const docs: CorpusDoc[] = [];

  for (let ei = 0; ei < config.epochs.length; ei++) {
    const epoch = config.epochs[ei];
    const [rangeStart, rangeEnd] = epoch.dateRange
      ? [Date.parse(epoch.dateRange[0]) / 1000, Date.parse(epoch.dateRange[1]) / 1000]
      : [0, Infinity];

    const files = findMarkdown(epoch.path);
    for (const file of files) {
      let ts = gitTimestamp(epoch.path, file);
      if (ts === 0) {
        try { ts = Math.floor(statSync(file).mtimeMs / 1000); } catch { ts = 0; }
      }
      // Filter by date range if specified
      if (epoch.dateRange && ts > 0 && (ts < rangeStart || ts > rangeEnd)) continue;

      let text: string;
      try { text = readFileSync(file, 'utf8'); } catch { continue; }

      const words = text.split(/\s+/).length;
      const mentions = countMentions(text, matchers);
      if (mentions.size === 0) continue; // skip docs with no concept mentions

      docs.push({
        path:       file,
        epochIndex: ei,
        epochName:  epoch.name,
        commitTs:   ts,
        isoWeek:    ts > 0 ? isoWeek(ts) : `${epoch.name}-unknown`,
        wordCount:  words,
        mentions,
      });
    }
  }

  return docs;
}

```
