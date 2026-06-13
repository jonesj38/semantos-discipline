---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/identity/PolicyCreator.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.947254+00:00
---

# archive/apps-loom-react/src/identity/PolicyCreator.tsx

```tsx
import { useState } from 'react';
import { useIdentity } from './IdentityProvider';
import { useExtension } from '../config/ExtensionProvider';

interface PolicyCreatorProps {
  channelId?: string;
  onClose: () => void;
}

let policyCounter = 0;

export function PolicyCreator({ channelId, onClose }: PolicyCreatorProps) {
  const { addPolicy } = useIdentity();
  const { config } = useExtension();
  const [name, setName] = useState('');
  const [scopeKey, setScopeKey] = useState('');
  const [scopeValue, setScopeValue] = useState('');
  const [scopeEntries, setScopeEntries] = useState<[string, string][]>([]);
  const [conditionField, setConditionField] = useState('');
  const [conditionOp, setConditionOp] = useState('gte');
  const [conditionValue, setConditionValue] = useState('');
  const [conditions, setConditions] = useState<[string, string, string][]>([]);
  const [selectedActions, setSelectedActions] = useState<string[]>([]);

  const scripts = config?.scripts ?? [];

  const addScopeEntry = () => {
    if (!scopeKey.trim() || !scopeValue.trim()) return;
    setScopeEntries(prev => [...prev, [scopeKey.trim(), scopeValue.trim()]]);
    setScopeKey('');
    setScopeValue('');
  };

  const addCondition = () => {
    if (!conditionField.trim() || !conditionValue.trim()) return;
    setConditions(prev => [...prev, [conditionField.trim(), conditionOp, conditionValue.trim()]]);
    setConditionField('');
    setConditionValue('');
  };

  const toggleAction = (scriptId: string) => {
    setSelectedActions(prev =>
      prev.includes(scriptId)
        ? prev.filter(a => a !== scriptId)
        : [...prev, scriptId]
    );
  };

  const handleCreate = () => {
    if (!name.trim()) return;

    const scope: Record<string, unknown> = {};
    for (const [k, v] of scopeEntries) scope[k] = v;

    const conds: Record<string, unknown> = {};
    for (const [field, op, val] of conditions) {
      conds[field] = { [op]: isNaN(Number(val)) ? val : Number(val) };
    }

    addPolicy({
      id: `policy-${Date.now()}-${++policyCounter}`,
      name: name.trim(),
      scope,
      conditions: conds,
      actions: selectedActions,
      createdViaChannel: channelId,
      enabled: true,
    });

    onClose();
  };

  return (
    <div className="bg-gray-800 border border-gray-700 rounded-lg p-3 space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium text-gray-300">Create Policy</span>
        <button onClick={onClose} className="text-xs text-gray-500 hover:text-gray-300">
          Cancel
        </button>
      </div>

      <div>
        <label className="text-[10px] text-gray-500 block mb-0.5">Policy Name</label>
        <input
          type="text"
          value={name}
          onChange={e => setName(e.target.value)}
          placeholder="Auto-ROM for Core Suburb Jobs"
          className="w-full bg-gray-900 border border-gray-700 rounded px-2 py-1 text-xs text-gray-100 focus:outline-none focus:border-blue-500"
          autoFocus
        />
      </div>

      {/* Scope */}
      <div>
        <label className="text-[10px] text-gray-500 block mb-0.5">Scope (match criteria)</label>
        {scopeEntries.map(([k, v], i) => (
          <div key={i} className="text-[10px] text-gray-400 bg-gray-900 rounded px-2 py-0.5 mb-0.5">
            {k}: {v}
          </div>
        ))}
        <div className="flex gap-1">
          <input
            type="text"
            value={scopeKey}
            onChange={e => setScopeKey(e.target.value)}
            placeholder="key"
            className="flex-1 bg-gray-900 border border-gray-700 rounded px-1.5 py-0.5 text-[10px] text-gray-100"
          />
          <input
            type="text"
            value={scopeValue}
            onChange={e => setScopeValue(e.target.value)}
            placeholder="value"
            className="flex-1 bg-gray-900 border border-gray-700 rounded px-1.5 py-0.5 text-[10px] text-gray-100"
          />
          <button onClick={addScopeEntry} className="text-[10px] text-blue-400 px-1">+</button>
        </div>
      </div>

      {/* Conditions */}
      <div>
        <label className="text-[10px] text-gray-500 block mb-0.5">Conditions</label>
        {conditions.map(([field, op, val], i) => (
          <div key={i} className="text-[10px] text-gray-400 bg-gray-900 rounded px-2 py-0.5 mb-0.5">
            {field} {op} {val}
          </div>
        ))}
        <div className="flex gap-1">
          <input
            type="text"
            value={conditionField}
            onChange={e => setConditionField(e.target.value)}
            placeholder="field"
            className="flex-1 bg-gray-900 border border-gray-700 rounded px-1.5 py-0.5 text-[10px] text-gray-100"
          />
          <select
            value={conditionOp}
            onChange={e => setConditionOp(e.target.value)}
            className="bg-gray-900 border border-gray-700 rounded px-1 py-0.5 text-[10px] text-gray-300"
          >
            <option value="gte">&gt;=</option>
            <option value="lte">&lt;=</option>
            <option value="eq">=</option>
            <option value="gt">&gt;</option>
            <option value="lt">&lt;</option>
          </select>
          <input
            type="text"
            value={conditionValue}
            onChange={e => setConditionValue(e.target.value)}
            placeholder="value"
            className="w-16 bg-gray-900 border border-gray-700 rounded px-1.5 py-0.5 text-[10px] text-gray-100"
          />
          <button onClick={addCondition} className="text-[10px] text-blue-400 px-1">+</button>
        </div>
      </div>

      {/* Actions */}
      {scripts.length > 0 && (
        <div>
          <label className="text-[10px] text-gray-500 block mb-0.5">Actions</label>
          <div className="flex flex-wrap gap-1">
            {scripts.map(script => (
              <button
                key={script.id}
                onClick={() => toggleAction(script.id)}
                className={`text-[10px] px-1.5 py-0.5 rounded ${
                  selectedActions.includes(script.id)
                    ? 'bg-blue-700 text-blue-100'
                    : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
                }`}
              >
                {script.name}
              </button>
            ))}
          </div>
        </div>
      )}

      <button
        onClick={handleCreate}
        disabled={!name.trim()}
        className="w-full bg-green-700 hover:bg-green-600 disabled:bg-gray-700 disabled:text-gray-500 text-white text-xs rounded px-2 py-1.5 transition-colors"
      >
        Create Policy
      </button>
    </div>
  );
}

```
