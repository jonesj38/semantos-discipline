---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/tmux/layout.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.378717+00:00
---

# runtime/shell/src/tmux/layout.ts

```ts
/**
 * SemantosTmuxSession — programmatic tmux session creation and management.
 *
 * Creates a tmux session with 4 panes:
 *   - objects (20%) — live object tree
 *   - shell (55%)   — semantic shell REPL
 *   - inspector (25%) — object inspector
 *   - events (bottom, 4 lines) — event log
 *
 * Config persisted to ~/.semantos/console.toml.
 */

import { execSync } from 'child_process';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';
import { homedir, tmpdir } from 'os';
import { defaultSocketPath } from './bridge';

// ── Types ────────────────────────────────────────────────────

export interface TmuxSessionConfig {
  sessionName?: string;
  width?: number;
  height?: number;
  configPath?: string;
  inspectObjectId?: string;
  noVfs?: boolean;
}

export interface ConsoleLayoutConfig {
  layout: {
    width: number;
    height: number;
  };
  panes: {
    objects: { width_percent: number; columns: string[] };
    shell: { width_percent: number };
    inspector: { width_percent: number };
    events: { height_lines: number; buffer_size: number };
  };
  colors: {
    theme: string;
  };
}

export type PaneName = 'objects' | 'shell' | 'inspector' | 'events';

// ── Default config ───────────────────────────────────────────

const DEFAULT_CONFIG: ConsoleLayoutConfig = {
  layout: { width: 200, height: 50 },
  panes: {
    objects: { width_percent: 20, columns: ['id', 'linearity', 'phase', 'visibility'] },
    shell: { width_percent: 55 },
    inspector: { width_percent: 25 },
    events: { height_lines: 4, buffer_size: 1000 },
  },
  colors: { theme: 'dark' },
};

// ── Minimal TOML serialization/parsing ──────────────────────

function configToToml(cfg: ConsoleLayoutConfig): string {
  const lines: string[] = [];
  lines.push('[layout]');
  lines.push(`width = ${cfg.layout.width}`);
  lines.push(`height = ${cfg.layout.height}`);
  lines.push('');
  lines.push('[panes.objects]');
  lines.push(`width_percent = ${cfg.panes.objects.width_percent}`);
  lines.push(`columns = [${cfg.panes.objects.columns.map(c => `"${c}"`).join(', ')}]`);
  lines.push('');
  lines.push('[panes.shell]');
  lines.push(`width_percent = ${cfg.panes.shell.width_percent}`);
  lines.push('');
  lines.push('[panes.inspector]');
  lines.push(`width_percent = ${cfg.panes.inspector.width_percent}`);
  lines.push('');
  lines.push('[panes.events]');
  lines.push(`height_lines = ${cfg.panes.events.height_lines}`);
  lines.push(`buffer_size = ${cfg.panes.events.buffer_size}`);
  lines.push('');
  lines.push('[colors]');
  lines.push(`theme = "${cfg.colors.theme}"`);
  return lines.join('\n') + '\n';
}

function parseTomlConfig(content: string): Partial<ConsoleLayoutConfig> {
  const result: Record<string, Record<string, unknown>> = {};
  let currentSection = '';

  for (const rawLine of content.split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;

    const sectionMatch = line.match(/^\[(.+)\]$/);
    if (sectionMatch) {
      currentSection = sectionMatch[1];
      continue;
    }

    const kvMatch = line.match(/^(\w+)\s*=\s*(.+)$/);
    if (kvMatch && currentSection) {
      if (!result[currentSection]) result[currentSection] = {};
      const val = kvMatch[2].trim();
      if (val.startsWith('[')) {
        // Parse array of strings
        const items = val.slice(1, -1).split(',').map(s => s.trim().replace(/"/g, ''));
        result[currentSection][kvMatch[1]] = items;
      } else if (val.startsWith('"')) {
        result[currentSection][kvMatch[1]] = val.replace(/"/g, '');
      } else {
        result[currentSection][kvMatch[1]] = parseInt(val, 10);
      }
    }
  }

  const cfg: Partial<ConsoleLayoutConfig> = {};
  if (result['layout']) {
    cfg.layout = {
      width: (result['layout'].width as number) ?? DEFAULT_CONFIG.layout.width,
      height: (result['layout'].height as number) ?? DEFAULT_CONFIG.layout.height,
    };
  }
  if (result['panes.objects']) {
    cfg.panes = {
      ...(cfg.panes ?? DEFAULT_CONFIG.panes),
      objects: {
        width_percent: (result['panes.objects'].width_percent as number) ?? DEFAULT_CONFIG.panes.objects.width_percent,
        columns: (result['panes.objects'].columns as string[]) ?? DEFAULT_CONFIG.panes.objects.columns,
      },
    };
  }
  if (result['panes.shell']) {
    cfg.panes = {
      ...(cfg.panes ?? DEFAULT_CONFIG.panes),
      shell: {
        width_percent: (result['panes.shell'].width_percent as number) ?? DEFAULT_CONFIG.panes.shell.width_percent,
      },
    };
  }
  if (result['panes.inspector']) {
    cfg.panes = {
      ...(cfg.panes ?? DEFAULT_CONFIG.panes),
      inspector: {
        width_percent: (result['panes.inspector'].width_percent as number) ?? DEFAULT_CONFIG.panes.inspector.width_percent,
      },
    };
  }
  if (result['panes.events']) {
    cfg.panes = {
      ...(cfg.panes ?? DEFAULT_CONFIG.panes),
      events: {
        height_lines: (result['panes.events'].height_lines as number) ?? DEFAULT_CONFIG.panes.events.height_lines,
        buffer_size: (result['panes.events'].buffer_size as number) ?? DEFAULT_CONFIG.panes.events.buffer_size,
      },
    };
  }
  if (result['colors']) {
    cfg.colors = {
      theme: (result['colors'].theme as string) ?? DEFAULT_CONFIG.colors.theme,
    };
  }

  return cfg;
}

// ── Session class ────────────────────────────────────────────

export class SemantosTmuxSession {
  private sessionName: string;
  private config: ConsoleLayoutConfig;
  private socketPath: string;
  private paneIds: Record<PaneName, string> = {
    objects: '',
    shell: '',
    inspector: '',
    events: '',
  };

  constructor(opts?: TmuxSessionConfig) {
    this.sessionName = opts?.sessionName ?? 'semantos-console';
    this.config = this.loadLayoutConfig(opts?.configPath);
    this.socketPath = defaultSocketPath(this.sessionName);

    if (opts?.width) this.config.layout.width = opts.width;
    if (opts?.height) this.config.layout.height = opts.height;
  }

  /** Get the resolved layout config. */
  getConfig(): ConsoleLayoutConfig {
    return this.config;
  }

  /** Get the socket path for IPC. */
  getSocketPath(): string {
    return this.socketPath;
  }

  /** Get the tmux pane target for a named pane. */
  getPane(name: PaneName): string {
    return this.paneIds[name];
  }

  /**
   * Launch the full 4-pane tmux session.
   *
   * Layout:
   * ┌────────────────┬─────────────────────────┬──────────────┐
   * │ objects (20%)   │ shell (55%)             │ inspector(25%)│
   * ├────────────────┴─────────────────────────┴──────────────┤
   * │ events (4 lines)                                         │
   * └─────────────────────────────────────────────────────────┘
   */
  launch(): string[] {
    const cmds: string[] = [];
    const sess = this.sessionName;
    const bin = process.argv[1] ?? 'semantos';
    const sock = this.socketPath;

    // Compute pane sizes
    const eventsHeight = this.config.panes.events.height_lines + 1; // +1 for border
    const objectsPercent = this.config.panes.objects.width_percent;
    const inspectorPercent = this.config.panes.inspector.width_percent;

    // Create session with the shell pane (center) as the initial pane
    cmds.push(
      `tmux new-session -d -s ${sess} -x ${this.config.layout.width} -y ${this.config.layout.height} ` +
      `"${bin} --socket ${sock}"`,
    );
    this.paneIds.shell = `${sess}:0.0`;

    // Split bottom for events (horizontal split of the full width)
    cmds.push(
      `tmux split-window -t ${sess}:0.0 -v -l ${eventsHeight} ` +
      `"${bin} console --pane events --socket ${sock}"`,
    );
    this.paneIds.events = `${sess}:0.1`;

    // Split the top pane (shell) to create objects on the left
    cmds.push(
      `tmux split-window -t ${sess}:0.0 -h -b -l ${objectsPercent}% ` +
      `"${bin} console --pane objects --socket ${sock}"`,
    );
    this.paneIds.objects = `${sess}:0.0`;
    // shell is now 0.1
    this.paneIds.shell = `${sess}:0.1`;

    // Split the shell pane to create inspector on the right
    cmds.push(
      `tmux split-window -t ${sess}:0.1 -h -l ${inspectorPercent}% ` +
      `"${bin} console --pane inspector --socket ${sock}"`,
    );
    this.paneIds.inspector = `${sess}:0.2`;

    // Select the shell pane as active
    cmds.push(`tmux select-pane -t ${this.paneIds.shell}`);

    // Attach to the session
    cmds.push(`tmux attach-session -t ${sess}`);

    return cmds;
  }

  /** Execute the tmux commands to launch the session. */
  exec(): void {
    const cmds = this.launch();
    for (const cmd of cmds) {
      execSync(cmd, { stdio: 'inherit' });
    }
  }

  /** Generate the command for launching a single pane (for embedding). */
  launchSinglePane(pane: PaneName, socketPath?: string): string {
    const bin = process.argv[1] ?? 'semantos';
    const sock = socketPath ?? this.socketPath;
    return `${bin} console --pane ${pane} --socket ${sock}`;
  }

  /** Load layout config from TOML file, creating default if not exists. */
  private loadLayoutConfig(configPath?: string): ConsoleLayoutConfig {
    const cfgPath = configPath ?? join(homedir(), '.semantos', 'console.toml');
    const cfgDir = join(homedir(), '.semantos');

    if (existsSync(cfgPath)) {
      try {
        const content = readFileSync(cfgPath, 'utf-8');
        const partial = parseTomlConfig(content);
        return {
          layout: partial.layout ?? DEFAULT_CONFIG.layout,
          panes: {
            objects: partial.panes?.objects ?? DEFAULT_CONFIG.panes.objects,
            shell: partial.panes?.shell ?? DEFAULT_CONFIG.panes.shell,
            inspector: partial.panes?.inspector ?? DEFAULT_CONFIG.panes.inspector,
            events: partial.panes?.events ?? DEFAULT_CONFIG.panes.events,
          },
          colors: partial.colors ?? DEFAULT_CONFIG.colors,
        };
      } catch {
        return { ...DEFAULT_CONFIG };
      }
    }

    // Create default config
    try {
      if (!existsSync(cfgDir)) {
        mkdirSync(cfgDir, { recursive: true });
      }
      writeFileSync(cfgPath, configToToml(DEFAULT_CONFIG));
    } catch {
      // Cannot write config — use defaults
    }

    return { ...DEFAULT_CONFIG };
  }
}

export { DEFAULT_CONFIG, configToToml, parseTomlConfig };

```
