#!/usr/bin/env bash
set -euo pipefail
BASE="/home/jake/.edwinpai/disciplines/semantos"
RUN_ROOT="$(cat "$BASE/state/parallel-multirun-root.txt")"
PROMPTS="$BASE/05-Scripts/stage-prompts"
mkdir -p "$RUN_ROOT/logs" "$RUN_ROOT/prompts"

launch() {
  local id="$1" out="$2" prompt="$3" pidfile="$4"
  if [[ -f "$pidfile" ]] && ps -p "$(cat "$pidfile")" >/dev/null 2>&1; then
    echo "$id already running pid=$(cat "$pidfile")"
    return
  fi
  if [[ -s "$out" ]] && ! grep -qx "No result" "$out"; then
    echo "$id already has output $out"
    return
  fi
  nohup "$BASE/05-Scripts/run-stage-auto-resume.sh" "$id" "$out" "$prompt" "$RUN_ROOT" > "$RUN_ROOT/logs/${id}.launch.log" 2>&1 &
  echo $! > "$pidfile"
  echo "launched $id pid=$(cat "$pidfile")"
}

# Concurrency target: 3 active stage processes including architecture resume.
active_count() {
  local n=0 p
  for f in "$BASE"/state/architecture-resume-deep.pid "$BASE"/state/stage-*.pid; do
    [[ -f "$f" ]] || continue
    p=$(cat "$f" 2>/dev/null || true)
    [[ -n "$p" ]] && ps -p "$p" >/dev/null 2>&1 && n=$((n+1))
  done
  echo "$n"
}

while [[ $(active_count) -lt 3 ]]; do
  launched=0
  if [[ ! -f "$BASE/state/stage-protocols-security.pid" ]] || ! ps -p "$(cat "$BASE/state/stage-protocols-security.pid" 2>/dev/null || echo 0)" >/dev/null 2>&1; then
    launch protocols-security "$BASE/03-Analysis/protocols-security.md" "$PROMPTS/protocols-security.md" "$BASE/state/stage-protocols-security.pid"; launched=1
  elif [[ ! -f "$BASE/state/stage-formal-methods.pid" ]] || ! ps -p "$(cat "$BASE/state/stage-formal-methods.pid" 2>/dev/null || echo 0)" >/dev/null 2>&1; then
    launch formal-methods "$BASE/03-Analysis/formal-methods.md" "$PROMPTS/formal-methods.md" "$BASE/state/stage-formal-methods.pid"; launched=1
  elif [[ ! -f "$BASE/state/stage-developer-workflows.pid" ]] || ! ps -p "$(cat "$BASE/state/stage-developer-workflows.pid" 2>/dev/null || echo 0)" >/dev/null 2>&1; then
    launch developer-workflows "$BASE/03-Analysis/developer-workflows.md" "$PROMPTS/developer-workflows.md" "$BASE/state/stage-developer-workflows.pid"; launched=1
  elif [[ ! -f "$BASE/state/stage-pitfalls.pid" ]] || ! ps -p "$(cat "$BASE/state/stage-pitfalls.pid" 2>/dev/null || echo 0)" >/dev/null 2>&1; then
    launch pitfalls "$BASE/03-Analysis/pitfalls-checklists.md" "$PROMPTS/pitfalls.md" "$BASE/state/stage-pitfalls.pid"; launched=1
  elif [[ ! -f "$BASE/state/stage-routing-hints.pid" ]] || ! ps -p "$(cat "$BASE/state/stage-routing-hints.pid" 2>/dev/null || echo 0)" >/dev/null 2>&1; then
    launch routing-hints "$BASE/03-Analysis/routing-hints.md" "$PROMPTS/routing-hints.md" "$BASE/state/stage-routing-hints.pid"; launched=1
  else
    break
  fi
  [[ $launched -eq 1 ]] || break
  sleep 1
done

echo "active stages: $(active_count)"
