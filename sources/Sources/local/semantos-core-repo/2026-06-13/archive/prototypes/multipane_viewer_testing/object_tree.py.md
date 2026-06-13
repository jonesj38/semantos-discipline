---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/prototypes/multipane_viewer_testing/object_tree.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.757958+00:00
---

# archive/prototypes/multipane_viewer_testing/object_tree.py

```py
#!/usr/bin/env python3
"""Semantos Object Tree TUI — live taxonomy browser.

Displays all objects grouped by type in a tree view. Refreshes on
keypress. Runs directly in ttyd without tmux.

Usage:
    python3 object_tree.py --deploy-dir /tmp/semantos-test-XXXX

Keys:
    r / Enter    Refresh object list
    q            Quit
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from collections import defaultdict


# ── ANSI ─────────────────────────────────────────────────────

C_RESET = "\033[0m"
C_BOLD = "\033[1m"
C_DIM = "\033[2m"
C_GREEN = "\033[32m"
C_YELLOW = "\033[33m"
C_CYAN = "\033[36m"
C_RED = "\033[31m"
C_MAGENTA = "\033[35m"

LINEARITY_COLORS = {
    "LINEAR": C_RED,
    "AFFINE": C_YELLOW,
    "RELEVANT": C_GREEN,
}


SHELL_SESSION = "sem-shell"


class ObjectTree:
    def __init__(self, deploy_dir: str):
        self.deploy_dir = deploy_dir
        self.objects: list[dict] = []
        self.last_refresh = 0.0
        self.error: str | None = None

    def _tmux_exec(self, shell_cmd: str) -> str:
        """Send a command to the shell REPL via tmux and capture the output.

        Workflow:
        1. Clear the pane scrollback
        2. Send the command
        3. Wait for the prompt to reappear
        4. Capture the pane content
        5. Extract the command output (between command echo and next prompt)
        """
        sess = SHELL_SESSION

        # Capture the current prompt to know what to look for
        pre = subprocess.run(
            ["tmux", "capture-pane", "-t", sess, "-p", "-S", "-1"],
            capture_output=True, text=True,
        ).stdout.strip()

        # Send the command
        subprocess.run(
            ["tmux", "send-keys", "-t", sess, shell_cmd, "Enter"],
            check=False,
        )

        # Wait for the prompt to return (command finished)
        for _ in range(30):  # 3 seconds max
            time.sleep(0.1)
            capture = subprocess.run(
                ["tmux", "capture-pane", "-t", sess, "-p", "-S", "-50"],
                capture_output=True, text=True,
            ).stdout
            lines = capture.strip().splitlines()
            # Look for the prompt after our command
            if len(lines) >= 2 and lines[-1].strip().endswith("> "):
                # Find our command in the output
                cmd_idx = None
                for i, line in enumerate(lines):
                    if shell_cmd[:30] in line:
                        cmd_idx = i
                        break
                if cmd_idx is not None:
                    # Output is between command line and final prompt
                    output_lines = lines[cmd_idx + 1:-1]
                    return "\n".join(output_lines).strip()

        return ""

    def fetch(self):
        """Fetch all objects from the running shell REPL."""
        try:
            output = self._tmux_exec("list --format=json")
            if output:
                parsed = json.loads(output)
                if isinstance(parsed, list):
                    self.objects = parsed
                    self.error = None
                else:
                    self.objects = []
                    self.error = None
            else:
                self.objects = []
                self.error = None
            self.last_refresh = time.time()
        except json.JSONDecodeError as e:
            self.error = f"JSON parse error: {e}"
        except Exception as e:
            self.error = str(e)[:100]

    def render(self):
        """Render the object tree to stdout."""
        w, h = shutil.get_terminal_size()

        # Clear screen
        sys.stdout.write("\033[2J\033[H")

        # Header
        print(f"{C_GREEN}{C_BOLD}OBJECT TREE{C_RESET}")
        ts = time.strftime("%H:%M:%S", time.localtime(self.last_refresh)) if self.last_refresh else "never"
        print(f"{C_DIM}Last refresh: {ts}  |  {len(self.objects)} object(s)  |  r=refresh  q=quit{C_RESET}")
        print(f"{C_DIM}{'─' * w}{C_RESET}")

        if self.error:
            print(f"\n{C_RED}  Error: {self.error}{C_RESET}")
            print(f"{C_DIM}  Press r to retry{C_RESET}")
            return

        if not self.objects:
            print(f"\n{C_DIM}  (no objects in store)")
            print(f"  Create objects in the shell pane:")
            print(f"    new Document --title='My first doc'")
            print(f"    new Event --title='Meeting'")
            print(f"  Then press r to refresh{C_RESET}")
            return

        # Group by type
        by_type: dict[str, list[dict]] = defaultdict(list)
        for obj in self.objects:
            obj_type = obj.get("typePath") or obj.get("type") or "unknown"
            by_type[obj_type].append(obj)

        # Sort types alphabetically
        lines_used = 3  # header
        for type_name in sorted(by_type.keys()):
            items = by_type[type_name]
            count = len(items)

            if lines_used >= h - 2:
                print(f"{C_DIM}  ... ({len(by_type) - lines_used + 3} more types){C_RESET}")
                break

            print(f"\n  {C_CYAN}{C_BOLD}▸ {type_name}{C_RESET} {C_DIM}({count}){C_RESET}")
            lines_used += 2

            for item in items:
                if lines_used >= h - 2:
                    remaining = count - items.index(item)
                    print(f"    {C_DIM}... {remaining} more{C_RESET}")
                    break

                oid = item.get("id", "?")
                linearity = item.get("linearity", "?")
                phase = item.get("phase", "")
                visibility = item.get("visibility", "")
                title = item.get("title", "")

                lin_color = LINEARITY_COLORS.get(linearity, C_DIM)
                phase_str = f" {C_MAGENTA}{phase}{C_RESET}" if phase else ""
                vis_str = f" {C_DIM}[{visibility}]{C_RESET}" if visibility else ""
                title_str = f" {C_DIM}— {title}{C_RESET}" if title else ""

                # Truncate to terminal width
                line = f"    {C_BOLD}{oid}{C_RESET}  {lin_color}{linearity}{C_RESET}{phase_str}{vis_str}{title_str}"
                print(line[:w + 50])  # allow for ANSI codes
                lines_used += 1

    def run(self):
        """Main loop: fetch, render, wait for keypress."""
        self.fetch()
        self.render()

        # Set terminal to raw mode for single-keypress reading
        import tty
        import termios
        old_settings = termios.tcgetattr(sys.stdin)

        try:
            tty.setcbreak(sys.stdin.fileno())

            while True:
                # Wait for keypress
                ch = sys.stdin.read(1)

                if ch in ("q", "Q", "\x03"):  # q or Ctrl+C
                    break
                elif ch in ("r", "R", "\n", " "):
                    self.fetch()
                    self.render()
                elif ch == "\x0c":  # Ctrl+L
                    self.render()

        except (KeyboardInterrupt, EOFError):
            pass
        finally:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
            # Clear screen on exit
            sys.stdout.write("\033[2J\033[H")
            print(f"{C_DIM}Object tree closed.{C_RESET}")


def main():
    parser = argparse.ArgumentParser(description="Semantos Object Tree TUI")
    parser.add_argument("--deploy-dir", required=True, help="Path to semantos deploy directory")
    args = parser.parse_args()

    tree = ObjectTree(args.deploy_dir)
    tree.run()


if __name__ == "__main__":
    main()

```
