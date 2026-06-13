---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.581311+00:00
---

# cartridges/jambox/web/bridge.ts

```ts
/**
 * Local jambox library bridge.
 *
 * This process is intentionally localhost-only. It indexes configured
 * Rekordbox XML and sample folders, then exposes semantic library objects
 * and audio blobs by stable id. The browser never gets arbitrary filesystem
 * read access; it can only request objects the bridge has indexed.
 */

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { basename, dirname, extname, join, normalize, relative, resolve } from 'node:path';

type ObjectKind = 'jam.crate' | 'jam.track' | 'jam.sample-pack' | 'jam.sample';

interface BridgeConfig {
  rekordboxXml?: string;
  sampleDirs: string[];
}

interface BridgeObject<TPayload> {
  id: string;
  header: {
    version: 1;
    objectType: ObjectKind;
    semanticPath: string;
    linearity: 'affine' | 'relevant';
    ownerIdentity: string;
    parents: string[];
    commercial: { listed: boolean; license: 'personal' };
    createdAt: number;
  };
  payload: TPayload;
}

interface TrackPayload {
  source: 'rekordbox';
  sourceTrackId: string;
  title: string;
  artist?: string;
  album?: string;
  location?: string;
  bpm?: number;
  key?: string;
  totalTimeSeconds?: number;
  cues: Array<{ name?: string; type?: string; startSeconds?: number }>;
  bridgeAudioId?: string;
}

interface CratePayload {
  source: 'rekordbox';
  label: string;
  trackObjectIds: string[];
  playlistPath: string[];
}

interface SamplePayload {
  source: 'splice-folder';
  name: string;
  relativePath: string;
  pack: string;
  sizeBytes: number;
  extension: string;
  bridgeAudioId: string;
}

interface SamplePackPayload {
  source: 'splice-folder';
  label: string;
  sampleObjectIds: string[];
  relativePath: string;
}

interface AudioEntry {
  id: string;
  path: string;
  kind: 'track' | 'sample';
  mime: string;
}

const AUDIO_EXTENSIONS = new Set(['aif', 'aiff', 'flac', 'm4a', 'mp3', 'ogg', 'wav', 'wave']);
const OWNER = process.env.JAM_BRIDGE_OWNER ?? 'bridge';
const PORT = Number(process.env.JAM_BRIDGE_PORT ?? 5182);
const startedAt = Date.now();

let config = loadConfig();
let tracks: BridgeObject<TrackPayload>[] = [];
let crates: BridgeObject<CratePayload>[] = [];
let samples: BridgeObject<SamplePayload>[] = [];
let samplePacks: BridgeObject<SamplePackPayload>[] = [];
let audioById = new Map<string, AudioEntry>();
let lastScan: { ok: boolean; at: number; message: string } | null = null;

await scan();

const server = Bun.serve({
  hostname: '127.0.0.1',
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);
    if (req.method === 'OPTIONS') return cors(new Response(null, { status: 204 }));
    try {
      if (url.pathname === '/api/bridge/status') return json({ ok: true, startedAt, config: publicConfig(), lastScan });
      if (url.pathname === '/api/bridge/sync' && req.method === 'POST') {
        await scan();
        return json(libraryPayload());
      }
      if (url.pathname === '/api/bridge/library') return json(libraryPayload());
      if (url.pathname.startsWith('/api/bridge/audio/')) return audioResponse(url.pathname.split('/').pop() ?? '');
      return cors(new Response('not found', { status: 404 }));
    } catch (err) {
      const message = err instanceof Error ? err.message : 'bridge error';
      return json({ ok: false, message }, 500);
    }
  },
});

console.log(`jambox bridge on http://127.0.0.1:${server.port}`);
console.log(`  rekordboxXml=${config.rekordboxXml ?? '(unset)'}`);
console.log(`  sampleDirs=${config.sampleDirs.length ? config.sampleDirs.join(', ') : '(unset)'}`);

async function scan(): Promise<void> {
  const freshAudio = new Map<string, AudioEntry>();
  const nextTracks: BridgeObject<TrackPayload>[] = [];
  const nextCrates: BridgeObject<CratePayload>[] = [];
  const nextSamples: BridgeObject<SamplePayload>[] = [];
  const nextPacks: BridgeObject<SamplePackPayload>[] = [];

  try {
    if (config.rekordboxXml && existsSync(config.rekordboxXml)) {
      const result = await scanRekordbox(config.rekordboxXml, freshAudio);
      nextTracks.push(...result.tracks);
      nextCrates.push(...result.crates);
    }
    const packMap = new Map<string, BridgeObject<SamplePayload>[]>();
    for (const dir of config.sampleDirs) {
      if (!existsSync(dir)) continue;
      for (const sample of await scanSamples(dir, freshAudio)) {
        nextSamples.push(sample);
        const packSamples = packMap.get(sample.payload.pack) ?? [];
        packSamples.push(sample);
        packMap.set(sample.payload.pack, packSamples);
      }
    }
    for (const [pack, packSamples] of packMap) {
      nextPacks.push(object('jam.sample-pack', `splice-${pack}`, `/jam/v1/import/splice/pack/${slug(pack)}`, 'relevant', {
        source: 'splice-folder',
        label: pack,
        sampleObjectIds: packSamples.map((sample) => sample.id),
        relativePath: pack,
      }, packSamples.map((sample) => sample.id)));
    }
    tracks = nextTracks;
    crates = nextCrates;
    samples = nextSamples;
    samplePacks = nextPacks;
    audioById = freshAudio;
    lastScan = {
      ok: true,
      at: Date.now(),
      message: `${tracks.length} tracks · ${crates.length} crates · ${samples.length} samples · ${samplePacks.length} packs`,
    };
  } catch (err) {
    lastScan = { ok: false, at: Date.now(), message: err instanceof Error ? err.message : 'scan failed' };
    throw err;
  }
}

async function scanRekordbox(
  xmlPath: string,
  freshAudio: Map<string, AudioEntry>,
): Promise<{ tracks: BridgeObject<TrackPayload>[]; crates: BridgeObject<CratePayload>[] }> {
  const xml = await readFile(xmlPath, 'utf8');
  const trackBySourceId = new Map<string, BridgeObject<TrackPayload>>();
  for (const tag of tags(xml, 'TRACK')) {
    const attrs = attrsFromTag(tag);
    const sourceTrackId = attrs.TrackID;
    const key = attrs.Key;
    if (!sourceTrackId || key) continue;
    const location = decodeRekordboxLocation(attrs.Location);
    const audioId = location && existsSync(location) ? audioIdFor(location) : undefined;
    if (audioId && location) {
      freshAudio.set(audioId, { id: audioId, path: location, kind: 'track', mime: mimeFor(location) });
    }
    const track = object('jam.track', `rekordbox-${sourceTrackId}-${attrs.Name ?? sourceTrackId}`, `/jam/v1/import/rekordbox/track/${slug(sourceTrackId)}`, 'relevant', {
      source: 'rekordbox',
      sourceTrackId,
      title: attrs.Name ?? `Track ${sourceTrackId}`,
      artist: attrs.Artist,
      album: attrs.Album,
      location,
      bpm: num(attrs.AverageBpm),
      key: attrs.Tonality,
      totalTimeSeconds: num(attrs.TotalTime),
      cues: positionMarks(tag).map((mark) => ({
        name: mark.Name,
        type: mark.Type,
        startSeconds: num(mark.Start),
      })),
      bridgeAudioId: audioId,
    });
    trackBySourceId.set(sourceTrackId, track);
  }

  const cratesOut: BridgeObject<CratePayload>[] = [];
  for (const playlist of playlists(xml)) {
    const trackObjectIds = playlist.trackIds
      .map((id) => trackBySourceId.get(id)?.id)
      .filter((id): id is string => Boolean(id));
    if (trackObjectIds.length === 0) continue;
    cratesOut.push(object('jam.crate', `rekordbox-${playlist.path.join('-')}`, `/jam/v1/import/rekordbox/crate/${playlist.path.map(slug).join('/')}`, 'relevant', {
      source: 'rekordbox',
      label: playlist.name,
      trackObjectIds,
      playlistPath: playlist.path,
    }, trackObjectIds));
  }
  if (cratesOut.length === 0 && trackBySourceId.size > 0) {
    const trackObjectIds = [...trackBySourceId.values()].map((track) => track.id);
    cratesOut.push(object('jam.crate', 'rekordbox-collection', '/jam/v1/import/rekordbox/crate/collection', 'relevant', {
      source: 'rekordbox',
      label: 'Rekordbox Collection',
      trackObjectIds,
      playlistPath: ['Rekordbox Collection'],
    }, trackObjectIds));
  }
  return { tracks: [...trackBySourceId.values()], crates: cratesOut };
}

async function scanSamples(root: string, freshAudio: Map<string, AudioEntry>): Promise<BridgeObject<SamplePayload>[]> {
  const out: BridgeObject<SamplePayload>[] = [];
  for await (const file of walk(root)) {
    const extension = extname(file).slice(1).toLowerCase();
    if (!AUDIO_EXTENSIONS.has(extension)) continue;
    const st = statSync(file);
    const rel = relative(root, file);
    const pack = inferPack(rel);
    const id = audioIdFor(file);
    freshAudio.set(id, { id, path: file, kind: 'sample', mime: mimeFor(file) });
    out.push(object('jam.sample', `splice-${file}`, `/jam/v1/import/splice/sample/${slug(rel)}`, 'affine', {
      source: 'splice-folder',
      name: basename(file),
      relativePath: rel,
      pack,
      sizeBytes: st.size,
      extension,
      bridgeAudioId: id,
    }));
  }
  return out;
}

async function* walk(dir: string): AsyncGenerator<string> {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) yield* walk(path);
    else if (entry.isFile()) yield path;
  }
}

function libraryPayload(): object {
  return { ok: true, tracks, crates, samples, samplePacks, lastScan, config: publicConfig() };
}

function publicConfig(): object {
  return {
    rekordboxXml: config.rekordboxXml ? basename(config.rekordboxXml) : null,
    sampleDirs: config.sampleDirs.map((dir) => basename(dir)),
  };
}

function audioResponse(id: string): Response {
  const entry = audioById.get(id);
  if (!entry || !existsSync(entry.path)) return cors(new Response('audio not indexed', { status: 404 }));
  return cors(new Response(Bun.file(entry.path), {
    headers: {
      'content-type': entry.mime,
      'cache-control': 'no-store',
    },
  }));
}

function loadConfig(): BridgeConfig {
  const configPath = resolve(import.meta.dir, '.bridge.local.json');
  let fileConfig: Partial<BridgeConfig> = {};
  if (existsSync(configPath)) {
    fileConfig = JSON.parse(readFileSync(configPath, 'utf8')) as Partial<BridgeConfig>;
  }
  return {
    rekordboxXml: normalizePath(process.env.JAM_BRIDGE_REKORDBOX_XML ?? fileConfig.rekordboxXml),
    sampleDirs: envList(process.env.JAM_BRIDGE_SAMPLE_DIRS ?? '')
      .concat(fileConfig.sampleDirs ?? [])
      .map(normalizePath)
      .filter((path): path is string => Boolean(path)),
  };
}

function envList(value: string): string[] {
  return value.split(',').map((part) => part.trim()).filter(Boolean);
}

function normalizePath(path: string | undefined): string | undefined {
  if (!path) return undefined;
  if (path.startsWith('~/')) return normalize(join(process.env.HOME ?? '', path.slice(2)));
  return normalize(resolve(path));
}

function object<TPayload>(
  kind: ObjectKind,
  localId: string,
  semanticPath: string,
  linearity: 'affine' | 'relevant',
  payload: TPayload,
  parents: string[] = [],
): BridgeObject<TPayload> {
  return {
    id: `${kind}:${slug(OWNER)}:${slug(localId)}`,
    header: {
      version: 1,
      objectType: kind,
      semanticPath,
      linearity,
      ownerIdentity: OWNER,
      parents,
      commercial: { listed: false, license: 'personal' },
      createdAt: Date.now(),
    },
    payload,
  };
}

function tags(xml: string, name: string): string[] {
  const re = new RegExp(`<${name}\\b[^>]*(?:/>|>[\\s\\S]*?</${name}>)`, 'gi');
  return xml.match(re) ?? [];
}

function attrsFromTag(tag: string): Record<string, string | undefined> {
  const attrs: Record<string, string | undefined> = {};
  const open = tag.slice(0, tag.indexOf('>') + 1);
  for (const match of open.matchAll(/([A-Za-z0-9_:-]+)="([^"]*)"/g)) attrs[match[1]] = entityDecode(match[2]);
  return attrs;
}

function positionMarks(trackTag: string): Array<Record<string, string | undefined>> {
  return tags(trackTag, 'POSITION_MARK').map(attrsFromTag);
}

function playlists(xml: string): Array<{ name: string; path: string[]; trackIds: string[] }> {
  const out: Array<{ name: string; path: string[]; trackIds: string[] }> = [];
  const playlistTags = xml.match(/<NODE\b(?=[^>]*Type="1")[^>]*>[\s\S]*?<\/NODE>/gi) ?? [];
  for (const tag of playlistTags) {
    const attrs = attrsFromTag(tag);
    const name = attrs.Name ?? 'Playlist';
    const trackIds = tags(tag, 'TRACK')
      .map((trackTag) => attrsFromTag(trackTag).Key)
      .filter((id): id is string => Boolean(id));
    out.push({ name, path: [name], trackIds });
  }
  return out;
}

function decodeRekordboxLocation(location: string | undefined): string | undefined {
  if (!location) return undefined;
  try {
    const stripped = location.replace(/^file:\/\/localhost/i, '').replace(/^file:\/\//i, '');
    return decodeURIComponent(stripped);
  } catch {
    return location;
  }
}

function inferPack(path: string): string {
  const parts = path.split(/[\\/]/).filter(Boolean);
  if (parts.length >= 2) return parts[parts.length - 2];
  return 'Loose Samples';
}

function audioIdFor(path: string): string {
  return createHash('sha256').update(path).digest('hex').slice(0, 24);
}

function mimeFor(path: string): string {
  const ext = extname(path).slice(1).toLowerCase();
  if (ext === 'mp3') return 'audio/mpeg';
  if (ext === 'm4a') return 'audio/mp4';
  if (ext === 'ogg') return 'audio/ogg';
  if (ext === 'flac') return 'audio/flac';
  if (ext === 'aif' || ext === 'aiff') return 'audio/aiff';
  return 'audio/wav';
}

function num(value: string | undefined): number | undefined {
  if (!value) return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') || 'object';
}

function entityDecode(value: string): string {
  return value
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&gt;/g, '>')
    .replace(/&lt;/g, '<')
    .replace(/&amp;/g, '&');
}

function json(value: unknown, status = 200): Response {
  return cors(new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  }));
}

function cors(res: Response): Response {
  const headers = new Headers(res.headers);
  headers.set('access-control-allow-origin', '*');
  headers.set('access-control-allow-methods', 'GET,POST,OPTIONS');
  headers.set('access-control-allow-headers', 'content-type');
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
}

```
