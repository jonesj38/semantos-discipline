---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/me/secret_questions_flow.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.121109+00:00
---

# apps/semantos/lib/shell/me/secret_questions_flow.dart

```dart
// C11 PR-C11-3 — Secret-questions setup sheet.
//
// Reference:
//   docs/design/HELM-ME-SURFACE.md §3, §6 D1 (3-of-3 fixed), §6 D5 (defaults
//     shown, custom allowed)
//   cartridges/wallet-headers/brain/src/popup-create.ts — UX reference.
//
// Collects 3 questions + answers from the operator, normalizes the
// answers (lowercase + collapse whitespace + trim), hashes each as
// sha256(salt || normalize(answer)) under a freshly-generated 32-byte
// salt, and persists the resulting ChallengeBundle via
// ChallengeBundleStore. RAW ANSWERS NEVER LEAVE THIS WIDGET — they're
// hashed in-place + wiped from the form state on Save.
//
// State machine:
//   1. Form (3 question fields + 3 answer fields + 3 retype-confirm
//      fields). Defaults pre-fill questions from
//      kDefaultChallengeQuestions; each question is editable per D5.
//   2. Validation:
//        - All 6 answer fields non-empty
//        - Each "answer" matches its "retype"
//        - No duplicates across the three answers
//        - No answer equals its own question
//      Hard-block on these. Soft-warn on single-word/short answers
//      (per popup-create.ts pattern) — surfaces a chip but doesn't
//      block.
//   3. On Save:
//        - Generate cryptographically-random 32-byte salt (Random.secure)
//        - Normalize each answer + sha256(salt || normalized)
//        - Build ChallengeBundle + persist via ChallengeBundleStore
//        - Pop sheet with `Navigator.pop(true)` so the caller knows
//          to refresh readiness
//   4. After save, the Me sheet's Recovery row's `hasQuestions` flips
//      true and the inline explainer updates accordingly.

import 'dart:convert' show utf8;
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../src/plexus/challenge_bundle_store.dart';
import '../../src/plexus/envelope.dart'
    show ChallengeBundle, kPbkdf2Iterations, normalizeAnswer;
import 'package:pointycastle/digests/sha256.dart';

/// Default questions from the wallet-headers reference. Editable per D5.
const List<String> kDefaultChallengeQuestions = [
  "Mother's maiden name?",
  "City of birth?",
  "First pet?",
];

/// Push the sheet and await Save. Returns true if a bundle was saved
/// (caller should refresh readiness); false if the operator cancelled.
Future<bool> showSecretQuestionsSheet(
  BuildContext context, {
  required ChallengeBundleStore store,
  StoredChallengeBundle? existing,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => _SecretQuestionsSheet(
      store: store,
      existing: existing,
    ),
  );
  return result ?? false;
}

class _SecretQuestionsSheet extends StatefulWidget {
  const _SecretQuestionsSheet({required this.store, this.existing});

  final ChallengeBundleStore store;

  /// If non-null, the sheet opens as an "Update" — questions pre-fill
  /// from the existing bundle (answers always start blank — we can't
  /// recover them from the hashes, by design).
  final StoredChallengeBundle? existing;

  @override
  State<_SecretQuestionsSheet> createState() => _SecretQuestionsSheetState();
}

class _SecretQuestionsSheetState extends State<_SecretQuestionsSheet> {
  static const int _kQuestionCount = 3;

  late List<TextEditingController> _questionCtl;
  late List<TextEditingController> _answerCtl;
  late List<TextEditingController> _retypeCtl;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialQuestions = widget.existing?.bundle.questions ??
        kDefaultChallengeQuestions;
    _questionCtl = List.generate(
      _kQuestionCount,
      (i) => TextEditingController(
        text: i < initialQuestions.length
            ? initialQuestions[i]
            : kDefaultChallengeQuestions[i],
      ),
    );
    _answerCtl =
        List.generate(_kQuestionCount, (_) => TextEditingController());
    _retypeCtl =
        List.generate(_kQuestionCount, (_) => TextEditingController());
  }

  @override
  void dispose() {
    // Best-effort wipe of in-memory answer buffers before disposal.
    for (final c in _answerCtl) {
      c.text = '';
      c.dispose();
    }
    for (final c in _retypeCtl) {
      c.text = '';
      c.dispose();
    }
    for (final c in _questionCtl) {
      c.dispose();
    }
    super.dispose();
  }

  /// Returns null when valid; otherwise the user-facing error message.
  String? _validate() {
    final questions = _questionCtl.map((c) => c.text.trim()).toList();
    final answers = _answerCtl.map((c) => c.text).toList();
    final retypes = _retypeCtl.map((c) => c.text).toList();
    for (var i = 0; i < _kQuestionCount; i++) {
      if (questions[i].isEmpty) return 'Question ${i + 1} is empty.';
      if (answers[i].isEmpty) return 'Answer ${i + 1} is empty.';
      if (retypes[i].isEmpty) return 'Retype ${i + 1} is empty.';
      if (normalizeAnswer(answers[i]) != normalizeAnswer(retypes[i])) {
        return "Answer ${i + 1} and retype don't match "
            '(normalized: lowercase + trim).';
      }
      if (normalizeAnswer(answers[i]) == normalizeAnswer(questions[i])) {
        return 'Answer ${i + 1} matches its question. Pick something else.';
      }
    }
    final normalized = answers.map(normalizeAnswer).toList();
    final unique = normalized.toSet();
    if (unique.length != normalized.length) {
      return 'All three answers must be different.';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final salt = _randomSalt();
      final saltHex = _bytesToHex(salt);
      final questions =
          _questionCtl.map((c) => c.text.trim()).toList(growable: false);
      final answerHashes = _answerCtl
          .map((c) => _hashAnswerHex(salt, normalizeAnswer(c.text)))
          .toList(growable: false);
      final bundle = ChallengeBundle(
        questions: questions,
        saltHex: saltHex,
        answerHashes: answerHashes,
        kdfIterations: kPbkdf2Iterations,
      );
      await widget.store.write(
        bundle,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      // Wipe form buffers before pop.
      for (final c in _answerCtl) {
        c.text = '';
      }
      for (final c in _retypeCtl) {
        c.text = '';
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      widget.existing == null
                          ? 'Set up secret questions'
                          : 'Update secret questions',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  children: [
                    Text(
                      'Three questions. Each answer gets normalized '
                      '(lowercased + whitespace-collapsed + trimmed) and '
                      'hashed with a fresh random salt before storage. '
                      'Plexus, the brain, and this device store ONLY the '
                      'hashes — never the raw answers.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < _SecretQuestionsSheetState._kQuestionCount; i++) ...[
                      _QuestionBlock(
                        index: i + 1,
                        questionCtl: _questionCtl[i],
                        answerCtl: _answerCtl[i],
                        retypeCtl: _retypeCtl[i],
                        disabled: _saving,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Save'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Uint8List _randomSalt() {
    final rng = Random.secure();
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }
}

class _QuestionBlock extends StatelessWidget {
  const _QuestionBlock({
    required this.index,
    required this.questionCtl,
    required this.answerCtl,
    required this.retypeCtl,
    required this.disabled,
  });

  final int index;
  final TextEditingController questionCtl;
  final TextEditingController answerCtl;
  final TextEditingController retypeCtl;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Question $index',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: questionCtl,
            enabled: !disabled,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: answerCtl,
            enabled: !disabled,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Answer',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: retypeCtl,
            enabled: !disabled,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Retype answer',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Hashing — used here at form-save time. Mirrors plexus/envelope.dart's
// internal _hashAnswer, kept private to the form widget so the
// envelope builder stays the canonical source.
// ─────────────────────────────────────────────────────────────────────

String _hashAnswerHex(Uint8List salt, String normalizedAnswer) {
  final ans = Uint8List.fromList(utf8.encode(normalizedAnswer));
  final buf = Uint8List(salt.length + ans.length)
    ..setRange(0, salt.length, salt)
    ..setRange(salt.length, salt.length + ans.length, ans);
  return _bytesToHex(SHA256Digest().process(buf));
}

String _bytesToHex(Uint8List bytes) {
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

```
