---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/VoiceInput.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.963881+00:00
---

# archive/apps-loom-react/src/helm/VoiceInput.tsx

```tsx
/**
 * VoiceInput — mic button + live transcript + edit-before-submit.
 *
 * Wraps useVoiceCapture for the Helm Talk surface. Fires onUtterance
 * when the user submits their (optionally edited) transcript.
 *
 * Phase 38E — 38G wires onUtterance to the NL extractor pipeline.
 */

import React, { useCallback, useEffect, useState } from 'react';
import { useVoiceCapture } from './hooks/useVoiceCapture';

export interface VoiceInputProps {
  onUtterance: (text: string) => void;
  lang?: string;
  continuous?: boolean;
}

export function VoiceInput({ onUtterance, lang, continuous }: VoiceInputProps) {
  const voice = useVoiceCapture({ lang, continuous });
  const [editableText, setEditableText] = useState('');

  // Sync finalized transcript into the editable field
  useEffect(() => {
    if (voice.transcript) {
      setEditableText(voice.transcript);
    }
  }, [voice.transcript]);

  const handleToggle = useCallback(() => {
    if (voice.listening) {
      voice.stop();
    } else {
      voice.start();
    }
  }, [voice.listening, voice.start, voice.stop]);

  const handleSubmit = useCallback(() => {
    const text = editableText.trim();
    if (!text) return;
    onUtterance(text);
    setEditableText('');
    voice.reset();
  }, [editableText, onUtterance, voice.reset]);

  if (!voice.supported) {
    return (
      <div className="flex items-center gap-2 px-3 py-2 rounded bg-gray-800 text-gray-500 text-sm">
        <span className="opacity-50">{'\uD83C\uDFA4'}</span>
        <span>Voice input not supported — try Chrome or Edge</span>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      {/* Mic toggle */}
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={handleToggle}
          className={`w-8 h-8 flex items-center justify-center rounded-full transition-colors ${
            voice.listening
              ? 'bg-red-500/80 text-white animate-pulse'
              : 'bg-gray-800 text-gray-400 hover:text-gray-200 hover:bg-gray-700'
          }`}
          aria-label={voice.listening ? 'Stop voice input' : 'Start voice input'}
        >
          {voice.listening ? '\u23F9' : '\uD83C\uDFA4'}
        </button>
        <span className="text-xs text-gray-500">
          {voice.listening ? 'Listening...' : 'Tap to speak'}
        </span>
      </div>

      {/* Interim text (live partial) */}
      {voice.listening && voice.interim && (
        <p className="text-sm text-gray-400 italic px-1">{voice.interim}</p>
      )}

      {/* Editable transcript + submit */}
      {editableText && (
        <div className="flex items-center gap-1 bg-gray-800 rounded px-2 py-1">
          <input
            type="text"
            role="textbox"
            value={editableText}
            onChange={(e) => setEditableText(e.target.value)}
            className="flex-1 bg-transparent text-sm text-gray-100 placeholder-gray-500 focus:outline-none font-mono"
            aria-label="Edit transcript"
          />
          <button
            type="button"
            onClick={handleSubmit}
            className="text-xs px-2 py-0.5 rounded bg-blue-600/80 hover:bg-blue-500 text-white transition-colors"
            aria-label="Send utterance"
          >
            Send
          </button>
        </div>
      )}

      {/* Permission denied */}
      {voice.permissionDenied && (
        <p className="text-xs text-red-400 px-1">
          Microphone permission denied. Enable it in browser settings.
        </p>
      )}

      {/* Other errors */}
      {voice.error && !voice.permissionDenied && (
        <p className="text-xs text-red-400 px-1">Mic: {voice.error}</p>
      )}
    </div>
  );
}

```
