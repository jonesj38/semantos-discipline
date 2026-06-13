---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/components/LiveApp.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.052240+00:00
---

# apps/oddjobtodd/src/components/LiveApp.tsx

```tsx
/**
 * LiveApp — real brain-connected operator interface for oddjobz.
 *
 * Architecture:
 *   - Bearer token in localStorage ('oddjobz_bearer')
 *   - Jobs list via POST /api/v1/repl { cmd: 'find jobs' }
 *   - Job detail + conversation turns via GET /api/v1/conversation/turns?entityRef=<cellId>
 *   - Approve outbound turn via POST /api/v1/conversation/turn/:id/approve
 *   - Quote job via POST /api/v1/repl { cmd: 'quote job <id>' }
 *
 * No React Router — three-view stack handled in local state.
 */

import { useState, useEffect, useCallback } from 'react';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Job {
  id: string;
  customer_name: string;
  state: string;
  scheduled_at?: string;
  created_at?: string;
  cellId?: string;              // hex-64; present for v2+ rows
  propertyAddress?: string;
  description?: string;
  services?: string;
  workOrderNumber?: string;
}

interface ConversationTurn {
  turnId: string;
  conversationId: string;
  participantRole: 'external' | 'operator' | 'ai' | 'subcontractor';
  direction: 'inbound' | 'outbound';
  surface: 'email' | 'gmail' | 'sms' | 'meta-inbox' | 'widget';
  bodyText: string;
  timestamp: number;
  correlationId: string;
  actorCertId?: string;
  identityHandle?: { kind: string; value: string };
  entityRef?: { kind: string; cellHash: string };
  outboundState?: 'drafted' | 'proposed' | 'approved' | 'sent' | 'delivered' | 'failed' | 'rejected';
  recipientHandle?: { kind: string; value: string };
  quotedTurnId?: string;
}

type View =
  | { kind: 'login' }
  | { kind: 'jobs' }
  | { kind: 'job'; job: Job };

// ── Constants ─────────────────────────────────────────────────────────────────

const BEARER_KEY = 'oddjobz_bearer';

const STATE_LABEL: Record<string, string> = {
  lead: 'lead', qualified: 'qualified', quoted: 'quoted',
  scheduled: 'sched', in_progress: 'on-site',
  visited: 'visited', completed: 'done',
  invoiced: 'invoiced', paid: 'paid', closed: 'closed',
};

const STATE_CLASS: Record<string, string> = {
  paid: 'done', closed: 'done', completed: 'done',
};

const SURFACE_ICON: Record<string, string> = {
  email: '✉', gmail: '✉', sms: '💬',
  'meta-inbox': '📩', widget: '🌐',
};

// ── Hooks ─────────────────────────────────────────────────────────────────────

function useBearer() {
  const [bearer, setBearer] = useState<string | null>(() => localStorage.getItem(BEARER_KEY));
  const save = useCallback((t: string) => {
    localStorage.setItem(BEARER_KEY, t.trim());
    setBearer(t.trim());
  }, []);
  const clear = useCallback(() => {
    localStorage.removeItem(BEARER_KEY);
    setBearer(null);
  }, []);
  return { bearer, save, clear };
}

async function replCmd(bearer: string, cmd: string): Promise<string> {
  const r = await fetch('/api/v1/repl', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${bearer}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ cmd }),
  });
  if (!r.ok) throw new Error(`REPL ${r.status}`);
  const data = await r.json();
  return (data.result as string) ?? '';
}

function useJobs(bearer: string | null) {
  const [jobs, setJobs] = useState<Job[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    if (!bearer) return;
    setLoading(true);
    setError(null);
    try {
      const raw = await replCmd(bearer, 'find jobs');
      const parsed = JSON.parse(raw.trim());
      setJobs(Array.isArray(parsed) ? parsed : []);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [bearer]);

  useEffect(() => { reload(); }, [reload]);
  return { jobs, loading, error, reload };
}

function useConversationTurns(bearer: string | null, cellId: string | undefined) {
  const [turns, setTurns] = useState<ConversationTurn[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    if (!bearer || !cellId) return;
    setLoading(true);
    setError(null);
    try {
      const url = `/api/v1/conversation/turns?entityRef=${encodeURIComponent(cellId)}&limit=100`;
      const r = await fetch(url, {
        headers: { Authorization: `Bearer ${bearer}` },
      });
      if (!r.ok) throw new Error(`turns ${r.status}`);
      const data = await r.json();
      setTurns(Array.isArray(data.turns) ? data.turns : []);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [bearer, cellId]);

  useEffect(() => { reload(); }, [reload]);
  return { turns, loading, error, reload };
}

// ── Sub-components ─────────────────────────────────────────────────────────────

function LoginView({ onSave }: { onSave: (t: string) => void }) {
  const [val, setVal] = useState('');
  return (
    <div className="la-login">
      <div className="la-login-card">
        <div className="la-logo">oddjobz</div>
        <div className="la-login-hint">Enter your operator bearer token</div>
        <input
          className="la-input"
          type="password"
          placeholder="64-char hex token"
          value={val}
          onChange={e => setVal(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && val.trim() && onSave(val)}
          autoFocus
        />
        <button
          className="la-btn-primary"
          disabled={val.trim().length < 8}
          onClick={() => onSave(val)}
        >
          Connect
        </button>
      </div>
    </div>
  );
}

function JobsView({
  jobs, loading, error,
  onSelect, onReload, onLogout,
}: {
  jobs: Job[];
  loading: boolean;
  error: string | null;
  onSelect: (j: Job) => void;
  onReload: () => void;
  onLogout: () => void;
}) {
  return (
    <div className="la-app">
      <div className="la-header">
        <span className="la-header-title">oddjobz</span>
        <div className="la-header-actions">
          <button className="la-btn-ghost" onClick={onReload} title="Refresh jobs">↻</button>
          <button className="la-btn-ghost" onClick={onLogout} title="Log out">⏻</button>
        </div>
      </div>

      <div className="la-body">
        {loading && <div className="la-status">loading…</div>}
        {error && <div className="la-error">{error}</div>}
        {!loading && jobs.length === 0 && !error && (
          <div className="la-status la-empty">No jobs found.</div>
        )}
        <div className="la-jobs-list">
          {jobs.map(j => (
            <div
              key={j.id}
              className="la-job-row"
              onClick={() => onSelect(j)}
            >
              <div className="la-job-row-main">
                <span className="la-job-name">{j.customer_name || j.id}</span>
                {j.propertyAddress && (
                  <span className="la-job-addr">{j.propertyAddress}</span>
                )}
                {j.services && (
                  <span className="la-job-services">{j.services}</span>
                )}
              </div>
              <span className={`la-stage ${STATE_CLASS[j.state] ?? ''}`}>
                {STATE_LABEL[j.state] ?? j.state}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function TurnBubble({
  turn, onApprove, approving,
}: {
  turn: ConversationTurn;
  onApprove?: () => void;
  approving?: boolean;
}) {
  const isInbound = turn.direction === 'inbound';
  const isProposed = turn.outboundState === 'proposed';
  const icon = SURFACE_ICON[turn.surface] ?? '·';
  const ts = new Date(turn.timestamp).toLocaleString('en-AU', {
    month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });

  return (
    <div className={`la-turn ${isInbound ? 'la-turn-in' : 'la-turn-out'} ${isProposed ? 'la-turn-proposed' : ''}`}>
      <div className="la-turn-meta">
        <span className="la-turn-surface">{icon} {turn.surface}</span>
        <span className="la-turn-ts">{ts}</span>
        {turn.outboundState && turn.direction === 'outbound' && (
          <span className={`la-turn-state la-turn-state-${turn.outboundState}`}>
            {turn.outboundState}
          </span>
        )}
        {turn.identityHandle && (
          <span className="la-turn-identity">{turn.identityHandle.value}</span>
        )}
      </div>
      <div className="la-turn-body">{turn.bodyText}</div>
      {isProposed && onApprove && (
        <button
          className="la-btn-approve"
          onClick={onApprove}
          disabled={approving}
        >
          {approving ? 'sending…' : '✓ Approve & send'}
        </button>
      )}
    </div>
  );
}

function JobDetailView({
  job, bearer,
  onBack,
}: {
  job: Job;
  bearer: string;
  onBack: () => void;
}) {
  const { turns, loading, error, reload } = useConversationTurns(bearer, job.cellId);
  const [approving, setApproving] = useState<string | null>(null);
  const [quoting, setQuoting] = useState(false);
  const [quoteResult, setQuoteResult] = useState<string | null>(null);

  const approveTurn = useCallback(async (turnId: string) => {
    setApproving(turnId);
    try {
      const r = await fetch(`/api/v1/conversation/turn/${encodeURIComponent(turnId)}/approve`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${bearer}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ approved: true }),
      });
      if (!r.ok) throw new Error(`approve ${r.status}`);
      await reload();
    } catch (e) {
      alert(`Approve failed: ${e instanceof Error ? e.message : e}`);
    } finally {
      setApproving(null);
    }
  }, [bearer, reload]);

  const quoteJob = useCallback(async () => {
    setQuoting(true);
    setQuoteResult(null);
    try {
      const raw = await replCmd(bearer, `quote job ${job.id}`);
      setQuoteResult(raw.trim());
    } catch (e) {
      setQuoteResult(`Error: ${e instanceof Error ? e.message : e}`);
    } finally {
      setQuoting(false);
    }
  }, [bearer, job.id]);

  const proposedCount = turns.filter(t => t.outboundState === 'proposed').length;

  return (
    <div className="la-app">
      <div className="la-header">
        <button className="la-back" onClick={onBack}>← jobs</button>
        <span className="la-header-title">{job.customer_name || job.id}</span>
        <span className={`la-stage la-stage-header ${STATE_CLASS[job.state] ?? ''}`}>
          {STATE_LABEL[job.state] ?? job.state}
        </span>
      </div>

      <div className="la-body">
        {/* Job metadata strip */}
        <div className="la-job-meta">
          {job.workOrderNumber && <span className="la-meta-chip">WO {job.workOrderNumber}</span>}
          {job.propertyAddress && <span className="la-meta-chip">📍 {job.propertyAddress}</span>}
          {job.services && <span className="la-meta-chip">🔧 {job.services}</span>}
          {job.scheduled_at && job.scheduled_at.length > 0 && (
            <span className="la-meta-chip">🗓 {job.scheduled_at}</span>
          )}
          {job.cellId && (
            <span className="la-meta-chip la-meta-dim" title={job.cellId}>
              cell {job.cellId.slice(0, 8)}…
            </span>
          )}
        </div>

        {/* Quick actions */}
        <div className="la-actions">
          {['lead', 'qualified'].includes(job.state) && (
            <button className="la-btn-action" onClick={quoteJob} disabled={quoting}>
              {quoting ? 'quoting…' : '📋 Quote job'}
            </button>
          )}
          {proposedCount > 0 && (
            <div className="la-pending-badge">{proposedCount} pending approval</div>
          )}
        </div>

        {quoteResult && (
          <div className="la-quote-result">
            <pre>{quoteResult}</pre>
          </div>
        )}

        {/* Conversation thread */}
        <div className="la-thread-header">
          <span>Conversation</span>
          <button className="la-btn-ghost la-btn-sm" onClick={reload}>↻</button>
        </div>

        {loading && <div className="la-status">loading turns…</div>}
        {error && <div className="la-error">{error}</div>}

        {!job.cellId && (
          <div className="la-status la-warn">
            This job has no cellId — entity anchoring not yet migrated.
            Run <code>find job {job.id}</code> to check.
          </div>
        )}

        {!loading && job.cellId && turns.length === 0 && !error && (
          <div className="la-status la-empty">No conversation turns for this job yet.</div>
        )}

        <div className="la-thread">
          {turns.map(turn => (
            <TurnBubble
              key={turn.turnId}
              turn={turn}
              approving={approving === turn.turnId}
              onApprove={
                turn.outboundState === 'proposed'
                  ? () => approveTurn(turn.turnId)
                  : undefined
              }
            />
          ))}
        </div>
      </div>
    </div>
  );
}

// ── Root ──────────────────────────────────────────────────────────────────────

export default function LiveApp() {
  const { bearer, save, clear } = useBearer();
  const [view, setView] = useState<View>({ kind: bearer ? 'jobs' : 'login' });
  const { jobs, loading, error, reload } = useJobs(bearer);

  // If bearer was just set, flip to jobs view.
  const handleSave = (t: string) => {
    save(t);
    setView({ kind: 'jobs' });
  };

  if (view.kind === 'login' || !bearer) {
    return <LoginView onSave={handleSave} />;
  }

  if (view.kind === 'job') {
    return (
      <JobDetailView
        job={view.job}
        bearer={bearer}
        onBack={() => setView({ kind: 'jobs' })}
      />
    );
  }

  // jobs list
  return (
    <JobsView
      jobs={jobs}
      loading={loading}
      error={error}
      onSelect={j => setView({ kind: 'job', job: j })}
      onReload={reload}
      onLogout={clear}
    />
  );
}

```
