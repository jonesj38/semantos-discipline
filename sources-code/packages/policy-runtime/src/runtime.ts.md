---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/policy-runtime/src/runtime.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.491618+00:00
---

# packages/policy-runtime/src/runtime.ts

```ts
/**
 * PolicyRuntime — shared evaluation engine for extension grammar policies.
 *
 * Routes compiled policy bytecode through the WASM 2-PDA kernel's executeScript,
 * with OP_CALLHOST dispatching to domain-specific host functions via HostFunctionRegistry.
 *
 * This is the ONLY code path that executes a .policy cell at runtime.
 * Extension grammars (CDM, SCADA, BoL, ...) all call through here.
 *
 * Phase 29.5 / D29.5.1
 */

import type { CellEngine } from '@semantos/cell-engine/bindings/bun/cell-engine';
import type { HostFunctionRegistry, HostFunctionContext } from '@semantos/cell-engine/bindings/host-functions';
import type { PolicyContext, PolicyResult, HostCallRecord, HostFunctionProvider } from './types';
import {
  ExtensionAuthorityError,
  RejectAuthorityVerifier,
  type AuthorityVerifier,
  type LexiconAuthority,
  type LoadedExtensionAuthority,
} from './authority';

export interface PolicyRuntimeOptions {
  /**
   * Authority verifier invoked at `loadExtension` time (D-A6). Defaults
   * to `RejectAuthorityVerifier` — extensions that declare an authority
   * MUST be loaded through a runtime configured with a real verifier
   * (typically `BrcVerifier` from `runtime/verifier-sidecar`). Tests
   * inject `StubAuthorityVerifier`.
   */
  authorityVerifier?: AuthorityVerifier;
}

export class PolicyRuntime {
  private readonly engine: CellEngine;
  private readonly registry: HostFunctionRegistry;
  /** Providers registered once at construction time (shared predicates). */
  private readonly baseProviders: HostFunctionProvider[];
  /**
   * Authority gate (D-A6). Extensions that mint capabilities or define
   * lexicons must pass this verifier before `loadExtension` returns.
   */
  private readonly authorityVerifier: AuthorityVerifier;
  /**
   * Extensions whose authority cert verified successfully, keyed by
   * extensionId. Capability scope is the authority's cert_id; the
   * runtime refuses cross-scope dispatch.
   */
  private readonly loadedExtensions: Map<string, LoadedExtensionAuthority> =
    new Map();

  constructor(
    engine: CellEngine,
    registry: HostFunctionRegistry,
    baseProviders: HostFunctionProvider[] = [],
    options: PolicyRuntimeOptions = {},
  ) {
    this.engine = engine;
    this.registry = registry;
    this.baseProviders = baseProviders;
    this.authorityVerifier =
      options.authorityVerifier ?? new RejectAuthorityVerifier();

    // Register base providers (e.g., builtin host functions)
    for (const provider of baseProviders) {
      provider.register(registry);
    }
  }

  /**
   * Verify and register an extension's lexicon authority (D-A6).
   *
   * MUST be called before any policy from this extension is evaluated
   * through `evaluate()`. Refuses to register the extension if:
   *   - the authority cert fails BRC-52 verification, or
   *   - the grammar signature does not bind `authority.grammarBytes`
   *     to `authority.cert.subjectPublicKey`.
   *
   * On success the extension is recorded under its authority cert_id;
   * subsequent `getExtension(id)` returns the record. Re-loading the
   * same extensionId re-verifies (no stale-state hazard if the
   * authority was rotated).
   *
   * @throws ExtensionAuthorityError on verification failure. The
   *         caller MUST NOT proceed to evaluate this extension's
   *         policies.
   */
  async loadExtension(
    extensionId: string,
    authority: LexiconAuthority,
  ): Promise<LoadedExtensionAuthority> {
    const result = await this.authorityVerifier.verifyAuthority(authority);
    if (!result.ok) {
      throw new ExtensionAuthorityError(
        `extension ${extensionId} authority verification failed: ${result.message}`,
        result.code,
        extensionId,
      );
    }
    const record: LoadedExtensionAuthority = {
      extensionId,
      authorityCertId: result.certId,
      authority,
    };
    this.loadedExtensions.set(extensionId, record);
    return record;
  }

  /**
   * Look up a previously-loaded extension's authority record.
   * Returns `undefined` if the extension was never loaded or its
   * authority failed verification.
   */
  getExtension(extensionId: string): LoadedExtensionAuthority | undefined {
    return this.loadedExtensions.get(extensionId);
  }

  /**
   * Drop an extension's authority record. Future `evaluate()` calls
   * scoped to this extension MUST be rejected by the caller (the
   * runtime no longer holds the authority cert_id for scope binding).
   */
  unloadExtension(extensionId: string): boolean {
    return this.loadedExtensions.delete(extensionId);
  }

  /**
   * Evaluate a compiled policy cell through the WASM 2-PDA.
   *
   * @param lockScript - The compiled policy bytecode (from LispCompiler → ScriptOutput.scriptBytes)
   * @param ctx - Frozen runtime context with fields, actor, and optional coActor
   * @param providers - Additional domain-specific host function providers for this evaluation
   * @returns PolicyResult — never throws
   */
  async evaluate(
    lockScript: Uint8Array,
    ctx: PolicyContext,
    providers: HostFunctionProvider[] = [],
  ): Promise<PolicyResult> {
    const hostCalls: HostCallRecord[] = [];

    // Register any per-evaluation providers
    for (const provider of providers) {
      provider.register(this.registry);
    }

    // Build the HostFunctionContext from PolicyContext
    // This is the frozen context that host functions read from
    const hostCtx: HostFunctionContext = {
      fields: ctx.fields,
      capabilities: ctx.actor.capabilities,
      certId: ctx.actor.certId,
      // Dual-auth: merge coActor capabilities
      coActorCapabilities: ctx.coActor?.capabilities,
      coActorCertId: ctx.coActor?.certId,
    };

    // Wrap the registry's call method to record host calls
    const originalCall = this.registry.call.bind(this.registry);
    const wrappedRegistry = {
      call: (name: string): number => {
        const result = originalCall(name);
        hostCalls.push({
          name,
          result,
          timestamp: Date.now() * 1000, // microseconds
        });
        return result;
      },
    };

    // Monkey-patch the registry's call for this evaluation
    // (The WASM host_call_by_name import calls registry.call internally)
    const savedCall = this.registry.call;
    (this.registry as any).call = wrappedRegistry.call;

    try {
      // Set the evaluation context
      this.registry.setContext(hostCtx);

      // Execute through the kernel
      const result = this.engine.executeScript(lockScript);

      // Read gas (opcode count)
      const gas = result.opcodeCount;

      if (result.success) {
        return {
          ok: true,
          gas,
          hostCalls,
        };
      } else {
        return {
          ok: false,
          gas,
          hostCalls,
          rejectionCode: result.error ?? 'VERIFY_FAILED',
          rejectionDetail: result.error ?? 'Policy evaluation failed: top-of-stack is falsy',
        };
      }
    } catch (err) {
      // Kernel errors surface as thrown errors from executeScript
      const message = err instanceof Error ? err.message : String(err);

      // Parse kernel error code from message (format: "Kernel error -N: ERROR_NAME")
      const codeMatch = message.match(/Kernel error (-?\d+): (\w+)/);
      const rejectionCode = codeMatch?.[2] ?? 'KERNEL_ERROR';

      return {
        ok: false,
        gas: 0,
        hostCalls,
        rejectionCode,
        rejectionDetail: message,
      };
    } finally {
      // Restore original call method and clear context
      (this.registry as any).call = savedCall;
      this.registry.clearContext();
    }
  }
}

```
