#!/usr/bin/env python3
r"""Walk RouterOS' own CLI tree through /console/inspect and dump it as JSON.

Why the retries: a failed SSH connection and an empty child list look identical
from the outside -- both give no output -- and an empty child list is a
legitimate answer (`/ip dns` has no submenus). Silently treating a timeout as
"no children" produces a *narrower* tree that still looks complete, which is the
one failure mode that must not happen here. So `children()` returns None on
failure and the walk aborts, rather than continuing with a hole in it.

The path spelling is the other trap. A multi-token path is a single string in
which spaces separate menu names, and the device's parser eats one backslash
before `/console/inspect` sees the value, so a space must be written as two
backslashes. With one backslash the command prints nothing and exits 0:

    /console/inspect request=child path="ip\\ dhcp-server"     # works
    /console/inspect request=child path="ip\ dhcp-server"      # silently empty

Usage:  CHR_SSH_PORT=2325 ./walk.py > tree.json
"""
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

PORT = os.environ.get("CHR_SSH_PORT", "2325")
HERE = os.path.dirname(os.path.abspath(__file__))
ASKPASS = os.environ.get("CHR_ASKPASS", os.path.join(HERE, "askpass.sh"))
ATTEMPTS = 4
# 8 workers drew "Connection timed out during banner exchange" on a tenth of the
# nodes on 7.15.3; the device is the bottleneck, not this machine.
WORKERS = 6

ENV = dict(os.environ)
ENV.update({"SSH_ASKPASS": ASKPASS, "SSH_ASKPASS_REQUIRE": "force", "DISPLAY": ":0"})

SSH = [
    # `-F /dev/null`: this device takes an empty password, and the operator's
    # own ~/.ssh/config is not part of the question (a permission error on a
    # home-managed file turns every inspect into "no children").
    "ssh", "-F", "/dev/null", "-p", PORT,
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "PreferredAuthentications=password",
    "-o", "PubkeyAuthentication=no",
    "-o", "LogLevel=ERROR",
    "-o", "ConnectTimeout=15",
    "admin@127.0.0.1",
]


def quote_path(path):
    return path.replace(" ", "\\\\ ")


def run(cmd, attempts=ATTEMPTS):
    """Run one RouterOS command; a list of output lines, or None if it failed."""
    delay = 2
    for attempt in range(1, attempts + 1):
        try:
            proc = subprocess.run(SSH + [cmd], env=ENV, capture_output=True,
                                  text=True, timeout=120)
        except subprocess.TimeoutExpired:
            proc = None
        if proc is not None and proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.replace("\r", "").splitlines()
        if attempt == attempts:
            return None
        time.sleep(delay)
        delay *= 2
    return None


def rows(path, request="child"):
    out = run('/console/inspect request=%s path="%s"' % (request, quote_path(path)))
    if out is None:
        return None
    parsed = []
    for line in out:
        if line.startswith("Columns:") or line.startswith("TYPE") or not line.strip():
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        kind, name, nodetype = parts[0], parts[1], parts[-1]
        if kind in ("self", "child"):
            parsed.append((kind, name, nodetype))
    return parsed


def children(path):
    got = rows(path)
    if got is None:
        return None
    return [(n, t) for (k, n, t) in got if k == "child"]


def main():
    version = run("/system resource print") or []
    ver = next((l.split(":", 1)[1].strip() for l in version if l.strip().startswith("version:")), "?")
    build = next((l.split(":", 1)[1].strip() for l in version if l.strip().startswith("build-time:")), "?")
    print("version %s (built %s)" % (ver, build), file=sys.stderr)

    root = children("")
    if root is None:
        sys.exit("could not read the root menu -- refusing to write a partial tree")
    print("root children: %d" % len(root), file=sys.stderr)

    seen = {}
    frontier = [(("" if False else "", root))]
    while frontier:
        jobs = []
        for parent, kids in frontier:
            for name, nodetype in kids:
                if nodetype in ("dir", "path"):
                    jobs.append((parent + " " + name).strip())
        results = []
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            for path, got in zip(jobs, pool.map(children, jobs)):
                results.append((path, got))
        next_frontier = []
        for path, kids in results:
            if kids is None:
                sys.exit("inspect failed on %r after %d attempts -- refusing to "
                         "write a tree with a hole in it" % (path, ATTEMPTS))
            names = dict(kids)
            seen[path] = {
                "path": path,
                "children": kids,
                "add": names.get("add") == "cmd",
                "set": names.get("set") == "cmd",
            }
            next_frontier.append((path, kids))
        print("level done: %d known, %d to expand" % (len(seen), len(next_frontier)),
              file=sys.stderr)
        frontier = next_frontier

    def args(path):
        out = {}
        for verb in ("add", "set"):
            if seen[path][verb]:
                got = rows(path + " " + verb)
                if got is None:
                    sys.exit("inspect failed listing %r %s" % (path, verb))
                out[verb] = sorted({n for k, n, t in got if t == "arg"})
        return path, out

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for path, out in pool.map(args, sorted(seen)):
            seen[path].update(out)

    lists = sum(1 for v in seen.values() if v["add"])
    objects = sum(1 for v in seen.values() if v["set"] and not v["add"])
    containers = sum(1 for v in seen.values() if not v["add"] and not v["set"])
    summary = {
        "routeros": ver,
        "build-time": build,
        "menus": len(seen),
        "add-style": lists,
        "set-only": objects,
        "containers": containers,
        "tree": seen,
    }
    json.dump(summary, sys.stdout, indent=1, sort_keys=True)
    print("\n%d menus: %d add, %d set-only, %d containers"
          % (len(seen), lists, objects, containers), file=sys.stderr)


if __name__ == "__main__":
    main()