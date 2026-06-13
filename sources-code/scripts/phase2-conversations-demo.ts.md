---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/phase2-conversations-demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.323904+00:00
---

# scripts/phase2-conversations-demo.ts

```ts
#!/usr/bin/env bun
/**
 * Phase 2 Conversations Demo — End-to-end walkthrough of the multi-context
 * conversation platform.
 *
 * Demonstrates:
 *   1. Identity bootstrap (Alice + Bob)
 *   2. SELF thread with dimension extraction
 *   3. MESSAGING edge + 1:1 encrypted exchange
 *   4. ZONE creation + GROUP messages with zone key
 *   5. AI_AGENT thread with coach persona
 *   6. Cross-context Paskian correlations
 *   7. Context-weighted dimension scores
 *   8. Plexus graph state dump
 *   9. Settlement cost summary
 *
 * Usage:
 *   bun run scripts/phase2-conversations-demo.ts
 */

import { ConversationStore } from '../packages/shell/src/conversation-store';
import { ConversationType, ContextWeight } from '../packages/protocol-types/src/conversation-types';
import { EncryptionService } from '../packages/protocol-types/src/encryption-service';
import { KeyDerivationService } from '../packages/protocol-types/src/identity-adapters/KeyDerivationService';
import { getContextConfig, contextIcon } from '../packages/shell/src/context-router';
import { BUILTIN_PERSONAS, listPersonas } from '../packages/shell/src/agent-personas';
import {
  scoreDimension, scoreAllDimensions, detectCorrelations,
  dimensionSummary,
  type DimensionMention,
} from '../packages/navigation/src/dimension-scorer';
import { LifeDimension } from '../packages/navigation/src/types/navigation-objects';
import { createHash } from 'crypto';

// ── ANSI Colors ──────────────────────────────────────────────
const C = {
  reset:   '\x1b[0m',
  bold:    '\x1b[1m',
  dim:     '\x1b[2m',
  cyan:    '\x1b[36m',
  green:   '\x1b[32m',
  yellow:  '\x1b[33m',
  magenta: '\x1b[35m',
  red:     '\x1b[31m',
  blue:    '\x1b[34m',
};

function header(title: string): void {
  console.log(`\n${C.bold}${C.cyan}═══ ${title} ${'═'.repeat(Math.max(0, 60 - title.length))}${C.reset}\n`);
}

function step(n: number, label: string): void {
  console.log(`${C.bold}${C.green}  Step ${n}:${C.reset} ${label}`);
}

function info(label: string, value: string): void {
  console.log(`    ${C.dim}${label}:${C.reset} ${value}`);
}

// ── Demo ──────────────────────────────────────────────────────

async function main(): Promise<void> {
  console.log(`
${C.bold}${C.cyan}╔══════════════════════════════════════════════════════════╗
║       Phase 2: Conversations & Plexus Integration        ║
║                    End-to-End Demo                        ║
╚══════════════════════════════════════════════════════════╝${C.reset}
`);

  // Use a temp file so we don't pollute the real state
  const stateFile = `/tmp/semantos-phase2-demo-${Date.now()}.json`;
  const store = new ConversationStore(stateFile);

  let settlementTotal = 0;

  // ── 1. Identity Bootstrap ──────────────────────────────────

  header('1. Identity Bootstrap');

  const kds = new KeyDerivationService();

  const aliceRoot = kds.generateRootKey('alice@semantos.dev');
  const aliceCertId = kds.generateCertId(aliceRoot);
  step(1, 'Alice identity registered');
  info('CertId', aliceCertId);
  info('PublicKey', Buffer.from(aliceRoot).toString('hex').slice(0, 32) + '...');

  const bobRoot = kds.generateRootKey('bob@semantos.dev');
  const bobCertId = kds.generateCertId(bobRoot);
  step(2, 'Bob identity registered');
  info('CertId', bobCertId);

  // ── 2. SELF Thread ─────────────────────────────────────────

  header('2. SELF Thread — Self-Reflection');

  const selfThread = store.getSelfThread();
  step(3, `SELF thread exists: ${selfThread.conversationId.slice(0, 8)}...`);
  info('Context', `${contextIcon(ConversationType.SELF)} ${selfThread.contextType}`);
  info('Config', `weight=${getContextConfig(ConversationType.SELF).contextWeight}, settlement=${getContextConfig(ConversationType.SELF).settlementSats} sats`);

  const selfMsg1 = store.addMessage(selfThread.conversationId, 'user',
    'I need to focus more on my financial planning. I keep putting it off.',
    aliceCertId,
    { dimensionTag: 'FINANCIAL' },
  );
  settlementTotal += 25;

  const selfMsg2 = store.addMessage(selfThread.conversationId, 'assistant',
    'I notice a pattern: you mention financial planning frequently but describe resistance to starting. This is a common pattern in the FINANCIAL dimension.',
    'system',
    { dimensionTag: 'FINANCIAL' },
  );

  step(4, 'Self-reflection messages added');
  info('User message', selfMsg1!.content.slice(0, 50) + '...');
  info('Hash chain', `prevHash=${selfMsg1!.prevMessageHash.slice(0, 16)}...`);
  info('Msg2 prevHash', `${selfMsg2!.prevMessageHash.slice(0, 16)}... (links to msg1)`);

  // Verify hash chain
  const chainCheck = store.verifyHashChain(selfThread.conversationId);
  info('Hash chain valid', chainCheck.valid ? `${C.green}✓${C.reset}` : `${C.red}✗ broken at ${chainCheck.brokenAt}${C.reset}`);

  // ── 3. MESSAGING Edge + 1:1 Encrypted ──────────────────────

  header('3. MESSAGING Edge — 1:1 Encrypted Conversation');

  // Derive shared secret (BRC-85/86 ECDH simulation)
  const sharedSecret = EncryptionService.deriveSharedSecret(aliceCertId, bobCertId, 'messaging-v1');
  step(5, 'Shared secret derived (BRC-85/86 ECDH)');
  info('SharedSecret', sharedSecret.slice(0, 32) + '...');
  info('Algorithm', 'AES-256-GCM');

  // Create INDIVIDUAL thread
  const individualThread = store.createThread(
    ConversationType.INDIVIDUAL,
    'Bob',
    [aliceCertId, bobCertId],
    { algorithm: 'AES-256-GCM', keyDerivation: 'BRC-85', edgeId: `edge-${Date.now()}` },
  );
  step(6, `1:1 thread created: ${individualThread.conversationId.slice(0, 8)}...`);
  info('Participants', `${aliceCertId.slice(0, 12)}... ↔ ${bobCertId.slice(0, 12)}...`);
  info('Encryption', `${individualThread.encryptionMetadata?.algorithm} (${individualThread.encryptionMetadata?.keyDerivation})`);

  // Encrypt a message
  const plaintext = 'Hey Bob, have you looked at the budget spreadsheet? I think we should increase the savings target.';
  const messageKey = EncryptionService.deriveMessageKey(sharedSecret, 'msg-001');
  const encrypted = EncryptionService.encrypt(plaintext, messageKey);

  step(7, 'Message encrypted with AES-256-GCM');
  info('Plaintext', plaintext.slice(0, 50) + '...');
  info('Ciphertext', encrypted.ciphertext.slice(0, 40) + '...');
  info('IV', encrypted.iv);
  info('Tag', encrypted.tag);

  // Decrypt to verify
  const decrypted = EncryptionService.decrypt(encrypted, messageKey);
  info('Decrypted', decrypted.slice(0, 50) + '...');
  info('Match', plaintext === decrypted ? `${C.green}✓${C.reset}` : `${C.red}✗${C.reset}`);

  // Sign the message
  const signingKey = Buffer.from(aliceRoot).toString('hex');
  const signature = EncryptionService.signMessage(signingKey, plaintext);
  const sigValid = EncryptionService.verifySignature(signingKey, plaintext, signature);
  info('Signature', signature.slice(0, 32) + '...');
  info('Verified', sigValid ? `${C.green}✓${C.reset}` : `${C.red}✗${C.reset}`);

  // Store the message
  store.addMessage(individualThread.conversationId, 'user', plaintext, aliceCertId, {
    encryptedContent: encrypted.ciphertext,
    signature,
    dimensionTag: 'FINANCIAL',
  });
  settlementTotal += 25;

  store.addMessage(individualThread.conversationId, 'assistant',
    'Good idea! I was thinking the same thing. Let\'s also review the investment portfolio.',
    bobCertId,
    { dimensionTag: 'FINANCIAL' },
  );
  settlementTotal += 25;

  // ── 4. ZONE + GROUP Messages ───────────────────────────────

  header('4. ZONE Node — Group Conversation');

  // Create ZONE (simulate PlexusService.createZone)
  const zoneId = `zone-${Date.now().toString(36)}`;
  const zoneKey = createHash('sha256').update(`${aliceCertId}:${zoneId}:zone-key-v1`).digest('hex');

  step(8, 'ZONE node created');
  info('ZoneId', zoneId);
  info('GroupName', 'Family Finance');
  info('ZoneKey', zoneKey.slice(0, 32) + '...');
  info('Members', `Alice, Bob`);

  // Create GROUP thread
  const groupThread = store.createThread(
    ConversationType.GROUP,
    'Family Finance',
    [aliceCertId, bobCertId],
    { algorithm: 'AES-256-GCM', keyDerivation: 'ZONE', zoneId },
  );
  step(9, `GROUP thread created: ${groupThread.conversationId.slice(0, 8)}...`);

  // Group messages
  store.addMessage(groupThread.conversationId, 'user',
    'Team, let\'s review our monthly budget. I think we can save more on groceries.',
    aliceCertId,
    { dimensionTag: 'FINANCIAL' },
  );
  settlementTotal += 25; // Once per sender, not per recipient

  store.addMessage(groupThread.conversationId, 'user',
    'Agreed. I also want to discuss the home renovation budget.',
    bobCertId,
    { dimensionTag: 'FINANCIAL' },
  );
  settlementTotal += 25;

  step(10, 'Group messages exchanged');
  info('Settlement', '25 sats per sender (not per recipient)');

  // ── 5. AI_AGENT Thread ─────────────────────────────────────

  header('5. AI Agent — Coach Persona');

  const personas = listPersonas();
  step(11, `${personas.length} agent personas available`);
  for (const p of personas) {
    info(p.name, p.expertise);
  }

  const coachPersona = BUILTIN_PERSONAS[0]; // Coach
  const agentThread = store.createThread(
    ConversationType.AI_AGENT,
    coachPersona.name,
    [aliceCertId],
  );
  step(12, `AI_AGENT thread created: ${agentThread.conversationId.slice(0, 8)}...`);
  info('Persona', coachPersona.name);
  info('Settlement', `${getContextConfig(ConversationType.AI_AGENT).settlementSats} sats (no cost)`);

  store.addMessage(agentThread.conversationId, 'user',
    'Coach, I keep procrastinating on my financial goals. What should I do?',
    aliceCertId,
    { dimensionTag: 'FINANCIAL' },
  );
  // No settlement for AI_AGENT

  store.addMessage(agentThread.conversationId, 'assistant',
    'I notice you\'ve mentioned financial planning in your self-reflection AND in conversation with Bob. This is clearly important to you. Let\'s start with one small action today.',
    'coach',
    { dimensionTag: 'FINANCIAL' },
  );

  step(13, 'Coach conversation active — no settlement cost');

  // ── 6. Cross-Context Paskian Correlations ───────────────────

  header('6. Cross-Context Dimension Scoring');

  // Simulate dimension mentions across contexts
  const mentions: DimensionMention[] = [
    // SELF context
    { dimension: LifeDimension.FINANCIAL, contextType: 'SELF', conversationId: selfThread.conversationId, timestamp: new Date().toISOString(), strength: 0.8 },
    { dimension: LifeDimension.MENTAL, contextType: 'SELF', conversationId: selfThread.conversationId, timestamp: new Date().toISOString(), strength: 0.5 },
    // INDIVIDUAL context
    { dimension: LifeDimension.FINANCIAL, contextType: 'INDIVIDUAL', conversationId: individualThread.conversationId, timestamp: new Date().toISOString(), strength: 0.9 },
    { dimension: LifeDimension.SOCIAL, contextType: 'INDIVIDUAL', conversationId: individualThread.conversationId, timestamp: new Date().toISOString(), strength: 0.6 },
    // GROUP context
    { dimension: LifeDimension.FINANCIAL, contextType: 'GROUP', conversationId: groupThread.conversationId, timestamp: new Date().toISOString(), strength: 0.7 },
    { dimension: LifeDimension.FAMILIAL, contextType: 'GROUP', conversationId: groupThread.conversationId, timestamp: new Date().toISOString(), strength: 0.4 },
    // AI_AGENT context
    { dimension: LifeDimension.FINANCIAL, contextType: 'AI_AGENT', conversationId: agentThread.conversationId, timestamp: new Date().toISOString(), strength: 0.6 },
    { dimension: LifeDimension.VOCATIONAL, contextType: 'AI_AGENT', conversationId: agentThread.conversationId, timestamp: new Date().toISOString(), strength: 0.3 },
  ];

  step(14, 'Dimension mentions collected across all contexts');

  // Score all dimensions
  const scores = scoreAllDimensions(mentions);
  step(15, 'Context-weighted dimension scores:');
  console.log(dimensionSummary(scores));

  // Detect cross-context correlations
  const correlations = detectCorrelations(mentions);
  step(16, `${correlations.length} cross-context correlation(s) detected`);
  for (const insight of correlations) {
    console.log(`    ${C.yellow}⚡${C.reset} ${insight.insight}`);
    info('  Contexts', insight.contexts.join(', '));
  }

  // ── 7. Thread Summary ──────────────────────────────────────

  header('7. Conversation Thread Summary');

  const allThreads = store.listThreads();
  step(17, `${allThreads.length} total threads, ${store.totalMessages} total messages`);

  for (const thread of allThreads) {
    const icon = contextIcon(thread.contextType);
    const msgCount = thread.messageIds.length;
    const lock = thread.encryptionMetadata?.keyDerivation === 'BRC-85' ? '🔒 '
      : thread.encryptionMetadata?.keyDerivation === 'ZONE' ? '🛡 '
      : '';
    console.log(`    ${lock}${icon} ${C.bold}${thread.displayName}${C.reset} ${C.dim}(${thread.contextType} · ${msgCount} msgs · ${thread.conversationId.slice(0, 8)}...)${C.reset}`);
  }

  // ── 8. Plexus Graph State ──────────────────────────────────

  header('8. Plexus Graph State (Simulated)');

  const edges = [
    { type: 'MESSAGING', from: 'Alice', to: 'Bob', secret: sharedSecret.slice(0, 16) + '...' },
    { type: 'DATA_ACCESS', from: 'Alice', to: zoneId.slice(0, 12) + '...', secret: '(zone key)' },
    { type: 'DATA_ACCESS', from: 'Bob', to: zoneId.slice(0, 12) + '...', secret: '(zone key)' },
  ];

  step(18, `${edges.length} Plexus edges`);
  for (const e of edges) {
    console.log(`    ${C.dim}[${e.type}]${C.reset} ${e.from} ↔ ${e.to} ${C.dim}secret=${e.secret}${C.reset}`);
  }

  // ── 9. Settlement Summary ──────────────────────────────────

  header('9. Settlement Summary');

  step(19, 'BRC-100 settlement cost');
  info('Total messages (settled)', `${settlementTotal / 25}`);
  info('Cost per message', '25 sats');
  info('AI Agent messages', '0 sats (exempt)');
  info('Total settlement', `${C.bold}${settlementTotal} sats${C.reset}`);

  // Cleanup
  try {
    const fs = await import('fs');
    fs.unlinkSync(stateFile);
  } catch { /* ignore */ }

  console.log(`\n${C.bold}${C.green}✓ Phase 2 demo complete.${C.reset}\n`);
}

main().catch(err => {
  console.error(`Fatal: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
});

```
