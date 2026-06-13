---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tools/method_sizes.py
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.170938+00:00
---

# runtime/semantos-brain/tools/method_sizes.py

```py
#!/usr/bin/env python3
"""Rank the largest fn / pub fn bodies inside a Zig source file.

Used during the cli.zig / site_server.zig / repl.zig / wss_wallet.zig
LOC-pressure refactor to pick the next extraction target.  Counts lines
between consecutive fn-headers (or until file end), so the size reflects
fn body + trailing blank lines.  Good enough for "what's worth moving"
ranking; not a precise metric.

Default: indented methods only (i.e. struct members — `    fn ...` and
`    pub fn ...`).  Pass `--all` to include top-level fns too.

Usage:
    python3 tools/method_sizes.py src/site_server.zig
    python3 tools/method_sizes.py --top 20 src/repl.zig
    python3 tools/method_sizes.py --all src/cli.zig
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


METHOD_RE = re.compile(r"^    (pub )?fn (\w+)")
TOPLEVEL_RE = re.compile(r"^(pub )?fn (\w+)")


def ranked(path: Path, *, include_toplevel: bool) -> list[tuple[int, int, str]]:
    lines = path.read_text().splitlines()
    rx = TOPLEVEL_RE if include_toplevel else METHOD_RE
    hits: list[tuple[int, str]] = []
    for i, l in enumerate(lines):
        m = rx.match(l)
        if m:
            hits.append((i + 1, m.group(2)))
    hits.append((len(lines) + 1, "<eof>"))
    out: list[tuple[int, int, str]] = []
    for (start, name), (next_start, _) in zip(hits, hits[1:]):
        out.append((next_start - start, start, name))
    out.sort(reverse=True)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("file", type=Path)
    ap.add_argument("--top", type=int, default=15, help="rows to print (default 15)")
    ap.add_argument(
        "--all",
        action="store_true",
        help="include top-level fns (default: struct methods only)",
    )
    args = ap.parse_args()

    if not args.file.exists():
        print(f"no such file: {args.file}", file=sys.stderr)
        return 1

    rows = ranked(args.file, include_toplevel=args.all)
    if not rows:
        print(f"no fn / pub fn declarations found in {args.file}")
        return 0

    print(f"Top {min(args.top, len(rows))} fns in {args.file} (by line span):")
    print(f"{'LOC':>5}  {'line':>6}  name")
    for size, start, name in rows[: args.top]:
        print(f"{size:5d}  L{start:5d}  {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

```
