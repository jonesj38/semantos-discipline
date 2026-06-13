---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tools/p3-spike-processintent.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.468509+00:00
---

# cartridges/oddjobz/brain/tools/p3-spike-processintent.ts

```ts
#!/usr/bin/env bun
/**
 * P3.1 — feasibility spike: can the oddjobz EDGE run the real
 * `@semantos/intent` pipeline (`processIntent`) end-to-end and produce
 * a valid envelope, using the existing `createShellPipelineDeps`
 * pattern + the `@semantos/cell-engine` bun kernel binding?
 *
 * STANDALONE harness. NOT wired to anything live — never touches the
 * site bundle, the brain, or any store. Proves Phase-3 Option-1
 * feasibility (DECISION-P4C). Per the committed P3.1 spec
 * (docs/design/ODDJOBZ-CONVERSATION-AS-SUBSTRATE-PROJECTION.md,
 * `1152d5c`).
 *
 *   bun run cartridges/oddjobz/brain/tools/p3-spike-processintent.ts
 *
 *   exit 0 + "P3.1 OK" on stdout  ⇒ a valid intent envelope is
 *                                   producible edge-side (feasible).
 *   non-zero + diagnostic         ⇒ the exact next fix (spike loop;
 *                                   verified only where @semantos/*
 *                                   resolves — the bun-installed rbs
 *                                   worktree; iterate there).
 *
 * Mirrors runtime/shell/src/intent-adapters/run-shell-intent.ts (the
 * canonical processIntent caller) + inlines the ~40-line
 * createShellPipelineDeps mapping (so this does not depend on
 * runtime/shell internals being importable from the oddjobz pkg).
 */

import {
  processIntent,
  buildHatContext,
  defaultTrustCeiling,
  createJsonlStderrLogger,
  type PipelineDeps,
  type Cell,
  type CellId,
  type ScriptResult,
  type IntentContext,
  type IdentityServiceLike,
  type HatLike,
  type IdentityLike,
} from '@semantos/intent';
// Deep import per the proven precedent runtime/shell/src/index.ts:74
// (@semantos/cell-engine's package main is a Phase-6 stub; the real
// bun kernel binding lives at the bindings/bun/loader subpath).
import { loadCellEngine } from '@semantos/cell-engine/bindings/bun/loader';
import { emit as emitIR } from '@semantos/semantos-ir';
import { acceptRomTargetJson } from '../src/conversation/accept-rom-target.js';

// ── inline createShellPipelineDeps equivalent ───────────────────────
// (verbatim mapping from runtime/shell/src/intent-adapters/
// shell-pipeline-deps.ts — authoring mode, OP_1 frame, deriveCellId,
// mapKernelResult)

const AUTHORING_FRAME = new Uint8Array([0x51]); // OP_1 → TRUE

interface CellEngineLike {
  executeScript(
    lockScript: Uint8Array,
    unlockScript?: Uint8Array,
  ): { success: boolean; typeClassification: number; opcodeCount: number; error: string | null };
}

function deriveCellId(bytes: Uint8Array, uuid: () => string): CellId {
  const sizeHex = bytes.byteLength.toString(16).padStart(6, '0');
  const bytePrefix = Array.from(bytes.slice(0, 4))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return `cell-${sizeHex}-${bytePrefix}-${uuid().slice(0, 8)}` as CellId;
}

function mapKernelResult(r: {
  success: boolean;
  typeClassification: number;
  opcodeCount: number;
  error: string | null;
}): ScriptResult {
  if (r.success) {
    return { ok: true, stackDepth: 0, opcount: r.opcodeCount, gasUsed: 0 };
  }
  const msg = r.error ?? 'kernel execution failed';
  const m = /\b(\d+)\b/.exec(msg);
  return {
    ok: false,
    stackDepth: 0,
    opcount: r.opcodeCount,
    gasUsed: 0,
    errorCode: m ? parseInt(m[1]!, 10) : undefined,
    errorMessage: msg,
  };
}

function makeMemoryStorage(): { write(k: string, b: Uint8Array): Promise<void>; read(k: string): Promise<Uint8Array | null> } {
  const m = new Map<string, Uint8Array>();
  return {
    write: async (k, b) => void m.set(k, b),
    read: async (k) => m.get(k) ?? null,
  };
}

function makeEdgePipelineDeps(engine: CellEngineLike): PipelineDeps {
  const uuid = () => crypto.randomUUID();
  const store = makeMemoryStorage();
  return {
    emitBytes: (ir) => emitIR(ir as Parameters<typeof emitIR>[0]),
    async executeScript(_bytes: Uint8Array): Promise<ScriptResult> {
      // authoring mode: no inbound cell on the stack ⇒ run OP_1
      try {
        return mapKernelResult(engine.executeScript(AUTHORING_FRAME));
      } catch (e) {
        return {
          ok: false,
          stackDepth: 0,
          opcount: 0,
          gasUsed: 0,
          errorMessage: e instanceof Error ? e.message : String(e),
        };
      }
    },
    buildCellFromBytes: (bytes: Uint8Array): Cell => ({
      id: deriveCellId(bytes, uuid),
      bytes,
    }),
    writeCell: async (cell: Cell) => {
      await store.write(`cells/${cell.id}`, cell.bytes);
    },
    // P3.3 sub-decision is real signing; the spike proves wiring with
    // a trivial signer (createShellPipelineDeps takes any AsyncSigner).
    sign: async (_preimage: Uint8Array) => new Uint8Array(64),
    now: () => Date.now(),
    uuid,
  };
}

// ── minimal dev identity (requireCert:false ⇒ no cert needed) ───────

// Mirror runtime/intent's proven mkHat: a certId-bearing hat with the
// SIGNING capability so defaultTrustCeiling → 'interpretive' (NOT
// 'cosmetic' — the latter allows no emit ops, which produced the
// degenerate zero-length lowering / emitBinding RangeError).
function makeStubIdentity(): IdentityServiceLike {
  const hat: HatLike = {
    id: 'oddjobz-spike',
    certId: 'cert-spike',
    capabilities: [5],
  };
  const identity: IdentityLike = {
    id: 'operator-spike',
    certId: 'cert-spike',
    activeHatId: hat.id,
    hats: [hat],
  };
  return { getIdentity: () => identity, getActiveHat: () => hat };
}

// ── the accept_rom Intent (jural/declaration to satisfy lowerSIR for
//    the spike; oddjobz-correct taxonomy is a P3.4 refinement) ───────

function buildAcceptRomIntent(uuid: () => string) {
  // Mirror runtime/intent's proven-green mkIntent: jural/declaration +
  // a real `comparison` constraint (the golden-test G1 `> amount 500`
  // — the most-proven-emittable expr in the codebase) so the REAL
  // @semantos/semantos-sir lowerSIR → @semantos/semantos-ir emit
  // produces non-degenerate opcode bytes (the empty-constraints
  // accept_rom placeholder lowered to a zero-binding program →
  // emitBinding RangeError). The oddjobz-correct accept_rom
  // taxonomy/action is the P3.4 refinement; P3.1 only proves the edge
  // runs the REAL pipeline against the REAL kernel end-to-end. The
  // money channel is still demonstrated via producerMeta.targetJson.
  return {
    id: uuid(),
    correlationId: uuid(),
    summary: 'P3.1 spike: publish core.Document with SIGNING capability',
    category: { lexicon: 'jural', category: 'declaration' },
    taxonomy: { what: 'core.Document', how: 'lifecycle.publish', why: 'audit' },
    action: 'transition',
    constraints: [{ kind: 'comparison', op: '>', field: 'amount', value: 500 }],
    confidence: 1.0,
    source: 'shell',
    producerMeta: {
      targetJson: acceptRomTargetJson({ costMin: 40000, costMax: 60000 }),
    },
  };
}

async function main(): Promise<number> {
  process.stderr.write('[p3.1] loading cell-engine bun binding…\n');
  const engine = (await loadCellEngine()) as unknown as CellEngineLike;

  const deps = makeEdgePipelineDeps(engine);
  const hat = buildHatContext({
    identity: makeStubIdentity(),
    extension: { extensionId: 'oddjobz', domainFlag: 0x0001_0101 },
    resolveMaxTrustClass: defaultTrustCeiling,
    requireCert: false,
  });

  const intent = buildAcceptRomIntent(deps.uuid);
  const ctx: IntentContext = {
    hat,
    logger: createJsonlStderrLogger(),
    correlationId: intent.correlationId as IntentContext['correlationId'],
  };

  process.stderr.write('[p3.1] running processIntent…\n');
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const result = await processIntent(intent as any, ctx, deps);

  const ok = (result as { ok?: boolean }).ok === true;
  const cellId =
    (result as { cell?: { id?: string } | null }).cell?.id ?? null;
  process.stdout.write(
    JSON.stringify(
      {
        verdict: ok && cellId ? 'P3.1 OK — envelope producible edge-side' : 'P3.1 FAIL',
        ok,
        cellId,
        kernelResult: (result as { kernelResult?: unknown }).kernelResult ?? null,
        rejection: (result as { rejection?: unknown }).rejection ?? null,
      },
      null,
      2,
    ) + '\n',
  );
  return ok && cellId ? 0 : 1;
}

if (import.meta.main) {
  main()
    .then((c) => process.exit(c))
    .catch((e) => {
      process.stderr.write(
        `[p3.1] THREW: ${e && e.stack ? e.stack : String(e)}\n`,
      );
      process.exit(2);
    });
}

export { makeEdgePipelineDeps, buildAcceptRomIntent };

```
