---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/host-exec/handlers/process-kill-by-port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.395113+00:00
---

# runtime/shell/src/host-exec/handlers/process-kill-by-port.ts

```ts
/**
 * Reference handler: process.killByPort
 *
 * Sends a signal to the process listening on a given TCP port.
 * Uses execFile (not exec) with array args — no shell interpolation.
 * Port validated as integer 1–65535 before any system call.
 */

import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { attachHandlerFn } from '../registry';
import type { HandlerArgs, HandlerContext, HandlerResult } from '../types';
// Side-effect import: registers the manifest. Must come before attachHandlerFn.
import { processKillByPortManifest } from './process-kill-by-port.manifest';

const MAX_OUTPUT_BYTES = 4096;

/** Cap output to MAX_OUTPUT_BYTES, appending a hash suffix if truncated. */
function capOutput(s: string): string {
  if (Buffer.byteLength(s, 'utf8') <= MAX_OUTPUT_BYTES) return s;
  const hash = createHash('sha256').update(s, 'utf8').digest('hex');
  // Truncate by bytes, not characters.
  const buf = Buffer.from(s, 'utf8');
  const truncated = buf.subarray(0, MAX_OUTPUT_BYTES).toString('utf8');
  return `${truncated}\n[truncated, full output hash: ${hash}]`;
}

/** Resolve PIDs listening on a TCP port via lsof. */
function resolvePids(port: number): Promise<number[]> {
  return new Promise((resolve, reject) => {
    execFile(
      'lsof',
      ['-i', `:${port}`, '-sTCP:LISTEN', '-t'],
      { timeout: 5000 },
      (err, stdout) => {
        if (err) {
          // lsof exits non-zero when no process is found — that's not an error.
          if (err.code === 1 || (err as NodeJS.ErrnoException).code === '1') {
            return resolve([]);
          }
          // Exit code 1 with empty stdout also means "no match".
          if (stdout === '' || stdout === undefined) {
            return resolve([]);
          }
          return reject(err);
        }
        const pids = stdout
          .trim()
          .split('\n')
          .filter(line => line.length > 0)
          .map(line => parseInt(line, 10))
          .filter(n => !isNaN(n));
        resolve(pids);
      },
    );
  });
}

async function killByPortHandler(args: HandlerArgs, _ctx: HandlerContext): Promise<HandlerResult> {
  const start = Date.now();

  // Platform check.
  if (process.platform === 'win32') {
    return { ok: false, code: 'PLATFORM_UNSUPPORTED', message: 'process.killByPort requires a unix platform (lsof)' };
  }

  // Port validation — before any system call.
  const port = args.port;
  if (typeof port !== 'number' || !Number.isInteger(port) || port < 1 || port > 65535) {
    return {
      ok: false,
      code: 'INVALID_ARGS',
      message: `port must be an integer 1–65535, got: ${JSON.stringify(port)}`,
    };
  }

  const signal = (args.signal as string) ?? 'SIGTERM';
  if (signal !== 'SIGTERM' && signal !== 'SIGKILL') {
    return {
      ok: false,
      code: 'INVALID_ARGS',
      message: `signal must be 'SIGTERM' or 'SIGKILL', got: ${JSON.stringify(signal)}`,
    };
  }

  // Resolve PIDs.
  let pids: number[];
  try {
    pids = await resolvePids(port);
  } catch (err) {
    return {
      ok: false,
      code: 'HANDLER_CRASHED',
      message: `lsof failed: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  if (pids.length === 0) {
    return {
      ok: true,
      exitCode: 0,
      stdout: capOutput(`no process on port ${port}`),
      stderr: '',
      durationMs: Date.now() - start,
    };
  }

  // Dry-run: report PIDs without killing.
  if (args.dryRun) {
    return {
      ok: true,
      exitCode: 0,
      stdout: capOutput(`dry-run: PID(s) [${pids.join(', ')}] on port ${port}`),
      stderr: '',
      durationMs: Date.now() - start,
    };
  }

  // Wet-run: kill each PID.
  const killed: number[] = [];
  const errors: string[] = [];
  for (const pid of pids) {
    try {
      process.kill(pid, signal);
      killed.push(pid);
    } catch (err) {
      errors.push(`PID ${pid}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  // Wait 500ms for process(es) to die.
  await new Promise(r => setTimeout(r, 500));

  const stdout = killed.length > 0
    ? `killed PID ${killed.join(', ')} on port ${port}`
    : `no PIDs killed on port ${port}`;
  const stderr = errors.length > 0 ? errors.join('\n') : '';

  return {
    ok: true,
    exitCode: errors.length > 0 ? 1 : 0,
    stdout: capOutput(stdout),
    stderr: capOutput(stderr),
    durationMs: Date.now() - start,
  };
}

// Attach impl on import. Manifest was registered by the sibling .manifest file.
attachHandlerFn(processKillByPortManifest.id, killByPortHandler);

```
