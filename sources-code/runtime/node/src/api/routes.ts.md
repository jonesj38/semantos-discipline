---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/api/routes.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.309385+00:00
---

# runtime/node/src/api/routes.ts

```ts
/**
 * Admin API route handlers.
 *
 * All handlers receive the SemantosNode reference and return a Response.
 * Routes are matched by the server module; handlers are pure functions.
 *
 * Cross-references:
 *   Phase 26G PRD (D26G.4) — endpoint specifications
 *   protocol-types/src/types/semantos-node.ts — SemantosNode, NodeStatus
 *   protocol-types/src/extension-registry.ts — ExtensionRegistry
 */

import type { SemantosNode } from '@semantos/protocol-types';
import { success, error } from './envelope';

// ── Node Introspection ───────────────────────────────────────────

export function handleGetStatus(node: SemantosNode): Response {
  return success(node.getStatus());
}

export async function handleGetSelf(node: SemantosNode): Promise<Response> {
  const selfPath = `objects/sovereignty/node/${node.config.nodeCert}`;
  const cellValue = await node.semanticFs.get(selfPath);
  if (!cellValue) {
    return error('NOT_FOUND', 'Node self-object not found', 404);
  }
  const payload = JSON.parse(new TextDecoder().decode(cellValue.payload));
  return success({
    path: selfPath,
    linearity: cellValue.header.linearity,
    payload,
  });
}

// ── Extension Management ──────────────────────────────────────────

export function handleGetExtensions(node: SemantosNode): Response {
  const extensions = node.config.extensions.map(v => ({
    name: v,
    installed: true,
  }));
  return success(extensions);
}

export async function handleInstallExtension(
  node: SemantosNode,
  req: Request,
): Promise<Response> {
  let body: { name: string; version?: string };
  try {
    body = await req.json();
  } catch {
    return error('INVALID_BODY', 'Request body must be JSON with { name }', 400);
  }
  if (!body.name) {
    return error('MISSING_NAME', 'Extension name is required', 400);
  }

  if (node.config.extensions.includes(body.name)) {
    return success({ status: 'already_installed', name: body.name });
  }

  node.config.extensions.push(body.name);
  return success({ status: 'installed', name: body.name });
}

export function handleDeleteExtension(
  node: SemantosNode,
  extensionName: string,
): Response {
  const idx = node.config.extensions.indexOf(extensionName);
  if (idx === -1) {
    return error('NOT_FOUND', `Extension "${extensionName}" not installed`, 404);
  }
  node.config.extensions.splice(idx, 1);
  return success({ status: 'removed', name: extensionName });
}

// ── Identity Management ──────────────────────────────────────────

export async function handleGetIdentities(node: SemantosNode): Promise<Response> {
  try {
    const root = await node.identity.resolveIdentity(node.config.nodeCert);
    return success([root]);
  } catch {
    return success([]);
  }
}

export async function handleGetIdentity(
  node: SemantosNode,
  certId: string,
): Promise<Response> {
  try {
    const identity = await node.identity.resolveIdentity(certId);
    return success(identity);
  } catch (err) {
    return error('NOT_FOUND', `Identity "${certId}" not found`, 404);
  }
}

export async function handleCreateIdentity(
  node: SemantosNode,
  req: Request,
): Promise<Response> {
  let body: { email: string };
  try {
    body = await req.json();
  } catch {
    return error('INVALID_BODY', 'Request body must be JSON with { email }', 400);
  }
  if (!body.email) {
    return error('MISSING_EMAIL', 'Email is required', 400);
  }

  try {
    const result = await node.identity.registerIdentity(body.email);
    return success(result);
  } catch (err: any) {
    return error('REGISTER_FAILED', err.message ?? 'Registration failed', 500);
  }
}

export async function handleRevokeIdentity(
  node: SemantosNode,
  certId: string,
): Promise<Response> {
  // Identity adapter doesn't have a revoke method directly.
  // For now, return a placeholder — future phases will add cert revocation.
  return success({ status: 'revoked', certId });
}

// ── Anchor Management ────────────────────────────────────────────

export async function handleAnchorNow(node: SemantosNode): Promise<Response> {
  try {
    const stateHash = Buffer.from(
      new TextEncoder().encode(JSON.stringify(node.getStatus())),
    ).toString('hex').slice(0, 64);

    const proof = await node.anchor.anchor(stateHash, {
      bcaAddress: node.config.bcaAddress,
      typeHint: 'sovereignty.node',
    });
    return success(proof);
  } catch (err: any) {
    return error('ANCHOR_FAILED', err.message ?? 'Anchor failed', 500);
  }
}

export function handleGetAnchorInterval(node: SemantosNode): Response {
  const intervalMs = node.anchor.getAnchorInterval();
  return success({ intervalMs });
}

export async function handleSetAnchorInterval(
  node: SemantosNode,
  req: Request,
): Promise<Response> {
  let body: { ms: number };
  try {
    body = await req.json();
  } catch {
    return error('INVALID_BODY', 'Request body must be JSON with { ms }', 400);
  }
  if (typeof body.ms !== 'number' || body.ms < 0) {
    return error('INVALID_INTERVAL', 'Interval must be a non-negative number', 400);
  }

  node.anchor.setAnchorInterval(body.ms);
  return success({ intervalMs: body.ms });
}

export async function handleGetAnchors(node: SemantosNode): Promise<Response> {
  try {
    const proofKeys = await node.storage.list('proofs/');
    const proofs: unknown[] = [];
    const recentKeys = proofKeys.slice(-10);
    for (const key of recentKeys) {
      const data = await node.storage.read(key);
      if (data) {
        proofs.push(JSON.parse(new TextDecoder().decode(data)));
      }
    }
    return success(proofs);
  } catch {
    return success([]);
  }
}

// ── Shell Integration ────────────────────────────────────────────

export async function handleShellCommand(
  _node: SemantosNode,
  req: Request,
): Promise<Response> {
  let body: { prompt: string };
  try {
    body = await req.json();
  } catch {
    return error('INVALID_BODY', 'Request body must be JSON with { prompt }', 400);
  }
  if (!body.prompt) {
    return error('MISSING_PROMPT', 'Prompt is required', 400);
  }

  // Shell integration is deferred to Phase 28 (Flutter mobile shell).
  // For now, echo the prompt as acknowledgement.
  return success({
    response: `Received: ${body.prompt}`,
    objectPath: null,
    nextPrompt: null,
  });
}

```
