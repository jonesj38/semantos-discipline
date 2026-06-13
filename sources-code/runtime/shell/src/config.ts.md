---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.363551+00:00
---

# runtime/shell/src/config.ts

```ts
/**
 * Shell configuration — loads from TOML file + env vars with defaults.
 *
 * Precedence: env vars > ./.semantos.toml > ~/.semantos/config.toml > defaults.
 * No external TOML library — the config format is flat key=value under sections.
 *
 * Phase 19.5: Added [plexus] section support and SEMANTOS_HAT cert resolution.
 */

import { readFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
import type { ShellConfig } from './types';
import type { OutputFormat } from './formatters';

const DEFAULTS: ShellConfig = {
  adapterMode: 'stub',
  activeHatId: null,
  activeHatCertId: null,
  defaultExtension: 'core',
  defaultFormat: 'json',
  plexusMode: 'stub',
  plexusEndpoint: 'http://localhost:9000',
};

/** Parsed TOML sections. */
interface ParsedTOML {
  shell: Record<string, string>;
  plexus: Record<string, string>;
}

/**
 * Parse a minimal TOML file — supports flat key = "value" pairs under [section] headers.
 * Returns records for [shell] and [plexus] sections.
 */
function parseSimpleTOML(content: string): ParsedTOML {
  const result: ParsedTOML = { shell: {}, plexus: {} };
  let currentSection: 'shell' | 'plexus' | null = null;

  for (const rawLine of content.split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;

    // Section header
    if (line.startsWith('[')) {
      if (line === '[shell]') {
        currentSection = 'shell';
      } else if (line === '[plexus]') {
        currentSection = 'plexus';
      } else {
        currentSection = null;
      }
      continue;
    }

    if (!currentSection) continue;

    const eqIndex = line.indexOf('=');
    if (eqIndex === -1) continue;

    const key = line.slice(0, eqIndex).trim();
    let value = line.slice(eqIndex + 1).trim();

    // Strip surrounding quotes
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }

    result[currentSection][key] = value;
  }

  return result;
}

/** Try reading a file, returning null on any error. */
function tryReadFile(path: string): string | null {
  try {
    return readFileSync(path, 'utf-8');
  } catch {
    return null;
  }
}

function isValidAdapterMode(v: string): v is 'stub' | 'local' | 'cloud' {
  return v === 'stub' || v === 'local' || v === 'cloud';
}

function isValidPlexusMode(v: string): v is 'stub' | 'real' | 'cloud' {
  return v === 'stub' || v === 'real' || v === 'cloud';
}

function isValidFormat(v: string): v is OutputFormat {
  return v === 'json' || v === 'table' || v === 'cell' || v === 'csv';
}

/**
 * Load shell configuration from files and environment variables.
 *
 * Precedence: env vars > ./.semantos.toml > ~/.semantos/config.toml > defaults.
 * activeHatCertId is initially null — resolved asynchronously after PlexusService init.
 */
export function loadConfig(): ShellConfig {
  const config: ShellConfig = { ...DEFAULTS };

  // Layer 1: User-home config file (~/.semantos/config.toml)
  const homeContent = tryReadFile(join(homedir(), '.semantos', 'config.toml'));
  if (homeContent) {
    const parsed = parseSimpleTOML(homeContent);
    applyParsed(config, parsed);
  }

  // Layer 2: Project-local config file (./.semantos.toml) — overrides home config
  const localContent = tryReadFile(join(process.cwd(), '.semantos.toml'));
  if (localContent) {
    const parsed = parseSimpleTOML(localContent);
    applyParsed(config, parsed);
  }

  // Layer 3: Environment variables — highest precedence
  const envMode = process.env.SEMANTOS_MODE;
  if (envMode && isValidAdapterMode(envMode)) {
    config.adapterMode = envMode;
  }

  const envFacet = process.env.SEMANTOS_HAT;
  if (envFacet) {
    config.activeHatId = envFacet;
  }

  const envExtension = process.env.SEMANTOS_EXTENSION;
  if (envExtension) {
    config.defaultExtension = envExtension;
  }

  const envFormat = process.env.SEMANTOS_FORMAT;
  if (envFormat && isValidFormat(envFormat)) {
    config.defaultFormat = envFormat;
  }

  const envEndpoint = process.env.SEMANTOS_ENDPOINT;
  if (envEndpoint) {
    config.apiEndpoint = envEndpoint;
  }

  // Plexus env vars
  const envPlexusMode = process.env.PLEXUS_MODE;
  if (envPlexusMode && isValidPlexusMode(envPlexusMode)) {
    config.plexusMode = envPlexusMode;
  }

  const envPlexusEndpoint = process.env.PLEXUS_ENDPOINT;
  if (envPlexusEndpoint) {
    config.plexusEndpoint = envPlexusEndpoint;
  }

  return config;
}

/** Apply parsed TOML values to a config object. */
function applyParsed(config: ShellConfig, parsed: ParsedTOML): void {
  // [shell] section
  const shell = parsed.shell;
  if (shell.adapter_mode && isValidAdapterMode(shell.adapter_mode)) {
    config.adapterMode = shell.adapter_mode;
  }
  if (shell.active_hat) {
    config.activeHatId = shell.active_hat;
  }
  if (shell.default_extension) {
    config.defaultExtension = shell.default_extension;
  }
  if (shell.default_format && isValidFormat(shell.default_format)) {
    config.defaultFormat = shell.default_format;
  }
  if (shell.api_endpoint) {
    config.apiEndpoint = shell.api_endpoint;
  }

  // [plexus] section
  const plexus = parsed.plexus;
  if (plexus.mode && isValidPlexusMode(plexus.mode)) {
    config.plexusMode = plexus.mode;
  }
  if (plexus.endpoint) {
    config.plexusEndpoint = plexus.endpoint;
  }
}

```
