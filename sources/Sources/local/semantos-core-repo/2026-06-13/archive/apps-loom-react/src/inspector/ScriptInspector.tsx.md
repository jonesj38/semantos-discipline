---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/inspector/ScriptInspector.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.944451+00:00
---

# archive/apps-loom-react/src/inspector/ScriptInspector.tsx

```tsx
import { useState } from 'react';
import { HexView } from './HexView';

/** Standard Bitcoin Script opcodes for syntax highlighting. */
const OPCODE_NAMES: Record<number, string> = {
  0x00: 'OP_0', 0x4c: 'OP_PUSHDATA1', 0x4d: 'OP_PUSHDATA2', 0x4e: 'OP_PUSHDATA4',
  0x4f: 'OP_1NEGATE', 0x51: 'OP_1', 0x52: 'OP_2', 0x53: 'OP_3',
  0x54: 'OP_4', 0x55: 'OP_5', 0x56: 'OP_6', 0x57: 'OP_7',
  0x58: 'OP_8', 0x59: 'OP_9', 0x5a: 'OP_10', 0x5b: 'OP_11',
  0x5c: 'OP_12', 0x5d: 'OP_13', 0x5e: 'OP_14', 0x5f: 'OP_15', 0x60: 'OP_16',
  0x61: 'OP_NOP', 0x63: 'OP_IF', 0x64: 'OP_NOTIF', 0x67: 'OP_ELSE', 0x68: 'OP_ENDIF',
  0x69: 'OP_VERIFY', 0x6a: 'OP_RETURN',
  0x6b: 'OP_TOALTSTACK', 0x6c: 'OP_FROMALTSTACK',
  0x73: 'OP_IFDUP', 0x74: 'OP_DEPTH', 0x75: 'OP_DROP', 0x76: 'OP_DUP',
  0x77: 'OP_NIP', 0x78: 'OP_OVER', 0x79: 'OP_PICK', 0x7a: 'OP_ROLL',
  0x7b: 'OP_ROT', 0x7c: 'OP_SWAP', 0x7d: 'OP_TUCK',
  0x82: 'OP_SIZE', 0x87: 'OP_EQUAL', 0x88: 'OP_EQUALVERIFY',
  0x93: 'OP_ADD', 0x94: 'OP_SUB', 0x9a: 'OP_BOOLAND', 0x9b: 'OP_BOOLOR',
  0x9c: 'OP_NUMEQUAL', 0x9d: 'OP_NUMEQUALVERIFY',
  0xa6: 'OP_RIPEMD160', 0xa7: 'OP_SHA1', 0xa8: 'OP_SHA256',
  0xa9: 'OP_HASH160', 0xaa: 'OP_HASH256',
  0xab: 'OP_CODESEPARATOR', 0xac: 'OP_CHECKSIG', 0xad: 'OP_CHECKSIGVERIFY',
  0xae: 'OP_CHECKMULTISIG', 0xaf: 'OP_CHECKMULTISIGVERIFY',
};

interface Instruction {
  offset: number;
  opcode: number;
  name: string;
  data?: Uint8Array;
  range: 'standard' | 'craig-macro' | 'plexus' | 'push';
}

function disassemble(scriptHex: string): Instruction[] {
  const bytes = new Uint8Array(scriptHex.match(/.{1,2}/g)?.map(b => parseInt(b, 16)) ?? []);
  const instructions: Instruction[] = [];
  let i = 0;
  while (i < bytes.length) {
    const offset = i;
    const op = bytes[i++];
    if (op >= 1 && op <= 75) {
      const data = bytes.slice(i, i + op);
      i += op;
      instructions.push({ offset, opcode: op, name: `PUSH_${op}`, data, range: 'push' });
    } else if (op >= 0xB0 && op <= 0xBF) {
      instructions.push({ offset, opcode: op, name: `CRAIG_MACRO_${(op - 0xB0).toString(16)}`, range: 'craig-macro' });
    } else if (op >= 0xC0 && op <= 0xCF) {
      instructions.push({ offset, opcode: op, name: `PLEXUS_${(op - 0xC0).toString(16)}`, range: 'plexus' });
    } else {
      instructions.push({ offset, opcode: op, name: OPCODE_NAMES[op] ?? `0x${op.toString(16)}`, range: 'standard' });
    }
  }
  return instructions;
}

const RANGE_COLORS: Record<string, string> = {
  standard: 'text-blue-300',
  'craig-macro': 'text-purple-300',
  plexus: 'text-cyan-300',
  push: 'text-green-300',
};

interface ScriptInspectorProps {
  scriptHex: string;
}

export function ScriptInspector({ scriptHex }: ScriptInspectorProps) {
  const [view, setView] = useState<'source' | 'hex'>('source');
  const instructions = disassemble(scriptHex);
  const bytes = new Uint8Array(scriptHex.match(/.{1,2}/g)?.map(b => parseInt(b, 16)) ?? []);

  return (
    <div className="text-xs">
      <div className="flex items-center gap-2 mb-2">
        <div className="text-[10px] text-gray-500 uppercase tracking-wider">Script</div>
        <div className="flex gap-1 ml-auto">
          <button
            className={`px-2 py-0.5 rounded text-[10px] ${view === 'source' ? 'bg-gray-700 text-white' : 'text-gray-500 hover:text-gray-300'}`}
            onClick={() => setView('source')}
          >
            Source
          </button>
          <button
            className={`px-2 py-0.5 rounded text-[10px] ${view === 'hex' ? 'bg-gray-700 text-white' : 'text-gray-500 hover:text-gray-300'}`}
            onClick={() => setView('hex')}
          >
            Hex
          </button>
        </div>
      </div>

      {view === 'source' ? (
        <div className="font-mono space-y-px">
          {instructions.map((inst, i) => (
            <div key={i} className="flex items-start gap-2">
              <span className="text-gray-600 w-8 flex-shrink-0 text-right">
                {inst.offset.toString(16).padStart(4, '0')}
              </span>
              <span className={RANGE_COLORS[inst.range] ?? 'text-gray-400'}>
                {inst.name}
              </span>
              {inst.data && (
                <span className="text-gray-500 truncate">
                  {Array.from(inst.data).map(b => b.toString(16).padStart(2, '0')).join('')}
                </span>
              )}
            </div>
          ))}
          <div className="text-gray-600 mt-1">
            {instructions.length} opcodes | {bytes.length} bytes
          </div>
        </div>
      ) : (
        <HexView data={bytes} />
      )}
    </div>
  );
}

```
