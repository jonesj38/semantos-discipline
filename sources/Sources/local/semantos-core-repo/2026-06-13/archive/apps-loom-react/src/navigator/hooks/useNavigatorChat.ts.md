---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/hooks/useNavigatorChat.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.971422+00:00
---

# archive/apps-loom-react/src/navigator/hooks/useNavigatorChat.ts

```ts
import { useState, useCallback, useRef } from 'react';
import { useKernel } from '../../contexts/KernelProvider';
import { OBJECT_TYPES } from '../data/objectTypes';
import { PROCESS_CYCLES } from '../data/processCycles';
import { DIMENSIONS_ENUM } from '../../hooks/useDimensions';

export interface ChatMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
  actions?: Array<{ type: string; objectType?: string; fields?: Record<string, unknown> }>;
}

export function useNavigatorChat() {
  const { kernel } = useKernel();
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      role: 'system',
      content: 'Talk to me about your day, what you\'re working through, or what you\'d like to release. I\'ll listen and help you grow.',
    },
  ]);
  const [isLoading, setIsLoading] = useState(false);
  const historyRef = useRef<Array<{ role: string; content: string }>>([]);
  const dimensionScoresRef = useRef<Record<string, number>>({
    mental: 5, physical: 4, spiritual: 6, social: 5, vocational: 7, financial: 4, familial: 6,
  });

  const executeAction = useCallback(
    (action: { type: string; objectType?: string; fields?: Record<string, unknown> }) => {
      if (action.type === 'create' && action.objectType && kernel) {
        kernel.createObject(action.objectType, action.fields || {});
      }
      if (action.fields?.dimensionScores) {
        Object.assign(dimensionScoresRef.current, action.fields.dimensionScores);
      }
    },
    [kernel],
  );

  const buildSystemPrompt = useCallback(() => {
    const objects = kernel ? kernel.listObjects() : [];
    const objectSummary = objects.length > 0
      ? objects.slice(-10).map(o => `  ${o.id.slice(0, 8)}: ${o.type} — ${JSON.stringify(o.fields).slice(0, 200)}`).join('\n')
      : '  (none yet)';

    const dimSummary = DIMENSIONS_ENUM.map(d =>
      `${d.emoji} ${d.label}: ${dimensionScoresRef.current[d.id] || 5}/10`,
    ).join(', ');

    return `You are the Navigation shell — a warm, genuine conversational partner for consciousness development.

The user talks naturally. You:
1. Have a real conversation. Be brief, warm, honest. Not therapist-speak. Not technical.
2. Extract structured fields from what they say and create semantic objects (the user never sees these labels).
3. Reference their dimension scores and patterns when relevant.

OBJECT TYPES (internal — never show these labels to the user):
${OBJECT_TYPES}

DIMENSIONS: ${dimSummary}

PROCESS CYCLES:
${PROCESS_CYCLES.map(c => `${c.label} (${c.inquiry}): ${c.steps.map(s => s.label).join(' → ')}`).join('\n')}

CURRENT OBJECTS:
${objectSummary}

RESPONSE FORMAT — always valid JSON:
{
  "reply": "Your conversational response — warm, human, no jargon",
  "extracted": { "field": "value" },
  "actions": [
    { "type": "create", "objectType": "Release", "fields": { "rawText": "...", "themes": ["..."] } }
  ]
}

RULES:
- When the user is venting/releasing, create a Release. Extract themes and emotional valence.
- When wisdom emerges, create an Insight.
- When the user sets a goal, create an Intention.
- When patterns repeat, create or update a Pattern.
- NEVER mention LINEAR, RELEVANT, AFFINE, kernel, or consumption semantics to the user.
- NEVER show shell commands or LISP policies in your reply.
- Be honest. If they're avoiding something, gently note it.`;
  }, [kernel]);

  const localProcess = useCallback(
    (message: string): { reply: string; actions: ChatMessage['actions'] } => {
      const lower = message.toLowerCase();

      if (lower.includes('release') || lower.includes('let go') || lower.includes('i feel') || lower.includes('frustrated') || lower.includes('anxious') || lower.includes('stressed')) {
        const fields = { rawText: message, source: 'keyboard', prompt: 'freeform', valence: 0 };
        executeAction({ type: 'create', objectType: 'Release', fields });
        return {
          reply: 'I hear you. That\'s been released — it\'s out of you now. What themes were in there for you?',
          actions: [{ type: 'create', objectType: 'Release', fields }],
        };
      }

      if (lower.includes('intention') || lower.includes('tomorrow') || lower.includes('i will') || lower.includes('i want to')) {
        return {
          reply: 'That sounds like a clear intention. Which area of your life does it touch most? Mental, physical, spiritual, social, vocational, financial, or family?',
          actions: [],
        };
      }

      if (lower.includes('insight') || lower.includes('realised') || lower.includes('realized') || lower.includes('i see that') || lower.includes('it hit me')) {
        const fields = { content: message, source: 'writing' };
        executeAction({ type: 'create', objectType: 'Insight', fields });
        return {
          reply: 'That\'s a real insight. I\'ll keep that one — it might connect with patterns down the track.',
          actions: [{ type: 'create', objectType: 'Insight', fields }],
        };
      }

      if (lower.startsWith('key:')) {
        const key = message.slice(4).trim();
        localStorage.setItem('openrouter_key', key);
        return { reply: 'API key saved. I can have deeper conversations with you now.', actions: [] };
      }

      return { reply: 'I\'m here. Tell me more — what\'s present for you right now?', actions: [] };
    },
    [executeAction],
  );

  const send = useCallback(
    async (text: string) => {
      if (!text.trim()) return;

      setMessages(prev => [...prev, { role: 'user', content: text }]);
      historyRef.current.push({ role: 'user', content: text });
      setIsLoading(true);

      try {
        const apiKey = localStorage.getItem('openrouter_key');
        if (!apiKey) {
          const result = localProcess(text);
          historyRef.current.push({ role: 'assistant', content: result.reply });
          setMessages(prev => [...prev, { role: 'assistant', content: result.reply, actions: result.actions }]);
          setIsLoading(false);
          return;
        }

        const systemPrompt = buildSystemPrompt();
        const apiMessages = [
          { role: 'system', content: systemPrompt },
          ...historyRef.current.slice(-20),
        ];

        const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://semantos.dev',
            'X-Title': 'Navigation Shell',
          },
          body: JSON.stringify({
            model: 'anthropic/claude-sonnet-4',
            messages: apiMessages,
            temperature: 0.3,
            response_format: { type: 'json_object' },
          }),
        });

        if (!response.ok) throw new Error(`LLM ${response.status}`);
        const data = await response.json();
        let content = data.choices?.[0]?.message?.content;
        if (!content) throw new Error('No response');

        content = content.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '').trim();
        const parsed = JSON.parse(content);
        historyRef.current.push({ role: 'assistant', content: parsed.reply || content });

        if (parsed.actions) {
          for (const action of parsed.actions) executeAction(action);
        }

        setMessages(prev => [
          ...prev,
          { role: 'assistant', content: parsed.reply || '', actions: parsed.actions },
        ]);
      } catch (err: any) {
        setMessages(prev => [
          ...prev,
          { role: 'system', content: `Something went wrong: ${err.message}` },
        ]);
      } finally {
        setIsLoading(false);
      }
    },
    [buildSystemPrompt, localProcess, executeAction],
  );

  return { messages, isLoading, send };
}

```
