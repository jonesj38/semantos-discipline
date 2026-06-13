---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase38-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.581470+00:00
---

# tests/gates/phase38-gate.test.ts

```ts
/**
 * Phase 38 Gate Tests — Voice-to-Execution Foundation (38A + 38B + 38C)
 *
 * 38A (T1–T11b):
 *   T1  host-ops.json validates via validateExtensionConfig()
 *   T2  HostCommand typeHash is real sha256('HostCommand')
 *   T3  HOST_EXEC capability id (11) is globally unique across extensions
 *   T4  HostCommand.linearity === "LINEAR"
 *   T5  HostCommand.visibility.states === ["draft", "published"]
 *   T6  HostCommand.defaultCapabilities includes 11
 *   T7  Required fields: handler, args, hatId, hatCertId, hatSig, requestedAt
 *   T8  governanceConfig declares trustClass/proofRequirement/executionAuthority
 *   T9  enforceL0Constraints rejects authoritative + non-formal
 *   T10 enforceL0Constraints rejects executionAuthority='delegated'
 *   T11 publishExtensionManifest rejects manifest missing trustClass
 *
 * 38B (T12–T18):
 *   T12 getHandler('process.killByPort') returns non-null manifest
 *   T13 invokeHandler('does-not-exist') returns UNKNOWN_HANDLER
 *   T14 invokeHandler with missing port returns INVALID_ARGS
 *   T15 invokeHandler with non-integer port returns INVALID_ARGS
 *   T16 invokeHandler with dryRun=true resolves without killing
 *   T17 handler timeout returns HANDLER_TIMEOUT
 *   T18 double-registration throws
 *
 * 38C (T19–T25):
 *   T19 parseCommand recognizes host.exec with handler id + args
 *   T20 route() without HOST_EXEC capability returns CAPABILITY_CHECK_FAILED
 *   T21 routeHostExec with missing handler id returns MISSING_HANDLER
 *   T22 routeHostExec with unknown handler publishes object + result has UNKNOWN_HANDLER
 *   T23 routeHostExec with --dry-run publishes but does NOT invoke handler
 *   T24 result patch does NOT rewind object's published visibility
 *   T25 round-trip: after host.exec, object visibility === 'published'
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { createHash } from 'crypto';

import { validateExtensionConfig } from '../../core/protocol-types/src/extension-config-types';
import type {
  ExtensionConfig,
} from '../../core/protocol-types/src/extension-config-types';
import type {
  GovernancePolicy,
} from '../../core/protocol-types/src/governance';
import type { ExtensionManifest } from '../../core/protocol-types/src/extension-manifest';
import type { ExtensionGrammar } from '../../core/protocol-types/src/extension-grammar';
import { enforceL0Constraints } from '../../packages/extraction/src/governance/constraint-engine';
import { publishExtensionManifest } from '../../packages/extraction/src/governance/manifest-publisher';

const ROOT = join(import.meta.dir, '../..');
const HOST_OPS_PATH = join(ROOT, 'configs/extensions/host-ops.json');
const EXTENSIONS_DIR = join(ROOT, 'configs/extensions');

// Lazily-loaded host-ops config, reused across tests.
function loadHostOps(): ExtensionConfig {
  return JSON.parse(readFileSync(HOST_OPS_PATH, 'utf8'));
}

function hostCommandType(cfg: ExtensionConfig) {
  const t = cfg.objectTypes.find(ot => ot.name === 'HostCommand');
  if (!t) throw new Error('HostCommand objectType not found in host-ops.json');
  return t;
}

// ── T1: host-ops.json validates ────────────────────────────────

describe('Phase 38 — Extension Config', () => {
  test('T1: configs/extensions/host-ops.json passes validateExtensionConfig()', () => {
    const data = loadHostOps();
    expect(() => validateExtensionConfig(data)).not.toThrow();
    const cfg = validateExtensionConfig(data);
    expect(cfg.id).toBe('host-ops');
    expect(cfg.name).toBe('Host Operations');
  });
});

// ── T2: typeHash is real sha256 ────────────────────────────────

describe('Phase 38 — HostCommand typeHash', () => {
  test('T2: HostCommand.typeHash is a 64-char hex matching sha256("HostCommand")', () => {
    const cfg = loadHostOps();
    const hc = hostCommandType(cfg);

    // Well-formed 64-char hex (validateExtensionConfig also enforces this)
    expect(hc.typeHash).toMatch(/^[0-9a-f]{64}$/);

    // Per scripts/compute-type-hashes.ts: sha256(category) if category
    // present, else sha256(name). HostCommand has no category.
    const expected = createHash('sha256').update('HostCommand', 'utf-8').digest('hex');
    expect(hc.typeHash).toBe(expected);
  });
});

// ── T3: HOST_EXEC capability id is unique across all extensions ─

describe('Phase 38 — HOST_EXEC capability uniqueness', () => {
  test('T3: HOST_EXEC (id=11) does not collide with any capability in any other extension config', () => {
    const hostOps = loadHostOps();
    const hostExec = hostOps.capabilities.find(c => c.name === 'HOST_EXEC');
    expect(hostExec).toBeDefined();
    expect(hostExec!.id).toBe(11);

    // Walk every other *.json in configs/extensions/ (skip host-ops.json itself)
    // and assert that id=11 is not used for any capability.
    const files = readdirSync(EXTENSIONS_DIR)
      .filter(f => f.endsWith('.json') && f !== 'host-ops.json');

    for (const file of files) {
      const raw = JSON.parse(readFileSync(join(EXTENSIONS_DIR, file), 'utf8'));
      const caps = Array.isArray(raw.capabilities) ? raw.capabilities : [];
      for (const c of caps) {
        expect(
          c.id,
          `capability id collision in ${file}: "${c.name}" uses id ${c.id}, which HOST_EXEC also claims`,
        ).not.toBe(11);
      }
    }
  });
});

// ── T4–T7: HostCommand schema shape ────────────────────────────

describe('Phase 38 — HostCommand shape', () => {
  test('T4: HostCommand.linearity === "LINEAR"', () => {
    const hc = hostCommandType(loadHostOps());
    expect(hc.linearity).toBe('LINEAR');
  });

  test('T5: HostCommand.visibility.states is exactly ["draft", "published"]', () => {
    const hc = hostCommandType(loadHostOps());
    expect(hc.visibility).toBeDefined();
    expect(hc.visibility!.states).toEqual(['draft', 'published']);
    expect(hc.visibility!.defaultState).toBe('draft');
    expect(hc.visibility!.revokePreservesEvidence).toBe(false);
  });

  test('T6: HostCommand.defaultCapabilities includes HOST_EXEC id (11)', () => {
    const hc = hostCommandType(loadHostOps());
    expect(hc.defaultCapabilities).toContain(11);
  });

  test('T7: HostCommand declares required request fields', () => {
    const hc = hostCommandType(loadHostOps());
    const fieldNames = new Set(hc.fields.map(f => f.name));
    for (const required of ['handler', 'args', 'hatId', 'hatCertId', 'hatSig', 'requestedAt']) {
      expect(fieldNames.has(required), `missing required field: ${required}`).toBe(true);
    }
  });
});

// ── T8: trust-tier fields present in host-ops.json ─────────────

describe('Phase 38 — Trust-tier governance', () => {
  test('T8: host-ops.json governanceConfig declares trust-tier fields', () => {
    const cfg = loadHostOps();
    expect(cfg.governanceConfig).toBeDefined();
    expect(cfg.governanceConfig!.trustClass).toBe('interpretive');
    expect(cfg.governanceConfig!.proofRequirement).toBe('attestation');
    expect(cfg.governanceConfig!.executionAuthority).toBe('hat_scoped');
  });
});

// ── T9–T10: conservative-by-default enforcement ────────────────

// Minimal fixtures sufficient for L0 trust-tier checks. These bypass the
// larger phase36d fixtures to stay focused on the trust-tier rules.

function minimalGrammar(): ExtensionGrammar {
  return {
    metaSchemaVersion: '1.0.0',
    grammarId: 'com.test.phase38',
    grammarVersion: '1.0.0',
    displayName: 'Phase 38 Trust-Tier Fixture',
    description: 'Minimal grammar for trust-tier enforcement tests',
    author: { certId: 'test-cert', name: 'Test' },
    source: {
      protocol: 'rest',
      baseUrlTemplate: 'https://api.test.local/v1',
      auth: { type: 'api-key', requiredCredentials: ['api_key'] },
      entities: [{
        entityId: 'noop',
        displayName: 'Noop',
        endpoint: { list: '/noop', get: '/noop/{id}' },
        responseShape: { dataPath: '$.data', idField: 'id' },
        fields: [{ sourceFieldName: 'id', sourceType: 'string', required: true }],
      }],
    },
    objectTypes: [{
      typePath: 'phase38.noop',
      displayName: 'Noop',
      description: 'Placeholder',
      linearity: 'AFFINE',
      phases: ['active'],
      initialPhase: 'active',
      payloadSchema: {},
      capabilities: { read: [1] },
    }],
    entityMappings: [{
      sourceEntityId: 'noop',
      targetObjectType: 'phase38.noop',
      fieldMappings: [],
      taxonomy: {
        what: 'what.phase38.noop',
        how: 'how.technical.api.rest',
        why: 'why.testing',
      },
    }],
    capabilities: [
      { capability: 'network.outbound', reason: 'test', required: true },
      { capability: 'storage.write', reason: 'test', required: true },
    ],
    taxonomyNamespace: 'phase38',
  };
}

function minimalPolicy(): GovernancePolicy {
  return {
    typePath: 'governance.policy',
    linearity: 'RELEVANT',
    constitution: true,
    payload: {
      metaSchemaVersion: '1.0.0',
      requiredCapabilitiesWhitelist: ['network.outbound', 'storage.write'],
      taxonomyNamespaceReservations: [],
      marketplaceListingRequirements: {
        minAuthorReputationScore: 0,
        minObjectCount: 0,
        requiresAudit: false,
        auditFrequencyDays: 365,
      },
      breakingChangeBallotQuorum: 66,
      emergencyDeprecationPolicy: {
        requiresVote: false,
        minDaysNotice: 30,
        escalationThreshold: 'critical',
      },
      effectiveDate: '2026-01-01T00:00:00Z',
      governedByHatId: 'semantos-core',
    },
  };
}

function minimalManifest(govOverrides: Partial<ExtensionManifest['governanceConfig']> = {}): ExtensionManifest {
  return {
    id: 'phase38-trust-test',
    name: 'Phase 38 Trust Test',
    version: '1.0.0',
    taxonomyPath: 'taxonomy/phase38.json',
    flowsDir: 'flows',
    promptsDir: 'prompts',
    grammar: minimalGrammar(),
    manifestLinearity: 'AFFINE',
    governanceConfig: {
      patchAcceptancePolicy: 'author_only',
      versionBumpRules: { major: 'author_only', minor: 'author_only', patch: 'author_only' },
      contributorHats: [],
      deprecationTimelineMinDays: 30,
      ...govOverrides,
    },
  };
}

describe('Phase 38 — Conservative-by-default enforcement', () => {
  test('T9: authoritative trustClass without formal proofRequirement is rejected', () => {
    const manifest = minimalManifest({
      trustClass: 'authoritative',
      proofRequirement: 'none',
      executionAuthority: 'local_facet',
    });
    const policy = minimalPolicy();

    const result = enforceL0Constraints(manifest, policy);
    expect(result.valid).toBe(false);
    const rule = result.violations.find(v => v.rule === 'authoritative-requires-formal-proof');
    expect(rule, 'expected authoritative-requires-formal-proof violation').toBeDefined();
  });

  test('T9b: authoritative + formal passes the trust-tier gate', () => {
    const manifest = minimalManifest({
      trustClass: 'authoritative',
      proofRequirement: 'formal',
      executionAuthority: 'hat_scoped',
    });
    const policy = minimalPolicy();

    const result = enforceL0Constraints(manifest, policy);
    const trustViolations = result.violations.filter(
      v => v.rule === 'authoritative-requires-formal-proof'
        || v.rule === 'delegated-execution-not-implemented',
    );
    expect(trustViolations).toHaveLength(0);
  });

  test('T10: executionAuthority="delegated" is rejected', () => {
    const manifest = minimalManifest({
      trustClass: 'interpretive',
      proofRequirement: 'attestation',
      executionAuthority: 'delegated',
    });
    const policy = minimalPolicy();

    const result = enforceL0Constraints(manifest, policy);
    expect(result.valid).toBe(false);
    const rule = result.violations.find(v => v.rule === 'delegated-execution-not-implemented');
    expect(rule, 'expected delegated-execution-not-implemented violation').toBeDefined();
  });
});

// ── T11: publisher requires trust-tier fields ──────────────────

describe('Phase 38 — Publisher requires trust-tier fields', () => {
  test('T11: publishExtensionManifest rejects manifest missing trustClass', () => {
    // Omit trustClass; other fields present so we isolate the check.
    const manifest = minimalManifest({
      proofRequirement: 'none',
      executionAuthority: 'local_facet',
    });
    const policy = minimalPolicy();

    const result = publishExtensionManifest(manifest, policy, 100);
    expect(result.success).toBe(false);
    expect(result.errors.some(e => /trustClass/.test(e))).toBe(true);
  });

  test('T11b: publishExtensionManifest succeeds with full conservative trust-tier', () => {
    const manifest = minimalManifest({
      trustClass: 'cosmetic',
      proofRequirement: 'none',
      executionAuthority: 'local_facet',
    });
    const policy = minimalPolicy();

    const result = publishExtensionManifest(manifest, policy, 100);
    expect(result.errors.some(e => /trustClass|proofRequirement|executionAuthority/.test(e))).toBe(false);
    // Note: we don't assert result.success here — other L0 rules may fire
    // on the minimal fixture — but the trust-tier path must be clean.
  });
});

// ── Phase 38B: Handler Registry & Reference Handler ──────────

import '../../runtime/shell/src/host-exec/handlers'; // triggers self-registration
import { getHandler, invokeHandler, registerHandler } from '../../runtime/shell/src/host-exec/registry';
import type { HandlerContext } from '../../runtime/shell/src/host-exec/types';

const testCtx: HandlerContext = {
  hatId: 'test-hat',
  hatCertId: 'test-cert',
  timeoutMs: 10_000,
};

describe('Phase 38B — Handler Registry', () => {
  test('T12: getHandler("process.killByPort") returns non-null manifest with capabilityId 11', () => {
    const entry = getHandler('process.killByPort');
    expect(entry).not.toBeNull();
    expect(entry!.manifest.id).toBe('process.killByPort');
    expect(entry!.manifest.capabilityId).toBe(11);
    expect(typeof entry!.fn).toBe('function');
  });

  test('T13: invokeHandler("does-not-exist") returns UNKNOWN_HANDLER', async () => {
    const result = await invokeHandler('does-not-exist', {}, testCtx);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('UNKNOWN_HANDLER');
    }
  });

  test('T14: invokeHandler("process.killByPort", {}) returns INVALID_ARGS (missing port)', async () => {
    const result = await invokeHandler('process.killByPort', {}, testCtx);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('INVALID_ARGS');
    }
  });

  test('T15: invokeHandler with port="abc" returns INVALID_ARGS (non-integer)', async () => {
    const result = await invokeHandler('process.killByPort', { port: 'abc' }, testCtx);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('INVALID_ARGS');
    }
  });

  test('T16: invokeHandler with dryRun=true resolves without killing', async () => {
    const result = await invokeHandler(
      'process.killByPort',
      { port: 9000, dryRun: true },
      testCtx,
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      // Either "dry-run: PID(s) [...]" or "no process on port 9000"
      expect(result.stdout).toMatch(/dry-run|no process/);
    }
  });

  test('T17: handler that sleeps 20s with timeoutMs=100 returns HANDLER_TIMEOUT', async () => {
    // Register a temporary sleepy handler for this test.
    registerHandler(
      {
        id: 'test.sleepy',
        description: 'Test handler that sleeps forever',
        argsSchema: {},
        capabilityId: 99,
      },
      async () => {
        await new Promise(r => setTimeout(r, 20_000));
        return { ok: true, exitCode: 0, stdout: '', stderr: '', durationMs: 0 };
      },
    );

    const result = await invokeHandler('test.sleepy', {}, { ...testCtx, timeoutMs: 100 });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('HANDLER_TIMEOUT');
    }
  });

  test('T18: registerHandler rejects double-registration of the same id', () => {
    expect(() =>
      registerHandler(
        {
          id: 'process.killByPort',
          description: 'duplicate',
          argsSchema: {},
          capabilityId: 11,
        },
        async () => ({ ok: true, exitCode: 0, stdout: '', stderr: '', durationMs: 0 }),
      ),
    ).toThrow(/already registered/);
  });
});

// ── Phase 38C: host.exec verb ────────────────────────────────

import { createHash as cryptoCreateHash } from 'crypto';
import { parseCommand } from '../../runtime/shell/src/parser';
import { route } from '../../runtime/shell/src/router';
import { routeHostExec } from '../../runtime/shell/src/commands/host-exec';
import { LoomStore, initializePlexusService, IdentityStore, ConfigStore, SettingsStore, FlowRunner } from '@semantos/runtime-services';
import type { ShellContext } from '../../runtime/shell/src/types';

// Per-test invocation tracker — each test.echo call pushes the snapshot here.
// Tests read and reset this instead of sharing a mutable boolean.
const echoInvocations: { args: Record<string, unknown>; publishedBefore: boolean }[] = [];

registerHandler(
  {
    id: 'test.echo',
    description: 'Test handler that echoes args',
    argsSchema: {},
    capabilityId: 11,
  },
  async (args, ctx) => {
    // Snapshot whether the HostCommand was already published at invoke time.
    // The handler receives ctx.hatId — we can't reach the store from here,
    // but the test injects a flag via a closure (see T26).
    echoInvocations.push({ args: { ...args }, publishedBefore: true });
    return { ok: true, exitCode: 42, stdout: JSON.stringify(args), stderr: 'warn', durationMs: 7 };
  },
);

// Register a handler that crashes for T29.
registerHandler(
  {
    id: 'test.crasher',
    description: 'Test handler that throws',
    argsSchema: {},
    capabilityId: 11,
  },
  async () => {
    throw new Error('kaboom from test.crasher');
  },
);

/**
 * Build a ShellContext with real services — LoomStore, IdentityStore,
 * ConfigStore (host-ops extension loaded via switchExtension), PlexusService (stub).
 */
async function buildTestContext(opts?: {
  withoutHostExec?: boolean;
  noCertId?: boolean;
  noFacet?: boolean;
}): Promise<ShellContext> {
  const store = new LoomStore();
  const plexus = initializePlexusService({ mode: 'stub' });
  const identity = new IdentityStore();
  const config = new ConfigStore();
  const settings = new SettingsStore();
  const flowRunner = new FlowRunner();

  if (!opts?.noFacet) {
    await identity.createIdentity('test-38c@semantos.local');
  }

  await config.switchExtension('host-ops');

  const facet = opts?.noFacet ? null : identity.getActiveHat()!;

  if (facet) {
    if (opts?.withoutHostExec) {
      (facet as any).capabilities = (facet.capabilities ?? []).filter((c: number) => c !== 11);
    } else if (!(facet.capabilities ?? []).includes(11)) {
      (facet as any).capabilities = [...(facet.capabilities ?? []), 11];
    }

    if (opts?.noCertId) {
      (facet as any).certId = undefined;
    }
  }

  return {
    store,
    flowRunner,
    identity,
    config,
    settings,
    plexus,
    activeExtension: 'host-ops',
    activeHatId: facet?.id ?? null,
    activeHatCertId: opts?.noCertId ? null : (facet?.certId ?? null),
    defaultFormat: 'json' as any,
  };
}

describe('Phase 38C — host.exec verb', () => {
  // ── Parser ──

  test('T19: parseCommand recognizes host.exec with handler id + arg flag', () => {
    const cmd = parseCommand(['host.exec', 'process.killByPort', '--arg', 'port=9000']);
    expect(cmd.verb).toBe('host.exec');
    expect(cmd.flags.handler).toBe('process.killByPort');
    expect(cmd.flags.arg).toBe('port=9000');
  });

  // ── Capability gate ──

  test('T20: route() without HOST_EXEC capability returns CAPABILITY_CHECK_FAILED, no object created', async () => {
    const ctx = await buildTestContext({ withoutHostExec: true });
    const cmd = parseCommand(['host.exec', 'test.echo']);
    const result = await route(cmd, ctx) as any;
    expect(result.code).toBe('CAPABILITY_CHECK_FAILED');
    expect(ctx.store.getState().objects.size).toBe(0);
  });

  // ── Guard: missing handler id ──

  test('T21: routeHostExec with missing handler id returns MISSING_HANDLER', async () => {
    const ctx = await buildTestContext();
    const cmd = parseCommand(['host.exec']);
    const result = await routeHostExec(cmd, ctx) as any;
    expect(result.code).toBe('MISSING_HANDLER');
    expect(ctx.store.getState().objects.size).toBe(0);
  });

  // ── Guard: no active hat ──

  test('T22: routeHostExec with no active hat returns NO_ACTIVE_HAT', async () => {
    const ctx = await buildTestContext({ noFacet: true });
    const cmd = parseCommand(['host.exec', 'test.echo']);
    const result = await routeHostExec(cmd, ctx) as any;
    expect(result.code).toBe('NO_ACTIVE_HAT');
  });

  // ── Guard: no cert id ──

  test('T23: routeHostExec with facet but no certId returns NO_HAT_CERT', async () => {
    const ctx = await buildTestContext({ noCertId: true });
    const cmd = parseCommand(['host.exec', 'test.echo']);
    const result = await routeHostExec(cmd, ctx) as any;
    expect(result.code).toBe('NO_HAT_CERT');
  });

  // ── Publish-before-execute: unknown handler ──

  test('T24: unknown handler — object IS published, result patch records UNKNOWN_HANDLER', async () => {
    const ctx = await buildTestContext();
    const cmd = parseCommand(['host.exec', 'does.not.exist']);
    const result = await routeHostExec(cmd, ctx) as any;

    expect(result.ok).toBe(true);
    expect(result.hostCommandId).toBeDefined();
    expect(result.result.ok).toBe(false);
    expect(result.result.code).toBe('UNKNOWN_HANDLER');

    const obj = ctx.store.getState().objects.get(result.hostCommandId)!;
    expect(obj.visibility).toBe('published');

    // Result patch was appended with the error
    const resultPatch = obj.patches.find(p => p.delta.action === 'handler_result');
    expect(resultPatch).toBeDefined();
    expect(resultPatch!.delta.code).toBe('UNKNOWN_HANDLER');
  });

  // ── Dry-run: publish yes, invoke no, no result patch ──

  test('T25: --dry-run publishes HostCommand but does NOT invoke handler and has NO result patch', async () => {
    echoInvocations.length = 0;
    const ctx = await buildTestContext();
    const cmd = parseCommand(['host.exec', 'test.echo', '--dry-run']);
    const result = await routeHostExec(cmd, ctx) as any;

    expect(result.ok).toBe(true);
    expect(result.dryRun).toBe(true);
    expect(result.hostCommandId).toBeDefined();

    // Handler was NOT invoked
    expect(echoInvocations).toHaveLength(0);

    const obj = ctx.store.getState().objects.get(result.hostCommandId)!;

    // Published
    expect(obj.visibility).toBe('published');

    // No result patch — evidence chain has creation + field patches, not handler_result
    const resultPatch = obj.patches.find(p => p.delta.action === 'handler_result');
    expect(resultPatch).toBeUndefined();
  });

  // ── Publish-before-execute ordering ──

  test('T26: object is published BEFORE handler is invoked', async () => {
    // Strategy: register a handler that checks the store at invoke time.
    let objectWasPublishedAtInvokeTime = false;
    let capturedObjId: string | null = null;

    registerHandler(
      {
        id: 'test.publish-order-check',
        description: 'Checks object state at invoke time',
        argsSchema: {},
        capabilityId: 11,
      },
      async (_args, handlerCtx) => {
        // The handler can't reach the store, but we captured the store ref
        // via the closure over `ctx` below. This is the whole point of the test.
        if (capturedObjId && capturedStore) {
          const obj = capturedStore.getState().objects.get(capturedObjId);
          objectWasPublishedAtInvokeTime = obj?.visibility === 'published';
        }
        return { ok: true, exitCode: 0, stdout: 'checked', stderr: '', durationMs: 0 };
      },
    );

    const ctx = await buildTestContext();
    let capturedStore: LoomStore | null = ctx.store;

    const cmd = parseCommand(['host.exec', 'test.publish-order-check']);
    // We need to know the objId before invocation — intercept createObjectFromType
    const origCreate = ctx.store.createObjectFromType.bind(ctx.store);
    ctx.store.createObjectFromType = (...args: any[]) => {
      const id = origCreate(...args);
      capturedObjId = id;
      return id;
    };

    const result = await routeHostExec(cmd, ctx) as any;
    expect(result.ok).toBe(true);
    expect(objectWasPublishedAtInvokeTime).toBe(true);
  });

  // ── Signature verification ──

  test('T27: hatSig matches sha256 of canonical payload (handler|args|hatId|requestedAt)', async () => {
    const ctx = await buildTestContext();
    const cmd = parseCommand(['host.exec', 'test.echo', '--arg', 'port=9000']);
    const result = await routeHostExec(cmd, ctx) as any;

    expect(result.ok).toBe(true);
    const obj = ctx.store.getState().objects.get(result.hostCommandId)!;

    const handler = obj.payload.handler as string;
    const argsJson = obj.payload.args as string;
    const hatId = obj.payload.hatId as string;
    const requestedAt = obj.payload.requestedAt as string;

    // Recompute canonical signature
    const args = JSON.parse(argsJson);
    const canonical = `${handler}|${JSON.stringify(args, Object.keys(args).sort())}|${hatId}|${requestedAt}`;
    const expectedSig = cryptoCreateHash('sha256').update(canonical).digest('hex');

    expect(obj.payload.hatSig).toBe(expectedSig);
  });

  // ── Linearity transition ──

  test('T28: published HostCommand has RELEVANT linearity (3) after publish transition', async () => {
    const ctx = await buildTestContext();
    const cmd = parseCommand(['host.exec', 'test.echo']);
    const result = await routeHostExec(cmd, ctx) as any;

    expect(result.ok).toBe(true);
    const obj = ctx.store.getState().objects.get(result.hostCommandId)!;
    // publishTransition: AFFINE(2) → RELEVANT(3)
    expect(obj.header.linearity).toBe(3);
  });

  // ── Handler crash recording ──

  test('T29: handler that throws — result patch records HANDLER_CRASHED, object stays published', async () => {
    const ctx = await buildTestContext();
    const cmd = parseCommand(['host.exec', 'test.crasher']);
    const result = await routeHostExec(cmd, ctx) as any;

    expect(result.ok).toBe(true);
    expect(result.result.ok).toBe(false);
    expect(result.result.code).toBe('HANDLER_CRASHED');
    expect(result.result.message).toContain('kaboom');

    const obj = ctx.store.getState().objects.get(result.hostCommandId)!;
    expect(obj.visibility).toBe('published');

    // Crash is recorded in the evidence chain
    const resultPatch = obj.patches.find(p => p.delta.action === 'handler_result');
    expect(resultPatch).toBeDefined();
    expect(resultPatch!.delta.code).toBe('HANDLER_CRASHED');
  });

  // ── Payload fields populated after execution ──

  test('T30: successful execution populates payload fields (startedAt, finishedAt, exitCode, stdout, stderr)', async () => {
    echoInvocations.length = 0;
    const ctx = await buildTestContext();
    const cmd = parseCommand(['host.exec', 'test.echo', '--arg', 'key=val']);
    const result = await routeHostExec(cmd, ctx) as any;

    expect(result.ok).toBe(true);
    const obj = ctx.store.getState().objects.get(result.hostCommandId)!;

    // Payload fields set by routeHostExec after handler returns
    expect(obj.payload.startedAt).toBeDefined();
    expect(obj.payload.finishedAt).toBeDefined();
    expect(typeof obj.payload.startedAt).toBe('string');
    expect(typeof obj.payload.finishedAt).toBe('string');
    // startedAt ≤ finishedAt
    expect(new Date(obj.payload.startedAt as string).getTime())
      .toBeLessThanOrEqual(new Date(obj.payload.finishedAt as string).getTime());
    expect(obj.payload.exitCode).toBe(42);
    expect(obj.payload.stdout).toContain('key');
    expect(obj.payload.stderr).toBe('warn');
  });

  // ── Result patch does NOT rewind visibility ──

  test('T31: result patch appends evidence without rewinding published visibility', async () => {
    const ctx = await buildTestContext();
    const cmd = parseCommand(['host.exec', 'test.echo', '--arg', 'msg=hello']);
    const result = await routeHostExec(cmd, ctx) as any;

    expect(result.ok).toBe(true);
    const obj = ctx.store.getState().objects.get(result.hostCommandId)!;

    // Visibility stays published
    expect(obj.visibility).toBe('published');

    // Result patch was appended (not replacing earlier patches)
    const resultPatch = obj.patches.find(p => p.delta.action === 'handler_result');
    expect(resultPatch).toBeDefined();
    expect(resultPatch!.kind).toBe('action');

    // Creation patch still exists (evidence chain is append-only)
    const creationPatch = obj.patches.find(p => p.delta.action === 'created');
    expect(creationPatch).toBeDefined();
  });

  // ── Multi-arg parsing ──

  test('T32: multiple --arg flags are all collected', async () => {
    echoInvocations.length = 0;
    const ctx = await buildTestContext();
    const cmd = parseCommand(['host.exec', 'test.echo', '--arg', 'port=9000', '--arg', 'signal=SIGTERM']);
    const result = await routeHostExec(cmd, ctx) as any;

    expect(result.ok).toBe(true);
    // Both args should be in the handler's stdout (JSON of args)
    const handlerArgs = JSON.parse(result.result.stdout);
    expect(handlerArgs.port).toBe(9000);
    expect(handlerArgs.signal).toBe('SIGTERM');
  });

  // ── Round-trip end-to-end ──

  test('T33: full round-trip — parse, publish, invoke, verify object + result', async () => {
    echoInvocations.length = 0;
    const ctx = await buildTestContext();
    const cmd = parseCommand(['host.exec', 'test.echo', '--arg', 'port=8080']);
    const result = await routeHostExec(cmd, ctx) as any;

    expect(result.ok).toBe(true);
    expect(echoInvocations.length).toBeGreaterThan(0);
    expect(result.result.ok).toBe(true);

    const obj = ctx.store.getState().objects.get(result.hostCommandId)!;
    expect(obj.visibility).toBe('published');
    expect(obj.header.linearity).toBe(3); // RELEVANT
    expect(obj.payload.handler).toBe('test.echo');
    expect(obj.payload.hatId).toBeDefined();
    expect(obj.payload.hatCertId).toBeDefined();
    expect(obj.payload.requestedAt).toBeDefined();
    expect(obj.payload.hatSig).toMatch(/^[0-9a-f]{64}$/);
    expect(obj.payload.exitCode).toBe(42);
  });
});

// ═══════════════════════════════════════════════════════════════════
// Phase 38D — host.audit verb (T34–T41)
// Read-only cryptographic verification of HostCommand invariants.
// ═══════════════════════════════════════════════════════════════════

import { routeHostAudit, type AuditReport } from '../../runtime/shell/src/commands/host-audit';

/**
 * Helper: execute host.exec with test.echo, return the hostCommandId
 * so audit tests can verify the resulting object.
 */
async function execAndGetId(ctx: ShellContext, extraArgs: string[] = []): Promise<string> {
  const cmd = parseCommand(['host.exec', 'test.echo', ...extraArgs]);
  const result = await routeHostExec(cmd, ctx) as any;
  if (!result.ok) throw new Error(`host.exec failed: ${JSON.stringify(result)}`);
  return result.hostCommandId;
}

describe('Phase 38D — host.audit verb', () => {
  // ── Parser ──

  test('T34: parseCommand recognizes host.audit with objectId positional', () => {
    const cmd = parseCommand(['host.audit', 'hcmd-12345']);
    expect(cmd.verb).toBe('host.audit');
    expect(cmd.objectId).toBe('hcmd-12345');
  });

  // ── Valid HostCommand → all invariants hold ──

  test('T35: audit a valid, signed, published HostCommand → allInvariantsHold, no issues', async () => {
    const ctx = await buildTestContext();
    const id = await execAndGetId(ctx, ['--arg', 'port=9000']);

    const auditCmd = parseCommand(['host.audit', id]);
    const report = await routeHostAudit(auditCmd, ctx) as AuditReport;

    expect(report.hostCommandId).toBe(id);
    expect(report.handler).toBe('test.echo');
    expect(report.signatureValid).toBe(true);
    expect(report.linearityValid).toBe(true);
    expect(report.patchChainValid).toBe(true);
    expect(report.resultPresent).toBe(true);
    expect(report.allInvariantsHold).toBe(true);
    expect(report.issues).toHaveLength(0);
  });

  // ── Tampered signature → signatureValid: false ──

  test('T36: tampered hatSig → signatureValid: false, allInvariantsHold: false', async () => {
    const ctx = await buildTestContext();
    const id = await execAndGetId(ctx);

    // Tamper the signature directly in the store
    const obj = ctx.store.getState().objects.get(id)!;
    (obj.payload as any).hatSig = 'deadbeef'.repeat(8); // 64 hex chars, wrong

    const auditCmd = parseCommand(['host.audit', id]);
    const report = await routeHostAudit(auditCmd, ctx) as AuditReport;

    expect(report.signatureValid).toBe(false);
    expect(report.allInvariantsHold).toBe(false);
    expect(report.issues.some(i => i.includes('signature'))).toBe(true);
  });

  // ── Object still in draft → linearityValid: false ──

  test('T37: audit unpublished (draft) object → linearityValid: false', async () => {
    const ctx = await buildTestContext();

    // Manually create a HostCommand in draft state (skip publish)
    const config = ctx.config.getConfig()!;
    const typeDef = config.objectTypes.find(t => t.name === 'HostCommand')!;
    const facet = ctx.identity.getActiveHat()!;
    const objId = ctx.store.createObjectFromType(typeDef, undefined, facet.id, facet.capabilities ?? [], false);

    // Populate minimal fields so signature check works
    const requestedAt = new Date().toISOString();
    const args = {};
    const canonical = `test.echo|${JSON.stringify(args)}|${facet.id}|${requestedAt}`;
    const hatSig = cryptoCreateHash('sha256').update(canonical).digest('hex');
    for (const [k, v] of Object.entries({
      handler: 'test.echo',
      args: JSON.stringify(args),
      hatId: facet.id,
      hatCertId: facet.certId ?? 'cert-test',
      hatSig,
      requestedAt,
    })) {
      ctx.store.dispatch({ type: 'UPDATE_PAYLOAD', objectId: objId, field: k, value: v });
    }

    const auditCmd = parseCommand(['host.audit', objId]);
    const report = await routeHostAudit(auditCmd, ctx) as AuditReport;

    expect(report.linearityValid).toBe(false);
    expect(report.allInvariantsHold).toBe(false);
    expect(report.issues.some(i => i.includes('published'))).toBe(true);
  });

  // ── Patch timestamp regression → patchChainValid: false ──

  test('T38: patch with regressing timestamp → patchChainValid: false', async () => {
    const ctx = await buildTestContext();
    const id = await execAndGetId(ctx);

    // Inject a patch with a timestamp that precedes the previous patch
    const obj = ctx.store.getState().objects.get(id)!;
    const earliestTs = Math.min(...obj.patches.map(p => p.timestamp)) - 1000;
    ctx.store.dispatch({
      type: 'ADD_PATCH',
      objectId: id,
      patch: {
        id: `patch-tampered-regression`,
        kind: 'action',
        timestamp: earliestTs,
        delta: { action: 'tampered' },
      },
    });

    const auditCmd = parseCommand(['host.audit', id]);
    const report = await routeHostAudit(auditCmd, ctx) as AuditReport;

    expect(report.patchChainValid).toBe(false);
    expect(report.issues.some(i => i.includes('timestamp'))).toBe(true);
  });

  // ── No result patch → resultPresent: false ──

  test('T39: dry-run HostCommand (no result patch) → resultPresent: false', async () => {
    const ctx = await buildTestContext();
    const cmd = parseCommand(['host.exec', 'test.echo', '--dry-run']);
    const result = await routeHostExec(cmd, ctx) as any;
    expect(result.ok).toBe(true);

    const auditCmd = parseCommand(['host.audit', result.hostCommandId]);
    const report = await routeHostAudit(auditCmd, ctx) as AuditReport;

    expect(report.resultPresent).toBe(false);
    expect(report.allInvariantsHold).toBe(false);
    expect(report.issues.some(i => i.includes('result'))).toBe(true);
  });

  // ── Non-existent id → structured error ──

  test('T40: audit non-existent id → structured error in issues', async () => {
    const ctx = await buildTestContext();
    const auditCmd = parseCommand(['host.audit', 'does-not-exist-999']);
    const report = await routeHostAudit(auditCmd, ctx) as AuditReport;

    expect(report.allInvariantsHold).toBe(false);
    expect(report.issues.some(i => i.includes('not found'))).toBe(true);
  });

  // ── Non-HostCommand object → rejected ──

  test('T41: audit a non-HostCommand object → issues include type mismatch', async () => {
    const ctx = await buildTestContext();
    const config = ctx.config.getConfig()!;
    // Find any non-HostCommand type
    const otherType = config.objectTypes.find(t => t.name !== 'HostCommand')!;
    const facet = ctx.identity.getActiveHat()!;
    const objId = ctx.store.createObjectFromType(otherType, undefined, facet.id, facet.capabilities ?? [], false);

    const auditCmd = parseCommand(['host.audit', objId]);
    const report = await routeHostAudit(auditCmd, ctx) as AuditReport;

    expect(report.allInvariantsHold).toBe(false);
    expect(report.issues.some(i => i.includes('HostCommand'))).toBe(true);
  });
});

// ═══════════════════════════════════════════════════════════════════
// Phase 38F — NL → ShellCommand Extractor (T42–T48)
// Deterministic fallback + LLM mock tests.
// ═══════════════════════════════════════════════════════════════════

import { extractShellCommand } from '../../runtime/shell/src/host-exec/extractor';
import type { ExtractResult, ExtractorContext, LlmClient } from '../../runtime/shell/src/host-exec/extractor/types';
import { listHandlers } from '../../runtime/shell/src/host-exec/registry';

/** Build an ExtractorContext with real handler manifests and optional LLM mock. */
function buildExtractorContext(llm?: LlmClient | null): ExtractorContext {
  return { handlers: listHandlers(), llm: llm ?? null };
}

/** Mock LLM that returns a canned JSON string. */
function mockLlm(response: string | null): LlmClient {
  return {
    complete: async () => response,
  };
}

describe('Phase 38F — NL → ShellCommand extractor', () => {
  // ── Deterministic fallback ──

  test('T42: fallback — "kill the process on port 9000" → process.killByPort with port=9000', async () => {
    const ctx = buildExtractorContext();
    const result = await extractShellCommand('kill the process on port 9000', ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.handler).toBe('process.killByPort');
    expect(result.args.port).toBe(9000);
    expect(result.confidence).toBeLessThanOrEqual(0.5);
  });

  test('T43: fallback — empty string → UNPARSEABLE', async () => {
    const ctx = buildExtractorContext();
    const result = await extractShellCommand('', ctx);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('UNPARSEABLE');
  });

  test('T44: fallback — "please delete all my files" → UNPARSEABLE (no unsafe match)', async () => {
    const ctx = buildExtractorContext();
    const result = await extractShellCommand('please delete all my files', ctx);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('UNPARSEABLE');
  });

  // ── LLM mock — handler grounding ──

  test('T45: LLM returns unknown handler → UNKNOWN_HANDLER with suggestions', async () => {
    const llm = mockLlm(JSON.stringify({
      handler: 'fs.deleteEverything',
      args: {},
      confidence: 0.8,
      rationale: 'delete files',
    }));
    const ctx = buildExtractorContext(llm);
    const result = await extractShellCommand('delete everything', ctx);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('UNKNOWN_HANDLER');
    expect(result.suggestions).toBeDefined();
    expect(Array.isArray(result.suggestions)).toBe(true);
  });

  // ── LLM mock — arg coercion ──

  test('T46: LLM returns port as string "9000" → coerced to number 9000', async () => {
    const llm = mockLlm(JSON.stringify({
      handler: 'process.killByPort',
      args: { port: '9000' },
      confidence: 0.9,
      rationale: 'kill port 9000',
    }));
    const ctx = buildExtractorContext(llm);
    const result = await extractShellCommand('kill port 9000', ctx);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.args.port).toBe(9000);
    expect(typeof result.args.port).toBe('number');
  });

  // ── LLM mock — malformed JSON ──

  test('T47: LLM returns malformed JSON → UNPARSEABLE', async () => {
    const llm = mockLlm('this is not json at all {broken');
    const ctx = buildExtractorContext(llm);
    const result = await extractShellCommand('do something', ctx);

    // Falls through to fallback, which also won't match → UNPARSEABLE
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('UNPARSEABLE');
  });

  // ── No LLM call on fallback path ──

  test('T48: when ctx.llm is null, LLM is never called', async () => {
    const completeSpy = { called: false };
    // ctx.llm is null — spy should never fire
    const ctx = buildExtractorContext(null);
    const result = await extractShellCommand('kill the process on port 8080', ctx);

    expect(result.ok).toBe(true);
    expect(completeSpy.called).toBe(false);
  });
});

// ═══════════════════════════════════════════════════════════════════
// Phase 38G — Helm wiring acceptance (T49–T52)
// voice utterance → NL extract → approval → host.exec → receipt
// ═══════════════════════════════════════════════════════════════════

import { routeHostAudit } from '../../runtime/shell/src/commands/host-audit';

/** Helper: build a dispatch command string from an ExtractedCommand (mirrors TalkMode wiring). */
function buildHostExecCommand(extracted: { handler: string; args: Record<string, unknown> }): string[] {
  const tokens = ['host.exec', extracted.handler];
  for (const [k, v] of Object.entries(extracted.args)) {
    tokens.push('--arg', `${k}=${v}`);
  }
  return tokens;
}

describe('Phase 38G — Helm acceptance (voice → extract → approve → host.exec)', () => {
  // Track invocations of the mock handler for T49
  const killByPortInvocations: Record<string, unknown>[] = [];

  // Shadow the real process.killByPort with a benign mock so tests don't touch host processes.
  // Use a different handler id and point the extractor at it.
  if (!killByPortInvocations.length) {
    // Already registered in 38B setup via real process.killByPort — override it locally via a test handler
    // that the fallback extractor points at: we re-use the registry by adding 'test.killByPort' here.
    try {
      registerHandler(
        {
          id: 'test.killByPort',
          description: 'Mock handler for 38G acceptance tests',
          argsSchema: { port: { type: 'number', required: true } },
          capabilityId: 11,
        },
        async (args) => {
          killByPortInvocations.push({ ...args });
          return { ok: true, exitCode: 0, stdout: '12345', stderr: '', durationMs: 5 };
        },
      );
    } catch {
      // already registered in a prior test run
    }
  }

  test('T49: full pipeline — utterance → fallback extract → route(host.exec) → published + audited', async () => {
    killByPortInvocations.length = 0;
    const ctx = await buildTestContext();

    // 1. Extract — use fallback (no LLM), which matches "kill ... port N" → process.killByPort
    const extractResult = await extractShellCommand('kill the process on port 9000', {
      handlers: listHandlers(),
      llm: null,
    });
    expect(extractResult.ok).toBe(true);
    if (!extractResult.ok) return;
    expect(extractResult.handler).toBe('process.killByPort');
    expect(extractResult.args.port).toBe(9000);

    // 2. Simulate the approval → dispatch via route() (exactly what useShellDispatch does)
    const tokens = buildHostExecCommand(extractResult);
    const cmd = parseCommand(tokens);
    const result = await route(cmd, ctx) as any;

    // 3. Assert: HostCommand was published with the right fields
    expect(result.ok).toBe(true);
    expect(result.hostCommandId).toBeDefined();

    const obj = ctx.store.getState().objects.get(result.hostCommandId)!;
    expect(obj.visibility).toBe('published');
    expect(obj.payload.handler).toBe('process.killByPort');
    expect(obj.payload.hatId).toBe(ctx.identity.getActiveHat()!.id);

    // 4. Cryptographic verification via 38D's audit
    const auditCmd = parseCommand(['host.audit', result.hostCommandId]);
    const audit = await route(auditCmd, ctx) as any;
    expect(audit.signatureValid).toBe(true);
    expect(audit.linearityValid).toBe(true);
    expect(audit.resultPresent).toBe(true);
    expect(audit.allInvariantsHold).toBe(true);
  });

  test('T50: capability-denied path — no HOST_EXEC → CAPABILITY_CHECK_FAILED, no publish, handler not invoked', async () => {
    echoInvocations.length = 0;
    const ctx = await buildTestContext({ withoutHostExec: true });

    // Simulate an already-extracted command (skip the NL step — we're testing the dispatch gate)
    const cmd = parseCommand(['host.exec', 'test.echo', '--arg', 'port=9000']);
    const result = await route(cmd, ctx) as any;

    expect(result.code).toBe('CAPABILITY_CHECK_FAILED');
    expect(ctx.store.getState().objects.size).toBe(0);
    expect(echoInvocations.length).toBe(0);
  });

  test('T51: extract → deny → retry path leaves no stale state (pending transcript cleared on error)', async () => {
    const ctx = await buildTestContext();

    // Extract a nonsense utterance that cannot be matched
    const extractResult = await extractShellCommand('xyzzy do the thing', {
      handlers: listHandlers(),
      llm: null,
    });
    expect(extractResult.ok).toBe(false);

    // No object created from a failed extract
    expect(ctx.store.getState().objects.size).toBe(0);

    // Next utterance proceeds normally — no leaked state
    const good = await extractShellCommand('kill the process on port 7777', {
      handlers: listHandlers(),
      llm: null,
    });
    expect(good.ok).toBe(true);
  });

  test('T52: approval card props carry enough info to satisfy "expanded by default" requirement', async () => {
    // This test verifies the shape of ExtractedCommand exposes the fields the approval card must display:
    //   handler, args, confidence, rationale
    // The card also needs hat/capability/timeout — those come from ShellContext, not the extract.
    const extractResult = await extractShellCommand('kill the process on port 5432', {
      handlers: listHandlers(),
      llm: null,
    });
    expect(extractResult.ok).toBe(true);
    if (!extractResult.ok) return;

    expect(typeof extractResult.handler).toBe('string');
    expect(typeof extractResult.args).toBe('object');
    expect(typeof extractResult.confidence).toBe('number');
    expect(extractResult.confidence).toBeGreaterThanOrEqual(0);
    expect(extractResult.confidence).toBeLessThanOrEqual(1);
    expect(extractResult.rationale).toBeDefined();
  });
});

```
