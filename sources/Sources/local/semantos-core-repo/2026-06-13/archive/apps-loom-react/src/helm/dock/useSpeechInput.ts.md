---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/helm/dock/useSpeechInput.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.975369+00:00
---

# archive/apps-loom-react/src/helm/dock/useSpeechInput.ts

```ts
/**
 * useSpeechInput — minimal Web Speech API hook for the dock mic.
 *
 * Chromium browsers expose `webkitSpeechRecognition` / `SpeechRecognition`.
 * Transcription happens client-side (Chrome uses Google's cloud; other
 * browsers may not support it at all). Returns null where unsupported.
 *
 * Kept deliberately small — this is a v1 wire-up, not a transcription service.
 */

import { useEffect, useRef, useState, useCallback } from 'react';

// Browser SpeechRecognition types vary; use a structural minimum.
interface SpeechRecognitionLike extends EventTarget {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  start(): void;
  stop(): void;
  onresult: ((event: SpeechRecognitionEventLike) => void) | null;
  onend: (() => void) | null;
  onerror: ((event: { error?: string }) => void) | null;
}

interface SpeechRecognitionEventLike {
  results: ArrayLike<ArrayLike<{ transcript: string; confidence: number }>>;
  resultIndex: number;
}

type SpeechRecognitionCtor = new () => SpeechRecognitionLike;

function getRecognitionCtor(): SpeechRecognitionCtor | null {
  if (typeof window === 'undefined') return null;
  const w = window as unknown as {
    SpeechRecognition?: SpeechRecognitionCtor;
    webkitSpeechRecognition?: SpeechRecognitionCtor;
  };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}

export interface SpeechInputState {
  supported: boolean;
  listening: boolean;
  transcript: string;
  error: string | null;
  start: () => void;
  stop: () => void;
  reset: () => void;
}

export function useSpeechInput(): SpeechInputState {
  const [listening, setListening] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [error, setError] = useState<string | null>(null);
  const recRef = useRef<SpeechRecognitionLike | null>(null);

  const Ctor = getRecognitionCtor();
  const supported = !!Ctor;

  useEffect(() => {
    if (!Ctor) return;
    const rec = new Ctor();
    rec.continuous = false;
    rec.interimResults = true;
    rec.lang = 'en-US';
    rec.onresult = (event) => {
      let text = '';
      for (let i = event.resultIndex; i < event.results.length; i++) {
        text += event.results[i][0].transcript;
      }
      setTranscript(text);
    };
    rec.onend = () => setListening(false);
    rec.onerror = (event) => {
      setError(event.error ?? 'unknown');
      setListening(false);
    };
    recRef.current = rec;
    return () => {
      try { rec.stop(); } catch { /* noop */ }
      recRef.current = null;
    };
  }, [Ctor]);

  const start = useCallback(() => {
    const rec = recRef.current;
    if (!rec) return;
    setError(null);
    setTranscript('');
    try {
      rec.start();
      setListening(true);
    } catch (e) {
      setError((e as Error).message);
    }
  }, []);

  const stop = useCallback(() => {
    const rec = recRef.current;
    if (rec) {
      try { rec.stop(); } catch { /* noop */ }
    }
  }, []);

  const reset = useCallback(() => {
    setTranscript('');
    setError(null);
  }, []);

  return { supported, listening, transcript, error, start, stop, reset };
}

```
