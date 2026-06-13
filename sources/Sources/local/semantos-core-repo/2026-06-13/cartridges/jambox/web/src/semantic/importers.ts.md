---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/semantic/importers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.611194+00:00
---

# cartridges/jambox/web/src/semantic/importers.ts

```ts
import {
  createRekordboxCrateObject,
  createRekordboxTrackObject,
  createSpliceSampleObject,
  createSpliceSamplePackObject,
  type JamboxCrateObject,
  type JamboxSampleObject,
  type JamboxSamplePackObject,
  type JamboxTrackObject,
} from './objects';

export interface RekordboxImportResult {
  source: 'rekordbox';
  tracks: JamboxTrackObject[];
  crates: JamboxCrateObject[];
}

export interface SpliceFolderImportResult {
  source: 'splice-folder';
  packs: JamboxSamplePackObject[];
  samples: JamboxSampleObject[];
}

type PlaylistNode = {
  name: string;
  trackIds: string[];
  children: PlaylistNode[];
};

const AUDIO_EXTENSIONS = new Set([
  'aif', 'aiff', 'flac', 'm4a', 'mp3', 'ogg', 'wav', 'wave',
]);

export function importRekordboxXml(ownerIdentity: string, xmlText: string): RekordboxImportResult {
  const doc = new DOMParser().parseFromString(xmlText, 'application/xml');
  const parserError = doc.querySelector('parsererror');
  if (parserError) throw new Error('That XML could not be parsed.');

  const trackObjectsById = new Map<string, JamboxTrackObject>();
  doc.querySelectorAll('COLLECTION > TRACK').forEach((trackEl, index) => {
    const sourceTrackId = attr(trackEl, 'TrackID') ?? String(index + 1);
    const title = attr(trackEl, 'Name') ?? `Track ${sourceTrackId}`;
    const trackObject = createRekordboxTrackObject({
      ownerIdentity,
      sourceTrackId,
      title,
      artist: attr(trackEl, 'Artist') ?? undefined,
      album: attr(trackEl, 'Album') ?? undefined,
      location: decodeLocation(attr(trackEl, 'Location')),
      bpm: numberAttr(trackEl, 'AverageBpm'),
      key: attr(trackEl, 'Tonality') ?? undefined,
      totalTimeSeconds: numberAttr(trackEl, 'TotalTime'),
      cues: [...trackEl.querySelectorAll('POSITION_MARK')].map((mark) => ({
        name: attr(mark, 'Name') ?? undefined,
        type: attr(mark, 'Type') ?? undefined,
        startSeconds: numberAttr(mark, 'Start'),
      })),
    });
    trackObjectsById.set(sourceTrackId, trackObject);
  });

  const crates: JamboxCrateObject[] = [];
  const rootNode = doc.querySelector('PLAYLISTS > NODE');
  if (rootNode) {
    for (const playlist of readPlaylistNodes(rootNode)) {
      collectCrates(ownerIdentity, playlist, [], trackObjectsById, crates);
    }
  }

  if (crates.length === 0 && trackObjectsById.size > 0) {
    crates.push(createRekordboxCrateObject({
      ownerIdentity,
      label: 'Rekordbox Collection',
      playlistPath: ['Rekordbox Collection'],
      trackObjectIds: [...trackObjectsById.values()].map((track) => track.id),
    }));
  }

  return {
    source: 'rekordbox',
    tracks: [...trackObjectsById.values()],
    crates,
  };
}

export function importSpliceFolder(ownerIdentity: string, files: FileList | File[]): SpliceFolderImportResult {
  const samples: JamboxSampleObject[] = [];
  const samplesByPack = new Map<string, JamboxSampleObject[]>();

  for (const file of Array.from(files)) {
    const relativePath = relativeFilePath(file);
    const extension = fileExtension(relativePath);
    if (!AUDIO_EXTENSIONS.has(extension)) continue;
    const pack = inferPack(relativePath);
    const sample = createSpliceSampleObject({
      ownerIdentity,
      name: file.name,
      relativePath,
      pack,
      sizeBytes: file.size,
      extension,
    });
    samples.push(sample);
    const packSamples = samplesByPack.get(pack) ?? [];
    packSamples.push(sample);
    samplesByPack.set(pack, packSamples);
  }

  const packs = [...samplesByPack.entries()].map(([pack, packSamples]) =>
    createSpliceSamplePackObject({
      ownerIdentity,
      label: pack,
      relativePath: pack,
      sampleObjectIds: packSamples.map((sample) => sample.id),
    }));

  return { source: 'splice-folder', packs, samples };
}

function collectCrates(
  ownerIdentity: string,
  node: PlaylistNode,
  parentPath: string[],
  tracksById: Map<string, JamboxTrackObject>,
  crates: JamboxCrateObject[],
): void {
  const path = [...parentPath, node.name].filter(Boolean);
  const trackObjectIds = node.trackIds
    .map((id) => tracksById.get(id)?.id)
    .filter((id): id is string => Boolean(id));
  if (trackObjectIds.length > 0) {
    crates.push(createRekordboxCrateObject({
      ownerIdentity,
      label: node.name,
      playlistPath: path,
      trackObjectIds,
    }));
  }
  for (const child of node.children) collectCrates(ownerIdentity, child, path, tracksById, crates);
}

function readPlaylistNodes(root: Element): PlaylistNode[] {
  const nodes: PlaylistNode[] = [];
  root.querySelectorAll(':scope > NODE').forEach((nodeEl) => {
    nodes.push({
      name: attr(nodeEl, 'Name') ?? 'Playlist',
      trackIds: [...nodeEl.querySelectorAll(':scope > TRACK')]
        .map((trackEl) => attr(trackEl, 'Key'))
        .filter((id): id is string => Boolean(id)),
      children: readPlaylistNodes(nodeEl),
    });
  });
  return nodes;
}

function attr(el: Element, name: string): string | null {
  const value = el.getAttribute(name);
  return value === '' ? null : value;
}

function numberAttr(el: Element, name: string): number | undefined {
  const value = attr(el, name);
  if (!value) return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function decodeLocation(location: string | null): string | undefined {
  if (!location) return undefined;
  try {
    return decodeURIComponent(location.replace(/^file:\/\//, ''));
  } catch {
    return location;
  }
}

function relativeFilePath(file: File): string {
  const withDirectory = file as File & { webkitRelativePath?: string };
  return withDirectory.webkitRelativePath || file.name;
}

function fileExtension(path: string): string {
  const idx = path.lastIndexOf('.');
  return idx === -1 ? '' : path.slice(idx + 1).toLowerCase();
}

function inferPack(relativePath: string): string {
  const parts = relativePath.split('/').filter(Boolean);
  if (parts.length >= 2) return parts[parts.length - 2];
  return 'Loose Samples';
}

```
