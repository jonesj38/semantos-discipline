---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/prototypes/multipane_viewer_testing/viewer_server.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.758624+00:00
---

# archive/prototypes/multipane_viewer_testing/viewer_server.py

```py
#!/usr/bin/env python3
"""Multipane viewer server for Semantos console testing.

Serves the viewer HTML and provides health/config APIs.
Manages ttyd instances for each tmux pane.

Usage:
    python3 viewer_server.py --deploy-dir /tmp/semantos-test-XXXX --port 9090
"""

import argparse
import http.server
import json
import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

VIEWER_DIR = Path(__file__).resolve().parent
VIEWER_HTML = VIEWER_DIR / "viewer.html"

DEFAULT_PORTS = {
    "objects": 9101,
    "shell": 9102,
    "inspector": 9103,
    "events": 9104,
}

SHELL_SESSION = "sem-shell"
LOG_FILE = "/tmp/semantos-events.log"


class ViewerConfig:
    def __init__(self, deploy_dir: str, viewer_port: int, ports: dict):
        self.deploy_dir = deploy_dir
        self.viewer_port = viewer_port
        self.ports = ports
        self.ttyd_pids: dict[str, int] = {}

    def to_dict(self) -> dict:
        return {
            "deploy_dir": self.deploy_dir,
            "viewer_port": self.viewer_port,
            "ports": self.ports,
        }


config: ViewerConfig | None = None


TEST_FACET = "test"
TEST_EMAIL = "test@semantos.local"


def _write_rc(label: str, color_code: str, deploy_dir: str) -> str:
    """Write a per-session bashrc and return the path."""
    bun = os.path.expanduser("~/.bun/bin/bun")
    rcfile = f"/tmp/.semantos_rc_{label}"
    Path(rcfile).write_text(
        f"export PS1=$'\\e[{color_code}m{label}\\e[0m> '\n"
        f"export BUN='{bun}'\n"
        f"export SEMANTOS_FACET='{TEST_FACET}'\n"
        f"cd {deploy_dir}\n"
    )
    return rcfile


def setup(deploy_dir: str):
    """Bootstrap test identity and create the shell tmux session.

    Pane architecture:

      OBJECT TREE (left)     Python TUI (object_tree.py). Fetches objects
                             from the shell on keypress. No tmux — runs
                             directly in ttyd. No logging needed, the
                             object store is the source of truth.

      SHELL REPL (center)    Only pane that uses tmux. The semantos shell
                             is an interactive REPL that needs persistent
                             state, readline history, and session continuity.

      INSPECTOR (right)      Python TUI (inspector.py). Interactive REPL
                             wrapping shell commands with colored output,
                             scrollback, and logging to /tmp/semantos-
                             inspector-logs/.

      EVENT LOG (bottom)     tail -f on a log file. Read-only. In production
                             this becomes the semantos watch stream.
    """
    bun = os.path.expanduser("~/.bun/bin/bun")

    # Kill previous shell session only
    subprocess.run(["tmux", "kill-session", "-t", SHELL_SESSION], capture_output=True)

    # Initialize event log
    Path(LOG_FILE).write_text(
        f"=== Semantos Event Log ===\n"
        f"Deploy: {deploy_dir}\n"
        f"Started: {time.strftime('%Y-%m-%d %H:%M:%S')}\n"
        f"Watching for events...\n\n"
    )

    # Bootstrap test identity (run without SEMANTOS_FACET)
    print(f"  Bootstrapping test facet '{TEST_FACET}'...")
    r = subprocess.run(
        [bun, "packages/shell/src/index.ts", "identity", "register", TEST_EMAIL],
        cwd=deploy_dir,
        capture_output=True, text=True, timeout=30,
    )
    if r.returncode == 0:
        print(f"  identity registered: {TEST_EMAIL}")
    else:
        print(f"  identity register: {r.stdout.strip()[:100]}")

    # Create shell tmux session (only pane that needs tmux)
    rc_shell = _write_rc("shell", "34", deploy_dir)
    r = subprocess.run(
        ["tmux", "new-session", "-d", "-s", SHELL_SESSION, "-x", "200", "-y", "50",
         "bash", "--rcfile", rc_shell],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        print(f"  ERROR creating shell session: {r.stderr.strip()}")
    else:
        print(f"  tmux session '{SHELL_SESSION}' created")

    time.sleep(0.3)

    # Launch shell REPL
    subprocess.run([
        "tmux", "send-keys", "-t", SHELL_SESSION,
        f"$BUN packages/shell/src/index.ts; "
        f"echo 'Shell exited. Retry: $BUN packages/shell/src/index.ts'",
        "Enter",
    ], check=False)
    print(f"  shell REPL launched")


def start_ttyd_panes():
    """Start a ttyd instance for each pane.

    shell:     tmux attach (interactive REPL, needs session persistence)
    objects:   python3 object_tree.py (TUI, no tmux)
    inspector: python3 inspector.py (TUI with REPL, logging, no tmux)
    events:    tail -f (read-only log stream, no tmux)
    """
    deploy_dir = config.deploy_dir
    viewer_dir = str(VIEWER_DIR)
    env_facet = f"SEMANTOS_FACET={TEST_FACET}"

    pane_cmds = {
        "objects": [
            "ttyd", "-p", str(config.ports["objects"]), "-W",
            "-t", "fontSize=13", "-t", "disableLeaveAlert=true",
            "bash", "-c",
            f"export {env_facet} && exec python3 {viewer_dir}/object_tree.py --deploy-dir {deploy_dir}",
        ],
        "shell": [
            "ttyd", "-p", str(config.ports["shell"]), "-W",
            "-t", "fontSize=13", "-t", "disableLeaveAlert=true",
            "tmux", "attach-session", "-t", SHELL_SESSION,
        ],
        "inspector": [
            "ttyd", "-p", str(config.ports["inspector"]), "-W",
            "-t", "fontSize=13", "-t", "disableLeaveAlert=true",
            "bash", "-c",
            f"export {env_facet} && exec python3 {viewer_dir}/inspector.py --deploy-dir {deploy_dir}",
        ],
        "events": [
            "ttyd", "-p", str(config.ports["events"]), "-R",
            "-t", "fontSize=13", "-t", "disableLeaveAlert=true",
            "tail", "-f", LOG_FILE,
        ],
    }

    for name, cmd in pane_cmds.items():
        port = config.ports[name]
        subprocess.run(["pkill", "-f", f"ttyd.*-p.*{port}"], capture_output=True)
        time.sleep(0.1)

        proc = subprocess.Popen(
            cmd,
            stdout=open(f"/tmp/ttyd_semantos_{name}.log", "w"),
            stderr=subprocess.STDOUT,
        )
        config.ttyd_pids[name] = proc.pid
        print(f"  ttyd {name}: pid={proc.pid} port={port}")


def stop_ttyd_panes():
    """Kill all managed ttyd instances."""
    for name, pid in config.ttyd_pids.items():
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    for port in config.ports.values():
        subprocess.run(["pkill", "-f", f"ttyd.*-p.*{port}"], capture_output=True)


def kill_sessions():
    subprocess.run(["tmux", "kill-session", "-t", SHELL_SESSION], capture_output=True)


def _port_open(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1):
            return True
    except (ConnectionRefusedError, OSError):
        return False


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


class ViewerHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # Log non-health requests (health polls are noisy)
        path = args[0].split()[1] if args else ""
        if path not in ("/api/health", "/api/config"):
            sys.stderr.write(f"  viewer: {args[0]}\n")

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self._serve_file(VIEWER_HTML, "text/html")
        elif self.path == "/api/config":
            self._json_response(config.to_dict())
        elif self.path == "/api/health":
            ttyd_status = {}
            for name, pid in config.ttyd_pids.items():
                ttyd_status[name] = {
                    "pid_alive": _pid_alive(pid),
                    "port_open": _port_open(config.ports[name]),
                }
            shell_alive = subprocess.run(
                ["tmux", "has-session", "-t", SHELL_SESSION],
                capture_output=True,
            ).returncode == 0
            self._json_response({
                "shell_session": shell_alive,
                "ttyd": ttyd_status,
            })
        else:
            self.send_error(404)

    def _serve_file(self, path: Path, content_type: str):
        try:
            data = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", len(data))
            self.end_headers()
            self.wfile.write(data)
        except FileNotFoundError:
            self.send_error(404)

    def _json_response(self, data: dict):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)


def main():
    global config

    parser = argparse.ArgumentParser(description="Semantos multipane viewer server")
    parser.add_argument("--deploy-dir", required=True, help="Path to semantos deploy directory")
    parser.add_argument("--port", type=int, default=9090, help="Viewer HTTP port (default: 9090)")
    parser.add_argument("--objects-port", type=int, default=DEFAULT_PORTS["objects"])
    parser.add_argument("--shell-port", type=int, default=DEFAULT_PORTS["shell"])
    parser.add_argument("--inspector-port", type=int, default=DEFAULT_PORTS["inspector"])
    parser.add_argument("--events-port", type=int, default=DEFAULT_PORTS["events"])
    args = parser.parse_args()

    ports = {
        "objects": args.objects_port,
        "shell": args.shell_port,
        "inspector": args.inspector_port,
        "events": args.events_port,
    }

    config = ViewerConfig(
        deploy_dir=args.deploy_dir,
        viewer_port=args.port,
        ports=ports,
    )

    print(f"Semantos Multipane Viewer")
    print(f"  deploy dir: {args.deploy_dir}")
    print(f"  viewer:     http://localhost:{args.port}")
    print()

    print("Setting up...")
    setup(args.deploy_dir)
    print()

    print("Starting ttyd instances...")
    start_ttyd_panes()
    print()

    def cleanup(sig=None, frame=None):
        print("\nShutting down...")
        stop_ttyd_panes()
        kill_sessions()
        sys.exit(0)

    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    server = http.server.HTTPServer(("0.0.0.0", args.port), ViewerHandler)
    print(f"Viewer ready: http://localhost:{args.port}")
    print("Press Ctrl+C to stop\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        cleanup()


if __name__ == "__main__":
    main()

```
