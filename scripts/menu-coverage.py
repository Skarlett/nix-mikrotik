#!/usr/bin/env python3
"""Check that `lib/menus.nix` covers every attribute the fleet's routers use.

The typed menu surface checks attribute names at evaluation time, which is only
useful if the table is right. `lib/menus.nix` says its `attrs` lists are "the
union of what the fleet's two routers, this repository's examples and the
CRS226's own /export actually use" -- so the device exports are the oracle, and
this compares the two.

Two ways it can be wrong, and both are silent without this:

  * an attribute the fleet uses is missing from the table -> evaluation refuses
    a router that used to render, and the fix is one line in `lib/menus.nix`;
  * the table lists a menu the fleet no longer uses -> harmless, reported as
    informational so the table can be pruned when someone gets to it.

Usage:
    menu-coverage.py RENDERS_DIR [--table PATH] [--json]

RENDERS_DIR holds the routers' own `/export` output, e.g. the fleet repo's
`routers/` directory (`homelab-router.rsc`, ...). Exits 1 if anything is
missing from the table, so it can gate a workflow.
"""
import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def table(path=None):
    """`lib/menus.nix` as JSON: [{ path, kind, attrs }]."""
    src = path or os.path.join(HERE, "lib", "menus.nix")
    out = subprocess.run(
        ["nix", "eval", "--json", "--file", src],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        sys.exit(f"menu-coverage: could not evaluate {src}:\n{out.stderr}")
    return json.loads(out.stdout)


def statements(path):
    """(section, attribute) pairs from a RouterOS `/export`.

    RouterOS wraps long lines with a trailing backslash, and the wrap lands
    mid-token (`endpoint-port=\\` newline `59662`), so continuations join
    without a space.
    """
    raw = open(path, newline="").read().replace("\r\n", "\n")
    raw = re.sub(r"\\\n\s*", "", raw)
    section = None
    for line in raw.split("\n"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith("/"):
            # A section header is the whole command path -- RouterOS paths are
            # multi-word (`/interface ethernet switch egress-vlan-tag`), so
            # taking the first token turns every one of them into `/interface`.
            section = s
            continue
        if not (s.startswith("add ") or s.startswith("set ")):
            continue
        for tok in s.split(" ", 1)[1].split():
            if "=" in tok:
                yield section, tok.split("=", 1)[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("renders", help="directory of RouterOS /export files")
    ap.add_argument("--table", default=None, help="path to lib/menus.nix")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    menus = {m["path"]: m for m in table(args.table)}

    files = sorted(
        os.path.join(args.renders, f)
        for f in os.listdir(args.renders)
        if f.endswith(".rsc") and os.path.getsize(os.path.join(args.renders, f)) > 0
    )
    if not files:
        sys.exit(f"menu-coverage: no non-empty .rsc files in {args.renders}")

    missing = {}   # (section, attr) -> [files]
    unknown_menu = {}  # section -> [files]
    for f in files:
        name = os.path.basename(f)
        for section, attr in statements(f):
            if section not in menus:
                unknown_menu.setdefault(section, []).append(name)
                continue
            known = menus[section]["attrs"]
            if known is not None and attr not in known:
                missing.setdefault((section, attr), []).append(name)

    if args.json:
        print(json.dumps(
            {
                "files": [os.path.basename(f) for f in files],
                "missing": [
                    {"section": s, "attribute": a, "seen_in": sorted(set(v))}
                    for (s, a), v in sorted(missing.items())
                ],
                "sections_not_in_table": {k: sorted(set(v)) for k, v in sorted(unknown_menu.items())},
            },
            indent=2,
        ))
        return 1 if missing else 0

    print(f"menu-coverage: {len(files)} export(s) against {len(menus)} menus")

    if unknown_menu:
        print("\nMenus the routers use that the table does not declare "
              "(acceptable -- they stay on `sections`):")
        for s, v in sorted(unknown_menu.items()):
            print(f"  {s}  ({', '.join(sorted(set(v)))})")

    if missing:
        print("\nMISSING FROM lib/menus.nix -- evaluation will refuse these:")
        for (s, a), v in sorted(missing.items()):
            print(f"  {s}: {a}   ({', '.join(sorted(set(v)))})")
        print(f"\n{len(missing)} attribute(s) to add.")
        return 1

    print("\nNo gaps: every attribute the fleet uses is declared.")
    return 0


if __name__ == "__main__":
    sys.exit(main())