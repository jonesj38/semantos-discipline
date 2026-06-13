---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/dock/Tier3Popover.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.974470+00:00
---

# archive/apps-loom-react/src/helm/dock/Tier3Popover.tsx

```tsx
/**
 * Tier3Popover — the compression-gradient surface.
 *
 * Three input modes in one popover (per docs/BRAINSTORM-DOCK-SHELL-SILOS.md §2):
 *   - favourites:  compressed CLI (pre-wired actions)
 *   - text input:  raw CLI (type anything, parseCommand handles it)
 *   - mic:         NL compression (Web Speech → text input)
 *
 * Special variant: **who-picker** (talk.direct / talk.squad).
 * These contexts model "who are you talking to", not "what to create",
 * so the favourites slot is replaced by a picker whose input field is a
 * name / @handle / identity-id selector. Submitting surfaces a
 * "contacts book lands with Plexus" hint instead of dispatching — the
 * real resolver will come with the Plexus SDK.
 *
 * When a favourite or submitted text resolves, we emit `onInvoke(command, result)`
 * so the parent can surface a DetailPane or refresh the attention surface.
 */

import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { Favourite, ContextPath } from './context-weights';
import { useSpeechInput } from './useSpeechInput';
import { useShellDispatch, type ShellDispatchResult } from '../../hooks/useShellDispatch';

/** Context paths that render the who-picker instead of favourites. */
const WHO_PICKER_PATHS = new Set<ContextPath>(['talk.direct', 'talk.squad']);

export interface Tier3PopoverProps {
  contextPath: ContextPath;
  contextLabel: string;
  contextIcon: string;
  favourites: Favourite[];
  onInvoke: (command: string, result: ShellDispatchResult) => void;
  onClose: () => void;
}

export function Tier3Popover({
  contextPath,
  contextLabel,
  contextIcon,
  favourites,
  onInvoke,
  onClose,
}: Tier3PopoverProps) {
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const [stubHint, setStubHint] = useState<string | null>(null);
  const [squadName, setSquadName] = useState('');
  const [participants, setParticipants] = useState<string[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);
  const squadNameRef = useRef<HTMLInputElement>(null);
  const dispatch = useShellDispatch();
  const speech = useSpeechInput();

  const isWhoPicker = WHO_PICKER_PATHS.has(contextPath);
  const whoVariant: 'direct' | 'squad' | null = useMemo(() => {
    if (contextPath === 'talk.direct') return 'direct';
    if (contextPath === 'talk.squad') return 'squad';
    return null;
  }, [contextPath]);

  // Autofocus the input when the popover opens; reset per-context state.
  useEffect(() => {
    // Squad variant focuses the name field first; everything else focuses input.
    if (whoVariant === 'squad') squadNameRef.current?.focus();
    else inputRef.current?.focus();
    setStubHint(null);
    setInput('');
    setSquadName('');
    setParticipants([]);
  }, [contextPath, whoVariant]);

  // Mic transcript flows into the text input live.
  useEffect(() => {
    if (speech.transcript) setInput(speech.transcript);
  }, [speech.transcript]);

  // Esc closes the popover.
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onClose();
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose]);

  // Live filter favourites against text input (progressive disclosure).
  const filter = input.trim().toLowerCase();
  const shownFavourites = filter
    ? favourites.filter(f =>
        f.label.toLowerCase().includes(filter) ||
        f.typeName.toLowerCase().includes(filter) ||
        f.command.toLowerCase().includes(filter),
      )
    : favourites;

  async function runCommand(command: string) {
    setStubHint(null);
    setBusy(true);
    try {
      const result = await dispatch(command);
      onInvoke(command, result);
      setInput('');
      speech.reset();
    } finally {
      setBusy(false);
    }
  }

  function handleFavourite(fav: Favourite) {
    if (fav.stubbed) {
      setStubHint(fav.stubNote ?? `${fav.typeName} isn't wired yet — coming with Plexus.`);
      return;
    }
    runCommand(fav.command);
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;

    // Who-picker paths don't dispatch (contacts book needs Plexus);
    // they accumulate participants instead and show a clear next-step hint.
    if (isWhoPicker) {
      const value = input.trim();
      if (!value) return;
      setParticipants(prev => (prev.includes(value) ? prev : [...prev, value]));
      setInput('');
      speech.reset();
      return;
    }

    if (!input.trim()) return;
    runCommand(input.trim());
  }

  function handleMicToggle() {
    if (speech.listening) speech.stop();
    else speech.start();
  }

  function handleRemoveParticipant(name: string) {
    setParticipants(prev => prev.filter(p => p !== name));
  }

  function handleSendWho() {
    if (participants.length === 0) {
      setStubHint(
        whoVariant === 'squad'
          ? 'Add at least one member, then name your squad.'
          : 'Pick at least one recipient.',
      );
      return;
    }
    if (whoVariant === 'squad' && !squadName.trim()) {
      setStubHint('Name the squad — try "core-devs" or "sunday-dinner".');
      squadNameRef.current?.focus();
      return;
    }
    setStubHint(
      whoVariant === 'squad'
        ? `Squad "${squadName.trim()}" with ${participants.length} member${
            participants.length === 1 ? '' : 's'
          } — lands with the Plexus SDK (contacts book + group routing).`
        : `Direct message to ${participants.length} recipient${
            participants.length === 1 ? '' : 's'
          } — lands with the Plexus SDK (identity resolution + E2E channel).`,
    );
  }

  return (
    <div
      role="dialog"
      aria-label={`${contextLabel} actions`}
      className="bg-gray-900 border border-gray-700 rounded-lg shadow-2xl p-2 min-w-[280px] max-w-[360px]"
      onClick={(e) => e.stopPropagation()}
    >
      <div className="flex items-center gap-2 px-2 py-1 text-xs text-gray-400 border-b border-gray-800 mb-2">
        <span>{contextIcon}</span>
        <span>{contextLabel}</span>
        {isWhoPicker && (
          <span className="ml-auto text-[10px] uppercase tracking-wide text-gray-500">
            who-picker
          </span>
        )}
      </div>

      {/* Who-picker (talk.direct / talk.squad) — replaces favourites list. */}
      {isWhoPicker && (
        <div className="flex flex-col gap-1.5 mb-2">
          {whoVariant === 'squad' && (
            <div className="flex items-center gap-1 bg-gray-800 rounded px-2 py-1">
              <span className="text-gray-500 text-xs">{'\u2302'}</span>
              <input
                ref={squadNameRef}
                type="text"
                value={squadName}
                onChange={(e) => setSquadName(e.target.value)}
                placeholder="squad name (e.g. core-devs)"
                disabled={busy}
                className="flex-1 bg-transparent text-sm text-gray-100 placeholder-gray-500 focus:outline-none font-mono"
                autoComplete="off"
                spellCheck={false}
                aria-label="Squad name"
              />
            </div>
          )}
          {participants.length > 0 ? (
            <div className="flex flex-wrap gap-1 px-1">
              {participants.map(p => (
                <span
                  key={p}
                  className="flex items-center gap-1 bg-gray-800 text-gray-200 rounded-full pl-2 pr-1 py-0.5 text-xs border border-gray-700"
                >
                  <span className="text-gray-400">@</span>
                  <span className="max-w-[140px] truncate">{p}</span>
                  <button
                    type="button"
                    onClick={() => handleRemoveParticipant(p)}
                    className="ml-0.5 w-4 h-4 flex items-center justify-center rounded-full text-gray-500 hover:text-red-400 hover:bg-gray-700"
                    aria-label={`Remove ${p}`}
                  >
                    {'\u2715'}
                  </button>
                </span>
              ))}
            </div>
          ) : (
            <div className="text-[11px] text-gray-500 px-2">
              {whoVariant === 'squad'
                ? 'Add members one at a time — squads can mix people, squads, and agents.'
                : 'Pick who to message — individual identity or agent.'}
            </div>
          )}
          <div className="flex items-center justify-between gap-2 px-1 pt-0.5">
            <span className="text-[10px] text-gray-500 italic">
              Contacts book lands with Plexus.
            </span>
            <button
              type="button"
              onClick={handleSendWho}
              disabled={busy || participants.length === 0}
              className="text-xs px-2 py-0.5 rounded bg-blue-600/80 hover:bg-blue-500 text-white disabled:bg-gray-800 disabled:text-gray-500 transition-colors"
              title={whoVariant === 'squad' ? 'Create squad' : 'Open direct channel'}
            >
              {whoVariant === 'squad' ? 'Create squad' : 'Open channel'}
            </button>
          </div>
        </div>
      )}

      {/* Favourites (hidden in who-picker mode). */}
      {!isWhoPicker && (
        <div className="flex flex-col gap-0.5 mb-2">
          {shownFavourites.length === 0 && !filter && (
            <div className="text-xs text-gray-500 px-2 py-3 text-center">
              No favourites yet. Type what you want to do, or press the mic.
            </div>
          )}
          {shownFavourites.length === 0 && filter && (
            <div className="text-xs text-gray-500 px-2 py-2">
              Press Enter to run: <span className="font-mono text-gray-300">{filter}</span>
            </div>
          )}
          {shownFavourites.map((fav, i) => (
            <button
              key={fav.typeName}
              data-fav-idx={i}
              onClick={() => handleFavourite(fav)}
              disabled={busy}
              className={`flex items-center justify-between gap-2 px-2 py-1.5 rounded hover:bg-gray-800 text-left group disabled:opacity-50 ${
                fav.stubbed ? 'opacity-70' : ''
              }`}
              title={fav.stubbed ? fav.stubNote ?? `${fav.typeName} (coming soon)` : fav.command}
            >
              <span className="text-sm text-gray-200 group-hover:text-white flex items-center">
                <span className={`mr-1.5 ${fav.stubbed ? 'text-gray-600' : 'text-yellow-500'}`}>
                  {fav.stubbed ? '\u25CB' : '\u2605'}
                </span>
                {fav.label}
                {fav.stubbed && (
                  <span className="ml-2 text-[9px] uppercase tracking-wide text-amber-400/80 border border-amber-500/30 rounded px-1 py-[1px]">
                    soon
                  </span>
                )}
              </span>
              <kbd className="text-[10px] text-gray-500 font-mono bg-gray-800 px-1.5 py-0.5 rounded opacity-0 group-hover:opacity-100 transition-opacity">
                {i + 1}
              </kbd>
            </button>
          ))}
        </div>
      )}

      {stubHint && (
        <div className="mx-1 mb-2 rounded border border-amber-500/30 bg-amber-900/20 px-2 py-1.5 text-[11px] text-amber-200 flex items-start gap-1.5">
          <span className="text-amber-400 mt-[1px]">{'\u29B7'}</span>
          <span className="flex-1">{stubHint}</span>
          <button
            type="button"
            onClick={() => setStubHint(null)}
            className="text-amber-300/60 hover:text-amber-200 shrink-0"
            aria-label="Dismiss"
          >
            {'\u2715'}
          </button>
        </div>
      )}

      {/* Text + mic input (compression gradient tiers 2 and 1) */}
      <form onSubmit={handleSubmit} className="border-t border-gray-800 pt-2">
        <div className="flex items-center gap-1 bg-gray-800 rounded px-2 py-1">
          <span className="text-gray-500 text-xs">{'\u23F5'}</span>
          <input
            ref={inputRef}
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder={
              isWhoPicker
                ? 'name, @handle, or identity id — Enter to add'
                : 'type or speak a command…'
            }
            disabled={busy}
            className="flex-1 bg-transparent text-sm text-gray-100 placeholder-gray-500 focus:outline-none font-mono"
            autoComplete="off"
            spellCheck={false}
          />
          {speech.supported && (
            <button
              type="button"
              onClick={handleMicToggle}
              disabled={busy}
              className={`w-6 h-6 flex items-center justify-center rounded transition-colors ${
                speech.listening
                  ? 'bg-red-500/80 text-white animate-pulse'
                  : 'text-gray-500 hover:text-gray-200 hover:bg-gray-700'
              }`}
              aria-label={speech.listening ? 'Stop listening' : 'Start voice input'}
              title={speech.listening ? 'Listening… click to stop' : 'Voice input'}
            >
              {'\uD83C\uDFA4'}
            </button>
          )}
        </div>
        {speech.error && (
          <div className="text-[10px] text-red-400 mt-1 px-1">Mic: {speech.error}</div>
        )}
      </form>
    </div>
  );
}

```
