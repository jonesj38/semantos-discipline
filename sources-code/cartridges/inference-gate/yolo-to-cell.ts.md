---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/yolo-to-cell.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.409538+00:00
---

# cartridges/inference-gate/yolo-to-cell.ts

```ts
#!/usr/bin/env bun
/**
 * yolo-to-cell.ts — Camera frame → YOLOv11 detection → inference cell
 *
 * Closes the camera→cell loop for the construction site safety pitch:
 *
 *   Camera (USB/RTSP/file)
 *     │  ffmpeg → /tmp/frame.jpg
 *     ▼
 *   YOLOv11 REST server (ultralytics serve / Roboflow inference)
 *     │  detected objects + confidence + bounding boxes
 *     ▼
 *   Detection mapper  ←  construction safety rules
 *     │  "person detected, no hard hat visible in zone 3"
 *     ▼
 *   inference.request.classify cell  →  relay  →  cell-handler  →  result cell
 *     │
 *     ▼
 *   inference.result.response  →  dashboard / SafetyCulture webhook
 *
 * USAGE
 * ─────
 *   bun cartridges/inference-gate/yolo-to-cell.ts          # mock mode (no camera)
 *   CAMERA=/dev/video0 bun yolo-to-cell.ts                 # USB camera (Linux)
 *   CAMERA=rtsp://192.168.0.3:554/stream bun yolo-to-cell.ts  # IP camera
 *   CAMERA=avfoundation:0 bun yolo-to-cell.ts              # Mac webcam
 *   YOLO_URL=http://localhost:8000 bun yolo-to-cell.ts     # real YOLOv11 server
 *   ROBOFLOW_KEY=xxx MODEL_ID=ppe-hard-hat/3 bun yolo-to-cell.ts  # Roboflow hosted
 *   ZONE="zone-3" RELAY_URL=http://192.168.0.50:5199 bun yolo-to-cell.ts
 *   bun yolo-to-cell.ts --once                             # single frame then exit
 *
 * YOLO SERVER SETUP (local)
 * ─────────────────────────
 *   pip install ultralytics
 *   yolo serve                          # starts on http://localhost:8000
 *   # or for PPE-specific model:
 *   yolo serve model=keremberke/yolov8-hard-hat-detection  # via ultralytics hub
 *
 * ROBOFLOW HOSTED INFERENCE (no GPU needed)
 * ─────────────────────────────────────────
 *   pip install inference-sdk
 *   inference server start              # or use hosted API
 *   ROBOFLOW_KEY=<api_key> MODEL_ID=<workspace/model/version>
 *
 * ENVIRONMENT
 * ───────────
 *   CAMERA          /dev/video0 | rtsp://... | avfoundation:N | "" (mock)
 *   YOLO_URL        http://localhost:8000    Ultralytics serve endpoint
 *   ROBOFLOW_KEY    (empty)                 Roboflow API key — enables hosted inference
 *   MODEL_ID        yolov8n                 Roboflow model ID (if ROBOFLOW_KEY set)
 *   RELAY_URL       http://localhost:5199   Relay endpoint
 *   ZONE            zone-1                  Location tag for this camera
 *   INTERVAL_MS     2000                    Ms between frame captures
 *   CONF_THRESHOLD  0.45                    Min detection confidence
 *   RESULT_MS       8000                    Ms to wait for inference result
 *   WAIT_RESULT     true                    Wait for result cell before next frame
 */

import { createHash, randomBytes } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { unlink } from 'node:fs/promises';

// ── Config ────────────────────────────────────────────────────────────────────

const RELAY_URL      = process.env.RELAY_URL      ?? 'http://localhost:5199';
const CAMERA         = process.env.CAMERA         ?? '';         // empty = mock
const YOLO_URL       = process.env.YOLO_URL       ?? '';         // empty = mock
const ROBOFLOW_KEY   = process.env.ROBOFLOW_KEY   ?? '';
const MODEL_ID       = process.env.MODEL_ID       ?? 'yolov8n';
const ZONE           = process.env.ZONE           ?? 'zone-1';
const INTERVAL_MS    = parseInt(process.env.INTERVAL_MS    ?? '2000', 10);
const CONF_THRESHOLD = parseFloat(process.env.CONF_THRESHOLD ?? '0.45');
const RESULT_MS      = parseInt(process.env.RESULT_MS      ?? '8000',  10);
const WAIT_RESULT    = process.env.WAIT_RESULT !== 'false';
const ONCE           = process.argv.includes('--once');

const CLIENT_FP = createHash('sha256').update('yolo-to-cell').digest('hex').slice(0, 8);
const MOCK_MODE = !CAMERA && !YOLO_URL && !ROBOFLOW_KEY;

let seq = 0;

// ── Detection types ───────────────────────────────────────────────────────────

interface Detection {
  label:      string;    // class name from YOLO
  confidence: number;    // 0-1
  box?:       { x1: number; y1: number; x2: number; y2: number };
}

interface SafetyEvent {
  prompt:    string;            // natural language description for cell-handler
  category:  'safety' | 'motion' | 'anomaly' | 'command';
  severity:  'low' | 'medium' | 'high' | 'critical';
  detections: Detection[];
}

// ── COCO + PPE class mapper ───────────────────────────────────────────────────
// Maps raw YOLO class names → construction safety categories.
// Works with both COCO (generic) and specialised PPE models.

const SAFETY_CLASSES = new Set([
  // PPE violations (custom model)
  'no_hard_hat', 'no_hardhat', 'no-hardhat', 'no_helmet',
  'no_safety_vest', 'no_vest', 'no_hi_vis',
  // Hazard objects
  'fire', 'smoke', 'flame', 'fire_extinguisher',
  // Generic COCO that imply safety risk
  'knife', 'scissors',
]);

const MOTION_CLASSES = new Set([
  // Vehicles (COCO)
  'car', 'truck', 'bus', 'motorcycle', 'bicycle', 'forklift', 'vehicle',
  // People in restricted areas handled via combination
  'person',
]);

const PPE_PRESENT_CLASSES = new Set([
  'hard_hat', 'hardhat', 'helmet', 'safety_vest', 'vest', 'hi_vis',
]);

function mapDetectionsToEvent(detections: Detection[], zone: string): SafetyEvent | null {
  if (detections.length === 0) return null;

  const labels     = detections.map(d => d.label.toLowerCase());
  const hasPerson  = labels.some(l => l === 'person');
  const hasPPE     = labels.some(l => PPE_PRESENT_CLASSES.has(l));
  const hasNoPPE   = labels.some(l => SAFETY_CLASSES.has(l));
  const hasFire    = labels.some(l => ['fire', 'smoke', 'flame'].includes(l));
  const hasVehicle = labels.some(l => MOTION_CLASSES.has(l) && l !== 'person');
  const personCount = labels.filter(l => l === 'person').length;

  // Critical: fire / smoke
  if (hasFire) {
    return {
      prompt: `fire or smoke detected in ${zone} — immediate evacuation required`,
      category: 'safety',
      severity: 'critical',
      detections,
    };
  }

  // High: PPE violation detected explicitly
  if (hasNoPPE && hasPerson) {
    const violations = detections
      .filter(d => SAFETY_CLASSES.has(d.label.toLowerCase()))
      .map(d => d.label.replace(/_/g, ' '))
      .join(', ');
    return {
      prompt: `ppe violation in ${zone}: ${violations} — ${personCount} person${personCount > 1 ? 's' : ''} detected`,
      category: 'safety',
      severity: 'high',
      detections,
    };
  }

  // Medium: person with no PPE class detected at all (generic COCO model)
  if (hasPerson && !hasPPE && !YOLO_URL.includes('ppe') && !MODEL_ID.includes('ppe')) {
    // Generic model — can't confirm PPE, flag for review
    return {
      prompt: `${personCount} person${personCount > 1 ? 's' : ''} detected in ${zone} — ppe status unconfirmed`,
      category: 'safety',
      severity: 'low',
      detections,
    };
  }

  // Person confirmed with PPE — motion event (access tracking)
  if (hasPerson && hasPPE) {
    return {
      prompt: `${personCount} worker${personCount > 1 ? 's' : ''} with ppe detected entering ${zone}`,
      category: 'motion',
      severity: 'low',
      detections,
    };
  }

  // Vehicle / machinery
  if (hasVehicle) {
    const vehicles = [...new Set(
      detections.filter(d => MOTION_CLASSES.has(d.label.toLowerCase()) && d.label.toLowerCase() !== 'person')
        .map(d => d.label)
    )].join(', ');
    return {
      prompt: `vehicle detected in ${zone}: ${vehicles}`,
      category: 'motion',
      severity: 'medium',
      detections,
    };
  }

  return null;  // nothing actionable
}

// ── Mock detection generator ──────────────────────────────────────────────────
// Realistic synthetic detections when no camera or YOLO server is available.
// Rotates through scenarios that exercise every classification path.

const MOCK_SCENARIOS: Detection[][] = [
  // PPE violation (what SafetyCulture cares about most)
  [
    { label: 'person',       confidence: 0.94 },
    { label: 'no_hard_hat',  confidence: 0.88 },
    { label: 'safety_vest',  confidence: 0.71 },
  ],
  // Compliant worker
  [
    { label: 'person',      confidence: 0.97 },
    { label: 'hard_hat',    confidence: 0.93 },
    { label: 'safety_vest', confidence: 0.82 },
  ],
  // Vehicle in zone
  [
    { label: 'forklift', confidence: 0.85 },
    { label: 'person',   confidence: 0.79 },
  ],
  // Multiple workers, missing PPE
  [
    { label: 'person',      confidence: 0.91 },
    { label: 'person',      confidence: 0.88 },
    { label: 'person',      confidence: 0.76 },
    { label: 'no_hard_hat', confidence: 0.83 },
    { label: 'no_vest',     confidence: 0.69 },
  ],
  // Smoke / fire
  [
    { label: 'smoke', confidence: 0.72 },
  ],
  // Empty zone
  [],
  // Truck access
  [
    { label: 'truck',  confidence: 0.96 },
    { label: 'person', confidence: 0.88 },
    { label: 'hard_hat', confidence: 0.81 },
  ],
];

let mockScenarioIdx = 0;

function mockDetect(): Detection[] {
  const scenario = MOCK_SCENARIOS[mockScenarioIdx % MOCK_SCENARIOS.length]!;
  mockScenarioIdx++;
  // Add slight confidence jitter
  return scenario.map(d => ({
    ...d,
    confidence: Math.min(0.99, d.confidence + (Math.random() - 0.5) * 0.06),
  }));
}

// ── Frame capture via ffmpeg ──────────────────────────────────────────────────

async function captureFrame(framePath: string): Promise<boolean> {
  let args: string[];

  if (CAMERA.startsWith('rtsp://') || CAMERA.startsWith('rtsps://')) {
    args = ['-y', '-rtsp_transport', 'tcp', '-i', CAMERA,
            '-frames:v', '1', '-q:v', '2', framePath];
  } else if (CAMERA.startsWith('avfoundation')) {
    // macOS: avfoundation:0 or avfoundation:0:0
    const dev = CAMERA.replace('avfoundation:', '');
    args = ['-y', '-f', 'avfoundation', '-framerate', '30',
            '-i', dev, '-frames:v', '1', '-q:v', '2', framePath];
  } else {
    // Linux V4L2 USB camera: /dev/video0 or similar
    args = ['-y', '-f', 'v4l2', '-i', CAMERA,
            '-frames:v', '1', '-q:v', '2', framePath];
  }

  const proc = Bun.spawn(['ffmpeg', ...args], { stdout: 'ignore', stderr: 'pipe' });
  const exit  = await proc.exited;
  return exit === 0;
}

// ── YOLO REST detection ───────────────────────────────────────────────────────
// Supports: Ultralytics serve, Roboflow Inference, or any OpenAPI-compatible endpoint.

interface YoloBox {
  x1: number; y1: number; x2: number; y2: number;
  confidence: number; class_id: number; class: string;
}

async function runYolo(framePath: string): Promise<Detection[]> {
  const imageData  = await Bun.file(framePath).arrayBuffer();
  const formData   = new FormData();
  formData.append('file', new Blob([imageData], { type: 'image/jpeg' }), 'frame.jpg');

  let url: string;
  let headers: Record<string, string> = {};

  if (ROBOFLOW_KEY) {
    // Roboflow hosted inference: POST /MODEL_ID with api_key param
    url = `https://detect.roboflow.com/${MODEL_ID}?api_key=${ROBOFLOW_KEY}&confidence=${Math.round(CONF_THRESHOLD * 100)}`;
  } else {
    // Ultralytics serve: POST /predict?model=...
    url = `${YOLO_URL}/predict?model=${MODEL_ID}&conf=${CONF_THRESHOLD}&iou=0.45&imgsz=640`;
  }

  const r = await fetch(url, {
    method: 'POST',
    body:   formData,
    headers,
    signal: AbortSignal.timeout(10_000),
  });

  if (!r.ok) throw new Error(`YOLO HTTP ${r.status}: ${await r.text().catch(() => '')}`);

  const json = await r.json() as Record<string, unknown>;

  // Handle Roboflow format
  if ('predictions' in json) {
    const preds = json.predictions as Array<{
      class: string; confidence: number; x: number; y: number; width: number; height: number;
    }>;
    return preds
      .filter(p => p.confidence >= CONF_THRESHOLD)
      .map(p => ({
        label:      p.class,
        confidence: p.confidence,
        box: {
          x1: p.x - p.width / 2,  y1: p.y - p.height / 2,
          x2: p.x + p.width / 2,  y2: p.y + p.height / 2,
        },
      }));
  }

  // Handle Ultralytics serve format (v8/v11): { results: [{ boxes: [...] }] }
  const results = (json.results as Array<{ boxes?: YoloBox[] }> | undefined) ?? [];
  const boxes   = results[0]?.boxes ?? [];
  return boxes
    .filter(b => b.confidence >= CONF_THRESHOLD)
    .map(b => ({
      label:      b.class,
      confidence: b.confidence,
      box:        { x1: b.x1, y1: b.y1, x2: b.x2, y2: b.y2 },
    }));
}

// ── Publish inference.request.classify cell ───────────────────────────────────

async function publishInferenceCell(event: SafetyEvent): Promise<string> {
  const requestId  = randomBytes(8).toString('hex');
  const payload    = JSON.stringify({
    requestId,
    prompt:      event.prompt,
    model:       MOCK_MODE ? 'mock-detector' : (ROBOFLOW_KEY ? MODEL_ID : 'yolov11'),
    source:      MOCK_MODE ? 'mock' : 'camera',
    zone:        ZONE,
    category:    event.category,
    severity:    event.severity,
    detections:  event.detections.map(d => ({
      label: d.label, confidence: parseFloat(d.confidence.toFixed(3)),
    })),
    detectionCount: event.detections.length,
  });
  const payloadHex = Buffer.from(payload, 'utf8').toString('hex');
  const cellId     = createHash('sha256').update(payloadHex).digest('hex');
  seq++;

  const body = {
    header: {
      cellId,
      typePath:   'inference.request.classify',
      senderFp:   CLIENT_FP,
      seq,
      payloadLen: payload.length,
    },
    payload: payloadHex,
  };

  const r = await fetch(`${RELAY_URL}/publish`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(body),
    signal:  AbortSignal.timeout(4000),
  });

  if (!r.ok) throw new Error(`relay publish HTTP ${r.status}`);
  return requestId;
}

// ── Poll for inference result ─────────────────────────────────────────────────

interface RecentCell {
  header: { cellId: string; typePath: string; ts: number };
  payload: string | null;
}

async function waitForResult(requestId: string): Promise<void> {
  const deadline = Date.now() + RESULT_MS;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(`${RELAY_URL}/cells/recent`, { signal: AbortSignal.timeout(2000) });
      if (r.ok) {
        const { cells } = await r.json() as { cells: RecentCell[] };
        for (const cell of cells) {
          if (cell.header.typePath !== 'inference.result.response' || !cell.payload) continue;
          try {
            const res = JSON.parse(Buffer.from(cell.payload, 'hex').toString('utf8')) as {
              requestId?: string; result?: string; label?: string;
              confidence?: number; latencyMs?: number;
            };
            if (res.requestId !== requestId) continue;
            const conf    = ((res.confidence ?? 0) * 100).toFixed(0);
            const latency = res.latencyMs ? ` ${res.latencyMs}ms` : '';
            console.log(`  ↳ ${res.result ?? res.label}  ${conf}% confidence${latency}`);
            return;
          } catch { /* skip malformed */ }
        }
      }
    } catch { /* relay unreachable */ }
    await Bun.sleep(350);
  }
  console.log('  ↳ (no result — handler running?)');
}

// ── Log helpers ───────────────────────────────────────────────────────────────

const C = {
  reset:   '\x1b[0m',
  bold:    '\x1b[1m',
  dim:     '\x1b[2m',
  red:     '\x1b[31m',
  yellow:  '\x1b[33m',
  green:   '\x1b[32m',
  cyan:    '\x1b[36m',
  bg_red:  '\x1b[41m',
  white:   '\x1b[97m',
};

function severityColor(s: SafetyEvent['severity']): string {
  return s === 'critical' ? C.bg_red + C.white
       : s === 'high'     ? C.red
       : s === 'medium'   ? C.yellow
       : C.dim;
}

// ── Main loop ─────────────────────────────────────────────────────────────────

async function tick(): Promise<void> {
  const ts   = new Date().toLocaleTimeString();
  const frame = join(tmpdir(), `yolo-frame-${Date.now()}.jpg`);

  // 1. Detect
  let detections: Detection[];

  if (MOCK_MODE) {
    detections = mockDetect();
    process.stdout.write(`[${ts}] 📷 mock  `);
  } else {
    // Capture frame
    process.stdout.write(`[${ts}] 📷 capture  `);
    const captured = await captureFrame(frame);
    if (!captured) {
      console.log(`${C.red}ffmpeg failed — check CAMERA=${CAMERA}${C.reset}`);
      return;
    }
    // Run YOLO
    try {
      detections = await runYolo(frame);
      process.stdout.write(`YOLO(${detections.length})  `);
    } catch (e: any) {
      console.log(`${C.red}YOLO error: ${e.message}${C.reset}`);
      return;
    } finally {
      unlink(frame).catch(() => {});
    }
  }

  // 2. Map to safety event
  const event = mapDetectionsToEvent(detections, ZONE);

  if (!event) {
    console.log(`${C.dim}no actionable detections${C.reset}`);
    return;
  }

  // 3. Print event
  const col = severityColor(event.severity);
  console.log(`${col}${event.severity.toUpperCase()}${C.reset}  ${event.category}`);
  console.log(`  "${event.prompt}"`);

  const topDets = event.detections
    .sort((a, b) => b.confidence - a.confidence)
    .slice(0, 4)
    .map(d => `${d.label}(${(d.confidence * 100).toFixed(0)}%)`)
    .join('  ');
  if (topDets) console.log(`  ${C.dim}${topDets}${C.reset}`);

  // 4. Publish cell
  try {
    const requestId = await publishInferenceCell(event);
    console.log(`  📡 cell published  requestId=${requestId.slice(0, 12)}…`);
    if (WAIT_RESULT) await waitForResult(requestId);
  } catch (e: any) {
    console.log(`  ${C.yellow}relay error: ${e.message}${C.reset}`);
  }
}

async function main() {
  const modeStr = MOCK_MODE         ? 'mock (no camera)'
                : ROBOFLOW_KEY      ? `Roboflow  model=${MODEL_ID}`
                : YOLO_URL          ? `YOLOv11 @ ${YOLO_URL}`
                : 'camera only (no YOLO)';

  console.log(`\n${C.bold}${C.cyan}  YOLO → Cell${C.reset}  ${new Date().toLocaleString()}`);
  console.log(`  Mode:     ${modeStr}`);
  console.log(`  Camera:   ${CAMERA || '(none)'}`);
  console.log(`  Zone:     ${ZONE}`);
  console.log(`  Relay:    ${RELAY_URL}`);
  console.log(`  Interval: ${INTERVAL_MS}ms  conf≥${CONF_THRESHOLD}`);
  if (MOCK_MODE) {
    console.log(`\n  ${C.yellow}Mock mode — no camera or YOLO server configured.${C.reset}`);
    console.log(`  Set CAMERA=/dev/video0 and YOLO_URL=http://localhost:8000 for real detection.`);
    console.log(`  Or set ROBOFLOW_KEY + MODEL_ID for hosted PPE inference.`);
  }
  console.log('');

  if (ONCE) {
    await tick();
    return;
  }

  let frames = 0;
  let events = 0;
  const startTs = Date.now();

  process.on('SIGINT', () => {
    const elapsed = ((Date.now() - startTs) / 1000).toFixed(0);
    console.log(`\n  ${frames} frames  ${events} events  ${elapsed}s\n`);
    process.exit(0);
  });

  while (true) {
    const before = seq;
    await tick();
    if (seq > before) events++;
    frames++;
    await Bun.sleep(INTERVAL_MS);
  }
}

main().catch(e => { console.error(e); process.exit(1); });

```
