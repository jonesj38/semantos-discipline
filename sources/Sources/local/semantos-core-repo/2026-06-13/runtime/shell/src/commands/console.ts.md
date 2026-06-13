---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/commands/console.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.374481+00:00
---

# runtime/shell/src/commands/console.ts

```ts
/**
 * Console and mount commands — launched as top-level subcommands
 * (not verb-routed) from the shell entry point.
 *
 * semantos console              — launch full tmux loom
 * semantos console --pane NAME  — launch single pane
 * semantos mount [path]         — mount VFS
 * semantos unmount [path]       — unmount VFS
 */

import type { ShellContext } from '../types';
import { SemantosTmuxSession, type TmuxSessionConfig, type PaneName } from '../tmux/layout';
import { StoreBridgeServer, StoreBridgeClient, defaultSocketPath } from '../tmux/bridge';
import { ObjectTreePane } from '../tmux/object-tree';
import { InspectorPane } from '../tmux/inspector';
import { EventLogPane } from '../tmux/event-log';
import { SemanticVFS } from '../vfs/mount';

// ── Arg parsing ──────────────────────────────────────────────

interface ConsoleArgs {
  pane?: PaneName;
  socket?: string;
  height?: number;
  width?: number;
  config?: string;
  inspect?: string;
  noVfs?: boolean;
}

interface MountArgs {
  path: string;
  user?: boolean;
  readOnly?: boolean;
  force?: boolean;
}

function parseConsoleArgs(args: string[]): ConsoleArgs {
  const result: ConsoleArgs = {};
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--pane':
        result.pane = args[++i] as PaneName;
        break;
      case '--socket':
        result.socket = args[++i];
        break;
      case '--height':
        result.height = parseInt(args[++i], 10);
        break;
      case '--width':
        result.width = parseInt(args[++i], 10);
        break;
      case '--config':
        result.config = args[++i];
        break;
      case '--inspect':
        result.inspect = args[++i];
        break;
      case '--no-vfs':
        result.noVfs = true;
        break;
    }
  }
  return result;
}

function parseMountArgs(args: string[]): MountArgs {
  const result: MountArgs = { path: '/semantos' };
  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--path':
        result.path = args[++i];
        break;
      case '--user':
        result.user = true;
        break;
      case '--read-only':
        result.readOnly = true;
        break;
      case '--force':
        result.force = true;
        break;
      default:
        if (!args[i].startsWith('--') && i === 0) {
          result.path = args[i];
        }
    }
  }
  return result;
}

// ── Console handler ──────────────────────────────────────────

export async function handleConsole(args: string[], ctx: ShellContext): Promise<void> {
  const opts = parseConsoleArgs(args);

  if (opts.pane) {
    // Single pane mode — connect to bridge and run the pane
    await runSinglePane(opts.pane, opts.socket, ctx, opts.inspect);
    return;
  }

  // Full tmux session mode
  const sessionConfig: TmuxSessionConfig = {
    width: opts.width,
    height: opts.height,
    configPath: opts.config,
    inspectObjectId: opts.inspect,
    noVfs: opts.noVfs,
  };

  const session = new SemantosTmuxSession(sessionConfig);
  const socketPath = session.getSocketPath();

  // Start bridge server
  const bridge = new StoreBridgeServer(ctx.store, socketPath);
  await bridge.start();

  // Mount VFS if not disabled
  let vfs: SemanticVFS | null = null;
  if (!opts.noVfs) {
    try {
      vfs = new SemanticVFS(ctx.store, ctx.identity, ctx.config);
      await vfs.mount();
    } catch {
      // VFS mount is best-effort — continue without it
      vfs = null;
    }
  }

  // Launch tmux session (blocks until tmux exits)
  try {
    session.exec();
  } finally {
    // Cleanup
    bridge.stop();
    if (vfs?.isMounted()) {
      await vfs.unmount().catch(() => {});
    }
  }
}

/** Run a single pane connected to the bridge. */
async function runSinglePane(
  pane: PaneName,
  socketPath: string | undefined,
  ctx: ShellContext,
  inspectObjectId?: string,
): Promise<void> {
  // If no socket path, run against the local store directly
  const useLocal = !socketPath;
  let client: StoreBridgeClient | null = null;

  if (!useLocal) {
    client = new StoreBridgeClient(socketPath!);
    await client.connect();
  }

  const source = useLocal ? ctx.store : client!;

  switch (pane) {
    case 'objects': {
      const tree = new ObjectTreePane(source);
      tree.subscribe();

      // Set up selection forwarding via bridge
      if (client) {
        tree.onSelect((objectId: string) => client!.sendSelect(objectId));
      }

      // In a real blessed session, we'd create a screen here.
      // For now, set up the pane and let process.stdin drive keyboard input.
      await runBlessedPane(tree, 'objects');
      tree.destroy();
      break;
    }
    case 'inspector': {
      const inspector = new InspectorPane(source);
      const hat = ctx.identity.getActiveHat();
      if (hat) inspector.setFacetCapabilities(hat.capabilities);
      if (inspectObjectId) inspector.inspect(inspectObjectId);
      inspector.subscribe();
      await runBlessedPane(inspector, 'inspector');
      inspector.destroy();
      break;
    }
    case 'events': {
      const events = new EventLogPane(source);
      events.subscribe();
      await runBlessedPane(events, 'events');
      events.destroy();
      break;
    }
    case 'shell': {
      // Shell pane — just run the REPL
      const { Shell } = await import('../shell');
      const shell = new Shell(ctx);
      await shell.repl();
      break;
    }
  }

  client?.disconnect();
}

/** Run a blessed-based TUI for a pane. */
async function runBlessedPane(
  pane: ObjectTreePane | InspectorPane | EventLogPane,
  paneName: string,
): Promise<void> {
  let blessed: any;
  try {
    blessed = await import('blessed');
    if (blessed.default) blessed = blessed.default;
  } catch {
    // Fallback: simple line-by-line output
    await runFallbackPane(pane, paneName);
    return;
  }

  const screen = blessed.screen({
    smartCSR: true,
    title: `semantos ${paneName}`,
  });

  const box = blessed.box({
    top: 0,
    left: 0,
    width: '100%',
    height: '100%',
    scrollable: true,
    alwaysScroll: true,
    scrollbar: { ch: ' ', track: { bg: 'grey' } },
    keys: true,
    vi: true,
  });

  screen.append(box);

  // Render callback
  const render = (lines: string[], ..._rest: unknown[]) => {
    box.setContent(lines.join('\n'));
    screen.render();
  };

  if (pane instanceof ObjectTreePane) {
    pane.onRender(render);
  } else if (pane instanceof InspectorPane) {
    pane.onRender(render);
  } else if (pane instanceof EventLogPane) {
    pane.onRender(render);
  }

  // Key bindings
  screen.key(['q', 'C-c'], () => {
    screen.destroy();
  });

  screen.key(['up', 'down', 'tab', 'return', '/'], (ch: string, key: { name: string }) => {
    pane.handleKey(key.name);
  });

  screen.key(['p', 'r', 'c'], (ch: string) => {
    pane.handleKey(ch);
  });

  return new Promise<void>((resolve) => {
    screen.on('destroy', resolve);
    screen.render();
  });
}

/** Fallback rendering when blessed is not available. */
async function runFallbackPane(
  pane: ObjectTreePane | InspectorPane | EventLogPane,
  _paneName: string,
): Promise<void> {
  const render = (lines: string[]) => {
    process.stdout.write('\x1b[2J\x1b[H'); // Clear screen
    for (const line of lines) {
      process.stdout.write(line + '\n');
    }
  };

  if (pane instanceof ObjectTreePane) {
    pane.onRender(render);
  } else if (pane instanceof InspectorPane) {
    pane.onRender(render);
  } else if (pane instanceof EventLogPane) {
    pane.onRender(render);
  }

  // Keep process alive until stdin closes
  return new Promise<void>((resolve) => {
    if (process.stdin.isTTY) {
      process.stdin.setRawMode(true);
    }
    process.stdin.resume();
    process.stdin.on('data', (data: Buffer) => {
      const ch = data.toString();
      if (ch === 'q' || ch === '\x03') {
        resolve();
      } else {
        pane.handleKey(ch);
      }
    });
    process.stdin.on('end', resolve);
  });
}

// ── Mount handler ────────────────────────────────────────────

export async function handleMount(args: string[], ctx: ShellContext): Promise<string> {
  const opts = parseMountArgs(args);
  const vfs = new SemanticVFS(ctx.store, ctx.identity, ctx.config, opts.path);

  try {
    await vfs.mount();
    return `Mounted semantic VFS at ${opts.path}`;
  } catch (err) {
    return `Failed to mount VFS: ${err instanceof Error ? err.message : String(err)}`;
  }
}

// ── Unmount handler ──────────────────────────────────────────

export async function handleUnmount(args: string[], _ctx: ShellContext): Promise<string> {
  const opts = parseMountArgs(args);

  // Use fusermount or umount to unmount
  const { execSync } = await import('child_process');
  try {
    if (opts.force) {
      execSync(`fusermount -u -z ${opts.path} 2>/dev/null || umount -f ${opts.path}`, { stdio: 'pipe' });
    } else {
      execSync(`fusermount -u ${opts.path} 2>/dev/null || umount ${opts.path}`, { stdio: 'pipe' });
    }
    return `Unmounted VFS at ${opts.path}`;
  } catch (err) {
    return `Failed to unmount VFS: ${err instanceof Error ? err.message : String(err)}`;
  }
}

```
