---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.364366+00:00
---

# runtime/shell/src/index.ts

```ts
#!/usr/bin/env node
/**
 * Semantic shell entry point — CLI binary for @semantos/shell.
 *
 * Detects REPL vs single-command mode from process.argv.
 * Wires up shared service instances from @semantos/runtime-services.
 *
 * Phase 19.5: Initializes PlexusService and resolves hat certId on startup.
 */

import { Shell } from './shell';
import { loadConfig } from './config';
import { LoomStore, FlowRunner, IdentityStore, ConfigStore, SettingsStore, initializePlexusService, intentTaxonomy } from '@semantos/runtime-services';
import { createAdapter, CellStore, SemanticFS } from '@semantos/protocol-types';
import { handleConsole, handleMount, handleUnmount } from './commands/console';
import { handleFs } from './commands/fs';
import type { ShellContext, IntentPipelineWiring } from './types';
import { TransferService } from './transfer-service';
import type { StorageAdapter } from '@semantos/protocol-types';
import { createShellPipelineDeps } from './intent-adapters/shell-pipeline-deps';

// Side-effect import: registers every host-exec handler manifest + impl
// on the shared registry. Must be imported for host.exec to find any
// handler to dispatch — without this the daemon would echo the same
// UNKNOWN_HANDLER the browser sees.
import './host-exec/handlers';

/** Top-level subcommands intercepted before verb routing. */
const TOP_LEVEL_COMMANDS = new Set(['console', 'mount', 'unmount', 'fs']);

/**
 * Load extension shell-handlers via dynamic import.
 *
 * Each entry in `enabledExtensions` corresponds to a workspace package
 * (`@semantos/<name>`) that exposes a `./shell-handler` subpath. Importing
 * that subpath has the side effect of calling `registerVerb(...)` on the
 * runtime-services verb registry, wiring the extension's verbs into
 * shell's router.
 *
 * Dynamic imports with template-literal specifiers are used DELIBERATELY:
 * they keep the static-import graph clean (the import-boundary gate looks
 * at static imports and never sees these), so shell stays in the runtime/
 * tier without a forbidden dependency on extensions/.
 *
 * To add a new extension, add its name here and the appropriate
 * @semantos/<name>/shell-handler subpath export in the extension's
 * package.json.
 */
async function loadExtensions(enabledExtensions: string[]): Promise<void> {
  for (const name of enabledExtensions) {
    try {
      // Template literal — opaque to static analysis, intentional.
      await import(`@semantos/${name}/shell-handler`);
    } catch (err) {
      console.warn(
        `[shell] failed to load @semantos/${name}/shell-handler:`,
        err instanceof Error ? err.message : err,
      );
    }
  }
}

/**
 * Build the intent-pipeline wiring when INTENT_PIPELINE=1.
 *
 * Lazy-imports cell-engine + session-protocol so the shell binary
 * doesn't pay the WASM load cost (or the BSV SDK import) on every
 * startup — only when the user opts in.
 */
async function buildIntentPipelineWiring(
  adapter: StorageAdapter,
  activeExtension: string,
): Promise<IntentPipelineWiring> {
  const [{ loadCellEngine }, { StubSigner }] = await Promise.all([
    import('@semantos/cell-engine/bindings/bun/loader'),
    import('@semantos/session-protocol/signer'),
  ]);

  const engine = await loadCellEngine({ profile: 'full' });
  const signer = new StubSigner();

  const deps = await createShellPipelineDeps({
    engine,
    storage: adapter,
    signer,
    mode: 'authoring',
  });

  return {
    deps,
    extension: {
      extensionId: activeExtension,
      // Domain flag — derived from extension config in later passes. For
      // now, 1 is the trades-vertical default; real extensions override
      // via their governance config.
      domainFlag: 1,
    },
    generateId: () => crypto.randomUUID(),
  };
}

async function main(): Promise<void> {
  const shellConfig = loadConfig();

  // Wire extension verbs (cdm, eventually extraction, games, …) into the
  // verb registry before any command can be routed. Driven by config so
  // the binary doesn't statically know about each extension package.
  await loadExtensions(['cdm', 'extraction', 'games']);

  // Create storage adapter (Node.js environment → NodeFsAdapter)
  const adapter = await createAdapter();

  // Create shared service instances with adapter injection
  const store = new LoomStore();
  const flowRunner = new FlowRunner();
  const identity = new IdentityStore(adapter);
  const config = new ConfigStore(adapter);
  const settings = new SettingsStore(adapter);

  // Load persisted state from adapter
  await Promise.all([
    identity.initFromAdapter(),
    config.initFromAdapter(),
    settings.initFromAdapter(),
  ]);

  // Initialize PlexusService with configured mode
  const plexus = initializePlexusService({
    mode: shellConfig.plexusMode === 'real' ? 'local' : shellConfig.plexusMode === 'cloud' ? 'cloud' : 'stub',
    endpoint: shellConfig.plexusEndpoint,
  });

  // Initialize config with the configured vertical
  try {
    await config.switchExtension(shellConfig.defaultExtension);
  } catch {
    // Config load may fail in stub mode — continue with no config
  }

  // If a hat is configured but no identity exists, create one
  if (shellConfig.activeHatId && !identity.isSetupComplete()) {
    await identity.createIdentity('shell-user');
  }

  // Switch to configured hat if available
  if (shellConfig.activeHatId) {
    identity.switchHat(shellConfig.activeHatId);
  }

  // Resolve hat certId via PlexusService if hat is set
  let activeHatCertId: string | null = null;
  if (shellConfig.activeHatId) {
    const hat = identity.getActiveHat();
    if (hat?.certId) {
      activeHatCertId = hat.certId;
    }
  }

  // Create CellStore and SemanticFS (Phase 25C)
  const cellStore = new CellStore(adapter);
  const semanticFs = new SemanticFS({
    cellStore,
    adapter,
    taxonomy: intentTaxonomy,
  });

  const ctx: ShellContext = {
    store,
    flowRunner,
    identity,
    config,
    settings,
    plexus,
    adapter,
    semanticFs,
    activeExtension: shellConfig.defaultExtension,
    activeHatId: shellConfig.activeHatId,
    activeHatCertId,
    defaultFormat: shellConfig.defaultFormat,
    // Metered Content Transfer as shell substrate. Lazy — opens no socket until
    // the first share/fetch, so this is free for shells that never transfer.
    transfer: new TransferService(),
  };

  // Slice 3: optional intent-pipeline wiring. Opt in with
  // INTENT_PIPELINE=1. When enabled, mutation verbs route through
  // runtime/intent's processIntent and produce cryptographically
  // signed receipts. When absent, the shell behaves as before.
  if (process.env.INTENT_PIPELINE === '1') {
    try {
      ctx.intentPipeline = await buildIntentPipelineWiring(
        adapter,
        shellConfig.defaultExtension,
      );
      process.stderr.write(
        '[shell] intent pipeline enabled — mutation verbs will route through processIntent\n',
      );
    } catch (err) {
      process.stderr.write(
        `[shell] INTENT_PIPELINE=1 set but failed to wire pipeline: ${
          err instanceof Error ? err.message : String(err)
        }\n[shell] falling back to direct-path dispatch\n`,
      );
    }
  }

  const args = process.argv.slice(2);

  // Intercept top-level subcommands before verb routing
  if (args.length > 0 && TOP_LEVEL_COMMANDS.has(args[0])) {
    const subcommand = args[0];
    const subArgs = args.slice(1);

    switch (subcommand) {
      case 'console':
        await handleConsole(subArgs, ctx);
        return;
      case 'mount': {
        const msg = await handleMount(subArgs, ctx);
        process.stdout.write(msg + '\n');
        return;
      }
      case 'unmount': {
        const msg = await handleUnmount(subArgs, ctx);
        process.stdout.write(msg + '\n');
        return;
      }
      case 'fs': {
        const msg = await handleFs(subArgs, ctx.semanticFs);
        process.stdout.write(msg + '\n');
        return;
      }
    }
  }

  const shell = new Shell(ctx);

  if (args.length === 0) {
    await shell.repl();
  } else {
    try {
      const output = await shell.execute(args);
      process.stdout.write(output + '\n');
    } catch (err) {
      process.stderr.write(`Error: ${err instanceof Error ? err.message : String(err)}\n`);
      process.exit(1);
    }
  }
}

main().catch(err => {
  process.stderr.write(`Fatal: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exit(1);
});

export { Shell } from './shell';
export { parseCommand, KNOWN_VERBS } from './parser';
export type { ShellCommand, ShellVerb } from './parser';
export { route } from './router';
export { OutputFormatter, parseOutputFormat } from './formatters';
export type { OutputFormat } from './formatters';
export { loadConfig } from './config';
export type { ShellConfig, ShellContext } from './types';
export { REPLShell } from './repl';
export { CAPABILITY_MAP, getRequiredCapability, getCapabilityName, MUTATION_VERBS } from './capabilities';
export { routeIdentity, routeWhoami, routeCapabilities } from './identity';

// Phase 20: tmux loom
export { SemantosTmuxSession } from './tmux/layout';
export type { TmuxSessionConfig, ConsoleLayoutConfig, PaneName } from './tmux/layout';
export { StoreBridgeServer, StoreBridgeClient, defaultSocketPath } from './tmux/bridge';
export { ObjectTreePane } from './tmux/object-tree';
export { InspectorPane } from './tmux/inspector';
export { EventLogPane } from './tmux/event-log';
export { handleConsole, handleMount, handleUnmount } from './commands/console';

// Phase 38F: NL → ShellCommand extractor
export { extractShellCommand } from './host-exec/extractor';
export type { ExtractResult, ExtractedCommand, ExtractError, ExtractorContext, LlmClient } from './host-exec/extractor/types';

// Phase 25C: fs subcommands
export { handleFs } from './commands/fs';

// Phase 20: VFS
export { SemanticVFS } from './vfs/mount';
export { VfsPathResolver } from './vfs/pathResolver';

```
