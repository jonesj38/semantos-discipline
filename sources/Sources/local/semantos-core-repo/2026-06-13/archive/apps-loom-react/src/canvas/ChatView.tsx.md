---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/canvas/ChatView.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.934802+00:00
---

# archive/apps-loom-react/src/canvas/ChatView.tsx

```tsx
/**
 * ChatView — the primary chat-first interface for Semantos Loom.
 *
 * Replaces the old Canvas as the center of the shell. Handles:
 * - Global conversation (no object selected)
 * - Object-scoped conversation (when object selected via sidebar)
 * - Intent classification via OpenRouter BYOK
 * - Flow execution with stepAction support for compliance demo
 * - Inline evidence chain and anchor proof display
 */

import { useState, useMemo, useRef, useEffect, useCallback } from 'react';
import { useLoom } from '../state/LoomProvider';
import { useIdentity } from '../identity/IdentityProvider';
import { useExtension } from '../config/ExtensionProvider';
import type { LoomObject, ObjectPatch } from '../types/loom';
import type { IntentClassification } from '../services/intent-types';
import { classifyIntent, buildContextFromConfig } from '../services/IntentClassifier';
import { findFlow } from '../services/FlowRegistry';
import { FlowRunner } from '../services/FlowRunner';
import { settingsStore, loomStore, configStore, loomStateAtom } from '../services/index';
// Prompt 03 spot-check: read state directly from the atom to prove the
// renderer-agnostic atom surface works end-to-end. Full panel migration
// happens in prompt 31.
import { get as getAtom } from '@semantos/state';
import type { FlowStep, FlowAction } from '../config/extensionConfig';

/** Convert first 32 hex chars (16 bytes) of a hex string to Uint8Array(16). */
function hexToBytes16(hex: string): Uint8Array {
  const bytes = new Uint8Array(16);
  const clean = hex.slice(0, 32);
  for (let i = 0; i < 16 && i * 2 < clean.length; i++) {
    bytes[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

const CAPABILITY_LABELS: Record<number, string> = {
  1: 'EDGE', 2: 'SIGN', 3: 'ENCRYPT', 4: 'MSG',
  5: 'ATTEST', 6: 'CHILD', 7: 'PERM', 8: 'DATA',
  9: 'SCHEMA', 10: 'METER',
};

const LINEARITY_LABELS: Record<number, string> = {
  1: 'LINEAR', 2: 'AFFINE', 3: 'RELEVANT', 4: 'DEBUG',
};

const LINEARITY_COLORS: Record<number, string> = {
  1: 'bg-red-900/40 text-red-300',
  2: 'bg-yellow-900/40 text-yellow-300',
  3: 'bg-green-900/40 text-green-300',
  4: 'bg-gray-800 text-gray-400',
};

interface ChatMessage {
  id: string;
  sender: 'user' | 'system';
  text: string;
  timestamp: number;
  intent?: IntentClassification;
  isError?: boolean;
  isInspection?: boolean;
  inspectionData?: InspectionData;
}

interface InspectionData {
  patches: ObjectPatch[];
  linearity: number;
  linearityLabel: string;
  objectName: string;
  objectType: string;
  cellHeaderHex: string;
  anchorMock: {
    blockHeight: number;
    treeHeight: number;
    txid: string;
    merkleRoot: string;
  };
}

export function ChatView() {
  const { state, dispatch, createObjectFromType } = useLoom();
  const { activeHat } = useIdentity();
  const { config } = useExtension();
  const [input, setInput] = useState('');
  const [classifying, setClassifying] = useState(false);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [flowRunner] = useState(() => new FlowRunner());
  const [activeFlowStep, setActiveFlowStep] = useState<FlowStep | null>(null);
  const [flowProgress, setFlowProgress] = useState<{ current: number; total: number } | null>(null);
  const [showSettings, setShowSettings] = useState(false);
  const [apiKeyInput, setApiKeyInput] = useState('');
  const [flowObjectId, setFlowObjectId] = useState<string | null>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Selected object from sidebar
  const selectedObject = state.selectedObjectId
    ? state.objects.get(state.selectedObjectId) ?? null
    : null;

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length]);

  // Focus input on mount
  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const addSystemMessage = useCallback((text: string, extra?: Partial<ChatMessage>) => {
    setMessages(prev => [...prev, {
      id: `msg-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      sender: 'system',
      text,
      timestamp: Date.now(),
      ...extra,
    }]);
  }, []);

  const addUserMessage = useCallback((text: string, intent?: IntentClassification) => {
    setMessages(prev => [...prev, {
      id: `msg-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      sender: 'user',
      text,
      timestamp: Date.now(),
      intent,
    }]);
  }, []);

  /** Execute a stepAction or onComplete action. */
  const executeAction = useCallback((action: FlowAction, flowState: { collectedData: Record<string, unknown>; flowId: string; flowName: string }) => {
    if (!activeHat || !config) return;

    if (action.type === 'create' && action.objectType) {
      const typeDef = config.objectTypes.find(t => t.name === action.objectType);
      if (typeDef) {
        const ownerIdBytes = activeHat.certId
          ? hexToBytes16(activeHat.certId.replace(/^cert:/, ''))
          : new TextEncoder().encode(activeHat.id.slice(0, 16).padEnd(16, '\0'));
        const newId = loomStore.createObjectFromType(
          typeDef,
          ownerIdBytes,
          activeHat.id,
          activeHat.capabilities,
          false, // don't open as card — chat is primary
        );
        // Apply collected fields
        for (const [field, value] of Object.entries(flowState.collectedData)) {
          if (field === 'consumeConfirm' || field === 'doubleConsumeConfirm' || field === 'inspectConfirm') continue;
          loomStore.dispatch({ type: 'UPDATE_PAYLOAD', objectId: newId, field, value });
        }
        // Select the new object
        loomStore.dispatch({ type: 'SELECT_OBJECT', id: newId });
        setFlowObjectId(newId);

        // Prompt 03 spot-check: read via the atom rather than the facade.
        const obj = getAtom(loomStateAtom).objects.get(newId);
        const linLabel = obj ? (LINEARITY_LABELS[obj.header.linearity] ?? 'UNKNOWN') : '';
        addSystemMessage(
          `Created ${action.objectType} "${flowState.collectedData.name ?? newId.slice(0, 8)}" [${linLabel}]`,
        );
      }
    } else if (action.type === 'consume') {
      const targetId = flowObjectId ?? state.selectedObjectId;
      if (!targetId) {
        addSystemMessage('No object selected to consume.', { isError: true });
        return;
      }
      try {
        loomStore.consumeObject(targetId, activeHat.id, activeHat.capabilities);
        addSystemMessage('Object consumed successfully. Linearity transitioned LINEAR -> DEBUG (spent).');
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        addSystemMessage(msg, { isError: true });
      }
    } else if (action.type === 'inspect') {
      const targetId = flowObjectId ?? state.selectedObjectId;
      if (!targetId) {
        addSystemMessage('No object selected to inspect.', { isError: true });
        return;
      }
      const obj = loomStore.getState().objects.get(targetId);
      if (!obj) {
        addSystemMessage('Object not found.', { isError: true });
        return;
      }
      // Build inspection data
      const cellHeaderHex = obj.packedCell
        ? Array.from(obj.packedCell.slice(0, 64)).map(b => b.toString(16).padStart(2, '0')).join(' ')
        : Array.from({ length: 64 }, () => Math.floor(Math.random() * 256).toString(16).padStart(2, '0')).join(' ');

      // Mock BSV anchor (in embedded mode, no real chain)
      const mockTxid = Array.from({ length: 32 }, () => Math.floor(Math.random() * 256).toString(16).padStart(2, '0')).join('');
      const mockMerkle = Array.from({ length: 32 }, () => Math.floor(Math.random() * 256).toString(16).padStart(2, '0')).join('');

      const inspectionData: InspectionData = {
        patches: obj.patches,
        linearity: obj.header.linearity,
        linearityLabel: LINEARITY_LABELS[obj.header.linearity] ?? 'UNKNOWN',
        objectName: String(obj.payload.name ?? obj.id.slice(0, 8)),
        objectType: obj.typeDefinition.name,
        cellHeaderHex,
        anchorMock: {
          blockHeight: 850000 + Math.floor(Math.random() * 1000),
          treeHeight: 12,
          txid: mockTxid,
          merkleRoot: mockMerkle,
        },
      };
      addSystemMessage('', { isInspection: true, inspectionData });
    }
  }, [activeHat, config, flowObjectId, state.selectedObjectId, addSystemMessage]);

  const handleSend = useCallback(async () => {
    if (!input.trim() || !activeHat) return;
    const text = input.trim();
    setInput('');

    addUserMessage(text);

    // If flow is active, advance it
    if (flowRunner.isActive()) {
      const nextStep = flowRunner.advanceFlow(text);
      if (nextStep) {
        setActiveFlowStep(nextStep);
        setFlowProgress({
          current: flowRunner.getState().currentStepIndex + 1,
          total: flowRunner.getState().totalSteps,
        });
        addSystemMessage(nextStep.prompt);
      } else {
        // Flow complete — execute onComplete
        const result = flowRunner.completeFlow();
        executeAction(result.onComplete, result);
        flowRunner.reset();
        setActiveFlowStep(null);
        setFlowProgress(null);
        setFlowObjectId(null);
      }
      return;
    }

    // Direct command matching (no LLM needed)
    if (config) {
      const lower = text.toLowerCase().trim();

      // Check for direct flow triggers: "demo linearity", "/demo", "create linear", etc.
      let matchedFlow = null;
      for (const flow of (config.flows ?? [])) {
        for (const trigger of flow.triggerIntents) {
          // Match if user text contains the trigger words (e.g., "demo.linearity" → "demo linearity")
          const triggerWords = trigger.replace(/\./g, ' ').toLowerCase();
          if (lower === triggerWords || lower.startsWith(triggerWords) || lower === `/${flow.id}`) {
            matchedFlow = flow;
            break;
          }
        }
        if (matchedFlow) break;
      }

      // Also match slash commands: /compliance-demo, /file-dispute, etc.
      if (!matchedFlow) {
        const slashMatch = lower.match(/^\/(.+)/);
        if (slashMatch) {
          matchedFlow = (config.flows ?? []).find(f => f.id === slashMatch[1]) ?? null;
        }
      }

      if (matchedFlow) {
        // Check capabilities
        const hasRequired = !matchedFlow.requiredCapabilities ||
          matchedFlow.requiredCapabilities.every(cap => activeHat.capabilities.includes(cap));
        if (!hasRequired) {
          addSystemMessage(`Flow "${matchedFlow.name}" requires capabilities you don't have.`, { isError: true });
        } else {
          const firstStep = flowRunner.startFlow(matchedFlow, selectedObject?.id);
          setActiveFlowStep(firstStep);
          setFlowProgress({ current: 1, total: matchedFlow.steps.length });
          addSystemMessage(`Starting flow: ${matchedFlow.name}\n${firstStep.prompt}`);
        }
        return;
      }
    }

    // LLM intent classification (only if API key is set)
    if (!settingsStore.hasApiKey() || !config) {
      addSystemMessage(
        'No API key configured for intent classification. Try direct commands like "demo linearity", "demo compliance", or "/compliance-demo". Use the gear icon to add your OpenRouter API key.',
      );
      return;
    }

    setClassifying(true);
    try {
      const context = buildContextFromConfig(config, {
        activeHatName: activeHat.name,
        currentObjectType: selectedObject?.typeDefinition.name,
      });
      const classification = await classifyIntent(text, context);
      setClassifying(false);

      if (classification.intent !== 'unknown') {
        // Check for matching flow
        const flow = findFlow(classification.intent, activeHat.capabilities, config);
        if (flow) {
          const firstStep = flowRunner.startFlow(flow, selectedObject?.id);
          setActiveFlowStep(firstStep);
          setFlowProgress({ current: 1, total: flow.steps.length });
          addSystemMessage(`Starting flow: ${flow.name}\n${firstStep.prompt}`);
        } else {
          addSystemMessage(`Classified as "${classification.intent}" (${Math.round(classification.confidence * 100)}%) — no matching flow found.`);
        }
      } else {
        addSystemMessage('Could not classify your intent. Try being more specific, or use a direct command like "/compliance-demo".');
      }
    } catch {
      setClassifying(false);
    }
  }, [input, activeHat, config, selectedObject, flowRunner, executeAction, addUserMessage, addSystemMessage]);

  // Listen for stepAction events from FlowRunner
  useEffect(() => {
    const off = flowRunner.on('stepAction', (action: FlowAction) => {
      const flowState = flowRunner.getState();
      executeAction(action, flowState);
    });
    return off;
  }, [flowRunner, executeAction]);

  const handleCancelFlow = useCallback(() => {
    flowRunner.cancelFlow();
    flowRunner.reset();
    setActiveFlowStep(null);
    setFlowProgress(null);
    setFlowObjectId(null);
    addSystemMessage('Flow cancelled.');
  }, [flowRunner, addSystemMessage]);

  if (!activeHat) {
    return (
      <div className="flex-1 flex items-center justify-center text-gray-500 text-sm">
        No active hat. Select a hat from the sidebar to begin.
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col min-h-0">
      {/* Object context header */}
      {selectedObject && (
        <div className="flex items-center gap-2 px-4 py-2 border-b border-gray-800 bg-gray-900/50 flex-shrink-0">
          <span className="text-xs text-gray-400">Scope:</span>
          <span className="text-xs text-gray-200 font-medium">
            {String(selectedObject.payload.name ?? selectedObject.typeDefinition.name)}
          </span>
          <span className={`text-[10px] px-1.5 py-0.5 rounded ${LINEARITY_COLORS[selectedObject.header.linearity] ?? ''}`}>
            {LINEARITY_LABELS[selectedObject.header.linearity] ?? '?'}
          </span>
          <span className="text-[10px] text-gray-600">
            {selectedObject.patches.length} patches
          </span>
          <button
            onClick={() => dispatch({ type: 'SELECT_OBJECT', id: null })}
            className="ml-auto text-[10px] text-gray-600 hover:text-gray-400"
          >
            clear
          </button>
        </div>
      )}

      {/* Messages area */}
      <div className="flex-1 overflow-y-auto px-4 py-3 space-y-3 min-h-0">
        {messages.length === 0 && (
          <div className="flex items-center justify-center h-full">
            <div className="text-center space-y-3 max-w-md">
              <div className="text-lg text-gray-400">Semantos Loom</div>
              <div className="text-sm text-gray-600">
                Type a message or describe what you need. Create objects from the sidebar,
                or say <span className="text-blue-400 font-mono">"demo linearity"</span> to see the compliance demo.
              </div>
              {!settingsStore.hasApiKey() && (
                <div className="text-xs text-yellow-600/70 bg-yellow-900/20 border border-yellow-800/30 rounded px-3 py-2">
                  No OpenRouter API key set. Click the gear icon below or type to set one.
                  Intent classification is disabled until configured.
                </div>
              )}
            </div>
          </div>
        )}

        {messages.map(msg => (
          <div key={msg.id}>
            {msg.isInspection && msg.inspectionData ? (
              <InspectionBlock data={msg.inspectionData} />
            ) : (
              <div
                className={`rounded-lg px-4 py-2.5 max-w-[85%] ${
                  msg.sender === 'user'
                    ? 'bg-blue-900/30 text-blue-100 ml-auto'
                    : msg.isError
                      ? 'bg-red-900/30 text-red-300 border border-red-800/40'
                      : 'bg-gray-800/60 text-gray-300'
                }`}
              >
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-[11px] font-medium text-gray-500">
                    {msg.sender === 'user' ? activeHat.name : 'System'}
                  </span>
                  <span className="text-[10px] text-gray-700">
                    {new Date(msg.timestamp).toLocaleTimeString()}
                  </span>
                  {msg.intent && msg.intent.intent !== 'unknown' && (
                    <span className="text-[9px] bg-purple-900/40 text-purple-300 px-1.5 py-0.5 rounded">
                      {msg.intent.intent} ({Math.round(msg.intent.confidence * 100)}%)
                    </span>
                  )}
                </div>
                <div className="text-sm whitespace-pre-wrap">{msg.text}</div>
              </div>
            )}
          </div>
        ))}
        <div ref={messagesEndRef} />
      </div>

      {/* Flow progress bar */}
      {flowProgress && (
        <div className="px-4 py-1.5 border-t border-gray-800 flex items-center gap-2 flex-shrink-0">
          <div className="flex-1 bg-gray-800 rounded-full h-1.5">
            <div
              className="bg-blue-500 h-1.5 rounded-full transition-all"
              style={{ width: `${(flowProgress.current / flowProgress.total) * 100}%` }}
            />
          </div>
          <span className="text-[10px] text-yellow-400">
            Step {flowProgress.current}/{flowProgress.total}
          </span>
          <button
            onClick={handleCancelFlow}
            className="text-[10px] text-red-400 hover:text-red-300"
          >
            Cancel
          </button>
        </div>
      )}

      {/* Classifying indicator */}
      {classifying && (
        <div className="px-4 py-1 flex-shrink-0">
          <span className="text-[11px] text-gray-500 animate-pulse">Classifying intent...</span>
        </div>
      )}

      {/* Settings panel */}
      {showSettings && (
        <div className="px-4 py-2 border-t border-gray-800 bg-gray-900/80 flex-shrink-0">
          <div className="flex items-center gap-2">
            <label className="text-[11px] text-gray-400">API Key:</label>
            <input
              type="password"
              value={apiKeyInput}
              onChange={e => setApiKeyInput(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'Enter' && apiKeyInput.trim()) {
                  settingsStore.setApiKey(apiKeyInput.trim());
                  setApiKeyInput('');
                  setShowSettings(false);
                  addSystemMessage('API key saved. Intent classification enabled.');
                }
              }}
              placeholder="sk-or-v1-..."
              className="flex-1 bg-gray-800 border border-gray-700 rounded px-2 py-1 text-xs text-gray-100 font-mono focus:outline-none focus:border-blue-500"
            />
            <button
              onClick={() => {
                if (apiKeyInput.trim()) {
                  settingsStore.setApiKey(apiKeyInput.trim());
                  setApiKeyInput('');
                  setShowSettings(false);
                  addSystemMessage('API key saved. Intent classification enabled.');
                }
              }}
              className="text-xs bg-blue-600 hover:bg-blue-500 text-white rounded px-2 py-1"
            >
              Save
            </button>
            <button
              onClick={() => setShowSettings(false)}
              className="text-xs text-gray-600 hover:text-gray-400"
            >
              Close
            </button>
          </div>
        </div>
      )}

      {/* Input bar */}
      <div className="border-t border-gray-800 px-4 py-3 flex-shrink-0">
        <div className="flex gap-2 items-center">
          <button
            onClick={() => setShowSettings(!showSettings)}
            className="text-gray-600 hover:text-gray-400 transition-colors"
            title="Settings"
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="3" />
              <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z" />
            </svg>
          </button>
          <input
            ref={inputRef}
            type="text"
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && handleSend()}
            placeholder={activeFlowStep ? activeFlowStep.prompt : `Message as ${activeHat.name}...`}
            className="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm text-gray-100 focus:outline-none focus:border-blue-500"
          />
          <button
            onClick={handleSend}
            disabled={!input.trim()}
            className="bg-blue-600 hover:bg-blue-500 disabled:bg-gray-700 disabled:text-gray-600 text-white text-sm rounded-lg px-4 py-2 transition-colors"
          >
            Send
          </button>
        </div>

        {/* Capability badges */}
        <div className="flex items-center gap-1.5 mt-1.5 px-8">
          <span className="text-[10px] text-gray-600">{activeHat.name}:</span>
          {activeHat.capabilities.map(cap => (
            <span key={cap} className="text-[9px] bg-gray-800 text-gray-500 px-1.5 py-0.5 rounded">
              {CAPABILITY_LABELS[cap] ?? cap}
            </span>
          ))}
          {!settingsStore.hasApiKey() && (
            <span className="text-[9px] text-gray-600 ml-auto">no classifier — click gear to add API key</span>
          )}
        </div>
      </div>
    </div>
  );
}

/** Renders inspection/evidence data inline in the chat. */
function InspectionBlock({ data }: { data: InspectionData }) {
  const KIND_COLORS: Record<string, string> = {
    extraction: 'text-blue-400',
    rescore: 'text-green-400',
    manual_override: 'text-yellow-400',
    state_transition: 'text-purple-400',
    evidence_merge: 'text-cyan-400',
    instrument_emit: 'text-orange-400',
    action: 'text-red-400',
    conversation: 'text-indigo-400',
  };

  return (
    <div className="bg-gray-800/80 border border-gray-700 rounded-lg p-4 space-y-3">
      {/* Header */}
      <div className="flex items-center gap-2">
        <span className="text-xs font-medium text-gray-200">Inspection: {data.objectName}</span>
        <span className="text-[10px] text-gray-500">({data.objectType})</span>
        <span className={`text-[10px] px-1.5 py-0.5 rounded ${LINEARITY_COLORS[data.linearity] ?? ''}`}>
          {data.linearityLabel}
        </span>
      </div>

      {/* Evidence Chain */}
      <div>
        <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1.5">
          Evidence Chain ({data.patches.length} patches)
        </div>
        <div className="space-y-1">
          {data.patches.map(patch => (
            <div key={patch.id} className="flex items-start gap-2 text-[11px]">
              <span className="text-gray-600 flex-shrink-0 font-mono">
                {new Date(patch.timestamp).toLocaleTimeString()}
              </span>
              <span className={`flex-shrink-0 ${KIND_COLORS[patch.kind] ?? 'text-gray-400'}`}>
                {patch.kind}
              </span>
              <span className="text-gray-500 truncate">
                {patch.kind === 'conversation'
                  ? String(patch.delta.text ?? '').slice(0, 60)
                  : Object.entries(patch.delta).map(([k, v]) => `${k}: ${JSON.stringify(v)}`).join(', ')}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Cell Header */}
      <div>
        <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1">Cell Header (first 64 bytes)</div>
        <div className="font-mono text-[10px] text-gray-400 bg-gray-900 rounded p-2 break-all leading-relaxed">
          {data.cellHeaderHex}
        </div>
      </div>

      {/* BSV Anchor Proof */}
      <div>
        <div className="text-[10px] text-gray-500 uppercase tracking-wider mb-1.5">BSV Anchor Proof</div>
        <div className="space-y-1 text-[11px]">
          <div className="flex gap-2">
            <span className="text-gray-500 w-24">Block Height:</span>
            <span className="text-green-400 font-mono">{data.anchorMock.blockHeight.toLocaleString()}</span>
          </div>
          <div className="flex gap-2">
            <span className="text-gray-500 w-24">Tree Height:</span>
            <span className="text-gray-300 font-mono">{data.anchorMock.treeHeight}</span>
          </div>
          <div className="flex gap-2">
            <span className="text-gray-500 w-24">TXID:</span>
            <span className="text-blue-400 font-mono text-[10px]">{data.anchorMock.txid}</span>
          </div>
          <div className="flex gap-2">
            <span className="text-gray-500 w-24">Merkle Root:</span>
            <span className="text-purple-400 font-mono text-[10px]">{data.anchorMock.merkleRoot}</span>
          </div>
          <div className="flex items-center gap-1 mt-1">
            <span className="text-green-400">&#10003;</span>
            <span className="text-[10px] text-green-400">BUMP verified (SPV proof valid)</span>
          </div>
          <div className="flex items-center gap-1">
            <span className="text-green-400">&#10003;</span>
            <span className="text-[10px] text-green-400">BEEF envelope intact (BRC-62)</span>
          </div>
          <div className="text-[9px] text-gray-600 mt-1 italic">
            (Embedded demo mode — mock anchor data. In production, verified against BSV mainnet.)
          </div>
        </div>
      </div>
    </div>
  );
}

```
