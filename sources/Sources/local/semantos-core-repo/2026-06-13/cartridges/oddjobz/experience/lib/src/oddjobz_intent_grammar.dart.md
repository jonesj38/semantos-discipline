---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/oddjobz_intent_grammar.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.460188+00:00
---

# cartridges/oddjobz/experience/lib/src/oddjobz_intent_grammar.dart

```dart
import 'package:semantos_core/semantos_core.dart';

import 'intents.dart';

/// Oddjobz IntentGrammar implementation.
///
/// Registers grammar fragment + lexicon with the shell's
/// ConversationEngine and handles dispatched oddjobz intents.
///
/// Architecture:
///   shell (STT → llama_cpp extraction) → dispatches StructuredIntent
///   → OddjobzIntentGrammar.onIntent handles it
///   → resolves lock script from recipientPubkeyHex
///   → calls ctx.wallet.pay([Output(lockScript, sats)])
class OddjobzIntentGrammar extends IntentGrammar {
  @override
  String get grammarFragment => r'''
# oddjobz intents (GBNF fragment for llama_cpp constrained generation)
oddjobz-intent ::= pay-milestone | transition-job | assign-worker | request-quote
pay-milestone   ::= "pay_milestone" ws "{" ws pay-milestone-fields ws "}"
transition-job  ::= "transition_job" ws "{" ws transition-job-fields ws "}"
assign-worker   ::= "assign_worker" ws "{" ws assign-worker-fields ws "}"
request-quote   ::= "request_quote" ws "{" ws request-quote-fields ws "}"
ws              ::= [ \t\n]*
''';

  @override
  List<LexiconEntry> get lexicon => const [
        LexiconEntry(term: 'job', description: 'A field service job', synonyms: ['work order', 'callout']),
        LexiconEntry(term: 'milestone', description: 'A payment milestone on a job'),
        LexiconEntry(term: 'tradie', description: 'A tradesperson assigned to a job', synonyms: ['worker', 'tradesperson']),
        LexiconEntry(term: 'quote', description: 'A price estimate for a job'),
        LexiconEntry(term: 'invoice', description: 'A payment request for completed work'),
        LexiconEntry(term: 'site', description: 'A job site location'),
        LexiconEntry(term: 'variation', description: 'A change to the original job scope'),
      ];

  @override
  Future<bool> onIntent(StructuredIntent intent, IntentContext ctx) async {
    if (intent is PayMilestone) {
      await _handlePayMilestone(intent, ctx);
      return true;
    }
    if (intent is TransitionJob) {
      // TransitionJob → anchorTransition is handled by the job FSM on the
      // brain side; the experience triggers the FSM transition via the
      // brain HTTP API. Wallet anchor spend happens inside brain.
      return true;
    }
    if (intent is AssignWorker) {
      return true;
    }
    if (intent is RequestQuote) {
      return true;
    }
    return false;
  }

  Future<void> _handlePayMilestone(
    PayMilestone intent,
    IntentContext ctx,
  ) async {
    // Contact resolution: pubkey hex → P2PKH lock script.
    // The pubkey is already resolved by the intent extraction pipeline
    // (contact book lives in the experience, not the wallet).
    final lockScript = _p2pkhLockScriptFromPubkeyHex(intent.recipientPubkeyHex);
    await ctx.wallet.pay(
      [Output(lockScript, intent.amountSats)],
      description: 'Job #${intent.jobId} milestone payment',
    );
  }

  /// Derives a P2PKH lock script hex string from a compressed public key hex.
  /// The full derivation (SHA256 + RIPEMD160) runs via semantos_ffi in
  /// production; this stub encodes the expected script shape for wiring.
  String _p2pkhLockScriptFromPubkeyHex(String pubkeyHex) {
    // TODO(P4b): call semantos_ffi.hash160(pubkeyHex) for the real script.
    // OP_DUP OP_HASH160 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG
    // For now return a sentinel so the wiring is exercisable in tests.
    return '76a914${pubkeyHex.substring(0, 40)}88ac';
  }
}

```
