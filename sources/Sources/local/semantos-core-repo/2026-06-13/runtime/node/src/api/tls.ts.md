---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/api/tls.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.309662+00:00
---

# runtime/node/src/api/tls.ts

```ts
/**
 * TLS certificate loading and validation utilities.
 *
 * Loads node cert, key, and CA from the certs directory.
 * Provides helpers for client certificate validation in mutual TLS.
 *
 * Cross-references:
 *   Phase 26G PRD (D26G.4) — mutual TLS authentication
 */

import { existsSync, readFileSync } from 'fs';
import { join } from 'path';

export interface TlsConfig {
  cert: string;
  key: string;
  ca: string;
}

/**
 * Load TLS configuration from a certs directory.
 *
 * Expects:
 *   certsDir/node.crt — node certificate (PEM)
 *   certsDir/node.key — node private key (PEM)
 *   certsDir/ca.crt   — CA certificate (PEM)
 *
 * @throws Error if any required file is missing
 */
export function loadTlsConfig(certsDir: string): TlsConfig {
  const certPath = join(certsDir, 'node.crt');
  const keyPath = join(certsDir, 'node.key');
  const caPath = join(certsDir, 'ca.crt');

  if (!existsSync(certPath)) {
    throw new Error(`TLS cert not found: ${certPath}`);
  }
  if (!existsSync(keyPath)) {
    throw new Error(`TLS key not found: ${keyPath}`);
  }
  if (!existsSync(caPath)) {
    throw new Error(`TLS CA not found: ${caPath}`);
  }

  return {
    cert: readFileSync(certPath, 'utf-8'),
    key: readFileSync(keyPath, 'utf-8'),
    ca: readFileSync(caPath, 'utf-8'),
  };
}

/**
 * Generate self-signed TLS certificates for development/testing.
 *
 * Creates a CA, node cert, and client cert in the specified directory.
 * Uses openssl via Bun.spawn.
 */
export async function generateSelfSignedCerts(outputDir: string): Promise<void> {
  const { mkdirSync } = await import('fs');
  mkdirSync(outputDir, { recursive: true });

  // Generate CA key and cert
  await run('openssl', [
    'req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1',
    '-keyout', join(outputDir, 'ca.key'),
    '-out', join(outputDir, 'ca.crt'),
    '-days', '3650',
    '-nodes',
    '-subj', '/CN=Semantos CA',
  ]);

  // Generate node key and CSR
  await run('openssl', [
    'req', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1',
    '-keyout', join(outputDir, 'node.key'),
    '-out', join(outputDir, 'node.csr'),
    '-nodes',
    '-subj', '/CN=Semantos Node',
  ]);

  // Sign node cert with CA
  await run('openssl', [
    'x509', '-req',
    '-in', join(outputDir, 'node.csr'),
    '-CA', join(outputDir, 'ca.crt'),
    '-CAkey', join(outputDir, 'ca.key'),
    '-CAcreateserial',
    '-out', join(outputDir, 'node.crt'),
    '-days', '365',
  ]);

  // Generate client key and CSR (for admin API access)
  await run('openssl', [
    'req', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1',
    '-keyout', join(outputDir, 'client.key'),
    '-out', join(outputDir, 'client.csr'),
    '-nodes',
    '-subj', '/CN=Semantos Admin Client',
  ]);

  // Sign client cert with CA
  await run('openssl', [
    'x509', '-req',
    '-in', join(outputDir, 'client.csr'),
    '-CA', join(outputDir, 'ca.crt'),
    '-CAkey', join(outputDir, 'ca.key'),
    '-CAcreateserial',
    '-out', join(outputDir, 'client.crt'),
    '-days', '365',
  ]);
}

async function run(cmd: string, args: string[]): Promise<void> {
  const proc = Bun.spawn([cmd, ...args], {
    stdout: 'ignore',
    stderr: 'pipe',
  });
  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(`${cmd} exited with ${exitCode}: ${stderr}`);
  }
}

```
