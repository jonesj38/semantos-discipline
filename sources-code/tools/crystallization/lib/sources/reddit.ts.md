---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/lib/sources/reddit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.557958+00:00
---

# tools/crystallization/lib/sources/reddit.ts

```ts
/**
 * Reddit source adapter for the crystallization analyzer.
 *
 * Fetches posts (+ top comments) from a subreddit via the public Reddit JSON
 * API. No OAuth required for read-only access to public subreddits.
 *
 * Each post + its top-level comments becomes one CorpusDoc, timestamped from
 * the post's created_utc. This gives the same temporal granularity as a git
 * commit: one document per event, dated precisely.
 *
 * Social-engineering detection use case:
 *   Run with sort=hot and sort=controversial for the same subreddit + period.
 *   Lifecycle divergence between the two reveals manipulation patterns:
 *   - CRYSTALLIZED in hot + absent/TRANSITION in controversial → organic
 *   - CRYSTALLIZED in controversial + LATE_EMERGENCE in hot → contested push
 *   - TRANSITION_ONLY in hot → manufactured burst, didn't stick
 *   - Pask score high in hot + low in controversial → scripted talking points
 */

import { writeFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';
import type { AnalysisConfig, ConceptDef, CorpusDoc } from '../../types';
import { buildMatchers, countMentions } from '../corpus-internal';

// ── Reddit API types ──────────────────────────────────────────────────────────

interface RedditPost {
  id: string;
  title: string;
  selftext: string;
  created_utc: number;
  score: number;
  upvote_ratio: number;
  num_comments: number;
  permalink: string;
  url: string;
  subreddit: string;
}

interface RedditComment {
  body: string;
  score: number;
  created_utc: number;
  author: string;
}

export interface RedditEpochConfig {
  source: 'reddit';
  name: string;
  subreddit: string;
  sort: 'hot' | 'controversial' | 'new' | 'top' | 'rising';
  timeFilter?: 'hour' | 'day' | 'week' | 'month' | 'year' | 'all'; // for top/controversial
  limit?: number;       // max posts to fetch (default 100, max 500 via pagination)
  dateRange?: [string, string];
  includeComments?: boolean;  // default true
  maxComments?: number;       // top N comments per post (default 10)
  cacheDir?: string;          // cache fetched JSON here to avoid re-fetching
}

// ── ISO week helper (shared with corpus.ts) ───────────────────────────────────

function isoWeek(ts: number): string {
  const d = new Date(ts * 1000);
  const jan4 = new Date(d.getFullYear(), 0, 4);
  const startOfWeek1 = new Date(jan4);
  startOfWeek1.setDate(jan4.getDate() - ((jan4.getDay() + 6) % 7));
  const diff = d.getTime() - startOfWeek1.getTime();
  const week = Math.floor(diff / (7 * 86400000)) + 1;
  return `${d.getFullYear()}-W${String(week).padStart(2, '0')}`;
}

// ── Reddit fetch helpers ──────────────────────────────────────────────────────

async function sleep(ms: number) {
  return new Promise(r => setTimeout(r, ms));
}

async function fetchJson(url: string, attempt = 0): Promise<unknown> {
  const res = await fetch(url, {
    headers: { 'User-Agent': 'crystallization-analyzer/1.0 (research tool)' },
  });
  if (res.status === 429) {
    if (attempt >= 6) throw new Error(`Reddit API rate limit after ${attempt} retries: ${url}`);
    const wait = 15000 * (attempt + 1); // 15s, 30s, 45s, 60s, 75s, 90s
    process.stderr.write(`  [reddit] rate limited, waiting ${wait / 1000}s...\n`);
    await sleep(wait);
    return fetchJson(url, attempt + 1);
  }
  if (!res.ok) throw new Error(`Reddit API ${res.status}: ${url}`);
  return res.json();
}

async function fetchPostListing(
  subreddit: string,
  sort: string,
  limit: number,
  timeFilter?: string,
  after?: string,
): Promise<{ posts: RedditPost[]; after: string | null }> {
  let url = `https://www.reddit.com/r/${subreddit}/${sort}.json?limit=${Math.min(limit, 100)}&raw_json=1`;
  if (timeFilter) url += `&t=${timeFilter}`;
  if (after) url += `&after=${after}`;

  await sleep(3000); // conservative — 1 listing call per 3s
  const data = await fetchJson(url) as { data: { children: Array<{ data: RedditPost }>; after: string | null } };
  const posts = data.data.children.map(c => c.data);
  return { posts, after: data.data.after };
}

async function fetchComments(permalink: string, maxComments: number): Promise<RedditComment[]> {
  const url = `https://www.reddit.com${permalink}.json?limit=${maxComments}&raw_json=1`;
  try {
    const data = await fetchJson(url) as Array<{ data: { children: Array<{ data: RedditComment & { kind?: string } }> } }>;
    if (!Array.isArray(data) || data.length < 2) return [];
    return data[1].data.children
      .filter(c => c.data.body && c.data.body !== '[deleted]' && c.data.body !== '[removed]')
      .slice(0, maxComments)
      .map(c => c.data);
  } catch {
    return [];
  }
}

// ── Cache helpers ─────────────────────────────────────────────────────────────

function cacheKey(cfg: RedditEpochConfig): string {
  return `${cfg.subreddit}-${cfg.sort}-${cfg.timeFilter ?? 'none'}-${cfg.limit ?? 100}`;
}

function loadCache(cacheDir: string, key: string): RedditPost[] | null {
  const path = join(cacheDir, `${key}.json`);
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(require('fs').readFileSync(path, 'utf8'));
  } catch {
    return null;
  }
}

function saveCache(cacheDir: string, key: string, posts: RedditPost[]): void {
  mkdirSync(cacheDir, { recursive: true });
  writeFileSync(join(cacheDir, `${key}.json`), JSON.stringify(posts, null, 2));
}

// ── Main fetch ────────────────────────────────────────────────────────────────

export async function fetchRedditPosts(cfg: RedditEpochConfig, verbose = true): Promise<RedditPost[]> {
  const limit = cfg.limit ?? 100;
  const cacheDir = cfg.cacheDir;
  const key = cacheKey(cfg);

  if (cacheDir) {
    const cached = loadCache(cacheDir, key);
    if (cached) {
      if (verbose) console.log(`  [reddit] cache hit: ${cached.length} posts for r/${cfg.subreddit}/${cfg.sort}`);
      return cached;
    }
  }

  if (verbose) console.log(`  [reddit] fetching r/${cfg.subreddit}/${cfg.sort} (up to ${limit} posts)...`);

  const posts: RedditPost[] = [];
  let after: string | null = null;
  let remaining = limit;

  while (remaining > 0) {
    const batch = await fetchPostListing(cfg.subreddit, cfg.sort, remaining, cfg.timeFilter, after ?? undefined);
    posts.push(...batch.posts);
    after = batch.after;
    remaining -= batch.posts.length;
    if (!after || batch.posts.length === 0) break;
    await sleep(1000); // polite rate limit
  }

  if (cacheDir) saveCache(cacheDir, key, posts);
  if (verbose) console.log(`  [reddit] fetched ${posts.length} posts`);
  return posts;
}

// ── Convert posts → CorpusDoc[] ───────────────────────────────────────────────

export async function loadRedditCorpus(
  cfg: RedditEpochConfig,
  epochIndex: number,
  concepts: ConceptDef[],
  verbose = true,
): Promise<CorpusDoc[]> {
  const matchers = buildMatchers(concepts);
  const posts = await fetchRedditPosts(cfg, verbose);

  const [rangeStart, rangeEnd] = cfg.dateRange
    ? [Date.parse(cfg.dateRange[0]) / 1000, Date.parse(cfg.dateRange[1]) / 1000]
    : [0, Infinity];

  const includeComments = cfg.includeComments ?? true;
  const maxComments = cfg.maxComments ?? 10;
  const docs: CorpusDoc[] = [];

  for (const post of posts) {
    const ts = post.created_utc;
    if (ts < rangeStart || ts > rangeEnd) continue;

    // Check title + body first — only fetch comments for posts that already match.
    // This cuts comment API calls to ~15% of posts rather than 100%.
    const parts: string[] = [post.title];
    if (post.selftext) parts.push(post.selftext);

    const titleMentions = countMentions(parts.join('\n\n'), matchers);

    if (includeComments && post.num_comments > 0 && titleMentions.size > 0) {
      await sleep(8000); // 8s between comment fetches — public API rate limit is harsh
      const comments = await fetchComments(post.permalink, maxComments);
      for (const c of comments) parts.push(c.body);
    }

    const text = parts.join('\n\n');
    const words = text.split(/\s+/).length;
    const mentions = countMentions(text, matchers);
    if (mentions.size === 0) continue;

    docs.push({
      path: `reddit://r/${post.subreddit}/${post.id}`,
      epochIndex,
      epochName: cfg.name,
      commitTs: ts,
      isoWeek: isoWeek(ts),
      wordCount: words,
      mentions,
    });
  }

  if (verbose) console.log(`  [reddit] ${docs.length} docs with concept mentions`);
  return docs;
}

```
