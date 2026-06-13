---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/prototypes/multipane_viewer_testing/inspector.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.758320+00:00
---

# archive/prototypes/multipane_viewer_testing/inspector.py

```py
#!/usr/bin/env python3
"""Semantos Inspector TUI — interactive object browser with scroll and logging.

A standalone REPL that wraps semantos shell commands and formats output
for comfortable browsing. Runs directly in ttyd without tmux.

Usage:
    python3 inspector.py --deploy-dir /tmp/semantos-test-XXXX
    SEMANTOS_FACET=test python3 inspector.py --deploy-dir /path

Commands:
    inspect <id>      Show object detail (header, payload, patches)
    capabilities      Show active facet capabilities
    whoami            Show active identity
    list [--type=X]   List objects (delegates to shell)
    trace <id>        Show object history
    help              Show this help
    clear             Clear screen
    quit              Exit
"""

import argparse
import json
import os
import readline
import shutil
import subprocess
import sys
import textwrap
import time
from datetime import datetime, timezone
from pathlib import Path

# ── ANSI colors ──────────────────────────────────────────────

C_RESET = "\033[0m"
C_BOLD = "\033[1m"
C_DIM = "\033[2m"
C_PURPLE = "\033[35m"
C_GREEN = "\033[32m"
C_BLUE = "\033[34m"
C_YELLOW = "\033[33m"
C_RED = "\033[31m"
C_CYAN = "\033[36m"

LOG_DIR = Path("/tmp/semantos-inspector-logs")
HISTORY_FILE = Path("/tmp/.semantos_inspector_history")


SHELL_SESSION = "sem-shell"


class Inspector:
    def __init__(self, deploy_dir: str):
        self.deploy_dir = deploy_dir
        self.bun = os.path.expanduser("~/.bun/bin/bun")
        self.shell_entry = os.path.join(deploy_dir, "packages/shell/src/index.ts")
        self.term_width = shutil.get_terminal_size().columns
        self.log_file = self._init_log()

        # readline history
        if HISTORY_FILE.exists():
            readline.read_history_file(str(HISTORY_FILE))
        readline.set_history_length(500)

    def _init_log(self) -> Path:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        log = LOG_DIR / f"inspector-{ts}.log"
        self._log_raw(f"=== Inspector started {ts} ===")
        self._log_raw(f"Deploy: {self.deploy_dir}")
        self._log_raw(f"Facet: {os.environ.get('SEMANTOS_FACET', '(none)')}")
        return log

    def _log_raw(self, msg: str):
        ts = datetime.now(timezone.utc).strftime("%H:%M:%S")
        line = f"[{ts}] {msg}\n"
        if hasattr(self, "log_file"):
            with open(self.log_file, "a") as f:
                f.write(line)

    def _log(self, cmd: str, output: str, elapsed: float):
        self._log_raw(f"CMD: {cmd} ({elapsed:.1f}s)")
        for line in output.splitlines()[:50]:
            self._log_raw(f"  {line}")
        if len(output.splitlines()) > 50:
            self._log_raw(f"  ... ({len(output.splitlines())} lines total)")

    def _run_shell(self, *args: str) -> tuple[str, float]:
        """Send a command to the running shell REPL via tmux and capture output."""
        shell_cmd = " ".join(args)
        t0 = time.time()
        try:
            output = self._tmux_exec(shell_cmd)
            return output, time.time() - t0
        except Exception as e:
            return f"ERROR: {e}", time.time() - t0

    def _tmux_exec(self, shell_cmd: str) -> str:
        """Send a command to the shell REPL via tmux and capture the output."""
        sess = SHELL_SESSION

        # Send the command
        subprocess.run(
            ["tmux", "send-keys", "-t", sess, shell_cmd, "Enter"],
            check=False,
        )

        # Wait for the prompt to return (command finished)
        for _ in range(50):  # 5 seconds max
            time.sleep(0.1)
            capture = subprocess.run(
                ["tmux", "capture-pane", "-t", sess, "-p", "-S", "-80"],
                capture_output=True, text=True,
            ).stdout
            lines = capture.strip().splitlines()
            if len(lines) >= 2 and lines[-1].strip().endswith("> "):
                # Find our command in the output
                cmd_idx = None
                for i, line in enumerate(lines):
                    if shell_cmd[:30] in line:
                        cmd_idx = i
                        break
                if cmd_idx is not None:
                    output_lines = lines[cmd_idx + 1:-1]
                    return "\n".join(output_lines).strip()

        return "(timeout waiting for shell response)"

    # ── Display helpers ──────────────────────────────────────

    def _header(self, text: str):
        w = self.term_width
        print(f"\n{C_PURPLE}{C_BOLD}{'─' * w}{C_RESET}")
        print(f"{C_PURPLE}{C_BOLD}  {text}{C_RESET}")
        print(f"{C_PURPLE}{'─' * w}{C_RESET}")

    def _status(self, text: str):
        print(f"{C_DIM}{text}{C_RESET}")

    def _json_pretty(self, text: str):
        """Pretty-print JSON with syntax highlighting."""
        try:
            obj = json.loads(text)
            formatted = json.dumps(obj, indent=2)
        except (json.JSONDecodeError, ValueError):
            print(text)
            return

        for line in formatted.splitlines():
            stripped = line.lstrip()
            if stripped.startswith('"') and '":' in stripped:
                key, rest = line.split(":", 1)
                print(f"{C_CYAN}{key}{C_RESET}:{self._colorize_value(rest)}")
            elif stripped in ("{", "}", "[", "]", "{}", "[]"):
                print(f"{C_DIM}{line}{C_RESET}")
            else:
                print(self._colorize_value(line))

    def _colorize_value(self, text: str) -> str:
        t = text.strip().rstrip(",")
        if t in ("true", "false"):
            return f"{C_YELLOW}{text}{C_RESET}"
        if t == "null":
            return f"{C_DIM}{text}{C_RESET}"
        if t.startswith('"'):
            return f"{C_GREEN}{text}{C_RESET}"
        try:
            float(t)
            return f"{C_BLUE}{text}{C_RESET}"
        except ValueError:
            return text

    def _paged_output(self, text: str):
        """Print with awareness of terminal height — no external pager."""
        lines = text.splitlines()
        term_h = shutil.get_terminal_size().lines - 2
        if len(lines) <= term_h:
            print(text)
            return
        # Print all lines — ttyd handles scrollback
        print(text)
        print(f"\n{C_DIM}({len(lines)} lines — scroll up to see full output){C_RESET}")

    # ── Commands ─────────────────────────────────────────────

    def cmd_inspect(self, object_id: str):
        if not object_id:
            print(f"{C_RED}Usage: inspect <object-id>{C_RESET}")
            return
        self._header(f"INSPECT: {object_id}")
        self._status("Loading object...")
        output, elapsed = self._run_shell("inspect", object_id)
        self._log(f"inspect {object_id}", output, elapsed)
        self._json_pretty(output)
        print(f"\n{C_DIM}({elapsed:.1f}s){C_RESET}")

    def cmd_capabilities(self):
        self._header("CAPABILITIES")
        output, elapsed = self._run_shell("capabilities")
        self._log("capabilities", output, elapsed)
        self._json_pretty(output)
        print(f"\n{C_DIM}({elapsed:.1f}s){C_RESET}")

    def cmd_whoami(self):
        self._header("IDENTITY")
        output, elapsed = self._run_shell("whoami")
        self._log("whoami", output, elapsed)
        self._json_pretty(output)
        print(f"\n{C_DIM}({elapsed:.1f}s){C_RESET}")

    def cmd_list(self, extra_args: list[str]):
        self._header("OBJECTS")
        output, elapsed = self._run_shell("list", *extra_args)
        self._log(f"list {' '.join(extra_args)}", output, elapsed)
        try:
            items = json.loads(output)
            if isinstance(items, list):
                if not items:
                    print(f"{C_DIM}  (no objects){C_RESET}")
                else:
                    for i, item in enumerate(items):
                        oid = item.get("id", "?")
                        otype = item.get("type", "?")
                        lin = item.get("linearity", "?")
                        print(f"  {C_BOLD}{oid}{C_RESET}  {C_DIM}{otype}{C_RESET}  {C_YELLOW}{lin}{C_RESET}")
                print(f"\n{C_DIM}{len(items)} object(s) ({elapsed:.1f}s){C_RESET}")
            else:
                self._json_pretty(output)
        except (json.JSONDecodeError, ValueError):
            self._paged_output(output)

    def cmd_trace(self, object_id: str):
        if not object_id:
            print(f"{C_RED}Usage: trace <object-id>{C_RESET}")
            return
        self._header(f"TRACE: {object_id}")
        self._status("Loading history...")
        output, elapsed = self._run_shell("trace", object_id)
        self._log(f"trace {object_id}", output, elapsed)
        self._json_pretty(output)
        print(f"\n{C_DIM}({elapsed:.1f}s){C_RESET}")

    def cmd_raw(self, args: list[str]):
        """Pass arbitrary args to the shell."""
        self._header(f"SHELL: {' '.join(args)}")
        output, elapsed = self._run_shell(*args)
        self._log(f"raw {' '.join(args)}", output, elapsed)
        self._paged_output(output)
        print(f"\n{C_DIM}({elapsed:.1f}s){C_RESET}")

    def cmd_help(self):
        self._header("INSPECTOR HELP")
        help_text = f"""
  {C_BOLD}inspect{C_RESET} <id>         Show object detail
  {C_BOLD}trace{C_RESET} <id>           Show object history
  {C_BOLD}list{C_RESET} [--type=X]      List objects
  {C_BOLD}capabilities{C_RESET}         Show facet capabilities
  {C_BOLD}whoami{C_RESET}               Show active identity
  {C_BOLD}shell{C_RESET} <args...>      Run arbitrary shell command
  {C_BOLD}log{C_RESET}                  Show log file path
  {C_BOLD}clear{C_RESET}               Clear screen
  {C_BOLD}help{C_RESET}                This help
  {C_BOLD}quit{C_RESET}                Exit

  {C_DIM}All output is logged to {self.log_file}{C_RESET}
  {C_DIM}Scroll up in the terminal to see previous output{C_RESET}
"""
        print(help_text)

    # ── REPL ─────────────────────────────────────────────────

    def run(self):
        self.term_width = shutil.get_terminal_size().columns

        # Show startup info
        print(f"{C_PURPLE}{C_BOLD}Semantos Inspector{C_RESET}")
        print(f"{C_DIM}Deploy: {self.deploy_dir}{C_RESET}")
        print(f"{C_DIM}Facet:  {os.environ.get('SEMANTOS_FACET', '(none)')}{C_RESET}")
        print(f"{C_DIM}Log:    {self.log_file}{C_RESET}")
        print(f"{C_DIM}Type 'help' for commands{C_RESET}\n")

        # Run whoami on startup
        self.cmd_whoami()
        print()
        self.cmd_capabilities()

        while True:
            try:
                self.term_width = shutil.get_terminal_size().columns
                line = input(f"{C_PURPLE}inspect{C_RESET}> ").strip()
                if not line:
                    continue

                parts = line.split()
                cmd = parts[0].lower()
                args = parts[1:]

                if cmd in ("quit", "exit", "q"):
                    break
                elif cmd == "inspect" and args:
                    self.cmd_inspect(args[0])
                elif cmd == "trace" and args:
                    self.cmd_trace(args[0])
                elif cmd == "list":
                    self.cmd_list(args)
                elif cmd == "capabilities":
                    self.cmd_capabilities()
                elif cmd == "whoami":
                    self.cmd_whoami()
                elif cmd == "shell" and args:
                    self.cmd_raw(args)
                elif cmd == "log":
                    print(f"{C_DIM}{self.log_file}{C_RESET}")
                elif cmd == "clear":
                    os.system("clear")
                elif cmd == "help":
                    self.cmd_help()
                else:
                    # Try as a direct shell command
                    self.cmd_raw(parts)

            except KeyboardInterrupt:
                print()
                continue
            except EOFError:
                break

        # Save history
        readline.write_history_file(str(HISTORY_FILE))
        self._log_raw("=== Inspector stopped ===")
        print(f"\n{C_DIM}Log saved: {self.log_file}{C_RESET}")


def main():
    parser = argparse.ArgumentParser(description="Semantos Inspector TUI")
    parser.add_argument("--deploy-dir", required=True, help="Path to semantos deploy directory")
    args = parser.parse_args()

    inspector = Inspector(args.deploy_dir)
    inspector.run()


if __name__ == "__main__":
    main()

```
